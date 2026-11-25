// conversation_search：在**当前工作区**的历史对话里按关键词找，返回对话标题、时间和命中的片段。只读，不跨工作区。
//
// 规矩：
// - 只看这个工作区对话目录里的对话（主对话和自动化任务跑出来的；子代理的对话不单列——它的汇报已经在上级对话里）；
// - 只在用户和助手说的话里找，不翻工具结果（那里是大段文件内容和命令输出）；
// - 片段先过一遍脱敏再交给模型；
// - 条数、片段长度、总长度都有上限。
import 'package:lopicode/agent/agent_tools.dart';
import 'package:lopicode/agent/auto_compact.dart';
import 'package:lopicode/core/crash_log.dart';
import 'package:lopicode/core/safe_file.dart';
import 'package:lopicode/session/conversation.dart';
import 'package:lopicode/session/session_core.dart';
import 'package:lopicode/state/workspace_chat.dart';

const String kConversationSearchTool = 'conversation_search';

/// 最多回几段对话、每段最多几个片段、每个片段多长、关键词最长多少、最多翻多少段对话。
const int kConvSearchMaxConversations = 8;
const int kConvSearchMaxSnippets = 3;
const int kConvSearchSnippetChars = 160;
const int kConvSearchMaxQueryChars = 100;
const int kConvSearchMaxScan = 200;

String _two(int n) => n.toString().padLeft(2, '0');
String _stamp(DateTime t) => '${t.year}-${_two(t.month)}-${_two(t.day)} ${_two(t.hour)}:${_two(t.minute)}';

/// 一条消息里命中处前后的一小段（压成一行、脱敏）。
String _snippet(String text, int at, int termLength) {
  final from = (at - kConvSearchSnippetChars ~/ 3).clamp(0, text.length);
  final to = (from + kConvSearchSnippetChars).clamp(0, text.length);
  final piece = redactSecrets(text.substring(from, to)).replaceAll(RegExp(r'\s+'), ' ').trim();
  return '${from > 0 ? '…' : ''}$piece${to < text.length ? '…' : ''}';
}

/// 在一段对话的消息里找：空白隔开的几个词要在同一条消息里都出现（不分大小写）。
List<String> searchMessages(List<Map<String, dynamic>> messages, List<String> terms) {
  final out = <String>[];
  for (final m in messages) {
    final role = m['role'];
    final content = m['content'];
    if ((role != 'user' && role != 'assistant') || content is! String || content.isEmpty) continue;
    if (m[kCompactAckMark] == true) continue;
    final lower = content.toLowerCase();
    if (!terms.every(lower.contains)) continue;
    final who = m[kCompactMark] == true ? '摘要' : (role == 'user' ? '用户' : '助手');
    out.add('$who：${_snippet(content, lower.indexOf(terms.first), terms.first.length)}');
    if (out.length >= kConvSearchMaxSnippets) break;
  }
  return out;
}

Future<List<Map<String, dynamic>>> _messagesOf(SessionCore core, Conversation conv) async {
  final run = core.runs[conv.id];
  if (run != null && run.loaded) return run.messages;
  // 坏文件：readJsonFile 备份后返回 null，这里当作这段对话是空的。
  final decoded = await readJsonFile(core.chatFileOf(conv.id), accept: (j) => j is List, label: '对话记录');
  return [
    for (final m in decoded is List ? decoded : const [])
      if (m is Map<String, dynamic>) m,
  ];
}

ExtraTool conversationSearchTool(SessionCore core, ChatRunNotifier run) => ExtraTool(
  spec: toolSpec(
    kConversationSearchTool,
    '在这个工作区以前的对话里按关键词找（用户提到“上次”“之前说过”而你这里没有上下文时用）。返回对话标题、时间和命中的片段。几个词用空格隔开，要在同一条消息里都出现才算。只能查当前工作区。',
    {
      'query': {'type': 'string', 'description': '关键词'},
    },
    ['query'],
  ),
  kind: ToolKind.read,
  run: (args) async {
    final query = AgentToolbox.argString(args, 'query').trim();
    if (query.length > kConvSearchMaxQueryChars) return ToolOutcome('错误：关键词太长（最多 $kConvSearchMaxQueryChars 字）。用几个短词', ok: false);
    final terms = [
      for (final t in query.toLowerCase().split(RegExp(r'\s+')))
        if (t.isNotEmpty) t,
    ];
    if (terms.isEmpty) return ToolOutcome('错误：缺少参数 query（要找的关键词）', ok: false);
    final here = core.dir.rootOf(run.conv).id;
    final convs = [...core.dir.top]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    final found = <String>[];
    var more = 0;
    for (final conv in convs.take(kConvSearchMaxScan)) {
      final hits = searchMessages(await _messagesOf(core, conv), terms);
      if (hits.isEmpty) continue;
      if (found.length >= kConvSearchMaxConversations) {
        more++;
        continue;
      }
      final title = conv.title.isEmpty ? '（没有标题）' : conv.title;
      found.add('${found.length + 1}. 《$title》 ${_stamp(conv.updatedAt)}${conv.id == here ? '（就是现在这段对话）' : ''}${conv.auto ? '（自动化任务）' : ''}\n${hits.map((h) => '   $h').join('\n')}');
    }
    if (found.isEmpty) return ToolOutcome('这个工作区的历史对话里没有提到“$query”的内容。');
    return ToolOutcome('在这个工作区的历史对话里找到 ${found.length} 段提到“$query”的：\n${found.join('\n')}${more > 0 ? '\n（还有 $more 段也提到了，没有列出；换更具体的词再查。）' : ''}');
  },
);
