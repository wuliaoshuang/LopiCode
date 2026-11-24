// 第二轮真机反馈：Ubuntu 终端一打开，提示符前面不能再有“莫名其妙的文字”——
// (a) 我们自己打的欢迎语；(b) 四行 groups: cannot find name for group ID。
//
// 测试跑在宿主机上：伪终端、PRoot 都是假的，不联网、不下载。安卓的规矩用 `localShellAllowed: false` 走。
//   LOPI_SHOTS=1 flutter test --no-pub test/terminal_clean_test.dart   # 同时写截图到 docs/screenshots/t2-*.png
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:lopicode/app.dart';
import 'package:lopicode/app_services.dart';
import 'package:lopicode/core/project_store.dart';
import 'package:lopicode/core/stores.dart';
import 'package:lopicode/core/templates.dart';
import 'package:lopicode/project_session.dart';
import 'package:lopicode/runtime/linux_command_runner.dart';
import 'package:lopicode/runtime/linux_runtime.dart';
import 'package:lopicode/runtime/runtime_diagnostics.dart';
import 'package:lopicode/ssh/ssh_config.dart';
import 'package:lopicode/ui/project_shell.dart';
import 'package:lopicode/ui/shell.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;

import 'support/harness.dart';
import 'support/runtime_fakes.dart';

final bool writeShots = Platform.environment['LOPI_SHOTS'] == '1';
bool fontsLoaded = false;

class _NoNetwork extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) => throw StateError('测试里不许联网：${request.url}');
}

const _ubuntuGroup = 'root:x:0:\nsudo:x:27:\nnogroup:x:65534:\n';
const _androidGroups = [10556, 3003, 9997, 20556, 50556];

class Env {
  Env(this.tmp, this.services);
  final Directory tmp;
  final AppServices services;
  LinuxRuntime get runtime => services.runtime;
  File get groupFile => File(p.join(runtime.rootfsDir, 'etc', 'group'));

  /// 摆出“早就装好的旧环境”：有 /etc/group，但里面没有安卓的组。
  static Future<Env> create({bool android = true, bool installed = true}) async {
    final tmp = Directory.systemTemp.createTempSync('lopi_tclean_');
    final settings = SettingsStore(File(p.join(tmp.path, 'settings.json')));
    final runtime = LinuxRuntime(
      settings: settings,
      baseDir: p.join(tmp.path, 'runtime'),
      host: FakeRuntimeHost(nativeDir: makeFakeNativeDir(tmp)),
      httpClient: _NoNetwork.new,
      localShellAllowed: android ? false : null,
      processGroups: () => _androidGroups,
    );
    if (installed) {
      markInstalled(runtime);
      File(p.join(runtime.rootfsDir, 'etc', 'group'))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(_ubuntuGroup);
    }
    await runtime.init();
    return Env(tmp, AppServices(settings: settings, secrets: MemorySecretStore(), projects: ProjectStore(p.join(tmp.path, 'projects')), runtime: runtime));
  }

  void dispose() {
    services.dispose();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  }
}

void _expectGroupsNamed(Env env) {
  final text = env.groupFile.readAsStringSync();
  expect(text, startsWith(_ubuntuGroup), reason: '原有内容不动');
  for (final gid in [3003, 9997, 20556, 50556]) {
    expect(text, contains('aid_$gid:x:$gid:\n'), reason: '截图里报错的 $gid 有名字了');
  }
}

