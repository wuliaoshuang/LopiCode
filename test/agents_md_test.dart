// 第 7 条：项目里的 AGENTS.md 自动当项目指令；系统提示词写明命令在什么环境里跑。
// 单元 + 会话（假模型看到的系统提示词）+ 390×844 界面（项目规则页的状态行，浅色 / 深色）。不联网、不起真进程。
//   LOPI_SHOTS=1 flutter test test/agents_md_test.dart   # 同时写截图到 docs/screenshots/（ap7-…）
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/core/path_guard.dart';
import 'package:lopicode/core/project_store.dart';
import 'package:lopicode/core/safe_file.dart';
import 'package:lopicode/core/stores.dart';
import 'package:lopicode/core/templates.dart';
import 'package:lopicode/project_session.dart';
import 'package:lopicode/runtime/linux_runtime.dart';
import 'package:lopicode/session/prompt_context.dart';
import 'package:lopicode/ui/settings_quota.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;

import 'agent_test.dart' show RecordingRunner;
import 'screens_test.dart' show shot, fontsLoaded;
import 'session_system_test.dart' show RoutingClient, reply;
import 'support/harness.dart';
import 'support/runtime_fakes.dart';

String systemOf(List<Map<String, dynamic>> messages) => '${messages.firstWhere((m) => m['role'] == 'system')['content']}';

