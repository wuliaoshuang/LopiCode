// 第 2 阶段的纯逻辑测试：带口的值在模型里的读写往返、旧文档一个字不差、坏数据不崩；口的编号与寻址；
// 排版几何（参数小块、口、口里的积木和拼接点、嵌套、长式子里折行）；文案模板 → 句子 → 排出来的积木。
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/blocks/block_geometry.dart';
import 'package:lopicode/blocks/block_host.dart';
import 'package:lopicode/blocks/block_layout.dart';
import 'package:lopicode/blocks/block_look_preview.dart';
import 'package:lopicode/blocks/block_ops.dart';
import 'package:lopicode/lowcode/logic_expr.dart';
import 'package:lopicode/lowcode/logic_model.dart';

import 'support/blocks_fake_fn_host.dart';
import 'support/blocks_fake_host.dart';
import 'support/blocks_fake_rig.dart';
import 'support/blocks_fn_rig.dart';

double measure(String s) => s.runes.fold(0.0, (w, r) => w + (r < 0x2E80 ? 8 : 14));

BlockLayoutEngine engineOf(BlockHost host) => BlockLayoutEngine(host, measure);

void main() {
  group('模型', () {
    test('带口的值：存出来再读回来一模一样；口里是真的积木对象', () {
      final host = FakeFnHost(scripts: [FakeScript('s1', body: [fxMapBlock()], x: 0, y: 0)]);
      final text = host.encode();
      final back = FakeScript.parse((jsonDecode(text) as List).first as Map<String, dynamic>);
      expect(jsonEncode([back.toJson()]), text);
      final fn = (back.body.first.args['value'] as Map)['fn'] as Map<String, dynamic>;
      expect(lcExprBody(fn), isA<List<LcBlock>>());
      expect(lcExprBody(fn)!.map((b) => b.op), ['say', 'return']);
      expect(back.body.first.exprMouths, hasLength(1));
      expect(identical(back.body.first.exprMouths.single, lcExprBody(fn)), isTrue);
    });

    test('旧文档（没有带口的值）：读进来再存出去一个字不差，参数对象原样不动', () {
      final host = FakeHost(scripts: [FakeScript('s1', body: [fxSampleIf(), fxSampleSwitch(), fxSay('好')], x: 3, y: 4)]);
      final text = host.encode();
      final list = jsonDecode(text) as List;
      final back = FakeScript.parse(list.first as Map<String, dynamic>);
      expect(jsonEncode([back.toJson()]), text);
      expect(text.contains('@body'), isFalse);
      expect(text.contains('"def"'), isFalse);
      expect(back.body.first.exprMouths, isEmpty);
    });

    test('坏数据不崩：@body 不是表、里面混了不是积木的东西、没有 e 的对象带 @body、嵌得太深', () {
      final weird = [
        {'op': 'say', 'args': {'text': {'e': 'fn', 'params': 'x', '@body': 'oops'}}},
        {'op': 'say', 'args': {'text': {'e': 'fn', '@body': [1, null, 'x', {'op': 'say', 'args': <String, dynamic>{}}, {'nope': 1}]}}},
        {'op': 'say', 'args': {'text': {'@body': [{'op': 'say'}]}}},
        {'op': 'say', 'args': {'text': [{'e': 'fn', '@body': [{'op': 'break'}]}]}},
      ];
      final blocks = LcBlock.parseList(weird, 0);
      expect(blocks, hasLength(4));
      expect(blocks[0].exprMouths, isEmpty);
      expect(blocks[1].exprMouths.single.map((b) => b.op), ['say']);
      expect(blocks[2].exprMouths, isEmpty, reason: '没有 e 的对象不是表达式，它的 @body 不当口');
      expect(blocks[3].exprMouths.single.single.op, 'break');
      // 一层套一层套很深：不抛异常。
      Object deep = {'e': 'num', 'v': 1};
      for (var i = 0; i < 40; i++) {
        deep = {'e': 'fn', 'params': <String>[], '@body': [{'op': 'return', 'args': {'value': deep}}]};
      }
      expect(() => LcBlock.parseList([{'op': 'run', 'args': {'fn': deep}}], 0), returnsNormally);
      final host = FakeFnHost(scripts: [FakeScript('s1', body: blocks, x: 0, y: 0)]);
      expect(() => engineOf(host).layoutScript(host.script('s1')!), returnsNormally);
      expect(() => jsonEncode(host.script('s1')!.body.map((b) => b.toJson()).toList()), returnsNormally);
    });

    test('口的编号：一块积木上有几个带口的值，按参数的先后数；路径能走进去、插入、删除、移动', () {
      final b = LcBlock(op: 'dictSet', args: {'dict': fxFn(['a'], [fxSay('一')]), 'key': fxText('k'), 'value': fxListMap(fxExpr('listNew'), fxFn(['b'], [fxSay('二'), fxSay('三')]))});
      final tree = FakeScript('s1', body: [b]);
      expect(b.exprMouths.map((m) => m.length), [1, 2]);
      expect(lcExprMouthArm(0), -2);
      expect(lcExprMouthIndex(-3), 1);
      final p = [lcStep(0), lcStep(1, arm: lcExprMouthArm(1))];
      expect(tree.blockAt(p)!.args['text'], fxText('三'));
      expect(tree.listAt([lcStep(0)], arm: lcExprMouthArm(0)), hasLength(1));
      expect(tree.insertBlock([lcStep(0)], fxSay('零'), arm: lcExprMouthArm(0), index: 0), isTrue);
      expect(b.exprMouths.first.map((x) => (x.args['text'] as Map)['v']), ['零', '一']);
      expect(tree.moveBlock(p, [lcStep(0)], arm: lcExprMouthArm(0), index: 2), isTrue);
      expect(b.exprMouths.map((m) => m.length), [3, 1]);
      expect(tree.removeBlock([lcStep(0), lcStep(0, arm: -2)])!.args['text'], fxText('零'));
      final seen = <String>[];
      tree.visitBlocks((x, path) => seen.add('${x.op}@${path.length}'));
      expect(seen, ['dictSet@1', 'say@2', 'say@2', 'say@2']);
      expect(bkCountBlocks([b]), 4);
    });

    test('复制是深拷贝：改副本口里的积木不动原件', () {
      final b = fxMapBlock();
      final copy = bkCopyArgs(b);
      copy.exprMouths.single.clear();
      (copy.args['value'] as Map)['list'] = fxText('x');
      expect(b.exprMouths.single, hasLength(2));
      expect((b.args['value'] as Map)['list'], fxExpr('listNew'));
      final e = deepCopyJson(b.args['value']) as Map<String, dynamic>;
      expect(identical(lcExprBody(asExpr(e['fn'])!), b.exprMouths.single), isFalse);
    });
  });

  group('排版几何', () {
    test('定义帽子：名字槽后面一排参数小块，最后一个“＋”；小块上写着名字、默认值、“…”', () {
      final def = fxGreetDef();
      def.def!['params'] = [
        {'name': '名字'},
        {'name': '次数', 'default': 1},
        {'name': '其余', 'rest': true},
      ];
      final host = FakeFnHost(scripts: [def]);
      final layout = engineOf(host).layoutScript(def);
      final hat = layout.hat!;
      final chips = hat.slots.where((s) => s.look == BkSlotLook.param).toList();
      expect(chips.map((s) => s.text), ['名字', '次数＝1', '…其余']);
      expect(chips.map((s) => s.param), [0, 1, 2]);
      final add = hat.slots.where((s) => s.look == BkSlotLook.add).single;
      expect(add.param, 3);
      expect(add.rect.left, greaterThan(chips.last.rect.right));
      expect(add.rect.center.dy, closeTo(chips.last.rect.center.dy, 0.5), reason: '三个参数加“＋”排在一行');
      for (final s in [...chips, add]) {
        expect(hat.rect.contains(s.rect.topLeft) && hat.rect.contains(s.rect.bottomRight), isTrue);
        expect(s.acceptsExpr, isFalse, reason: '参数小块不是能放值的槽');
      }
      expect(hat.slots.first.hatSlotId, 'name');
      // 点得到：小块算小块。
      final hit = layout.hitTest(chips[1].rect.center)!;
      expect(hit.slot, same(chips[1]));
      // 满了（6 个）就没有“＋”。
      def.def!['params'] = [for (var i = 0; i < 6; i++) {'name': 'p$i'}];
      final full = engineOf(host).layoutScript(def).hat!;
      expect(full.slots.where((s) => s.look == BkSlotLook.add), isEmpty);
      expect(full.slots.where((s) => s.look == BkSlotLook.param), hasLength(6));
    });

    test('普通帽子（宿主没说是定义帽子）：一个小块都没有，排出来和以前一样宽', () {
      final plain = FakeHost(scripts: [FakeScript('s1', x: 0, y: 0)]);
      final fn = FakeFnHost(scripts: [FakeScript('s1', x: 0, y: 0)]);
      final a = engineOf(plain).layoutScript(plain.script('s1')!).hat!, b = engineOf(fn).layoutScript(fn.script('s1')!).hat!;
      expect(b.rect, a.rect);
      expect(b.slots, isEmpty);
    });

    test('带口的值：口在那句话下面，口里的积木在口里面、在所属积木后面（画在上面、先被点到），拼接点带着口的编号', () {
      final host = FakeFnHost(scripts: [FakeScript('s1', body: [fxMapBlock(), fxSay('好了')], x: 0, y: 0)]);
      final layout = engineOf(host).layoutScript(host.script('s1')!);
      final owner = layout.blockAt([lcStep(0)])!;
      final map = owner.slots.firstWhere((s) => s.arg == 'value').expr!;
      final fn = map.slots.firstWhere((s) => s.exprPath.last == 'fn').expr!;
      final mouth = fn.mouth!;
      expect(fn.rect.contains(mouth.topLeft) && fn.rect.contains(mouth.bottomRight - const Offset(0.1, 0.1)), isTrue);
      expect(fn.labels.single.text, '函数');
      expect(fn.labels.single.rect.bottom, lessThanOrEqualTo(mouth.top + 1));
      expect(fn.slots.where((s) => s.look == BkSlotLook.param).single.text, 'x');
      expect(fn.slots.where((s) => s.look == BkSlotLook.add).single.param, 1);
      expect(fn.inner, isEmpty, reason: '排完以后口里的积木都挪进整串的表里了');
      final say = layout.blockAt([lcStep(0), lcStep(0, arm: -2)])!, ret = layout.blockAt([lcStep(0), lcStep(1, arm: -2)])!;
      for (final b in [say, ret]) {
        expect(mouth.contains(b.rect.topLeft), isTrue);
        expect(b.rect.right, lessThanOrEqualTo(mouth.right));
        expect(b.rect.bottom, lessThanOrEqualTo(mouth.bottom));
        expect(layout.blocks.indexOf(b), greaterThan(layout.blocks.indexOf(owner)));
      }
      expect(ret.rect.top, closeTo(say.rect.bottom, 1));
      expect(owner.rect.contains(fn.rect.topLeft) && owner.rect.contains(fn.rect.bottomRight - const Offset(0.1, 0.1)), isTrue);
      expect(layout.blockAt([lcStep(1)])!.rect.top, closeTo(owner.rect.bottom, 1));
      // 点：口里的积木先被点到；口里的空白处算那个值。
      expect(layout.hitTest(say.head.centerLeft + const Offset(6, 0))!.block, same(say));
      final blank = layout.hitTest(Offset(mouth.right - 6, say.rect.center.dy))!;
      expect(blank.block, same(owner));
      expect(blank.expr, same(fn));
      // 拼接点：口里 3 个位置（最前、中间、最后），都在口里。
      final snaps = layout.snaps.where((s) => s.kind == BkSnapKind.statement && s.arm == -2).toList();
      expect(snaps.map((s) => s.index), [0, 1, 2]);
      for (final s in snaps) {
        expect(bkSameBlockPath(s.parent, [lcStep(0)]), isTrue);
        expect(mouth.inflate(2).contains(s.anchor), isTrue);
      }
      // 值槽的落点也有：口里“返回”的槽、函数自己所在的槽。
      expect(layout.snaps.any((s) => s.kind == BkSnapKind.expr && bkSameBlockPath(s.parent, [lcStep(0), lcStep(1, arm: -2)]) && s.arg == 'value'), isTrue);
    });

    test('空的口：有最小的大小，里面有一个拼接点；短写法没有口，只有参数小块和一个式子槽', () {
      final host = FakeFnHost(scripts: [FakeScript('s1', body: [LcBlock(op: 'run', args: {'fn': fxFn(const [])}), LcBlock(op: 'run', args: {'fn': fxFnShort(['a', 'b'], fxParam('a'))})], x: 0, y: 0)]);
      final layout = engineOf(host).layoutScript(host.script('s1')!);
      final fn = layout.blockAt([lcStep(0)])!.slots.single.expr!;
      expect(fn.mouth!.height, greaterThanOrEqualTo(28));
      expect(fn.mouth!.width, greaterThanOrEqualTo(120));
      expect(layout.snaps.where((s) => s.kind == BkSnapKind.statement && s.arm == -2).single.index, 0);
      final short = layout.blockAt([lcStep(1)])!.slots.single.expr!;
      expect(short.mouth, isNull);
      expect(short.slots.where((s) => s.look == BkSlotLook.param).map((s) => s.text), ['a', 'b']);
      expect(short.labels.single.text, '→');
      final chipsRight = short.slots.where((s) => s.param != null).map((s) => s.rect.right).reduce((a, b) => a > b ? a : b);
      expect(short.labels.single.rect.left, greaterThan(chipsRight), reason: '{@params} 写在句子开头：小块排在箭头前面');
      expect(short.slots.last.arg, 'fn');
      expect(short.slots.last.exprPath, ['body']);
    });

    test('嵌套：匿名函数里再放匿名函数、放在“对每一项”和“如果”的口里；每一层的口各走各的路径', () {
      final inner = LcBlock(op: 'run', args: {'fn': fxFn(['y'], [fxSay('最里面')])});
      final outer = LcBlock(op: 'run', args: {'fn': fxFn(['x'], [fxSay('外面'), inner])});
      final host = FakeFnHost(scripts: [
        FakeScript('s1', body: [
          LcBlock(op: 'forEach', args: {'list': fxExpr('listNew')}, body: [outer]),
          LcBlock(op: 'if', args: {'cond': fxBool(true)}, body: [fxMapBlock()], noElse: true),
        ], x: 0, y: 0),
      ]);
      final tree = host.script('s1')!;
      final layout = engineOf(host).layoutScript(tree);
      final deep = [lcStep(0), lcStep(0), lcStep(1, arm: -2), lcStep(0, arm: -2)];
      expect(tree.blockAt(deep)!.args['text'], fxText('最里面'));
      final deepBlock = layout.blockAt(deep)!;
      final mid = layout.blockAt(deep.sublist(0, 3))!, top = layout.blockAt(deep.sublist(0, 2))!;
      expect(top.rect.contains(mid.rect.topLeft) && top.rect.contains(mid.rect.bottomRight - const Offset(0.1, 0.1)), isTrue);
      expect(mid.rect.contains(deepBlock.rect.topLeft) && mid.rect.contains(deepBlock.rect.bottomRight - const Offset(0.1, 0.1)), isTrue);
      expect(layout.hitTest(deepBlock.head.centerLeft + const Offset(6, 0))!.block, same(deepBlock));
      expect(layout.blockAt([lcStep(1), lcStep(0), lcStep(1, arm: -2)])!.block!.op, 'return');
      // 没有两块积木的头互相压着。
      final heads = [for (final b in layout.blocks) if (!b.isHat) b];
      for (final a in heads) {
        for (final b in heads) {
          if (identical(a, b) || bkPathWithin(a.path, b.path) || bkPathWithin(b.path, a.path)) continue;
          expect(a.head.deflate(1).overlaps(b.head.deflate(1)), isFalse, reason: '${a.block!.op} 和 ${b.block!.op} 压着了');
        }
      }
      // 每个口里的拼接点都在。
      expect(layout.snaps.where((s) => s.kind == BkSnapKind.statement && bkSameBlockPath(s.parent, deep.sublist(0, 3)) && s.arm == -2).map((s) => s.index), [0, 1]);
    });

    test('带口的值嵌在长式子里：折行不乱——值整个换到下一行，不超出积木，后面的字和槽不和它叠着', () {
      final long = LcBlock(
        op: 'dictSet',
        args: {
          'dict': fxExpr('arith', {'l': fxExpr('textLen', {'x': fxText('一段比较长的文字用来把这一行撑满')}), 'op': '+', 'r': fxNum(1)}),
          'key': fxFn(['第一个参数', '第二个参数', '第三个'], [fxSay('口里的一块')]),
          'value': fxText('后面的值'),
        },
      );
      final host = FakeFnHost(scripts: [FakeScript('s1', body: [long, fxSay('下一块')], x: 0, y: 0)]);
      final layout = engineOf(host).layoutScript(host.script('s1')!);
      final b = layout.blockAt([lcStep(0)])!;
      final rects = [for (final s in b.slots) s.rect, for (final l in b.labels) l.rect];
      for (final r in rects) {
        expect(b.head.contains(r.topLeft) && r.right <= b.head.right + 0.1 && r.bottom <= b.head.bottom + 0.1, isTrue, reason: '$r 超出了积木 ${b.head}');
      }
      for (var i = 0; i < rects.length; i++) {
        for (var j = i + 1; j < rects.length; j++) {
          expect(rects[i].deflate(0.5).overlaps(rects[j].deflate(0.5)), isFalse, reason: '${rects[i]} 和 ${rects[j]} 叠着了');
        }
      }
      final fn = b.slots.firstWhere((s) => s.arg == 'key').expr!;
      final inside = layout.blockAt([lcStep(0), lcStep(0, arm: -2)])!;
      expect(fn.mouth!.contains(inside.rect.topLeft), isTrue);
      expect(fn.rect.width, lessThanOrEqualTo(b.rect.width));
      // 参数小块多了自己也会折行，都还在值里面。
      for (final s in fn.slots.where((s) => s.param != null)) {
        expect(fn.rect.contains(s.rect.topLeft) && s.rect.right <= fn.rect.right, isTrue);
        expect(s.rect.bottom, lessThanOrEqualTo(fn.mouth!.top + 1));
      }
      expect(layout.blockAt([lcStep(1)])!.rect.top, closeTo(b.rect.bottom, 1));
    });

    test('单独摆着的带口的值（积木盒里的样品、拖在手上的）：口里的积木一起排出来', () {
      final host = FakeFnHost();
      final l = engineOf(host).layoutExpr(fxFn(['x'], [fxSay('一'), fxSay('二')]), controls: false);
      expect(l.loose!.mouth, isNotNull);
      expect(l.blocks, hasLength(2));
      expect(l.size.height, greaterThanOrEqualTo(l.blocks.last.rect.bottom));
      expect(l.loose!.slots.where((s) => s.look == BkSlotLook.add), isEmpty, reason: '样品上不画“＋”');
      final sample = engineOf(host).layoutExpr(host.newExpr('listMap'));
      expect(sample.loose!.mouth, isNull);
    });
  });

  group('文案模板 → 积木', () {
    BkScriptLayout lay(CustomBlockLook look, List<String> params, {FakeFnHost? host}) {
      final h = BkLookPreviewHost(host ?? FakeFnHost(), look, params);
      return h.layout(engineOf(h));
    }

    List<String> words(BkBlock b) => [for (final l in b.labels) l.text];

    test('语句：把 {集合} 里编号是 {id} 的那条删掉——字和槽照模板的先后排', () {
      final l = lay(const CustomBlockLook('删一条', shape: CustomBlockShape.statement, template: '把 {集合} 里编号是 {id} 的那条删掉'), ['集合', 'id']);
      final b = l.blocks.single;
      expect(b.shape, BkShape.stack);
      expect(words(b), ['把', '里编号是', '的那条删掉']);
      expect(b.slots.map((s) => s.arg), ['集合', 'id']);
      final xs = [b.labels[0].rect.left, b.slots[0].rect.left, b.labels[1].rect.left, b.slots[1].rect.left, b.labels[2].rect.left];
      expect(xs, orderedEquals([...xs]..sort()));
      expect(b.colorKey, BlockColorKey.custom);
    });

    test('英文、槽在句首句尾、没有槽、花括号本身、不是参数的 {x}、同一个槽写了两次', () {
      expect(bkLookSentence(const CustomBlockLook('x', template: '{a} plus {b}'), ['a', 'b']), '{a} plus {b}');
      final head = lay(const CustomBlockLook('add', shape: CustomBlockShape.statement, template: '{a} plus {b}'), ['a', 'b']).blocks.single;
      expect(head.slots.first.rect.left, lessThan(head.labels.single.rect.left));
      expect(head.slots.last.rect.left, greaterThan(head.labels.single.rect.right));
      final none = lay(const CustomBlockLook('清空一切', shape: CustomBlockShape.statement, template: '清空一切'), const []).blocks.single;
      expect(words(none), ['清空一切']);
      expect(none.slots, isEmpty);
      final braces = lay(const CustomBlockLook('b', shape: CustomBlockShape.statement, template: '集合 {{全部}} 加 {n} 和 {没有} 再加 {n}'), ['n']).blocks.single;
      expect(braces.slots.map((s) => s.arg), ['n']);
      expect(words(braces).join(' ').replaceAll('\u200B', ''), '集合 {全部} 加 和 {没有} 再加 {n}');
      // 没写模板：名字 + 每个参数一个槽。
      final auto = lay(const CustomBlockLook('问好', shape: CustomBlockShape.statement), ['名字', '次数']).blocks.single;
      expect(words(auto), ['问好']);
      expect(auto.slots.map((s) => s.arg), ['名字', '次数']);
      // 模板里漏了的参数：排在最后，前面带着它的名字（不会没处填）。
      final missing = lay(const CustomBlockLook('m', shape: CustomBlockShape.statement, template: '只写了 {a}'), ['a', 'b']).blocks.single;
      expect(missing.slots.map((s) => s.arg), ['a', 'b']);
      expect(words(missing), ['只写了', 'b']);
    });

    test('很长的文案：折行，不超过积木最宽，行与行不叠', () {
      final l = lay(const CustomBlockLook('长', shape: CustomBlockShape.statement, template: '把 {集合} 里面所有满足条件 {条件} 的记录按照 {字段} 从小到大排好以后取出最前面的 {数量} 条再交给后面的积木接着用'), ['集合', '条件', '字段', '数量']);
      final b = l.blocks.single;
      expect(b.rect.width, lessThanOrEqualTo(320));
      final rows = {for (final r in [...b.labels.map((l) => l.rect), ...b.slots.map((s) => s.rect)]) r.center.dy.round()};
      expect(rows.length, greaterThan(2));
      for (final r in [...b.labels.map((l) => l.rect), ...b.slots.map((s) => s.rect)]) {
        expect(r.right, lessThanOrEqualTo(b.rect.right));
        expect(r.bottom, lessThanOrEqualTo(b.rect.bottom));
      }
    });

    test('三种形状：语句是拼图块；值是胶囊；是否是六边形；颜色照外观；不认识的颜色按“我的积木”色', () {
      const t = '{a} 比 {b} 大';
      final st = lay(const CustomBlockLook('大', shape: CustomBlockShape.statement, template: t, colorKey: BlockColorKey.list), ['a', 'b']);
      expect(st.loose, isNull);
      expect(st.blocks.single.colorKey, BlockColorKey.list);
      final v = lay(const CustomBlockLook('大', shape: CustomBlockShape.value, template: t), ['a', 'b']);
      expect(v.blocks, isEmpty);
      expect(v.loose!.hex, isFalse);
      final h = lay(const CustomBlockLook('大', shape: CustomBlockShape.boolean, template: t, colorKey: '没有这种颜色'), ['a', 'b']);
      expect(h.loose!.hex, isTrue);
      expect(h.loose!.colorKey, BlockColorKey.custom);
      expect(lay(const CustomBlockLook('大', template: t), ['a', 'b']).blocks, hasLength(1), reason: '自动：预览按语句画');
    });

    test('槽的种类：值槽放默认值、是否槽是六边形、固定选项是下拉；先放的东西照外观', () {
      final l = lay(
        const CustomBlockLook('问好', shape: CustomBlockShape.statement, template: '向 {名字} 问好 {次数} 次 大声 {大声} 语气 {语气}', slots: [
          CustomBlockSlot('次数', defaultValue: 3),
          CustomBlockSlot('大声', kind: CustomSlotKind.boolean, defaultValue: true),
          CustomBlockSlot('语气', kind: CustomSlotKind.choice, options: ['客气', '随便'], defaultValue: '随便'),
        ]),
        ['名字', '次数', '大声', '语气'],
      );
      final b = l.blocks.single;
      final by = {for (final s in b.slots) s.arg: s};
      expect(by['名字']!.expr!.expr, fxText(''));
      expect(by['次数']!.expr!.expr, fxNum(3));
      expect(by['大声']!.hex, isTrue);
      expect(by['大声']!.expr!.expr, fxBool(true));
      expect(by['语气']!.look, BkSlotLook.dropdown);
      expect(by['语气']!.text, '随便');
    });

    test('校验分到各行：名字、文案、选项；重名和宿主自己的规矩', () {
      List<BlockLookField> fields(CustomBlockLook look, List<String> params, {List<String> taken = const []}) => [for (final p in bkCheckLook(look, params, taken: taken)) p.field];
      expect(fields(const CustomBlockLook(''), const []), [BlockLookField.name]);
      expect(fields(const CustomBlockLook('好', template: '{没有}'), const []), [BlockLookField.template]);
      expect(fields(const CustomBlockLook('好', template: '好'), ['a']), [BlockLookField.template]);
      expect(fields(const CustomBlockLook('好', template: '{a} {a}'), ['a']), [BlockLookField.template]);
      expect(fields(const CustomBlockLook('好', slots: [CustomBlockSlot('a', kind: CustomSlotKind.choice)]), ['a']), [BlockLookField.options]);
      expect(fields(const CustomBlockLook('好'), const [], taken: ['好']), [BlockLookField.name]);
      expect(fields(const CustomBlockLook('这个名字实在是太长了太长了太长了太长了太长了太长了'), const []), [BlockLookField.name]);
      expect(fields(const CustomBlockLook('好', template: '向 {名字} 问好'), ['名字']), isEmpty);
      expect(bkParamNameProblems(['a', '', 'a', '带{括号}', 'b']).map((p) => p == null), [true, false, false, false, true]);
      expect(FakeFnHost().check(const CustomBlockLook('说'), const []).single.message, contains('内置积木'));
      expect(bkFreshParamName(['参数1', '参数3']), '参数2');
    });

    test('老的句子写法没变：{name} 这种英文槽名照旧；不是参数的英文花括号照旧单独成段；中文花括号不是参数就留在字里', () {
      final parts = parseBlockSentence('把 {name} 设为 {value}', fakeBlockSpecs['set']!.args);
      expect([for (final p in parts) p.arg ?? p.text], ['把', 'name', '设为', 'value']);
      final odd = parseBlockSentence('说 {text} 和 {nope} 和 {没有这个}', fakeBlockSpecs['say']!.args);
      expect([for (final p in odd) p.arg ?? p.text], ['说', 'text', '和', '{nope}', '和 {没有这个}']);
      final tail = parseBlockSentence('只有字', fakeBlockSpecs['say']!.args);
      expect([for (final p in tail) p.arg ?? p.text], ['只有字', '内容', 'text']);
    });
  });
}
