// Agent 系统与 AI 配置的界面：390×844 浅色 + 深色各渲染一遍（不能有异常或溢出），并走关键操作。
//   LOPI_SHOTS=1 flutter test test/agent_ui_test.dart   # 同时写截图到 docs/screenshots/
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/agent/agent_tools.dart';
import 'package:lopicode/agent/automation.dart';
import 'package:lopicode/agent/chat_client.dart';
import 'package:lopicode/agent/model_config.dart';
import 'package:lopicode/agent/presets.dart';
import 'package:lopicode/agent/team.dart';
import 'package:lopicode/agent/web_search.dart';
import 'package:lopicode/core/project_store.dart';
import 'package:lopicode/core/stores.dart';
import 'package:lopicode/core/templates.dart';
import 'package:lopicode/project_session.dart';
import 'package:lopicode/ui/automation_screen.dart';
import 'package:lopicode/ui/chat_panels.dart';
import 'package:lopicode/ui/project_list_screen.dart';
import 'package:lopicode/ui/project_shell.dart';
import 'package:lopicode/ui/settings_agent.dart';
import 'package:lopicode/ui/settings_ai.dart';
import 'package:lopicode/ui/settings_screen.dart';
import 'package:lopicode/ui/team_screen.dart';
import 'package:material_ui/material_ui.dart';

import 'agent_test.dart' show RecordingRunner;
import 'screens_test.dart' show shot, fontsLoaded;
import 'session_system_test.dart' show RoutingClient, Turn, reply, use, firstUser, hasToolResult;
import 'support/harness.dart';

/// 先显示一个空首页再把 [page] 推进来：页面保存后会自己返回，得有地方可回。
class Launcher extends StatefulWidget {
  const Launcher({super.key, required this.page});
  final Widget page;
  @override
  State<Launcher> createState() => _LauncherState();
}

class _LauncherState extends State<Launcher> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Navigator.of(context).push(PageRouteBuilder<void>(pageBuilder: (_, _, _) => widget.page));
    });
  }

  @override
  Widget build(BuildContext context) => const Scaffold(body: SizedBox.expand());
}

/// 真实 IO 和界面交替推进，直到条件成立。
Future<void> waitReal(WidgetTester tester, bool Function() cond, {String what = '条件'}) async {
  for (var i = 0; i < 300 && !cond(); i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    await tester.pump(const Duration(milliseconds: 20));
  }
  if (!cond()) fail('等不到：$what');
  await settle(tester, rounds: 3);
}

