// 文档级的函数（积木第 4 版·第 2 阶段）接进后端：函数、匿名函数、旧后端积木混在同一个接口里，
// 生成四种语言的后端真的起起来发请求，响应逐字节相同、且等于写死的预期。PHP 也真跑（2026-11-26 起；本机没有 php 时跳过），另有文本检查。
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

BeX _call(String name, List<BeX> args) => BeXCall(name, args);
BeX _query(String name) => _call('query', [const BeXReq(), BeXLit(name)]);
BeXCall _send(String name, int status, BeX value) => BeXCall(name, [BeXLit(status), value]);

/// 文档级的函数。
List<LFuncDecl> _functions() => [
  // 递归
  fn(
    'fact',
    [p('k')],
    [
      iff(bin('<=', v('k'), n(1)), [ret(n(1))]),
      ret(bin('*', v('k'), callN('fact', [bin('-', v('k'), n(1))]))),
    ],
  ),
  // 默认参数
  fn('tax', [p('amount'), p('rate', or: 0.1)], [ret(bin('*', v('amount'), v('rate')))]),
  // 剩下的全收
  fn(
    'label',
    [p('parts', rest: true)],
    [
      ret(rt('listJoin', [v('parts'), t('-')])),
    ],
  ),
  // 函数体里夹着旧语句：旧语句给函数里新建的变量赋值
  fn(
    'bump',
    [p('x')],
    [
      let('y', n(0)),
      ...beHostStmts([
        BeSSet('y', _call('add', [const BeXVar('x'), const BeXLit(1)])),
      ]),
      ret(v('y')),
    ],
  ),
  // 调排在后面的函数
  fn(
    'isBig',
    [p('x')],
    [
      ret(callN('over', [v('x'), n(10)])),
    ],
  ),
  fn('over', [p('x'), p('limit')], [ret(bin('>', v('x'), v('limit')))]),
];

/// GET /fn 的函数体。[request] 是“这次请求”在这种语言的代码里叫什么。
List<BeS> _fnBody(String request) {
  LExpr old(BeX x) => beToLangExpr(x, request: request);
  return [
    // 旧：给文档里声明的变量赋值
    const BeSSet('acc', BeXLit(1)),
    BeSLang([
      // 新：调函数，参数是旧式子
      let(
        'total',
        callN('fact', [
          rt('toNumber', [old(_query('n'))]),
        ]),
      ),
      // 新：带函数体的匿名函数，体里是一句旧语句，改的是文档里声明的变量（Java 要装盒子、Python 要 nonlocal）
      let(
        'addf',
        lam(
          [p('x')],
          [
            ...beHostStmts([
              BeSSet('acc', _call('add', [const BeXVar('acc'), BeXLang(v('x'))])),
            ]),
          ],
        ),
      ),
      run(call(v('addf'), [n(5)])),
    ]),
    // 旧语句读写那个装了盒子的变量；式子里调函数
    BeSSet(
      'acc',
      _call('add', [
        const BeXVar('acc'),
        BeXLang(callN('bump', [n(1)])),
      ]),
    ),
    // 旧的“如果”，条件里是一个带函数体的匿名函数（要先在这一句前面定义好）
    BeSIf(
      _call('truthy', [
        BeXLang(
          call(
            lam([], [
              ret(callN('isBig', [v('total')])),
            ]),
          ),
        ),
      ]),
      [
        BeSLang([set('total', bin('-', v('total'), n(10)))]),
      ],
      const [],
    ),
    BeSLang([
      // 短写法的匿名函数里用“这次请求”和文档里声明的变量
      let(
        'tags',
        rt('listMap', [
          list([t('x'), t('y')]),
          lamx([p('e')], rt('join', [old(_query('s')), v('e'), v('acc')])),
        ]),
      ),
    ]),
    // 旧的“返回响应”，内容里调函数：默认参数全给 / 少给、剩下的全收、函数当值
    BeSReturn(
      _send(
        'sendJson',
        200,
        BeXLang(
          dict({
            'acc': v('acc'),
            'total': v('total'),
            'tags': v('tags'),
            'tax': callN('tax', [n(200)]),
            'tax2': callN('tax', [n(200), n(0.5)]),
            'label': callN('label', [t('a'), t('b')]),
            'none': callN('label'),
            'mapped': rt('listMap', [
              list([n(1), n(2)]),
              v('fact'),
            ]),
          }),
        ),
      ),
    ),
  ];
}

