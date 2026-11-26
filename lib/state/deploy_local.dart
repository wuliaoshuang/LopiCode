// 后端项目的“本地构建”：在手机的 Ubuntu 环境里编译 / 检查语法，再把产物放进工作区 build/（按工作区分身）。
//
// 流程：运行环境在不在 → 这种语言的工具在不在（不在就替她装，大的先问）→ 一条条跑命令 → 不用编译的打成压缩包。
// 防并发和防“销毁后写状态”：同一时间只受理一次；每次开始换一个代次，`await` 回来代次对不上、
// 或工作区 / 应用已经关了，就什么都不写。取消＝代次加一 + 停掉正在跑的命令 / 安装。
import 'dart:async';
import 'dart:io';

import 'package:lopicode/build/deploy_backends.dart';
import 'package:lopicode/build/deploy_commands.dart';
import 'package:lopicode/build/deploy_files.dart';
import 'package:lopicode/build/deploy_project.dart';
import 'package:lopicode/core/crash_log.dart';
import 'package:lopicode/project_session.dart';
import 'package:lopicode/state/deploy_run.dart';
import 'package:path/path.dart' as p;
import 'package:riverpod/riverpod.dart';

class DeployLocalNotifier extends Notifier<DeployRunState> with DeployRunBase {
  DeployLocalNotifier(this.session);
  @override
  final ProjectSession session;

  Completer<void>? _stop;
  Completer<bool>? _answer;
  DeployGuest? _guest;

  @override
  DeployRunState build() => initial();

  /// 回答“要不要装这个大的语言包”。
  void answerInstall(bool yes) {
    final c = _answer;
    if (c != null && !c.isCompleted) c.complete(yes);
  }

  void cancel() {
    if (!snap.busy) return;
    gen++;
    final stop = _stop;
    if (stop != null && !stop.isCompleted) stop.complete();
    answerInstall(false);
    _guest?.cancelInstall();
    put(snap.copyWith(phase: DeployPhase.cancelled, headline: '已取消', ask: () => null, failure: () => '你取消了这次构建。已经生成的文件可能不完整。'));
  }

