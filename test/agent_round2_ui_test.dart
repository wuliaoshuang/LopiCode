// Agent 第二轮的界面与会话测试（390×844，浅色 + 深色）：思考过程、已压缩提示、命令输出转存、
// 被关掉后的恢复提示、步数上限询问、“本对话都允许”二次确认、设置里的三行。不联网。
//   LOPI_SHOTS=1 flutter test test/agent_round2_ui_test.dart   # 同时写截图到 docs/screenshots/
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/agent/agent_runner.dart';
import 'package:lopicode/agent/agent_tools.dart';
import 'package:lopicode/agent/automation.dart';
import 'package:lopicode/agent/chat_client.dart';
import 'package:lopicode/agent/command_output_store.dart';
import 'package:lopicode/agent/command_runner.dart';
import 'package:lopicode/agent/model_config.dart';
import 'package:lopicode/agent/usage.dart';
import 'package:lopicode/core/project_store.dart';
import 'package:lopicode/core/safe_file.dart';
import 'package:lopicode/core/stores.dart';
import 'package:lopicode/core/templates.dart';
import 'package:lopicode/project_session.dart';
import 'package:lopicode/session/chat_rows.dart';
import 'package:lopicode/session/turn_journal.dart';
import 'package:lopicode/session/turn_runner.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/chat_cards.dart';
import 'package:lopicode/ui/chat_extras.dart';
import 'package:lopicode/ui/chat_row_view.dart';
import 'package:lopicode/ui/project_shell.dart';
import 'package:lopicode/ui/settings_chat.dart';
import 'package:lopicode/ui/settings_screen.dart';
import 'package:material_ui/material_ui.dart';

import 'agent_test.dart' show RecordingRunner;
import 'agent_ui_test.dart' show waitReal;
import 'screens_test.dart' show shot, fontsLoaded;
import 'session_system_test.dart' show RoutingClient, Turn, reply, use, waitFor;
import 'support/harness.dart';

/// 假命令：输出由测试指定；[gate] 不为 null 时卡在那里等放行（模拟“命令正在跑”）。
class SlowRunner implements CommandRunner {
  SlowRunner({this.output = 'ok', this.gate});
  final String output;
  final Completer<void>? gate;
  final List<String> commands = [];
  @override
  String get description => 'test';
  @override
  Future<CommandResult> run(String command, {required String workingDirectory, Duration timeout = Duration.zero}) async {
    commands.add(command);
    await gate?.future;
    return CommandResult(exitCode: 0, output: output);
  }
}

String bigOutput(int lines) => [for (var i = 1; i <= lines; i++) 'line $i ${'x' * 40}'].join('\n');

