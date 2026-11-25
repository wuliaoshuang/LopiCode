// 检查器里“函数”那一部分的后一半：S11、函数体里照样查的规则、函数对外的样子（返回值 / 返回类型 / 参数个数 / 递归）、
// 函数里用到了哪些宿主的东西（L15）。前一半（L01 / L02 / L03 / L09 / L11 / L14）在 lang_analyze_func_test.dart。
import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/lang/lang.dart';

import 'support/lang_conformance.dart';

List<String> _codes(Iterable<LIssue> issues) => [for (final i in issues) '${i.code}${i.isError ? '' : 'w'}'];

/// 查一个模块，给出问题的规则号（警告带 w）。
List<String> _module(List<LDecl> decls, [List<LStmt> body = const []]) => _codes(analyzeModule(LModule(decls: decls, body: body)).issues);

void main() {
  group('S11 有返回值的函数有的走法没有返回值（警告）', () {
    test('命中：“如果”里返回了值、别的走法没有；带值和不带值的返回混用；匿名函数也查', () {
      expect(
        _module(
          [
            fn(
              'f',
              [p('k')],
              [
                iff(v('k'), [ret(n(1))]),
              ],
            ),
          ],
          [
            log(callN('f', [n(1)])),
          ],
        ),
        ['S11w'],
      );
      expect(
        _module(
          [
            fn(
              'f',
              [p('k')],
              [
                iff(v('k'), [ret()]),
                ret(n(1)),
              ],
            ),
          ],
          [
            log(callN('f', [n(1)])),
          ],
        ),
        ['S11w'],
      );
      expect(
        _module([], [
          let(
            'g',
            lam(
              [p('k')],
              [
                iff(v('k'), [ret(n(1))]),
              ],
            ),
          ),
          log(call(v('g'), [n(1)])),
        ]),
        ['S11w'],
      );
    });

    test('不命中：每条走法都返回了值；根本没有返回值的函数', () {
      expect(
        _module(
          [
            fn(
              'f',
              [p('k')],
              [
                iff(v('k'), [ret(n(1))], [ret(n(2))]),
              ],
            ),
          ],
          [
            log(callN('f', [n(1)])),
          ],
        ),
        isEmpty,
      );
      expect(
        _module(
          [
            fn(
              'f',
              [p('k')],
              [
                iff(v('k'), [ret(n(1))]),
                ret(n(2)),
              ],
            ),
          ],
          [
            log(callN('f', [n(1)])),
          ],
        ),
        isEmpty,
      );
      expect(
        _module(
          [
            fn(
              'f',
              [p('k')],
              [
                iff(v('k'), [ret()]),
                log(v('k')),
              ],
            ),
          ],
          [
            run(callN('f', [n(1)])),
          ],
        ),
        isEmpty,
      );
    });
  });

  group('G03 / L04 / S10 在函数里照样查', () {
    test('函数里看不见“启动时”新建的变量、别的函数的变量；看得见模块级的', () {
      expect(
        _module(
          [
            fn('f', [], [ret(v('local'))]),
          ],
          [let('local', n(1)), log(callN('f')), log(v('local'))],
        ),
        ['G03'],
      );
      expect(
        _module(
          [
            fn('f', [], [let('mine', n(1)), ret(v('mine'))]),
            fn('g', [], [ret(v('mine'))]),
          ],
          [log(callN('f')), log(callN('g'))],
        ),
        ['G03'],
      );
      expect(
        _module(
          [
            LVarDecl('shared', n(1)),
            fn('f', [], [ret(v('shared'))]),
          ],
          [log(callN('f'))],
        ),
        isEmpty,
      );
    });

    test('匿名函数看得见外层函数的变量；外层看不见匿名函数里新建的', () {
      expect(_module([], [let('a', n(1)), let('g', lamx([], v('a'))), log(call(v('g')))]), isEmpty);
      expect(
        _module([], [
          let('g', lam([], [let('inner', n(1)), ret(v('inner'))])),
          log(call(v('g'))),
          log(v('inner')),
        ]),
        ['G03'],
      );
    });

    test('“跳出”不能穿过函数：循环里的匿名函数里写“跳出”算不在循环里', () {
      expect(
        _module([], [
          LRepeat(n(2), [
            let('g', lam([], [const LBreak()])),
            run(call(v('g'))),
          ]),
        ]),
        contains('L04'),
      );
      expect(
        _module(
          [
            fn('f', [], [
              LRepeat(n(2), [const LBreak()]),
            ]),
          ],
          [run(callN('f'))],
        ),
        isEmpty,
      );
    });

    test('返回后面还有语句：S10', () {
      expect(
        _module(
          [
            fn('f', [], [ret(n(1)), log(t('x'))]),
          ],
          [log(callN('f'))],
        ),
        ['S10w'],
      );
      expect(
        _module(
          [
            fn(
              'f',
              [p('k')],
              [
                iff(v('k'), [ret(n(1))], [ret(n(2))]),
                log(t('x')),
              ],
            ),
          ],
          [
            log(callN('f', [n(1)])),
          ],
        ),
        ['S10w'],
      );
    });

    test('“怎么走都返回了”从前往后看：返回后面跟着别的语句也算返回了', () {
      expect(lAlwaysReturns([ret(n(1)), log(t('x'))]), isTrue);
      expect(
        lAlwaysReturns([
          iff(yes, [ret(n(1))], [ret(n(2))]),
          log(t('x')),
        ]),
        isTrue,
      );
      expect(lAlwaysReturns([const LNote('注'), ret()]), isTrue);
      expect(lAlwaysReturns([log(t('x'))]), isFalse);
      expect(
        lAlwaysReturns([
          iff(yes, [ret(n(1))]),
        ]),
        isFalse,
      );
      expect(lAlwaysReturns([const LBreak(), ret(n(1))]), isFalse, reason: '跳出后面的不生成');
      expect(lAlwaysReturns(const []), isFalse);
    });
  });

  group('函数对外的样子（给调用积木定形状用）', () {
    final fa = analyzeFunctions([
      fn('say', [p('x')], [log(v('x'))]),
      fn('isBig', [p('x')], [ret(bin('>', v('x'), n(10)))]),
      fn('twice', [p('x'), p('times', or: 2)], [ret(bin('*', v('x'), v('times')))]),
      fn('name', [], [ret(t('甲'))]),
      fn(
        'either',
        [p('k')],
        [
          iff(v('k'), [ret(n(1))]),
          ret(t('二')),
        ],
      ),
      fn(
        'viaOther',
        [p('x')],
        [
          ret(callN('isBig', [v('x')])),
        ],
      ),
      fn('all', [p('xs', rest: true)], [ret(v('xs'))]),
      fn(
        'maybe',
        [p('k')],
        [
          iff(v('k'), [ret(nul)]),
          ret(n(1)),
        ],
      ),
    ]);
    LFuncInfo f(String name) => fa.functions[name]!;

    test('有没有返回值、返回类型', () {
      expect(f('say').returnsValue, isFalse);
      expect(f('say').returnType, LType.nul);
      expect(f('isBig').returnsValue, isTrue);
      expect(f('isBig').returnType, LType.boolean);
      expect(f('isBig').returnsBool, isTrue);
      expect(f('twice').returnType, LType.number);
      expect(f('twice').returnsBool, isFalse);
      expect(f('name').returnType, LType.text);
      expect(f('either').returnType, LType.any, reason: '有时数字有时文字：说不清');
      expect(f('viaOther').returnsBool, isTrue, reason: '返回的是另一个函数的结果：跟着它');
      expect(f('maybe').returnType, const LType(LKind.number, nullable: true));
    });

    test('接上外观模型：形状填“自动”时按它选', () {
      CustomBlockShape shape(String name) => resolveLookShape(CustomBlockShape.auto, hasValue: f(name).returnsValue, returnsBool: f(name).returnsBool);
      expect(shape('say'), CustomBlockShape.statement);
      expect(shape('isBig'), CustomBlockShape.boolean);
      expect(shape('twice'), CustomBlockShape.value);
    });

    test('参数个数', () {
      expect((f('say').minArgs, f('say').maxArgs), (1, 1));
      expect((f('twice').minArgs, f('twice').maxArgs), (1, 2));
      expect((f('all').minArgs, f('all').maxArgs), (0, -1));
    });

    test('调了谁、是不是递归的（带内联口的定义不许递归，第 3 阶段用）', () {
      final g = analyzeFunctions([
        fn('a', [], [ret(callN('b'))]),
        fn('b', [], [ret(callN('a'))]),
        fn(
          'self',
          [p('k')],
          [
            ret(callN('self', [v('k')])),
          ],
        ),
        fn('plain', [], [ret(callN('a'))]),
        fn('asValue', [], [ret(v('asValue'))]),
      ]).functions;
      expect(g['a']!.calls, {'b'});
      expect({for (final e in g.entries) e.key: e.value.recursive}, {'a': true, 'b': true, 'self': true, 'plain': false, 'asValue': true});
      expect(
        lRecursiveFunctions({
          'x': {'y'},
          'y': {'z'},
          'z': <String>{},
        }),
        isEmpty,
      );
    });
  });

  group('函数里用到了哪些宿主的东西（L15）', () {
    const req = LName('req', kind: LNameKind.host);
    final uses = fn('who', [], [
      ret(LNative('query', [req, t('name')])),
    ]);
    final inLambda = fn('later', [], [
      ret(lamx([], const LNative('header', [req, LLit('x')]))),
    ]);
    final clean = fn('clean', [p('x')], [ret(const LNative('nowText', []))]);

    test('命中：函数体里、里面的匿名函数里用了“这次请求”；有“会结束函数”的宿主语句', () {
      expect(_codes(analyzeFunctions([uses]).issues), ['L15']);
      expect(_codes(analyzeFunctions([inLambda]).issues), ['L15']);
      expect(
        _codes(
          analyzeFunctions([
            fn('send', [], [const LHost('返回响应', returns: true)]),
          ]).issues,
        ),
        ['L15'],
      );
      expect(analyzeFunctions([uses]).issues.single.message, allOf(contains('who'), contains('req'), contains('参数')));
    });

    test('不命中：只用了不带请求的宿主函数；宿主说可以用（hostAllowed）', () {
      expect(_codes(analyzeFunctions([clean]).issues), ['L14w']);
      expect(analyzeFunctions([uses], hostAllowed: true).issues, isEmpty);
    });

    test('信息本身：用到的宿主名字、宿主函数、有没有宿主语句', () {
      final f = analyzeFunctions([
        uses,
        inLambda,
        clean,
        fn('h', [], [const LHost('别的语句')]),
      ]).functions;
      expect(f['who']!.hostNames, {'req'});
      expect(f['who']!.natives, {'query'});
      expect(f['later']!.hostNames, {'req'});
      expect(f['clean']!.hostNames, isEmpty);
      expect(f['clean']!.natives, {'nowText'});
      expect(f['h']!.hostStmts, isTrue);
      expect(f['h']!.hostReturns, isFalse);
    });

    test('宿主语句用到的名字（inspect）：参数只在宿主语句里用到也算用到', () {
      final g = fn('viaHost', [p('x')], [const LHost('用 x')]);
      expect(_codes(analyzeFunctions([g]).issues), ['L14w']);
      expect(analyzeFunctions([g], inspect: (_) => const LHostUse(reads: {'x'})).issues, isEmpty);
    });

    test('宿主语句用到了函数里看不见的变量（接口的变量）：G03；看得见的、宿主语句自己新建的不报', () {
      final g = fn('viaHost', [p('x')], [const LHost('用 x 和 total')]);
      final bad = analyzeFunctions([g], inspect: (_) => const LHostUse(reads: {'x', 'total'}, writes: {'count'})).issues;
      expect(_codes(bad), ['G03', 'G03']);
      expect(bad.first.message, allOf(contains('viaHost'), contains('参数')));
      expect(
        analyzeFunctions(
          [g],
          outer: {'total'},
          inspect: (_) => const LHostUse(reads: {'x', 'total'}),
        ).issues,
        isEmpty,
      );
      expect(analyzeFunctions([g], inspect: (_) => const LHostUse(reads: {'x', 'tmp'}, declares: {'tmp'})).issues, isEmpty);
      // 接口体里（不是有名字的函数）：旧语句的名字归宿主自己的校验管，这里不报
      expect(analyzeBody([const LHost('用 total')], inspect: (_) => const LHostUse(reads: {'total'})).issues, isEmpty);
    });
  });

  test('任何输入都不抛异常：套得很深的匿名函数、空名字、参数表是空的', () {
    LExpr deep = n(1);
    for (var i = 0; i < 3000; i++) {
      deep = lamx([], deep);
    }
    expect(() => analyzeModule(LModule(body: [log(deep)])), returnsNormally);
    expect(
      () => analyzeFunctions([
        fn('', [p('')], [ret(v(''))]),
      ]),
      returnsNormally,
    );
    expect(() => analyzeFunctions(const []), returnsNormally);
  });
}
