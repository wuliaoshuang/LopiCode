// DeepSeek 官方渠道的余额与“额度上限”。
//
// 接口（见 docs/api-notes.md 的“DeepSeek 余额”一节）：GET https://api.deepseek.com/user/balance，
// Authorization: Bearer <key>，返回 is_available 和 balance_infos[]（currency / total_balance /
// granted_balance / topped_up_balance，金额都是字符串）。接口只说“还剩多少”，没有“限额”这类字段，
// 所以上限是用户自己在设置里填的：
//   已用 = 设上限之后，每次查到余额比上一次少了多少，累加起来；
//   百分比 = 已用 ÷ 上限；到 100% 时在代码里拦住这个渠道的新请求。
// 余额变多（充值、换了 Key）不会把已用冲掉，只打一个标记，让界面提示“可以从现在重新算”。
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:lopicode/agent/chat_client.dart';
import 'package:lopicode/agent/model_config.dart';
import 'package:lopicode/core/stores.dart';

/// 被拦住时提示语的开头（聊天页据此给“去调上限”的入口）。
const String kQuotaBlockedPrefix = '已达到你设的额度上限';

/// 这个接口地址是不是 DeepSeek 官方（主机名正好是 api.deepseek.com）。
/// 中转站、自建网关即使转发的是 DeepSeek 模型也不算：它们的余额查不到，也不归 DeepSeek 结算。
bool isDeepSeekOfficial(String baseUrl) {
  var text = baseUrl.trim();
  if (text.isEmpty) return false;
  if (!text.contains('://')) text = 'https://$text';
  final uri = Uri.tryParse(text);
  if (uri == null) return false;
  return uri.host.toLowerCase() == 'api.deepseek.com';
}

/// 余额接口的地址：和对话接口同一个主机，路径固定是 /user/balance
/// （对话接口地址可能带 /v1、/beta、/anthropic 这样的后缀，这里都不要）。
Uri? deepSeekBalanceUri(String baseUrl) {
  var text = baseUrl.trim();
  if (text.isEmpty) return null;
  if (!text.contains('://')) text = 'https://$text';
  final uri = Uri.tryParse(text);
  if (uri == null || uri.host.isEmpty || (uri.scheme != 'https' && uri.scheme != 'http')) return null;
  return Uri(scheme: uri.scheme, host: uri.host, port: uri.hasPort ? uri.port : null, path: '/user/balance');
}

/// 一种币的余额。
class BalanceInfo {
  const BalanceInfo({required this.currency, required this.total, this.granted, this.toppedUp});
  final String currency; // CNY / USD

  /// 可用总额（赠送 + 充值）。
  final double total;
  final double? granted;
  final double? toppedUp;
}

class BalanceResult {
  const BalanceResult({required this.isAvailable, required this.infos});

  /// DeepSeek 说的“余额够不够调用接口”。
  final bool isAvailable;
  final List<BalanceInfo> infos;

  BalanceInfo? of(String currency) => infos.where((i) => i.currency == currency).firstOrNull;

  /// 优先人民币那一条；没有就第一条。
  BalanceInfo? get preferred => of('CNY') ?? infos.firstOrNull;
}

class BalanceException implements Exception {
  BalanceException(this.message, {this.keyInvalid = false});
  final String message;

  /// 是不是 Key 无效（401 / 403）。
  final bool keyInvalid;
  @override
  String toString() => message;
}

double? _money(Object? v) {
  final d = v is num ? v.toDouble() : (v is String ? double.tryParse(v.trim()) : null);
  return d == null || !d.isFinite ? null : d;
}

/// 解析余额接口的返回。字段对不上就抛 [BalanceException]，不编数字。
BalanceResult parseBalance(Object? json) {
  if (json is! Map || json['balance_infos'] is! List) throw BalanceException('余额接口返回的内容看不懂');
  final infos = <BalanceInfo>[];
  for (final item in json['balance_infos'] as List) {
    if (item is! Map || item['currency'] is! String) continue;
    final total = _money(item['total_balance']);
    if (total == null) continue;
    infos.add(BalanceInfo(currency: (item['currency'] as String).toUpperCase(), total: total, granted: _money(item['granted_balance']), toppedUp: _money(item['topped_up_balance'])));
  }
  if (infos.isEmpty) throw BalanceException('余额接口没有返回任何余额');
  return BalanceResult(isAvailable: json['is_available'] == true, infos: infos);
}

