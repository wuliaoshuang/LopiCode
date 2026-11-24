// 第二阶段（装上真依赖之后）不上真机就能验证的部分：
// 安全存储包装、主机指纹核对、SSH 错误说明、终端后端选择与回退、SSH 构建流程。
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/build/build_controller.dart';
import 'package:lopicode/build/remote_exec.dart';
import 'package:lopicode/build/ssh_build_controller.dart';
import 'package:lopicode/core/secure_secret_store.dart';
import 'package:lopicode/core/stores.dart';
import 'package:lopicode/ssh/ssh_config.dart';
import 'package:lopicode/ssh/ssh_connector.dart';
import 'package:lopicode/ssh/ssh_shell_backend.dart';
import 'package:lopicode/terminal/terminal_session.dart';
import 'package:path/path.dart' as p;
import 'package:xterm/xterm.dart';

class FakeSecureBackend implements SecureBackend {
  final Map<String, String> data = {};
  Object? failWith;
  Object? failReadWith;

  @override
  Future<String?> read(String key) async {
    if (failWith != null) throw failWith!;
    if (failReadWith != null) throw failReadWith!;
    return data[key];
  }

  @override
  Future<void> write(String key, String value) async {
    if (failWith != null) throw failWith!;
    data[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    if (failWith != null) throw failWith!;
    data.remove(key);
  }
}

class FakePty implements PtyProcess {
  final StreamController<List<int>> out = StreamController();
  final Completer<int> exit = Completer();
  final List<String> written = [];
  final List<(int, int)> sizes = [];
  bool killed = false;

  @override
  Stream<List<int>> get output => out.stream;
  @override
  Future<int> get exitCode => exit.future;
  @override
  void write(List<int> data) => written.add(utf8.decode(data));
  @override
  void resize(int rows, int columns) => sizes.add((rows, columns));
  @override
  void kill() => killed = true;
}

class RecordingBackend implements TerminalBackend {
  final List<String> written = [];
  final StreamController<String> out = StreamController.broadcast();
  bool started = false;

  @override
  String get label => '假';
  @override
  Stream<String> get output => out.stream;
  @override
  bool get isRunning => started;
  @override
  Future<void> start({required int columns, required int rows}) async => started = true;
  @override
  void write(String data) => written.add(data);
  @override
  void resize(int columns, int rows) {}
  @override
  Future<void> close() async => out.close();
}

class FakeRemoteExec implements RemoteExec {
  FakeRemoteExec({this.buildExit = 0, this.apkExists = true, this.connectError});
  final int? buildExit;
  final bool apkExists;
  final Object? connectError;
  final List<String> commands = [];
  final Map<String, List<int>> uploaded = {};
  bool connected = false;
  bool closed = false;
  Completer<void>? holdBuild;

  @override
  Future<void> connect() async {
    if (connectError != null) throw connectError!;
    connected = true;
  }

  @override
  Future<int?> run(String command, {required void Function(String chunk) onOutput}) async {
    commands.add(command);
    if (command.startsWith('mkdir -p')) return 0;
    if (command.endsWith('&& pwd')) {
      onOutput('/home/builder/work\n');
      return 0;
    }
    if (command.startsWith('f=')) {
      if (!apkExists) return 1;
      onOutput('/home/builder/work/out/app-release.apk');
      return 0;
    }
    onOutput('Running Gradle task…\n');
    await holdBuild?.future;
    onOutput(buildExit == 0 ? 'Built out/app-release.apk\n' : 'FAILURE: Build failed\n');
    return buildExit;
  }

  @override
  Future<void> upload(String remotePath, List<int> bytes) async => uploaded[remotePath] = bytes;

  @override
  Future<int> download(String remotePath, File target, {void Function(int received, int? total)? onProgress}) async {
    await target.writeAsBytes(List.filled(2048, 7));
    return 2048;
  }

