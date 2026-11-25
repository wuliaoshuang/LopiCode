// 积木让位动画、表达式交换的纯逻辑（lib/blocks/block_motion.dart、block_drag.dart）的单元测试：不搭界面，量字宽用假的。
// 外加一条粗略的性能冒烟：200 块积木的一串，拖动时不许每动一下就把所有串重排一遍。
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/blocks/block_canvas_layout.dart';
import 'package:lopicode/blocks/block_drag.dart';
import 'package:lopicode/blocks/block_geometry.dart';
import 'package:lopicode/blocks/block_motion.dart';
import 'package:lopicode/lowcode/logic_blocks.dart';
import 'package:lopicode/lowcode/logic_model.dart';
import 'package:lopicode/lowcode/model.dart';

import 'blocks_drag_test.dart' show Bench;
import 'support/blocks_fixture.dart';

/// 一串 `n` 块积木（中间夹几个 C 形块），外加两串小的。
LcDocument bigDoc(int n) {
  final doc = sampleDoc();
  final body = doc.logic.handlers[0].body..clear();
  for (var i = 0; i < n; i++) {
    body.add(
      i % 20 == 7
          ? LcBlock(
              op: 'repeat',
              args: {'times': exNum(i)},
              body: [
                LcBlock(op: 'alert', args: {'message': exText('第 $i 块')}),
              ],
            )
          : LcBlock(op: 'changeVar', args: {'name': 'count', 'by': exNum(i)}),
    );
  }
  return doc;
}

Rect frameOf(BkCanvasLayout l, String id, LcBlockPath path) {
  final p = l.placed(id)!;
  return p.layout.blockAt(path)!.rect.shift(p.origin);
}