  /// 开始构建。进行中再点不受理（返回 false）。
  Future<bool> start(DeployProject project, {bool amd64 = false, bool npmInstall = false}) async {
    if (snap.busy) return false;
    final my = ++gen;
    bool current() => my == gen && alive;
    final plan = localBuildPlan(project, name: session.project.id, amd64: amd64, npmInstall: npmInstall);
    final packing = plan.outputKind == LocalOutputKind.archive;
    put(
      DeployRunState(
        phase: DeployPhase.running,
        headline: '正在准备…',
        steps: [
          for (final s in plan.steps) DeployStepState(s.title, command: s.command),
          if (packing) const DeployStepState('打成压缩包'),
        ],
      ),
    );
    void fail(String message, {bool needsRuntime = false}) {
      if (current()) put(snap.copyWith(phase: DeployPhase.failed, headline: '没成', failure: () => message, needsRuntime: needsRuntime, ask: () => null));
    }

    try {
      if (plan.unsupported != null) {
        fail(plan.unsupported!);
        return true;
      }
      final guest = _guest = deployGuestFor(session.app.runtime, session.project);
      // 只打压缩包（没有要跑的命令）不需要运行环境。
      if (plan.steps.isNotEmpty) {
        switch (guest.status) {
          case GuestStatus.ready:
            break;
          case GuestStatus.notInstalled:
            fail('还没装运行环境。本地构建要在手机里的 Ubuntu 环境中进行，先把它装上。', needsRuntime: true);
            return true;
          case GuestStatus.installing:
            fail('运行环境正在安装，装完再来。', needsRuntime: true);
            return true;
          case GuestStatus.broken:
            fail('运行环境下载了但进不去。到“运行环境”页看看原因。', needsRuntime: true);
            return true;
        }
        if (!await _ensurePack(guest, plan.packId, current, fail)) return true;
      }

      for (var i = 0; i < plan.steps.length; i++) {
        final step = plan.steps[i];
        if (!current()) return true;
        put(snap.mark(i, StepStatus.running).copyWith(headline: '正在${step.title}…').addLog('\$ ${step.command}\n'));
        final stop = _stop = Completer<void>();
        final r = await guest.run(
          step.command,
          stop: stop.future,
          onOutput: (chunk) {
            if (current()) put(snap.addLog(chunk));
          },
        );
        if (!current()) return true;
        if (r.exitCode != 0) {
          put(snap.mark(i, StepStatus.failed));
          fail(r.exitCode == null ? '停在第 ${i + 1} 步“${step.title}”：${r.note ?? '命令没跑完'}。' : '停在第 ${i + 1} 步“${step.title}”：命令退出码 ${r.exitCode}。具体原因看下面的输出。');
          return true;
        }
        put(snap.mark(i, StepStatus.ok));
      }

      final outFile = File(p.join(session.project.dir, 'build', plan.output));
      if (packing) {
        final index = plan.steps.length;
        put(snap.mark(index, StepStatus.running).copyWith(headline: '正在打成压缩包…'));
        final root = project.dir.isEmpty ? session.project.dir : p.join(session.project.dir, project.dir);
        final set = collectDeployFiles(root, includeNodeModules: npmInstall);
        if (set.files.isEmpty) {
          put(snap.mark(index, StepStatus.failed));
          fail('停在“打成压缩包”：没有可以打包的文件。');
          return true;
        }
        final bytes = await buildDeployArchive(set, topDir: deploySafeName(session.project.id));
        if (!current()) return true;
        await outFile.parent.create(recursive: true);
        final tmp = File('${outFile.path}.part');
        await tmp.writeAsBytes(bytes, flush: true);
        await tmp.rename(outFile.path);
        if (!current()) return true;
        put(snap.mark(index, StepStatus.ok).addLog('打包了 ${set.files.length} 个文件${set.skipped.isEmpty ? '' : '，${set.skipped.length} 项没带（密钥、依赖目录、构建产物等）'}。\n'));
      } else if (!outFile.existsSync()) {
        fail('命令跑完了，但 build 目录里没有 ${plan.output}。看看下面的输出里有没有报错。');
        return true;
      }
      final size = await outFile.length();
      if (!current()) return true;
      put(
        snap.copyWith(
          phase: DeployPhase.done,
          headline: switch (plan.outputKind) {
            LocalOutputKind.binary => '编译好了',
            LocalOutputKind.jar => 'jar 打好了',
            LocalOutputKind.archive => '压缩包打好了',
          },
          result: DeployResult(headline: plan.output, fileName: plan.output, bytes: size, location: 'build/${plan.output}', notes: plan.howTo),
        ),
      );
      if (!session.disposed) session.filesChanged();
    } on DeployException catch (e) {
      fail(e.message);
    } on FileSystemException catch (e) {
      fail('读写文件失败：${e.osError?.message ?? e.message}');
    } on Object catch (e, st) {
      CrashLog.instance.record(e, st, source: 'deploy-local');
      fail('出了意外的错误：${e.runtimeType}。');
    }
    return true;
  }

  /// 语言工具不在就装。返回 false＝已经报了失败 / 被取消，别往下走了。
  Future<bool> _ensurePack(DeployGuest guest, String? packId, bool Function() current, void Function(String, {bool needsRuntime}) fail) async {
    final pack = packId == null ? null : guest.pack(packId);
    if (pack == null) return true;
    put(snap.copyWith(headline: '正在看 ${pack.title} 装了没有…'));
    final has = await guest.hasPack(pack.id);
    if (!current()) return false;
    if (has != false) return true;
    if (pack.needsConfirm) {
      final answer = _answer = Completer<bool>();
      put(snap.copyWith(headline: '等你确认', ask: () => '构建要用到 ${pack.title}，运行环境里还没有。${pack.sizeNote == null ? '' : '${pack.sizeNote}。'}现在装吗？'));
      final yes = await answer.future;
      if (!current()) return false;
      put(snap.copyWith(ask: () => null));
      if (!yes) {
        fail('没有装 ${pack.title}，构建没法进行。');
        return false;
      }
    }
    put(snap.copyWith(headline: '正在安装 ${pack.title}…').addLog('运行环境里没有 ${pack.title}，先装上。\n'));
    final r = await guest.installPack(
      pack.id,
      onLine: (line) {
        if (current()) put(snap.addLog('$line\n'));
      },
    );
    if (!current()) return false;
    if (!r.ok) {
      fail('安装 ${pack.title} 没成：${r.message ?? '原因不明'}');
      return false;
    }
    return true;
  }
}

final deployLocalProvider = NotifierProvider.family<DeployLocalNotifier, DeployRunState, ProjectSession>(DeployLocalNotifier.new);
