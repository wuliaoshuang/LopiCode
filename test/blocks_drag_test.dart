// 积木拖拽与改模型的纯逻辑（lib/blocks/block_ops.dart、block_drag.dart）的单元测试：不搭界面，量字宽用假的。
import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/blocks/block_canvas_layout.dart';
import 'package:lopicode/blocks/block_drag.dart';
import 'package:lopicode/blocks/block_geometry.dart';
import 'package:lopicode/blocks/block_layout.dart';
import 'package:lopicode/blocks/block_ops.dart';
import 'package:lopicode/lowcode/logic_block_host.dart';
import 'package:lopicode/lowcode/logic_blocks.dart';
import 'package:lopicode/lowcode/logic_model.dart';
import 'package:lopicode/lowcode/model.dart';

import 'support/blocks_fixture.dart';

double fakeMeasure(String s) => s.runes.fold(0.0, (w, r) => w + (r < 128 ? 8 : 14));

class Bench {
  Bench(this.doc) {
    host = LogicBlockHost(
      doc: doc,
      onEdit: (change) {
        edits++;
        change(doc);
      },
    );
    engine = BlockLayoutEngine(host, fakeMeasure);
  }
  final LcDocument doc;
  late final LogicBlockHost host;
  late final BlockLayoutEngine engine;
  int edits = 0;

  BkCanvasLayout get layout => layoutBlockCanvas(host, engine);
  List<LcHandler> get hs => doc.logic.handlers;
  List<String> ops(int i) => [for (final b in hs[i].body) b.op];

  /// 抓起第 i 串里某条路径上的积木（路径空＝帽子）。
  BkDragSession grab(int i, LcBlockPath path) {
    final l = layout;
    final p = l.placed(hs[i].id)!;
    final b = path.isEmpty ? p.layout.hat! : p.layout.blockAt(path)!;
    return BkDragSession.fromHit(host, engine, l, p, BkHit(b))!;
  }

  /// 把手上那截的左上角对到某个拼接点。
  Offset at(BkDragSession d, int i, LcBlockPath parent, int index, {bool inElse = false}) {
    final p = d.base.placed(hs[i].id)!;
    final snap = p.layout.snaps.firstWhere((x) => x.kind == BkSnapKind.statement && bkSameBlockPath(x.parent, parent) && x.inElse == inElse && x.index == index);
    return p.origin + snap.anchor;
  }
}

