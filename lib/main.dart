import 'dart:async';
import 'dart:io';

import 'package:lopicode/app.dart';
import 'package:lopicode/app_services.dart';
import 'package:lopicode/core/crash_log.dart';
import 'package:lopicode/ui/error_guard.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 三道兜底都在这里装上：界面框架的（FlutterError.onError）、平台层的（PlatformDispatcher.onError）、
/// 以及包住整个应用的 runZonedGuarded。没被接住的异常统一进错误日志，界面给可复制的提示，不白屏、不悄悄闪退。
void main() {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    installErrorHandlers();
    await _attachLog();
    await _boot();
  }, recordZoneError);
}

Future<void> _attachLog() async {
  try {
    final support = await getApplicationSupportDirectory();
    CrashLog.instance.attach(Directory(p.join(support.path, 'logs')));
  } on Exception catch (e, st) {
    // 拿不到目录：日志只进内存，不影响启动
    CrashLog.instance.record(e, st, source: '启动（日志目录）');
  }
}

Future<void> _boot() async {
  try {
    final services = await AppServices.boot();
    runApp(LopiCodeApp(services: services));
  } catch (e, st) {
    // 启动就失败：不能白屏。显示说明 + 可复制的错误 + 重试。
    CrashLog.instance.record(e, st, source: '启动');
    await CrashLog.instance.flush();
    runApp(BootFailureApp(error: CrashLog.instance.export(), onRetry: _boot));
  }
}