  @override
  Future<void> close() async {
    closed = true;
    if (holdBuild != null && !holdBuild!.isCompleted) holdBuild!.completeError(StateError('连接已断开'));
  }
}

void main() {
  group('安全存储', () {
    test('正常读写删，值进的是安全后端，标成持久', () async {
      final backend = FakeSecureBackend();
      final store = SecureSecretStore(backend);
      await store.probe();
      expect(store.persistent, isTrue);
      await store.write(SecretKeys.sshPassword, 'pw-123');
      expect(backend.data[SecretKeys.sshPassword], 'pw-123');
      expect(await store.read(SecretKeys.sshPassword), 'pw-123');
      await store.delete(SecretKeys.sshPassword);
      expect(await store.read(SecretKeys.sshPassword), isNull);
      expect(backend.data, isEmpty);
    });

    test('插件没注册：退回内存，如实标成不持久，读写仍可用', () async {
      final backend = FakeSecureBackend()..failWith = MissingPluginException();
      final store = SecureSecretStore(backend);
      await store.probe();
      expect(store.persistent, isFalse);
      await store.write('k', 'v');
      expect(await store.read('k'), 'v');
      expect(backend.data, isEmpty);
    });

    test('没探测就写入时插件缺失：这一次也不丢，之后标成不持久', () async {
      final backend = FakeSecureBackend()..failWith = MissingPluginException();
      final store = SecureSecretStore(backend);
      await store.write('k', 'v');
      expect(store.persistent, isFalse);
      expect(await store.read('k'), 'v');
    });

    test('系统密钥库写入报错：只留内存并标成不持久', () async {
      final backend = FakeSecureBackend();
      final store = SecureSecretStore(backend);
      backend.failWith = PlatformException(code: 'keystore');
      await store.write('k', 'v');
      expect(store.persistent, isFalse);
      expect(await store.read('k'), 'v');
    });

    test('读到解不开的值：当作没存过，不抛错', () async {
      final backend = FakeSecureBackend()..failReadWith = PlatformException(code: 'decrypt');
      final store = SecureSecretStore(backend);
      expect(await store.read('k'), isNull);
      expect(store.persistent, isTrue);
    });
  });

  group('SSH 主机与指纹', () {
    late Directory tmp;
    late SettingsStore settings;
    const config = SshConfig(host: 'build.example.com', port: 2222, user: 'dev');

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('lopi_ssh_');
      settings = SettingsStore(File(p.join(tmp.path, 'settings.json')));
    });
    tearDown(() => tmp.deleteSync(recursive: true));

    test('表单校验', () {
      expect(SshConfig.validate(host: '', port: '22', user: 'a'), contains('主机'));
      expect(SshConfig.validate(host: 'root@1.2.3.4', port: '22', user: 'a'), contains('只填域名或 IP'));
      expect(SshConfig.validate(host: 'h', port: '0', user: 'a'), contains('端口'));
      expect(SshConfig.validate(host: 'h', port: 'abc', user: 'a'), contains('端口'));
      expect(SshConfig.validate(host: 'h', port: '22', user: ' '), contains('用户名'));
      expect(SshConfig.validate(host: 'h', port: '22', user: 'a'), isNull);
    });

    test('配置存取：密码和私钥不在普通设置文件里', () async {
      await const SshConfig(host: 'h', port: 2200, user: 'u', useKey: true).save(settings);
      final loaded = SshConfig.load(settings);
      expect((loaded.host, loaded.port, loaded.user, loaded.useKey), ('h', 2200, 'u', true));
      expect(loaded.display, 'u@h:2200');
      final raw = File(p.join(tmp.path, 'settings.json')).readAsStringSync();
      expect(raw, isNot(contains('password')));
      expect(raw, isNot(contains('PRIVATE')));
    });

    test('第一次连接：用户同意才记住；之后同一指纹直接放行', () async {
      final known = KnownHosts(settings);
      var asked = 0;
      final verifier = HostKeyVerifier(
        config: config,
        knownHosts: known,
        prompt: (_, _, _) async {
          asked++;
          return true;
        },
      );
      expect(await verifier.verify('ssh-ed25519', 'SHA256:aaa'), isTrue);
      expect(known.fingerprintOf('build.example.com:2222'), 'SHA256:aaa');
      expect(await verifier.verify('ssh-ed25519', 'SHA256:aaa'), isTrue);
      expect(asked, 1);
    });

    test('第一次连接：用户拒绝就不连、不记', () async {
      final known = KnownHosts(settings);
      final verifier = HostKeyVerifier(config: config, knownHosts: known, prompt: (_, _, _) async => false);
      expect(await verifier.verify('ssh-ed25519', 'SHA256:aaa'), isFalse);
      expect(known.fingerprintOf(config.hostPort), isNull);
      expect(verifier.rejection, contains('没有信任'));
    });

    test('没有确认框可弹（后台场景）：没见过的主机一律拒绝', () async {
      final verifier = HostKeyVerifier(config: config, knownHosts: KnownHosts(settings));
      expect(await verifier.verify('ssh-ed25519', 'SHA256:aaa'), isFalse);
      expect(verifier.rejection, contains('需要先确认主机指纹'));
    });

    test('指纹变了：拒绝，而且不问用户；忘记之后才会重新问', () async {
      final known = KnownHosts(settings);
      await known.trust(config.hostPort, 'SHA256:aaa');
      var asked = 0;
      final verifier = HostKeyVerifier(
        config: config,
        knownHosts: known,
        prompt: (_, _, _) async {
          asked++;
          return true;
        },
      );
      expect(await verifier.verify('ssh-ed25519', 'SHA256:bbb'), isFalse);
      expect(asked, 0);
      expect(verifier.rejection, contains('不一样'));
      expect(known.fingerprintOf(config.hostPort), 'SHA256:aaa');
      await known.forget(config.hostPort);
      expect(await verifier.verify('ssh-ed25519', 'SHA256:bbb'), isTrue);
      expect(asked, 1);
    });

    test('错误说明是人话', () {
      expect(describeSshError(SSHAuthFailError('x'), config), contains('用户名或密码不对'));
      expect(describeSshError(SSHAuthFailError('x'), const SshConfig(host: 'h', user: 'u', useKey: true)), contains('私钥'));
      expect(describeSshError(TimeoutException('t'), config), contains('超时'));
      expect(describeSshError(const SocketException('refused'), config), contains('连不上 build.example.com:2222'));
      expect(describeSshError(const FormatException('bad'), config), contains('私钥格式不对'));
    });

    test('connectSsh：没存密码 / 私钥时不发起连接，直接说明', () async {
      final secrets = MemorySecretStore();
      await expectLater(connectSsh(config: config, secrets: secrets, knownHosts: KnownHosts(settings)), throwsA(isA<SshConnectException>().having((e) => e.message, 'message', contains('还没保存密码'))));
      await expectLater(
        connectSsh(
          config: const SshConfig(host: 'h', user: 'u', useKey: true),
          secrets: secrets,
          knownHosts: KnownHosts(settings),
        ),
        throwsA(isA<SshConnectException>().having((e) => e.message, 'message', contains('还没保存私钥'))),
      );
      await secrets.write(SecretKeys.sshPrivateKey, 'not a key');
      await expectLater(
        connectSsh(
          config: const SshConfig(host: 'h', user: 'u', useKey: true),
          secrets: secrets,
          knownHosts: KnownHosts(settings),
        ),
        throwsA(isA<SshConnectException>().having((e) => e.message, 'message', contains('私钥格式不对'))),
      );
    });

    test('connectSsh：本机一个没人监听的端口 → 明确说连不上', () async {
      final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = probe.port;
      await probe.close();
      final secrets = MemorySecretStore();
      await secrets.write(SecretKeys.sshPassword, 'pw');
      await expectLater(
        connectSsh(
          config: SshConfig(host: '127.0.0.1', port: port, user: 'u'),
          secrets: secrets,
          knownHosts: KnownHosts(settings),
          timeout: const Duration(seconds: 3),
        ),
        throwsA(isA<SshConnectException>().having((e) => e.message, 'message', contains('连不上 127.0.0.1:$port'))),
      );
    });

    test('connectSsh：对面不是 SSH 服务（本机假服务）→ 失败并给出说明，不会挂住', () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((socket) {
        socket.write('HTTP/1.1 400 Bad Request\r\n\r\n');
        socket.close();
      });
      final secrets = MemorySecretStore();
      await secrets.write(SecretKeys.sshPassword, 'pw');
      await expectLater(
        connectSsh(
          config: SshConfig(host: '127.0.0.1', port: server.port, user: 'u'),
          secrets: secrets,
          knownHosts: KnownHosts(settings),
          timeout: const Duration(seconds: 3),
        ).timeout(const Duration(seconds: 20)),
        throwsA(isA<SshConnectException>()),
      );
      await server.close();
    });