void main() {
  test('拿起中间一块：带走下面整串，原位合拢；放回原处＝没动，不产生改动', () {
    final b = Bench(sampleDoc());
    final d = b.grab(0, [lcStep(1)]);
    expect(d.kind, BkDragKind.statement);
    expect([for (final x in d.blocks) x.op], ['if', 'repeat']);
    expect(d.base.placed(b.hs[0].id)!.layout.blocks.where((x) => !x.isHat && x.path.length == 1), hasLength(1));
    final home = b.at(d, 0, const [], 1);
    expect(d.update(home), isTrue);
    expect(d.target!.noop, isTrue);
    expect(d.check(home), BkDropResult.noop);
    expect(d.commit(home), isNull);
    expect(b.edits, 0);
    expect(b.ops(0), ['changeVar', 'if', 'repeat']);
  });

  test('吸附半径内才有落点；跨脚本放下是一次改动', () {
    final b = Bench(sampleDoc());
    final d = b.grab(0, [lcStep(2)]);
    final to = b.at(d, 1, const [], 2);
    expect(d.update(const Offset(3000, 3000)), isFalse);
    expect(d.target, isNull);
    expect(d.check(const Offset(3000, 3000)), BkDropResult.rejected);
    expect(d.rejectReason, contains('事件下面'));
    expect(d.update(to + const Offset(10, 8)), isTrue);
    expect(d.ghost, isNotNull);
    expect(d.commit(to + const Offset(10, 8))!.scriptId, b.hs[1].id);
    expect(b.edits, 1);
    expect(b.ops(0), ['changeVar', 'if']);
    expect(b.ops(1), ['setVar', 'setProp', 'repeat']);
  });

  test('不能拖进自己：拿走以后的排布里根本没有自己里面的拼接点', () {
    final b = Bench(sampleDoc());
    final d = b.grab(0, [lcStep(1)]);
    final snaps = d.base.placed(b.hs[0].id)!.layout.snaps.where((x) => x.kind == BkSnapKind.statement);
    expect(snaps.every((x) => x.parent.isEmpty), isTrue);
  });

  test('嵌套太深：放不下，拒绝并给原因，模型不变', () {
    final b = Bench(sampleDoc());
    // 第 0 串末尾套 10 层“如果”；第 1 串开头放一截 5 层高的。
    var parent = <LcBlockStep>[];
    for (var i = 0; i < 10; i++) {
      expect(b.hs[0].insertBlock(parent, b.host.newBlock('if')), isTrue);
      parent = [...parent, lcStep(i == 0 ? 3 : 0)];
    }
    var inner = <LcBlockStep>[];
    for (var i = 0; i < 5; i++) {
      expect(b.hs[1].insertBlock(inner, b.host.newBlock('if'), index: 0), isTrue);
      inner = [...inner, lcStep(0)];
    }
    final d = b.grab(1, [lcStep(0)]);
    expect(d.blocks.first.height, greaterThanOrEqualTo(5));
    final enc = b.doc.encode();
    final to = b.at(d, 0, parent, 0);
    expect(d.update(to), isTrue);
    expect(d.check(to), BkDropResult.rejected);
    expect(d.rejectReason, contains('太深'));
    expect(d.commit(to), isNull);
    expect(b.edits, 0);
    expect(b.doc.encode(), enc);
  });

  test('拖帽子：写下这一串的位置，别的自动排的串一起固定；删除＝删整串', () {
    final b = Bench(sampleDoc());
    final auto = {for (final p in b.layout.scripts) p.id: p.origin};
    expect(b.hs.every((h) => h.x == null && h.y == null), isTrue);
    final d = b.grab(1, const []);
    expect(d.kind, BkDragKind.hat);
    expect(d.commit(const Offset(400, 90))!.path, isEmpty);
    expect(b.edits, 1);
    expect(Offset(b.hs[1].x!, b.hs[1].y!), const Offset(400, 90));
    expect(Offset(b.hs[0].x!, b.hs[0].y!), auto[b.hs[0].id]);
    expect(Offset(b.hs[2].x!, b.hs[2].y!), auto[b.hs[2].id]);

    final d2 = b.grab(2, const []);
    expect(d2.deleteCount, 1 + bkCountBlocks(b.hs[2].body));
    expect(d2.delete(), isTrue);
    expect(b.hs, hasLength(2));
  });

  test('宿主在拖动中被别人改了：这次拖动作废', () {
    final b = Bench(sampleDoc());
    final d = b.grab(0, [lcStep(0)]);
    final to = b.at(d, 1, const [], 0);
    b.host.edit(() => b.hs[2].body.clear());
    expect(d.check(to), BkDropResult.noop);
    expect(d.commit(to), isNull);
    expect(d.delete(), isFalse);
    expect(b.ops(0), ['changeVar', 'if', 'repeat']);
  });

  test('拿走表达式：普通槽恢复默认；一串值里去掉一项，只剩一项时换成默认', () {
    final b = Bench(sampleDoc());
    final cond = b.hs[0].body[1];
    final taken = bkTakeExpr(b.host, cond, 'cond', const ['r']);
    expect(exprKind(taken), 'not');
    expect(asExpr(bkExprAt(cond, 'cond', const ['r'])), isNotNull);
    expect(exprKind(bkExprAt(cond, 'cond', const ['r'])), isNot('not'));

    final join = b.hs[0].body[1].orElse[0];
    List<dynamic> items() => (join.args['value'] as Map<String, dynamic>)['items'] as List;
    expect(exprKind(bkTakeExpr(b.host, join, 'value', const ['items', 1])), 'var');
    expect(items(), hasLength(2));
    expect(bkTakeExpr(b.host, join, 'value', const ['items', 0]), isNotNull);
    expect(bkTakeExpr(b.host, join, 'value', const ['items', 0]), isNotNull);
    expect(items(), hasLength(1), reason: '最后一项不去掉，换成默认值');
    expect(bkTakeExpr(b.host, join, 'value', const ['items', 9]), isNull);
    expect(bkAddListItem(b.host, join, 'value', const ['items']), isTrue);
    expect(items(), hasLength(2));
    expect(bkAddListItem(b.host, join, 'value', const ['nope']), isFalse);
  });

  test('一串长高了：正下方已固定的串往下让，旁边的不动', () {
    final b = Bench(sampleDoc());
    b.hs[0]
      ..x = 20
      ..y = 20;
    final h0 = b.layout.placed(b.hs[0].id)!.layout.size.height;
    b.hs[1]
      ..x = 30
      ..y = 20 + h0 + 10;
    b.hs[2]
      ..x = 900
      ..y = 20 + h0 + 10;
    final before = b.layout;
    final moved = bkPushedOrigins(before, b.hs[0].id, h0 + 64);
    expect(moved[b.hs[1].id], Offset(30, 20 + h0 + 10 + 64));
    expect(moved[b.hs[2].id], Offset(900, 20 + h0 + 10), reason: '不在正下方的不动');
    expect(moved[b.hs[0].id], const Offset(20, 20));
    final shrunk = bkPushedOrigins(before, b.hs[0].id, h0 - 40);
    expect(shrunk[b.hs[1].id], Offset(30, 20 + h0 + 10), reason: '只推不拉');
  });
}
