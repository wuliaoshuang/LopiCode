// 停命令停得干净、没输入时关掉标准输入：用宿主机上真实的 /bin/sh 跑。
//
// 以前：超时只杀我们起的那个 shell，它起的 sleep / node 之类还在后台接着跑；用户点“停止”时正在跑的命令根本不停。
// 现在：超时、停止都把整棵进程树清掉；命令起来后标准输入立刻关上。
@TestOn('linux')
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/agent/command_runner.dart';
import 'package:lopicode/agent/process_tree.dart';

/// 这个进程还活着吗（已经结束、只等父进程来收的不算活着）。
bool alive(int id) {
  try {
    return !File('/proc/$id/status').readAsStringSync().contains('\nState:\tZ');
  } on FileSystemException {
    return false;
  }
}

Future<void> expectGone(Iterable<int> ids, {String reason = ''}) async {
  final until = DateTime.now().add(const Duration(seconds: 3));
  while (ids.any(alive) && DateTime.now().isBefore(until)) {
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  expect([...ids.where(alive)], isEmpty, reason: '这些进程应该已经结束。$reason');
}

/// 从输出里找 `名字:进程号`。
int pidOf(String output, String name) => int.parse(RegExp('$name:(\\d+)').firstMatch(output)!.group(1)!);

/// 等输出里出现匹配 [pattern] 的内容。回显里先有一行命令原文，所以要找的是“真的输出”：一行开头的 ready、带数字的进程号。
Future<void> waitFor(StringBuffer echoed, String pattern) async {
  final re = RegExp(pattern);
  final until = DateTime.now().add(const Duration(seconds: 5));
  while (!re.hasMatch(echoed.toString()) && DateTime.now().isBefore(until)) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  expect(re.hasMatch(echoed.toString()), isTrue, reason: '没等到 $pattern：$echoed');
}

const String kReady = r'\nready\r';

void main() {
  final tmp = Directory.systemTemp.createTempSync('lopi_stop_');
  tearDownAll(() => tmp.deleteSync(recursive: true));

  group('标准输入', () {
    test('cat 这类等输入的命令：马上读到“没有了”，立刻结束，不用等到超时', () async {
      final watch = Stopwatch()..start();
      final r = await runAndCollect(() => Process.start('/bin/sh', ['-c', 'cat; echo after-cat']), timeout: const Duration(seconds: 20));
      expect(r.exitCode, 0);
      expect(r.timedOut, isFalse);
      expect(r.output, 'after-cat\n');
      expect(watch.elapsed, lessThan(const Duration(seconds: 2)), reason: '用了 ${watch.elapsedMilliseconds} 毫秒');
    });

    test('read 读不到输入：命令接着往下走，不卡住', () async {
      final r = await LocalShellRunner().run(r'read answer; echo "got:[$answer]"', workingDirectory: tmp.path, timeout: const Duration(seconds: 20));
      expect(r.output, 'got:[]\n');
      expect(r.timedOut, isFalse);
    });
  });

  group('超时', () {
    test('孙进程也一起结束（以前只杀外面那层 shell）', () async {
      final echoed = StringBuffer();
      final r = await runAndCollect(
        () => Process.start('/bin/sh', ['-c', r'sh -c "sleep 301 & echo kid:\$!; wait" & echo mid:$!; wait']),
        timeout: const Duration(milliseconds: 600),
        onOutput: echoed.write,
      );
      expect(r.timedOut, isTrue);
      expect(r.stopped, isFalse);
      expect(r.exitCode, -1);
      await expectGone([pidOf(r.output, 'mid'), pidOf(r.output, 'kid')], reason: '超时后 sleep 和中间那层 sh 都不该留下');
    });
  });

  group('用户点停止', () {
    test('整棵树清掉，结果标成 stopped，停之前的输出还在', () async {
      final stop = Completer<void>();
      final echoed = StringBuffer();
      final watch = Stopwatch()..start();
      final running = LocalShellRunner(onOutput: echoed.write)
          .runStoppable(r'sh -c "sleep 302 & echo kid:\$!; wait" & echo mid:$!; echo ready; wait', workingDirectory: tmp.path, timeout: const Duration(seconds: 60), stop: stop.future);
      await waitFor(echoed, r'kid:\d+\r');
      await waitFor(echoed, kReady);
      stop.complete();
      final r = await running;
      expect(r.stopped, isTrue);
      expect(r.timedOut, isFalse);
      expect(r.output, contains('ready'));
      expect(watch.elapsed, lessThan(const Duration(seconds: 8)));
      await expectGone([pidOf(r.output, 'mid'), pidOf(r.output, 'kid')]);
    });

    test('先客气地请它退出：命令有机会自己收尾', () async {
      final stop = Completer<void>();
      final echoed = StringBuffer();
      final watch = Stopwatch()..start();
      final running = LocalShellRunner(onOutput: echoed.write)
          .runStoppable(r'''trap 'echo bye; exit 0' TERM; echo ready; while true; do sleep 0.1; done''', workingDirectory: tmp.path, timeout: const Duration(seconds: 60), stop: stop.future);
      await waitFor(echoed, kReady);
      stop.complete();
      final r = await running;
      expect(r.stopped, isTrue);
      expect(r.output, contains('bye'), reason: '收到“请退出”后它自己打了一句再走的');
      expect(watch.elapsed, lessThan(kStopGrace + const Duration(seconds: 3)));
    });

    test('不理“请退出”的：等一小会儿后强行结束', () async {
      final stop = Completer<void>();
      final echoed = StringBuffer();
      final running = LocalShellRunner(onOutput: echoed.write)
          .runStoppable(r'''trap '' TERM; echo me:$$; echo ready; while true; do sleep 0.1; done''', workingDirectory: tmp.path, timeout: const Duration(seconds: 60), stop: stop.future);
      await waitFor(echoed, kReady);
      final watch = Stopwatch()..start();
      stop.complete();
      final r = await running;
      expect(r.stopped, isTrue);
      expect(watch.elapsed, greaterThanOrEqualTo(kStopGrace - const Duration(milliseconds: 300)), reason: '先等了一小会儿');
      expect(watch.elapsed, lessThan(kStopGrace + const Duration(seconds: 4)));
      await expectGone([pidOf(r.output, 'me')]);
    });

    test('父进程先退出、被系统收养的进程：凭记号也能找到并结束', () async {
      final stop = Completer<void>();
      final echoed = StringBuffer();
      final running = LocalShellRunner(onOutput: echoed.write).runStoppable(
        // 括号里那层 shell 起了 sleep 303 就退出：sleep 303 不再是我们起的 shell 的后代。
        r'(sleep 303 >/dev/null 2>&1 & echo orphan:$!); echo ready; sleep 300',
        workingDirectory: tmp.path,
        timeout: const Duration(seconds: 60),
        stop: stop.future,
      );
      await waitFor(echoed, r'orphan:\d+\r');
      await waitFor(echoed, kReady);
      final orphan = pidOf(echoed.toString(), 'orphan');
      expect(alive(orphan), isTrue);
      stop.complete();
      final r = await running;
      expect(r.stopped, isTrue);
      await expectGone([orphan], reason: '被收养的 sleep 303 也要清掉');
    });

    test('命令已经自己结束了才点停止：照常返回，不算 stopped', () async {
      final stop = Completer<void>();
      final r = await LocalShellRunner().runStoppable('echo done', workingDirectory: tmp.path, timeout: const Duration(seconds: 20), stop: stop.future);
      stop.complete();
      expect(r.stopped, isFalse);
      expect(r.exitCode, 0);
      expect(r.output, 'done\n');
    });
  });

  group('进程树', () {
    test('members：后代都在里面，不含别人的进程和本应用', () async {
      final tag = newCommandTag();
      final p = await Process.start('/bin/sh', ['-c', r'sleep 304 & echo kid:$!; wait'], environment: {kCommandTagEnv: tag});
      final line = await p.stdout.transform(const SystemEncoding().decoder).first;
      final kid = pidOf(line, 'kid');
      final tree = CommandProcessTree(p.pid, tag: tag);
      expect(tree.members(), containsAll([p.pid, kid]));
      expect(tree.members(), isNot(contains(pid)));
      expect(CommandProcessTree(p.pid, tag: newCommandTag()).members(), containsAll([p.pid, kid]), reason: '记号对不上时，按进程树照样找得到');
      tree.killNow();
      await p.exitCode;
      await expectGone([p.pid, kid]);
      expect(tree.members(), isEmpty);
    });

    test('killTaggedProcesses：只结束带这个记号的', () async {
      final tag = newCommandTag();
      final mine = await Process.start('/bin/sh', ['-c', 'exec sleep 305'], environment: {kCommandTagEnv: tag});
      final other = await Process.start('/bin/sh', ['-c', 'exec sleep 306'], environment: {kCommandTagEnv: newCommandTag()});
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(killTaggedProcesses(tag), greaterThanOrEqualTo(1));
      await mine.exitCode;
      expect(alive(other.pid), isTrue, reason: '别的记号的进程不能动');
      expect(killTaggedProcesses(''), 0, reason: '空记号什么都不动');
      other.kill(ProcessSignal.sigkill);
      await other.exitCode;
    });
  });
}
