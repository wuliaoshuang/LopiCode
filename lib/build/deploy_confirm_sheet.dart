// 设计约束（构建与部署 · 底部面板 · 390×844）
//
// 三张面板，都是“先给你看全文，你点了才做”：
//   - [showWorkflowSheet]：部署工作流的全文，可以直接改；“写进项目”才落到 .github/workflows/。
//   - [showPushConfirmSheet]：推送前的清单——推到哪、推哪些文件、哪些被挡在外面、接下来会做什么。
//   - [showSshConfirmSheet]：SSH 部署前的清单——连哪台、每一步执行的命令全文、传哪些文件。
// 层级：标题 → 一句话说清这一下会发生什么 → 清单（分组卡片；文件清单默认收着，点开才展开，免得一屏都是文件名）→
//   底部固定两个按钮：主按钮（确认）在上，“取消”是弱化的文字按钮在下。
// 命令和工作流用等宽字、代码底色；字号读全应用的代码字号。被挡掉的文件用正文弱色，不用红色（不是出错）。
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lopicode/build/deploy_commands.dart';
import 'package:lopicode/build/deploy_files.dart';
import 'package:lopicode/build/deploy_widgets.dart';
import 'package:lopicode/build/deploy_workflows.dart';
import 'package:lopicode/state/code_font.dart';
import 'package:lopicode/state/deploy_github.dart';
import 'package:lopicode/state/deploy_ssh.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/settings_widgets.dart';
import 'package:material_ui/material_ui.dart';

Widget _confirmFooter(BuildContext context, {required String label}) => Column(
  mainAxisSize: MainAxisSize.min,
  crossAxisAlignment: CrossAxisAlignment.stretch,
  children: [
    FilledButton(
      key: const Key('deploy-confirm'),
      onPressed: () => Navigator.pop(context, true),
      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
      child: Text(label),
    ),
    const SizedBox(height: Space.x1),
    TextButton(key: const Key('deploy-confirm-cancel'), onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
  ],
);

/// 等宽的一块文字（命令、路径）。
class _Mono extends ConsumerWidget {
  const _Mono(this.text, {this.faint = false});
  final String text;
  final bool faint;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(Space.x3),
      decoration: BoxDecoration(color: c.codeBg, borderRadius: BorderRadius.circular(Radii.md)),
      child: SelectableText(
        text,
        style: TextStyle(fontFamily: kMonoFont, fontFamilyFallback: kMonoFallback, fontSize: ref.watch(compactCodeFontProvider), height: 1.45, color: faint ? c.textMuted : c.text),
      ),
    );
  }
}

/// 文件清单：一行摘要，点开看全部（要带走的 + 被挡掉的和原因）。
class _FileList extends StatefulWidget {
  const _FileList({required this.files, required this.verb});
  final DeployFileSet files;

  /// “推送” / “上传”。
  final String verb;

  @override
  State<_FileList> createState() => _FileListState();
}

class _FileListState extends State<_FileList> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final set = widget.files;
    return SettingsGroup(
      title: '文件',
      children: [
        SettingsRow(
          key: const Key('deploy-files-toggle'),
          icon: Icons.folder_outlined,
          title: '${widget.verb} ${set.files.length} 个文件 · ${formatDeployBytes(set.totalBytes)}',
          subtitle: set.skipped.isEmpty ? '没有被挡掉的文件' : '另有 ${set.skipped.length} 项不会${widget.verb}（密钥、依赖目录、构建产物等）',
          value: _open ? '收起' : '展开',
          onTap: () => setState(() => _open = !_open),
        ),
        if (_open)
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.x4, Space.x3, Space.x4, Space.x4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Mono(set.files.map((f) => f.rel).join('\n')),
                if (set.skipped.isNotEmpty) ...[
                  const SizedBox(height: Space.x3),
                  Text('不会${widget.verb}的', style: t.labelMedium?.copyWith(color: c.textMuted)),
                  const SizedBox(height: Space.x2),
                  _Mono(set.skipped.map((s) => '${s.rel}  — ${s.reason}').join('\n'), faint: true),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

/// 推送前确认。返回 true＝她点了“确认推送并启动”。
Future<bool> showPushConfirmSheet(BuildContext context, GithubDeployPlan plan) async {
  final ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (sheet) => DeploySheet(
      title: '确认推送并启动',
      note: '点确认后会做两件事：把下面的文件推送到仓库（一次提交，只新增和修改，不删仓库里的文件），然后启动部署工作流。',
      footer: _confirmFooter(sheet, label: '确认推送并启动'),
      children: [
        SettingsGroup(
          title: '推到哪',
          children: [
            SettingsRow(icon: Icons.inventory_2_outlined, title: '仓库', value: '${plan.owner}/${plan.repo}'),
            SettingsRow(icon: Icons.call_split_rounded, title: '分支', value: plan.branch),
            SettingsRow(icon: Icons.play_circle_outline_rounded, title: '启动的工作流', subtitle: plan.runDeploy ? '构建完接着部署到服务器（用仓库里配的 Secrets）' : '只构建并上传产物，不部署', value: plan.workflowFile),
          ],
        ),
        _FileList(files: plan.files, verb: '推送'),
      ],
    ),
  );
  return ok ?? false;
}

/// SSH 部署前确认。返回 true＝她点了“确认，开始执行”。
Future<bool> showSshConfirmSheet(BuildContext context, SshDeployPlan plan) async {
  final t = Theme.of(context).textTheme;
  final ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (sheet) => DeploySheet(
      title: '确认要执行的步骤',
      note: '点确认后会连到 ${plan.host}，按顺序执行下面每一步，原样执行、不多不少。哪一步失败就停在那里，后面的不执行。',
      footer: _confirmFooter(sheet, label: '确认，开始执行'),
      children: [
        for (final (i, step) in plan.steps.indexed) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: Space.x2),
            child: Text('${i + 1}. ${step.title}', style: t.labelLarge),
          ),
          _Mono(step.command),
          const SizedBox(height: Space.x4),
        ],
        _FileList(files: plan.files, verb: '上传'),
      ],
    ),
  );
  return ok ?? false;
}