void main() {
  test('落下的缩放回弹：1.04 → 0.98 → 1.0，中间不乱跳', () {
    expect(bkLandScale(0), 1.04);
    expect(bkLandScale(1), 1.0);
    expect(bkLandScale(0.55), closeTo(0.98, 1e-9));
    var low = 2.0;
    for (var i = 0; i <= 100; i++) {
      final v = bkLandScale(i / 100);
      expect(v, inInclusiveRange(0.98 - 1e-9, 1.04 + 1e-9));
      if (v < low) low = v;
    }
    expect(low, closeTo(0.98, 1e-3));
    // 前半段一路往下，后半段一路往上。
    for (var i = 1; i <= 55; i++) {
      expect(bkLandScale(i / 100), lessThanOrEqualTo(bkLandScale((i - 1) / 100) + 1e-9));
    }
    for (var i = 56; i <= 100; i++) {
      expect(bkLandScale(i / 100), greaterThanOrEqualTo(bkLandScale((i - 1) / 100) - 1e-9));
    }
  });

  test('路径换算：让出一截以后的路径换回原来的；落点阴影里的没有名字', () {
    const BkRoom room = (scriptId: 's', parent: [], inElse: false, arm: -1, start: 1, count: 2);
    expect(bkPathBeforeRoom([lcStep(0)], room), [lcStep(0)]);
    expect(bkPathBeforeRoom([lcStep(1)], room), isNull);
    expect(bkPathBeforeRoom([lcStep(2), lcStep(0)], room), isNull, reason: '阴影里面的子积木也算阴影');
    expect(bkPathBeforeRoom([lcStep(3)], room), [lcStep(1)]);
    expect(bkPathBeforeRoom([lcStep(4), lcStep(0, inElse: true)], room), [lcStep(2), lcStep(0, inElse: true)]);
    // 口里的一截：只动同一个口里的。
    final BkRoom inner = (scriptId: 's', parent: [lcStep(1)], inElse: true, arm: -1, start: 0, count: 1);
    expect(bkPathBeforeRoom([lcStep(1), lcStep(0)], inner), [lcStep(1), lcStep(0)], reason: '“那么”口里的不受“否则”口影响');
    expect(bkPathBeforeRoom([lcStep(1), lcStep(0, inElse: true)], inner), isNull);
    expect(bkPathBeforeRoom([lcStep(1), lcStep(1, inElse: true)], inner), [lcStep(1), lcStep(0, inElse: true)]);
    expect(bkPathBeforeRoom([lcStep(2)], inner), [lcStep(2)]);
    expect(bkMotionKey('s', [lcStep(1), lcStep(0, inElse: true)]), isNot(bkMotionKey('s', [lcStep(1), lcStep(0)])));
  });

  test('让位：下面的积木从原位滑到让开以后的位置，中间态在两头之间；中途换落点从当时的位置接着走', () {
    final b = Bench(sampleDoc());
    final id = b.hs[0].id;
    final d = b.grab(0, [lcStep(2)]); // 拿走最后的“重复”
    final m = BkMotion()..jump(d.normal);
    m.retarget(d.display);
    expect(m.moving, isFalse, reason: '拿走最后一块，别的都不用动');

    // 对到最前面：两块都要往下让。
    expect(d.update(b.at(d, 0, const [], 0)), isTrue);
    final ghost = d.ghost!;
    expect((ghost.start, ghost.count), (0, 1));
    m.retarget(d.display, room: ghost);
    expect(m.moveCount, greaterThanOrEqualTo(2));
    final from = frameOf(d.base, id, [lcStep(0)]), to = frameOf(d.display, id, [lcStep(1)]);
    expect(to.top, greaterThan(from.top));
    final key = bkMotionKey(id, [lcStep(0)]);
    expect(m.frameByKey(key, 0)!.rect, from);
    expect(m.frameByKey(key, 1)!.rect, to);
    final mid = m.frameByKey(key, 0.5)!.rect;
    expect(mid.top, closeTo((from.top + to.top) / 2, 0.01));
    final shown = d.display.placed(id)!.layout.blockAt([lcStep(1)])!;
    expect(m.frameOf(shown, 0.5)!.rect, mid);
    expect(m.frameOf(shown, 1), isNull, reason: '到位了就按排版画');
    final ghostBlock = d.display.placed(id)!.layout.blockAt([lcStep(0)])!;
    expect(m.frameOf(ghostBlock, 0.5), isNull, reason: '落点阴影不滑');

    // 滑到一半改主意，对到第 1、2 块之间：第一块从半路滑回去，不跳。
    expect(d.update(b.at(d, 0, const [], 1)), isTrue);
    m.retarget(d.display, room: d.ghost, progress: 0.5);
    expect(m.frameByKey(key, 0)!.rect, mid);
    expect(m.frameByKey(key, 1)!.rect, from);

    // C 形块里让位：外层的口跟着长高，外形一起插值。
    expect(d.update(b.at(d, 0, [lcStep(1)], 0)), isTrue);
    m.jump(d.base);
    m.retarget(d.display, room: d.ghost);
    final outer = bkMotionKey(id, [lcStep(1)]);
    final f0 = m.frameByKey(outer, 0)!, f1 = m.frameByKey(outer, 1)!, fh = m.frameByKey(outer, 0.5)!;
    expect(f1.mouths.first.height, greaterThan(f0.mouths.first.height));
    expect(fh.mouths.first.height, closeTo((f0.mouths.first.height + f1.mouths.first.height) / 2, 0.01));
    expect(fh.rect.height, closeTo((f0.rect.height + f1.rect.height) / 2, 0.01));
  });

  test('弹回前把落点对回原位：原位让出空来', () {
    final b = Bench(sampleDoc());
    final d = b.grab(0, [lcStep(0)]);
    d.update(const Offset(900, 900));
    expect(d.target, isNull);
    expect(d.aimHome(), isTrue);
    final g = d.ghost!;
    expect(g.parent, isEmpty);
    expect((g.start, g.count), (0, 3), reason: '拿第一块会带走它下面的两块');
    expect(d.target!.noop, isTrue);
    expect(d.check(const Offset(900, 900)), isNot(BkDropResult.applied));
    expect(b.edits, 0);
  });

  group('表达式拖进有值的槽', () {
    BkDragSession grabExpr(Bench b, int i, LcBlockPath path, String arg, BkExprPath ep) {
      final l = b.layout;
      final p = l.placed(b.hs[i].id)!;
      for (final (blk, sl) in p.layout.allSlots) {
        if (!blk.isHat && bkSameBlockPath(blk.path, path) && sl.arg == arg && bkSameExprPath(sl.exprPath, ep) && sl.expr != null) {
          return BkDragSession.fromHit(b.host, b.engine, l, p, BkHit(blk, slot: sl, expr: sl.expr))!;
        }
      }
      throw StateError('没找到表达式');
    }

    Offset slotAt(BkDragSession d, Bench b, int i, LcBlockPath block, String arg, [BkExprPath ep = const []]) {
      final p = d.base.placed(b.hs[i].id)!;
      final snap = p.layout.snaps.firstWhere((x) => x.kind == BkSnapKind.expr && bkSameBlockPath(x.parent, block) && x.arg == arg && bkSameExprPath(x.exprPath, ep));
      return p.origin + snap.rect.topLeft + const Offset(2, 0);
    }

    test('从槽里拖来的：两个值交换，一次改动，谁也不丢', () {
      final b = Bench(sampleDoc());
      final d = grabExpr(b, 0, [lcStep(1)], 'cond', const ['r']);
      expect(exprKind(d.expr), 'not');
      final at = slotAt(d, b, 0, [lcStep(1), lcStep(0)], 'message');
      d.update(at);
      expect(d.commit(at), isNotNull);
      expect(b.edits, 1);
      expect(d.swapped, isTrue);
      expect(d.droppedExpr, isNull);
      final cond = b.hs[0].body[1].args['cond'] as Map<String, dynamic>;
      expect(b.hs[0].body[1].body[0].args['message'], exNot(exVar('ok')));
      expect(cond['r'], exText('点太多次啦'), reason: '被换下来的值回到被拖的那块原来的槽里');
    });

    test('从“一串值”里拖走一项去换：换下来的值插回原来的位置，项数不变', () {
      final b = Bench(sampleDoc());
      // “点了 ”、count、“ 次” 里的 count 拖去换 “把 count 设为 0” 的 0。
      final d = grabExpr(b, 0, [lcStep(1), lcStep(0, inElse: true)], 'value', const ['items', 1]);
      expect(exprKind(d.expr), 'var');
      final at = slotAt(d, b, 0, [lcStep(1), lcStep(1)], 'value');
      d.update(at);
      expect(d.commit(at), isNotNull);
      expect(d.swapped, isTrue);
      expect(b.hs[0].body[1].body[1].args['value'], exVar('count'));
      final join = b.hs[0].body[1].orElse[0].args['value'] as Map<String, dynamic>;
      expect(join['items'], [exText('点了 '), exNum(0), exText(' 次')]);
      expect(b.edits, 1);
    });

    test('把里面的一块拖出来盖住外面整块：没法交换，原值记在 droppedExpr 里', () {
      final b = Bench(sampleDoc());
      final d = grabExpr(b, 0, [lcStep(1)], 'cond', const ['r']);
      final at = slotAt(d, b, 0, [lcStep(1)], 'cond');
      d.update(at);
      expect(d.target, isNotNull);
      expect(d.commit(at), isNotNull);
      expect(b.hs[0].body[1].args['cond'], exNot(exVar('ok')));
      expect(d.swapped, isFalse);
      expect(exprKind(d.droppedExpr), 'bin');
      expect(b.edits, 1);
    });
  });

  test('性能冒烟：200 块的一串，拖动时每换一个落点最多重排一串，同一个落点上怎么动都不重排', () {
    final b = Bench(bigDoc(200));
    final watch = Stopwatch()..start();
    final d = b.grab(1, [lcStep(1)]); // 从第二串拿一块，往大串里放
    final afterGrab = b.engine.scriptLayouts;
    final m = BkMotion()..jump(d.normal);
    m.retarget(d.display);
    var changes = 0, most = 0;
    for (var i = 0; i < 60; i++) {
      final at = b.at(d, 0, const [], 3 + i ~/ 6);
      for (var frame = 0; frame < 4; frame++) {
        final before = b.engine.scriptLayouts;
        final changed = d.update(at + Offset(frame * 0.5, frame * 0.5));
        final cost = b.engine.scriptLayouts - before;
        if (cost > most) most = cost;
        if (changed) {
          changes++;
          m.retarget(d.display, room: d.ghost, progress: 0.4);
        } else {
          expect(cost, 0, reason: '落点没变不许重排');
        }
        // 每帧只做插值：不排版。
        final shown = d.display.placed(b.hs[0].id)!.layout;
        for (final blk in shown.blocks) {
          m.frameOf(blk, 0.3);
        }
        expect(b.engine.scriptLayouts - before, cost);
      }
    }
    watch.stop();
    expect(changes, 10);
    expect(most, lessThanOrEqualTo(1), reason: '换落点只重排落点那一串（三串里的一串）');
    expect(b.engine.scriptLayouts - afterGrab, lessThanOrEqualTo(changes));
    // 240 帧。阈值放得很宽，只防明显退化（本机实际几十毫秒）。
    expect(watch.elapsedMilliseconds, lessThan(4000));
    printOnFailure('200 块 240 帧：${watch.elapsedMilliseconds} ms，重排 ${b.engine.scriptLayouts - afterGrab} 次');
  });
}
