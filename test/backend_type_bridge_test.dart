// 规矩版本 2 的文档：类型问题能不能对回到积木的那一格上（lib/backend/backend_type_bridge.dart），
// 一键修落到积木文档上以后问题是不是真的消失（lib/backend/backend_type_fix.dart）。
import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/backend/backend_model.dart';
import 'package:lopicode/backend/backend_type_bridge.dart';
import 'package:lopicode/backend/backend_type_fix.dart';
import 'package:lopicode/lang/lang.dart';
import 'package:lopicode/lowcode/logic_expr.dart';
import 'package:lopicode/lowcode/logic_model.dart';

import 'support/backend_func_blocks.dart';
import 'support/backend_lang_blocks.dart';

J tpar(String name, J type) => {'name': name, 'type': type};

BeDocument docOf({List<J> functions = const [], List<J> routes = const [], int rules = 2}) => BeDocument.fromJson({'name': 't', 'rules': rules, 'functions': functions, 'routes': routes}).doc;

BeDocument sample({int rules = 2}) => docOf(
  rules: rules,
  functions: [
    fnDef('f1', '加倍', [tpar('x', lTypeToJson(LType.integer))], [ret(op2('*', pm('x'), nm(2)))]),
    fnDef('f2', '喊', [tpar('话', lTypeToJson(LType.text))], [ret(pm('话'))]),
  ],
  routes: [
    route('r1', 'GET', '/a', [
      let('a', call('f1', {'x': tx('12')})),
      let('b', call('f1', {'x': nm(2.5)})),
      let('c', call('f2', {'话': nm(3)})),
      let(
        'd',
        call('f1', {
          'x': ex('parseInt', {'s': tx('7')}),
        }),
      ),
      iff(nm(1), [json(vr('a'))], noElse: true),
      json(nm(1)),
    ]),
  ],
);

List<String> lines(BeDocument doc) => [
  for (final f in beTypeCheck(doc)!.findings) '${f.issue.code} 第${f.at.path.single.index + 1}块 ${f.at.arg}${f.at.exprPath} ${[for (final x in f.fixes) x.fix.kind.name].join('+')}',
];

/// 找到带这种修法的那条，修掉，返回修的是哪一条。
BeTypeFinding fixIn(BeDocument doc, LFixKind kind) {
  final check = beTypeCheck(doc)!;
  final f = check.findings.firstWhere((f) => f.fixes.any((x) => x.fix.kind == kind));
  final x = f.fixes.firstWhere((x) => x.fix.kind == kind);
  final target = x.fix.target;
  final tree = [...doc.routes, ...doc.functions].cast<LcBlockTree>().firstWhere((t) => t.id == x.slot.treeId);
  expect(beApplyTypeFix(tree, x.fix, x.slot, got: target is LExpr ? check.result.typeOf(target) : null), isTrue);
  return f;
}

