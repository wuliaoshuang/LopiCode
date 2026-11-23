// 设计约束（Agent 对话 · 390×844）— 布局照霜霜给的参考图
// - 顶栏：左汉堡按钮；两行标题（对话名 + “工作区 / 模型名”）；右边子代理胶囊（有才出现）、“新对话”和 ⋮ 菜单。没有底部导航。
// - 空对话：顶部正中一个小的文字入口“项目规则”，下面留白；几条开场建议贴着输入卡片上方，弱化显示。
// - 底部是一张大圆角输入卡片：上面是输入区，下面一行控件都在卡片里——左：模型、权限、计划模式；右：＋（附件 / 引用文件）、圆形发送 / 停止。
// - 输入卡片上方按需叠几条“一行只做一件事”的窄条：自动允许中、计划模式、排队的消息、附件缩略图、/ 指令提示。
// - 对话是主角：用户消息靠右的浅强调色气泡，Agent 回复是不带气泡的正文。
// - 工具调用是次要信息：一行小卡，点开才看参数和输出。
// - 需要她点头的操作（确认卡）和 AI 的提问（选择卡）钉在输入卡片上方。
// - 主操作只有一个：发送。AI 生成时长按发送键选“排队 / 插话 / 中断并发送”。
import 'dart:convert';

import 'package:lopicode/agent/agent_tools.dart';
import 'package:lopicode/app_services.dart';
import 'package:lopicode/core/project_store.dart';
import 'package:lopicode/project_session.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/chat_panels.dart';
import 'package:lopicode/ui/settings_ai.dart';
import 'package:lopicode/ui/shell.dart';
import 'package:lopicode/ui/team_screen.dart';
import 'package:lopicode/ui/widgets.dart';
import 'package:material_ui/material_ui.dart';

