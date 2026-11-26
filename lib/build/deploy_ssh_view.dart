// 设计约束（构建与部署 · SSH 部署 · 390×844）
//
// 后端项目的“SSH 部署”表单：把代码传到服务器，在服务器上编译 / 装依赖，需要的话重启服务。
// 层级：① 主机（一行，点进去改；和终端、SSH 构建机是同一台）→ ② 目录与命令（远程目录、编译命令各一行；
//   “部署完重启服务”开关一行，打开才出现“重启命令”那一行）→ 唯一的主按钮“查看步骤并开始”→ 进度 / 结果卡。
// 主按钮不直接动手：先弹“确认要执行的步骤”，把每一步的命令全文列出来，点了确认才连接、才执行。
// 默认命令里没有任何删除服务器上东西的命令；用户自己填的命令原样执行，但也先原样列出来。
// 颜色：强调色只给主按钮和“完成”；红色只给失败。
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lopicode/build/build_widgets.dart';
import 'package:lopicode/build/deploy_commands.dart';
import 'package:lopicode/build/deploy_confirm_sheet.dart';
import 'package:lopicode/build/deploy_files.dart';
import 'package:lopicode/build/deploy_project.dart';
import 'package:lopicode/build/deploy_widgets.dart';
import 'package:lopicode/core/stores.dart';
import 'package:lopicode/project_session.dart';
import 'package:lopicode/ssh/ssh_config.dart';
import 'package:lopicode/ssh/ssh_connect_screen.dart';
import 'package:lopicode/state/app_providers.dart';
import 'package:lopicode/state/config_providers.dart';
import 'package:lopicode/state/deploy_run.dart';
import 'package:lopicode/state/deploy_ssh.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/app_ref.dart';
import 'package:lopicode/ui/settings_widgets.dart';
import 'package:lopicode/ui/widgets.dart';
import 'package:material_ui/material_ui.dart';

class DeploySshView extends ConsumerStatefulWidget {
  const DeploySshView({super.key, required this.session, required this.project});
  final ProjectSession session;
  final DeployProject project;

  @override
  ConsumerState<DeploySshView> createState() => _DeploySshViewState();
}

class _DeploySshViewState extends ConsumerState<DeploySshView> {
  final _dir = TextEditingController();
  final _build = TextEditingController();
  final _restart = TextEditingController();
  bool _loaded = false;
  final _cardKey = GlobalKey();

