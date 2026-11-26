// 后端项目的“GitHub 部署”：把代码推到仓库 → 触发部署工作流 → 等它跑完（按工作区分身）。
//
// 推送和触发之前界面一定先给用户看 [GithubDeployPlan]（仓库、分支、要推的文件、被挡掉的文件）并等她点确认，
// 这里的 [start] 只在她确认之后才被调用。令牌只从安全存储读，不进状态、不进日志。
import 'dart:async';
import 'dart:io';

import 'package:lopicode/build/deploy_backends.dart';
import 'package:lopicode/build/deploy_files.dart';
import 'package:lopicode/build/deploy_project.dart';
import 'package:lopicode/build/deploy_workflows.dart';
import 'package:lopicode/build/github_client.dart';
import 'package:lopicode/core/crash_log.dart';
import 'package:lopicode/core/stores.dart';
import 'package:lopicode/project_session.dart';
import 'package:lopicode/state/deploy_run.dart';
import 'package:path/path.dart' as p;
import 'package:riverpod/riverpod.dart';

/// 多久查一次运行状态、最长等多久（自定；测试里会调短）。
Duration deployPollInterval = const Duration(seconds: 6);
Duration deployPollTimeout = const Duration(minutes: 40);

/// 推送前给用户确认的清单。
class GithubDeployPlan {
  const GithubDeployPlan({required this.owner, required this.repo, required this.branch, required this.workflowFile, required this.files, required this.runDeploy});
  final String owner;
  final String repo;
  final String branch;
  final String workflowFile;
  final DeployFileSet files;

  /// 触发时带 deploy=true（构建完接着部署到服务器）。
  final bool runDeploy;

  String get workflowPath => deployWorkflowPath(workflowFile);

  /// 这次推送里有没有工作流文件（有的话令牌要有改工作流的权限）。
  bool get touchesWorkflows => files.files.any((f) => f.rel.startsWith('.github/workflows/'));
}

/// 令牌没有“改工作流文件”权限时的大白话说明。
const String kWorkflowPermissionHelp =
    '这次推送里有工作流文件（.github/workflows/ 下面的），GitHub 要求令牌有“改工作流”的权限：\n'
    '· 细粒度令牌（Fine-grained）：给这个仓库把 Workflows 设成 Read and write（Contents 也要 Read and write）；\n'
    '· 经典令牌（classic）：勾上 workflow。\n'
    '到 GitHub › 右上角头像 › Settings › Developer settings › Personal access tokens 里改，改完回来再点一次。';

class DeployGithubNotifier extends Notifier<DeployRunState> with DeployRunBase {
  DeployGithubNotifier(this.session);
  @override
  final ProjectSession session;

  SettingsStore get _settings => session.app.settings;
  String get workflowFile {
    final v = _settings.getString(SettingKeys.githubDeployWorkflow).trim();
    return v.isEmpty ? kDeployWorkflowFile : v;
  }

  File get _workflow => File(p.join(session.project.dir, '.github', 'workflows', workflowFile));

  @override
  DeployRunState build() => initial();

  /// 项目里已经有这个工作流文件了吗。
  bool get workflowExists => _workflow.existsSync();

  /// 给“查看 / 修改工作流”面板用：项目里有就读它，没有就按语言生成一份（还没写进项目）。
  Future<String> workflowText(DeployProject project) async {
    final f = _workflow;
    if (await f.exists()) return f.readAsString();
    return deployWorkflow(project, name: session.project.id);
  }

  /// 把工作流写进项目（用户点了“写进项目”才调）。
  Future<void> writeWorkflow(String text) async {
    final f = _workflow;
    await f.parent.create(recursive: true);
    await f.writeAsString(text.endsWith('\n') ? text : '$text\n', flush: true);
    if (!session.disposed) session.filesChanged();
  }

  /// 看看这次会推什么。有问题（没填仓库、没令牌、没工作流、文件太多）抛 [DeployException]。
  Future<GithubDeployPlan> plan() async {
    final owner = _settings.getString(SettingKeys.githubOwner).trim();
    final repo = _settings.getString(SettingKeys.githubRepo).trim();
    final ref = _settings.getString(SettingKeys.githubRef).trim();
    if (owner.isEmpty || repo.isEmpty) throw const DeployException('还没填仓库。在上面“仓库”一行里填 用户名/仓库名。');
    final token = await session.app.secrets.read(SecretKeys.githubToken);
    if (token == null || token.isEmpty) throw const DeployException('还没填访问令牌。在上面“访问令牌”一行里填。');
    if (!workflowExists) throw DeployException('项目里还没有部署工作流（${deployWorkflowPath(workflowFile)}）。点“查看 / 修改工作流”，看过以后点“写进项目”。');
    final files = collectDeployFiles(session.project.dir, limits: DeployLimits.push);
    if (files.files.isEmpty) throw const DeployException('没有可以推送的文件。');
    return GithubDeployPlan(
      owner: owner,
      repo: repo,
      branch: ref.isEmpty ? 'main' : ref,
      workflowFile: workflowFile,
      files: files,
      runDeploy: _settings.getBool(deployKey(SettingKeys.githubDeployRun, session)),
    );
  }

  /// 停止等待。已经推上去的代码和已经启动的工作流不会被撤回。
  void cancel() {
    if (!snap.busy) return;
    gen++;
    put(snap.copyWith(phase: DeployPhase.cancelled, headline: '已停止等待', failure: () => '你停止了等待。已经推上去的代码和已经启动的工作流不会被撤回，可以到 GitHub 的 Actions 页面看它。'));
  }

