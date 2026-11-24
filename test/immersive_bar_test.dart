// “搭建”相关页面（有画布）上的悬浮顶栏（390×844，另加一组带状态栏 / 系统手势条的）。2026-11-24 第二轮起它和全应用是同一个 PageBar：
// 顶栏没有底色（只有一层不接手指的渐隐遮罩）、画布从屏幕最顶铺起；按钮和标题都在、可点；标题只有文字、没有胶囊；
// 顶栏空白处能拖画布；起始内容不被顶栏挡住；定位（跳到积木、双击回原位、适应屏幕）把顶栏那一段当成被盖住的。
//   LOPI_SHOTS=1 flutter test --no-pub test/immersive_bar_test.dart   # 同时把截图写到 docs/screenshots/10-*.png
import 'dart:io';

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/blocks/block_dock.dart';
import 'package:lopicode/blocks/block_editor_view.dart';
import 'package:lopicode/core/templates.dart';
import 'package:lopicode/lowcode/builder_screen.dart';
import 'package:lopicode/lowcode/canvas_view.dart';
import 'package:lopicode/lowcode/layers_sheet.dart';
import 'package:lopicode/lowcode/model.dart';
import 'package:lopicode/project_session.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/backend_screen.dart';
import 'package:lopicode/ui/chrome.dart';
import 'package:lopicode/ui/shell.dart';
import 'package:material_ui/material_ui.dart';

import 'backend_screen_test.dart' as be show boot, project, tapNav;
import 'blocks_issue_ui_test.dart' show troubled;
import 'lowcode_component_ui_test.dart' as comp show cardDoc, fontsLoaded, moreAction, openBuilder, select;
import 'screens_test.dart' show fontsLoaded, shot;
import 'support/blocks_rig.dart';
import 'support/harness.dart';

Finder k(String key) => find.byKey(ValueKey(key));

/// 现在看得见的那个顶栏。它自己是透明的（正中间点不到东西），所以靠“里面的左圆按钮点得到”来认；
/// 单独打开的页面没有左按钮（没有上一页可回），那时整棵树里只有它一个。
Finder bar() {
  final shown = find.ancestor(of: find.byType(RoundIconButton).hitTestable(), matching: find.byType(PageBar));
  return shown.evaluate().isEmpty ? find.byType(PageBar) : shown;
}

const EdgeInsets kSafe = EdgeInsets.only(top: 30, bottom: 20);

/// 悬浮顶栏里画了底色 / 描边 / 阴影的东西：只许是悬浮的小块（左圆按钮、操作胶囊，都比屏幕窄得多），不许有横贯整条的；
/// 唯一的例外是那层渐隐遮罩（bar-scrim）：它不接手指、最下面是全透明的，另外检查。
void expectNoBarBackground(WidgetTester tester, {required double top}) {
  final b = bar();
  expect(b, findsOneWidget);
  final rect = tester.getRect(b);
  expect(rect.top, 0, reason: '顶栏从屏幕最顶算起（状态栏那一段也是透明的）');
  expect(rect.bottom, top + PageBar.kHeight);
  expect(rect.width, 390);
  var painted = 0;
  void check(Element e, Object? decoration, Color? color) {
    final has = color != null && color.a > 0 || decoration is BoxDecoration && (decoration.color != null || decoration.gradient != null || decoration.border != null || decoration.boxShadow != null);
    if (!has || e.widget.key == const ValueKey('bar-scrim')) return;
    painted++;
    final r = tester.getRect(find.byElementPredicate((x) => x == e));
    expect(r.width, lessThan(260), reason: '顶栏里不许有横贯整条的底色 / 分隔线 / 阴影：${e.widget.runtimeType} $r');
    expect(r.top, greaterThanOrEqualTo(top), reason: '状态栏那一段不画东西');
  }

  for (final e in find.descendant(of: b, matching: find.byWidgetPredicate((w) => w is DecoratedBox || w is ColoredBox || w is Container || w is Material)).evaluate()) {
    final w = e.widget;
    switch (w) {
      case DecoratedBox(:final decoration):
        check(e, decoration, null);
      case ColoredBox(:final color):
        check(e, null, color);
      case Container(:final decoration, :final color):
        check(e, decoration, color);
      case Material(:final color, :final type):
        check(e, null, type == MaterialType.transparency ? null : color);
    }
  }
  expect(painted, greaterThanOrEqualTo(1), reason: '悬浮按钮自己的底还在（看得清）');
  expect(
    find.descendant(of: b, matching: find.byKey(const ValueKey('immersive-title'))),
    findsNothing,
    reason: '标题没有胶囊，只有文字',
  );
  final scrim = find.descendant(of: b, matching: find.byKey(const ValueKey('bar-scrim')));
  expect(scrim, findsOneWidget);
  expect(
    find.ancestor(of: scrim, matching: find.byType(IgnorePointer)),
    findsWidgets,
    reason: '遮罩不接手指',
  );
  final g = (tester.widget<DecoratedBox>(scrim).decoration as BoxDecoration).gradient! as LinearGradient;
  expect(g.colors.last.a, 0, reason: '遮罩往下淡到全透明，没有边');
  expect(tester.getRect(scrim).bottom, rect.bottom + BarScrim.kTail);
}