/// `/` 指令。
const List<(String, String)> kSlashCommands = [
  ('/new', '开一段新对话'),
  ('/model', '换模型和思考深度'),
  ('/plan', '开 / 关计划模式'),
  ('/compact', '把前面的对话压缩成摘要'),
  ('/export', '把对话导出成文件'),
  ('/permission', '改这段对话的权限'),
];

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, required this.session});
  final ProjectSession session;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _input = TextEditingController();
  final _focus = FocusNode();
  final _scroll = ScrollController();
  int _lastCount = 0;

  /// 还没发出去的图片附件（`{path, mime}`，path 相对工作区）。
  final List<Map<String, dynamic>> _attachments = [];

  ProjectSession get s => widget.session;

  @override
  void initState() {
    super.initState();
    s.addListener(_onSession);
    _input.addListener(_onInput);
    s.loadChat();
  }

  @override
  void dispose() {
    s.removeListener(_onSession);
    _input.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onInput() {
    if (mounted) setState(() {}); // 发送按钮、/ 指令提示跟着输入变
  }

  void _onSession() {
    if (!mounted) return;
    final draft = s.restoredDraft;
    if (draft != null && _input.text.isEmpty) {
      _input.text = draft;
      s.restoredDraft = null;
    }
    setState(() {});
    // 有新内容时滚到底（用户自己往上翻时不打扰）。
    final grew = s.chat.length != _lastCount;
    _lastCount = s.chat.length;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final pos = _scroll.position;
      if (grew || pos.maxScrollExtent - pos.pixels < 120) _scroll.jumpTo(pos.maxScrollExtent);
    });
  }

  bool get _canSend => _input.text.trim().isNotEmpty || _attachments.isNotEmpty;

  void _send([String? preset, SendMode mode = SendMode.queue]) {
    final text = (preset ?? _input.text).trim();
    if (text.isEmpty && _attachments.isEmpty) return;
    if (preset == null && _attachments.isEmpty && _runSlash(text)) {
      _input.clear();
      return;
    }
    final images = [..._attachments];
    _input.clear();
    setState(_attachments.clear);
    s.sendToAgent(text, images: images, mode: mode);
  }

  /// 是 `/` 指令就执行并返回 true。
  bool _runSlash(String text) {
    if (!text.startsWith('/')) return false;
    final cmd = text.split(RegExp(r'\s')).first.toLowerCase();
    switch (cmd) {
      case '/new':
        if (s.agentBusy) {
          showSnack(context, 'AI 正在生成，停下后才能开新对话');
        } else {
          s.newConversation();
        }
      case '/model':
        _pickModel();
      case '/plan':
        _togglePlan();
      case '/compact':
        _compact();
      case '/export':
        _export();
      case '/permission':
        _pickPermission();
      default:
        return false;
    }
    return true;
  }

  Future<void> _togglePlan() async {
    await s.setPlanMode(!s.planMode);
    if (mounted) showSnack(context, s.planMode ? '计划模式已开：Agent 只出计划，不改文件、不跑命令' : '计划模式已关');
  }

  Future<void> _compact() async {
    final msg = await s.compactConversation();
    if (mounted && msg != '已压缩') showSnack(context, msg);
  }

  Future<void> _export() async {
    final path = await s.exportConversation();
    if (mounted) showSnack(context, path == null ? '对话还是空的，没有可导出的内容' : '已导出到工作区：$path');
  }

  Future<void> _pickSendMode() async {
    if (!_canSend) return;
    final mode = await showModalBottomSheet<SendMode>(context: context, builder: (_) => SendModeSheet(hasImages: _attachments.isNotEmpty));
    if (mode != null) _send(null, mode);
  }

  Future<void> _editRules() async {
    final text = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _RulesSheet(initial: s.projectRules),
    );
    if (text != null) await s.setProjectRules(text);
  }

  Future<void> _pickModel() async {
    final picked = await showModalBottomSheet<Object>(
      context: context,
      isScrollControlled: true,
      builder: (_) => ModelPickerSheet(current: s.currentModel?.selection),
    );
    if (!mounted) return;
    if (picked is ModelSelectionResult) await s.setModel(picked.selection);
    if (picked == 'manage' && mounted) {
      await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const ChannelsScreen()));
      if (mounted) setState(() {});
    }
  }

  Future<void> _pickPermission() async {
    final level = await showModalBottomSheet<PermissionLevel>(context: context, builder: (_) => PermissionSheet(current: s.permission));
    if (level == null || !mounted || level == s.permission) return;
    if (level == PermissionLevel.full && !await confirmFullPermission(context)) return;
    await s.setPermission(level);
  }

  Future<void> _pickPreset() async {
    final app = AppScope.of(context);
    final id = await showModalBottomSheet<String>(
      context: context,
      builder: (_) => PresetPickerSheet(presets: app.presets.all, current: s.preset.id),
    );
    if (id != null) await s.setPreset(id);
  }

  void _insertReference(String path) {
    final sel = _input.selection;
    final at = sel.isValid ? sel.start : _input.text.length;
    final before = _input.text.substring(0, at);
    final insert = '${before.isEmpty || before.endsWith(' ') || before.endsWith('\n') ? '' : ' '}@$path ';
    _input.value = TextEditingValue(
      text: before + insert + _input.text.substring(at),
      selection: TextSelection.collapsed(offset: at + insert.length),
    );
    _focus.requestFocus();
  }

  Future<void> _attach() async {
    final choice = await showModalBottomSheet<String>(context: context, builder: (_) => const AttachSheet());
    if (choice == null || !mounted) return;
    if (choice == 'ref') {
      final path = await showModalBottomSheet<String>(context: context, builder: (_) => _FilePickerSheet(session: s));
      if (path != null) _insertReference(path);
      return;
    }
    final room = ProjectSession.maxAttachments - _attachments.length;
    if (room <= 0) {
      showSnack(context, '一条消息最多带 ${ProjectSession.maxAttachments} 张图片');
      return;
    }
    try {
      final added = <Map<String, dynamic>>[];
      if (choice == 'file') {
        final path = await showModalBottomSheet<String>(context: context, builder: (_) => _FilePickerSheet(session: s, imagesOnly: true));
        if (path != null) added.add(s.attachWorkspaceFile(path));
      } else {
        final picked = await pickImages(camera: choice == 'camera');
        for (final img in picked.take(room)) {
          added.add(await s.saveAttachment(img.bytes, img.name));
        }
        if (picked.length > room && mounted) showSnack(context, '最多 ${ProjectSession.maxAttachments} 张，多出来的没加');
      }
      if (mounted && added.isNotEmpty) setState(() => _attachments.addAll(added));
    } on FormatException catch (e) {
      if (mounted) showSnack(context, e.message);
    } on Exception catch (e) {
      if (mounted) showSnack(context, '没选成：$e');
    }
  }

  Future<void> _deleteConversation() async {
    final kids = s.subAgents.length;
    final ok = await confirmDialog(
      context,
      title: '删除这段对话？',
      message: '对话记录会被删除${kids > 0 ? '，它派出的 $kids 个子代理对话也一起删' : ''}。工作区里的文件不受影响。',
      confirmLabel: '删除',
      danger: true,
    );
    if (ok) await s.deleteConversation();
  }

  Future<void> _openSubAgents() async {
    final id = await showModalBottomSheet<String>(context: context, builder: (_) => SubAgentSheet(session: s));
    if (id != null && mounted) {
      await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => SubConversationScreen(session: s, conversationId: id)));
    }
  }

  void _openChild(String id) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => SubConversationScreen(session: s, conversationId: id)));

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final c = context.colors;
    final pending = s.pendingApproval;
    final question = s.pendingQuestion;
    final model = s.currentModel;
    final subs = s.subAgents;
    final running = subs.where((a) => s.isRunning(a.id)).length;
    final text = _input.text;
    final slash = text.startsWith('/') && !text.contains(RegExp(r'\s'))
        ? kSlashCommands.where((k) => k.$1.startsWith(text.toLowerCase())).toList()
        : const <(String, String)>[];
    return Scaffold(
      appBar: ShellAppBar(
        title: s.conversationTitle,
        subtitle: '${s.project.name} / ${model == null ? '未设置模型' : model.model.name}',
        actions: [
          if (subs.isNotEmpty) SubAgentCapsule(total: subs.length, running: running, onTap: _openSubAgents),
          IconButton(
            tooltip: '新对话',
            icon: Icon(Icons.add_comment_outlined, color: c.text),
            onPressed: s.agentBusy ? null : s.newConversation,
          ),
          PopupMenuButton<String>(
            tooltip: '更多',
            icon: Icon(Icons.more_vert, color: c.text),
            onSelected: (v) {
              if (v == 'rules') _editRules();
              if (v == 'preset') _pickPreset();
              if (v == 'team') {
                Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => TeamScreen(session: s)));
              }
              if (v == 'compact') _compact();
              if (v == 'export') _export();
              if (v == 'delete') _deleteConversation();
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'rules', child: Text('项目规则')),
              PopupMenuItem(value: 'preset', child: Text('Agent 预设：${s.preset.name}')),
              if (s.teamEnabled) const PopupMenuItem(value: 'team', child: Text('智能体团队')),
              PopupMenuItem(value: 'compact', enabled: !s.agentBusy && s.chat.isNotEmpty, child: const Text('压缩对话')),
              PopupMenuItem(value: 'export', enabled: s.chat.isNotEmpty, child: const Text('导出对话')),
              PopupMenuItem(
                value: 'delete',
                enabled: !s.agentBusy && s.chat.isNotEmpty,
                child: Text('删除这段对话', style: TextStyle(color: !s.agentBusy && s.chat.isNotEmpty ? c.danger : c.textFaint)),
              ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: s.chat.isEmpty
                  ? _EmptyChat(
                      configured: app.agentConfigured,
                      hasRules: s.projectRules.isNotEmpty,
                      onRules: _editRules,
                      onPick: _send,
                    )
                  : ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.fromLTRB(Space.x4, Space.x2, Space.x4, Space.x4),
                      itemCount: s.chat.length + (s.agentBusy && pending == null && question == null ? 1 : 0),
                      itemBuilder: (context, i) {
                        if (i >= s.chat.length) return const _Working();
                        return ChatItemView(item: s.chat[i], onOpenChild: _openChild);
                      },
                    ),
            ),
            PendingArea(session: s),
            if (s.queue.isNotEmpty) QueueStrip(session: s),
            if (s.autoAllowActive && s.permission != PermissionLevel.full)
              StatusChipRow(
                key: const ValueKey('auto-allow-chip'),
                icon: Icons.bolt,
                text: '自动允许中：本对话的命令和删除不再逐次问你',
                action: '关闭',
                tone: BannerTone.warning,
                onTap: s.clearAutoAllow,
              ),
            if (s.planMode)
              StatusChipRow(
                key: const ValueKey('plan-chip'),
                icon: Icons.map_outlined,
                text: '计划模式：只出计划，不改文件、不跑命令',
                action: '退出',
                tone: BannerTone.info,
                onTap: _togglePlan,
              ),
            if (_attachments.isNotEmpty)
              AttachmentStrip(
                paths: [for (final a in _attachments) '${s.project.dir}/${a['path']}'],
                canSee: model?.model.vision ?? false,
                onRemove: (i) => setState(() => _attachments.removeAt(i)),
              ),
            if (slash.isNotEmpty)
              SlashSuggestions(
                commands: slash,
                onPick: (cmd) {
                  _input.clear();
                  _runSlash(cmd);
                },
              ),
            _InputCard(
              controller: _input,
              focusNode: _focus,
              busy: s.agentBusy,
              canSend: _canSend,
              permission: s.permission,
              planMode: s.planMode,
              onModel: _pickModel,
              onPermission: _pickPermission,
              onPlan: _togglePlan,
              onAttach: _attach,
              onSend: _send,
              onLongSend: _pickSendMode,
              onStop: s.stopAgent,
            ),
          ],
        ),
      ),
    );
  }
}

