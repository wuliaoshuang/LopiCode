// 多口积木的纯逻辑测试（续）：拖进拖出各个口、让位、撤销重做。从 blocks_arms_test.dart 拆出来的（文件不超过 600 行）。
// 不搭界面，量字宽用假的；宿主用测试专用的假宿主（test/support/blocks_fake_host.dart）。

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/blocks/block_canvas_layout.dart';
import 'package:lopicode/blocks/block_drag.dart';
import 'package:lopicode/blocks/block_geometry.dart';
import 'package:lopicode/blocks/block_layout.dart';
import 'package:lopicode/lowcode/logic_model.dart';

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
