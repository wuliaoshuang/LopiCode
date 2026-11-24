// 待办清单条（390×844，浅色 / 深色）：模型调用 update_todos 后，输入框上方出现一条进度；点开是清单；下一轮消失。
import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/core/project_store.dart';
import 'package:lopicode/core/templates.dart';
import 'package:lopicode/project_session.dart';
import 'package:lopicode/ui/chat_todos.dart';
import 'package:lopicode/ui/project_shell.dart';
import 'package:material_ui/material_ui.dart';

import 'agent_test.dart' show RecordingRunner;
import 'agent_ui_test.dart' show waitReal;
import 'screens_test.dart' show shot, fontsLoaded;
import 'session_system_test.dart' show RoutingClient, reply, use;
import 'support/harness.dart';

void main() {
  setUpAll(() async => fontsLoaded = await loadRealFonts());

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    final suffix = mode == ThemeMode.light ? 'light' : 'dark';

    testWidgets('待办清单：列出来 → 输入框上方一条进度 → 点开看清单 → 做完 → 发新消息后消失 ($suffix)', (tester) async {
      late TestEnv env;
      late Project project;
      late ProjectSession session;
      Map<String, dynamic> todos(List<String> status) => {
        'items': [
          for (final (i, text) in ['看看项目里有什么', '写深色样式 dark.css', '在页面里加切换按钮'].indexed) {'text': text, 'status': status[i]},
        ],
      };
      var n = 0;
      usePhoneViewport(tester);
      await tester.runAsync(
        () async => env = await TestEnv.create(
          chatClient: () => RoutingClient(
            (m, t) => switch (n++) {
              0 => use('update_todos', todos(['in_progress', 'pending', 'pending'])),
              1 => use('list_files', {}),
              2 => use('update_todos', todos(['done', 'in_progress', 'pending'])),
              3 => reply('先做到这里。'),
              4 => use('update_todos', todos(['done', 'done', 'done'])),
              5 => reply('都做完了。'),
              _ => reply('好的。'),
            },
            [],
          ),
        ),
      );
      addTearDown(() => env.dispose());
      await tester.runAsync(() async {
        project = await env.services.projects.create('我的小站', ProjectTemplate.web);
        session = ProjectSession(env.services, project)..commandRunnerFactory = RecordingRunner.new;
        await session.loadChat();
      });
      addTearDown(() => session.dispose());
      await tester.pumpWidget(
        appFor(
          env,
          ProjectShell(project: project, session: session),
          mode: mode,
          font: kTestFont,
        ),
      );
      await settle(tester);
      expect(find.byType(TodoBar), findsNothing);

      Future<void> send(String text) async {
        await tester.enterText(find.byType(TextField), text);
        await tester.pump();
        await tester.tap(find.byTooltip('发送'));
        await waitReal(tester, () => !session.agentBusy && session.chat.length > 1, what: '这一轮结束');
        await settle(tester);
      }

      await send('加个深色模式');
      expect(find.text('待办 1/3'), findsOneWidget);
      expect(find.text('写深色样式 dark.css'), findsOneWidget, reason: '收起时只露正在做的那一项');
      expect(find.text('在页面里加切换按钮'), findsNothing);
      await shot(tester, '82-todos-collapsed-$suffix');

      await tester.tap(find.byKey(const ValueKey('todo-bar')));
      await tester.pumpAndSettle();
      expect(find.text('看看项目里有什么'), findsOneWidget);
      expect(find.text('在页面里加切换按钮'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await shot(tester, '83-todos-open-$suffix');

      await send('继续');
      expect(find.text('待办 3/3'), findsOneWidget);
      expect(find.text('都做完了'), findsOneWidget);

      // 发了新消息、这一轮没再列清单：上一轮的清单不再挂着
      await send('谢谢');
      expect(find.byType(TodoBar), findsNothing);
    });
  }
}
