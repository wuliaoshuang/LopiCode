// 设计约束（对话页的面板和窄条 · 390×844）
// - 每个底部面板只做一件事：选模型、选权限、选发送方式、选附件来源、看子代理。
// - 模型面板分三步往下排：渠道（横向一行标签）→ 模型（列表）→ 思考深度（一行分段），不把三样摊在一行。
// - 输入卡片上方的窄条一行一条：左图标 + 一句话 + 右边一个文字按钮。
// - 窄条和确认卡 / 提问卡（chat_cards.dart）是一家：中性底 + 细边，颜色只落在左边那个小图标上。
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lopicode/agent/agent_tools.dart';
import 'package:lopicode/agent/presets.dart';
import 'package:lopicode/project_session.dart';
import 'package:lopicode/state/workspace_chat.dart';
import 'package:lopicode/state/workspace_conversations.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/chat_cards.dart';
import 'package:lopicode/ui/chat_row_view.dart';
import 'package:lopicode/ui/chrome.dart';
import 'package:lopicode/ui/widgets.dart';
import 'package:material_ui/material_ui.dart';

export 'package:lopicode/ui/chat_cards.dart';
export 'package:lopicode/ui/chat_queue.dart';
export 'package:lopicode/ui/model_picker_sheet.dart';

// ── 权限 ─────────────────────────────────────────────
String permissionHint(PermissionLevel level) => switch (level) {
  PermissionLevel.view => 'Agent 只能看文件，不能改、不能删、不能跑命令',
  PermissionLevel.workspace => '可以改工作区里的文件；删文件、跑命令每次先问你',
  PermissionLevel.full => '删文件、跑命令不再问你，适合你完全信任的任务',
};

class PermissionSheet extends StatelessWidget {
  const PermissionSheet({super.key, required this.current, this.title = '这段对话的权限'});
  final PermissionLevel current;
  final String title;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.x4, 0, Space.x4, Space.x2),
            child: Text(title, style: t.titleLarge),
          ),
          for (final level in PermissionLevel.values)
            ListTile(
              leading: Icon(level == current ? Icons.radio_button_checked : Icons.radio_button_off, color: level == current ? c.accent : c.textFaint),
              title: Text(level.label),
              subtitle: Text(permissionHint(level), style: t.bodySmall),
              onTap: () => Navigator.pop(context, level),
            ),
          const SizedBox(height: Space.x2),
        ],
      ),
    );
  }
}

Future<bool> confirmFullPermission(BuildContext context) =>
    confirmDialog(context, title: '改成完全权限？', message: '改成完全权限后，Agent 删除文件、执行命令都不再问你。命令在运行环境里什么都能做，请只在你信得过这次任务时使用。随时可以改回来。', confirmLabel: '改成完全权限', danger: true);

// ── 预设 ─────────────────────────────────────────────
class PresetPickerSheet extends StatelessWidget {
  const PresetPickerSheet({super.key, required this.presets, required this.current});
  final List<AgentPreset> presets;
  final String current;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.x4, 0, Space.x4, Space.x2),
            child: Text('这段对话用哪个预设', style: t.titleLarge),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final p in presets)
                  ListTile(
                    leading: Icon(p.id == current ? Icons.radio_button_checked : Icons.radio_button_off, color: p.id == current ? c.accent : c.textFaint),
                    title: Text(p.name),
                    subtitle: Text(p.tools == null ? '全部工具' : '${p.tools!.length} 个工具', style: t.bodySmall),
                    onTap: () => Navigator.pop(context, p.id),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.x4, Space.x2, Space.x4, Space.x3),
            child: Text('新建和修改预设在“设置 → 个性化”。', style: t.bodySmall),
          ),
        ],
      ),
    );
  }
}

// ── 发送方式 / 附件来源 ──────────────────────────────
class _SheetOption extends StatelessWidget {
  const _SheetOption({required this.icon, required this.title, required this.subtitle, required this.value, this.enabled = true});
  final IconData icon;
  final String title;
  final String subtitle;
  final Object value;
  final bool enabled;

  @override
  Widget build(BuildContext context) => ListTile(
    enabled: enabled,
    leading: Icon(icon),
    title: Text(title),
    subtitle: Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
    onTap: () => Navigator.pop(context, value),
  );
}

class SendModeSheet extends StatelessWidget {
  const SendModeSheet({super.key, this.hasImages = false});
  final bool hasImages;

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const _SheetOption(icon: Icons.schedule, title: '排队', subtitle: '等 AI 这一轮做完再发', value: SendMode.queue),
        _SheetOption(icon: Icons.subdirectory_arrow_right, title: '插话', subtitle: hasImages ? '带图片的消息不能插话' : 'AI 做下一步时就能看到，不打断它', value: SendMode.steer, enabled: !hasImages),
        const _SheetOption(icon: Icons.stop_circle_outlined, title: '中断并发送', subtitle: '让 AI 马上停下，改做这条', value: SendMode.interrupt),
        const SizedBox(height: Space.x2),
      ],
    ),
  );
}

