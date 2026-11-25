// 后台命令的界面（390×844，浅色 / 深色）：命令用真实的 /bin/sh 跑。
// 输入框上方一条 → 点开面板（每个任务一行）→ 点进去看实时日志 → 停止 → 聊天里一行安静的提示。
@TestOn('linux')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/agent/agent_tools.dart';
import 'package:lopicode/agent/background_commands.dart';
import 'package:lopicode/agent/background_tools.dart';
import 'package:lopicode/agent/command_runner.dart';
import 'package:lopicode/core/project_store.dart';
import 'package:lopicode/core/safe_file.dart';
import 'package:lopicode/core/templates.dart';
import 'package:lopicode/project_session.dart';
import 'package:lopicode/state/workspace_background.dart';
import 'package:lopicode/ui/chat_background.dart';
import 'package:lopicode/ui/project_shell.dart';
import 'package:material_ui/material_ui.dart';

import 'agent_ui_test.dart' show waitReal;
import 'screens_test.dart' show fontsLoaded, shot;
import 'session_system_test.dart' show RoutingClient, reply, use;
import 'support/harness.dart';

void main() {
  setUpAll(() async => fontsLoaded = await loadRealFonts());

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    final suffix = mode == ThemeMode.light ? 'light' : 'dark';

    testWidgets('后台命令：启动 → 输入框上方一条 → 面板 → 实时日志 → 停止 → 聊天里提示 ($suffix)', (tester) async {
      late TestEnv env;
      late Project project;
      late ProjectSession session;
      var n = 0;
      usePhoneViewport(tester);
      await tester.runAsync(
        () async => env = await TestEnv.create(
          chatClient: () => RoutingClient(
            (m, t) => switch (n++) {
              0 => use(kBgStartTool, {'command': 'sh dev.sh'}),
              1 => use(kBgStartTool, {'command': 'sh watch.sh --css'}),
              2 => reply('开发服务器和样式监听都在后台跑起来了。'),
              _ => reply('好的。'),
            },
            [],
          ),
        ),
      );
      await tester.runAsync(() async {
        project = await env.services.projects.create('我的小站', ProjectTemplate.web);
        File('${project.dir}/dev.sh').writeAsStringSync(
          'echo "> my-site@1.0.0 dev"\necho "> vite"\necho ""\necho "  VITE v7.2.4  ready in 312 ms"\necho ""\necho "  Local:   http://localhost:5173/"\necho "  好了，等待改动…"\nsleep 300\n',
        );
        File('${project.dir}/watch.sh').writeAsStringSync('echo "watching styles…"\nsleep 300\n');
        session = ProjectSession(env.services, project)..commandRunnerFactory = LocalShellRunner.new;
        await session.loadChat();
        await session.setPermission(PermissionLevel.full);
      });
      BackgroundTasksState state() => env.services.container.read(backgroundTasksProvider(session));
      await tester.pumpWidget(
        appFor(
          env,
          ProjectShell(project: project, session: session),
          mode: mode,
          font: kTestFont,
        ),
      );
      await settle(tester);
      expect(find.byKey(const ValueKey('bg-bar')), findsNothing, reason: '没有后台命令时这一条不出现');

      await tester.enterText(find.byType(TextField), '把开发服务器跑起来');
      await tester.pump();
      await tester.tap(find.byTooltip('发送'));
      await waitReal(tester, () => !session.agentBusy && session.chat.length > 1 && state().tasks.length == 2, what: '这一轮结束');
      await waitReal(tester, () => state().tasks.first.bytes > 0, what: '日志有内容');

      // 1) 输入框上方一条。
      expect(find.text('后台任务 2 个在跑'), findsOneWidget);
      await shot(tester, '110-background-bar-$suffix');

      // 步骤行：后台启动 <命令> · #任务号。
      await tester.tap(find.textContaining('步').first, warnIfMissed: false);
      await settle(tester, rounds: 2);
      if (find.textContaining('后台启动', findRichText: true).evaluate().isNotEmpty) {
        expect(find.textContaining('sh dev.sh · #1', findRichText: true), findsOneWidget);
        await shot(tester, '111-background-steps-$suffix');
      }

      // 2) 面板：每个任务一行。
      await tester.tap(find.byKey(const ValueKey('bg-bar')));
      await settle(tester, rounds: 3);
      expect(find.text('后台任务'), findsOneWidget);
      expect(find.text('sh dev.sh'), findsOneWidget);
      expect(find.text('sh watch.sh --css'), findsOneWidget);
      expect(find.textContaining('#1 · 在跑'), findsOneWidget);
      expect(find.textContaining('#2 · 在跑'), findsOneWidget);
      await shot(tester, '112-background-sheet-$suffix');

      // 3) 日志页。
      await tester.tap(find.byKey(const ValueKey('bg-task-1')));
      await settle(tester, rounds: 4);
      expect(find.text('后台命令 #1'), findsOneWidget);
      expect(find.textContaining('http://localhost:5173/'), findsOneWidget);
      expect(find.byKey(const ValueKey('bg-log-stop')), findsOneWidget);
      await shot(tester, '113-background-log-$suffix');

      // 停止。
      await tester.tap(find.byKey(const ValueKey('bg-log-stop')));
      await waitReal(tester, () => !state().tasks.first.running, what: '停下来');
      expect(state().tasks.first.status, BackgroundStatus.stopped);
      expect(find.byKey(const ValueKey('bg-log-stop')), findsNothing);
      expect(find.textContaining('你停掉的'), findsOneWidget);
      await shot(tester, '114-background-log-stopped-$suffix');

      // 复制日志（放在停止之后：提示条会短暂盖住底部）。
      await tester.tap(find.byKey(const ValueKey('bg-log-copy')));
      await settle(tester, rounds: 2);
      expect(find.text('已复制日志'), findsOneWidget);
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(seconds: 2)); // 让提示消失
      }
      expect(find.text('已复制日志'), findsNothing);

      // 回到聊天：一行安静的提示；那一条还在（还有一个在跑）。
      await tester.binding.handlePopRoute(); // 自定义顶栏：不用 pageBack
      await settle(tester, rounds: 3);
      await tester.tapAt(const Offset(195, 120)); // 关面板
      await settle(tester, rounds: 3);
      expect(find.text('后台任务 1 个在跑'), findsOneWidget);
      expect(find.textContaining('后台命令 #1 已停止。下次发消息时会告诉 AI。'), findsOneWidget);
      await shot(tester, '115-background-notice-$suffix');

      // 收尾：全部停掉，别把进程和定时器留到测试外面。
      await tester.runAsync(() async {
        session.dispose();
        await pendingWrites();
      });
      await tester.pump(const Duration(seconds: 3));
      expect(find.byType(BackgroundBar), findsOneWidget);
      expect(find.byKey(const ValueKey('bg-bar')), findsNothing);
      await tester.runAsync(() => env.dispose());
    });
  }
}