/// 部署工作流的全文：能改；点“写进项目”返回改过的全文，点别处关掉返回 null。
Future<String?> showWorkflowSheet(BuildContext context, {required String text, required String path, required bool exists}) => showModalBottomSheet<String>(
  context: context,
  isScrollControlled: true,
  builder: (_) => _WorkflowSheet(text: text, path: path, exists: exists),
);

class _WorkflowSheet extends ConsumerStatefulWidget {
  const _WorkflowSheet({required this.text, required this.path, required this.exists});
  final String text;
  final String path;
  final bool exists;

  @override
  ConsumerState<_WorkflowSheet> createState() => _WorkflowSheetState();
}

class _WorkflowSheetState extends ConsumerState<_WorkflowSheet> {
  late final TextEditingController _text = TextEditingController(text: widget.text);

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    return DeploySheet(
      title: '部署工作流',
      note:
          '${widget.exists ? '这是项目里现有的 ${widget.path}。' : '这是按项目语言生成的，还没写进项目。'}'
          '默认只“构建并上传产物”；最后那步“部署到服务器”要你在 GitHub 仓库里配好 Secrets 才会跑。可以直接在下面改。这份模板没在真实的 GitHub Actions 上跑过。',
      footer: FilledButton(
        key: const Key('deploy-workflow-write'),
        onPressed: _text.text.trim().isEmpty ? null : () => Navigator.pop(context, _text.text),
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
        child: Text(widget.exists ? '保存到项目（覆盖现有的）' : '写进项目'),
      ),
      children: [
        TextField(
          key: const Key('deploy-workflow-text'),
          controller: _text,
          maxLines: null,
          minLines: 12,
          keyboardType: TextInputType.multiline,
          autocorrect: false,
          enableSuggestions: false,
          onChanged: (_) => setState(() {}),
          style: TextStyle(fontFamily: kMonoFont, fontFamilyFallback: kMonoFallback, fontSize: ref.watch(compactCodeFontProvider), height: 1.45, color: c.text),
          decoration: InputDecoration(
            filled: true,
            fillColor: c.codeBg,
            contentPadding: const EdgeInsets.all(Space.x3),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(Radii.md), borderSide: BorderSide.none),
          ),
        ),
        const SizedBox(height: Space.x4),
        Text('要部署到服务器，需要配的 Secrets', style: t.labelLarge),
        const SizedBox(height: Space.x2),
        Text('在 $kDeploySecretsWhere 里加。密钥只放在那里，不要写进上面的文件。', style: t.bodySmall?.copyWith(color: c.textMuted, height: 1.6)),
        const SizedBox(height: Space.x2),
        for (final e in kDeploySecrets.entries)
          Padding(
            padding: const EdgeInsets.only(bottom: Space.x1),
            child: Text('${e.key} — ${e.value}', style: t.bodySmall?.copyWith(height: 1.6)),
          ),
      ],
    );
  }
}

/// 本地构建“这次会做什么”：每一步的名字和命令全文（只读）。
Future<void> showLocalStepsSheet(BuildContext context, List<DeployStep> steps, {required String output}) {
  final t = Theme.of(context).textTheme;
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheet) => DeploySheet(
      title: '这次会执行的命令',
      note: '都在手机的 Ubuntu 运行环境里、从工作区根目录出发执行。产物：build/$output',
      children: [
        if (steps.isEmpty) Text('没有要执行的命令：只把源码打成压缩包。', style: t.bodyMedium),
        for (final (i, step) in steps.indexed) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: Space.x2),
            child: Text('${i + 1}. ${step.title}', style: t.labelLarge),
          ),
          _Mono(step.command),
          const SizedBox(height: Space.x4),
        ],
      ],
    ),
  );
}
