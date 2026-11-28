// 平板适配（2026-11-28 霜霜：“适配平板”）：窗口宽度三档下，外壳、对话、设置、文件、搭建、打包、弹层的排法。
// 尺寸：600×960（刚够“中”档）、800×1280（平板竖屏）、1280×800（平板横屏）。手机 390×844 的样子由原有测试守着。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/core/project_store.dart';
import 'package:lopicode/core/templates.dart';
import 'package:lopicode/project_session.dart';
import 'package:lopicode/theme/breakpoints.dart';
import 'package:lopicode/ui/chrome.dart';
import 'package:lopicode/ui/nav_rail.dart';
import 'package:lopicode/ui/preview_tab.dart';
import 'package:lopicode/ui/project_shell.dart';
import 'package:lopicode/ui/settings_screen.dart';
import 'package:lopicode/ui/settings_split.dart';
import 'package:lopicode/ui/shell.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;

import 'support/harness.dart';
import 'support/lowcode_builder.dart';

const _dir = '../preview/tablet';

Future<(TestEnv, Project, ProjectSession)> _open(WidgetTester tester, Size size, {ProjectTemplate template = ProjectTemplate.lowcode}) async {
  useViewport(tester, size);
  late TestEnv e;
  late Project project;
  late ProjectSession session;
  await tester.runAsync(() async {
    e = await TestEnv.create();
    project = await e.services.projects.create('我的小站', template);
    session = ProjectSession(e.services, project);
    await session.loadChat();
    await Future<void>.delayed(const Duration(milliseconds: 150));
  });
  addTearDown(() async {
    session.dispose();
    await e.dispose();
  });
  return (e, project, session);
}

String _name(Size s) => '${s.width.toInt()}x${s.height.toInt()}';

Future<void> _nav(WidgetTester tester, ShellDest d) async {
  await tester.tap(find.byKey(ValueKey('nav-${ShellDest.bottom.indexOf(d)}')));
  await settle(tester, rounds: 8);
}

void _noError(WidgetTester tester, String where) => expect(tester.takeException(), isNull, reason: '$where：渲染出了异常（多半是排不下）');

