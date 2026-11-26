/// 搭建页的“存盘合并”：连着改好几下，只在停手以后存一次（不带界面）。
///
/// - 每次修改调 [markDirty]：重新开始等 [delay]；等满了才真的写一次，写的是那一刻的最新内容（[snapshot] 到时候才取）。
/// - 一次写入没做完时又到点了：排在它后面，不会两次写入同时进行。
/// - 要马上用到文件的地方（去预览、离开页面、应用退到后台）调 [flush]：有没存的立刻存，并等它存完。
/// - 状态变了通过 [onState] 告诉界面：saved＝都存好了；pending＝有改动还没存 / 正在存；failed＝上一次没存上（[lastError] 是原因）。
///   没存上以后下一次修改会照常再存。
library;

import 'dart:async';
import 'dart:io';

import 'package:lopicode/core/path_guard.dart';

enum SaveState { saved, pending, failed }

/// 把存盘 / 导出时的出错变成一句写清原因的人话（系统给的原因优先，比如“设备上没有空间”“权限不够”）。
String describeSaveError(Object error) {
  if (error is FileSystemException) {
    final why = error.osError?.message ?? error.message;
    final path = error.path ?? ''; // 有的异常路径是空字符串，不是 null
    return why.isEmpty ? '写不进文件${path.isEmpty ? '' : ' $path'}' : '$why${path.isEmpty ? '' : '（$path）'}';
  }
  if (error is PathGuardException) return error.message;
  return '$error';
}

class SaveQueue<T> {
  SaveQueue({required this.snapshot, required this.write, required this.describeError, this.onState, this.delay = const Duration(milliseconds: 400)});

  /// 取“现在要存的内容”。写之前才调，所以拿到的总是最新的。
  final T Function() snapshot;

  /// 真的写盘。抛出的异常交给 [describeError] 变成一句人话（写清真正的原因）。
  final Future<void> Function(T value) write;
  final String Function(Object error) describeError;
  final void Function(SaveState state)? onState;

  /// 停手多久以后存。
  final Duration delay;

  Timer? _timer;
  bool _dirty = false;
  bool _disposed = false;
  Future<void> _tail = Future.value();
  SaveState _state = SaveState.saved;

  SaveState get state => _state;

  /// 上一次没存上的原因（存上了就是 null）。
  String? lastError;

  /// 一共真的写了几次（测试用）。
  int writes = 0;

  void _set(SaveState s) {
    if (_state == s) return;
    _state = s;
    if (!_disposed) onState?.call(s);
  }

  /// 有改动了：重新计时。
  void markDirty() {
    if (_disposed) return;
    _dirty = true;
    _set(SaveState.pending);
    _timer?.cancel();
    _timer = Timer(delay, () => unawaited(flush())); // 到点自己存；结果通过 onState 告诉界面，这里不用等
  }

  /// 有没存的立刻存；返回的 Future 在“到目前为止的改动都写完（或写失败）”后完成。
  Future<void> flush() {
    _timer?.cancel();
    _timer = null;
    if (_dirty) {
      _dirty = false;
      _tail = _tail.then((_) => _writeOnce());
    }
    return _tail;
  }

  Future<void> _writeOnce() async {
    try {
      writes++;
      await write(snapshot());
      lastError = null;
      if (!_dirty) _set(SaveState.saved);
    } on Object catch (e) {
      // 什么错都接住：这条队列后面还排着下一次存盘，不能让一次失败把后面的都带断
      lastError = describeError(e);
      // 先回到“待定”再报失败：连着两次都没存上时，界面每次都能收到通知
      _state = SaveState.pending;
      _set(SaveState.failed);
    }
  }

  /// 页面关掉：不再通知界面；还没存的照样存完（返回的 Future 可以不等）。
  Future<void> dispose() {
    final done = flush();
    _disposed = true;
    return done;
  }
}
