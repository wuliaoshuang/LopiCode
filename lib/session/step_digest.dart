// 每一步的“结果摘要”：展开步骤清单时，每步下面不用点开就能看到的那一小段。纯计算：不读盘、不碰状态、不带界面。
//
// 规矩：
// - 每种工具一种写法（见 [stepDigest] 里的分支）；不认识的工具（含以后 MCP 接进来的）走通用写法：结果的第一行。
// - 只从“工具名 + 参数 + 结果文字”里读，结果是坏数据 / 空 / 超长都不抛异常。
// - 有长度上限：一行标题最多 [kDigestHeadMax] 字，下面最多 [kDigestLines] 行、每行最多 [kDigestLineMax] 字。
// - 失败 / 被拒绝的，不分工具，统一是“原因一行”。
import 'dart:convert';

import 'package:lopicode/agent/auto_compact.dart' show kUnknownResultNote;

/// 摘要标题最多多少字。
const int kDigestHeadMax = 80;

/// 摘要下面每行最多多少字。
const int kDigestLineMax = 120;

/// 摘要下面最多几行。
const int kDigestLines = 3;

/// 读文件的摘要带开头几行。
const int kDigestReadLines = 2;

/// 结果超过这么多字时，只看开头和结尾各这么多字来挑“开头几行 / 最后几行”（数行数仍然数全部）。
const int kDigestScanChars = 6000;

enum DigestTone { plain, bad, denied }

/// App 被关掉时没跑完的那一步的摘要。
const String kInterruptedDigest = '被中断，没有拿到结果';

/// 一步的结果摘要：[head] 一行（可能为空），[lines] 是原样的几行输出 / 内容（等宽显示）。
class StepDigest {
  const StepDigest(this.head, {this.lines = const [], this.tone = DigestTone.plain});
  final String head;
  final List<String> lines;
  final DigestTone tone;

  bool get isEmpty => head.isEmpty && lines.isEmpty;
}

String _clip(String s, int max) {
  final one = s.replaceAll(RegExp(r'[\r\n\t]+'), ' ').trim();
  if (one.length <= max) return one;
  // 不把一个字符（表情等占两个编码单位的）从中间切开。
  var cut = max - 1;
  if (cut > 0 && _isHighSurrogate(one.codeUnitAt(cut - 1))) cut--;
  return '${one.substring(0, cut)}…';
}

bool _isHighSurrogate(int unit) => unit >= 0xD800 && unit <= 0xDBFF;

/// 去掉终端的颜色 / 光标控制码，免得摘要里出现一串乱码。
final RegExp _ansi = RegExp('\u001b\\[[0-9;?]*[ -/]*[@-~]');

List<String> _nonEmptyLines(String text) => [
  for (final l in const LineSplitter().convert(text.replaceAll(_ansi, '')))
    if (l.trim().isNotEmpty) l.trimRight(),
];

/// 超长的只留开头和结尾，够挑几行用。
String _scanHead(String s) => s.length > kDigestScanChars ? s.substring(0, kDigestScanChars) : s;
String _scanTail(String s) => s.length > kDigestScanChars ? s.substring(s.length - kDigestScanChars) : s;

List<String> _firstLines(String text, int n) => [for (final l in _nonEmptyLines(_scanHead(text)).take(n)) _clip(l, kDigestLineMax)];

List<String> _lastLines(String text, int n) {
  final all = _nonEmptyLines(_scanTail(text));
  return [for (final l in all.skip(all.length > n ? all.length - n : 0)) _clip(l, kDigestLineMax)];
}

String _firstLine(String text) => _firstLines(text, 1).firstOrNull ?? '';

int _lineCount(String text) => text.isEmpty ? 0 : '\n'.allMatches(text).length + (text.endsWith('\n') ? 0 : 1);

Map<String, dynamic> _args(String raw) {
  try {
    final decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic>) return decoded;
  } on FormatException {
    // 参数不是合法 JSON：当没有参数
  }
  return const {};
}

StepDigest _head(String text, {DigestTone tone = DigestTone.plain, List<String> lines = const []}) => StepDigest(_clip(text, kDigestHeadMax), lines: lines.take(kDigestLines).toList(), tone: tone);

