// 额度与余额的状态（DeepSeek 官方渠道）。口径和接口说明见 lib/agent/quota.dart 开头。
//
// 这里是这份状态唯一的主人：界面订阅 [quotaProvider]，要改就调 [QuotaNotifier] 的方法。
// 防“旧结果盖新结果”有三道：同一渠道同一时间只发一个请求；每个渠道一个“代次”，换了 Key
// 代次加一，旧请求回来发现代次不对就整个丢掉；容器销毁以后不再写状态。
import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:lopicode/agent/chat_client.dart';
import 'package:lopicode/agent/model_config.dart';
import 'package:lopicode/agent/quota.dart';
import 'package:lopicode/core/stores.dart';
import 'package:lopicode/state/app_providers.dart';
import 'package:riverpod/riverpod.dart';

/// 查余额用的网络。测试里替换成假的；平时为 null（用真实网络）。
final quotaHttpProvider = Provider<http.Client?>((ref) => ref.watch(appServicesProvider).quotaHttp);

/// 各渠道的额度上限和最近一次查到的余额。不可变，每次变化换一个新的。
class QuotaState {
  const QuotaState({this.quotas = const {}, this.balances = const {}, this.lowLine = QuotaNotifier.defaultLowLine, this.lowDismissed = const {}});

  /// 渠道 id → 额度上限（没设上限的渠道不在里面）。
  final Map<String, ChannelQuota> quotas;

  /// 渠道 id → 最近一次查余额的结果。
  final Map<String, BalanceState> balances;

  /// 低余额提醒线（金额）。0＝不提醒。
  final int lowLine;

  /// 这次运行里关掉过低余额提示的渠道。
  final Set<String> lowDismissed;

  QuotaState copyWith({Map<String, ChannelQuota>? quotas, Map<String, BalanceState>? balances, int? lowLine, Set<String>? lowDismissed}) =>
      QuotaState(quotas: quotas ?? this.quotas, balances: balances ?? this.balances, lowLine: lowLine ?? this.lowLine, lowDismissed: lowDismissed ?? this.lowDismissed);
}

class QuotaNotifier extends Notifier<QuotaState> {
  static const kQuotas = 'quota.channels';

  /// 自动刷新（打开聊天或设置、打开用量弹层、对话结束、发请求前）最短间隔：最多每分钟查一次。手动刷新不受限。
  static const Duration throttle = Duration(minutes: 1);

  /// DeepSeek 充值页（网址来自 dsh-Go 的做法，没在官方文档里核对到）。
  static const String topUpUrl = 'https://platform.deepseek.com/top_up';

  /// 低余额提醒线（金额，和余额同币种）。0＝不提醒。
  static const kLowLine = 'quota.lowLine';
  static const List<int> lowLineChoices = [0, 1, 5, 10, 20, 50];
  static const int defaultLowLine = 5;

  late SettingsStore _settings;
  late ModelConfigStore _models;
  late DateTime Function() _now;

  final Map<String, DateTime> _lastAttempt = {};
  final Map<String, Future<void>> _inFlight = {};
  final Map<String, int> _epoch = {};
  final Set<String> _toldReached = {};

  /// 当前状态的一份本地快照。容器销毁以后（应用退出、测试收尾），还没跑完的对话仍可能来问
  /// “到上限了吗”：这时照最后一份快照回答，不报错；写入则直接丢掉（销毁后不写）。
  late QuotaState _snap;

  void _put(QuotaState next) {
    _snap = next;
    if (ref.mounted) state = next;
  }

  @override
  QuotaState build() {
    _settings = ref.watch(settingsStoreProvider);
    _models = ref.watch(appServicesProvider).models;
    _now = ref.watch(clockProvider);
    _models.keyListeners.add(_onKeyChanged);
    ref.onDispose(() => _models.keyListeners.remove(_onKeyChanged));
    final quotas = <String, ChannelQuota>{};
    final raw = _settings.get<Map<String, dynamic>>(kQuotas);
    for (final e in (raw ?? const <String, dynamic>{}).entries) {
      final q = ChannelQuota.fromJson(e.value);
      if (q != null) quotas[e.key] = q;
    }
    final line = _settings.get<int>(kLowLine);
    return _snap = QuotaState(quotas: quotas, lowLine: line != null && lowLineChoices.contains(line) ? line : defaultLowLine);
  }

  int get lowLine => _snap.lowLine;

  Future<void> setLowLine(int value) async {
    _put(_snap.copyWith(lowLine: lowLineChoices.contains(value) ? value : defaultLowLine));
    await _settings.set(kLowLine, value);
  }