/// 查余额。只发一个 GET，不产生任何费用。出错信息里不带 Key。
Future<BalanceResult> fetchDeepSeekBalance({required String baseUrl, required String apiKey, http.Client? httpClient}) async {
  final uri = deepSeekBalanceUri(baseUrl);
  if (uri == null) throw BalanceException('接口地址不是合法的网址');
  if (apiKey.isEmpty) throw BalanceException('这个渠道还没填 API Key');
  final client = httpClient ?? http.Client();
  final http.Response response;
  try {
    response = await client.get(uri, headers: {'Authorization': 'Bearer $apiKey', 'Accept': 'application/json'}).timeout(const Duration(seconds: 10));
  } on TimeoutException {
    throw BalanceException('10 秒没有回应');
  } on Exception catch (e) {
    throw BalanceException('连不上 ${uri.host}：${shortError(e)}');
  } finally {
    if (httpClient == null) client.close();
  }
  if (response.statusCode == 401 || response.statusCode == 403) throw BalanceException('Key 无效，查不到余额（${response.statusCode}：Key 不对，或者没有查余额的权限）', keyInvalid: true);
  if (response.statusCode != 200) throw BalanceException('余额接口返回 ${response.statusCode}');
  final Object? json;
  try {
    json = jsonDecode(utf8.decode(response.bodyBytes, allowMalformed: true));
  } on FormatException {
    throw BalanceException('余额接口返回的不是 JSON');
  }
  return parseBalance(json);
}

String currencySymbol(String currency) => switch (currency) {
  'CNY' => '¥',
  'USD' => r'$',
  _ => '$currency ',
};

String formatMoney(String currency, double amount) => '${currencySymbol(currency)}${amount.toStringAsFixed(2)}';

double _round4(double v) => (v * 10000).round() / 10000;

/// 一个渠道的额度上限（存进普通设置，不含任何密钥）。
class ChannelQuota {
  ChannelQuota({required this.limit, required this.currency, this.used = 0, this.lastBalance, this.warnPct = defaultWarnPct, this.warned = false, this.recharge = false, DateTime? since})
    : since = since ?? DateTime.now();

  static const int defaultWarnPct = 80;

  /// 上限金额（> 0），币种见 [currency]。
  double limit;
  String currency;

  /// 设上限（或“重新算”）以来花掉的钱。
  double used;

  /// 上一次查到的余额；还没查到过是 null（第一次查到时记为起点）。
  double? lastBalance;

  /// 到这个百分比时提醒一次（只提醒不拦）。0 表示不提醒。
  int warnPct;
  bool warned;

  /// 查到余额比上次多了（充值，或者换了 Key）。
  bool recharge;
  DateTime since;

  double get fraction => limit <= 0 ? 0 : (used / limit).clamp(0.0, 1.0);
  int get percent => (fraction * 100 + 1e-9).floor();
  bool get reached => used + 1e-9 >= limit;
  double get remaining => (limit - used).clamp(0.0, limit);

  Map<String, dynamic> toJson() => {
    'limit': limit,
    'currency': currency,
    'used': used,
    'lastBalance': lastBalance,
    'warnPct': warnPct,
    'warned': warned,
    'recharge': recharge,
    'since': since.toIso8601String(),
  };

  static ChannelQuota? fromJson(Object? j) {
    if (j is! Map) return null;
    final limit = _money(j['limit']);
    if (limit == null || limit <= 0 || j['currency'] is! String) return null;
    final used = _money(j['used']) ?? 0;
    return ChannelQuota(
      limit: limit,
      currency: j['currency'] as String,
      used: used < 0 ? 0 : used,
      lastBalance: _money(j['lastBalance']),
      warnPct: j['warnPct'] is int ? (j['warnPct'] as int).clamp(0, 99) : defaultWarnPct,
      warned: j['warned'] == true,
      recharge: j['recharge'] == true,
      since: j['since'] is String ? DateTime.tryParse(j['since'] as String) : null,
    );
  }
}

/// 最近一次查余额的结果（只在内存里）。
class BalanceState {
  BalanceResult? result;

  /// 最近一次没查到的原因；查到了是 null。
  String? error;

  /// 最近一次是不是因为 Key 无效（401 / 403）没查到。断网、服务器出错不算。
  bool keyInvalid = false;
  DateTime? at;
  bool loading = false;
}

/// 各渠道的余额和额度上限。
class QuotaStore extends ChangeNotifier {
  QuotaStore(this.settings, this.models, {this.httpClient, DateTime Function()? now}) : _now = now ?? DateTime.now;

  final SettingsStore settings;
  final ModelConfigStore models;

  /// 测试钩子：替换真实的网络。
  final http.Client? httpClient;
  final DateTime Function() _now;

  static const kQuotas = 'quota.channels';