/// 输入栏“＋”打开的面板：一行只做一件事。
/// 模型与权限在工具栏直接可点，这里只放计划模式和往消息里加东西。
/// 选中后返回：`plan` / `gallery` / `camera` / `file` / `ref`。
class PlusSheet extends StatelessWidget {
  const PlusSheet({super.key, required this.planMode});
  final bool planMode;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    Widget row(String value, IconData icon, String title, {String? state, String? subtitle, Color? stateColor}) => ListTile(
      key: ValueKey('plus-$value'),
      leading: Icon(icon, color: c.text),
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle, style: t.bodySmall),
      trailing: state == null
          ? null
          : ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 150),
              child: Text(
                state,
                style: t.bodyMedium?.copyWith(color: stateColor ?? c.textFaint),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
              ),
            ),
      onTap: () => Navigator.pop(context, value),
    );
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            row('plan', planMode ? Icons.map : Icons.map_outlined, '计划模式', state: planMode ? '已开' : '未开', stateColor: planMode ? c.accent : null),
            Divider(height: Space.x4, indent: Space.x4, endIndent: Space.x4, color: c.border),
            row('gallery', Icons.photo_library_outlined, '相册', subtitle: '从手机相册选图片'),
            row('camera', Icons.photo_camera_outlined, '拍照', subtitle: '现在拍一张'),
            row('file', Icons.image_outlined, '工作区里的图片', subtitle: '选工作区已有的图片文件'),
            row('ref', Icons.alternate_email, '引用项目文件', subtitle: '在消息里插入 @文件路径'),
            const SizedBox(height: Space.x2),
          ],
        ),
      ),
    );
  }
}

class PickedImage {
  PickedImage(this.name, this.bytes);
  final String name;
  final Uint8List bytes;
}

/// 测试用：换掉系统的相册 / 相机。
Future<List<PickedImage>> Function({required bool camera})? pickImagesOverride;

/// [single]：只要一张（相册里只能点一张；低代码给图片组件选图用）。
Future<List<PickedImage>> pickImages({required bool camera, bool single = false}) async {
  final override = pickImagesOverride;
  if (override != null) return override(camera: camera);
  final picker = ImagePicker();
  final files = camera || single
      ? [await picker.pickImage(source: camera ? ImageSource.camera : ImageSource.gallery, maxWidth: 2048, maxHeight: 2048, imageQuality: 85)].nonNulls.toList()
      : await picker.pickMultiImage(maxWidth: 2048, maxHeight: 2048, imageQuality: 85);
  return [for (final f in files) PickedImage(f.name, await f.readAsBytes())];
}

class ImageThumb extends StatelessWidget {
  const ImageThumb({super.key, required this.path, this.size = 56});
  final String path;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ClipRRect(
      borderRadius: BorderRadius.circular(Radii.sm),
      child: Image.file(
        File(path),
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => Container(
          width: size,
          height: size,
          color: c.surfaceMuted,
          child: Icon(Icons.image_outlined, size: 20, color: c.textFaint),
        ),
      ),
    );
  }
}

class AttachmentStrip extends StatelessWidget {
  const AttachmentStrip({super.key, required this.paths, required this.canSee, required this.onRemove});
  final List<String> paths;
  final bool canSee;
  final void Function(int index) onRemove;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.x4, 0, Space.x4, Space.x2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 56,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: paths.length,
              separatorBuilder: (_, _) => const SizedBox(width: Space.x2),
              itemBuilder: (context, i) => Stack(
                children: [
                  ImageThumb(path: paths[i]),
                  Positioned(
                    top: 0,
                    right: 0,
                    child: InkWell(
                      onTap: () => onRemove(i),
                      child: DecoratedBox(
                        decoration: BoxDecoration(color: c.text.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(Radii.sm)),
                        child: Icon(Icons.close, size: 16, color: c.surface, semanticLabel: '移除这张图片'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (!canSee)
            Padding(
              padding: const EdgeInsets.only(top: Space.x1),
              child: Text('当前模型不能看图：图片会作为文件路径告诉它。', style: t.bodySmall?.copyWith(color: c.warning)),
            ),
        ],
      ),
    );
  }
}

// ── 输入卡片上方的窄条 ───────────────────────────────
class StatusChipRow extends StatelessWidget {
  const StatusChipRow({super.key, required this.icon, required this.text, required this.action, required this.tone, required this.onTap});
  final IconData icon;
  final String text;
  final String action;
  final BannerTone tone;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final fg = tone == BannerTone.warning ? c.warning : c.accent;
    return Container(
      margin: const EdgeInsets.fromLTRB(Space.x4, 0, Space.x4, Space.x2),
      padding: const EdgeInsets.only(left: Space.x3),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(Radii.lg),
        border: Border.all(color: c.border),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: fg),
          const SizedBox(width: Space.x2),
          Expanded(
            child: Text(
              text,
              style: t.bodySmall?.copyWith(color: c.text),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: c.textMuted),
            onPressed: onTap,
            child: Text(action),
          ),
        ],
      ),
    );
  }
}

