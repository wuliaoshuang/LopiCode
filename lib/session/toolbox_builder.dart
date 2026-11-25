// 给一段对话组装工具箱：基础的文件 / 命令工具（AgentToolbox）加上按设置才出现的那些——
// 待办清单、提问、后端积木、联网搜索、技能、派子代理、任务板、自动化任务。
//
// 安全规矩都在这里接线，改动要小心：
// - 没人在场（自动化任务）：没有提问工具、没有自动化工具，确认一律按拒绝；
// - 权限档位和计划模式每次现查目录里的最新值；
// - “本对话都允许”按主对话记；
// - 写入范围（团队任务）原样传给 AgentToolbox。
import 'package:lopicode/agent/agent_tools.dart';
import 'package:lopicode/agent/skills.dart';
import 'package:lopicode/agent/team.dart';
import 'package:lopicode/agent/todos.dart';
import 'package:lopicode/agent/web_search.dart';
import 'package:lopicode/backend/backend_agent_tools.dart';
import 'package:lopicode/runtime/linux_command_runner.dart';
import 'package:lopicode/session/automation_tools.dart';
import 'package:lopicode/session/background_flow.dart';
import 'package:lopicode/session/chat_models.dart';
import 'package:lopicode/session/conversation.dart';
import 'package:lopicode/session/session_core.dart';
import 'package:lopicode/ssh/ssh_shell_backend.dart';
import 'package:lopicode/state/workspace_chat.dart';
import 'package:lopicode/terminal/terminal_session.dart';

/// 造“派子代理”工具的函数（在 subagents.dart 里；从外面传进来免得两个文件互相拿着对方）。
typedef SpawnToolFactory = ExtraTool Function(ChatRunNotifier parent, Conversation root, List<Skill> skills);

class ToolboxBuilder {
  ToolboxBuilder(this.core, {required this.spawnTool, this.background});

  /// 后台命令的接线（工具、结束通知）。
  final BackgroundFlow? background;

  final SessionCore core;
  final SpawnToolFactory spawnTool;

  /// 出一张确认卡。没人在场：一律按拒绝。
  Future<bool> requestApproval(ChatRunNotifier run, ApprovalRequest request) {
    if (run.unattended) return Future.value(false);
    // 记一笔“正在等确认”：这时候 App 被关掉，下次能说清楚这一步没有执行。
    final journal = core.journalOf(run.convId)..setAwaitingApproval(true);
    return core.cards.requestApproval(PendingApproval(request, conversationId: run.convId, agentName: run.conv.agentName)).whenComplete(() => journal.setAwaitingApproval(false));
  }

  Future<String> _askUser(ChatRunNotifier run, String question, List<String> options) {
    if (run.unattended) return Future.value('（这是无人值守的自动化任务，没有人能回答。请按最稳妥的做法继续，或者说明卡在哪里。）');
    return core.cards.ask(PendingQuestion(question, options, conversationId: run.convId, agentName: run.conv.agentName));
  }

  ExtraTool _askTool(ChatRunNotifier run) => ExtraTool(
    spec: toolSpec(
      'ask_user',
      '需要用户拿主意时，向用户提一个问题并等他回答。给出 2 到 4 个选项，用户也可以自己写别的回答。',
      {
        'question': {'type': 'string', 'description': '要问的问题'},
        'options': {
          'type': 'array',
          'items': {'type': 'string'},
          'description': '可选的回答',
        },
      },
      ['question'],
    ),
    kind: ToolKind.other,
    run: (args) async {
      final raw = args['options'];
      final options = [
        for (final o in raw is List ? raw : const [])
          if (o is String && o.trim().isNotEmpty) o.trim(),
      ].take(6).toList();
      final answer = await _askUser(run, AgentToolbox.argString(args, 'question'), options);
      return ToolOutcome('用户的回答：$answer');
    },
  );

  /// run_command 的回显写进哪个终端：第一个不是 SSH 的会话（Ubuntu，桌面上是本机 shell）。
  /// 安卓上没装运行环境时可能一个都没有，或者只有 SSH 会话——那就不回显，免得把本机命令的输出混进远程主机的屏幕里。
  TerminalSession? _echoTerminal() => core.session.terminals.where((t) => t.backend is! SshShellBackend).firstOrNull;

  Future<AgentToolbox> build(ChatRunNotifier run, Conversation root, List<Skill> skills, {List<String>? writeScope}) async {
    final app = core.app;
    final session = core.session;
    final conv = run.conv;
    final extras = <ExtraTool>[];
    extras.add(todoTool());
    if (!run.unattended) extras.add(_askTool(run));
    // 后端积木的读 / 改：和低代码页面的两个工具一样一直在（权限档位、计划模式由 AgentToolbox 按 kind 拦）
    extras.addAll(backendTools(guard: core.guard, writeScope: writeScope));
    final search = await WebSearchConfig.load(app.settings, app.secrets);
    if (search != null) extras.add((session.webSearchFactory ?? WebSearchClient.new)(search).tool);
    final skillTool = app.skills.tool(skills);
    if (skillTool != null) extras.add(skillTool);
    if (core.subagentsEnabled && conv.depth < core.subagentMaxDepth) extras.add(spawnTool(run, root, skills));
    if (core.teamEnabled) extras.addAll((await core.boardOf(root)).tools(conv.parentId == null ? TeamBoard.lead : conv.agentName));
    if (!run.unattended) extras.addAll(automationTools(store: app.automations, project: core.project, approve: (request) => requestApproval(run, request)));
    final runner = session.commandRunnerFactory?.call() ?? LinuxCommandRunner(app.runtime, guestCwd: core.project.linuxPath, onOutput: (t) => _echoTerminal()?.append(t));
    // 后台命令：启动的确认接的是工具箱里 run_command 用的同一个判断（工具箱在下面才建，所以用 late）。
    late final AgentToolbox box;
    extras.addAll(background?.tools(run, root, runner, approve: (r) => box.approveCommand(r), stopSignal: () => box.stopSignal?.call()) ?? const []);
    return box = AgentToolbox(
      guard: core.guard,
      runner: runner,
      requestApproval: (r) => requestApproval(run, r),
      autoApprove: () => core.cards.autoAllowed(root.id),
      // 权限和计划模式每次都现查目录里的最新值：跑到一半改了档位、开了计划模式，下一步就生效
      permission: () => core.permissionOf(core.live(root)),
      planMode: () => core.live(root).planMode,
      allowedTools: core.presetOf(core.live(root)).tools,
      writeScope: writeScope,
      extras: extras,
    );
  }
}
