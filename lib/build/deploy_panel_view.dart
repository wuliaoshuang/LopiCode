// 设计约束（构建与部署 · 后端项目的打包页正文 · 390×844）
//
// 霜霜（2026-11-26）：“后端项目默认打包形式应该和 apk 区分开。本地打包就是能编译的就编译。
//   github 和 ssh，这两个分别是推送代码并启动部署工作流和操作 ssh 直接编译部署。”
// 内容排序（Refactoring UI：先定层级，再排版，最后上色）
//   主要：用哪种方式（三选一）→ 这种方式要填的东西 → 唯一的主按钮 → 进度 / 结果卡。
//   次要：这是什么类型的项目（最上面一行，认错了点它改）；这种方式是怎么回事（三选一下面一句弱色小字）。
// 三种方式的表单都一直留着（只是不显示），切走再切回来填到一半的内容和上一次的结果都还在。
//   任何一种正在跑时，三选一和“项目类型”都锁住（不然切走就看不到进度了）。
// 排版和 APK 打包页同一套：浅灰底上放白色分组卡片；页边 16，组与组相隔 24，组标题是弱色小字。
// 颜色：强调色只给选中的方式、主按钮、“完成”；红色只给失败。
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lopicode/build/deploy_github_view.dart';
import 'package:lopicode/build/deploy_local_view.dart';
import 'package:lopicode/build/deploy_project.dart';
import 'package:lopicode/build/deploy_ssh_view.dart';
import 'package:lopicode/build/deploy_widgets.dart';
import 'package:lopicode/core/stores.dart';
import 'package:lopicode/project_session.dart';
import 'package:lopicode/state/deploy_busy.dart';
import 'package:lopicode/state/deploy_run.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/app_ref.dart';
import 'package:lopicode/ui/settings_widgets.dart';
import 'package:material_ui/material_ui.dart';

class DeployPanel extends ConsumerWidget {
  const DeployPanel({super.key, required this.session, required this.project});
  final ProjectSession session;
  final DeployProject project;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final mode = ref.watch(deployModeProvider(session));
    final busy = ref.watch(deployBusyProvider(session));
    Widget section(DeployMode m, Widget child) => Offstage(
      offstage: mode != m,
      child: TickerMode(enabled: mode == m, child: child),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SettingsGroup(
          children: [
            SettingsRow(
              key: const Key('deploy-kind'),
              icon: Icons.category_outlined,
              title: '项目类型',
              subtitle: project.auto ? '自动识别：${project.reason}' : '你手动选的',
              value: project.title,
              valueKey: const Key('deploy-kind-value'),
              enabled: !busy,
              onTap: () => showProjectKindSheet(context, session, project),
            ),
          ],
        ),
        DeployModePicker(mode: mode, onChanged: busy ? null : (m) => appOf(context).settings.setLater(deployKey(SettingKeys.deployMode, session), m.id)),
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.x1, Space.x3, Space.x1, Space.x6),
          child: Text(
            mode.about,
            key: const Key('deploy-mode-about'),
            style: t.bodySmall?.copyWith(color: c.textFaint, height: 1.6),
          ),
        ),
        section(DeployMode.local, DeployLocalView(session: session, project: project)),
        section(DeployMode.github, DeployGithubView(session: session, project: project)),
        section(DeployMode.ssh, DeploySshView(session: session, project: project)),
      ],
    );
  }
}
