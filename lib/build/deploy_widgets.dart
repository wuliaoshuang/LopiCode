// 设计约束（构建与部署 · 共用控件 · 390×844）
//
// 这里是后端项目“构建与部署”三种方式共用的三样东西：
//   - [DeployModePicker]：三选一轨道，和 APK 打包页的那条一个样子（44 高、选中的是白底强调色字）；
//   - [DeployRunCard]：进度 / 结果卡，和 APK 的进度卡同一套（RunCard + RunHeader）；
//   - [showProjectKindSheet]：改“项目类型”的底部面板。
// 进度卡的层级（Refactoring UI：先层级）：一句结论最显眼 → 失败原因（红底框）/ 要你点头的问题 / 产物在哪 →
//   步骤清单（弱色小字，现在这一步是正文色）→ 命令输出（等宽框，最多 220 高，自己滚）。
// 颜色：强调色只给“完成”和选中的方式；红色只给失败；黄色只给“已取消”。状态除了颜色还有图标。
// 一行只做一件事：复制路径、复制链接各占一行；“去装运行环境”是失败框下面单独一行的按钮。
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lopicode/build/build_widgets.dart';
import 'package:lopicode/build/deploy_files.dart';
import 'package:lopicode/build/deploy_project.dart';
import 'package:lopicode/core/stores.dart';
import 'package:lopicode/project_session.dart';
import 'package:lopicode/runtime/runtime_screen.dart';
import 'package:lopicode/state/code_font.dart';
import 'package:lopicode/state/deploy_run.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/app_ref.dart';
import 'package:lopicode/ui/settings_widgets.dart';
import 'package:lopicode/ui/shell.dart';
import 'package:material_ui/material_ui.dart';

