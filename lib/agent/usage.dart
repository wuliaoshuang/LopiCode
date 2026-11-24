// 用量统计：每次模型请求的 token 数、每一轮（用户发一条消息到 Agent 停下）的轨迹和合计、每段对话的累计。
// 字段出处见 docs/api-notes.md 的“用量（usage）”一节。接口没给的数一律留空，不估、不编。
//
// 口径（参照 dsh-Go 的做法，代码是自己写的）：
//   输入 = 未缓存输入 + 缓存读取 + 缓存写入；合计 = 输入 + 输出；缓存命中率 = 缓存读取 ÷ 输入。
import 'package:lopicode/agent/model_config.dart';

int? _int(Object? v) => v is int ? v : (v is num ? v.toInt() : null);

/// 一次请求的用量（各协议统一成同一个样子）。
class TokenUsage {
  const TokenUsage({required this.uncached, required this.output, this.cacheRead = 0, this.cacheWrite = 0, this.reasoning, this.hasCache = false});

  /// 没走缓存的输入。
  final int uncached;

  /// 从缓存读到的输入（命中）。
  final int cacheRead;

  /// 这次新写进缓存的输入（只有部分接口给）。
  final int cacheWrite;
  final int output;

  /// 输出里用于推理的部分（已包含在 [output] 里）；接口没给是 null。
  final int? reasoning;

  /// 接口有没有给缓存相关的字段。没给时 [cacheRead] 是 0，但那不代表“命中率 0%”，界面上不显示命中率。
  final bool hasCache;

  int get input => uncached + cacheRead + cacheWrite;
  int get total => input + output;

  Map<String, dynamic> toJson() => {'in': uncached, 'out': output, if (hasCache) 'hit': cacheRead, if (cacheWrite > 0) 'write': cacheWrite, 'think': ?reasoning};

  static TokenUsage? fromJson(Object? j) {
    if (j is! Map) return null;
    final uncached = _int(j['in']), output = _int(j['out']);
    if (uncached == null || output == null) return null;
    final hit = _int(j['hit']), write = _int(j['write']);
    return TokenUsage(uncached: uncached, output: output, cacheRead: hit ?? 0, cacheWrite: write ?? 0, reasoning: _int(j['think']), hasCache: hit != null || write != null);
  }
}

int _nonNeg(int v) => v < 0 ? 0 : v;

/// OpenAI Chat Completions 的 `usage`（DeepSeek 多两个缓存字段）。
/// - `prompt_tokens`、`completion_tokens`；
/// - DeepSeek：`prompt_cache_hit_tokens` → 缓存读取，`prompt_cache_miss_tokens` → 未缓存输入（两者相加等于 prompt_tokens）；
/// - OpenAI：`prompt_tokens_details.cached_tokens`（是 prompt_tokens 的一部分）→ 缓存读取，其余算未缓存；
/// - `completion_tokens_details.reasoning_tokens` → 推理。
TokenUsage? usageFromChatCompletions(Object? u) {
  if (u is! Map) return null;
  final prompt = _int(u['prompt_tokens']), output = _int(u['completion_tokens']);
  if (prompt == null && output == null) return null;
  final details = u['prompt_tokens_details'];
  final hit = _int(u['prompt_cache_hit_tokens']) ?? (details is Map ? _int(details['cached_tokens']) : null);
  final miss = _int(u['prompt_cache_miss_tokens']);
  final out = u['completion_tokens_details'];
  return TokenUsage(
    uncached: miss ?? _nonNeg((prompt ?? 0) - (hit ?? 0)),
    cacheRead: hit ?? 0,
    output: output ?? 0,
    reasoning: out is Map ? _int(out['reasoning_tokens']) : null,
    hasCache: hit != null || miss != null,
  );
}

/// OpenAI Responses 的 `response.usage`：`input_tokens`（含缓存）、`input_tokens_details.cached_tokens`、
/// `output_tokens`、`output_tokens_details.reasoning_tokens`。
TokenUsage? usageFromResponses(Object? u) {
  if (u is! Map) return null;
  final input = _int(u['input_tokens']), output = _int(u['output_tokens']);
  if (input == null && output == null) return null;
  final details = u['input_tokens_details'];
  final hit = details is Map ? _int(details['cached_tokens']) : null;
  final write = details is Map ? _int(details['cache_write_tokens']) : null;
  final out = u['output_tokens_details'];
  return TokenUsage(
    uncached: _nonNeg((input ?? 0) - (hit ?? 0) - (write ?? 0)),
    cacheRead: hit ?? 0,
    cacheWrite: write ?? 0,
    output: output ?? 0,
    reasoning: out is Map ? _int(out['reasoning_tokens']) : null,
    hasCache: hit != null || write != null,
  );
}

