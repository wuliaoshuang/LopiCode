// 底部导航点一下短震一次（霜霜真机反馈第二轮第 1 条，390×844，浅色、深色）。
// 用假的平台通道记下 HapticFeedback.vibrate 调用，断言次数和类型。没有可见变化，所以不出截图。
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/core/project_store.dart';
import 'package:lopicode/core/templates.dart';
import 'package:lopicode/project_session.dart';
import 'package:lopicode/theme/app_theme.dart';
import 'package:lopicode/ui/chrome.dart';
import 'package:lopicode/ui/project_shell.dart';
import 'package:lopicode/ui/push_drawer.dart';
import 'package:lopicode/ui/shell.dart';
import 'package:material_ui/material_ui.dart';

import 'support/harness.dart';

/// 导航用的那一种震动：轻的一下。
const String kNavHaptic = 'HapticFeedbackType.lightImpact';

/// 接管平台通道，返回记录震动类型的清单（每震一次加一条）。
List<String> recordHaptics(WidgetTester tester) {
  final log = <String>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
    if (call.method == 'HapticFeedback.vibrate') log.add('${call.arguments}');
    return null;
  });
  addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
  return log;
}

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

bool navSelected(WidgetTester tester, int i) => tester.widget<Semantics>(find.byKey(ValueKey('nav-$i'))).properties.selected ?? false;

void main() {
  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    final name = mode == ThemeMode.light ? '浅色' : '深色';

    testWidgets('底部导航（$name）：五项每点一项都轻震一次，页面照常切换', (tester) async {
      final (env, project, session) = await openProject(tester);
      await tester.pumpWidget(
        appFor(
          env,
          ProjectShell(project: project, session: session),
          mode: mode,
        ),
      );
      await settle(tester);
      expect(tester.getSize(find.byType(IconBottomNav)).width, 390);
      final log = recordHaptics(tester);

      // 从聊天页（第 0 项）出发，依次点 1、2、3、4，再点回 0：五项都点到。
      final n = ShellDest.bottom.length;
      expect(n, 5);
      final order = [for (var i = 1; i < n; i++) i, 0];
      for (var k = 0; k < order.length; k++) {
        final i = order[k];
        await tester.tap(find.byKey(ValueKey('nav-$i')));
        await tester.pump();
        expect(log, List.filled(k + 1, kNavHaptic), reason: '点第 $i 项：正好多震一次，而且是轻的那种');
        await settle(tester, rounds: 8);
        expect(navSelected(tester, i), isTrue, reason: '震动不影响切页');
        expect(log.length, k + 1, reason: '切页过程里不再多震');
      }
    });

    testWidgets('底部导航（$name）：重复点当前已选中的那一项也震一次，页面不变', (tester) async {
      final (env, project, session) = await openProject(tester);
      await tester.pumpWidget(
        appFor(
          env,
          ProjectShell(project: project, session: session),
          mode: mode,
        ),
      );
      await settle(tester);
      final log = recordHaptics(tester);

      expect(navSelected(tester, 0), isTrue);
      await tester.tap(find.byKey(const ValueKey('nav-0')));
      await settle(tester);
      expect(log, [kNavHaptic]);
      expect(navSelected(tester, 0), isTrue);

      await tester.tap(find.byKey(const ValueKey('nav-0')));
      await settle(tester);
      expect(log, [kNavHaptic, kNavHaptic], reason: '每点一下震一下，不合并、不漏');
      expect(navSelected(tester, 0), isTrue);
    });
  }

  testWidgets('没点到导航就不震：侧边栏开着时点露出来的导航只是关侧边栏', (tester) async {
    final (env, project, session) = await openProject(tester);
    await tester.pumpWidget(appFor(env, ProjectShell(project: project, session: session)));
    await settle(tester);
    final log = recordHaptics(tester);

    await tester.tap(find.byTooltip('打开侧边栏').hitTestable());
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await settle(tester, rounds: 3);
    expect(find.byType(AppDrawer), findsOneWidget);

    await tester.tapAt(Offset(PushDrawer.slideFor(390) + 60, 820));
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await settle(tester, rounds: 3);
    expect(find.byType(AppDrawer), findsNothing);
    expect(navSelected(tester, 0), isTrue);
    expect(log, isEmpty, reason: '导航没被点到，不该震');
  });

  testWidgets('IconBottomNav 单独用：点第 i 项先震一次再回调 i；不在五项里的页面（current = -1）也一样', (tester) async {
    usePhoneViewport(tester);
    final log = recordHaptics(tester);
    final taps = <int>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.light),
        home: Scaffold(
          bottomNavigationBar: IconBottomNav(items: shellNavItems(), current: -1, onTap: taps.add),
        ),
      ),
    );
    for (var i = 0; i < shellNavItems().length; i++) {
      await tester.tap(find.byKey(ValueKey('nav-$i')));
      await tester.pump();
      expect(taps.last, i);
      expect(log, List.filled(i + 1, kNavHaptic));
    }
    expect(taps, [0, 1, 2, 3, 4]);
    await tester.pumpAndSettle();
  });
}
