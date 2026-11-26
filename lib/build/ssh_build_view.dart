// 设计约束（打包页 · SSH 构建机方式 · 390×844）
// 一条主线从上到下：① 构建机（在哪打，一行跳转到 SSH 主机设置）→ ② 构建命令（目录 / 命令 / APK 路径，各占一行）
//   → ③ 打包（开关 + 唯一的主按钮）→ 进度 / 结果卡。
// 主按钮只有一个“开始打包”；打包中它换成次要的“停止并断开”，表单锁住。
import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lopicode/build/apk_output.dart';
import 'package:lopicode/build/build_controller.dart';
import 'package:lopicode/build/build_job_view.dart';
import 'package:lopicode/build/build_widgets.dart';
import 'package:lopicode/build/remote_exec.dart';
import 'package:lopicode/build/ssh_build_controller.dart';
import 'package:lopicode/core/stores.dart';
import 'package:lopicode/project_session.dart';
import 'package:lopicode/ssh/ssh_config.dart';
import 'package:lopicode/ssh/ssh_connect_screen.dart';
import 'package:lopicode/ssh/ssh_connector.dart';
import 'package:lopicode/state/config_providers.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/app_ref.dart';
import 'package:lopicode/ui/settings_widgets.dart';
import 'package:lopicode/ui/widgets.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;

class SshBuildView extends ConsumerStatefulWidget {
  const SshBuildView({super.key, required this.session, required this.job, required this.onJob});
  final ProjectSession session;
  final SshBuildController? job;
  final ValueChanged<SshBuildController> onJob;

  @override
  ConsumerState<SshBuildView> createState() => _SshBuildViewState();
}

class _SshBuildViewState extends ConsumerState<SshBuildView> {
  final _dir = TextEditingController();
  final _command = TextEditingController();
  final _apk = TextEditingController();
  bool _uploadFirst = true;
  bool _loaded = false;
  final _cardKey = GlobalKey();

  bool get _isFlutterProject => File(p.join(widget.session.project.dir, 'pubspec.yaml')).existsSync();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loaded) return;
    _loaded = true;
    final app = appOf(context);
    _dir.text = app.settings.getString(SettingKeys.sshBuildDir, '~/lopicode-build/${widget.session.project.id}');
    _command.text = app.settings.getString(SettingKeys.sshBuildCommand, _isFlutterProject ? 'flutter build apk --release' : '');
    _apk.text = app.settings.getString(SettingKeys.sshBuildOutput, _isFlutterProject ? 'build/app/outputs/flutter-apk/app-release.apk' : '');
  }

  @override
  void dispose() {
    _dir.dispose();
    _command.dispose();
    _apk.dispose();
    super.dispose();
  }

  Future<void> _editHost() async {
    await Navigator.of(context).push<SshConfig>(MaterialPageRoute(builder: (_) => const SshConnectScreen(submitLabel: '保存')));
    if (mounted) setState(() {});
  }

  Future<void> _start() async {
    final app = appOf(context);
    final navigator = Navigator.of(context);
    final config = SshConfig.load(app.settings);
    final dir = _dir.text.trim();
    final command = _command.text.trim();
    final apk = _apk.text.trim();
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
    final outDir = await apkDownloadDir(widget.session.project.id);
    final files = _uploadFirst ? await ApkBuildController.collectFiles(widget.session.guard) : null;
    if (!mounted) return;
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
    );
    widget.onJob(job);
    FocusScope.of(context).unfocus();
    // 进度卡在主按钮下面：滚进视野，不然点了像没反应。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final card = _cardKey.currentContext;
      if (card != null) unawaited(revealBelowBar(card));
    });
    await job.run(uploadFiles: files);
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(sshConfigRevProvider); // 构建机和终端的 SSH 主机是同一台：在别的页面改了，这里跟着变
    final config = SshConfig.load(appOf(context).settings);
    final job = widget.job;
    final busy = job?.busy ?? false;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SettingsGroup(
          title: '① 构建机',
          children: [
            SettingsRow(
              key: const Key('ssh-build-host'),
              icon: Icons.dns_outlined,
              enabled: !busy,
              title: config.isComplete ? config.display : '还没设置',
              subtitle: config.isComplete ? (config.useKey ? '私钥登录' : '密码登录') : '填一台装好 Android SDK 的服务器',
              onTap: _editHost,
            ),
          ],
        ),
        SettingsGroup(
          title: '② 构建命令',
          padded: true,
          children: [
            PackField(label: '远程目录', controller: _dir, enabled: !busy, mono: true, helper: '项目文件传到这里，命令也在这里运行'),
            PackField(label: '构建命令', controller: _command, enabled: !busy, mono: true, minLines: 1, maxLines: 3, hint: '例如 flutter build apk --release'),
            PackField(label: 'APK 路径', controller: _apk, enabled: !busy, mono: true, helper: '构建完 APK 在哪；相对路径按远程目录算', last: true),
          ],
        ),
        SettingsGroup(
          title: '③ 打包',
          children: [SettingsSwitchRow(title: '先把项目文件传到构建机', value: _uploadFirst, onChanged: busy ? null : (v) => setState(() => _uploadFirst = v))],
        ),
        busy
            ? OutlinedButton(
                onPressed: job!.cancel,
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                child: const Text('停止并断开'),
              )
            : PrimaryBuildButton(buttonKey: const Key('ssh-build-start'), label: job == null ? '开始打包' : '重新打包', onPressed: _start),
        if (job != null) ...[const SizedBox(height: Space.x4), BuildJobCard(key: _cardKey, job: job)],
      ],
    );
  }
}
