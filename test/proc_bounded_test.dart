// 测试里跑外面的程序的两样保底：超时要真的杀掉（连子进程）；起了的服务在测试没走到 stop() 时也要被收尾杀掉。
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'support/gen2_serve.dart';
import 'support/proc_bounded.dart';

bool _alive(int pid) => Directory('/proc/$pid').existsSync() && !File('/proc/$pid/status').readAsStringSync().contains('State:\tZ');

Future<void> _gone(int pid) async {
  for (var i = 0; i < 100 && _alive(pid); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  expect(_alive(pid), isFalse, reason: '进程 $pid 还活着');
}

void main() {
  final linux = Platform.isLinux;

  test('跑完的命令：交回退出码、标准输出、标准错误', () async {
    final r = await runBounded('bash', ['-c', 'echo 好; echo 坏 >&2; exit 3'], limit: const Duration(seconds: 20));
    expect(r.exitCode, 3);
    expect(r.stdout, '好\n');
    expect(r.stderr, '坏\n');
  }, skip: !linux);

  test('超时：抛超时，程序和它的子进程都被杀掉', () async {
    final dir = Directory.systemTemp.createTempSync('lopi_bounded_');
    addTearDown(() => dir.deleteSync(recursive: true));
    // 父进程起一个子进程，把两个进程号写下来，然后一直不退出。
    const script = 'sleep 300 & echo \$\$ \$! > pids; wait';
    await expectLater(runBounded('bash', ['-c', script], workingDirectory: dir.path, limit: const Duration(seconds: 2)), throwsA(isA<TimeoutException>()));
    final pids = File('${dir.path}/pids').readAsStringSync().trim().split(' ').map(int.parse).toList();
    expect(pids, hasLength(2));
    for (final p in pids) {
      await _gone(p);
    }
  }, skip: !linux);

  group('起了的服务没走到 stop()', () {
    int? pid;
    test('（一）起一个不退出的服务，故意不停', () async {
      final dir = Directory.systemTemp.createTempSync('lopi_bounded_srv_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final port = await gen2FreePort();
      final server = await gen2ServeShell(dir, build: const [], start: 'bash -c "echo 后端已启动：http://127.0.0.1:$port; sleep 300"', port: port, php: false, seconds: 20);
      pid = server.pid;
      expect(_alive(pid!), isTrue);
    });
    test('（二）上一条收尾以后它已经没了', () async {
      expect(pid, isNotNull);
      await _gone(pid!);
    });
  }, skip: !linux);

  test('没起成（一直不说“后端已启动”）：报错，进程被杀掉', () async {
    final dir = Directory.systemTemp.createTempSync('lopi_bounded_srv_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final port = await gen2FreePort();
    await expectLater(gen2ServeShell(dir, build: const [], start: 'bash -c "echo \$\$ > pid; sleep 300"', port: port, php: false, seconds: 2), throwsA(isA<StateError>()));
    await _gone(int.parse(File('${dir.path}/pid').readAsStringSync().trim()));
  }, skip: !linux);
}
