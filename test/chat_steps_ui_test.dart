// 聊天里的步骤组、确认卡、提问卡：390×844 浅色 + 深色各渲染一遍（不能有异常或溢出），并走关键操作。
//   LOPI_SHOTS=1 flutter test test/chat_steps_ui_test.dart   # 同时写截图到 docs/screenshots/
import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/agent/agent_tools.dart';
import 'package:lopicode/agent/approval_risk.dart';
import 'package:lopicode/agent/usage.dart';
import 'package:lopicode/core/project_store.dart';
import 'package:lopicode/core/templates.dart';
import 'package:lopicode/project_session.dart';
import 'package:lopicode/session/chat_rows.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/chat_cards.dart';
import 'package:lopicode/ui/chat_row_view.dart';
import 'package:lopicode/ui/chat_steps.dart';
import 'package:lopicode/ui/project_shell.dart';
import 'package:material_ui/material_ui.dart';

import 'agent_test.dart' show RecordingRunner;
import 'agent_ui_test.dart' show waitReal;
import 'screens_test.dart' show shot, fontsLoaded;
import 'session_system_test.dart' show RoutingClient, Turn, reply, use;
import 'support/harness.dart';

ToolItem tool(String id, String name, String args, {String? result = 'ok', bool ok = true, bool denied = false, String? child}) =>
    ToolItem(id, name, args, result: result, ok: ok, denied: denied, childConversationId: child);

final List<ChatItem> kDoneTurn = [
  const UserItem('给页面加一个深色模式切换按钮'),
  const AssistantItem('我先看看项目里有什么。'),
  tool('c1', 'list_files', '{}', result: 'index.html\nstyle.css\napp.js'),
  tool('c2', 'read_file', '{"path":"index.html"}', result: '<!doctype html>\n<html>…</html>'),
  tool('c3', 'read_file', '{"path":"style.css"}', result: 'body { color: #222; }'),
  const AssistantItem('需要加一份深色样式，再在页面里放一个按钮。'),
  tool('c4', 'write_file', '{"path":"dark.css","content":"body.dark { background: #111; color: #eee; }"}', result: '已写入 dark.css（44 字符）'),
  tool('c5', 'run_command', '{"command":"npx prettier --check ."}', result: '错误：命令退出码 127\nsh: npx: not found', ok: false),
  tool('c6', 'read_file', '{"path":"app.js"}', result: List.filled(400, 'console.log("line");').join('\n')),
  const AssistantItem('已经加好 dark.css，并在页面右上角放了切换按钮。格式检查没跑成：手机上没有 npx。'),
  UsageItem(TurnUsage()),
];

