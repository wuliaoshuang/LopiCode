// 新旧两条路混在同一个后端接口函数体里（积木第 4 版·第 1 阶段）：
// 旧积木的中间形式（BeS / BeX）和新语法树（BeSLang / BeXLang）互相套着，生成四种语言的后端真的起起来发请求，响应逐字节相同。
// PHP 也真跑（2026-11-26 起；本机没有 php 时跳过），另有文本检查。
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/backend/backend_ir.dart';
import 'package:lopicode/backend/backend_lang.dart';
import 'package:lopicode/backend/backend_model.dart';
import 'package:lopicode/backend/backend_target.dart';
import 'package:lopicode/backend/backend_targets.dart';
import 'package:lopicode/lang/lang.dart';
import 'package:lopicode/lowcode/logic_model.dart';

import 'support/backend_conformance.dart';
import 'support/lang_conformance.dart';

BeX _call(String fn, List<BeX> args) => BeXCall(fn, args);
BeX _query(String name) => _call('query', [const BeXReq(), BeXLit(name)]);
BeXCall _send(String fn, int status, BeX value) => BeXCall(fn, [BeXLit(status), value]);

/// 混着写的接口函数体。[request] 是“这次请求”在这种语言的代码里叫什么。
List<BeS> _mixedBody(String request) {
  LExpr old(BeX x) => beToLangExpr(x, request: request);
  return [
    // 旧：给文档里声明的变量赋值
    const BeSSet('acc', BeXLit(0)),
    // 新：新建变量、从…数到…（上限是旧式子“网址参数”）、跳过、跳出
    BeSLang([
      let('out', list()),
      LForCount('i', n(1), old(_query('n')), n(1), [
        iff(bin('==', v('i'), n(3)), [const LContinue()]),
        iff(bin('>', v('i'), n(5)), [const LBreak()]),
        // 新循环里套旧语句；旧语句的式子里又读新循环的变量
        ...beHostStmts([
          BeSSet('acc', _call('add', [const BeXVar('acc'), BeXLang(v('i'))])),
          BeSIf(_call('eq', [BeXLang(v('i')), _query('stop')]), [
            BeSReturn(_send('sendText', 200, BeXLang(rt('join', [t('在第 '), v('i'), t(' 遍提前返回')])))),
          ], const []),
        ]),
        run(rt('listPush', [v('out'), v('i')])),
      ]),
    ]),
    // 旧的“如果”里套新的“当…时重复”，条件读的是旧变量
    BeSIf(_call('gt', [const BeXVar('acc'), const BeXLit(100)]), [
      BeSLang([
        LWhile(bin('>', v('acc'), n(100)), [set('acc', bin('-', v('acc'), n(100)))]),
      ]),
    ], const []),
    // 旧的“重复”里套新语句
    BeSRepeat(1, _call('times', [const BeXLit(2)]), [
      BeSLang([
        run(rt('listPush', [v('out'), t('尾')])),
      ]),
    ]),
    // 旧的“返回响应”，内容是新式子（字典字面量、小库函数、值版如果），里面又套旧式子
    BeSReturn(
      _send(
        'sendJson',
        200,
        BeXLang(
          LDictLit([
            LDictEntry(t('acc'), v('acc')),
            LDictEntry(t('out'), v('out')),
            LDictEntry(t('s'), rt('upper', [old(_query('s'))])),
            LDictEntry(t('big'), LCond(bin('>', v('acc'), n(10)), t('大'), t('小'))),
          ]),
        ),
      ),
    ),
  ];
}

BeDocument _doc() {
  final doc = BeDocument(
    name: '新旧混用',
    port: 8124,
    variables: [LcVariable(name: 'acc', type: 'number')],
  );
  doc.addRoute('GET', '/mix');
  return doc;
}

/// 样本：一个接口 GET /mix，函数体是 [body]。
BeProgram _program(List<BeS> body) {
  final base = lowerBackend(_doc());
  final r = base.routes.single;
  final doc = _doc();
  return BeProgram(
    name: base.name,
    port: base.port,
    collections: base.collections,
    skipped: base.skipped,
    routes: [BeRouteProgram(id: r.id, fnName: r.fnName, method: r.method, path: r.path, title: r.title, variables: doc.variables, body: body, usesFetch: false)],
  );
}

