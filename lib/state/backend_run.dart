// 后端“运行”：先把这种语言的工具配好，再在终端里启动（按工作区分身）。
//
// 点“运行”以后依次做这几件事，哪一步不用做就跳过：
//   1. Ubuntu 运行环境没装：自动开始装（下载约 29 MB，不到要先问的门槛），终端页这时是安装引导，进度和“取消”都在那里。
//      装好自动往下走；她在引导里点了“取消”就整个停下；装失败（原因引导里有）就等她在引导里再点一次安装，装好还是接着走。
//   2. 核对这种语言的工具在不在：先看环境里有没有那个文件（不用进 Ubuntu，已装的直接启动、不多一步），
//      没有再进 Ubuntu 用 `command -v` 问一遍（她自己用别的办法装的也认）。
//   3. 不在就装（清单和脚本在 lib/runtime/runtime_sources.dart）。下载量过了 `kPackConfirmBytes` 的先问一次。
//      输出一行行抄进“后端”终端；可以取消；失败带真正的原因，可以重试。
//   4. 在“后端”终端里打启动命令。
//
// 允许本机 shell 的平台（桌面调试、宿主机测试）上环境没装时，和以前一样直接把命令打进本机 shell，不核对也不装。
//
// 防并发和防“销毁后写状态”：
//   - 同一时间只有一次在进行：进行中再点“运行”不受理（不会装两遍）；
//   - 每次开始 / 放弃都换一个代次，`await` 回来代次对不上、或工作区 / 应用已经关了，就什么都不写、不往终端里打字。
import 'dart:async';

import 'package:lopicode/backend/backend_launch.dart';
import 'package:lopicode/project_session.dart';
import 'package:lopicode/runtime/linux_runtime.dart';
import 'package:lopicode/runtime/pack_install.dart';
import 'package:lopicode/runtime/runtime_sources.dart';
import 'package:lopicode/terminal/terminal_session.dart';
import 'package:riverpod/riverpod.dart';

enum BackendRunPhase {
  /// 没有在准备。
  idle,

  /// 在等 Ubuntu 运行环境装好。
  waitingRuntime,

  /// 在核对工具装没装（或在等别处正在装的东西装完）。
  checking,

  /// 要装的东西比较大，等用户点头。
  confirming,

  /// 正在装。
  installing,

  /// 没装成；[BackendRunState.error] 是原因，可以重试。
  failed,
}

class BackendRunState {
  const BackendRunState({this.phase = BackendRunPhase.idle, this.language = '', this.packId, this.packTitle, this.sizeNote, this.error, this.failure});

  final BackendRunPhase phase;

  /// 要启动的后端是哪种语言（id）。
  final String language;

  /// 要装 / 正在装 / 没装成的那一项（运行环境清单里的 id 和名字）；还没走到那一步是 null。
  final String? packId;
  final String? packTitle;

  /// “下载约多少、占多少”；没核对过数字的是 null。
  final String? sizeNote;

  /// 失败的原因（大白话）和类别。
  final String? error;
  final PackFailure? failure;

  /// 有一次“运行”正在进行（这时再点“运行”不受理）。
  bool get active => phase != BackendRunPhase.idle && phase != BackendRunPhase.failed;
}

class BackendRunNotifier extends Notifier<BackendRunState> {
  BackendRunNotifier(this.session);
  final ProjectSession session;

  int _gen = 0;
  ({String language, String command})? _request;
  Completer<void>? _waiter;
  Completer<bool>? _confirm;
  bool _cancelInstall = false;

  LinuxRuntime get _runtime => session.app.runtime;
  bool get _alive => ref.mounted && !session.disposed && !session.app.disposed;
  bool _current(int gen) => _alive && gen == _gen;

  @override
  BackendRunState build() {
    final runtime = session.app.runtime;
    runtime.changeListeners.add(_wake);
    ref.onDispose(() {
      runtime.changeListeners.remove(_wake);
      _gen++;
      _wake();
      _answer(false);
    });
    return const BackendRunState();
  }

  void _wake() {
    final waiter = _waiter;
    _waiter = null;
    if (waiter != null && !waiter.isCompleted) waiter.complete();
  }

  void _answer(bool yes) {
    final confirm = _confirm;
    _confirm = null;
    if (confirm != null && !confirm.isCompleted) confirm.complete(yes);
  }

  void _set(BackendRunState next) {
    if (_alive) state = next;
  }

  /// 运行环境每变一次看一眼，直到 [waiting] 不成立（或这一次已经作废）。
  Future<void> _waitWhile(int gen, bool Function() waiting) async {
    while (_current(gen) && waiting()) {
      final waiter = _waiter = Completer<void>();
      await waiter.future;
    }
  }

  /// 点“运行”。返回这次有没有受理：已经有一次在进行时返回 false（不会并发装两遍）。
  bool start({required String language, required String command}) {
    if (!_alive) return false;
    // 在等 Ubuntu 环境、而环境那边已经停了（装失败了，原因在安装引导里）：再点“运行”就是再来一次。
    final stalled = state.phase == BackendRunPhase.waitingRuntime && !_runtime.busy;
    if (state.active && !stalled) return false;
    _request = (language: language, command: command);
    final gen = ++_gen;
    if (stalled) _wake();
    _cancelInstall = false;
    unawaited(_drive(gen, language, command));
    return true;
  }

  /// 没装成以后再来一次。
  bool retry() {
    final request = _request;
    if (request == null || state.phase != BackendRunPhase.failed) return false;
    return start(language: request.language, command: request.command);
  }

  /// 收起“没装成”的提示。
  void dismiss() {
    if (state.phase == BackendRunPhase.failed) _set(const BackendRunState());
  }

