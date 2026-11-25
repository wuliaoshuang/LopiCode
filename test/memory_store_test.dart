// 文件记忆（lib/agent/memory_store.dart、memory_tools.dart）：读写删查、上限、像密钥的拒写、撤销、并发写排队、
// 外面手改文件、系统提示词里的清单、四个工具各自的行为。
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/agent/agent_tools.dart';
import 'package:lopicode/agent/memory_store.dart';
import 'package:lopicode/agent/memory_tools.dart';
import 'package:lopicode/core/crash_log.dart';
import 'package:lopicode/core/safe_file.dart';
import 'package:path/path.dart' as p;

// 拼出来的假密钥（不是真的）：拆开写，免得源码里出现一整串像密钥的东西。
final String fakeKey = 'sk-${'a1b2c3d4' * 3}';

void main() {
  late Directory tmp;
  late MemoryStore store;
  var changed = 0;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('lopi_mem_');
    changed = 0;
    store = MemoryStore(p.join(tmp.path, 'memory'), MemoryScope.global, onChanged: () => changed++);
    CrashLog.instance.resetForTest();
  });
  tearDown(() async {
    await pendingWrites();
    tmp.deleteSync(recursive: true);
  });

  File md(String id) => File(p.join(store.dir, '$id.md'));

  group('读写删查', () {
    test('写一条：落成一个普通的 Markdown 文件（# 标题 + 正文），读得回来', () async {
      final r = await store.write('回答的语言', '用简体中文回答。\n先给结论再解释。');
      expect(r.created, isTrue);
      expect(r.entry.title, '回答的语言');
      expect(md('回答的语言').readAsStringSync(), '# 回答的语言\n\n用简体中文回答。\n先给结论再解释。\n');
      expect(store.entries.single.body, '用简体中文回答。\n先给结论再解释。');
      expect(store.entries.single.summary, '用简体中文回答。');
      expect(changed, greaterThan(0), reason: '写了要通知界面');

      final again = MemoryStore(store.dir, MemoryScope.global);
      expect((await again.load()).single.title, '回答的语言');
    });

    test('同标题再写＝改写那一条（不多出文件）；标题不分大小写也认', () async {
      await store.write('Commit 规范', '用中文写提交说明');
      final r = await store.write('commit 规范', '用中文写提交说明，一行以内');
      expect(r.created, isFalse);
      expect(store.entries, hasLength(1));
      expect(store.entries.single.body, '用中文写提交说明，一行以内');
      expect(Directory(store.dir).listSync().where((e) => e.path.endsWith('.md')), hasLength(1));
    });

    test('标题里有文件名不能用的符号：文件名换掉，标题原样', () async {
      final r = await store.write('路径 a/b: 的坑?', '别用反斜杠');
      expect(r.entry.title, '路径 a/b: 的坑?');
      expect(r.entry.id, isNot(contains('/')));
      expect(md(r.entry.id).existsSync(), isTrue);
      expect(p.isWithin(store.dir, md(r.entry.id).path), isTrue);
    });

    test('标题是 ../ 之类：文件还是落在记忆目录里', () async {
      final r = await store.write('../../逃出去', '试试');
      expect(p.isWithin(store.dir, md(r.entry.id).path), isTrue);
      expect(File(p.join(tmp.path, '逃出去.md')).existsSync(), isFalse);
    });

    test('删一条：文件没了；删不存在的报错', () async {
      await store.write('甲', '一');
      await store.write('乙', '二');
      final gone = await store.delete('甲');
      expect(gone.title, '甲');
      expect(md('甲').existsSync(), isFalse);
      expect(store.entries.map((e) => e.title), ['乙']);
      expect(() => store.delete('没有这条'), throwsA(isA<MemoryException>()));
    });

    test('清空：全删，撤销记录也清掉', () async {
      await store.write('甲', '一');
      await store.write('乙', '二');
      expect(await store.clear(), 2);
      expect(store.entries, isEmpty);
      expect(store.changes, isEmpty);
      expect(() => store.undoLast(), throwsA(isA<MemoryException>()));
    });

    test('外面手改 / 手加的文件：重新读就看得到；没有 # 标题的用文件名当标题', () async {
      await store.write('甲', '一');
      md('甲').writeAsStringSync('# 甲\n\n被她手改了\n');
      File(p.join(store.dir, '手写的.md')).writeAsStringSync('没有标题行，只有正文');
      File(p.join(store.dir, 'notes.txt')).writeAsStringSync('不是 md，不算');
      await store.load();
      expect(store.find('甲')!.body, '被她手改了');
      expect(store.find('手写的')!.body, '没有标题行，只有正文');
      expect(store.entries, hasLength(2));
    });

    test('手放进来的超大文件不读（免得一条把提示词撑爆）；目录不存在也不崩', () async {
      expect(await store.load(), isEmpty);
      Directory(store.dir).createSync(recursive: true);
      File(p.join(store.dir, '巨大.md')).writeAsStringSync('# 巨大\n\n${'字' * 20000}');
      expect(await store.load(), isEmpty);
    });

    test('searchMemory：几个词都出现才算，不分大小写，标题里的也算', () async {
      await store.write('回答的语言', '用简体中文回答');
      await store.write('Flutter 版本', '这个项目用 Flutter 3.x，不要升级');
      await store.write('提交规范', '提交说明用中文');
      expect(searchMemory(store.entries, '中文').map((h) => h.entry.title), unorderedEquals(['回答的语言', '提交规范']));
      expect(searchMemory(store.entries, 'flutter 升级').single.entry.title, 'Flutter 版本');
      expect(searchMemory(store.entries, 'flutter 中文'), isEmpty);
      expect(searchMemory(store.entries, '规范').single.entry.title, '提交规范');
      expect(searchMemory(store.entries, '   '), isEmpty);
    });
  });

  group('上限', () {
    test('标题、正文为空或太长：拒绝，什么都不写', () async {
      Future<void> bad(String title, String body, String why) async {
        await expectLater(store.write(title, body), throwsA(isA<MemoryException>().having((e) => e.message, 'message', contains(why))));
      }

      await bad('', '正文', '标题不能为空');
      await bad('题' * (kMemoryMaxTitleChars + 1), '正文', '标题太长');
      await bad('标题', '   ', '正文不能为空');
      await bad('标题', '字' * (kMemoryMaxBodyChars + 1), '正文太长');
      expect(Directory(store.dir).existsSync() ? Directory(store.dir).listSync() : const <FileSystemEntity>[], isEmpty);
      // 刚好到上限可以
      await store.write('题' * kMemoryMaxTitleChars, '字' * kMemoryMaxBodyChars);
      expect(store.entries, hasLength(1));
    });

    test('条数到上限：不能再新增，但还能改写已有的', () async {
      for (var i = 0; i < kMemoryMaxEntries; i++) {
        await store.write('第 $i 条', '内容 $i');
      }
      await expectLater(store.write('再来一条', '放不下'), throwsA(isA<MemoryException>().having((e) => e.message, 'message', contains('到上限'))));
      expect(store.entries, hasLength(kMemoryMaxEntries));
      final r = await store.write('第 0 条', '改写可以');
      expect(r.created, isFalse);
    });

    test('总字数到上限：拒绝；把一条改短以后又放得下', () async {
      const n = kMemoryMaxTotalChars ~/ kMemoryMaxBodyChars;
      for (var i = 0; i < n; i++) {
        await store.write('大 $i', '字' * kMemoryMaxBodyChars);
      }
      await expectLater(store.write('超了', '多一个字'), throwsA(isA<MemoryException>().having((e) => e.message, 'message', contains('$kMemoryMaxTotalChars'))));
      await store.write('大 0', '短');
      await store.write('现在可以', '多一个字');
      expect(store.find('现在可以'), isNotNull);
    });
  });

  group('像密钥的内容拒写', () {
    test('正文或标题里有密钥 / 令牌 / 密码的样子：拒绝并说明，文件没落盘', () async {
      final samples = [
        '接口的 Key 是 $fakeKey',
        'password${'='}hunter2hunter2',
        'Authorization${':'} Bearer ${'abcdefgh' * 3}',
        'ghp_${'A1b2C3d4' * 4}',
        'https://user:${'p4ssw0rd'}@example.com/repo.git',
      ];
      for (final s in samples) {
        expect(looksLikeSecret(s), isTrue, reason: s);
        await expectLater(store.write('部署', s), throwsA(isA<MemoryException>().having((e) => e.message, 'message', contains('像密钥'))), reason: s);
      }
      await expectLater(store.write(fakeKey, '标题里也不行'), throwsA(isA<MemoryException>()));
      expect(store.entries, isEmpty);
      expect(Directory(store.dir).existsSync() ? Directory(store.dir).listSync() : const <FileSystemEntity>[], isEmpty);
    });

    test('普通内容不误伤', () async {
      expect(looksLikeSecret('密钥放在系统的安全存储里，不要写进代码'), isFalse);
      await store.write('密钥放哪', '密钥放在系统的安全存储里，不要写进代码');
      expect(store.entries, hasLength(1));
    });

    test('拒写的报错里不带那串密钥', () async {
      try {
        await store.write('部署', '接口的 Key 是 $fakeKey');
        fail('应该拒绝');
      } on MemoryException catch (e) {
        expect(e.message, isNot(contains(fakeKey)));
      }
    });
  });

  group('撤销', () {
    test('撤销新增＝删掉；撤销改写＝回到原文；撤销删除＝放回来', () async {
      await store.write('甲', '第一版');
      await store.write('甲', '第二版');
      await store.delete('甲');
      expect(store.entries, isEmpty);
      expect(store.changes, hasLength(3));

      expect((await store.undoLast()).describe, contains('删除了'));
      expect(store.find('甲')!.body, '第二版');
      expect((await store.undoLast()).describe, contains('改写了'));
      expect(store.find('甲')!.body, '第一版');
      expect((await store.undoLast()).describe, contains('记下了'));
      expect(store.entries, isEmpty);
      await expectLater(store.undoLast(), throwsA(isA<MemoryException>()));
    });

    test('谁改的写在说明里（Agent / 自动整理 / 你）', () async {
      await store.write('甲', '一');
      expect(store.changes.last.describe, 'Agent 记下了“甲”');
      await store.write('乙', '二', by: 'auto');
      expect(store.changes.last.describe, '自动整理时记下了“乙”');
      await store.delete('甲', by: 'user');
      expect(store.changes.last.describe, '你删除了“甲”');
    });

    test('撤销记录存盘：换一个对象（重开应用）还能撤销；最多留 $kMemoryUndoDepth 步', () async {
      for (var i = 0; i < kMemoryUndoDepth + 3; i++) {
        await store.write('第 $i 条', '内容');
      }
      expect(store.changes, hasLength(kMemoryUndoDepth));
      final again = MemoryStore(store.dir, MemoryScope.global);
      await again.load();
      expect(again.changes, hasLength(kMemoryUndoDepth));
      await again.undoLast();
      expect(again.find('第 ${kMemoryUndoDepth + 2} 条'), isNull);
    });

    test('那之后文件又被手改过：不动它，说清楚', () async {
      await store.write('甲', 'Agent 写的');
      md('甲').writeAsStringSync('# 甲\n\n她自己又改了\n');
      await expectLater(store.undoLast(), throwsA(isA<MemoryException>().having((e) => e.message, 'message', contains('又被改过'))));
      expect(md('甲').readAsStringSync(), contains('她自己又改了'));
      expect(store.changes, isEmpty, reason: '这一步作废');
    });

    test('撤销记录 undo.json 坏了：不崩，当作没有可撤销的，坏文件留备份，记忆本身照常', () async {
      await store.write('甲', '一');
      final undo = File(p.join(store.dir, 'undo.json'));
      for (final bad in ['{"半截": [1, 2', '\u0000乱码}{', '42', '"字符串"', 'null', '{"是对象不是列表": 1}', '[1, "x", {"id": 5}, {"id": "../x", "after": "a"}, {"id": "甲", "before": 3}]']) {
        undo.writeAsStringSync(bad);
        final again = MemoryStore(store.dir, MemoryScope.global);
        await again.load();
        expect(again.entries.single.title, '甲', reason: bad);
        expect(again.changes, isEmpty, reason: bad);
        await expectLater(again.undoLast(), throwsA(isA<MemoryException>()), reason: bad);
      }
      expect(Directory(store.dir).listSync().where((e) => p.basename(e.path).startsWith('undo.json.bad-')), isNotEmpty);
    });

    test('撤销记录里的文件名不许带路径（被人改过的 undo.json 不能让撤销去动目录外面的文件）', () async {
      final outside = File(p.join(tmp.path, 'outside.md'))..writeAsStringSync('外面的文件');
      Directory(store.dir).createSync(recursive: true);
      File(p.join(store.dir, 'undo.json')).writeAsStringSync(
        jsonEncode([
          {'id': '../outside', 'title': 'x', 'before': null, 'after': '外面的文件', 'at': 0, 'by': 'agent'},
        ]),
      );
      await store.load();
      expect(store.changes, isEmpty);
      expect(outside.readAsStringSync(), '外面的文件');
    });
  });

  group('并发写排队', () {
    test('同时发起很多次写（含同一个目录的两个对象）：一条不丢、文件都完整', () async {
      final other = MemoryStore(store.dir, MemoryScope.global);
      await Future.wait([for (var i = 0; i < 20; i++) (i.isEven ? store : other).write('并发 $i', '内容 $i')]);
      await store.load();
      expect(store.entries, hasLength(20));
      for (final e in store.entries) {
        expect(md(e.id).readAsStringSync(), '# ${e.title}\n\n${e.body}\n');
      }
    });

    test('同时写同一个标题：最后只有一条（不会各建一个文件）', () async {
      final other = MemoryStore(store.dir, MemoryScope.global);
      await Future.wait([store.write('同一条', '主对话写的'), other.write('同一条', '后台整理写的')]);
      await store.load();
      expect(store.entries, hasLength(1));
      expect(Directory(store.dir).listSync().where((e) => e.path.endsWith('.md')), hasLength(1));
    });

    test('前一个操作失败不会卡住后面的', () async {
      await expectLater(store.write('', ''), throwsA(isA<MemoryException>()));
      await store.write('后面的', '照常');
      expect(store.entries, hasLength(1));
    });
  });

  group('系统提示词里的那一段', () {
    MemoryEntry e(String title, String body, [MemoryScope scope = MemoryScope.global]) => MemoryEntry(scope: scope, id: title, title: title, body: body, updatedAt: DateTime(2026));

    test('没有记忆：说“还没有”；写明不要记密钥', () {
      final s = memoryPromptSection(const [], const [], canWrite: true);
      expect(s, contains('现在还没有任何记忆'));
      expect(s, contains('绝对不要把密钥、令牌、密码记进记忆'));
      expect(s, contains(kMemoryWriteTool));
    });

    test('不能写的对话（仅可查看 / 计划模式 / 子代理）：只说能读', () {
      final s = memoryPromptSection([e('甲', '一')], null, canWrite: false);
      expect(s, contains('只能读记忆，不能写'));
      expect(s, isNot(contains(kMemoryWriteTool)));
      expect(s, contains('甲'));
    });

    test('内容不多：直接带全文，分全局和项目两段', () {
      final s = memoryPromptSection([e('回答的语言', '用简体中文回答')], [e('构建命令', 'flutter build apk', MemoryScope.project)], canWrite: true);
      expect(s, contains('全局记忆'));
      expect(s, contains('### 回答的语言\n用简体中文回答'));
      expect(s, contains('这个项目的记忆'));
      expect(s, contains('### 构建命令\nflutter build apk'));
      expect(s, isNot(contains('下面只有标题和摘要')));
    });

    test('内容多（超过 $kMemoryPromptFullChars 字）：只带标题和摘要，并提示用工具读全文', () {
      final list = [for (var i = 0; i < 4; i++) e('长的 $i', '第一行摘要 $i\n${'字' * 1000}')];
      final s = memoryPromptSection(list, const [], canWrite: true);
      expect(s, contains('下面只有标题和摘要'));
      expect(s, contains(kMemoryReadTool));
      expect(s, contains('- 长的 0：第一行摘要 0'));
      expect(s, isNot(contains('字' * 100)));
      expect(s.length, lessThan(kMemoryPromptIndexChars + 600));
    });

    test('条目多到清单也放不下：只列到上限，剩下的提示用查的', () {
      final list = [for (var i = 0; i < 120; i++) e('${'标题' * 15} $i', '${'摘要' * 30}\n${'字' * 100}')];
      final s = memoryPromptSection(list.sublist(0, 60), list.sublist(60), canWrite: true);
      expect(s, contains('条没列出来'));
      expect(s, contains(kMemorySearchTool));
      expect(s.length, lessThan(kMemoryPromptIndexChars + 600), reason: '整段有上限');
    });
  });

  group('四个工具', () {
    late MemoryStore project;
    setUp(() => project = MemoryStore(p.join(tmp.path, 'ws', '.lopicode', 'memory'), MemoryScope.project));

    Map<String, ExtraTool> tools({bool canWrite = true, bool allowGlobalWrite = true, bool withProject = true}) => {
      for (final t in memoryTools(global: store, project: withProject ? project : null, canWrite: canWrite, allowGlobalWrite: allowGlobalWrite)) (t.spec['function'] as Map)['name'] as String: t,
    };

    test('读和查是只读工具，写和删是写工具（权限档 / 计划模式按这个拦）', () {
      final t = tools();
      expect(t.keys, unorderedEquals([kMemoryReadTool, kMemorySearchTool, kMemoryWriteTool, kMemoryDeleteTool]));
      expect(t[kMemoryReadTool]!.kind, ToolKind.read);
      expect(t[kMemorySearchTool]!.kind, ToolKind.read);
      expect(t[kMemoryWriteTool]!.kind, ToolKind.write);
      expect(t[kMemoryDeleteTool]!.kind, ToolKind.write);
    });

    test('不给写（子代理）：只有读和查', () {
      expect(tools(canWrite: false).keys, unorderedEquals([kMemoryReadTool, kMemorySearchTool]));
    });

    test('memory_write：记到指定的那一处，回答里写明“记住了”；同标题是改写', () async {
      final t = tools();
      final a = await t[kMemoryWriteTool]!.run({'scope': 'global', 'title': '回答的语言', 'content': '用简体中文'});
      expect(a.ok, isTrue);
      expect(a.text, contains('记住了：“回答的语言”'));
      expect(a.text, contains('全局记忆'));
      expect(a.text, contains('新增'));
      final b = await t[kMemoryWriteTool]!.run({'scope': 'project', 'title': '构建命令', 'content': 'flutter build apk'});
      expect(b.text, contains('项目记忆'));
      expect(store.entries.single.title, '回答的语言');
      expect(project.entries.single.title, '构建命令');
      final c = await t[kMemoryWriteTool]!.run({'scope': 'global', 'title': '回答的语言', 'content': '用简体中文，短一点'});
      expect(c.text, contains('改写'));
      expect(store.entries.single.body, '用简体中文，短一点');
    });

    test('memory_write：像密钥的被拒，模型看得到原因，看不到那串密钥被存下', () async {
      final r = await tools()[kMemoryWriteTool]!.run({'scope': 'global', 'title': '部署', 'content': '服务器的 key 是 $fakeKey'});
      expect(r.ok, isFalse);
      expect(r.text, contains('像密钥'));
      expect(r.text, isNot(contains(fakeKey)));
      expect(store.entries, isEmpty);
    });

    test('memory_write：scope 缺了 / 乱写、超上限都是给模型的错误，不抛异常', () async {
      final t = tools();
      expect((await t[kMemoryWriteTool]!.run({'title': '甲', 'content': '一'})).ok, isFalse);
      expect((await t[kMemoryWriteTool]!.run({'scope': '别的', 'title': '甲', 'content': '一'})).ok, isFalse);
      final long = await t[kMemoryWriteTool]!.run({'scope': 'global', 'title': '甲', 'content': '字' * (kMemoryMaxBodyChars + 1)});
      expect(long.ok, isFalse);
      expect(long.text, contains('正文太长'));
    });

    test('没人在场（自动化任务）：写、删全局记忆都被拒；项目记忆可以', () async {
      await store.write('原有的', '全局');
      final t = tools(allowGlobalWrite: false);
      final scopes = (((t[kMemoryWriteTool]!.spec['function'] as Map)['parameters'] as Map)['properties'] as Map)['scope'] as Map;
      expect(scopes['enum'], ['project'], reason: '工具说明里就不给 global 这个选项');
      final w = await t[kMemoryWriteTool]!.run({'scope': 'global', 'title': '偷偷记', 'content': '不行'});
      expect(w.ok, isFalse);
      expect(w.text, contains('无人值守'));
      final d = await t[kMemoryDeleteTool]!.run({'scope': 'global', 'title': '原有的'});
      expect(d.ok, isFalse);
      expect(store.entries.single.title, '原有的');
      expect((await t[kMemoryWriteTool]!.run({'scope': 'project', 'title': '这个可以', 'content': '项目的'})).ok, isTrue);
      // 读还是两处都能读
      expect((await t[kMemoryReadTool]!.run({'title': '原有的'})).text, contains('全局'));
    });

    test('没人在场、项目记忆又读不了：写和删干脆不给', () {
      expect(tools(allowGlobalWrite: false, withProject: false).keys, unorderedEquals([kMemoryReadTool, kMemorySearchTool]));
    });

    test('memory_read：不给标题列清单；给标题读全文；没有这条给清单', () async {
      await store.write('回答的语言', '用简体中文\n第二行');
      await project.write('构建命令', 'flutter build apk');
      final t = tools();
      final list = await t[kMemoryReadTool]!.run({});
      expect(list.text, contains('全局记忆'));
      expect(list.text, contains('- 回答的语言：用简体中文'));
      expect(list.text, contains('项目记忆'));
      expect(list.text, contains('- 构建命令'));
      final one = await t[kMemoryReadTool]!.run({'title': '回答的语言'});
      expect(one.text, contains('用简体中文\n第二行'));
      expect((await t[kMemoryReadTool]!.run({'scope': 'project', 'title': '回答的语言'})).ok, isFalse);
      final none = await t[kMemoryReadTool]!.run({'title': '没有'});
      expect(none.ok, isFalse);
      expect(none.text, contains('回答的语言'));
      expect((await t[kMemoryReadTool]!.run({'scope': '乱写'})).ok, isFalse);
    });

    test('memory_read：读的是盘上最新的（她刚手改过也读得到）', () async {
      await store.write('甲', '旧的');
      md('甲').writeAsStringSync('# 甲\n\n她刚改的\n');
      expect((await tools()[kMemoryReadTool]!.run({'title': '甲'})).text, contains('她刚改的'));
    });

    test('memory_search：两处一起查，标出是哪一处；没有就说没有', () async {
      await store.write('回答的语言', '用简体中文');
      await project.write('提交规范', '提交说明用中文');
      final t = tools();
      final hit = await t[kMemorySearchTool]!.run({'query': '中文'});
      expect(hit.text, contains('找到 2 条'));
      expect(hit.text, contains('全局记忆'));
      expect(hit.text, contains('项目记忆'));
      expect((await t[kMemorySearchTool]!.run({'query': '火星'})).text, contains('没有提到'));
    });

    test('memory_delete：删掉指定那一处的那一条；没有就报错', () async {
      await store.write('甲', '一');
      final t = tools();
      expect((await t[kMemoryDeleteTool]!.run({'scope': 'project', 'title': '甲'})).ok, isFalse);
      final r = await t[kMemoryDeleteTool]!.run({'scope': 'global', 'title': '甲'});
      expect(r.ok, isTrue);
      expect(store.entries, isEmpty);
      expect(store.changes.last.after, isNull, reason: '删了也能撤销');
    });
  });
}