/// (请求, 状态, Content-Type 开头, 内容)
const List<(String, int, String, String)> _requests = [
  ('/mix?n=10', 200, 'application/json', '{"acc":12,"big":"大","out":[1,2,4,5,"尾","尾"],"s":""}'),
  ('/mix?n=2&s=abc%20%E4%B8%AD', 200, 'application/json', '{"acc":3,"big":"小","out":[1,2,"尾","尾"],"s":"ABC 中"}'),
  ('/mix?n=0', 200, 'application/json', '{"acc":0,"big":"小","out":["尾","尾"],"s":""}'),
  ('/mix', 200, 'application/json', '{"acc":0,"big":"小","out":["尾","尾"],"s":""}'),
  ('/mix?n=10&stop=4', 200, 'text/plain', '在第 4 遍提前返回'),
  ('/mix?n=10&stop=3', 200, 'application/json', '{"acc":12,"big":"大","out":[1,2,4,5,"尾","尾"],"s":""}'),
  // 每次请求变量都从初始值开始
  ('/mix?n=1', 200, 'application/json', '{"acc":1,"big":"小","out":[1,"尾","尾"],"s":""}'),
];

void main() {
  group('新旧混在同一个接口函数体里', () {
    final bodies = <String, List<String>>{};
    for (final language in kLangRunnable) {
      test('$language：生成的后端能（编译）启动，${_requests.length} 条请求的响应都等于预期', () async {
        final tools = await toolchainFor(language);
        if (tools == null) {
          // ignore: avoid_print 跳过的原因要让跑测试的人看见
          print('跳过：本机没有 $language 的工具');
          markTestSkipped('本机没有 $language 的工具');
          return;
        }
        final target = backendTargetFor(language)! as BeCodeTarget;
        final dir = writeProject(target.generateProgram(_program(_mixedBody(target.request))), 'lopi_lang_be_${language}_');
        try {
          await buildProject(target, dir, tools);
          final server = await startBackend(dir, tools.resolve(target.startCommandFor(0), dir), environment: tools.environment);
          try {
            final got = <String>[];
            for (final (path, status, type, expected) in _requests) {
              final r = await sendRaw(server.port, 'GET', path);
              final text = utf8.decode(r.body);
              final where = '[$language] $path\n服务的错误输出：${server.stderrText}';
              expect(text, expected, reason: where);
              expect(r.status, status, reason: where);
              expect(r.type, startsWith(type), reason: where);
              got.add(text);
            }
            bodies[language] = got;
          } finally {
            await server.stop();
          }
        } finally {
          dir.deleteSync(recursive: true);
        }
      }, timeout: const Timeout(Duration(minutes: 8)));
    }

    test('各语言的响应逐字节相同', () {
      if (bodies.length < 2) {
        // ignore: avoid_print 跳过的原因要让跑测试的人看见
        print('跳过：能跑的语言不到两种');
        markTestSkipped('能跑的语言不到两种');
        return;
      }
      for (final e in bodies.entries.skip(1)) {
        expect(e.value, bodies.values.first, reason: e.key);
      }
    });

    test('go：混用的工程也是 gofmt 的规范格式，go vet 没有意见', () async {
      final tools = await toolchainFor('go');
      if (tools == null) {
        // ignore: avoid_print 跳过的原因要让跑测试的人看见
        print('跳过：本机没有 go');
        markTestSkipped('本机没有 go');
        return;
      }
      final target = backendTargetFor('go')! as BeCodeTarget;
      final dir = writeProject(target.generateProgram(_program(_mixedBody(target.request))), 'lopi_lang_be_fmt_');
      try {
        final fmt = await runTool(tools.resolve(['gofmt', '-l', '.'], dir), dir, tools.environment);
        expect(fmt.exitCode, 0, reason: '${fmt.stderr}');
        expect('${fmt.stdout}'.trim(), isEmpty, reason: '这些文件不是 gofmt 的格式');
        final vet = await runTool(tools.resolve(['go', 'vet', './...'], dir), dir, tools.environment);
        expect(vet.exitCode, 0, reason: '${vet.stdout}\n${vet.stderr}');
      } finally {
        dir.deleteSync(recursive: true);
      }
    }, timeout: const Timeout(Duration(minutes: 8)));
  });

  group('生成的工程', () {
    test('没用到新节点：文件清单和以前一样，不带语言核心的小库；用到了才多带一个', () {
      for (final t in backendTargets) {
        final target = t as BeCodeTarget;
        final langFile = target.langGen(const LangHost()).runtimeFile;
        final plain = target.generateProgram(lowerBackend(conformanceDocument()));
        expect(plain.keys, isNot(contains(langFile)), reason: target.id);
        expect(plain, target.generate(conformanceDocument()), reason: target.id);
        expect(beUsesLang(lowerBackend(conformanceDocument())), isFalse);
        final mixed = target.generateProgram(_program(_mixedBody(target.request)));
        expect(mixed.keys.toSet().difference(plain.keys.toSet()), {langFile}, reason: target.id);
        expect(mixed[langFile], target.langRuntimeSource);
        expect(mixed[target.runtimeFile], plain[target.runtimeFile], reason: '${target.id}：原来的小库不因为用了新节点而变');
      }
    });

    test('只在式子里用到新节点（没有新语句）也算用到', () {
      final p = _program([
        BeSReturn(
          _send(
            'sendJson',
            200,
            _call('add', [
              const BeXLit(1),
              BeXLang(rt('abs', [n(-2)])),
            ]),
          ),
        ),
      ]);
      expect(beUsesLang(p), isTrue);
      expect(beBodyUsesLang(const [BeSSet('acc', BeXLit(1))]), isFalse);
    });

    test('新节点新建的名字在接口函数开头声明一次；文档里已经声明的变量不重复声明', () {
      final body = _mixedBody('req');
      expect(beLangDeclares(body), ['out', 'i']);
      final node = backendTargetFor('node')! as BeCodeTarget;
      final entry = node.generateProgram(_program(body))[node.entryFile]!;
      expect('let v_out'.allMatches(entry).length, 1);
      expect('let v_i'.allMatches(entry).length, 1);
      expect('let v_acc'.allMatches(entry).length, 1);
      expect(entry, contains('require("./lc_lang.js")'));
    });

    test('还不支持的节点（抛出错误、类…）不让整份生成失败：留一行说明；这一段本该返回的补一个 500', () {
      for (final t in backendTargets) {
        final target = t as BeCodeTarget;
        final p = _program([
          const BeSLang([
            LThrow(LLit('x')),
            LHost(BeSReturn(BeXCall('sendText', [BeXLit(200), BeXLit('好')])), returns: true),
          ]),
        ]);
        late Map<String, String> files;
        expect(() => files = target.generateProgram(p), returnsNormally, reason: target.id);
        final entry = files[target.entryFile]!;
        expect(entry, contains('还不支持“抛出错误”'), reason: target.id);
        expect(entry, contains('这个接口里有还不支持的积木'), reason: target.id);
      }
    });

    test('php（文本检查）：混用的入口文件引了语言核心的小库，新旧两种写法都在', () {
      final target = backendTargetFor('php')! as BeCodeTarget;
      final files = target.generateProgram(_program(_mixedBody(target.request)));
      final entry = files[target.entryFile]!;
      expect(files.keys, contains('lc_lang.php'));
      expect(entry, contains("require_once __DIR__ . '/lc_lang.php';"));
      expect(entry, contains(r'lc_countSteps('));
      expect(entry, contains(r'$v_acc = lc_add($v_acc, $v_i);'));
      expect(entry, contains(r'lc_listPush($v_out, $v_i);'));
      expect(entry, contains(r'lc_upper(lc_query('));
      expect(entry, isNot(contains('?>')));
    });
  });
}
