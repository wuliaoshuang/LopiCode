// 设计约束（Agent 聊天 · 390×844）— 2026-11-23 按霜霜的参考图（workspace/user/files/88187_0_7hlw.jpg）改版
// - 近白底。顶部不是一条栏：左上悬浮圆按钮（汉堡），右上悬浮圆按钮（···）；对话名和“工作区 / 模型名”只是贴着左按钮的两行文字，
//   不带胶囊底色和描边（2026-11-24 霜霜要求弱化），也不可点。
//   聊天内容从它们下面滚过去，顶部渐隐。有子代理时，右上的圆变成胶囊，多一个子代理计数。
// - 气泡：Agent 的回复是靠左的大圆角浅灰块（左上角小圆角），右边留出一截；我的消息是靠右的浅蓝块（右上角小圆角）。正文 16 号字。
// - 输入区是贴底的白色圆角面板：上方多行输入，下方附件、权限、模型、语音、发送常驻。
// - 模型与权限直接可点；计划模式、图片、引用文件仍可进“＋”面板，每项一行并写着当前值；
//   新对话、Agent 预设、团队、压缩、导出、删除都在右上“···”菜单里。项目规则在“设置”里。
// - 胶囊上方按需叠几条窄条：自动允许中、计划模式、排队的消息、附件缩略图、/ 指令提示；确认卡和提问卡也钉在这里。
// - 空对话：没有可用模型时给明确的上手入口；模型可用时默认显示几条弱化的开场建议，可在“设置”里关闭。
// - 主操作只有一个：发送。AI 生成时长按发送键选“排队 / 插话 / 中断并发送”。
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lopicode/agent/agent_tools.dart';
import 'package:lopicode/agent/usage.dart';
import 'package:lopicode/project_session.dart';
import 'package:lopicode/session/chat_rows.dart';
import 'package:lopicode/state/models_state.dart';
import 'package:lopicode/state/presets_state.dart';
import 'package:lopicode/state/ui_prefs.dart';
import 'package:lopicode/state/workspace_chat.dart';
import 'package:lopicode/state/workspace_conversations.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/chat_background.dart';
import 'package:lopicode/ui/chat_composer.dart';
import 'package:lopicode/ui/chat_extras.dart';
import 'package:lopicode/ui/chat_panels.dart';
import 'package:lopicode/ui/chat_row_view.dart';
import 'package:lopicode/ui/chat_todos.dart';
import 'package:lopicode/ui/chrome.dart';
import 'package:lopicode/ui/file_picker_sheet.dart';
import 'package:lopicode/ui/model_setup.dart';
import 'package:lopicode/ui/settings_ai.dart';
import 'package:lopicode/ui/settings_quota.dart';
import 'package:lopicode/ui/shell.dart';
import 'package:lopicode/ui/team_screen.dart';
import 'package:lopicode/ui/usage_sheet.dart';
import 'package:lopicode/ui/usage_ui.dart';
import 'package:lopicode/ui/widgets.dart';
import 'package:material_ui/material_ui.dart';