/// GET /two：另一个接口也能调同一批函数。
List<BeS> _twoBody(String request) => [
  BeSReturn(
    _send(
      'sendText',
      200,
      BeXLang(
        callN('label', [
          t('p'),
          beToLangExpr(_query('q'), request: request),
          callN('fact', [n(3)]),
        ]),
      ),
    ),
  ),
];

BeDocument _doc() {
  final doc = BeDocument(
    name: '函数',
    port: 8125,
    variables: [LcVariable(name: 'acc', type: 'number')],
  );
  doc.addRoute('GET', '/fn');
  doc.addRoute('GET', '/two');
  return doc;
}

BeProgram _plain(String request) {
  final base = lowerBackend(_doc());
  final doc = _doc();
  BeRouteProgram route(int i, List<BeS> body) {
    final r = base.routes[i];
    return BeRouteProgram(id: r.id, fnName: r.fnName, method: r.method, path: r.path, title: r.title, variables: i == 0 ? doc.variables : const [], body: body, usesFetch: false);
  }

  return BeProgram(name: base.name, port: base.port, collections: base.collections, skipped: base.skipped, routes: [route(0, _fnBody(request)), route(1, _twoBody(request))]);
}

BeProgram _program(String request) => beWithFunctions(_plain(request), _functions());

/// (请求, 内容)
const List<(String, String)> _requests = [
  ('/fn?n=4&s=ab', '{"acc":8,"label":"a-b","mapped":[1,2],"none":"","tags":["abx8","aby8"],"tax":20,"tax2":100,"total":14}'),
  ('/fn', '{"acc":8,"label":"a-b","mapped":[1,2],"none":"","tags":["x8","y8"],"tax":20,"tax2":100,"total":1}'),
  ('/fn?n=5', '{"acc":8,"label":"a-b","mapped":[1,2],"none":"","tags":["x8","y8"],"tax":20,"tax2":100,"total":110}'),
  ('/two?q=z', 'p-z-6'),
  ('/two', 'p--6'),
];

