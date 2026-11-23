// 侧边栏导航和对话输入卡片的行为测试（390×844）。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/core/project_store.dart';
import 'package:lopicode/core/templates.dart';
import 'package:lopicode/project_session.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/home_gate.dart';
import 'package:lopicode/ui/preview_tab.dart';
import 'package:lopicode/ui/project_shell.dart';
import 'package:lopicode/ui/shell.dart';
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
    await Future<void>.delayed(const Duration(milliseconds: 150));
  });
  addTearDown(() async {
    session.dispose();
    e.dispose();
  });
  return (e, project, session);
}

Future<void> openDrawer(WidgetTester tester) async {
  // 每个页面都有自己的汉堡按钮；IndexedStack 里只有当前页的那个能点到。
  await tester.tap(find.byTooltip('打开侧边栏').hitTestable());
  await drawerSettle(tester);
  expect(find.byType(Drawer), findsOneWidget);
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
  expect(find.byType(Drawer), findsNothing);
}

/// 侧边栏里这一项是不是高亮的（强调色浅底）。
bool highlighted(WidgetTester tester, String label) {
  final item = find.descendant(of: find.byType(Drawer), matching: find.text(label));
  expect(item, findsOneWidget, reason: '侧边栏里应该有“$label”');
  final material = tester.widget<Material>(find.ancestor(of: item, matching: find.byType(Material)).first);
  final colors = tester.element(item).colors;
  return material.color == colors.accentSoft;
}