void main() {
  setUpAll(() async => fontsLoaded = await loadRealFonts());

  group('启动 PRoot 之前先补组名（旧环境也补）', () {
    late Env env;
    tearDown(() => env.dispose());

    test('终端会话：还没起伪终端，/etc/group 就已经补好；会话里没有欢迎语', () async {
      env = await Env.create();
      final project = await env.services.projects.create('我的小站', ProjectTemplate.web);
      final session = ProjectSession(env.services, project);
      addTearDown(session.dispose);
      String? groupAtSpawn;
      final ptys = <FakePty>[];
      session.linuxPtySpawner = (exe, args, {required workingDirectory, required environment, required rows, required columns}) {
        groupAtSpawn = env.groupFile.readAsStringSync();
        final pty = FakePty();
        ptys.add(pty);
        return pty;
      };
      final t = session.addTerminal()!;
      expect(t.text, isEmpty, reason: '建会话时不往屏幕上写任何字');
      await t.ensureStarted();
      expect(groupAtSpawn, contains('aid_3003:x:3003:'), reason: 'PRoot 启动的那一刻文件已经改好');
      _expectGroupsNamed(env);
      ptys.single.emit('root@localhost:/workspace# ');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(t.text, 'root@localhost:/workspace#', reason: '屏幕上只有提示符');
      expect(env.runtime.logLines.where((l) => l.contains('登记安卓的组')), hasLength(1));
    });

    test('Agent 的 run_command：执行前补好，输出里只有命令自己的输出', () async {
      env = await Env.create();
      final echoed = StringBuffer();
      final runner = LinuxCommandRunner(env.runtime, onOutput: echoed.write);
      if (Platform.isWindows) return;
      final project = Directory(p.join(env.tmp.path, 'proj'))..createSync();
      final result = await runner.run('node -v', workingDirectory: project.path);
      expect(result.exitCode, 0);
      _expectGroupsNamed(env);
      expect(result.output, isNot(contains('cannot find name')));
      expect(echoed.toString(), isNot(contains('LopiCode 终端')));
    });

    test('一键诊断：跑之前也补', () async {
      env = await Env.create();
      final diag = RuntimeDiagnostics(
        env.runtime,
        commandTimeout: const Duration(milliseconds: 300),
        ptyTimeout: const Duration(milliseconds: 300),
        runProcess: (exe, args, {environment, required timeout}) async => const DiagRun(exitCode: 0, stdout: 'ok', stderr: '', elapsed: Duration(milliseconds: 1)),
        ptySpawner: (exe, {required workingDirectory, required environment, required rows, required columns}) => FakePty()..exit(0),
        ptyArgsSpawner: (exe, args, {required workingDirectory, required environment, required rows, required columns}) => FakePty()..exit(0),
      );
      await diag.run();
      _expectGroupsNamed(env);
    });

    test('环境没装时拼命令不崩，也不凭空造出 rootfs', () async {
      env = await Env.create(installed: false);
      env.runtime.prootCommand(guestCommand: const ['/bin/true']);
      expect(Directory(env.runtime.rootfsDir).existsSync(), isFalse);
    });

    test('本机 shell（桌面调试）：也没有欢迎语；SSH 只有“正在连接”这句状态', () async {
      env = await Env.create(android: false, installed: false);
      final project = await env.services.projects.create('我的小站', ProjectTemplate.web);
      final session = ProjectSession(env.services, project);
      addTearDown(session.dispose);
      session.ptySpawner = (shell, {required workingDirectory, required environment, required rows, required columns}) => FakePty();
      final local = session.addTerminal(forceLocal: true)!;
      expect(local.title, startsWith('本机'));
      expect(local.text, isEmpty);
      final ssh = session.addSshTerminal(const SshConfig(host: '127.0.0.1', port: 1, user: 'me'));
      expect(ssh.text, isEmpty);
    });

    test('本机 shell：本该进 Ubuntu 却连续失败时，那句原因还在（有用的状态提示保留）', () async {
      env = await Env.create(android: false);
      final project = await env.services.projects.create('我的小站', ProjectTemplate.web);
      env.runtime
        ..recordLaunchFailure('测试：起不来')
        ..recordLaunchFailure('测试：起不来');
      final session = ProjectSession(env.services, project);
      addTearDown(session.dispose);
      session.ptySpawner = (shell, {required workingDirectory, required environment, required rows, required columns}) => FakePty();
      final t = session.addTerminal()!;
      expect(t.title, startsWith('本机'));
      expect(t.text, contains('Ubuntu 环境连续启动失败'));
      expect(t.text, isNot(contains('LopiCode 终端')));
      // 用户自己点“本机 shell”开的不算进不去：不说这句
      expect(session.addTerminal(forceLocal: true)!.text, isEmpty);
    });
  });

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    final suffix = mode == ThemeMode.light ? 'light' : 'dark';

    testWidgets('终端页 390×844：打开就是干净的提示符，没有欢迎语，也没有 groups 报错 ($suffix)', (tester) async {
      usePhoneViewport(tester);
      final env = (await tester.runAsync(Env.create))!;
      addTearDown(env.dispose);
      final project = (await tester.runAsync(() => env.services.projects.create('我的后端服务（积木）', ProjectTemplate.web)))!;
      final ptys = <FakePty>[];
      late ProjectSession session;
      await tester.runAsync(() async {
        session = ProjectSession(env.services, project);
        await session.loadChat();
        session.linuxPtySpawner = (exe, args, {required workingDirectory, required environment, required rows, required columns}) {
          final pty = FakePty();
          ptys.add(pty);
          return pty;
        };
      });
      // 第一个会话在注入假伪终端之前就建好了：换一个用假伪终端的
      session.addTerminal();
      session.closeTerminal(0);

      await tester.pumpWidget(
        RepaintBoundary(
          key: shotKey,
          child: LopiCodeApp(
            services: env.services,
            home: ProjectShell(project: project, session: session, initial: ShellDest.terminal),
            fontFamily: kTestFont,
            forceThemeMode: mode,
          ),
        ),
      );
      await settle(tester);
      expect(tester.getSize(find.byKey(shotKey)), kPhone);
      expect(ptys, hasLength(1), reason: 'Ubuntu 的 shell 已经启动');
      final t = session.terminals.single;
      expect(t.text, isEmpty, reason: 'shell 还没说话之前，屏幕上一个字都没有');
      _expectGroupsNamed(env);

      ptys.single.emit('root@localhost:/workspace# ');
      await settle(tester);
      expect(t.text, 'root@localhost:/workspace#');
      for (final gone in ['LopiCode 终端', 'Ubuntu 24.04', '装软件用 apt', '项目目录挂在', 'cannot find name']) {
        expect(t.text, isNot(contains(gone)), reason: '不该再出现：$gone');
      }
      expect(find.byKey(const Key('terminal-keys')), findsOneWidget);
      expect(tester.takeException(), isNull);
      if (writeShots && fontsLoaded) {
        final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(shotKey));
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 2);
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          File('docs/screenshots/t2-terminal-clean-$suffix.png')
            ..parent.createSync(recursive: true)
            ..writeAsBytesSync(data!.buffer.asUint8List());
        });
      }
      await tester.runAsync(() async => session.dispose());
      await tester.pump(const Duration(seconds: 1));
    });
  }
}
