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

import 'package:http/http.dart' as http;
import 'package:lopicode/agent/chat_client.dart';

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

/// 一个渠道的额度上限（存进普通设置，不含任何密钥）。不可变：要改就 [copyWith] 出一个新的。
class ChannelQuota {
  ChannelQuota({required this.limit, required this.currency, this.used = 0, this.lastBalance, this.warnPct = defaultWarnPct, this.warned = false, this.recharge = false, DateTime? since})
    : since = since ?? DateTime.now();

  static const int defaultWarnPct = 80;

  /// 上限金额（> 0），币种见 [currency]。
  final double limit;
  final String currency;

  /// 设上限（或“重新算”）以来花掉的钱。
  final double used;

  /// 上一次查到的余额；还没查到过是 null（第一次查到时记为起点）。
  final double? lastBalance;

  /// 到这个百分比时提醒一次（只提醒不拦）。0 表示不提醒。
  final int warnPct;
  final bool warned;

  /// 查到余额比上次多了（充值，或者换了 Key）。
  final bool recharge;
  final DateTime since;

  double get fraction => limit <= 0 ? 0 : (used / limit).clamp(0.0, 1.0);
  int get percent => (fraction * 100 + 1e-9).floor();
  bool get reached => used + 1e-9 >= limit;
  double get remaining => (limit - used).clamp(0.0, limit);

  /// [lastBalance] 要清成 null 时传 `clearLastBalance: true`。
  ChannelQuota copyWith({double? limit, double? used, double? lastBalance, bool clearLastBalance = false, int? warnPct, bool? warned, bool? recharge, DateTime? since}) => ChannelQuota(
    limit: limit ?? this.limit,
    currency: currency,
    used: used ?? this.used,
    lastBalance: clearLastBalance ? null : (lastBalance ?? this.lastBalance),
    warnPct: warnPct ?? this.warnPct,
    warned: warned ?? this.warned,
    recharge: recharge ?? this.recharge,
    since: since ?? this.since,
  );

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

/// 最近一次查余额的结果（只在内存里）。不可变。
class BalanceState {
  const BalanceState({this.result, this.error, this.keyInvalid = false, this.at, this.loading = false});

  final BalanceResult? result;

  /// 最近一次没查到的原因；查到了是 null。
  final String? error;

  /// 最近一次是不是因为 Key 无效（401 / 403）没查到。断网、服务器出错不算。
  final bool keyInvalid;
  final DateTime? at;
  final bool loading;

  static const empty = BalanceState();
}

/// 金额保留四位小数（余额相减会有浮点尾巴）。
double roundMoney4(double v) => (v * 10000).round() / 10000;
