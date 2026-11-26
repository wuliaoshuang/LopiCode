// 后端项目的“SSH 部署”：把代码传到服务器 → 解压 → 在服务器上编译 / 装依赖 →（可选）重启服务（按工作区分身）。
//
// 开始前界面一定先给用户看 [SshDeployPlan]（每一步要执行的命令全文、要传的文件、被挡掉的文件）并等她点确认，
// 这里的 [start] 只在她确认之后才被调用，而且执行的就是清单里那几条，一个字不改。
// 某一步失败就停。取消＝代次加一 + 断开连接。
import 'dart:async';
import 'dart:io';

import 'package:lopicode/build/deploy_backends.dart';
import 'package:lopicode/build/deploy_commands.dart';
import 'package:lopicode/build/deploy_files.dart';
import 'package:lopicode/build/deploy_project.dart';
import 'package:lopicode/build/remote_exec.dart';
import 'package:lopicode/core/crash_log.dart';
import 'package:lopicode/core/stores.dart';
import 'package:lopicode/project_session.dart';
import 'package:lopicode/ssh/ssh_config.dart';
import 'package:lopicode/ssh/ssh_connector.dart';
import 'package:lopicode/state/deploy_run.dart';
import 'package:path/path.dart' as p;
import 'package:riverpod/riverpod.dart';

class SshDeployPlan {
  const SshDeployPlan({required this.host, required this.remoteDir, required this.steps, required this.files, required this.localRoot});

  /// 主机的显示名（用户@地址:端口）。
  final String host;
  final String remoteDir;
  final List<DeployStep> steps;
  final DeployFileSet files;
  final String localRoot;
}

class DeploySshNotifier extends Notifier<DeployRunState> with DeployRunBase {
  DeploySshNotifier(this.session);
  @override
  final ProjectSession session;

  RemoteExec? _exec;
  SettingsStore get _settings => session.app.settings;
  String _key(String key) => deployKey(key, session);

  @override
  DeployRunState build() => initial();

  /// 远程目录：她填过用她的，没填过是 `~/lopicode-deploy/<名字>`。
  String get remoteDir {
    final v = _settings.getString(_key(SettingKeys.deploySshDir)).trim();
    return v.isEmpty ? '~/lopicode-deploy/${deploySafeName(session.project.id)}' : v;
  }

  /// 编译命令：她改过（包括改成空的）用她的，没动过用按语言给的默认。
  String buildCommand(DeployProject project) => _settings.get<String>(_key(SettingKeys.deploySshBuild)) ?? defaultRemoteBuildCommand(project);

  bool get restartOn => _settings.getBool(_key(SettingKeys.deploySshRestartOn));
  String get restartCommand => _settings.getString(_key(SettingKeys.deploySshRestart));

  /// 这次会做什么。有问题（没配主机、目录不对、文件太多）抛 [DeployException]。
  SshDeployPlan plan(DeployProject project) {
    final config = SshConfig.load(_settings);
    if (!config.isComplete) throw const DeployException('还没配 SSH 主机。点上面“主机”一行填上。');
    final dir = remoteDir;
    if (dir.contains('\n') || dir.contains('\r')) throw const DeployException('远程目录里不能有换行。');
    if (dir == '/' || dir == '~' || dir == '~/') throw const DeployException('远程目录不能直接是根目录或主目录，请指定一个专门的子目录。');
    if (restartOn && restartCommand.trim().isEmpty) throw const DeployException('打开了“重启服务”但没填命令。填上命令，或者把开关关掉。');
    final root = project.dir.isEmpty ? session.project.dir : p.join(session.project.dir, project.dir);
    final files = collectDeployFiles(root);
    if (files.files.isEmpty) throw const DeployException('没有可以上传的文件。');
    return SshDeployPlan(
      host: config.display,
      remoteDir: dir,
      localRoot: root,
      files: files,
      steps: sshDeploySteps(remoteDir: dir, buildCommand: buildCommand(project), restartCommand: restartOn ? restartCommand : null),
    );
  }

  void cancel() {
    if (!snap.busy) return;
    gen++;
    final exec = _exec;
    _exec = null;
    if (exec != null) unawaited(exec.close().catchError((Object _) {}));
    put(snap.copyWith(phase: DeployPhase.cancelled, headline: '已取消', failure: () => '你取消了这次部署，连接已断开。正在服务器上跑的那条命令可能还会跑完；已经传上去、解压出来的文件留在服务器上。'));
  }

