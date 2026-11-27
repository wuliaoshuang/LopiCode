/// 库的文字写坏了，坏在第几行（“改库的文字”那一页用，见 lib/backend/lib_service_fork.dart）。
///
/// 读库的那一套（lc_text.dart、lib_model.dart）只管读，不记行号；这里另外扫一遍文字，只回答“哪一行”：
/// - 模块文件：括号不配对、文字的引号没收尾——说得出行；括号都配对，就把模块里的声明一句一句单独读，哪一句读不了说那一句从第几行开始。
/// - JSON 文件：说出解析停在第几行。
/// 找不出行就返回 null，调用的人照旧只说原因。纯函数，不碰磁盘。
library;

import 'dart:convert';

import 'package:lopicode/lang/lc_text.dart';

/// 第 [offset] 个字在第几行（从 1 数）。
int lcLineOf(String src, int offset) {
  var line = 1;
  final end = offset.clamp(0, src.length);
  for (var i = 0; i < end; i++) {
    if (src.codeUnitAt(i) == 0x0A) line++;
  }
  return line;
}

/// JSON 写坏了：一句带行号的话；没坏返回 null。
String? jsonLocateProblem(String src) {
  try {
    jsonDecode(src);
    return null;
  } on FormatException catch (e) {
    final at = e.offset;
    return at == null ? '不是合法的 JSON' : '第 ${lcLineOf(src, at)} 行附近不是合法的 JSON（常见的是少了逗号、引号，或者多了一个逗号）';
  }
}

/// 模块文件写坏了：一句带行号的话；找不出毛病返回 null。
String? lcLocateProblem(String src) {
  const quote = 0x22, back = 0x5C, semi = 0x3B, open = 0x28, close = 0x29, nl = 0x0A;
  var line = 1;
  final opened = <int>[]; // 还没收尾的左括号各在第几行
  final spans = <({int from, int to, int line})>[]; // 模块里一句一句的声明
  var from = -1, fromLine = 0;
  for (var i = 0; i < src.length; i++) {
    final ch = src.codeUnitAt(i);
    if (ch == nl) {
      line++;
    } else if (ch == semi) {
      while (i + 1 < src.length && src.codeUnitAt(i + 1) != nl) {
        i++;
      }
    } else if (ch == quote) {
      final startLine = line;
      var done = false;
      for (i++; i < src.length; i++) {
        final c = src.codeUnitAt(i);
        if (c == back) {
          i++;
        } else if (c == nl) {
          line++;
        } else if (c == quote) {
          done = true;
          break;
        }
      }
      if (!done) return '第 $startLine 行：文字的双引号没有收尾';
    } else if (ch == open) {
      opened.add(line);
      if (opened.length == 2) {
        from = i;
        fromLine = line;
      }
    } else if (ch == close) {
      if (opened.isEmpty) return '第 $line 行：多了一个右括号';
      opened.removeLast();
      if (opened.length == 1 && from >= 0) {
        spans.add((from: from, to: i + 1, line: fromLine));
        from = -1;
      }
    }
  }
  if (opened.isNotEmpty) return '第 ${opened.last} 行开的括号没有收尾（少了右括号）';

  // 括号都配对：一句一句单独读。“变体”的声明别的句子读的时候要用到，每次都带上。
  final texts = [for (final s in spans) src.substring(s.from, s.to)];
  final variants = [
    for (final t in texts)
      if (t.startsWith('(变体') || t.startsWith('(公开 (变体')) t,
  ].join('\n');
  for (var i = 0; i < spans.length; i++) {
    final t = texts[i];
    final alone = t.startsWith('(变体') || t.startsWith('(公开 (变体');
    final read = lcTryProgram('(模块 试\n${alone ? '' : variants}\n$t)');
    if (read.problem != null) return '第 ${spans[i].line} 行开始的这一句：${read.problem}';
  }
  return null;
}

/// 一条问题里用「」括着的名字，在文字里头一次出现在第几行；找不到返回 null。
/// 读库查出来的问题（类型对不上、积木对不上函数……）只带名字不带行，用这个补一句“在第几行附近”。
int? lcLineOfNamed(String src, String problem) {
  for (final m in RegExp('「([^」]{1,64})」').allMatches(problem)) {
    final name = m.group(1)!;
    for (final probe in ['(函数 $name ', '(要等函数 $name ', '(记录 $name ', '(类 $name ', '"id": "$name"', '"id":"$name"', '"of": "$name"', name]) {
      final at = src.indexOf(probe);
      if (at >= 0) return lcLineOf(src, at);
    }
  }
  return null;
}
