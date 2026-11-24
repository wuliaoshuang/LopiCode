// 运行环境和一键诊断“某一刻的样子”（不可变）。界面订阅的就是这两个，见 lib/state/runtime_state.dart。
//
// 进程、下载、解压这些活还是 LinuxRuntime / RuntimeDiagnostics 在干（它们管着进程和文件）；
// 每次有变化，它们拍一张这样的快照送出去。界面拿到的东西改不了。
import 'package:lopicode/runtime/runtime_sources.dart';

enum RuntimePhase { notInstalled, downloading, verifying, extracting, installed }

class RuntimeView {
  RuntimeView({
    required this.phase,
    required this.progressDone,
    required this.progressTotal,
    required this.installError,
    required this.prootBundled,
    required List<String> missingLauncherFiles,
    required this.freeSpace,
    required this.partialBytes,
    required this.imageSize,
    required this.rootfsSourceId,
    required this.aptMirrorId,
    required List<RuntimePack> packs,
    required Set<String> installedPacks,
    required this.runningPack,
    required List<String> packOutput,
    required this.launchFailures,
    required this.lastLaunchError,
    required this.shouldUseLinux,
    required this.compatMode,
    required List<String> logLines,
    this.localShellAllowed = true,
    this.compatPinned = false,
    this.packErrorId,
    this.packError,
  }) : missingLauncherFiles = List.unmodifiable(missingLauncherFiles),
       packs = List.unmodifiable(packs),
       installedPacks = Set.unmodifiable(installedPacks),
       packOutput = List.unmodifiable(packOutput),
       logLines = List.unmodifiable(logLines);

  final RuntimePhase phase;
  final int progressDone;
  final int progressTotal;

  /// 上一次安装失败的原因（给用户看的大白话）。
  final String? installError;

  /// 安装包里带没带进入 Ubuntu 要用的那几个文件。
  final bool prootBundled;
  final List<String> missingLauncherFiles;
  final int? freeSpace;

  /// 下到一半留着的字节数。
  final int partialBytes;
  final int imageSize;
  final String rootfsSourceId;
  final String aptMirrorId;

  /// 能一键装的运行时，和其中已经装好的那些（id）。
  final List<RuntimePack> packs;
  final Set<String> installedPacks;

  /// 正在装的运行时（id）和它的输出。
  final String? runningPack;
  final List<String> packOutput;

  /// 上一次没装成的是哪一项（id）和原因（大白话）；装成功、重新开始装或用户取消的都是 null。
  final String? packErrorId;
  final String? packError;

  final int launchFailures;
  final String? lastLaunchError;

  /// 新开的终端该不该进 Ubuntu（装好了、进得去、没有连续失败）。
  final bool shouldUseLinux;
  final bool compatMode;
  final List<String> logLines;

  /// 能不能用本机 shell（安卓上不能，见 `LinuxRuntime.localShellAllowed`）。
  final bool localShellAllowed;

  /// 兼容模式是不是已经定下来了（这时“重试”就是兼容模式）。
  final bool compatPinned;

  /// 必须先装好运行环境才有终端可用。
  bool get needsSetup => !localShellAllowed && !usable;

  bool get installed => phase == RuntimePhase.installed;
  bool get busy => phase == RuntimePhase.downloading || phase == RuntimePhase.verifying || phase == RuntimePhase.extracting;

  /// 装好了并且进得去。
  bool get usable => installed && prootBundled;
  bool packInstalled(RuntimePack pack) => installedPacks.contains(pack.id);
}

class DiagnosticsView {
  DiagnosticsView({required this.running, required this.progress, required this.stepCount, required List<String> conclusions, required this.hasReport, required this.report, required this.finishedAt})
    : conclusions = List.unmodifiable(conclusions);

  final bool running;

  /// 正在查的那一项的名字，和它是第几项。
  final String progress;
  final int stepCount;

  /// 最后的结论（一两句大白话）。
  final List<String> conclusions;
  final bool hasReport;

  /// 整份报告的文字（复制、截图都用它）。
  final String report;
  final DateTime? finishedAt;
}
