// 把较早的对话压成摘要：/compact（手动，整段压）和“上下文快满时自动压缩”（只压较早的部分）共用这一份。
//
// 规矩：
// - 发给模型的是**一段纯文字的对话记录**，不是原来的消息列表：这样不带工具定义也合法（Anthropic 等接口不许消息里有
//   工具调用却不带工具定义），思考内容之类的协议细节也不用管。
// - 失败（接口报错、被额度拦下、模型没给摘要）时消息记录**一个字都不动**，把原因交回去。
// - 自动压缩时：最近 [keepRecent] 条原样留着（切口不落在工具结果上，保证调用和结果成对）；
//   被压掉的不删，打上 `_archived` 标记留在记录里——聊天页照样能看，只是不再发给模型。
// - 自动压缩发生在一轮中间，用户最近一次的要求要是在被压掉的那段里，就把原话附在摘要后面（不靠模型自觉）。
import 'package:lopicode/agent/chat_client.dart';
import 'package:lopicode/agent/usage.dart';

/// 自动压缩时原样保留最近几条消息。
const int kCompactKeepRecent = 6;

/// 交给模型做摘要的对话记录最多这么多字符（上下文长度未知时用）。
const int kCompactMaxTranscriptChars = 240000;

/// 摘要消息、承接消息、已归档消息上的标记（都以 `_` 开头：发给接口前会去掉）。
const String kCompactMark = '_compact';
const String kCompactAckMark = '_compactAck';
const String kArchivedMark = '_archived';

/// 摘要消息的开头（聊天页据此把它显示成“已压缩较早的对话”）。
const String kCompactPrefix = '（之前的对话已压缩，以下是摘要）\n';

bool isArchived(Map<String, dynamic> m) => m[kArchivedMark] == true;

/// 摘要消息里的摘要正文（不含开头那句）。
String compactSummaryOf(Map<String, dynamic> m) {
  final text = '${m['content'] ?? ''}';
  return text.startsWith(kCompactPrefix) ? text.substring(kCompactPrefix.length) : text;
}

class CompactOutcome {
  const CompactOutcome({this.error, this.skipped = false, this.summary = '', this.usage, this.ms = 0, this.startedAt, this.requested = false, this.replaced = 0});

  /// 失败原因；成功是 null。
  final String? error;

  /// 没什么可压的（对话还短）：没发请求，记录没动。
  final bool skipped;
  final String summary;

  /// 压缩那次请求的用量（接口没给是 null）、用时。
  final TokenUsage? usage;
  final int ms;
  final DateTime? startedAt;

  /// 接口是不是已经开始回话（开始了才算一次请求、才记用量）。
  final bool requested;

  /// 被摘要顶替的消息条数。
  final int replaced;

  bool get ok => error == null && !skipped;
}

String _clip(String s, int max) => s.length > max ? '${s.substring(0, max)}…（共 ${s.length} 字，后面省略）' : s;

/// 把消息记录写成一段给模型看的纯文字。工具参数、工具结果各自截短。
String renderTranscript(List<Map<String, dynamic>> messages, {int maxChars = kCompactMaxTranscriptChars}) {
  final out = StringBuffer();
  for (final m in messages) {
    final content = m['content'];
    final text = content is String ? content.trim() : '';
    switch (m['role']) {
      case 'user':
        final images = m['_images'];
        out.writeln('【用户】${_clip(text, 6000)}${images is List && images.isNotEmpty ? '（附了 ${images.length} 张图片）' : ''}');
      case 'assistant':
        if (text.isNotEmpty) out.writeln('【助手】${_clip(text, 6000)}');
        final calls = m['tool_calls'];
        for (final c in calls is List ? calls : const []) {
          final fn = c is Map ? c['function'] : null;
          if (fn is Map) out.writeln('【助手调用工具 ${fn['name']}】${_clip('${fn['arguments'] ?? ''}', 600)}');
        }
      case 'tool':
        out.writeln('【工具结果】${_clip(text, 1500)}');
    }
  }
  final all = out.toString();
  if (all.length <= maxChars) return all;
  // 还是太长：留开头三成、结尾七成（最近的更要紧）。
  final head = (maxChars * 0.3).floor();
  return '${all.substring(0, head)}\n…（中间省略 ${all.length - maxChars} 字）…\n${all.substring(all.length - (maxChars - head))}';
}

const String _ask =
    '请把上面这段对话记录压缩成一份摘要，之后会用它顶替原来的记录接着干活。写清楚：用户的目标和要求、已经做完的事（改了哪些文件）、'
    '还没做完的事、要注意的约定。只输出摘要本身，用简体中文。';

