// 第 11 条：ask_user 一次多问、多选；确认卡“拒绝”时可以写一句原因。
// 单元（读参数、整理回答）+ 会话（工具结果、安全语义）+ 假模型服务器（真实 HTTP 请求体）+ 390×844 界面（浅色 / 深色）。不联网。
//   LOPI_SHOTS=1 flutter test test/ask_multi_test.dart   # 同时写截图到 docs/screenshots/（ap11-…）
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/agent/agent_runner.dart';
import 'package:lopicode/agent/agent_tools.dart';
import 'package:lopicode/agent/chat_client.dart';
import 'package:lopicode/agent/loop_guard.dart';
import 'package:lopicode/core/path_guard.dart';
import 'package:lopicode/core/project_store.dart';
import 'package:lopicode/core/templates.dart';
import 'package:lopicode/project_session.dart';
import 'package:lopicode/session/ask_user.dart';
import 'package:lopicode/session/chat_rows.dart';
import 'package:lopicode/ui/chat_cards.dart';
import 'package:lopicode/ui/chat_question_multi.dart';
import 'package:lopicode/ui/project_shell.dart';
import 'package:material_ui/material_ui.dart';

import 'agent_test.dart' show RecordingRunner;
import 'agent_ui_test.dart' show waitReal;
import 'screens_test.dart' show shot, fontsLoaded;
import 'session_system_test.dart' show RoutingClient, Turn, reply, use, waitFor, toolResults;
import 'support/fake_model_server.dart';
import 'support/harness.dart';

const _three = {
  'questions': [
    {
      'question': '主页用什么配色？',
      'options': ['浅色、简洁', '深色、科技感', '跟着系统走'],
    },
    {
      'question': '要哪些页面？',
      'options': ['首页', '关于', '作品集', '联系方式'],
      'multiple': true,
    },
    {'question': '网站叫什么名字？'},
  ],
};

