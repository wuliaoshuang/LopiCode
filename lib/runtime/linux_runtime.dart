import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:lopicode/core/safe_file.dart';
import 'package:lopicode/core/stores.dart';
import 'package:lopicode/runtime/proot_command.dart';
import 'package:lopicode/runtime/resumable_download.dart';
import 'package:lopicode/runtime/runtime_diagnostics.dart';
import 'package:lopicode/runtime/runtime_sources.dart';
import 'package:lopicode/runtime/tar_extract.dart';
import 'package:path/path.dart' as p;

/// 运行环境需要问系统的几件事。真机走平台通道，测试里换成假的。
abstract class RuntimeHost {
  /// 安装包自带的原生库目录；拿不到返回 null。
  Future<String?> nativeLibraryDir();

  /// [path] 所在分区的剩余空间；拿不到返回 null。
  Future<int?> freeBytes(String path);

  /// 开 / 关“保持后台运行”的前台服务（常驻通知）。
  Future<void> startKeepAlive(String text);
  Future<void> stopKeepAlive();

  /// 手机型号、系统版本这类信息（诊断用）；拿不到返回空表。
  Future<Map<String, String>> deviceInfo();
}

class ChannelRuntimeHost implements RuntimeHost {
  static const _channel = MethodChannel('lopicode/runtime');

