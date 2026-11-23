// 会话层的测试（不带界面）：权限 / 计划模式 / 预设在真实会话里的强制、排队 / 插话 / 中断、
// 提问卡、子代理（层数 / 并发 / 允许模型 / 连带删除）、团队写入范围、自动化确认卡与调度、技能与搜索工具。
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/agent/agent_tools.dart';
import 'package:lopicode/agent/automation.dart';
import 'package:lopicode/agent/chat_client.dart';
import 'package:lopicode/agent/model_config.dart';
import 'package:lopicode/agent/team.dart';
import 'package:lopicode/agent/web_search.dart';
import 'package:lopicode/core/project_store.dart';
import 'package:lopicode/core/stores.dart';
import 'package:lopicode/core/templates.dart';
import 'package:lopicode/project_session.dart';

import 'agent_test.dart' show RecordingRunner;
import 'support/harness.dart';

typedef Turn = FutureOr<List<ChatDelta>> Function(List<Map<String, dynamic>> messages, List<String> tools);

/// 每次调用模型都交给 [turn] 决定回什么；记下每次看到的消息和工具名。
class RoutingClient implements ChatClient {
  RoutingClient(this.turn, this.log);
  final Turn turn;
  final List<({List<Map<String, dynamic>> messages, List<String> tools})> log;

  @override
  Stream<ChatDelta> streamChat({required List<Map<String, dynamic>> messages, List<Map<String, dynamic>> tools = const []}) async* {
    final names = [for (final t in tools) (t['function'] as Map)['name'] as String];
    final snapshot = [for (final m in messages) Map<String, dynamic>.from(m)];
    log.add((messages: snapshot, tools: names));
    for (final d in await turn(snapshot, names)) {
      yield d;
    }
  }
}

List<ChatDelta> reply(String text) => [say(text), ChatDelta(finishReason: 'stop')];
List<ChatDelta> use(String name, Map<String, dynamic> args, [int index = 0]) => [call(index, name, jsonEncode(args)), ChatDelta(finishReason: 'tool_calls')];

String lastUser(List<Map<String, dynamic>> messages) => '${messages.lastWhere((m) => m['role'] == 'user')['content']}';
String firstUser(List<Map<String, dynamic>> messages) => '${messages.firstWhere((m) => m['role'] == 'user')['content']}';
bool hasToolResult(List<Map<String, dynamic>> messages) => messages.any((m) => m['role'] == 'tool');
String toolResults(List<Map<String, dynamic>> messages) => messages.where((m) => m['role'] == 'tool').map((m) => '${m['content']}').join('\n');

