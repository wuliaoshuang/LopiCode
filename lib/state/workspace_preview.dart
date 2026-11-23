// 一个工作区的预览：本机小服务器起没起来、出没出错、控制台日志变了没有。
//
// 服务器本身（[PreviewServer]）是“干活的对象”，由这里持有、工作区关掉时停掉；
// 状态里只放界面要看的：起好了没有、报错文字、日志变动次数（日志内容从 [PreviewNotifier.server] 上读）。
import 'dart:async';

import 'package:lopicode/preview/preview_server.dart';
import 'package:lopicode/project_session.dart';
import 'package:riverpod/riverpod.dart';

class PreviewState {
  const PreviewState({this.ready = false, this.error, this.logRev = 0});

  /// 服务器已经在听端口了。
  final bool ready;

  /// 没起来的原因（起来了是 null）。
  final String? error;

  /// 控制台日志变了几次（来了新日志、被清空）。
  final int logRev;

  PreviewState copyWith({bool? ready, String? error, bool clearError = false, int? logRev}) =>
      PreviewState(ready: ready ?? this.ready, error: clearError ? null : error ?? this.error, logRev: logRev ?? this.logRev);
}

class PreviewNotifier extends Notifier<PreviewState> {
  PreviewNotifier(this.session);
  final ProjectSession session;

  late final PreviewServer server = PreviewServer(session.project.dir);
  StreamSubscription<void>? _logSub;
  Future<void>? _starting;

  bool get _alive => ref.mounted && !session.disposed;

  @override
  PreviewState build() {
    ref.onDispose(() {
      unawaited(_logSub?.cancel());
      _logSub = null;
      unawaited(server.stop());
    });
    if (session.disposed) return const PreviewState();
    _logSub ??= server.onLog.listen((_) {
      if (_alive) state = state.copyWith(logRev: state.logRev + 1);
    });
    return PreviewState(ready: server.isRunning);
  }

  /// 把服务器起起来。已经起了、正在起，都不会起第二个。
  Future<void> start() => _starting ??= _start().whenComplete(() => _starting = null);

  Future<void> _start() async {
    if (!_alive || server.isRunning) return;
    try {
      await server.start();
    } on Exception catch (e) {
      if (_alive) state = state.copyWith(ready: false, error: '$e');
      return;
    }
    if (!_alive) {
      // 起到一半工作区关了：别留着没人管的端口
      await server.stop();
      return;
    }
    state = state.copyWith(ready: true, clearError: true);
  }

  void clearLogs() => server.clearLogs();
}

/// 某个工作区的预览（按工作区分身）。
final previewProvider = NotifierProvider.family<PreviewNotifier, PreviewState, ProjectSession>(PreviewNotifier.new);