/// 顶栏里的一个按钮：看得见、点得到、点击区域不小于 44。
void expectButton(WidgetTester tester, Finder button, String what) {
  final f = find.descendant(of: bar(), matching: button);
  expect(f.hitTestable(), findsOneWidget, reason: what);
  final size = tester.getSize(f);
  expect(size.width, greaterThanOrEqualTo(44), reason: what);
  expect(size.height, greaterThanOrEqualTo(44), reason: what);
}

/// 顶栏里一块“什么都没有”的地方：按钮上面那一条的正中间。
Offset blankInBar(double top) => Offset(195, top + 5);

/// 打开低代码搭建页；`safe`＝假装屏幕上下有状态栏 / 系统手势条。
Future<ProjectSession> openBuilder(WidgetTester tester, {LcDocument? doc, ThemeMode mode = ThemeMode.light, EdgeInsets? safe}) async {
  usePhoneViewport(tester);
  late TestEnv env;
  late ProjectSession session;
  await tester.runAsync(() async {
    env = await TestEnv.create();
    final project = await env.services.projects.create('我的小站', ProjectTemplate.lowcode);
    session = ProjectSession(env.services, project);
    if (doc != null) File(session.guard.resolve(kLowcodePageFile)).writeAsStringSync(doc.encode());
  });
  addTearDown(() async {
    session.dispose();
    await env.dispose();
  });
  await tester.pumpWidget(
    appFor(
      env,
      Builder(
        builder: (context) => safe == null
            ? BuilderScreen(session: session)
            : MediaQuery(
                data: MediaQuery.of(context).copyWith(padding: safe, viewPadding: safe),
                child: BuilderScreen(session: session),
              ),
      ),
      mode: mode,
      font: fontsLoaded ? kTestFont : null,
    ),
  );
  await settle(tester, rounds: 6);
  return session;
}

/// 一张很长的页面（一屏放不下，能上下滚）。
LcDocument longDoc() {
  final doc = LcDocument.starter('长页面');
  for (var i = 0; i < 40; i++) {
    doc.insert(doc.root.id, doc.newNode('text')..props['text'] = '第 ${i + 1} 行');
  }
  return doc;
}

/// 页面那一块在屏幕上的位置。
Rect pageRect(WidgetTester tester) {
  final view = find.byType(CanvasView).hitTestable();
  return tester.state<CanvasViewState>(view).pageRect.shift(tester.getTopLeft(view));
}

