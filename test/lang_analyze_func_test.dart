// 检查器里“函数”那一部分（积木第 4 版·第 2 阶段）：每条规则命中和不命中各一条；函数“有没有返回值 / 返回类型”的推断；
// “这段体里用到了哪些宿主的东西”。
import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/lang/lang.dart';

import 'support/lang_conformance.dart';

List<String> _codes(Iterable<LIssue> issues) => [for (final i in issues) '${i.code}${i.isError ? '' : 'w'}'];

/// 查一个模块，给出问题的规则号（警告带 w）。
List<String> _module(List<LDecl> decls, [List<LStmt> body = const []]) => _codes(analyzeModule(LModule(decls: decls, body: body)).issues);

LFuncDecl _id(String name) => fn(name, [p('x')], [ret(v('x'))]);

void main() {
  group('L01 调用的函数不存在', () {
    test('命中：没有这个函数；调的东西明摆着不是函数', () {
      expect(_module([], [run(callN('nope'))]), ['L01']);
      expect(
        _module(
          [_id('f')],
          [
            run(callN('f', [n(1)])),
            run(callN('g', [n(1)])),
          ],
        ),
        ['L01'],
      );
      expect(_module([], [run(call(n(5)))]), ['L01']);
      expect(_module([], [run(call(list()))]), ['L01']);
      expect(analyzeModule(LModule(body: [run(callN('nope'))])).issues.single.message, contains('nope'));
    });

    test('不命中：调有的函数、调排在后面的函数、调变量里的函数值、函数自己调自己', () {
      expect(
        _module(
          [_id('f')],
          [
            run(callN('f', [n(1)])),
          ],
        ),
        isEmpty,
      );
      expect(
        _module(
          [
            fn('a', [], [ret(callN('b'))]),
            fn('b', [], [ret(n(1))]),
          ],
          [log(callN('a'))],
        ),
        isEmpty,
      );
      expect(_module([], [let('g', lamx([], n(1))), log(call(v('g')))]), isEmpty);
      expect(
        _module(
          [
            fn(
              'loop',
              [p('k')],
              [
                iff(bin('>', v('k'), n(0)), [
                  ret(callN('loop', [bin('-', v('k'), n(1))])),
                ]),
                ret(n(0)),
              ],
            ),
          ],
          [
            log(callN('loop', [n(3)])),
          ],
        ),
        isEmpty,
      );
    });

    test('变量盖住了同名的函数：按变量算，不报', () {
      expect(
        _module(
          [_id('f')],
          [
            let('h', lamx([], n(1))),
            run(call(v('h'))),
            run(callN('f', [n(1)])),
          ],
        ),
        isEmpty,
      );
    });
  });

  group('L02 参数个数对不上', () {
    final decls = [
      fn('two', [p('a'), p('b', or: 1)], [ret(bin('+', v('a'), v('b')))]),
      fn(
        'many',
        [p('a'), p('more', rest: true)],
        [
          ret(rt('join', [v('a'), json(v('more'))])),
        ],
      ),
    ];
    test('命中：少给了没有默认值的、多给了', () {
      expect(
        _module(decls, [
          log(callN('two')),
          log(callN('many', [n(1)])),
        ]),
        ['L02'],
      );
      expect(
        _module(decls, [
          log(callN('two', [n(1), n(2), n(3)])),
          log(callN('many', [n(1)])),
        ]),
        ['L02'],
      );
      expect(
        _module(decls, [
          log(callN('many')),
          log(callN('two', [n(1)])),
        ]),
        ['L02'],
      );
      // 当场调的匿名函数也查
      expect(
        _module([], [
          log(call(lamx([p('a')], v('a')))),
        ]),
        ['L02'],
      );
      final message = analyzeModule(
        LModule(
          decls: decls,
          body: [
            log(callN('two')),
            log(callN('many', [n(1)])),
          ],
        ),
      ).issues.single.message;
      expect(message, allOf(contains('two'), contains('1 到 2 个'), contains('给了 0 个')));
    });

    test('不命中：正好、少给有默认值的、“剩下的全收”给多少都行', () {
      expect(
        _module(decls, [
          log(callN('two', [n(1)])),
          log(callN('two', [n(1), n(2)])),
          log(callN('many', [n(1)])),
          log(callN('many', [n(1), n(2), n(3), n(4)])),
        ]),
        isEmpty,
      );
      expect(
        _module([], [
          log(call(lamx([p('a')], v('a')), [n(1)])),
        ]),
        isEmpty,
      );
    });

    test('命中：参数表本身不对——“剩下的全收”不在最后、带默认值；没有默认值的排在有默认值的后面', () {
      expect(
        _module(
          [
            fn(
              'f',
              [p('xs', rest: true), p('a')],
              [
                ret(rt('join', [v('xs'), v('a')])),
              ],
            ),
          ],
          [
            log(callN('f', [n(1)])),
          ],
        ),
        ['L02'],
      );
      expect(
        _module(
          [
            fn(
              'f',
              [p('a', or: 1), p('b')],
              [
                ret(rt('join', [v('a'), v('b')])),
              ],
            ),
          ],
          [
            log(callN('f', [n(1), n(2)])),
          ],
        ),
        ['L02'],
      );
      expect(
        _module(
          [
            fn('f', [const LParam('xs', rest: true, defaultValue: LLit(1))], [ret(v('xs'))]),
          ],
          [log(callN('f'))],
        ),
        ['L02'],
      );
    });
  });

  group('L03 “返回”不在函数里 / 把没有返回值的函数当值用', () {
    test('错误命中：“启动时”里的返回；不命中：函数里、匿名函数里的返回', () {
      expect(_module([], [ret(n(1))]), ['L03']);
      expect(
        _module(
          [_id('f')],
          [
            log(callN('f', [n(1)])),
          ],
        ),
        isEmpty,
      );
      expect(
        _module([], [
          let('g', lam([], [ret(n(1))])),
          log(call(v('g'))),
        ]),
        isEmpty,
      );
      expect(_codes(analyzeBody([ret()], inFunction: false).issues), ['L03']);
    });

    test('警告命中：没有返回值的函数被当成值；不命中：单独成一句、有返回值的', () {
      final decls = [
        fn('say', [p('x')], [log(v('x'))]),
        _id('same'),
      ];
      expect(
        _module(decls, [
          log(callN('say', [n(1)])),
          log(callN('same', [n(1)])),
        ]),
        ['L03w'],
      );
      expect(
        _module(decls, [
          let('r', callN('say', [n(1)])),
          log(callN('same', [v('r')])),
        ]),
        ['L03w'],
      );
      expect(
        _module(decls, [
          run(callN('say', [n(1)])),
          log(callN('same', [n(1)])),
        ]),
        isEmpty,
      );
      // 只有不带值的“返回”：也算没有返回值
      expect(
        _module(
          [
            fn('quit', [], [ret()]),
          ],
          [log(callN('quit'))],
        ),
        ['L03w'],
      );
    });
  });

  group('L09 重名', () {
    test('命中：函数重名、函数和模块级变量重名、只差大小写、参数重名、匿名函数的参数重名', () {
      expect(
        _module(
          [_id('f'), _id('f')],
          [
            log(callN('f', [n(1)])),
          ],
        ),
        ['L09'],
      );
      expect(_module([LVarDecl('f', n(1)), _id('f')], [log(v('f'))]), contains('L09'));
      expect(
        _module(
          [_id('Save'), _id('save')],
          [
            log(callN('save', [n(1)])),
            log(callN('Save', [n(1)])),
          ],
        ),
        ['L09'],
      );
      expect(
        _module(
          [
            fn('f', [p('a'), p('a')], [ret(v('a'))]),
          ],
          [
            log(callN('f', [n(1), n(2)])),
          ],
        ),
        ['L09'],
      );
      expect(
        _module([], [
          let('g', lamx([p('a'), p('a')], v('a'))),
          log(v('g')),
        ]),
        ['L09'],
      );
    });

    test('命中：函数里新建了和参数同名的变量；同一个函数里新建两次；先当外面的用了又新建同名的', () {
      expect(
        _module(
          [
            fn('f', [p('a')], [let('a', n(1)), ret(v('a'))]),
          ],
          [
            log(callN('f', [n(1)])),
          ],
        ),
        ['L09'],
      );
      expect(
        _module(
          [
            fn('f', [], [let('a', n(1)), let('a', n(2)), ret(v('a'))]),
          ],
          [log(callN('f'))],
        ),
        ['L09'],
      );
      expect(
        _module(
          [
            LVarDecl('total', n(0)),
            fn('f', [], [set('total', n(1)), let('total', n(2)), ret(v('total'))]),
          ],
          [log(callN('f'))],
        ),
        ['L09'],
      );
    });

    test('不命中：两个函数各有同名的参数 / 变量；函数里的变量盖住模块级的；匿名函数的参数盖住外面的变量', () {
      expect(
        _module(
          [
            fn('f', [p('a')], [let('t', v('a')), ret(v('t'))]),
            fn('g', [p('a')], [let('t', v('a')), ret(v('t'))]),
          ],
          [
            log(callN('f', [n(1)])),
            log(callN('g', [n(1)])),
          ],
        ),
        isEmpty,
      );
      expect(
        _module(
          [
            LVarDecl('total', n(0)),
            fn('f', [], [let('total', n(2)), ret(v('total'))]),
          ],
          [log(callN('f')), log(v('total'))],
        ),
        isEmpty,
      );
      expect(
        _module([], [
          let('x', n(1)),
          let('g', lamx([p('x')], v('x'))),
          log(call(v('g'), [v('x')])),
        ]),
        isEmpty,
      );
    });
  });

  group('L11 常量', () {
    test('命中：函数里、匿名函数里改模块级 / 外层的常量；不命中：改变量', () {
      expect(
        _module(
          [
            const LVarDecl('k', LLit(1), isConst: true),
            fn('f', [], [set('k', n(2))]),
          ],
          [run(callN('f')), log(v('k'))],
        ),
        ['L11'],
      );
      expect(
        _module([], [
          let('k', n(1), isConst: true),
          let('g', lam([], [set('k', n(2))])),
          run(call(v('g'))),
          log(v('k')),
        ]),
        ['L11'],
      );
      expect(
        _module(
          [
            LVarDecl('k', n(1)),
            fn('f', [], [set('k', n(2))]),
          ],
          [run(callN('f')), log(v('k'))],
        ),
        isEmpty,
      );
    });
  });

  group('L14 定义了没人用的函数 / 参数（警告）', () {
    test('命中：没人调的函数；只有自己调自己的也算没人用；没用到的参数', () {
      expect(_module([_id('f')]), ['L14w']);
      expect(
        _module([
          fn(
            'f',
            [p('k')],
            [
              ret(callN('f', [v('k')])),
            ],
          ),
        ]),
        ['L14w'],
      );
      expect(
        _module(
          [
            fn('f', [p('a'), p('b')], [ret(v('a'))]),
          ],
          [
            log(callN('f', [n(1), n(2)])),
          ],
        ),
        ['L14w'],
      );
      expect(
        _module([], [
          let('g', lamx([p('a')], n(1))),
          log(call(v('g'), [n(1)])),
        ]),
        ['L14w'],
      );
      expect(analyzeModule(LModule(decls: [_id('f')])).issues.single.message, contains('f'));
    });

    test('不命中：被调用、被当成值、被别的函数用；参数在里层的匿名函数里用到、被赋值也算用到', () {
      expect(
        _module(
          [_id('f')],
          [
            log(callN('f', [n(1)])),
          ],
        ),
        isEmpty,
      );
      expect(
        _module(
          [_id('f')],
          [
            let('g', v('f')),
            log(call(v('g'), [n(1)])),
          ],
        ),
        isEmpty,
      );
      expect(
        _module(
          [
            _id('f'),
            fn('g', [], [
              ret(callN('f', [n(1)])),
            ]),
          ],
          [log(callN('g'))],
        ),
        isEmpty,
      );
      expect(
        _module(
          [
            fn('f', [p('a')], [ret(lamx([], v('a')))]),
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
            fn('f', [p('a')], [set('a', n(1)), ret(n(2))]),
          ],
          [
            log(callN('f', [n(1)])),
          ],
        ),
        isEmpty,
      );
    });

    test('宿主（后端）自己说别处用了哪些函数：unusedIssues', () {
      final fa = analyzeFunctions([_id('f'), _id('g')]);
      expect(fa.issues, isEmpty);
      expect(_codes(fa.unusedIssues(const {})), ['L14w', 'L14w']);
      expect(
        [
          for (final i in fa.unusedIssues(const {'f'})) i.message,
        ],
        [contains('g')],
      );
      expect(fa.unusedIssues(const {'f', 'g'}), isEmpty);
      // 接口体里用到了哪些函数：analyzeBody 给
      final body = analyzeBody(
        [
          log(callN('f', [n(1)])),
        ],
        functions: [_id('f'), _id('g')],
        signatures: fa.signatures,
      );
      expect(body.issues, isEmpty);
      expect(body.usedFunctions, {'f'});
    });
  });
}