/// 把 [messages] 里较早的部分压成摘要，就地改写。
///
/// - [keepRecent]：最近几条原样保留（0＝整段都压）。
/// - [archive]：被压掉的消息留在记录里并标成已归档（聊天页还能看）；false 则直接去掉。
/// - [keepLastRequest]：把被压掉那段里用户最近一次的原话附在摘要后面。
/// - [contextLimit]：模型的上下文长度（token），用来限制交给它的记录长度。
Future<CompactOutcome> compactOlder(ChatClient client, List<Map<String, dynamic>> messages, {int keepRecent = 0, bool archive = false, bool keepLastRequest = false, int? contextLimit}) async {
  var first = messages.indexWhere((m) => !isArchived(m));
  if (first < 0) first = messages.length;
  var cut = messages.length - keepRecent;
  // 切口不能落在工具结果上：往前挪到发起调用的那条 assistant 消息。
  while (cut > first && cut < messages.length && messages[cut]['role'] == 'tool') {
    cut--;
  }
  final older = cut > first ? messages.sublist(first, cut) : const <Map<String, dynamic>>[];
  // 太短，或者这段里只有上一次的摘要：不压。
  if (older.length < 2 || older.every((m) => m[kCompactMark] == true || m[kCompactAckMark] == true)) return const CompactOutcome(skipped: true);

  final maxChars = contextLimit == null ? kCompactMaxTranscriptChars : (contextLimit * 3 * 0.6).floor().clamp(6000, kCompactMaxTranscriptChars);
  final request = <Map<String, dynamic>>[
    {'role': 'system', 'content': '你是对话记录整理员。'},
    {'role': 'user', 'content': '下面是一段编程助手和用户的对话记录：\n<<<\n${renderTranscript(older, maxChars: maxChars)}>>>\n\n$_ask'},
  ];
  final text = StringBuffer();
  TokenUsage? usage;
  var requested = false;
  final startedAt = DateTime.now();
  final clock = Stopwatch()..start();
  CompactOutcome failed(String why) => CompactOutcome(error: why, usage: usage, ms: clock.elapsedMilliseconds, startedAt: startedAt, requested: requested);
  try {
    await for (final d in client.streamChat(messages: request)) {
      requested = true;
      if (d.usage != null) usage = d.usage;
      if (d.content != null) text.write(d.content);
    }
  } on ChatApiException catch (e) {
    return failed(e.message);
  } on Exception catch (e) {
    return failed('和模型的连接中断了：${shortError(e)}');
  }
  final summary = text.toString().trim();
  if (summary.isEmpty) return failed('模型没有给出摘要，对话记录没有动');

  var content = '$kCompactPrefix$summary';
  if (keepLastRequest) {
    final last = older.lastWhere((m) => m['role'] == 'user' && m[kCompactMark] != true, orElse: () => const {});
    final said = '${last['content'] ?? ''}'.trim();
    if (said.isNotEmpty) content = '$content\n\n用户最近一次的要求（原话）：\n${_clip(said, 4000)}';
  }
  final tail = messages.sublist(cut);
  final next = <Map<String, dynamic>>[
    ...messages.sublist(0, first),
    if (archive)
      for (final m in older) {...m, kArchivedMark: true},
    {'role': 'user', 'content': content, kCompactMark: true},
    // 后面紧跟的要是 assistant 消息，就不再插一句承接（免得两条 assistant 连着）。
    if (tail.isEmpty || tail.first['role'] == 'user') {'role': 'assistant', 'content': '好的，我已经了解之前的进展，可以接着做。', kCompactAckMark: true},
    ...tail,
  ];
  messages
    ..clear()
    ..addAll(next);
  return CompactOutcome(summary: summary, usage: usage, ms: clock.elapsedMilliseconds, startedAt: startedAt, requested: true, replaced: older.length);
}

/// /compact：让模型把到目前为止的对话压成一段摘要，然后用摘要顶替原来的记录。
/// 成功返回 null 并就地改写 [messages]；失败返回原因，记录不动。
Future<String?> compactHistory(ChatClient client, List<Map<String, dynamic>> messages) async {
  if (messages.where((m) => !isArchived(m)).length < 2) return '对话还很短，不需要压缩';
  final r = await compactOlder(client, messages);
  return r.skipped ? '对话还很短，不需要压缩' : r.error;
}

/// 上一轮没正常收尾（App 被关掉）时，记录里可能有“发起了工具调用、却没有结果”的 assistant 消息——
/// 这样的记录下一次请求会被接口拒绝。给每个缺结果的调用补一条说明，返回补了几条。
int repairDanglingCalls(List<Map<String, dynamic>> messages, {String note = kUnknownResultNote}) {
  var fixed = 0;
  for (var i = 0; i < messages.length; i++) {
    final m = messages[i];
    final calls = m['tool_calls'];
    if (m['role'] != 'assistant' || calls is! List || calls.isEmpty) continue;
    var end = i + 1;
    final have = <String>{};
    while (end < messages.length && messages[end]['role'] == 'tool') {
      have.add('${messages[end]['tool_call_id']}');
      end++;
    }
    final missing = [
      for (final c in calls)
        if (c is Map && !have.contains('${c['id']}')) '${c['id']}',
    ];
    if (missing.isEmpty) continue;
    messages.insertAll(end, [
      for (final id in missing) {'role': 'tool', 'tool_call_id': id, 'content': note, if (isArchived(m)) kArchivedMark: true},
    ]);
    fixed += missing.length;
    i = end + missing.length - 1;
  }
  return fixed;
}

/// 补给“没有结果的工具调用”的说明。以“错误”开头：聊天页会把这一步显示成失败。
const String kUnknownResultNote = '错误：这一步执行到一半时 App 被关掉了，没有拿到结果——它可能没执行、可能只执行了一半、也可能已经执行完。接着做之前先检查实际情况，不要想当然地重做。';