Future<void> waitFor(bool Function() cond, {String what = '条件'}) async {
  for (var i = 0; i < 400 && !cond(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  if (!cond()) fail('等不到：$what');
}

void main() {
  late TestEnv env;
  late Project project;
  late ProjectSession session;
  late RecordingRunner shell;
  late List<({List<Map<String, dynamic>> messages, List<String> tools})> log;
  Turn turn = (_, _) => reply('好的。');

  Future<void> boot({ProjectTemplate template = ProjectTemplate.web}) async {
    log = [];
    env = await TestEnv.create(chatClient: () => RoutingClient((m, t) => turn(m, t), log));
    project = await env.services.projects.create('测试工作区', template);
    session = ProjectSession(env.services, project, headless: true);
    shell = RecordingRunner();
    session.commandRunnerFactory = () => shell;
    await session.loadChat();
  }

  setUp(() async {
    turn = (_, _) => reply('好的。');
    await boot();
  });
  tearDown(() {
    session.dispose();
    env.dispose();
  });

  File f(String rel) => File('${project.dir}/$rel');

  group('权限在会话里强制', () {
    test('新对话默认权限来自设置；单个对话可改，并且存盘', () async {
      expect(session.permission, PermissionLevel.workspace);
      await env.services.settings.set(SettingKeys.defaultPermission, 'view');
      expect(session.permission, PermissionLevel.view);
      await session.setPermission(PermissionLevel.full);
      expect(session.permission, PermissionLevel.full);
      final again = ProjectSession(env.services, project, headless: true);
      await again.loadChat();
      addTearDown(again.dispose);
      expect(again.permission, PermissionLevel.full);
    });

    test('仅可查看：模型拿不到写工具；硬调用被拒，文件没动、命令没跑、不弹卡', () async {
      await session.setPermission(PermissionLevel.view);
      final before = f('index.html').readAsStringSync();
      var n = 0;
      turn = (m, t) => switch (n++) {
        0 => [
          call(0, 'write_file', jsonEncode({'path': 'index.html', 'content': '被改了'})),
          call(1, 'run_command', jsonEncode({'command': 'rm -rf .'})),
          call(2, 'delete_file', jsonEncode({'path': 'index.html'})),
          ChatDelta(finishReason: 'tool_calls'),
        ],
        _ => reply('改不了。'),
      };
      await session.sendToAgent('把首页删了');
      expect(log.first.tools, isNot(contains('write_file')));
      expect(log.first.tools, isNot(contains('run_command')));
      expect(log.first.tools, isNot(contains('delete_file')));
      expect(log.first.tools, contains('read_file'));
      expect(f('index.html').readAsStringSync(), before);
      expect(shell.commands, isEmpty);
      expect(session.pendingApproval, isNull);
      expect(toolResults(log.last.messages), contains('仅可查看'));
      expect(firstSystem(log.first.messages), contains('仅可查看'));
    });

    test('“本对话都允许”：之后不再问；提示可点关；新会话（重启）恢复逐次询问', () async {
      var n = 0;
      turn = (m, t) => n++ < 2 ? use('run_command', {'command': 'ls'}) : reply('看完了。');
      final done = session.sendToAgent('看两次目录');
      await waitFor(() => session.pendingApproval != null, what: '第一张确认卡');
      expect(session.autoAllowActive, isFalse);
      session.resolveApproval(true, always: true);
      await done;
      expect(shell.commands, ['ls', 'ls'], reason: '第二次没有再问');
      expect(session.autoAllowActive, isTrue);

      session.clearAutoAllow();
      expect(session.autoAllowActive, isFalse);
      n = 1;
      final again = session.sendToAgent('再看一次');
      await waitFor(() => session.pendingApproval != null, what: '关掉后又开始问');
      session.resolveApproval(false);
      await again;
      expect(shell.commands, hasLength(2));

      // 重启：autoAllow 不落盘
      n = 0;
      session.resolveApproval(true); // 没有卡时调用是空操作
      final restarted = ProjectSession(env.services, project, headless: true)..commandRunnerFactory = () => shell;
      await restarted.loadChat();
      addTearDown(restarted.dispose);
      expect(restarted.autoAllowActive, isFalse);
      expect(File('${project.dir}/.lopicode/chats.json').readAsStringSync(), isNot(contains('autoAllow')));
    });

    test('完全权限：命令不再问', () async {
      await session.setPermission(PermissionLevel.full);
      var n = 0;
      turn = (m, t) => n++ == 0 ? use('run_command', {'command': 'ls'}) : reply('好了');
      await session.sendToAgent('看目录');
      expect(shell.commands, ['ls']);
      expect(session.pendingApproval, isNull);
    });
  });

  group('计划模式 / 预设', () {
    test('计划模式：完全权限也拿不到写工具，硬调用被拒；退出后恢复', () async {
      await session.setPermission(PermissionLevel.full);
      await session.setPlanMode(true);
      final before = f('index.html').readAsStringSync();
      var n = 0;
      turn = (m, t) => n++ == 0 ? use('write_file', {'path': 'index.html', 'content': '改'}) : reply('计划如下……');
      await session.sendToAgent('改首页');
      expect(log.first.tools, isNot(contains('write_file')));
      expect(log.first.tools, isNot(contains('run_command')));
      expect(f('index.html').readAsStringSync(), before);
      expect(toolResults(log.last.messages), contains('计划模式'));
      expect(firstSystem(log.first.messages), contains('计划模式'));

      await session.setPlanMode(false);
      n = 0;
      log.clear();
      await session.sendToAgent('照计划做');
      expect(log.first.tools, contains('write_file'));
      expect(f('index.html').readAsStringSync(), '改');
    });

    test('预设：提示词和个人偏好进系统提示词；没勾的工具拿不到也调不动', () async {
      await env.services.presets.setPreferences('回答尽量短');
      final preset = await env.services.presets.upsert(name: '只读顾问', prompt: '你只负责讲解代码', tools: {'read_file', 'list_files'});
      await session.setPreset(preset.id);
      final before = f('index.html').readAsStringSync();
      var n = 0;
      turn = (m, t) => n++ == 0 ? use('write_file', {'path': 'index.html', 'content': '改'}) : reply('我不能改');
      await session.sendToAgent('改首页');
      expect(log.first.tools, unorderedEquals(['read_file', 'list_files']));
      expect(f('index.html').readAsStringSync(), before);
      expect(toolResults(log.last.messages), contains('预设'));
      final sys = firstSystem(log.first.messages);
      expect(sys, contains('你只负责讲解代码'));
      expect(sys, contains('回答尽量短'));

      await env.services.presets.setPreferences('');
      log.clear();
      n = 1;
      await session.sendToAgent('再说一次');
      expect(firstSystem(log.first.messages), isNot(contains('回答尽量短')), reason: '清空即删除');
    });

    test('新对话用默认预设和默认模型', () async {
      final preset = await env.services.presets.upsert(name: '我的预设', prompt: 'x');
      await env.services.presets.setDefault(preset.id);
      await session.sendToAgent('第一句');
      await session.newConversation();
      expect(session.preset.id, preset.id);
    });
  });

  group('排队 / 插话 / 中断', () {
    test('生成中发的消息默认排队，这一轮结束后自动发出', () async {
      final gate = Completer<void>();
      var n = 0;
      turn = (m, t) async {
        if (n++ == 0) await gate.future;
        return reply('答 ${lastUser(m)}');
      };
      final first = session.sendToAgent('第一条');
      await waitFor(() => log.isNotEmpty);
      await session.sendToAgent('第二条');
      expect(session.queue.single.text, '第二条');
      expect(session.queue.single.steer, isFalse);
      gate.complete();
      await first;
      await waitFor(() => !session.agentBusy && session.queue.isEmpty && log.length == 2, what: '排队的消息发出去');
      expect(session.chat.whereType<UserItem>().map((u) => u.text), ['第一条', '第二条']);
      expect(lastUser(log.last.messages), '第二条');
    });

    test('排队的消息可以撤回；改为插话后下一步模型就能看到', () async {
      final gate = Completer<void>();
      var n = 0;
      turn = (m, t) async {
        n++;
        if (n == 1) {
          await gate.future;
          return use('read_file', {'path': 'index.html'});
        }
        return reply('好');
      };
      final first = session.sendToAgent('看看首页');
      await waitFor(() => log.isNotEmpty);
      await session.sendToAgent('这条会撤回');
      await session.sendToAgent('标题用红色');
      session.withdrawQueued(session.queue.first);
      expect(session.queue.single.text, '标题用红色');
      session.steerQueued(session.queue.single);
      expect(session.queue.single.steer, isTrue);
      gate.complete();
      await first;
      expect(log, hasLength(2));
      expect(lastUser(log[1].messages), '标题用红色', reason: '读完文件后的下一步就带上了插话');
      expect(session.queue, isEmpty);
      expect(session.chat.whereType<UserItem>().map((u) => u.text), ['看看首页', '标题用红色']);
      await waitFor(() => !session.agentBusy);
      expect(log, hasLength(2), reason: '撤回的那条没有发出去');
    });

    test('直接选“插话”发送', () async {
      final gate = Completer<void>();
      var n = 0;
      turn = (m, t) async {
        if (n++ == 0) {
          await gate.future;
          return use('list_files', {});
        }
        return reply('好');
      };
      final first = session.sendToAgent('列一下文件');
      await waitFor(() => log.isNotEmpty);
      await session.sendToAgent('只看 html', mode: SendMode.steer);
      expect(session.queue.single.steer, isTrue);
      gate.complete();
      await first;
      expect(lastUser(log[1].messages), '只看 html');
    });

    test('中断并发送：当前这轮停下，新消息马上发', () async {
      final gate = Completer<void>();
      var n = 0;
      turn = (m, t) async {
        if (n++ == 0) {
          await gate.future;
          return use('run_command', {'command': 'sleep 100'});
        }
        return reply('改做这个');
      };
      final first = session.sendToAgent('跑个很久的命令');
      await waitFor(() => log.isNotEmpty);
      await session.sendToAgent('别跑了，改做别的', mode: SendMode.interrupt);
      gate.complete();
      await first;
      await waitFor(() => !session.agentBusy && log.length == 2, what: '中断后新消息发出');
      expect(shell.commands, isEmpty, reason: '被中断的那一轮不再执行工具');
      expect(lastUser(log.last.messages), '别跑了，改做别的');
    });

    test('用户点停止后，排着的消息留在底部不自动发', () async {
      final gate = Completer<void>();
      var n = 0;
      turn = (m, t) async {
        if (n++ == 0) await gate.future;
        return reply('好');
      };
      final first = session.sendToAgent('第一条');
      await waitFor(() => log.isNotEmpty);
      await session.sendToAgent('排着的');
      session.stopAgent();
      gate.complete();
      await first;
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(session.agentBusy, isFalse);
      expect(session.queue.single.text, '排着的');
      expect(log, hasLength(1));
    });
  });

  group('提问卡 / 附件 / 指令', () {
    test('ask_user：停下来等回答；选项和“其他回答”都原样交回模型', () async {
      var n = 0;
      turn = (m, t) => n++ == 0
          ? use('ask_user', {
              'question': '用哪个配色？',
              'options': ['蓝色', '绿色'],
            })
          : reply('好的');
      final done = session.sendToAgent('做个页面');
      await waitFor(() => session.pendingQuestion != null, what: '提问卡');
      expect(session.pendingQuestion!.question, '用哪个配色？');
      expect(session.pendingQuestion!.options, ['蓝色', '绿色']);
      expect(log.first.tools, contains('ask_user'));
      session.answerQuestion('都不要，用橙色');
      await done;
      expect(toolResults(log.last.messages), contains('都不要，用橙色'));
      expect(session.pendingQuestion, isNull);
    });

    test('附件：存进工作区；最多 9 个由常量限定；不是图片的类型认不出 mime', () async {
      expect(ProjectSession.maxAttachments, 9);
      final saved = await session.saveAttachment([1, 2, 3], '截图 1.PNG');
      final rel = saved['path'] as String;
      expect(saved['mime'], 'image/png');
      await expectLater(session.saveAttachment([1], 'a.exe'), throwsA(isA<FormatException>()));
      expect(() => session.attachWorkspaceFile('../outside.png'), throwsA(anything), reason: '工作区外的文件不能当附件');
      expect(rel, startsWith('${ProjectSession.attachmentsDir}/'));
      expect(f(rel).readAsBytesSync(), [1, 2, 3]);
      expect(ProjectSession.imageMimeOf(rel), 'image/png');
      expect(ProjectSession.imageMimeOf('a.txt'), isNull);
      expect(ProjectSession.imageMimeOf('a.jpeg'), 'image/jpeg');
    });

    test('图片：模型能看图就发图片内容，不能看图就只告诉它文件在哪', () async {
      final image = await session.saveAttachment([9, 8, 7], 'a.png');
      final rel = image['path'] as String;
      // 测试客户端没有渠道配置：按“不能看图”处理
      await session.sendToAgent('这是什么', images: [image]);
      expect(log.last.messages.last['content'], isA<String>());
      expect(log.last.messages.last['content'], contains(rel));

      // 配一个能看图的模型
      final ch = await env.services.models.upsert(
        name: '甲',
        protocol: ChatProtocol.openaiChat,
        baseUrl: 'http://127.0.0.1:1/v1',
        apiKey: 'k',
        models: [ModelSpec(id: 'v', vision: true)],
      );
      await session.newConversation();
      await session.setModel(ModelSelection(ch.id, 'v'));
      await session.sendToAgent('这是什么', images: [image]);
      final content = log.last.messages.last['content'];
      expect(content, isA<List<dynamic>>());
      expect(jsonEncode(content), contains('data:image/png;base64,${base64Encode([9, 8, 7])}'));
      expect(session.chat.whereType<UserItem>().single.images, hasLength(1));
    });

    test('/compact 和 /export 背后的动作', () async {
      await session.sendToAgent('做个页面');
      turn = (m, t) => reply('摘要：做过一个页面');
      expect(await session.compactConversation(), '已压缩');
      turn = (m, t) => reply('继续');
      log.clear();
      await session.sendToAgent('接着做');
      expect(jsonEncode(log.single.messages), contains('摘要：做过一个页面'));
      expect(jsonEncode(log.single.messages), isNot(contains('做个页面')));

      final path = await session.exportConversation();
      expect(path, startsWith('exports/'));
      expect(f(path!).readAsStringSync(), contains('接着做'));
    });
  });

  group('技能 / 联网搜索工具', () {
    test('没配搜索时没有 web_search；配了才有', () async {
      await session.sendToAgent('你好');
      expect(log.last.tools, isNot(contains('web_search')));
      await env.services.settings.set(WebSearchConfig.kUrl, WebSearchConfig.defaultUrl);
      await env.services.secrets.write(WebSearchConfig.secretKey, 'tvly-k');
      await session.sendToAgent('再来');
      expect(log.last.tools, contains('web_search'));
      // 计划模式和仅可查看下搜索照样能用（只读）
      await session.setPermission(PermissionLevel.view);
      await session.sendToAgent('再来');
      expect(log.last.tools, contains('web_search'));
    });

    test('技能：名字和描述进提示词，全文用 read_skill 读；关掉就没有', () async {
      await env.services.skills.create(name: '发版', description: '发版流程', body: '机密步骤一二三', workspaceDir: project.dir);
      var n = 0;
      turn = (m, t) => n++ == 0 ? use('read_skill', {'name': '发版'}) : reply('知道了');
      await session.sendToAgent('怎么发版');
      final sys = firstSystem(log.first.messages);
      expect(sys, contains('发版流程'));
      expect(sys, isNot(contains('机密步骤')));
      expect(log.first.tools, contains('read_skill'));
      expect(toolResults(log.last.messages), contains('机密步骤一二三'));

      final skill = (await env.services.skills.list(workspaceDir: project.dir)).single;
      await env.services.skills.setEnabled(skill, false);
      await session.sendToAgent('再问');
      expect(firstSystem(log.last.messages), isNot(contains('发版流程')));
      expect(log.last.tools, isNot(contains('read_skill')));
    });
  });

  group('子代理', () {
    Future<void> enable({int depth = 1, int concurrent = 2}) async {
      await env.services.settings.set(SettingKeys.subagentEnabled, true);
      await env.services.settings.set(SettingKeys.subagentMaxDepth, depth);
      await env.services.settings.set(SettingKeys.subagentMaxConcurrent, concurrent);
    }

    test('默认开着（一层）；设置里关掉或层数调成 0 就没有 spawn_agent 工具', () async {
      await session.sendToAgent('你好');
      expect(log.last.tools, contains('spawn_agent'));
      await env.services.settings.set(SettingKeys.subagentMaxDepth, 0);
      await session.sendToAgent('你好');
      expect(log.last.tools, isNot(contains('spawn_agent')));
      await env.services.settings.set(SettingKeys.subagentMaxDepth, 1);
      await env.services.settings.set(SettingKeys.subagentEnabled, false);
      await session.sendToAgent('你好');
      expect(log.last.tools, isNot(contains('spawn_agent')));
    });

    test('派出子代理：独立上下文、汇报交回上级、谱系可查、子代理不能再往下派', () async {
      await enable();
      turn = (m, t) {
        final task = firstUser(m);
        if (task.contains('写首页')) {
          return hasToolResult(m) ? reply('首页写好了') : use('write_file', {'path': 'home.html', 'content': 'H'});
        }
        return hasToolResult(m) ? reply('都做完了') : use('spawn_agent', {'name': '前端', 'task': '写首页 home.html'});
      };
      await session.sendToAgent('帮我做个站');
      expect(f('home.html').readAsStringSync(), 'H');

      final kids = session.subAgents;
      expect(kids.single.agentName, '前端');
      expect(kids.single.parentId, session.activeConversation.id);
      expect(kids.single.depth, 1);
      expect(session.topConversations, hasLength(1), reason: '子对话不出现在侧边栏列表里');

      final childCalls = log.where((l) => firstUser(l.messages).contains('写首页')).toList();
      expect(jsonEncode(childCalls.first.messages), isNot(contains('帮我做个站')), reason: '子代理看不到上级的对话');
      expect(childCalls.first.tools, isNot(contains('spawn_agent')), reason: '层数上限 1：子代理不能再派');
      expect(childCalls.first.tools, contains('write_file'));
      expect(toolResults(log.last.messages), allOf(contains('前端'), contains('首页写好了')));

      // 能进入子对话看记录；工具卡连着子对话
      final card = session.chat.whereType<ToolItem>().single;
      expect(card.childConversationId, kids.single.id);
      final childRun = await session.openRun(kids.single.id);
      expect(childRun!.items.whereType<UserItem>().single.text, '写首页 home.html');
    });

    test('层数上限在代码里强制：子代理硬调 spawn_agent 也派不出去', () async {
      await enable(depth: 1);
      turn = (m, t) {
        final task = firstUser(m);
        if (task.contains('子任务')) {
          return hasToolResult(m) ? reply('派不了') : use('spawn_agent', {'name': '孙', 'task': '孙任务'});
        }
        return hasToolResult(m) ? reply('完') : use('spawn_agent', {'name': '子', 'task': '子任务'});
      };
      await session.sendToAgent('开始');
      expect(session.conversations.where((c) => c.parentId != null), hasLength(1));
      expect(log.any((l) => firstUser(l.messages).contains('孙任务')), isFalse);
    });

    test('层数 2 时子代理可以再派一层，第三层不行', () async {
      await enable(depth: 2);
      turn = (m, t) {
        final task = firstUser(m);
        if (task.contains('孙任务')) return reply('孙做完');
        if (task.contains('子任务')) return hasToolResult(m) ? reply('子做完') : use('spawn_agent', {'name': '孙', 'task': '孙任务'});
        return hasToolResult(m) ? reply('完') : use('spawn_agent', {'name': '子', 'task': '子任务'});
      };
      await session.sendToAgent('开始');
      expect(session.conversations.map((c) => c.depth), unorderedEquals([0, 1, 2]));
      final grand = log.firstWhere((l) => firstUser(l.messages).contains('孙任务'));
      expect(grand.tools, isNot(contains('spawn_agent')));
      expect(session.descendantsOf(session.activeConversation.id), hasLength(2));
    });

    test('并发上限：同时在跑的子代理不超过设置的个数', () async {
      await enable(concurrent: 2);
      var running = 0, peak = 0;
      turn = (m, t) async {
        final task = firstUser(m);
        if (task.startsWith('活')) {
          running++;
          if (running > peak) peak = running;
          await Future<void>.delayed(const Duration(milliseconds: 40));
          running--;
          return reply('$task 完成');
        }
        if (hasToolResult(m)) return reply('完');
        return [
          for (var i = 0; i < 4; i++) call(i, 'spawn_agent', jsonEncode({'name': '工$i', 'task': '活$i'})),
          ChatDelta(finishReason: 'tool_calls'),
        ];
      };
      await session.sendToAgent('开四个');
      expect(session.subAgents, hasLength(4));
      expect(peak, 2);
    });

    test('模型：默认跟随上级；只能换成设置里允许的', () async {
      await enable();
      final ch = await env.services.models.upsert(
        name: '甲',
        protocol: ChatProtocol.openaiChat,
        baseUrl: 'http://127.0.0.1:1/v1',
        apiKey: 'k',
        models: [ModelSpec(id: 'big'), ModelSpec(id: 'small'), ModelSpec(id: 'other')],
      );
      await session.setModel(ModelSelection(ch.id, 'big'));
      await env.services.settings.set(SettingKeys.subagentAllowedModels, ['${ch.id}/small']);
      var step = 0;
      turn = (m, t) {
        if (firstUser(m).startsWith('活')) return reply('完成');
        return switch (step++) {
          0 => use('spawn_agent', {'name': '甲', 'task': '活1'}),
          1 => use('spawn_agent', {'name': '乙', 'task': '活2', 'model': '${ch.id}/small'}),
          2 => use('spawn_agent', {'name': '丙', 'task': '活3', 'model': '${ch.id}/other'}),
          _ => reply('完'),
        };
      };
      await session.sendToAgent('开始');
      final kids = session.subAgents;
      expect(kids.map((k) => k.agentName), ['甲', '乙'], reason: '不在允许列表里的模型派不出去');
      expect(kids[0].selection!.modelId, 'big');
      expect(kids[1].selection!.modelId, 'small');
      expect(toolResults(log.last.messages), contains('不在允许'));
    });

    test('子代理跟着主对话的权限：仅可查看时子代理也改不了', () async {
      await enable();
      await session.setPermission(PermissionLevel.view);
      turn = (m, t) {
        if (firstUser(m).contains('改文件')) {
          return hasToolResult(m) ? reply('改不了') : use('write_file', {'path': 'x.txt', 'content': '1'});
        }
        return hasToolResult(m) ? reply('完') : use('spawn_agent', {'name': '子', 'task': '改文件 x.txt'});
      };
      await session.sendToAgent('开始');
      expect(f('x.txt').existsSync(), isFalse);
      final child = log.firstWhere((l) => firstUser(l.messages).contains('改文件'));
      expect(child.tools, isNot(contains('write_file')));
    });

    test('删除主对话：子对话的记录一起删', () async {
      await enable();
      turn = (m, t) {
        if (firstUser(m).contains('子任务')) return reply('子做完');
        return hasToolResult(m) ? reply('完') : use('spawn_agent', {'name': '子', 'task': '子任务'});
      };
      await session.sendToAgent('开始');
      final kid = session.subAgents.single;
      final kidFile = File('${project.dir}/.lopicode/chat-${kid.id}.json');
      expect(kidFile.existsSync(), isTrue);
      await session.deleteConversation();
      expect(kidFile.existsSync(), isFalse);
      expect(session.conversations.any((c) => c.id == kid.id), isFalse);
      expect(session.conversations.every((c) => c.parentId == null), isTrue);
    });
  });

  group('智能体团队', () {
    test('默认关闭：没有任务板工具', () async {
      await session.sendToAgent('你好');
      expect(log.last.tools.where((t) => t.startsWith('team_')), isEmpty);
    });

    test('按任务派子代理：成为负责人、只能改任务写入范围里的文件、结束后任务标完成', () async {
      await env.services.settings.set(SettingKeys.subagentEnabled, true);
      await env.services.settings.set(SettingKeys.teamEnabled, true);
      var step = 0;
      turn = (m, t) {
        if (firstUser(m).contains('写页面')) {
          final done = m.where((x) => x['role'] == 'tool').length;
          return switch (done) {
            0 => use('write_file', {'path': 'pages/a.html', 'content': 'A'}),
            1 => use('write_file', {'path': 'index.html', 'content': '越界'}),
            _ => reply('页面写了'),
          };
        }
        return switch (step++) {
          0 => use('team_task', {
              'title': '写页面',
              'write_scope': ['pages/'],
            }),
          1 => use('spawn_agent', {'name': '前端', 'task': '写页面 pages/a.html', 'task_id': 't1'}),
          _ => reply('完'),
        };
      };
      final before = f('index.html').readAsStringSync();
      await session.sendToAgent('组队做');
      expect(log.first.tools, containsAll(['team_board', 'team_task', 'team_message']));
      expect(f('pages/a.html').readAsStringSync(), 'A');
      expect(f('index.html').readAsStringSync(), before, reason: '范围外的文件不能改');
      final board = await session.boardOf(session.activeConversation);
      expect(board.tasks.single.owner, '前端');
      expect(board.tasks.single.status, TaskStatus.done);
      expect(board.members.map((m) => m.name), containsAll([TeamBoard.lead, '前端']));
      final child = log.firstWhere((l) => firstUser(l.messages).contains('写页面'));
      expect(child.tools, contains('team_board'));
    });
  });

  group('自动化任务', () {
    Map<String, dynamic> args() => {'title': '晨检', 'instruction': '检查依赖有没有更新，写进 report.md', 'kind': 'daily', 'time': '08:30', 'tz_offset_minutes': 480};

    test('Agent 建任务必须过单独确认卡：完全权限 + 本对话都允许 也代替不了', () async {
      await session.setPermission(PermissionLevel.full);
      // 先让“本对话都允许”生效
      await session.setPermission(PermissionLevel.workspace);
      var n = 0;
      turn = (m, t) => n++ == 0 ? use('run_command', {'command': 'ls'}) : reply('ok');
      var done = session.sendToAgent('看目录');
      await waitFor(() => session.pendingApproval != null);
      session.resolveApproval(true, always: true);
      await done;
      expect(session.autoAllowActive, isTrue);
      await session.setPermission(PermissionLevel.full);

      n = 0;
      turn = (m, t) => n++ == 0 ? use('schedule_task', args()) : reply('建好了');
      done = session.sendToAgent('每天早上检查依赖');
      await waitFor(() => session.pendingApproval != null, what: '自动化确认卡');
      final card = session.pendingApproval!.request;
      expect(card.tool, 'schedule_task');
      expect(card.allowAlways, isFalse, reason: '这张卡没有“本对话都允许”');
      expect(card.detail, contains('检查依赖有没有更新，写进 report.md'), reason: '展示完整指令');
      expect(card.detail, contains('下一次触发：'));
      expect(card.detail, contains('08:30'));
      expect(card.detail, contains('UTC+8'));
      expect(card.detail, contains('只有 App 正在运行时才会触发'));
      expect(env.services.automations.items, isEmpty, reason: '确认前什么都没存');
      session.resolveApproval(true, always: true);
      await done;
      expect(env.services.automations.items.single.title, '晨检');
      expect(env.services.automations.items.single.workspaceId, project.id);

      // 再建一个：照样弹卡（上一次点了 always 也不算数）；拒绝就不保存
      n = 0;
      turn = (m, t) => n++ == 0 ? use('schedule_task', {...args(), 'title': '晚检'}) : reply('没建');
      done = session.sendToAgent('再建一个');
      await waitFor(() => session.pendingApproval != null, what: '第二张自动化确认卡');
      session.resolveApproval(false);
      await done;
      expect(env.services.automations.items, hasLength(1));

      // 修改也要确认
      final id = env.services.automations.items.single.id;
      n = 0;
      turn = (m, t) => n++ == 0 ? use('schedule_task', {...args(), 'id': id, 'time': '09:00'}) : reply('改了');
      done = session.sendToAgent('改到九点');
      await waitFor(() => session.pendingApproval != null, what: '修改的确认卡');
      expect(session.pendingApproval!.request.title, '修改自动化任务');
      session.resolveApproval(true);
      await done;
      expect(env.services.automations.items.single.rule.hour, 9);
    });

    test('到点运行：开一段带标记的对话；没人在场，要确认的操作自动拒绝；不能再建任务、不提问', () async {
      final a = await env.services.automations.upsert(
        title: '晨检',
        instruction: '跑一下 ls 再写 report.md',
        workspaceId: project.id,
        rule: TimeRule(kind: RuleKind.daily, hour: 8, tzOffsetMinutes: 0),
        now: DateTime.utc(2026, 11, 23, 0),
      );
      var n = 0;
      turn = (m, t) => switch (n++) {
        0 => use('run_command', {'command': 'ls'}),
        1 => use('write_file', {'path': 'report.md', 'content': '没问题'}),
        _ => reply('检查完了'),
      };
      env.services.scheduler.liveSessions[project.id] = session;
      expect(await env.services.scheduler.tick(DateTime.utc(2026, 11, 23, 7, 59)), 0);
      expect(await env.services.scheduler.tick(DateTime.utc(2026, 11, 23, 8, 1)), 1);
      await waitFor(() => a.history.isNotEmpty && !env.services.scheduler.running.contains(a.id), what: '自动化跑完');
      expect(a.history.first.status, 'ok');
      expect(a.history.first.summary, contains('检查完了'));
      expect(shell.commands, isEmpty, reason: '命令需要确认，没人在场＝拒绝');
      expect(f('report.md').readAsStringSync(), '没问题', reason: '工作区内修改权限下可以写文件');
      expect(session.pendingApproval, isNull);
      final conv = session.conversations.firstWhere((c) => c.auto);
      expect(conv.title, contains('晨检'));
      expect(log.first.tools, isNot(contains('schedule_task')));
      expect(log.first.tools, isNot(contains('ask_user')));
      // 同一分钟再 tick 不会重复跑
      expect(await env.services.scheduler.tick(DateTime.utc(2026, 11, 23, 8, 2)), 0);
    });

    test('App 没开错过的：只记一条“错过”，不补跑', () async {
      final a = await env.services.automations.upsert(
        title: '晨检',
        instruction: 'x',
        workspaceId: project.id,
        rule: TimeRule(kind: RuleKind.daily, hour: 8, tzOffsetMinutes: 0),
        now: DateTime.utc(2026, 11, 23, 0),
      );
      env.services.scheduler.liveSessions[project.id] = session;
      expect(await env.services.scheduler.tick(DateTime.utc(2026, 11, 23, 15)), 0);
      expect(a.history.single.status, 'missed');
      expect(log, isEmpty);
    });

    test('工作区没打开也能跑（后台开一个会话）；从列表移除的工作区不跑', () async {
      final a = await env.services.automations.upsert(
        title: '写报告',
        instruction: '写 report.md',
        workspaceId: project.id,
        rule: TimeRule(kind: RuleKind.daily, hour: 8, tzOffsetMinutes: 0),
        now: DateTime.utc(2026, 11, 23, 0),
      );
      var n = 0;
      turn = (m, t) => n++ == 0 ? use('write_file', {'path': 'report.md', 'content': '后台写的'}) : reply('写好了');
      expect(env.services.scheduler.liveSessions, isEmpty);
      final run = await env.services.scheduler.runNow(a);
      expect(run.status, 'ok', reason: run.summary);
      expect(f('report.md').readAsStringSync(), '后台写的');
      expect(File('${project.dir}/.lopicode/chats.json').readAsStringSync(), contains('"auto":true'), reason: '后台跑的对话也存进了这个工作区');

      await env.services.projects.removeFromList(project);
      n = 0;
      f('report.md').deleteSync();
      final gone = await env.services.scheduler.runNow(a);
      expect(gone.status, 'failed');
      expect(f('report.md').existsSync(), isFalse);
    });

    test('工作区没了：记失败，不乱跑', () async {
      final a = await env.services.automations.upsert(
        title: '孤儿',
        instruction: 'x',
        workspaceId: 'gone',
        rule: TimeRule(kind: RuleKind.daily, hour: 8, tzOffsetMinutes: 0),
        now: DateTime.utc(2026, 11, 23, 0),
      );
      await env.services.scheduler.tick(DateTime.utc(2026, 11, 23, 8, 1));
      await waitFor(() => a.history.isNotEmpty);
      expect(a.history.first.status, 'failed');
      expect(log, isEmpty);
    });
  });
}

String firstSystem(List<Map<String, dynamic>> messages) => '${messages.firstWhere((m) => m['role'] == 'system')['content']}';
