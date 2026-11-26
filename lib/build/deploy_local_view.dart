// 设计约束（构建与部署 · 本地构建 · 390×844）
//
// 后端项目的“本地构建”表单：能编译的就编译（Go → 程序，Java → jar），不用编译的检查语法后打成压缩包。
// 层级：① 这次会做什么（产物叫什么、会执行哪些命令——命令全文收进底部面板）→ ② 选项（只有 Go / Node 有；没有就不出这组）→
//   唯一的主按钮“开始构建”→ 进度 / 结果卡。做不了的项目（带包名的 Java 等）不给主按钮，换成一段说明讲清原因和出路。
// 一行只做一件事：每个开关一行，说明写在开关下面的小字里。
// 颜色：强调色只给主按钮和“完成”；“做不了”的说明是正文弱色，不是红色（不是出错）。
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lopicode/build/build_widgets.dart';
import 'package:lopicode/build/deploy_commands.dart';
import 'package:lopicode/build/deploy_confirm_sheet.dart';
import 'package:lopicode/build/deploy_project.dart';
import 'package:lopicode/build/deploy_widgets.dart';
import 'package:lopicode/core/stores.dart';
import 'package:lopicode/project_session.dart';
import 'package:lopicode/state/app_providers.dart';
import 'package:lopicode/state/deploy_local.dart';
import 'package:lopicode/state/deploy_run.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/settings_widgets.dart';
import 'package:material_ui/material_ui.dart';

class DeployLocalView extends ConsumerWidget {
  const DeployLocalView({super.key, required this.session, required this.project});
  final ProjectSession session;
  final DeployProject project;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final settings = ref.watch(settingsStoreProvider);
    final amdKey = deployKey(SettingKeys.deployGoAmd64, session);
    final npmKey = deployKey(SettingKeys.deployNpmInstall, session);
    ref.watch(settingRevProvider(amdKey));
    ref.watch(settingRevProvider(npmKey));
    final amd64 = settings.getBool(amdKey);
    final npm = settings.getBool(npmKey);
    final state = ref.watch(deployLocalProvider(session));
    final notifier = ref.read(deployLocalProvider(session).notifier);
    final plan = localBuildPlan(project, name: session.project.id, amd64: amd64, npmInstall: npm);
    final busy = state.busy;
    final what = switch (plan.outputKind) {
      LocalOutputKind.binary => '编译成 Linux 程序',
      LocalOutputKind.jar => '编译并打成 jar',
      LocalOutputKind.archive => plan.steps.isEmpty ? '把源码打成压缩包' : '检查语法，再打成压缩包',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SettingsGroup(
          title: '① 这次会做什么',
          children: [
            SettingsRow(icon: Icons.inventory_2_outlined, title: what, subtitle: '产物：build/${plan.output}'),
            if (plan.unsupported == null)
              SettingsRow(
                key: const Key('deploy-local-steps'),
                icon: Icons.terminal_rounded,
                title: '会执行的命令',
                value: plan.steps.isEmpty ? '没有' : '${plan.steps.length} 条',
                onTap: () => showLocalStepsSheet(context, plan.steps, output: plan.output),
              ),
          ],
        ),
        if (project.lang == DeployLang.go)
          SettingsGroup(
            title: '② 选项',
            children: [
              SettingsSwitchRow(
                switchKey: const Key('deploy-go-amd64'),
                title: '给服务器用（linux/amd64）',
                subtitle: amd64 ? '编出来的程序给 x86-64 的 Linux 服务器用，手机上跑不了' : '现在编的是 linux/arm64：手机的 Ubuntu 环境和 arm64 服务器能跑',
                value: amd64,
                onChanged: busy ? null : (v) => settings.setLater(amdKey, v ? true : null),
              ),
            ],
          ),
        if (project.lang == DeployLang.node && project.hasPackageJson)
          SettingsGroup(
            title: '② 选项',
            children: [
              SettingsSwitchRow(
                switchKey: const Key('deploy-npm-install'),
                title: '把依赖装进包',
                subtitle: '先跑 npm install --omit=dev，把 node_modules 一起打进去。包会大很多；里面有按 CPU 编译的模块时，换到 x86-64 服务器上要重装',
                value: npm,
                onChanged: busy ? null : (v) => settings.setLater(npmKey, v ? true : null),
              ),
            ],
          ),
        if (plan.unsupported != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.x1, 0, Space.x1, Space.x4),
            child: Text(
              plan.unsupported!,
              key: const Key('deploy-local-unsupported'),
              style: t.bodyMedium?.copyWith(color: c.textMuted, height: 1.6),
            ),
          )
        else if (busy)
          OutlinedButton(
            key: const Key('deploy-cancel'),
            onPressed: notifier.cancel,
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            child: const Text('取消'),
          )
        else
          PrimaryBuildButton(
            buttonKey: const Key('deploy-start'),
            label: state.phase == DeployPhase.idle ? '开始构建' : '重新构建',
            onPressed: () => unawaited(notifier.start(project, amd64: amd64, npmInstall: npm)),
          ),
        if (state.phase != DeployPhase.idle) ...[const SizedBox(height: Space.x4), DeployRunCard(state: state, onAnswer: notifier.answerInstall, runtimeProjectDir: session.project.dir)],
      ],
    );
  }
}
