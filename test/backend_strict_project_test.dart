// 严格规矩的后端文档走产品路径（积木第 5 版·库 1 下半）：重新生成写进项目的文件、README、启动命令、“看代码”，
// 再照产品给的编译 / 启动命令五种语言真跑。顺带真跑 A1 没跑过的四样：分了模块的文档带接口、“字典的字段”、端口用文档里写的（不设 PORT）；
// “回应（状态码、说明、内容）”是给写库的人用的积木（积木盒里没有），在最后一组里直接用库机制搭出来真跑。服务只开在本机回环地址上，不联外网。
@Tags(['external'])
@Timeout(Duration(minutes: 30))
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/backend/backend_block_host.dart';
import 'package:lopicode/backend/backend_blocks.dart';
import 'package:lopicode/backend/backend_model.dart';
import 'package:lopicode/backend/backend_project.dart';
import 'package:lopicode/backend/backend_strict_target.dart';
import 'package:lopicode/backend/backend_targets.dart';
import 'package:lopicode/backend/backend_templates.dart';
import 'package:lopicode/backend/backend_to_service.dart';
import 'package:lopicode/backend/backend_validate.dart';
import 'package:lopicode/backend/lib_service.dart';
import 'package:lopicode/core/safe_file.dart';
import 'package:lopicode/lang/ast.dart';
import 'package:lopicode/lang/gen2_all.dart';
import 'package:lopicode/lang/lib_apply.dart';
import 'package:lopicode/lang/rules.dart';
import 'package:path/path.dart' as p;

import 'support/backend_core_samples.dart';
import 'support/backend_func_blocks.dart';
import 'support/backend_lang_blocks.dart';
import 'support/gen2_run.dart';
import 'support/gen2_serve.dart';

J _route(String id, String method, String path, List<J> body) => {'id': id, 'method': method, 'path': path, 'body': body};

/// 分了两个模块（“工具”里一块公开的积木，“主”用它）、带四个接口的严格文档。
BeDocument _doc(String language, int port) {
  final json = coreDoc(
    '严格的小服务',
    modules: [
      {
        'name': '工具',
        'owns': ['f1'],
      },
      {
        'name': '主',
        'uses': ['工具'],
      },
    ],
    entry: '主',
    public: ['f1'],
    functions: [
      tfn('f1', '翻倍', [tpar('n', tInt)], [ret(op2('*', pm('n'), nm(2)))], returns: tInt),
    ],
    main: [log(tx('开始了'))],
  );
  json['language'] = language;
  json['port'] = port;
  json['collections'] = [
    {'name': 'notes'},
    {'name': 'empty'},
  ];
  json['routes'] = [
    _route('r1', 'GET', '/double', [
      blk('respondJson', {
        'status': nm(200),
        'value': dc({
          'v': call('f1', {'n': nm(21)}),
        }),
      }),
    ]),
    _route('r3', 'GET', '/field', [
      blk('respondJson', {
        'status': nm(200),
        'value': dc({
          'v': beField(dc({'a': nm(1)}), 'a'),
          'none': beField(dc({'a': nm(1)}), 'b'),
        }),
      }),
    ]),
    _route('r4', 'POST', '/notes', [
      blk('dbInsert', {
        'collection': 'notes',
        'value': dc({'t': tx('记一条')}),
      }),
      blk('respondJson', {
        'status': nm(201),
        'value': dc({'count': beDbCount('notes')}),
      }),
    ]),
    _route('r5', 'GET', '/boom', [
      blk('respondJson', {
        'status': nm(200),
        'value': dc({'v': op2('/', nm(1), beDbCount('empty'))}),
      }),
    ]),
  ];
  return BeDocument.fromJson(json).doc;
}