/// 底部的大圆角输入卡片：上面输入，下面一行控件。
class _InputCard extends StatelessWidget {
  const _InputCard({
    required this.controller,
    required this.focusNode,
    required this.busy,
    required this.canSend,
    required this.permission,
    required this.planMode,
    required this.onModel,
    required this.onPermission,
    required this.onPlan,
    required this.onAttach,
    required this.onSend,
    required this.onLongSend,
    required this.onStop,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool busy;
  final bool canSend;
  final PermissionLevel permission;
  final bool planMode;
  final VoidCallback onModel;
  final VoidCallback onPermission;
  final VoidCallback onPlan;
  final VoidCallback onAttach;
  final VoidCallback onSend;
  final VoidCallback onLongSend;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    const none = OutlineInputBorder(borderSide: BorderSide.none);
    final (IconData permIcon, Color permColor) = switch (permission) {
      PermissionLevel.view => (Icons.visibility_outlined, c.textMuted),
      PermissionLevel.workspace => (Icons.verified_user_outlined, c.accent),
      PermissionLevel.full => (Icons.bolt, c.warning),
    };
    return Container(
      margin: const EdgeInsets.fromLTRB(Space.x2, 0, Space.x2, Space.x2),
      decoration: BoxDecoration(
        color: c.bg,
        borderRadius: BorderRadius.circular(Radii.xl),
        border: Border.all(color: c.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: controller,
            focusNode: focusNode,
            minLines: 1,
            maxLines: 6,
            style: t.bodyLarge,
            textInputAction: TextInputAction.newline,
            decoration: InputDecoration(
              hintText: busy ? '可以接着说：点发送排队，长按选插话或中断' : '告诉 Agent 你想做什么，输入 / 看指令',
              hintStyle: t.bodyLarge?.copyWith(color: c.textFaint),
              filled: false,
              isDense: false,
              contentPadding: const EdgeInsets.fromLTRB(Space.x6, Space.x4, Space.x6, Space.x2),
              border: none,
              enabledBorder: none,
              focusedBorder: none,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.x3, 0, Space.x3, Space.x2),
            child: Row(
              children: [
                IconButton(
                  tooltip: '模型',
                  onPressed: onModel,
                  icon: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(color: c.accentSoft, shape: BoxShape.circle),
                    child: Icon(Icons.auto_awesome, size: 16, color: c.accent),
                  ),
                ),
                IconButton(tooltip: '权限：${permission.label}', onPressed: onPermission, icon: Icon(permIcon, color: permColor)),
                IconButton(
                  tooltip: planMode ? '计划模式已开' : '计划模式',
                  onPressed: onPlan,
                  icon: Icon(planMode ? Icons.map : Icons.map_outlined, color: planMode ? c.accent : c.textMuted),
                ),
                const Spacer(),
                IconButton(tooltip: '添加图片或引用文件', onPressed: onAttach, icon: Icon(Icons.add, color: c.text)),
                const SizedBox(width: Space.x1),
                if (busy && !canSend)
                  _RoundButton(tooltip: '停止', icon: Icons.stop_rounded, bg: c.danger, fg: c.surface, onPressed: onStop)
                else
                  GestureDetector(
                    key: const ValueKey('send-button'),
                    onLongPress: busy && canSend ? onLongSend : null,
                    child: _RoundButton(
                      tooltip: busy ? '排队发送（长按选方式）' : '发送',
                      icon: Icons.arrow_upward_rounded,
                      bg: canSend ? c.accentFill : c.surfaceMuted,
                      fg: canSend ? c.onAccent : c.textFaint,
                      onPressed: canSend ? onSend : null,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.tooltip, required this.icon, required this.bg, required this.fg, required this.onPressed});
  final String tooltip;
  final IconData icon;
  final Color bg;
  final Color fg;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tooltip,
    onPressed: onPressed,
    style: IconButton.styleFrom(
      backgroundColor: bg,
      disabledBackgroundColor: bg,
      foregroundColor: fg,
      disabledForegroundColor: fg,
      minimumSize: const Size(36, 36),
      fixedSize: const Size(36, 36),
      padding: EdgeInsets.zero,
      shape: const CircleBorder(),
    ),
    icon: Icon(icon, size: 20),
  );
}

/// 空对话：顶部正中一个小入口，底部几条弱化的开场建议。
class _EmptyChat extends StatelessWidget {
  const _EmptyChat({required this.configured, required this.hasRules, required this.onRules, required this.onPick});
  final bool configured;
  final bool hasRules;
  final VoidCallback onRules;
  final void Function(String) onPick;

  static const _ideas = [
    '看一下项目里有哪些文件，告诉我它是做什么的',
    '做一个个人主页：头像、简介、三个作品卡片',
    '给页面加一个深色模式切换按钮',
  ];

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    return Column(
      children: [
        const SizedBox(height: Space.x6),
        TextButton.icon(
          onPressed: onRules,
          icon: Icon(Icons.tune, size: 18, color: c.accent),
          label: Text(hasRules ? '项目规则 · 已设置' : '项目规则', style: t.bodyMedium?.copyWith(color: c.accent)),
        ),
        Expanded(child: configured ? const SizedBox.shrink() : const _NeedsSetup()),
        if (configured)
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.x4, 0, Space.x4, Space.x3),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final idea in _ideas)
                  InkWell(
                    borderRadius: BorderRadius.circular(Radii.md),
                    onTap: () => onPick(idea),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: Space.x2, vertical: Space.x2),
                      child: Row(
                        children: [
                          Icon(Icons.north_east, size: 14, color: c.textFaint),
                          const SizedBox(width: Space.x2),
                          Expanded(child: Text(idea, style: t.bodyMedium?.copyWith(color: c.textMuted))),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _RulesSheet extends StatefulWidget {
  const _RulesSheet({required this.initial});
  final String initial;

  @override
  State<_RulesSheet> createState() => _RulesSheetState();
}

class _RulesSheetState extends State<_RulesSheet> {
  late final _text = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(Space.x4, 0, Space.x4, MediaQuery.viewInsetsOf(context).bottom + Space.x4),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('项目规则', style: t.titleLarge),
            const SizedBox(height: Space.x1),
            Text('写给 Agent 的长期要求，这个项目的每段对话都会带上。', style: t.bodySmall),
            const SizedBox(height: Space.x4),
            TextField(
              controller: _text,
              minLines: 5,
              maxLines: 10,
              decoration: const InputDecoration(hintText: '比如：页面用中文；颜色用浅色系；改完告诉我改了哪些文件。'),
            ),
            const SizedBox(height: Space.x4),
            FilledButton(onPressed: () => Navigator.pop(context, _text.text), child: const Text('保存')),
          ],
        ),
      ),
    );
  }
}

class _FilePickerSheet extends StatelessWidget {
  const _FilePickerSheet({required this.session, this.imagesOnly = false});
  final ProjectSession session;

  /// 只列图片（当附件用）。
  final bool imagesOnly;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    return SafeArea(
      top: false,
      child: FutureBuilder<List<String>>(
        future: listProjectFiles(session.guard),
        builder: (context, snap) {
          final files = (snap.data ?? const <String>[]).where((f) => !f.endsWith('/') && (!imagesOnly || ProjectSession.imageMimeOf(f) != null)).toList();
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(Space.x4, 0, Space.x4, Space.x2),
                child: Text(imagesOnly ? '选工作区里的图片' : '引用项目文件', style: t.titleLarge),
              ),
              if (snap.connectionState != ConnectionState.done)
                const Padding(padding: EdgeInsets.all(Space.x6), child: Center(child: CircularProgressIndicator()))
              else if (files.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(Space.x6),
                  child: Text(imagesOnly ? '工作区里还没有图片。' : '项目里还没有文件。', style: t.bodyMedium?.copyWith(color: c.textMuted), textAlign: TextAlign.center),
                )
              else
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: files.length,
                    itemBuilder: (context, i) => ListTile(
                      dense: true,
                      leading: const Icon(Icons.insert_drive_file_outlined, size: 20),
                      title: Text(files[i], style: t.bodyMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                      onTap: () => Navigator.pop(context, files[i]),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _NeedsSetup extends StatelessWidget {
  const _NeedsSetup();

  @override
  Widget build(BuildContext context) => EmptyState(
    icon: Icons.key_outlined,
    title: '先连上一个模型',
    message: '添加一个渠道（接口地址和 API Key），\n再勾上要用的模型，Agent 才能开始干活。',
    action: FilledButton(
      onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const ChannelsScreen())),
      child: const Text('去设置'),
    ),
  );
}

class _Working extends StatelessWidget {
  const _Working();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: Space.x2),
    child: Row(
      children: [
        SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: context.colors.textFaint)),
        const SizedBox(width: Space.x2),
        Text('处理中…', style: Theme.of(context).textTheme.bodySmall),
      ],
    ),
  );
}

class ChatItemView extends StatelessWidget {
  const ChatItemView({super.key, required this.item, this.onOpenChild});
  final ChatItem item;

  /// 点“派子代理”那张卡时进子对话。
  final void Function(String conversationId)? onOpenChild;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    switch (item) {
      case UserItem(:final text, :final images):
        return Align(
          alignment: Alignment.centerRight,
          child: Container(
            margin: const EdgeInsets.only(top: Space.x4, bottom: Space.x2, left: Space.x12),
            padding: const EdgeInsets.symmetric(horizontal: Space.x3, vertical: Space.x2),
            decoration: BoxDecoration(color: c.accentSoft, borderRadius: BorderRadius.circular(Radii.md)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (images.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: Space.x2),
                    child: Wrap(
                      spacing: Space.x1,
                      runSpacing: Space.x1,
                      alignment: WrapAlignment.end,
                      children: [for (final path in images) ImageThumb(path: path, size: 64)],
                    ),
                  ),
                SelectableText(text, style: t.bodyLarge),
              ],
            ),
          ),
        );
      case AssistantItem(:final text, :final streaming):
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: Space.x2),
          child: SelectableText(streaming ? '$text▍' : text, style: t.bodyLarge),
        );
      case final ToolItem tool:
        return _ToolCard(tool: tool, onOpenChild: onOpenChild);
      case NoticeItem(:final text, :final isError):
        return InfoBanner(
          text,
          tone: isError ? BannerTone.danger : BannerTone.info,
          margin: const EdgeInsets.symmetric(vertical: Space.x2),
        );
    }
  }
}