  /// 推送并启动（用户确认过 [plan] 之后）。进行中再点不受理（返回 false）。
  Future<bool> start(GithubDeployPlan plan) async {
    if (snap.busy) return false;
    final my = ++gen;
    bool current() => my == gen && alive;
    put(
      const DeployRunState(
        phase: DeployPhase.running,
        headline: '正在推送代码…',
        steps: [
          DeployStepState('推送代码', status: StepStatus.running),
          DeployStepState('启动工作流'),
          DeployStepState('等工作流跑完'),
        ],
      ),
    );
    var step = 0;
    void fail(String message) {
      if (current()) put(snap.mark(step, StepStatus.failed).copyWith(phase: DeployPhase.failed, headline: '没成', failure: () => message));
    }

    void next(String headline) {
      put(snap.mark(step, StepStatus.ok).mark(step + 1, StepStatus.running).copyWith(headline: headline));
      step++;
    }

    try {
      final token = await session.app.secrets.read(SecretKeys.githubToken);
      if (!current()) return true;
      if (token == null || token.isEmpty) {
        fail('还没填访问令牌。');
        return true;
      }
      final client = deployGitHubClient(token, plan.owner, plan.repo);
      final files = await readDeployFiles(plan.files);
      if (!current()) return true;
      put(snap.addLog('推送 ${files.length} 个文件到 ${plan.owner}/${plan.repo} 的 ${plan.branch} 分支\n'));
      final sha = await client.pushFiles(
        branch: plan.branch,
        files: files,
        message: '从 LopiCode 推送（构建与部署）',
        onProgress: (done, total) {
          if (current()) put(snap.copyWith(headline: '正在推送代码…（$done / $total）'));
        },
      );
      if (!current()) return true;
      put(snap.addLog('推送完成，提交 ${sha.length > 7 ? sha.substring(0, 7) : sha}\n'));

      next('正在启动工作流…');
      final startedAt = DateTime.now();
      var runId = await client.dispatchWorkflow(plan.workflowFile, plan.branch, inputs: {'deploy': plan.runDeploy ? 'true' : 'false'});
      if (!current()) return true;
      put(snap.addLog('已启动 ${plan.workflowFile}${plan.runDeploy ? '（构建完接着部署）' : '（只构建并上传产物）'}\n'));

      next('等工作流跑完…');
      final deadline = startedAt.add(deployPollTimeout);
      WorkflowRun? run;
      while (true) {
        if (DateTime.now().isAfter(deadline)) {
          fail('等了 ${deployPollTimeout.inMinutes} 分钟工作流还没跑完，不等了。它可能还在跑，到 GitHub 的 Actions 页面看。');
          return true;
        }
        await Future<void>.delayed(deployPollInterval);
        if (!current()) return true;
        if (runId == null) {
          runId = (await client.findLatestDispatchRun(plan.workflowFile, plan.branch, startedAt))?.id;
          if (!current()) return true;
          continue;
        }
        run = await client.getRun(runId);
        if (!current()) return true;
        if (snap.url != run.htmlUrl) put(snap.copyWith(url: run.htmlUrl, headline: run.status == 'queued' ? '工作流在排队…' : '工作流正在跑…'));
        if (run.status == 'completed') break;
      }
      if (run.conclusion == 'success') {
        put(
          snap
              .mark(step, StepStatus.ok)
              .copyWith(
                phase: DeployPhase.done,
                headline: plan.runDeploy ? '构建并部署完了' : '构建完了',
                result: DeployResult(
                  headline: '工作流跑成功了',
                  url: run.htmlUrl,
                  notes: ['构建产物在 GitHub 运行页的 Artifacts 里，可以下载。', if (!plan.runDeploy) '这次只构建、没部署。要让它构建完直接部署到服务器：先在 $kDeploySecretsWhere 里配好 ${kDeploySecrets.keys.join('、')}，再打开“构建完部署到服务器”。'],
                ),
              ),
        );
      } else {
        fail('工作流没跑成功（结论：${run.conclusion ?? '未知'}）。打开运行页看是哪一步出的错。');
      }
    } on GitHubException catch (e) {
      // 403：令牌权限不够。推送里带了工作流文件时，最常见的就是缺“改工作流”的权限，直接讲清楚去哪开。
      final workflowDenied = step == 0 && plan.touchesWorkflows && (e.statusCode == 403 || e.statusCode == 404);
      fail(workflowDenied ? '${e.message}\n\n$kWorkflowPermissionHelp${e.statusCode == 404 ? '\n（细粒度令牌权限不够时，GitHub 有时回的是“找不到”而不是“没权限”。也请核对仓库名和分支名。）' : ''}' : e.message);
    } on DeployException catch (e) {
      fail(e.message);
    } on FileSystemException catch (e) {
      fail('读项目文件失败：${e.osError?.message ?? e.message}');
    } on Object catch (e, st) {
      CrashLog.instance.record(e, st, source: 'deploy-github');
      fail('出了意外的错误：${e.runtimeType}。');
    }
    return true;
  }
}

final deployGithubProvider = NotifierProvider.family<DeployGithubNotifier, DeployRunState, ProjectSession>(DeployGithubNotifier.new);