void main() {
  setUpAll(() async => fontsLoaded = await loadRealFonts());

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    final suffix = mode == ThemeMode.light ? 'light' : 'dark';
    late TestEnv env;

    Future<void> bootEnv(WidgetTester tester, {Turn? turn}) async {
      usePhoneViewport(tester);
      await tester.runAsync(() async => env = await TestEnv.create(chatClient: turn == null ? null : () => RoutingClient(turn, [])));
      addTearDown(() => env.dispose());
    }

    Future<void> showRows(WidgetTester tester, List<ChatItem> items, {bool busy = false, List<Widget> below = const [], void Function(String)? onOpenChild}) async {
      await tester.pumpWidget(
        appFor(
          env,
          Scaffold(
            body: SafeArea(
              child: Column(
                children: [
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.all(Space.x4),
                      children: [for (final row in deriveChatRows(items, busy: busy)) ChatRowView(row: row, onOpenChild: onOpenChild)],
                    ),
                  ),
                  ...below,
                ],
              ),
            ),
          ),
          mode: mode,
          font: kTestFont,
        ),
      );
      // 进行中的组有转圈动画：不能等“全部静止”，推几帧就够。
      await tester.pump(const Duration(milliseconds: 300));
    }

    testWidgets('步骤组 · 做完：折成一行摘要，失败的那一步露在外面；点开是清单，再点看参数和结果 ($suffix)', (tester) async {
      await bootEnv(tester);
      await showRows(tester, kDoneTurn);
      // 一行摘要：文件按路径去重（读了 3 个），失败的命令照样算一条命令
      expect(find.text('执行了 6 步 · 读 3 个文件 · 改 1 个文件 · 1 条命令'), findsOneWidget);
      expect(find.descendant(of: find.byKey(const ValueKey('flag-步失败')), matching: find.text('1')), findsOneWidget);
      // 折叠着：成功的步骤和中间的话都不显示，失败的那一步露在外面
      expect(find.text('读取 index.html'), findsNothing);
      expect(find.text('需要加一份深色样式，再在页面里放一个按钮。'), findsNothing);
      expect(find.text('执行 npx prettier --check .'), findsOneWidget);
      expect(find.text('失败'), findsOneWidget);
      // 正式回复在组外面
      expect(find.textContaining('已经加好 dark.css'), findsOneWidget);
      await shot(tester, '70-steps-collapsed-$suffix');

      // 点摘要展开清单
      await tester.tap(find.byKey(const ValueKey('step-group-c1')));
      await tester.pumpAndSettle();
      for (final line in ['查看文件列表', '读取 index.html', '读取 style.css', '写入 dark.css', '执行 npx prettier --check .', '读取 app.js']) {
        expect(find.text(line), findsOneWidget, reason: line);
      }
      expect(find.text('我先看看项目里有什么。'), findsOneWidget);
      expect(find.text('需要加一份深色样式，再在页面里放一个按钮。'), findsOneWidget);
      await shot(tester, '71-steps-expanded-$suffix');

      // 点失败的那一步：看到命令和报错
      await tester.tap(find.byKey(const ValueKey('step-c5')));
      await tester.pumpAndSettle();
      expect(find.text(r'$ npx prettier --check .'), findsOneWidget);
      expect(find.text('报错'), findsOneWidget);
      expect(find.textContaining('npx: not found'), findsOneWidget);
      await shot(tester, '72-steps-detail-$suffix');
      await tester.tap(find.byKey(const ValueKey('step-c5')));
      await tester.pumpAndSettle();
      expect(find.text('报错'), findsNothing);

      // 长结果：先截一段，点“显示全部”
      await tester.ensureVisible(find.byKey(const ValueKey('step-c6')));
      await tester.tap(find.byKey(const ValueKey('step-c6')));
      await tester.pumpAndSettle();
      expect(find.textContaining('还有'), findsOneWidget);
      await tester.ensureVisible(find.text('显示全部'));
      await tester.tap(find.text('显示全部'));
      await tester.pumpAndSettle();
      expect(find.text('显示全部'), findsNothing);
      expect(find.textContaining('还有'), findsNothing);
      expect(tester.takeException(), isNull);

      // 再点摘要收起
      await tester.ensureVisible(find.byKey(const ValueKey('step-group-c1')));
      await tester.tap(find.byKey(const ValueKey('step-group-c1')));
      await tester.pumpAndSettle();
      expect(find.text('读取 index.html'), findsNothing);
    });

    testWidgets('步骤组 · 进行中：一行说现在在做什么 + 第几步，转圈；不展开清单 ($suffix)', (tester) async {
      await bootEnv(tester);
      final items = <ChatItem>[
        const UserItem('跑一下测试，有问题就修'),
        tool('r1', 'read_file', '{"path":"package.json"}'),
        tool('r2', 'read_file', '{"path":"test/app.test.js"}'),
        tool('r3', 'run_command', '{"command":"node --test"}', result: null),
      ];
      await showRows(tester, items, busy: true);
      expect(find.text('执行 node --test'), findsOneWidget);
      expect(find.text('第 3 步'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('读取 package.json'), findsNothing);
      expect(find.textContaining('执行了'), findsNothing);
      await shot(tester, '73-steps-live-$suffix');

      // 这一步做完、模型还没开口：在想下一步
      await showRows(tester, [...items.take(3), tool('r3', 'run_command', '{"command":"node --test"}', result: 'ok')], busy: true);
      expect(find.text('正在想下一步…'), findsOneWidget);
      expect(find.text('第 3 步'), findsOneWidget);
    });

    testWidgets('只有一步：不套组，直接一行；被拒绝的写“已拒绝”；子代理那一步能点“查看” ($suffix)', (tester) async {
      await bootEnv(tester);
      String? opened;
      await showRows(tester, [
        const UserItem('删掉旧文件'),
        tool('d1', 'delete_file', '{"path":"old.txt"}', result: '用户拒绝了这次删除，文件没有被改动。', ok: false, denied: true),
        const AssistantItem('好的，没有删。'),
        const UserItem('派人查一下'),
        tool('s1', 'spawn_agent', '{"name":"调研员","task":"查一下深色模式的常见做法"}', result: '子代理汇报：…', child: 'conv-9'),
        const AssistantItem('查好了。'),
      ], onOpenChild: (id) => opened = id);
      expect(find.byType(StepRow), findsNWidgets(2));
      expect(find.textContaining('执行了'), findsNothing);
      expect(find.text('删除 old.txt'), findsOneWidget);
      expect(find.text('已拒绝'), findsOneWidget);
      expect(find.text('派子代理“调研员” 查一下深色模式的常见做法'), findsOneWidget);
      await tester.tap(find.text('查看'));
      await tester.pump();
      expect(opened, 'conv-9');
      await shot(tester, '74-steps-single-$suffix');
    });

    testWidgets('折叠时被拒绝的步骤也露在外面，摘要行尾有标记；多于两条只露最后两条 ($suffix)', (tester) async {
      await bootEnv(tester);
      await showRows(tester, [
        const UserItem('清理一下'),
        tool('x1', 'run_command', '{"command":"a"}', result: '错误：1', ok: false),
        tool('x2', 'run_command', '{"command":"b"}', result: '错误：2', ok: false),
        tool('x3', 'run_command', '{"command":"c"}', result: '用户拒绝执行这条命令，命令没有运行。', ok: false, denied: true),
        tool('x4', 'read_file', '{"path":"a.txt"}'),
        const AssistantItem('没弄成。'),
      ]);
      expect(find.descendant(of: find.byKey(const ValueKey('flag-步失败')), matching: find.text('2')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const ValueKey('flag-步被拒绝')), matching: find.text('1')), findsOneWidget);
      expect(find.text('执行 a'), findsNothing);
      expect(find.text('执行 b'), findsOneWidget);
      expect(find.text('执行 c'), findsOneWidget);
      expect(find.byType(StepRow), findsNWidgets(kExposedFailures));
      expect(tester.takeException(), isNull);
    });

    testWidgets('确认卡：中性底；危险程度只有一小处颜色（普通 / 需留意 / 危险）；主按钮一个，“都允许”弱化 ($suffix)', (tester) async {
      await bootEnv(tester);
      final answers = <String>[];
      Widget card(ApprovalRequest r, {String agent = ''}) => ApprovalCard(
        pending: PendingApproval(r, agentName: agent),
        onAnswer: (allow, {always = false}) => answers.add('$allow/$always'),
      );

      // 需留意：一般命令
      await showRows(
        tester,
        const [UserItem('装一下依赖')],
        below: [card(ApprovalRequest(tool: 'run_command', title: '执行命令', detail: 'npm install'))],
      );
      expect(find.text('Agent 想执行命令，要允许吗？'), findsOneWidget);
      expect(find.byKey(const ValueKey('risk-caution')), findsOneWidget);
      expect(find.text(r'$ npm install'), findsOneWidget);
      expect(find.byType(FilledButton), findsOneWidget, reason: '只有一个实心主按钮');
      expect(find.widgetWithText(FilledButton, '允许这一次'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, '拒绝'), findsOneWidget);
      expect(find.widgetWithText(TextButton, '本对话都允许'), findsOneWidget);
      // 卡壳是中性底，不是警告色底
      final c = mode == ThemeMode.light ? AppColors.light : AppColors.dark;
      final shell = tester.widget<Container>(find.descendant(of: find.byType(ChatCard), matching: find.byType(Container)).first);
      expect((shell.decoration! as BoxDecoration).color, c.surface);
      await shot(tester, '75-approval-caution-$suffix');
      await tester.tap(find.text('允许这一次'));
      await tester.tap(find.text('拒绝'));
      await tester.tap(find.text('本对话都允许'));
      await tester.pump();
      // 二次确认：第一下只换出说明，不回答；取消能退回去；确认才算。
      expect(answers, ['true/false', 'false/false'], reason: '只点一次“本对话都允许”不能生效');
      expect(find.textContaining('同类操作不再问你'), findsOneWidget);
      expect(find.text('允许这一次'), findsNothing);
      await shot(tester, '75b-approval-always-confirm-$suffix');
      await tester.tap(find.byKey(const Key('always-cancel')));
      await tester.pump();
      expect(answers, ['true/false', 'false/false']);
      expect(find.text('允许这一次'), findsOneWidget);
      await tester.tap(find.text('本对话都允许'));
      await tester.pump();
      await tester.tap(find.byKey(const Key('always-confirm')));
      expect(answers, ['true/false', 'false/false', 'true/true']);
      // 换一张卡之前先清空界面：刚才点过的按钮状态（按下 / 聚焦的底色）不带到下一张截图里。
      await tester.pumpWidget(const SizedBox());

      // 危险：强制删除
      await showRows(
        tester,
        const [UserItem('清掉依赖目录')],
        below: [
          card(
            ApprovalRequest(tool: 'run_command', title: '执行命令', detail: 'rm -rf node_modules && npm ci'),
            agent: '清理员',
          ),
        ],
      );
      expect(find.text('子代理“清理员” 想执行命令，要允许吗？'), findsOneWidget);
      expect(find.byKey(const ValueKey('risk-danger')), findsOneWidget);
      expect(find.textContaining(RiskLevel.danger.label, findRichText: true), findsOneWidget);
      await shot(tester, '76-approval-danger-$suffix');

      // 普通：只看不改
      await showRows(
        tester,
        const [UserItem('看看目录')],
        below: [card(ApprovalRequest(tool: 'run_command', title: '执行命令', detail: 'ls -la'))],
      );
      expect(find.byKey(const ValueKey('risk-normal')), findsOneWidget);
      await shot(tester, '77-approval-normal-$suffix');

      // 删除文件：危险
      await showRows(
        tester,
        const [UserItem('删掉旧文件')],
        below: [card(ApprovalRequest(tool: 'delete_file', title: '删除文件', detail: 'old/notes.txt'))],
      );
      expect(find.byKey(const ValueKey('risk-danger')), findsOneWidget);
      expect(find.text('old/notes.txt'), findsOneWidget);

      // 自动化任务：没有“本对话都允许”，主按钮是“确认保存”
      await showRows(
        tester,
        const [UserItem('每天早上跑一下测试')],
        below: [card(ApprovalRequest(tool: 'schedule_task', title: '新建自动化任务', detail: '标题：每天跑测试\n时间：每天 08:00\n权限：工作区内修改', allowAlways: false))],
      );
      expect(find.text('本对话都允许'), findsNothing);
      expect(find.widgetWithText(FilledButton, '确认保存'), findsOneWidget);
      expect(find.byKey(const ValueKey('risk-caution')), findsOneWidget);
      await shot(tester, '78-approval-schedule-$suffix');
    });

    testWidgets('提问卡：和确认卡同一个卡壳；选项一行一个，“其他回答”可以自己写 ($suffix)', (tester) async {
      await bootEnv(tester);
      final answers = <String>[];
      await showRows(
        tester,
        const [UserItem('做个主页')],
        below: [
          QuestionCard(question: PendingQuestion('主页用什么配色？', ['浅色、简洁', '深色、科技感', '跟着系统走']), onAnswer: answers.add),
        ],
      );
      expect(find.byType(ChatCard), findsOneWidget);
      expect(find.text('Agent 想问你'), findsOneWidget);
      expect(find.byType(FilledButton), findsNothing, reason: '选项都是同级的，没有哪个更突出');
      await shot(tester, '79-question-$suffix');
      await tester.tap(find.text('深色、科技感'));
      expect(answers, ['深色、科技感']);
      await tester.tap(find.text('其他回答'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '粉色');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, '回答'));
      expect(answers.last, '粉色');
    });

    testWidgets('对话页整条链路：多步工具调用聚成一组；进行中等确认；做完折成一行；重新打开还是这个样子 ($suffix)', (tester) async {
      late Project project;
      late ProjectSession session;
      var n = 0;
      await bootEnv(
        tester,
        turn: (m, t) => switch (n++) {
          0 => use('list_files', {}),
          1 => use('write_file', {'path': 'dark.css', 'content': 'body.dark{}'}),
          2 => use('read_file', {'path': 'dark.css'}),
          3 => use('run_command', {'command': 'npm test'}),
          _ => reply('都弄好了。'),
        },
      );
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
      await tester.enterText(find.byType(TextField), '加个深色样式并跑测试');
      await tester.pump();
      await tester.tap(find.byTooltip('发送'));
      await waitReal(tester, () => session.pendingApproval != null, what: '确认卡');
      // 进行中：只有一行，说的是正在等确认的那条命令
      expect(find.text('执行 npm test'), findsOneWidget);
      expect(find.text('第 4 步'), findsOneWidget);
      expect(find.text('写入 dark.css'), findsNothing);
      expect(find.text('处理中…'), findsNothing);
      expect(find.byKey(const ValueKey('risk-caution')), findsOneWidget);
      await shot(tester, '80-chat-live-approval-$suffix');

      await tester.tap(find.text('允许这一次'));
      await waitReal(tester, () => !session.agentBusy, what: '这一轮结束');
      expect(find.text('执行了 4 步 · 读 1 个文件 · 改 1 个文件 · 1 条命令'), findsOneWidget);
      expect(find.text('都弄好了。'), findsOneWidget);
      expect(find.byType(StepRow), findsNothing);
      await shot(tester, '81-chat-done-$suffix');

      // 重新打开这段对话（从存盘的记录重建）：还是一行摘要
      await tester.runAsync(() async {
        session.dispose();
        session = ProjectSession(env.services, project)..commandRunnerFactory = RecordingRunner.new;
        await session.loadChat();
      });
      await tester.pumpWidget(
        appFor(
          env,
          ProjectShell(key: UniqueKey(), project: project, session: session),
          mode: mode,
          font: kTestFont,
        ),
      );
      await settle(tester);
      expect(find.text('执行了 4 步 · 读 1 个文件 · 改 1 个文件 · 1 条命令'), findsOneWidget);
      expect(find.text('都弄好了。'), findsOneWidget);
      await tester.tap(find.textContaining('执行了 4 步'));
      await tester.pumpAndSettle();
      expect(find.byType(StepRow), findsNWidgets(4));
      expect(find.text('执行 npm test'), findsOneWidget);
    });
  }
}
