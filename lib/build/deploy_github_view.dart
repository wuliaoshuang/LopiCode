// 设计约束（构建与部署 · GitHub 部署 · 390×844）
//
// 后端项目的“GitHub 部署”表单：把代码推到仓库，再启动部署工作流。
// 层级：① 仓库（仓库、分支、访问令牌各一行——和打 APK 那边是同一份设置）→ ② 工作流（文件名一行；“查看 / 修改工作流”一行，
//   全文在底部面板里看和改；“构建完部署到服务器”开关一行）→ 唯一的主按钮“推送并启动”→ 进度 / 结果卡。
// 主按钮不直接动手：先弹确认清单（推到哪、推哪些文件、哪些被挡掉），点了确认才推送和启动。写工作流文件也要在面板里点“写进项目”。
// 令牌：输入后只写进安全存储，输入框随即清空；这里不显示、不记日志。
// 颜色：强调色只给主按钮和“完成”；红色只给失败。
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lopicode/build/build_widgets.dart';
import 'package:lopicode/build/deploy_confirm_sheet.dart';
import 'package:lopicode/build/deploy_files.dart';
import 'package:lopicode/build/deploy_project.dart';
import 'package:lopicode/build/deploy_widgets.dart';
import 'package:lopicode/build/deploy_workflows.dart';
import 'package:lopicode/core/stores.dart';
import 'package:lopicode/project_session.dart';
import 'package:lopicode/state/app_providers.dart';
import 'package:lopicode/state/deploy_github.dart';
import 'package:lopicode/state/deploy_run.dart';
import 'package:lopicode/state/workspace_files.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/app_ref.dart';
import 'package:lopicode/ui/settings_widgets.dart';
import 'package:lopicode/ui/widgets.dart';
import 'package:material_ui/material_ui.dart';

class DeployGithubView extends ConsumerStatefulWidget {
  const DeployGithubView({super.key, required this.session, required this.project});
  final ProjectSession session;
  final DeployProject project;

  @override
  ConsumerState<DeployGithubView> createState() => _DeployGithubViewState();
}

class _DeployGithubViewState extends ConsumerState<DeployGithubView> {
  final _repo = TextEditingController();
  final _ref = TextEditingController();
  final _workflow = TextEditingController();
  final _token = TextEditingController();
  bool _hasToken = false;
  bool _loaded = false;
  final _cardKey = GlobalKey();

  DeployGithubNotifier get _notifier => ref.read(deployGithubProvider(widget.session).notifier);

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
    _workflow.text = app.settings.getString(SettingKeys.githubDeployWorkflow, kDeployWorkflowFile);
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

  /// 把表单存下来。填得不对返回 false（已经提示过了）。
  Future<bool> _save() async {
    final app = appOf(context);
    final parts = _repo.text.trim().split('/');
    if (parts.length != 2 || parts.any((s) => s.trim().isEmpty)) {
      showSnack(context, '仓库请写成 用户名/仓库名');
      return false;
    }
    final workflow = _workflow.text.trim().isEmpty ? kDeployWorkflowFile : _workflow.text.trim();
    if (!RegExp(r'^[A-Za-z0-9._-]+\.ya?ml$').hasMatch(workflow)) {
      showSnack(context, '工作流文件名只能是字母、数字、点、横线、下划线，以 .yml 或 .yaml 结尾');
      return false;
    }
    if (_token.text.trim().isNotEmpty) {
      await app.secrets.write(SecretKeys.githubToken, _token.text.trim());
      _token.clear();
      _hasToken = true;
    }
    await app.settings.set(SettingKeys.githubOwner, parts[0].trim());
    await app.settings.set(SettingKeys.githubRepo, parts[1].trim());
    await app.settings.set(SettingKeys.githubRef, _ref.text.trim().isEmpty ? 'main' : _ref.text.trim());
    await app.settings.set(SettingKeys.githubDeployWorkflow, workflow);
    if (mounted) setState(() {});
    return true;
  }