/// `/` 指令。
const List<(String, String)> kSlashCommands = [('/new', '开一段新对话'), ('/model', '换模型和思考深度'), ('/plan', '开 / 关计划模式'), ('/compact', '把前面的对话压缩成摘要'), ('/export', '把对话导出成文件'), ('/permission', '改这段对话的权限')];

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key, required this.session});
  final ProjectSession session;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
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
    // 对话目录、当前对话的条目和忙不忙、确认卡 / 提问卡、排队的消息：哪个变了都重画（页面销毁时自动取消订阅）
    ref.listenManual(conversationsProvider(s), (_, _) => _onSession());
    ref.listenManual(activeChatProvider(s), (_, _) => _onSession());
    ref.listenManual(pendingCardsProvider(s), (_, _) => _onSession());
    ref.listenManual(sendQueueProvider(s), (_, _) => _onSession());
    _input.addListener(_onInput);
    // 打开聊天时查一次余额（只对 DeepSeek 官方渠道有动作，最多每分钟一次）。
    s.loadChat().then((_) {
      final ch = s.currentModel?.channel;
      if (mounted && ch != null) s.app.quota.refresh(ch);
      // 没配好模型：进聊天页时引导一次（这次运行里弹过就不再自动弹）。
      if (mounted) ensureModelReady(context, current: s.currentModel, auto: true);
    });
  }

  @override
  void dispose() {
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
    if (s.restoredDraft != null && _input.text.isEmpty) {
      scheduleMicrotask(() {
        if (mounted && _input.text.isEmpty) _input.text = s.takeRestoredDraft() ?? ''; // 通知里不能再改状态：等这一拍过去再拿走草稿
      });
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

  Future<void> _send([String? preset, SendMode mode = SendMode.queue]) async {
    final text = (preset ?? _input.text).trim();
    if (text.isEmpty && _attachments.isEmpty) return;
    if (preset == null && _attachments.isEmpty && _runSlash(text)) {
      _input.clear();
      return;
    }
    // 没有可用模型就不发：弹窗说明并带她去配置，输入的字留着。
    if (!await ensureModelReady(context, current: s.currentModel) || !mounted) return;
    final images = [..._attachments];
    _input.clear();
    setState(_attachments.clear);
    unawaited(s.sendToAgent(text, images: images, mode: mode));
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
    // 不弹底部提示条：它会盖住输入框。开着时输入框上方有常驻提示条。
    await s.setPlanMode(!s.planMode);
  }

  void _openQuota() {
    final ch = s.currentModel?.channel;
    if (ch == null) return;
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => QuotaScreen(channelId: ch.id)));
  }

  void _showUsage() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheet) => UsageSheet(
        session: s,
        onOpenQuota: (ch) {
          Navigator.pop(sheet);
          Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => QuotaScreen(channelId: ch.id)));
        },
      ),
    );
  }

  void _showTurn(TurnUsage turn) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => TrajectorySheet(turn: turn, findTool: s.findToolItem),
    );
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
    final mode = await showModalBottomSheet<SendMode>(
      context: context,
      builder: (_) => SendModeSheet(hasImages: _attachments.isNotEmpty),
    );
    if (mode != null) await _send(null, mode);
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
    final level = await showModalBottomSheet<PermissionLevel>(
      context: context,
      builder: (_) => PermissionSheet(current: s.permission),
    );
    if (level == null || !mounted || level == s.permission) return;
    if (level == PermissionLevel.full && !await confirmFullPermission(context)) return;
    await s.setPermission(level);
  }

  Future<void> _pickPreset() async {
    final id = await showModalBottomSheet<String>(
      context: context,
      builder: (_) => PresetPickerSheet(presets: ref.read(presetsProvider).all, current: s.preset.id),
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

  /// 输入栏左边的“＋”：计划模式、图片、引用文件。
  Future<void> _openPlus() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => PlusSheet(planMode: s.planMode),
    );
    if (choice == null || !mounted) return;
    if (choice == 'plan') return _togglePlan();
    return _attach(choice);
  }

  Future<void> _attach(String choice) async {
    if (choice == 'ref') {
      final path = await showModalBottomSheet<String>(
        context: context,
        builder: (_) => FilePickerSheet(session: s),
      );
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
        final path = await showModalBottomSheet<String>(
          context: context,
          builder: (_) => FilePickerSheet(session: s, imagesOnly: true),
        );
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
    final ok = await confirmDialog(context, title: '删除这段对话？', message: '对话记录会被删除${kids > 0 ? '，它派出的 $kids 个子代理对话也一起删' : ''}。工作区里的文件不受影响。', confirmLabel: '删除', danger: true);
    if (ok) await s.deleteConversation();
  }

  Future<void> _openSubAgents() async {
    final id = await showModalBottomSheet<String>(
      context: context,
      builder: (_) => SubAgentSheet(session: s),
    );
    if (id != null && mounted) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => SubConversationScreen(session: s, conversationId: id),
        ),
      );
    }
  }

  void _openChild(String id) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => SubConversationScreen(session: s, conversationId: id),
    ),
  );

  @override
  Widget build(BuildContext context) {
    ref
      ..watch(modelsProvider)
      ..watch(presetsProvider);
    final prefs = ref.watch(chatPrefsProvider);
    final c = context.colors;
    final pending = s.pendingApproval;
    final question = s.pendingQuestion;
    final model = s.currentModel;
    final subs = s.subAgents;
    final running = subs.where((a) => s.isRunning(a.id)).length;
    final text = _input.text;
    final slash = text.startsWith('/') && !text.contains(RegExp(r'\s')) ? kSlashCommands.where((k) => k.$1.startsWith(text.toLowerCase())).toList() : const <(String, String)>[];
    final topInset = PageBar.insetOf(context);
    final rows = deriveChatRows(s.chat, busy: s.agentBusy, showThinking: prefs.thinking);
    final todos = latestTodos(s.chat);
    // 最后一行已经是“进行中”的步骤组（它自己在转圈）或正在往外冒的回复时，不再另起一行“处理中”。
    final last = rows.lastOrNull;
    final showsProgress =
        (last is StepGroupRow && last.live) ||
        (last is ItemRow && last.item is AssistantItem && (last.item as AssistantItem).streaming) ||
        (last is ItemRow && last.item is ThinkingItem && (last.item as ThinkingItem).streaming);
    final working = s.agentBusy && pending == null && question == null && !showsProgress;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: ShellAppBar(
        title: s.conversationTitle,
        subtitle: '${s.project.name} / ${model == null ? '未设置模型' : model.model.name}',
        actions: [
          if (subs.isNotEmpty) SubAgentCapsule(total: subs.length, running: running, onTap: _openSubAgents),
          PopupMenuButton<String>(
            tooltip: '更多',
            icon: const Icon(Icons.more_horiz),
            onSelected: (v) {
              if (v == 'new') s.newConversation();
              if (v == 'preset') _pickPreset();
              if (v == 'team') {
                Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => TeamScreen(session: s)));
              }
              if (v == 'usage') _showUsage();
              if (v == 'compact') _compact();
              if (v == 'export') _export();
              if (v == 'delete') _deleteConversation();
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: 'new', enabled: !s.agentBusy, child: const Text('新对话')),
              PopupMenuItem(value: 'preset', child: Text('Agent 预设：${s.preset.name}')),
              if (s.teamEnabled) const PopupMenuItem(value: 'team', child: Text('智能体团队')),
              const PopupMenuItem(value: 'usage', child: Text('用量')),
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
                  ? Padding(
                      padding: EdgeInsets.only(top: topInset),
                      child: _EmptyChat(configured: model != null, showIdeas: prefs.suggestions, onPick: _send),
                    )
                  : ChatRowActions(
                      readOutput: s.readCommandOutput,
                      onResume: s.resumeInterrupted,
                      onDismissInterrupted: s.dismissInterrupted,
                      child: ListView.builder(
                        controller: _scroll,
                        padding: EdgeInsets.fromLTRB(Space.x4, topInset + Space.x2, Space.x4, Space.x4),
                        itemCount: rows.length + (working ? 1 : 0),
                        itemBuilder: (context, i) {
                          if (i >= rows.length) return const _Working();
                          return ChatRowView(row: rows[i], onOpenChild: _openChild, onOpenQuota: _openQuota, onOpenTurn: _showTurn);
                        },
                      ),
                    ),
            ),
            if (todos != null && todos.isNotEmpty) TodoBar(todos: todos),
            BackgroundBar(session: s),
            PendingArea(session: s),
            if (s.queue.isNotEmpty) QueueStrip(session: s),
            if (s.autoAllowActive && s.permission != PermissionLevel.full)
              StatusChipRow(key: const ValueKey('auto-allow-chip'), icon: Icons.bolt, text: '自动允许中：本对话的命令和删除不再逐次问你', action: '关闭', tone: BannerTone.warning, onTap: s.clearAutoAllow),
            if (s.mcpAllowCount > 0)
              StatusChipRow(
                key: const ValueKey('mcp-allow-chip'),
                icon: Icons.extension_outlined,
                text: '有 ${s.mcpAllowCount} 个 MCP 工具在本对话里不再逐次问你',
                action: '恢复询问',
                tone: BannerTone.warning,
                onTap: s.clearMcpAllow,
              ),
            if (s.planMode) StatusChipRow(key: const ValueKey('plan-chip'), icon: Icons.map_outlined, text: '计划模式：只出计划，不改文件、不跑命令', action: '退出', tone: BannerTone.info, onTap: _togglePlan),
            if (_attachments.isNotEmpty)
              AttachmentStrip(paths: [for (final a in _attachments) '${s.project.dir}/${a['path']}'], canSee: model?.model.vision ?? false, onRemove: (i) => setState(() => _attachments.removeAt(i))),
            if (slash.isNotEmpty)
              SlashSuggestions(
                commands: slash,
                onPick: (cmd) {
                  _input.clear();
                  _runSlash(cmd);
                },
              ),
            if (model != null) LowBalanceStrip(channel: model.channel),
            ChatComposer(
              context_: s.contextUsage,
              onContext: _showUsage,
              controller: _input,
              focusNode: _focus,
              mentionGuard: s.guard,
              busy: s.agentBusy,
              canSend: _canSend,
              modelName: model == null ? '选择模型' : model.model.name,
              permission: s.permission,
              onPlus: _openPlus,
              onModel: _pickModel,
              onPermission: _pickPermission,
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

/// 空对话：模型不可用时显示设置入口；可用时按偏好显示开场建议。
class _EmptyChat extends StatelessWidget {
  const _EmptyChat({required this.configured, required this.showIdeas, required this.onPick});
  final bool configured;
  final bool showIdeas;
  final void Function(String) onPick;

  static const _ideas = ['看一下项目里有哪些文件，告诉我它是做什么的', '做一个个人主页：头像、简介、三个作品卡片', '给页面加一个深色模式切换按钮'];

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    return Column(
      children: [
        Expanded(child: configured ? const SizedBox.shrink() : const _NeedsSetup()),
        if (configured && showIdeas)
          Padding(
            key: const ValueKey('chat-ideas'),
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
                          Expanded(
                            child: Text(idea, style: t.bodyMedium?.copyWith(color: c.textMuted)),
                          ),
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

class _NeedsSetup extends StatelessWidget {
  const _NeedsSetup();

  @override
  Widget build(BuildContext context) => EmptyState(
    icon: Icons.key_outlined,
    title: '先连上一个模型',
    message: '添加一个渠道（接口地址和 API Key），\n再勾上要用的模型，Agent 才能开始干活。',
    action: FilledButton(
      onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const ChannelsScreen())),
      child: const Text('添加模型'),
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
