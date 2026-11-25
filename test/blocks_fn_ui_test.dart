// 第 2 阶段在编辑器里的界面测试（390×844）：定义帽子的参数小块（加、删、改名、默认值、剩下的全收、拖出来当值用）、
// 带口的值（把语句拖进口、从口里拖出、整个值连里面的语句一起拖走、让位和剪影、长按拿起、单指平移、校验标记、撤销重做）。
import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/blocks/block_dock.dart';
import 'package:lopicode/blocks/block_drag.dart';
import 'package:lopicode/blocks/block_geometry.dart';
import 'package:lopicode/lowcode/logic_expr.dart';
import 'package:lopicode/lowcode/logic_model.dart';
import 'package:material_ui/material_ui.dart';

import 'screens_test.dart' show fontsLoaded;
import 'support/blocks_fake_fn_host.dart';
import 'support/blocks_fake_host.dart';
import 'support/blocks_fake_rig.dart';
import 'support/blocks_fn_rig.dart';
import 'support/harness.dart';

List<String> chipTexts(FnRig rig, String id, {LcBlockPath? owner}) => [for (final c in rig.chips(id, owner: owner)) c.text];

LcBlockPath inMouth(LcBlockPath owner, int index, [int k = 0]) => [...owner, lcStep(index, arm: lcExprMouthArm(k))];

