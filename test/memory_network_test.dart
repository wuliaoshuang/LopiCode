// 后台整理记忆碰到网络问题时（超时 / 连不上 / 中途断开）：对话不受影响、不打扰、只记一笔日志，日志里没有密钥；
// 以及“记忆变了”的订阅（memoryRevProvider）。不调用任何真实接口：模型走脚本客户端。
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/agent/chat_client.dart';
import 'package:lopicode/agent/memory_store.dart';
import 'package:lopicode/agent/model_config.dart';
import 'package:lopicode/core/crash_log.dart';
import 'package:lopicode/core/project_store.dart';
import 'package:lopicode/core/stores.dart';
import 'package:lopicode/core/templates.dart';
import 'package:lopicode/project_session.dart';
import 'package:lopicode/state/app_providers.dart';
import 'package:lopicode/state/memory_state.dart';
import 'package:riverpod/riverpod.dart';

import 'agent_test.dart' show RecordingRunner;
import 'session_system_test.dart' show RoutingClient, Turn, reply;
import 'support/harness.dart';

const _marker = '记忆整理员';

void main() {
  setUp(CrashLog.instance.resetForTest);

  late TestEnv env;
  late Project project;
  late ProjectSession session;
  late List<({List<Map<String, dynamic>> messages, List<String> tools})> log;
  late Turn consolidate;

  setUp(() async {
    log = [];
    consolidate = (_, _) => reply('{"items":[]}');
    env = await TestEnv.create(chatClient: () => RoutingClient((m, t) => jsonEncode(m).contains(_marker) ? consolidate(m, t) : reply('好的。'), log));
    final ch = await env.services.models.upsert(
      name: '我的中转站',
      protocol: ChatProtocol.openaiChat,
      baseUrl: 'https://relay.example.cn/v1',
      apiKey: 'test-only',
      models: [ModelSpec(id: 'some-model')],
    );
    project = await env.services.projects.create('测试工作区', ProjectTemplate.web);
    session = ProjectSession(env.services, project, headless: true);
    session.commandRunnerFactory = RecordingRunner.new;
    await session.loadChat();
    await session.setModel(ModelSelection(ch.id, 'some-model'));
  });
  tearDown(() async {
    await env.services.memory.idle();
    if (!session.disposed) session.dispose();
    await env.dispose();
  });

  AppMemory memory() => env.services.memory;
  int consolidations() => log.where((l) => jsonEncode(l.messages).contains(_marker)).length;
  Future<void> chat(int rounds) async {
    for (var i = 0; i < rounds; i++) {
      await session.sendToAgent('问题 $i');
      await memory().idle();
    }
  }

  group('整理请求碰到网络问题', () {
    setUp(() => env.services.settings.set(SettingKeys.memoryAutoConsolidate, true));

    /// 三轮对话以后整理那一次按 [fail] 的方式失败：对话照常、没有提示、记一笔不致命的日志。
    Future<String> failsQuietly(Turn fail) async {
      consolidate = fail;
      await chat(3);
      expect(consolidations(), 1);
      expect(session.chat.whereType<NoticeItem>(), isEmpty, reason: '失败不打扰');
      expect(session.chat.whereType<AssistantItem>(), hasLength(3));
      expect(memory().global.entries, isEmpty);
      expect(memory().project(project).entries, isEmpty);
      final notes = CrashLog.instance.entries.where((e) => e.source == '记忆').toList();
      expect(notes.single.fatal, isFalse);
      expect(notes.single.message, contains('没整理成'));
      // 下一轮照常，而且间隔内不再去撞
      await chat(1);
      expect(session.chat.whereType<AssistantItem>(), hasLength(4));
      expect(consolidations(), 1);
      return notes.single.message;
    }

    test('超时：说清是等太久了', () async {
      final msg = await failsQuietly((_, _) => throw ChatApiException('等了 60 秒模型接口还没有回应（relay.example.cn）'));
      expect(msg, contains('等了 60 秒'));
    });

    test('连不上：只带错误类型，不带请求头和密钥', () async {
      final key = 'sk-${'q1w2e3r4' * 3}';
      final msg = await failsQuietly((_, _) => throw SocketException('Connection refused (Authorization: Bearer $key)'));
      expect(msg, contains('连接中断'));
      expect(msg, isNot(contains(key)), reason: '日志里不许出现密钥');
      expect(jsonEncode([for (final e in CrashLog.instance.entries) e.message]), isNot(contains(key)));
    });

    test('流到一半断了（没有结束标记就抛错）：已经收到的半截不当结果用', () async {
      final msg = await failsQuietly((_, _) async => throw TimeoutException('流式中途 5 分钟没有新内容'));
      expect(msg, contains('没整理成'));
    });
  });

  group('“记忆变了”的订阅', () {
    test('增、改、删、撤销、清空各通知一次；内容没变的写入不通知', () async {
      final box = ProviderContainer(overrides: [appServicesProvider.overrideWithValue(env.services)]);
      addTearDown(box.dispose);
      var n = 0;
      box.listen(memoryRevProvider, (_, _) => n++);
      Future<int> after(Future<void> Function() act) async {
        final before = n;
        await act();
        await Future<void>.delayed(const Duration(milliseconds: 20));
        return n - before;
      }

      expect(await after(() => memory().global.write('甲', '第一版')), 1);
      expect(await after(() => memory().global.write('甲', '第二版')), 1);
      expect(await after(() => memory().project(project).write('乙', '项目的')), 1, reason: '项目记忆变了也通知');
      expect(await after(() => memory().global.delete('甲')), 1);
      expect(await after(() => memory().global.undoLast()), 1);
      expect(await after(() => memory().global.clear()), 1);
    });

    test('没人订阅以后，存储对象上不留监听；容器销毁后再写不报错', () async {
      final box = ProviderContainer(overrides: [appServicesProvider.overrideWithValue(env.services)]);
      final before = memory().changeListeners.length;
      box.listen(memoryRevProvider, (_, _) {});
      expect(memory().changeListeners.length, before + 1);
      box.dispose();
      expect(memory().changeListeners.length, before);
      await memory().global.write('丙', '销毁后写的');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(memory().global.find('丙'), isNotNull);
    });
  });
}
