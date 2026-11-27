// 一键修真的改语法树（lib/lang/type_fix.dart）：十三种修法每种来一个会报错的小程序，
// 拿检查器自己给的修法去改，改完再查一遍——原来那条问题得没了，而且没有冒出新的错。
import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/lang/lang.dart';
import 'package:lopicode/lang/type_fix.dart';

const _int = LType.integer;
const _txt = LType.text;

LFuncDecl _fn(String name, LType param, [LType? returns]) => LFuncDecl(name, [LParam('x', type: param)], [const LReturn(LName('x'))], type: returns);

LStmt _call(String fn, LExpr arg) => LExprStmt(LCall(LName(fn), [arg]));

final List<LDecl> _types = [
  const LRecordDecl('点', [LTypedField('x', _int), LTypedField('y', _int), LTypedField('名', _txt)]),
  const LVariantDecl('形状', [
    LVariantCase('圆', [LTypedField('r', _int)]),
    LVariantCase('方', [LTypedField('a', _int)]),
    LVariantCase('无'),
  ]),
];

/// 找到带这种修法的那条问题，修，再查。返回（修之前那条问题，修好的模块，修之后的结果）。
(LTypeIssue, LModule, LTypeResult) fixOnce(LModule m, LFixKind kind, {LExpr? fill}) {
  final before = checkModuleTypes(m);
  final issue = before.issues.firstWhere((i) => i.fixes.any((f) => f.kind == kind), orElse: () => fail('没有带 ${kind.name} 的问题：${before.issues}'));
  final fix = issue.fixes.firstWhere((f) => f.kind == kind);
  final next = lApplyFix(m, fix, types: before, fill: fill);
  expect(next, isNotNull, reason: '${kind.name} 没改成');
  return (issue, next!, checkModuleTypes(next));
}

