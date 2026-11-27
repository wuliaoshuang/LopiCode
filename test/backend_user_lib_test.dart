// 用户自己写的库（积木第 5 版·库 2）不真跑的部分：写错的库在检查阶段被拦、库在项目里的存取、导出导入、
// “复制一份来改”、库改了以后用它的文档重查、编辑器宿主和校验认识库积木。真跑在 backend_user_lib_run_test.dart。
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/backend/backend_block_host.dart';
import 'package:lopicode/backend/backend_lib_build.dart';
import 'package:lopicode/backend/backend_lib_doc.dart';
import 'package:lopicode/backend/backend_lib_pack.dart';
import 'package:lopicode/backend/backend_lib_store.dart';
import 'package:lopicode/backend/backend_model.dart';
import 'package:lopicode/backend/backend_project.dart';
import 'package:lopicode/backend/backend_to_service.dart';
import 'package:lopicode/backend/backend_validate.dart';
import 'package:lopicode/core/path_guard.dart';
import 'package:lopicode/core/safe_file.dart';
import 'package:lopicode/lang/gen2_all.dart';
import 'package:lopicode/lang/lib_model.dart';

import 'support/backend_core_samples.dart';
import 'support/backend_func_blocks.dart';
import 'support/backend_lang_blocks.dart';
import 'support/user_libs.dart';

List<String> problemsOf(J doc, [List<LibLibrary> loaded = const []]) => beLibFiles(parseLangBlocksDocument(doc)..loaded = [...loaded]).problems;

J tiny({List<J>? functions, List<J>? blocks, String id = 'tata/tiny'}) => libDoc(
  '小库',
  id,
  functions: functions ?? [
    tfn('f1', '公开的', [tpar('话', tText)], [ret(cat([tx('公'), pm('话')]))], returns: tText),
    tfn('f2', '私下的', [tpar('话', tText)], [ret(cat([tx('私'), pm('话')]))], returns: tText),
  ],
  blocks: blocks ?? [def('pub', 'call', fn: 'f1', look: look('公开的', '公开 {话}', shape: 'value'))],
);

Future<Directory> _project() => Directory.systemTemp.createTemp('lopi_libs_');

/// 把库文档放进项目（和应用里“新建库 → 在画布上改 → 自动存盘”走的是同一个函数）。
Future<BeLibSaved> putLib(PathGuard guard, J json) async {
  final doc = parseLangBlocksDocument(json);
  final rel = beLibSourceRel(doc.library!.id);
  final file = File(guard.resolve(rel));
  await file.parent.create(recursive: true);
  await saveBackendFile(file, doc);
  return beLibSaveSource(guard, rel, doc);
}

