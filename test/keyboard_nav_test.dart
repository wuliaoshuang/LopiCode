// 软键盘与底部导航（霜霜真机反馈第 4 条，390×844）：导航钉在屏幕最底部，键盘盖在它上面；内容底边跟着键盘上沿走。
//   LOPI_SHOTS=1 flutter test test/keyboard_nav_test.dart   # 同时写截图到 docs/screenshots/kb-*.png
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/build/build_screen.dart';
import 'package:lopicode/core/project_store.dart';
import 'package:lopicode/core/templates.dart';
import 'package:lopicode/project_session.dart';
import 'package:lopicode/ui/builder_hub_screen.dart';
import 'package:lopicode/ui/chat_screen.dart';
import 'package:lopicode/ui/chrome.dart';
import 'package:lopicode/ui/code_editor.dart';
import 'package:lopicode/ui/files_tab.dart';
import 'package:lopicode/ui/pinned_nav_layout.dart';
import 'package:lopicode/ui/preview_tab.dart';
import 'package:lopicode/ui/project_shell.dart';
import 'package:lopicode/ui/push_drawer.dart';
import 'package:lopicode/ui/shell.dart';
import 'package:lopicode/ui/terminal_tab.dart';
import 'package:material_ui/material_ui.dart';

import 'support/harness.dart';

final bool writeShots = Platform.environment['LOPI_SHOTS'] == '1';
const double kKeyboard = 320;
const double kNav = IconBottomNav.kHeight;

Future<(TestEnv, Project, ProjectSession)> openProject(WidgetTester tester) async {
  usePhoneViewport(tester);
  late TestEnv env;
  late Project project;
  late ProjectSession session;
  await tester.runAsync(() async {
    env = await TestEnv.create();
    project = await env.services.projects.create('我的小站', ProjectTemplate.lowcode);
    session = ProjectSession(env.services, project);
    await session.loadChat();
    await Future<void>.delayed(const Duration(milliseconds: 150));
  });
  addTearDown(() async {
    session.dispose();
    await env.dispose();
  });
  return (env, project, session);
}

/// 模拟系统：键盘高 [inset]（从屏幕底算起），底部安全区 [safe]。
/// 真机上键盘升起时系统给的 padding.bottom = max(安全区 − 键盘, 0)，viewPadding 不变。
void setKeyboard(WidgetTester tester, double inset, {double safe = 0}) {
  tester.view.viewInsets = FakeViewPadding(bottom: inset);
  tester.view.viewPadding = FakeViewPadding(bottom: safe);
  tester.view.padding = FakeViewPadding(bottom: (safe - inset).clamp(0, safe));
}

void resetKeyboardLater(WidgetTester tester) {
  addTearDown(tester.view.resetViewInsets);
  addTearDown(tester.view.resetViewPadding);
  addTearDown(tester.view.resetPadding);
}

/// 键盘升起再收起的逐帧高度（含比导航矮的那几帧）。
const List<double> kFrames = [0, 8, 30, 63, 64, 65, 90, 180, 300, 320, 310, 200, 100, 66, 64, 40, 12, 0];

