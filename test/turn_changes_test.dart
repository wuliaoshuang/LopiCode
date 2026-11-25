// “这次改过的文件”的账本（纯逻辑）和它在聊天记录里的存取：合并同一文件的多次改动、子代理记进上级、
// 净效果没变的不算、上限、从存盘的消息重建、坏数据不崩。
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/agent/line_diff.dart';
import 'package:lopicode/session/chat_items.dart';
import 'package:lopicode/session/chat_models.dart';
import 'package:lopicode/session/chat_rows.dart';
import 'package:lopicode/session/turn_changes.dart';

FileChange ch(String path, String? before, String? after) =>
    diffFileChange(path, kind: before == null ? ChangeKind.created : (after == null ? ChangeKind.deleted : ChangeKind.modified), before: before, after: after);

void main() {
  group('账本', () {
    test('同一个文件改三次：合成一份，从最早的“改之前”比到最新的“改之后”', () {
      final book = TurnChangeBook()..begin('main');
      book
        ..record('main', ch('a.txt', '1\n2\n3\n', '1\nB\n3\n'))
        ..record('main', ch('a.txt', '1\nB\n3\n', '1\nB\n3\n4\n'))
        ..record('main', ch('a.txt', '1\nB\n3\n4\n', '1\n2\n3\n4\n'))
        ..record('main', null);
      final files = book.end('main');
      expect(files, hasLength(1));
      final f = files.single;
      expect((f.path, f.kind, f.added, f.removed), ('a.txt', ChangeKind.modified, 1, 0), reason: '第 2 行改了又改回去，净效果只多了一行');
      expect(f.hunks.single.lines, [' 1', ' 2', ' 3', '+4']);
      expect(f.before, isNull, reason: '交出来的不带全文');
      expect(book.end('main'), isEmpty, reason: '收过就销掉');
    });

    test('新建后再改：仍然算新建；新建了又删掉、改了又改回去：不进清单；改完删掉：算删除', () {
      final book = TurnChangeBook()..begin('main');
      book
        ..record('main', ch('new.txt', null, 'a\n'))
        ..record('main', ch('new.txt', 'a\n', 'a\nb\n'))
        ..record('main', ch('tmp.txt', null, 'x\n'))
        ..record('main', ch('tmp.txt', 'x\n', null))
        ..record('main', ch('back.txt', 'k\n', 'K\n'))
        ..record('main', ch('back.txt', 'K\n', 'k\n'))
        ..record('main', ch('old.txt', 'p\nq\n', 'p\n'))
        ..record('main', ch('old.txt', 'p\n', null));
      final files = book.end('main');
      expect([for (final f in files) (f.path, f.kind, f.added, f.removed)], [('new.txt', ChangeKind.created, 2, 0), ('old.txt', ChangeKind.deleted, 0, 2)]);
      expect(totalsOfChanges(files), (files: 2, added: 2, removed: 2));
    });

    test('子代理改的文件：记进它自己那一轮，也记进上级和上上级还在跑的那一轮', () {
      final book = TurnChangeBook()
        ..begin('main')
        ..begin('kid', parentId: 'main')
        ..begin('grandkid', parentId: 'kid');
      book
        ..record('main', ch('a.txt', 'a\n', 'A\n'))
        ..record('kid', ch('b.txt', null, 'b\n'))
        ..record('grandkid', ch('c.txt', 'c\n', null))
        ..record('kid', ch('a.txt', 'A\n', 'A\nmore\n'));
      expect([for (final f in book.end('grandkid')) f.path], ['c.txt']);
      expect([for (final f in book.end('kid')) f.path], ['a.txt', 'b.txt', 'c.txt']);
      // 孙代理收了以后子代理 / 上级的账不受影响；主对话里 a.txt 是两边改动合起来的
      final main = book.end('main');
      expect([for (final f in main) (f.path, f.kind)], [('a.txt', ChangeKind.modified), ('b.txt', ChangeKind.created), ('c.txt', ChangeKind.deleted)]);
      expect(main.first.hunks.single.lines, ['-a', '+A', '+more']);
    });

    test('上级这一轮已经收了（或者根本没开）：子代理照样只记自己的，不报错', () {
      final book = TurnChangeBook()..begin('kid', parentId: 'gone');
      book.record('kid', ch('a.txt', null, 'a\n'));
      book.record('nobody', ch('z.txt', null, 'z\n'));
      expect(book.end('kid'), hasLength(1));
      expect(book.end('nobody'), isEmpty);
    });

    test('有一次改动拿不到全文（二进制、目录）：这个文件没有合并对比，只有说明和累计的统计', () {
      final book = TurnChangeBook()..begin('main');
      book
        ..record('main', ch('bin.dat', 'a\n', 'b\n'))
        ..record('main', const FileChange(path: 'bin.dat', kind: ChangeKind.modified, note: '原文件是二进制文件，没有生成对比'))
        ..record('main', const FileChange(path: 'build/', kind: ChangeKind.deleted, note: '删除了整个目录'));
      final files = book.end('main');
      expect([for (final f in files) (f.path, f.kind, f.hasDiff, f.note)], [('bin.dat', ChangeKind.modified, false, '原文件是二进制文件，没有生成对比'), ('build/', ChangeKind.deleted, false, '删除了整个目录')]);
      expect((files.first.added, files.first.removed), (1, 1));
    });

    test('上限：最多 $kTurnFilesMax 个文件；对比加起来超过 $kTurnFilesDiffChars 字符后只存统计', () {
      final many = [for (var i = 0; i < kTurnFilesMax + 30; i++) ch('f$i.txt', null, 'x\n').slim];
      expect(capTurnFiles(many), hasLength(kTurnFilesMax));
      final fat = [for (var i = 0; i < 12; i++) ch('big$i.txt', null, List.filled(300, 'y' * 100).join('\n')).slim];
      final capped = capTurnFiles(fat);
      expect(capped, hasLength(12));
      expect(capped.fold<int>(0, (s, f) => s + f.storedChars), lessThanOrEqualTo(kTurnFilesDiffChars));
      expect(capped.first.hasDiff, isTrue);
      expect(capped.last.hasDiff, isFalse);
      expect(capped.last.added, 300, reason: '统计还在');
      expect(capped.last.note, contains('没有保存'));
      expect(jsonEncode([for (final f in capped) f.toJson()]).length, lessThan(kTurnFilesDiffChars * 2));
    });
  });

  group('聊天记录里的存取', () {
    List<ChatItem> rebuild(List<Map<String, dynamic>> messages) => chatItemsFromMessages(messages, childConversationIds: const [], hostPathOf: (r) => r);

    Map<String, dynamic> assistantCall(String id, String name, String args) => {
      'role': 'assistant',
      'content': null,
      'tool_calls': [
        {
          'id': id,
          'type': 'function',
          'function': {'name': name, 'arguments': args},
        },
      ],
    };

    test('存了对比的记录：步骤带着对比，回复下面有“改过的文件”那一项，排在用量前面', () {
      final step = ch('lib/a.dart', 'a\n', 'b\n').slim;
      final items = rebuild([
        {'role': 'user', 'content': '改一下'},
        assistantCall('c1', 'edit_file', '{"path":"lib/a.dart","old_text":"a","new_text":"b"}'),
        {'role': 'tool', 'tool_call_id': 'c1', 'content': '已修改 lib/a.dart', '_diff': jsonDecode(jsonEncode(step.toJson()))},
        {
          'role': 'assistant',
          'content': '改好了',
          '_files': jsonDecode(jsonEncode([step.toJson()])),
          '_usage': {'ms': 10, 'steps': <Object>[]},
        },
      ]);
      final tool = items.whereType<ToolItem>().single;
      expect((tool.change!.path, tool.change!.added, tool.change!.removed), ('lib/a.dart', 1, 1));
      expect(tool.change!.hunks.single.lines, ['-a', '+b']);
      final files = items.whereType<ChangedFilesItem>().single;
      expect(files.files.single.path, 'lib/a.dart');
      expect(items[items.length - 2], isA<ChangedFilesItem>());
      expect(items.last, isA<UsageItem>(), reason: '用量脚注排在清单后面');
      // 排成行：改过的文件是回复下面单独的一行，不进步骤组
      final rows = deriveChatRows(items, busy: false);
      expect(rows[rows.length - 2], isA<ItemRow>().having((r) => r.item, 'item', isA<ChangedFilesItem>()));
      expect(rows.whereType<StepGroupRow>().single.steps, hasLength(1), reason: '步骤组里只有那一步工具调用，清单不在里面');
    });

    test('旧记录（没有这些字段）照常能开', () {
      final items = rebuild([
        {'role': 'user', 'content': '写个文件'},
        assistantCall('c1', 'write_file', '{"path":"a.txt","content":"x"}'),
        {'role': 'tool', 'tool_call_id': 'c1', 'content': '已写入 a.txt（1 字符）'},
        {'role': 'assistant', 'content': '好了'},
      ]);
      expect(items.whereType<ToolItem>().single.change, isNull);
      expect(items.whereType<ChangedFilesItem>(), isEmpty);
      expect(items, hasLength(3));
    });

    test('坏数据不崩：字段类型不对、内容乱七八糟，都当作没有', () {
      for (final bad in <Object?>[
        'text',
        42,
        true,
        <Object>[1, 2],
        {'p': 9},
        {'p': 'a.txt', 'h': 'x', 'a': <Object>[]},
      ]) {
        final items = rebuild([
          {'role': 'user', 'content': '改'},
          assistantCall('c1', 'edit_file', '{bad json'),
          {'role': 'tool', 'tool_call_id': 'c1', 'content': '已修改', '_diff': bad},
          {'role': 'assistant', 'content': '好了', '_files': bad},
        ]);
        expect(items.whereType<ToolItem>(), hasLength(1), reason: '$bad');
        expect(items.whereType<AssistantItem>().single.text, '好了');
        // 能认出路径的那一份算数（对比丢掉），其余当作没有
        final ok = bad is Map && bad['p'] is String;
        expect(items.whereType<ToolItem>().single.change?.path, ok ? 'a.txt' : null, reason: '$bad');
        expect(items.whereType<ChangedFilesItem>(), isEmpty, reason: '$bad（_files 不是列表）');
      }
      final mixed = rebuild([
        {'role': 'user', 'content': '改'},
        {
          'role': 'assistant',
          'content': '好了',
          '_files': [
            null,
            3,
            {'p': 'ok.txt', 'k': 'new', 'a': 1},
            {'k': 'mod'},
          ],
        },
      ]);
      expect(mixed.whereType<ChangedFilesItem>().single.files.single.path, 'ok.txt');
    });
  });
}
