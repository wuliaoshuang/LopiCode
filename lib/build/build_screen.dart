// 设计约束（APK 打包 · 390×844）
// - 第一屏先把限制说清楚：手机自己打不了包，这里是“遥控”远程去打。
// - 最上面一个二选一：GitHub Actions / SSH 构建机。选哪个，下面只出现那一种的表单。
// - 一条主线从上到下：① 在哪打（仓库 / 构建机）→ ② 怎么打（工作流 / 构建命令）→ ③ 开始打包 → 进度 → APK 在哪。
// - 主按钮只有一个“开始打包”；“先推送项目文件”是它上面的一个开关，不是第二个主按钮。
// - 模板、SSH 说明这类次要内容收进底部面板。
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lopicode/build/build_controller.dart';
import 'package:lopicode/build/github_client.dart';
import 'package:lopicode/build/remote_exec.dart';
import 'package:lopicode/build/ssh_build_controller.dart';
import 'package:lopicode/build/workflow_templates.dart';
import 'package:lopicode/core/stores.dart';
import 'package:lopicode/core/templates.dart';
import 'package:lopicode/lowcode/builder_screen.dart' show CodeSheetBody;
import 'package:lopicode/project_session.dart';
import 'package:lopicode/ssh/ssh_config.dart';
import 'package:lopicode/ssh/ssh_connect_screen.dart';
import 'package:lopicode/ssh/ssh_connector.dart';
import 'package:lopicode/state/config_providers.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/app_ref.dart';
import 'package:lopicode/ui/shell.dart';
import 'package:lopicode/ui/widgets.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class BuildScreen extends ConsumerStatefulWidget {
  const BuildScreen({super.key, required this.session, this.debugController});
  final ProjectSession session;

  /// 测试 / 截图用：直接展示某个状态。
  final BuildJob? debugController;

  @override
  ConsumerState<BuildScreen> createState() => _BuildScreenState();
}