/// 失败 / 被拒绝：原因一行（去掉开头的“错误：”）。
StepDigest _reason(String result, DigestTone tone) {
  var line = _firstLine(result);
  for (final prefix in const ['错误：', '错误:']) {
    if (line.startsWith(prefix)) line = line.substring(prefix.length).trim();
  }
  return _head(line.isEmpty ? (tone == DigestTone.denied ? '没有执行' : '失败，没有给出原因') : line, tone: tone);
}

final RegExp _exitLine = RegExp(r'^退出码 (-?\d+)\s*$');

/// 命令的结果是“第一行状态 + 后面的输出”（见 agent_tools.dart 的 _run）。
StepDigest _command(String result, {required bool ok}) {
  final nl = result.indexOf('\n');
  final status = (nl < 0 ? result : result.substring(0, nl)).trim();
  final output = nl < 0 ? '' : result.substring(nl + 1);
  final none = output.trim().isEmpty || output.trim() == '（没有输出）';
  final tail = none ? const <String>[] : _lastLines(output, kDigestLines);
  final exit = _exitLine.firstMatch(status)?.group(1);
  if (exit != null) {
    return _head(none ? '退出码 $exit · 没有输出' : '退出码 $exit', tone: exit == '0' ? DigestTone.plain : DigestTone.bad, lines: tail);
  }
  // 不是“退出码 N”开头：被停止、超时、没执行，或者不是命令工具的标准格式——状态那行就是原因。
  if (!ok) {
    final reason = _reason(status.isEmpty ? result : status, DigestTone.bad);
    return StepDigest(reason.head, lines: tail, tone: DigestTone.bad);
  }
  return _head(status, lines: tail);
}

final RegExp _bgStarted = RegExp(r'^后台命令 #(\d+) 已启动');
final RegExp _bgEndedEarly = RegExp(r'^后台命令 #(\d+) 刚启动就结束了：(.*)$');

StepDigest _backgroundStart(String result, {required bool ok}) {
  final first = _firstLine(result);
  final started = _bgStarted.firstMatch(first);
  if (started != null) return _head('已在后台启动 · #${started.group(1)}');
  final early = _bgEndedEarly.firstMatch(first);
  if (early != null) {
    final nl = result.indexOf('\n');
    final output = nl < 0 ? '' : result.substring(nl + 1);
    final none = output.trim().isEmpty || output.trim() == '（没有输出）';
    return _head('刚启动就结束了：${early.group(2)}', tone: ok ? DigestTone.plain : DigestTone.bad, lines: none ? const [] : _lastLines(output, kDigestLines));
  }
  return ok ? _head(first) : _reason(result, DigestTone.bad);
}

/// 看后台输出的结果：`#3 在跑，已运行 12 秒` / `命令：…` / `日志：…` / `最后 N 行：` 或 `新输出：` / 输出。
StepDigest _backgroundRead(String result) {
  final lines = const LineSplitter().convert(result);
  final first = lines.isEmpty ? '' : lines.first.trim();
  final status = RegExp(r'^#\d+\s+(.*)$').firstMatch(first)?.group(1) ?? first;
  final mark = lines.indexWhere((l) => RegExp(r'^(最后 \d+ 行：|新输出：)').hasMatch(l));
  if (mark < 0) {
    final quiet = result.contains('没有新输出');
    return _head(quiet ? '$status · 没有新输出' : status);
  }
  final output = lines.skip(mark + 1).join('\n');
  final none = output.trim().isEmpty || output.trim() == '（没有输出）';
  return _head(none ? '$status · 没有输出' : status, lines: none ? const [] : _lastLines(output, kDigestLines));
}

final RegExp _readRange = RegExp(r'^（.* 第 (\d+)–(\d+) 行，全文共 (\d+) 行）\n');
final RegExp _readCut = RegExp(r'\n…（(?:文件|这一段)共 \d+ 字符，只显示前 \d+ 字符[^\n]*）\s*$');