void main() {
  setUpAll(() async => comp.fontsLoaded = fontsLoaded = await loadRealFonts());
  tearDown(BkDockMemory.clear);

  for (final safe in <EdgeInsets?>[null, kSafe]) {
    final tag = safe == null ? '没有状态栏' : '状态栏 30 / 手势条 20';
    final top = safe?.top ?? 0;
    final barBottom = top + PageBar.kHeight;

    group('积木逻辑页（$tag）', () {
      testWidgets('顶栏没有底色，画布从屏幕最顶铺起；返回、标题、副标题、变量、问题、看代码都在、都能点', (tester) async {
        final rig = Rig(troubled());
        await rig.pumpLogic(tester, safe: safe);
        expectNoBarBackground(tester, top: top);
        expect(tester.getRect(k('bk-canvas')).top, 0);
        expect(tester.getRect(k('bk-canvas')).width, 390);

        expect(find.descendant(of: bar(), matching: find.text('积木逻辑')), findsOneWidget);
        expect(
          find.descendant(of: bar(), matching: find.text('2 个错误，没更新')),
          findsOneWidget,
          reason: '副标题还在',
        );
        // 标题只有文字（和别的页面一样），贴着左按钮；下面滑过的积木由渐隐遮罩淡掉。
        final back = tester.getRect(find.byType(RoundIconButton));
        expect(back, Rect.fromLTWH(16, top + 10, 44, 44), reason: '左按钮还在状态栏下面的老位置');
        expect(tester.getRect(find.byType(BarTitle)).left, back.right + Space.x3);
        expect(tester.getRect(find.byType(BarTitle)).right, lessThanOrEqualTo(tester.getRect(find.byType(ActionPill)).left - Space.x3));
        expect(tester.getRect(find.byType(ActionPill)).right, 390 - Space.x4);

        expectButton(tester, find.byTooltip('返回'), '返回');
        expectButton(tester, k('lc-top-vars'), '变量');
        expectButton(tester, k('bk-issues'), '问题');
        expectButton(tester, k('bk-code'), '看代码');

        await tester.tap(k('bk-issues'));
        await tester.pumpAndSettle();
        expect(find.textContaining('个问题'), findsWidgets);
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        await tester.tap(k('lc-top-vars'));
        await tester.pumpAndSettle();
        expect(find.textContaining('变量'), findsWidgets);
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('返回'));
        await tester.pumpAndSettle();
        expect(find.byType(BlockEditorView), findsNothing, reason: '返回真的返回了');
        expect(tester.takeException(), isNull);
      });

      testWidgets('起始时第一串积木在顶栏下沿之下；顶栏空白处往下拖＝平移画布；双击空白处回到原位（还在顶栏下面）', (tester) async {
        final rig = Rig(troubled());
        await rig.pumpLogic(tester, safe: safe);
        double firstTop() => [for (final p in rig.s.layout.scripts) rig.s.globalOf(rig.s.toView(p.origin)).dy].reduce((a, b) => a < b ? a : b);
        expect(rig.s.pan, Offset.zero);
        expect(firstTop(), greaterThanOrEqualTo(barBottom), reason: '第一串不被悬浮顶栏挡住');
        expect(firstTop(), lessThan(barBottom + 40));

        final g = await tester.startGesture(blankInBar(top));
        await tester.pump(const Duration(milliseconds: 20));
        for (var i = 0; i < 6; i++) {
          await g.moveBy(const Offset(0, 15));
          await tester.pump(const Duration(milliseconds: 16));
        }
        await g.up();
        await tester.pumpAndSettle();
        expect(rig.s.pan.dy, closeTo(90, 1), reason: '手指落在顶栏的空白处，等于落在画布上');

        // 往上推：积木从顶栏按钮下面滑过去（画布一直铺到最顶）。
        rig.s.setPan(const Offset(0, -40));
        (rig.s.context as Element).markNeedsBuild();
        await tester.pump();
        expect(firstTop(), lessThan(barBottom));

        final blank = Offset(370, barBottom + 300);
        await tester.tapAt(blank);
        await tester.pump(const Duration(milliseconds: 80));
        await tester.tapAt(blank);
        await tester.pumpAndSettle();
        expect(rig.s.pan, Offset.zero);
        expect(rig.s.zoom, 1);
        expect(firstTop(), greaterThanOrEqualTo(barBottom));
        expect(tester.takeException(), isNull);
      });

      testWidgets('跳到某块积木：不落在顶栏后面；缩放的中心是露出来那一段的正中', (tester) async {
        final rig = Rig(troubled());
        await rig.pumpLogic(tester, safe: safe);
        final id = rig.s.layout.scripts.first.id;
        Rect hat() => rig.s.rectToView(rig.s.layout.placed(id)!.layout.hat!.rect.shift(rig.s.layout.placed(id)!.origin));
        // 先把它推到顶栏后面去。
        rig.s.setPan(Offset(0, -hat().top + top + 6 + rig.s.pan.dy));
        (rig.s.context as Element).markNeedsBuild();
        await tester.pump();
        expect(rig.s.globalOf(hat().topLeft).dy, lessThan(barBottom));
        rig.s.jumpTo(id, const []);
        await tester.pumpAndSettle();
        expect(rig.s.globalOf(hat().topLeft).dy, greaterThanOrEqualTo(barBottom + 56), reason: '跳过去以后在顶栏（和它下面的小工具条）之下');
        expect(rig.s.globalOf(hat().bottomLeft).dy, lessThan(tester.getRect(k('bk-dock')).top));

        final dockTop = tester.getRect(k('bk-dock')).top;
        expect(rig.s.globalOf(rig.s.canvasCenter).dy, closeTo((barBottom + dockTop) / 2, 0.5));
        expect(tester.takeException(), isNull);
      });

      testWidgets('积木盒面板拖到最高：上沿＝状态栏下沿，盖住悬浮顶栏；还能拖回来，顶栏又能点', (tester) async {
        final rig = Rig(troubled());
        await rig.pumpLogic(tester, safe: safe);
        Future<void> pull(double dy) async {
          final g = await tester.startGesture(tester.getCenter(k('bk-palette-grip')));
          for (var i = 0; i < 10; i++) {
            await g.moveBy(Offset(0, dy / 10));
            await tester.pump(const Duration(milliseconds: 16));
          }
          await g.up();
          await tester.pumpAndSettle();
        }

        await pull(-900);
        expect(tester.getRect(k('bk-dock')).top, top);
        expect(
          find.descendant(of: find.byType(PageBar), matching: k('bk-code')).hitTestable(),
          findsNothing,
          reason: '面板盖住了顶栏',
        );
        await pull(900);
        expect(tester.getRect(k('bk-dock')).top, greaterThan(barBottom + 300));
        expectButton(tester, k('bk-code'), '看代码');
        expect(tester.takeException(), isNull);
      });
    });

    group('低代码画布页（$tag）', () {
      testWidgets('顶栏没有底色，画布从屏幕最顶铺起；页面顶边在顶栏下沿；撤销、重做、图层、更多都在、都能点', (tester) async {
        await openBuilder(tester, safe: safe);
        expectNoBarBackground(tester, top: top);
        final canvas = tester.getRect(k('lowcode-canvas'));
        expect(canvas.top, 0);
        expect(canvas.width, 390);
        expect(pageRect(tester).top, barBottom, reason: '页面的顶边起始时正好在悬浮顶栏的下沿');
        expect(pageRect(tester).bottom, lessThanOrEqualTo(canvas.bottom - kCanvasToolsInset + 0.5), reason: '一屏放得下的页面不压到底部的小胶囊下面');
        expect(find.descendant(of: bar(), matching: find.text('低代码搭建')), findsOneWidget);
        for (final tip in ['撤销', '重做', '图层', '更多']) {
          expectButton(tester, find.byTooltip(tip), tip);
        }
        // “怎么看”的两个小胶囊浮在画布底部，中间是透明的。
        final width = tester.getRect(k('lowcode-width-pill')), zoom = tester.getRect(k('lowcode-zoom-pill'));
        expect(width.bottom, lessThanOrEqualTo(canvas.bottom));
        expect(width.top, greaterThanOrEqualTo(canvas.bottom - kCanvasToolsInset));
        expect(width.right, lessThan(zoom.left));
        expect(find.byTooltip('适应屏幕').hitTestable(), findsOneWidget);

        await tester.tap(find.byTooltip('图层'));
        await tester.pumpAndSettle();
        expect(find.byType(LayerSheet), findsOneWidget);
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('更多'));
        await tester.pumpAndSettle();
        expect(find.text('积木逻辑'), findsOneWidget);
        await tester.tapAt(const Offset(40, 700));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });

      testWidgets('长页面：在顶栏空白处往上拖＝滚动画布，页面从顶栏下面滑过去；滚到底时底边停在小胶囊上面；适应屏幕回到顶栏下沿', (tester) async {
        await openBuilder(tester, doc: longDoc(), safe: safe);
        final canvas = tester.getRect(k('lowcode-canvas'));
        expect(pageRect(tester).top, barBottom);
        expect(pageRect(tester).height, greaterThan(canvas.height), reason: '这张页面一屏放不下');

        await tester.dragFrom(blankInBar(top), const Offset(0, -160));
        await tester.pump();
        await tester.pump(const Duration(seconds: 3));
        await settle(tester, rounds: 2);
        expect(pageRect(tester).top, lessThan(barBottom - 100), reason: '页面滑到顶栏下面去了');

        // 一路拖到底。
        for (var i = 0; i < 12; i++) {
          await tester.dragFrom(Offset(195, barBottom + 320), const Offset(0, -300));
          await tester.pump(const Duration(seconds: 2));
        }
        await settle(tester, rounds: 2);
        expect(pageRect(tester).bottom, closeTo(canvas.bottom - kCanvasToolsInset, 0.5));

        await tester.tap(find.byTooltip('适应屏幕'));
        await settle(tester, rounds: 2);
        expect(pageRect(tester).top, barBottom);
        // 往下拖不动：顶边不会离开顶栏下沿。
        await tester.dragFrom(Offset(195, barBottom + 320), const Offset(0, 200));
        await tester.pump(const Duration(seconds: 2));
        await settle(tester, rounds: 2);
        expect(pageRect(tester).top, barBottom);
        expect(tester.takeException(), isNull);
      });
    });
  }

  testWidgets('编辑组件页：同一个悬浮顶栏，标题、组件名、撤销、重做、更多、“完成”都在；“完成”能关掉', (tester) async {
    await comp.openBuilder(tester, doc: comp.cardDoc());
    await comp.select(tester, 'a');
    await comp.moreAction(tester, '编辑组件');
    expectNoBarBackground(tester, top: 0);
    expect(find.descendant(of: bar(), matching: find.text('编辑组件')), findsOneWidget);
    expect(find.descendant(of: bar(), matching: find.text('问候卡')), findsOneWidget);
    final canvas = find.byKey(const ValueKey('lowcode-canvas')).hitTestable();
    expect(tester.getRect(canvas).top, 0);
    expect(pageRect(tester).top, PageBar.kHeight);
    for (final tip in ['返回', '撤销', '重做', '更多']) {
      expectButton(tester, find.byTooltip(tip), tip);
    }
    await tester.tap(k('comp-editor-done'));
    await tester.pumpAndSettle();
    await settle(tester, rounds: 2);
    expect(find.text('编辑组件'), findsNothing);
    expect(find.byType(BuilderScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  group('后端积木页', () {
    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      final suffix = mode == ThemeMode.light ? 'light' : 'dark';
      testWidgets('悬浮顶栏：没有底色、画布到顶；标题、状态小字、运行、更多、问题、看代码都在 ($suffix)', (tester) async {
        await be.boot(tester, ProjectTemplate.backendBlocks, language: 'node', mode: mode);
        expectNoBarBackground(tester, top: 0);
        expect(tester.getRect(k('bk-canvas').hitTestable()).top, 0);
        expect(find.descendant(of: bar(), matching: find.text('后端积木')), findsOneWidget);
        final sub = find.descendant(of: bar(), matching: find.text('Node.js · 7 个接口'));
        expect(sub, findsOneWidget, reason: '状态小字还在');
        expect(
          tester.renderObject<RenderParagraph>(find.descendant(of: sub, matching: find.byType(RichText))).didExceedMaxLines,
          isFalse,
          reason: '右边四个按钮时小字也放得下，不被截成省略号',
        );
        expectButton(tester, find.byTooltip('打开侧边栏'), '汉堡按钮');
        for (final key in ['be-run', 'be-more', 'bk-issues', 'bk-code']) {
          expectButton(tester, k(key), key);
        }
        final ed = tester.state<BlockEditorViewState>(find.byType(BlockEditorView));
        final first = ed.globalOf(ed.toView(ed.layout.scripts.first.origin)).dy;
        expect(first, greaterThanOrEqualTo(PageBar.kHeight));
        await shot(tester, '10-backend-$suffix');
        await tester.tap(k('be-more'));
        await tester.pumpAndSettle();
        expect(k('be-menu-language'), findsOneWidget);
        await tester.tapAt(const Offset(40, 500));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('页面 + 后端都有：切换条也是浮着的，画布照样到顶；顶栏还在全应用同一个位置，切换条排在它下面', (tester) async {
      await be.boot(tester, ProjectTemplate.fullstack, language: 'python', before: () => File('${be.project.dir}/$kLowcodePageFile').writeAsStringSync(LcDocument.starter('首页').encode()));
      final sw = tester.getRect(k('hub-switch'));
      expect(sw.top, PageBar.kHeight);
      expect(tester.getRect(k('lowcode-canvas').hitTestable()).top, 0, reason: '切换条下面没有整条底色，画布一直到顶');
      expect(
        tester.getRect(find.descendant(of: bar(), matching: find.byType(RoundIconButton))),
        const Rect.fromLTWH(16, 10, 44, 44),
        reason: '顶栏不因为多了切换条往下挪',
      );
      expect(pageRect(tester).top, sw.bottom + Space.x2, reason: '页面起始在切换条下面');
      expect(
        tester.getRect(find.descendant(of: bar(), matching: find.byKey(const ValueKey('bar-scrim')))).bottom,
        sw.bottom + Space.x2 + BarScrim.kTail,
        reason: '渐隐遮罩盖到切换条下面',
      );
      await shot(tester, '10-hub-page-light');
      await tester.tap(find.descendant(of: k('hub-switch'), matching: find.text('后端')));
      await settle(tester, rounds: 6);
      expect(find.byType(BackendScreen).hitTestable(), findsOneWidget);
      expect(tester.getRect(k('bk-canvas').hitTestable()).top, 0);
      expect(tester.getRect(find.descendant(of: bar(), matching: find.byType(RoundIconButton))), const Rect.fromLTWH(16, 10, 44, 44));
      final ed = tester.state<BlockEditorViewState>(find.byType(BlockEditorView));
      expect(ed.globalOf(ed.toView(ed.layout.scripts.first.origin)).dy, greaterThanOrEqualTo(sw.bottom), reason: '第一串积木在切换条下面');
      await shot(tester, '10-hub-backend-light');
      expect(tester.takeException(), isNull);
    });

    testWidgets('别的页面（聊天、文件、终端、打包）和搭建页是同一个悬浮顶栏：没有底色，位置和高度一样', (tester) async {
      await be.boot(tester, ProjectTemplate.backendBlocks, language: 'node', initial: ShellDest.chat);
      for (final d in [ShellDest.chat, ShellDest.files, ShellDest.terminal, ShellDest.apk, ShellDest.builder]) {
        await be.tapNav(tester, d);
        expect(bar(), findsOneWidget, reason: d.label);
        expectNoBarBackground(tester, top: 0);
        expect(
          tester.getRect(find.descendant(of: bar(), matching: find.byType(RoundIconButton))),
          const Rect.fromLTWH(16, 10, 44, 44),
          reason: d.label,
        );
      }
      expect(tester.takeException(), isNull);
    });
  });

  group('截图', () {
    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      final suffix = mode == ThemeMode.light ? 'light' : 'dark';

      testWidgets('低代码画布页 ($suffix)', (tester) async {
        final doc = LcDocument.starter('我的小站');
        doc.find('n3')!.style.addAll({'margin-top': '12px', 'margin-bottom': '20px'});
        await openBuilder(tester, doc: doc, mode: mode, safe: kSafe);
        await shot(tester, '10-builder-$suffix');
        await tester.pumpWidget(const SizedBox());
        await openBuilder(tester, doc: longDoc(), mode: mode, safe: kSafe);
        await tester.dragFrom(const Offset(195, 400), const Offset(0, -150));
        await tester.pump(const Duration(seconds: 3));
        await settle(tester, rounds: 2);
        await shot(tester, '10-builder-scrolled-$suffix');
      });

      testWidgets('积木逻辑页 ($suffix)', (tester) async {
        final rig = Rig(troubled());
        await rig.pumpLogic(tester, mode: mode, safe: kSafe);
        await shot(tester, '10-logic-$suffix');
        rig.s.setPan(const Offset(40, -70));
        (rig.s.context as Element).markNeedsBuild();
        await tester.pump();
        await shot(tester, '10-logic-under-bar-$suffix');
      });

      testWidgets('编辑组件页 ($suffix)', (tester) async {
        await comp.openBuilder(tester, doc: comp.cardDoc(), mode: mode);
        await comp.select(tester, 'a');
        await comp.moreAction(tester, '编辑组件');
        await shot(tester, '10-component-$suffix');
      });
    }
  });
}
