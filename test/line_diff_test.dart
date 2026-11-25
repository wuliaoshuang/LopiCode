// 按行对比（纯逻辑）：增删统计、只留改动附近、各上限、存盘格式和坏数据。
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/agent/line_diff.dart';

FileChange diff(String? a, String? b, {ChangeKind? kind}) =>
    diffFileChange('lib/a.dart', kind: kind ?? (a == null ? ChangeKind.created : (b == null ? ChangeKind.deleted : ChangeKind.modified)), before: a, after: b);

String flat(FileChange c) => c.hunks.expand((h) => h.lines).join('\n');

void main() {
  test('改一行：一删一增，前后各带 $kDiffContext 行不变的行，行号对得上', () {
    final a = [for (var i = 1; i <= 20; i++) 'line $i'].join('\n');
    final b = a.replaceFirst('line 10', 'LINE TEN');
    final c = diff('$a\n', '$b\n');
    expect((c.added, c.removed), (1, 1));
    expect(c.stat, '+1 −1');
    expect(c.hunks, hasLength(1));
    final h = c.hunks.single;
    expect((h.oldStart, h.newStart), (7, 7));
    expect(h.lines, [' line 7', ' line 8', ' line 9', '-line 10', '+LINE TEN', ' line 11', ' line 12', ' line 13']);
    final rows = h.rows;
    expect((rows[3].op, rows[3].oldNo, rows[3].newNo), (DiffOp.del, 10, null));
    expect((rows[4].op, rows[4].oldNo, rows[4].newNo), (DiffOp.add, null, 10));
    expect((rows.last.oldNo, rows.last.newNo), (13, 13));
    expect(c.note, isNull);
  });

  test('两处改动隔得远：分成两段，中间的不变行不存', () {
    final a = [for (var i = 1; i <= 40; i++) 'l$i'];
    final b = [...a]
      ..[2] = 'X'
      ..[30] = 'Y';
    final c = diff(a.join('\n'), b.join('\n'));
    expect(c.hunks, hasLength(2));
    expect(c.hunks[0].newStart, 1);
    expect(c.hunks[1].newStart, 28);
    expect(flat(c), isNot(contains('l15')));
    expect((c.added, c.removed), (2, 2));
  });

  test('两处改动离得近：合成一段', () {
    final a = [for (var i = 1; i <= 12; i++) 'l$i'];
    final b = [...a]
      ..[2] = 'X'
      ..[6] = 'Y';
    expect(diff(a.join('\n'), b.join('\n')).hunks, hasLength(1));
  });

  test('新建：全是增；删除：全是删；行号从 1 开始', () {
    final made = diff(null, 'a\nb\nc\n');
    expect((made.kind, made.added, made.removed), (ChangeKind.created, 3, 0));
    expect(made.hunks.single.lines, ['+a', '+b', '+c']);
    expect((made.hunks.single.oldStart, made.hunks.single.newStart), (1, 1));
    final gone = diff('a\nb\n', null);
    expect((gone.kind, gone.added, gone.removed), (ChangeKind.deleted, 0, 2));
    expect(gone.hunks.single.lines, ['-a', '-b']);
    expect(gone.stat, '−2');
  });

  test('在开头加、在结尾加、在中间删', () {
    expect(diff('b\nc\n', 'a\nb\nc\n').hunks.single.lines, ['+a', ' b', ' c']);
    final tail = diff('a\nb\n', 'a\nb\nc\n').hunks.single;
    expect(tail.lines, [' a', ' b', '+c']);
    expect(tail.rows.last.newNo, 3);
    expect(diff('a\nb\nc\n', 'a\nc\n').hunks.single.lines, [' a', '-b', ' c']);
  });

  test('只有换行符或末尾换行不同：0 增 0 删，给一句说明', () {
    final c = diff('a\r\nb\r\n', 'a\nb');
    expect((c.added, c.removed, c.hasDiff), (0, 0, false));
    expect(c.note, contains('换行'));
    expect(diff('', '').note, isNotNull);
    expect(diff(null, '').note, contains('空文件'));
  });

  test('中文、重复行、空行', () {
    final c = diff('你好\n\n你好\n世界\n', '你好\n\n大家好\n世界\n');
    expect(c.hunks.single.lines, [' 你好', ' ', '-你好', '+大家好', ' 世界']);
  });

  test('最长公共子序列：只挪了一行，不会报成全删全增', () {
    final c = diff('a\nb\nc\nd\ne\n', 'b\nc\nd\ne\na\n');
    expect((c.added, c.removed), (1, 1));
  });

  test('超过行数上限：不比，只留说明', () {
    final big = List.filled(kDiffMaxInputLines + 1, 'x').join('\n');
    final c = diff(big, '${big}y');
    expect(c.hasDiff, isFalse);
    expect(c.note, contains('$kDiffMaxInputLines'));
    expect((c.added, c.removed), (0, 0));
  });

  test('超过字符上限：不比，只留说明', () {
    final c = diff('a' * (kDiffMaxInputChars + 1), 'b');
    expect(c.hasDiff, isFalse);
    expect(c.note, contains('太大'));
  });

  test('中间那段太大（旧行数×新行数超过上限）：整段按先删后增算，统计照样准', () {
    final a = [for (var i = 0; i < 2100; i++) 'old $i'];
    final b = [for (var i = 0; i < 2100; i++) 'new $i'];
    expect(a.length * b.length, greaterThan(kDiffMaxCells));
    final c = diff('head\n${a.join('\n')}\ntail\n', 'head\n${b.join('\n')}\ntail\n');
    expect((c.added, c.removed), (2100, 2100));
    expect(c.hunks.first.lines.first, ' head');
    expect(c.hunks.first.lines[1], '-old 0');
  });

  test('对比太长：最多存 $kDiffStoreLines 行，记下截了多少，并写进说明', () {
    final b = [for (var i = 0; i < 1000; i++) 'row $i'].join('\n');
    final c = diff(null, b);
    expect(c.added, 1000);
    expect(c.hunks.fold<int>(0, (s, h) => s + h.lines.length), kDiffStoreLines);
    expect(c.cutLines, 1000 - kDiffStoreLines);
    expect(c.note, contains('${1000 - kDiffStoreLines} 行没有显示'));
  });

  test('一行太长：只存前 $kDiffStoreLineChars 个字符；总字符数不超过 $kDiffStoreChars', () {
    final long = 'x' * 5000;
    final one = diff('a\n', '$long\n');
    expect(one.hunks.single.lines.last.length, kDiffStoreLineChars + 2);
    final many = diff(null, List.filled(300, 'y' * 390).join('\n'));
    expect(many.storedChars, lessThanOrEqualTo(kDiffStoreChars));
    expect(many.cutLines, greaterThan(0));
  });

  group('存盘', () {
    test('存下去再读回来一样；不存全文', () {
      final c = diff('a\nb\nc\n', 'a\nB\nc\nd\n');
      expect(c.before, isNotNull);
      final json = jsonEncode(c.slim.toJson());
      expect(json, isNot(contains('before')));
      final back = FileChange.tryParse(jsonDecode(json))!;
      expect((back.path, back.kind, back.added, back.removed), ('lib/a.dart', ChangeKind.modified, 2, 1));
      expect(back.hunks.single.lines, c.hunks.single.lines);
      expect((back.hunks.single.oldStart, back.hunks.single.newStart), (1, 1));
      expect(back.before, isNull);
      expect(back.after, isNull);
    });

    test('坏数据不崩：类型不对、缺字段、乱七八糟的都返回 null 或丢掉坏的部分', () {
      for (final bad in [
        null,
        3,
        'x',
        <Object>[],
        <String, Object>{},
        {'p': 5},
        {'p': ''},
      ]) {
        expect(FileChange.tryParse(bad), isNull, reason: '$bad');
      }
      final c = FileChange.tryParse({
        'p': 'a.txt',
        'k': 42,
        'a': 'three',
        'r': -5,
        'x': <Object>[],
        'm': 7,
        'h': [
          'not a map',
          {'o': 'x', 'n': 1, 'l': <Object>[]},
          {'o': 1, 'n': 1, 'l': 'nope'},
          {
            'o': -3,
            'n': 0,
            'l': [' ok', 5, '', '?bad', '+good', null],
          },
        ],
      })!;
      expect((c.kind, c.added, c.removed, c.cutLines, c.note), (ChangeKind.modified, 0, 0, 0, null));
      expect(c.hunks.single.lines, [' ok', '+good']);
      expect((c.hunks.single.oldStart, c.hunks.single.newStart), (1, 1));
      expect(c.hunks.single.rows, hasLength(2));
    });

    test('一串改动：不是列表就是空；坏的项丢掉', () {
      expect(parseFileChanges(null), isEmpty);
      expect(parseFileChanges({'p': 'a'}), isEmpty);
      expect(parseFileChanges('oops'), isEmpty);
      final list = parseFileChanges([
        {'p': 'a.txt', 'k': 'new', 'a': 2},
        7,
        {'k': 'mod'},
        {'p': 'b.txt', 'k': 'del', 'r': 1},
      ]);
      expect([for (final c in list) (c.path, c.kind)], [('a.txt', ChangeKind.created), ('b.txt', ChangeKind.deleted)]);
    });

    test('读回来的对比行数有上限：存盘文件被人塞了很多行也不会全收', () {
      final c = FileChange.tryParse({
        'p': 'a',
        'h': [
          {'o': 1, 'n': 1, 'l': List.filled(5000, '+x')},
        ],
      })!;
      expect(c.hunks.single.lines.length, kDiffStoreLines * 2);
    });
  });
}
