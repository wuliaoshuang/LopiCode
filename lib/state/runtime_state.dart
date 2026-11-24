// 运行环境（Ubuntu）和一键诊断的状态（完整版：不可变快照 + Notifier）。
//
// 下载、解压、起进程这些活由 `LinuxRuntime` / `RuntimeDiagnostics` 干（它们管着进程和文件，放在应用服务里，
// 终端和 Agent 的命令也直接用它们）。它们每次有变化就说一声，这里拍一张不可变的快照给界面订阅；
// 界面要做什么（安装、取消、卸载、装运行时、换下载源、开始诊断）就调 Notifier 的方法。
import 'package:lopicode/runtime/linux_runtime.dart';
import 'package:lopicode/runtime/pack_install.dart';
import 'package:lopicode/runtime/runtime_diagnostics.dart';
import 'package:lopicode/runtime/runtime_snapshot.dart';
import 'package:lopicode/runtime/runtime_sources.dart';
import 'package:lopicode/state/app_providers.dart';
import 'package:riverpod/riverpod.dart';

class RuntimeNotifier extends Notifier<RuntimeView> {
  LinuxRuntime get _runtime => ref.read(appServicesProvider).runtime;

  @override
  RuntimeView build() {
    final runtime = ref.watch(appServicesProvider).runtime;
    void onChange() {
      if (ref.mounted) state = runtime.view;
    }

    runtime.changeListeners.add(onChange);
    ref.onDispose(() => runtime.changeListeners.remove(onChange));
    return runtime.view;
  }

  /// 下载（能续传）、校验、解压、配置。失败原因进快照的 installError。
  Future<void> install() => _runtime.install();
  void cancelInstall() => _runtime.cancelInstall();
  Future<void> uninstall() => _runtime.uninstall();

  /// 一键装一个常用运行时；返回装没装成。
  Future<bool> installPack(RuntimePack pack) => _runtime.installPack(pack);

  /// 同上，但返回带失败原因的结果（原因也在快照的 packError 里）。
  Future<PackInstallResult> installPackDetailed(RuntimePack pack) => _runtime.installPackDetailed(pack);
  void cancelPack() => _runtime.cancelPack();

  Future<void> setRootfsSource(String id) => _runtime.setRootfsSource(id);
  Future<void> setAptMirror(String id) => _runtime.setAptMirror(id);

  /// 用户点“重新尝试进入 Ubuntu”：清掉失败计数。
  void resetLaunchFailures() => _runtime.resetLaunchFailures();
}

final runtimeProvider = NotifierProvider<RuntimeNotifier, RuntimeView>(RuntimeNotifier.new);

class RuntimeDiagnosticsNotifier extends Notifier<DiagnosticsView> {
  RuntimeDiagnostics get _diagnostics => ref.read(appServicesProvider).runtime.diagnostics;

  @override
  DiagnosticsView build() {
    final diagnostics = ref.watch(appServicesProvider).runtime.diagnostics;
    void onChange() {
      if (ref.mounted) state = diagnostics.view;
    }

    diagnostics.changeListeners.add(onChange);
    ref.onDispose(() => diagnostics.changeListeners.remove(onChange));
    return diagnostics.view;
  }

  /// 跑一遍诊断（已经在跑就不重复跑）。
  Future<void> run({String? projectDir}) => _diagnostics.run(projectDir: projectDir);
}

final runtimeDiagnosticsProvider = NotifierProvider<RuntimeDiagnosticsNotifier, DiagnosticsView>(RuntimeDiagnosticsNotifier.new);
