// 第 12 条：view_image 工具——模型直接看工作区里的图片。
// 单元（工具本身、请求怎么拼、三种协议各自的请求体）+ 假模型服务器（真实 HTTP 请求体）+ 会话 + 390×844 界面（浅色 / 深色）。不联网。
//   LOPI_SHOTS=1 flutter test test/view_image_test.dart   # 同时写截图到 docs/screenshots/（ap12-…）
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/agent/agent_runner.dart';
import 'package:lopicode/agent/agent_tools.dart';
import 'package:lopicode/agent/chat_client.dart';
import 'package:lopicode/agent/loop_guard.dart';
import 'package:lopicode/agent/model_config.dart';
import 'package:lopicode/agent/presets.dart';
import 'package:lopicode/agent/protocols.dart';
import 'package:lopicode/agent/tool_images.dart';
import 'package:lopicode/core/path_guard.dart';
import 'package:lopicode/core/project_store.dart';
import 'package:lopicode/core/safe_file.dart';
import 'package:lopicode/core/templates.dart';
import 'package:lopicode/project_session.dart';
import 'package:lopicode/session/attachments.dart';
import 'package:lopicode/session/chat_rows.dart';
import 'package:lopicode/session/view_image_tool.dart';
import 'package:lopicode/ui/project_shell.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;

import 'agent_test.dart' show RecordingRunner;
import 'agent_ui_test.dart' show waitReal;
import 'screens_test.dart' show shot, fontsLoaded;
import 'session_system_test.dart' show RoutingClient, Turn, reply, use;
import 'support/fake_model_server.dart';
import 'support/harness.dart';

/// 1×1 的真 PNG。
final List<int> kPng = base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==');
const List<int> kJpegHead = [0xFF, 0xD8, 0xFF, 0xE0, 0, 0x10, 0x4A, 0x46, 0x49, 0x46, 0, 1];