  DeploySshNotifier get _notifier => ref.read(deploySshProvider(widget.session).notifier);
  String _key(String key) => deployKey(key, widget.session);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loaded) return;
    _loaded = true;
    final n = _notifier;
    _dir.text = n.remoteDir;
    _build.text = n.buildCommand(widget.project);
    _restart.text = n.restartCommand;
  }

  @override
  void didUpdateWidget(DeploySshView old) {
    super.didUpdateWidget(old);
    // 认出的语言 / 结构变了（比如刚加了 pom.xml），而编译命令她没动过：跟着换成新的默认。
    final before = defaultRemoteBuildCommand(old.project);
    final after = defaultRemoteBuildCommand(widget.project);
    if (before != after && _build.text.trim() == before) _build.text = after;
  }

  @override
  void dispose() {
    _dir.dispose();
    _build.dispose();
    _restart.dispose();
    super.dispose();
  }

  Future<void> _editHost() async {
    await Navigator.of(context).push<SshConfig>(MaterialPageRoute(builder: (_) => const SshConnectScreen(submitLabel: '保存')));
    if (mounted) setState(() {});
  }

  Future<void> _save() async {
    final settings = appOf(context).settings;
    final dir = _dir.text.trim();
    final build = _build.text.trim();
    // 和默认一样就不存（以后默认跟着项目变）；改过——包括清空——才存。
    await settings.set(_key(SettingKeys.deploySshDir), dir.isEmpty ? null : dir);
    await settings.set(_key(SettingKeys.deploySshBuild), build == defaultRemoteBuildCommand(widget.project) ? null : build);
    await settings.set(_key(SettingKeys.deploySshRestart), _restart.text.trim().isEmpty ? null : _restart.text.trim());
    if (dir.isEmpty && mounted) _dir.text = _notifier.remoteDir;
  }

  Future<void> _start() async {
    final navigator = Navigator.of(context);
    await _save();
    if (!mounted) return;
    final notifier = _notifier;
    final SshDeployPlan plan;
    try {
      plan = notifier.plan(widget.project);
    } on DeployException catch (e) {
      showSnack(context, e.message);
      return;
    }
    FocusScope.of(context).unfocus();
    if (!await showSshConfirmSheet(context, plan) || !mounted) return;
    // 进度卡在主按钮下面：滚进视野，不然点了像没反应。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final card = _cardKey.currentContext;
      if (card != null) unawaited(revealBelowBar(card));
    });
    await notifier.start(plan, onUnknownHost: (config, type, fingerprint) async => mounted ? confirmHostKey(navigator.context, config, type, fingerprint) : false);
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    ref.watch(sshConfigRevProvider); // 和终端、SSH 构建机是同一台主机：在别的页面改了，这里跟着变
    final restartKey = _key(SettingKeys.deploySshRestartOn);
    ref.watch(settingRevProvider(restartKey));
    final settings = ref.watch(settingsStoreProvider);
    final config = SshConfig.load(settings);
    final restartOn = settings.getBool(restartKey);
    final state = ref.watch(deploySshProvider(session));
    final busy = state.busy;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SettingsGroup(
          title: '① 主机',
          children: [
            SettingsRow(
              key: const Key('deploy-ssh-host'),
              icon: Icons.dns_outlined,
              enabled: !busy,
              title: config.isComplete ? config.display : '还没设置',
              subtitle: config.isComplete ? (config.useKey ? '私钥登录' : '密码登录') : '填上要部署到的那台服务器',
              onTap: _editHost,
            ),
          ],
        ),
        SettingsGroup(
          title: '② 目录与命令',
          padded: true,
          children: [
            PackField(fieldKey: const Key('deploy-ssh-dir'), label: '远程目录', controller: _dir, enabled: !busy, mono: true, helper: '代码传到这里并解压：同名文件会被覆盖，服务器上多出来的文件不会被删'),
            PackField(
              fieldKey: const Key('deploy-ssh-build'),
              label: '编译 / 装依赖的命令',
              controller: _build,
              enabled: !busy,
              mono: true,
              minLines: 1,
              maxLines: 4,
              hint: '留空就跳过这一步',
              helper: '在远程目录里执行。服务器上要先装好 ${widget.project.lang == DeployLang.other ? '需要的工具' : widget.project.lang.label}',
              last: !restartOn,
            ),
            if (restartOn)
              PackField(
                fieldKey: const Key('deploy-ssh-restart'),
                label: '重启服务的命令',
                controller: _restart,
                enabled: !busy,
                mono: true,
                minLines: 1,
                maxLines: 4,
                hint: '例如 systemctl restart 你的服务名',
                helper: '最后一步，在远程目录里原样执行',
                last: true,
              ),
          ],
        ),
        SettingsGroup(
          children: [
            SettingsSwitchRow(
              switchKey: const Key('deploy-ssh-restart-on'),
              title: '部署完重启服务',
              subtitle: '命令你自己填；关着就只传代码、编译',
              value: restartOn,
              onChanged: busy ? null : (v) => settings.setLater(restartKey, v ? true : null),
            ),
          ],
        ),
        busy
            ? OutlinedButton(
                key: const Key('deploy-cancel'),
                onPressed: _notifier.cancel,
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                child: const Text('取消'),
              )
            : PrimaryBuildButton(buttonKey: const Key('deploy-start'), label: state.phase == DeployPhase.idle ? '查看步骤并开始' : '再部署一次', onPressed: _start),
        if (state.phase != DeployPhase.idle) ...[const SizedBox(height: Space.x4), DeployRunCard(key: _cardKey, state: state, outputLabel: '服务器上的输出')],
      ],
    );
  }
}
