// runAndCollect 收尾的回归测试：用宿主机上真实的 /bin/sh 跑。
//
// 以前是等到退出码之后才去挂“输出读完了”的 Future：输出比退出码先结束时，这个 Future 永远不完成，
// 每条命令都白等满 2 秒兜底。现在先拿 Future 再等退出码。
@TestOn('linux || mac-os')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/agent/command_runner.dart';

Future<(CommandResult, Duration, String)> sh(String command, {Duration timeout = const Duration(seconds: 30)}) async {
  final echoed = StringBuffer();
  final watch = Stopwatch()..start();
  final result = await runAndCollect(() => Process.start('/bin/sh', ['-c', command]), timeout: timeout, onOutput: echoed.write);
  return (result, watch.elapsed, echoed.toString());
}

void main() {
  test('很快结束的命令：不白等兜底时限，输出完整', () async {
    // 连跑几次：输出和退出码谁先到是不定的，哪种先后都不该等。
    for (var i = 0; i < 5; i++) {
      final (r, elapsed, echoed) = await sh('echo hi; echo oops >&2');
      expect(r.exitCode, 0);
      expect(r.timedOut, isFalse);
      expect(r.output.split('\n')..sort(), ['', 'hi', 'oops']);
      expect(echoed, contains('hi\r\n'), reason: '回显给终端的换行是 \\r\\n');
      expect(elapsed, lessThan(const Duration(milliseconds: 1500)), reason: '第 ${i + 1} 次用了 ${elapsed.inMilliseconds} 毫秒：正常结束的命令不该等满 ${kOutputDrainGrace.inSeconds} 秒兜底');
    }
  });

  test('退出码不是 0 也一样不白等', () async {
    final (r, elapsed, _) = await sh('echo bad; exit 3');
    expect(r.exitCode, 3);
    expect(r.output, 'bad\n');
    expect(elapsed, lessThan(const Duration(milliseconds: 1500)));
  });

  test('输出较大：尾巴不丢，也不白等', () async {
    final (r, elapsed, echoed) = await sh('seq 1 20000');
    final expected = [for (var i = 1; i <= 20000; i++) '$i\n'].join();
    expect(r.exitCode, 0);
    expect(r.output.length, expected.length);
    expect(r.output, expected);
    expect(r.output.endsWith('19999\n20000\n'), isTrue);
    expect(echoed, expected.replaceAll('\n', '\r\n'));
    expect(elapsed, lessThan(const Duration(milliseconds: 1500)), reason: '用了 ${elapsed.inMilliseconds} 毫秒');
  });

  test('超过收集上限：只留上限以内的，回显照常全给，命令照常结束', () async {
    // 每行 100 个字符，一共约 2.5 MB。
    final (r, _, echoed) = await sh(r'''i=0; line=$(printf '%099d' 0); while [ $i -lt 25 ]; do j=0; while [ $j -lt 1000 ]; do echo $line; j=$((j+1)); done; i=$((i+1)); done''');
    expect(r.exitCode, 0);
    expect(r.output.length, greaterThanOrEqualTo(kMaxCollectedOutputChars));
    expect(r.output.length, lessThan(2500000), reason: '超过上限以后的不再留');
    expect(echoed.length, 25000 * 101, reason: '回显不受上限影响');
  });

  test('后台子进程攥着输出管道：主进程退出后在兜底时限内返回，已有的输出不丢', () async {
    final (r, elapsed, _) = await sh('sleep 6 & echo started');
    expect(r.exitCode, 0);
    expect(r.timedOut, isFalse);
    expect(r.output, 'started\n');
    expect(elapsed, greaterThanOrEqualTo(kOutputDrainGrace - const Duration(milliseconds: 200)), reason: '管道还开着，应该等满兜底时限');
    expect(elapsed, lessThan(const Duration(seconds: 5)), reason: '用了 ${elapsed.inMilliseconds} 毫秒：不能一直等到后台进程结束');
  });

  test('超时：进程被杀，timedOut 为 true、退出码 -1，超时前的输出还在', () async {
    final (r, elapsed, _) = await sh('echo before; sleep 6; echo after', timeout: const Duration(milliseconds: 400));
    expect(r.timedOut, isTrue);
    expect(r.exitCode, -1);
    expect(r.output, 'before\n');
    expect(elapsed, greaterThanOrEqualTo(const Duration(milliseconds: 400)));
    expect(elapsed, lessThan(const Duration(seconds: 5)), reason: '用了 ${elapsed.inMilliseconds} 毫秒');
  });

  test('启动不了：退出码 127，说出原因', () async {
    final r = await runAndCollect(() => Process.start('/没有/这个/程序', const []), timeout: const Duration(seconds: 5), startError: '无法启动 shell');
    expect(r.exitCode, 127);
    expect(r.output, startsWith('无法启动 shell：'));
    expect(r.timedOut, isFalse);
  });
}
