// 底部导航、侧边栏和对话输入框的行为测试（390×844）。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/core/project_store.dart';
import 'package:lopicode/core/templates.dart';
import 'package:lopicode/project_session.dart';
import 'package:lopicode/lowcode/builder_screen.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/chrome.dart';
import 'package:lopicode/ui/home_gate.dart';
import 'package:lopicode/ui/preview_tab.dart';
import 'package:lopicode/ui/project_shell.dart';
import 'package:lopicode/ui/push_drawer.dart';
import 'package:lopicode/ui/shell.dart';
import 'package:lopicode/ui/terminal_tab.dart';
import 'package:material_ui/material_ui.dart';

import 'support/harness.dart';

Future<(TestEnv, Project, ProjectSession)> openProject(WidgetTester tester, {TestEnv? env, ProjectTemplate template = ProjectTemplate.lowcode}) async {
  usePhoneViewport(tester);
  late TestEnv e;
  late Project project;
  late ProjectSession session;
  await tester.runAsync(() async {
    e = env ?? await TestEnv.create();
    project = await e.services.projects.create('我的小站', template);
    session = ProjectSession(e.services, project);
        await session.loadChat();
    await Future<void>.delayed(const Duration(milliseconds: 150));
  });
  addTearDown(() async {
    session.dispose();
    e.dispose();
  });
  return (e, project, session);
}

/// 右上“···”菜单里的“新对话”。
Future<void> newChat(WidgetTester tester) async {
  await tester.tap(find.byTooltip('更多').hitTestable());
  await tester.pumpAndSettle();
  await tester.tap(find.text('新对话').last);
  await tester.pumpAndSettle();
}

Future<void> openDrawer(WidgetTester tester) async {
  // 每个页面都有自己的汉堡按钮；IndexedStack 里只有当前页的那个能点到。
  await tester.tap(find.byTooltip('打开侧边栏').hitTestable());
  await drawerSettle(tester);
  expect(find.byType(AppDrawer), findsOneWidget);
}

/// 等侧边栏的开 / 关动画走完。
Future<void> drawerSettle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  await settle(tester, rounds: 3);
}

Future<void> closeDrawer(WidgetTester tester) async {
  await tester.tapAt(const Offset(370, 400)); // 点遮罩
  await drawerSettle(tester);
  expect(find.byType(AppDrawer), findsNothing);
}

/// 侧边栏里这一项是不是高亮的（强调色浅底）。
bool highlighted(WidgetTester tester, String label) {
  final item = find.descendant(of: find.byType(AppDrawer), matching: find.text(label));
  expect(item, findsOneWidget, reason: '侧边栏里应该有“$label”');
  final material = tester.widget<Material>(find.ancestor(of: item, matching: find.byType(Material)).first);
  final colors = tester.element(item).colors;
  return material.color == colors.accentSoft;
}