/// 读文件：多少行 + 开头两行。
StepDigest _read(String result) {
  var text = result;
  String? range;
  final head = _readRange.firstMatch(text);
  if (head != null) {
    range = '第 ${head.group(1)}–${head.group(2)} 行（全文 ${head.group(3)} 行）';
    text = text.substring(head.end);
  }
  final cut = _readCut.firstMatch(text);
  if (cut != null) text = text.substring(0, cut.start);
  final n = _lineCount(text);
  final what = range ?? (text.isEmpty ? '空文件' : '$n 行');
  return _head(cut == null ? what : '$what · 太长，只读了前面一段', lines: _firstLines(text, kDigestReadLines));
}

StepDigest _list(String result) {
  final t = result.trim();
  if (t.isEmpty || t == '（空目录）') return _head('空目录');
  return _head('${_nonEmptyLines(result).length} 项');
}

/// 搜索结果的样子：`1. 标题` / `   网址` / `   摘要`，一条一段（见 web_search.dart）。
StepDigest _search(String result) {
  final titles = [
    for (final l in const LineSplitter().convert(result))
      if (RegExp(r'^\d+\.\s').hasMatch(l)) l.replaceFirst(RegExp(r'^\d+\.\s+'), '').trim(),
  ];
  if (titles.isEmpty) return _head(_firstLine(result).isEmpty ? '没有搜到结果' : _firstLine(result));
  return _head('${titles.length} 条结果', lines: [_clip(titles.first, kDigestLineMax)]);
}

StepDigest _ask(String result) {
  const prefix = '用户的回答：';
  final answer = result.startsWith(prefix) ? result.substring(prefix.length) : result;
  return _head(answer.trim().isEmpty ? '你没有填回答' : '你的回答：${answer.trim()}');
}

/// 子代理：`子代理“名字”的汇报：` 下面第一句有内容的话。
StepDigest _agent(String result, {required bool ok}) {
  final nl = result.indexOf('\n');
  final first = (nl < 0 ? result : result.substring(0, nl)).trim();
  final body = first.startsWith('子代理') && first.endsWith('汇报：') && nl >= 0 ? result.substring(nl + 1) : result;
  final line = _firstLine(body);
  return _head(line.isEmpty ? '子代理没有汇报内容' : line, tone: ok ? DigestTone.plain : DigestTone.bad);
}

final RegExp _todoLine = RegExp(r'待办清单已更新：(\d+) 项，已完成 (\d+) 项(?:，正在做：(.*?))?。?\s*$');

StepDigest _todos(String result) {
  final m = _todoLine.firstMatch(_firstLine(result));
  if (m == null) return _head(_firstLine(result));
  final doing = m.group(3);
  return _head('完成 ${m.group(2)} / ${m.group(1)} 项${doing == null || doing.isEmpty ? '' : ' · 正在做：$doing'}');
}

int _countTyped(Object? node, {int depth = 0}) {
  if (depth > 40) return 0; // 坏数据套得太深：不再往下数
  if (node is List) return node.fold<int>(0, (n, e) => n + _countTyped(e, depth: depth + 1));
  if (node is! Map) return 0;
  var n = node['type'] is String ? 1 : 0;
  for (final e in node.entries) {
    if (e.key == 'logic') continue; // 积木逻辑不算页面元素
    n += _countTyped(e.value, depth: depth + 1);
  }
  return n;
}

/// 低代码页面 / 后端积木的“更新”：这次写进去多少 + 有没有错误 / 提醒。
/// （结果里没有“和上一版比改了几处”的信息，所以写的是这次写入的规模。）
StepDigest _blocksUpdate(String name, Map<String, dynamic> args, String result) {
  final errors = RegExp(r'有 (\d+) 个错误').firstMatch(result)?.group(1);
  final warned = result.contains('\n提醒（');
  final String size;
  if (name == 'lowcode_update_page') {
    Object? page = args['page'];
    if (page is String) {
      try {
        page = jsonDecode(page);
      } on FormatException {
        page = null;
      }
    }
    final n = _countTyped(page);
    size = n > 0 ? '页面已更新 · 写入 $n 个元素' : '页面已更新';
  } else {
    Object? doc = args['backend'];
    if (doc is String) {
      try {
        doc = jsonDecode(doc);
      } on FormatException {
        doc = null;
      }
    }
    final routes = doc is Map ? doc['routes'] : null;
    size = routes is List ? '已保存 · 写入 ${routes.length} 个接口' : '已保存';
  }
  if (errors != null) return _head('$size · 积木逻辑有 $errors 个错误，logic.js 没更新', tone: DigestTone.bad);
  return _head(warned ? '$size · 有提醒' : size);
}

