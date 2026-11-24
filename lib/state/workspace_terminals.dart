// 一个工作区开着的终端：有哪些会话、当前是哪个。
//
// 终端会话本身（[TerminalSession]）拿着进程和 xterm 的屏幕缓冲区，是“干活的对象”，不放进不可变状态里复制；
// 没有会话是正常状态：安卓上运行环境没装好时不开本机 shell（见 LinuxRuntime.localShellAllowed），终端页显示安装引导。
// 这里的状态只记“有哪些、当前哪个”，外加一个 [TerminalsState.tick]：某个会话的 Ctrl 点亮状态、
// Ubuntu“没有响应”标记变了就加一，终端页订阅它重画。
import 'package:lopicode/project_session.dart';
import 'package:lopicode/runtime/linux_shell_backend.dart';
import 'package:lopicode/ssh/ssh_config.dart';
import 'package:lopicode/ssh/ssh_connector.dart';
import 'package:lopicode/ssh/ssh_shell_backend.dart';
import 'package:lopicode/terminal/terminal_session.dart';
import 'package:riverpod/riverpod.dart';

class TerminalsState {
  const TerminalsState({this.sessions = const [], this.active = 0, this.tick = 0});

  /// 开着的会话（列表本身不可改；要增删走 [TerminalsNotifier]）。
  final List<TerminalSession> sessions;

  /// 当前显示的是第几个。
  final int active;

  /// 某个会话自己的小状态（Ctrl 点亮、“没有响应”）变了的次数。
  final int tick;

  TerminalSession? get current => sessions.isEmpty ? null : sessions[active.clamp(0, sessions.length - 1)];

  TerminalsState copyWith({List<TerminalSession>? sessions, int? active, int? tick}) =>
      TerminalsState(sessions: sessions == null ? this.sessions : List.unmodifiable(sessions), active: active ?? this.active, tick: tick ?? this.tick);
}

class TerminalsNotifier extends Notifier<TerminalsState> {
  TerminalsNotifier(this.session);
  final ProjectSession session;

  int _localCounter = 0;
  int _sshCounter = 0;
  int _linuxCounter = 0;
  bool _wasUsable = false;

  @override
  TerminalsState build() {
    // 工作区关掉（或整个应用退出）时把进程都收掉
    ref.onDispose(() {
      for (final t in _owned) {
        t.dispose();
      }
      _owned.clear();
    });
    // 不带界面的（自动化任务）不开终端
    if (session.headless || session.disposed) return const TerminalsState();
    final runtime = session.app.runtime;
    _wasUsable = runtime.usable;
    runtime.changeListeners.add(_onRuntimeChanged);
    ref.onDispose(() => runtime.changeListeners.remove(_onRuntimeChanged));
    // 带界面的工作区一打开就有一个会话：Ubuntu（装好了）或本机 shell（只在允许的平台，见 LinuxRuntime.localShellAllowed）。
    // 安卓上没装运行环境时一个都不开：终端页显示安装引导。
    final first = _newLocal(forceLocal: false);
    return TerminalsState(sessions: List.unmodifiable([if (first != null) _track(first)]));
  }

  /// 运行环境变了（装好了 / 卸掉了）。只在不许用本机 shell 的平台上有事要做：
  /// - 装好了而还没有 Ubuntu 会话：自动开一个并切过去（安装引导的“装好后直接进终端”）；
  /// - 环境没了：把 Ubuntu 会话都关掉（它们已经进不去了），终端页回到安装引导。
  ///
  /// 只在“能用 ↔ 不能用”翻转的那一下动手：用户自己关掉了 Ubuntu 会话的话，不会因为环境记了一行日志又被开回来。
  void _onRuntimeChanged() {
    final runtime = session.app.runtime;
    final usable = runtime.usable;
    if (usable == _wasUsable) return;
    _wasUsable = usable;
    if (!_alive || runtime.localShellAllowed) return;
    final hasLinux = state.sessions.any((t) => t.backend is LinuxShellBackend);
    if (usable && !hasLinux) {
      addLocal();
    } else if (!usable && hasLinux) {
      final keep = <TerminalSession>[];
      for (final t in state.sessions) {
        if (t.backend is LinuxShellBackend) {
          _owned.remove(t);
          t.dispose();
        } else {
          keep.add(t);
        }
      }
      state = state.copyWith(sessions: keep, active: keep.isEmpty ? 0 : state.active.clamp(0, keep.length - 1));
    }
  }

  /// 这里建的会话，销毁时要负责关掉。
  final List<TerminalSession> _owned = [];

  bool get _alive => ref.mounted && !session.disposed;

  void _tick() {
    if (_alive) state = state.copyWith(tick: state.tick + 1);
  }

