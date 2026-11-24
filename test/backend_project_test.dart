// 后端积木落到项目里：重新生成代码（只覆盖我们生成的、没人动过的文件）、认出项目里的后端、README 的启动与 curl 段。
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/backend/backend_model.dart';
import 'package:lopicode/backend/backend_project.dart';
import 'package:lopicode/backend/backend_targets.dart';
import 'package:lopicode/backend/backend_templates.dart';
import 'package:lopicode/backend/backend_validate.dart';
import 'package:lopicode/core/path_guard.dart';
import 'package:lopicode/core/safe_file.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tmp;
  late String ws;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('lopi_be_proj_');
    ws = p.join(tmp.path, 'proj');
    Directory(ws).createSync();
    File(p.join(tmp.path, 'outside.txt')).writeAsStringSync('原样');
  });
  tearDown(() async {
    await pendingWrites();
    tmp.deleteSync(recursive: true);
  });

  File f(String rel) => File(p.join(ws, rel));
  void put(String rel, String content) => f(rel)
    ..createSync(recursive: true)
    ..writeAsStringSync(content);
  void putDoc(String language, {String dir = ''}) => put(p.join(dir, kBackendFileName), '${backendStarterDocument('样本', language: language).encode()}\n');
  Map<String, dynamic> manifest() => jsonDecode(f('${PathGuard.reservedDir}/$kBackendManifestFile').readAsStringSync()) as Map<String, dynamic>;

  /// 工作区里除内部目录外的全部文件 → 内容。
  Map<String, String> snapshot() => {
    for (final e in Directory(ws).listSync(recursive: true).whereType<File>())
      if (!p.relative(e.path, from: ws).startsWith(PathGuard.reservedDir)) p.relative(e.path, from: ws): e.readAsStringSync(),
  };

  final node = backendTargetFor('node')!;
  final python = backendTargetFor('python')!;

  group('重新生成', () {
    test('根目录：照文档里记的语言生成，文件和生成器给的一样；再来一次什么都不写', () async {
      putDoc('node');
      final r = await regenerateBackend(ws);
      expect(r.error, isNull);
      expect((r.file, r.dir, r.language, r.languageLabel), (kBackendFileName, '', 'node', node.label));
      final expected = backendProjectFiles(backendStarterDocument('样本', language: 'node'))!.files;
      expect(r.written.toSet(), expected.keys.toSet());
      expect(r.conflicts, isEmpty);
      expect(r.removed, isEmpty);
      expect(r.errorCount, 0);
      for (final e in expected.entries) {
        expect(f(e.key).readAsStringSync(), e.value, reason: e.key);
      }
      expect((manifest()['.'] as Map)['language'], 'node');
      expect(((manifest()['.'] as Map)['files'] as Map).keys.toSet(), expected.keys.toSet());

      final again = await regenerateBackend(ws);
      expect(again.written, isEmpty);
      expect(again.unchanged.toSet(), expected.keys.toSet());
      expect(again.summary, contains('写入 0 个文件'));
    });

    test('server/ 子目录：按文件所在目录生成，根目录不多出文件', () async {
      putDoc('python', dir: 'server');
      put('README.md', '根说明');
      final r = await regenerateBackend(ws);
      expect(r.error, isNull);
      expect((r.file, r.dir), ('server/$kBackendFileName', 'server'));
      expect(r.written, everyElement(startsWith('server/')));
      expect(f('server/${python.entryFile}').existsSync(), isTrue);
      expect(f('server/README.md').readAsStringSync(), contains('`cd server`'));
      expect(f('README.md').readAsStringSync(), '根说明');
      expect(Directory(ws).listSync().map((e) => p.basename(e.path)).toSet(), {'server', 'README.md', PathGuard.reservedDir});
      expect(manifest().keys, ['server']);
      // 明确指定文件也行
      expect((await regenerateBackend(ws, file: 'server/$kBackendFileName')).unchanged, isNotEmpty);
    });

    test('手改过的生成文件不覆盖，列进冲突；别的照常更新；改回去 / 强制覆盖后恢复', () async {
      putDoc('node');
      await regenerateBackend(ws);
      final original = f(node.entryFile).readAsStringSync();
      final edited = '$original\n// 我自己加的一行\n';
      f(node.entryFile).writeAsStringSync(edited);
      // 改积木：加一个接口，入口文件和 README 都该变
      final doc = backendStarterDocument('样本', language: 'node')..addRoute('GET', '/ping');
      await saveBackendFile(f(kBackendFileName), doc);

      final r = await regenerateBackend(ws);
      expect(r.error, isNull);
      expect([for (final c in r.conflicts) c.path], [node.entryFile]);
      expect(r.conflicts.single.reason, contains('手改过'));
      expect(f(node.entryFile).readAsStringSync(), edited, reason: '手改过的不能被覆盖');
      expect(r.written, contains('README.md'));
      expect(f('README.md').readAsStringSync(), contains('/ping'));
      expect(r.summary, contains('没有动'));

      // 再生成一次：还是认得出它被改过（没有因为上一次而“洗白”）
      final r2 = await regenerateBackend(ws);
      expect([for (final c in r2.conflicts) c.path], [node.entryFile]);
      expect(f(node.entryFile).readAsStringSync(), edited);

      final forced = await regenerateBackend(ws, overwriteEdited: true);
      expect(forced.conflicts, isEmpty);
      expect(forced.written, [node.entryFile]);
      expect(f(node.entryFile).readAsStringSync(), contains('/ping'));
      expect(f(node.entryFile).readAsStringSync(), isNot(contains('我自己加的一行')));
    });

    test('没有生成标记的同名文件（用户自己的）不覆盖；带标记、没登记过的可以覆盖', () async {
      putDoc('node');
      put(node.entryFile, '// 我自己写的服务\nconsole.log(1);\n');
      put('README.md', '# 样本\n\n> 由 LopiCode 后端积木生成（旧版本留下的）\n');
      final r = await regenerateBackend(ws);
      expect([for (final c in r.conflicts) c.path], [node.entryFile]);
      expect(r.conflicts.single.reason, contains('没有生成标记'));
      expect(f(node.entryFile).readAsStringSync(), '// 我自己写的服务\nconsole.log(1);\n');
      expect(r.written, contains('README.md'), reason: '带标记的旧文件算我们的');
      expect(f('README.md').readAsStringSync(), contains('## 用 curl 试一试'));
      // 同名位置是个目录：不动它，算冲突
      Directory(p.join(ws, 'lopi')).createSync();
    });

    test('换语言：旧语言的生成文件清掉（没动过的才清），手改过的留下并列出', () async {
      putDoc('node');
      await regenerateBackend(ws);
      final nodeFiles = backendProjectFiles(backendStarterDocument('样本', language: 'node'))!.files.keys.toSet();
      final pyFiles = backendProjectFiles(backendStarterDocument('样本', language: 'python'))!.files.keys.toSet();
      final onlyNode = nodeFiles.difference(pyFiles);
      expect(onlyNode, isNotEmpty);
      put('notes.txt', '我的笔记');

      putDoc('python');
      final r = await regenerateBackend(ws);
      expect(r.error, isNull);
      expect(r.language, 'python');
      expect(r.removed.toSet(), onlyNode);
      for (final k in onlyNode) {
        expect(f(k).existsSync(), isFalse, reason: '$k 是 Node.js 留下的，应该清掉');
      }
      expect(snapshot().keys.toSet(), {...pyFiles, kBackendFileName, 'notes.txt'});
      expect(f('notes.txt').readAsStringSync(), '我的笔记');
      expect((manifest()['.'] as Map)['language'], 'python');

      // 换回 Node.js，但先手改 Python 的入口文件：它不该被删
      f(python.entryFile).writeAsStringSync('# 我改过\n');
      putDoc('node');
      final back = await regenerateBackend(ws);
      final onlyPython = pyFiles.difference(nodeFiles);
      expect(back.removed.toSet(), onlyPython.difference({python.entryFile}));
      expect(f(python.entryFile).readAsStringSync(), '# 我改过\n');
      expect([for (final c in back.conflicts) c.path], [python.entryFile]);
      expect(back.conflicts.single.reason, contains('没有删'));
    });

    test('越界 / 不对的路径：拒绝，什么都没写', () async {
      putDoc('node');
      put('other.json', '{}');
      for (final bad in ['../outside.txt', '../../etc/$kBackendFileName', '/etc/$kBackendFileName', '${PathGuard.reservedDir}/$kBackendFileName', 'other.json', 'server/../../$kBackendFileName']) {
        final r = await regenerateBackend(ws, file: bad);
        expect(r.ok, isFalse, reason: bad);
        expect(r.written, isEmpty);
      }
      expect(snapshot().keys.toSet(), {kBackendFileName, 'other.json'});
      expect(File(p.join(tmp.path, 'outside.txt')).readAsStringSync(), '原样');
      expect(Directory(tmp.path).listSync().map((e) => p.basename(e.path)).toSet(), {'proj', 'outside.txt'});
    });

    test('子目录是指到工作区外面的符号链接：不往外写', () async {
      final outside = Directory(p.join(tmp.path, 'elsewhere'))..createSync();
      File(p.join(outside.path, kBackendFileName)).writeAsStringSync('${backendStarterDocument('外面', language: 'node').encode()}\n');
      Link(p.join(ws, 'server')).createSync(outside.path);
      final r = await regenerateBackend(ws, file: 'server/$kBackendFileName');
      expect(r.ok, isFalse);
      expect(outside.listSync().map((e) => p.basename(e.path)), [kBackendFileName]);
      expect(await findBackendProjects(ws), isEmpty);
      final auto = await regenerateBackend(ws); // 自动找也不会顺着链接出去
      expect(auto.ok, isFalse);
      expect(outside.listSync().map((e) => p.basename(e.path)), [kBackendFileName]);
    });

    test('坏文件不崩：坏 JSON、不是对象、别的 kind、空文件——都说明原因，磁盘不动', () async {
      for (final bad in ['{ 这不是 JSON', '[1, 2]', '{"kind": "page", "root": {}}', '', '"just a string"']) {
        put(kBackendFileName, bad);
        put('server.js', '// 我的\n');
        final r = await regenerateBackend(ws);
        expect(r.ok, isFalse, reason: bad);
        expect(r.error, isNotEmpty);
        expect(r.summary, startsWith('没有生成'));
        expect(snapshot(), {kBackendFileName: bad, 'server.js': '// 我的\n'}, reason: bad);
        expect(f('${PathGuard.reservedDir}/$kBackendManifestFile').existsSync(), isFalse);
      }
    });

    test('文档里有读不懂的条目：照读得懂的部分生成，并说明跳过了什么', () async {
      final json = backendStarterDocument('样本', language: 'node').toJson();
      json['routes'] = [...json['routes'] as List, '不是接口'];
      put(kBackendFileName, jsonEncode(json));
      final r = await regenerateBackend(ws);
      expect(r.ok, isTrue);
      expect(r.note, isNotNull);
      expect(r.summary, contains(r.note!));
    });

    test('没有后端文件 / 语言没有生成器：说明原因，不写文件', () async {
      expect((await regenerateBackend(ws)).error, contains('没有 $kBackendFileName'));
      expect((await regenerateBackend(ws, file: 'server/$kBackendFileName')).error, contains('找不到'));
      final doc = backendStarterDocument('样本')..language = 'cobol';
      put(kBackendFileName, doc.encode());
      final r = await regenerateBackend(ws);
      expect(r.error, contains('还没有生成器'));
      expect(snapshot().keys, [kBackendFileName]);
    });

    test('生成记录坏了不崩：当成没有记录，靠开头的标记认文件；坏文件留一份备份', () async {
      putDoc('node');
      await regenerateBackend(ws);
      final mf = f('${PathGuard.reservedDir}/$kBackendManifestFile');
      for (final bad in ['{ 坏的', '[]', '{".": "不是对象"}', '{".": {"files": [1, 2]}}', '{".": {"files": {"server.js": 42}}}']) {
        mf.writeAsStringSync(bad);
        final r = await regenerateBackend(ws);
        expect(r.error, isNull, reason: bad);
        expect(r.conflicts, isEmpty, reason: '文件没动过，开头有标记，应该认得出来');
        expect((manifest()['.'] as Map)['files'], isA<Map<String, dynamic>>());
      }
      expect(Directory(p.join(ws, PathGuard.reservedDir)).listSync().any((e) => p.basename(e.path).startsWith('$kBackendManifestFile.bad')), isTrue, reason: '坏的记录文件要留备份');
    });

    test('直接给文档（界面刚改完还没存盘时用）：按给的文档生成', () async {
      putDoc('node');
      final doc = backendStarterDocument('样本', language: 'node')..addRoute('GET', '/from-memory');
      final r = await regenerateBackend(ws, doc: doc);
      expect(r.ok, isTrue);
      expect(f(node.entryFile).readAsStringSync(), contains('/from-memory'));
      expect(f(kBackendFileName).readAsStringSync(), isNot(contains('/from-memory')), reason: '这个函数不负责存文档');
    });

    test('有校验错误的文档：不生成新代码，上一次生成的文件原样留着，结果里说明被拦下和错误条数；修好以后照常生成', () async {
      // 先正常生成一次。
      final good = backendStarterDocument('样本', language: 'node');
      put(kBackendFileName, good.encode());
      final first = await regenerateBackend(ws);
      expect((first.ok, first.blocked, first.errorCount), (true, false, 0));
      final before = f('server.js').readAsStringSync();
      final stamp = f('server.js').lastModifiedSync();

      final doc = backendStarterDocument('样本', language: 'node');
      doc.addRoute('GET', '/hello'); // 和已有的重复＝错误
      doc.addRoute('GET', '/brand-new');
      put(kBackendFileName, doc.encode());
      final r = await regenerateBackend(ws);
      expect(r.ok, isFalse);
      expect(r.blocked, isTrue);
      expect(r.errorCount, greaterThan(0));
      expect(r.written, isEmpty);
      expect(r.removed, isEmpty);
      expect(r.error, contains('有 ${r.errorCount} 个错误，代码没有更新'));
      expect(r.summary, contains('代码没有更新'));
      expect(f('server.js').readAsStringSync(), before, reason: '上一次生成的原样留着');
      expect(f('server.js').lastModifiedSync(), stamp);
      expect(before, isNot(contains('/brand-new')));

      // 只有警告（一个空接口）：照常生成。
      final warn = backendStarterDocument('样本', language: 'node')..addRoute('GET', '/brand-new');
      expect(validateBackend(warn).where((i) => i.isError), isEmpty);
      expect(validateBackend(warn), isNotEmpty);
      put(kBackendFileName, warn.encode());
      final w = await regenerateBackend(ws);
      expect((w.ok, w.blocked, w.errorCount), (true, false, 0));
      expect(f('server.js').readAsStringSync(), contains('/brand-new'));
    });
  });

  group('认出项目里的后端', () {
    test('没有后端：空表 / null；目录不存在也不崩', () async {
      expect(await findBackendProjects(ws), isEmpty);
      expect(await detectBackendProject(ws), isNull);
      expect(await findBackendProjects(p.join(tmp.path, '没有这个目录')), isEmpty);
    });

    test('根目录的后端：名字、语言、端口、接口数、启动命令', () async {
      putDoc('node');
      final b = (await detectBackendProject(ws))!;
      expect((b.file, b.dir, b.readable, b.name, b.language, b.port), (kBackendFileName, '', true, '样本', 'node', 8080));
      expect(b.routeCount, 7);
      expect(b.errorCount, 0);
      expect(b.target, same(node));
      expect(b.startCommand, node.startCommand.join(' '));
      expect(b.buildCommands, [for (final c in node.buildCommands) c.join(' ')]);
      expect(b.terminalCommand, [...b.buildCommands, b.startCommand].join(' && '));
      expect(b.localUrl, 'http://localhost:8080');
    });

    test('server/ 下的后端：终端命令先 cd；根目录和 server/ 都有时根目录排前面', () async {
      putDoc('python', dir: 'server');
      final b = (await detectBackendProject(ws))!;
      expect((b.file, b.dir, b.language), ('server/$kBackendFileName', 'server', 'python'));
      expect(b.terminalCommand, 'cd server && ${python.startCommand.join(' ')}');
      putDoc('node');
      expect([for (final x in await findBackendProjects(ws)) x.file], [kBackendFileName, 'server/$kBackendFileName']);
      expect((await detectBackendProject(ws))!.dir, '');
    });

    test('每种现有语言：都给得出启动命令', () async {
      for (final t in backendTargets) {
        putDoc(t.id);
        final b = (await detectBackendProject(ws))!;
        expect(b.target, same(t));
        expect(b.terminalCommand, [for (final c in t.buildCommands) c.join(' '), t.startCommand.join(' ')].join(' && '));
      }
    });

    test('端口写在命令里的语言（PHP）：启动命令、终端命令、README 里用的都是文档里的端口，不是默认的 8080', () async {
      final doc = backendStarterDocument('样本', language: 'php')..port = 3210;
      put(p.join('server', kBackendFileName), '${doc.encode()}\n');
      final b = (await detectBackendProject(ws))!;
      expect(b.port, 3210);
      expect(b.startCommand, 'php -S 0.0.0.0:3210 server.php');
      expect(b.terminalCommand, 'cd server && php -S 0.0.0.0:3210 server.php');
      final result = await regenerateBackend(ws);
      expect(result.ok, isTrue);
      final readme = f('server/README.md').readAsStringSync();
      expect(readme, contains('启动：`php -S 0.0.0.0:3210 server.php`'), reason: '“在 LopiCode 里启动”那一段');
      expect(readme, isNot(contains('0.0.0.0:8080')));
      // 别的语言端口不在命令里：改了端口命令不变。
      final nodeDoc = backendStarterDocument('样本')..port = 3210;
      put(kBackendFileName, '${nodeDoc.encode()}\n');
      expect((await detectBackendProject(ws))!.startCommand, node.startCommand.join(' '));
    });

    test('后端文件坏了：认得出“这里有后端”，但标成读不了，带原因；没有启动命令', () async {
      put(kBackendFileName, '{ 坏的');
      final b = (await detectBackendProject(ws))!;
      expect((b.readable, b.target, b.startCommand, b.terminalCommand), (false, null, null, null));
      expect(b.note, contains('JSON'));
    });

    test('语言没有生成器：读得出来，但没有启动命令', () async {
      put(kBackendFileName, (backendStarterDocument('样本')..language = 'cobol').encode());
      final b = (await detectBackendProject(ws))!;
      expect((b.readable, b.language, b.target, b.terminalCommand), (true, 'cobol', null, null));
    });
  });

  test('生成标记：只看开头几行；两种标记都认', () {
    for (final m in kBackendGeneratedMarkers) {
      expect(hasBackendMarker('// $m，手改会被覆盖\ncode();\n'), isTrue);
    }
    expect(hasBackendMarker('code();\n'), isFalse);
    expect(hasBackendMarker(''), isFalse);
    expect(hasBackendMarker('${'x\n' * 40}// ${kBackendGeneratedMarkers.first}\n'), isFalse, reason: '标记在很后面的不算（可能只是用户代码里提到）');
    for (final t in backendTargets) {
      for (final e in t.generate(backendStarterDocument('x', language: t.id)).entries) {
        if (RegExp(r'\.(mod|sum|json|toml|xml|csproj|gitignore)$').hasMatch(e.key) || e.key == '.gitignore') continue;
        expect(hasBackendMarker(e.value), isTrue, reason: '${t.id} 生成的 ${e.key} 开头没有生成标记——没登记过时会被当成用户自己的文件');
      }
    }
  });
}