void main() {
  setUpAll(() async => fontsLoaded = await loadRealFonts());

  group('读 AGENTS.md', () {
    late Directory tmp;
    late PathGuard guard;
    setUp(() {
      tmp = Directory.systemTemp.createTempSync('lopi_agentsmd_');
      guard = PathGuard(tmp.path);
    });
    tearDown(() => tmp.deleteSync(recursive: true));
    File md() => File(p.join(tmp.path, 'AGENTS.md'));

    test('没有文件：missing，不出这一段', () {
      final r = readAgentsMd(guard);
      expect(r.state, AgentsMdState.missing);
      expect(agentsMdSection(r), isNull);
    });

    test('有内容：全文放进去，标明来源是工作区里的文件', () {
      md().writeAsStringSync('  用 pnpm，不要用 npm\n注释写中文\n');
      final r = readAgentsMd(guard);
      expect(r.state, AgentsMdState.loaded);
      expect(r.text, '用 pnpm，不要用 npm\n注释写中文');
      final s = agentsMdSection(r)!;
      expect(s, contains('AGENTS.md'));
      expect(s, contains('来源是工作区里的文件'));
      expect(s, contains('用 pnpm，不要用 npm'));
      expect(s, isNot(contains('太长')));
    });

    test('只有空白：empty，不出这一段', () {
      md().writeAsStringSync(' \n\n ');
      final r = readAgentsMd(guard);
      expect(r.state, AgentsMdState.empty);
      expect(agentsMdSection(r), isNull);
    });

    test('超过上限：只放开头，告诉模型被截断、可以用 read_file 看全文；截在汉字中间不留乱码', () {
      // 每个汉字 3 字节；前面垫 1 个字节，让上限正好落在一个字的中间。
      md().writeAsStringSync('a${'字' * 12000}尾巴');
      final r = readAgentsMd(guard);
      expect(r.state, AgentsMdState.truncated);
      expect(r.totalBytes, 1 + 12000 * 3 + 6);
      expect(r.text.contains('\u{FFFD}'), isFalse);
      expect(r.text.contains('尾巴'), isFalse);
      expect(r.text.length, lessThanOrEqualTo(kAgentsMdMaxBytes));
      final s = agentsMdSection(r)!;
      expect(s, contains('共 ${r.totalBytes} 字节'));
      expect(s, contains('只放了开头约 24KB'));
      expect(s, contains('read_file'));
    });

    test('读不了也不崩：是个目录 / 是二进制 / 是指到工作区外面的链接', () {
      Directory(md().path).createSync();
      expect(readAgentsMd(guard).state, AgentsMdState.unreadable);
      Directory(md().path).deleteSync();

      md().writeAsBytesSync([0x89, 0x50, 0, 0, 1, 2]);
      final bin = readAgentsMd(guard);
      expect(bin.state, AgentsMdState.unreadable);
      expect(bin.problem, contains('不是文本'));
      expect(agentsMdSection(bin), isNull);
      md().deleteSync();

      final outside = Directory.systemTemp.createTempSync('lopi_outside_');
      addTearDown(() => outside.deleteSync(recursive: true));
      File(p.join(outside.path, 'secret.md')).writeAsStringSync('外面的秘密');
      Link(md().path).createSync(p.join(outside.path, 'secret.md'));
      final link = readAgentsMd(guard);
      expect(link.active, isFalse, reason: '路径守卫照旧：不许顺着链接读到工作区外面');
      expect(agentsMdSection(link), isNull);
    });

    test('小写的 agents.md 不算', () {
      File(p.join(tmp.path, 'agents.md')).writeAsStringSync('x');
      // 文件系统不分大小写的机器上这条不成立，跳过。
      if (File(p.join(tmp.path, 'AGENTS.md')).existsSync()) return;
      expect(readAgentsMd(guard).state, AgentsMdState.missing);
    });
  });

  group('命令执行环境那一段', () {
    late Directory tmp;
    late SettingsStore settings;
    setUp(() async {
      tmp = Directory.systemTemp.createTempSync('lopi_envsec_');
      settings = SettingsStore(File(p.join(tmp.path, 's.json')));
      await settings.load();
    });
    tearDown(() async {
      await pendingWrites();
      tmp.deleteSync(recursive: true);
    });

    Future<LinuxRuntime> runtime({required bool android, bool installed = false, bool proot = true}) async {
      final host = FakeRuntimeHost(nativeDir: proot ? makeFakeNativeDir(tmp) : tmp.path);
      final r = LinuxRuntime(settings: settings, baseDir: p.join(tmp.path, 'runtime'), host: host, localShellAllowed: !android);
      if (installed) markInstalled(r);
      await r.init();
      return r;
    }

    test('手机上装好了：写清 Ubuntu 版本、arm64、PRoot、root、bash、/workspace、apt、5 分钟，和代码里的值一致', () async {
      final r = await runtime(android: true, installed: true);
      File(p.join(r.rootfsDir, 'usr/local/bin/node'))
        ..createSync(recursive: true)
        ..writeAsStringSync('x');
      File(p.join(r.rootfsDir, 'usr/bin/git'))
        ..createSync(recursive: true)
        ..writeAsStringSync('x');
      final s = environmentSection(r);
      expect(s, contains('Ubuntu ${r.image.version} arm64'));
      expect(r.image.version, startsWith('24.04'));
      expect(s, contains('PRoot'));
      expect(s, contains('用户是 root'));
      expect(s, contains('/bin/bash'));
      expect(s, contains('项目目录在 /workspace'));
      expect(s, contains('apt'));
      expect(s, contains(r.aptMirror.label));
      expect(s, contains('最长 5 分钟'));
      final ok = s.split('\n').firstWhere((l) => l.contains('已经装好的'));
      expect(ok, contains('Git（命令 git）'));
      expect(ok, contains('node'));
      expect(ok, isNot(contains('PHP')));
      final no = s.split('\n').firstWhere((l) => l.contains('还没装的'));
      expect(no, contains('PHP 8.3'));
      expect(no, isNot(contains('Git')));
    });

    test('工作区本来就在 Ubuntu 里：项目目录写它自己的路径', () async {
      final r = await runtime(android: true, installed: true);
      expect(environmentSection(r, guestCwd: '/root/site'), contains('项目目录在 /root/site'));
    });

    test('手机上没装：写清命令不会执行、要先装运行环境', () async {
      final s = environmentSection(await runtime(android: true));
      expect(s, contains('Ubuntu 运行环境还没有安装'));
      expect(s, contains('不会执行任何命令'));
      expect(s, contains('运行环境'));
      expect(s, isNot(contains('apt')));
    });

    test('手机上装了但安装包里缺进入环境的文件：照实写进不去', () async {
      final s = environmentSection(await runtime(android: true, installed: true, proot: false));
      expect(s, contains('进不去'));
      expect(s, contains('不会执行任何命令'));
    });

    test('桌面没装运行环境：写本机 shell 和系统名，60 秒', () async {
      final s = environmentSection(await runtime(android: false));
      expect(s, contains(Platform.isWindows ? 'Git Bash' : '本机 /bin/sh'));
      expect(s, contains(Platform.operatingSystem));
      expect(s, contains('不是手机上的 Ubuntu'));
      expect(s, contains('最长 60 秒'));
    });

    test('换掉了执行环境（测试 / 调试）：照它自己的说明写', () async {
      expect(environmentSection(await runtime(android: true), customRunner: RecordingRunner()), '命令执行环境：${RecordingRunner().description}。');
    });
  });

  group('会话：模型实际看到的系统提示词', () {
    late TestEnv env;
    late Project project;
    late ProjectSession session;
    late List<({List<Map<String, dynamic>> messages, List<String> tools})> log;
    setUp(() async {
      log = [];
      env = await TestEnv.create(chatClient: () => RoutingClient((_, _) => reply('好的。'), log));
      project = await env.services.projects.create('测试工作区', ProjectTemplate.web);
      session = ProjectSession(env.services, project, headless: true)..commandRunnerFactory = RecordingRunner.new;
      await session.loadChat();
    });
    tearDown(() async {
      session.dispose();
      await env.dispose();
    });

    test('每一轮开始现读：没有 → 不出现；加了 → 下一轮就有；改了 → 下一轮是新的；删了 → 又没有', () async {
      final file = File(p.join(project.dir, 'AGENTS.md'));
      await session.sendToAgent('一');
      expect(systemOf(log.last.messages), isNot(contains('AGENTS.md（项目自带的说明')));
      file.writeAsStringSync('提交信息用英文');
      await session.sendToAgent('二');
      expect(systemOf(log.last.messages), contains('提交信息用英文'));
      file.writeAsStringSync('提交信息用中文');
      await session.sendToAgent('三');
      expect(systemOf(log.last.messages), contains('提交信息用中文'));
      expect(systemOf(log.last.messages), isNot(contains('提交信息用英文')));
      file.deleteSync();
      await session.sendToAgent('四');
      expect(systemOf(log.last.messages), isNot(contains('提交信息用中文')));
    });

    test('和手填的项目规则并存：两段都在、各自标明来源，手填的排在前面', () async {
      File(p.join(project.dir, 'AGENTS.md')).writeAsStringSync('文件里的规矩');
      await session.setProjectRules('手填的规矩');
      await session.sendToAgent('做事');
      final s = systemOf(log.last.messages);
      final manual = s.indexOf('用户给这个项目定的规则（必须遵守）：\n手填的规矩');
      final fromFile = s.indexOf('文件里的规矩');
      expect(manual, greaterThanOrEqualTo(0));
      expect(fromFile, greaterThan(manual));
      expect(s, contains('来源是工作区里的文件'));
      expect(s, contains('以用户手填的为准'));
    });

    test('AGENTS.md 读不了：这一轮照常跑，只是没有这一段', () async {
      Directory(p.join(project.dir, 'AGENTS.md')).createSync();
      await session.sendToAgent('做事');
      expect(log, hasLength(1));
      expect(session.agentBusy, isFalse);
      expect(systemOf(log.last.messages), isNot(contains('项目自带的说明')));
    });

    test('系统提示词里有执行环境那一段；过时的“手机自带的 shell 没有编译器”那句没有了', () async {
      await session.sendToAgent('做事');
      final s = systemOf(log.last.messages);
      expect(s, contains('命令执行环境：${RecordingRunner().description}。'));
      expect(s, isNot(contains('手机自带的 shell 没有编译器')));
      expect(session.systemPrompt, contains('命令执行环境'));
    });
  });

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    final suffix = mode == ThemeMode.light ? 'light' : 'dark';
    group('项目规则页 ($suffix)', () {
      late TestEnv env;
      late Project project;
      late ProjectSession session;

      Future<void> boot(WidgetTester tester, {String? agentsMd}) async {
        usePhoneViewport(tester);
        await tester.runAsync(() async {
          env = await TestEnv.create(chatClient: () => ScriptedChatClient([]));
          project = await env.services.projects.create('我的小站', ProjectTemplate.web);
          if (agentsMd != null) File(p.join(project.dir, 'AGENTS.md')).writeAsStringSync(agentsMd);
          session = ProjectSession(env.services, project, headless: true);
          await session.loadChat();
          await session.setProjectRules('用中文写注释\n改完代码先跑测试');
        });
        addTearDown(() async {
          await tester.runAsync(() async {
            session.dispose();
            await env.dispose();
          });
        });
        await tester.pumpWidget(
          appFor(
            env,
            ProjectRulesScreen(session: session),
            mode: mode,
            font: fontsLoaded ? kTestFont : null,
          ),
        );
        await settle(tester, rounds: 6);
      }

      testWidgets('读到了：一行“AGENTS.md · 已读到”，写明多大；脚注说明会自动生效', (tester) async {
        await boot(tester, agentsMd: '# 项目说明\n- 包管理用 pnpm\n- 提交前跑 pnpm test\n');
        expect(find.byKey(const Key('agents-md-row')), findsOneWidget);
        expect(tester.widget<Text>(find.byKey(const Key('agents-md-state'))).data, '已读到');
        expect(find.textContaining('全文都会交给 Agent'), findsOneWidget);
        expect(find.textContaining('项目里的 AGENTS.md 会自动生效'), findsOneWidget);
        expect(find.byKey(const Key('rules-field')), findsOneWidget, reason: '手填的规则照旧');
        await shot(tester, 'ap7-01-rules-agentsmd-found-$suffix');
      });

      testWidgets('没有文件：状态是“没有这个文件”，告诉她怎么让它生效；后来加了文件，状态跟着变', (tester) async {
        await boot(tester);
        expect(tester.widget<Text>(find.byKey(const Key('agents-md-state'))).data, '没有这个文件');
        expect(find.textContaining('新建一个 AGENTS.md 就会生效'), findsOneWidget);
        await shot(tester, 'ap7-02-rules-agentsmd-missing-$suffix');
        await tester.runAsync(() async => File(p.join(project.dir, 'AGENTS.md')).writeAsStringSync('新加的'));
        session.filesChanged();
        await settle(tester, rounds: 2);
        expect(tester.widget<Text>(find.byKey(const Key('agents-md-state'))).data, '已读到');
      });

      testWidgets('太长 / 读不了：照实显示，不崩', (tester) async {
        await boot(tester, agentsMd: '规' * 20000);
        expect(tester.widget<Text>(find.byKey(const Key('agents-md-state'))).data, '太长');
        expect(find.textContaining('只把开头 24 KB 交给 Agent'), findsOneWidget);
        await tester.runAsync(() async => File(p.join(project.dir, 'AGENTS.md')).writeAsBytesSync([0, 1, 2, 3]));
        session.filesChanged();
        await settle(tester, rounds: 2);
        expect(tester.widget<Text>(find.byKey(const Key('agents-md-state'))).data, '读不了');
        expect(find.textContaining('不是文本文件'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    });
  }
}