class _BuildScreenState extends ConsumerState<BuildScreen> {
  final _repo = TextEditingController();
  final _ref = TextEditingController();
  final _workflow = TextEditingController();
  final _token = TextEditingController();
  bool _hasToken = false;
  bool _pushFirst = true;
  bool _loaded = false;
  BuildJob? _job;
  bool _ssh = false;
  bool _uploadFirst = true;
  final _sshDir = TextEditingController();
  final _sshCommand = TextEditingController();
  final _sshApk = TextEditingController();

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
    _ssh = app.settings.getString(SettingKeys.apkBuildMode) == 'ssh' || widget.debugController is SshBuildController;
    _sshDir.text = app.settings.getString(SettingKeys.sshBuildDir, '~/lopicode-build/${widget.session.project.id}');
    _sshCommand.text = app.settings.getString(SettingKeys.sshBuildCommand, _isFlutterProject ? 'flutter build apk --release' : '');
    _sshApk.text = app.settings.getString(SettingKeys.sshBuildOutput, _isFlutterProject ? 'build/app/outputs/flutter-apk/app-release.apk' : '');
    _job = widget.debugController?..addListener(_onJob);
  }

  @override
  void dispose() {
    _job?.removeListener(_onJob);
    _repo.dispose();
    _ref.dispose();
    _workflow.dispose();
    _token.dispose();
    _sshDir.dispose();
    _sshCommand.dispose();
    _sshApk.dispose();
    super.dispose();
  }

  void _onJob() {
    if (mounted) setState(() {});
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

    final outDir = await _apkOutDir();
    final files = _pushFirst ? await ApkBuildController.collectFiles(widget.session.guard) : null;
    if (!mounted) return;
    _job?.removeListener(_onJob);
    final job = ApkBuildController(
      client: GitHubClient(token: token, owner: parts[0].trim(), repo: parts[1].trim()),
      workflowFile: workflow,
      ref: ref,
      outputDir: outDir.path,
    )..addListener(_onJob);
    setState(() => _job = job);
    FocusScope.of(context).unfocus();
    await job.run(pushFiles: files);
  }

  Future<Directory> _apkOutDir() async {
    final outDir = (Platform.isAndroid ? await getExternalStorageDirectory() : null) ?? await getApplicationDocumentsDirectory();
    return Directory(p.join(outDir.path, 'apk', widget.session.project.id));
  }

  Future<void> _editSshHost() async {
    await Navigator.of(context).push<SshConfig>(MaterialPageRoute(builder: (_) => const SshConnectScreen(submitLabel: '保存')));
    if (mounted) setState(() {});
  }

  Future<void> _startSsh() async {
    final app = appOf(context);
    final navigator = Navigator.of(context);
    final config = SshConfig.load(app.settings);
    final dir = _sshDir.text.trim();
    final command = _sshCommand.text.trim();
    final apk = _sshApk.text.trim();
    final problem = !config.isComplete
        ? '请先设置构建机'
        : dir.isEmpty
        ? '请填写远程目录'
        : command.isEmpty
        ? '请填写构建命令'
        : apk.isEmpty
        ? '请填写 APK 路径'
        : null;
    if (problem != null) {
      showSnack(context, problem);
      return;
    }
    await app.settings.set(SettingKeys.sshBuildDir, dir);
    await app.settings.set(SettingKeys.sshBuildCommand, command);
    await app.settings.set(SettingKeys.sshBuildOutput, apk);
    final outDir = await _apkOutDir();
    final files = _uploadFirst ? await ApkBuildController.collectFiles(widget.session.guard) : null;
    if (!mounted) return;
    _job?.removeListener(_onJob);
    final job = SshBuildController(
      exec: DartSshRemoteExec(
        () => connectSsh(
          config: config,
          secrets: app.secrets,
          knownHosts: KnownHosts(app.settings),
          onUnknownHost: (config, type, fingerprint) async => mounted ? confirmHostKey(navigator.context, config, type, fingerprint) : false,
        ),
      ),
      remoteDir: dir,
      command: command,
      apkRemotePath: apk,
      outputDir: outDir.path,
    )..addListener(_onJob);
    setState(() => _job = job);
    FocusScope.of(context).unfocus();
    await job.run(uploadFiles: files);
  }

  Future<void> _setMode(bool ssh) async {
    setState(() => _ssh = ssh);
    await appOf(context).settings.set(SettingKeys.apkBuildMode, ssh ? 'ssh' : 'github');
  }

  List<Widget> _sshForm(BuildContext context, bool busy) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    ref.watch(sshConfigRevProvider); // 构建机和终端的 SSH 主机是同一台：在别的页面改了，这里跟着变
    final config = SshConfig.load(appOf(context).settings);
    final job = _job;
    return [
      Text('① 构建机', style: t.titleMedium),
      const SizedBox(height: Space.x3),
      Material(
        color: c.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.md),
          side: BorderSide(color: c.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          key: const Key('ssh-build-host'),
          enabled: !busy,
          leading: Icon(Icons.dns_outlined, color: c.textMuted),
          title: Text(
            config.isComplete ? config.display : '还没设置',
            style: config.isComplete ? const TextStyle(fontFamily: kMonoFont, fontFamilyFallback: kMonoFallback, fontSize: FontSize.sm) : null,
          ),
          subtitle: Text(config.isComplete ? (config.useKey ? '私钥登录' : '密码登录') : '填一台装好 Android SDK 的服务器'),
          trailing: const Icon(Icons.chevron_right),
          onTap: _editSshHost,
        ),
      ),
      const SizedBox(height: Space.x6),
      Text('② 构建命令', style: t.titleMedium),
      const SizedBox(height: Space.x3),
      TextField(
        controller: _sshDir,
        enabled: !busy,
        autocorrect: false,
        decoration: const InputDecoration(labelText: '远程目录', helperText: '项目文件传到这里，命令也在这里运行'),
      ),
      const SizedBox(height: Space.x3),
      TextField(
        controller: _sshCommand,
        enabled: !busy,
        autocorrect: false,
        minLines: 1,
        maxLines: 3,
        decoration: const InputDecoration(labelText: '构建命令', hintText: '例如 flutter build apk --release'),
      ),
      const SizedBox(height: Space.x3),
      TextField(
        controller: _sshApk,
        enabled: !busy,
        autocorrect: false,
        decoration: const InputDecoration(labelText: 'APK 路径', helperText: '构建完 APK 在哪；相对路径按远程目录算'),
      ),
      const SizedBox(height: Space.x6),
      Text('③ 打包', style: t.titleMedium),
      const SizedBox(height: Space.x1),
      Row(
        children: [
          Expanded(child: Text('先把项目文件传到构建机', style: t.bodyMedium)),
          Switch(value: _uploadFirst, onChanged: busy ? null : (v) => setState(() => _uploadFirst = v)),
        ],
      ),
      const SizedBox(height: Space.x2),
      busy
          ? OutlinedButton(onPressed: job!.cancel, child: const Text('停止并断开'))
          : FilledButton.icon(key: const Key('ssh-build-start'), onPressed: _startSsh, icon: const Icon(Icons.rocket_launch_outlined, size: 18), label: Text(job == null ? '开始打包' : '重新打包')),
      if (job != null) ...[const SizedBox(height: Space.x4), _JobCard(job: job)],
    ];
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
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final job = _job;
    final busy = job?.busy ?? false;
    return Scaffold(
      appBar: const ShellAppBar(title: 'APK 打包'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Space.x4, Space.x2, Space.x4, Space.x8),
        children: [
          InfoBanner(
            _ssh
                ? '手机上跑不了 Android SDK 和 Gradle，所以不是在手机里打包：LopiCode 通过 SSH 连到你的服务器，在上面运行构建命令，再把 APK 拉回手机。'
                : '手机上跑不了 Android SDK 和 Gradle，所以不是在手机里打包：LopiCode 把项目推到你的 GitHub 仓库，让 GitHub Actions 打包，再把 APK 下载回来。',
          ),
          const SizedBox(height: Space.x4),
          SegmentedButton<bool>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: false, label: Text('GitHub Actions')),
              ButtonSegment(value: true, label: Text('SSH 构建机')),
            ],
            selected: {_ssh},
            onSelectionChanged: busy ? null : (s) => _setMode(s.first),
          ),
          const SizedBox(height: Space.x6),
          if (_ssh)
            ..._sshForm(context, busy)
          else ...[
            Text('① 仓库', style: t.titleMedium),
            const SizedBox(height: Space.x3),
            TextField(
              controller: _repo,
              enabled: !busy,
              autocorrect: false,
              decoration: const InputDecoration(labelText: '仓库', hintText: '用户名/仓库名'),
            ),
            const SizedBox(height: Space.x3),
            TextField(
              controller: _ref,
              enabled: !busy,
              autocorrect: false,
              decoration: const InputDecoration(labelText: '分支', hintText: 'main'),
            ),
            const SizedBox(height: Space.x3),
            TextField(
              controller: _token,
              enabled: !busy,
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(labelText: 'GitHub Token', hintText: _hasToken ? '已保存，留空表示不改' : '粘贴 Token', helperText: '需要这个仓库的 Contents 和 Actions 读写权限；要推送工作流文件还得有 Workflows 权限。加密保存在本机。'),
            ),
            const SizedBox(height: Space.x6),
            Text('② 工作流', style: t.titleMedium),
            const SizedBox(height: Space.x3),
            TextField(
              controller: _workflow,
              enabled: !busy,
              autocorrect: false,
              decoration: const InputDecoration(labelText: '工作流文件名', hintText: 'android.yml'),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(onPressed: _showTemplate, icon: const Icon(Icons.description_outlined, size: 18), label: Text(_isFlutterProject ? '查看现成模板（Flutter 项目）' : '查看现成模板（网页套壳成 App）')),
            ),
            const SizedBox(height: Space.x4),
            Text('③ 打包', style: t.titleMedium),
            const SizedBox(height: Space.x1),
            Row(
              children: [
                Expanded(child: Text('先把项目文件推送到仓库', style: t.bodyMedium)),
                Switch(value: _pushFirst, onChanged: busy ? null : (v) => setState(() => _pushFirst = v)),
              ],
            ),
            const SizedBox(height: Space.x2),
            busy
                ? OutlinedButton(onPressed: job!.cancel, child: const Text('停止等待'))
                : FilledButton.icon(onPressed: _start, icon: const Icon(Icons.rocket_launch_outlined, size: 18), label: Text(job == null ? '开始打包' : '重新打包')),
            if (job != null) ...[const SizedBox(height: Space.x4), _JobCard(job: job)],
          ],
          if (widget.session.project.template == ProjectTemplate.lowcode) ...[
            const SizedBox(height: Space.x2),
            Text('低代码页面会按“网页套壳”的方式打包（用导出的 index.html）。', style: t.bodySmall?.copyWith(color: c.textMuted)),
          ],
        ],
      ),
    );
  }
}

