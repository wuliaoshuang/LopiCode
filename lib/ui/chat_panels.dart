// 设计约束（对话页的面板和窄条 · 390×844）
// - 每个底部面板只做一件事：选模型、选权限、选发送方式、选附件来源、看子代理。
// - 模型面板分三步往下排：渠道（横向一行标签）→ 模型（列表）→ 思考深度（一行分段），不把三样摊在一行。
// - 输入卡片上方的窄条一行一条：左图标 + 一句话 + 右边一个文字按钮。
// - 确认卡、提问卡是需要她动手的：用暖色 / 强调色底，按钮一行最多两个，多出来的另起一行。
import 'dart:io';
import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';
import 'package:lopicode/agent/agent_tools.dart';
import 'package:lopicode/agent/model_config.dart';
import 'package:lopicode/agent/presets.dart';
import 'package:lopicode/app_services.dart';
import 'package:lopicode/project_session.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/chat_screen.dart';
import 'package:lopicode/ui/chrome.dart';
import 'package:lopicode/ui/provider_icon.dart';
import 'package:lopicode/ui/widgets.dart';
import 'package:material_ui/material_ui.dart';

// ── 模型选择 ─────────────────────────────────────────
class ModelSelectionResult {
  ModelSelectionResult(this.selection);
  final ModelSelection selection;
}

/// 先选渠道，再选模型和思考深度。返回 [ModelSelectionResult]，或字符串 'manage'（去管理渠道）。
class ModelPickerSheet extends StatefulWidget {
  const ModelPickerSheet({super.key, this.current});
  final ModelSelection? current;

  @override
  State<ModelPickerSheet> createState() => _ModelPickerSheetState();
}

class _ModelPickerSheetState extends State<ModelPickerSheet> {
  String? _channelId;
  String? _modelId;
  String _level = 'off';

  @override
  void initState() {
    super.initState();
    _channelId = widget.current?.channelId;
    _modelId = widget.current?.modelId;
    _level = widget.current?.level ?? 'off';
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final channels = app.models.channels;
    final channel = app.models.channel(_channelId) ?? channels.firstOrNull;
    final model = channel?.model(_modelId);
    final levels = model != null && model.thinking ? model.levels : const <String>[];
    final level = levels.contains(_level) ? _level : 'off';
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Space.x4, 0, Space.x4, Space.x4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('选择模型', style: t.titleLarge),
            const SizedBox(height: Space.x3),
            if (channels.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: Space.x6),
                child: Text('还没有渠道。先去添加一个渠道，填好接口地址和 API Key。', style: t.bodyMedium?.copyWith(color: c.textMuted)),
              )
            else ...[
              const SectionLabel('渠道'),
              SizedBox(
                height: 40,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: channels.length,
                  separatorBuilder: (_, _) => const SizedBox(width: Space.x2),
                  itemBuilder: (context, i) => ChoiceChip(
                    avatar: ProviderIcon.forBaseUrl(channels[i].baseUrl, size: 24),
                    label: Text(channels[i].name),
                    selected: channels[i].id == channel?.id,
                    onSelected: (_) => setState(() {
                      _channelId = channels[i].id;
                      _modelId = null;
                    }),
                  ),
                ),
              ),
              const SizedBox(height: Space.x3),
              const SectionLabel('模型'),
              if (channel!.models.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: Space.x3),
                  child: Text('这个渠道还没勾选模型。', style: t.bodyMedium?.copyWith(color: c.textMuted)),
                )
              else
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final m in channel.models)
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(m.id == model?.id ? Icons.radio_button_checked : Icons.radio_button_off, color: m.id == model?.id ? c.accent : c.textFaint),
                          title: Text(m.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text('${m.contextLength ~/ 1000}K 上下文 · ${m.vision ? '能看图' : '只看文字'}${m.thinking ? ' · 可思考' : ''}', style: t.bodySmall),
                          onTap: () => setState(() => _modelId = m.id),
                        ),
                    ],
                  ),
                ),
              if (levels.isNotEmpty) ...[
                const SizedBox(height: Space.x2),
                const SectionLabel('思考深度'),
                SegmentedButton<String>(
                  showSelectedIcon: false,
                  segments: [
                    const ButtonSegment(value: 'off', label: Text('关')),
                    for (final l in levels) ButtonSegment(value: l, label: Text(thinkingLabel(l))),
                  ],
                  selected: {level},
                  onSelectionChanged: (v) => setState(() => _level = v.first),
                ),
              ],
              const SizedBox(height: Space.x4),
              FilledButton(
                onPressed: model == null ? null : () => Navigator.pop(context, ModelSelectionResult(ModelSelection(channel.id, model.id, level))),
                child: const Text('用这个模型'),
              ),
            ],
            TextButton(onPressed: () => Navigator.pop(context, 'manage'), child: const Text('管理渠道和模型')),
          ],
        ),
      ),
    );
  }
}

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