  /// 照 [plan] 执行（用户确认过之后）。进行中再点不受理（返回 false）。
  Future<bool> start(SshDeployPlan plan, {required HostKeyPrompt onUnknownHost}) async {
    if (snap.busy) return false;
    final my = ++gen;
    bool current() => my == gen && alive;
    put(
      DeployRunState(
        phase: DeployPhase.running,
        headline: '正在连接 ${plan.host}…',
        steps: [for (final s in plan.steps) DeployStepState(s.title, command: s.command)],
      ),
    );
    var index = -1;
    void fail(String message) {
      if (!current()) return;
      put((index >= 0 ? snap.mark(index, StepStatus.failed) : snap).copyWith(phase: DeployPhase.failed, headline: '没成', failure: () => message));
    }

    final exec = _exec = deployRemoteExec(_settings, session.app.secrets, onUnknownHost: onUnknownHost);
    try {
      await exec.connect();
      if (!current()) return true;
      put(snap.addLog('已连上 ${plan.host}\n'));
      for (index = 0; index < plan.steps.length; index++) {
        final step = plan.steps[index];
        put(snap.mark(index, StepStatus.running).copyWith(headline: '第 ${index + 1} 步：${step.title}…'));
        if (index == 1) {
          // 上传：先查出目录的完整路径（SFTP 不认 ~），再打包、传上去。
          final pwd = StringBuffer();
          final code = await exec.run(sshResolveDirCommand(plan.remoteDir), onOutput: pwd.write);
          if (!current()) return true;
          final base = pwd.toString().trim().split('\n').last.trim();
          if (code != 0 || !base.startsWith('/')) {
            fail('停在第 2 步“${step.title}”：进不去远程目录 ${plan.remoteDir}${code == null ? '（连接断了）' : '（退出码 $code）'}。后面的步骤没有执行。');
            return true;
          }
          final bytes = await buildDeployArchive(plan.files, topDir: 'upload');
          if (!current()) return true;
          put(snap.addLog('上传 ${plan.files.files.length} 个文件到 $base（压缩后 ${formatDeployBytes(bytes.length)}）\n'));
          await exec.upload('$base/$kRemoteArchiveName', bytes);
          if (!current()) return true;
        } else {
          put(snap.addLog('\$ ${step.command}\n'));
          final code = await exec.run(
            step.command,
            onOutput: (chunk) {
              if (current()) put(snap.addLog(chunk));
            },
          );
          if (!current()) return true;
          if (code != 0) {
            fail(code == null ? '停在第 ${index + 1} 步“${step.title}”：连接断了，没拿到结果。后面的步骤没有执行。' : '停在第 ${index + 1} 步“${step.title}”：命令退出码 $code。后面的步骤没有执行。具体原因看下面的输出。');
            return true;
          }
        }
        put(snap.mark(index, StepStatus.ok));
      }
      put(
        snap.copyWith(
          phase: DeployPhase.done,
          headline: '部署完了',
          result: DeployResult(
            headline: '${plan.steps.length} 步都执行成功了',
            location: '${plan.host} 上的 ${plan.remoteDir}',
            notes: ['上传的压缩包 $kRemoteArchiveName 留在这个目录里，下次部署会覆盖它。', '服务器上以前有、这次没有的文件不会被删掉。'],
          ),
        ),
      );
    } on SshConnectException catch (e) {
      fail(index < 0 ? '连不上服务器：${e.message}' : '停在第 ${index + 1} 步：${e.message}');
    } on DeployException catch (e) {
      fail(e.message);
    } on FileSystemException catch (e) {
      fail('读项目文件失败：${e.osError?.message ?? e.message}');
    } on Object catch (e, st) {
      // SSH 库的各种异常：类型名和它自己的说明都不含密码 / 私钥。
      CrashLog.instance.record(e, st, source: 'deploy-ssh');
      fail(index < 0 ? '连不上服务器：$e' : '停在第 ${index + 1} 步“${plan.steps[index].title}”：$e');
    } finally {
      if (identical(_exec, exec)) _exec = null;
      unawaited(exec.close().catchError((Object _) {}));
    }
    return true;
  }
}

final deploySshProvider = NotifierProvider.family<DeploySshNotifier, DeployRunState, ProjectSession>(DeploySshNotifier.new);