  /// 自动刷新（打开聊天或设置、打开用量弹层、对话结束、发请求前）最短间隔：最多每分钟查一次。手动刷新不受限。
  static const Duration throttle = Duration(minutes: 1);

  /// DeepSeek 充值页（网址来自 dsh-Go 的做法，没在官方文档里核对到）。
  static const String topUpUrl = 'https://platform.deepseek.com/top_up';

  /// 低余额提醒线（金额，和余额同币种）。0＝不提醒。
  static const kLowLine = 'quota.lowLine';
  static const List<int> lowLineChoices = [0, 1, 5, 10, 20, 50];
  static const int defaultLowLine = 5;

  int get lowLine {
    final v = settings.get<int>(kLowLine);
    return v != null && lowLineChoices.contains(v) ? v : defaultLowLine;
  }

  Future<void> setLowLine(int value) async {
    await settings.set(kLowLine, value);
    notifyListeners();
  }

  final Set<String> _lowDismissed = {};

  /// 余额低于提醒线时返回那一条余额（聊天输入框上方的小提示用）；这次运行里关掉过就不再返回。
  BalanceInfo? lowBalance(Channel ch) {
    if (!isDeepSeekOfficial(ch.baseUrl) || lowLine <= 0 || _lowDismissed.contains(ch.id)) return null;
    final info = stateOf(ch.id).result?.preferred;
    return info != null && info.total < lowLine ? info : null;
  }

  /// 关掉低余额提示：这次运行不再出现。
  void dismissLow(String channelId) {
    _lowDismissed.add(channelId);
    notifyListeners();
  }

  final Map<String, ChannelQuota> _quotas = {};
  final Map<String, BalanceState> _states = {};
  final Map<String, DateTime> _lastAttempt = {};
  final Map<String, Future<void>> _inFlight = {};
  final Set<String> _toldReached = {};
  bool _loaded = false;

  void _load() {
    if (_loaded) return;
    _loaded = true;
    final raw = settings.get<Map<String, dynamic>>(kQuotas);
    for (final e in (raw ?? const <String, dynamic>{}).entries) {
      final q = ChannelQuota.fromJson(e.value);
      if (q != null) _quotas[e.key] = q;
    }
  }

  Future<void> _save() => settings.set(kQuotas, _quotas.isEmpty ? null : {for (final e in _quotas.entries) e.key: e.value.toJson()});

  ChannelQuota? quotaOf(String channelId) {
    _load();
    return _quotas[channelId];
  }

  BalanceState stateOf(String channelId) => _states.putIfAbsent(channelId, BalanceState.new);

  /// 被拦住的原因；没被拦是 null。不发网络请求，只看已经记下的数。
  String? blockReason(Channel ch) {
    if (!isDeepSeekOfficial(ch.baseUrl)) return null;
    final q = quotaOf(ch.id);
    if (q == null || !q.reached) return null;
    return '$kQuotaBlockedPrefix（${formatMoney(q.currency, q.limit)}，渠道“${ch.name}”）。这个渠道的新请求已被拦住，到“设置 → 额度上限”调高上限或重新开始计算后才能继续。';
  }

  /// 查一次余额并更新“已用”。[force] 为 false 时一分钟内不重复查。查不到只记原因，不改已用。
  Future<void> refresh(Channel ch, {bool force = false}) {
    if (!isDeepSeekOfficial(ch.baseUrl)) return Future.value();
    final running = _inFlight[ch.id];
    if (running != null) return running;
    final last = _lastAttempt[ch.id];
    if (!force && last != null && _now().difference(last) < throttle) return Future.value();
    _lastAttempt[ch.id] = _now();
    // 注意要用花括号：箭头写法会把 remove 的返回值（就是这个 Future 自己）交给 whenComplete 去等，永远等不完。
    final future = _refresh(ch).whenComplete(() {
      _inFlight.remove(ch.id);
    });
    _inFlight[ch.id] = future;
    return future;
  }

  Future<void> _refresh(Channel ch) async {
    final state = stateOf(ch.id)..loading = true;
    notifyListeners();
    try {
      final result = await fetchDeepSeekBalance(baseUrl: ch.baseUrl, apiKey: await models.apiKey(ch.id), httpClient: httpClient);
      state
        ..result = result
        ..keyInvalid = false
        ..error = null
        ..at = _now();
      await _apply(ch.id, result);
    } on BalanceException catch (e) {
      state
        ..keyInvalid = e.keyInvalid
        ..error = e.message
        ..at = _now();
    } on Exception catch (e) {
      state
        ..error = shortError(e)
        ..at = _now();
    } finally {
      state.loading = false;
      notifyListeners();
    }
  }

