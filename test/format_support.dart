// 格式化器测试共用的小工具（不是测试文件本身）。
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/format/format.dart';

/// 格式化成功，并且守住铁律 1（幂等）、铁律 2（记号序列不变）和“末尾恰好一个换行”。返回排好的文本。
String formatOk(String source, String language, {int indent = 2}) {
  final r = formatCode(source, language, indent: indent);
  expect(r.problem, isNull, reason: '不该失败：\n$source');
  expect(r.changed, r.text != source);
  final again = formatCode(r.text, language, indent: indent);
  expect(again.problem, isNull, reason: '排好的结果自己应该还能排');
  expect(again.text, r.text, reason: '不幂等：再排一次结果变了');
  expect(again.changed, isFalse);
  final before = codeTokens(source, language);
  expect(before, isNotNull);
  expect(codeTokens(r.text, language), before, reason: '记号序列变了');
  expect(r.text.endsWith('\n') || r.text.endsWith('\r\n'), isTrue, reason: '末尾要有换行');
  expect(r.text.endsWith('\n\n') || r.text.endsWith('\n\r\n'), isFalse, reason: '末尾只能有一个换行');
  return r.text;
}

/// 没法格式化：原样返回，并给出原因（[hint] 是原因里应该出现的字样，比如“第 3 行”）。
String formatFails(String source, String language, {Pattern? hint}) {
  final r = formatCode(source, language);
  expect(r.problem, isNotNull, reason: '应该放弃格式化：\n$source');
  expect(r.text, source, reason: '失败时必须原样返回');
  expect(r.changed, isFalse);
  if (hint != null) expect(r.problem, contains(hint));
  return r.problem!;
}

/// 这些输入一个都不许抛异常（铁律 4），而且不管成不成功都要守住“失败就原样返回”。
void neverThrows(String language, List<String> extra) {
  final junk = String.fromCharCodes([for (var i = 0; i < 400; i++) (i * 7919 + 13) % 0x2FF]);
  final inputs = <String>[
    '',
    ' ',
    '\n\n\t  \r\n',
    '\uFEFF',
    '\u0000\u0001\u0002binary\u0000',
    junk,
    'x' * 200000,
    '{' * 5000,
    '[' * 5000 + ']' * 5000,
    '<div>' * 3000,
    '`\${' * 3000,
    '(' * 3000,
    '"',
    "'",
    '/*',
    '<!--',
    '`',
    '</',
    '<',
    '\\',
    ...extra,
  ];
  for (final input in inputs) {
    final FormatResult r;
    try {
      r = formatCode(input, language);
    } on Object catch (e) {
      fail('抛了异常 $e，输入开头：${input.length > 40 ? input.substring(0, 40) : input}');
    }
    if (r.problem != null) {
      expect(r.text, input);
      expect(r.changed, isFalse);
    } else if (r.changed) {
      expect(formatCode(r.text, language).text, r.text);
    }
  }
}

final String? _node = () {
  for (final dir in ['/usr/bin', '/usr/local/bin', ...?Platform.environment['PATH']?.split(':')]) {
    final f = File('$dir/node');
    if (f.existsSync()) return f.path;
  }
  return null;
}();

bool get hasNode => _node != null;

/// 用 `node --check` 看一段 JS 语法对不对。找不到 node 返回 null（调用方据此跳过）。
bool? nodeSyntaxOk(String js, {bool module = false}) {
  final node = _node;
  if (node == null) return null;
  final dir = Directory.systemTemp.createTempSync('lopi_fmt_');
  try {
    final file = File('${dir.path}/check.${module ? 'mjs' : 'cjs'}')..writeAsStringSync(js);
    return Process.runSync(node, ['--check', file.path]).exitCode == 0;
  } finally {
    dir.deleteSync(recursive: true);
  }
}

/// 把一段“已经排好”的代码按行弄乱：每行缩进随机、行尾加空白、空行变多。
/// 只动行首行尾，所以要求样本里没有“跨行且内容不能动”的东西（模板字符串、<pre>）。
String scrambleLines(String formatted, Random rnd) {
  final out = StringBuffer();
  for (final line in formatted.split('\n')) {
    if (line.trim().isEmpty) {
      out.write('\n' * rnd.nextInt(3));
      out.write('${' ' * rnd.nextInt(4)}\n');
      continue;
    }
    final lead = rnd.nextBool() ? ' ' * rnd.nextInt(9) : '\t' * rnd.nextInt(3);
    final tail = rnd.nextInt(3) == 0 ? ' ' * rnd.nextInt(4) : '';
    out.write('$lead${line.trimLeft()}$tail\n');
  }
  return out.toString();
}