/// Anthropic Messages：`message_start.message.usage` 给输入，`message_delta.usage` 给（累计的）输出，
/// 后者里出现的非空字段以后者为准。
/// Anthropic 的 `input_tokens` **不含**缓存，正好是“未缓存输入”；`cache_read_input_tokens` → 缓存读取，
/// `cache_creation_input_tokens` → 缓存写入。
TokenUsage? usageFromAnthropic(Object? start, Object? delta) {
  if (start is! Map && delta is! Map) return null;
  int? pick(String key) => (delta is Map ? _int(delta[key]) : null) ?? (start is Map ? _int(start[key]) : null);
  final uncached = pick('input_tokens'), output = pick('output_tokens');
  if (uncached == null && output == null) return null;
  final read = pick('cache_read_input_tokens'), write = pick('cache_creation_input_tokens');
  return TokenUsage(uncached: uncached ?? 0, cacheRead: read ?? 0, cacheWrite: write ?? 0, output: output ?? 0, hasCache: read != null || write != null);
}

/// 模型单价（元每百万 token），用户自己填的；没填全就不估算。LopiCode 不内置价格表。
class ModelPrice {
  const ModelPrice({required this.hit, required this.miss, required this.output});
  final double hit;
  final double miss;
  final double output;

  static ModelPrice? of(ModelSpec m) => m.priceHit == null || m.priceMiss == null || m.priceOutput == null ? null : ModelPrice(hit: m.priceHit!, miss: m.priceMiss!, output: m.priceOutput!);

  /// 一次请求的估算费用：缓存写入按输入（未命中）价，命中按命中价。
  double cost(TokenUsage u) => ((u.uncached + u.cacheWrite) * miss + u.cacheRead * hit + u.output * output) / 1e6;
}

/// 一次模型请求。
class RequestUsage {
  RequestUsage({this.usage, required this.ms, this.firstMs, this.startedAt, this.cost, this.compaction = false});

  /// 这次请求是“自动压缩对话”那一次（不是在回答用户）。
  final bool compaction;

  /// 接口没返回用量是 null。
  final TokenUsage? usage;

  /// 这次请求从发出到收完用了多久。
  final int ms;

  /// 从发出到收到第一块内容用了多久（首字）；没收到内容是 null。
  final int? firstMs;

  /// 发出的时刻。
  final DateTime? startedAt;

  /// 估算费用（填了单价才有）。
  final double? cost;

  /// 生成用时 = 总用时 − 首字用时。
  int? get generationMs => firstMs == null ? null : (ms - firstMs! < 0 ? 0 : ms - firstMs!);

  /// 输出速度（tokens/秒）：输出 ÷ 生成用时。算不出来是 null。
  double? get speed {
    final gen = generationMs, out = usage?.output;
    return gen == null || gen <= 0 || out == null || out <= 0 ? null : out / (gen / 1000);
  }

  Map<String, dynamic> toJson() => {'u': ?usage?.toJson(), 'ms': ms, 'first': ?firstMs, 'at': ?startedAt?.millisecondsSinceEpoch, 'cost': ?cost, if (compaction) 'k': 'compact'};

  static RequestUsage fromJson(Map<dynamic, dynamic> j) {
    final cost = j['cost'], at = _int(j['at']);
    return RequestUsage(
      usage: TokenUsage.fromJson(j['u']),
      ms: _int(j['ms']) ?? 0,
      firstMs: _int(j['first']),
      startedAt: at == null ? null : DateTime.fromMillisecondsSinceEpoch(at),
      cost: cost is num ? cost.toDouble() : null,
      compaction: j['k'] == 'compact',
    );
  }
}

/// 轨迹里的一段：一次模型请求，或一次工具调用。
sealed class TraceStep {
  Map<String, dynamic> toJson();

  static TraceStep? fromJson(Object? j) {
    if (j is! Map) return null;
    return j['t'] == 'tool' ? ToolStep.fromJson(j) : RequestStep(RequestUsage.fromJson(j));
  }
}

class RequestStep extends TraceStep {
  RequestStep(this.request);
  final RequestUsage request;

  @override
  Map<String, dynamic> toJson() => request.toJson();
}

class ToolStep extends TraceStep {
  ToolStep(this.callId, this.name, {this.ms, this.ok = true});

  /// 对应聊天记录里的那次工具调用（参数和结果在聊天记录里，不在这里重复存）。
  final String callId;
  final String name;

