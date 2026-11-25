// 设计约束（打包页 · GitHub Actions 方式 · 390×844）
// 一条主线从上到下：① 仓库（在哪打）→ ② 工作流（怎么打）→ ③ 打包（开关 + 唯一的主按钮）→ 进度 / 结果卡。
// 一行只做一件事：每个输入独占一行；“查看现成模板”是一行跳转，模板本身在底部面板里；“先推送项目文件”是一行开关。
// 主按钮只有一个“开始打包”（打过一次后叫“重新打包”）；打包中它换成次要的“停止等待”，表单锁住。
import 'dart:async';
import 'dart:io';

import 'package:lopicode/build/apk_output.dart';
import 'package:lopicode/build/build_controller.dart';
import 'package:lopicode/build/build_job_view.dart';
import 'package:lopicode/build/build_widgets.dart';
import 'package:lopicode/build/github_client.dart';
import 'package:lopicode/build/workflow_templates.dart';
import 'package:lopicode/core/stores.dart';
import 'package:lopicode/lowcode/builder_screen.dart' show CodeSheetBody;
import 'package:lopicode/project_session.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/app_ref.dart';
import 'package:lopicode/ui/settings_widgets.dart';
import 'package:lopicode/ui/widgets.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;

class GithubBuildView extends StatefulWidget {
  const GithubBuildView({super.key, required this.session, required this.job, required this.onJob});
  final ProjectSession session;

  /// 这种方式当前 / 上一次的任务（页面拿着，切到别的方式再回来还在）。
  final ApkBuildController? job;
  final ValueChanged<ApkBuildController> onJob;

  @override
  State<GithubBuildView> createState() => _GithubBuildViewState();
}

class _GithubBuildViewState extends State<GithubBuildView> {
  final _repo = TextEditingController();
  final _ref = TextEditingController();
  final _workflow = TextEditingController();
  final _token = TextEditingController();
  bool _hasToken = false;
  bool _pushFirst = true;
  bool _loaded = false;
  final _cardKey = GlobalKey();

  bool get _isFlutterProject => File(p.join(widget.session.project.dir, 'pubspec.yaml')).existsSync();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loaded) return;
    _loaded = true;
    final app = appOf(context);
    final owner = app.settings.getString(SettingKeys.githubOwner);
    final repo = app.settings.getString(SettingKeys.githubRepo);
    _repo.text = owner.isEmpty || repo.isEmpty ? '' : '$owner/$repo';
    _ref.text = app.settings.getString(SettingKeys.githubRef, 'main');
    _workflow.text = app.settings.getString(SettingKeys.githubWorkflow, 'android.yml');
    app.secrets.read(SecretKeys.githubToken).then((v) {
      if (mounted) setState(() => _hasToken = v != null && v.isNotEmpty);
    });
  }

  @override
  void dispose() {
    _repo.dispose();
    _ref.dispose();
    _workflow.dispose();
    _token.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    final app = appOf(context);
    final parts = _repo.text.trim().split('/');
    if (parts.length != 2 || parts.any((s) => s.trim().isEmpty)) {
      showSnack(context, '仓库请写成 用户名/仓库名');
      return;
    }
    if (_token.text.trim().isNotEmpty) {
      await app.secrets.write(SecretKeys.githubToken, _token.text.trim());
      _token.clear();
      _hasToken = true;
    }
    final token = await app.secrets.read(SecretKeys.githubToken) ?? '';
    if (token.isEmpty) {
      if (mounted) showSnack(context, '请先填 GitHub Token');
      return;
    }
    final ref = _ref.text.trim().isEmpty ? 'main' : _ref.text.trim();
    final workflow = _workflow.text.trim().isEmpty ? 'android.yml' : _workflow.text.trim();
    await app.settings.set(SettingKeys.githubOwner, parts[0].trim());
    await app.settings.set(SettingKeys.githubRepo, parts[1].trim());
    await app.settings.set(SettingKeys.githubRef, ref);
    await app.settings.set(SettingKeys.githubWorkflow, workflow);

    final outDir = await apkDownloadDir(widget.session.project.id);
    final files = _pushFirst ? await ApkBuildController.collectFiles(widget.session.guard) : null;
    if (!mounted) return;
    final job = ApkBuildController(
      client: GitHubClient(token: token, owner: parts[0].trim(), repo: parts[1].trim()),
      workflowFile: workflow,
      ref: ref,
      outputDir: outDir.path,
    );
    widget.onJob(job);
    FocusScope.of(context).unfocus();
    // 进度卡在主按钮下面：滚进视野，不然点了像没反应。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final card = _cardKey.currentContext;
      if (card != null) unawaited(revealBelowBar(card));
    });
    await job.run(pushFiles: files);
  }

  void _showTemplate() {
    final flutter = _isFlutterProject;
    final code = (flutter ? flutterWorkflowTemplate : webShellWorkflowTemplate).trimLeft();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => CodeSheetBody(
        title: flutter ? '工作流模板 · Flutter 项目' : '工作流模板 · 网页套壳',
        note: '放到仓库的 $kWorkflowPath。这份模板还没在真实的 GitHub Actions 上跑过。',
        code: code,
        language: 'yaml',
        extraAction: OutlinedButton(
          onPressed: () async {
            final file = File(widget.session.guard.resolve(kWorkflowPath));
            await file.parent.create(recursive: true);
            await file.writeAsString(code);
            widget.session.filesChanged();
            if (sheetContext.mounted) Navigator.pop(sheetContext);
            if (mounted) showSnack(context, '已写入项目的 $kWorkflowPath');
          },
          child: const Text('写进项目'),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final job = widget.job;
    final busy = job?.busy ?? false;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SettingsGroup(
          title: '① 仓库',
          padded: true,
          children: [
            PackField(label: '仓库', controller: _repo, enabled: !busy, hint: '用户名/仓库名', mono: true),
            PackField(label: '分支', controller: _ref, enabled: !busy, hint: 'main', mono: true),
            PackField(
              label: 'GitHub Token',
              controller: _token,
              enabled: !busy,
              obscure: true,
              hint: _hasToken ? '已保存，留空表示不改' : '粘贴 Token',
              helper: '需要这个仓库的 Contents 和 Actions 读写权限；要推送工作流文件还得有 Workflows 权限。加密保存在本机。',
              last: true,
            ),
          ],
        ),
        SettingsGroup(
          title: '② 工作流',
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.x4, Space.x4, Space.x4, Space.x3),
              child: PackField(label: '工作流文件名', controller: _workflow, enabled: !busy, hint: 'android.yml', mono: true, last: true),
            ),
            SettingsRow(icon: Icons.description_outlined, title: _isFlutterProject ? '查看现成模板（Flutter 项目）' : '查看现成模板（网页套壳成 App）', onTap: _showTemplate),
          ],
        ),
        SettingsGroup(
          title: '③ 打包',
          children: [SettingsSwitchRow(title: '先把项目文件推送到仓库', value: _pushFirst, onChanged: busy ? null : (v) => setState(() => _pushFirst = v))],
        ),
        busy
            ? OutlinedButton(
                onPressed: job!.cancel,
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                child: const Text('停止等待'),
              )
            : PrimaryBuildButton(label: job == null ? '开始打包' : '重新打包', onPressed: _start),
        if (job != null) ...[const SizedBox(height: Space.x4), BuildJobCard(key: _cardKey, job: job)],
      ],
    );
  }
}
