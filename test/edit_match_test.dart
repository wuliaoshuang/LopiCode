// edit_file 的匹配与替换（纯逻辑）：三级匹配各自命中、多处、找不到、空原文、换行符、文件末尾、中文、上限。
import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/agent/edit_match.dart';

EditOk ok(EditResult r) {
  expect(r, isA<EditOk>(), reason: r is EditFail ? r.message : '');
  return r as EditOk;
}

EditFail fail(EditResult r) {
  expect(r, isA<EditFail>());
  return r as EditFail;
}

void main() {
  group('第 1 级：精确匹配', () {
    test('一行里的一小段：只换这一段，其余一字不动', () {
      final r = ok(applyEdit('int a = 1;\nint b = 2;\n', 'b = 2', 'b = 3'));
      expect(r.content, 'int a = 1;\nint b = 3;\n');
      expect(r.level, MatchLevel.exact);
      expect(r.ranges, [(2, 2)]);
      expect(r.where, '第 2 行');
    });

    test('多行原文换成多行新文：报出改动落在新文件的哪几行', () {
      final r = ok(applyEdit('a\nb\nc\nd\n', 'b\nc\n', 'B\nB2\nC\n'));
      expect(r.content, 'a\nB\nB2\nC\nd\n');
      expect(r.ranges, [(2, 4)]);
      expect(r.where, '第 2–4 行');
    });

    test('新文是空的：删掉这一段', () {
      final r = ok(applyEdit('a\nb\nc\n', 'b\n', ''));
      expect(r.content, 'a\nc\n');
      expect(r.level, MatchLevel.exact);
    });

    test('中文和表情照样能找到、能换', () {
      final r = ok(applyEdit('标题：你好，世界 🌍\n正文：今天天气不错\n', '今天天气不错', '今天下雨了 ☔'));
      expect(r.content, '标题：你好，世界 🌍\n正文：今天下雨了 ☔\n');
    });

    test('出现多处、没要求全部替换：不改，说清有几处、在哪几行', () {
      final f = fail(applyEdit('x = 1\ny = 2\nx = 1\nz = 3\nx = 1\n', 'x = 1', 'x = 9'));
      expect(f.kind, EditFailKind.ambiguous);
      expect(f.count, 3);
      expect(f.message, contains('3 处'));
      expect(f.message, contains('第 1 行、第 3 行、第 5 行'));
      expect(f.message, contains('replace_all'));
      expect(f.message, contains('没有改动'));
    });

    test('出现多处、要求全部替换：全换，逐处报行号', () {
      final r = ok(applyEdit('x = 1\ny = 2\nx = 1\n', 'x = 1', 'x = 9\nw = 0', replaceAll: true));
      expect(r.content, 'x = 9\nw = 0\ny = 2\nx = 9\nw = 0\n');
      expect(r.count, 2);
      expect(r.ranges, [(1, 2), (4, 5)]);
    });

    test('处数很多：只列前 $kEditListedPlaces 处', () {
      final r = ok(applyEdit(List.filled(8, 'a').join('\n'), 'a', 'b', replaceAll: true));
      expect(r.count, 8);
      expect(r.where, endsWith('等 8 处'));
      expect('第'.allMatches(r.where).length, kEditListedPlaces);
    });
  });

  group('换行符与文件末尾', () {
    test('CRLF 文件：原文用 LF 给也算精确匹配；写回去仍然全是 CRLF', () {
      final r = ok(applyEdit('a\r\nb\r\nc\r\n', 'a\nb\n', 'A\nB\nB2\n'));
      expect(r.level, MatchLevel.exact);
      expect(r.content, 'A\r\nB\r\nB2\r\nc\r\n');
      expect(r.content.replaceAll('\r\n', ''), isNot(contains('\n')), reason: '不能混进单独的 LF');
    });

    test('LF 文件：原文、新文带 CRLF 给，写回去仍然是 LF', () {
      final r = ok(applyEdit('a\nb\nc\n', 'a\r\nb\r\n', 'A\r\nB\r\n'));
      expect(r.content, 'A\nB\nc\n');
    });

    test('CRLF 文件按行匹配（缩进对不上）：新行也用 CRLF', () {
      final r = ok(applyEdit('if (x) {\r\n    go();\r\n}\r\n', 'go();  ', 'stop();\nwait();'));
      expect(r.level, MatchLevel.trimmed);
      expect(r.content, 'if (x) {\r\n    stop();\r\n    wait();\r\n}\r\n');
    });

    test('文件末尾没有换行：改最后一行以后还是没有', () {
      expect(ok(applyEdit('a\nb', 'b', 'c')).content, 'a\nc');
      expect(ok(applyEdit('a\nb', 'b', 'c\n')).content, 'a\nc', reason: '新文多带了一个换行也不给文件加上');
      expect(ok(applyEdit('a\nb', 'b\n', 'c\n')).content, 'a\nc', reason: '原文多带了换行：按行匹配能找到');
    });

    test('文件末尾有换行：删掉最后一行、改最后一行以后还有', () {
      expect(ok(applyEdit('a\nb\n', 'b', 'c')).content, 'a\nc\n');
      expect(ok(applyEdit('a\nb\n', '\nb\n', '')).content, 'a\n');
      expect(ok(applyEdit('a\nb', 'a\n', '')).content, 'b');
    });
  });

  group('第 2 级：忽略每行首尾空白', () {
    const src = 'class A {\n    void run() {\n        print("hi");   \n    }\n}\n';

    test('缩进、行尾空格对不上也能找到；新文按文件里真实的缩进对齐', () {
      final r = ok(applyEdit(src, 'void run() {\n  print("hi");\n}', 'void run() {\n  print("hello");\n  done();\n}'));
      expect(r.level, MatchLevel.trimmed);
      expect(r.content, 'class A {\n    void run() {\n      print("hello");\n      done();\n    }\n}\n');
      expect(r.ranges, [(2, 5)]);
    });

    test('模型给的原文完全没有缩进：新文每一行都补上文件里的缩进', () {
      final r = ok(applyEdit('  a:\n    b: 1\n    c: 2\n', 'b: 1\nc: 2', 'b: 1\nc: 3\nd: 4'));
      expect(r.level, MatchLevel.trimmed);
      expect(r.content, '  a:\n    b: 1\n    c: 3\n    d: 4\n');
    });

    test('多处：不改；全部替换：都换', () {
      const twice = '  go();\nx\n    go();\n';
      final f = fail(applyEdit(twice, 'go();  ', 'stop();'));
      expect(f.kind, EditFailKind.ambiguous);
      expect(f.count, 2);
      expect(f.message, contains('忽略行首尾空白'));
      final r = ok(applyEdit(twice, 'go();  ', 'stop();', replaceAll: true));
      expect(r.level, MatchLevel.trimmed);
      expect(r.content, '  stop();\nx\n    stop();\n');
      expect(r.count, 2);
    });

    test('新文是空的：整段连同换行一起删掉', () {
      final r = ok(applyEdit('a\n   b\nc\n', 'b  ', ''));
      expect(r.level, MatchLevel.trimmed);
      expect(r.content, 'a\nc\n');
    });
  });

  group('第 3 级：首行、末行当锚点', () {
    const src = 'void main() {\n  final a = 1;\n  final b = 2;\n  final c = a + b;\n  print(c);\n}\n\nvoid other() {\n  print(0);\n}\n';

    test('中间行有出入（相似度够）：整段换掉', () {
      // 中间第二行模型记成了 b = 3
      final r = ok(applyEdit(src, 'void main() {\n  final a = 1;\n  final b = 3;\n  final c = a + b;\n  print(c);\n}', 'void main() {\n  print(3);\n}'));
      expect(r.level, MatchLevel.anchors);
      expect(r.similarity, greaterThanOrEqualTo(kAnchorSimilarity));
      expect(r.content, 'void main() {\n  print(3);\n}\n\nvoid other() {\n  print(0);\n}\n');
      expect(r.ranges, [(1, 3)]);
    });

    test('中间少记了一行（行数差在允许范围内）也能对上', () {
      final r = ok(applyEdit(src, 'void main() {\n  final a = 1;\n  final c = a + b;\n  print(c);\n}', 'void main() {}'));
      expect(r.level, MatchLevel.anchors);
      expect(r.content, startsWith('void main() {}\n\nvoid other()'));
    });

    test('中间行差太多（低于门槛）：不改', () {
      final f = fail(applyEdit(src, 'void main() {\n  completely different line here\n  and another unrelated one\n  nothing in common at all\n  zzz\n}', 'x'));
      expect(f.kind, EditFailKind.notFound);
    });

    test('原文不到 $kAnchorMinLines 行不走锚点', () {
      final f = fail(applyEdit('a {\n  x\n}\n', 'a {\n}', 'b'));
      expect(f.kind, EditFailKind.notFound);
    });

    test('锚点对上两段：不改，也不支持全部替换', () {
      const two = 'f() {\n  aaa1\n  bbb\n}\nf() {\n  aaa2\n  bbb\n}\n';
      for (final all in [false, true]) {
        final f = fail(applyEdit(two, 'f() {\n  aaa3\n  bbb\n}', 'g()', replaceAll: all));
        expect(f.kind, EditFailKind.ambiguous);
        expect(f.count, 2);
        expect(f.message, contains('锚点'));
      }
    });

    test('相似度的算法：一样是 1，完全不同接近 0，改一个字在中间', () {
      expect(textSimilarity('abc', 'abc'), 1);
      expect(textSimilarity('', 'abc'), 0);
      expect(textSimilarity('abcd', 'abxd'), closeTo(0.75, 1e-9));
      expect(textSimilarity('aaaa', 'zzzz'), 0);
    });
  });

  group('找不到 / 参数不对', () {
    test('原文为空或只有空白：不改，提示用 write_file', () {
      for (final old in ['', '   ', '\n\n']) {
        final f = fail(applyEdit('abc\n', old, 'x'));
        expect(f.kind, EditFailKind.emptyOld);
        expect(f.message, contains('write_file'));
      }
    });

    test('新旧一样：不改', () {
      expect(fail(applyEdit('abc\n', 'abc', 'abc')).kind, EditFailKind.same);
      expect(fail(applyEdit('a\r\nb\r\n', 'a\nb', 'a\r\nb')).kind, EditFailKind.same);
    });

    test('找不到，但第一行在文件里有：说出在第几行、从哪一行开始对不上，并贴出那一段', () {
      final f = fail(applyEdit('one\ntwo\nthree\nfour\n', 'two\nthree\nFIVE', 'x'));
      expect(f.kind, EditFailKind.notFound);
      expect(f.message, contains('没有找到'));
      expect(f.message, contains('文件第 2 行能找到'));
      expect(f.message, contains('old_text 的第 3 行起和文件第 4 行对不上'));
      expect(f.message, contains('2| two\n3| three\n4| four'));
      expect(f.message, contains('没有改动'));
    });

    test('找不到，有一行很像：给出最接近的位置', () {
      final f = fail(applyEdit('alpha\nfinal total = price * count;\nomega\n', 'final total = price * amount;', 'x'));
      expect(f.kind, EditFailKind.notFound);
      expect(f.message, contains('最接近的是文件第 2 行附近'));
      expect(f.message, contains('2| final total = price * count;'));
    });

    test('找不到，也没有相近的：直说', () {
      final f = fail(applyEdit('alpha\nbeta\n', 'zzzzzzzzzzzzzzzzzzzzzzzz', 'x'));
      expect(f.message, contains('没有和它相近的内容'));
    });

    test('文件是空的：找不到', () {
      expect(fail(applyEdit('', 'a', 'b')).kind, EditFailKind.notFound);
    });

    test('文件超过上限（$kEditMaxChars 字符）：不改', () {
      final big = 'a' * (kEditMaxChars + 1);
      final f = fail(applyEdit(big, 'a', 'b'));
      expect(f.kind, EditFailKind.tooLarge);
      expect(f.message, contains('$kEditMaxChars'));
    });

    test('刚好在上限内的大文件：能改，而且不慢', () {
      final lines = [for (var i = 0; i < 30000; i++) 'line number $i of the file'];
      final src = '${lines.join('\n')}\n';
      expect(src.length, lessThanOrEqualTo(kEditMaxChars));
      final watch = Stopwatch()..start();
      final r = ok(applyEdit(src, 'line number 29999 of the file', 'the end'));
      expect(r.content, endsWith('line number 29998 of the file\nthe end\n'));
      expect(r.ranges, [(30000, 30000)]);
      final f = fail(applyEdit(src, 'no such thing\nanywhere', 'x'));
      expect(f.kind, EditFailKind.notFound);
      expect(watch.elapsed, lessThan(const Duration(seconds: 20)));
    });
  });
}