void main() {
  group('写错的库在检查阶段被拦', () {
    test('好的库没有问题', () => expect(problemsOf(tiny()), isEmpty));

    test('函数重名', () {
      final p = problemsOf(tiny(functions: [
        tfn('f1', '公开的', [tpar('话', tText)], [ret(pm('话'))], returns: tText),
        tfn('f2', '公开的', [tpar('话', tText)], [ret(pm('话'))], returns: tText),
      ]));
      expect(p.join('\n'), contains('公开的'));
      expect(p, isNotEmpty);
    });

    test('积木编号重复', () {
      final doc = parseLangBlocksDocument(tiny());
      doc.library!.blocks.add(doc.library!.blocks.first.clone());
      expect(beLibFiles(doc).problems.join('\n'), contains('pub'));
    });

    test('展开型自己展开自己（递归展开）', () {
      final p = problemsOf(tiny(
        functions: [
          tfn('f1', '转圈', [tpar('话', tText)], [
            callS('f1', {'话': pm('话')}),
          ]),
        ],
        blocks: [def('loop', 'expand', fn: 'f1', look: look('转圈', '转圈 {话}'))],
      ));
      expect(p, isNotEmpty);
      expect(p.join('\n'), anyOf(contains('展开'), contains('自己')));
    });

    test('手改库文件，让展开的模板把同一个槽用两次：读进来就拦下', () {
      final files = buildUserLib(notesLibDoc()).files;
      final blocks = files['blocks.json']!;
      final hacked = blocks.replaceFirst('(槽 话)', '(拼 (槽 话) (槽 话))');
      expect(hacked, isNot(blocks), reason: '样例里要有展开型的模板');
      final lib = libRead({...files, 'blocks.json': hacked}, builtin: false);
      expect(lib.problems.join('\n'), contains('话'));
    });

    test('同一个槽在样子里写了两次', () {
      final p = problemsOf(tiny(blocks: [def('pub', 'call', fn: 'f1', look: look('公开的', '公开 {话} 再来 {话}', shape: 'value'))]));
      expect(p, isNotEmpty);
      expect(p.join('\n'), contains('话'));
    });

    test('没公开的名字，别的库用不到', () {
      final a = buildUserLib(tiny());
      final b = buildUserLib(
        libDoc('借用', 'tata/borrow', functions: [
          tfn('f1', '借', [tpar('话', tText)], [ret(lx('tata/tiny', 'pub', {'话': pm('话')}))], returns: tText),
        ], blocks: [def('borrow', 'call', fn: 'f1', look: look('借', '借 {话}', shape: 'value'))], uses: [use('tata/tiny')]),
        [a.lib],
      );
      expect(beLibCheckWith(b.lib, [a.lib]), isEmpty);
      // 手改库文件，去调人家没公开的函数：读得进来，一查就拦下。
      final hacked = {for (final e in b.files.entries) e.key: e.value.replaceAll('公开的', '私下的')};
      expect(hacked.toString(), isNot(b.files.toString()));
      final lib = libRead(hacked, builtin: false);
      final problems = [...lib.problems, if (lib.ok) ...beLibCheckWith(lib, [a.lib])];
      expect(problems, isNotEmpty);
      expect(problems.join('\n'), contains('私下的'));
    });

    test('库里不能有接口、“程序开始时”；作者段 lopi / local 不许用', () {
      expect(problemsOf({...tiny(), 'routes': [route('r1', 'GET', '/x', [])]}).join(), contains('接口'));
      expect(problemsOf(tiny(id: 'lopi/tiny')).join(), contains('lopi'));
      expect(problemsOf(tiny(id: 'local/tiny')).join(), contains('local'));
    });

    test('用的文档：库不在项目里、库的积木不在了，都报出来', () {
      final doc = userDocument(manyUserDoc(), [buildUserLib(flowLibDoc()).lib]);
      final errors = backendErrors(doc).map((i) => i.problem).join('\n');
      expect(errors, contains(kLibNotes));
      expect(beServiceGenerate(doc, 'node').problem, isNotNull);
    });
  });

  group('校验和编辑器宿主认识库积木', () {
    for (final (name, user, libs) in [
      ('校验器', checkUserDoc, [checkLibDoc]),
      ('流程', flowUserDoc, [flowLibDoc]),
      ('待办', todoUserDoc, [todoLibDoc]),
      ('批量任务', batchUserDoc, [batchLibDoc]),
      ('三个库', manyUserDoc, [flowLibDoc, notesLibDoc, checkLibDoc]),
    ]) {
      test('$name：没有错误，也没有“不认识的积木”', () {
        final doc = userDocument(user(), [for (final l in libs) buildUserLib(l()).lib]);
        final issues = validateBackend(doc);
        expect([for (final i in issues) if (i.isError) '${i.where}：${i.problem}'], isEmpty);
        expect([for (final i in issues) if (i.problem.contains('不认识')) i.problem], isEmpty);
      });
    }
    for (final (name, lib) in [('校验器', checkLibDoc), ('流程', flowLibDoc), ('待办', todoLibDoc), ('批量任务', batchLibDoc), ('记事', notesLibDoc)]) {
      test('库文档「$name」：没有错误，也没有“不认识的积木”', () {
        final issues = validateBackend(parseLangBlocksDocument(lib()));
        expect([for (final i in issues) if (i.isError) '${i.where}：${i.problem}'], isEmpty);
        expect([for (final i in issues) if (i.problem.contains('不认识')) i.problem], isEmpty);
      });
    }

    test('积木盒：每个用上的库一页；帽子串在画布上；拿得出新积木', () {
      final host = BeBlockHost(doc: userDocument(flowUserDoc(), [buildUserLib(flowLibDoc()).lib]));
      final page = host.categories.where((c) => c.id == 'lib:$kLibFlow').single;
      expect(page.label, '流程');
      expect(page.hats, isNotEmpty);
      expect([...page.blocks, ...page.exprs], isNotEmpty);
      for (final op in page.blocks) {
        expect(host.blockSpec(op), isNotNull, reason: op);
        expect(host.blockSentence(op), isNotNull, reason: op);
        expect(host.newBlock(op).op, op);
      }
      for (final kind in page.exprs) {
        expect(host.exprSpec(kind), isNotNull, reason: kind);
        expect(host.newExpr(kind)['e'], kind);
      }
      final hats = host.scripts.whereType<BeLibHat>().toList();
      expect(hats, isNotEmpty);
      expect(host.hatOf(hats.first).parts, isNotEmpty);
      // 再拖一个帽子出来、删掉。
      final before = host.doc.hats.length;
      late final String id;
      host.edit(() => id = host.addScript(page.hats.first.id)!.id);
      expect(host.doc.hats.length, before + 1);
      host.edit(() => host.removeScript(id));
      expect(host.doc.hats.length, before);
      // 带口的积木：口有名字。
      final retry = host.blockSpec(beLibOp(kLibFlow, 'retry'))!;
      expect(retry.bodyLabel, isNotNull);
      expect(retry.elseLabel, isNotNull);
    });

    test('库文档的积木盒多一页“做库积木”；没用库的文档一页都不多', () {
      final lib = BeBlockHost(doc: parseLangBlocksDocument(flowLibDoc()));
      expect(lib.categories.where((c) => c.id == 'libdef').single.blocks, [kBeLibMouthOp, kBeLibPutOp]);
      expect(lib.blockSpec(kBeLibMouthOp), isNotNull);
      final plain = BeBlockHost(doc: parseLangBlocksDocument(coreDoc('普通', main: [log(tx('好'))])));
      expect(plain.categories.where((c) => c.id.startsWith('lib')), isEmpty);
    });
  });

  group('库在项目里的存取、导出导入', () {
    late Directory dir;
    late PathGuard guard;
    setUp(() async {
      dir = await _project();
      guard = PathGuard(dir.path);
    });
    tearDown(() async {
      await pendingWrites();
      await dir.delete(recursive: true);
    });

    test('新建 → 存 → 读回来；清单记着；坏的画布不动上一次出的库文件', () async {
      final made = await beLibCreate(guard, id: 'tata/tiny', name: '小库', author: '小塔塔');
      expect(made.problem, isNull);
      expect(made.rel, 'blocks/tata/tiny/source/backend.lc.json');
      expect((await beLibCreate(guard, id: 'tata/tiny', name: '小库')).problem, contains('已经有'));
      expect((await beLibCreate(guard, id: 'Tata/x', name: '小库')).problem, isNotNull);
      expect((await beLibCreate(guard, id: 'lopi/x', name: '小库')).problem, contains('lopi'));
      expect((await putLib(guard, tiny())).problems, isEmpty);
      final all = await beLibsRead(guard);
      expect(all.single.ok, isTrue);
      expect(all.single.hasSource, isTrue);
      expect(all.single.lib.blocks.single.id, 'pub');
      final index = jsonDecode(await File(guard.resolve(kBeLibsIndexFile)).readAsString()) as Map;
      expect((index['libs'] as List).single['id'], 'tata/tiny');
      final before = all.single.files[kLibManifestFile];
      final bad = await putLib(guard, tiny(blocks: [def('pub', 'call', fn: 'f1', look: look('公开的', '公开 {话} 再来 {话}', shape: 'value'))]));
      expect(bad.problems, isNotEmpty);
      expect((await beLibsRead(guard)).single.files[kLibManifestFile], before);
    });

    test('导出再导入到另一个项目：库文件一个字不差，五种语言生成的也一个字不差', () async {
      for (final l in [flowLibDoc, notesLibDoc, checkLibDoc]) {
        expect((await putLib(guard, l())).problems, isEmpty);
      }
      final other = await _project();
      addTearDown(() => other.delete(recursive: true));
      final guard2 = PathGuard(other.path);
      for (final id in [kLibFlow, kLibNotes, kLibCheck]) {
        final out = await beLibExport(guard, id);
        expect(out.problem, isNull);
        expect(out.rel, endsWith(kBeLibFileSuffix));
        await File(guard.resolve(out.rel!)).copy('${other.path}/in.lopilib');
        final opened = await beLibOpenPack(guard2, 'in.lopilib');
        expect(opened.problem, isNull);
        final pre = opened.preview!;
        expect(pre.canImport, isTrue, reason: pre.problems.join('；'));
        expect(pre.id, id);
        expect(pre.author, isNotEmpty);
        expect(pre.blocks, isNotEmpty);
        expect(pre.hasNative, isFalse);
        expect(pre.hasSource, isTrue);
        expect((await beLibInstall(guard2, pre)).problems, isEmpty);
        expect((await beLibInstall(guard2, pre)).problems.single, contains('已经有'));
        expect((await beLibInstall(guard2, pre, replace: true)).problems, isEmpty);
      }
      final a = await beLibsRead(guard), b = await beLibsRead(guard2);
      expect([for (final s in b) s.id], [for (final s in a) s.id]);
      for (var i = 0; i < a.length; i++) {
        expect(b[i].files, a[i].files, reason: a[i].id);
        expect(b[i].from, 'file');
      }
      final one = parseLangBlocksDocument(manyUserDoc()), two = parseLangBlocksDocument(manyUserDoc());
      await beLibsAttach(guard, one);
      await beLibsAttach(guard2, two);
      for (final language in kGen2Languages) {
        final x = beServiceGenerate(one, language), y = beServiceGenerate(two, language);
        expect(x.problem, isNull, reason: language);
        expect(y.files, x.files, reason: language);
      }
      // 同样的库打两次包，一个字节不差。
      expect(beLibPack(a.first.files), beLibPack(a.first.files));
    });

    test('导入的防护：不是库的文件、名字不对劲的文件、带手写代码的库', () async {
      expect(beLibUnpack(utf8.encode('不是压缩包')).problem, isNotNull);
      expect(beLibUnpack(beLibPack({'x.txt': '1'})).problem, contains('清单'));
      expect(beLibUnpack(beLibPack({'../lib.json': '{}', 'lib.json': '{}'})).problem, contains('不对劲'));
      expect(beLibUnpack(List.filled(kBeLibMaxPackBytes + 1, 0)).problem, contains('太大'));
      final files = buildUserLib(tiny()).files;
      // 带手写代码：如实显示有哪些文件，但是不许导入。
      final native = beLibPreview(beLibUnpack(beLibPack({...files, 'native/hack.js': 'require("child_process")'})).files!);
      expect(native.hasNative, isTrue);
      expect(native.nativeFiles, ['native/hack.js']);
      expect(native.files['native/hack.js'], contains('child_process'));
      expect(native.canImport, isFalse);
      expect((await beLibInstall(guard, native)).problems, isNotEmpty);
      expect(await beLibsRead(guard), isEmpty);
      // 清单里自称“允许手写代码”也一样不许。
      final manifest = jsonDecode(files[kLibManifestFile]!) as Map;
      final allowed = beLibPreview({...files, kLibManifestFile: jsonEncode({...manifest, 'native': {'allowed': true, 'files': ['native/hack.js'], 'waits': ['慢慢来']}}), 'native/hack.js': 'x'});
      expect(allowed.canImport, isFalse);
      expect(allowed.lib.nativeWaits, ['慢慢来']);
      // 冒充应用自带的库。
      final fake = beLibPreview({...files, kLibManifestFile: jsonEncode({...manifest, 'id': 'lopi/service'})});
      expect(fake.canImport, isFalse);
      // 它靠的库项目里没有：预览里说出来。
      final needs = beLibPreview(buildUserLib(todoLibDoc()).files);
      expect(needs.needs.join(), contains('接口服务'));
      // 坏清单不崩。
      expect(beLibPreview({kLibManifestFile: '{"id": 3'}).canImport, isFalse);
      expect(beLibPreview({kLibManifestFile: '[]'}).canImport, isFalse);
    });

    test('复制一份来改：换标识、记着从谁复制的、和原来的断开；文档里的用法可以换过去', () async {
      expect((await putLib(guard, notesLibDoc())).problems, isEmpty);
      expect((await beLibFork(guard, kLibNotes, id: kLibNotes, name: '记事二')).problem, isNotNull);
      final got = await beLibFork(guard, kLibNotes, id: 'tata/notes2', name: '记事二');
      expect(got.problem, isNull);
      final all = await beLibsRead(guard);
      final copy = all.firstWhere((s) => s.id == 'tata/notes2');
      expect(copy.ok, isTrue);
      expect(copy.name, '记事二');
      expect(copy.from, 'copy');
      expect(jsonDecode(copy.files[kLibManifestFile]!)['origin'], {'id': kLibNotes, 'version': '1.0.0'});
      expect(all.firstWhere((s) => s.id == kLibNotes).name, '记事');
      final doc = parseLangBlocksDocument({...coreDoc('用记事', main: [lb(kLibNotes, 'note', {'话': tx('好')})]), 'version': 5, 'uses': [use(kLibNotes)]});
      await beLibsAttach(guard, doc);
      final switched = beLibSwitchUses(doc, kLibNotes, 'tata/notes2')!;
      expect(switched.count, 1);
      expect(switched.doc.use('tata/notes2'), isNotNull);
      expect(switched.doc.use(kLibNotes), isNull);
      expect(backendErrors(switched.doc), isEmpty);
      expect(beServiceGenerate(switched.doc, 'node').problem, isNull);
      // 没带画布原件的库（别人导出时没带）：说清楚为什么不能复制来改。
      final bare = buildUserLib(tiny()).files;
      expect(await beLibWriteFolder(guard, 'tata/tiny', bare, from: 'file'), isNull);
      expect((await beLibFork(guard, 'tata/tiny', id: 'tata/tiny2', name: '小库二')).problem, contains('画布原件'));
    });

    test('库改了以后，用它的文档重查：新冒出来的问题交回来；生成代码的入口也认', () async {
      expect((await putLib(guard, notesLibDoc())).problems, isEmpty);
      final user = parseLangBlocksDocument({...coreDoc('用记事', main: [lb(kLibNotes, 'note', {'话': tx('好')})]), 'version': 5, 'uses': [use(kLibNotes)]});
      await saveBackendFile(File(guard.resolve(kBackendFileName)), user);
      final first = await regenerateBackend(dir.path);
      expect(first.error, isNull);
      expect(first.written, isNotEmpty);
      // 把库里那块积木拿掉 → 用它的文档里那一块就找不到了。
      final changed = notesLibDoc();
      ((changed['library'] as Map)['blocks'] as List).removeWhere((b) => (b as Map)['id'] == 'note');
      final saved = await putLib(guard, changed);
      expect(saved.problems, isEmpty);
      expect(saved.fresh.keys, [kBackendFileName]);
      expect(saved.freshNote, contains(kBackendFileName));
      final again = await regenerateBackend(dir.path);
      expect(again.blocked, isTrue);
      // 存库走的是同一个生成入口：库文档不生成代码，出库文件。
      await saveBackendFile(File(guard.resolve(beLibSourceRel(kLibNotes))), parseLangBlocksDocument(notesLibDoc()));
      final lib = await regenerateBackend(dir.path, file: beLibSourceRel(kLibNotes));
      expect(lib.error, isNull);
      expect(lib.written, isEmpty);
      expect((await regenerateBackend(dir.path)).error, isNull);
      // 拿掉整个库。
      await beLibDelete(guard, kLibNotes);
      expect(await beLibsRead(guard), isEmpty);
      expect((await regenerateBackend(dir.path)).blocked, isTrue);
    });

    test('项目的库目录里有坏东西不崩', () async {
      final bad = Directory('${dir.path}/blocks/tata/broken');
      await bad.create(recursive: true);
      await File('${bad.path}/lib.json').writeAsString('{"id": ');
      await File('${dir.path}/blocks/libs.json').writeAsString('[1, 2');
      final all = await beLibsRead(guard);
      expect(all.single.ok, isFalse);
      final doc = parseLangBlocksDocument({...coreDoc('用坏库', main: []), 'version': 5, 'uses': [use('tata/broken')]});
      await beLibsAttach(guard, doc);
      expect(backendErrors(doc), isNotEmpty);
    });
  });
}