void main() {
  setUpAll(() async => fontsLoaded = await loadRealFonts());
  tearDown(BkDockMemory.clear);

  group('定义帽子的参数小块', () {
    testWidgets('点“＋”：多一个参数并弹小卡起名字；点小块：改名（这一串里用到它的值跟着改）、给默认值；每步一条撤销记录', (tester) async {
      final rig = FnRig([fxGreetDef()]);
      await rig.pump(tester);
      final start = rig.host.encode();
      expect(chipTexts(rig, 's1'), ['名字', '次数＝1']);

      await tester.tapAt(rig.chipAdd('s1'));
      await tester.pumpAndSettle();
      expect(k('bk-param-card'), findsOneWidget);
      expect(chipTexts(rig, 's1'), ['名字', '次数＝1', '参数1']);
      await tester.enterText(k('bk-param-name'), '语气');
      await tester.pump();
      await tester.tap(k('bk-param-ok'));
      await tester.pumpAndSettle();
      expect(k('bk-param-card'), findsNothing);
      expect(chipTexts(rig, 's1'), ['名字', '次数＝1', '语气']);

      // 改名：名字 → 谁。口里“说 (名字)”跟着变成“说 (谁)”。
      await tester.tapAt(rig.chip('s1', 0));
      await tester.pumpAndSettle();
      await tester.enterText(k('bk-param-name'), '谁');
      await tester.tap(k('bk-param-ok'));
      await tester.pumpAndSettle();
      expect(chipTexts(rig, 's1'), ['谁', '次数＝1', '语气']);
      expect(rig.tree.blockAt([lcStep(0), lcStep(0)])!.args['text'], fxParam('谁'));
      expect(rig.host.issues, isEmpty);

      // 默认值：语气＝客气（文字）；次数的默认值清掉。
      await tester.tapAt(rig.chip('s1', 2));
      await tester.pumpAndSettle();
      await tester.enterText(k('bk-param-default'), '客气');
      await tester.tap(k('bk-param-ok'));
      await tester.pumpAndSettle();
      await tester.tapAt(rig.chip('s1', 1));
      await tester.pumpAndSettle();
      await tester.enterText(k('bk-param-default'), '');
      await tester.tap(k('bk-param-ok'));
      await tester.pumpAndSettle();
      expect(chipTexts(rig, 's1'), ['谁', '次数', '语气＝客气']);
      expect(rig.fn.paramsOf(rig.script('s1')).map((p) => p.defaultValue), [null, null, '客气']);

      // 5 步：加、起名、改名、默认值、清默认值。一步一步撤回去，再重做回来。
      final end = rig.host.encode();
      for (var i = 0; i < 5; i++) {
        expect(rig.host.canUndo, isTrue);
        rig.host.undo();
      }
      await tester.pumpAndSettle();
      expect(rig.host.encode(), start);
      expect(rig.host.canUndo, isFalse);
      for (var i = 0; i < 5; i++) {
        rig.host.redo();
      }
      await tester.pumpAndSettle();
      expect(rig.host.encode(), end);
      expect(chipTexts(rig, 's1'), ['谁', '次数', '语气＝客气']);
    });

    testWidgets('小卡里：名字空 / 和别的参数重名时说原因、“好”点不了；“剩下的全收”只有最后一个能开；点外面＝不改', (tester) async {
      final rig = FnRig([fxGreetDef()]);
      await rig.pump(tester);
      final start = rig.host.encode();
      await tester.tapAt(rig.chip('s1', 0));
      await tester.pumpAndSettle();
      expect(k('bk-param-rest'), findsNothing, reason: '不是最后一个');
      await tester.enterText(k('bk-param-name'), '次数');
      await tester.pump();
      expect(tester.widget<Text>(k('bk-param-problem')).data, contains('已经有'));
      expect(tester.widget<TextButton>(k('bk-param-ok')).onPressed, isNull);
      await tester.enterText(k('bk-param-name'), '  ');
      await tester.pump();
      expect(k('bk-param-problem'), findsOneWidget);
      expect(tester.widget<TextButton>(k('bk-param-ok')).onPressed, isNull);
      await tester.tapAt(const Offset(195, 700));
      await tester.pumpAndSettle();
      expect(k('bk-param-card'), findsNothing);
      expect(rig.host.encode(), start);
      expect(rig.host.canUndo, isFalse);

      await tester.tapAt(rig.chip('s1', 1));
      await tester.pumpAndSettle();
      await tester.tap(k('bk-param-rest'));
      await tester.pump();
      await tester.tap(k('bk-param-ok'));
      await tester.pumpAndSettle();
      expect(chipTexts(rig, 's1'), ['名字', '…次数']);
      expect(rig.fn.paramsOf(rig.script('s1')).last.rest, isTrue);
      // 最后一个是“全收”时点“＋”：新的插在它前面。
      await tester.tapAt(rig.chipAdd('s1'));
      await tester.pumpAndSettle();
      await tester.tap(k('bk-param-ok'));
      await tester.pumpAndSettle();
      expect(chipTexts(rig, 's1'), ['名字', '参数1', '…次数']);
      expect(tester.takeException(), isNull);
    });

    testWidgets('删参数：别处有调用在用就先问“有 N 处在用，槽里的东西会丢掉”；取消＝不删；确认＝删掉，调用处的槽跟着少一个', (tester) async {
      final rig = FnRig([
        fxGreetDef(),
        FakeScript(
          's2',
          body: [
            LcBlock(op: 'greet', args: {'名字': fxText('小明'), '次数': fxNum(3)}),
            LcBlock(op: 'greet', args: {'名字': fxText('小红'), '次数': fxNum(2)}),
          ],
          x: 0,
          y: 260,
        ),
      ]);
      await rig.pump(tester);
      final start = rig.host.encode();
      await tester.tapAt(rig.chip('s1', 1));
      await tester.pumpAndSettle();
      await tester.tap(k('bk-param-delete'));
      await tester.pumpAndSettle();
      expect(find.text('删掉参数“次数”？'), findsOneWidget);
      expect(find.text('有 2 处在用，槽里的东西会丢掉。'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(rig.host.encode(), start);

      await tester.tapAt(rig.chip('s1', 1));
      await tester.pumpAndSettle();
      await tester.tap(k('bk-param-delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();
      expect(chipTexts(rig, 's1'), ['名字']);
      final call = rig.host.script('s2')!.body.first;
      expect(call.args.keys, ['名字']);
      expect(rig.s.layout.placed('s2')!.layout.blockAt([lcStep(0)])!.slots.map((s) => s.arg), ['名字']);
      // 这一串里还用着“次数”的地方：标出来（假宿主的规矩 F03），不崩。
      expect(rig.host.issues.any((i) => i.rule == 'F03'), isTrue);
      rig.host.undo();
      await tester.pumpAndSettle();
      expect(rig.host.encode(), start);
      expect(rig.host.canUndo, isFalse, reason: '删参数（含各处调用跟着变）只有一条撤销记录');
      expect(tester.takeException(), isNull);
    });

    testWidgets('长按参数小块拖出来：手上是一份副本（帽子上的还在），放进这一串里的槽就是那个参数的值；撤销一步回去', (tester) async {
      final rig = FnRig([fxGreetDef()..body.add(fxSay('完'))]);
      await rig.pump(tester);
      final start = rig.host.encode();
      final from = rig.chip('s1', 0);
      final g = await rig.lift(tester, from);
      expect(rig.s.drag!.kind, BkDragKind.expr);
      expect(rig.s.drag!.expr, fxParam('名字'));
      expect(chipTexts(rig, 's1'), ['名字', '次数＝1'], reason: '拖出来的是副本');
      await rig.glide(tester, g, from, rig.exprSnap('s1', [lcStep(1)], 'text'));
      expect(rig.s.drag!.target, isNotNull);
      await rig.drop(tester, g);
      expect(rig.tree.blockAt([lcStep(1)])!.args['text'], fxParam('名字'));
      expect(chipTexts(rig, 's1'), ['名字', '次数＝1']);
      expect(rig.host.encode() == start, isFalse);
      rig.host.undo();
      await tester.pumpAndSettle();
      expect(rig.host.encode(), start);
    });

    testWidgets('把参数放到已经是它的槽上：什么都没变，也不说“原来的值被换掉了”；盖住别的值才说、能撤销', (tester) async {
      final rig = FnRig([fxGreetDef()]);
      await rig.pump(tester);
      final start = rig.host.encode();
      final say = [lcStep(0), lcStep(0)];
      var from = rig.chip('s1', 0);
      var g = await rig.lift(tester, from);
      await rig.glide(tester, g, from, rig.exprSnap('s1', say, 'text'));
      await rig.drop(tester, g);
      expect(rig.host.encode(), start);
      expect(find.text('原来的值被换掉了。'), findsNothing);

      from = rig.chip('s1', 1);
      g = await rig.lift(tester, from);
      await rig.glide(tester, g, from, rig.exprSnap('s1', say, 'text'));
      await rig.drop(tester, g);
      expect(rig.tree.blockAt(say)!.args['text'], fxParam('次数'));
      expect(find.text('原来的值被换掉了。'), findsOneWidget);
      await tester.tap(find.text('撤销'));
      await tester.pumpAndSettle();
      expect(rig.host.encode(), start);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
    });

    testWidgets('键盘弹起时参数小卡整个在键盘上面（小块下面放不下时往上挪）', (tester) async {
      final rig = FnRig([fxGreetDef(y: 300)]);
      await rig.pump(tester);
      await tester.tapAt(rig.chip('s1', 0));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('bk-param-card')), findsOneWidget, reason: '小块在 ${rig.chip('s1', 0)}');
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      final card = tester.getRect(find.byKey(const ValueKey('bk-param-card')));

      expect(card.bottom, lessThanOrEqualTo(844 - 300));
      expect(card.top, greaterThanOrEqualTo(0));
      expect(tester.takeException(), isNull);
    });

    testWidgets('参数小块只能放进它自己这一串：拖到别的串的槽上不吸附，松手弹回去、什么都没改；长按没挪就松手＝弹小卡', (tester) async {
      final rig = FnRig([
        fxGreetDef(),
        FakeScript('s2', body: [fxSay('别的串')], x: 0, y: 260),
      ]);
      await rig.pump(tester);
      final start = rig.host.encode();
      final from = rig.chip('s1', 1);
      final g = await rig.lift(tester, from);
      await rig.glide(tester, g, from, rig.exprSnap('s2', [lcStep(0)], 'text'));
      expect(rig.s.drag!.target, isNull);
      await rig.drop(tester, g);
      expect(rig.host.encode(), start);
      expect(rig.host.canUndo, isFalse);

      final g2 = await tester.startGesture(rig.chip('s1', 1));
      await tester.pump(const Duration(milliseconds: 300));
      expect(rig.s.drag, isNotNull);
      await g2.up();
      await tester.pumpAndSettle();
      expect(rig.s.drag, isNull);
      expect(k('bk-param-card'), findsOneWidget);
      expect(tester.widget<TextField>(k('bk-param-name')).controller!.text, '次数');
      await tester.tapAt(const Offset(195, 700));
      await tester.pumpAndSettle();
      expect(rig.host.encode(), start);
      expect(tester.takeException(), isNull);
    });

    testWidgets('不是定义帽子的串、不支持这些的宿主：帽子上没有小块，点和长按帽子照旧', (tester) async {
      final rig = FakeRig([fxSay('好')]);
      await rig.pump(tester);
      expect(rig.placed.layout.hat!.slots, isEmpty);
      final g = await rig.lift(tester, rig.s.globalOf(rig.s.toView(rig.placed.origin + rig.placed.layout.hat!.rect.center)));
      expect(rig.s.drag!.kind, BkDragKind.hat);
      await rig.drop(tester, g);
      expect(tester.takeException(), isNull);
    });
  });

  group('带口的值', () {
    testWidgets('匿名函数上的参数小块：加、改名（口里用到的跟着改）、删；拖出来放进口里的槽', (tester) async {
      final rig = FnRig([
        FakeScript('s1', body: [fxMapBlock()], x: 0, y: 0),
      ]);
      await rig.pump(tester);
      final start = rig.host.encode();
      final owner = [lcStep(0)];
      Map<String, dynamic> fn() => (rig.first.args['value'] as Map)['fn'] as Map<String, dynamic>;
      expect(chipTexts(rig, 's1', owner: owner), ['x']);
      await tester.tapAt(rig.chip('s1', 0, owner: owner));
      await tester.pumpAndSettle();
      expect(k('bk-param-default'), findsNothing, reason: '匿名函数的参数没有默认值');
      expect(k('bk-param-rest'), findsNothing);
      await tester.enterText(k('bk-param-name'), '每一项');
      await tester.tap(k('bk-param-ok'));
      await tester.pumpAndSettle();
      expect(fn()['params'], ['每一项']);
      final ret = rig.tree.blockAt(inMouth(owner, 1))!;
      expect((ret.args['value'] as Map)['l'], fxParam('每一项'));

      await tester.tapAt(rig.chipAdd('s1', owner: owner));
      await tester.pumpAndSettle();
      await tester.enterText(k('bk-param-name'), '第几个');
      await tester.tap(k('bk-param-ok'));
      await tester.pumpAndSettle();
      expect(fn()['params'], ['每一项', '第几个']);

      // 把“第几个”拖进口里“说”的槽。
      final from = rig.chip('s1', 1, owner: owner);
      final g = await rig.lift(tester, from);
      await rig.glide(tester, g, from, rig.exprSnap('s1', inMouth(owner, 0), 'text'));
      await rig.drop(tester, g);
      expect(rig.tree.blockAt(inMouth(owner, 0))!.args['text'], fxParam('第几个'));

      await tester.tapAt(rig.chip('s1', 0, owner: owner));
      await tester.pumpAndSettle();
      await tester.tap(k('bk-param-delete'));
      await tester.pumpAndSettle();
      expect(fn()['params'], ['第几个']);
      // 5 步：改名、加、起名、拖进槽、删。
      for (var i = 0; i < 5; i++) {
        rig.host.undo();
      }
      await tester.pumpAndSettle();
      expect(rig.host.encode(), start);
      expect(rig.host.canUndo, isFalse);
      expect(tester.takeException(), isNull);
    });

    testWidgets('把外面的语句拖进口里：口让出位置、画出落点剪影；松手落进去；再从口里拖出来接回外面；撤销重做', (tester) async {
      final rig = FnRig([
        FakeScript('s1', body: [fxMapBlock(), fxSay('外面的')], x: 0, y: 0),
      ]);
      await rig.pump(tester);
      final start = rig.host.encode();
      final owner = [lcStep(0)];
      final before = rig.block(inMouth(owner, 1)).rect.top;
      var from = rig.grip([lcStep(1)]);
      var g = await rig.lift(tester, from);
      expect(rig.s.drag!.kind, BkDragKind.statement);
      await rig.glide(tester, g, from, rig.snapIn('s1', owner, 1, arm: -2));
      await tester.pump(const Duration(milliseconds: 300));
      final ghost = rig.s.drag!.ghost!;
      expect(ghost.arm, -2);
      expect(ghost.start, 1);
      expect(bkSameBlockPath(ghost.parent, owner), isTrue);
      // 让位：原来口里的第 2 块往下挪了（现在排在第 3）。
      final shown = rig.s.drag!.display.placed('s1')!.layout;
      expect(shown.blockAt(inMouth(owner, 2))!.rect.top, greaterThan(before + 20));
      await rig.drop(tester, g);
      expect(rig.tree.body, hasLength(1));
      expect(rig.first.exprMouths.single.map((b) => b.op), ['say', 'say', 'return']);
      expect(rig.first.exprMouths.single[1].args['text'], fxText('外面的'));
      expect(rig.s.selection?.path.last.arm, -2, reason: '落下去的那块被选中');
      final mid = rig.host.encode();

      // 从口里拖出来：拖第 2 块＝它和它下面的“返回”一起走，接到外面那块后面。
      from = rig.grip(inMouth(owner, 1));
      g = await rig.lift(tester, from);
      expect(rig.s.drag!.blocks.map((b) => b.op), ['say', 'return']);
      await rig.glide(tester, g, from, rig.snap(const [], 1));
      await rig.drop(tester, g);
      expect(rig.tree.body.map((b) => b.op), ['set', 'say', 'return']);
      expect(rig.first.exprMouths.single.map((b) => b.op), ['say']);

      rig.host.undo();
      await tester.pumpAndSettle();
      expect(rig.host.encode(), mid);
      rig.host.undo();
      await tester.pumpAndSettle();
      expect(rig.host.encode(), start);
      rig.host.redo();
      rig.host.redo();
      await tester.pumpAndSettle();
      expect(rig.tree.body.map((b) => b.op), ['set', 'say', 'return']);
      expect(tester.takeException(), isNull);
    });

    testWidgets('口里拖到口里的原处＝没动；拖到空白处松手＝弹回去；口里的积木上下换位置', (tester) async {
      final rig = FnRig([
        FakeScript('s1', body: [fxMapBlock()], x: 0, y: 0),
      ]);
      await rig.pump(tester);
      final start = rig.host.encode();
      final owner = [lcStep(0)];
      var from = rig.grip(inMouth(owner, 1));
      var g = await rig.lift(tester, from);
      await rig.glide(tester, g, from, rig.snapIn('s1', owner, 1, arm: -2));
      expect(rig.s.drag!.target!.noop, isTrue);
      await rig.drop(tester, g);
      expect(rig.host.encode(), start);
      expect(rig.host.canUndo, isFalse);

      from = rig.grip(inMouth(owner, 1));
      g = await rig.lift(tester, from);
      await rig.glide(tester, g, from, const Offset(350, 300));
      expect(rig.s.drag!.target, isNull);
      await rig.drop(tester, g);
      expect(rig.host.encode(), start);

      // “返回”拖到“说”前面。
      from = rig.grip(inMouth(owner, 1));
      g = await rig.lift(tester, from);
      await rig.glide(tester, g, from, rig.snapIn('s1', owner, 0, arm: -2));
      await rig.drop(tester, g);
      expect(rig.first.exprMouths.single.map((b) => b.op), ['return', 'say']);
      expect(tester.takeException(), isNull);
    });

    testWidgets('整个带口的值连里面的语句一起拖走：手上那块带着口里的积木；放进别的槽，里面的原样跟着；原槽回到默认值', (tester) async {
      final rig = FnRig([
        FakeScript(
          's1',
          body: [
            fxMapBlock(),
            LcBlock(op: 'run', args: {'fn': fxFn(const [])}),
          ],
          x: 0,
          y: 0,
        ),
      ]);
      await rig.pump(tester);
      final start = rig.host.encode();
      final layout = rig.placed.layout;
      final map = layout.blockAt([lcStep(0)])!.slots.firstWhere((s) => s.arg == 'value').expr!;
      final fn = map.slots.firstWhere((s) => s.exprPath.last == 'fn').expr!;
      // 按在“函数”两个字上＝拿整个值。
      final from = rig.at('s1', fn.labels.single.rect.center);
      final g = await rig.lift(tester, from);
      final drag = rig.s.drag!;
      expect(drag.kind, BkDragKind.expr);
      expect(exprKind(drag.expr!), 'fn');
      expect(drag.piece.blocks.map((b) => b.block!.op), ['say', 'return'], reason: '口里的积木跟在手上');
      // 拿走以后：原来的口没了，那里的拼接点也没了。
      expect(drag.base.placed('s1')!.layout.snaps.where((s) => s.kind == BkSnapKind.statement && bkSameBlockPath(s.parent, [lcStep(0)]) && s.arm <= -2), isEmpty);
      await rig.glide(tester, g, from, rig.exprSnap('s1', [lcStep(1)], 'fn'), steps: 10);
      expect(rig.s.drag!.target, isNotNull);
      await rig.drop(tester, g);
      final moved = rig.tree.blockAt([lcStep(1)])!;
      expect(moved.exprMouths.single.map((b) => b.op), ['say', 'return']);
      expect(lcExprBody(asExpr(moved.args['fn'])!)!.length, 2);
      // 换下来的那个空函数回到了原来的槽里（交换）。
      final back = asExpr((rig.first.args['value'] as Map)['fn'])!;
      expect(exprKind(back), 'fn');
      expect(lcExprBody(back), isEmpty);
      rig.host.undo();
      await tester.pumpAndSettle();
      expect(rig.host.encode(), start);
      expect(rig.host.canUndo, isFalse);
      expect(tester.takeException(), isNull);
    });

    testWidgets('嵌套：匿名函数里的匿名函数、放在“对每一项”口里的——往最里面的口拖、从里面拖到最外面，路径都对', (tester) async {
      final inner = LcBlock(
        op: 'run',
        args: {
          'fn': fxFn(['y'], [fxSay('最里面')]),
        },
      );
      final outer = LcBlock(
        op: 'run',
        args: {
          'fn': fxFn(['x'], [fxSay('外面'), inner]),
        },
      );
      final rig = FnRig([
        FakeScript(
          's1',
          body: [
            LcBlock(op: 'forEach', args: {'list': fxExpr('listNew')}, body: [outer]),
            fxSay('尾巴'),
          ],
          x: 0,
          y: 0,
        ),
      ]);
      await rig.pump(tester);
      final start = rig.host.encode();
      final outerPath = [lcStep(0), lcStep(0)];
      final innerPath = inMouth(outerPath, 1);
      var from = rig.grip([lcStep(1)]);
      var g = await rig.lift(tester, from);
      await rig.glide(tester, g, from, rig.snapIn('s1', innerPath, 1, arm: -2), steps: 10);
      await rig.drop(tester, g);
      expect(rig.tree.blockAt(inMouth(innerPath, 1))!.args['text'], fxText('尾巴'));
      expect(rig.tree.body, hasLength(1));

      from = rig.grip(inMouth(innerPath, 0));
      g = await rig.lift(tester, from);
      expect(rig.s.drag!.blocks, hasLength(2));
      await rig.glide(tester, g, from, rig.snap(const [], 1), steps: 10);
      await rig.drop(tester, g);
      expect(rig.tree.body.map((b) => b.op), ['forEach', 'say', 'say']);
      expect(rig.tree.blockAt(innerPath)!.exprMouths.single, isEmpty);
      rig.host.undo();
      rig.host.undo();
      await tester.pumpAndSettle();
      expect(rig.host.encode(), start);
      expect(tester.takeException(), isNull);
    });

    testWidgets('单指在带口的值上滑＝平移画布，不会把积木拖走；点口里的积木＝选中它；删掉它＝一条撤销记录', (tester) async {
      final rig = FnRig([
        FakeScript('s1', body: [fxMapBlock()], x: 0, y: 0),
      ]);
      await rig.pump(tester);
      final start = rig.host.encode();
      final at = rig.grip(inMouth([lcStep(0)], 0));
      final origin = rig.s.toView(rig.placed.origin);
      await tester.dragFrom(at, const Offset(40, 60));
      await tester.pumpAndSettle();
      expect(rig.host.encode(), start);
      expect((rig.s.toView(rig.placed.origin) - origin).distance, greaterThan(30));
      expect(rig.s.drag, isNull);

      await tester.tapAt(rig.grip(inMouth([lcStep(0)], 1)));
      await tester.pumpAndSettle();
      expect(rig.s.selection?.path.map((s) => (s.index, s.arm)), [(0, -1), (1, -2)]);

      // 删掉选中的那块：口里少一块；撤销一步就回来（一条撤销记录）。
      final before = rig.first.exprMouths.single.length;
      await tester.tap(find.byKey(const ValueKey('bk-action-delete')));
      await tester.pumpAndSettle();
      expect(rig.first.exprMouths.single, hasLength(before - 1));
      rig.host.undo();
      await tester.pumpAndSettle();
      expect(rig.host.encode(), start);
      expect(rig.host.canUndo, isFalse);
      expect(tester.takeException(), isNull);
    });

    testWidgets('校验标记：口里的积木有问题，标在那块积木上（路径走得进口里）；点它能看到原因', (tester) async {
      final body = [
        LcBlock(op: 'say', args: {'text': fxParam('没有这个参数')}),
      ];
      final rig = FnRig([
        FakeScript('s1', body: [fxMapBlock(body: body)], x: 0, y: 0),
      ]);
      await rig.pump(tester);
      final issue = rig.host.issues.single;
      expect(issue.rule, 'F03');
      expect(issue.path.last.arm, -2);
      final marks = rig.s.issueMarks['s1']!;
      final blk = rig.block(inMouth([lcStep(0)], 0));
      expect(marks.levelOf(blk), isNotNull);
      expect(marks.levelOf(rig.block([lcStep(0)])), isNull, reason: '外面那块自己没问题');
      await tester.tapAt(rig.grip(blk.path));
      await tester.pumpAndSettle();
      expect(find.textContaining('没有这个参数'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('从积木盒拖一个“函数”进槽，再拖一块语句进它的口；短写法也能拖进槽', (tester) async {
      final rig = FnRig([
        FakeScript(
          's1',
          body: [
            LcBlock(op: 'run', args: {'fn': fxText('')}),
            LcBlock(op: 'run', args: {'fn': fxText('')}),
          ],
          x: 0,
          y: 0,
        ),
      ]);
      await rig.pump(tester);
      await rig.openTab(tester, 'function');
      await tester.ensureVisible(rig.item('expr-fn'));
      await tester.pumpAndSettle();
      var from = tester.getTopLeft(rig.item('expr-fn')) + const Offset(10, 14);
      var g = await tester.startGesture(from);
      await tester.pump(const Duration(milliseconds: 220));
      await rig.glide(tester, g, from, from + const Offset(0, -40), steps: 4);
      expect(rig.s.drag, isNotNull, reason: '样品在 ${tester.getRect(rig.item('expr-fn'))}');
      expect(rig.s.drag!.piece.loose!.mouth, isNotNull);
      await rig.glide(tester, g, from + const Offset(0, -40), rig.exprSnap('s1', [lcStep(0)], 'fn'), steps: 10);
      await rig.drop(tester, g);
      expect(exprKind(asExpr(rig.first.args['fn'])!), 'fn');
      expect(rig.first.exprMouths.single, isEmpty);

      from = rig.grip([lcStep(1)]);
      g = await rig.lift(tester, from);
      await rig.glide(tester, g, from, rig.snapIn('s1', [lcStep(0)], 0, arm: -2), steps: 8);
      await rig.drop(tester, g);
      expect(rig.tree.body, hasLength(1));
      expect(rig.first.exprMouths.single.single.op, 'run');

      // 短写法（一个式子槽、没有口）：也能从积木盒拖进口里那块的槽。
      await tester.ensureVisible(rig.item('expr-fnShort'));
      await tester.pumpAndSettle();
      from = tester.getTopLeft(rig.item('expr-fnShort')) + const Offset(10, 14);
      g = await tester.startGesture(from);
      await tester.pump(const Duration(milliseconds: 220));
      await rig.glide(tester, g, from, from + const Offset(0, -40), steps: 4);
      expect(rig.s.drag!.piece.loose!.mouth, isNull);
      final inner = inMouth([lcStep(0)], 0);
      await rig.glide(tester, g, from + const Offset(0, -40), rig.exprSnap('s1', inner, 'fn'), steps: 10);
      await rig.drop(tester, g);
      final short = asExpr(rig.tree.blockAt(inner)!.args['fn'])!;
      expect(exprKind(short), 'fnShort');
      expect(short['params'], ['x']);
      expect(tester.takeException(), isNull);
    });
  });
}