void main() {
  final cases = <LFixKind, (String code, LModule Function() build)>{
    LFixKind.wrapToText: ('T01', () => LModule(decls: [_fn('喊', _txt)], body: [_call('喊', const LLit(3))])),
    LFixKind.wrapToInt: ('T01', () => LModule(decls: [_fn('数', _int)], body: [_call('数', const LLit(2.5))])),
    LFixKind.wrapParseInt: ('T01', () => LModule(decls: [_fn('数', _int)], body: [_call('数', const LLit('12'))])),
    LFixKind.wrapOrElse: (
      'T02',
      () => LModule(
        decls: [_fn('数', _int)],
        body: [
          const LLet('n', LRt('parseInt', [LLit('7')])),
          _call('数', const LName('n')),
        ],
      ),
    ),
    LFixKind.wrapMust: (
      'T02',
      () => LModule(
        decls: [_fn('数', _int)],
        body: [
          const LLet('n', LRt('parseInt', [LLit('7')])),
          _call('数', const LName('n')),
        ],
      ),
    ),
    LFixKind.compareNotZero: (
      'T09',
      () => const LModule(
        body: [
          LLet('n', LLit(1)),
          LIf([LIfArm(LName('n'), [])]),
        ],
      ),
    ),
    LFixKind.addMatchCases: (
      'T03',
      () => LModule(
        decls: _types,
        body: [
          const LLet('s', LVariantNew('形状', '圆', [LLit(1)])),
          const LMatch(LName('s'), [
            LMatchArm('圆', ['r'], []),
          ]),
        ],
      ),
    ),
    LFixKind.addMatchElse: (
      'T03',
      () => LModule(
        decls: _types,
        body: [
          const LLet('s', LVariantNew('形状', '圆', [LLit(1)])),
          const LMatch(LName('s'), [
            LMatchArm('圆', ['r'], []),
          ]),
        ],
      ),
    ),
    LFixKind.addRecordFields: (
      'T04',
      () => LModule(
        decls: _types,
        body: [
          const LLet('p', LRecordNew('点', [LFieldInit('x', LLit(1))])),
        ],
      ),
    ),
    LFixKind.removeRecordField: (
      'T04',
      () => LModule(
        decls: _types,
        body: [
          const LLet('p', LRecordNew('点', [LFieldInit('x', LLit(1)), LFieldInit('y', LLit(2)), LFieldInit('名', LLit('a')), LFieldInit('多的', LLit(0))])),
        ],
      ),
    ),
    LFixKind.useRecordCopy: (
      'T10',
      () => LModule(
        decls: _types,
        body: [
          const LLet('p', LRecordNew('点', [LFieldInit('x', LLit(1)), LFieldInit('y', LLit(2)), LFieldInit('名', LLit('a'))])),
          const LAssign(LTField(LName('p'), 'x'), LLit(5)),
        ],
      ),
    ),
    // 核心 3 加的两种。
    LFixKind.dropAwait: ('T31', () => const LModule(body: [LLet('n', LAwait(LLit(1)))])),
    LFixKind.wrapSpawn: (
      'T29',
      () => const LModule(
        decls: [
          LNativeDecl('time.sleep', [LParam('毫秒', type: _int)], type: LType.nul),
          LFuncDecl('快', [], [
            LExprStmt(LNative('time.sleep', [LLit(1)])),
          ], noWait: true),
        ],
        body: [LExprStmt(LCall(LName('快'), []))],
      ),
    ),
  };

  test('十三种修法一种不少', () => expect(cases.keys.toSet(), LFixKind.values.toSet()));

  for (final MapEntry(key: kind, value: (code, build)) in cases.entries) {
    test('${kind.name}：修完 $code 那条没了，也没有新的错', () {
      final m = build();
      final (issue, next, after) = fixOnce(m, kind);
      expect(issue.code, code);
      expect(after.issues.where((i) => i.code == code && i.message == issue.message), isEmpty, reason: '${after.issues}');
      if (kind == LFixKind.wrapParseInt) {
        // 设计如此：变成整数“变不了就是空”，所以修完换成一条“可能是空”（T02），再点一次“是空就用 …”才干净。
        expect([for (final i in after.errors) i.code], ['T02']);
        expect(fixOnce(next, LFixKind.wrapOrElse).$3.errors, isEmpty);
      } else {
        expect(after.errors, isEmpty, reason: '${after.issues}');
      }
      expect(identical(next, m), isFalse);
      // 原来那棵树没被动过：再查一遍还是原来的问题。
      expect(checkModuleTypes(m).issues.map((i) => i.toString()), contains(issue.toString()));
    });
  }

  test('修出来的样子：包一层 / 补上 / 换写法', () {
    LStmt last(LFixKind k) => fixOnce(cases[k]!.$2(), k).$2.body.last;
    LExpr arg(LFixKind k) => ((last(k) as LExprStmt).expr as LCall).args.single;
    expect(arg(LFixKind.wrapToText), isA<LRt>().having((r) => r.fn, 'fn', 'toText'));
    expect(arg(LFixKind.wrapToInt), isA<LRt>().having((r) => r.fn, 'fn', 'toInt'));
    expect(arg(LFixKind.wrapParseInt), isA<LRt>().having((r) => r.fn, 'fn', 'parseInt'));
    expect(arg(LFixKind.wrapMust), isA<LRt>().having((r) => r.fn, 'fn', 'must'));
    // “是空就用 ▢”：▢ 里照类型先放 0。
    final orElse = arg(LFixKind.wrapOrElse) as LRt;
    expect(orElse.fn, 'orElse');
    expect((orElse.args[1] as LLit).value, 0);
    final cond = (last(LFixKind.compareNotZero) as LIf).arms.single.cond as LBinary;
    expect((cond.op, (cond.r as LLit).value), ('!=', 0));
    final cases3 = last(LFixKind.addMatchCases) as LMatch;
    expect([for (final a in cases3.arms) a.caseName], ['圆', '方', '无']);
    expect(cases3.orElse, isNull);
    final other = last(LFixKind.addMatchElse) as LMatch;
    expect(other.arms.length, 1);
    expect(other.orElse, isEmpty);
    final filled = (last(LFixKind.addRecordFields) as LLet).value as LRecordNew;
    expect({for (final f in filled.fields) f.name: (f.value as LLit).value}, {'x': 1, 'y': 0, '名': ''});
    final cut = (last(LFixKind.removeRecordField) as LLet).value as LRecordNew;
    expect([for (final f in cut.fields) f.name], ['x', 'y', '名']);
    final copy = last(LFixKind.useRecordCopy) as LAssign;
    expect((copy.target as LTName).name, 'p');
    final rc = copy.value as LRecordCopy;
    expect(((rc.of as LName).name, rc.fields.single.name, (rc.fields.single.value as LLit).value), ('p', 'x', 5));
  });

  test('“是空就用”可以自己给后面那个值', () {
    final (_, next, after) = fixOnce(cases[LFixKind.wrapOrElse]!.$2(), LFixKind.wrapOrElse, fill: const LLit(42));
    final r = ((next.body.last as LExprStmt).expr as LCall).args.single as LRt;
    expect((r.args[1] as LLit).value, 42);
    expect(after.errors, isEmpty);
  });

  test('目标在函数里、套在别的式子里也找得到；别的节点还是原来的对象', () {
    const keep = LLet('别的', LLit(1));
    final m = LModule(
      decls: [
        _fn('喊', _txt),
        const LFuncDecl('外', [], [
          keep,
          LIf([
            LIfArm(LLit(true), [
              LExprStmt(
                LListLit([
                  LCall(LName('喊'), [LLit(3)]),
                ]),
              ),
            ]),
          ]),
        ]),
      ],
    );
    final (_, next, after) = fixOnce(m, LFixKind.wrapToText);
    expect(after.errors, isEmpty);
    final outer = next.decls[1] as LFuncDecl;
    expect(identical(outer.body.first, keep), isTrue);
    expect(identical(next.decls.first, m.decls.first), isTrue);
  });

  test('做不了就返回 null，什么都不改', () {
    const m = LModule(body: [LLet('n', LLit(1))]);
    // 目标不在这个模块里。
    expect(lApplyFix(m, const LFix(LFixKind.wrapToText, '变成文字', target: LLit(9))), isNull);
    // 没有目标。
    expect(lApplyFix(m, const LFix(LFixKind.wrapToText, '变成文字')), isNull);
    // 种类和目标对不上。
    final let = m.body.single;
    expect(lApplyFix(m, LFix(LFixKind.addMatchElse, '加一个“其他情况”', target: let)), isNull);
    expect(lApplyFix(m, LFix(LFixKind.useRecordCopy, '换成“复制并改”', target: let)), isNull);
    expect(lApplyFix(m, LFix(LFixKind.wrapToText, '变成文字', target: let)), isNull);
  });
}