/// 工具名 → 人话。
String describeTool(String name, String rawArgs) {
  Map<String, dynamic> args = const {};
  try {
    final decoded = jsonDecode(rawArgs);
    if (decoded is Map<String, dynamic>) args = decoded;
  } on FormatException {
    // 参数不是合法 JSON：只显示动作名
  }
  String a(String key) => '${args[key] ?? ''}';
  return switch (name) {
    'list_files' => '查看文件列表${a('path').isEmpty ? '' : ' ${a('path')}'}',
    'read_file' => '读取 ${a('path')}',
    'write_file' => '写入 ${a('path')}',
    'delete_file' => '删除 ${a('path')}',
    'run_command' => '执行 ${a('command')}',
    'lowcode_get_page' => '读取低代码页面',
    'lowcode_update_page' => '更新低代码页面',
    'ask_user' => '向你提问：${a('question')}',
    'web_search' => '联网搜索 ${a('query')}',
    'read_skill' => '读技能 ${a('name')}',
    'spawn_agent' => '派子代理${a('name').isEmpty ? '' : '“${a('name')}”'}：${a('task')}',
    'team_board' => '查看任务板',
    'team_task' => '更新任务板${a('title').isEmpty ? '' : '：${a('title')}'}',
    'team_message' => '团队留言${a('to').isEmpty ? '' : '给 ${a('to')}'}',
    'list_scheduled_tasks' => '查看自动化任务',
    'schedule_task' => '安排自动化任务：${a('title')}',
    _ => name,
  };
}