  /// 用时；还没结束是 null。
  int? ms;
  bool ok;

  @override
  Map<String, dynamic> toJson() => {'t': 'tool', 'id': callId, 'name': name, 'ms': ?ms, 'ok': ok};

  static ToolStep fromJson(Map<dynamic, dynamic> j) => ToolStep('${j['id'] ?? ''}', '${j['name'] ?? ''}', ms: _int(j['ms']), ok: j['ok'] != false);
}

/// 合计。
class UsageTotals {
  int uncached = 0;
  int cacheRead = 0;
  int cacheWrite = 0;
  int output = 0;
  int reasoning = 0;

  /// 请求总数，其中 [unreported] 次接口没返回用量。
  int requests = 0;
  int unreported = 0;

  /// 轮数（只在对话累计里用）。
  int turns = 0;

  /// 有没有哪次请求给了缓存 / 推理的数（没有就不显示对应的项）。
  bool hasCache = false;
  bool hasReasoning = false;

  /// 估算费用；[costed] 是算进去的请求数（比有用量的请求少时，金额只是一部分）。
  double cost = 0;
  int costed = 0;

  int get input => uncached + cacheRead + cacheWrite;
  int get total => input + output;
  int get reported => requests - unreported;

  /// 缓存命中率 = 缓存读取 ÷ 输入；没有输入、或接口没给缓存数据是 null（界面显示“—”）。
  double? get hitRate => !hasCache || input == 0 ? null : cacheRead / input;

  void addRequest(RequestUsage r) {
    requests++;
    final u = r.usage;
    if (u == null) {
      unreported++;
      return;
    }
    uncached += u.uncached;
    cacheRead += u.cacheRead;
    cacheWrite += u.cacheWrite;
    output += u.output;
    hasCache = hasCache || u.hasCache;
    if (u.reasoning != null) {
      hasReasoning = true;
      reasoning += u.reasoning!;
    }
    if (r.cost != null) {
      cost += r.cost!;
      costed++;
    }
  }

  void add(UsageTotals o) {
    uncached += o.uncached;
    cacheRead += o.cacheRead;
    cacheWrite += o.cacheWrite;
    output += o.output;
    reasoning += o.reasoning;
    requests += o.requests;
    unreported += o.unreported;
    turns += o.turns;
    hasCache = hasCache || o.hasCache;
    hasReasoning = hasReasoning || o.hasReasoning;
    cost += o.cost;
    costed += o.costed;
  }

  Map<String, dynamic> toJson() => {
    'in': uncached,
    'hit': cacheRead,
    'write': cacheWrite,
    'out': output,
    'think': reasoning,
    'req': requests,
    'noUsage': unreported,
    'turns': turns,
    'cache': hasCache,
    'hasThink': hasReasoning,
    'cost': cost,
    'costed': costed,
  };

  static UsageTotals fromJson(Object? j) {
    final t = UsageTotals();
    if (j is! Map) return t;
    final cost = j['cost'];
    return t
      ..uncached = _int(j['in']) ?? 0
      ..cacheRead = _int(j['hit']) ?? 0
      ..cacheWrite = _int(j['write']) ?? 0
      ..output = _int(j['out']) ?? 0
      ..reasoning = _int(j['think']) ?? 0
      ..requests = _int(j['req']) ?? 0
      ..unreported = _int(j['noUsage']) ?? 0
      ..turns = _int(j['turns']) ?? 0
      ..hasCache = j['cache'] == true
      ..hasReasoning = j['hasThink'] == true
      ..cost = cost is num ? cost.toDouble() : 0
      ..costed = _int(j['costed']) ?? 0;
  }
}

/// 一轮：用户发一条消息到 Agent 停下。[steps] 按时间记着每次模型请求和每次工具调用，派出去的子代理各算一份。
class TurnUsage {
  TurnUsage({List<TraceStep>? steps, this.ms = 0, List<ChildUsage>? children}) : steps = steps ?? [], children = children ?? [];
  final List<TraceStep> steps;

  /// 这一轮从开始到停下用了多久（含跑工具、等确认的时间）。
  int ms;
  final List<ChildUsage> children;

  List<RequestUsage> get requests => [
    for (final s in steps)
      if (s is RequestStep) s.request,
  ];

  /// 只算自己发的请求。
  UsageTotals get own {
    final t = UsageTotals();
    for (final r in requests) {
      t.addRequest(r);
    }
    return t;
  }

  /// 自己加上所有子代理。
  UsageTotals get totals {
    final t = own;
    for (final c in children) {
      t.add(c.turn.totals);
    }
    return t;
  }