  /// “要装的东西比较大”那一问：装。
  void confirmInstall() => _answer(true);

  /// 取消这一次“运行”。正在装的会停下（下次再装接着来）；正在装 Ubuntu 环境的也会停下。
  void cancel() {
    switch (state.phase) {
      case BackendRunPhase.idle || BackendRunPhase.failed:
        return;
      case BackendRunPhase.confirming:
        _answer(false);
      case BackendRunPhase.installing:
        // 等安装进程真的停下来，由 _drive 收尾（这样“已取消”那一行排在安装输出后面）。
        _cancelInstall = true;
        _runtime.cancelPack();
      case BackendRunPhase.waitingRuntime:
        _gen++;
        if (_runtime.busy) _runtime.cancelInstall();
        _set(const BackendRunState());
        _wake();
      case BackendRunPhase.checking:
        _gen++;
        _note(backendTerminal(session)?.terminal, '已取消，没有启动。');
        _set(const BackendRunState());
        _wake();
    }
  }

  /// 往“后端”终端里写一行说明（暗色，和命令的输出区分开）。
  void _note(TerminalSession? term, String text) => term?.append('\x1b[2m[运行] $text\x1b[0m\n');

  void _launch(String command, {TerminalSession? justOpened}) {
    _set(const BackendRunState());
    launchBackendInTerminal(session, command, justOpened: justOpened);
  }

  Future<void> _drive(int gen, String language, String command) async {
    final runtime = _runtime;
    // 桌面调试 / 宿主机测试：没装环境就是本机 shell，和以前一样直接打命令。
    if (runtime.localShellAllowed && !runtime.usable) return _launch(command);
    if (!runtime.usable) {
      // 这个安装包进不了 Ubuntu：装了也没用。终端页的安装引导已经写明原因，这里不重复。
      if (!runtime.prootBundled) return;
      _set(BackendRunState(phase: BackendRunPhase.waitingRuntime, language: language));
      if (!runtime.busy && !runtime.installed) {
        try {
          await runtime.install();
        } on Object catch (e) {
          // install 自己会把能预料的失败记成 installError；到这里的是没预料到的。
          if (_current(gen)) _set(BackendRunState(phase: BackendRunPhase.failed, language: language, error: '安装运行环境时出错了：$e', failure: PackFailure.other));
          return;
        }
      }
      await _waitWhile(gen, () => runtime.busy);
      while (_current(gen) && !runtime.usable) {
        // 没在装、也没留下失败原因：是她取消的。整个停下，什么都不留。
        if (runtime.installError == null) return _set(const BackendRunState());
        // 装失败了：原因和“再装一次”都在安装引导里。等她再点一次，装好了接着走。
        await _waitWhile(gen, () => !runtime.busy && !runtime.usable);
        await _waitWhile(gen, () => runtime.busy);
      }
      if (!_current(gen)) return;
    }

    final pack = runtimePackById(runtime.packs, language);
    // 清单里没有这种语言：没什么可装的，直接启动。
    if (pack == null || runtime.packInstalled(pack)) return _launch(command);

    final found = backendTerminal(session);
    if (found == null) return _set(const BackendRunState());
    final term = found.terminal;
    BackendRunState at(BackendRunPhase phase, {String? error, PackFailure? failure}) =>
        BackendRunState(phase: phase, language: language, packId: pack.id, packTitle: pack.title, sizeNote: pack.sizeNote, error: error, failure: failure);

    var confirmed = false;
    while (true) {
      _set(at(BackendRunPhase.checking));
      if (runtime.runningPack != null) {
        _note(term, '“运行环境”里正在装别的东西，等它装完。');
        await _waitWhile(gen, () => runtime.runningPack != null);
        if (!_current(gen)) return;
      }
      if (runtime.packInstalled(pack)) break;
      _note(term, '检查 ${pack.title} 装没装…');
      final has = await runtime.packInstaller.hasCommands(pack.commands);
      if (!_current(gen)) return;
      // true＝她自己装过；null＝核对不了（Ubuntu 进不去）：都直接启动，进不去的原因终端自己会显示。
      if (has != false) break;

      if (pack.needsConfirm && !confirmed) {
        final confirm = _confirm = Completer<bool>();
        _set(at(BackendRunPhase.confirming));
        final yes = await confirm.future;
        if (!_current(gen)) return;
        if (!yes) {
          _note(term, '没有安装 ${pack.title}，也没有启动。');
          return _set(const BackendRunState());
        }
        confirmed = true;
      }

      _set(at(BackendRunPhase.installing));
      _note(term, '没找到 ${pack.title}，现在自动安装${pack.sizeNote == null ? '' : '（${pack.sizeNote}）'}，装好后接着启动。要停下点上面的“取消”。');
      final result = await runtime.installPackDetailed(
        pack,
        onLine: (line) {
          if (_current(gen)) term.append('$line\n');
        },
      );
      if (!_current(gen)) return;
      if (result.ok) {
        _note(term, '${pack.title} 装好了，现在启动。');
        break;
      }
      if (result.cancelled || _cancelInstall) {
        _note(term, '已取消安装，没有启动。再点一次“运行”会接着装。');
        return _set(const BackendRunState());
      }
      // 刚好被别处抢先开始装了：回到上面等它装完再看。
      if (result.failure == PackFailure.busy) continue;
      _note(term, '没有启动：${result.message}');
      return _set(at(BackendRunPhase.failed, error: result.message, failure: result.failure));
    }
    _launch(command, justOpened: found.fresh ? term : null);
  }
}

/// 某个工作区的后端“运行”准备状态。
final backendRunProvider = NotifierProvider.family<BackendRunNotifier, BackendRunState, ProjectSession>(BackendRunNotifier.new);
