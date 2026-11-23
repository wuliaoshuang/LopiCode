// 设计约束（Agent 对话 · 390×844）— 布局照霜霜给的参考图
// - 顶栏：左汉堡按钮；两行标题（对话名 + “项目名 / 模型名”）；右边“新对话”和 ⋮ 菜单。没有底部导航。
// - 空对话：顶部正中一个小的文字入口“项目规则”，下面留白；几条开场建议贴着输入卡片上方，弱化显示。
// - 底部是一张大圆角输入卡片：上面是输入区，下面一行控件都在卡片里——左：模型、自动批准开关；右：＋（引用项目文件）、圆形发送 / 停止。
// - 对话是主角：用户消息靠右的浅强调色气泡，Agent 回复是不带气泡的正文。
// - 工具调用是次要信息：一行小卡，点开才看参数和输出。
// - 需要她点头的操作（执行命令 / 删除文件）用确认卡钉在输入卡片上方：一句话说清要做什么，两个按钮。
// - 主操作只有一个：发送。
import 'dart:convert';

import 'package:lopicode/app_services.dart';
import 'package:lopicode/core/project_store.dart';
import 'package:lopicode/core/stores.dart';
import 'package:lopicode/project_session.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/settings_screen.dart';
import 'package:lopicode/ui/shell.dart';
import 'package:lopicode/ui/widgets.dart';
import 'package:material_ui/material_ui.dart';

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
    if (mounted) setState(() {}); // 发送按钮跟着“有没有字”变
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

  void _send([String? preset]) {
    final text = (preset ?? _input.text).trim();
    if (text.isEmpty || s.agentBusy) return;
    _input.clear();
    s.sendToAgent(text);
  }

  Future<void> _toggleAutoApprove() async {
    if (s.autoApprove) {
      await s.setAutoApprove(false);
      if (mounted) showSnack(context, '已关闭自动批准：执行命令、删除文件前会先问你');
      return;
    }
    final ok = await confirmDialog(
      context,
      title: '开启自动批准？',
      message: '开启后，Agent 在这个项目里执行命令、删除文件不再逐次问你。只对这个项目生效，随时可以关。',
      confirmLabel: '开启',
    );
    if (ok) await s.setAutoApprove(true);
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
    await showModalBottomSheet<void>(context: context, isScrollControlled: true, builder: (_) => const _ModelSheet());
    if (mounted) setState(() {});
  }

  Future<void> _attachFile() async {
    final path = await showModalBottomSheet<String>(context: context, builder: (_) => _FilePickerSheet(session: s));
    if (path == null) return;
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

  Future<void> _deleteConversation() async {
    final ok = await confirmDialog(context, title: '删除这段对话？', message: '对话记录会被删除，项目文件不受影响。', confirmLabel: '删除', danger: true);
    if (ok) await s.deleteConversation();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final c = context.colors;
    final pending = s.pendingApproval;
    final model = app.settings.getString(SettingKeys.agentModel).trim();
    return Scaffold(
      appBar: ShellAppBar(
        title: s.conversationTitle,
        subtitle: '${s.project.name} / ${model.isEmpty ? '未设置模型' : model}',
        actions: [
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
              if (v == 'auto') _toggleAutoApprove();
              if (v == 'delete') _deleteConversation();
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'rules', child: Text('项目规则')),
              PopupMenuItem(value: 'auto', child: Text(s.autoApprove ? '关闭自动批准' : '开启自动批准')),
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
                      itemCount: s.chat.length + (s.agentBusy && pending == null ? 1 : 0),
                      itemBuilder: (context, i) {
                        if (i >= s.chat.length) return const _Working();
                        return _ChatItemView(item: s.chat[i]);
                      },
                    ),
            ),
            if (pending != null) _ApprovalCard(pending: pending, onAnswer: s.resolveApproval),
            _InputCard(
              controller: _input,
              focusNode: _focus,
              busy: s.agentBusy,
              autoApprove: s.autoApprove,
              onModel: _pickModel,
              onToggleAuto: _toggleAutoApprove,
              onAttach: _attachFile,
              onSend: _send,
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
    required this.autoApprove,
    required this.onModel,
    required this.onToggleAuto,
    required this.onAttach,
    required this.onSend,
    required this.onStop,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool busy;
  final bool autoApprove;
  final VoidCallback onModel;
  final VoidCallback onToggleAuto;
  final VoidCallback onAttach;
  final VoidCallback onSend;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final hasText = controller.text.trim().isNotEmpty;
    const none = OutlineInputBorder(borderSide: BorderSide.none);
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
              hintText: '告诉 Agent 你想做什么',
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
                IconButton(
                  tooltip: autoApprove ? '自动批准已开' : '执行命令、删除文件前先问我',
                  onPressed: onToggleAuto,
                  icon: Icon(autoApprove ? Icons.bolt : Icons.verified_user_outlined, color: autoApprove ? c.warning : c.accent),
                ),
                const Spacer(),
                IconButton(
                  tooltip: '引用项目文件',
                  onPressed: onAttach,
                  icon: Icon(Icons.add, color: c.text),
                ),
                const SizedBox(width: Space.x1),
                busy
                    ? _RoundButton(tooltip: '停止', icon: Icons.stop_rounded, bg: c.danger, fg: c.surface, onPressed: onStop)
                    : _RoundButton(
                        tooltip: '发送',
                        icon: Icons.arrow_upward_rounded,
                        bg: hasText ? c.accentFill : c.surfaceMuted,
                        fg: hasText ? c.onAccent : c.textFaint,
                        onPressed: hasText ? onSend : null,
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

class _ModelSheet extends StatefulWidget {
  const _ModelSheet();

  @override
  State<_ModelSheet> createState() => _ModelSheetState();
}

class _ModelSheetState extends State<_ModelSheet> {
  TextEditingController? _model;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _model ??= TextEditingController(text: AppScope.of(context).settings.getString(SettingKeys.agentModel));
  }

  @override
  void dispose() {
    _model?.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final app = AppScope.of(context);
    await app.settings.set(SettingKeys.agentModel, _model!.text.trim());
    app.touch();
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final t = Theme.of(context).textTheme;
    final base = app.settings.getString(SettingKeys.agentBaseUrl).trim();
    return Padding(
      padding: EdgeInsets.fromLTRB(Space.x4, 0, Space.x4, MediaQuery.viewInsetsOf(context).bottom + Space.x4),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('模型', style: t.titleLarge),
            const SizedBox(height: Space.x1),
            Text(base.isEmpty ? '还没填接口地址' : '接口：$base', style: t.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: Space.x4),
            TextField(
              controller: _model,
              decoration: const InputDecoration(labelText: '模型名', hintText: '接口支持的模型名'),
              onSubmitted: (_) => _save(),
            ),
            const SizedBox(height: Space.x4),
            FilledButton(onPressed: _save, child: const Text('保存')),
            TextButton(
              onPressed: () {
                final nav = Navigator.of(context)..pop();
                nav.push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen()));
              },
              child: const Text('接口地址和 API Key 在设置里'),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilePickerSheet extends StatelessWidget {
  const _FilePickerSheet({required this.session});
  final ProjectSession session;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    return SafeArea(
      top: false,
      child: FutureBuilder<List<String>>(
        future: listProjectFiles(session.guard),
        builder: (context, snap) {
          final files = (snap.data ?? const <String>[]).where((f) => !f.endsWith('/')).toList();
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(Space.x4, 0, Space.x4, Space.x2),
                child: Text('引用项目文件', style: t.titleLarge),
              ),
              if (snap.connectionState != ConnectionState.done)
                const Padding(padding: EdgeInsets.all(Space.x6), child: Center(child: CircularProgressIndicator()))
              else if (files.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(Space.x6),
                  child: Text('项目里还没有文件。', style: t.bodyMedium?.copyWith(color: c.textMuted), textAlign: TextAlign.center),
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
    message: '填好接口地址、模型名和 API Key，\nAgent 才能开始干活。',
    action: FilledButton(
      onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen())),
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

class _ChatItemView extends StatelessWidget {
  const _ChatItemView({required this.item});
  final ChatItem item;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    switch (item) {
      case UserItem(:final text):
        return Align(
          alignment: Alignment.centerRight,
          child: Container(
            margin: const EdgeInsets.only(top: Space.x4, bottom: Space.x2, left: Space.x12),
            padding: const EdgeInsets.symmetric(horizontal: Space.x3, vertical: Space.x2),
            decoration: BoxDecoration(color: c.accentSoft, borderRadius: BorderRadius.circular(Radii.md)),
            child: SelectableText(text, style: t.bodyLarge),
          ),
        );
      case AssistantItem(:final text, :final streaming):
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: Space.x2),
          child: SelectableText(streaming ? '$text▍' : text, style: t.bodyLarge),
        );
      case final ToolItem tool:
        return _ToolCard(tool: tool);
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
    _ => name,
  };
}

class _ToolCard extends StatefulWidget {
  const _ToolCard({required this.tool});
  final ToolItem tool;

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

class _ApprovalCard extends StatelessWidget {
  const _ApprovalCard({required this.pending, required this.onAnswer});
  final PendingApproval pending;
  final void Function(bool) onAnswer;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final isDelete = pending.request.tool == 'delete_file';
    return Container(
      margin: const EdgeInsets.fromLTRB(Space.x2, 0, Space.x2, Space.x2),
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
              Icon(isDelete ? Icons.delete_outline : Icons.terminal, size: 18, color: c.warning),
              const SizedBox(width: Space.x2),
              Text('Agent 想${pending.request.title}，要允许吗？', style: t.titleSmall?.copyWith(color: c.warning)),
            ],
          ),
          const SizedBox(height: Space.x2),
          Container(
            constraints: const BoxConstraints(maxHeight: 96),
            padding: const EdgeInsets.all(Space.x2),
            decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(Radii.sm)),
            child: SingleChildScrollView(
              child: SelectableText(
                pending.request.detail,
                style: TextStyle(fontFamily: kMonoFont, fontFamilyFallback: kMonoFallback, fontSize: FontSize.sm, height: 1.5, color: c.text),
              ),
            ),
          ),
          const SizedBox(height: Space.x3),
          Row(
            children: [
              Expanded(child: OutlinedButton(onPressed: () => onAnswer(false), child: const Text('拒绝'))),
              const SizedBox(width: Space.x2),
              Expanded(child: FilledButton(onPressed: () => onAnswer(true), child: const Text('允许这一次'))),
            ],
          ),
        ],
      ),
    );
  }
}
