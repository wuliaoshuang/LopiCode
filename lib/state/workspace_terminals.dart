// 一个工作区开着的终端：有哪些会话、当前是哪个。
//
// 终端会话本身（[TerminalSession]）拿着进程和 xterm 的屏幕缓冲区，是“干活的对象”，不放进不可变状态里复制；
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

  @override
  TerminalsState build() {
    // 工作区关掉（或整个应用退出）时把进程都收掉
    ref.onDispose(() {
      for (final t in _owned) {
        t.dispose();
      }
      _owned.clear();
    });
    // 带界面的工作区一打开就有一个本机会话；不带界面的（自动化任务）不开终端
    if (session.headless || session.disposed) return const TerminalsState();
    return TerminalsState(sessions: List.unmodifiable([_track(_newLocal(forceLocal: false))]));
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

  TerminalSession _newLocal({required bool forceLocal}) {
    final runtime = session.app.runtime;
    final project = session.project;
    if (!forceLocal && runtime.shouldUseLinux) {
      final t = TerminalSession(
        title: 'Ubuntu ${++_linuxCounter}',
        backend: LinuxShellBackend(runtime: runtime, projectDir: project.dir, guestCwd: project.linuxPath, spawner: session.linuxPtySpawner, fallbackSpawner: session.ptySpawner),
      );
      t.append(
        '\x1b[2mLopiCode 终端 · Ubuntu 24.04\n'
        '${project.isLinux ? '工作区目录是 ${project.linuxPath}' : '项目目录挂在 /workspace'}。装软件用 apt，常用运行时可以在侧边栏“运行环境”里一键安装。\x1b[0m\n\n',
      );
      return t;
    }
    final String hint;
    if (runtime.usable) {
      hint = 'Ubuntu 环境连续启动失败，这里先用手机自带的 sh。到侧边栏“运行环境”看日志、重新尝试。';
    } else if (runtime.installed) {
      hint = 'Ubuntu 环境已下载，但这个安装包缺少进入 Ubuntu 要用的文件，进不去。';
    } else {
      hint = '需要 node、python：安装 Ubuntu 环境，或点右上角 ＋ 连接 SSH。';
    }
    final t = TerminalSession(
      title: '本机 ${++_localCounter}',
      backend: LocalShellBackend(project.dir, spawner: session.ptySpawner),
    );
    t.append(
      '\x1b[2mLopiCode 终端 · 本机 shell\n'
      '可用 ls、cat、cp、mkdir；没有 git、node、python。\n'
      '$hint\x1b[0m\n\n',
    );
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

  /// 新开一个本机会话。Ubuntu 环境能用就进 Ubuntu，否则是手机自带的 sh。
  /// [forceLocal] 为 true 时不管环境装没装，都开手机自带的 sh。
  TerminalSession addLocal({bool forceLocal = false}) => _add(_newLocal(forceLocal: forceLocal));

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

  /// 关掉第 [index] 个会话。只剩一个时不关。
  void close(int index) {
    if (!_alive || state.sessions.length <= 1 || index < 0 || index >= state.sessions.length) return;
    final list = [...state.sessions];
    final gone = list.removeAt(index);
    _owned.remove(gone);
    gone.dispose();
    state = state.copyWith(sessions: list, active: state.active.clamp(0, list.length - 1));
  }

  void select(int index) {
    if (!_alive || index < 0 || index >= state.sessions.length) return;
    state = state.copyWith(active: index);
  }
}

/// 某个工作区的终端列表（按工作区分身）。
final terminalsProvider = NotifierProvider.family<TerminalsNotifier, TerminalsState, ProjectSession>(TerminalsNotifier.new);
