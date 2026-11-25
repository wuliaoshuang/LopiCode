// 压缩摘要的固定栏目：给模型的那句指令、收到摘要后的“补齐栏目”。纯计算，不发请求、不碰磁盘。
//
// 规矩：
// - 栏目是固定的七个（见 [kCompactSections]），顺序不变。压缩后 Agent 接着干活最容易忘的就是文件路径、命令、还剩什么，
// 所以这几样单独成栏。
// - 模型听不听话不靠提示词保证：摘要回来以后由代码检查，缺的栏目补上——
// “关键文件”“跑过的命令”这两栏能从对话记录里的工具调用直接抄出来，就抄；别的栏写明“摘要里没有写这一栏”。
// - 压缩请求里模型反而去调工具：那段话多半是“我先看看文件”，不能当摘要存，按失败处理（见 auto_compact.dart）。
import 'dart:convert';

/// 一个栏目：标题 + 给模型的一句说明。
class CompactSection {
  const CompactSection(this.title, this.hint);
  final String title;
  final String hint;
}

const String kSectionFiles = '关键文件';
const String kSectionCommands = '跑过的命令和结果';

/// 摘要的固定栏目（顺序就是输出顺序）。
const List<CompactSection> kCompactSections = [
  CompactSection('用户要做什么', '用户的目标和提过的全部要求，尽量保留原话里的关键字眼'),
  CompactSection('已经做了什么', '按先后列出已经完成的事，各一句话'),
  CompactSection(kSectionFiles, '改过、新建、删过、读过的文件，写完整的相对路径，各带一句“动了什么 / 里面有什么要紧的”'),
  CompactSection(kSectionCommands, '执行过的要紧命令原样写出，各带一句结果（成功 / 报了什么错）'),
  CompactSection('定下来的决定和约束', '和用户商量定的做法、用户不许做的事、要遵守的约定'),
  CompactSection('还剩什么没做', '没做完的事，按该做的先后列出；都做完了就写“没有”'),
  CompactSection('当前卡在哪', '此刻正在做哪一步、遇到的问题、下一步打算怎么做；没有卡住就写“没有”'),
];

/// 栏目标题在摘要里的写法（独占一行）。
String sectionHeading(String title) => '## $title';

/// 压缩指令的开头（测试和假模型据此认出“这是压缩请求”）。
const String kCompactAskHead = '（压缩对话）';

/// 追加在对话末尾的压缩指令（同前缀方式）。[transcript] 为 true 时是给“纯文字记录”那种老办法用的说法。
String compactInstruction({bool transcript = false}) {
  final b = StringBuffer()
    ..writeln('$kCompactAskHead${transcript ? '请把上面这段对话记录' : '先不要继续干活，也不要调用任何工具。请把到目前为止的整段对话'}写成一份摘要，之后会用它顶替较早的记录接着干活。')
    ..writeln('只输出摘要本身，用简体中文，严格按下面的栏目和顺序写，每个栏目的标题独占一行、原样照抄（含前面的“##”），没有内容的栏目写“没有”：');
  for (final s in kCompactSections) {
    b.writeln('${sectionHeading(s.title)}\n（${s.hint}）');
  }
  return b.toString().trimRight();
}

/// 摘要里有没有某个栏目（标题独占一行；前面的 # 个数、标题后的冒号不计较）。
bool hasSection(String summary, String title) => RegExp('^\\s*#{1,6}\\s*${RegExp.escape(title)}\\s*[:：]?\\s*\$', multiLine: true).hasMatch(summary);

/// 摘要里缺的栏目。
List<String> missingSections(String summary) => [
  for (final s in kCompactSections)
    if (!hasSection(summary, s.title)) s.title,
];

const int kSummaryMaxFiles = 30;
const int kSummaryMaxCommands = 15;

String _short(String s, int max) => s.length > max ? '${s.substring(0, max)}…' : s;

Map<String, dynamic>? _argsOf(Object? raw) {
  if (raw is Map<String, dynamic>) return raw;
  if (raw is! String || raw.trim().isEmpty) return null;
  try {
    final v = jsonDecode(raw);
    return v is Map<String, dynamic> ? v : null;
  } on FormatException {
    return null;
  }
}

/// 从对话记录的工具调用里抄出“动过哪些文件”“跑过哪些命令”（去重，保持先后）。
({List<String> files, List<String> commands}) touchedByTools(List<Map<String, dynamic>> messages) {
  final files = <String, String>{}; // 路径 → 动作
  final commands = <String>[];
  for (final m in messages) {
    final calls = m['tool_calls'];
    for (final c in calls is List ? calls : const []) {
      final fn = c is Map ? c['function'] : null;
      if (fn is! Map) continue;
      final name = '${fn['name']}';
      final args = _argsOf(fn['arguments']);
      if (args == null) continue;
      final path = args['path'];
      final command = args['command'];
      if (command is String && command.trim().isNotEmpty && name.contains('command')) {
        final line = _short(command.trim().replaceAll('\n', ' ⏎ '), 200);
        if (!commands.contains(line)) commands.add(line);
      } else if (path is String && path.trim().isNotEmpty) {
        final verb = switch (name) {
          'write_file' => '写入',
          'edit_file' => '修改',
          'delete_file' => '删除',
          'read_file' => '读过',
          _ => null,
        };
        if (verb == null) continue;
        final old = files[path.trim()];
        // 读过又改过的，记成改过。
        if (old == null || old == '读过') files[path.trim()] = verb;
      }
    }
  }
  return (files: [for (final e in files.entries) '${e.key}（${e.value}）'], commands: commands);
}

/// 把摘要补成“栏目齐全”：缺的栏目接在后面。[older] 是被摘要顶替的那段记录（用来抄文件和命令）。
String completeSummary(String summary, List<Map<String, dynamic>> older) {
  final missing = missingSections(summary);
  if (missing.isEmpty) return summary;
  final touched = touchedByTools(older);
  final out = StringBuffer(summary.trimRight());
  String list(List<String> all, int max) => [for (final x in all.take(max)) '- $x', if (all.length > max) '- ……（还有 ${all.length - max} 项没列出）'].join('\n');
  for (final title in missing) {
    out.write('\n\n${sectionHeading(title)}\n');
    if (title == kSectionFiles && touched.files.isNotEmpty) {
      out.write('（模型的摘要里没有写这一栏，下面是从工具调用记录里抄出来的）\n${list(touched.files, kSummaryMaxFiles)}');
    } else if (title == kSectionCommands && touched.commands.isNotEmpty) {
      out.write('（模型的摘要里没有写这一栏，下面是从工具调用记录里抄出来的，结果没有记）\n${list(touched.commands, kSummaryMaxCommands)}');
    } else {
      out.write('（模型的摘要里没有写这一栏）');
    }
  }
  return out.toString();
}