Future<bool> confirmFullPermission(BuildContext context) => confirmDialog(
  context,
  title: '改成完全权限？',
  message: '改成完全权限后，Agent 删除文件、执行命令都不再问你。命令在运行环境里什么都能做，请只在你信得过这次任务时使用。随时可以改回来。',
  confirmLabel: '改成完全权限',
  danger: true,
);

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
        _SheetOption(
          icon: Icons.subdirectory_arrow_right,
          title: '插话',
          subtitle: hasImages ? '带图片的消息不能插话' : 'AI 做下一步时就能看到，不打断它',
          value: SendMode.steer,
          enabled: !hasImages,
        ),
        const _SheetOption(icon: Icons.stop_circle_outlined, title: '中断并发送', subtitle: '让 AI 马上停下，改做这条', value: SendMode.interrupt),
        const SizedBox(height: Space.x2),
      ],
    ),
  );
}

/// 输入胶囊左边“＋”打开的面板：一行只做一件事。
/// 上半是这段对话的设置（模型、权限、计划模式），下半是往消息里加东西（图片、引用文件）。
/// 选中后返回：`model` / `permission` / `plan` / `gallery` / `camera` / `file` / `ref`。
class PlusSheet extends StatelessWidget {
  const PlusSheet({super.key, required this.modelName, required this.permission, required this.planMode});
  final String modelName;
  final PermissionLevel permission;
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
              child: Text(state, style: t.bodyMedium?.copyWith(color: stateColor ?? c.textFaint), maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.end),
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
            row('model', Icons.auto_awesome_outlined, '模型', state: modelName),
            row(
              'permission',
              switch (permission) {
                PermissionLevel.view => Icons.visibility_outlined,
                PermissionLevel.workspace => Icons.verified_user_outlined,
                PermissionLevel.full => Icons.bolt,
              },
              '权限',
              state: permission.label,
              stateColor: permission == PermissionLevel.full ? c.warning : null,
            ),
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

Future<List<PickedImage>> pickImages({required bool camera}) async {
  final override = pickImagesOverride;
  if (override != null) return override(camera: camera);
  final picker = ImagePicker();
  final files = camera
      ? [await picker.pickImage(source: ImageSource.camera, maxWidth: 2048, maxHeight: 2048, imageQuality: 85)].nonNulls.toList()
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
    final (bg, fg) = tone == BannerTone.warning ? (c.warningSoft, c.warning) : (c.accentSoft, c.accent);
    return Container(
      margin: const EdgeInsets.fromLTRB(Space.x4, 0, Space.x4, Space.x2),
      padding: const EdgeInsets.only(left: Space.x3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(Radii.lg)),
      child: Row(
        children: [
          Icon(icon, size: 16, color: fg),
          const SizedBox(width: Space.x2),
          Expanded(child: Text(text, style: t.bodySmall?.copyWith(color: c.text), maxLines: 2, overflow: TextOverflow.ellipsis)),
          TextButton(onPressed: onTap, child: Text(action)),
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
                      child: Text(cmd, style: TextStyle(fontFamily: kMonoFont, fontFamilyFallback: kMonoFallback, fontSize: FontSize.sm, color: c.accent)),
                    ),
                    Expanded(child: Text(hint, style: t.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 排队 / 插话的消息：每条一行，操作收进右边的菜单。
class QueueStrip extends StatelessWidget {
  const QueueStrip({super.key, required this.session});
  final ProjectSession session;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(Space.x4, 0, Space.x4, Space.x2),
      constraints: const BoxConstraints(maxHeight: 132),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(Radii.lg),
        border: Border.all(color: c.border),
      ),
      child: ListView(
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        children: [
          for (final q in session.queue)
            Padding(
              padding: const EdgeInsets.only(left: Space.x3),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: Space.x2, vertical: 2),
                    decoration: BoxDecoration(color: q.steer ? c.accentSoft : c.surfaceMuted, borderRadius: BorderRadius.circular(Radii.sm)),
                    child: Text(q.steer ? '插话' : '排队', style: t.bodySmall?.copyWith(color: q.steer ? c.accent : c.textMuted)),
                  ),
                  const SizedBox(width: Space.x2),
                  Expanded(
                    child: Text('${q.images.isEmpty ? '' : '[${q.images.length} 张图] '}${q.text}', style: t.bodySmall?.copyWith(color: c.text), maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                  PopupMenuButton<String>(
                    tooltip: '处理这条消息',
                    icon: Icon(Icons.more_horiz, size: 20, color: c.textMuted),
                    onSelected: (v) {
                      if (v == 'now') session.sendQueuedNow(q);
                      if (v == 'steer') session.steerQueued(q);
                      if (v == 'withdraw') session.withdrawQueued(q);
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(value: 'now', child: Text('立即发送')),
                      if (!q.steer && q.images.isEmpty) const PopupMenuItem(value: 'steer', child: Text('改为插话')),
                      const PopupMenuItem(value: 'withdraw', child: Text('撤回')),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ── 确认卡 / 提问卡 ──────────────────────────────────
/// 钉在输入卡片上方：最前面的一张确认卡，或一张提问卡。
class PendingArea extends StatelessWidget {
  const PendingArea({super.key, required this.session});
  final ProjectSession session;

  @override
  Widget build(BuildContext context) {
    final approval = session.pendingApproval;
    if (approval != null) return ApprovalCard(pending: approval, onAnswer: session.resolveApproval);
    final question = session.pendingQuestion;
    if (question != null) return QuestionCard(key: ObjectKey(question), question: question, onAnswer: session.answerQuestion);
    return const SizedBox.shrink();
  }
}

class ApprovalCard extends StatelessWidget {
  const ApprovalCard({super.key, required this.pending, required this.onAnswer});
  final PendingApproval pending;
  final void Function(bool allow, {bool always}) onAnswer;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final req = pending.request;
    final isSchedule = req.tool == 'schedule_task';
    final who = pending.agentName.isEmpty ? 'Agent' : '子代理“${pending.agentName}”';
    final icon = switch (req.tool) {
      'delete_file' => Icons.delete_outline,
      'schedule_task' => Icons.event_repeat,
      _ => Icons.terminal,
    };
    return Container(
      margin: const EdgeInsets.fromLTRB(Space.x4, 0, Space.x4, Space.x2),
      padding: const EdgeInsets.all(Space.x4),
      decoration: BoxDecoration(
        color: c.warningSoft,
        borderRadius: BorderRadius.circular(Radii.xl),
        border: Border.all(color: c.warning.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: c.warning),
              const SizedBox(width: Space.x2),
              Expanded(
                child: Text(
                  isSchedule ? '$who 想${req.title}，请核对后再确认' : '$who 想${req.title}，要允许吗？',
                  style: t.titleSmall?.copyWith(color: c.warning),
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.x2),
          Container(
            constraints: BoxConstraints(maxHeight: isSchedule ? 220 : 96),
            padding: const EdgeInsets.all(Space.x2),
            decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(Radii.sm)),
            child: SingleChildScrollView(
              child: SelectableText(
                req.detail,
                style: TextStyle(fontFamily: kMonoFont, fontFamilyFallback: kMonoFallback, fontSize: FontSize.sm, height: 1.5, color: c.text),
              ),
            ),
          ),
          const SizedBox(height: Space.x3),
          Row(
            children: [
              Expanded(child: OutlinedButton(onPressed: () => onAnswer(false), child: const Text('拒绝'))),
              const SizedBox(width: Space.x2),
              Expanded(child: FilledButton(onPressed: () => onAnswer(true), child: Text(isSchedule ? '确认保存' : '允许这一次'))),
            ],
          ),
          if (req.allowAlways)
            TextButton(onPressed: () => onAnswer(true, always: true), child: const Text('本对话都允许')),
        ],
      ),
    );
  }
}

class QuestionCard extends StatefulWidget {
  const QuestionCard({super.key, required this.question, required this.onAnswer});
  final PendingQuestion question;
  final void Function(String answer) onAnswer;

  @override
  State<QuestionCard> createState() => _QuestionCardState();
}

class _QuestionCardState extends State<QuestionCard> {
  final _other = TextEditingController();
  bool _typing = false;

  @override
  void initState() {
    super.initState();
    _typing = widget.question.options.isEmpty;
  }

  @override
  void dispose() {
    _other.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final q = widget.question;
    return Container(
      margin: const EdgeInsets.fromLTRB(Space.x4, 0, Space.x4, Space.x2),
      padding: const EdgeInsets.all(Space.x4),
      constraints: const BoxConstraints(maxHeight: 380),
      decoration: BoxDecoration(
        color: c.accentSoft,
        borderRadius: BorderRadius.circular(Radii.xl),
        border: Border.all(color: c.accent.withValues(alpha: 0.4)),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(Icons.help_outline, size: 18, color: c.accent),
                const SizedBox(width: Space.x2),
                Expanded(child: Text(q.agentName.isEmpty ? 'Agent 想问你' : '子代理“${q.agentName}”想问你', style: t.titleSmall?.copyWith(color: c.accent))),
              ],
            ),
            const SizedBox(height: Space.x2),
            Text(q.question, style: t.bodyLarge),
            const SizedBox(height: Space.x3),
            for (final o in q.options)
              Padding(
                padding: const EdgeInsets.only(bottom: Space.x2),
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(backgroundColor: c.surface, alignment: Alignment.centerLeft),
                  onPressed: () => widget.onAnswer(o),
                  child: Text(o),
                ),
              ),
            if (!_typing)
              TextButton(onPressed: () => setState(() => _typing = true), child: const Text('其他回答'))
            else ...[
              TextField(
                controller: _other,
                autofocus: q.options.isNotEmpty,
                minLines: 1,
                maxLines: 3,
                decoration: const InputDecoration(hintText: '写下你的回答'),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: Space.x2),
              FilledButton(onPressed: _other.text.trim().isEmpty ? null : () => widget.onAnswer(_other.text), child: const Text('回答')),
            ],
          ],
        ),
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
                Text('$total', style: t.bodySmall?.copyWith(color: running > 0 ? c.accent : c.textMuted, fontWeight: FontWeight.w600)),
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
class SubConversationScreen extends StatefulWidget {
  const SubConversationScreen({super.key, required this.session, required this.conversationId});
  final ProjectSession session;
  final String conversationId;

  @override
  State<SubConversationScreen> createState() => _SubConversationScreenState();
}

class _SubConversationScreenState extends State<SubConversationScreen> {
  ConvRun? _run;

  @override
  void initState() {
    super.initState();
    widget.session.addListener(_changed);
    widget.session.openRun(widget.conversationId).then((r) {
      if (mounted) setState(() => _run = r);
    });
  }

  @override
  void dispose() {
    widget.session.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final s = widget.session;
    final conv = s.conversationById(widget.conversationId);
    final run = _run;
    final parent = s.conversationById(conv?.parentId);
    final parentName = parent == null ? '上级' : (parent.agentName.isEmpty ? '主智能体' : parent.agentName);
    return Scaffold(
      appBar: PageBar(
        backTooltip: '返回上级',
        titleText: conv?.agentName ?? '子代理',
        subtitle: '子代理 · 上级：$parentName · ${s.modelOf(conv ?? s.activeConversation)?.model.name ?? '未设置模型'}',
      ),
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
                      padding: const EdgeInsets.fromLTRB(Space.x4, Space.x2, Space.x4, Space.x4),
                      children: [
                        for (final item in run.items)
                          ChatItemView(
                            item: item,
                            onOpenChild: (id) => Navigator.of(context).push(
                              MaterialPageRoute<void>(builder: (_) => SubConversationScreen(session: s, conversationId: id)),
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
              child: Text('子代理的对话只能看。要改方向，回到上级对话里说。', style: t.bodySmall?.copyWith(color: c.textFaint), textAlign: TextAlign.center),
            ),
          ],
        ),
      ),
    );
  }
}