    test('SSH 终端后端：连接失败把原因写到屏幕上，回车可重试', () async {
      var attempts = 0;
      final backend = SshShellBackend(
        hostLabel: 'dev@h',
        connect: () async {
          attempts++;
          throw SshConnectException('登录被拒绝：用户名或密码不对。');
        },
      );
      final seen = StringBuffer();
      backend.output.listen(seen.write);
      await backend.start(columns: 80, rows: 24);
      await Future<void>.delayed(Duration.zero);
      expect(seen.toString(), contains('正在连接 dev@h'));
      expect(seen.toString(), contains('登录被拒绝'));
      expect(backend.isRunning, isFalse);
      backend.write('x'); // 普通字符不触发重连
      expect(attempts, 1);
      backend.write('\r');
      await Future<void>.delayed(Duration.zero);
      expect(attempts, 2);
      await backend.close();
    });
  });

  group('终端后端', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('lopi_term_'));
    tearDown(() => tmp.deleteSync(recursive: true));

    test('伪终端能开：走 PTY，按键原样送进去，窗口大小跟着变', () async {
      final pty = FakePty();
      String? exe;
      Map<String, String>? env;
      final backend = LocalShellBackend(
        tmp.path,
        spawner: (executable, {required workingDirectory, required environment, required rows, required columns}) {
          exe = executable;
          env = environment;
          expect((rows, columns, workingDirectory), (30, 48, tmp.path));
          return pty;
        },
      );
      final seen = StringBuffer();
      backend.output.listen(seen.write);
      await backend.start(columns: 48, rows: 30);
      expect(backend.mode, LocalShellMode.pty);
      expect(exe, LocalShellBackend.shellPath);
      expect(env!['TERM'], 'xterm-256color');
      backend.write('ls\r');
      backend.write('\x03');
      expect(pty.written, ['ls\r', '\x03']);
      backend.resize(52, 20);
      expect(pty.sizes, [(20, 52)]);
      pty.out.add(utf8.encode('你好\r\n'));
      await Future<void>.delayed(Duration.zero);
      expect(seen.toString(), contains('你好'));
      await backend.close();
      expect(pty.killed, isTrue);
    });

    test('伪终端里的 shell 退出后，回车会重新开一个', () async {
      final ptys = <FakePty>[];
      final backend = LocalShellBackend(
        tmp.path,
        spawner: (executable, {required workingDirectory, required environment, required rows, required columns}) {
          ptys.add(FakePty());
          return ptys.last;
        },
      );
      final seen = StringBuffer();
      backend.output.listen(seen.write);
      await backend.start(columns: 80, rows: 24);
      ptys.first.exit.complete(0);
      await Future<void>.delayed(Duration.zero);
      expect(backend.isRunning, isFalse);
      expect(seen.toString(), contains('shell 已退出'));
      backend.write('\r');
      await Future<void>.delayed(Duration.zero);
      expect(ptys.length, 2);
      expect(backend.isRunning, isTrue);
      await backend.close();
    });

    test('伪终端开不出来：退回管道模式，屏幕上如实说明，命令照样能跑', () async {
      final backend = LocalShellBackend(
        tmp.path,
        spawner: (executable, {required workingDirectory, required environment, required rows, required columns}) => throw ArgumentError('Failed to load dynamic library libflutter_pty.so'),
      );
      File(p.join(tmp.path, 'hello.txt')).writeAsStringSync('x');
      final seen = StringBuffer();
      backend.output.listen(seen.write);
      await backend.start(columns: 80, rows: 24);
      expect(backend.mode, LocalShellMode.pipe);
      expect(seen.toString(), contains('基础模式'));
      backend.write('lx\x7fs\r'); // 打错一个字、退格、再回车
      await Future<void>.delayed(const Duration(milliseconds: 500));
      expect(seen.toString(), contains('hello.txt'));
      expect(seen.toString(), contains('\b \b'));
      await backend.close();
    });

    test('默认的创建方式在宿主机测试里加载不了原生库，也会平稳回退而不是崩', () async {
      final backend = LocalShellBackend(tmp.path);
      await backend.start(columns: 80, rows: 24);
      expect(backend.mode, anyOf(LocalShellMode.pipe, LocalShellMode.pty));
      await backend.close();
    });

    test('会话：粘滞 Ctrl 把下一个字母变成控制字符，只生效一次', () async {
      final backend = RecordingBackend();
      final session = TerminalSession(title: 't', backend: backend);
      await session.ensureStarted();
      session.toggleCtrl();
      expect(session.ctrlArmed, isTrue);
      session.sendText('c');
      expect(session.ctrlArmed, isFalse);
      session.sendText('c');
      expect(backend.written, ['\x03', 'c']);
      expect(TerminalSession.controlCharFor('d'), '\x04');
      expect(TerminalSession.controlCharFor('1'), isNull);
      session.dispose();
    });

    test('会话：方向键、Tab、Esc 发的是终端转义序列；屏幕文字读得出来', () async {
      final backend = RecordingBackend();
      final session = TerminalSession(title: 't', backend: backend);
      await session.ensureStarted();
      session.sendKey(TerminalKey.arrowUp);
      session.sendKey(TerminalKey.tab);
      session.sendKey(TerminalKey.escape);
      expect(backend.written, ['\x1b[A', '\t', '\x1b']);
      backend.out.add('\x1b[32mindex.html\x1b[0m  style.css\r\n');
      await Future<void>.delayed(Duration.zero);
      expect(session.text, contains('index.html  style.css'));
      session.append('说明\n第二行');
      expect(session.text, contains('说明\n第二行'));
      session.run('pwd');
      await Future<void>.delayed(Duration.zero);
      expect(backend.written.last, 'pwd\r');
      session.dispose();
    });
  });

  group('SSH 构建', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('lopi_sshbuild_'));
    tearDown(() => tmp.deleteSync(recursive: true));

    SshBuildController controller(FakeRemoteExec exec, {String dir = '~/work dir', String apk = 'out/app-release.apk'}) =>
        SshBuildController(exec: exec, remoteDir: dir, command: 'make apk', apkRemotePath: apk, outputDir: p.join(tmp.path, 'apk'));

    test('路径加引号：空格和单引号安全，~ 仍能展开', () {
      expect(shellQuote("a b'c"), "'a b'\\''c'");
      expect(SshBuildController.quotePath('~/my app'), "~/'my app'");
      expect(SshBuildController.quotePath('/srv/x'), "'/srv/x'");
      expect(SshBuildController.quotePath('~'), '~');
    });

    test('完整流程：上传 → 构建 → 下载，日志和产物都在', () async {
      final exec = FakeRemoteExec();
      final job = controller(exec);
      final phases = <BuildPhase>[];
      job.onChanged = () {
        if (phases.isEmpty || phases.last != job.phase) phases.add(job.phase);
      };
      await job.run(
        uploadFiles: {
          'pubspec.yaml': [1],
          'lib/main.dart': [2, 3],
        },
      );
      expect(phases, [BuildPhase.connecting, BuildPhase.pushing, BuildPhase.building, BuildPhase.downloading, BuildPhase.done]);
      expect(exec.commands.first, startsWith('mkdir -p '));
      expect(exec.commands.first, contains("~/'work dir/lib'"));
      expect(exec.uploaded.keys, ['/home/builder/work/pubspec.yaml', '/home/builder/work/lib/main.dart']);
      expect(exec.commands, contains("cd ~/'work dir' && make apk"));
      expect(job.output, contains('Built out/app-release.apk'));
      expect(job.apkPath, p.join(tmp.path, 'apk', 'app-release.apk'));
      expect(File(job.apkPath!).lengthSync(), 2048);
      expect(job.apkBytes, 2048);
      expect(job.log.last, contains('APK 已保存'));
      expect(exec.closed, isTrue);
    });

    test('不上传时不动远程文件', () async {
      final exec = FakeRemoteExec();
      final job = controller(exec);
      await job.run();
      expect(exec.uploaded, isEmpty);
      expect(exec.commands.any((c) => c.startsWith('mkdir')), isFalse);
      expect(job.phase, BuildPhase.done);
    });

    test('构建命令失败：报退出码，不去下载', () async {
      final exec = FakeRemoteExec(buildExit: 1);
      final job = controller(exec);
      await job.run();
      expect(job.phase, BuildPhase.failed);
      expect(job.log.last, contains('退出码 1'));
      expect(job.output, contains('FAILURE'));
      expect(exec.commands.any((c) => c.startsWith('f=')), isFalse);
      expect(job.apkPath, isNull);
    });

    test('构建成功但 APK 路径不对：说清楚找的是哪里', () async {
      final exec = FakeRemoteExec(apkExists: false);
      final job = controller(exec, dir: '/srv/app', apk: 'build/x.apk');
      await job.run();
      expect(job.phase, BuildPhase.failed);
      expect(job.log.last, contains('/srv/app/build/x.apk'));
    });

    test('连不上：把连接错误原样说出来', () async {
      final exec = FakeRemoteExec(connectError: SshConnectException('登录被拒绝：用户名或密码不对。'));
      final job = controller(exec);
      await job.run();
      expect(job.phase, BuildPhase.failed);
      expect(job.log.last, '登录被拒绝：用户名或密码不对。');
    });

    test('构建中途停止：断开连接，状态是已停止而不是失败', () async {
      final exec = FakeRemoteExec()..holdBuild = Completer<void>();
      final job = controller(exec);
      final done = job.run();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(job.phase, BuildPhase.building);
      expect(job.busy, isTrue);
      job.cancel();
      await done;
      expect(job.phase, BuildPhase.cancelled);
      expect(exec.closed, isTrue);
    });

    test('输出只保留末尾一段，不会越攒越大', () async {
      final exec = FakeRemoteExec();
      final job = SshBuildController(exec: exec, remoteDir: '/w', command: 'x', apkRemotePath: 'a.apk', outputDir: tmp.path, maxOutputChars: 30);
      await job.run();
      expect(job.output.length, lessThanOrEqualTo(30));
      expect(job.output, endsWith('Built out/app-release.apk\n'));
    });
  });
}