void main() {
  setUpAll(() async => fontsLoaded = await loadRealFonts());

  group('读参数', () {
    test('旧写法（question + options）：一个单选问题', () {
      final plan = parseAskArgs({
        'question': ' 用哪个？ ',
        'options': ['甲', '乙', '甲', '', 3],
      });
      expect(plan.dropped, 0);
      expect(plan.parts.single.question, '用哪个？');
      expect(plan.parts.single.options, ['甲', '乙'], reason: '去重、去空、去掉不是文字的');
      expect(plan.parts.single.multiple, isFalse);
    });

    test('新写法（questions）：单选 / 多选 / 没选项；也认只写一句话的', () {
      final plan = parseAskArgs({..._three, 'question': '被忽略的旧写法'});
      expect(plan.parts.map((q) => q.question).toList(), ['主页用什么配色？', '要哪些页面？', '网站叫什么名字？']);
      expect(plan.parts.map((q) => q.multiple).toList(), [false, true, false]);
      expect(plan.parts[2].options, isEmpty);
      expect(
        parseAskArgs({
          'questions': ['直接一句话'],
        }).parts.single.question,
        '直接一句话',
      );
    });

    test('上限：最多 $kAskMaxQuestions 个问题、每个最多 $kAskMaxOptions 个选项；多出来的数得出来', () {
      final plan = parseAskArgs({
        'questions': [
          for (var i = 1; i <= 6; i++)
            {
              'question': '问题 $i',
              'options': [for (var j = 1; j <= 9; j++) '选项 $j'],
            },
        ],
      });
      expect(plan.parts, hasLength(4));
      expect(plan.dropped, 2);
      expect(plan.parts.first.options, hasLength(6));
    });

    test('坏参数不崩：类型不对的条目跳过；questions 是空的就退回旧写法；什么都没有报清楚', () {
      expect(
        parseAskArgs({
          'questions': [
            1,
            null,
            {'question': ''},
            {
              'options': ['a'],
            },
            {'question': '好的', 'options': '不是列表', 'multiple': 'yes'},
          ],
        }).parts.single.options,
        isEmpty,
      );
      expect(parseAskArgs({'questions': <Object>[], 'question': '旧的'}).parts.single.question, '旧的');
      expect(parseAskArgs({'questions': '不是列表', 'question': '旧的'}).parts.single.question, '旧的');
      for (final bad in [
        <String, dynamic>{},
        {'question': '  '},
        {'questions': <Object>[]},
        {'question': 5},
      ]) {
        expect(() => parseAskArgs(bad), throwsA(isA<ToolArgError>()), reason: '$bad');
      }
    });

    test('整理回答：按选项原来的顺序；多选用“；”隔开；自己写的单独标出；没答写明', () {
      final parts = parseAskArgs(_three).parts;
      final text = formatAnswers(parts, [
        (picked: ['深色、科技感'], written: ''),
        (picked: ['作品集', '首页', '不在选项里的'], written: ' 还要一个博客 '),
        (picked: <String>[], written: '霜霜的小站'),
      ]);
      expect(
        text,
        '1. 主页用什么配色？\n   回答：深色、科技感\n'
        '2. 要哪些页面？\n   回答：首页；作品集；用户另外写的：还要一个博客\n'
        '3. 网站叫什么名字？\n   回答：霜霜的小站',
      );
      expect(formatAnswers(parts.take(1).toList(), const []), contains('（用户没有回答）'));
    });

    test('步骤列表里的摘要；工具定义里两种写法都在', () {
      expect(stepLabel('ask_user', jsonEncode(_three)), ('向你提问', '3 个问题：主页用什么配色？'));
      expect(stepLabel('ask_user', '{"question":"用哪个？"}'), ('向你提问', '用哪个？'));
      expect(askSummary(const {}), '');
      final props = ((askUserSpec()['function'] as Map)['parameters'] as Map)['properties'] as Map;
      expect(props.keys, containsAll(['questions', 'question', 'options']));
    });

    test('拒绝原因：没写是空串；空白压成一个空格；超过 $kDenyReasonMaxChars 字截断', () {
      final r = ApprovalRequest(tool: 'run_command', title: '执行命令', detail: 'ls');
      expect(r.denyNote, '');
      r.denyReason = '   ';
      expect(r.denyNote, '');
      r.denyReason = ' 别动\n\n线上库 ';
      expect(r.denyNote, '用户写的原因：别动 线上库');
      r.denyReason = '啊' * 300;
      expect(r.denyNote, '用户写的原因：${'啊' * 200}…');
    });
  });

  group('会话', () {
    late TestEnv env;
    late Project project;
    late ProjectSession session;
    late RecordingRunner shell;
    late List<({List<Map<String, dynamic>> messages, List<String> tools})> log;
    Turn turn = (_, _) => reply('好的。');

    setUp(() async {
      log = [];
      env = await TestEnv.create(chatClient: () => RoutingClient((m, t) => turn(m, t), log));
      project = await env.services.projects.create('测试工作区', ProjectTemplate.web);
      session = ProjectSession(env.services, project, headless: true);
      shell = RecordingRunner();
      session.commandRunnerFactory = () => shell;
      await session.loadChat();
    });
    tearDown(() async {
      session.dispose();
      await env.dispose();
    });
    File f(String rel) => File('${project.dir}/$rel');

    test('旧写法照常：还是原来那张卡（没有分页），回话还是“用户的回答：…”', () async {
      var n = 0;
      turn = (m, t) => n++ == 0
          ? use('ask_user', {
              'question': '用哪个配色？',
              'options': ['蓝色', '绿色'],
            })
          : reply('好。');
      final done = session.sendToAgent('做个主页');
      await waitFor(() => session.pendingQuestion != null, what: '提问卡');
      expect(session.pendingQuestion!.parts, isEmpty);
      expect(session.pendingQuestion!.options, ['蓝色', '绿色']);
      session.answerQuestion('绿色');
      await done;
      expect(toolResults(log[1].messages), '用户的回答：绿色');
    });

    test('新写法只带一个单选问题：也走原来那张卡', () async {
      var n = 0;
      turn = (m, t) => n++ == 0
          ? use('ask_user', {
              'questions': [
                {
                  'question': '用哪个配色？',
                  'options': ['蓝色', '绿色'],
                },
              ],
            })
          : reply('好。');
      final done = session.sendToAgent('做个主页');
      await waitFor(() => session.pendingQuestion != null, what: '提问卡');
      expect(session.pendingQuestion!.parts, isEmpty);
      expect(session.pendingQuestion!.question, '用哪个配色？');
      session.answerQuestion('蓝色');
      await done;
      expect(toolResults(log[1].messages), '用户的回答：蓝色');
    });

    test('一次三个问题：只出一张卡，回答一起交回模型', () async {
      var n = 0;
      turn = (m, t) => n++ == 0 ? use('ask_user', _three) : reply('好。');
      final done = session.sendToAgent('做个主页');
      await waitFor(() => session.pendingQuestion != null, what: '提问卡');
      final q = session.pendingQuestion!;
      expect(q.parts, hasLength(3));
      expect(q.parts[1].multiple, isTrue);
      session.answerQuestion(
        formatAnswers(q.parts, [
          (picked: ['浅色、简洁'], written: ''),
          (picked: ['首页', '关于'], written: ''),
          (picked: <String>[], written: '小站'),
        ]),
      );
      await done;
      expect(session.pendingQuestion, isNull);
      expect(toolResults(log[1].messages), '用户的回答：\n1. 主页用什么配色？\n   回答：浅色、简洁\n2. 要哪些页面？\n   回答：首页；关于\n3. 网站叫什么名字？\n   回答：小站');
    });

    test('只有一个问题但是多选：走新卡', () async {
      var n = 0;
      turn = (m, t) => n++ == 0
          ? use('ask_user', {
              'question': '要哪些？',
              'options': ['甲', '乙'],
              'multiple': true,
            })
          : reply('好。');
      final done = session.sendToAgent('问');
      await waitFor(() => session.pendingQuestion != null, what: '提问卡');
      expect(session.pendingQuestion!.parts.single.multiple, isTrue);
      session.answerQuestion('x');
      await done;
    });

    test('问了 6 个：只问前 4 个，并告诉模型后面 2 个没问', () async {
      var n = 0;
      turn = (m, t) => n++ == 0
          ? use('ask_user', {
              'questions': [for (var i = 1; i <= 6; i++) '问题 $i'],
            })
          : reply('好。');
      final done = session.sendToAgent('问');
      await waitFor(() => session.pendingQuestion != null, what: '提问卡');
      expect(session.pendingQuestion!.parts, hasLength(4));
      session.answerQuestion('都行');
      await done;
      expect(toolResults(log[1].messages), contains('一次最多问 4 个问题，后面的 2 个没有问'));
    });

    test('参数里一个问题都没有：工具报错，不弹卡、不卡住', () async {
      var n = 0;
      turn = (m, t) => n++ == 0 ? use('ask_user', {'questions': <Object>[]}) : reply('好。');
      await session.sendToAgent('问');
      expect(session.pendingQuestion, isNull);
      expect(toolResults(log[1].messages), contains('缺少要问的问题'));
    });

    test('拒绝并写原因：命令没跑；模型看到“用户拒绝……”后面跟着原因；仍然算被拒绝', () async {
      var n = 0;
      turn = (m, t) => n++ == 0 ? use('run_command', {'command': 'npm run deploy'}) : reply('明白，不部署。');
      final done = session.sendToAgent('收个尾');
      await waitFor(() => session.pendingApproval != null, what: '确认卡');
      session.rejectApproval('  先别部署，\n我还没看过改动 ');
      await done;
      expect(shell.commands, isEmpty, reason: '拒绝＝不执行');
      expect(toolResults(log[1].messages), '用户拒绝执行这条命令，命令没有运行。用户写的原因：先别部署， 我还没看过改动');
      final step = session.chat.whereType<ToolItem>().single;
      expect(step.ok, isFalse);
      expect(step.denied, isTrue);
      expect(session.autoAllowActive, isFalse);
    });

    test('拒绝不写原因 / 原因是空的：和以前一字不差', () async {
      var n = 0;
      turn = (m, t) => switch (n++) {
        0 => use('run_command', {'command': 'ls'}),
        1 => use('delete_file', {'path': 'index.html'}),
        _ => reply('好。'),
      };
      final done = session.sendToAgent('看看');
      await waitFor(() => session.pendingApproval != null, what: '第一张确认卡');
      session.resolveApproval(false);
      await waitFor(() => session.pendingApproval?.request.tool == 'delete_file', what: '第二张确认卡');
      session.rejectApproval('   ');
      await done;
      expect(toolResults(log[1].messages), '用户拒绝执行这条命令，命令没有运行。');
      expect(toolResults(log[2].messages).split('\n').last, '用户拒绝了这次删除，文件没有被改动。');
      expect(f('index.html').existsSync(), isTrue);
      expect(shell.commands, isEmpty);
    });

    test('删除被拒绝并写原因：文件还在，原因带给模型', () async {
      var n = 0;
      turn = (m, t) => n++ == 0 ? use('delete_file', {'path': 'index.html'}) : reply('好。');
      final done = session.sendToAgent('删');
      await waitFor(() => session.pendingApproval != null, what: '确认卡');
      session.rejectApproval('这个文件还要用');
      await done;
      expect(f('index.html').existsSync(), isTrue);
      expect(toolResults(log[1].messages), '用户拒绝了这次删除，文件没有被改动。用户写的原因：这个文件还要用');
    });

    test('重复失败拦截不变：带原因拒绝也算一次失败——同一条命令被拒两次后，第三次不再弹卡、不执行', () async {
      var n = 0;
      turn = (m, t) => n++ < 3 ? use('run_command', {'command': 'rm -rf build'}) : reply('不试了。');
      final done = session.sendToAgent('清理');
      for (var i = 1; i < kRepeatFailLimit; i++) {
        await waitFor(() => session.pendingApproval != null, what: '第 $i 张确认卡');
        final card = session.pendingApproval;
        session.rejectApproval('不许删 $i');
        await waitFor(() => !identical(session.pendingApproval, card) && log.length > i, what: '第 $i 次拒绝交回');
      }
      await done;
      expect(session.pendingApproval, isNull);
      expect(shell.commands, isEmpty);
      expect(toolResults(log[3].messages).split('\n').last, contains('这一次没有执行'));
    });

    test('“本对话都允许”不受影响：写了原因再点拒绝，不会变成允许，也不会打开自动允许', () async {
      var n = 0;
      turn = (m, t) => n++ < 2 ? use('run_command', {'command': 'ls $n'}) : reply('好。');
      final done = session.sendToAgent('看两次');
      await waitFor(() => session.pendingApproval != null, what: '第一张确认卡');
      session.rejectApproval('先不看');
      await waitFor(() => session.pendingApproval != null && log.length == 2, what: '第二张确认卡');
      expect(session.autoAllowActive, isFalse);
      expect(session.pendingApproval!.request.denyReason, isNull, reason: '上一张卡的原因不会带到下一张');
      session.resolveApproval(true);
      await done;
      expect(shell.commands, hasLength(1));
    });
  });

  group('假模型服务器（真实 HTTP 请求体）', () {
    late Directory tmp;
    FakeModelServer? server;
    // 界面测试默认把所有网络请求挡成 400；这里要连本机的假服务，放开（只会连 127.0.0.1）。
    setUp(() {
      HttpOverrides.global = null;
      tmp = Directory.systemTemp.createTempSync('lopi_ask_');
    });
    tearDown(() async {
      await server?.stop();
      server = null;
      tmp.deleteSync(recursive: true);
    });

    test('拒绝原因在发给模型的 tool 消息里；命令没有执行', () async {
      server = FakeModelServer([
        ScriptedReply(calls: [ScriptedCall('run_command', '{"command":"git push -f"}', id: 'c1')]),
        ScriptedReply(text: '好的，不推。'),
      ]);
      await server!.start();
      final shell = RecordingRunner();
      final box = AgentToolbox(
        guard: PathGuard(tmp.path),
        runner: shell,
        requestApproval: (r) async {
          r.denyReason = '不要强推，会覆盖远程';
          return false;
        },
        autoApprove: () => false,
      );
      final runner = AgentRunner(
        client: OpenAiChatClient(baseUrl: server!.baseUrl, apiKey: 'sk-test-key', model: 'fake'),
        toolbox: box,
        retryDelayOf: (_) => Duration.zero,
      );
      await runner.send('推一下').toList();
      final messages = server!.requests[1]['messages'] as List;
      final tool = (messages.last as Map).cast<String, dynamic>();
      expect(tool['role'], 'tool');
      expect(tool['tool_call_id'], 'c1');
      expect(tool['content'], '用户拒绝执行这条命令，命令没有运行。用户写的原因：不要强推，会覆盖远程');
      expect(shell.commands, isEmpty);
    });

    test('ask_user 的工具定义发给模型时带 questions（数组）和旧的 question / options', () async {
      server = FakeModelServer([ScriptedReply(text: '好。')]);
      await server!.start();
      final box = AgentToolbox(
        guard: PathGuard(tmp.path),
        runner: RecordingRunner(),
        requestApproval: (_) async => false,
        autoApprove: () => false,
        extras: [ExtraTool(spec: askUserSpec(), kind: ToolKind.other, run: (_) async => ToolOutcome('x'))],
      );
      await AgentRunner(
        client: OpenAiChatClient(baseUrl: server!.baseUrl, apiKey: 'sk-test-key', model: 'fake'),
        toolbox: box,
      ).send('hi').toList();
      final tools = [for (final t in server!.requests.single['tools'] as List) ((t as Map)['function'] as Map)];
      final ask = tools.singleWhere((t) => t['name'] == 'ask_user');
      final props = (ask['parameters'] as Map)['properties'] as Map;
      expect((props['questions'] as Map)['type'], 'array');
      expect(props.keys, containsAll(['question', 'options']));
      expect((ask['parameters'] as Map)['required'] ?? const <Object>[], isEmpty, reason: '两种写法二选一，都不是必填');
    });
  });

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    final suffix = mode == ThemeMode.light ? 'light' : 'dark';

    Future<({TestEnv env, ProjectSession session, List<({List<Map<String, dynamic>> messages, List<String> tools})> log})> open(WidgetTester tester, Turn turn) async {
      usePhoneViewport(tester);
      late TestEnv env;
      late Project project;
      late ProjectSession session;
      final log = <({List<Map<String, dynamic>> messages, List<String> tools})>[];
      await tester.runAsync(() async {
        env = await TestEnv.create(chatClient: () => RoutingClient(turn, log));
        project = await env.services.projects.create('我的小站', ProjectTemplate.web);
        session = ProjectSession(env.services, project)..commandRunnerFactory = RecordingRunner.new;
        await session.loadChat();
      });
      addTearDown(() async {
        session.dispose();
        await env.dispose();
      });
      await tester.pumpWidget(
        appFor(
          env,
          ProjectShell(project: project, session: session),
          mode: mode,
          font: fontsLoaded ? kTestFont : null,
        ),
      );
      await settle(tester, rounds: 6);
      return (env: env, session: session, log: log);
    }

    Future<void> say(WidgetTester tester, String text) async {
      await tester.enterText(find.byType(TextField).last, text);
      await tester.pump();
      await tester.tap(find.byTooltip('发送'));
    }

    testWidgets('多问卡：一页一问，单选 → 多选 → 自己写，能回上一个改，最后一起提交 ($suffix)', (tester) async {
      var n = 0;
      final o = await open(tester, (m, t) => n++ == 0 ? use('ask_user', _three) : reply('收到，开始做。'));
      await say(tester, '帮我做个个人主页');
      await waitReal(tester, () => o.session.pendingQuestion != null, what: '提问卡');
      await settle(tester, rounds: 3);
      expect(find.byType(MultiQuestionCard), findsOneWidget);
      expect(find.byType(QuestionCard), findsNothing);
      expect(find.text('主页用什么配色？'), findsOneWidget);
      expect(find.text('要哪些页面？'), findsNothing, reason: '一页只有一个问题');
      expect(tester.widget<Text>(find.byKey(const Key('ask-progress'))).data, contains('1 / 3'));
      expect(find.byKey(const Key('ask-prev')), findsNothing);
      expect(tester.widget<FilledButton>(find.byKey(const Key('ask-next'))).onPressed, isNull, reason: '没答不能往下');
      await shot(tester, 'ap11-01-ask-single-$suffix');

      // 第 1 问：单选，换一个会顶掉前一个
      await tester.tap(find.byKey(const ValueKey('ask-option-浅色、简洁')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('ask-option-深色、科技感')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('ask-next')));
      await settle(tester, rounds: 2);

      // 第 2 问：多选
      expect(find.text('要哪些页面？'), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const Key('ask-progress'))).data, allOf(contains('2 / 3'), contains('可以选多个')));
      await tester.tap(find.byKey(const ValueKey('ask-option-首页')));
      await tester.tap(find.byKey(const ValueKey('ask-option-作品集')));
      await settle(tester, rounds: 3);
      await shot(tester, 'ap11-02-ask-multi-$suffix');
      await tester.tap(find.byKey(const Key('ask-next')));
      await settle(tester, rounds: 2);

      // 第 3 问：没有选项，只能自己写
      expect(find.text('网站叫什么名字？'), findsOneWidget);
      expect(find.text('提交'), findsOneWidget);
      expect(tester.widget<FilledButton>(find.byKey(const Key('ask-next'))).onPressed, isNull);
      await tester.enterText(find.byKey(const ValueKey('ask-written-2')), '霜霜的小站');
      await tester.pump();

      // 回上一个：之前勾的还在
      await tester.tap(find.byKey(const Key('ask-prev')));
      await settle(tester, rounds: 2);
      expect(find.text('要哪些页面？'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('ask-option-作品集'))); // 取消一个
      await tester.pump();
      await tester.tap(find.byKey(const Key('ask-next')));
      await settle(tester, rounds: 2);
      await tester.tap(find.byKey(const Key('ask-next')));
      await waitReal(tester, () => n >= 2 && !o.session.agentBusy, what: '答完继续');
      expect(toolResults(o.log[1].messages), '用户的回答：\n1. 主页用什么配色？\n   回答：深色、科技感\n2. 要哪些页面？\n   回答：首页\n3. 网站叫什么名字？\n   回答：霜霜的小站');
      expect(find.byType(MultiQuestionCard), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('多问卡 · 单选题自己写：写了字就不算选项，选了选项就清掉写的 ($suffix)', (tester) async {
      var n = 0;
      final o = await open(
        tester,
        (m, t) => n++ == 0
            ? use('ask_user', {
                'questions': [
                  {
                    'question': '用哪个配色？',
                    'options': ['蓝色', '绿色'],
                  },
                  {
                    'question': '字体呢？',
                    'options': ['黑体', '宋体'],
                    'multiple': true,
                  },
                ],
              })
            : reply('好。'),
      );
      await say(tester, '做个主页');
      await waitReal(tester, () => o.session.pendingQuestion != null, what: '提问卡');
      await settle(tester, rounds: 3);
      await tester.tap(find.byKey(const ValueKey('ask-option-蓝色')));
      await tester.pump();
      await tester.enterText(find.byKey(const ValueKey('ask-written-0')), '橙色');
      await tester.pump();
      await tester.tap(find.byKey(const Key('ask-next')));
      await settle(tester, rounds: 2);
      // 多选题：选项 + 自己写的一起算
      await tester.tap(find.byKey(const ValueKey('ask-option-宋体')));
      await tester.pump();
      await tester.enterText(find.byKey(const ValueKey('ask-written-1')), '标题用圆体');
      await tester.pump();
      await tester.tap(find.byKey(const Key('ask-next')));
      await waitReal(tester, () => n >= 2 && !o.session.agentBusy, what: '答完继续');
      expect(toolResults(o.log[1].messages), '用户的回答：\n1. 用哪个配色？\n   回答：橙色\n2. 字体呢？\n   回答：宋体；用户另外写的：标题用圆体');
      expect(tester.takeException(), isNull);
    });

    testWidgets('多问卡 · 选项最多（6 个）+ 问题很长：只有问题和选项那块滑，“自己写”和按钮一直点得到 ($suffix)', (tester) async {
      var n = 0;
      final o = await open(
        tester,
        (m, t) => n++ == 0
            ? use('ask_user', {
                'questions': [
                  {
                    'question': '这个项目打算部署到哪里？不同的地方打包方式不一样，选错了后面要重来，所以先问清楚再动手。',
                    'options': ['自己的服务器（宝塔面板）', 'Vercel', 'GitHub Pages', 'Cloudflare Pages', '先只在本机预览', '还没想好'],
                    'multiple': true,
                  },
                  '域名是什么？',
                ],
              })
            : reply('好。'),
      );
      await say(tester, '帮我部署');
      await waitReal(tester, () => o.session.pendingQuestion != null, what: '提问卡');
      await settle(tester, rounds: 3);
      await shot(tester, 'ap11-05-ask-six-options-$suffix');
      final next = find.byKey(const Key('ask-next'));
      expect(tester.getRect(next).bottom, lessThan(844));
      await tester.ensureVisible(find.byKey(const ValueKey('ask-option-还没想好')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('ask-option-还没想好')));
      await tester.pump();
      WidgetController.hitTestWarningShouldBeFatal = true;
      addTearDown(() => WidgetController.hitTestWarningShouldBeFatal = false);
      await tester.tap(next);
      await settle(tester, rounds: 2);
      expect(find.text('域名是什么？'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('ask-written-1')), '还没买');
      await tester.pump();
      await tester.tap(next);
      WidgetController.hitTestWarningShouldBeFatal = false;
      await waitReal(tester, () => n >= 2 && !o.session.agentBusy, what: '答完继续');
      expect(toolResults(o.log[1].messages), contains('回答：还没想好\n2. 域名是什么？\n   回答：还没买'));
      expect(tester.takeException(), isNull);
    });

    testWidgets('确认卡 · 拒绝并说明原因：小字入口点开是一行输入 + 取消 / 拒绝；原因带给模型，命令没跑 ($suffix)', (tester) async {
      var n = 0;
      late RecordingRunner shell;
      final o = await open(tester, (m, t) => n++ == 0 ? use('run_command', {'command': 'npm run deploy'}) : reply('明白，先不部署。'));
      o.session.commandRunnerFactory = () => shell = RecordingRunner();
      await say(tester, '收个尾');
      await waitReal(tester, () => o.session.pendingApproval != null, what: '确认卡');
      await settle(tester, rounds: 3);
      // 原来的两个按钮和“本对话都允许”都还在，位置没动
      expect(find.widgetWithText(OutlinedButton, '拒绝'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, '允许这一次'), findsOneWidget);
      expect(find.text('本对话都允许'), findsOneWidget);
      expect(find.byKey(const Key('reject-reason-open')), findsOneWidget);
      await shot(tester, 'ap11-03-approval-with-reason-link-$suffix');

      await tester.tap(find.byKey(const Key('reject-reason-open')));
      await settle(tester, rounds: 2);
      expect(find.byKey(const Key('reject-reason-field')), findsOneWidget);
      expect(find.widgetWithText(FilledButton, '允许这一次'), findsNothing, reason: '写原因时卡上只剩“取消 / 拒绝”，不会误点成允许');
      // 取消：回到原来的样子，卡还在等
      await tester.tap(find.byKey(const Key('reject-reason-cancel')));
      await settle(tester, rounds: 2);
      expect(find.widgetWithText(FilledButton, '允许这一次'), findsOneWidget);
      expect(o.session.pendingApproval, isNotNull);

      await tester.tap(find.byKey(const Key('reject-reason-open')));
      await settle(tester, rounds: 2);
      await tester.enterText(find.byKey(const Key('reject-reason-field')), '先别部署，我还没看过改动');
      await tester.pump();
      await shot(tester, 'ap11-04-reject-reason-form-$suffix');
      await tester.tap(find.byKey(const Key('reject-reason-submit')));
      await waitReal(tester, () => n >= 2 && !o.session.agentBusy, what: '拒绝后继续');
      expect(toolResults(o.log[1].messages), '用户拒绝执行这条命令，命令没有运行。用户写的原因：先别部署，我还没看过改动');
      expect(shell.commands, isEmpty);
      expect(find.byType(ApprovalCard), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('确认卡 · 原因留空直接点拒绝：和点“拒绝”按钮一样 ($suffix)', (tester) async {
      var n = 0;
      final o = await open(tester, (m, t) => n++ == 0 ? use('run_command', {'command': 'ls'}) : reply('好。'));
      await say(tester, '看看');
      await waitReal(tester, () => o.session.pendingApproval != null, what: '确认卡');
      await settle(tester, rounds: 3);
      await tester.tap(find.byKey(const Key('reject-reason-open')));
      await settle(tester, rounds: 2);
      await tester.tap(find.byKey(const Key('reject-reason-submit')));
      await waitReal(tester, () => n >= 2 && !o.session.agentBusy, what: '拒绝后继续');
      expect(toolResults(o.log[1].messages), '用户拒绝执行这条命令，命令没有运行。');
      expect(tester.takeException(), isNull);
    });
  }
}
