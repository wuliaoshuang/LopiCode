// 顶栏（390×844）：标题只有文字、贴着左按钮左对齐；左右按钮按下的反馈一模一样，都裁在 44 的圆里。
//   LOPI_SHOTS=1 flutter test test/topbar_test.dart   # 同时写截图到 docs/screenshots/tb-*.png
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/chrome.dart';
import 'package:lopicode/ui/preview_tab.dart';
import 'package:lopicode/ui/project_shell.dart';
import 'package:lopicode/ui/shell.dart';
import 'package:material_ui/material_ui.dart';

import 'screens_test.dart' show fontsLoaded, shot;
import 'shell_test.dart' show openProject;
import 'support/harness.dart';

/// 现在看得见的那个顶栏。它自己是透明的、不接手指（正中间点不到东西），所以靠“里面的左圆按钮点得到”来认。
Finder shownBar() => find.ancestor(of: find.byType(RoundIconButton).hitTestable(), matching: find.byType(PageBar));

/// 截一张当前画面，取几个点的颜色（逻辑坐标）。
Future<List<int>> pixelsAt(WidgetTester tester, List<Offset> points) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(shotKey));
  late List<int> out;
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    out = [for (final p in points) data.getUint32((p.dy.round() * image.width + p.dx.round()) * 4)];
    image.dispose();
  });
  return out;
}

/// 按住不放，等按下的反馈完全显出来。
Future<TestGesture> hold(WidgetTester tester, Finder target) async {
  final g = await tester.startGesture(tester.getCenter(target), kind: PointerDeviceKind.touch);
  for (final ms in [60, 200, 200, 300]) {
    await tester.pump(Duration(milliseconds: ms));
  }
  return g;
}

Future<void> release(WidgetTester tester, TestGesture g) async {
  await g.cancel();
  for (var i = 0; i < 3; i++) {
    await tester.pump(const Duration(milliseconds: 500));
  }
}

/// 这个按钮真正接收按压、画反馈的那一块。
InkWell inkOf(WidgetTester tester, Finder button) => tester.widget<InkWell>(find.descendant(of: button, matching: find.byType(InkWell)));
Rect inkRect(WidgetTester tester, Finder button) => tester.getRect(find.descendant(of: button, matching: find.byType(InkWell)));

/// 标题文字到顶栏之间有没有画了底色 / 描边 / 阴影的框（顶栏自己的底不算）。
List<BoxDecoration> decorationsAround(WidgetTester tester, Finder text) {
  final out = <BoxDecoration>[];
  tester.element(text).visitAncestorElements((e) {
    final w = e.widget;
    if (w is SafeArea) return false; // 到顶栏自己的那一层为止（再往外是顶栏的底色）
    final d = switch (w) {
      DecoratedBox(:final decoration) => decoration,
      Container(:final decoration?) => decoration,
      _ => null,
    };
    if (d is BoxDecoration && (d.color != null || d.border != null || d.boxShadow != null || d.gradient != null)) out.add(d);
    if (w is Material && w.type != MaterialType.transparency) out.add(BoxDecoration(color: w.color));
    return true;
  });
  return out;
}

/// 标题文字到顶栏之间有没有能点的东西。
bool tappableAround(WidgetTester tester, Finder text) {
  var found = false;
  tester.element(text).visitAncestorElements((e) {
    final w = e.widget;
    if (w is SafeArea) return false; // 到顶栏自己的那一层为止（再往外是顶栏的底色）
    if (w is GestureDetector || w is InkResponse || w is Listener && w.onPointerDown != null) found = true;
    return true;
  });
  return found;
}

Widget barHost(TestEnv env, PreferredSizeWidget bar, {ThemeMode mode = ThemeMode.light, bool shell = true}) {
  final page = Scaffold(appBar: bar, body: const SizedBox.expand());
  return appFor(
    env,
    shell ? ShellScope(openDrawer: () {}, go: (_) {}, projectName: '我的前端 + 后端', child: page) : page,
    mode: mode,
    font: kTestFont,
  );
}

