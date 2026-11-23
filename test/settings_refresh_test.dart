// “在别处改了，这里要跟着变”的界面：以前靠整个应用重建顺带刷新，现在各自订阅。
// 逐页的排查清单在 docs/dsh-go-architecture-study.md 的“Riverpod 迁移进度”里。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/agent/chat_client.dart';
import 'package:lopicode/agent/model_config.dart';
import 'package:lopicode/build/build_screen.dart';
import 'package:lopicode/core/crash_log.dart';
import 'package:lopicode/core/project_store.dart';
import 'package:lopicode/core/safe_file.dart';
import 'package:lopicode/core/stores.dart';
import 'package:lopicode/core/templates.dart';
import 'package:lopicode/project_session.dart';
import 'package:lopicode/runtime/linux_runtime.dart';
import 'package:lopicode/ssh/ssh_config.dart';
import 'package:lopicode/ui/project_shell.dart';
import 'package:lopicode/ui/settings_screen.dart';
import 'package:lopicode/ui/shell.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;

import 'support/harness.dart';
import 'support/runtime_fakes.dart';
import 'usage_ui_test.dart' show u;

void main() {
  setUpAll(loadRealFonts);

  late TestEnv env;
  late Project project;
  late ProjectSession session;

  Future<void> boot(WidgetTester tester, {List<List<ChatDelta>> script = const []}) async {
    usePhoneViewport(tester);
    await tester.runAsync(() async {
      env = await TestEnv.create(chatClient: () => ScriptedChatClient(script));
      await env.services.models.upsert(
        name: '我的中转站',
        protocol: ChatProtocol.openaiChat,
        baseUrl: 'https://relay.example.cn/v1',
        apiKey: 'sk-test',
        models: [ModelSpec(id: 'demo', contextLength: 128000)],
      );
      project = await env.services.projects.create('我的小站', ProjectTemplate.web);
      session = ProjectSession(env.services, project);
      await session.loadChat();
    });
    addTearDown(() async {
      await tester.runAsync(() async {
        session.dispose();
        await pendingWrites();
        env.dispose();
      });
    });
  }

  String rowValue(WidgetTester tester, String key) {
    final texts = tester.widgetList<Text>(find.descendant(of: find.byKey(Key(key)), matching: find.byType(Text))).map((t) => t.data).toList();
    return texts.join('|');
  }

  testWidgets('联网搜索：保存 Key 后设置页写“已配置”，清除 Key 后回到“未配置”', (tester) async {
    await boot(tester);
    await tester.pumpWidget(appFor(env, SettingsScreen(workspace: project), font: kTestFont));
    await settle(tester);
    final row = find.byKey(const Key('settings-search'));
    await tester.scrollUntilVisible(row, 120, scrollable: find.byType(Scrollable).first);
    await settle(tester, rounds: 2);
    expect(rowValue(tester, 'settings-search'), contains('未配置'));

    await tester.tap(row);
    await settle(tester);
    await tester.tap(find.text('填入 Tavily 的官方地址'));
    await tester.enterText(find.byKey(const Key('search-key')), 'tvly-demo');
    await tester.ensureVisible(find.byKey(const Key('search-save')));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(const Key('search-save')));
    await settle(tester);
    await tester.tap(find.byTooltip('返回').last);
    await settle(tester);
    expect(rowValue(tester, 'settings-search'), contains('已配置'));

    await tester.tap(row);
    await settle(tester);
    await tester.tap(find.byTooltip('清除已保存的 Key'));
    await settle(tester);
    await tester.tap(find.byTooltip('返回').last);
    await settle(tester);
    expect(rowValue(tester, 'settings-search'), contains('未配置'), reason: '清掉 Key 以后不能还写着“已配置”');
  });

  testWidgets('打包页（一直留在后台的页面）：在别处改了 SSH 主机，构建机那一行跟着变', (tester) async {
    await boot(tester);
    await tester.runAsync(() => env.services.settings.set(SettingKeys.apkBuildMode, 'ssh'));
    await tester.pumpWidget(
      appFor(
        env,
        ShellScope(
          openDrawer: () {},
          go: (_) {},
          projectName: '我的小站',
          child: BuildScreen(session: session),
        ),
        font: kTestFont,
      ),
    );
    await settle(tester);
    expect(find.text('还没设置'), findsOneWidget);
    // 相当于在终端页连了一台 SSH 主机：打包页没有重建，只靠订阅刷新
    await tester.runAsync(() => const SshConfig(host: 'build.example.com', user: 'dev').save(env.services.settings));
    await settle(tester, rounds: 2);
    expect(find.text('还没设置'), findsNothing);
    expect(find.text('dev@build.example.com'), findsOneWidget);
  });

  testWidgets('用量弹层开着的时候又跑了一轮：累计数字跟着变', (tester) async {
    await boot(
      tester,
      // 每一轮都新建一个照本宣科的假模型，所以两轮各用掉同样的量
      script: [
        [say('好的。'), ChatDelta(finishReason: 'stop', usage: u(1000, 0, 100))],
      ],
    );
    await tester.pumpWidget(
      appFor(
        env,
        ProjectShell(project: project, session: session, initial: ShellDest.chat),
        font: kTestFont,
      ),
    );
    await settle(tester);
    await tester.runAsync(() => session.sendToAgent('第一句').timeout(const Duration(seconds: 20)));
    await settle(tester, rounds: 3);
    await tester.tap(find.byKey(const Key('context-ring')));
    await settle(tester);
    String stat(String key) => tester.widget<Text>(find.byKey(Key(key))).data!;
    expect((stat('usage-total-turns'), stat('usage-total-in'), stat('usage-total-out')), ('1', '1K', '100'));

    await tester.runAsync(() => session.sendToAgent('第二句').timeout(const Duration(seconds: 20)));
    await settle(tester, rounds: 3);
    expect(find.text('用量'), findsOneWidget, reason: '弹层还开着');
    expect((stat('usage-total-turns'), stat('usage-total-in'), stat('usage-total-out')), ('2', '2K', '200'));
  });

  group('不等写完盘的设置（setLater）', () {
    late Directory tmp;
    setUp(() {
      tmp = Directory.systemTemp.createTempSync('lopi_later_');
      CrashLog.instance.resetForTest();
    });
    tearDown(() async {
      await pendingWrites();
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
      CrashLog.instance.resetForTest();
    });

    test('写得进去：内存立刻生效，盘上随后也有', () async {
      final settings = SettingsStore(File(p.join(tmp.path, 's.json')));
      settings.setLater('k', 1);
      expect(settings.get<int>('k'), 1);
      await pendingWrites();
      expect(File(p.join(tmp.path, 's.json')).readAsStringSync(), contains('"k":1'));
      expect(CrashLog.instance.entries, isEmpty);
    });

    test('写不进去：只记进错误日志，不会变成没人接的异常', () async {
      File(p.join(tmp.path, 'blocked')).writeAsStringSync('这里是个文件，不是目录');
      final settings = SettingsStore(File(p.join(tmp.path, 'blocked', 's.json')));
      settings.setLater('k', 1);
      expect(settings.get<int>('k'), 1);
      await pendingWrites();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(CrashLog.instance.entries.single.source, '保存设置 k');
    });

    test('运行环境“记住兼容模式”那一笔：盘写不进去（目录没了）也不抛错', () async {
      // 在迁移前的代码上，同样的步骤会冒出一个没人接的 FileSystemException——runtime_diagnostics 测试偶发失败就是它。
      File(p.join(tmp.path, 'blocked')).writeAsStringSync('挡路');
      final settings = SettingsStore(File(p.join(tmp.path, 'blocked', 's.json')));
      final runtime = LinuxRuntime(
        settings: settings,
        baseDir: p.join(tmp.path, 'runtime'),
        host: FakeRuntimeHost(nativeDir: makeFakeNativeDir(tmp)),
      );
      runtime.forceCompat = true;
      runtime.recordLaunchSuccess();
      expect(settings.getBool(SettingKeys.runtimeCompat), isTrue, reason: '内存里已经记住了');
      await pendingWrites();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(CrashLog.instance.entries.single.source, contains('保存设置'));
    });
  });
}
