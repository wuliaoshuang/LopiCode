import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

// 测试里的等待：一律“等到条件成立、有上限”，不写“固定等多少毫秒就断言”（机器忙时会挂）。
// 界面测试用的 `waitUntil`、`settle`、`waitWritesDone` 在 harness.dart；这里是不带界面也能用的两个。

/// 等待类辅助函数的上限（真实时间）。机器很忙时一次写盘、起一个进程都可能要好几秒，所以给得宽；条件成立就立刻返回，不会真等这么久。
const Duration kWaitLimit = Duration(seconds: 30);

/// 不带界面的测试里“等到条件成立”：条件成立就返回，到了上限就失败并报出等的是什么。[cond] 可以是异步的（比如读文件）。
Future<void> waitUntilReal(FutureOr<bool> Function() cond, String what, {Duration limit = kWaitLimit, Duration every = const Duration(milliseconds: 10)}) async {
  final watch = Stopwatch()..start();
  while (!await cond()) {
    if (watch.elapsed > limit) fail('等了 ${limit.inSeconds} 秒也没等到：$what');
    await Future<void>.delayed(every);
  }
}

/// “这件事不该发生”的断言前用：真等 [ms] 毫秒，中途一旦 [happened] 成立就立刻失败。
/// 这种断言没法写成等条件（等的就是“没动静”），固定时长在这里的意思是“给它这么久的机会出错”：机器忙只会让它更不容易抓到错，不会误报。
Future<void> expectStaysQuiet(bool Function() happened, String what, {int ms = 200}) async {
  final watch = Stopwatch()..start();
  while (watch.elapsedMilliseconds < ms) {
    if (happened()) fail('不该发生却发生了：$what');
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  if (happened()) fail('不该发生却发生了：$what');
}
