// 后端“运行前自动配工具”的测试用具：假的 Ubuntu 进程（不进 PRoot、不联网）和一套安卓规矩的应用环境。
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:lopicode/app_services.dart';
import 'package:lopicode/core/project_store.dart';
import 'package:lopicode/core/safe_file.dart';
import 'package:lopicode/core/stores.dart';
import 'package:lopicode/project_session.dart';
import 'package:lopicode/runtime/linux_runtime.dart';
import 'package:lopicode/runtime/proot_command.dart';
import 'package:lopicode/runtime/runtime_sources.dart';
import 'package:lopicode/state/backend_run.dart';
import 'package:path/path.dart' as p;

import 'runtime_fakes.dart';

/// 假的进程：测试自己决定它说什么、什么时候退出。
class FakeProc implements Process {
  final StreamController<List<int>> _out = StreamController();
  final StreamController<List<int>> _err = StreamController();
  final Completer<int> _exit = Completer();
  bool killed = false;

  void say(String text) => _out.add(utf8.encode(text));
  void complain(String text) => _err.add(utf8.encode(text));

  void finish(int code) {
    if (_exit.isCompleted) return;
    unawaited(_out.close());
    unawaited(_err.close());
    _exit.complete(code);
  }

  @override
  Stream<List<int>> get stdout => _out.stream;
  @override
  Stream<List<int>> get stderr => _err.stream;
  @override
  Future<int> get exitCode => _exit.future;
  @override
  int get pid => 4242;
  @override
  IOSink get stdin => throw UnsupportedError('假进程没有 stdin');
  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    killed = true;
    finish(-9);
    return true;
  }
}

/// 假的 Ubuntu：记下要它跑的每一段脚本。`command -v …` 的核对按 [present] 立刻回答；
/// 别的（安装脚本）交给测试自己控制（[installs] 里拿到进程，自己 say / finish）。
class FakeGuest {
  /// 环境里“已经有”的命令。
  final Set<String> present = {};
  final List<String> scripts = [];
  final List<FakeProc> installs = [];

  /// 安装脚本的进程起不来。
  bool failInstallStart = false;

  /// 核对的进程起不来（模拟 Ubuntu 进不去）。
  bool failProbeStart = false;

  /// 设了以后核对不马上回答，等测试 `complete()`。
  Completer<void>? holdProbe;

  int get probes => scripts.where((s) => s.startsWith('command -v')).length;

  Future<Process> start(ProotCommand command) async {
    final script = command.arguments.last;
    scripts.add(script);
    final probe = script.startsWith('command -v');
    if (probe ? failProbeStart : failInstallStart) throw ProcessException(command.executable, const [], '假的：起不来');
    final proc = FakeProc();
    if (probe) {
      final names = RegExp(r'command -v (\S+)').allMatches(script).map((m) => m[1]!);
      final hold = holdProbe;
      unawaited((hold?.future ?? Future<void>.value()).then((_) => proc.finish(names.every(present.contains) ? 0 : 1)));
    } else {
      installs.add(proc);
    }
    return proc;
  }
}

/// 一联网就让测试失败的客户端。
class NoNetworkClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) => throw StateError('测试里不许联网：${request.url}');
}

/// 剩余空间可以中途改的假宿主。
class AdjustableHost extends FakeRuntimeHost {
  AdjustableHost({super.nativeDir, int? free}) : freeNow = free;
  int? freeNow;
  @override
  Future<int?> freeBytes(String path) async => freeNow;
}

/// 安卓规矩（不许用本机 shell）的应用环境 + 假 Ubuntu。
class RunEnv {
  RunEnv._(this.tmp, this.services, this.host, this.guest);
  final Directory tmp;
  final AppServices services;
  final AdjustableHost host;
  final FakeGuest guest;
  LinuxRuntime get runtime => services.runtime;

  /// 开过的假伪终端和往里打过的字。
  final List<FakePty> ptys = [];
  List<String> get typed => [
    for (final pty in ptys)
      if (pty.written.isNotEmpty) utf8.decode(pty.written),
  ];

  static Future<RunEnv> create({
    bool android = true,
    bool installed = true,
    bool proot = true,
    int? free = 23 * 1024 * 1024 * 1024,
    http.Client Function()? httpClient,
    RootfsImage image = RootfsImage.ubuntu2404Arm64,
  }) async {
    final tmp = Directory.systemTemp.createTempSync('lopi_run_');
    final settings = SettingsStore(File(p.join(tmp.path, 'settings.json')));
    await settings.load();
    final host = AdjustableHost(nativeDir: proot ? makeFakeNativeDir(tmp) : tmp.path, free: free);
    final guest = FakeGuest();
    final runtime = LinuxRuntime(
      settings: settings,
      baseDir: p.join(tmp.path, 'runtime'),
      host: host,
      httpClient: httpClient ?? NoNetworkClient.new,
      image: image,
      localShellAllowed: android ? false : null,
      startProcess: guest.start,
    );
    if (installed) markInstalled(runtime);
    await runtime.init();
    final services = AppServices(settings: settings, secrets: MemorySecretStore(), projects: ProjectStore(p.join(tmp.path, 'projects')), runtime: runtime);
    await services.ready();
    services.modelSetupPrompted = true;
    return RunEnv._(tmp, services, host, guest);
  }

  /// 给工作区接上假伪终端（Ubuntu 的和本机的都接）。
  void wire(ProjectSession session) {
    session.linuxPtySpawner = (exe, args, {required workingDirectory, required environment, required rows, required columns}) {
      final pty = FakePty();
      ptys.add(pty);
      return pty;
    };
    session.ptySpawner = (exe, {required workingDirectory, required environment, required rows, required columns}) {
      final pty = FakePty();
      ptys.add(pty);
      return pty;
    };
  }

  /// 摆出“这一项已经装好”的样子（环境里有那个文件）。
  void markPack(String id) {
    final pack = runtimePackById(runtime.packs, id)!;
    File(p.join(runtime.rootfsDir, pack.marker))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('x');
  }

  BackendRunState run(ProjectSession session) => services.container.read(backendRunProvider(session));
  BackendRunNotifier ctl(ProjectSession session) => services.container.read(backendRunProvider(session).notifier);

  Future<void> dispose() async {
    services.dispose();
    await pendingWrites();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  }
}

/// 让真实的异步（微任务、流事件、文件读写）走一会儿。
Future<void> tick([int ms = 20]) => Future<void>.delayed(Duration(milliseconds: ms));

/// 等到条件成立；一直不成立就抛错。
Future<void> waitFor(bool Function() done, String what, {int tries = 400}) async {
  for (var i = 0; i < tries && !done(); i++) {
    await tick(10);
  }
  if (!done()) throw StateError('等不到：$what');
}