class DeployModePicker extends StatelessWidget {
  const DeployModePicker({super.key, required this.mode, required this.onChanged});
  final DeployMode mode;
  final ValueChanged<DeployMode>? onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    return Container(
      height: 44,
      padding: const EdgeInsets.all(Space.x1),
      decoration: BoxDecoration(color: c.surfaceMuted, borderRadius: BorderRadius.circular(Radii.lg)),
      child: Row(
        children: [
          for (final m in DeployMode.values)
            Expanded(
              child: Semantics(
                button: true,
                selected: m == mode,
                enabled: onChanged != null,
                child: Material(
                  color: m == mode ? c.surface : Colors.transparent,
                  borderRadius: BorderRadius.circular(Radii.md),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    key: Key('deploy-mode-${m.id}'),
                    onTap: onChanged == null || m == mode ? null : () => onChanged!(m),
                    child: Center(
                      child: Text(
                        m.label,
                        maxLines: 1,
                        style: t.labelLarge?.copyWith(fontWeight: m == mode ? FontWeight.w600 : FontWeight.w400, color: m == mode ? c.accent : (onChanged == null ? c.textFaint : c.textMuted)),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 一次运行的进度 / 结果。[onAnswer] 给“要不要装语言包”用；[onCancel] 为 null 时不出“取消”。
class DeployRunCard extends ConsumerWidget {
  const DeployRunCard({super.key, required this.state, this.onAnswer, this.runtimeProjectDir, this.outputLabel = '命令的输出'});
  final DeployRunState state;
  final ValueChanged<bool>? onAnswer;

  /// 给了就能出“去装运行环境”按钮（跳到运行环境页）。
  final String? runtimeProjectDir;
  final String outputLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final codeSize = ref.watch(compactCodeFontProvider);
    final tone = switch (state.phase) {
      DeployPhase.done => RunTone.done,
      DeployPhase.failed => RunTone.failed,
      DeployPhase.cancelled => RunTone.paused,
      _ => RunTone.busy,
    };
    final result = state.result;
    final failed = state.phase == DeployPhase.failed;
    final url = result?.url ?? state.url;
    return RunCard(
      children: [
        RunHeader(tone: tone, title: state.headline, subtitle: state.phase == DeployPhase.done ? result?.headline : null),
        if (state.failure != null) ...[
          const SizedBox(height: Space.x3),
          Container(
            key: const Key('deploy-failure'),
            padding: const EdgeInsets.all(Space.x3),
            decoration: BoxDecoration(color: failed ? c.dangerSoft : c.surfaceMuted, borderRadius: BorderRadius.circular(Radii.md)),
            child: Text(state.failure!, style: t.bodyMedium?.copyWith(color: failed ? c.danger : c.textMuted, height: 1.5)),
          ),
        ],
        if (state.needsRuntime && runtimeProjectDir != null) ...[
          const SizedBox(height: Space.x3),
          OutlinedButton(
            key: const Key('deploy-go-runtime'),
            onPressed: () {
              final shell = ShellScope.maybeOf(context);
              if (shell != null) {
                shell.go(ShellDest.runtime);
              } else {
                pushSettingsPage<void>(context, RuntimeScreen(projectDir: runtimeProjectDir));
              }
            },
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(44)),
            child: const Text('去装运行环境'),
          ),
        ],
        if (state.ask != null && onAnswer != null) ...[
          const SizedBox(height: Space.x3),
          Text(state.ask!, key: const Key('deploy-ask'), style: t.bodyMedium?.copyWith(height: 1.5)),
          const SizedBox(height: Space.x3),
          FilledButton(
            key: const Key('deploy-ask-yes'),
            onPressed: () => onAnswer!(true),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(44)),
            child: const Text('装上并继续'),
          ),
          const SizedBox(height: Space.x2),
          TextButton(key: const Key('deploy-ask-no'), onPressed: () => onAnswer!(false), child: const Text('先不装')),
        ],
        if (result != null) ...[
          if (result.location != null) ...[const SizedBox(height: Space.x3), CopyLine(label: result.bytes == null ? '位置' : '位置 · ${formatDeployBytes(result.bytes!)}', value: result.location!)],
          for (final note in result.notes)
            Padding(
              padding: const EdgeInsets.only(top: Space.x2),
              child: Text(note, style: t.bodySmall?.copyWith(color: c.textMuted, height: 1.6)),
            ),
        ],
        if (url != null) ...[const SizedBox(height: Space.x3), CopyLine(label: 'GitHub 运行页（完整日志和产物）', value: url, note: '复制后粘贴到浏览器里打开。')],
        if (state.steps.isNotEmpty) ...[
          const SizedBox(height: Space.x3),
          Divider(height: 1, color: c.border),
          const SizedBox(height: Space.x3),
          for (final (i, step) in state.steps.indexed) _StepLine(index: i + 1, step: step),
        ],
        if (state.log.trim().isNotEmpty) ...[
          const SizedBox(height: Space.x2),
          Text(outputLabel, style: t.labelMedium),
          const SizedBox(height: Space.x2),
          Container(
            width: double.infinity,
            constraints: const BoxConstraints(maxHeight: 220),
            padding: const EdgeInsets.all(Space.x3),
            decoration: BoxDecoration(color: c.codeBg, borderRadius: BorderRadius.circular(Radii.md)),
            child: SingleChildScrollView(
              reverse: true,
              child: SelectableText(
                state.log.trimRight(),
                key: const Key('deploy-log'),
                style: TextStyle(fontFamily: kMonoFont, fontFamilyFallback: kMonoFallback, fontSize: codeSize, height: 1.45, color: c.text),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _StepLine extends StatelessWidget {
  const _StepLine({required this.index, required this.step});
  final int index;
  final DeployStepState step;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final (IconData icon, Color color) = switch (step.status) {
      StepStatus.pending => (Icons.radio_button_unchecked_rounded, c.textFaint),
      StepStatus.running => (Icons.more_horiz_rounded, c.text),
      StepStatus.ok => (Icons.check_rounded, c.accent),
      StepStatus.failed => (Icons.close_rounded, c.danger),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.x2),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: Space.x2),
          Expanded(
            child: Text(
              '$index. ${step.title}',
              style: t.bodySmall?.copyWith(
                color: step.status == StepStatus.pending || step.status == StepStatus.ok ? c.textMuted : color,
                fontWeight: step.status == StepStatus.running ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 底部面板的外框：标题 + 一句说明 + 内容（内容多了自己滚），最多占屏幕 85%。
class DeploySheet extends StatelessWidget {
  const DeploySheet({super.key, required this.title, this.note, required this.children, this.footer});
  final String title;
  final String? note;
  final List<Widget> children;

  /// 固定在底部的按钮区（不跟着滚）。
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final media = MediaQuery.of(context);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: media.size.height * 0.85),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(Space.x4, Space.x4, Space.x4, Space.x2),
                child: Text(title, style: t.titleMedium),
              ),
              if (note != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(Space.x4, 0, Space.x4, Space.x3),
                  child: Text(note!, style: t.bodySmall?.copyWith(color: c.textMuted, height: 1.6)),
                ),
              Flexible(
                child: ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(Space.x4, 0, Space.x4, Space.x3), children: children),
              ),
              if (footer != null) Padding(padding: const EdgeInsets.fromLTRB(Space.x4, Space.x2, Space.x4, Space.x4), child: footer),
            ],
          ),
        ),
      ),
    );
  }
}

/// 改“项目类型”：自动识别 / 网页 / 后端 / 其它。选了就按工作区记住。
Future<void> showProjectKindSheet(BuildContext context, ProjectSession session, DeployProject detected) {
  final settings = appOf(context).settings;
  final key = deployKey(SettingKeys.deployKind, session);
  final auto = detectDeployProject(session.project.dir, template: session.project.template, templateLanguage: session.project.language);
  final current = ProjectKind.fromSetting(settings.getString(key));
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheet) {
      Widget row(ProjectKind? kind, String title, String subtitle) => SettingsChoiceRow(
        key: Key('deploy-kind-${kind?.id ?? 'auto'}'),
        title: title,
        subtitle: subtitle,
        selected: current == kind,
        onTap: () {
          settings.setLater(key, kind?.id);
          Navigator.pop(sheet);
        },
      );
      return DeploySheet(
        title: '项目类型',
        note: '打包页按类型给不同的做法。认错了在这里改，只对这个工作区有效。',
        children: [
          SettingsGroup(
            children: [
              row(null, '自动识别', '现在认成：${auto.title}（${auto.reason}）'),
              row(ProjectKind.web, '网页', '打成安卓安装包（APK）'),
              row(ProjectKind.backend, '后端', '构建与部署：本地编译、推到 GitHub 部署、SSH 到服务器部署'),
              row(ProjectKind.other, '其它（Flutter / 原生等）', '用 GitHub Actions 或 SSH 构建机远程打 APK'),
            ],
          ),
        ],
      );
    },
  );
}
