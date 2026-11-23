// 运行环境（Ubuntu）的订阅入口。
//
// 运行环境本身（下载、解压、启动、诊断）的主人还是 `LinuxRuntime` / `RuntimeDiagnostics`：它们管着
// 进程和文件，不适合做成不可变状态。这里把它们的“变了”接进状态容器，界面统一用 `ref.watch` 订阅，
// 不再自己 `addListener` / `ListenableBuilder`。
import 'package:flutter/foundation.dart';
import 'package:lopicode/state/app_providers.dart';
import 'package:riverpod/riverpod.dart';

/// 把一个“会通知的对象”接成计数：它每通知一次加一；容器销毁时自动取消监听。
abstract class ListenableRev extends Notifier<int> {
  Listenable source();

  @override
  int build() {
    final target = source();
    void onChange() {
      if (ref.mounted) state = state + 1;
    }

    target.addListener(onChange);
    ref.onDispose(() => target.removeListener(onChange));
    return 0;
  }
}

/// 运行环境的状态变了（安装进度、装没装好、能不能用、连续失败次数…）。
class RuntimeRev extends ListenableRev {
  @override
  Listenable source() => ref.watch(appServicesProvider).runtime;
}

final runtimeRevProvider = NotifierProvider<RuntimeRev, int>(RuntimeRev.new);

/// 一键诊断的状态变了（在跑 / 跑完 / 报告内容）。
class RuntimeDiagnosticsRev extends ListenableRev {
  @override
  Listenable source() => ref.watch(appServicesProvider).runtime.diagnostics;
}

final runtimeDiagnosticsRevProvider = NotifierProvider<RuntimeDiagnosticsRev, int>(RuntimeDiagnosticsRev.new);