void main() {
  test('规矩版本 1 的文档：不查，返回 null', () {
    expect(beTypeCheck(sample(rules: 1)), isNull);
    expect(beTypeCheck(BeDocument()), isNull);
  });

  test('每条问题都对到了哪一块、哪一格，带着能在积木上做的修法', () {
    expect(lines(sample()), ['T01 第1块 value[x] wrapParseInt', 'T01 第2块 value[x] wrapToInt', 'T01 第3块 value[话] wrapToText', 'T02 第4块 value[x] wrapOrElse+wrapMust', 'T09 第5块 cond[] compareNotZero']);
    final check = beTypeCheck(sample())!;
    expect(check.findings.first.issue.message, '「加倍」的第 1 个参数要整数，放进来的是文字');
    expect(check.findings.last.issue.message, '这里要“是/否”，放进来的是整数');
    // 变量、参数的类型查得到（界面上“类型一行字”用）。
    expect(check.result.variable(check.scopes['f1']!, 'x')?.type.show(), '整数');
    expect(check.result.variable(check.scopes['r1']!, 'c')?.type.show(), '文字');
  });

  test('六种积木上能做的修法：修完那条没了，积木文档里真的多包了一层', () {
    final doc = sample();
    Object? at(int block, String arg) => doc.routes.single.body[block].args[arg];
    Object? inner(int block, String key) => exprField(at(block, 'value'), key);

    fixIn(doc, LFixKind.wrapToText);
    expect(inner(2, '话'), {'e': 'convert', 'x': nm(3), 'fn': 'toText'});
    fixIn(doc, LFixKind.wrapToInt);
    expect(inner(1, 'x'), {'e': 'round', 'x': nm(2.5), 'fn': 'round'});
    fixIn(doc, LFixKind.compareNotZero);
    expect(at(4, 'cond'), {'e': 'bin', 'op': '!=', 'l': nm(1), 'r': nm(0)});
    fixIn(doc, LFixKind.wrapOrElse);
    expect(inner(3, 'x'), {
      'e': 'orElse',
      'x': ex('parseInt', {'s': tx('7')}),
      'd': nm(0),
    });
    expect(lines(doc), ['T01 第1块 value[x] wrapParseInt']);

    // “变成整数”变不了就是空：修完换成一条“可能是空”，再点“一定不是空”才干净。
    fixIn(doc, LFixKind.wrapParseInt);
    expect(inner(0, 'x'), {'e': 'parseInt', 's': tx('12')});
    expect(lines(doc), ['T02 第1块 value[x] wrapOrElse+wrapMust']);
    fixIn(doc, LFixKind.wrapMust);
    expect(inner(0, 'x'), {
      'e': 'must',
      'x': ex('parseInt', {'s': tx('12')}),
    });
    expect(lines(doc), isEmpty);

    // 存盘再读回来还是没问题（三块严格积木、参数上标的类型都存得住）。
    final again = BeDocument.fromJson(doc.toJson()).doc;
    expect(again.rules, 2);
    expect(again.functions.first.params.single.type, LType.integer);
    expect(lines(again), isEmpty);
  });

  test('套在别的积木里面的格子也找得准（列表的第 2 项、“如果”的第 2 段、匿名函数的口里）', () {
    final doc = docOf(
      functions: [
        fnDef('f2', '喊', [tpar('话', lTypeToJson(LType.text))], [ret(pm('话'))]),
      ],
      routes: [
        route('r1', 'GET', '/a', [
          let(
            'xs',
            ls([
              tx('a'),
              call('f2', {'话': nm(1)}),
            ]),
          ),
          iff(
            yes(),
            [],
            arms: [
              arm(
                {'cond': nm(2)},
                [
                  let('y', call('f2', {'话': nm(3)})),
                ],
              ),
            ],
            noElse: true,
          ),
          json(nm(1)),
        ]),
      ],
    );
    final check = beTypeCheck(doc)!;
    expect(
      [for (final f in check.findings) '${f.issue.code} ${f.at.path.map((s) => '${s.index}/${s.arm}').join('>')} ${f.at.arg}${f.at.exprPath}'],
      ['T01 0/-1 value[items, 1, 话]', 'T09 1/-1 @0:cond[]', 'T01 1/-1>0/0 value[话]'],
    );
    for (final kind in [LFixKind.wrapToText, LFixKind.compareNotZero, LFixKind.wrapToText]) {
      fixIn(doc, kind);
    }
    expect(beTypeCheck(doc)!.findings, isEmpty);
    expect(doc.routes.single.body[1].arms.single.args['cond'], {'e': 'bin', 'op': '!=', 'l': nm(2), 'r': nm(0)});
  });

  test('函数里面的问题记在函数那一串上；标了“交回什么”对不上也报', () {
    final doc = docOf(
      functions: [
        {
          ...fnDef('f1', '算', [tpar('x', lTypeToJson(LType.integer))], [ret(tx('不是数'))]),
          'returns': lTypeToJson(LType.integer),
        },
      ],
      routes: [
        route('r1', 'GET', '/a', [
          json(call('f1', {'x': nm(1)})),
        ]),
      ],
    );
    final f = beTypeCheck(doc)!.findings.single;
    expect((f.issue.code, f.at.treeId, f.at.path.single.index, f.at.arg), ('T01', 'f1', 0, 'value'));
  });

  test('“是空就用”后面先放什么：照类型来', () {
    expect(beFixDefaultValue(LType.integer), nm(0));
    expect(beFixDefaultValue(LType.text), tx(''));
    expect(beFixDefaultValue(LType.boolean), no());
    expect(beFixDefaultValue(const LType.listOf(LType.integer)), {'e': 'listLit', 'items': <dynamic>[]});
    expect(beFixDefaultValue(const LType.dictOf(LType.any)), {'e': 'obj', 'fields': <dynamic>[]});
    expect(beFixDefaultValue(LType.any), isNull);
    expect(beFixDefaultValue(null), isNull);
  });

  test('积木上表达不了的五种修法：不硬造，返回 null / false', () {
    for (final kind in LFixKind.values) {
      // “去掉‘等’”要那一格里真是一块“等”才有的修（核心 3）；别的修法放什么都能包。
      final wrapped = beTypeFixWrap(LFix(kind, ''), kind == LFixKind.dropAwait ? ex('await', {'x': nm(1)}) : nm(1));
      expect(wrapped == null, !kBeBlockFixKinds.contains(kind), reason: kind.name);
    }
    expect(beTypeFixWrap(const LFix(LFixKind.dropAwait, ''), nm(1)), isNull, reason: '那一格里不是“等”：不动');
    final doc = sample();
    expect(beApplyTypeFix(doc.routes.single, const LFix(LFixKind.addMatchElse, ''), const BeSlotRef('r1', [(inElse: false, index: 0, arm: -1)], 'value', [])), isFalse);
    // 格子不在了也不崩。
    expect(beApplyTypeFix(doc.routes.single, const LFix(LFixKind.wrapToText, ''), const BeSlotRef('r1', [(inElse: false, index: 99, arm: -1)], 'value', [])), isFalse);
    expect(beApplyTypeFix(doc.routes.single, const LFix(LFixKind.wrapToText, ''), const BeSlotRef('r1', [(inElse: false, index: 0, arm: -1)], 'value', ['没有', 3])), isFalse);
  });

  test('坏文档不崩', () {
    final doc = docOf(
      routes: [
        route('r1', 'GET', '/a', [
          blk('let', {'name': 3, 'value': ex('不认识', {})}),
          blk('不认识的积木', {'x': ex('parseInt', {})}),
          blk('if', {}),
        ]),
      ],
    );
    expect(() => beTypeCheck(doc), returnsNormally);
  });
}