  /// 步数：模型请求的次数（含子代理的）。
  int get stepCount => totals.requests;

  Map<String, dynamic> toJson() => {
    'steps': [for (final s in steps) s.toJson()],
    'ms': ms,
    if (children.isNotEmpty) 'kids': [for (final c in children) c.toJson()],
  };

  static TurnUsage? fromJson(Object? j) {
    if (j is! Map) return null;
    return TurnUsage(
      steps: [for (final s in (j['steps'] as List?) ?? const []) ?TraceStep.fromJson(s)],
      ms: _int(j['ms']) ?? 0,
      children: [for (final c in (j['kids'] as List?) ?? const []) ?ChildUsage.fromJson(c)],
    );
  }
}

/// 子代理在上级这一轮里花的用量。
class ChildUsage {
  ChildUsage(this.name, this.turn);
  final String name;
  final TurnUsage turn;

  Map<String, dynamic> toJson() => {'name': name, 'turn': turn.toJson()};

  static ChildUsage? fromJson(Object? j) {
    if (j is! Map) return null;
    final turn = TurnUsage.fromJson(j['turn']);
    return turn == null ? null : ChildUsage('${j['name'] ?? ''}', turn);
  }
}

String _trimZeros(String text) {
  if (!text.contains('.')) return text;
  return text.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
}

/// 999 → “999”；1000 → “1K”；61800 → “61.8K”；1050000 → “1.05M”。只用 K、M，不用万、亿。
String formatTokens(int n) {
  if (n < 1000) return '$n';
  if (n < 999950) return '${_trimZeros((n / 1000).toStringAsFixed(1))}K';
  return '${_trimZeros((n / 1000000).toStringAsFixed(2))}M';
}

/// “0.8 秒”“47 秒”“1 分 5 秒”。
String formatSpan(int ms) {
  if (ms < 1000) return '${_trimZeros((ms / 1000).toStringAsFixed(1))} 秒';
  final s = (ms / 1000).round();
  if (s < 60) return ms < 10000 ? '${_trimZeros((ms / 1000).toStringAsFixed(1))} 秒' : '$s 秒';
  return s % 60 == 0 ? '${s ~/ 60} 分' : '${s ~/ 60} 分 ${s % 60} 秒';
}

/// 百分比；大于 0 但不到 1% 写“<1%”。
String formatPercent(double fraction) {
  if (fraction > 0 && fraction < 0.01) return '<1%';
  return '${(fraction * 100).round()}%';
}

/// 估算金额：“约 ¥0.03”；不到一分写“不到 ¥0.01”。
String formatCost(double yuan) => yuan < 0.01 ? '不到 ¥0.01' : '约 ¥${yuan.toStringAsFixed(2)}';

/// 回合脚注从全到简的几种写法（第一种放得下就用它）：依次省掉 tokens、步数、花费，用时永远保留。
List<String> footnoteVariants(TurnUsage turn) {
  final t = turn.totals;
  final time = formatSpan(turn.ms);
  final steps = t.requests > 0 ? '${t.requests} 步' : null;
  final cost = t.costed > 0 ? formatCost(t.cost) : null;
  final tokens = t.requests == 0 ? null : (t.reported == 0 ? '接口没返回用量' : '${formatTokens(t.total)} tokens');
  String join(List<String?> parts) => parts.whereType<String>().join(' · ');
  final out = <String>[];
  for (final v in [
    join([time, steps, cost, tokens]),
    join([time, steps, cost]),
    join([time, cost]),
    time,
  ]) {
    if (!out.contains(v)) out.add(v);
  }
  return out;
}

/// 合计的一行（轨迹顶部、子代理小计用）。
String totalsLine(UsageTotals t) {
  if (t.requests == 0) return '没有向模型发出请求';
  if (t.reported == 0) return '${t.requests} 次请求，接口都没返回用量';
  final rate = t.hitRate;
  return [
    '${formatTokens(t.total)} tokens',
    '输入 ${formatTokens(t.input)}${rate == null ? '' : '（缓存命中 ${formatPercent(rate)}）'}',
    '输出 ${formatTokens(t.output)}',
    if (t.hasReasoning) '推理 ${formatTokens(t.reasoning)}',
    t.unreported > 0 ? '${t.requests} 次请求（${t.unreported} 次没返回用量）' : '${t.requests} 次请求',
    if (t.costed > 0) formatCost(t.cost),
  ].join(' · ');
}

/// 粗略估算一段文字占多少 token（按 3 个字符 1 个 token，偏保守）。只用于上下文分项，界面上要注明是估算。
int estimateTextTokens(String text) => (text.length / 3).ceil();