void main() {
  late Directory tmp;
  late String ws;

  setUp(() {
    beStrictBackendGen = true;
    tmp = Directory.systemTemp.createTempSync('lopi_be_strict_');
    ws = p.join(tmp.path, 'proj');
    Directory(ws).createSync();
  });
  tearDown(() async {
    beStrictBackendGen = kLangStrictBackendGen;
    await pendingWrites();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  File f(String rel) => File(p.join(ws, rel));
  void putDoc(BeDocument doc) => f(kBackendFileName)
    ..createSync(recursive: true)
    ..writeAsStringSync('${doc.encode()}\n');

  test('样本文档没有错误；严格文档用的是严格的生成器，老规矩的文档还是老的', () {
    final doc = _doc('node', 8131);
    expect([for (final e in backendErrors(doc)) '${e.code} ${e.where} ${e.problem}'], isEmpty);
    expect(beStrictGenPending(doc), isFalse);
    expect(backendTargetOf(doc), isA<StrictBackendTarget>());
    expect(backendTargetOf(backendStarterDocument('x', rules: kLangRulesLoose)), isNot(isA<StrictBackendTarget>()));
    beStrictBackendGen = false;
    expect(beStrictGenPending(doc), isTrue);
    expect(backendTargetOf(doc), isNot(isA<StrictBackendTarget>()));
  });

  test('五种语言：生成的每个代码文件开头都有生成标记；固定文件的名单和真生成的对得上', () {
    for (final language in kGen2Languages) {
      final doc = _doc(language, 8131);
      final t = backendTargetOf(doc)!;
      final files = t.generate(doc);
      // 固定的那几个之外，只多出分出去的模块文件：内置错误种类一份、“接口服务”库一份、“工具”模块一份。
      final extra = files.keys.toSet().difference({...kBeStrictFiles[language]!, 'README.md'});
      expect(extra, hasLength(3), reason: '$language：$extra');
      expect(extra.every(RegExp(r'^(lc_kinds\.|LcKinds\.|m_|M_)').hasMatch), isTrue, reason: '$language：$extra');
      expect(files.keys.first, t.entryFile);
      for (final e in files.entries) {
        if (e.key == 'go.mod') continue;
        expect(hasBackendMarker(e.value), isTrue, reason: '$language 的 ${e.key} 开头没有生成标记');
      }
      final readme = files['README.md']!;
      expect(readme, contains(t.startCommandFor(8131).join(' ')));
      expect(readme, contains('严格规矩'));
      expect(readme, contains('| GET | `/double` |'));
    }
  });

  test('重新生成：写文件、登记；再来一次什么都不写；“看代码”就是写进去的入口文件', () async {
    final doc = _doc('node', 8131);
    putDoc(doc);
    final r = await regenerateBackend(ws);
    expect(r.error, isNull);
    expect(r.strictPending, isFalse);
    expect(r.written.toSet(), {'main.js', 'lc_kinds.js', 'm_接口服务.js', 'm_工具.js', 'lc2.js', 'README.md'});
    expect(f('README.md').readAsStringSync(), contains('## 在 LopiCode 里启动'));
    expect(f('README.md').readAsStringSync(), contains('启动：`node main.js`'));
    final again = await regenerateBackend(ws);
    expect(again.written, isEmpty);
    expect(again.unchanged.toSet(), {'main.js', 'lc_kinds.js', 'm_接口服务.js', 'm_工具.js', 'lc2.js', 'README.md'});
    final host = BeBlockHost(doc: doc);
    expect(host.codeText, f('main.js').readAsStringSync());
    expect(host.codeFileName, 'main.js');
    host.stopIssueTimer();
    final info = (await findBackendProjects(ws)).single;
    expect(info.terminalCommand, 'node main.js');
    // 模块改了名字：老名字的那个文件跟着删掉（它登记过），不留在工程里。
    f(kBackendFileName).writeAsStringSync('${doc.encode().replaceAll('工具', '帮手')}\n');
    final third = await regenerateBackend(ws);
    expect(third.error, isNull);
    expect(third.written, contains('m_帮手.js'));
    expect(f('m_工具.js').existsSync(), isFalse);
    expect(f('m_帮手.js').readAsStringSync(), contains('模块「帮手」'));
  });

  test('同一种语言换规矩：宽松 → 严格清掉 server.js 和老小库；严格 → 宽松清掉 main.js、lc2.js', () async {
    final loose = backendStarterDocument('样本', language: 'node', rules: kLangRulesLoose);
    putDoc(loose);
    final first = await regenerateBackend(ws);
    expect(first.error, isNull);
    expect(f('server.js').existsSync(), isTrue);
    final strict = BeDocument.fromJson(jsonDecode(loose.encode()) as Map<String, dynamic>).doc..rules = kLangRulesStrict;
    expect(backendErrors(strict), isEmpty);
    final up = await regenerateBackend(ws, doc: strict);
    expect(up.error, isNull);
    expect(f('main.js').existsSync(), isTrue);
    expect(f('server.js').existsSync(), isFalse);
    expect(up.removed, containsAll(first.written.where((w) => w != 'README.md')));
    final down = await regenerateBackend(ws, doc: loose);
    expect(down.error, isNull);
    expect(f('server.js').existsSync(), isTrue);
    expect(f('main.js').existsSync(), isFalse);
    expect(f('lc2.js').existsSync(), isFalse);
  });

  test('没有接口、只用语言核心的严格文档：写出来的是跑完就结束的程序，README 里明说', () async {
    final doc = BeDocument.fromJson(coreDoc('小程序', main: [log(tx('你好'))])).doc;
    expect(beStrictIsPlainProgram(doc, 'node'), isTrue);
    putDoc(doc);
    final r = await regenerateBackend(ws);
    expect(r.error, isNull);
    expect(f('main.js').readAsStringSync(), isNot(contains('http.serve')));
    expect(f('README.md').readAsStringSync(), contains('跑完就结束的程序'));
    final node = gen2Tools['node'];
    if (node == null) return;
    final run = Process.runSync(node, ['main.js'], workingDirectory: ws);
    expect((run.exitCode, run.stdout), (0, '你好\n'));
  });

  for (final language in kGen2Languages) {
    test('$language：照产品给的命令编译、启动（端口用文档里写的），真跑四个接口', () async {
      final skip = gen2SkipReason(language);
      if (skip != null) {
        markTestSkipped(skip);
        return;
      }
      final port = await gen2FreePort();
      final doc = _doc(language, port);
      putDoc(doc);
      final r = await regenerateBackend(ws);
      expect(r.error, isNull);
      final info = (await findBackendProjects(ws)).single;
      final server = await gen2ServeShell(Directory(ws), build: info.buildCommands, start: info.startCommand!.replaceFirst('0.0.0.0:', '127.0.0.1:'), port: port, php: language == 'php');
      final got = <String>[];
      List<String> out;
      try {
        for (final (method, target) in [('GET', '/double'), ('GET', '/field'), ('POST', '/notes'), ('POST', '/notes'), ('GET', '/boom'), ('GET', '/nope')]) {
          final reply = await server.send(method, target);
          got.add('${reply.status} ${reply.headers['content-type'] ?? '-'} ${utf8.decode(reply.body)}');
        }
      } finally {
        out = await server.stop();
      }
      expect(got, [
        '200 application/json; charset=utf-8 {"v":42}',
        '200 application/json; charset=utf-8 {"none":null,"v":1}',
        '201 application/json; charset=utf-8 {"count":1}',
        '201 application/json; charset=utf-8 {"count":2}',
        '500 application/json; charset=utf-8 $kBeStrictFailedBody',
        got.last,
      ], reason: server.stderrText);
      expect(got.last, startsWith('404 '));
      if (language != 'php') expect(out.first, '开始了');
    });
  }

  // “回应（状态码、说明、内容）”：库里给写库的人用的那块积木，用库机制搭一个接口真跑。
  LProgram respondProgram() {
    final lib = beServiceLibrary();
    var n = 0;
    String fresh(String name) => '$name${++n}';
    final settings = beServiceSettings(BeDocument(name: '回应', port: 8132, rules: kLangRulesStrict));
    final cx = LibCx(context: lib.provides, settings: settings, fresh: fresh);
    final hat = lib.block('onRequest')!;
    final provided = libProvided(hat, fresh);
    final inner = libApply(
      lib,
      lib.block('respond')!,
      const LibUse(values: {'status': LLit(201), 'type': LLit('text/html; charset=utf-8'), 'content': LLit('<b>好</b>')}),
      LibCx(context: {...lib.provides, ...provided}, settings: settings, fresh: fresh),
    );
    expect(inner.problem, isNull);
    final route = libApply(lib, hat, LibUse(values: const {'method': LLit('GET'), 'path': LLit('/page')}, mouths: {'body': inner.stmts}, provided: provided), cx);
    expect(route.problem, isNull);
    final init = libMoment(lib, lib.init, cx), start = libMoment(lib, lib.start, cx);
    return libProgram([lib], LModule(name: 'main', body: [...init.stmts, ...route.stmts, ...start.stmts]));
  }

  for (final language in kGen2Languages) {
    test('$language：“回应（状态码、说明、内容）”真跑', () async {
      final skip = gen2SkipReason(language);
      if (skip != null) {
        markTestSkipped(skip);
        return;
      }
      final server = await gen2Serve(language, gen2ProgramFiles(language, respondProgram()));
      final Gen2Reply reply;
      try {
        reply = await server.send('GET', '/page');
      } finally {
        await server.stop();
      }
      expect((reply.status, reply.headers['content-type'], utf8.decode(reply.body)), (201, 'text/html; charset=utf-8', '<b>好</b>'), reason: server.stderrText);
    });
  }
}
