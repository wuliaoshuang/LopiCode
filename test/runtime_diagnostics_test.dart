// 卡住检测（进 Ubuntu 后没有任何输出）和一键诊断。
// PRoot 在真手机上到底卡在哪，这里验证不了；这里验证的是“卡住时不再是空屏”和“诊断把证据收全”。
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/core/safe_file.dart';
import 'package:lopicode/core/stores.dart';
import 'package:lopicode/runtime/linux_runtime.dart';
import 'package:lopicode/runtime/linux_shell_backend.dart';
import 'package:lopicode/runtime/runtime_diagnostics.dart';
import 'package:path/path.dart' as p;

import 'support/runtime_fakes.dart';

/// 会对写入做出反应的假伪终端：像真 tty 一样先回显，再给结果。
class EchoPty extends FakePty {
  EchoPty({this.echo = true, this.execute = true});
  final bool echo;
  final bool execute;
  @override
  void write(List<int> data) {
    super.write(data);
    final text = utf8.decode(data);
    if (echo) emit(text.replaceAll('\r', '\r\n'));
    if (execute && text.contains(r'$((40+2))')) emit('lopi-42\r\n\$ ');
  }
}

void main() {
  late Directory tmp;
  late LinuxRuntime runtime;
  late FakeRuntimeHost host;
  late SettingsStore settings;

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('lopi_diag_');
    host = FakeRuntimeHost(nativeDir: makeFakeNativeDir(tmp));
    settings = SettingsStore(File(p.join(tmp.path, 's.json')));
    runtime = LinuxRuntime(settings: settings, baseDir: p.join(tmp.path, 'runtime'), host: host);
    markInstalled(runtime);
    File(p.join(runtime.rootfsDir, 'usr/bin/env')).writeAsStringSync('x');
    File(p.join(runtime.rootfsDir, 'usr/bin/bash')).writeAsStringSync('x');
    Link(p.join(runtime.rootfsDir, 'bin')).createSync('usr/bin');
    await runtime.init();
  });
  tearDown(() async {
    // 运行环境会“顺手”存设置（不等它写完）：先等写完再删目录，不然机器忙的时候会删到一半撞上。
    await pendingWrites();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  group('卡住检测', () {
    LinuxShellBackend make(List<FakePty> spawned, List<Map<String, String>> envs, {List<FakePty>? local}) => LinuxShellBackend(
      runtime: runtime,
      projectDir: tmp.path,
      quickExit: const Duration(milliseconds: 30),
      stallTimeout: const Duration(milliseconds: 150),
      spawner: (exe, args, {required workingDirectory, required environment, required rows, required columns}) {
        envs.add(environment);
        final pty = FakePty();
        spawned.add(pty);
        return pty;
      },
      fallbackSpawner: (exe, {required workingDirectory, required environment, required rows, required columns}) {
        final pty = FakePty();
        local?.add(pty);
        return pty;
      },
    );

    test('进程活着但一个字都不输出：到点提示“没有响应”，不算启动成功', () async {
      final spawned = <FakePty>[];
      final backend = make(spawned, []);
      final seen = StringBuffer();
      backend.output.listen(seen.write);
      await backend.start(columns: 80, rows: 24);
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(backend.stalled, isFalse, reason: '还没到时间');
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(backend.stalled, isTrue);
      expect(seen.toString(), contains('还没有任何响应'));
      expect(runtime.logLines.join('\n'), contains('没有任何输出'));
      expect(settings.getBool(SettingKeys.runtimeCompat), isFalse);
      await backend.close();
    });

    test('有输出就不提示；迟到的输出会把提示撤掉', () async {
      final spawned = <FakePty>[];
      final backend = make(spawned, []);
      backend.output.listen((_) {});
      await backend.start(columns: 80, rows: 24);
      spawned.single.emit('root@localhost:~# ');
      await Future<void>.delayed(const Duration(milliseconds: 250));
      expect(backend.stalled, isFalse);
      await backend.close();

      final spawned2 = <FakePty>[];
      final late = make(spawned2, []);
      late.output.listen((_) {});
      await late.start(columns: 80, rows: 24);
      await Future<void>.delayed(const Duration(milliseconds: 250));
      expect(late.stalled, isTrue);
      spawned2.single.emit('root@localhost:~# ');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(late.stalled, isFalse);
      await late.close();
    });

    test('改用兼容模式重试：杀掉卡住的进程，带 PROOT_NO_SECCOMP 重进；有响应后记住兼容模式', () async {
      final spawned = <FakePty>[];
      final envs = <Map<String, String>>[];
      final backend = make(spawned, envs);
      final seen = StringBuffer();
      backend.output.listen(seen.write);
      await backend.start(columns: 80, rows: 24);
      await Future<void>.delayed(const Duration(milliseconds: 250));
      expect(backend.stalled, isTrue);
      expect(envs.single.containsKey('PROOT_NO_SECCOMP'), isFalse);

      await backend.retryCompat();
      expect(spawned.first.killed, isTrue);
      expect(spawned, hasLength(2));
      expect(envs.last['PROOT_NO_SECCOMP'], '1');
      expect(backend.stalled, isFalse);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(seen.toString(), isNot(contains('会话已结束')), reason: '主动重试不该提示会话结束');
      expect(runtime.launchFailures, 0, reason: '卡住不算进连续失败，不会把以后的会话都赶去本机 shell');

      spawned.last.emit('root@localhost:~# ');
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(settings.getBool(SettingKeys.runtimeCompat), isTrue, reason: '兼容模式确实有用才记住');
      await backend.close();
    });

    test('兼容模式下还是没响应：不记住兼容模式，再次提示', () async {
      final spawned = <FakePty>[];
      final backend = make(spawned, []);
      backend.output.listen((_) {});
      await backend.start(columns: 80, rows: 24);
      await Future<void>.delayed(const Duration(milliseconds: 250));
      await backend.retryCompat();
      await Future<void>.delayed(const Duration(milliseconds: 250));
      expect(backend.stalled, isTrue);
      expect(settings.getBool(SettingKeys.runtimeCompat), isFalse);
      await backend.close();
    });

    test('先用本机 shell：这个会话换成手机自带的 sh，之后的输入写给它', () async {
      final spawned = <FakePty>[];
      final local = <FakePty>[];
      final backend = make(spawned, [], local: local);
      final seen = StringBuffer();
      backend.output.listen(seen.write);
      await backend.start(columns: 80, rows: 24);
      await Future<void>.delayed(const Duration(milliseconds: 250));
      await backend.switchToLocal();
      expect(spawned.single.killed, isTrue);
      expect(local, hasLength(1));
      expect(backend.stalled, isFalse);
      backend.write('ls\r');
      expect(utf8.decode(local.single.written), 'ls\r');
      expect(utf8.decode(spawned.single.written), isEmpty);
      expect(seen.toString(), contains('已退回手机自带的 sh'));
      await backend.close();
    });
  });

  group('一键诊断', () {
    test('普通进程执行器：记下输出和退出码；卡住的到点强行停止', () async {
      final ok = await runDiagProcess('/bin/sh', ['-c', 'echo out; echo err >&2; exit 3'], timeout: const Duration(seconds: 5));
      expect(ok.exitCode, 3);
      expect(ok.stdout.trim(), 'out');
      expect(ok.stderr.trim(), 'err');
      expect(ok.timedOut, isFalse);

      final hung = await runDiagProcess('/bin/sh', ['-c', 'echo before; sleep 30'], timeout: const Duration(milliseconds: 400));
      expect(hung.timedOut, isTrue);
      expect(hung.stdout, contains('before'), reason: '卡住前的输出要留着');
      expect(hung.elapsed, lessThan(const Duration(seconds: 5)));

      final missing = await runDiagProcess('/no/such/program', const [], timeout: const Duration(seconds: 2));
      expect(missing.startError, isNotNull);

      final env = await runDiagProcess('/bin/sh', ['-c', r'echo "[$LOPI_X][${HOME:-unset}]"'], environment: {'LOPI_X': '1'}, timeout: const Duration(seconds: 5));
      expect(env.stdout.trim(), '[1][unset]', reason: '给了环境就只用给的，不继承应用自己的');
    });

    RuntimeDiagnostics make({required bool Function(Map<String, String> env, List<String> args) hangs, bool ptyEcho = true, bool ptyProotOk = true}) {
      return RuntimeDiagnostics(
        runtime,
        commandTimeout: const Duration(milliseconds: 300),
        ptyTimeout: const Duration(milliseconds: 600),
        localShell: '/bin/sh',
        runProcess: (exe, args, {environment, required timeout}) async {
          if (!exe.endsWith('libproot.so')) return runDiagProcess(exe, args, environment: environment, timeout: timeout);
          if (args.contains('--version')) {
            return const DiagRun(exitCode: 0, stdout: 'proot 5.1.107', stderr: '', elapsed: Duration(milliseconds: 5));
          }
          if (hangs(environment ?? const {}, args)) {
            return DiagRun(exitCode: null, stdout: '', stderr: environment!.containsKey('PROOT_VERBOSE') ? 'proot info: loading...' : '', elapsed: timeout, timedOut: true);
          }
          return DiagRun(exitCode: 0, stdout: args.contains('/bin/ls') ? 'index.html\n' : 'ok\nuid=0(root)\n', stderr: '', elapsed: const Duration(milliseconds: 40));
        },
        ptySpawner: (exe, {required workingDirectory, required environment, required rows, required columns}) => EchoPty(echo: ptyEcho, execute: ptyEcho),
        ptyArgsSpawner: (exe, args, {required workingDirectory, required environment, required rows, required columns}) {
          final pty = FakePty();
          if (ptyProotOk) {
            Future<void>.delayed(const Duration(milliseconds: 20), () {
              pty.emit('lopi-pty-ok\r\n');
              pty.exit(0);
            });
          }
          return pty;
        },
      );
    }

    test('默认模式卡住、兼容模式能跑：自动记住兼容模式，报告里项目齐全', () async {
      final diag = make(hangs: (env, args) => !env.containsKey('PROOT_NO_SECCOMP'));
      var notified = 0;
      diag.addListener(() => notified++);
      await diag.run(projectDir: tmp.path);
      expect(notified, greaterThan(5));
      expect(diag.running, isFalse);
      expect(settings.getBool(SettingKeys.runtimeCompat), isTrue);
      expect(runtime.compatMode, isTrue);
      final report = diag.report;
      for (final title in const [
        '手机和系统',
        '安装包自带的四个文件',
        'libtalloc.so.2 链接',
        'Ubuntu 系统文件抽查',
        'PRoot 本体（--version）',
        '进 Ubuntu 跑 echo（默认模式）',
        '同一条命令的详细输出（默认模式）',
        '进 Ubuntu 跑 echo（兼容模式）',
        '同一条命令的详细输出（兼容模式）',
        'bash 登录 shell',
        '项目目录（/workspace）',
        '伪终端自检（手机自带的 sh）',
        '伪终端里进 Ubuntu 跑 echo',
      ]) {
        expect(report, contains('== $title'), reason: title);
      }
      expect(report, contains('TestPhone X1'));
      expect(report, contains('uname -a：Linux'));
      expect(report, contains('libproot.so：文件'));
      expect(report, contains('/bin：链接 → usr/bin'));
      expect(report, contains('秒没结束，已强行停止'));
      expect(report, contains('proot info: loading...'), reason: '详细输出要留在报告里');
      expect(report, contains('PROOT_NO_SECCOMP=1'));
      expect(report, contains('index.html'));
      expect(diag.conclusions.join(), contains('默认模式进不去，兼容模式可以'));
      expect(diag.conclusions.join(), contains('伪终端和输入这条路是通的'));
      // bash 和 /workspace 用的是能跑的那个模式
      final bash = diag.steps.firstWhere((s) => s.title == 'bash 登录 shell');
      expect(bash.ok, isTrue);
      expect(bash.lines.join(), contains('兼容模式'));
    });

    test('两种模式都正常：不动兼容模式开关', () async {
      final diag = make(hangs: (_, _) => false);
      await diag.run();
      expect(settings.getBool(SettingKeys.runtimeCompat), isFalse);
      expect(diag.conclusions.first, contains('普通方式能进 Ubuntu'));
      expect(diag.report, contains('这次没有打开的项目，跳过'));
    });

    test('两种模式都卡住：如实说都不行，不乱记开关', () async {
      final diag = make(hangs: (_, _) => true, ptyProotOk: false);
      await diag.run();
      expect(settings.getBool(SettingKeys.runtimeCompat), isFalse);
      expect(diag.conclusions.join(), contains('都进不了 Ubuntu'));
      expect(diag.steps.firstWhere((s) => s.title == '伪终端里进 Ubuntu 跑 echo').ok, isFalse);
    });

    test('伪终端自检：没有回显和结果时判不通过，并指明问题在终端这层', () async {
      final diag = make(hangs: (_, _) => false, ptyEcho: false);
      await diag.run();
      final step = diag.steps.firstWhere((s) => s.title.startsWith('伪终端自检'));
      expect(step.ok, isFalse);
      expect(step.lines.join('\n'), contains('回显（屏幕上看得到自己打的字）：没有'));
      expect(diag.conclusions.join(), contains('问题在“终端 / 输入”这一层'));
    });

    test('伪终端自检：用真的 sh（管道模式的后备实现）也能核对出回显以外的执行结果', () async {
      // 测试机上没有 flutter_pty 的原生库，这里只确认判定逻辑：有结果没回显 → 不通过。
      final diag = RuntimeDiagnostics(
        runtime,
        commandTimeout: const Duration(milliseconds: 300),
        ptyTimeout: const Duration(milliseconds: 600),
        localShell: '/bin/sh',
        runProcess: (exe, args, {environment, required timeout}) async => const DiagRun(exitCode: 0, stdout: 'ok', stderr: '', elapsed: Duration(milliseconds: 1)),
        ptySpawner: (exe, {required workingDirectory, required environment, required rows, required columns}) => EchoPty(echo: false),
        ptyArgsSpawner: (exe, args, {required workingDirectory, required environment, required rows, required columns}) => FakePty()..exit(1),
      );
      await diag.run();
      final step = diag.steps.firstWhere((s) => s.title.startsWith('伪终端自检'));
      expect(step.ok, isFalse);
      expect(step.lines.join('\n'), contains('执行结果（出现 lopi-42）：有'));
    });

    test('报告里不出现任何密钥', () async {
      await settings.set('agent.baseUrl', 'https://example.invalid');
      final diag = make(hangs: (_, _) => false);
      await diag.run(projectDir: tmp.path);
      expect(diag.report, isNot(contains('example.invalid')));
      expect(diag.report.toLowerCase(), isNot(contains('api_key')));
      expect(diag.report.toLowerCase(), isNot(contains('password')));
    });
  });
}