class _JobCard extends StatelessWidget {
  const _JobCard({required this.job});
  final BuildJob job;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final (String title, Color color, IconData icon) = switch (job.phase) {
      BuildPhase.done => ('打包完成', c.accent, Icons.check_circle_outline),
      BuildPhase.failed => ('打包没成功', c.danger, Icons.error_outline),
      BuildPhase.cancelled => ('已停止等待', c.warning, Icons.pause_circle_outline),
      BuildPhase.connecting => ('正在连接构建机', c.text, Icons.link),
      BuildPhase.building => ('构建机正在打包', c.text, Icons.hourglass_top),
      BuildPhase.pushing => ('正在上传文件', c.text, Icons.cloud_upload_outlined),
      BuildPhase.dispatching => ('正在触发工作流', c.text, Icons.play_circle_outline),
      BuildPhase.waiting => ('GitHub 正在打包', c.text, Icons.hourglass_top),
      BuildPhase.downloading => ('正在下载 APK', c.text, Icons.cloud_download_outlined),
      BuildPhase.idle => ('准备中', c.text, Icons.more_horiz),
    };
    Widget copyRow(String label, String value) => Padding(
      padding: const EdgeInsets.only(top: Space.x3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: t.labelMedium),
          const SizedBox(height: 2),
          Row(
            children: [
              Expanded(
                child: Text(
                  value,
                  style: TextStyle(fontFamily: kMonoFont, fontFamilyFallback: kMonoFallback, fontSize: FontSize.xs, height: 1.5, color: c.text),
                ),
              ),
              IconButton(
                tooltip: '复制',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.copy, size: 16),
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: value));
                  if (context.mounted) showSnack(context, '已复制');
                },
              ),
            ],
          ),
        ],
      ),
    );
    return Container(
      padding: const EdgeInsets.all(Space.x4),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: color),
              const SizedBox(width: Space.x2),
              Expanded(
                child: Text(title, style: t.titleMedium?.copyWith(color: color)),
              ),
              if (job.busy) const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
            ],
          ),
          const SizedBox(height: Space.x3),
          for (final line in job.log)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(line, style: t.bodySmall?.copyWith(color: c.textMuted, height: 1.6)),
            ),
          if (job.output.trim().isNotEmpty) ...[
            const SizedBox(height: Space.x2),
            Container(
              width: double.infinity,
              constraints: const BoxConstraints(maxHeight: 220),
              padding: const EdgeInsets.all(Space.x2),
              decoration: BoxDecoration(
                color: c.codeBg,
                borderRadius: BorderRadius.circular(Radii.sm),
                border: Border.all(color: c.border),
              ),
              child: SingleChildScrollView(
                reverse: true,
                child: SelectableText(
                  job.output.trimRight(),
                  style: TextStyle(fontFamily: kMonoFont, fontFamilyFallback: kMonoFallback, fontSize: FontSize.xs, height: 1.45, color: c.text),
                ),
              ),
            ),
          ],
          if (job.apkPath != null) copyRow('APK 保存在（用文件管理器打开安装）', job.apkPath!),
          if (job.runUrl != null) copyRow('运行页面（完整日志）', job.runUrl!),
        ],
      ),
    );
  }
}
