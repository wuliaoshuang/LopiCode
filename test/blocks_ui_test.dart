// 积木编辑器（lib/blocks）静态部分的界面测试：画布、选中、积木盒（390×844，浅色 + 深色）。
//   LOPI_SHOTS=1 flutter test --no-pub test/blocks_ui_test.dart   # 同时把截图写到 docs/screenshots/bk1-*.png
import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/blocks/block_canvas_view.dart';
import 'package:lopicode/blocks/block_geometry.dart';
import 'package:lopicode/blocks/block_paint_view.dart';
import 'package:lopicode/blocks/block_palette_view.dart';
import 'package:lopicode/blocks/block_script_view.dart';
import 'package:lopicode/lowcode/logic_block_host.dart';
import 'package:lopicode/lowcode/logic_blocks.dart';
import 'package:lopicode/lowcode/logic_model.dart';
import 'package:lopicode/lowcode/model.dart';
import 'package:lopicode/theme/app_theme.dart';
import 'package:material_ui/material_ui.dart';

import 'screens_test.dart' show fontsLoaded, shot;
import 'support/blocks_fixture.dart';
import 'support/harness.dart';

Future<void> pump(WidgetTester tester, Widget body, {ThemeMode mode = ThemeMode.light}) async {
  usePhoneViewport(tester);
  await tester.pumpWidget(
    RepaintBoundary(
      key: shotKey,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(Brightness.light, fontFamily: fontsLoaded ? kTestFont : null),
        darkTheme: buildAppTheme(Brightness.dark, fontFamily: fontsLoaded ? kTestFont : null),
        themeMode: mode,
        home: Scaffold(body: SafeArea(child: body)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// 画布 + 底下的积木盒（下一步的编辑页大致就是这个排法）。
Widget editor(LogicBlockHost host, {GlobalKey<BlockCanvasViewState>? canvasKey, String? category, void Function(BlockSelection?)? onSelect, void Function(BlockPaletteItem)? onPick}) => Column(
  children: [
    Expanded(
      child: BlockCanvasView(key: canvasKey, host: host, onSelectionChanged: onSelect),
    ),
    BlockPaletteView(host: host, initialCategory: category, onPick: onPick),
  ],
);

void main() {
  setUpAll(() async => fontsLoaded = await loadRealFonts());

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    final suffix = mode == ThemeMode.light ? 'light' : 'dark';

    testWidgets('画布：三串脚本都画出来，点积木选中、再点取消（$suffix）', (tester) async {
      final host = LogicBlockHost(doc: sampleDoc(), onEdit: (change) => fail('只读的画布不该改文档'));
      final key = GlobalKey<BlockCanvasViewState>();
      final picked = <BlockSelection?>[];
      await pump(
        tester,
        BlockCanvasView(key: key, host: host, onSelectionChanged: picked.add),
        mode: mode,
      );
      final layout = key.currentState!.layout;
      expect(layout.scripts, hasLength(3));
      expect(layout.scripts.every((s) => s.auto), isTrue, reason: '样例里都没有 x / y，全是自动排的');
      // 自动排：自上而下、不重叠。
      for (var i = 1; i < layout.scripts.length; i++) {
        expect(layout.scripts[i].bounds.top, greaterThan(layout.scripts[i - 1].bounds.bottom));
      }
      // 自动排的结果不写回模型。
      expect(host.doc.logic.handlers.every((h) => h.x == null && h.y == null), isTrue);
      await shot(tester, 'bk1-canvas-$suffix');

      // 点第一串的第 2 块（如果）的头。
      final first = layout.scripts.first;
      final ifBlock = first.layout.blockAt([lcStep(1)])!;
      final origin = tester.getTopLeft(find.byType(BlockCanvasView));
      await tester.tapAt(origin + first.origin + ifBlock.head.centerLeft + const Offset(6, 0));
      await tester.pump();
      expect(picked.last!.scriptId, first.id);
      expect(bkSameBlockPath(picked.last!.path, [lcStep(1)]), isTrue);
      await shot(tester, 'bk1-canvas-selected-$suffix');

      // 点 C 形块的口里的空白：不算点到它（口是空的地方），取消选中。
      final repeat = layout.scripts.first.layout.blocks.firstWhere((b) => b.block?.op == 'repeat');
      await tester.tapAt(origin + first.origin + repeat.mouths.first.rect.centerRight - const Offset(4, 0));
      await tester.pump();
      expect(picked.last, isNull);

      // 点帽子＝选中这一串本身。
      await tester.tapAt(origin + first.origin + first.layout.hat!.rect.center);
      await tester.pump();
      expect(picked.last!.path, isEmpty);
      // 再点一下取消。
      await tester.tapAt(origin + first.origin + first.layout.hat!.rect.center);
      await tester.pump();
      expect(picked.last, isNull);
    });

    testWidgets('积木盒：按类别分页，里面是画出来的积木，点一下回调（$suffix）', (tester) async {
      final host = LogicBlockHost(doc: sampleDoc(), onEdit: (change) => fail('不该改文档'));
      final picked = <BlockPaletteItem>[];
      await pump(tester, editor(host, onPick: picked.add), mode: mode);
      // 第一页是事件：三个帽子模板。
      for (final e in LcHandler.events) {
        expect(find.byKey(ValueKey('bk-palette-item-hat-$e')), findsOneWidget);
      }
      await shot(tester, 'bk1-palette-event-$suffix');
      await tester.tap(find.byKey(const ValueKey('bk-palette-item-hat-click')));
      expect(picked.single.kind, BlockPaletteKind.hat);
      expect(picked.single.id, 'click');

      for (final (id, shotName) in [('流程', 'control'), ('运算', 'operator'), ('网络', 'network'), ('控件', 'widget'), ('变量', 'variable')]) {
        final tab = find.byKey(ValueKey('bk-palette-tab-$id'));
        // 分类一行放不下，要横着滑；滑到看得见再点。
        final tabs = find.descendant(of: find.byType(BlockPaletteView), matching: find.byType(Scrollable)).first;
        await tester.scrollUntilVisible(tab, tester.any(tab) ? 0 : -80, scrollable: tabs);
        await tester.ensureVisible(tab);
        await tester.pumpAndSettle();
        await tester.tap(tab);
        await tester.pumpAndSettle();
        expect(find.byKey(ValueKey('bk-palette-page-$id')), findsOneWidget);
        await shot(tester, 'bk1-palette-$shotName-$suffix');
      }
      // 变量页：两块语句积木 + 一个表达式。
      expect(find.byKey(const ValueKey('bk-palette-item-block-setVar')), findsOneWidget);
      expect(find.byKey(const ValueKey('bk-palette-item-expr-var')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('bk-palette-item-expr-var')));
      expect(picked.last.kind, BlockPaletteKind.expr);
      expect(picked.last.layout.loose, isNotNull);
      // 每一样的触控范围不小于 40 高。
      expect(tester.getSize(find.byKey(const ValueKey('bk-palette-item-expr-var'))).height, greaterThanOrEqualTo(40));
    });

    testWidgets('各种外形与状态：长句换行、深嵌套、不认识的积木、被拖起、落点阴影（$suffix）', (tester) async {
      final host = LogicBlockHost(doc: shapesDoc(), onEdit: (change) => fail('不该改文档'));
      late BkKit kit;
      await pump(
        tester,
        Builder(
          builder: (context) {
            kit = BkKit.of(context);
            final engine = kit.engine(host);
            final lifted = engine.layoutStack([newBlock('repeat', host.doc)..body.add(newBlock('alert', host.doc))]);
            final ghost = engine.layoutStack([newBlock('alert', host.doc)]);
            return ColoredBox(
              color: kit.palette.canvas,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    BlockScriptView(
                      host: host,
                      scriptId: 'h1',
                      state: BkPaintState(
                        selected: [lcStep(0)],
                        selectedSlot: (block: [lcStep(1)], arg: 'cond', path: const ['l']),
                        errors: [
                          [lcStep(2)],
                        ],
                        warnings: [
                          [lcStep(3)],
                        ],
                      ),
                    ),
                    const SizedBox(height: 28),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        BkLayoutView(layout: lifted, kit: kit, state: const BkPaintState(lifted: true)),
                        const SizedBox(width: 24),
                        BkLayoutView(layout: ghost, kit: kit, state: const BkPaintState(ghost: true)),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        ),
        mode: mode,
      );
      expect(find.byType(BlockScriptView), findsOneWidget);
      expect(tester.getSize(find.byType(BlockScriptView)).width, lessThanOrEqualTo(const BkMetrics().maxBlockWidth + 1), reason: '最外层的积木不超过最大宽度');
      await shot(tester, 'bk1-shapes-$suffix');
      // 往下滑到被拖起的样子和落点阴影。
      await tester.drag(find.byType(SingleChildScrollView), const Offset(0, -900));
      await tester.pumpAndSettle();
      await shot(tester, 'bk1-states-$suffix');
    });

    testWidgets('深嵌套 12 层 + 空画布（$suffix）', (tester) async {
      final host = LogicBlockHost(doc: deepDoc(), onEdit: (change) => fail('不该改文档'));
      final key = GlobalKey<BlockCanvasViewState>();
      await pump(
        tester,
        BlockCanvasView(key: key, host: host),
        mode: mode,
      );
      expect(key.currentState!.layout.scripts.single.layout.blocks, hasLength(1 + 12 + 1));
      await shot(tester, 'bk1-deep-$suffix');

      final empty = LogicBlockHost(doc: LcDocument.starter('空'), onEdit: (change) {});
      await pump(tester, editor(empty), mode: mode);
      expect(find.textContaining('还没有积木'), findsOneWidget);
      await shot(tester, 'bk1-empty-$suffix');
    });
  }

  testWidgets('宿主内容变了（revision 变了）画布跟着重排；选中的积木被删就取消选中', (tester) async {
    final doc = sampleDoc();
    final host = LogicBlockHost(doc: doc, onEdit: (change) => change(doc));
    final key = GlobalKey<BlockCanvasViewState>();
    var rebuilds = 0;
    late StateSetter refresh;
    host.onChanged = () => refresh(() => rebuilds++);
    await pump(
      tester,
      StatefulBuilder(
        builder: (context, setState) {
          refresh = setState;
          return BlockCanvasView(key: key, host: host);
        },
      ),
    );
    final before = key.currentState!.layout.scripts.first.layout.blocks.length;
    key.currentState!.select(BlockSelection('h1', [lcStep(0)]));
    await tester.pump();
    expect(key.currentState!.selection, isNotNull);

    host.edit(() => host.script('h1')!.removeBlock([lcStep(0)]));
    await tester.pump();
    expect(rebuilds, 1);
    expect(key.currentState!.layout.scripts.first.layout.blocks.length, lessThan(before));
    // 原来的第 1 块没了，路径 [0] 现在是另一块：选中的是“位置”，还在就留着。
    expect(key.currentState!.selection, isNotNull);

    host.edit(() => host.removeScript('h1'));
    await tester.pump();
    expect(key.currentState!.selection, isNull);
    expect(key.currentState!.layout.scripts, hasLength(2));

    // 摆过位置的脚本照 x / y 放。
    host.edit(() {
      host.script('h2')!
        ..x = 120
        ..y = 300;
    });
    await tester.pump();
    final placed = key.currentState!.layout.placed('h2')!;
    expect(placed.auto, isFalse);
    expect(placed.origin, const Offset(120, 300));
    host.onChanged = null;
  });
}