void main() {
  group('函数、匿名函数和旧后端积木混在同一个接口里', () {
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
        final dir = writeProject(target.generateProgram(_program(target.request)), 'lopi_lang_fn_${language}_');
        try {
          await buildProject(target, dir, tools);
          final server = await startBackend(dir, tools.resolve(target.startCommandFor(0), dir), environment: tools.environment);
          try {
            final got = <String>[];
            for (final (path, expected) in _requests) {
              final r = await sendRaw(server.port, 'GET', path);
              final text = utf8.decode(r.body);
              final where = '[$language] $path\n服务的错误输出：${server.stderrText}';
              expect(text, expected, reason: where);
              expect(r.status, 200, reason: where);
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

    test('go：带函数的工程也是 gofmt 的规范格式，go vet 没有意见', () async {
      final tools = await toolchainFor('go');
      if (tools == null) {
        // ignore: avoid_print 跳过的原因要让跑测试的人看见
        print('跳过：本机没有 go');
        markTestSkipped('本机没有 go');
        return;
      }
      final target = backendTargetFor('go')! as BeCodeTarget;
      final dir = writeProject(target.generateProgram(_program(target.request)), 'lopi_lang_fn_fmt_');
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
    test('没有函数：beWithFunctions 原样返回，生成结果一个字不变', () {
      for (final t in backendTargets) {
        final target = t as BeCodeTarget;
        final plain = lowerBackend(conformanceDocument());
        expect(identical(beWithFunctions(plain, const []), plain), isTrue);
        expect(target.generateProgram(beWithFunctions(plain, const [])), target.generate(conformanceDocument()), reason: target.id);
        expect(target.moduleFunctions(plain), isEmpty, reason: target.id);
      }
    });

    test('新节点里“返回响应”后面还跟着语句：算一定返回了，接口末尾不再补一句（Java 里那一句执行不到、编译不过）', () {
      final send = beHostStmts([BeSReturn(_send('sendText', 200, const BeXLit('好')))]);
      expect(
        beAlwaysReturns([
          BeSLang([...send, log(t('到不了'))]),
        ]),
        isTrue,
      );
      expect(
        beAlwaysReturns([
          BeSLang([iff(yes, send, send), log(t('到不了'))]),
        ]),
        isTrue,
      );
      expect(
        beAlwaysReturns([
          BeSLang([iff(yes, send), log(t('到得了'))]),
        ]),
        isFalse,
      );
    });

    test('只有函数、接口里没用新积木：也带语言核心的小库', () {
      final target = backendTargetFor('node')! as BeCodeTarget;
      final p = beWithFunctions(lowerBackend(conformanceDocument()), _functions());
      expect(beUsesLang(p), isTrue);
      final files = target.generateProgram(p);
      expect(files.keys, contains('lc_lang.js'));
      expect(files[target.entryFile], contains('function f_fact(v_k) {'));
    });

    test('函数排在接口前面，每种语言各是各的写法', () {
      final want = {
        'node': ['function f_fact(v_k) {', 'function f_tax(v_amount, v_rate = 0.1) {', 'function f_label(...v_parts) {', 'f_tax(200)', 'lc.fn("fact", 1, 1, f_fact)'],
        'python': ['def f_fact(v_k):', 'def f_tax(v_amount, v_rate=0.1):', 'def f_label(*v_parts):', 'nonlocal v_acc', 'f_tax(200)'],
        'go': ['func f_fact(v_k any) any {', 'func f_tax(v_amount any, v_rate any) any {', 'func f_label(v_parts any) any {', 'f_tax(200.0, 0.1)', 'f_label(lc.ListOf())'],
        'java': [
          'static Object f_fact(Object v_k) {',
          'static Object f_label(Object v_parts) {',
          'final Object[] v_acc = {0.0};',
          'v_acc[0] = Lc.add(v_acc[0], ',
          'f_tax(200.0, 0.1)',
          'f_label(LcLang.listOf())',
        ],
        'php': [r'function f_fact($v_k)', r'function f_tax($v_amount, $v_rate = 0.1)', r'function f_label(...$v_parts)', r'use (&$v_acc', "lc_fn(\"fact\", 1, 1, 'f_fact')"],
      };
      for (final t in backendTargets) {
        final target = t as BeCodeTarget;
        final entry = target.generateProgram(_program(target.request))[target.entryFile]!;
        for (final piece in want[target.id]!) {
          expect(entry, contains(piece), reason: '${target.id}\n$entry');
        }
        expect(entry.indexOf('f_fact'), lessThan(entry.indexOf('route_')), reason: '${target.id}：函数在接口前面');
      }
    });

    test('函数里有还不支持的节点：留一行说明，函数体换成空的，整份照样生成', () {
      for (final t in backendTargets) {
        final target = t as BeCodeTarget;
        final program = beWithFunctions(_plain(target.request), [
          ..._functions(),
          fn('bad', [p('x')], [const LThrow(LLit('x'))]),
        ]);
        late Map<String, String> files;
        expect(() => files = target.generateProgram(program), returnsNormally, reason: target.id);
        final entry = files[target.entryFile]!;
        expect(entry, contains('函数 bad 没有生成'), reason: target.id);
        expect(entry, contains('f_bad('), reason: target.id);
      }
    });

    test('php（文本检查）：带函数的入口文件引了语言核心的小库，花括号成对', () {
      final target = backendTargetFor('php')! as BeCodeTarget;
      final files = target.generateProgram(_program(target.request));
      final entry = files[target.entryFile]!;
      expect(files.keys, contains('lc_lang.php'));
      expect(files['lc_lang.php'], contains('final class LcFn'));
      expect(files['lc_lang.php'], contains('function lc_listSortBy('));
      expect(entry, contains(r'$req'));
      expect('{'.allMatches(entry).length, '}'.allMatches(entry).length);
      expect('('.allMatches(entry).length, ')'.allMatches(entry).length);
      expect(entry, isNot(contains('?>')));
      expect(entry, isNot(contains('=>')), reason: '不用箭头函数（它按值抓变量，改不了外面的）');
    });
  });
}