  TerminalSession _track(TerminalSession t) {
    _owned.add(t);
    t.onChanged = _tick;
    final backend = t.backend;
    if (backend is LinuxShellBackend) backend.onStalledChanged = _tick;
    return t;
  }

  /// 造一个新会话（还没放进列表）。不许用本机 shell 而环境又不能用时返回 null。
  TerminalSession? _newLocal({required bool forceLocal}) {
    final runtime = session.app.runtime;
    final project = session.project;
    if (!runtime.localShellAllowed && !runtime.usable) return null;
    // 不许用本机 shell 的平台：只要环境能用就进 Ubuntu，之前连续失败过也照样试（失败了显示原因和出路，不退回本机）。
    if (!runtime.localShellAllowed || (!forceLocal && runtime.shouldUseLinux)) {
      // 不打欢迎语：打开就是 Ubuntu 自己的提示符（霜霜 2026-11-24：提示符前面的字“莫名其妙”）。
      return TerminalSession(
        title: 'Ubuntu ${++_linuxCounter}',
        backend: LinuxShellBackend(runtime: runtime, projectDir: project.dir, guestCwd: project.linuxPath, spawner: session.linuxPtySpawner, fallbackSpawner: session.ptySpawner),
      );
    }
    final t = TerminalSession(
      title: '本机 ${++_localCounter}',
      backend: LocalShellBackend(project.dir, spawner: session.ptySpawner),
    );
    // 本机 shell（只在桌面调试、宿主机测试里有）同样不打欢迎语；只有“本该进 Ubuntu 却进不去”才说一句原因。
    // 用户自己点“本机 shell”开的（forceLocal）不算进不去，什么都不说。
    if (forceLocal) return t;
    if (runtime.usable) {
      t.append('\x1b[2mUbuntu 环境连续启动失败，这里先用本机的 sh。到侧边栏“运行环境”看日志、重新尝试。\x1b[0m\n\n');
    } else if (runtime.installed) {
      t.append('\x1b[2mUbuntu 环境已下载，但这个安装包缺少进入 Ubuntu 要用的文件，进不去；这里先用本机的 sh。\x1b[0m\n\n');
    }
    return t;
  }

  TerminalSession _add(TerminalSession t) {
    _track(t);
    if (_alive) {
      state = state.copyWith(sessions: [...state.sessions, t], active: state.sessions.length);
    } else {
      // 工作区已经关了：不留着没人管的进程
      _owned.remove(t);
      t.dispose();
    }
    return t;
  }

  /// 新开一个会话。Ubuntu 环境能用就进 Ubuntu；否则在允许本机 shell 的平台（桌面调试、宿主机测试）开本机 shell。
  /// 安卓上环境不能用时什么都不开，返回 null（调用方切到终端页，那里是安装引导）。
  /// [forceLocal] 为 true 时不管环境装没装都开本机 shell——同样只在允许的平台有效。
  TerminalSession? addLocal({bool forceLocal = false}) {
    final t = _newLocal(forceLocal: forceLocal);
    return t == null ? null : _add(t);
  }

  /// 新开一个 SSH 会话。[onUnknownHost] 在第一次连这台主机时弹指纹确认。
  TerminalSession addSsh(SshConfig config, {HostKeyPrompt? onUnknownHost}) {
    final app = session.app;
    return _add(
      TerminalSession(
        title: 'SSH ${++_sshCounter}',
        backend: SshShellBackend(
          hostLabel: config.display,
          connect: () => connectSsh(config: config, secrets: app.secrets, knownHosts: KnownHosts(app.settings), onUnknownHost: onUnknownHost),
        ),
      ),
    );
  }

  /// 关掉第 [index] 个会话。只剩一个时不关——除非终端页此刻本来就该显示安装引导
  /// （安卓上环境没装好，剩下的只会是 SSH 会话），那时可以关到一个不剩。
  void close(int index) {
    final min = session.app.runtime.needsSetup ? 0 : 1;
    if (!_alive || state.sessions.length <= min || index < 0 || index >= state.sessions.length) return;
    final list = [...state.sessions];
    final gone = list.removeAt(index);
    _owned.remove(gone);
    gone.dispose();
    state = state.copyWith(sessions: list, active: list.isEmpty ? 0 : state.active.clamp(0, list.length - 1));
  }

  void select(int index) {
    if (!_alive || index < 0 || index >= state.sessions.length) return;
    state = state.copyWith(active: index);
  }
}

/// 某个工作区的终端列表（按工作区分身）。
final terminalsProvider = NotifierProvider.family<TerminalsNotifier, TerminalsState, ProjectSession>(TerminalsNotifier.new);