class _ToolCard extends StatefulWidget {
  const _ToolCard({required this.tool, this.onOpenChild});
  final ToolItem tool;
  final void Function(String conversationId)? onOpenChild;

  @override
  State<_ToolCard> createState() => _ToolCardState();
}

class _ToolCardState extends State<_ToolCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final tool = widget.tool;
    final (IconData icon, Color color) = tool.running
        ? (Icons.more_horiz, c.textFaint)
        : tool.denied
        ? (Icons.block, c.warning)
        : tool.ok
        ? (Icons.check_circle_outline, c.accent)
        : (Icons.error_outline, c.danger);
    final mono = TextStyle(fontFamily: kMonoFont, fontFamilyFallback: kMonoFallback, fontSize: FontSize.xs, height: 1.5, color: c.textMuted);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: Space.x1),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(Radii.md),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.x3, vertical: Space.x2),
              child: Row(
                children: [
                  Icon(icon, size: 16, color: color),
                  const SizedBox(width: Space.x2),
                  Expanded(
                    child: Text(
                      describeTool(tool.name, tool.arguments),
                      style: t.bodySmall?.copyWith(color: c.text),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (tool.childConversationId != null && widget.onOpenChild != null)
                    InkWell(
                      onTap: () => widget.onOpenChild!(tool.childConversationId!),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: Space.x2),
                        child: Text('查看', style: t.bodySmall?.copyWith(color: c.accent)),
                      ),
                    ),
                  if (tool.denied) Text('已拒绝', style: t.bodySmall?.copyWith(color: c.warning)),
                  if (!tool.running && !tool.ok && !tool.denied) Text('失败', style: t.bodySmall?.copyWith(color: c.danger)),
                  Icon(_expanded ? Icons.expand_less : Icons.expand_more, size: 18, color: c.textFaint),
                ],
              ),
            ),
          ),
          if (_expanded)
            Container(
              constraints: const BoxConstraints(maxHeight: 220),
              decoration: BoxDecoration(
                color: c.codeBg,
                border: Border(top: BorderSide(color: c.border)),
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(Radii.md)),
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(Space.x3),
                child: SelectableText(
                  '${tool.name} ${_clip(tool.arguments, 600)}\n\n${tool.result == null ? '执行中…' : _clip(tool.result!, 4000)}',
                  style: mono,
                ),
              ),
            ),
        ],
      ),
    );
  }

  static String _clip(String s, int max) => s.length > max ? '${s.substring(0, max)}…' : s;
}