class SlashSuggestions extends StatelessWidget {
  const SlashSuggestions({super.key, required this.commands, required this.onPick});
  final List<(String, String)> commands;
  final void Function(String command) onPick;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(Space.x4, 0, Space.x4, Space.x2),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(Radii.lg),
        border: Border.all(color: c.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (cmd, hint) in commands)
            InkWell(
              onTap: () => onPick(cmd),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: Space.x3, vertical: Space.x2),
                child: Row(
                  children: [
                    SizedBox(
                      width: 104,
                      child: Text(
                        cmd,
                        style: TextStyle(fontFamily: kMonoFont, fontFamilyFallback: kMonoFallback, fontSize: FontSize.sm, color: c.accent),
                      ),
                    ),
                    Expanded(
                      child: Text(hint, style: t.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── 子代理 ───────────────────────────────────────────
/// 顶栏胶囊：派出了几个子代理。
class SubAgentCapsule extends StatelessWidget {
  const SubAgentCapsule({super.key, required this.total, required this.running, required this.onTap});
  final int total;
  final int running;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    return Center(
      child: Tooltip(
        message: '子代理',
        child: InkWell(
          borderRadius: BorderRadius.circular(Radii.xl),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: Space.x2, vertical: Space.x1),
            decoration: BoxDecoration(color: running > 0 ? c.accentSoft : c.surfaceMuted, borderRadius: BorderRadius.circular(Radii.xl)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.account_tree_outlined, size: 14, color: running > 0 ? c.accent : c.textMuted),
                const SizedBox(width: Space.x1),
                Text(
                  '$total',
                  style: t.bodySmall?.copyWith(color: running > 0 ? c.accent : c.textMuted, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 谱系列表：这段对话派出的子代理，按层级缩进。返回要进入的子对话 id。
class SubAgentSheet extends StatelessWidget {
  const SubAgentSheet({super.key, required this.session});
  final ProjectSession session;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final root = session.activeConversation;
    final subs = session.subAgents;
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.x4, 0, Space.x4, Space.x1),
            child: Text('子代理（${subs.length}）', style: t.titleLarge),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.x4, 0, Space.x4, Space.x2),
            child: Text('主智能体：${session.conversationTitle}', style: t.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final a in subs)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.only(left: Space.x4 + (a.depth - root.depth - 1).clamp(0, 3) * Space.x4, right: Space.x4),
                    leading: session.isRunning(a.id)
                        ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: c.accent))
                        : Icon(Icons.check_circle_outline, size: 18, color: c.textFaint),
                    title: Text(a.agentName, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text('${session.isRunning(a.id) ? '进行中' : '已结束'} · ${a.title}', style: t.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                    trailing: Icon(Icons.chevron_right, color: c.textFaint),
                    onTap: () => Navigator.pop(context, a.id),
                  ),
              ],
            ),
          ),
          const SizedBox(height: Space.x2),
        ],
      ),
    );
  }
}

/// 子代理的对话：只读，左上角返回上级。
class SubConversationScreen extends ConsumerStatefulWidget {
  const SubConversationScreen({super.key, required this.session, required this.conversationId});
  final ProjectSession session;
  final String conversationId;

  @override
  ConsumerState<SubConversationScreen> createState() => _SubConversationScreenState();
}

class _SubConversationScreenState extends ConsumerState<SubConversationScreen> {
  ConvRun? _run;

  @override
  void initState() {
    super.initState();
    widget.session.openRun(widget.conversationId).then((r) {
      if (mounted) setState(() => _run = r);
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final s = widget.session;
    // 这段子对话的条目、它在目录里的那一条：变了就重画
    ref.watch(chatRunProvider((s, widget.conversationId)));
    ref.watch(conversationsProvider(s));
    final conv = s.conversationById(widget.conversationId);
    final run = _run;
    final parent = s.conversationById(conv?.parentId);
    final parentName = parent == null ? '上级' : (parent.agentName.isEmpty ? '主智能体' : parent.agentName);
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: PageBar(backTooltip: '返回上级', titleText: conv?.agentName ?? '子代理', subtitle: '子代理 · 上级：$parentName · ${s.modelOf(conv ?? s.activeConversation)?.model.name ?? '未设置模型'}'),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: conv == null
                  ? const EmptyState(icon: Icons.account_tree_outlined, title: '这段子代理对话已经删除', message: '上级对话被删除时，它派出的子代理对话会一起删掉。')
                  : run == null
                  ? const Center(child: CircularProgressIndicator())
                  : ListView(
                      padding: EdgeInsets.fromLTRB(Space.x4, PageBar.insetOf(context) + Space.x2, Space.x4, Space.x4),
                      children: [
                        for (final row in chatRowsOf(ref, run.items, busy: run.busy))
                          ChatRowView(
                            row: row,
                            onOpenChild: (id) => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => SubConversationScreen(session: s, conversationId: id),
                              ),
                            ),
                          ),
                        if (run.busy)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: Space.x2),
                            child: Text('进行中…', style: t.bodySmall),
                          ),
                      ],
                    ),
            ),
            PendingArea(session: s),
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.x4, 0, Space.x4, Space.x3),
              child: Text(
                '子代理的对话只能看。要改方向，回到上级对话里说。',
                style: t.bodySmall?.copyWith(color: c.textFaint),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