  Future<void> _apply(String channelId, BalanceResult result) async {
    final q = quotaOf(channelId);
    if (q == null) return;
    final info = result.of(q.currency);
    if (info == null) {
      stateOf(channelId).error = '这次没有返回 ${q.currency} 的余额，已用没有更新';
      return;
    }
    final before = q.lastBalance;
    if (before != null) {
      final spent = _round4(before - info.total);
      if (spent > 0) {
        q.used = _round4(q.used + spent);
      } else if (spent < 0) {
        q.recharge = true;
      }
    }
    q.lastBalance = info.total;
    if (q.warnPct > 0 && q.percent < q.warnPct) q.warned = false;
    await _save();
  }

  /// 设上限（或改上限、改提醒阈值）。新设的会先查一次余额当起点；改已有的不清零已用。
  Future<void> setLimit(Channel ch, {required double limit, required String currency, int warnPct = ChannelQuota.defaultWarnPct}) async {
    if (!(limit > 0) || !limit.isFinite) throw ArgumentError('上限要大于 0');
    final old = quotaOf(ch.id);
    if (old != null && old.currency == currency) {
      old
        ..limit = limit
        ..warnPct = warnPct.clamp(0, 99);
      if (old.warnPct == 0 || old.percent < old.warnPct) old.warned = false;
    } else {
      _quotas[ch.id] = ChannelQuota(limit: limit, currency: currency, warnPct: warnPct.clamp(0, 99), since: _now());
      // 记起点：用刚查到的余额；没查到就等第一次查到时再记。
      final known = stateOf(ch.id).result?.of(currency);
      if (known != null) _quotas[ch.id]!.lastBalance = known.total;
    }
    await _save();
    notifyListeners();
    if (_quotas[ch.id]!.lastBalance == null) await refresh(ch, force: true);
  }

  /// 从现在重新算：已用清零，起点改成当前余额。
  Future<void> restart(Channel ch) async {
    final q = quotaOf(ch.id);
    if (q == null) return;
    q
      ..used = 0
      ..warned = false
      ..recharge = false
      ..since = _now()
      ..lastBalance = stateOf(ch.id).result?.of(q.currency)?.total;
    await _save();
    notifyListeners();
    await refresh(ch, force: true);
  }

  Future<void> clearLimit(String channelId) async {
    _load();
    _quotas.remove(channelId);
    await _save();
    notifyListeners();
  }

  /// 一段对话结束后调用：刷新余额（有节流），需要提醒时返回给用户看的一句话。
  Future<String?> afterRun(Channel ch) async {
    if (!isDeepSeekOfficial(ch.baseUrl)) return null;
    await refresh(ch);
    final q = quotaOf(ch.id);
    if (q == null) return null;
    if (q.reached) {
      // 到顶只说一次（之后每次被拦都会有拦截提示）。
      if (!_toldReached.add(ch.id)) return null;
      return '$kQuotaBlockedPrefix（${formatMoney(q.currency, q.limit)}）。这个渠道接下来的请求会被拦住，到“设置 → 额度上限”可以调。';
    }
    _toldReached.remove(ch.id);
    if (q.warnPct > 0 && q.percent >= q.warnPct && !q.warned) {
      q.warned = true;
      await _save();
      return '额度提醒：渠道“${ch.name}”已经用了你设的上限的 ${q.percent}%（还剩 ${formatMoney(q.currency, q.remaining)}）。到 100% 会被拦住。';
    }
    return null;
  }

  /// 给模型客户端套上额度检查。不是 DeepSeek 官方渠道原样返回。
  ChatClient guard(Channel ch, ChatClient inner) => isDeepSeekOfficial(ch.baseUrl) ? _QuotaGuardClient(this, ch, inner) : inner;
}

/// 每次向模型发请求之前检查额度（主对话、子代理、自动化任务、压缩对话都经过这里）。
class _QuotaGuardClient implements ChatClient {
  _QuotaGuardClient(this.store, this.channel, this.inner);
  final QuotaStore store;
  final Channel channel;
  final ChatClient inner;

  @override
  Stream<ChatDelta> streamChat({required List<Map<String, dynamic>> messages, List<Map<String, dynamic>> tools = const []}) async* {
    // 设了上限才值得在发请求前多查一次余额（有节流；查不到不拦）。
    if (store.quotaOf(channel.id) != null) await store.refresh(channel);
    final reason = store.blockReason(channel);
    if (reason != null) {
      // 拦截提示本身已经说了“到上限”，对话结束后的提醒就不再重复说一遍。
      store._toldReached.add(channel.id);
      throw ChatApiException(reason);
    }
    yield* inner.streamChat(messages: messages, tools: tools);
  }
}
