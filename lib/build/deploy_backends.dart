// “构建与部署”要用到的三样外部能力，各留一个可以换掉的口子（测试里不真起进程、不真联网、不真连 SSH）：
//   - [DeployGuest]：在手机的 Ubuntu 运行环境里跑命令、核对 / 安装语言工具；
//   - GitHub 客户端的造法；
//   - SSH 远程执行的造法。
import 'dart:async';

import 'package:lopicode/agent/command_runner.dart';
import 'package:lopicode/build/github_client.dart';
import 'package:lopicode/build/remote_exec.dart';
import 'package:lopicode/core/project_store.dart';
import 'package:lopicode/core/stores.dart';
import 'package:lopicode/runtime/linux_command_runner.dart';
import 'package:lopicode/runtime/linux_runtime.dart';
import 'package:lopicode/runtime/pack_install.dart';
import 'package:lopicode/runtime/runtime_sources.dart';
import 'package:lopicode/ssh/ssh_config.dart';
import 'package:lopicode/ssh/ssh_connector.dart';

/// 运行环境现在能不能跑命令。
enum GuestStatus {
  /// 能跑（Ubuntu 环境可用，或者是允许用本机 shell 的桌面 / 宿主机测试）。
  ready,

  /// 还没装。
  notInstalled,

  /// 正在装。
  installing,

  /// 下载了但进不去（安装包里缺进入它要用的文件）。
  broken,
}

/// 一种语言工具在“运行环境”清单里的样子。
class GuestPack {
  const GuestPack({required this.id, required this.title, this.sizeNote, this.needsConfirm = false});
  final String id;
  final String title;
  final String? sizeNote;

  /// 下载量大，装之前要先问一次。
  final bool needsConfirm;
}

/// 在运行环境里跑一条命令的结果。[exitCode] 为 null＝没跑完（被停了 / 超时 / 起不来），原因在 [note]。
class GuestRunResult {
  const GuestRunResult(this.exitCode, {this.note});
  final int? exitCode;
  final String? note;
}

abstract class DeployGuest {
  GuestStatus get status;

  /// 清单里的这一项；清单里没有这种语言返回 null（那就不核对、不安装）。
  GuestPack? pack(String id);

  /// 这种语言的工具在不在。true＝在；false＝不在；null＝核对不了（当作在，让命令自己报错）。
  Future<bool?> hasPack(String id);

  /// 安装。输出一行行交给 [onLine]。
  Future<PackInstallResult> installPack(String id, {required void Function(String line) onLine});

  /// 停掉正在进行的安装。
  void cancelInstall();

  /// 从工作区根目录出发跑 [command]，输出一块块交给 [onOutput]。[stop] 完成时整棵进程树停掉。
  Future<GuestRunResult> run(String command, {required void Function(String chunk) onOutput, required Future<void> stop});
}

/// 一条构建命令最长跑多久（自定）：Go 第一次编译标准库、npm install 都慢。
const Duration kDeployCommandTimeout = Duration(minutes: 20);

class RuntimeDeployGuest implements DeployGuest {
  RuntimeDeployGuest(this.runtime, this.project);
  final LinuxRuntime runtime;
  final Project project;

  @override
  GuestStatus get status {
    if (runtime.usable || runtime.localShellAllowed) return GuestStatus.ready;
    if (runtime.busy) return GuestStatus.installing;
    return runtime.installed ? GuestStatus.broken : GuestStatus.notInstalled;
  }

  RuntimePack? _pack(String id) => runtimePackById(runtime.packs, id);

  @override
  GuestPack? pack(String id) {
    final pack = _pack(id);
    return pack == null ? null : GuestPack(id: pack.id, title: pack.title, sizeNote: pack.sizeNote, needsConfirm: pack.needsConfirm);
  }

  @override
  Future<bool?> hasPack(String id) async {
    final pack = _pack(id);
    // 桌面 / 宿主机测试用的是本机 shell：装没装让命令自己说话。
    if (pack == null || !runtime.usable) return null;
    if (runtime.packInstalled(pack)) return true;
    return runtime.packInstaller.hasCommands(pack.commands);
  }

  @override
  Future<PackInstallResult> installPack(String id, {required void Function(String line) onLine}) async {
    final pack = _pack(id);
    if (pack == null) return const PackInstallResult.failed(PackFailure.other, '运行环境的清单里没有这种语言。');
    return runtime.installPackDetailed(pack, onLine: onLine);
  }

  @override
  void cancelInstall() => runtime.cancelPack();

  @override
  Future<GuestRunResult> run(String command, {required void Function(String chunk) onOutput, required Future<void> stop}) async {
    var streamed = false;
    final runner = LinuxCommandRunner(
      runtime,
      guestCwd: project.linuxPath,
      onOutput: (String chunk) {
        streamed = true;
        onOutput(chunk);
      },
    );
    final result = await runner.runStoppable(command, workingDirectory: project.dir, timeout: kDeployCommandTimeout, stop: stop);
    // 走本机 shell 的那条路不一定边跑边给输出：没给过就把收集到的一次交出去。
    if (!streamed && result.exitCode != kCommandNotRun && result.output.isNotEmpty) onOutput(result.output);
    if (result.stopped) return const GuestRunResult(null, note: '已停止');
    if (result.timedOut) return GuestRunResult(null, note: '跑了 ${kDeployCommandTimeout.inMinutes} 分钟还没结束，已强制停止');
    if (result.exitCode == kCommandNotRun) return GuestRunResult(null, note: result.output);
    return GuestRunResult(result.exitCode);
  }
}

/// 测试 / 截图用：换掉真实现。
DeployGuest Function(Project project)? deployGuestOverride;
GitHubClient Function(String token, String owner, String repo)? deployGitHubOverride;
RemoteExec Function()? deployRemoteExecOverride;

DeployGuest deployGuestFor(LinuxRuntime runtime, Project project) => deployGuestOverride?.call(project) ?? RuntimeDeployGuest(runtime, project);

GitHubClient deployGitHubClient(String token, String owner, String repo) => deployGitHubOverride?.call(token, owner, repo) ?? GitHubClient(token: token, owner: owner, repo: repo);

/// 连到设置里那台 SSH 主机（含指纹核对；第一次见到的指纹交给 [onUnknownHost] 问用户）。
RemoteExec deployRemoteExec(SettingsStore settings, SecretStore secrets, {required Future<bool> Function(SshConfig config, String type, String fingerprint) onUnknownHost}) {
  final fake = deployRemoteExecOverride;
  if (fake != null) return fake();
  final config = SshConfig.load(settings);
  return DartSshRemoteExec(() => connectSsh(config: config, secrets: secrets, knownHosts: KnownHosts(settings), onUnknownHost: onUnknownHost));
}
