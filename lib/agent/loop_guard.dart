// 工具循环里的几道“保险”：重复失败的死循环、过长的工具结果、快占满的上下文、接口临时出错的重试。
// 都是纯计算，不碰界面、不碰磁盘；AgentRunner 在循环里调用。
import 'dart:convert';

/// 同一个调用（工具名 + 参数）连续失败几次后，不再真的执行，直接告诉模型换办法。
const int kRepeatFailLimit = 3;

/// 同一个调用连续失败到这个数，整轮停下（模型已经不听劝了）。
const int kRepeatFailStop = 5;

/// 同一个调用连续成功到这个数（比如反复读同一个文件），提醒模型别原地打转。
const int kRepeatOkNudge = 4;

/// 交给模型的单条工具结果的上限（字符）。读文件、命令输出各自还有更小的上限，这里是兜底。
const int kMaxToolResultChars = 24000;

/// 重复调用检测的结论。
enum LoopVerdict {
  /// 正常执行。
  run,

  /// 不执行，把“换个办法”的提示当结果回给模型。
  refuse,

  /// 整轮停下。
  stop,
}

/// 记“上一次调用是什么、连着几次、成没成”。只看**连续**的同一调用，中间夹了别的调用就重新数。
class LoopGuard {
  String? _lastKey;
  int _fails = 0;
  int _oks = 0;

  static String keyOf(String name, String rawArgs) {
    // 参数按规范化后的 JSON 比（键的顺序、空白不同算同一个）；不是合法 JSON 就按原文比。
    try {
      return '$name\u0000${jsonEncode(_canonical(jsonDecode(rawArgs.trim().isEmpty ? '{}' : rawArgs)))}';
    } on FormatException {
      return '$name\u0000${rawArgs.trim()}';
    }
  }

  static Object? _canonical(Object? v) {
    if (v is Map) {
      final keys = v.keys.map((k) => '$k').toList()..sort();
      return {for (final k in keys) k: _canonical(v[k])};
    }
    if (v is List) return [for (final e in v) _canonical(e)];
    return v;
  }

  /// 执行前问一声：这个调用该不该跑。
  LoopVerdict check(String name, String rawArgs) {
    final key = keyOf(name, rawArgs);
    if (key != _lastKey) return LoopVerdict.run;
    if (_fails >= kRepeatFailStop - 1) return LoopVerdict.stop;
    if (_fails >= kRepeatFailLimit - 1) return LoopVerdict.refuse;
    return LoopVerdict.run;
  }

  /// 执行后记一笔。[refused] 是被 [check] 拦下没真跑的，也算一次失败。返回要附在结果后面的提醒（没有就是 null）。
  String? record(String name, String rawArgs, {required bool ok}) {
    final key = keyOf(name, rawArgs);
    if (key != _lastKey) {
      _lastKey = key;
      _fails = 0;
      _oks = 0;
    }
    if (ok) {
      _oks++;
      _fails = 0;
      if (_oks == kRepeatOkNudge) return '\n\n（提醒：你已经连续 $_oks 次用完全相同的参数调用 $name，结果不会变。请根据已有结果继续下一步，不要再重复。）';
    } else {
      _fails++;
      _oks = 0;
    }
    return null;
  }

  /// 被拦下时回给模型的话。
  static String refusal(String name) =>
      '错误：你已经连续 ${kRepeatFailLimit - 1} 次用完全相同的参数调用 $name，都失败了，这一次没有执行。'
      '请先看清前面的报错原因，改参数或换一个办法；确实做不到就向用户说明卡在哪里。';
}

/// 把过长的工具结果截成“开头 + 结尾”，中间说明省了多少。不超过 [max] 的原样返回。
String clipToolResult(String text, {int max = kMaxToolResultChars}) {
  if (text.length <= max) return text;
  final head = (max * 0.7).floor();
  final tail = max - head;
  final omitted = text.length - head - tail;
  return '${text.substring(0, head)}\n…（中间省略 $omitted 字符，结果共 ${text.length} 字符。需要被省略的部分请缩小范围再查，例如读文件时指定行号范围）…\n${text.substring(text.length - tail)}';
}

/// 被裁掉的旧工具结果换成的占位文字（以它开头就说明已经裁过，不重复裁）。
const String kPrunedToolResult = '（这条较早的工具结果已省略，以节省上下文。需要时请重新调用工具获取。）';

/// 上下文快满时的省法：把**较早**的、比较长的工具结果换成一句占位，最近 [keepRecent] 条不动。
/// 不删消息、不动 tool_call_id（接口要求每个 tool_call 都有对应的 tool 消息）。返回裁掉了几条。
int pruneOldToolResults(List<Map<String, dynamic>> messages, {int keepRecent = 6, int minChars = 400}) {
  final toolAt = <int>[
    for (var i = 0; i < messages.length; i++)
      if (messages[i]['role'] == 'tool' && messages[i]['_archived'] != true) i,
  ];
  var pruned = 0;
  for (var k = 0; k < toolAt.length - keepRecent; k++) {
    final m = messages[toolAt[k]];
    final content = m['content'];
    if (content is! String || content.length < minChars || content.startsWith(kPrunedToolResult)) continue;
    messages[toolAt[k]] = {...m, 'content': kPrunedToolResult};
    pruned++;
  }
  return pruned;
}

/// 接口返回这些状态码时值得等一下再试（限流、服务端临时出错）。别的（401、404、400……）重试也没用。
bool isRetryableStatus(int? status) => status != null && const {408, 429, 500, 502, 503, 504, 529}.contains(status);

/// 第 [attempt] 次重试前等多久（从 1 起）。
Duration retryDelay(int attempt) => Duration(milliseconds: 1500 * attempt * attempt);

/// 工具参数解析不了时回给模型的话：说清楚错在哪、该怎么改。
String badArgumentsMessage(String name, String rawArgs, {FormatException? error, bool truncated = false}) {
  final why = truncated
      ? '参数没写完就被截断了（可能是一次输出太长）'
      : error == null
      ? '参数必须是一个 JSON 对象（形如 {"键": 值}）'
      : '参数不是合法的 JSON（${error.message}）';
  final shown = rawArgs.length > 200 ? '${rawArgs.substring(0, 200)}…' : rawArgs;
  return '错误：调用 $name 失败，$why，这次没有执行。你给的参数是：$shown\n请重新调用，给出完整、合法的 JSON 对象${truncated ? '；内容太长时分几次写' : ''}。';
}