/// 一步的结果摘要。还在执行（[result] 为 null）返回 null。
/// [hasChange]：这一步带改动对比（行尾已经有 +N −M），写文件 / 改文件就不再重复说一遍。
StepDigest? stepDigest(String name, String rawArgs, String? result, {bool ok = true, bool denied = false, bool hasChange = false}) {
  if (result == null) return null;
  try {
    if (denied) return _reason(result, DigestTone.denied);
    // App 被关掉时没跑完的那一步：一句短的就够（详细的说明在“上一轮被中断”那张卡和点开的详情里，不在这里再念一遍）。
    if (result == kUnknownResultNote) return const StepDigest(kInterruptedDigest, tone: DigestTone.bad);
    // 命令失败也要看得到退出码和最后几行，不只是一句原因。
    if (name == 'run_command') return _command(result, ok: ok);
    if (name == 'start_background_command') return _backgroundStart(result, ok: ok);
    if (name == 'spawn_agent' && !result.startsWith('错误')) return _agent(result, ok: ok);
    if (!ok) return _reason(result, DigestTone.bad);
    if (result.trim().isEmpty) return const StepDigest('没有返回内容');
    final StepDigest digest = switch (name) {
      'read_background_output' => _backgroundRead(result),
      'stop_background_command' => _head(_firstLine(result), lines: result.contains('最后几行输出：') ? _lastLines(result.substring(result.indexOf('最后几行输出：') + 7), kDigestLines) : const []),
      'list_background_commands' => () {
        final n = const LineSplitter().convert(result).where((l) => RegExp(r'^#\d+ ').hasMatch(l)).length;
        return _head(n == 0 ? _firstLine(result) : '$n 个后台命令');
      }(),
      'read_file' || 'lowcode_get_page' || 'read_skill' => _read(result),
      'list_files' => _list(result),
      'write_file' || 'edit_file' => hasChange ? const StepDigest('') : _head(_firstLine(result)),
      'delete_file' => _head(_firstLine(result)),
      'web_search' => _search(result),
      'ask_user' => _ask(result),
      'update_todos' => _todos(result),
      'lowcode_update_page' || 'backend_update_blocks' => _blocksUpdate(name, _args(rawArgs), result),
      _ => _head(_firstLine(result)),
    };
    return digest.isEmpty ? null : digest;
  } on Object {
    // 摘要只是锦上添花：任何没想到的坏数据都不许让聊天页崩，退回“结果第一行”。
    final nl = result.indexOf('\n');
    final first = nl < 0 ? result : result.substring(0, nl);
    return StepDigest(first.length > kDigestHeadMax ? first.substring(0, kDigestHeadMax) : first, tone: ok && !denied ? DigestTone.plain : DigestTone.bad);
  }
}

/// 步骤行尾“用了多久”的写法。进行中按整秒：`12 秒`、`1 分 5 秒`。
String formatStepSeconds(int seconds) => seconds < 60 ? '$seconds 秒' : '${seconds ~/ 60} 分 ${seconds % 60} 秒';

/// 做完以后的写法：不到 10 秒带一位小数（`0.3 秒`、`2.4 秒`），再长按整秒。
String formatStepSpan(int ms) {
  if (ms < 0) return '0 秒';
  if (ms < 10000) {
    final tenths = (ms / 100).round();
    return tenths >= 100 ? '10 秒' : '${tenths ~/ 10}.${tenths % 10} 秒';
  }
  return formatStepSeconds((ms / 1000).round());
}

/// 做完的步骤，用时不到这么久就不在那一行显示（点开详情里照样有）：免得每个读文件后面都挂一个“0.1 秒”。
const int kStepShowSpanMs = 1000;
