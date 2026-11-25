// 多口积木（如果…否则如果…否则、分情况、试着做）的纯逻辑测试：模型读写、路径操作、排版几何、增减段、拖进拖出各个口。
// 不搭界面，量字宽用假的；宿主用测试专用的假宿主（test/support/blocks_fake_host.dart）。
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/blocks/block_canvas_layout.dart';
import 'package:lopicode/blocks/block_drag.dart';
import 'package:lopicode/blocks/block_geometry.dart';
import 'package:lopicode/blocks/block_layout.dart';
import 'package:lopicode/blocks/block_motion.dart';
import 'package:lopicode/blocks/block_ops.dart';
import 'package:lopicode/lowcode/logic_block_host.dart';
import 'package:lopicode/lowcode/logic_expr.dart';
import 'package:lopicode/lowcode/logic_model.dart';
import 'package:lopicode/lowcode/model.dart';

import 'support/blocks_fake_host.dart';

double fakeMeasure(String s) => s.runes.fold(0.0, (w, r) => w + (r < 128 ? 8 : 14));

LcBlock say(String t) => LcBlock(op: 'say', args: {'text': fxText(t)});

/// 如果 (分数 > 90) 那么 {说 A} 否则如果 (分数 > 60) {说 B} 否则如果 (是) {} 否则 {说 D}
LcBlock sampleIf() => LcBlock(
  op: 'if',
  args: {'cond': fxCmp(fxVar('分数'), '>', fxNum(90))},
  body: [say('A')],
  arms: [
    LcArm(args: {'cond': fxCmp(fxVar('分数'), '>', fxNum(60))}, body: [say('B')]),
    LcArm(args: {'cond': fxBool(true)}),
  ],
  orElse: [say('D')],
);

LcBlock sampleSwitch() => LcBlock(
  op: 'switch',
  args: {'x': fxVar('次数')},
  arms: [
    LcArm(args: {'value': fxNum(1)}, body: [say('一')]),
    LcArm(args: {'value': fxNum(2)}, body: [say('二')]),
  ],
  orElse: [say('别的')],
);

class Bench {
  Bench(List<LcBlock> body)
    : host = FakeHost(
        scripts: [
          FakeScript('s1', body: body),
          FakeScript('s2', body: [say('另一串')], x: 400, y: 0),
        ],
      ) {
    engine = BlockLayoutEngine(host, fakeMeasure);
  }
  final FakeHost host;
  late final BlockLayoutEngine engine;

  LcBlockTree get tree => host.script('s1')!;
  BkCanvasLayout get layout => layoutBlockCanvas(host, engine);
  BkScriptLayout get script => engine.layoutScript(tree);
  List<String> texts(List<LcBlock> list) => [for (final b in list) '${(b.args['text'] as Map?)?['v'] ?? b.op}'];

  BkDragSession grab(LcBlockPath path) {
    final l = layout;
    final p = l.placed('s1')!;
    return BkDragSession.fromHit(host, engine, l, p, BkHit(p.layout.blockAt(path)!))!;
  }

  Offset at(BkDragSession d, LcBlockPath parent, int index, {bool inElse = false, int arm = -1, String scriptId = 's1'}) {
    final p = d.base.placed(scriptId)!;
    final snap = p.layout.snaps.firstWhere((x) => x.kind == BkSnapKind.statement && bkSameBlockPath(x.parent, parent) && x.arm == arm && (arm >= 0 || x.inElse == inElse) && x.index == index);
    return p.origin + snap.anchor;
  }
}