void main() {
  setUpAll(() => PreviewTab.debugViewBuilder = (uri) => const ColoredBox(color: Colors.white));
  tearDownAll(() => PreviewTab.debugViewBuilder = null);

  testWidgets('没有底部导航；侧边栏能去每个页面，当前项高亮，再回到对话', (tester) async {
    final (env, project, session) = await openProject(tester);
    await tester.pumpWidget(appFor(env, ProjectShell(project: project, session: session)));
    await settle(tester);

    expect(find.byType(NavigationBar), findsNothing);
    expect(find.byType(BottomNavigationBar), findsNothing);
    // 进项目先看到对话页
    expect(find.byTooltip('发送'), findsOneWidget);

    await openDrawer(tester);
    // 项目切换在最上，设置在最下
    final drawer = find.byType(Drawer);
    final top = tester.getTopLeft(find.descendant(of: drawer, matching: find.text('切换项目'))).dy;
    final bottom = tester.getTopLeft(find.descendant(of: drawer, matching: find.text('设置'))).dy;
    for (final d in ShellDest.values.skip(1)) {
      final y = tester.getTopLeft(find.descendant(of: drawer, matching: find.text(d.label))).dy;
      expect(y, greaterThan(top));
      expect(y, lessThan(bottom));
    }
    expect(highlighted(tester, '新对话'), isTrue, reason: '一进来在对话页');
    await closeDrawer(tester);

    final marks = <ShellDest, Finder>{
      ShellDest.files: find.text('index.html'),
      ShellDest.terminal: find.byTooltip('新建会话'),
      ShellDest.preview: find.text('手机'),
      ShellDest.builder: find.byTooltip('图层'),
      ShellDest.apk: find.textContaining('手机上跑不了 Android SDK 和 Gradle'),
      ShellDest.runtime: find.byKey(const Key('runtime-status')),
    };
    for (final d in ShellDest.values.skip(1)) {
      await openDrawer(tester);
      await tester.tap(find.descendant(of: find.byType(Drawer), matching: find.text(d.label)));
      await drawerSettle(tester);
      await settle(tester, rounds: 8);
      expect(find.byType(Drawer), findsNothing, reason: '选了“${d.label}”后侧边栏应该收起');
      expect(marks[d]!.hitTestable(), findsWidgets, reason: '应该到了“${d.label}”页');
      expect(find.byTooltip('打开侧边栏').hitTestable(), findsOneWidget, reason: '“${d.label}”页也要有汉堡按钮');
      expect(tester.takeException(), isNull);

      await openDrawer(tester);
      expect(highlighted(tester, d.label), isTrue, reason: '“${d.label}”应该高亮');
      for (final other in ShellDest.values.skip(1).where((o) => o != d)) {
        expect(highlighted(tester, other.label), isFalse, reason: '“${other.label}”不该高亮');
      }
      await closeDrawer(tester);
    }

    // 回到对话
    await openDrawer(tester);
    await tester.tap(find.descendant(of: find.byType(Drawer), matching: find.text('新对话')));
    await drawerSettle(tester);
    expect(find.byTooltip('发送').hitTestable(), findsOneWidget);
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
    expect(find.byType(Drawer), findsOneWidget, reason: '对话页右滑应该拉出侧边栏');
    for (final d in [ShellDest.terminal, ShellDest.builder]) {
      await tester.tap(find.descendant(of: find.byType(Drawer), matching: find.text(d.label)));
      await drawerSettle(tester);
      await settle(tester, rounds: 8);
      await swipe();
      expect(find.byType(Drawer), findsNothing, reason: '“${d.label}”页右滑不该拉出侧边栏');
      await openDrawer(tester);
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
    await tester.tap(find.byTooltip('新对话'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await settle(tester, rounds: 2);
    expect(session.conversations.length, 2);
    expect(session.chat, isEmpty);
    await tester.tap(find.byTooltip('新对话'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await settle(tester, rounds: 2);
    expect(session.conversations.length, 2, reason: '当前对话还是空的，不再新建');

    await tester.runAsync(() => session.sendToAgent('第二段对话'));
    await settle(tester, rounds: 2);

    await openDrawer(tester);
    expect(highlighted(tester, '第二段对话'), isTrue);
    expect(highlighted(tester, '第一段对话'), isFalse);
    await tester.tap(find.descendant(of: find.byType(Drawer), matching: find.text('第一段对话')));
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

  testWidgets('项目规则会拼进系统提示词并存盘', (tester) async {
    final (env, project, session) = await openProject(tester, template: ProjectTemplate.web);
    await tester.pumpWidget(appFor(env, ProjectShell(project: project, session: session)));
    await settle(tester);
    await tester.tap(find.text('项目规则'));
    await settle(tester, rounds: 3);
    await tester.enterText(find.byType(TextField).last, '页面一律用中文');
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await settle(tester, rounds: 3);
    expect(session.systemPrompt, contains('页面一律用中文'));
    expect(find.text('项目规则 · 已设置'), findsOneWidget);
    expect(File('${project.dir}/.lopicode/rules.md').readAsStringSync(), '页面一律用中文');
  });

  testWidgets('首页：没有项目是项目列表空状态；记住上次打开的项目', (tester) async {
    usePhoneViewport(tester);
    late TestEnv env;
    await tester.runAsync(() async => env = await TestEnv.create());
    addTearDown(env.dispose);
    await tester.pumpWidget(appFor(env, const HomeGate()));
    await settle(tester);
    expect(find.text('还没有项目'), findsOneWidget);
    await openDrawer(tester);
    expect(find.descendant(of: find.byType(Drawer), matching: find.text('设置')), findsOneWidget);
    await closeDrawer(tester);

    await tester.tap(find.widgetWithText(FilledButton, '新建项目').first);
    await settle(tester, rounds: 3);
    await tester.tap(find.widgetWithText(FilledButton, '创建'));
    await settle(tester, rounds: 40, ms: 5);
    expect(find.byTooltip('发送'), findsOneWidget, reason: '新建后直接进项目的对话页');
    final last = env.services.settings.getString('ui.lastProject');
    expect(last, isNotEmpty);

    // 重新启动：直接回到这个项目
    await tester.pumpWidget(appFor(env, HomeGate(key: UniqueKey())));
    await settle(tester, rounds: 40, ms: 5);
    expect(find.byTooltip('发送'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await settle(tester, rounds: 2);
  });
}