void main() {
  setUpAll(() => PreviewTab.debugViewBuilder = (uri) => const ColoredBox(color: Colors.white));
  tearDownAll(() => PreviewTab.debugViewBuilder = null);

  Future<void> tapNav(WidgetTester tester, ShellDest d) async {
    await tester.tap(find.byKey(ValueKey('nav-${ShellDest.bottom.indexOf(d)}')));
    await settle(tester, rounds: 8);
  }

  final nav = find.byType(IconBottomNav);
  final input = find.byKey(const ValueKey('chat-input'));

  test('让开的高度 = max(键盘, 导航 + 底部安全区)：安全区不重复算也不漏', () {
    double f(double inset, double safe) => PinnedNavLayout.bottomObstruction(
      MediaQueryData(
        viewInsets: EdgeInsets.only(bottom: inset),
        viewPadding: EdgeInsets.only(bottom: safe),
        padding: EdgeInsets.only(bottom: (safe - inset).clamp(0, safe)),
      ),
      kNav,
    );
    expect(f(0, 0), 64);
    expect(f(0, 34), 98);
    expect(f(50, 34), 98, reason: '键盘还没高过导航：内容不动');
    expect(f(98, 34), 98);
    expect(f(320, 34), 320, reason: '键盘高度已含安全区，不再相加');
    expect(f(320, 0), 320);
  });

  for (final safe in [0.0, 34.0]) {
    testWidgets('聊天页（底部安全区 $safe）：键盘升起到收起的每一帧，导航都在原位；输入框贴着键盘上沿，收起后回到导航上方', (tester) async {
      final (env, project, session) = await openProject(tester);
      resetKeyboardLater(tester);
      setKeyboard(tester, 0, safe: safe);
      await tester.pumpWidget(appFor(env, ProjectShell(project: project, session: session)));
      await settle(tester);

      final navBefore = tester.getRect(nav);
      final item0 = tester.getRect(find.byKey(const ValueKey('nav-0')));
      expect(navBefore, Rect.fromLTRB(0, 844 - kNav - safe, 390, 844), reason: '导航在屏幕最底部，含底部安全区');
      expect(item0.bottom, 844 - safe, reason: '图标在安全区上方');
      final gap = navBefore.top - tester.getRect(input).bottom;
      expect(gap, greaterThanOrEqualTo(0), reason: '没有键盘时输入框在导航上方');

      for (final k in kFrames) {
        setKeyboard(tester, k, safe: safe);
        await tester.pump();
        expect(nav, findsOneWidget, reason: '键盘 $k：导航一直在树里');
        expect(tester.getRect(nav), navBefore, reason: '键盘 $k：导航位置和高度不变');
        expect(tester.getRect(find.byKey(const ValueKey('nav-0'))), item0, reason: '键盘 $k：导航里的图标也不动');
        final contentBottom = 844 - (k > kNav + safe ? k : kNav + safe);
        expect(tester.getRect(find.byType(ChatScreen)).bottom, contentBottom, reason: '键盘 $k：内容底边 = 键盘上沿和导航上沿里靠上的那个');
        expect(tester.getRect(input).bottom, closeTo(contentBottom - gap, 0.01), reason: '键盘 $k：输入框底边紧贴内容底边（原有间距不变），没有空白也没有重叠');
        expect(tester.takeException(), isNull);
      }
      // 收起后的同一帧：和一开始完全一样
      expect(tester.getRect(input).bottom, navBefore.top - gap, reason: '键盘收起后输入框回到导航上方');

      // 键盘完全升起时
      setKeyboard(tester, kKeyboard, safe: safe);
      await tester.pump();
      expect(tester.getRect(input).bottom, 844 - kKeyboard - gap, reason: '输入框底边紧贴键盘上沿');
      expect(tester.getRect(nav), navBefore);
    });

    testWidgets('五个页面（底部安全区 $safe）：键盘升起时导航都不动，页面内容都缩到键盘上方；终端按键行、文件编辑器不被盖住', (tester) async {
      final (env, project, session) = await openProject(tester);
      resetKeyboardLater(tester);
      setKeyboard(tester, 0, safe: safe);
      await tester.pumpWidget(appFor(env, ProjectShell(project: project, session: session)));
      await settle(tester);
      final navBefore = tester.getRect(nav);
      const keyboardTop = 844 - kKeyboard;

      Future<void> check(ShellDest d, Finder page, {Finder? inputArea}) async {
        setKeyboard(tester, 0, safe: safe);
        await tester.pump();
        await tapNav(tester, d);
        expect(tester.getRect(nav), navBefore, reason: '${d.label}：切过来导航不动');
        expect(tester.getRect(page).bottom, navBefore.top, reason: '${d.label}：没有键盘时内容到导航上沿');
        if (inputArea != null) expect(inputArea, findsOneWidget, reason: '${d.label}：要检查的输入处应该在');
        for (final k in kFrames) {
          setKeyboard(tester, k, safe: safe);
          await tester.pump();
          expect(tester.getRect(nav), navBefore, reason: '${d.label} 键盘 $k：导航不动');
          expect(tester.getRect(page).bottom, 844 - (k > kNav + safe ? k : kNav + safe), reason: '${d.label} 键盘 $k：内容底边跟着键盘');
        }
        setKeyboard(tester, kKeyboard, safe: safe);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.getRect(nav), navBefore, reason: '${d.label}：键盘升起导航不动');
        expect(tester.getRect(page).bottom, keyboardTop, reason: '${d.label}：内容缩到键盘上沿');
        if (inputArea != null) {
          final r = tester.getRect(inputArea);
          expect(r.bottom, lessThanOrEqualTo(keyboardTop), reason: '${d.label}：输入处没被键盘盖住');
          expect(r.height, greaterThan(0));
        }
        expect(tester.takeException(), isNull, reason: '${d.label}：键盘升起不能溢出');
      }

      await check(ShellDest.terminal, find.byType(TerminalTab), inputArea: find.byKey(const Key('terminal-keys')));
      expect(tester.getRect(find.byKey(const Key('terminal-keys'))).bottom, keyboardTop, reason: '终端按键行贴着键盘上沿');

      // 文件页：先打开一个文件进编辑器
      setKeyboard(tester, 0, safe: safe);
      await tester.pump();
      await tapNav(tester, ShellDest.files);
      await tester.tap(find.text('index.html'));
      await settle(tester, rounds: 6);
      await check(ShellDest.files, find.byType(FilesTab), inputArea: find.byType(LopiCodeEditor));
      expect(tester.getRect(find.byType(LopiCodeEditor)).height, greaterThan(200), reason: '编辑器在键盘上方还留着够用的高度');

      await check(ShellDest.builder, find.byType(BuilderHubScreen));
      await check(ShellDest.apk, find.byType(BuildScreen));
      await check(ShellDest.chat, find.byType(ChatScreen), inputArea: input);
    });
  }

  testWidgets('侧边栏推开时导航跟着主界面一起右移；提示条没键盘时在导航上方、有键盘时在键盘上方', (tester) async {
    final (env, project, session) = await openProject(tester);
    resetKeyboardLater(tester);
    await tester.pumpWidget(appFor(env, ProjectShell(project: project, session: session)));
    await settle(tester);
    final navBefore = tester.getRect(nav);

    ScaffoldMessenger.of(tester.element(find.byType(ChatScreen))).showSnackBar(const SnackBar(content: Text('提示一下'), duration: Duration(days: 1)));
    await tester.pumpAndSettle();
    expect(tester.getRect(find.byType(SnackBar)).bottom, lessThanOrEqualTo(navBefore.top), reason: '提示条不盖导航');
    setKeyboard(tester, kKeyboard);
    await tester.pumpAndSettle();
    expect(tester.getRect(find.byType(SnackBar)).bottom, lessThanOrEqualTo(844 - kKeyboard), reason: '提示条不被键盘盖住');
    expect(find.byType(SnackBar), findsOneWidget, reason: '只有外壳这一层显示提示条');
    ScaffoldMessenger.of(tester.element(find.byType(ChatScreen))).removeCurrentSnackBar();
    setKeyboard(tester, 0);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('打开侧边栏').hitTestable());
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await settle(tester, rounds: 3);
    expect(find.byType(AppDrawer), findsOneWidget);
    final moved = tester.getRect(nav);
    expect(moved.left, greaterThan(100), reason: '导航跟着主界面被推到右边');
    expect(moved.left, tester.getRect(find.byType(ChatScreen)).left, reason: '导航和页面一起走');
    expect(find.byType(PushDrawer), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('从页面里弹出的底部面板在外壳上面，看到的是真实键盘高度：里面的输入框照常避让', (tester) async {
    usePhoneViewport(tester);
    resetKeyboardLater(tester);
    await tester.pumpWidget(
      MaterialApp(
        home: PinnedNavLayout(
          navHeight: kNav,
          nav: const ColoredBox(
            color: Colors.blue,
            child: SafeArea(top: false, child: SizedBox(height: kNav)),
          ),
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  builder: (context) => Padding(
                    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
                    child: const TextField(key: Key('sheet-field')),
                  ),
                ),
                child: const Text('打开面板'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开面板'));
    await tester.pumpAndSettle();
    expect(tester.getRect(find.byKey(const Key('sheet-field'))).bottom, 844, reason: '没有键盘：面板贴底，盖在导航上面');
    setKeyboard(tester, kKeyboard);
    await tester.pumpAndSettle();
    expect(tester.getRect(find.byKey(const Key('sheet-field'))).bottom, 844 - kKeyboard, reason: '面板里的输入框正好让开键盘，不多让一个导航的高度');
    expect(tester.takeException(), isNull);
  });

  // 截图：键盘用一块半透明的灰色示意（真机上键盘是不透明的，这里留一点透明度好看出导航还在原位）。
  group('截图', () {
    var fontsLoaded = false;
    setUpAll(() async => fontsLoaded = await loadRealFonts());
    final key = GlobalKey();

    Future<void> shot(WidgetTester tester, String name) async {
      expect(tester.takeException(), isNull, reason: '$name 渲染时出了异常');
      if (!writeShots || !fontsLoaded) return;
      final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(key));
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 2);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        final file = File('docs/screenshots/$name.png');
        file.parent.createSync(recursive: true);
        file.writeAsBytesSync(data!.buffer.asUint8List());
      });
    }

    for (final (mode, suffix) in [(ThemeMode.light, 'light'), (ThemeMode.dark, 'dark')]) {
      testWidgets('聊天页键盘收起 / 升起（$suffix）', (tester) async {
        final (env, project, session) = await openProject(tester);
        resetKeyboardLater(tester);
        final keyboard = ValueNotifier<double>(0);
        addTearDown(keyboard.dispose);
        await tester.pumpWidget(
          RepaintBoundary(
            key: key,
            child: Stack(
              textDirection: TextDirection.ltr,
              children: [
                appFor(
                  env,
                  ProjectShell(project: project, session: session),
                  mode: mode,
                  font: fontsLoaded ? kTestFont : null,
                ),
                ValueListenableBuilder<double>(
                  valueListenable: keyboard,
                  builder: (context, h, _) => Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    height: h,
                    child: IgnorePointer(
                      child: ColoredBox(
                        color: mode == ThemeMode.dark ? const Color(0xE0303236) : const Color(0xE0D5D8DE),
                        child: Center(
                          child: Text(
                            '（示意：软键盘）',
                            textDirection: TextDirection.ltr,
                            style: TextStyle(fontFamily: kTestFont, fontSize: 14, color: mode == ThemeMode.dark ? const Color(0xFFB8BCC4) : const Color(0xFF5A606B)),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
        await settle(tester);
        await shot(tester, 'kb-4-chat-keyboard-down-$suffix');
        final navBefore = tester.getRect(nav);

        setKeyboard(tester, kKeyboard);
        keyboard.value = kKeyboard;
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.getRect(nav), navBefore);
        await shot(tester, 'kb-4-chat-keyboard-up-$suffix');

        // 升到一半（键盘还没高过导航）：内容不动，键盘盖住导航下半截
        setKeyboard(tester, 40);
        keyboard.value = 40;
        await tester.pump();
        expect(tester.getRect(nav), navBefore);
        await shot(tester, 'kb-4-chat-keyboard-rising-$suffix');
      });
    }
  });
}