void main() {
  setUpAll(() => PreviewTab.debugViewBuilder = (uri) => const ColoredBox(color: Colors.white));
  tearDownAll(() => PreviewTab.debugViewBuilder = null);

  /// 底部导航第 i 项是不是选中（实心）的。
  bool navSelected(WidgetTester tester, int i) {
    final sem = tester.widget<Semantics>(find.byKey(ValueKey('nav-$i')));
    return sem.properties.selected ?? false;
  }

  Future<void> tapNav(WidgetTester tester, ShellDest d) async {
    await tester.tap(find.byKey(ValueKey('nav-${ShellDest.bottom.indexOf(d)}')));
    await settle(tester, rounds: 8);
  }

  final marks = <ShellDest, Finder>{
    ShellDest.chat: find.byTooltip('发送'),
    ShellDest.files: find.text('index.html'),
    ShellDest.terminal: find.byTooltip('新建会话'),
    ShellDest.preview: find.text('手机'),
    ShellDest.builder: find.byTooltip('图层'),
    ShellDest.apk: find.textContaining('手机上跑不了 Android SDK 和 Gradle'),
    ShellDest.runtime: find.byKey(const Key('runtime-status')),
  };

  testWidgets('底部导航五项只有图标：点哪个去哪个页，选中的那个是实心', (tester) async {
    usePhoneViewport(tester);
    final (env, project, session) = await openProject(tester);
    await tester.pumpWidget(appFor(env, ProjectShell(project: project, session: session)));
    await settle(tester);

    final nav = find.byType(IconBottomNav);
    expect(nav, findsOneWidget);
    expect(ShellDest.bottom.map((d) => d.label).toList(), ['Agent 聊天', '文件', '终端', '低代码', '打包']);
    expect(find.descendant(of: nav, matching: find.byType(Text)), findsNothing, reason: '底部导航只有图标，没有文字');
    // 贴着屏幕底边
    expect(tester.getRect(nav).bottom, 844);
    // 进项目先看到聊天页
    expect(marks[ShellDest.chat]!.hitTestable(), findsOneWidget);
    expect(navSelected(tester, 0), isTrue);

    for (final d in [...ShellDest.bottom.skip(1), ShellDest.chat]) {
      await tapNav(tester, d);
      expect(marks[d]!.hitTestable(), findsWidgets, reason: '应该到了“${d.label}”页');
      expect(find.byTooltip('打开侧边栏').hitTestable(), findsOneWidget, reason: '“${d.label}”页也要有汉堡按钮');
      for (var i = 0; i < 5; i++) {
        expect(navSelected(tester, i), i == ShellDest.bottom.indexOf(d), reason: '在“${d.label}”页时第 $i 项的选中状态');
      }
      // 页面内容不能伸到导航下面去
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('键盘弹出时底部导航不被顶起来：导航原地不动，只有输入框贴着键盘', (tester) async {
    usePhoneViewport(tester);
    final (env, project, session) = await openProject(tester);
    await tester.pumpWidget(appFor(env, ProjectShell(project: project, session: session)));
    await settle(tester);

    final nav = find.byType(IconBottomNav);
    final input = find.byKey(const ValueKey('chat-input'));
    final navBefore = tester.getRect(nav);
    expect(navBefore.bottom, 844);
    expect(tester.getRect(input).bottom, lessThanOrEqualTo(navBefore.top), reason: '没有键盘时输入框在导航上方');

    // 软键盘弹出：占掉屏幕下面 320
    const keyboard = 320.0;
    tester.view.viewInsets = const FakeViewPadding(bottom: keyboard);
    addTearDown(tester.view.resetViewInsets);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final keyboardTop = 844 - keyboard;
    expect(tester.getRect(nav), navBefore, reason: '导航不能被键盘顶起来');
    expect(tester.getRect(nav).top, greaterThanOrEqualTo(keyboardTop), reason: '导航整个在键盘后面');
    final inputRect = tester.getRect(input);
    expect(inputRect.bottom, lessThanOrEqualTo(keyboardTop), reason: '输入框在键盘上方');
    expect(inputRect.bottom, greaterThan(keyboardTop - 16), reason: '输入框贴着键盘，中间没有夹着导航');
    expect(tester.takeException(), isNull);

    // 终端页：按键行贴着键盘，导航同样不动
    tester.view.resetViewInsets();
    await tester.pump();
    await tapNav(tester, ShellDest.terminal);
    final keysBefore = tester.getRect(find.byType(TerminalTab)).bottom;
    expect(keysBefore, lessThanOrEqualTo(navBefore.top), reason: '终端页没有被导航挡住');
    tester.view.viewInsets = const FakeViewPadding(bottom: keyboard);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.getRect(nav), navBefore);
    expect(tester.getRect(find.byType(TerminalTab)).bottom, keyboardTop, reason: '终端页缩到键盘上方');
    expect(tester.takeException(), isNull);
  });

  testWidgets('低代码页：画布和组件栏都在底部导航上方', (tester) async {
    usePhoneViewport(tester);
    final (env, project, session) = await openProject(tester);
    await tester.pumpWidget(appFor(env, ProjectShell(project: project, session: session, initial: ShellDest.builder)));
    await settle(tester, rounds: 8);
    final navTop = tester.getRect(find.byType(IconBottomNav)).top;
    expect(tester.getRect(find.byType(BuilderScreen)).bottom, navTop);
    expect(tester.takeException(), isNull);
  });

  testWidgets('侧边栏只放底部导航里没有的：工作区切换、预览、运行环境、对话、设置', (tester) async {
    final (env, project, session) = await openProject(tester);
    await tester.pumpWidget(appFor(env, ProjectShell(project: project, session: session)));
    await settle(tester);

    await openDrawer(tester);
    // 项目切换在最上，设置在最下
    final drawer = find.byType(AppDrawer);
    final top = tester.getTopLeft(find.descendant(of: drawer, matching: find.textContaining('切换工作区'))).dy;
    final bottom = tester.getTopLeft(find.descendant(of: drawer, matching: find.text('设置'))).dy;
    for (final d in ShellDest.drawerOnly) {
      final y = tester.getTopLeft(find.descendant(of: drawer, matching: find.text(d.label))).dy;
      expect(y, greaterThan(top));
      expect(y, lessThan(bottom));
    }
    for (final d in ShellDest.bottom) {
      expect(find.descendant(of: drawer, matching: find.text(d.label)), findsNothing, reason: '“${d.label}”在底部导航里，侧边栏不重复放');
    }
    expect(highlighted(tester, '新对话'), isTrue, reason: '一进来在对话页');
    await closeDrawer(tester);

    for (final d in ShellDest.drawerOnly) {
      await openDrawer(tester);
      await tester.tap(find.descendant(of: find.byType(AppDrawer), matching: find.text(d.label)));
      await drawerSettle(tester);
      await settle(tester, rounds: 8);
      expect(find.byType(AppDrawer), findsNothing, reason: '选了“${d.label}”后侧边栏应该收起');
      expect(marks[d]!.hitTestable(), findsWidgets, reason: '应该到了“${d.label}”页');
      expect(find.byTooltip('打开侧边栏').hitTestable(), findsOneWidget, reason: '“${d.label}”页也要有汉堡按钮');
      for (var i = 0; i < 5; i++) {
        expect(navSelected(tester, i), isFalse, reason: '在“${d.label}”页时底部导航没有选中项');
      }
      expect(tester.takeException(), isNull);

      await openDrawer(tester);
      expect(highlighted(tester, d.label), isTrue, reason: '“${d.label}”应该高亮');
      for (final other in ShellDest.drawerOnly.where((o) => o != d)) {
        expect(highlighted(tester, other.label), isFalse, reason: '“${other.label}”不该高亮');
      }
      await closeDrawer(tester);
    }

    // 回到对话
    await openDrawer(tester);
    await tester.tap(find.descendant(of: find.byType(AppDrawer), matching: find.text('新对话')));
    await drawerSettle(tester);
    expect(find.byTooltip('发送').hitTestable(), findsOneWidget);
    expect(navSelected(tester, 0), isTrue);
  });

  testWidgets('侧边栏是把主界面向右推开：位移、左侧大圆角、遮罩、底部导航一起走；点右侧 / 返回键 / 左滑都能关', (tester) async {
    final (env, project, session) = await openProject(tester);
    await tester.pumpWidget(appFor(env, ProjectShell(project: project, session: session)));
    await settle(tester);

    final nav = find.byType(IconBottomNav);
    final clip = find.byKey(const ValueKey('push-drawer-clip'));
    expect(tester.getTopLeft(nav).dx, 0);
    expect(tester.widget<ClipRRect>(clip).borderRadius, BorderRadius.zero, reason: '关着的时候主界面是直角、铺满');
    expect(find.byKey(const ValueKey('push-drawer-scrim')), findsNothing);

    await openDrawer(tester);
    final slide = PushDrawer.slideFor(390);
    expect(slide, 390 - PushDrawer.kPeek);
    expect(tester.getTopLeft(nav).dx, slide, reason: '底部导航跟着主界面一起被推到右边');
    expect(tester.getTopLeft(find.byTooltip('发送')).dx, greaterThan(slide), reason: '聊天页整体右移');
    final r = tester.widget<ClipRRect>(clip).borderRadius as BorderRadius;
    expect(r.topLeft.x, PushDrawer.kRadius);
    expect(r.bottomLeft.x, PushDrawer.kRadius);
    expect(r.topRight, Radius.zero);
    expect(r.bottomRight, Radius.zero);
    expect(find.byKey(const ValueKey('push-drawer-scrim')), findsOneWidget, reason: '被推走的主界面上盖一层遮罩');
    // 侧边栏平铺在左边那一块，没有阴影抽屉
    expect(tester.getRect(find.byType(AppDrawer)), const Rect.fromLTWH(0, 0, 308, 844));
    expect(find.byType(Drawer), findsNothing);

    // 打开期间主界面点不到：点露出来的底部导航只会关侧边栏，不会切页
    await tester.tapAt(Offset(slide + 60, 820));
    await drawerSettle(tester);
    expect(find.byType(AppDrawer), findsNothing);
    expect(tester.getTopLeft(nav).dx, 0);
    expect(navSelected(tester, 0), isTrue, reason: '点右侧只是关侧边栏');

    // 系统返回键先关侧边栏，页面不退出、也不切页
    await tapNav(tester, ShellDest.files);
    await openDrawer(tester);
    await tester.binding.handlePopRoute();
    await drawerSettle(tester);
    expect(find.byType(AppDrawer), findsNothing);
    expect(navSelected(tester, 1), isTrue, reason: '第一次返回只关侧边栏，还在文件页');
    await tester.binding.handlePopRoute();
    await settle(tester, rounds: 6);
    expect(navSelected(tester, 0), isTrue, reason: '第二次返回才回聊天页');

    // 跟手：拖到一半主界面停在一半；松手后过半就打开
    final g = await tester.startGesture(const Offset(4, 420));
    await g.moveBy(const Offset(30, 0)); // 过拖动判定距离
    await g.moveBy(const Offset(100, 0));
    await tester.pump();
    final half = tester.getTopLeft(nav).dx;
    expect(half, greaterThan(60));
    expect(half, lessThan(slide));
    await g.moveBy(const Offset(120, 0));
    await g.up();
    await drawerSettle(tester);
    expect(tester.getTopLeft(nav).dx, slide);

    // 开着时在侧边栏上左滑关闭
    await tester.dragFrom(const Offset(250, 600), const Offset(-220, 0));
    await drawerSettle(tester);
    expect(find.byType(AppDrawer), findsNothing);
  });

  testWidgets('键盘开着时打开侧边栏会先收键盘', (tester) async {
    final (env, project, session) = await openProject(tester);
    await tester.pumpWidget(appFor(env, ProjectShell(project: project, session: session)));
    await settle(tester);
    await tester.tap(find.byType(TextField).hitTestable().first);
    await settle(tester, rounds: 3);
    expect(tester.testTextInput.isVisible, isTrue);
    await openDrawer(tester);
    expect(tester.testTextInput.isVisible, isFalse, reason: '打开侧边栏要先把键盘收起来');
    expect(FocusManager.instance.primaryFocus?.context?.widget is EditableText, isFalse);
  });

  testWidgets('终端和低代码页不让边缘右滑拉出侧边栏，其他页可以', (tester) async {
    final (env, project, session) = await openProject(tester);
    await tester.pumpWidget(appFor(env, ProjectShell(project: project, session: session)));
    await settle(tester);

    Future<void> swipe() async {
      await tester.dragFrom(const Offset(4, 420), const Offset(260, 0));
      await drawerSettle(tester);
    }

    await swipe();
    expect(find.byType(AppDrawer), findsOneWidget, reason: '对话页右滑应该拉出侧边栏');
    await closeDrawer(tester);
    for (final d in [ShellDest.terminal, ShellDest.builder]) {
      await tapNav(tester, d);
      await swipe();
      expect(find.byType(AppDrawer), findsNothing, reason: '“${d.label}”页右滑不该拉出侧边栏');
      await openDrawer(tester);
      await closeDrawer(tester);
    }
  });

  testWidgets('输入卡片：空的时候发不出去；发送后能停止；确认卡照常', (tester) async {
    usePhoneViewport(tester);
    late TestEnv env;
    await tester.runAsync(() async {
      env = await TestEnv.create(
        chatClient: () => ScriptedChatClient([
          [say('我看一下目录。'), call(0, 'run_command', '{"command":"ls"}')],
          [say('看完了。')],
        ]),
      );
    });
    final (_, project, session) = await openProject(tester, env: env, template: ProjectTemplate.web);
    await tester.pumpWidget(appFor(env, ProjectShell(project: project, session: session)));
    await settle(tester);

    // 空输入：发送按钮是灰的，点了没反应
    final send = find.byTooltip('发送');
    expect(tester.widget<IconButton>(find.ancestor(of: send, matching: find.byType(IconButton)).first).onPressed, isNull);

    await tester.enterText(find.byType(TextField), '看看目录');
    await tester.pump();
    expect(tester.widget<IconButton>(find.ancestor(of: find.byTooltip('发送'), matching: find.byType(IconButton)).first).onPressed, isNotNull);
    await tester.tap(find.byTooltip('发送'));
    await tester.runAsync(() async {
      for (var i = 0; i < 40 && session.pendingApproval == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    });
    await settle(tester, rounds: 3);

    expect(find.text('看看目录'), findsWidgets); // 气泡 + 顶栏标题
    expect(session.conversationTitle, '看看目录');
    expect(session.pendingApproval, isNotNull, reason: '执行命令前必须停下来等确认');
    expect(find.text('允许这一次'), findsOneWidget);
    expect(find.byTooltip('停止'), findsOneWidget, reason: '运行中发送按钮变成停止');
    expect(find.byTooltip('发送'), findsNothing);

    // 点停止：确认卡消失，命令没有执行
    await tester.tap(find.byTooltip('停止'));
    await tester.runAsync(() async {
      for (var i = 0; i < 40 && session.agentBusy; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    });
    await settle(tester, rounds: 3);
    expect(session.agentBusy, isFalse);
    expect(session.pendingApproval, isNull);
    expect(find.text('允许这一次'), findsNothing);
    expect(find.byTooltip('发送'), findsOneWidget);
    expect(session.chat.whereType<ToolItem>().single.denied, isTrue, reason: '没批准的命令不能执行');
  });

  testWidgets('新对话、对话记录、切换与删除', (tester) async {
    usePhoneViewport(tester);
    late TestEnv env;
    await tester.runAsync(() async {
      env = await TestEnv.create(chatClient: () => ScriptedChatClient([[say('好的。')]]));
    });
    final (_, project, session) = await openProject(tester, env: env, template: ProjectTemplate.web);
    await tester.pumpWidget(appFor(env, ProjectShell(project: project, session: session)));
    await settle(tester);

    await tester.runAsync(() => session.sendToAgent('第一段对话'));
    await settle(tester, rounds: 2);
    // 空对话时“新对话”不堆空的；有内容后才开新的
    await newChat(tester);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await settle(tester, rounds: 2);
    expect(session.conversations.length, 2);
    expect(session.chat, isEmpty);
    await newChat(tester);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await settle(tester, rounds: 2);
    expect(session.conversations.length, 2, reason: '当前对话还是空的，不再新建');

    await tester.runAsync(() => session.sendToAgent('第二段对话'));
    await settle(tester, rounds: 2);

    await openDrawer(tester);
    expect(highlighted(tester, '第二段对话'), isTrue);
    expect(highlighted(tester, '第一段对话'), isFalse);
    await tester.tap(find.descendant(of: find.byType(AppDrawer), matching: find.text('第一段对话')));
    await drawerSettle(tester);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
    await settle(tester, rounds: 3);
    expect(session.conversationTitle, '第一段对话');
    expect(session.chat.whereType<UserItem>().single.text, '第一段对话');

    // 存盘了：重新打开会话还在
    late ProjectSession again;
    await tester.runAsync(() async {
      again = ProjectSession(env.services, project);
      await again.loadChat();
    });
    addTearDown(again.dispose);
    expect(again.conversations.map((c) => c.title), containsAll(['第一段对话', '第二段对话']));

    await tester.runAsync(() => session.deleteConversation());
    await settle(tester, rounds: 2);
    expect(session.conversations.map((c) => c.title), ['第二段对话']);
    expect(File('${project.dir}/.lopicode/chat.json').existsSync(), isFalse);
  });

  testWidgets('项目规则在设置里编辑（聊天页和 ··· 菜单里没有了），会拼进系统提示词并存盘', (tester) async {
    final (env, project, session) = await openProject(tester, template: ProjectTemplate.web);
    await tester.pumpWidget(appFor(env, ProjectShell(project: project, session: session)));
    await settle(tester);
    expect(find.text('项目规则'), findsNothing, reason: '聊天页中间不再有入口');
    await tester.tap(find.byTooltip('更多').hitTestable());
    await tester.pumpAndSettle();
    expect(find.text('项目规则'), findsNothing, reason: '··· 菜单里也没有');
    await tester.tapAt(const Offset(20, 400));
    await tester.pumpAndSettle();

    await openDrawer(tester);
    await tester.tap(find.descendant(of: find.byType(AppDrawer), matching: find.text('设置')));
    await settle(tester, rounds: 4);
    final row = find.byKey(const Key('settings-rules'));
    expect(find.descendant(of: row, matching: find.text('未设置')), findsOneWidget);
    expect(find.descendant(of: row, matching: find.textContaining('只对工作区“我的小站”生效')), findsOneWidget);
    await tester.tap(row);
    await settle(tester, rounds: 4);
    expect(find.textContaining('只对这个工作区生效'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('rules-field')), '页面一律用中文');
    await tester.tap(find.byKey(const Key('rules-save')));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await settle(tester, rounds: 3);
    expect(session.systemPrompt, contains('页面一律用中文'));
    expect(File('${project.dir}/.lopicode/rules.md').readAsStringSync(), '页面一律用中文');
    await tester.tap(find.byTooltip('返回').last);
    await settle(tester, rounds: 4);
    expect(find.descendant(of: find.byKey(const Key('settings-rules')), matching: find.text('已设置')), findsOneWidget);
  });

  testWidgets('首页：没有项目是项目列表空状态；记住上次打开的项目', (tester) async {
    usePhoneViewport(tester);
    late TestEnv env;
    await tester.runAsync(() async => env = await TestEnv.create());
    addTearDown(env.dispose);
    await tester.pumpWidget(appFor(env, const HomeGate()));
    await settle(tester);
    expect(find.text('还没有工作区'), findsOneWidget);
    await openDrawer(tester);
    expect(find.descendant(of: find.byType(AppDrawer), matching: find.text('设置')), findsOneWidget);
    await closeDrawer(tester);

    await tester.tap(find.widgetWithText(FilledButton, '添加工作区').first);
    await settle(tester, rounds: 3);
    await tester.tap(find.text('新建项目'));
    await settle(tester, rounds: 3);
    await tester.tap(find.widgetWithText(FilledButton, '创建'));
    await settle(tester, rounds: 150, ms: 5);
    expect(find.byTooltip('发送'), findsOneWidget, reason: '新建后直接进项目的对话页');
    final last = env.services.settings.getString('ui.lastProject');
    expect(last, isNotEmpty);

    // 重新启动：直接回到这个项目
    await tester.pumpWidget(appFor(env, HomeGate(key: UniqueKey())));
    await settle(tester, rounds: 150, ms: 5);
    expect(find.byTooltip('发送'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await settle(tester, rounds: 2);
  });
}