void main() {
  setUpAll(() async => fontsLoaded = await loadRealFonts());

  // ── 会话层（不带界面）────────────────────────────────
  group('会话', () {
    late TestEnv env;
    late Project project;
    late ProjectSession session;
    late List<({List<Map<String, dynamic>> messages, List<String> tools})> log;
    Turn turn = (_, _) => reply('好的。');

    Future<ProjectSession> open({CommandRunner Function()? runner}) async {
      final s = ProjectSession(env.services, project, headless: true)..commandRunnerFactory = runner ?? RecordingRunner.new;
      await s.loadChat();
      return s;
    }

    setUp(() async {
      log = [];
      turn = (_, _) => reply('好的。');
      env = await TestEnv.create(chatClient: () => RoutingClient((m, t) => turn(m, t), log));
      project = await env.services.projects.create('测试工作区', ProjectTemplate.web);
      session = await open();
    });
    tearDown(() async {
      session.dispose();
      await env.dispose();
    });

    File reserved(String name) => File('${project.dir}/.lopicode/$name');

    test('步数上限：设置里的数生效；到了出“要继续吗”卡，选继续接着做，选停止就停', () async {
      await env.services.settings.set(SettingKeys.agentMaxSteps, 10);
      var n = 0;
      turn = (m, t) => n++ < 25 ? use('list_files', {'n': n}) : reply('终于做完。');
      final done = session.sendToAgent('一直干');
      await waitFor(() => session.pendingQuestion != null, what: '第一次问');
      final q = session.pendingQuestion!;
      expect(q.question, contains('10 步'));
      expect(q.options, [kContinueAnswer, kStopAnswer]);
      expect(q.choiceOnly, isTrue);
      expect(session.chat.whereType<ToolItem>().length, 10);
      session.answerQuestion(kContinueAnswer);
      await waitFor(() => session.pendingQuestion != null && session.chat.whereType<ToolItem>().length == 20, what: '第二次问');
      expect(session.pendingQuestion!.question, contains('20 步'));
      session.answerQuestion(kStopAnswer);
      await done;
      expect(session.chat.whereType<ToolItem>().length, 20);
      expect(session.chat.whereType<NoticeItem>().last.text, contains('已执行 20 步'));
      expect(session.agentBusy, isFalse);
    });

    test('步数上限：存了范围外的数会夹回 10–100；没设是 30', () async {
      expect(stepLimitOf(env.services.settings), 30);
      await env.services.settings.set(SettingKeys.agentMaxSteps, 3);
      expect(stepLimitOf(env.services.settings), 10);
      await env.services.settings.set(SettingKeys.agentMaxSteps, 5000);
      expect(stepLimitOf(env.services.settings), 100);
    });

    test('步数上限：问的时候点了停止 → 卡收掉，这一轮停下', () async {
      await env.services.settings.set(SettingKeys.agentMaxSteps, 10);
      var n = 0;
      turn = (m, t) => use('list_files', {'n': n++});
      final done = session.sendToAgent('一直干');
      await waitFor(() => session.pendingQuestion != null, what: '问');
      session.stopAgent();
      await done;
      expect(session.pendingQuestion, isNull);
      expect(session.chat.whereType<NoticeItem>().last.text, '已停止。');
    });

    test('无人值守的自动化任务：到上限直接停，不出卡；运行记录记成没做完并写明原因', () async {
      await env.services.settings.set(SettingKeys.agentMaxSteps, 10);
      var n = 0;
      turn = (m, t) => use('list_files', {'n': n++});
      final run = await session.runAutomation(
        Automation(
          id: 'a1',
          title: '每日检查',
          instruction: '检查一遍',
          workspaceId: 'w',
          rule: TimeRule(kind: RuleKind.values.first, tzOffsetMinutes: 480),
        ),
      );
      expect(session.pendingQuestion, isNull);
      expect(run.status, 'failed');
      expect(run.summary, contains(AgentRunner.stepLimitStopPrefix));
      expect(run.summary, contains('10 步'));
      expect(n, 10, reason: '到 10 步就不再调模型');
    });

    test('子代理到上限：上级有人在场时照样问（卡上写明是哪个子代理）', () async {
      await env.services.settings.set(SettingKeys.agentMaxSteps, 10);
      var n = 0;
      turn = (m, t) {
        if (!t.contains('spawn_agent')) return n++ < 12 ? use('list_files', {'n': n}) : reply('子代理做完了。');
        return m.any((x) => x['role'] == 'tool') ? reply('都好了。') : use('spawn_agent', {'name': '小工', 'task': '把文件都看一遍'});
      };
      final done = session.sendToAgent('派人看看');
      await waitFor(() => session.pendingQuestion != null, what: '子代理的询问');
      expect(session.pendingQuestion!.agentName, '小工');
      session.answerQuestion(kContinueAnswer);
      await done;
      expect(session.chat.whereType<AssistantItem>().last.text, '都好了。');
    });

    test('自动压缩：快满时压成摘要接着跑；聊天里一条“已压缩”，用量里多一次标明是压缩的请求；重开还在；关掉开关就不压', () async {
      // 配一个上下文很小的模型（4000 token ≈ 12000 字符）
      await env.services.models.upsert(
        name: '我的中转站',
        protocol: ChatProtocol.openaiChat,
        baseUrl: 'https://relay.example.cn/v1',
        apiKey: 'sk-test',
        models: [ModelSpec(id: 'small', contextLength: 4000)],
      );
      expect(session.currentModel!.model.contextLength, 4000);
      await env.services.settings.set(SettingKeys.agentAutoCompact, false);
      for (var i = 0; i < 6; i++) {
        turn = (m, t) => reply('第 $i 个回答 ${'答' * 900}');
        await session.sendToAgent('第 $i 个要求 ${'字' * 900}');
      }
      expect(session.chat.whereType<CompactionItem>(), isEmpty, reason: '开关关着：不压');
      expect(log.every((r) => r.tools.isNotEmpty), isTrue, reason: '没有发过压缩请求');
      // 关着的时候，快满了给的是“发 /compact”的提醒
      expect(session.chat.whereType<NoticeItem>().map((n) => n.text).join(), contains('/compact'));

      await env.services.settings.set(SettingKeys.agentAutoCompact, true);
      log.clear();
      turn = (m, t) => t.isEmpty
          ? [say('摘要：前面聊了六轮'), ChatDelta(usage: const TokenUsage(uncached: 3000, output: 40)), ChatDelta(finishReason: 'stop')]
          : [say('接着做完了。'), ChatDelta(usage: const TokenUsage(uncached: 500, output: 10)), ChatDelta(finishReason: 'stop')];
      await session.sendToAgent('再做一件事');
      expect(log.length, 2, reason: '一次压缩 + 一次正常回复');
      expect(log.first.tools, isEmpty);
      expect(session.chat.whereType<CompactionItem>().single.summary, '摘要：前面聊了六轮');
      expect(session.chat.whereType<AssistantItem>().last.text, '接着做完了。', reason: '这一轮没中断');
      // 用量：这一轮两次请求，其中一次标着“压缩”，都算进合计
      final usage = session.chat.whereType<UsageItem>().last.turn;
      final requests = usage.steps.whereType<RequestStep>().toList();
      expect(requests.length, 2);
      expect(requests.where((r) => r.request.compaction).single.request.usage!.input, 3000);
      expect(usage.totals.input, 3500);
      // 压缩后发给模型的没有最早的原文；聊天页里原文还在
      expect(jsonEncode(log.last.messages), isNot(contains('第 0 个要求')));
      expect(jsonEncode(log.last.messages), contains('摘要：前面聊了六轮'));
      expect(session.chat.whereType<UserItem>().first.text, startsWith('第 0 个要求'));
      // 上下文占用按最近一次正常请求算，不被压缩那次带偏
      expect(session.activeConversation.lastInput, 500);

      // 重开：提示和原文都还在；再发一条不会又压一次
      session.dispose();
      session = await open();
      expect(session.chat.whereType<CompactionItem>().length, 1);
      expect(session.chat.whereType<UserItem>().first.text, startsWith('第 0 个要求'));
      log.clear();
      turn = (m, t) => reply('好。');
      await session.sendToAgent('谢谢');
      expect(log.length, 1);
    });

    test('自动压缩失败：对话不丢，给一句提示，这一轮照常', () async {
      await env.services.models.upsert(
        name: '我的中转站',
        protocol: ChatProtocol.openaiChat,
        baseUrl: 'https://relay.example.cn/v1',
        apiKey: 'sk-test',
        models: [ModelSpec(id: 'small', contextLength: 4000)],
      );
      await env.services.settings.set(SettingKeys.agentAutoCompact, false);
      for (var i = 0; i < 6; i++) {
        turn = (m, t) => reply('第 $i 个回答 ${'答' * 900}');
        await session.sendToAgent('第 $i 个要求 ${'字' * 900}');
      }
      await env.services.settings.set(SettingKeys.agentAutoCompact, true);
      turn = (m, t) => t.isEmpty ? throw ChatApiException('额度用完了', statusCode: 402) : reply('照常回答。');
      await session.sendToAgent('再做一件事');
      expect(session.chat.whereType<CompactionItem>(), isEmpty);
      expect(session.chat.whereType<NoticeItem>().map((n) => n.text).join(), allOf(contains('没成功'), contains('额度用完了'), contains('没有丢')));
      expect(session.chat.whereType<AssistantItem>().last.text, '照常回答。');
      expect(session.chat.whereType<UserItem>().length, 7);
    });

    test('被关掉后重新打开：命令跑到一半 → 提示说清楚；记录里那一步补成“结果不明”；不自动重跑', () async {
      final gate = Completer<void>();
      final slow = SlowRunner(gate: gate);
      session.dispose();
      session = await open(runner: () => slow);
      await session.setPermission(PermissionLevel.full);
      var n = 0;
      turn = (m, t) => switch (n++) {
        0 => use('read_file', {'path': 'index.html'}),
        1 => use('run_command', {'command': 'npm install'}),
        _ => reply('装好了。'),
      };
      final done = session.sendToAgent('装依赖');
      await waitFor(() => slow.commands.isNotEmpty, what: '命令开始跑');
      await pendingWrites();
      // 这一刻的存盘内容＝“App 这时候被关掉”留下的样子
      final journalAtKill = reserved('turn.json').readAsStringSync();
      final chatAtKill = reserved('chat.json').readAsStringSync();
      expect(jsonDecode(journalAtKill)['finished'], isFalse);
      expect(chatAtKill, contains('npm install'), reason: '进行中也存了消息记录');
      gate.complete();
      await done;
      session.dispose();
      await pendingWrites();
      expect(jsonDecode(reserved('turn.json').readAsStringSync())['finished'], isTrue, reason: '正常收尾会标成已结束');

      // 把存盘内容换回被关掉那一刻的（记号换成别的启动）
      reserved('turn.json').writeAsStringSync(jsonEncode({...jsonDecode(journalAtKill) as Map<String, dynamic>, 'token': 'old'}));
      reserved('chat.json').writeAsStringSync(chatAtKill);
      slow.commands.clear();
      log.clear();
      session = await open(runner: () => slow);
      final cut = session.chat.whereType<InterruptedItem>().single;
      expect(cut.headline, contains('第 2 步'));
      expect(cut.risky, isTrue);
      expect(cut.lines.join('\n'), allOf(contains('已经执行完 1 步'), contains('npm install'), contains('只执行了一半')));
      // 那一步在聊天里显示成失败，结果写明“结果不明”
      final step = session.chat.whereType<ToolItem>().last;
      expect(step.name, 'run_command');
      expect(step.ok, isFalse);
      expect(step.result, contains('App 被关掉'));
      // 光打开不会重跑任何东西
      expect(slow.commands, isEmpty);
      expect(log, isEmpty);
      expect(session.agentBusy, isFalse);

      // “不用了”：提示收掉，再打开也不再提示
      await session.dismissInterrupted();
      expect(session.chat.whereType<InterruptedItem>(), isEmpty);
      session.dispose();
      session = await open(runner: () => slow);
      expect(session.chat.whereType<InterruptedItem>(), isEmpty);
      expect(slow.commands, isEmpty);
    });

    test('被关掉后点“继续”：发一条“接着做”，模型看得到“结果不明”的说明；要不要重跑由它决定、照样要确认', () async {
      // 造一份“等模型回复时被关掉”的记录
      await session.sendToAgent('先聊一句');
      session.dispose();
      await pendingWrites();
      final msgs = jsonDecode(reserved('chat.json').readAsStringSync()) as List;
      msgs.addAll([
        {'role': 'user', 'content': '删掉 build 目录'},
        {
          'role': 'assistant',
          'content': '',
          'tool_calls': [
            {
              'id': 'c9',
              'type': 'function',
              'function': {'name': 'run_command', 'arguments': '{"command":"rm -rf build"}'},
            },
          ],
        },
      ]);
      reserved('chat.json').writeAsStringSync(jsonEncode(msgs));
      reserved('turn.json').writeAsStringSync(
        jsonEncode({
          'v': 1,
          'token': 'old',
          'at': 1,
          'text': '删掉 build 目录',
          'finished': false,
          'steps': [
            {'id': 'c9', 'name': 'run_command', 'args': '{"command":"rm -rf build"}', 'done': false, 'ok': true, 'awaiting': true},
          ],
        }),
      );
      final shell = RecordingRunner();
      session = await open(runner: () => shell);
      final cut = session.chat.whereType<InterruptedItem>().single;
      expect(cut.risky, isFalse);
      expect(cut.lines.join('\n'), allOf(contains('没有执行'), contains('确认卡不会恢复')));
      expect(session.pendingApproval, isNull, reason: '确认卡不恢复');
      expect(shell.commands, isEmpty);

      log.clear();
      var n = 0;
      turn = (m, t) => n++ == 0 ? use('run_command', {'command': 'rm -rf build'}) : reply('好。');
      final done = session.resumeInterrupted();
      await waitFor(() => session.pendingApproval != null, what: '重新要确认');
      expect(session.chat.whereType<InterruptedItem>(), isEmpty);
      expect(shell.commands, isEmpty, reason: '没点允许之前不执行');
      final sent = jsonEncode(log.first.messages);
      expect(sent, contains(kResumeText.substring(0, 12)));
      expect(sent, contains('App 被关掉'), reason: '模型看得到那一步结果不明');
      session.resolveApproval(false);
      await done;
      expect(shell.commands, isEmpty);
    });

    test('进行中记录文件坏了：不崩、不提示', () async {
      session.dispose();
      reserved('turn.json').writeAsStringSync('{"token": 12, "at": "x"');
      session = await open();
      expect(session.chat.whereType<InterruptedItem>(), isEmpty);
      reserved('turn.json').writeAsStringSync('[1,2,3]');
      session.dispose();
      session = await open();
      expect(session.chat.whereType<InterruptedItem>(), isEmpty);
    });

    test('删对话：进行中记录一起删', () async {
      await session.sendToAgent('hi');
      await pendingWrites();
      expect(reserved('turn.json').existsSync(), isTrue);
      await session.deleteConversation();
      expect(reserved('turn.json').existsSync(), isFalse);
    });

    test('命令输出太长：会话里也转存；readCommandOutput 读得到完整的', () async {
      session.dispose();
      session = await open(runner: () => SlowRunner(output: bigOutput(1500)));
      await session.setPermission(PermissionLevel.full);
      var n = 0;
      turn = (m, t) => n++ == 0 ? use('run_command', {'command': 'npm test'}) : reply('跑完了。');
      await session.sendToAgent('跑测试');
      final rel = spilledOutputPathOf(session.chat.whereType<ToolItem>().single.result);
      expect(rel, isNotNull);
      final full = await session.readCommandOutput(rel!);
      expect(full, contains('line 750 '));
      expect(await session.readCommandOutput('.lopicode/chat.json'), isNull);
    });

    test('“本对话都允许”仍然只在这段对话、这次启动里有效（二次确认只改界面，不改规则）', () async {
      final shell = RecordingRunner();
      session.dispose();
      session = await open(runner: () => shell);
      var n = 0;
      turn = (m, t) => n++ == 0 ? use('run_command', {'command': 'npm install'}) : reply('好。');
      final done = session.sendToAgent('装依赖');
      await waitFor(() => session.pendingApproval != null, what: '确认卡');
      expect(session.autoAllowActive, isFalse);
      session.resolveApproval(true, always: true);
      await done;
      expect(session.autoAllowActive, isTrue);
      session.dispose();
      session = await open(runner: () => shell);
      expect(session.autoAllowActive, isFalse, reason: '重开后恢复逐次询问');
    });
  });

  // ── 界面 ─────────────────────────────────────────────
  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    final suffix = mode == ThemeMode.light ? 'light' : 'dark';
    late TestEnv env;

    Future<void> bootEnv(WidgetTester tester, {Turn? turn}) async {
      usePhoneViewport(tester);
      await tester.runAsync(() async => env = await TestEnv.create(chatClient: turn == null ? null : () => RoutingClient(turn, [])));
      addTearDown(() => env.dispose());
    }

    Future<void> showRows(
      WidgetTester tester,
      List<ChatItem> items, {
      bool busy = false,
      bool showThinking = true,
      List<Widget> below = const [],
      Future<String?> Function(String)? readOutput,
      VoidCallback? onResume,
      VoidCallback? onDismiss,
    }) async {
      await tester.pumpWidget(
        appFor(
          env,
          Scaffold(
            body: SafeArea(
              child: Column(
                children: [
                  Expanded(
                    child: ChatRowActions(
                      readOutput: readOutput,
                      onResume: onResume,
                      onDismissInterrupted: onDismiss,
                      child: ListView(
                        padding: const EdgeInsets.all(Space.x4),
                        children: [for (final row in deriveChatRows(items, busy: busy, showThinking: showThinking)) ChatRowView(row: row)],
                      ),
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
      await tester.pump(const Duration(milliseconds: 300));
    }

    const thought = '用户要给页面加深色模式。先看看现有的样式文件怎么组织的，再决定是另起一份 dark.css 还是用 CSS 变量。\n\n看起来 style.css 很短，用变量更干净。';

    testWidgets('思考过程：正在想是一行“正在思考…”带秒数；想完折成“思考了 N 秒”，点开看全文 ($suffix)', (tester) async {
      await bootEnv(tester);
      // 还在想
      await showRows(tester, [const UserItem('加个深色模式'), ThinkingItem('用户要给页面加深色模式。', streaming: true, startedAt: DateTime.now().subtract(const Duration(seconds: 4)))], busy: true);
      expect(find.textContaining(RegExp(r'正在思考… \d+ 秒')), findsOneWidget); // 机器慢时不一定正好 4 秒
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.textContaining('用户要给页面'), findsNothing, reason: '不点开不显示全文');
      await shot(tester, '90-thinking-live-$suffix');

      // 想完了、后面跟着工具和回答
      await tester.pumpWidget(const SizedBox());
      await showRows(tester, const [
        UserItem('加个深色模式'),
        ThinkingItem(thought, ms: 5300),
        ToolItem('c1', 'read_file', '{"path":"style.css"}', result: 'body { color: #222; }'),
        ToolItem('c2', 'write_file', '{"path":"style.css","content":":root{}"}', result: '已写入 style.css'),
        ThinkingItem('改好了，告诉用户怎么切换。', ms: 900),
        AssistantItem('已经加好深色模式，右上角有切换按钮。'),
      ]);
      // 折叠：步骤组一行 + 回答前的思考一行 + 回答；组里的思考不露出来
      expect(find.text('执行了 2 步 · 读 1 个文件 · 改 1 个文件'), findsOneWidget);
      expect(find.text('思考了 5 秒'), findsNothing);
      expect(find.text('思考了不到 1 秒'), findsOneWidget);
      await shot(tester, '91-thinking-folded-$suffix');
      // 展开步骤组：思考是清单里的一行，点开看全文
      await tester.tap(find.byKey(const ValueKey('step-group-c1')));
      await tester.pumpAndSettle();
      expect(find.text('思考了 5 秒'), findsOneWidget);
      await tester.tap(find.text('思考了 5 秒'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('thinking-text')), findsOneWidget);
      expect(find.textContaining('用变量更干净'), findsOneWidget);
      await shot(tester, '92-thinking-open-$suffix');
      await tester.tap(find.text('思考了 5 秒'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('thinking-text')), findsNothing);

      // 设置里关了：完全不出现
      await tester.pumpWidget(const SizedBox());
      await showRows(tester, const [UserItem('hi'), ThinkingItem(thought, ms: 5300), AssistantItem('你好')], showThinking: false);
      expect(find.byType(ThinkingRow), findsNothing);
      // 旧记录没存用时：只写“思考过程”
      await tester.pumpWidget(const SizedBox());
      await showRows(tester, const [UserItem('hi'), ThinkingItem(thought), AssistantItem('你好')]);
      expect(find.text('思考过程'), findsOneWidget);
    });

    test('想了多久的写法 ($suffix)', () {
      expect(formatThinkingSpan(300), '不到 1 秒');
      expect(formatThinkingSpan(1400), '1 秒');
      expect(formatThinkingSpan(59400), '59 秒');
      expect(formatThinkingSpan(65000), '1 分 5 秒');
    });

    testWidgets('已压缩较早的对话：安静的一行，点开看摘要 ($suffix)', (tester) async {
      await bootEnv(tester);
      await showRows(tester, const [
        UserItem('先做登录页'),
        AssistantItem('登录页做好了。'),
        CompactionItem('用户在做一个小站：登录页已完成（login.html、login.css）；接下来要做首页，要求深色模式、右上角切换按钮。约定：不引入外部库。'),
        UserItem('接着做首页'),
        AssistantItem('好的，开始做首页。'),
      ]);
      expect(find.text('已压缩较早的对话'), findsOneWidget);
      expect(find.byKey(const ValueKey('compaction-summary')), findsNothing);
      await shot(tester, '93-compacted-$suffix');
      await tester.tap(find.byKey(const ValueKey('compaction-row')));
      await tester.pumpAndSettle();
      expect(find.textContaining('不引入外部库'), findsOneWidget);
      expect(find.textContaining('不再占上下文'), findsOneWidget);
      await shot(tester, '94-compacted-open-$suffix');
      await tester.tap(find.byKey(const ValueKey('compaction-row')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('compaction-summary')), findsNothing);
    });

    testWidgets('上一轮没正常结束：一张卡说清楚停在哪，“不用了 / 继续”；只读页面里没有按钮 ($suffix)', (tester) async {
      await bootEnv(tester);
      final taps = <String>[];
      const cut = InterruptedItem(
        headline: '上一轮在第 3 步时中断了（App 被关掉或被系统回收）',
        lines: ['当时你说的是：“装依赖然后跑测试”', '已经执行完 2 步：', '· 读取 package.json', '· 写入 a.js', '“执行 npm install”这条命令当时正在跑：它可能没执行完，只执行了一半。', '不会自动重做任何一步。点“继续”会让 Agent 从这里接着做；点“不用了”就停在这里。'],
        risky: true,
      );
      await showRows(tester, const [UserItem('装依赖然后跑测试'), cut], onResume: () => taps.add('resume'), onDismiss: () => taps.add('dismiss'));
      expect(find.byKey(const ValueKey('interrupted-card')), findsOneWidget);
      expect(find.textContaining('第 3 步'), findsOneWidget);
      expect(find.textContaining('只执行了一半'), findsOneWidget);
      expect(find.byType(FilledButton), findsOneWidget, reason: '只有“继续”一个实心主按钮');
      expect(find.widgetWithText(FilledButton, '继续'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, '不用了'), findsOneWidget);
      await shot(tester, '95-interrupted-$suffix');
      await tester.tap(find.text('不用了'));
      await tester.tap(find.text('继续'));
      expect(taps, ['dismiss', 'resume']);

      await tester.pumpWidget(const SizedBox());
      await showRows(tester, const [UserItem('装依赖然后跑测试'), cut]);
      expect(find.byKey(const ValueKey('interrupted-card')), findsOneWidget);
      expect(find.text('继续'), findsNothing);
    });

    testWidgets('命令输出被转存：步骤详情里有“查看完整输出”，点开是整页；文件被清掉了说清楚 ($suffix)', (tester) async {
      await bootEnv(tester);
      final full = bigOutput(400);
      final result = '退出码 0\n${spilledOutputText(full, '.lopicode/outputs/cmd-20261124073000-0.txt')}';
      final asked = <String>[];
      String? stored = '\$ npm test\n\n$full';
      await showRows(
        tester,
        [const UserItem('跑测试'), ToolItem('c1', 'run_command', '{"command":"npm test"}', result: result), const AssistantItem('跑完了。')],
        readOutput: (rel) async {
          asked.add(rel);
          return stored;
        },
      );
      await tester.tap(find.byKey(const ValueKey('step-c1')));
      await tester.pumpAndSettle();
      expect(find.text('查看完整输出'), findsOneWidget);
      await shot(tester, '96-output-spilled-$suffix');
      await tester.ensureVisible(find.text('查看完整输出'));
      await tester.tap(find.text('查看完整输出'));
      await tester.pumpAndSettle();
      expect(asked, ['.lopicode/outputs/cmd-20261124073000-0.txt']);
      expect(find.text('完整输出'), findsOneWidget);
      expect(find.byKey(const ValueKey('output-full-text')), findsOneWidget);
      expect(find.textContaining('line 200 '), findsOneWidget, reason: '中间被省略的部分在这里看得到');
      await shot(tester, '97-output-full-$suffix');
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      stored = null;
      await tester.tap(find.text('查看完整输出'));
      await tester.pumpAndSettle();
      expect(find.textContaining('已经不在了'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      // 普通结果、或者页面没给读取入口：没有这个链接
      await tester.pumpWidget(const SizedBox());
      await showRows(tester, [const UserItem('跑测试'), ToolItem('c1', 'run_command', '{"command":"npm test"}', result: result), const AssistantItem('跑完了。')]);
      await tester.tap(find.byKey(const ValueKey('step-c1')));
      await tester.pumpAndSettle();
      expect(find.text('查看完整输出'), findsNothing);
    });

    testWidgets('“要继续吗”卡：只有“继续 / 停止”，没有“其他回答” ($suffix)', (tester) async {
      await bootEnv(tester);
      final answers = <String>[];
      await showRows(
        tester,
        [const UserItem('把所有页面都检查一遍'), for (var i = 0; i < 30; i++) ToolItem('c$i', 'read_file', '{"path":"page$i.html"}', result: 'ok')],
        busy: true,
        below: [
          QuestionCard(
            question: PendingQuestion('这一轮已经连着执行了 30 步，还没做完。要继续吗？', const [kContinueAnswer, kStopAnswer], title: '要继续吗？', choiceOnly: true),
            onAnswer: answers.add,
          ),
        ],
      );
      expect(find.text('要继续吗？'), findsOneWidget);
      expect(find.textContaining('30 步'), findsWidgets);
      expect(find.text('其他回答'), findsNothing);
      expect(find.byType(TextField), findsNothing);
      await shot(tester, '98-step-limit-ask-$suffix');
      await tester.tap(find.widgetWithText(OutlinedButton, '继续'));
      await tester.tap(find.widgetWithText(OutlinedButton, '停止'));
      expect(answers, [kContinueAnswer, kStopAnswer]);
    });

    testWidgets('设置：显示思考过程（对话显示页）、自动压缩（写明代价）与步数上限（权限与执行页，底部弹层选档） ($suffix)', (tester) async {
      await bootEnv(tester);
      late Project project;
      await tester.runAsync(() async => project = await env.services.projects.create('我的小站', ProjectTemplate.web));
      await tester.pumpWidget(
        appFor(
          env,
          SettingsScreen(workspace: project),
          mode: mode,
          font: kTestFont,
        ),
      );
      await settle(tester);
      final list = find.byType(Scrollable).first;
      // 显示思考过程在 设置 › 界面 › 对话显示
      await tester.scrollUntilVisible(find.byKey(const Key('settings-chat')), 120, scrollable: list);
      await tester.ensureVisible(find.byKey(const Key('settings-chat')));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byKey(const Key('settings-chat')));
      await tester.pumpAndSettle();
      expect(find.text('显示思考过程'), findsOneWidget);
      expect(tester.widget<Switch>(find.byKey(const Key('settings-thinking'))).value, isTrue);
      await shot(tester, '99-settings-chat-$suffix');
      await tester.tap(find.byKey(const Key('settings-thinking')));
      await settle(tester, rounds: 2);
      expect(env.services.settings.getBool(SettingKeys.chatThinking, true), isFalse);
      expect(tester.widget<Switch>(find.byKey(const Key('settings-thinking'))).value, isFalse);
      await tester.tap(find.byTooltip('返回').last);
      await tester.pumpAndSettle();

      // 自动压缩、步数上限在 设置 › Agent › 权限与执行
      await tester.scrollUntilVisible(find.byKey(const Key('settings-agent')), -120, scrollable: list);
      await tester.ensureVisible(find.byKey(const Key('settings-agent')));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byKey(const Key('settings-agent')));
      await tester.pumpAndSettle();
      expect(find.text('上下文快满时自动压缩'), findsOneWidget);
      expect(find.textContaining('会多调用一次模型、多花一点额度'), findsOneWidget);
      expect(find.text('连续执行多少步后问我'), findsOneWidget);
      expect(find.text('30 步'), findsOneWidget);
      // 默认都开
      expect(tester.widget<Switch>(find.byKey(const Key('settings-auto-compact'))).value, isTrue);
      await shot(tester, '99a-settings-agent-$suffix');

      await tester.tap(find.byKey(const Key('settings-auto-compact')));
      await settle(tester, rounds: 2);
      expect(env.services.settings.getBool(SettingKeys.agentAutoCompact, true), isFalse);
      expect(tester.widget<Switch>(find.byKey(const Key('settings-auto-compact'))).value, isFalse);

      await tester.tap(find.byKey(const Key('settings-step-limit')));
      await tester.pumpAndSettle();
      expect(find.text('30 步（默认）'), findsOneWidget);
      for (final n in kStepLimitChoices) {
        expect(find.byKey(Key('step-limit-$n')), findsOneWidget);
      }
      await shot(tester, '99b-step-limit-sheet-$suffix');
      await tester.tap(find.byKey(const Key('step-limit-50')));
      await settle(tester, rounds: 2);
      expect(env.services.settings.get<int>(SettingKeys.agentMaxSteps), 50);
      expect(find.text('50 步'), findsOneWidget);
    });

    testWidgets('对话页整条链路：思考 → 步骤 → 到上限问 → 继续 → 做完；重新打开思考还在；关掉设置就不显示 ($suffix)', (tester) async {
      late Project project;
      late ProjectSession session;
      var n = 0;
      await bootEnv(
        tester,
        turn: (m, t) {
          n++;
          if (n <= 12) {
            return [
              ChatDelta(reasoning: '第 $n 步前想一想'),
              call(0, 'list_files', jsonEncode({'n': n})),
              ChatDelta(finishReason: 'tool_calls'),
            ];
          }
          return [ChatDelta(reasoning: '可以收尾了'), say('全部检查完了。'), ChatDelta(usage: const TokenUsage(uncached: 100, output: 10)), ChatDelta(finishReason: 'stop')];
        },
      );
      await tester.runAsync(() async {
        await env.services.settings.set(SettingKeys.agentMaxSteps, 10);
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
      await tester.enterText(find.byType(TextField), '把所有文件检查一遍');
      await tester.pump();
      await tester.tap(find.byTooltip('发送'));
      await waitReal(tester, () => session.pendingQuestion != null, what: '到上限的询问');
      expect(find.text('要继续吗？'), findsOneWidget);
      expect(find.textContaining('已经连着执行了 10 步'), findsOneWidget);
      expect(find.text('其他回答'), findsNothing);
      await shot(tester, '100-chat-step-limit-$suffix');
      await tester.tap(find.widgetWithText(OutlinedButton, '继续'));
      await waitReal(tester, () => !session.agentBusy, what: '这一轮结束');
      expect(find.text('全部检查完了。'), findsOneWidget);
      expect(find.textContaining('执行了 12 步'), findsOneWidget);
      // 回答前的那段思考：一行
      expect(find.byType(ThinkingRow), findsOneWidget);
      expect(find.textContaining('思考了'), findsOneWidget);
      await shot(tester, '101-chat-thinking-done-$suffix');

      // 重新打开：思考从存盘的记录里重建
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
      expect(find.byType(ThinkingRow), findsOneWidget);
      expect(find.byKey(const ValueKey('interrupted-card')), findsNothing, reason: '正常结束的不提示');
      await tester.tap(find.byType(ThinkingRow));
      await tester.pumpAndSettle();
      expect(find.text('可以收尾了'), findsOneWidget);

      // 设置里关掉“显示思考过程”：立刻不显示
      await tester.runAsync(() => env.services.settings.set(SettingKeys.chatThinking, false));
      await settle(tester, rounds: 2);
      expect(find.byType(ThinkingRow), findsNothing);
      expect(find.text('全部检查完了。'), findsOneWidget);
    });

    testWidgets('对话页：上一轮被关掉 → 打开就看到提示卡；点“不用了”收掉 ($suffix)', (tester) async {
      late Project project;
      late ProjectSession session;
      await bootEnv(tester, turn: (m, t) => reply('好的。'));
      await tester.runAsync(() async {
        project = await env.services.projects.create('我的小站', ProjectTemplate.web);
        final dir = Directory('${project.dir}/.lopicode')..createSync(recursive: true);
        File('${dir.path}/chat.json').writeAsStringSync(
          jsonEncode([
            {'role': 'user', 'content': '装依赖然后跑测试'},
            {
              'role': 'assistant',
              'content': '',
              'tool_calls': [
                {
                  'id': 'c1',
                  'type': 'function',
                  'function': {'name': 'read_file', 'arguments': '{"path":"package.json"}'},
                },
              ],
            },
            {'role': 'tool', 'tool_call_id': 'c1', 'content': '{}'},
            {
              'role': 'assistant',
              'content': '',
              'tool_calls': [
                {
                  'id': 'c2',
                  'type': 'function',
                  'function': {'name': 'run_command', 'arguments': '{"command":"npm install"}'},
                },
              ],
            },
          ]),
        );
        final journal = TurnJournal(token: 'old', startedAt: DateTime(2026, 11, 24, 15), text: '装依赖然后跑测试')
          ..steps.addAll([JournalStep('c1', 'read_file', '{"path":"package.json"}', done: true), JournalStep('c2', 'run_command', '{"command":"npm install"}')]);
        File('${dir.path}/turn.json').writeAsStringSync(jsonEncode(journal.toJson()));
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
      expect(find.byKey(const ValueKey('interrupted-card')), findsOneWidget);
      expect(find.textContaining('第 2 步'), findsOneWidget);
      expect(find.textContaining('只执行了一半'), findsOneWidget);
      expect(find.text('处理中…'), findsNothing);
      await shot(tester, '102-chat-interrupted-$suffix');
      await tester.tap(find.byKey(const ValueKey('interrupted-dismiss')));
      await settle(tester, rounds: 3);
      expect(find.byKey(const ValueKey('interrupted-card')), findsNothing);
      expect(session.agentBusy, isFalse);
    });
  }
}