void main() {
  setUpAll(() async => fontsLoaded = await loadRealFonts());

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    final suffix = mode == ThemeMode.light ? 'light' : 'dark';
    const font = kTestFont;
    late TestEnv env;
    late Project project;
    late ProjectSession session;
    late RecordingRunner shell;
    Turn turn = (_, _) => reply('好的。');

    Future<void> boot(WidgetTester tester, {bool withSession = true}) async {
      usePhoneViewport(tester);
      turn = (_, _) => reply('好的。');
      await tester.runAsync(() async {
        env = await TestEnv.create(chatClient: () => RoutingClient((m, t) => turn(m, t), []));
        if (withSession) {
          project = await env.services.projects.create('我的小站', ProjectTemplate.web);
          session = ProjectSession(env.services, project);
          shell = RecordingRunner();
          session.commandRunnerFactory = () => shell;
          await session.loadChat();
        }
      });
      addTearDown(() async {
        if (withSession) session.dispose();
        await env.dispose();
      });
    }

    Future<Channel> addChannels(WidgetTester tester) async {
      late Channel first;
      await tester.runAsync(() async {
        first = await env.services.models.upsert(
          name: '我的中转站',
          protocol: ChatProtocol.openaiChat,
          baseUrl: 'https://api.example.com/v1',
          apiKey: 'sk-demo',
          models: [
            ModelSpec(id: 'gpt-demo', name: '主力模型', vision: true, thinking: true),
            ModelSpec(id: 'mini-demo', contextLength: 128000),
          ],
        );
        await env.services.models.upsert(
          name: 'Claude 官方',
          protocol: ChatProtocol.anthropic,
          baseUrl: 'https://api.anthropic.com/v1',
          apiKey: 'ak-demo',
          models: [ModelSpec(id: 'claude-demo', vision: true, thinking: true)],
        );
        await env.services.models.upsert(name: '还没填 Key 的', protocol: ChatProtocol.openaiResponses, baseUrl: 'https://api.openai.com/v1');
      });
      return first;
    }

    Future<void> show(WidgetTester tester, Widget home, {int rounds = 6, bool push = false}) async {
      await tester.pumpWidget(
        appFor(
          env,
          push ? Launcher(key: UniqueKey(), page: home) : home,
          mode: mode,
          font: font,
        ),
      );
      await settle(tester, rounds: rounds);
    }

    testWidgets('设置目录页：概况卡 + 模型 / Agent / 能力 / 界面 / 运行与打包 / 当前工作区 / 关于，只放入口 ($suffix)', (tester) async {
      await boot(tester);
      await addChannels(tester);
      await show(tester, SettingsScreen(workspace: project), push: true);
      // 顶部：圆形返回按钮 + 贴着它左对齐的标题（2026-11-24 起全应用的标题都不再居中）
      expect(find.byTooltip('返回'), findsOneWidget);
      expect(tester.getTopLeft(find.text('设置')).dx, tester.getRect(find.byTooltip('返回')).right + 12, reason: '标题贴着返回按钮');
      // 概况卡：新对话用的模型 + 运行环境，都是真实状态
      final overview = find.byKey(const Key('settings-overview'));
      expect(find.descendant(of: overview, matching: find.text('主力模型')), findsOneWidget);
      // 不是 DeepSeek 官方渠道：只有模型名和渠道名，没有进度条和百分比（运行环境那一块仍有自己的进度条）
      expect(find.descendant(of: overview, matching: find.textContaining('新对话用的模型 · 我的中转站')), findsOneWidget);
      expect(find.descendant(of: overview, matching: find.textContaining('%')), findsNothing);
      expect(
        find.descendant(of: overview, matching: find.byKey(const Key('overview-bar'))),
        findsOneWidget,
        reason: '只剩运行环境那一根',
      );
      expect(find.byKey(const Key('overview-set-quota')), findsNothing);
      expect(find.descendant(of: overview, matching: find.text('运行环境')), findsWidgets);
      expect(find.descendant(of: overview, matching: find.text('未安装')), findsOneWidget);
      // 每一项都在：滚到它再看
      final list = find.byType(Scrollable).first;
      for (final title in ['模型', 'Agent', '能力', '界面', '运行与打包', '当前工作区 · ${project.name}', '关于']) {
        await tester.scrollUntilVisible(find.text(title), 120, scrollable: list);
        expect(find.text(title), findsOneWidget);
      }
      // 回到顶上，再按从上到下的顺序一项项找。一级页只放入口：每一行右边都有箭头，开关和输入框都不在这一页。
      expect(find.byType(Switch), findsNothing, reason: '一级页没有开关');
      expect(find.byType(TextField), findsNothing, reason: '一级页没有输入框');
      await tester.drag(list, const Offset(0, 4000));
      await settle(tester, rounds: 2);
      for (final key in [
        'settings-channels',
        'settings-agent',
        'settings-personalize',
        'settings-subagents',
        'settings-search',
        'settings-skills',
        'settings-automations',
        'settings-chat',
        'settings-appearance',
        'settings-runtime',
        'settings-ssh',
        'settings-third-party',
        'settings-error-log',
      ]) {
        await tester.scrollUntilVisible(find.byKey(Key(key)), 120, scrollable: list);
        expect(find.byKey(Key(key)), findsOneWidget, reason: key);
        expect(
          find.descendant(of: find.byKey(Key(key)), matching: find.byIcon(Icons.chevron_right)),
          findsOneWidget,
          reason: '$key 右边有箭头',
        );
      }
      expect(find.byKey(const Key('settings-permission')), findsNothing, reason: '权限这一项挪进了“权限与执行”页');
      await tester.drag(list, const Offset(0, 2000));
      await settle(tester, rounds: 2);
      final yChannels = tester.getTopLeft(find.byKey(const Key('settings-channels'))).dy;
      final yPerm = tester.getTopLeft(find.byKey(const Key('settings-agent'))).dy;
      expect(yChannels, lessThan(yPerm));
      await shot(tester, '37-settings-directory-$suffix');

      // 新对话的权限（在“权限与执行”页里）：选完全权限要先确认
      await tester.tap(find.byKey(const Key('settings-agent')));
      await settle(tester, rounds: 6);
      expect(find.text('权限与执行'), findsWidgets);
      await tester.tap(find.byKey(const Key('settings-permission')));
      await settle(tester, rounds: 3);
      expect(find.text('仅可查看'), findsOneWidget);
      expect(find.text('工作区内修改'), findsWidgets);
      await shot(tester, '38-permission-sheet-$suffix');
      await tester.tap(find.text('完全权限').last);
      await settle(tester, rounds: 3);
      expect(find.text('改成完全权限？'), findsOneWidget);
      expect(env.services.settings.getString(SettingKeys.defaultPermission, 'workspace'), 'workspace', reason: '没确认前不生效');
      await tester.tap(find.text('取消'));
      await settle(tester, rounds: 3);
      expect(env.services.settings.getString(SettingKeys.defaultPermission, 'workspace'), 'workspace');
    });

    testWidgets('模型与渠道：列表、新建渠道（Key 进安全存储）、编辑留空保留原 Key ($suffix)', (tester) async {
      await boot(tester, withSession: false);
      final ch = await addChannels(tester);
      await show(tester, const ChannelsScreen());
      expect(find.text('我的中转站'), findsOneWidget);
      expect(find.text('Claude 官方'), findsOneWidget);
      expect(find.textContaining('沿用上次'), findsWidgets);
      await shot(tester, '39-channels-$suffix');

      await show(tester, ChannelEditScreen(channel: ch), push: true);
      expect(find.byKey(const Key('channel-protocol')), findsOneWidget);
      expect(find.text('主力模型'), findsOneWidget);
      // Key 不回显
      expect(tester.widget<TextField>(find.byKey(const Key('channel-key'))).controller!.text, isEmpty);
      expect(find.textContaining('sk-demo'), findsNothing);
      await shot(tester, '40-channel-edit-$suffix');
      await tester.enterText(find.byKey(const Key('channel-url')), 'https://api2.example.com/v1');
      // 页面分了四步、变长了：刚输过字的输入框会把页面滚回去露出光标，先等它滚完，再滚到“保存”。
      await tester.pump(const Duration(milliseconds: 500));
      await tester.ensureVisible(find.byKey(const Key('channel-save')));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byKey(const Key('channel-save')));
      await settle(tester, rounds: 6);
      expect(env.services.models.channel(ch.id)!.baseUrl, 'https://api2.example.com/v1');
      late String? key;
      await tester.runAsync(() async => key = await env.services.models.apiKey(ch.id));
      expect(key, 'sk-demo', reason: 'Key 留空＝保留原来的');
      expect(File('${env.tmp.path}/settings.json').readAsStringSync(), isNot(contains('sk-demo')));

      // 模型参数面板
      await show(tester, Scaffold(body: ModelSpecSheet(model: ch.models.first)));
      expect(find.textContaining('上下文'), findsWidgets);
      expect(find.textContaining('最大输出'), findsWidgets);
      await shot(tester, '41-model-spec-$suffix');
    });

    testWidgets('对话里选模型：先渠道，再模型和思考深度 ($suffix)', (tester) async {
      await boot(tester);
      final ch = await addChannels(tester);
      await show(tester, Scaffold(body: ModelPickerSheet(current: ModelSelection(ch.id, 'gpt-demo', 'medium'))));
      expect(find.text('我的中转站'), findsWidgets);
      expect(find.text('主力模型'), findsOneWidget);
      expect(find.text('mini-demo'), findsOneWidget);
      expect(find.textContaining('思考'), findsWidgets);
      await shot(tester, '42-model-picker-$suffix');
      await tester.tap(find.text('Claude 官方'));
      await settle(tester, rounds: 2);
      expect(find.text('claude-demo'), findsOneWidget);
      expect(find.text('mini-demo'), findsNothing);
    });

    testWidgets('对话页：确认卡三个选择、排队条、自动允许提示可点关 ($suffix)', (tester) async {
      await boot(tester);
      var n = 0;
      turn = (m, t) => n++ < 2 ? use('run_command', {'command': 'npm install'}) : reply('装好了。');
      await show(tester, ProjectShell(project: project, session: session));
      await tester.enterText(find.byType(TextField), '装一下依赖');
      await tester.pump();
      await tester.tap(find.byTooltip('发送'));
      await waitReal(tester, () => session.pendingApproval != null, what: '确认卡');
      expect(find.text('拒绝'), findsOneWidget);
      expect(find.text('允许这一次'), findsOneWidget);
      expect(find.text('本对话都允许'), findsOneWidget);
      expect(find.textContaining('npm install'), findsWidgets);

      // 生成中再发两条：排队显示在底部
      await tester.runAsync(() async {
        await session.sendToAgent('顺便看看 README');
        await session.sendToAgent('再跑一下测试');
      });
      await settle(tester, rounds: 2);
      expect(find.text('顺便看看 README'), findsOneWidget);
      expect(find.text('再跑一下测试'), findsOneWidget);
      await shot(tester, '43-chat-approval-queue-$suffix');
      // 每条一个菜单：立即发送 / 改为插话 / 撤回
      await tester.tap(find.byTooltip('处理这条消息').last);
      await settle(tester, rounds: 3);
      expect(find.text('立即发送'), findsOneWidget);
      expect(find.text('改为插话'), findsOneWidget);
      expect(find.text('撤回'), findsOneWidget);
      await shot(tester, '43b-queue-menu-$suffix');
      await tester.tap(find.text('撤回'));
      await settle(tester, rounds: 3);
      expect(session.queue.single.text, '顺便看看 README');
      await tester.tap(find.byTooltip('处理这条消息'));
      await settle(tester, rounds: 3);
      await tester.tap(find.text('改为插话'));
      await settle(tester, rounds: 3);
      expect(session.queue.single.steer, isTrue);
      expect(find.textContaining('插话'), findsWidgets);

      await tester.tap(find.text('本对话都允许'));
      await settle(tester, rounds: 2);
      // 二次确认：点了还不生效，先说明后果，再点“确认，都允许”才算。
      expect(session.pendingApproval, isNotNull, reason: '只点一次不能生效');
      expect(session.autoAllowActive, isFalse);
      expect(find.byKey(const Key('always-explain')), findsOneWidget);
      await tester.tap(find.byKey(const Key('always-confirm')));
      await waitReal(tester, () => !session.agentBusy, what: '这一轮结束');
      expect(shell.commands, ['npm install', 'npm install']);
      expect(find.byKey(const ValueKey('auto-allow-chip')), findsOneWidget);
      await shot(tester, '44-chat-auto-allow-$suffix');
      await tester.tap(find.descendant(of: find.byKey(const ValueKey('auto-allow-chip')), matching: find.text('关闭')));
      await settle(tester, rounds: 2);
      expect(session.autoAllowActive, isFalse);
      expect(find.byKey(const ValueKey('auto-allow-chip')), findsNothing);
    });

    testWidgets('对话页：提问卡（选项 + 其他回答）($suffix)', (tester) async {
      await boot(tester);
      var n = 0;
      turn = (m, t) => n++ == 0
          ? use('ask_user', {
              'question': '首页用哪种配色？',
              'options': ['清爽蓝', '暖橙色', '深色'],
            })
          : reply('好的，用橙色。');
      await show(tester, ProjectShell(project: project, session: session));
      await tester.runAsync(() async => unawaited(session.sendToAgent('做个首页')));
      await waitReal(tester, () => session.pendingQuestion != null, what: '提问卡');
      expect(find.text('首页用哪种配色？'), findsOneWidget);
      expect(find.text('清爽蓝'), findsOneWidget);
      expect(find.text('其他回答'), findsOneWidget);
      await shot(tester, '45-chat-question-$suffix');
      await tester.tap(find.text('暖橙色'));
      await waitReal(tester, () => !session.agentBusy, what: '回答后继续');
      expect(session.pendingQuestion, isNull);
      expect(find.text('首页用哪种配色？'), findsNothing);
    });

    testWidgets('对话页：/ 指令提示、/plan 开计划模式、提示条可退出；长按发送选方式 ($suffix)', (tester) async {
      await boot(tester);
      await show(tester, ProjectShell(project: project, session: session));
      await tester.enterText(find.byType(TextField), '/');
      await settle(tester, rounds: 2);
      for (final cmd in ['/new', '/model', '/plan', '/compact', '/export', '/permission']) {
        expect(find.text(cmd), findsOneWidget, reason: cmd);
      }
      await shot(tester, '46-chat-slash-$suffix');
      await tester.enterText(find.byType(TextField), '/plan');
      await tester.pump();
      await tester.tap(find.byTooltip('发送'));
      await settle(tester, rounds: 4);
      expect(session.planMode, isTrue);
      expect(session.chat, isEmpty, reason: '指令不当成消息发给模型');
      expect(find.byKey(const ValueKey('plan-chip')), findsOneWidget);
      await shot(tester, '47-chat-plan-$suffix');
      await tester.tap(find.descendant(of: find.byKey(const ValueKey('plan-chip')), matching: find.text('退出')));
      await settle(tester, rounds: 4);
      expect(session.planMode, isFalse);

      // 生成中长按发送键：选排队 / 插话 / 中断并发送
      final gate = Completer<void>();
      turn = (m, t) async {
        await gate.future;
        return reply('好');
      };
      await tester.runAsync(() async => unawaited(session.sendToAgent('先做这个')));
      await waitReal(tester, () => session.agentBusy, what: '开始生成');
      await tester.enterText(find.byType(TextField), '改主意了');
      await tester.pump();
      await tester.longPress(find.byKey(const ValueKey('send-button')));
      await settle(tester, rounds: 3);
      expect(find.text('排队'), findsWidgets);
      expect(find.text('插话'), findsWidgets);
      expect(find.text('中断并发送'), findsOneWidget);
      await shot(tester, '48-send-mode-$suffix');
      gate.complete();
      await tester.tapAt(const Offset(195, 80));
      await waitReal(tester, () => !session.agentBusy, what: '结束');
    });

    testWidgets('工作区列表：目录、对话数、置顶、分组、添加面板 ($suffix)', (tester) async {
      await boot(tester);
      await tester.runAsync(() async {
        final rootfs = Directory('${env.tmp.path}/rootfs/root')..createSync(recursive: true);
        env.services.projects.linuxRootfs = rootfs.parent.path;
        final b = await env.services.projects.create('活动报名页', ProjectTemplate.lowcode);
        await env.services.projects.setGroup(b, '公司');
        final u = await env.services.projects.addLinux('/root/node-api', name: '接口服务');
        await env.services.projects.setPinned(u, true);
        await session.sendToAgent('做个首页');
      });
      await show(tester, ProjectListScreen(onOpen: (_) {}), rounds: 60);
      expect(find.text('工作区'), findsWidgets);
      expect(find.text('接口服务'), findsOneWidget);
      expect(find.textContaining('/root/node-api'), findsOneWidget);
      expect(find.textContaining('1 段对话'), findsOneWidget);
      expect(find.text('公司'), findsOneWidget);
      // 置顶的排最前
      expect(tester.getTopLeft(find.text('接口服务')).dy, lessThan(tester.getTopLeft(find.text('我的小站')).dy));
      await shot(tester, '49-workspaces-$suffix');
      await tester.tap(find.text('添加工作区'));
      await settle(tester, rounds: 3);
      expect(find.text('新建项目'), findsOneWidget);
      expect(find.text('Ubuntu 里的目录'), findsOneWidget);
      await shot(tester, '50-workspace-add-$suffix');
    });

    testWidgets('子代理：顶栏胶囊 → 谱系列表 → 进入子对话，左上角返回上级 ($suffix)', (tester) async {
      await boot(tester);
      turn = (m, t) {
        final task = firstUser(m);
        if (task.startsWith('写')) return hasToolResult(m) ? reply('$task：写好了') : use('write_file', {'path': '${task.hashCode}.html', 'content': 'x'});
        if (hasToolResult(m)) return reply('两个页面都好了。');
        return [
          call(0, 'spawn_agent', jsonEncode({'name': '首页', 'task': '写首页 index 的结构'})),
          call(1, 'spawn_agent', jsonEncode({'name': '关于页', 'task': '写关于我们页面'})),
          ChatDelta(finishReason: 'tool_calls'),
        ];
      };
      await tester.runAsync(() => session.sendToAgent('做首页和关于页'));
      await show(tester, ProjectShell(project: project, session: session));
      expect(find.byType(SubAgentCapsule), findsOneWidget);
      expect(find.descendant(of: find.byType(SubAgentCapsule), matching: find.textContaining('2')), findsOneWidget);
      await shot(tester, '51-chat-subagents-$suffix');
      await tester.tap(find.byType(SubAgentCapsule));
      await settle(tester, rounds: 3);
      expect(find.text('首页'), findsWidgets);
      expect(find.text('关于页'), findsWidgets);
      await shot(tester, '52-subagent-list-$suffix');
      await tester.tap(find.descendant(of: find.byType(SubAgentSheet), matching: find.text('关于页')));
      await settle(tester, rounds: 6);
      expect(find.byType(SubConversationScreen), findsOneWidget);
      expect(find.text('写关于我们页面'), findsWidgets);
      expect(find.byTooltip('返回上级'), findsOneWidget);
      expect(find.byType(TextField), findsNothing, reason: '子对话只读');
      await shot(tester, '53-subagent-chat-$suffix');
      await tester.tap(find.byTooltip('返回上级'));
      await settle(tester, rounds: 10);
      expect(find.byType(SubConversationScreen), findsNothing);
    });

    testWidgets('智能体团队：成员 / 任务 / 消息三栏，范围重叠提示 ($suffix)', (tester) async {
      await boot(tester);
      await tester.runAsync(() async {
        await env.services.settings.set(SettingKeys.teamEnabled, true);
        final board = await session.boardOf(session.activeConversation);
        final t1 = await board.create(title: '搭页面框架', owner: TeamBoard.lead, scope: ['src/']);
        await board.create(title: '写登录页', owner: '前端', deps: [t1.id], scope: ['src/login/']);
        final t3 = await board.create(title: '整理样式', owner: '样式', scope: ['src/']);
        await board.create(title: '写说明文档', scope: ['docs/']);
        await board.update(t1.id, status: TaskStatus.doing);
        await board.update(t3.id, status: TaskStatus.doing);
        await board.post('前端', '', '登录页等框架好了就开工');
      });
      await show(tester, TeamScreen(session: session));
      expect(find.text('成员'), findsWidgets);
      expect(find.text('任务'), findsWidgets);
      expect(find.text('消息'), findsWidgets);
      await tester.tap(find.text('任务').first);
      await settle(tester, rounds: 3);
      expect(find.textContaining('待办'), findsWidgets);
      expect(find.textContaining('进行中'), findsWidgets);
      expect(find.textContaining('写登录页'), findsOneWidget);
      expect(find.textContaining('重叠'), findsWidgets);
      await shot(tester, '54-team-tasks-$suffix');
      await tester.tap(find.text('成员').first);
      await settle(tester, rounds: 3);
      expect(find.text('前端'), findsWidgets);
      await shot(tester, '55-team-members-$suffix');
      await tester.tap(find.text('消息').first);
      await settle(tester, rounds: 3);
      expect(find.text('登录页等框架好了就开工'), findsOneWidget);
      await shot(tester, '56-team-messages-$suffix');
    });

    testWidgets('自动化任务：列表如实说明、新建要过确认卡（完整指令 + 实际触发时间）($suffix)', (tester) async {
      await boot(tester);
      await tester.runAsync(() async {
        final a = await env.services.automations.upsert(
          title: '每天检查依赖',
          instruction: '看看 package.json 里的依赖有没有新版本，把结果写进 report.md',
          workspaceId: project.id,
          rule: TimeRule(kind: RuleKind.daily, hour: 8, minute: 30, tzOffsetMinutes: 480),
        );
        await env.services.automations.record(a.id, AutomationRun(DateTime.utc(2026, 11, 22, 0, 30), 'ok', '依赖都是最新的。'));
        await env.services.automations.record(a.id, AutomationRun(DateTime.utc(2026, 11, 23, 0, 30), 'missed', 'App 当时没在运行'));
      });
      await show(tester, AutomationListScreen(workspace: project), rounds: 40);
      expect(find.textContaining('工作区：我的小站'), findsOneWidget);
      expect(find.textContaining('已不在'), findsNothing);
      expect(find.text(kAutomationHonesty), findsOneWidget, reason: '必须如实说明 App 不在运行时不会触发');
      expect(kAutomationHonesty, contains('不'));
      expect(find.text('每天检查依赖'), findsOneWidget);
      await shot(tester, '57-automations-$suffix');

      await tester.tap(find.text('每天检查依赖'));
      await settle(tester, rounds: 4);
      expect(find.textContaining('错过'), findsWidgets);
      await shot(tester, '58-automation-detail-$suffix');

      await show(tester, AutomationEditScreen(workspace: project), push: true, rounds: 40);
      await tester.enterText(find.byKey(const Key('automation-title')), '晚上备份');
      await tester.enterText(find.byKey(const Key('automation-instruction')), '把 src 目录打包成 backup.tar.gz');
      await settle(tester, rounds: 2);
      await shot(tester, '59-automation-edit-$suffix');
      await tester.ensureVisible(find.byKey(const Key('automation-save')));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byKey(const Key('automation-save')));
      await settle(tester, rounds: 4);
      final card = tester.widget<SelectableText>(find.byKey(const Key('automation-confirm-text'))).data!;
      expect(card, contains('把 src 目录打包成 backup.tar.gz'));
      expect(card, contains('下一次触发：'));
      expect(card, contains('只有 App 正在运行时才会触发'));
      expect(env.services.automations.items, hasLength(1), reason: '确认前不保存');
      await shot(tester, '60-automation-confirm-$suffix');
      await tester.tap(find.byKey(const Key('automation-confirm')));
      await settle(tester, rounds: 6);
      expect(env.services.automations.items.map((a) => a.title), contains('晚上备份'));
    });

    testWidgets('个性化、预设、子代理设置、联网搜索、技能 ($suffix)', (tester) async {
      await boot(tester);
      await tester.runAsync(() async {
        await env.services.presets.upsert(name: '只读顾问', prompt: '只讲解，不改代码', tools: {'read_file', 'list_files'});
        await env.services.skills.create(name: '发版流程', description: '要打包发布时用', body: '1. 跑测试\n2. 打包');
        await env.services.skills.create(name: '写周报', description: '周五写周报时用', body: '按项目列进展', workspaceDir: project.dir);
      });
      await show(tester, const PersonalizeScreen());
      expect(find.text('标准模式'), findsWidgets);
      expect(find.text('只读顾问'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('prefs-field')), '回答用中文，尽量短');
      await tester.tap(find.byKey(const Key('prefs-save')));
      await settle(tester, rounds: 4);
      expect(env.services.presets.preferences, '回答用中文，尽量短');
      await shot(tester, '61-personalize-$suffix');

      await show(tester, PresetEditScreen(preset: env.services.presets.custom.single), push: true);
      expect(find.byKey(const Key('tool-read_file')), findsOneWidget);
      expect(find.byKey(const Key('tool-run_command')), findsOneWidget);
      await tester.pump(const Duration(seconds: 6)); // 等上一页的提示条消失
      await settle(tester, rounds: 2);
      await shot(tester, '62-preset-edit-$suffix');
      await tester.ensureVisible(find.byKey(const Key('tool-run_command')));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byKey(const Key('tool-run_command')));
      await tester.pump();
      await tester.ensureVisible(find.byKey(const Key('preset-save')));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byKey(const Key('preset-save')));
      await settle(tester, rounds: 4);
      expect(env.services.presets.custom.single.tools, containsAll(['read_file', 'list_files', 'run_command']));

      await show(tester, const SubagentSettingsScreen());
      expect(find.byKey(const Key('subagent-enabled')), findsOneWidget);
      expect(find.byKey(const Key('team-enabled')), findsOneWidget);
      expect(env.services.settings.getBool(SettingKeys.teamEnabled, false), isFalse, reason: '团队默认关闭');
      await shot(tester, '63-subagent-settings-$suffix');
      await tester.ensureVisible(find.byKey(const Key('team-enabled')));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byKey(const Key('team-enabled')));
      await settle(tester, rounds: 3);
      expect(env.services.settings.getBool(SettingKeys.teamEnabled, false), isTrue);

      await show(tester, const WebSearchSettingsScreen());
      expect(find.byKey(const Key('search-url')), findsOneWidget);
      await tester.enterText(find.byKey(const Key('search-key')), 'tvly-demo');
      await tester.tap(find.byKey(const Key('search-save')));
      await settle(tester, rounds: 4);
      late String? key;
      await tester.runAsync(() async => key = await env.services.secrets.read(WebSearchConfig.secretKey));
      expect(File('${env.tmp.path}/settings.json').readAsStringSync(), isNot(contains('tvly-demo')), reason: 'Key 只进安全存储');
      expect(key, 'tvly-demo');
      await shot(tester, '64-web-search-$suffix');

      await show(tester, SkillsScreen(workspace: project), rounds: 60);
      expect(find.text('发版流程'), findsOneWidget);
      expect(find.text('写周报'), findsOneWidget);
      await shot(tester, '65-skills-$suffix');
    });
  }
}

// 保证没用到的导入不报警（这些类型在上面的测试里以断言形式出现）。
// ignore: unused_element
void _unused(PermissionLevel a, AgentPreset b, ChatDelta c) {}