void main() {
  setUpAll(() async => fontsLoaded = await loadRealFonts());

  late Directory tmp;
  late PathGuard guard;
  FakeModelServer? server;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('lopi_view_');
    Directory(p.join(tmp.path, 'proj', 'shots')).createSync(recursive: true);
    guard = PathGuard(p.join(tmp.path, 'proj'));
    File(guard.resolve('shots/home.png')).writeAsBytesSync(kPng);
  });
  tearDown(() async {
    await server?.stop();
    server = null;
    tmp.deleteSync(recursive: true);
  });

  File f(String rel) => File(p.join(guard.root, rel));
  AgentToolbox box({PermissionLevel level = PermissionLevel.workspace, bool plan = false}) => AgentToolbox(
    guard: guard,
    runner: RecordingRunner(),
    requestApproval: (_) async => false,
    autoApprove: () => false,
    permission: () => level,
    planMode: () => plan,
    extras: [viewImageTool(guard)],
  );
  Future<List<int>?> load(String path) async {
    try {
      return await File(guard.resolve(path)).readAsBytes();
    } on Exception {
      return null;
    }
  }

  group('工具本身', () {
    test('读到图片：结果只有路径、类型、大小；图片内容不在结果里', () async {
      final r = await box().execute('view_image', {'path': 'shots/home.png'});
      expect(r.ok, isTrue);
      expect(r.text, contains('已读取图片 shots/home.png（image/png，'));
      expect(r.images, [
        {'path': 'shots/home.png', 'mime': 'image/png', 'bytes': kPng.length},
      ]);
      expect(r.withText('x').images, r.images, reason: '换文字不丢图片');
    });

    test('只读工具：仅可查看、计划模式下也能用，不弹确认卡', () async {
      expect(box(level: PermissionLevel.view).blockReason('view_image'), isNull);
      expect(box(plan: true).blockReason('view_image'), isNull);
      expect((await box(level: PermissionLevel.view, plan: true).execute('view_image', {'path': 'shots/home.png'})).ok, isTrue);
    });

    test('格式按附件的规矩：png / jpg / jpeg / gif / webp；别的扩展名直接说明', () async {
      for (final ext in ['png', 'jpg', 'jpeg', 'gif', 'webp']) {
        expect(imageMimeOf('a.$ext'), isNotNull);
      }
      f('notes.txt').writeAsStringSync('hi');
      f('logo.svg').writeAsStringSync('<svg/>');
      for (final path in ['notes.txt', 'logo.svg']) {
        final r = await box().execute('view_image', {'path': path});
        expect(r.ok, isFalse);
        expect(r.text, contains('只支持 png、jpg、gif、webp'));
        expect(r.images, isEmpty);
      }
    });

    test('文件头说了算：.png 里其实是 jpg → 按 jpg 交；扩展名是图片但内容不是 → 不交', () async {
      f('photo.png').writeAsBytesSync(kJpegHead);
      final jpg = await box().execute('view_image', {'path': 'photo.png'});
      expect(jpg.images.single['mime'], 'image/jpeg');
      f('fake.png').writeAsStringSync('<html>不是图片</html>');
      final fake = await box().execute('view_image', {'path': 'fake.png'});
      expect(fake.ok, isFalse);
      expect(fake.text, contains('内容不是'));
      expect(fake.images, isEmpty);
      expect(sniffImageMime([0x47, 0x49, 0x46, 0x38, 0x39, 0x61]), 'image/gif');
      expect(sniffImageMime([0x52, 0x49, 0x46, 0x46, 1, 2, 3, 4, 0x57, 0x45, 0x42, 0x50]), 'image/webp');
      expect(sniffImageMime([0x52, 0x49, 0x46, 0x46, 1, 2, 3, 4, 0x57, 0x41, 0x56, 0x45]), isNull, reason: 'RIFF 但不是 WEBP（比如 wav）');
      expect(sniffImageMime(const []), isNull);
    });

    test('不存在 / 空文件 / 超过 8MB：都说清楚，不交', () async {
      expect((await box().execute('view_image', {'path': 'nope.png'})).text, contains('文件不存在'));
      f('empty.png').writeAsBytesSync(const []);
      expect((await box().execute('view_image', {'path': 'empty.png'})).text, contains('空文件'));
      final big = f('big.png').openSync(mode: FileMode.write);
      big
        ..writeFromSync(kPng)
        ..truncateSync(kMaxAttachmentBytes + 1)
        ..closeSync();
      final r = await box().execute('view_image', {'path': 'big.png'});
      expect(r.ok, isFalse);
      expect(r.text, contains('超过 8MB 的上限'));
      expect(r.images, isEmpty);
    });

    test('路径守卫照旧：工作区外、.lopicode 里、顺着链接出去的都读不了', () async {
      File(p.join(tmp.path, 'outside.png')).writeAsBytesSync(kPng);
      Directory(p.join(guard.root, '.lopicode')).createSync();
      f('.lopicode/x.png').writeAsBytesSync(kPng);
      Link(p.join(guard.root, 'link.png')).createSync(p.join(tmp.path, 'outside.png'));
      for (final path in ['../outside.png', p.join(tmp.path, 'outside.png'), '.lopicode/x.png', 'link.png']) {
        final r = await box().execute('view_image', {'path': path});
        expect(r.ok, isFalse, reason: path);
        expect(r.text, startsWith('错误：'), reason: path);
        expect(r.images, isEmpty, reason: path);
      }
    });

    test('设置里的工具清单、步骤文案都认得它', () {
      expect(kToolLabels['view_image'], '查看图片');
      expect(stepKindOf('view_image'), StepKind.read);
      expect(stepLabel('view_image', '{"path":"shots/home.png"}'), ('查看图片', 'shots/home.png'));
    });
  });

  group('请求体', () {
    // 界面测试默认把所有网络请求挡成 400；这里要连本机的假服务，放开（只会连 127.0.0.1）。
    setUp(() => HttpOverrides.global = null);
    Future<AgentRunner> runnerFor(List<ScriptedReply> script, {bool vision = true}) async {
      server = FakeModelServer(script);
      await server!.start();
      return AgentRunner(
        client: OpenAiChatClient(baseUrl: server!.baseUrl, apiKey: 'sk-test-key', model: 'fake'),
        toolbox: box(),
        vision: vision,
        loadImage: load,
        retryDelayOf: (_) => Duration.zero,
      );
    }

    List<Map<String, dynamic>> sent(int request) => [for (final m in server!.requests[request]['messages'] as List) (m as Map).cast<String, dynamic>()];
    final dataUrl = 'data:image/png;base64,${base64Encode(kPng)}';

    test('Chat Completions（真实 HTTP 请求体）：tool 消息只有文字；图片在紧随其后的一条 user 消息里', () async {
      final runner = await runnerFor([
        ScriptedReply(calls: [ScriptedCall('view_image', '{"path":"shots/home.png"}', id: 'c1')]),
        ScriptedReply(text: '图里是一个像素。'),
      ]);
      await runner.send('看看首页截图').toList();
      final second = sent(1);
      expect(second.map((m) => m['role']).toList(), ['system', 'user', 'assistant', 'tool', 'user']);
      final tool = second[3];
      expect(tool['content'], isA<String>(), reason: 'tool 消息的内容只能是文字');
      expect(tool['content'], contains('已读取图片 shots/home.png'));
      expect(tool.keys, isNot(contains('_images')), reason: '内部字段不发出去');
      final parts = second[4]['content'] as List;
      expect((parts[0] as Map)['type'], 'text');
      expect((parts[0] as Map)['text'], allOf(contains('这不是用户说的话'), contains('shots/home.png')));
      expect(parts[1], {
        'type': 'image_url',
        'image_url': {'url': dataUrl},
      });
      // 聊天记录里：只有路径和大小，没有图片内容
      final saved = jsonEncode(runner.messages);
      expect(saved, isNot(contains(base64Encode(kPng))));
      expect(runner.messages.firstWhere((m) => m['role'] == 'tool')['_images'], [
        {'path': 'shots/home.png', 'mime': 'image/png', 'bytes': kPng.length},
      ]);
      expect(runner.messages.where((m) => m['role'] == 'user'), hasLength(1), reason: '带图的那条 user 消息只在请求里，不进历史');
    });

    test('一次调两个工具：两条 tool 消息挨着，图片排在它们后面（不会插在两条 tool 中间）', () async {
      final runner = await runnerFor([
        ScriptedReply(
          calls: [
            ScriptedCall('view_image', '{"path":"shots/home.png"}', id: 'c1'),
            ScriptedCall('list_files', '{}', id: 'c2'),
          ],
        ),
        ScriptedReply(text: '好。'),
      ]);
      await runner.send('看').toList();
      expect(sent(1).map((m) => m['role']).toList(), ['system', 'user', 'assistant', 'tool', 'tool', 'user']);
    });

    test('模型不能看图（工具被硬调用，或者后来换了模型）：不带图片，文字说明“当前模型不能看图”', () async {
      final runner = await runnerFor([
        ScriptedReply(calls: [ScriptedCall('view_image', '{"path":"shots/home.png"}', id: 'c1')]),
        ScriptedReply(text: '看不了。'),
      ], vision: false);
      await runner.send('看').toList();
      final last = sent(1).last;
      expect(last['role'], 'user');
      expect(last['content'], isA<String>());
      expect(last['content'], contains('当前模型不能看图'));
      expect(jsonEncode(sent(1)), isNot(contains('base64')));
    });

    test('看完以后文件被删了：下一次请求不带图，说明读不到，不崩', () async {
      final runner = await runnerFor([
        ScriptedReply(calls: [ScriptedCall('view_image', '{"path":"shots/home.png"}', id: 'c1')]),
        ScriptedReply(text: '看到了。'),
        ScriptedReply(text: '好的。'),
      ]);
      await runner.send('看').toList();
      f('shots/home.png').deleteSync();
      await runner.send('再说一遍').toList();
      final third = sent(2);
      expect(third[4]['content'], contains('文件现在读不到了'));
      expect(jsonEncode(third), isNot(contains('base64')));
    });

    test('只带最近 $kToolImagesKept 次看图的图片；更早的只剩文字', () async {
      for (var i = 1; i <= 4; i++) {
        f('shots/s$i.png').writeAsBytesSync(kPng);
      }
      final runner = await runnerFor([
        for (var i = 1; i <= 4; i++) ScriptedReply(calls: [ScriptedCall('view_image', '{"path":"shots/s$i.png"}', id: 'c$i')]),
        ScriptedReply(text: '都看了。'),
      ]);
      await runner.send('挨个看').toList();
      final last = sent(4);
      final texts = [
        for (final m in last)
          if (m['role'] == 'user' && m['content'] is List) '${((m['content'] as List).first as Map)['text']}',
      ];
      expect(texts, hasLength(3));
      expect(texts.join(), isNot(contains('s1.png')));
      expect(texts.join(), allOf(contains('s2.png'), contains('s3.png'), contains('s4.png')));
      expect(last.where((m) => m['role'] == 'tool'), hasLength(4), reason: '四条工具结果的文字都还在');
    });

    test('Anthropic 的请求体：同一条 user 消息里 tool_result 在最前，后面是说明文字和 base64 图片块', () async {
      final runner = await runnerFor([
        ScriptedReply(calls: [ScriptedCall('view_image', '{"path":"shots/home.png"}', id: 'c1')]),
        ScriptedReply(text: '好。'),
      ]);
      await runner.send('看').toList();
      final body = anthropicMessages(await runner.buildRequest()).messages;
      final withResult = body.lastWhere((m) => m['role'] == 'user' && (m['content'] as List).any((b) => (b as Map)['type'] == 'tool_result'));
      final blocks = [for (final b in withResult['content'] as List) (b as Map).cast<String, dynamic>()];
      expect(blocks.map((b) => b['type']).toList(), ['tool_result', 'text', 'image']);
      expect(blocks[0]['content'], isA<String>());
      expect(blocks[2]['source'], {'type': 'base64', 'media_type': 'image/png', 'data': base64Encode(kPng)});
    });

    test('Responses 的请求体：function_call_output 是文字；后面一条 user 里是 input_text + input_image', () async {
      final runner = await runnerFor([
        ScriptedReply(calls: [ScriptedCall('view_image', '{"path":"shots/home.png"}', id: 'c1')]),
        ScriptedReply(text: '好。'),
      ]);
      await runner.send('看').toList();
      final input = responsesInput(await runner.buildRequest()).input;
      final at = input.indexWhere((m) => m['type'] == 'function_call_output');
      expect(input[at]['output'], isA<String>());
      final next = input[at + 1];
      expect(next['role'], 'user');
      final parts = [for (final b in next['content'] as List) (b as Map).cast<String, dynamic>()];
      expect(parts.map((b) => b['type']).toList(), ['input_text', 'input_image']);
      expect(parts[1]['image_url'], dataUrl);
    });

    test('裁掉旧的工具结果时，连带的图片记录也拿掉', () {
      final messages = <Map<String, dynamic>>[
        {
          'role': 'tool',
          'tool_call_id': 'a',
          'content': 'x' * 500,
          '_images': [
            {'path': 'a.png'},
          ],
        },
        for (var i = 0; i < 6; i++) {'role': 'tool', 'tool_call_id': 'b$i', 'content': 'y'},
      ];
      expect(pruneOldToolResults(messages), 1);
      expect(messages.first.containsKey('_images'), isFalse);
      expect(toolImageMessagesToSend(messages), isEmpty);
    });
  });

  group('会话', () {
    late TestEnv env;
    late Project project;
    late ProjectSession session;
    late List<({List<Map<String, dynamic>> messages, List<String> tools})> log;
    Turn turn = (_, _) => reply('好的。');

    Future<void> boot({required bool vision}) async {
      log = [];
      env = await TestEnv.create(chatClient: () => RoutingClient((m, t) => turn(m, t), log));
      await env.services.models.upsert(
        name: '测试渠道',
        protocol: ChatProtocol.openaiChat,
        baseUrl: 'http://127.0.0.1:9/v1',
        apiKey: 'sk-test',
        models: [ModelSpec(id: 'm', vision: vision)],
      );
      project = await env.services.projects.create('测试工作区', ProjectTemplate.web);
      File(p.join(project.dir, 'shot.png')).writeAsBytesSync(kPng);
      session = ProjectSession(env.services, project, headless: true)..commandRunnerFactory = RecordingRunner.new;
      await session.loadChat();
    }

    tearDown(() async {
      session.dispose();
      await env.dispose();
    });

    test('模型开了“支持看图”：工具给模型；看图后的请求带图片；存盘的聊天记录里没有图片内容', () async {
      await boot(vision: true);
      var n = 0;
      turn = (m, t) => n++ == 0 ? use('view_image', {'path': 'shot.png'}) : reply('是一个像素。');
      await session.sendToAgent('看看 shot.png');
      expect(log.first.tools, contains('view_image'));
      final second = log[1].messages;
      expect(second[second.length - 2]['role'], 'tool');
      final parts = second.last['content'] as List;
      expect(((parts[1] as Map)['image_url'] as Map)['url'], 'data:image/png;base64,${base64Encode(kPng)}');
      final step = session.chat.whereType<ToolItem>().single;
      expect(step.ok, isTrue);
      expect(step.result, contains('已读取图片 shot.png'));
      await pendingWrites();
      final onDisk = [
        for (final e in Directory(p.join(project.dir, '.lopicode')).listSync(recursive: true))
          if (e is File) e.readAsStringSync(),
      ].join();
      expect(onDisk, contains('shot.png'));
      expect(onDisk, isNot(contains(base64Encode(kPng))), reason: '记录里只存路径和大小');
    });

    test('模型没开“支持看图”：工具不给模型；硬调用得到明确的“没有这个工具”，不崩', () async {
      await boot(vision: false);
      var n = 0;
      turn = (m, t) => n++ == 0 ? use('view_image', {'path': 'shot.png'}) : reply('好。');
      await session.sendToAgent('看看 shot.png');
      expect(log.first.tools, isNot(contains('view_image')));
      final step = session.chat.whereType<ToolItem>().single;
      expect(step.ok, isFalse);
      expect(step.result, contains('没有名为 view_image 的工具'));
      expect(jsonEncode(log[1].messages), isNot(contains('base64')));
    });
  });

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    final suffix = mode == ThemeMode.light ? 'light' : 'dark';
    testWidgets('聊天页：看图是一步“查看图片 路径”，点开看到文件和结果（没有一大串图片内容） ($suffix)', (tester) async {
      usePhoneViewport(tester);
      late TestEnv env;
      late Project project;
      late ProjectSession session;
      var n = 0;
      await tester.runAsync(() async {
        env = await TestEnv.create(chatClient: () => RoutingClient((m, t) => n++ == 0 ? use('view_image', {'path': 'design/home.png'}) : reply('截图里标题偏左了 8 像素，我来改。'), []));
        await env.services.models.upsert(
          name: '测试渠道',
          protocol: ChatProtocol.openaiChat,
          baseUrl: 'http://127.0.0.1:9/v1',
          apiKey: 'sk-test',
          models: [ModelSpec(id: 'm', vision: true)],
        );
        project = await env.services.projects.create('我的小站', ProjectTemplate.web);
        Directory(p.join(project.dir, 'design')).createSync();
        File(p.join(project.dir, 'design', 'home.png')).writeAsBytesSync(kPng);
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
      await tester.enterText(find.byType(TextField), '对照 design/home.png 看看首页哪里不对');
      await tester.pump();
      await tester.tap(find.byTooltip('发送'));
      await waitReal(tester, () => n >= 2 && !session.agentBusy, what: '做完');
      expect(find.textContaining('截图里标题偏左了'), findsOneWidget);
      // 只有一步时不折成一组，直接就是这一步
      expect(find.textContaining('查看图片'), findsWidgets);
      await tester.tap(find.byKey(const ValueKey('step-call_view_image_0')));
      await settle(tester, rounds: 3);
      expect(find.textContaining('已读取图片 design/home.png'), findsWidgets);
      expect(find.textContaining('base64'), findsNothing);
      await shot(tester, 'ap12-01-view-image-step-$suffix');
    });
  }
}