  Future<T?> _call<T>(String method, [Object? arguments]) async {
    try {
      return await _channel.invokeMethod<T>(method, arguments);
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  @override
  Future<String?> nativeLibraryDir() => _call<String>('nativeLibraryDir');

  @override
  Future<int?> freeBytes(String path) => _call<int>('freeBytes', path);

  @override
  Future<void> startKeepAlive(String text) => _call<void>('startKeepAlive', text);

  @override
  Future<void> stopKeepAlive() => _call<void>('stopKeepAlive');

  @override
  Future<Map<String, String>> deviceInfo() async {
    final raw = await _call<Map<Object?, Object?>>('deviceInfo');
    return {for (final e in (raw ?? const {}).entries) '${e.key}': '${e.value}'};
  }
}

/// 什么都没有的宿主（测试、非 Android 平台）。
class NoRuntimeHost implements RuntimeHost {
  const NoRuntimeHost();
  @override
  Future<String?> nativeLibraryDir() async => null;
  @override
  Future<int?> freeBytes(String path) async => null;
  @override
  Future<void> startKeepAlive(String text) async {}
  @override
  Future<void> stopKeepAlive() async {}
  @override
  Future<Map<String, String>> deviceInfo() async => const {};
}

enum RuntimePhase { notInstalled, downloading, verifying, extracting, installed }

/// 本机 Linux 运行环境（PRoot + Ubuntu 24.04）的安装、状态和启动方式。
class LinuxRuntime extends ChangeNotifier {
  LinuxRuntime({
    required this.settings,
    required this.baseDir,
    this.host = const NoRuntimeHost(),
    http.Client Function()? httpClient,
    this.image = RootfsImage.ubuntu2404Arm64,
    this.makeExecutable = chmodExecutable,
  }) : _httpClient = httpClient ?? http.Client.new;

  final SettingsStore settings;

  /// 运行环境的全部文件都在这个目录下（应用私有目录里）。
  final String baseDir;
  final RuntimeHost host;
  final RootfsImage image;
  final MakeExecutable makeExecutable;
  final http.Client Function() _httpClient;

  /// 连续启动失败到这个次数，就不再自动进 Ubuntu，退回本机 shell。
  static const int maxLaunchFailures = 2;

  String get rootfsDir => p.join(baseDir, 'rootfs');
  String get tmpDir => p.join(baseDir, 'tmp');

  /// 放 `libtalloc.so.2` 链接的目录（见 [ProotFiles.tallocSoname]）。
  String get hostLibDir => p.join(baseDir, 'hostlib');
  File get _marker => File(p.join(baseDir, 'rootfs.version'));
  File get _archive => File(p.join(baseDir, 'download', image.fileName));
  File get logFile => File(p.join(baseDir, 'runtime.log'));

  RuntimePhase phase = RuntimePhase.notInstalled;
  int progressDone = 0;
  int progressTotal = 0;

  /// 上一次安装失败的真实原因；没有失败是 null。
  String? installError;
  String? nativeLibDir;
  bool prootBundled = false;

  /// 安装包里缺了哪几个 PRoot 文件（齐全时是空的）。
  List<String> missingLauncherFiles = ProotFiles.bundled;
  int? freeSpace;
  CancelToken? _cancel;

  bool get installed => phase == RuntimePhase.installed;
  bool get busy =>
      phase == RuntimePhase.downloading || phase == RuntimePhase.verifying || phase == RuntimePhase.extracting;

  // ── 下载源 ───────────────────────────────────────────
  MirrorOption get rootfsSource => mirrorById(rootfsSources, settings.getString(SettingKeys.runtimeRootfsSource));
  MirrorOption get aptMirror => mirrorById(aptMirrors, settings.getString(SettingKeys.runtimeAptMirror));

  Future<void> setRootfsSource(String id) async {
    await settings.set(SettingKeys.runtimeRootfsSource, id);
    notifyListeners();
  }

  Future<void> setAptMirror(String id) async {
    await settings.set(SettingKeys.runtimeAptMirror, id);
    if (installed) await _writeAptSources();
    notifyListeners();
  }

  // ── 状态 ─────────────────────────────────────────────
  Future<void> init() async {
    nativeLibDir = await host.nativeLibraryDir();
    final dir = nativeLibDir;
    missingLauncherFiles = dir == null
        ? ProotFiles.bundled
        : [
            for (final name in ProotFiles.bundled)
              if (!File(p.join(dir, name)).existsSync()) name,
          ];
    prootBundled = missingLauncherFiles.isEmpty;
    if (!busy) {
      phase = _marker.existsSync() && Directory(rootfsDir).existsSync()
          ? RuntimePhase.installed
          : RuntimePhase.notInstalled;
    }
    freeSpace = await host.freeBytes(Directory(baseDir).parent.path);
    notifyListeners();
  }

  /// 没下完的压缩包已经有多少字节（界面上显示“可以接着下”）。
  int get partialBytes {
    final part = ResumableDownload.partFile(_archive);
    return part.existsSync() ? part.lengthSync() : 0;
  }

  // ── 安装 / 卸载 ──────────────────────────────────────
  Future<void> install() async {
    if (busy) return;
    installError = null;
    final cancel = _cancel = CancelToken();
    final client = _httpClient();
    try {
      final free = await host.freeBytes(Directory(baseDir).parent.path);
      freeSpace = free;
      if (free != null && free < RootfsImage.requiredBytes) {
        throw DownloadException('手机剩余空间不够：需要约 ${formatBytes(RootfsImage.requiredBytes)}，现在只剩 ${formatBytes(free)}');
      }
      await Directory(baseDir).create(recursive: true);
      final url = Uri.parse('${rootfsSource.base}/${image.fileName}');
      _log('开始安装：从 ${rootfsSource.label} 下载 ${image.fileName}');
      _setPhase(RuntimePhase.downloading, partialBytes, image.size);
      var lastNotified = 0;
      await ResumableDownload(client).fetch(
        url,
        _archive,
        expectedSize: image.size,
        expectedSha256: image.sha256,
        cancel: cancel,
        onProgress: (received, total) {
          progressDone = received;
          progressTotal = total;
          if (received == total) phase = RuntimePhase.verifying;
          // 进度回调很密，隔 64 KB 才刷新一次界面。
          if (received - lastNotified >= 65536 || received == total) {
            lastNotified = received;
            notifyListeners();
          }
        },
      );
      _log('下载完成，校验通过（sha256 ${image.sha256.substring(0, 12)}…）');

      final staging = Directory(p.join(baseDir, 'rootfs.staging'));
      if (await staging.exists()) await staging.delete(recursive: true);
      if (await _marker.exists()) await _marker.delete();
      _setPhase(RuntimePhase.extracting, 0, image.size);
      final result = await extractTarGz(
        _archive,
        staging,
        makeExecutable: makeExecutable,
        isCancelled: () => cancel.isCancelled,
        onProgress: (consumed, total) {
          if (consumed - progressDone >= 262144 || consumed == total) {
            progressDone = consumed;
            notifyListeners();
          }
        },
      );
      final old = Directory(rootfsDir);
      if (await old.exists()) await old.delete(recursive: true);
      await staging.rename(rootfsDir);
      await _configureGuest();
      await writeJsonAtomic(_marker, {'version': image.version, 'sha256': image.sha256});
      await _archive.delete();
      _log('解压完成：${result.files} 个文件，${formatBytes(result.bytes)}（跳过 ${result.skipped} 个设备文件）');
      launchFailures = 0;
      lastLaunchError = null;
      _setPhase(RuntimePhase.installed, 0, 0);
    } on DownloadException catch (e) {
      _fail(e.message, cancelled: e.cancelled);
    } on TarException catch (e) {
      _fail(cancel.isCancelled ? '已取消安装' : '解压失败：${e.message}', cancelled: cancel.isCancelled);
    } on FileSystemException catch (e) {
      _fail('写文件失败：${e.osError?.message ?? e.message}');
    } finally {
      client.close();
      _cancel = null;
    }
  }

  void cancelInstall() => _cancel?.cancel();

  void _fail(String message, {bool cancelled = false}) {
    installError = cancelled ? null : message;
    _log(cancelled ? '安装已取消' : '安装失败：$message');
    _setPhase(RuntimePhase.notInstalled, 0, 0);
  }

  void _setPhase(RuntimePhase next, int done, int total) {
    phase = next;
    progressDone = done;
    progressTotal = total;
    notifyListeners();
  }

  /// 删掉整个环境（包括里面装的 Node、Python 和下到一半的压缩包）。项目文件不在这里面，不受影响。
  Future<void> uninstall() async {
    if (busy) return;
    final dir = Directory(baseDir);
    if (await dir.exists()) await dir.delete(recursive: true);
    launchFailures = 0;
    lastLaunchError = null;
    installError = null;
    _setPhase(RuntimePhase.notInstalled, 0, 0);
  }

  /// 解压后的收尾：域名解析、本机名、apt 源，以及 PRoot 需要的两个目录。
  Future<void> _configureGuest() async {
    final etc = p.join(rootfsDir, 'etc');
    await Directory(p.join(rootfsDir, 'tmp')).create(recursive: true);
    await Directory(p.join(rootfsDir, 'workspace')).create(recursive: true);
    await Directory(tmpDir).create(recursive: true);
    await _writeReplacing(p.join(etc, 'resolv.conf'), guestResolvConf);
    await _writeReplacing(p.join(etc, 'hosts'), '127.0.0.1 localhost\n::1 localhost ip6-localhost ip6-loopback\n');
    // 环境里没有真正的多用户，apt 默认要切到 _apt 用户下载，会失败；让它直接用 root。
    await _writeReplacing(p.join(etc, 'apt', 'apt.conf.d', '99lopicode'), 'APT::Sandbox::User "root";\n');
    await _writeAptSources();
  }

  Future<void> _writeAptSources() =>
      _writeReplacing(p.join(rootfsDir, 'etc', 'apt', 'sources.list.d', 'ubuntu.sources'), aptSourcesFor(aptMirror));

  Future<void> _writeReplacing(String path, String content) async {
    // 目标可能是个符号链接（比如 resolv.conf），先删掉再写，免得写到链接指向的别处去。
    if (await FileSystemEntity.type(path, followLinks: false) == FileSystemEntityType.link) await Link(path).delete();
    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsString(content);
  }

  // ── 常用运行时 ───────────────────────────────────────
  List<RuntimePack> get packs => runtimePacks(rootfsSource.id);

  bool packInstalled(RuntimePack pack) =>
      installed && FileSystemEntity.typeSync(p.join(rootfsDir, pack.marker), followLinks: false) != FileSystemEntityType.notFound;

  String? runningPack;
  final List<String> packOutput = [];
  Process? _packProcess;

  /// 在环境里执行某个运行时的安装脚本，输出实时进 [packOutput]。返回是否成功。
  Future<bool> installPack(RuntimePack pack) async {
    if (runningPack != null || !usable) return false;
    runningPack = pack.id;
    packOutput
      ..clear()
      ..add('开始安装 ${pack.title}…');
    notifyListeners();
    await acquireKeepAlive();
    var ok = false;
    try {
      final command = prootCommand(guestCommand: guestRun(pack.script), term: 'dumb');
      final process = _packProcess = await Process.start(
        command.executable,
        command.arguments,
        environment: command.environment,
        includeParentEnvironment: false,
      );
      void collect(String line) {
        packOutput.add(line);
        if (packOutput.length > 400) packOutput.removeRange(0, packOutput.length - 400);
        notifyListeners();
      }

      const decoder = Utf8Decoder(allowMalformed: true);
      final out = process.stdout.transform(decoder).transform(const LineSplitter()).listen(collect, onError: (_) {});
      final err = process.stderr.transform(decoder).transform(const LineSplitter()).listen(collect, onError: (_) {});
      final code = await process.exitCode;
      await Future.wait([out.asFuture<void>(), err.asFuture<void>()]).timeout(const Duration(seconds: 2), onTimeout: () => const []);
      await out.cancel();
      await err.cancel();
      ok = code == 0;
      collect(ok ? '${pack.title} 安装完成。' : '${pack.title} 安装失败（退出码 $code）。上面是完整输出。');
      _log('安装 ${pack.title}：${ok ? '成功' : '失败，退出码 $code'}');
    } on ProcessException catch (e) {
      packOutput.add('无法启动 PRoot：${e.message}');
      _log('安装 ${pack.title}：无法启动 PRoot：${e.message}');
    } finally {
      _packProcess = null;
      runningPack = null;
      await releaseKeepAlive();
      notifyListeners();
    }
    return ok;
  }

  void cancelPack() => _packProcess?.kill(ProcessSignal.sigkill);

  // ── 启动 ─────────────────────────────────────────────
  int launchFailures = 0;
  String? lastLaunchError;

  /// 环境装好了，安装包里也带着 PRoot。
  bool get usable => installed && prootBundled;

  /// 新开终端 / Agent 跑命令时要不要进 Ubuntu：能用，而且没有连续启动失败。
  bool get shouldUseLinux => usable && launchFailures < maxLaunchFailures;

  /// 第一次失败后的下一次尝试改用兼容模式。
  bool get compatMode => forceCompat || launchFailures > 0 || settings.getBool(SettingKeys.runtimeCompat);

  /// 用户在“没有响应”的提示里点了“改用兼容模式重试”：这次运行期间都用兼容模式。
  bool forceCompat = false;

  /// 兼容模式确实能用（终端里有了输出，或诊断跑通）：记住，以后默认用它。
  Future<void> rememberCompat(String why) async {
    if (settings.getBool(SettingKeys.runtimeCompat)) return;
    await settings.set(SettingKeys.runtimeCompat, true);
    _log('$why，以后默认用兼容模式');
    notifyListeners();
  }

  /// 进了 Ubuntu 但一直没有任何输出（卡住了）。不算进“连续失败”，只记日志。
  void recordStall(Duration waited) {
    _log('进入 Ubuntu 后 ${waited.inSeconds} 秒没有任何输出（${compatMode ? '兼容模式' : '默认模式'}）。可以到“运行环境”页点“一键诊断”');
    notifyListeners();
  }

  /// 给别处往运行环境日志里记一行。
  void log(String message) {
    _log(message);
    notifyListeners();
  }

  /// 让 [hostLibDir] 里的 `libtalloc.so.2` 指向安装包里现在的 talloc 库。
  ///
  /// 应用每次更新，原生库目录的路径都会变，所以每次启动前都核对一遍。建不了链接
  /// （个别文件系统不支持）就改成复制一份。返回 null 表示就绪，否则是失败原因。
  String? prepareLauncherLibs() {
    final native = nativeLibDir;
    if (native == null) return '拿不到安装包的原生库目录';
    final target = p.join(native, ProotFiles.talloc);
    final linkPath = p.join(hostLibDir, ProotFiles.tallocSoname);
    try {
      Directory(hostLibDir).createSync(recursive: true);
      final type = FileSystemEntity.typeSync(linkPath, followLinks: false);
      if (type == FileSystemEntityType.link) {
        if (Link(linkPath).targetSync() == target) return null;
        Link(linkPath).deleteSync();
      } else if (type != FileSystemEntityType.notFound) {
        // 上次是复制的：安装包里的库没变就不用再动。
        final source = File(target);
        if (type == FileSystemEntityType.file && source.existsSync() && File(linkPath).lengthSync() == source.lengthSync()) {
          return null;
        }
        File(linkPath).deleteSync();
      }
      try {
        Link(linkPath).createSync(target);
      } on FileSystemException {
        File(target).copySync(linkPath);
      }
      return null;
    } on FileSystemException catch (e) {
      final reason = '准备 PRoot 依赖的库失败：${e.osError?.message ?? e.message}';
      _log(reason);
      return reason;
    }
  }

  ProotCommand prootCommand({required List<String> guestCommand, String? projectDir, String? guestCwd, String term = 'xterm-256color'}) {
    prepareLauncherLibs();
    return buildProotCommand(
        nativeLibDir: nativeLibDir ?? '',
        libDir: hostLibDir,
        rootfs: rootfsDir,
        tmpDir: tmpDir,
        guestCommand: guestCommand,
        projectDir: projectDir,
        guestCwd: guestCwd,
        term: term,
        noSeccomp: compatMode,
      );
  }

  /// 一次启动成功（进去后稳定运行了几秒，或者命令正常结束）。
  void recordLaunchSuccess() {
    if ((launchFailures > 0 || forceCompat) && !settings.getBool(SettingKeys.runtimeCompat)) {
      // 是兼容模式救回来的：记住，以后直接用兼容模式。
      unawaited(settings.set(SettingKeys.runtimeCompat, true));
      _log('兼容模式启动成功，以后默认用兼容模式');
    }
    if (launchFailures != 0 || lastLaunchError != null) {
      launchFailures = 0;
      lastLaunchError = null;
      notifyListeners();
    }
  }

  /// 一次启动失败：记下原因和 PRoot 的输出。
  void recordLaunchFailure(String reason, {String output = ''}) {
    launchFailures++;
    lastLaunchError = reason;
    _log('启动失败（第 $launchFailures 次${compatMode && launchFailures > 1 ? '，兼容模式' : ''}）：$reason');
    final trimmed = output.trim();
    if (trimmed.isNotEmpty) _log('PRoot 输出：\n$trimmed');
    if (launchFailures >= maxLaunchFailures) _log('连续 $launchFailures 次启动失败，新开的终端先退回本机 shell');
    notifyListeners();
  }

  /// 用户点“再试一次 Ubuntu”：清掉失败计数。
  void resetLaunchFailures() {
    launchFailures = 0;
    lastLaunchError = null;
    _log('已重置启动失败计数');
    notifyListeners();
  }

  // ── 一键诊断 ─────────────────────────────────────────
  RuntimeDiagnostics? _diagnostics;

  /// 诊断的状态挂在这里，离开“运行环境”页再回来结果还在。
  RuntimeDiagnostics get diagnostics => _diagnostics ??= RuntimeDiagnostics(this);
  set diagnostics(RuntimeDiagnostics value) => _diagnostics = value;

  // ── 后台保活 ─────────────────────────────────────────
  int _keepAlive = 0;

  Future<void> acquireKeepAlive() async {
    if (_keepAlive++ == 0) await host.startKeepAlive('Ubuntu 环境运行中');
  }

  Future<void> releaseKeepAlive() async {
    if (_keepAlive == 0) return;
    if (--_keepAlive == 0) await host.stopKeepAlive();
  }

  // ── 日志 ─────────────────────────────────────────────
  final List<String> logLines = [];

  void _log(String message) {
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    final line = '${two(now.hour)}:${two(now.minute)}:${two(now.second)} $message';
    logLines.add(line);
    if (logLines.length > 200) logLines.removeRange(0, logLines.length - 200);
    try {
      final file = logFile;
      if (file.parent.existsSync()) {
        if (file.existsSync() && file.lengthSync() > 256 * 1024) file.deleteSync();
        file.writeAsStringSync('${now.toIso8601String()} $message\n', mode: FileMode.append);
      }
    } on FileSystemException {
      // 日志写不进去不影响功能
    }
  }
}

String formatBytes(int bytes) {
  if (bytes >= 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  if (bytes >= 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '$bytes B';
}