void main() {
  setUpAll(() async {
    fontsLoaded = await loadRealFonts();
    PreviewTab.debugViewBuilder = (uri) => const ColoredBox(color: Colors.white);
  });
  tearDownAll(() => PreviewTab.debugViewBuilder = null);

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    final suffix = mode == ThemeMode.light ? 'light' : 'dark';

    testWidgets('对话页标题：只有两行文字，没有胶囊底色和描边，贴着左按钮左对齐 ($suffix)', (tester) async {
      final (env, project, session) = await openProject(tester);
      await tester.pumpWidget(
        appFor(
          env,
          ProjectShell(project: project, session: session),
          mode: mode,
          font: kTestFont,
        ),
      );
      await settle(tester);

      final title = find.descendant(of: find.byType(PageBar), matching: find.text('新对话')).hitTestable();
      final sub = find.text('我的小站 / 未设置模型').hitTestable();
      expect(title, findsOneWidget);
      expect(sub, findsOneWidget);
      final c = tester.element(title).colors;

      expect(decorationsAround(tester, title), isEmpty, reason: '标题外面不能再有底色、描边或阴影');
      expect(tappableAround(tester, title), isFalse, reason: '标题以前就不可点，现在也不可点');

      // 层级靠字重和颜色：标题常规字重、不比以前（14）大；小字更小更淡
      final ts = tester.widget<Text>(title).style!;
      expect(ts.fontWeight, FontWeight.w400);
      expect(ts.fontSize, lessThanOrEqualTo(FontSize.sm));
      expect(ts.color, c.text);
      final ss = tester.widget<Text>(sub).style!;
      expect(ss.fontSize, FontSize.xs);
      expect(ss.color, c.textFaint);

      // 贴着左按钮右侧，两行左边对齐，竖直方向和按钮居中
      final menu = tester.getRect(find.byType(RoundIconButton).hitTestable());
      expect(menu.size, const Size(44, 44));
      expect(tester.getRect(title).left, menu.right + Space.x3);
      expect(tester.getRect(sub).left, tester.getRect(title).left);
      final block = tester.getRect(find.descendant(of: shownBar(), matching: find.byType(BarTitle)));
      expect(block.center.dy, closeTo(menu.center.dy, 0.5));
      expect(tester.getRect(sub).right, lessThanOrEqualTo(tester.getRect(find.byType(ActionPill).hitTestable()).left - Space.x3));

      // 右上“···”还是原来的菜单
      await tester.tap(find.byTooltip('更多').hitTestable());
      await tester.pumpAndSettle();
      expect(find.text('导出对话'), findsOneWidget);
      await tester.tapAt(const Offset(60, 600));
      await tester.pumpAndSettle();
      await shot(tester, 'tb-5-chat-$suffix');
    });

    testWidgets('按住左上按钮：反馈裁在 44 的圆里，和右上“···”一模一样 ($suffix)', (tester) async {
      final (env, project, session) = await openProject(tester);
      await tester.pumpWidget(
        appFor(
          env,
          ProjectShell(project: project, session: session),
          mode: mode,
          font: kTestFont,
        ),
      );
      await settle(tester);

      final menu = find.byTooltip('打开侧边栏').hitTestable();
      final more = find.byTooltip('更多').hitTestable();
      final round = tester.getRect(find.byType(RoundIconButton).hitTestable());

      // 画反馈的那一块：都是 44×44 的圆，正好是按钮本身（以前左边是 42×62 的长条）
      expect(inkRect(tester, menu), round);
      expect(inkRect(tester, menu).size, const Size(44, 44));
      expect(inkRect(tester, more).size, const Size(44, 44));
      expect(inkRect(tester, more), tester.getRect(find.byType(ActionPill).hitTestable()), reason: '只有一个操作时，胶囊就是这个圆');
      expect(inkRect(tester, menu).center.dy, inkRect(tester, more).center.dy);
      final a = inkOf(tester, menu);
      final b = inkOf(tester, more);
      expect(a.customBorder, isA<CircleBorder>());
      expect(a.customBorder, b.customBorder);
      for (final states in [
        {WidgetState.pressed},
        {WidgetState.hovered},
        {WidgetState.focused},
      ]) {
        expect(a.overlayColor!.resolve(states), isNotNull);
        expect(a.overlayColor!.resolve(states), b.overlayColor!.resolve(states), reason: '$states 时两个按钮的颜色要一样');
      }
      expect(a.splashFactory, b.splashFactory);
      expect(a.radius, b.radius);

      // 真画出来看：圆外面（以前长条伸出去的地方）按下前后一个像素都不变，圆里面变了
      for (final (name, button) in [('menu', menu), ('more', more)]) {
        final r = inkRect(tester, button);
        final outside = [Offset(r.center.dx, r.top - 5), Offset(r.center.dx, r.bottom + 5), Offset(r.center.dx, r.top - 9), Offset(r.left - 3, r.center.dy)];
        final inside = [Offset(r.center.dx, r.top + 8), Offset(r.center.dx, r.bottom - 8)];
        final before = await pixelsAt(tester, [...outside, ...inside]);
        final g = await hold(tester, button);
        final during = await pixelsAt(tester, [...outside, ...inside]);
        await shot(tester, 'tb-9-press-$name-$suffix');
        await release(tester, g);
        expect(during.sublist(0, outside.length), before.sublist(0, outside.length), reason: '$name：按下的反馈不能画到圆外面');
        for (var i = outside.length; i < before.length; i++) {
          expect(during[i], isNot(before[i]), reason: '$name：圆里面应该看得到按下的反馈');
        }
      }
      // 两个按钮按下时，圆里同一个位置的颜色一样
      Future<int> pressedColor(Finder button) async {
        final r = inkRect(tester, button);
        final g = await hold(tester, button);
        final px = await pixelsAt(tester, [Offset(r.center.dx, r.top + 8)]);
        await release(tester, g);
        return px.single;
      }

      expect(await pressedColor(menu), await pressedColor(more));
      // 按住再松开不算点：侧边栏没开
      expect(find.byType(AppDrawer), findsNothing);
    });

    testWidgets('别的页面是同一个顶栏：标题左对齐、只有文字，按钮都是 44 的圆 ($suffix)', (tester) async {
      final (env, project, session) = await openProject(tester);
      await tester.pumpWidget(
        appFor(
          env,
          ProjectShell(project: project, session: session),
          mode: mode,
          font: kTestFont,
        ),
      );
      await settle(tester);
      double? left;
      for (final d in [...ShellDest.bottom.skip(1), ShellDest.chat]) {
        await tester.tap(find.byKey(ValueKey('nav-${ShellDest.bottom.indexOf(d)}')));
        await settle(tester, rounds: 8);
        // 五个页面（含有画布的“搭建”页）都是同一个 PageBar：标题只有文字，没有胶囊。
        final bar = shownBar();
        expect(bar, findsOneWidget, reason: '“${d.label}”页');
        expect(tester.getSize(bar).height, PageBar.kHeight, reason: '“${d.label}”页的顶栏高度');
        final block = find.descendant(of: bar, matching: find.byType(BarTitle));
        expect(block, findsOneWidget, reason: '“${d.label}”页的标题用的是统一的 BarTitle');
        final title = find.descendant(of: block, matching: find.byType(Text)).first;
        expect(decorationsAround(tester, title), isEmpty, reason: '“${d.label}”页');
        final round = tester.getRect(find.descendant(of: bar, matching: find.byType(RoundIconButton)));
        expect(round.size, const Size(44, 44));
        expect(inkRect(tester, find.descendant(of: bar, matching: find.byType(RoundIconButton))), round);
        left ??= tester.getRect(title).left;
        expect(tester.getRect(title).left, left, reason: '“${d.label}”页的标题和别的页左边对齐');
        expect(tester.getRect(title).left, round.right + Space.x3);
        final pill = find.descendant(of: bar, matching: find.byType(ActionPill));
        if (pill.evaluate().isNotEmpty) {
          expect(tester.getRect(pill).height, 44);
          expect(tester.getRect(block).right, lessThanOrEqualTo(tester.getRect(pill).left - Space.x3));
        }
        expect(tester.takeException(), isNull, reason: '“${d.label}”页');
        if (d == ShellDest.files || d == ShellDest.builder) await shot(tester, 'tb-5-${d.name}-$suffix');
      }
    });

    testWidgets('标题太长：省略号截断，不挤右边的操作，也不溢出 ($suffix)', (tester) async {
      usePhoneViewport(tester);
      late TestEnv env;
      await tester.runAsync(() async => env = await TestEnv.create());
      addTearDown(() => env.dispose());
      var taps = 0;
      await tester.pumpWidget(
        barHost(
          env,
          mode: mode,
          ShellAppBar(
            title: '帮我把首页的轮播图改成自动播放并且加上左右滑动的手势还有指示小圆点',
            subtitle: '一个名字起得特别特别特别长的工作区 / some-provider/very-long-model-name-2026-11-24-preview',
            actions: [
              IconButton(tooltip: '撤销', icon: const Icon(Icons.undo), onPressed: () => taps++),
              const IconButton(tooltip: '重做', icon: Icon(Icons.redo), onPressed: null),
              IconButton(tooltip: '图层', icon: const Icon(Icons.layers_outlined), onPressed: () => taps++),
            ],
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      final block = tester.getRect(find.byType(BarTitle));
      final pill = tester.getRect(find.byType(ActionPill));
      final menu = tester.getRect(find.byType(RoundIconButton));
      expect(block.left, menu.right + Space.x3);
      expect(block.right, lessThanOrEqualTo(pill.left - Space.x3));
      expect(pill.right, 390 - Space.x4);
      expect(pill.size, const Size(44.0 * 3, 44));
      for (final text in find.descendant(of: find.byType(BarTitle), matching: find.byType(Text)).evaluate()) {
        final w = text.widget as Text;
        expect(w.maxLines, 1);
        expect(w.overflow, TextOverflow.ellipsis);
        final p = tester.renderObject<RenderParagraph>(find.descendant(of: find.byWidget(w), matching: find.byType(RichText)));
        expect(p.didExceedMaxLines, isTrue, reason: '这么长的字应该被截断');
        expect(p.size.width, lessThanOrEqualTo(block.width));
      }
      // 标题这一块至少 44 高（和按钮一样），里面两行字放得下
      final slot = tester.getRect(find.ancestor(of: find.byType(BarTitle), matching: find.byType(Align)).first);
      expect(slot.height, greaterThanOrEqualTo(44));
      expect(block.height, lessThanOrEqualTo(44));
      // 胶囊里的每个按钮都是 44 的圆，能点
      for (final tip in ['撤销', '重做', '图层']) {
        expect(inkRect(tester, find.byTooltip(tip)).size, const Size(44, 44), reason: tip);
      }
      await tester.tap(find.byTooltip('撤销'));
      await tester.tap(find.byTooltip('图层'));
      await tester.tap(find.byTooltip('重做'));
      expect(taps, 2);
      await shot(tester, 'tb-5-long-$suffix');
    });

    testWidgets('推进来的页面（返回按钮）：同一个标题样子；按住返回按钮也裁在圆里 ($suffix)', (tester) async {
      usePhoneViewport(tester);
      late TestEnv env;
      await tester.runAsync(() async => env = await TestEnv.create());
      addTearDown(() => env.dispose());
      await tester.pumpWidget(
        appFor(
          env,
          mode: mode,
          font: kTestFont,
          Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (context) => Scaffold(
                        backgroundColor: context.colors.canvas,
                        appBar: PageBar(
                          background: context.colors.canvas,
                          title: const Text('模型与渠道'),
                          actions: [IconButton(tooltip: '添加', icon: const Icon(Icons.add), onPressed: () {})],
                        ),
                        body: const SizedBox.expand(),
                      ),
                    ),
                  ),
                  child: const Text('进去'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('进去'));
      await tester.pumpAndSettle();
      final back = find.byTooltip('返回');
      final title = find.text('模型与渠道');
      final round = tester.getRect(find.byType(RoundIconButton));
      expect(round, const Rect.fromLTWH(16, 10, 44, 44));
      expect(inkRect(tester, back), round);
      expect(tester.getRect(title).left, round.right + Space.x3);
      expect(tester.getRect(title).center.dy, closeTo(round.center.dy, 0.5));
      expect(decorationsAround(tester, title), isEmpty);
      final style = tester.renderObject<RenderParagraph>(find.descendant(of: title, matching: find.byType(RichText))).text.style!;
      expect(style.fontWeight, FontWeight.w400);
      expect(style.fontSize, FontSize.sm);
      // 返回按钮和右边的操作按钮：同一种反馈
      final a = inkOf(tester, back);
      final b = inkOf(tester, find.byTooltip('添加'));
      expect(a.customBorder, b.customBorder);
      expect(a.overlayColor!.resolve({WidgetState.pressed}), b.overlayColor!.resolve({WidgetState.pressed}));
      final outside = [Offset(round.center.dx, round.top - 5), Offset(round.center.dx, round.bottom + 5)];
      final before = await pixelsAt(tester, outside);
      final g = await hold(tester, back);
      expect(await pixelsAt(tester, outside), before);
      await shot(tester, 'tb-9-press-back-$suffix');
      await release(tester, g);
      // 点一下真的返回
      await tester.tap(back);
      await tester.pumpAndSettle();
      expect(find.text('进去'), findsOneWidget);
    });
  }

  testWidgets('圆按钮不跟着外面给的高度被拉长（波纹变长条的原因）', (tester) async {
    usePhoneViewport(tester);
    late TestEnv env;
    await tester.runAsync(() async => env = await TestEnv.create());
    addTearDown(() => env.dispose());
    // 外面硬给 44×64（以前顶栏就是这样给左按钮的）
    await tester.pumpWidget(
      appFor(
        env,
        Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 44,
              height: 64,
              child: RoundIconButton(icon: Icons.drag_handle_rounded, tooltip: '按钮', onPressed: () {}),
            ),
          ),
        ),
      ),
    );
    final ink = inkRect(tester, find.byTooltip('按钮'));
    expect(ink, const Rect.fromLTWH(0, 10, 44, 44));
    expect(tester.getRect(find.descendant(of: find.byType(RoundIconButton), matching: find.byType(DecoratedBox)).first), ink);
  });
}
