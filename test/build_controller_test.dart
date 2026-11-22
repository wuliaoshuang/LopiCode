import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/build/build_controller.dart';
import 'package:lopicode/build/github_client.dart';
import 'package:lopicode/build/workflow_templates.dart';
import 'package:lopicode/core/path_guard.dart';
import 'package:path/path.dart' as p;

import 'github_client_test.dart' show FakeGitHub;

void main() {
  late FakeGitHub gh;
  late Directory tmp;

  setUp(() async {
    gh = FakeGitHub();
    await gh.start();
    tmp = Directory.systemTemp.createTempSync('lopi_build_');
  });
  tearDown(() async {
    await gh.stop();
    tmp.deleteSync(recursive: true);
  });

  ApkBuildController controller({String token = 'ghp_test'}) => ApkBuildController(
    client: GitHubClient(token: token, owner: 'shuang', repo: 'demo', baseUrl: gh.base),
    workflowFile: 'android.yml',
    ref: 'main',
    outputDir: p.join(tmp.path, 'out'),
    pollInterval: const Duration(milliseconds: 10),
  );

  test('完整流程：推送 → 触发 → 轮询 → 下载 → 解出 APK', () async {
    final proj = Directory(p.join(tmp.path, 'proj'))..createSync();
    File(p.join(proj.path, 'index.html')).writeAsStringSync('<h1>x</h1>');
    Directory(p.join(proj.path, '.lopicode')).createSync();
    File(p.join(proj.path, '.lopicode', 'chat.json')).writeAsStringSync('[]');
    final files = await ApkBuildController.collectFiles(PathGuard(proj.path));
    expect(files.keys, ['index.html'], reason: '内部目录不推送');

    final job = controller();
    final phases = <BuildPhase>[];
    job.addListener(() {
      if (phases.isEmpty || phases.last != job.phase) phases.add(job.phase);
    });
    await job.run(pushFiles: files);
    expect(phases, [BuildPhase.pushing, BuildPhase.dispatching, BuildPhase.waiting, BuildPhase.downloading, BuildPhase.done]);
    expect(job.apkPath, p.join(tmp.path, 'out', 'app-debug.apk'));
    expect(File(job.apkPath!).readAsBytesSync(), [80, 75, 3, 4]);
    expect(job.runUrl, contains('/actions/runs/777'));
    expect(job.log.join('\n'), allOf(contains('构建中'), contains('成功'), contains('APK 已保存')));
  });

  test('接口不返回运行 ID 时，从运行列表里找到它', () async {
    gh.supportsRunDetails = false;
    final job = controller();
    await job.run();
    // 假服务器的列表里最新的是 #778，但它没有 /runs/778 → 明确失败而不是卡住
    expect(job.phase, BuildPhase.failed);
    expect(job.log.join('\n'), contains('#778'));
  });

  test('Token 不对：失败并说明原因，日志里没有 Token', () async {
    final job = controller(token: 'ghp_wrong_secret');
    await job.run();
    expect(job.phase, BuildPhase.failed);
    expect(job.log.last, contains('Token'));
    expect(job.log.join('\n'), isNot(contains('ghp_wrong_secret')));
    expect(job.apkPath, isNull);
  });

  test('可以停止等待', () async {
    gh.runPolls = -1000000; // 永远 in_progress
    final job = controller();
    final running = job.run();
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(job.phase, BuildPhase.waiting);
    job.cancel();
    await running;
    expect(job.phase, BuildPhase.cancelled);
  });

  test('工作流模板：手动触发、上传 APK 产物', () {
    for (final tpl in [flutterWorkflowTemplate, webShellWorkflowTemplate]) {
      expect(tpl, contains('workflow_dispatch'));
      expect(tpl, contains('actions/upload-artifact@v4'));
      expect(tpl, contains('flutter build apk --\${{ inputs.mode }}'));
      expect(tpl, contains('.apk'));
      expect(tpl.contains('\t'), isFalse, reason: 'YAML 不能有制表符');
    }
    expect(webShellWorkflowTemplate, contains("loadFlutterAsset('assets/www/index.html')"));
    expect(kWorkflowPath, '.github/workflows/android.yml');
    expect(ApkBuildController.formatBytes(1536), '1.5 KB');
    expect(ApkBuildController.formatBytes(5 * 1024 * 1024), '5.0 MB');
  });
}