  /// 余额低于提醒线时返回那一条余额（聊天输入框上方的小提示用）；这次运行里关掉过就不再返回。
  BalanceInfo? lowBalance(Channel ch) {
    if (!isDeepSeekOfficial(ch.baseUrl) || lowLine <= 0 || _snap.lowDismissed.contains(ch.id)) return null;
    final info = stateOf(ch.id).result?.preferred;
    return info != null && info.total < lowLine ? info : null;
  }

  /// 关掉低余额提示：这次运行不再出现。
  void dismissLow(String channelId) => _put(_snap.copyWith(lowDismissed: {..._snap.lowDismissed, channelId}));

  ChannelQuota? quotaOf(String channelId) => _snap.quotas[channelId];

  BalanceState stateOf(String channelId) => _snap.balances[channelId] ?? BalanceState.empty;

  void _setBalance(String channelId, BalanceState value) => _put(_snap.copyWith(balances: {..._snap.balances, channelId: value}));

  Future<void> _setQuota(String channelId, ChannelQuota? value) async {
    final next = {..._snap.quotas};
    if (value == null) {
      next.remove(channelId);
    } else {
      next[channelId] = value;
    }
    _put(_snap.copyWith(quotas: next));
    await _settings.set(kQuotas, next.isEmpty ? null : {for (final e in next.entries) e.key: e.value.toJson()});
  }