void main() {
  setUpAll(() async {
    lbFontsLoaded = await loadRealFonts();
    PreviewTab.debugViewBuilder = (uri) => const ColoredBox(color: Colors.white);
  });
  tearDownAll(() => PreviewTab.debugViewBuilder = null);

  test('宽度分档：窄 ＜600、中 600–839、宽 ≥840', () {
    expect(Breakpoints.forWidth(390), WidthClass.compact);
    expect(Breakpoints.forWidth(599.9), WidthClass.compact);
    expect(Breakpoints.forWidth(600), WidthClass.medium);
    expect(Breakpoints.forWidth(839.9), WidthClass.medium);
    expect(Breakpoints.forWidth(840), WidthClass.expanded);
    expect(Breakpoints.forWidth(1280), WidthClass.expanded);
    expect(ContentWidth.marginFor(390), 0);
    expect(ContentWidth.marginFor(720), 0);
    expect(ContentWidth.marginFor(1000), 140);
  });

  for (final size in [kTabletSmall, kTabletPortrait, kTabletLandscape]) {
    final tag = _name(size);
    final expanded = Breakpoints.forWidth(size.width).isExpanded;

    testWidgets('外壳 $tag：导航在左边竖排，五个页面都进得去、不溢出', (tester) async {
      final (env, project, session) = await _open(tester, size);
      await tester.pumpWidget(
        appFor(
          env,
          ProjectShell(project: project, session: session),
          font: lbFontsLoaded ? kTestFont : null,
        ),
      );
      await settle(tester);
      _noError(tester, '对话页');
      expect(find.byType(IconBottomNav), findsNothing);
      final rail = tester.getRect(find.byType(IconNavRail));
      expect(rail.left, 0);
      expect(rail.width, Breakpoints.rail);
      expect(rail.bottom, size.height);
      for (final label in ['聊天', '文件', '终端', '搭建', '打包']) {
        expect(find.descendant(of: find.byType(IconNavRail), matching: find.text(label)), findsOneWidget);
      }
      // 对话页：输入栏限宽；宽屏侧边栏常驻、顶栏没有汉堡按钮；中屏还是抽屉。
      final input = tester.getRect(find.byKey(const ValueKey('chat-input')));
      expect(input.width, lessThanOrEqualTo(Breakpoints.reading));
      expect(input.left, greaterThanOrEqualTo(Breakpoints.rail));
      if (expanded) {
        expect(find.byType(AppDrawer), findsOneWidget);
        expect(tester.getRect(find.byKey(const ValueKey('shell-side'))).left, Breakpoints.rail);
        expect(find.byTooltip('打开侧边栏').hitTestable(), findsNothing);
        expect(input.left, greaterThanOrEqualTo(Breakpoints.rail + Breakpoints.side));
      } else {
        expect(find.byType(AppDrawer), findsNothing);
        expect(find.byTooltip('打开侧边栏').hitTestable(), findsOneWidget);
      }
      await lbShot(tester, _dir, 'shell-chat-$tag');

      // 文件：宽屏两栏（文件树常驻），别的档一次看一样。
      await _nav(tester, ShellDest.files);
      _noError(tester, '文件页');
      expect(find.text('index.html'), findsWidgets);
      expect(find.byKey(const ValueKey('files-side')), expanded ? findsOneWidget : findsNothing);
      if (expanded) expect(find.text('还没打开文件'), findsOneWidget);
      await tester.tap(find.text('index.html').first);
      await settle(tester, rounds: 8);
      _noError(tester, '编辑器');
      if (expanded) {
        expect(find.byKey(const ValueKey('files-side')), findsOneWidget, reason: '开了文件，文件树还在左边');
        expect(find.byTooltip('文件列表'), findsNothing);
        expect(tester.getRect(find.byKey(const ValueKey('files-side'))).width, Breakpoints.side);
      } else {
        expect(find.byTooltip('文件列表'), findsOneWidget);
      }
      await lbShot(tester, _dir, 'files-editor-$tag');

      await _nav(tester, ShellDest.terminal);
      _noError(tester, '终端页');
      expect(find.byTooltip('新建会话'), findsOneWidget);
      await lbShot(tester, _dir, 'terminal-$tag');

      await _nav(tester, ShellDest.builder);
      _noError(tester, '搭建页');
      expect(find.byTooltip('图层'), findsOneWidget);
      await lbShot(tester, _dir, 'builder-$tag');

      await _nav(tester, ShellDest.apk);
      _noError(tester, '打包页');
      expect(find.textContaining('就在这台手机上打包'), findsOneWidget);
      await lbShot(tester, _dir, 'pack-$tag');

      // 回对话页：宽屏时不在对话页，侧边栏不常驻（汉堡按钮回来）。
      if (expanded) {
        expect(find.byKey(const ValueKey('shell-side')), findsNothing);
        expect(find.byTooltip('打开侧边栏').hitTestable(), findsOneWidget);
      }
      await _nav(tester, ShellDest.chat);
      _noError(tester, '回到对话页');
    });

    testWidgets('对话 $tag：底部弹层限宽居中，不横向拉满', (tester) async {
      final (env, project, session) = await _open(tester, size);
      await tester.pumpWidget(
        appFor(
          env,
          ProjectShell(project: project, session: session),
          font: lbFontsLoaded ? kTestFont : null,
        ),
      );
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('plus-button')));
      await tester.pumpAndSettle();
      _noError(tester, '加号面板');
      // BottomSheet 这个控件自己占满一行，限宽的是它里面那块面板
      final sheet = tester.getRect(find.descendant(of: find.byType(BottomSheet), matching: find.byType(Material)).first);
      expect(sheet.width, lessThanOrEqualTo(Breakpoints.sheet));
      expect(sheet.center.dx, closeTo(size.width / 2, 1));
      await lbShot(tester, _dir, 'chat-plus-sheet-$tag');
    });

    testWidgets('设置 $tag：${expanded ? '左清单右详情两栏' : '单栏限宽居中'}', (tester) async {
      useViewport(tester, size);
      late TestEnv env;
      await tester.runAsync(() async => env = await TestEnv.create());
      addTearDown(env.dispose);
      await tester.pumpWidget(appFor(env, const SettingsScreen(), font: lbFontsLoaded ? kTestFont : null));
      await settle(tester);
      _noError(tester, '设置');
      final row = find.byKey(const Key('settings-chat'));
      await tester.scrollUntilVisible(
        row,
        200,
        scrollable: find.descendant(of: find.byKey(const Key('settings-list')), matching: find.byType(Scrollable)).first,
      );
      await tester.ensureVisible(row);
      await tester.pumpAndSettle();
      if (expanded) {
        expect(tester.getRect(find.byKey(const ValueKey('settings-master'))).width, SettingsSplit.kMasterWidth);
        expect(find.text('在左边选一项'), findsOneWidget);
        await lbShot(tester, _dir, 'settings-empty-$tag');
        await tester.tap(row);
        await tester.pumpAndSettle();
        _noError(tester, '设置 › 对话显示');
        // 清单还在左边，点开的页在右边那一栏里
        expect(find.byKey(const Key('settings-chat')), findsOneWidget);
        final detail = tester.getRect(find.byKey(const ValueKey('settings-detail')));
        expect(detail.left, greaterThan(SettingsSplit.kMasterWidth));
        final title = find.descendant(of: find.byKey(const ValueKey('settings-detail')), matching: find.text('对话显示'));
        expect(title, findsWidgets);
        await lbShot(tester, _dir, 'settings-detail-$tag');
        // 再点左边另一项：右边整栏换掉，不是叠上去
        final other = find.byKey(const Key('settings-third-party'));
        await tester.scrollUntilVisible(
          other,
          200,
          scrollable: find.descendant(of: find.byKey(const Key('settings-list')), matching: find.byType(Scrollable)).first,
        );
        await tester.ensureVisible(other);
        await tester.pumpAndSettle();
        await tester.tap(other);
        await tester.pumpAndSettle();
        _noError(tester, '设置 › 第三方声明');
        expect(find.descendant(of: find.byKey(const ValueKey('settings-detail')), matching: find.text('对话显示')), findsNothing);
        // 返回键：先退右边的那一页，回到“在左边选一项”
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.text('在左边选一项'), findsOneWidget);
        expect(find.byKey(const Key('settings-list')), findsOneWidget);
      } else {
        expect(find.byKey(const ValueKey('settings-master')), findsNothing);
        final list = tester.getRect(find.byKey(const Key('settings-list')));
        expect(list.width, lessThanOrEqualTo(Breakpoints.page));
        expect(list.center.dx, closeTo(size.width / 2, 1));
        await lbShot(tester, _dir, 'settings-$tag');
        await tester.tap(row);
        await tester.pumpAndSettle();
        _noError(tester, '设置 › 对话显示');
        expect(find.byKey(const Key('settings-chat')), findsNothing, reason: '中屏是整页进');
        await lbShot(tester, _dir, 'settings-detail-$tag');
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('settings-chat')), findsOneWidget);
      }
    });
  }

  testWidgets('拖窗口：390 → 1280 → 390，页面不重建、草稿和打开的文件都在，不报错', (tester) async {
    final (env, project, session) = await _open(tester, kPhone, template: ProjectTemplate.web);
    await tester.pumpWidget(appFor(env, ProjectShell(project: project, session: session)));
    await settle(tester);
    expect(find.byType(IconBottomNav), findsOneWidget);
    final field = find.descendant(of: find.byKey(const ValueKey('chat-input')), matching: find.byType(EditableText));
    await tester.enterText(field, '写到一半的话');
    await tester.pump();
    // 去文件页开一个文件
    await _nav(tester, ShellDest.files);
    await tester.tap(find.text('index.html').first);
    await settle(tester, rounds: 8);
    expect(find.byTooltip('文件列表'), findsOneWidget);
    final editorState = tester.state(find.byType(ProjectShell));

    for (final w in [600.0, 800.0, 1000.0, 1280.0]) {
      useViewport(tester, Size(w, 844));
      await settle(tester, rounds: 3);
      _noError(tester, '宽度 $w');
      expect(find.byType(IconNavRail), findsOneWidget);
      expect(find.byType(IconBottomNav), findsNothing);
    }
    // 宽屏：文件树常驻、文件还开着
    expect(find.byKey(const ValueKey('files-side')), findsOneWidget);
    expect(find.byTooltip('文件列表'), findsNothing);
    expect(find.textContaining('index.html'), findsWidgets);
    expect(identical(tester.state(find.byType(ProjectShell)), editorState), isTrue);
    await _nav(tester, ShellDest.chat);
    expect(tester.widget<EditableText>(field).controller.text, '写到一半的话', reason: '拉宽以后草稿还在');
    expect(find.byType(AppDrawer), findsOneWidget, reason: '宽屏的对话页侧边栏常驻');

    for (final w in [1000.0, 700.0, 390.0]) {
      useViewport(tester, Size(w, 844));
      await settle(tester, rounds: 3);
      _noError(tester, '宽度 $w');
    }
    expect(find.byType(IconBottomNav), findsOneWidget);
    expect(find.byType(IconNavRail), findsNothing);
    expect(find.byType(AppDrawer), findsNothing);
    expect(tester.widget<EditableText>(field).controller.text, '写到一半的话', reason: '拉回手机宽度草稿还在');
    expect(tester.getRect(find.byType(IconBottomNav)).bottom, 844);
    await _nav(tester, ShellDest.files);
    expect(find.byTooltip('文件列表'), findsOneWidget, reason: '拉回手机宽度，刚才开着的文件还开着');
    expect(File(p.join(project.dir, 'index.html')).existsSync(), isTrue);
  });

  testWidgets('设置：宽屏在右边点开一项后把窗口拉窄，那一页接着显示、返回回到清单；再拉宽还是两栏', (tester) async {
    useViewport(tester, kTabletLandscape);
    late TestEnv env;
    await tester.runAsync(() async => env = await TestEnv.create());
    addTearDown(env.dispose);
    await tester.pumpWidget(appFor(env, const SettingsScreen()));
    await settle(tester);
    final row = find.byKey(const Key('settings-third-party'));
    await tester.scrollUntilVisible(
      row,
      200,
      scrollable: find.descendant(of: find.byKey(const Key('settings-list')), matching: find.byType(Scrollable)).first,
    );
    await tester.ensureVisible(row);
    await tester.pumpAndSettle();
    await tester.tap(row);
    await tester.pumpAndSettle();
    expect(find.text('第三方声明'), findsWidgets);

    useViewport(tester, kTabletPortrait); // 转成竖屏：中档
    await tester.pumpAndSettle();
    _noError(tester, '转竖屏');
    expect(find.byKey(const ValueKey('settings-master')), findsNothing);
    expect(find.byKey(const Key('settings-third-party')), findsNothing, reason: '清单让位给刚才点开的那一页');
    expect(find.text('第三方声明'), findsWidgets);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('settings-list')), findsOneWidget);

    useViewport(tester, kTabletLandscape);
    await tester.pumpAndSettle();
    _noError(tester, '转回横屏');
    expect(find.byKey(const ValueKey('settings-master')), findsOneWidget);
    expect(find.text('在左边选一项'), findsOneWidget);
  });
}
