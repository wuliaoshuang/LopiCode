import 'dart:async';
import 'dart:io';

import 'package:lopicode/build/github_client.dart';
import 'package:lopicode/core/path_guard.dart';
import 'package:lopicode/core/project_store.dart';
import 'package:path/path.dart' as p;

enum BuildPhase { idle, connecting, pushing, dispatching, waiting, building, downloading, done, failed, cancelled }

/// 一次打包任务对界面暴露的东西（GitHub 和 SSH 两种方式共用一张进度卡）。
abstract class BuildJob {
  /// 进度变了（阶段、日志、输出）回调一声。任务是打包页自己建、自己丢的，所以只留一个回调位，不做全局状态。
  void Function()? onChanged;

  void changed() => onChanged?.call();

  BuildPhase phase = BuildPhase.idle;

  /// 一步一句的进度。
  final List<String> log = [];

  /// 构建命令的原始输出（只有 SSH 方式有），只保留末尾一段。
  String get output => '';
  String? runUrl;
  String? apkPath;
  int? apkBytes;

  bool get busy => const {BuildPhase.connecting, BuildPhase.pushing, BuildPhase.dispatching, BuildPhase.waiting, BuildPhase.building, BuildPhase.downloading}.contains(phase);

  void cancel();

  void say(String line) {
    log.add(line);
    changed();
  }

  void setPhase(BuildPhase next) {
    phase = next;
    changed();
  }
}

/// 通过 GitHub Actions 打包的完整流程：
/// （可选）推送项目文件 → 触发 workflow_dispatch → 轮询运行状态 → 下载产物 → 解出 APK。
class ApkBuildController extends BuildJob {
  ApkBuildController({
    required this.client,
    required this.workflowFile,
    required this.ref,
    required this.outputDir,
    this.pollInterval = const Duration(seconds: 6),
    this.timeout = const Duration(minutes: 40),
  });

  final GitHubClient client;
  final String workflowFile;
  final String ref;

  /// APK 保存到哪个目录。
  final String outputDir;
  final Duration pollInterval;
  final Duration timeout;

  bool _cancelled = false;

  @override
  void cancel() {
    if (busy) _cancelled = true;
  }

  void _checkCancelled() {
    if (_cancelled) throw _Cancelled();
  }

  /// 读出项目里要推送的文件（跳过内部目录和过大的文件）。
  static Future<Map<String, List<int>>> collectFiles(PathGuard guard, {int maxBytes = 5 * 1024 * 1024}) async {
    final out = <String, List<int>>{};
    for (final rel in await listProjectFiles(guard, limit: 2000)) {
      if (rel.endsWith('/')) continue;
      final file = File(guard.resolve(rel));
      if (await file.length() > maxBytes) continue;
      out[rel] = await file.readAsBytes();
    }
    return out;
  }

  Future<void> run({Map<String, List<int>>? pushFiles}) async {
    if (busy) return;
    _cancelled = false;
    log.clear();
    runUrl = null;
    apkPath = null;
    apkBytes = null;
    try {
      if (pushFiles != null) {
        setPhase(BuildPhase.pushing);
        say('推送 ${pushFiles.length} 个文件到 ${client.owner}/${client.repo} 的 $ref 分支…');
        final sha = await client.pushFiles(branch: ref, files: pushFiles, message: 'LopiCode：同步项目文件');
        say('已提交 ${sha.length > 7 ? sha.substring(0, 7) : sha}');
        _checkCancelled();
      }

      setPhase(BuildPhase.dispatching);
      say('触发工作流 $workflowFile…');
      final startedAt = DateTime.now();
      var runId = await client.dispatchWorkflow(workflowFile, ref);
      final deadline = startedAt.add(timeout);

      setPhase(BuildPhase.waiting);
      // 老接口不返回运行 ID：等它出现在运行列表里。
      for (var i = 0; runId == null && i < 10; i++) {
        _checkCancelled();
        await Future<void>.delayed(pollInterval);
        runId = (await client.findLatestDispatchRun(workflowFile, ref, startedAt))?.id;
      }
      if (runId == null) throw GitHubException('工作流已触发，但在运行列表里没找到它。请到 GitHub 的 Actions 页面看看。');
      say('运行 #$runId 已开始');

      WorkflowRun run;
      String? lastStatus;
      while (true) {
        _checkCancelled();
        run = await client.getRun(runId);
        if (run.htmlUrl.isNotEmpty && runUrl == null) {
          runUrl = run.htmlUrl;
          changed();
        }
        if (run.status != lastStatus) {
          lastStatus = run.status;
          say(switch (run.status) {
            'queued' || 'pending' || 'requested' || 'waiting' => '排队中…',
            'in_progress' => '构建中…（一般要几分钟）',
            'completed' => '构建结束：${_conclusion(run.conclusion)}',
            _ => '状态：${run.status}',
          });
        }
        if (run.isCompleted) break;
        if (DateTime.now().isAfter(deadline)) {
          throw GitHubException('等了 ${timeout.inMinutes} 分钟还没结束，已停止等待。构建本身可能还在跑，可以到运行页面查看。');
        }
        await Future<void>.delayed(pollInterval);
      }
      if (!run.isSuccess) {
        throw GitHubException('构建没有成功（${_conclusion(run.conclusion)}）。打开运行页面可以看到完整日志。');
      }

      setPhase(BuildPhase.downloading);
      final artifacts = (await client.listArtifacts(runId)).where((a) => !a.expired).toList();
      if (artifacts.isEmpty) throw GitHubException('构建成功了，但没有上传任何产物。请检查工作流里的 upload-artifact 步骤。');
      _checkCancelled();
      final artifact = artifacts.first;
      say('下载产物 ${artifact.name}（${formatBytes(artifact.sizeInBytes)}）…');
      final apks = GitHubClient.extractApks(await client.downloadArtifactZip(artifact.id));
      if (apks.isEmpty) throw GitHubException('产物 ${artifact.name} 里没有 .apk 文件');
      await Directory(outputDir).create(recursive: true);
      final file = File(p.join(outputDir, apks.first.name));
      await file.writeAsBytes(apks.first.bytes);
      apkPath = file.path;
      apkBytes = apks.first.bytes.length;
      say('APK 已保存（${formatBytes(apkBytes!)}）');
      setPhase(BuildPhase.done);
    } on _Cancelled {
      say('已停止等待。已经触发的构建不会被取消，可以到运行页面查看。');
      setPhase(BuildPhase.cancelled);
    } on GitHubException catch (e) {
      say(e.message);
      setPhase(BuildPhase.failed);
    } on FileSystemException catch (e) {
      say('保存 APK 失败：${e.osError?.message ?? e.message}');
      setPhase(BuildPhase.failed);
    }
  }

  static String _conclusion(String? c) => switch (c) {
    'success' => '成功',
    'failure' => '失败',
    'cancelled' => '被取消',
    'timed_out' => '超时',
    null => '未知',
    _ => c,
  };

  static String formatBytes(int n) => n >= 1024 * 1024 ? '${(n / 1024 / 1024).toStringAsFixed(1)} MB' : '${(n / 1024).toStringAsFixed(n < 10240 ? 1 : 0)} KB';
}

class _Cancelled implements Exception {}
