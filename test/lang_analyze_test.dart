// 语言核心的检查：名字与作用域（设计稿 3.2）、类型推断（4.3 第一步）、规则 G03 / L03 / L04 / L09 / L11 / L13 / S10。
// 检查是纯函数，再怪的输入也不抛异常。
import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/lang/lang.dart';

import 'support/lang_conformance.dart';

List<String> _codes(List<LStmt> body, {Set<String> outer = const {}, Set<String> outerConsts = const {}, bool inFunction = true}) => [
  for (final i in analyzeBody(body, outer: outer, outerConsts: outerConsts, inFunction: inFunction).issues) i.code,
];

void main() {
  group('名字与作用域', () {
    test('没有问题的程序：零条问题；新建的名字按先后列出来（生成器据此在函数开头声明）', () {
      final a = analyzeBody([
        let('x', n(1)),
        LForCount('i', n(1), n(3), n(1), [let('inner', v('i'))]),
        LForEach(list(), 'item', index: 'k', [log(v('k'))]),
        LForPairs(dict(), 'key', 'value', []),
        set('x', v('inner')),
      ]);
      expect(a.issues, isEmpty);
      expect(a.hasErrors, isFalse);
      expect(a.declared, ['x', 'i', 'inner', 'item', 'k', 'key', 'value']);
    });

    test('没有块级作用域：在“如果”/ 循环里新建的变量，出来以后还看得见', () {
      expect(
        _codes([
          iff(yes, [let('a', n(1))], [let('b', n(2))]),
          LRepeat(n(2), [let('c', n(3))]),
          log(rt('join', [v('a'), v('b'), v('c')])),
        ]),
        isEmpty,
      );
    });

    test('G03：用了还没新建的变量（读、写、先用后建）', () {
      expect(_codes([log(v('nope'))]), ['G03']);
      expect(_codes([set('nope', n(1))]), ['G03']);
      expect(_codes([log(v('later')), let('later', n(1))]), ['G03']);
      final issue = analyzeBody(const [LExprStmt(LName('nope', src: LSrc(block: 'b7')))]).issues.single;
      expect(issue.isError, isTrue);
      expect(issue.message, contains('nope'));
      expect(issue.src?.block, 'b7', reason: '问题要能指回是哪块积木');
    });

    test('G03：循环变量出了循环就看不见（设计稿 3.2），同名的可以在下一个循环里再用', () {
      expect(_codes([LForCount('i', n(1), n(2), n(1), []), log(v('i'))]), ['G03']);
      expect(_codes([LForEach(list(), 'x', index: 'k', []), log(v('x')), log(v('k'))]), ['G03', 'G03']);
      expect(_codes([LForPairs(dict(), 'k', 'val', []), set('k', n(1))]), ['G03']);
      expect(
        _codes([
          LForCount('i', n(1), n(2), n(1), []),
          LForCount('i', n(1), n(2), n(1), [log(v('i'))]),
        ]),
        isEmpty,
      );
    });

    test('外面（模块级）的名字看得见；外面的常量不能改', () {
      expect(_codes([log(v('g')), set('g', n(1))], outer: {'g'}), isEmpty);
      expect(_codes([set('g', n(1))], outer: {'g'}, outerConsts: {'g'}), ['L11']);
      final a = analyzeBody([set('g', n(1))], outer: {'g'});
      expect(a.declared, isEmpty, reason: '外面的名字不归这个函数声明');
    });

    test('L09：同一层重名（变量和变量、循环变量和变量、套着的循环用同一个名字、一个循环的两个变量同名）', () {
      expect(_codes([let('x', n(1)), let('x', n(2))]), ['L09']);
      expect(
        _codes([
          let('x', n(1)),
          iff(yes, [let('x', n(2))]),
        ]),
        ['L09'],
        reason: '没有块级：如果里面的也算同一层',
      );
      expect(_codes([let('i', n(0)), LForCount('i', n(1), n(2), n(1), [])]), ['L09']);
      expect(
        _codes([
          LForCount('i', n(1), n(2), n(1), [LForCount('i', n(1), n(2), n(1), [])]),
        ]),
        ['L09'],
      );
      expect(_codes([LForPairs(dict(), 'k', 'k', [])]), ['L09']);
      expect(_codes([LForEach(list(), 'x', index: 'x', [])]), ['L09']);
      expect(_codes([let('g', n(1))], outer: {'g'}), ['L09'], reason: '和外面的名字重了也算');
      expect(
        _codes([
          LForCount('i', n(1), n(2), n(1), [let('i', n(5))]),
        ]),
        ['L09'],
      );
    });

    test('L11：给常量赋值是错误；读常量、改常量列表里的项不算', () {
      expect(_codes([let('c', n(1), isConst: true), set('c', n(2))]), ['L11']);
      expect(_codes([let('c', n(1), isConst: true), log(v('c'))]), isEmpty);
      expect(
        _codes([
          let('c', list(), isConst: true),
          setAt(v('c'), n(0), n(1)),
          run(rt('listPush', [v('c'), n(1)])),
        ]),
        isEmpty,
      );
      expect(_codes([let('c', list(), isConst: true), LForEach(list(), 'c', reuse: true, [])]), ['L11'], reason: '把每一项赋给常量也是改它');
      final issue = analyzeBody([let('PI', n(3.14), isConst: true), set('PI', n(3))]).issues.single;
      expect(issue.isError, isTrue);
      expect(issue.message, contains('PI'));
    });

    test('临时名、宿主的名字不参加名字检查', () {
      expect(
        _codes([
          const LLet('t1', LLit(1), kind: LNameKind.temp),
          const LLet('t1', LLit(2), kind: LNameKind.temp),
          log(const LName('t1', kind: LNameKind.temp)),
          log(const LName('req', kind: LNameKind.host)),
        ]),
        isEmpty,
      );
      expect(_codes(lSwitch('s', n(1), [LIfArm(n(1), [])])), isEmpty, reason: '“分情况”的临时值不占变量名');
    });
  });

  group('控制流的规则', () {
    test('L04：“跳出”/“跳过”不在循环里是错误；在五种循环里都行；隔着“如果”也行', () {
      expect(_codes([const LBreak()]), ['L04']);
      expect(_codes([const LContinue()]), ['L04']);
      expect(
        _codes([
          iff(yes, [const LBreak()]),
        ]),
        ['L04'],
      );
      for (final loop in <LStmt Function(List<LStmt>)>[
        (b) => LWhile(v('go'), b),
        (b) => LRepeat(n(2), b),
        (b) => LForCount('i', n(1), n(2), n(1), b),
        (b) => LForEach(list(), 'x', b),
        (b) => LForPairs(dict(), 'k', 'val', b),
      ]) {
        expect(
          _codes([
            let('go', yes),
            loop([
              iff(yes, [const LBreak()], [const LContinue()]),
            ]),
          ]),
          isEmpty,
        );
      }
      expect(_codes([LRepeat(n(1), []), const LBreak()]), ['L04'], reason: '循环后面的不算在循环里');
      expect(analyzeBody([const LBreak()]).issues.single.message, contains('跳出循环'));
      expect(analyzeBody([const LContinue()]).issues.single.message, contains('跳过这一轮'));
    });

    test('L13：可能的死循环是警告——“一直重复”或条件写死成“是”，里面又没有出路', () {
      final a = analyzeBody([const LWhile(null, [])]);
      expect([for (final i in a.issues) i.code], ['L13']);
      expect(a.issues.single.isError, isFalse);
      expect(a.hasErrors, isFalse);
      expect(
        _codes([
          LWhile(yes, [log(n(1))]),
        ]),
        ['L13'],
      );
      expect(_codes([LWhile(n(1), [])]), ['L13']);
      expect(_codes([LWhile(t('x'), [])]), ['L13']);
      // 有出路：本层的跳出、返回（哪一层都行）、藏在“如果”里的
      expect(
        _codes([
          const LWhile(null, [LBreak()]),
        ]),
        isEmpty,
      );
      expect(
        _codes([
          const LWhile(null, [LReturn(null)]),
        ]),
        isEmpty,
      );
      expect(
        _codes(
          [
            LWhile(null, [
              iff(v('x'), [const LBreak()]),
            ]),
          ],
          outer: {'x'},
        ),
        isEmpty,
      );
      expect(
        _codes([
          const LWhile(null, [
            LRepeat(LLit(2), [LReturn(null)]),
          ]),
        ]),
        isEmpty,
      );
      // 里面那层循环的“跳出”出不了外面这层
      expect(
        _codes([
          const LWhile(null, [
            LRepeat(LLit(2), [LBreak()]),
          ]),
        ]),
        ['L13'],
      );
      // 条件不是写死的：说不准，不报
      expect(_codes([LWhile(v('x'), [])], outer: {'x'}), isEmpty);
      expect(_codes(const [LWhile(no, [])]), isEmpty);
      expect(
        _codes([
          const LWhile(null, [LHost('返回响应', returns: true)]),
        ]),
        isEmpty,
        reason: '宿主的“返回响应”也是出路',
      );
    });

    test('S10：返回 / 跳出 / 跳过后面还有语句是警告，一串只报一次，注释不算', () {
      final a = analyzeBody([const LReturn(null), log(n(1)), log(n(2))]);
      expect([for (final i in a.issues) i.code], ['S10']);
      expect(a.issues.single.isError, isFalse);
      expect(
        _codes([
          LRepeat(n(1), [const LBreak(), log(n(1))]),
        ]),
        ['S10'],
      );
      expect(
        _codes([
          LRepeat(n(1), [const LContinue(), log(n(1))]),
        ]),
        ['S10'],
      );
      expect(_codes([const LReturn(null), const LNote('只是注释')]), isEmpty);
      expect(_codes([const LThrow(LLit('出错')), log(n(1))]), ['S10']);
      expect(_codes([const LHost('x', returns: true), log(n(1))]), ['S10']);
      // “如果”里返回了，外面后面的照常执行
      expect(
        _codes([
          iff(yes, [const LReturn(null)]),
          log(n(1)),
        ]),
        isEmpty,
      );
    });

    test('L03：“返回”不在函数里（模块最外层）是错误', () {
      expect(_codes([const LReturn(null)], inFunction: false), ['L03']);
      expect(_codes([const LReturn(null)]), isEmpty);
      expect(
        [
          for (final i in analyzeModule(const LModule(body: [LReturn(null)])).issues) i.code,
        ],
        ['L03'],
      );
    });
  });

  group('模块', () {
    test('模块级变量：函数体看得见；重名 L09；模块级常量不能改 L11', () {
      const ok = LModule(
        decls: [LVarDecl('g', LLit(1)), LVarDecl('K', LLit(2), isConst: true)],
        body: [
          LExprStmt(LRt('log', [LName('g')])),
        ],
      );
      expect(analyzeModule(ok).issues, isEmpty);
      const dup = LModule(decls: [LVarDecl('g', LLit(1)), LVarDecl('g', LLit(2))]);
      expect([for (final i in analyzeModule(dup).issues) i.code], ['L09']);
      const write = LModule(decls: [LVarDecl('K', LLit(2), isConst: true)], body: [LAssign(LTName('K'), LLit(3))]);
      expect([for (final i in analyzeModule(write).issues) i.code], ['L11']);
      const init = LModule(decls: [LVarDecl('a', LName('nope'))]);
      expect([for (final i in analyzeModule(init).issues) i.code], ['G03'], reason: '初值里用的名字也要查');
    });
  });

  group('类型推断（只用于校验；生成时一律按“任意”）', () {
    test('字面量、运算、小库函数的结果类型', () {
      final exprs = <LExpr, LType>{
        n(1): LType.number,
        t('a'): LType.text,
        yes: LType.boolean,
        nul: LType.nul,
        bin('+', n(1), t('2')): LType.number,
        bin('==', n(1), n(2)): LType.boolean,
        bin('**', n(1), n(2)): LType.number,
        LUnary('not', n(1)): LType.boolean,
        LUnary('neg', n(1)): LType.number,
        LLogic('and', n(1), n(2)): LType.boolean,
        rt('upper', [t('a')]): LType.text,
        rt('contains', [t('a'), t('a')]): LType.boolean,
        rt('dictKeys', [dict()]): LType.list,
        rt('dictMerge', [dict(), dict()]): LType.dict,
        rt('listGet', [list(), n(0)]): LType.any,
        rt('没有这个函数'): LType.any,
        LCond(yes, n(1), n(2)): LType.number,
        LCond(yes, n(1), t('a')): LType.any,
        const LNative('whatever', []): LType.any,
      };
      final a = analyzeBody([for (final e in exprs.keys) run(e)]);
      for (final e in exprs.entries) {
        expect(a.typeOf(e.key), e.value, reason: '${e.key.runtimeType}');
      }
    });

    test('列表 / 字典带着元素类型；元素不一样就是“任意”；可以是空', () {
      final same = list([n(1), n(2)]);
      final mixed = list([n(1), t('a')]);
      final withNull = list([n(1), nul]);
      final d = dict({'a': t('x')});
      final idx = at(same, n(0));
      final a = analyzeBody([run(same), run(mixed), run(withNull), run(d), run(idx), run(list())]);
      expect(a.typeOf(same), const LType(LKind.list, of: LType.number));
      expect(a.typeOf(mixed), const LType(LKind.list, of: LType.any));
      expect(a.typeOf(withNull), const LType(LKind.list, of: LType(LKind.number, nullable: true)));
      expect(a.typeOf(d), const LType(LKind.dict, of: LType.text));
      expect(a.typeOf(idx), LType.number);
    });

    test('变量的类型：各处赋的值合起来；循环变量；节点自己标了类型就用标的', () {
      final a = analyzeBody([
        let('x', n(1)),
        set('x', n(2)),
        let('y', n(1)),
        set('y', t('变了')),
        let('z', nul),
        set('z', t('后来有了')),
        LForCount('i', n(1), n(2), n(1), []),
        LForEach(list([t('a')]), 'item', index: 'k', []),
        LForPairs(dict({'a': n(1)}), 'key', 'val', []),
        const LLet('marked', LLit(1), type: LType.text),
      ]);
      expect(a.variableTypes['x'], LType.number);
      expect(a.variableTypes['y'], LType.any);
      expect(a.variableTypes['z'], const LType(LKind.text, nullable: true));
      expect(a.variableTypes['i'], LType.number);
      expect(a.variableTypes['item'], LType.text);
      expect(a.variableTypes['k'], LType.number);
      expect(a.variableTypes['key'], LType.text);
      expect(a.variableTypes['val'], LType.number);
      expect(a.variableTypes['marked'], LType.text);
    });

    test('后面才赋的类型也算进来（两遍）：读变量时拿到的是合起来以后的类型', () {
      final read = v('x');
      final a = analyzeBody([let('x', n(1)), run(read), set('x', t('a'))]);
      expect(a.typeOf(read), LType.any);
      final read2 = v('w');
      final b = analyzeBody([let('w', n(1)), run(read2), set('w', n(2))]);
      expect(b.typeOf(read2), LType.number);
    });

    test('LType：合并与“确定对不上”', () {
      expect(LType.number.join(LType.number), LType.number);
      expect(LType.number.join(LType.text), LType.any);
      expect(LType.nul.join(LType.nul), LType.nul);
      expect(LType.number.clashesWith(LType.text), isTrue);
      expect(LType.number.clashesWith(LType.any), isFalse);
      expect(LType.number.clashesWith(LType.nul), isFalse);
      expect(LType.number.clashesWith(LType.number), isFalse);
    });
  });

  group('不抛异常', () {
    test('空的、缺东西的、还没实现的节点、套得很深的：都只给结果', () {
      expect(analyzeBody(const []).issues, isEmpty);
      expect(analyzeModule(const LModule()).issues, isEmpty);
      expect(
        () => analyzeBody([
          const LIf([]),
          const LTry([]),
          const LThrow(LLit('x')),
          run(const LLambda([], [])),
          run(const LThis()),
          run(const LCall(LName('f', kind: LNameKind.host), [])),
          run(const LNew('C', [])),
          run(const LAwait(LLit(1))),
          run(const LSpawn([])),
        ]),
        returnsNormally,
      );
      LExpr deep = n(1);
      for (var i = 0; i < 3000; i++) {
        deep = LUnary('neg', deep);
      }
      List<LStmt> nest = [log(deep)];
      for (var i = 0; i < 3000; i++) {
        nest = [LRepeat(n(1), nest)];
      }
      late LangAnalysis a;
      expect(() => a = analyzeBody(nest), returnsNormally);
      expect(a.issues.where((i) => i.isError && i.code != 'G07'), isEmpty);
      expect(() => analyzeBody([run(bin('没有这个运算', n(1), n(2))), run(LUnary('??', n(1)))]), returnsNormally);
    });
  });
}