  /// 这个渠道的 Key 换了（或渠道删了）：正在路上的旧请求作废，已查到的余额清掉，
  /// “上一次余额”也清掉——新 Key 第一次查到的余额当新的起点，不和旧账号的余额相减。
  void _onKeyChanged(String channelId) {
    if (!ref.mounted) return;
    _epoch[channelId] = (_epoch[channelId] ?? 0) + 1;
    _inFlight.remove(channelId);
    _lastAttempt.remove(channelId);
    final balances = {..._snap.balances}..remove(channelId);
    _put(_snap.copyWith(balances: balances));
    final q = quotaOf(channelId);
    if (q != null && q.lastBalance != null) unawaited(_setQuota(channelId, q.copyWith(clearLastBalance: true)));
  }

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
    late final Future<void> future;
    // 注意要用花括号：箭头写法会把 remove 的返回值（就是这个 Future 自己）交给 whenComplete 去等，永远等不完。
    // 放到微任务里开始：界面常在“进页面”那一刻（还在搭界面）调这里，那时不允许改状态。
    future = Future.microtask(() => _refresh(ch)).whenComplete(() {
      // 只摘掉自己：换 Key 以后可能已经有新的一次在路上了。
      if (identical(_inFlight[ch.id], future)) _inFlight.remove(ch.id);
    });
    _inFlight[ch.id] = future;
    return future;
  }

  Future<void> _refresh(Channel ch) async {
    final epoch = _epoch[ch.id] ?? 0;
    // 等待回来以后：容器已经销毁，或者这期间换过 Key，这次结果就不算数。
    bool stale() => !ref.mounted || (_epoch[ch.id] ?? 0) != epoch;
    final before = stateOf(ch.id);
    _setBalance(ch.id, BalanceState(result: before.result, error: before.error, keyInvalid: before.keyInvalid, at: before.at, loading: true));
    try {
      final key = await _models.apiKey(ch.id);
      if (stale()) return;
      final result = await fetchDeepSeekBalance(baseUrl: ch.baseUrl, apiKey: key, httpClient: ref.read(quotaHttpProvider));
      if (stale()) return;
      final problem = await _apply(ch.id, result);
      if (stale()) return;
      _setBalance(ch.id, BalanceState(result: result, error: problem, at: _now()));
    } on BalanceException catch (e) {
      if (stale()) return;
      _setBalance(ch.id, BalanceState(result: before.result, error: e.message, keyInvalid: e.keyInvalid, at: _now()));
    } on Exception catch (e) {
      if (stale()) return;
      _setBalance(ch.id, BalanceState(result: before.result, error: shortError(e), keyInvalid: before.keyInvalid, at: _now()));
    }
  }

  /// 把新查到的余额记进“已用”。返回要给用户看的问题（没有是 null）。
  Future<String?> _apply(String channelId, BalanceResult result) async {
    final q = quotaOf(channelId);
    if (q == null) return null;
    final info = result.of(q.currency);
    if (info == null) return '这次没有返回 ${q.currency} 的余额，已用没有更新';
    var used = q.used;
    var recharge = q.recharge;
    final before = q.lastBalance;
    if (before != null) {
      final spent = roundMoney4(before - info.total);
      if (spent > 0) {
        used = roundMoney4(q.used + spent);
      } else if (spent < 0) {
        recharge = true;
      }
    }
    var next = q.copyWith(used: used, recharge: recharge, lastBalance: info.total);
    if (next.warnPct > 0 && next.percent < next.warnPct) next = next.copyWith(warned: false);
    await _setQuota(channelId, next);
    return null;
  }

  /// 设上限（或改上限、改提醒阈值）。新设的会先查一次余额当起点；改已有的不清零已用。
  Future<void> setLimit(Channel ch, {required double limit, required String currency, int warnPct = ChannelQuota.defaultWarnPct}) async {
    if (!(limit > 0) || !limit.isFinite) throw ArgumentError('上限要大于 0');
    final old = quotaOf(ch.id);
    final ChannelQuota next;
    if (old != null && old.currency == currency) {
      final updated = old.copyWith(limit: limit, warnPct: warnPct.clamp(0, 99));
      next = (updated.warnPct == 0 || updated.percent < updated.warnPct) ? updated.copyWith(warned: false) : updated;
    } else {
      // 记起点：用刚查到的余额；没查到就等第一次查到时再记。
      next = ChannelQuota(limit: limit, currency: currency, warnPct: warnPct.clamp(0, 99), since: _now(), lastBalance: stateOf(ch.id).result?.of(currency)?.total);
    }
    await _setQuota(ch.id, next);
    if (!ref.mounted) return;
    if (quotaOf(ch.id)?.lastBalance == null) await refresh(ch, force: true);
  }

  /// 从现在重新算：已用清零，起点改成当前余额。
  Future<void> restart(Channel ch) async {
    final q = quotaOf(ch.id);
    if (q == null) return;
    final known = stateOf(ch.id).result?.of(q.currency)?.total;
    await _setQuota(ch.id, q.copyWith(used: 0, warned: false, recharge: false, since: _now(), lastBalance: known, clearLastBalance: known == null));
    if (!ref.mounted) return;
    await refresh(ch, force: true);
  }

  Future<void> clearLimit(String channelId) => _setQuota(channelId, null);

  /// 一段对话结束后调用：刷新余额（有节流），需要提醒时返回给用户看的一句话。
  Future<String?> afterRun(Channel ch) async {
    if (!isDeepSeekOfficial(ch.baseUrl)) return null;
    await refresh(ch);
    if (!ref.mounted) return null;
    final q = quotaOf(ch.id);
    if (q == null) return null;
    if (q.reached) {
      // 到顶只说一次（之后每次被拦都会有拦截提示）。
      if (!_toldReached.add(ch.id)) return null;
      return '$kQuotaBlockedPrefix（${formatMoney(q.currency, q.limit)}）。这个渠道接下来的请求会被拦住，到“设置 → 额度上限”可以调。';
    }
    _toldReached.remove(ch.id);
    if (q.warnPct > 0 && q.percent >= q.warnPct && !q.warned) {
      await _setQuota(ch.id, q.copyWith(warned: true));
      return '额度提醒：渠道“${ch.name}”已经用了你设的上限的 ${q.percent}%（还剩 ${formatMoney(q.currency, q.remaining)}）。到 100% 会被拦住。';
    }
    return null;
  }

  /// 给模型客户端套上额度检查。不是 DeepSeek 官方渠道原样返回。
  ChatClient guard(Channel ch, ChatClient inner) => isDeepSeekOfficial(ch.baseUrl) ? _QuotaGuardClient(this, ch, inner) : inner;
}

final quotaProvider = NotifierProvider<QuotaNotifier, QuotaState>(QuotaNotifier.new);

/// 每次向模型发请求之前检查额度（主对话、子代理、自动化任务、压缩对话都经过这里）。
class _QuotaGuardClient implements ChatClient {
  _QuotaGuardClient(this.quota, this.channel, this.inner);
  final QuotaNotifier quota;
  final Channel channel;
  final ChatClient inner;

  @override
  Stream<ChatDelta> streamChat({required List<Map<String, dynamic>> messages, List<Map<String, dynamic>> tools = const []}) async* {
    // 设了上限才值得在发请求前多查一次余额（有节流；查不到不拦）。
    if (quota.quotaOf(channel.id) != null) await quota.refresh(channel);
    final reason = quota.blockReason(channel);
    if (reason != null) {
      // 拦截提示本身已经说了“到上限”，对话结束后的提醒就不再重复说一遍。
      quota._toldReached.add(channel.id);
      throw ChatApiException(reason);
    }
    yield* inner.streamChat(messages: messages, tools: tools);
  }
}
