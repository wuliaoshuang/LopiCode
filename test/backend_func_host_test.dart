// 积木第 4 版·第 2 阶段：后端宿主（BeBlockHost）给编辑器的那些回调——定义帽子（改名、参数小块）、“我的积木”（新建 / 改 / 删 / 包）、
// 下拉选项、撤销重做。不搭界面，直接调宿主。
import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/backend/backend_block_host.dart';
import 'package:lopicode/backend/backend_blocks.dart';
import 'package:lopicode/backend/backend_func_host.dart';
import 'package:lopicode/backend/backend_function.dart';
import 'package:lopicode/backend/backend_model.dart';
import 'package:lopicode/blocks/block_host.dart';
import 'package:lopicode/lowcode/logic_model.dart';

import 'support/backend_func_blocks.dart';
import 'support/backend_lang_blocks.dart';

BeDocument docOf(List<J> fns, List<J> body) => parseLangBlocksDocument({
  ...langBlocksDocumentJson([route('r1', 'GET', '/x', body)]),
  'functions': fns,
});

void main() {
  late List<String> notices;
  BeBlockHost hostOf(BeDocument doc) {
    notices = [];
    return BeBlockHost(doc: doc, onNotice: notices.add);
  }

  test('画布上的串：接口在前、函数在后；函数的帽子是“定义 名字”、带参数小块；删这一串＝删函数（调用一起拿掉）', () {
    final host = hostOf(
      docOf(
        [
          fnDef('f1', '加倍', [par('x', def: 2), par('多的', rest: true)], [ret(pm('x'))]),
        ],
        [
          callS('f1', {'x': nm(1)}),
          json(nm(1)),
        ],
      ),
    );
    expect([for (final s in host.scripts) s.id], ['r1', 'f1']);
    final f = host.doc.function('f1')!;
    final hat = host.hatOf(f);
    expect(hat.colorKey, BlockColorKey.function);
    expect(hat.parts.first.text, '定义');
    final params = host.hatParams(f)!;
    expect([for (final p in params.params) (p.name, p.defaultValue, p.rest)], [('x', 2, false), ('多的', null, true)]);
    expect(params.max, kBeMaxParams);
    expect(host.hatParams(host.doc.route('r1')!), isNull, reason: '接口的帽子没有参数小块');
    expect(host.hatParamUses(f, 'x'), 1);
    expect(host.paramExpr('x'), {'e': 'param', 'name': 'x'});
    host.edit(() => host.removeScript('f1'));
    expect(host.doc.functions, isEmpty);
    expect([for (final b in host.doc.route('r1')!.body) b.op], ['respondJson']);
    host.undo();
    expect(host.doc.functions, hasLength(1));
    expect(host.doc.route('r1')!.body.first.op, 'call:f1');
  });

  test('从积木盒拖“定义”帽子：多一个函数，名字不重（新积木、新积木2）；满了说原因', () {
    final host = hostOf(docOf([], [json(nm(1))]));
    final a = host.addScript(kBeDefineTemplate, x: 10, y: 20)! as BeFunction;
    final b = host.addScript(kBeDefineTemplate)! as BeFunction;
    expect((a.name, b.name, a.id, b.id, a.x, a.y), ('新积木', '新积木2', 'f1', 'f2', 10, 20));
    for (var i = host.doc.functions.length; i < kBeMaxFunctions; i++) {
      expect(host.addScript(kBeDefineTemplate), isNotNull);
    }
    expect(host.addScript(kBeDefineTemplate), isNull);
    expect(notices.single, contains('$kBeMaxFunctions'));
    expect(host.custom!.create(const CustomBlockLook('再来'), const []), isNull);
  });

  test('帽子上改名：空的、太长、重名不改并说原因；改了以后调用积木上的话跟着变', () {
    final host = hostOf(docOf([fnDef('f1', '甲', [], []), fnDef('f2', '乙', [], [])], [callS('f1'), json(nm(1))]));
    final f = host.doc.function('f1')!;
    for (final (bad, why) in [('  ', '不能空着'), ('乙', '已经有'), ('很' * 25, '太长')]) {
      expect(host.setHatSlot(f, 'name', bad), isFalse);
      expect(notices.last, contains(why));
    }
    expect(f.name, '甲');
    expect(host.setHatSlot(f, 'name', ' 丙 '), isTrue);
    expect(f.name, '丙');
    expect(host.blockSpec('call:f1')!.label, contains('丙'));
  });

  test('帽子上改参数：改名（定义里、各处调用跟着改）、加、删（丢了内容说一声）；保留名、重名、太多不改并说原因', () {
    final host = hostOf(
      docOf(
        [
          fnDef('f1', '甲', [par('a')], [ret(pm('a'))]),
        ],
        [
          json(call('f1', {'a': nm(7)})),
        ],
      ),
    );
    final f = host.doc.function('f1')!;
    Map<dynamic, dynamic> callArgs() => host.doc.route('r1')!.body.single.args['value'] as Map;
    expect(host.setHatParams(f, const [BlockParam('甲')], renamed: (from: 'a', to: '甲')), isTrue);
    expect(f.paramNames, ['甲']);
    expect(f.body.single.args['value'], {'e': 'param', 'name': '甲'});
    expect(callArgs().keys.toList(), ['e', '甲']);
    expect(host.setHatParams(f, const [BlockParam('甲'), BlockParam('次数', defaultValue: 3)]), isTrue);
    expect((callArgs()['次数'] as Map)['v'], 3, reason: '新加的参数：各处调用补上默认值');
    expect(host.custom!.customs.single.look.slotFor('次数').defaultValue, 3, reason: '帽子上的默认值同时是调用槽里先放的内容');
    for (final (bad, why) in [
      (const [BlockParam('e')], '自己要用'),
      (const [BlockParam('@x')], '自己要用'),
      (const [BlockParam('甲'), BlockParam('甲')], '已经有'),
      ([for (var i = 0; i <= kBeMaxParams; i++) BlockParam('p$i')], '最多'),
    ]) {
      expect(host.setHatParams(f, bad), isFalse, reason: '$bad');
      expect(notices.last, contains(why));
    }
    expect(f.paramNames, ['甲', '次数']);
    notices.clear();
    expect(host.setHatParams(f, const [BlockParam('次数', defaultValue: 3)]), isTrue);
    expect(callArgs().keys.toList(), ['e', '次数']);
    expect(notices.single, contains('1 格内容一起丢掉了'));
  });

  test('“我的积木”：新建 / 改 / 查重名 / 用了几处 / 删；改的时候丢了内容留一句话给编辑器；形状跟着定义变', () {
    final host = hostOf(docOf([], [json(nm(1))]));
    final custom = host.custom!;
    expect(custom.canWrap, isTrue);
    final id = custom.create(const CustomBlockLook('问好', slots: [CustomBlockSlot('次数', defaultValue: 1)]), const ['谁', '次数'])!;
    expect(id, 'call:f1');
    expect(custom.definitionOf(id), 'f1');
    expect(custom.customs.single.look.shape, CustomBlockShape.statement);
    expect(host.newBlock(id).args.keys, ['谁', '次数']);
    expect(host.newExpr(id)['e'], id);
    expect(custom.check(const CustomBlockLook('问好'), const ['谁'], editing: id), isEmpty);
    expect(custom.check(const CustomBlockLook('别的'), const ['e']).single.field, BlockLookField.slot);
    expect(custom.check(const CustomBlockLook('写到日志'), const []).single.message, contains('内置积木'));
    host.doc.route('r1')!.body.insert(0, LcBlock(op: id, args: {'谁': tx('小明'), '次数': nm(5)}));
    host.edit(() {});
    expect(custom.usesOf(id), 1);
    expect(custom.update(id, const CustomBlockLook('问好'), const ['对谁'], const [0]), isTrue);
    expect(host.doc.route('r1')!.body.first.args.keys, ['对谁']);
    expect(custom.takeNotice(), contains('1 格内容一起丢掉了'));
    expect(custom.takeNotice(), isNull, reason: '问过一次就清掉');
    expect(custom.update('call:nope', const CustomBlockLook('x'), const [], const []), isFalse);
    // 定义里放了“返回 (是否)”：积木盒里它变成六边形的“是否”。
    host.edit(() => host.doc.function('f1')!.body.add(LcBlock(op: 'return', args: {'value': yes()})));
    expect(custom.customs.single.look.shape, CustomBlockShape.boolean);
    expect(host.isBooleanExpr({'e': id}), isTrue);
    expect(custom.remove(id), isTrue);
    expect(host.doc.functions, isEmpty);
    expect(custom.remove(id), isFalse);
  });

  test('下拉：“这块积木本身”列出全部自定义积木；“参数”列出这一串看得见的参数；定义里的变量下拉不列文档变量', () {
    final host = hostOf(
      docOf(
        [
          fnDef(
            'f1',
            '甲',
            [par('a'), par('b')],
            [
              let('mine', lam(['x'], [ret(pm('x'))])),
              ret(vr('mine')),
            ],
          ),
          fnDef('f2', '乙', [], []),
        ],
        [let('here', nm(1)), json(vr('here'))],
      ),
    );
    final f = host.doc.function('f1')!;
    final refArg = host.exprSpec('funcRef')!.args.single;
    expect([for (final o in host.options(refArg, expr: ref('f1'))) (o.value, o.label)], [('f1', '甲'), ('f2', '乙')]);
    expect(host.optionLabel(refArg, 'f2'), '乙');
    expect(host.optionLabel(refArg, 'f9'), contains('删掉'));
    final paramArg = host.exprSpec('param')!.args.single;
    expect([for (final o in host.options(paramArg, tree: f, expr: pm('a'))) o.value], ['a', 'b', 'x']);
    final varArg = beExprSpecs['var']!.args.single;
    final inFn = [for (final o in host.options(varArg, tree: f, expr: vr('mine'))) o.value];
    expect(inFn, contains('mine'));
    expect(inFn, isNot(contains('total')), reason: '定义里看不见文档变量');
    expect([for (final o in host.options(varArg, tree: host.doc.route('r1')!, expr: vr('here'))) o.value], containsAll(['here', 'total']));
  });

  test('包成积木走宿主：包不了有原因；包了以后原处是调用；撤销重做整个文档来回一致', () {
    final host = hostOf(
      docOf([], [
        let('n', nm(1)),
        blk('log', {'value': vr('n')}),
        blk('log', {'value': tx('x')}),
      ]),
    );
    final custom = host.custom!;
    final r = host.doc.route('r1')!;
    final start = host.doc.encode();
    expect(custom.wrapBlocker(r, const []), isNotNull);
    expect(custom.wrapBlocker(r, [lcStep(1)]), isNull);
    expect(custom.outerNames(r, [lcStep(1)]), ['n']);
    String? id;
    host.edit(() => id = custom.wrap(host.doc.route('r1')!, [lcStep(1)], const CustomBlockLook('记两笔'), const ['n']));
    expect(id, 'call:f1');
    expect([for (final b in host.doc.route('r1')!.body) b.op], ['let', 'call:f1']);
    expect(host.issues.where((i) => i.isError), isEmpty);
    final end = host.doc.encode();
    host.undo();
    expect(host.doc.encode(), start);
    expect(host.custom!.customs, isEmpty, reason: '撤销以后“我的积木”页签跟着空');
    host.redo();
    expect(host.doc.encode(), end);
    expect(host.custom!.customs.single.look.name, '记两笔');
  });
}