  Future<void> _editWorkflow() async {
    if (!await _save() || !mounted) return;
    final notifier = _notifier;
    final text = await notifier.workflowText(widget.project);
    if (!mounted) return;
    final path = deployWorkflowPath(notifier.workflowFile);
    final edited = await showWorkflowSheet(context, text: text, path: path, exists: notifier.workflowExists);
    if (edited == null || !mounted) return;
    try {
      await notifier.writeWorkflow(edited);
      if (mounted) showSnack(context, '已写入项目的 $path');
    } on Exception catch (e) {
      if (mounted) showSnack(context, '没写成：$e');
    }
  }

  Future<void> _start() async {
    if (!await _save() || !mounted) return;
    final notifier = _notifier;
    final GithubDeployPlan plan;
    try {
      plan = await notifier.plan();
    } on DeployException catch (e) {
      if (mounted) showSnack(context, e.message);
      return;
    }
    if (!mounted) return;
    FocusScope.of(context).unfocus();
    if (!await showPushConfirmSheet(context, plan) || !mounted) return;
    // 进度卡在主按钮下面：滚进视野，不然点了像没反应。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final card = _cardKey.currentContext;
      if (card != null) unawaited(revealBelowBar(card));
    });
    await notifier.start(plan);
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final state = ref.watch(deployGithubProvider(session));
    ref.watch(filesRevProvider(session)); // 工作流文件写进 / 删掉了，下面那行的说明跟着变
    final runKey = deployKey(SettingKeys.githubDeployRun, session);
    ref.watch(settingRevProvider(runKey));
    ref.watch(settingRevProvider(SettingKeys.githubDeployWorkflow));
    final settings = ref.watch(settingsStoreProvider);
    final runDeploy = settings.getBool(runKey);
    final busy = state.busy;
    final exists = _notifier.workflowExists;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SettingsGroup(
          title: '① 仓库',
          padded: true,
          children: [
            PackField(fieldKey: const Key('deploy-gh-repo'), label: '仓库', controller: _repo, enabled: !busy, hint: '用户名/仓库名', mono: true),
            PackField(fieldKey: const Key('deploy-gh-ref'), label: '分支', controller: _ref, enabled: !busy, hint: 'main', mono: true),
            PackField(
              fieldKey: const Key('deploy-gh-token'),
              label: '访问令牌（Token）',
              controller: _token,
              enabled: !busy,
              obscure: true,
              hint: _hasToken ? '已保存，留空表示不改' : '粘贴 Token',
              helper: '要有这个仓库的 Contents、Actions 读写权限；推送工作流文件还要 Workflows 读写（经典令牌是 workflow）。加密保存在本机。',
              last: true,
            ),
          ],
        ),
        SettingsGroup(
          title: '② 工作流',
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.x4, Space.x4, Space.x4, Space.x3),
              child: PackField(fieldKey: const Key('deploy-gh-workflow'), label: '工作流文件名', controller: _workflow, enabled: !busy, hint: kDeployWorkflowFile, mono: true, last: true),
            ),
            SettingsRow(
              key: const Key('deploy-gh-edit-workflow'),
              icon: Icons.description_outlined,
              title: '查看 / 修改工作流',
              subtitle: exists ? '已经在项目里，会跟代码一起推送' : '还没写进项目：点开看全文，确认后写进项目',
              enabled: !busy,
              onTap: _editWorkflow,
            ),
            SettingsSwitchRow(
              switchKey: const Key('deploy-gh-run-deploy'),
              icon: Icons.rocket_launch_outlined,
              title: '构建完部署到服务器',
              subtitle: '关着时只构建并上传产物。要打开，先在 GitHub 仓库里配好 ${kDeploySecrets.length} 个 Secrets（“查看 / 修改工作流”里有说明）',
              value: runDeploy,
              onChanged: busy ? null : (v) => settings.setLater(runKey, v ? true : null),
            ),
          ],
        ),
        busy
            ? OutlinedButton(
                key: const Key('deploy-cancel'),
                onPressed: _notifier.cancel,
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                child: const Text('停止等待'),
              )
            : PrimaryBuildButton(buttonKey: const Key('deploy-start'), label: state.phase == DeployPhase.idle ? '推送并启动' : '再推送并启动一次', onPressed: _start),
        if (state.phase != DeployPhase.idle) ...[const SizedBox(height: Space.x4), DeployRunCard(key: _cardKey, state: state, outputLabel: '过程')],
      ],
    );
  }
}
