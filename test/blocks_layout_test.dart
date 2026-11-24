// 积木排版引擎（lib/blocks/block_layout.dart）和宿主接口的单元测试：几何、换行、可拼接点与模型路径一一对应、
// 深嵌套和坏数据不崩。量字宽用假的（每个字 14、ASCII 8），所以结果是确定的。
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/blocks/block_colors.dart';
import 'package:lopicode/blocks/block_geometry.dart';
import 'package:lopicode/blocks/block_host.dart';
import 'package:lopicode/blocks/block_layout.dart';
import 'package:lopicode/blocks/block_shapes.dart';
import 'package:lopicode/lowcode/logic_block_host.dart';
import 'package:lopicode/lowcode/logic_blocks.dart';
import 'package:lopicode/lowcode/logic_model.dart';
import 'package:lopicode/lowcode/model.dart';

import 'support/blocks_fixture.dart';

double fakeMeasure(String s) => s.runes.fold(0.0, (w, r) => w + (r < 128 ? 8 : 14));

const m = BkMetrics();

LogicBlockHost hostOf(LcDocument doc) => LogicBlockHost(doc: doc, onEdit: (change) => change(doc));

BlockLayoutEngine engineOf(BlockHost host) => BlockLayoutEngine(host, fakeMeasure);

void main() {
  group('模板', () {
    test('拆成文字和参数；没提到的参数接在后面；不认识的 {x} 当文字', () {
      final spec = lcBlockSpecs['setProp']!;
      final parts = parseBlockSentence('把 {node} 的 {prop} 改成 {value}', spec.args);
      expect([for (final p in parts) p.arg ?? p.text], ['把', 'node', '的', 'prop', '改成', 'value']);
      final missing = parseBlockSentence('改 {node} {nope}', spec.args);
      expect([for (final p in missing) p.arg ?? p.text], ['改', 'node', '{nope}', '改什么', 'prop', '改成', 'value']);
    });

    test('通用排法：每种积木、表达式都能排出来，参数一个不少', () {
      for (final s in lcBlockSpecs.values) {
        final parts = parseBlockSentence(defaultBlockSentence(s), s.args);
        expect({for (final p in parts) ?p.arg}, {for (final a in s.args) a.name}, reason: s.op);
      }
      for (final s in lcExprSpecs.values) {
        final parts = parseBlockSentence(defaultExprSentence(s), s.args);
        expect({for (final p in parts) ?p.arg}, {for (final a in s.args) a.name}, reason: s.kind);
      }
    });

    test('前端宿主给的模板：参数名都对得上目录', () {
      final host = hostOf(sampleDoc());
      for (final s in lcBlockSpecs.values) {
        final t = host.blockSentence(s.op);
        expect(t, isNotNull, reason: s.op);
        for (final hit in RegExp(r'\{(\w+)\}').allMatches(t!)) {
          expect(s.arg(hit[1]!), isNotNull, reason: '${s.op} 的模板里有不存在的参数 ${hit[1]}');
        }
      }
    });
  });

  group('一串脚本的几何', () {
    late LogicBlockHost host;
    late BkScriptLayout layout;
    setUp(() {
      host = hostOf(sampleDoc());
      layout = engineOf(host).layoutScript(host.script('h1')!);
    });

    test('帽子在最上面，下面的积木上下紧贴、左边对齐', () {
      final hat = layout.hat!;
      expect(hat.rect.top, 0);
      expect(hat.path, isEmpty);
      final top = [
        for (final b in layout.blocks)
          if (b.path.length == 1) b,
      ];
      expect(top, hasLength(3));
      expect(top.first.rect.top, hat.rect.bottom);
      for (var i = 1; i < top.length; i++) {
        expect(top[i].rect.top, top[i - 1].rect.bottom, reason: '上一块的凸起要正好落进下一块的凹口');
        expect(top[i].rect.left, top[0].rect.left);
      }
      expect(layout.size.height, top.last.rect.bottom + m.notchD + m.edgeH);
    });

    test('每块积木不矮于 40、自己那条不宽于最大宽度；槽位都在积木头里', () {
      for (final b in layout.blocks) {
        expect(b.head.height, greaterThanOrEqualTo(40));
        expect(b.head.width, lessThanOrEqualTo(m.maxBlockWidth));
        for (final s in b.slots) {
          expect(b.head.contains(s.rect.topLeft) && b.head.contains(s.rect.bottomRight - const Offset(0.01, 0.01)), isTrue, reason: '${b.block?.op} 的槽 ${s.arg} 跑到积木外面了');
        }
      }
    });

    test('C / E 形：口里的积木缩进一个胳膊宽，口正好包住它们，口之间有带标签的横栏', () {
      final ifBlock = layout.blockAt([lcStep(1)])!;
      expect(ifBlock.shape, BkShape.mouth);
      expect(ifBlock.mouths, hasLength(2));
      final body = ifBlock.mouths[0], orElse = ifBlock.mouths[1];
      expect(body.inElse, isFalse);
      expect(orElse.inElse, isTrue);
      expect(body.bar, isNull);
      expect(orElse.label!.text, '否则');
      expect(body.rect.top, ifBlock.head.bottom);
      expect(orElse.bar!.top, body.rect.bottom);
      expect(orElse.rect.top, orElse.bar!.bottom);
      expect(ifBlock.rect.bottom, orElse.rect.bottom + m.footerH);

      final first = layout.blockAt([lcStep(1), lcStep(0)])!, second = layout.blockAt([lcStep(1), lcStep(1)])!;
      expect(first.rect.left, ifBlock.rect.left + m.armW);
      expect(first.rect.top, body.rect.top);
      expect(second.rect.top, first.rect.bottom);
      expect(body.rect.bottom, second.rect.bottom);
      final inElse = layout.blockAt([lcStep(1), lcStep(0, inElse: true)])!;
      expect(inElse.rect.top, orElse.rect.top);
      expect(inElse.block!.op, 'setProp');

      // 空的口有最小高度。
      final repeat = layout.blockAt([lcStep(2)])!;
      expect(repeat.mouths.single.rect.height, m.mouthMinH);
    });

    test('表达式：是 / 否的是六边形，其余是胶囊；直接填的值是光杆输入框；嵌套的在外层里面', () {
      final ifBlock = layout.blockAt([lcStep(1)])!;
      final cond = ifBlock.slots.single;
      expect(cond.look, BkSlotLook.expr);
      expect(cond.hex, isTrue);
      final and = cond.expr!;
      expect(and.kind, 'bin');
      final left = and.slots.firstWhere((s) => bkSameExprPath(s.exprPath, ['l']));
      expect(left.expr!.hex, isTrue, reason: 'count > 10 是比较');
      final count = left.expr!.slots.first;
      expect(count.expr!.kind, 'var');
      expect(count.expr!.hex, isFalse);
      final ten = left.expr!.slots.last;
      expect(ten.expr!.bare, isTrue);
      expect(ten.expr!.slots.single.look, BkSlotLook.field);
      expect(ten.expr!.slots.single.text, '10');
      expect(bkSameExprPath(ten.expr!.slots.single.exprPath, ['l', 'r', 'v']), isTrue);
      // 嵌套：里层的矩形在外层里面。
      void inside(BkExpr outer) {
        for (final s in outer.slots) {
          expect(outer.rect.contains(s.rect.topLeft) && outer.rect.contains(s.rect.bottomRight - const Offset(0.01, 0.01)), isTrue);
          if (s.expr != null) inside(s.expr!);
        }
      }

      inside(and);
    });

    test('点哪是哪：积木头、槽位、最里面的表达式；C 形的口不算', () {
      final ifBlock = layout.blockAt([lcStep(1)])!;
      final cond = ifBlock.slots.single;
      final count = cond.expr!.slots.first.expr!.slots.first; // count > 10 里的 count
      final hit = layout.hitTest(count.rect.center)!;
      expect(bkSameBlockPath(hit.block.path, [lcStep(1)]), isTrue);
      expect(hit.slot!.spec!.kind, LcArgKind.variable, reason: '点到的是“变量的值”块里的下拉');
      expect(hit.expr!.kind, 'var');
      // 积木头的空白处：只有积木。
      final blank = layout.hitTest(ifBlock.head.topLeft + const Offset(3, 3))!;
      expect(blank.slot, isNull);
      // 口里的积木算它自己；口里的空白谁也不算。
      final first = layout.blockAt([lcStep(1), lcStep(0)])!;
      expect(layout.hitTest(first.rect.center)!.block, same(first));
      final repeat = layout.blockAt([lcStep(2)])!;
      expect(layout.hitTest(repeat.mouths.single.rect.center), isNull);
      expect(layout.hitTest(const Offset(-5, -5)), isNull);
      // 帽子的槽位。
      final hatHit = layout.hitTest(layout.hat!.slots.single.rect.center)!;
      expect(hatHit.block.isHat, isTrue);
      expect(hatHit.slot!.hatSlotId, 'target');
    });
  });

  group('可拼接点', () {
    test('语句：每个列表有“长度 + 1”个插入位，路径照着插进去位置正好对', () {
      final doc = sampleDoc();
      final host = hostOf(doc);
      final tree = host.script('h1')!;
      final layout = engineOf(host).layoutScript(tree);
      final snaps = [
        for (final s in layout.snaps)
          if (s.kind == BkSnapKind.statement) s,
      ];
      // 最外层 3 块 → 4 个；如果的 body 2 块 → 3 个、else 1 块 → 2 个；重复的空口 → 1 个。
      expect(snaps, hasLength(4 + 3 + 2 + 1));
      for (final s in snaps) {
        final list = tree.listAt(s.parent, inElse: s.inElse);
        expect(list, isNotNull);
        expect(s.index, inInclusiveRange(0, list!.length));
        // 插入位的位置＝那个位置上现有积木的左上角；最后一个＝上一块的左下角。
        if (s.index < list.length) {
          final b = layout.blockAt([...s.parent, lcStep(s.index, inElse: s.inElse)])!;
          expect(s.anchor, b.rect.topLeft);
        } else if (list.isNotEmpty) {
          final b = layout.blockAt([...s.parent, lcStep(s.index - 1, inElse: s.inElse)])!;
          expect(s.anchor, b.rect.bottomLeft);
        }
      }
      // 没有重复的。
      final keys = {for (final s in snaps) '${s.parent}|${s.inElse}|${s.index}'};
      expect(keys, hasLength(snaps.length));

      // 真的照着插一块：重排以后新积木就在那个点上。
      for (final s in snaps) {
        final copy = hostOf(sampleDoc());
        final t = copy.script('h1')!;
        expect(
          t.insertBlock(
            s.parent,
            LcBlock(op: 'log', args: {'value': exText('x')}),
            inElse: s.inElse,
            index: s.index,
          ),
          isTrue,
        );
        final again = engineOf(copy).layoutScript(t);
        final placed = again.blockAt([...s.parent, lcStep(s.index, inElse: s.inElse)])!;
        expect(placed.block!.op, 'log');
        expect(placed.rect.topLeft, s.anchor, reason: '插在 ${s.parent} ${s.inElse} ${s.index}');
      }
    });

    test('表达式：每个能放表达式的槽一个，路径能取到、能写回', () {
      final host = hostOf(sampleDoc());
      final tree = host.script('h1')!;
      final layout = engineOf(host).layoutScript(tree);
      final snaps = [
        for (final s in layout.snaps)
          if (s.kind == BkSnapKind.expr) s,
      ];
      final slots = [
        for (final (_, s) in layout.allSlots)
          if (s.acceptsExpr && s.hatSlotId == null) s,
      ];
      expect(snaps, hasLength(slots.length));
      expect(snaps, isNotEmpty);
      for (final s in snaps) {
        final block = tree.blockAt(s.parent)!;
        expect(isExpr(bkExprAt(block, s.arg!, s.exprPath)), isTrue, reason: '${block.op}.${s.arg}${s.exprPath}');
      }
      // 把“count > 10”的右边换成一个变量。
      final target = snaps.firstWhere((s) => bkSameExprPath(s.exprPath, ['l', 'r']));
      final block = tree.blockAt(target.parent)!;
      expect(bkSetExprAt(block, target.arg!, target.exprPath, exVar('count')), isTrue);
      expect(exprKind(exprChild(exprChild(block.args['cond'], 'l'), 'r')), 'var');
      expect(bkSetExprAt(block, 'cond', ['nope', 'x'], exNum(1)), isFalse);
      expect(bkExprAt(block, 'cond', ['l', 9]), isNull);
      // join 的第 2 项。
      final join = tree.blockAt([lcStep(1), lcStep(0, inElse: true)])!;
      expect(exprKind(bkExprAt(join, 'value', ['items', 1])), 'var');
      expect(bkSetExprAt(join, 'value', ['items', 1], exNum(5)), isTrue);
      expect(exprItems(join.args['value'])[1]['v'], 5);
    });

    test('给一个点找最近的：近的才算、里层优先、不能吸进自己里面、分语句和表达式', () {
      final host = hostOf(sampleDoc());
      final layout = engineOf(host).layoutScript(host.script('h1')!);
      final repeat = layout.blockAt([lcStep(2)])!;
      // 重复的空口附近 → 口里的第 0 位。
      final mouth = repeat.mouths.single.rect;
      final inMouth = layout.nearestSnap(mouth.topLeft + const Offset(8, 4), kind: BkSnapKind.statement)!;
      expect(bkSameBlockPath(inMouth.parent, [lcStep(2)]), isTrue);
      expect(inMouth.index, 0);
      expect(inMouth.anchor, mouth.topLeft);
      // 整串最下面 → 最外层的最后一位。
      final end = layout.nearestSnap(repeat.rect.bottomLeft + const Offset(3, 6), kind: BkSnapKind.statement)!;
      expect(end.parent, isEmpty);
      expect(end.index, 3);
      // 太远：没有。
      expect(layout.nearestSnap(const Offset(900, 900), kind: BkSnapKind.statement), isNull);
      expect(layout.nearestSnap(repeat.rect.bottomLeft + const Offset(0, 80), kind: BkSnapKind.statement, maxDistance: 20), isNull);
      // 拖着“如果”那块：它里面的位置都不算。
      final ifBlock = layout.blockAt([lcStep(1)])!;
      final inner = ifBlock.mouths.first.rect.topLeft;
      expect(bkSameBlockPath(layout.nearestSnap(inner, kind: BkSnapKind.statement)!.parent, [lcStep(1)]), isTrue);
      final excluded = layout.nearestSnap(inner, kind: BkSnapKind.statement, exclude: [lcStep(1)], maxDistance: 400);
      expect(excluded, isNotNull);
      expect(bkPathWithin([lcStep(1)], excluded!.parent), isFalse);
      // 表达式：点在槽里距离是 0，取最里层那个槽。
      final cond = ifBlock.slots.single;
      final ten = cond.expr!.slots.first.expr!.slots.last;
      final snap = layout.nearestSnap(ten.rect.center, kind: BkSnapKind.expr)!;
      expect(bkSameExprPath(snap.exprPath, ['l', 'r']), isTrue);
      expect(snap.distanceTo(ten.rect.center), 0);
      expect(snap.arg, 'cond');
      // 语句的点不会吸到表达式槽上，反过来也不会。
      expect(layout.nearestSnap(ten.rect.center, kind: BkSnapKind.statement, maxDistance: 1), isNull);
    });

    test('拖在手上的一截：路径照原来的算，没有头尾的插入位', () {
      final host = hostOf(sampleDoc());
      final tree = host.script('h1')!;
      final part = engineOf(host).layoutStack(tree.body.sublist(1), startIndex: 1);
      expect(part.hat, isNull);
      expect(part.blocks.first.rect.topLeft, Offset.zero);
      expect(bkSameBlockPath(part.blocks.first.path, [lcStep(1)]), isTrue);
      expect(part.blockAt([lcStep(2)])!.block!.op, 'repeat');
      final outer = [
        for (final s in part.snaps)
          if (s.kind == BkSnapKind.statement && s.parent.isEmpty) s.index,
      ];
      expect(outer, [2], reason: '只有两块之间那一个');
    });
  });

  group('换行与极端情况', () {
    test('一行放不下就在积木内部换行，积木变高不变宽', () {
      final host = hostOf(shapesDoc());
      final layout = engineOf(host).layoutScript(host.script('h1')!);
      final long = layout.blockAt([lcStep(0)])!;
      expect(long.head.width, lessThanOrEqualTo(m.maxBlockWidth));
      expect(long.head.height, greaterThan(m.minBlockHeight * 2));
      final rows = {for (final s in long.slots) s.rect.center.dy};
      expect(rows.length, greaterThan(1));
      // 很长的文字：输入框封顶，不把积木撑宽。
      final field = long.slots.last.expr!.slots.first.expr!.slots.single;
      expect(field.look, BkSlotLook.field);
      expect(field.rect.width, m.fieldMaxTextW + m.fieldPadH * 2);
      // 同一行里的东西竖直居中。
      final label = long.labels.first, node = long.slots.first;
      expect(label.rect.center.dy, closeTo(node.rect.center.dy, 0.01));
    });

    test('不认识的积木 / 表达式、没填的槽、没选的变量：都画得出来', () {
      final host = hostOf(shapesDoc());
      final layout = engineOf(host).layoutScript(host.script('h1')!);
      final unknown = layout.blocks.firstWhere((b) => b.block?.op == 'frobnicate');
      expect(unknown.unknown, isTrue);
      expect(unknown.colorKey, BlockColorKey.unknown);
      expect(unknown.labels.single.text, '不认识的积木（frobnicate）');
      expect(unknown.slots, isEmpty);
      final setVar = layout.blockAt([lcStep(2)])!;
      expect(setVar.slots.first.placeholder, isTrue);
      expect(setVar.slots.first.text, '选变量');
      expect(setVar.slots.last.expr!.unknown, isTrue);
      expect(setVar.slots.last.expr!.labels.single.text, '不认识的值（mystery）');
      final emptyIf = layout.blockAt([lcStep(3)])!;
      expect(emptyIf.slots.single.look, BkSlotLook.empty);
      expect(emptyIf.slots.single.hex, isTrue, reason: '条件槽要的是“是 / 否”');
      final toggle = layout.blockAt([lcStep(4)])!.slots.single.expr!;
      expect(toggle.bare, isTrue);
      expect(toggle.slots.single.look, BkSlotLook.toggle);
      expect(toggle.slots.single.text, '是');
      // 帽子没选控件：槽是提示语。
      expect(layout.hat!.slots.single.placeholder, isTrue);
    });

    test('不能放积木的积木里有积木（坏数据）：照样画成有口的，里面的也排出来', () {
      final doc = sampleDoc();
      doc.logic.handlers.first.body.add(
        LcBlock(
          op: 'alert',
          args: {'message': exText('x')},
          body: [
            LcBlock(op: 'log', args: {'value': exText('y')}),
          ],
          orElse: [LcBlock(op: 'nope')],
        ),
      );
      final host = hostOf(doc);
      final layout = engineOf(host).layoutScript(host.script('h1')!);
      final stray = layout.blockAt([lcStep(3)])!;
      expect(stray.mouths, hasLength(2));
      expect(layout.blockAt([lcStep(3), lcStep(0)])!.block!.op, 'log');
      expect(layout.blockAt([lcStep(3), lcStep(0, inElse: true)])!.unknown, isTrue);
    });

    test('嵌套 12 层不崩，一层缩进一个胳膊宽；模型外的 60 层坏数据也不崩', () {
      final host = hostOf(deepDoc());
      final layout = engineOf(host).layoutScript(host.script('h1')!);
      expect(layout.blocks, hasLength(1 + 12 + 1));
      final innermost = layout.blocks.last;
      expect(innermost.block!.op, 'alert');
      expect(innermost.path, hasLength(13));
      expect(innermost.rect.left, m.armW * 12);
      for (final b in layout.blocks) {
        for (final mouth in b.mouths) {
          expect(mouth.rect.height, greaterThanOrEqualTo(m.mouthMinH));
        }
      }
      final tooDeep = hostOf(deepDoc(60));
      final cut = engineOf(tooDeep).layoutScript(tooDeep.script('h1')!);
      expect(cut.blocks.length, lessThanOrEqualTo(kBkMaxBlockDepth + 3));
      expect(cut.size.height.isFinite, isTrue);
    });

    test('表达式套 40 层（超过上限）不崩，超出的画成“…”；越套越窄但不窄过下限', () {
      final doc = sampleDoc();
      var e = exNum(1);
      for (var i = 0; i < 40; i++) {
        e = exNot(e);
      }
      doc.logic.handlers.first.body.insert(0, LcBlock(op: 'log', args: {'value': e}));
      final host = hostOf(doc);
      final layout = engineOf(host).layoutScript(host.script('h1')!);
      final block = layout.blockAt([lcStep(0)])!;
      var depth = 0;
      BkExpr? cur = block.slots.single.expr;
      BkExpr? last;
      while (cur != null) {
        depth++;
        last = cur;
        cur = cur.slots.isEmpty ? null : cur.slots.first.expr;
      }
      expect(depth, lessThan(40));
      expect(last!.unknown, isTrue);
      expect(last.labels.single.text, '…');
      expect(block.rect.width.isFinite && block.rect.height.isFinite, isTrue);
    });

    test('坏参数（类型不对、列表里混了别的）不崩', () {
      final doc = sampleDoc();
      doc.logic.handlers.first.body.addAll([
        LcBlock(op: 'setVar', args: {'name': 42, 'value': 'not an expr'}),
        LcBlock(
          op: 'setProp',
          args: {
            'node': 'gone',
            'prop': 7,
            'value': {
              'e': 'join',
              'items': [1, exText('a'), null],
            },
          },
        ),
        LcBlock(
          op: 'log',
          args: {
            'value': {'e': 'join', 'items': 'oops'},
          },
        ),
        LcBlock(
          op: 'log',
          args: {
            'value': {'e': 'num', 'v': double.nan},
          },
        ),
        LcBlock(
          op: 'log',
          args: {
            'value': {'e': 'text', 'v': '第一行\n第二行'},
          },
        ),
      ]);
      final host = hostOf(doc);
      final layout = engineOf(host).layoutScript(host.script('h1')!);
      final setVar = layout.blockAt([lcStep(3)])!;
      expect(setVar.slots.first.placeholder, isTrue);
      expect(setVar.slots.last.look, BkSlotLook.empty);
      final join = layout.blockAt([lcStep(4)])!.slots.last.expr!;
      expect([for (final s in join.slots) s.look], [BkSlotLook.empty, BkSlotLook.expr, BkSlotLook.empty]);
      expect(layout.blockAt([lcStep(7)])!.slots.single.expr!.slots.single.text, '第一行 第二行');
    });
  });

  group('外形', () {
    test('凸起和凹口对得上：上一块轮廓的凸起范围＝下一块凹口的范围', () {
      const upper = Rect.fromLTWH(0, 0, 120, 40), lower = Rect.fromLTWH(0, 40, 160, 40);
      final up = bkStackPath(upper, m), low = bkStackPath(lower, m);
      final probe = Offset(m.notchX + m.notchW / 2, 40 + m.notchD / 2);
      expect(up.contains(probe), isTrue, reason: '上一块的凸起伸到这里');
      expect(low.contains(probe), isFalse, reason: '下一块在这里是凹口');
      // 凹口两边、凸起下面：归下一块。
      expect(low.contains(Offset(m.notchX - 4, 42)), isTrue);
      expect(low.contains(Offset(m.notchX + m.notchW / 2, 40 + m.notchD + 2)), isTrue);
      expect(up.getBounds().bottom, closeTo(40 + m.notchD, 0.01));
    });

    test('C 形：口是空的，胳膊和上下两条是实的；口的上沿有凸起、下沿有凹口', () {
      final host = hostOf(sampleDoc());
      final layout = engineOf(host).layoutScript(host.script('h1')!);
      final repeat = layout.blockAt([lcStep(2)])!;
      final path = bkBlockPath(repeat, m);
      final mouth = repeat.mouths.single.rect;
      expect(path.contains(mouth.center), isFalse);
      expect(path.contains(Offset(repeat.rect.left + m.armW / 2, mouth.center.dy)), isTrue);
      expect(path.contains(repeat.head.center), isTrue);
      expect(path.contains(Offset(repeat.rect.center.dx, repeat.rect.bottom - m.footerH / 2 + 2)), isTrue);
      final tabX = mouth.left + m.notchX + m.notchW / 2;
      expect(path.contains(Offset(tabX, mouth.top + m.notchD / 2)), isTrue, reason: '口上沿的凸起');
      expect(path.contains(Offset(tabX, mouth.bottom + m.notchD / 2)), isFalse, reason: '口下沿的凹口');
    });

    test('帽子有圆顶；六边形两头是尖的', () {
      const r = Rect.fromLTWH(0, 0, 160, 53);
      final hat = bkHatPath(r, m);
      expect(hat.contains(Offset(m.hatDomeW / 2, 3)), isTrue);
      expect(hat.contains(const Offset(150, 3)), isFalse, reason: '圆顶右边是平的，比圆顶低');
      expect(hat.contains(Offset(150, m.hatDome + 3)), isTrue);
      const h = Rect.fromLTWH(0, 0, 60, 26);
      final hex = bkHexPath(h, m);
      expect(hex.contains(const Offset(2, 2)), isFalse);
      expect(hex.contains(const Offset(3, 13)), isTrue);
      expect(bkPillPath(h).contains(const Offset(1, 13)), isTrue);
    });

    test('色表：每一类浅色深色都有，积木上的白字对比度够（≥ 4:1）', () {
      double contrast(Color a, Color b) {
        final la = a.computeLuminance(), lb = b.computeLuminance();
        return (la > lb ? la + 0.05 : lb + 0.05) / (la > lb ? lb + 0.05 : la + 0.05);
      }

      for (final p in [BkPalette.light, BkPalette.darkTheme]) {
        for (final key in BlockColorKey.all) {
          final t = p.tone(key);
          expect(contrast(t.text, t.fillTop), greaterThanOrEqualTo(4.0), reason: '$key ${p.dark ? '深色' : '浅色'}');
          expect(contrast(t.fieldText, t.fieldBg), greaterThanOrEqualTo(7.0));
          expect(t.deep.computeLuminance(), lessThan(t.fill.computeLuminance()));
        }
        expect(p.tone('没有这个键').fill, p.tone(BlockColorKey.unknown).fill);
      }
    });
  });
}