void main() {
  group('模型读写', () {
    test('旧文档（只有 那么 / 否则 的如果）：读进来再写出去，一个字节都不变，也不会多出新字段', () {
      const old =
          '[{"op":"if","args":{"cond":{"e":"bool","v":true}},"body":[{"op":"alert","args":{"message":{"e":"text","v":"a"}}}],"else":[{"op":"log","args":{"value":{"e":"num","v":1}}}]},'
          '{"op":"if","args":{"cond":{"e":"bool","v":false}}},{"op":"repeat","args":{"times":{"e":"num","v":3}},"body":[{"op":"if","args":{"cond":{"e":"bool","v":true}},"else":[{"op":"log"}]}]}]';
      final blocks = LcBlock.parseList(jsonDecode(old), 0);
      expect(jsonEncode([for (final b in blocks) b.toJson()]), old);
      expect(blocks.first.arms, isEmpty);
      expect(blocks.first.noElse, isFalse);
      // 深拷贝、浅拷贝也不会凭空带出新字段。
      expect(jsonEncode([for (final b in blocks) b.clone().toJson()]), old);
      expect(jsonEncode([for (final b in blocks) b.copyWith().toJson()]), old);
    });

    test('整份页面文档带着旧的如果：encode 两次一样，里面没有 arms / noElse', () {
      final doc = LcDocument.starter('t');
      final h = doc.logic.addHandler('load')!;
      h.body.add(
        LcBlock(
          op: 'if',
          args: {'cond': exBool(true)},
          body: [
            LcBlock(op: 'log', args: {'value': exNum(1)}),
          ],
          orElse: [
            LcBlock(op: 'log', args: {'value': exNum(2)}),
          ],
        ),
      );
      final text = doc.encode();
      expect(text.contains('arms'), isFalse);
      expect(text.contains('noElse'), isFalse);
      expect(LcDocument.parse(text).encode(), text);
    });

    test('多口积木：arms / noElse 原样存取，字段顺序固定（op args body arms else noElse）', () {
      const text =
          '{"op":"if","args":{"cond":{"e":"bool","v":true}},"body":[{"op":"say"}],"arms":[{"args":{"cond":{"e":"bool","v":false}},"body":[{"op":"say"}]},{"args":{"cond":{"e":"bool","v":true}}},{}],"else":[{"op":"say"}]}';
      final b = LcBlock.tryParse(jsonDecode(text), 0)!;
      expect(b.arms, hasLength(3));
      expect(b.arms[0].body.single.op, 'say');
      expect(b.arms[2].args, isEmpty);
      expect(jsonEncode(b.toJson()), text);
      const off = '{"op":"if","args":{"cond":{"e":"bool","v":true}},"noElse":true}';
      final c = LcBlock.tryParse(jsonDecode(off), 0)!;
      expect(c.noElse, isTrue);
      expect(jsonEncode(c.toJson()), off);
      expect(jsonEncode(c.clone().toJson()), off);
    });

    test('坏数据不崩：arms 不是表、段不是对象、参数不是对象、noElse 不是布尔、段太多、套太深', () {
      LcBlock p(String s) => LcBlock.tryParse(jsonDecode(s), 0)!;
      expect(p('{"op":"if","arms":"x"}').arms, isEmpty);
      expect(p('{"op":"if","arms":{"a":1}}').arms, isEmpty);
      final mixed = p('{"op":"if","arms":[1,null,"x",{"args":[1,2],"body":"y"},{"args":{"a":1},"body":[{"op":"say"},7,{"nop":1}]}]}');
      expect(mixed.arms, hasLength(2));
      expect(mixed.arms[0].args, isEmpty);
      expect(mixed.arms[0].body, isEmpty);
      expect(mixed.arms[1].body.single.op, 'say');
      expect(p('{"op":"if","noElse":"yes"}').noElse, isFalse);
      expect(p('{"op":"if","noElse":1}').noElse, isFalse);
      final many = p(jsonEncode({'op': 'if', 'arms': List.filled(100, <String, dynamic>{})}));
      expect(many.arms, hasLength(LcBlock.maxArms));
      // 段里一层套一层：超过最大深度的那几层丢掉，不崩。
      Map<String, dynamic> deep = {'op': 'say'};
      for (var i = 0; i < 30; i++) {
        deep = {
          'op': 'if',
          'arms': [
            {
              'body': [deep],
            },
          ],
        };
      }
      final d = LcBlock.tryParse(deep, 0)!;
      expect(d.height, LcBlock.maxDepth + 1);
    });

    test('段参数的名字：编码、解码、按名字读写', () {
      expect(lcArmArg(2, 'cond'), '@2:cond');
      expect(lcArmArgOf('@2:cond'), (arm: 2, name: 'cond'));
      expect(lcArmArgOf('cond'), isNull);
      expect(lcArmArgOf('@x:cond'), isNull);
      expect(lcArmArgOf('@:cond'), isNull);
      final b = sampleIf();
      expect((b.argValue('@1:cond') as Map)['e'], 'bool');
      expect((b.argValue('cond') as Map)['e'], 'cmp');
      expect(b.argValue('@9:cond'), isNull);
      expect(b.setArgValue('@9:cond', 1), isFalse);
      expect(b.setArgValue('@1:cond', fxBool(false)), isTrue);
      expect((b.arms[1].args['cond'] as Map)['v'], false);
      // 表达式路径照样能往段参数里走。
      expect(bkExprAt(b, '@0:cond', const ['l', 'name']), '分数');
      expect(bkSetExprAt(b, '@0:cond', const ['r'], fxNum(70)), isTrue);
      expect(((b.arms[0].args['cond'] as Map)['r'] as Map)['v'], 70);
      expect(fakeBlockSpecs['if']!.arg('@0:cond')!.name, 'cond');
      expect(fakeBlockSpecs['say']!.arg('@0:cond'), isNull);
    });
  });

  group('按路径操作', () {
    test('找、插、删、挪、上下移：段里的口和 那么 / 否则 一样用', () {
      final b = Bench([sampleIf()]);
      final t = b.tree;
      expect(
        b.texts([
          t.blockAt([lcStep(0), lcStep(0, arm: 0)])!,
        ]),
        ['B'],
      );
      expect(t.blockAt([lcStep(0), lcStep(0, arm: 1)]), isNull);
      expect(t.blockAt([lcStep(0), lcStep(0, arm: 5)]), isNull, reason: '没有这一段');
      expect(t.listAt([lcStep(0)], arm: 1), isEmpty);
      expect(t.listAt([lcStep(0)], arm: 7), isNull);
      expect(t.insertBlock([lcStep(0)], say('C'), arm: 1), isTrue);
      expect(t.insertBlock([lcStep(0)], say('X'), arm: 7), isFalse);
      expect(t.insertBlock([lcStep(0)], say('B0'), arm: 0, index: 0), isTrue);
      expect(b.texts(t.body.single.arms[0].body), ['B0', 'B']);
      expect(t.shiftBlock([lcStep(0), lcStep(0, arm: 0)], 1), isTrue);
      expect(b.texts(t.body.single.arms[0].body), ['B', 'B0']);
      // 从第 1 段挪到“否则”，再从“否则”挪到第 2 段。
      expect(t.moveBlock([lcStep(0), lcStep(1, arm: 0)], [lcStep(0)], inElse: true, index: 0), isTrue);
      expect(b.texts(t.body.single.orElse), ['B0', 'D']);
      expect(t.moveBlock([lcStep(0), lcStep(1, inElse: true)], [lcStep(0)], arm: 1), isTrue);
      expect(b.texts(t.body.single.arms[1].body), ['C', 'D']);
      expect(
        b.texts([
          t.removeBlock([lcStep(0), lcStep(0, arm: 1)])!,
        ]),
        ['C'],
      );
      // 不能挪进自己的段里。
      expect(t.moveBlock([lcStep(0)], [lcStep(0)], arm: 0), isFalse);
    });

    test('同一个下标、不同的口不是同一条路径', () {
      expect(bkSameBlockPath([lcStep(0), lcStep(0, arm: 0)], [lcStep(0), lcStep(0, arm: 0)]), isTrue);
      expect(bkSameBlockPath([lcStep(0), lcStep(0, arm: 0)], [lcStep(0), lcStep(0, arm: 1)]), isFalse);
      expect(bkSameBlockPath([lcStep(0), lcStep(0, arm: 0)], [lcStep(0), lcStep(0)]), isFalse);
      expect(bkSameBlockPath([lcStep(0), lcStep(0, arm: 0)], [lcStep(0), lcStep(0, inElse: true)]), isFalse);
      // 第一步在哪个口不看（最外层没有口）。
      expect(bkSameBlockPath([lcStep(0, arm: 3)], [lcStep(0)]), isTrue);
      expect(bkMotionKey('s', [lcStep(0), lcStep(1, arm: 2)]), isNot(bkMotionKey('s', [lcStep(0), lcStep(1)])));
      expect(bkMotionKey('s', [lcStep(0), lcStep(1, arm: 2)]), isNot(bkMotionKey('s', [lcStep(0), lcStep(1, arm: 1)])));
    });

    test('遍历顺序：自己 → 那么 → 各段 → 否则；层数、块数都把段算上', () {
      final b = Bench([sampleIf()]);
      final seen = <String>[];
      b.tree.visitBlocks(
        (blk, path) => seen.add('${blk.op == 'say' ? (blk.args['text'] as Map)['v'] : blk.op}@${path.map((s) => s.arm >= 0 ? 'a${s.arm}.${s.index}' : '${s.inElse ? 'e' : ''}${s.index}').join('/')}'),
      );
      expect(seen, ['if@0', 'A@0/0', 'B@0/a0.0', 'D@0/e0']);
      final nest = LcBlock(
        op: 'if',
        arms: [
          LcArm(body: [sampleIf()]),
        ],
      );
      expect(nest.height, 3);
      expect(bkCountBlocks([nest]), 5);
      // 嵌套上限对段里的积木一样管用。
      final t = Bench([
        LcBlock(op: 'if', arms: [LcArm()]),
      ]).tree;
      var parent = <LcBlockStep>[lcStep(0)];
      var okCount = 0;
      for (var i = 0; i < 20; i++) {
        if (!t.insertBlock(parent, LcBlock(op: 'if', arms: [LcArm()]), arm: 0)) break;
        okCount++;
        parent = [...parent, lcStep(0, arm: 0)];
      }
      expect(okCount, LcBlock.maxDepth);
    });

    test('让位以后的路径换算：只动同一段里的', () {
      final BkRoom room = (scriptId: 's', parent: [lcStep(0)], inElse: false, arm: 1, start: 0, count: 2);
      expect(bkPathBeforeRoom([lcStep(0), lcStep(0, arm: 1)], room), isNull);
      expect(bkPathBeforeRoom([lcStep(0), lcStep(2, arm: 1)], room), [lcStep(0), lcStep(0, arm: 1)]);
      expect(bkPathBeforeRoom([lcStep(0), lcStep(2, arm: 0)], room), [lcStep(0), lcStep(2, arm: 0)]);
      expect(bkPathBeforeRoom([lcStep(0), lcStep(2)], room), [lcStep(0), lcStep(2)]);
    });
  });

  group('排版几何', () {
    test('如果 + 两段否则如果 + 否则：四个口从上到下，每段横栏上有自己的条件槽', () {
      final b = Bench([sampleIf()]);
      final blk = b.script.blockAt([lcStep(0)])!;
      expect(blk.shape, BkShape.mouth);
      expect([for (final m in blk.mouths) m.arm], [-1, 0, 1, -1]);
      expect([for (final m in blk.mouths) m.inElse], [false, false, false, true]);
      // 口不重叠、从上到下；每条横栏正好夹在上一个口和自己的口之间。
      for (var i = 1; i < blk.mouths.length; i++) {
        final prev = blk.mouths[i - 1], cur = blk.mouths[i];
        expect(cur.bar!.top, prev.rect.bottom);
        expect(cur.bar!.bottom, cur.rect.top);
        expect(cur.bar!.left, blk.rect.left);
        expect(cur.bar!.right, blk.rect.right);
        expect(cur.rect.left, blk.rect.left + const BkMetrics().armW);
      }
      expect(blk.mouths.first.bar, isNull);
      expect(blk.mouths.first.rect.top, blk.head.bottom);
      expect(blk.rect.bottom, blk.mouths.last.rect.bottom + const BkMetrics().addFooterH);
      // 段的横栏和积木头一样高（里面有槽）；“否则”还是矮的那条。
      expect(blk.mouths[1].bar!.height, greaterThanOrEqualTo(const BkMetrics().minBlockHeight));
      expect(blk.mouths[3].bar!.height, const BkMetrics().dividerH);
      expect(blk.mouths[3].label!.text, '否则');
      // 槽：头上一个 cond，每段一个 @i:cond；都落在各自的横栏里。
      final own = blk.slots.where((s) => s.exprPath.isEmpty).toList();
      expect([for (final s in own) s.arg], ['cond', '@0:cond', '@1:cond']);
      expect(blk.headSlots, 1);
      expect(blk.head.contains(own[0].rect.center), isTrue);
      expect(blk.mouths[1].bar!.contains(own[1].rect.center), isTrue);
      expect(blk.mouths[2].bar!.contains(own[2].rect.center), isTrue);
      expect(blk.mouths[1].labels.map((l) => l.text), ['否则如果']);
      // 口里的积木缩进在各自的口里。
      final inArm = b.script.blockAt([lcStep(0), lcStep(0, arm: 0)])!;
      expect(blk.mouths[1].rect.contains(inArm.rect.center), isTrue);
      final inElse = b.script.blockAt([lcStep(0), lcStep(0, inElse: true)])!;
      expect(blk.mouths[3].rect.contains(inElse.rect.center), isTrue);
    });

    test('整块的宽度跟着最宽的那条横栏走：段上的条件比头长，积木也跟着变宽，“−”不压槽', () {
      final wide = sampleIf()..args['cond'] = fxBool(true);
      final blk = Bench([wide]).script.blockAt([lcStep(0)])!;
      final armSlot = blk.mouths[1].slots.first;
      final minus = blk.controls.firstWhere((c) => c.kind == BkControlKind.removeArm && c.arm == 0);
      expect(armSlot.rect.right, lessThanOrEqualTo(minus.rect.left - const BkMetrics().gap + 2.01));
      expect(minus.rect.right, lessThanOrEqualTo(blk.rect.right));
      expect(blk.rect.width, lessThanOrEqualTo(const BkMetrics().maxBlockWidth));
      for (final m in blk.mouths) {
        expect(m.rect.right, blk.rect.right);
      }
    });

    test('小按钮：每段一个“−”、可收起的否则一个“−”、底条一个“＋”；到了最少 / 最多就没有', () {
      final b = Bench([
        sampleIf(),
        sampleSwitch()..arms.removeLast(),
        LcBlock(op: 'try', arms: [LcArm()], noElse: true),
      ]);
      final l = b.script;
      List<String> kinds(BkBlock x) => [for (final c in x.controls) '${c.kind.name}${c.arm >= 0 ? c.arm : ''}'];
      final ifB = l.blockAt([lcStep(0)])!;
      expect(kinds(ifB), ['removeArm0', 'removeArm1', 'removeTail', 'add']);
      for (final c in ifB.controls) {
        expect(c.hitRect.width, greaterThanOrEqualTo(40));
        expect(c.hitRect.height, greaterThanOrEqualTo(40));
        expect(ifB.rect.contains(c.rect.center), isTrue);
      }
      // “−”在自己那条横栏上竖直居中；“＋”在底条上。
      expect(ifB.controls[0].rect.center.dy, closeTo(ifB.mouths[1].bar!.center.dy, 0.01));
      expect(ifB.controls[2].rect.center.dy, closeTo(ifB.mouths[3].bar!.center.dy, 0.01));
      expect(ifB.controls[3].rect.top, greaterThan(ifB.mouths.last.rect.bottom));
      // 分情况只剩一段（最少一段）：这一段没有“−”。
      expect(kinds(l.blockAt([lcStep(1)])!), ['removeTail', 'add']);
      // 试着做：正好一段（最少最多都是 1），收尾口收起来了：只有“＋”（加回“最后总要”）。
      final tryB = l.blockAt([lcStep(2)])!;
      expect(kinds(tryB), ['add']);
      expect([for (final m in tryB.mouths) m.arm], [-1, 0]);
      expect(tryB.mouths[1].bar!.height, const BkMetrics().dividerH, reason: '不带参数的段用矮横栏');
      expect(tryB.mouths[1].labels.single.text, '出错了');
      // 段到了上限、否则也在：没有“＋”，底条回到普通高度。
      final full = LcBlock(
        op: 'if',
        args: {'cond': fxBool(true)},
        arms: [
          for (var i = 0; i < 8; i++) LcArm(args: {'cond': fxBool(true)}),
        ],
      );
      final fullB = Bench([full]).script.blockAt([lcStep(0)])!;
      expect(fullB.controls.any((c) => c.kind == BkControlKind.add), isFalse);
      expect(fullB.rect.bottom, fullB.mouths.last.rect.bottom + const BkMetrics().footerH);
    });

    test('分情况：没有开头口，第一段的横栏紧贴着头；收起“都不是”以后少一个口', () {
      final b = Bench([sampleSwitch()]);
      final blk = b.script.blockAt([lcStep(0)])!;
      expect([for (final m in blk.mouths) m.arm], [0, 1, -1]);
      expect(blk.mouths[0].bar!.top, blk.head.bottom);
      expect(blk.mouths.last.label!.text, '都不是');
      expect(blk.mouths[0].labels.map((l) => l.text), ['是', '时']);
      final off = Bench([
        sampleSwitch()
          ..orElse.clear()
          ..noElse = true,
      ]).script.blockAt([lcStep(0)])!;
      expect([for (final m in off.mouths) m.arm], [0, 1]);
      expect(off.controls.last.kind, BkControlKind.add);
    });

    test('坏数据照样画：noElse 却还有否则的积木、规格没说有段却存了段、一段都没有的分情况', () {
      final weird = sampleIf()..noElse = true;
      expect(Bench([weird]).script.blockAt([lcStep(0)])!.mouths.last.inElse, isTrue, reason: '里面有积木就不藏');
      // “重复”的规格没有段，文件里却有：照样画出来，积木不丢，也没有增减按钮。
      final odd = LcBlock(
        op: 'repeat',
        args: {'times': fxNum(2)},
        arms: [
          LcArm(body: [say('藏着的')]),
        ],
      );
      final l = Bench([odd]).script;
      final blk = l.blockAt([lcStep(0)])!;
      expect([for (final m in blk.mouths) m.arm], [-1, 0]);
      expect(blk.controls, isEmpty);
      expect(l.blockAt([lcStep(0), lcStep(0, arm: 0)]), isNotNull);
      // 不认识的积木带着段。
      final unknown = LcBlock(
        op: 'nope',
        arms: [
          LcArm(args: {'x': 1}, body: [say('x')]),
          LcArm(),
        ],
      );
      expect(Bench([unknown]).script.blockAt([lcStep(0)])!.mouths, hasLength(2));
      final empty = LcBlock(op: 'switch', args: {'x': fxNum(1)}, noElse: true);
      final e = Bench([empty]).script.blockAt([lcStep(0)])!;
      expect(e.mouths, isEmpty);
      expect(e.controls.single.kind, BkControlKind.add);
    });

    test('每个口都有拼接点，照着拼接点插进去，新积木正好落在锚点上', () {
      final b = Bench([sampleIf(), sampleSwitch()]);
      final snaps = b.script.snaps.where((s) => s.kind == BkSnapKind.statement).toList();
      final keys = {for (final s in snaps) '${s.parent.length}|${s.parent.isEmpty ? '' : s.parent.last.index}|${s.inElse}|${s.arm}|${s.index}'};
      expect(keys.length, snaps.length, reason: '没有重复的拼接点');
      expect(snaps.where((s) => s.parent.length == 1 && s.parent.last.index == 0 && s.arm == 1), hasLength(1), reason: '空的那一段有一个落点');
      expect(snaps.where((s) => s.parent.length == 1 && s.parent.last.index == 0 && s.arm == 0), hasLength(2));
      for (final s in snaps) {
        final probe = LcBlock(op: 'break');
        final shown = bkEditedBody(b.tree.body, s.parent, s.inElse, arm: s.arm, (list) => list.insert(s.index, probe));
        final made = b.engine.layoutScript(b.tree, body: shown);
        final placed = made.blocks.firstWhere((x) => identical(x.block, probe));
        expect(placed.rect.topLeft, s.anchor, reason: '插在 ${s.parent} else=${s.inElse} arm=${s.arm} 第 ${s.index} 位');
        expect(placed.path.last.arm, s.arm);
      }
      // 预览用的副本不动原来的模型，也不丢段和 noElse。
      final src = sampleIf()..noElse = true;
      final copy = bkEditedBody([src], [lcStep(0)], false, arm: 1, (list) => list.add(say('新')));
      expect(src.arms[1].body, isEmpty);
      expect(copy.single.arms[1].body.single.op, 'say');
      expect(copy.single.arms, hasLength(2));
      expect(copy.single.noElse, isTrue);
      expect(identical(copy.single.arms[0], src.arms[0]), isTrue, reason: '没动的段共用');
    });

    test('点到小按钮算小按钮；紧挨着的槽还是槽；口里的空白不算', () {
      final l = Bench([sampleIf()]).script;
      final blk = l.blockAt([lcStep(0)])!;
      final minus = blk.controls[0], plus = blk.controls.last;
      expect(l.hitTest(minus.rect.center)!.control, same(minus));
      expect(l.hitTest(plus.rect.center)!.control, same(plus));
      // 小圆外面一点（放大的点击范围里）也算。
      expect(l.hitTest(plus.rect.center + const Offset(16, 0))!.control, same(plus));
      final slot = blk.mouths[1].slots.first;
      final hit = l.hitTest(slot.rect.center)!;
      expect(hit.control, isNull);
      expect(hit.slot, isNotNull);
      // 第 2 段的口是空的：点在里面什么都没点到。
      expect(l.hitTest(blk.mouths[2].rect.center), isNull);
      // 横栏上的字：点到的是积木本身。
      final onBar = l.hitTest(blk.mouths[1].labels.first.rect.center)!;
      expect(onBar.block, same(blk));
      expect(onBar.control, isNull);
      expect(onBar.slot, isNull);
    });

    test('旧的两个口的如果（前端宿主，规格没变）：排出来和以前一模一样——没有小按钮、底条 16、两个口', () {
      final doc = LcDocument.starter('t');
      final h = doc.logic.addHandler('load')!;
      h.body.add(
        LcBlock(
          op: 'if',
          args: {'cond': exBool(true)},
          body: [
            LcBlock(op: 'log', args: {'value': exNum(1)}),
          ],
        ),
      );
      final host = LogicBlockHost(doc: doc, onEdit: (c) => c(doc));
      final blk = BlockLayoutEngine(host, fakeMeasure).layoutScript(h).blockAt([lcStep(0)])!;
      expect(blk.controls, isEmpty);
      expect([for (final m in blk.mouths) (m.inElse, m.arm)], [(false, -1), (true, -1)]);
      expect(blk.mouths[1].bar!.height, 26);
      expect(blk.rect.bottom - blk.mouths[1].rect.bottom, 16);
      expect(blk.headSlots, blk.slots.length);
      expect(blk.headLabels, blk.labels.length);
    });
  });

  group('增减段', () {
    test('加一段、删一段、收起 / 加回收尾口：守最少最多', () {
      final host = FakeHost();
      final b = host.newBlock('if');
      expect(b.noElse, isTrue);
      expect(bkCanShowTail(host, b), isTrue);
      expect(bkAddArm(host, b), 0);
      expect((b.arms[0].args['cond'] as Map)['e'], 'bool', reason: '新的一段参数填好了默认值');
      expect(bkSetTail(host, b, shown: true), isTrue);
      expect(bkSetTail(host, b, shown: true), isFalse, reason: '已经在了');
      expect(b.noElse, isFalse);
      for (var i = 1; i < 8; i++) {
        expect(bkAddArm(host, b), i);
      }
      expect(bkCanAddArm(host, b), isFalse);
      expect(bkAddArm(host, b), -1);
      expect(bkRemoveArm(host, b, 3), isTrue);
      expect(bkRemoveArm(host, b, 99), isFalse);
      expect(b.arms, hasLength(7));
      b.orElse.add(say('x'));
      expect(bkSetTail(host, b, shown: false), isTrue);
      expect(b.orElse, isEmpty);
      expect(b.noElse, isTrue);
      // 分情况至少留一段。
      final sw = host.newBlock('switch');
      expect(bkRemoveArm(host, sw, 0), isFalse);
      expect(bkAddArm(host, sw), 1);
      expect(bkRemoveArm(host, sw, 0), isTrue);
      // 规格没说有段的积木：什么都不做。
      final rp = host.newBlock('repeat');
      expect(bkAddArm(host, rp), -1);
      expect(bkSetTail(host, rp, shown: false), isFalse);
      expect(bkCanShowTail(host, rp), isFalse);
    });

    test('副本的参数是深拷贝（含各段的），改副本不动原件', () {
      final src = sampleIf();
      final copy = bkCopyArgs(src);
      (copy.arms[0].args['cond'] as Map)['op'] = '<';
      copy.args['cond'] = fxBool(false);
      expect((src.arms[0].args['cond'] as Map)['op'], '>');
      expect((src.args['cond'] as Map)['e'], 'cmp');
      expect(identical(copy.arms[0].body, src.arms[0].body), isTrue);
      final deep = src.clone();
      deep.arms[0].body.clear();
      expect(src.arms[0].body, hasLength(1));
    });
  });

  group('拖进拖出各个口', () {
    test('从“那么”拖进第 2 段：一次改动；落点阴影记着是哪一段；撤销回到原样', () {
      final b = Bench([sampleIf()]);
      final before = b.host.encode();
      final d = b.grab([lcStep(0), lcStep(0)]);
      expect(b.texts(d.blocks), ['A']);
      final to = b.at(d, [lcStep(0)], 0, arm: 1);
      expect(d.update(to + const Offset(6, 5)), isTrue);
      expect(d.ghost!.arm, 1);
      expect(d.target!.noop, isFalse);
      // 让位以后的排布里，落点那一段的口变高了，阴影在里面。
      final shown = d.display.placed('s1')!.layout;
      final ghost = shown.blockAt([lcStep(0), lcStep(0, arm: 1)])!;
      expect(shown.blockAt([lcStep(0)])!.mouths[2].rect.contains(ghost.rect.center), isTrue);
      final placed = d.commit(to)!;
      expect(placed.path.last.arm, 1);
      expect(b.host.edits, 1);
      final blk = b.tree.body.single;
      expect(blk.body, isEmpty);
      expect(b.texts(blk.arms[1].body), ['A']);
      b.host.undo();
      expect(b.host.encode(), before);
      b.host.redo();
      expect(b.texts(b.tree.body.single.arms[1].body), ['A']);
    });

    test('从段里拖出来放到最外层、放到另一串；从否则拖进第 1 段的中间', () {
      final b = Bench([sampleIf()]);
      var d = b.grab([lcStep(0), lcStep(0, arm: 0)]);
      var to = b.at(d, const [], 1);
      expect(d.update(to), isTrue);
      expect(d.commit(to)!.path, [lcStep(1)]);
      expect(b.texts(b.tree.body), ['if', 'B']);
      expect(b.tree.body.first.arms[0].body, isEmpty);
      d = b.grab([lcStep(1)]);
      to = b.at(d, const [], 1, scriptId: 's2');
      expect(d.update(to), isTrue);
      expect(d.commit(to)!.scriptId, 's2');
      expect(b.texts(b.host.script('s2')!.body), ['另一串', 'B']);
      // 再把另一串那块拿回第 1 段，然后把“否则”里的 D 插到它前面。
      final l = b.layout;
      final p2 = l.placed('s2')!;
      d = BkDragSession.fromHit(b.host, b.engine, l, p2, BkHit(p2.layout.blockAt([lcStep(1)])!))!;
      to = b.at(d, [lcStep(0)], 0, arm: 0);
      expect(d.update(to), isTrue);
      expect(d.commit(to), isNotNull);
      d = b.grab([lcStep(0), lcStep(0, inElse: true)]);
      to = b.at(d, [lcStep(0)], 0, arm: 0);
      expect(d.update(to), isTrue);
      expect(d.commit(to), isNotNull);
      expect(b.texts(b.tree.body.single.arms[0].body), ['D', 'B']);
      expect(b.tree.body.single.orElse, isEmpty);
    });

    test('放回段里原来的位置＝没动；弹回去时落点对回原来那一段', () {
      final b = Bench([sampleIf()]);
      final d = b.grab([lcStep(0), lcStep(0, arm: 0)]);
      final home = b.at(d, [lcStep(0)], 0, arm: 0);
      expect(d.update(home), isTrue);
      expect(d.target!.noop, isTrue);
      expect(d.check(home), BkDropResult.noop);
      expect(d.commit(home), isNull);
      expect(b.host.edits, 0);
      // 同一个下标、别的口不算原处。
      final other = b.at(d, [lcStep(0)], 0, arm: 1);
      expect(d.update(other), isTrue);
      expect(d.target!.noop, isFalse);
      expect(d.aimHome(), isTrue);
      expect(d.target!.noop, isTrue);
      expect(d.target!.snap.arm, 0);
    });

    test('整块多口积木拖走：里面各段的积木一起走；不能拖进自己的段里', () {
      final b = Bench([say('前'), sampleIf()]);
      final d = b.grab([lcStep(1)]);
      expect(d.deleteCount, 4);
      final snaps = d.base.placed('s1')!.layout.snaps.where((x) => x.kind == BkSnapKind.statement);
      expect(snaps.every((x) => x.parent.isEmpty), isTrue, reason: '拿走以后没有自己里面的落点');
      final to = b.at(d, const [], 0);
      expect(d.update(to), isTrue);
      expect(d.commit(to), isNotNull);
      expect(b.texts(b.tree.body), ['if', '前']);
      expect(b.tree.body.first.arms, hasLength(2));
      expect(b.texts(b.tree.body.first.arms[0].body), ['B']);
    });

    test('从积木盒拿一块新的放进段里；新拿的“分情况”自带一段', () {
      final b = Bench([sampleIf()]);
      final l = b.layout;
      final piece = b.engine.layoutStack([b.host.newBlock('switch')]);
      final d = BkDragSession.fromPalette(b.host, b.engine, l, const BkPaletteSource(BkDragKind.statement, 'switch'), piece);
      final to = b.at(d, [lcStep(0)], 1, arm: 0);
      expect(d.update(to), isTrue);
      final placed = d.commit(to)!;
      expect(placed.path, [lcStep(0), lcStep(1, arm: 0)]);
      final made = b.tree.blockAt(placed.path)!;
      expect(made.op, 'switch');
      expect(made.arms, hasLength(1));
    });

    test('表达式拖进段的条件槽：换进去，原来的值交换回来', () {
      final b = Bench([sampleIf()]);
      final l = b.layout;
      final p = l.placed('s1')!;
      final blk = p.layout.blockAt([lcStep(0)])!;
      final headSlot = blk.slots.first;
      final d = BkDragSession.fromHit(b.host, b.engine, l, p, BkHit(blk, slot: headSlot, expr: headSlot.expr))!;
      expect(d.kind, BkDragKind.expr);
      final target = d.base.placed('s1')!.layout.snaps.firstWhere((s) => s.kind == BkSnapKind.expr && s.arg == '@1:cond' && s.exprPath.isEmpty);
      final at = p.origin + target.rect.centerLeft - Offset(6, d.piece.size.height / 2) + const Offset(2, 0);
      expect(d.update(at), isTrue);
      expect(d.target!.snap.arg, '@1:cond');
      expect(d.commit(at), isNotNull);
      final m = b.tree.body.single;
      expect((m.arms[1].args['cond'] as Map)['e'], 'cmp');
      expect((m.args['cond'] as Map)['e'], 'bool', reason: '第 2 段原来的“是”换回了头上');
      expect(d.swapped, isTrue);
    });
  });
}
