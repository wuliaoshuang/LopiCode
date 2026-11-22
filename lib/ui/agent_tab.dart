// 设计约束（Agent · 390×844）
// - 对话是主角：用户消息靠右的浅强调色气泡，Agent 回复是不带气泡的正文，读起来像文档。
// - 工具调用是次要信息：一行小卡（做了什么 + 结果状态），点开才看参数和输出。
// - 需要她点头的操作（执行命令 / 删除文件）用确认卡钉在输入框上方：一句话说清要做什么，两个按钮。
// - 输入行只做一件事：输入 + 发送（运行中变成“停止”）。清空对话收进右上角菜单。
import 'dart:convert';

import 'package:lopicode/app_services.dart';
import 'package:lopicode/project_session.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/settings_screen.dart';
import 'package:lopicode/ui/widgets.dart';
import 'package:material_ui/material_ui.dart';

class AgentTab extends StatefulWidget {
  const AgentTab({super.key, required this.session});
  final ProjectSession session;

  @override
  State<AgentTab> createState() => _AgentTabState();
}

class _AgentTabState extends State<AgentTab> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  int _lastCount = 0;

  ProjectSession get s => widget.session;

  @override
  void initState() {
    super.initState();
    s.addListener(_onSession);
    s.loadChat();
  }

  @override
  void dispose() {
    s.removeListener(_onSession);
    _input.dispose();
    _scroll.dispose();
    super.dispose();
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

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final pending = s.pendingApproval;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.x4, Space.x1, Space.x2, Space.x1),
          child: Row(
            children: [
              Icon(s.autoApprove ? Icons.bolt : Icons.verified_user_outlined, size: 16, color: s.autoApprove ? c.warning : c.textFaint),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  s.autoApprove ? '自动批准已开：命令和删除不再询问' : '执行命令、删除文件前会先问你',
                  style: t.bodySmall?.copyWith(color: s.autoApprove ? c.warning : c.textMuted),
                ),
              ),
              PopupMenuButton<String>(
                tooltip: '更多',
                icon: Icon(Icons.more_horiz, color: c.textFaint),
                onSelected: (v) async {
                  if (v == 'auto') {
                    await s.setAutoApprove(!s.autoApprove);
                  } else if (v == 'clear') {
                    final ok = await confirmDialog(context, title: '清空对话？', message: '这个项目的对话记录会被删除，文件不受影响。', confirmLabel: '清空', danger: true);
                    if (ok) await s.clearChat();
                  }
                },
                itemBuilder: (_) => [
                  PopupMenuItem(value: 'auto', child: Text(s.autoApprove ? '关闭自动批准' : '开启自动批准')),
                  PopupMenuItem(value: 'clear', enabled: !s.agentBusy && s.chat.isNotEmpty, child: const Text('清空对话')),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: s.chat.isEmpty
              ? (app.agentConfigured ? _Suggestions(onPick: _send) : const _NeedsSetup())
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
        Container(
          decoration: BoxDecoration(color: c.surface, border: Border(top: BorderSide(color: c.border))),
          padding: const EdgeInsets.fromLTRB(Space.x3, Space.x2, Space.x2, Space.x2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: _input,
                  minLines: 1,
                  maxLines: 5,
                  textInputAction: TextInputAction.newline,
                  decoration: InputDecoration(
                    hintText: '告诉 Agent 你想做什么…',
                    fillColor: c.bg,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(Radii.md), borderSide: BorderSide.none),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(Radii.md), borderSide: BorderSide.none),
                  ),
                ),
              ),
              const SizedBox(width: Space.x2),
              s.agentBusy
                  ? IconButton.filled(
                      tooltip: '停止',
                      style: IconButton.styleFrom(backgroundColor: c.danger, foregroundColor: c.surface),
                      icon: const Icon(Icons.stop_rounded),
                      onPressed: s.stopAgent,
                    )
                  : IconButton.filled(
                      tooltip: '发送',
                      style: IconButton.styleFrom(backgroundColor: c.accentFill, foregroundColor: c.onAccent),
                      icon: const Icon(Icons.arrow_upward_rounded),
                      onPressed: _send,
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
    message: '填好接口地址、模型名和 API Key，\nAgent 才能开始干活。',
    action: FilledButton(
      onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen())),
      child: const Text('去设置'),
    ),
  );
}

class _Suggestions extends StatelessWidget {
  const _Suggestions({required this.onPick});
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
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(Space.x6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(Icons.auto_awesome, size: 32, color: c.accent),
            const SizedBox(height: Space.x3),
            Text('想做点什么？', style: t.titleLarge, textAlign: TextAlign.center),
            const SizedBox(height: Space.x1),
            Text('Agent 可以读写这个项目的文件、跑命令、改低代码页面。', style: t.bodySmall, textAlign: TextAlign.center),
            const SizedBox(height: Space.x6),
            for (final idea in _ideas)
              Padding(
                padding: const EdgeInsets.only(bottom: Space.x2),
                child: OutlinedButton(
                  onPressed: () => onPick(idea),
                  style: OutlinedButton.styleFrom(
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.symmetric(horizontal: Space.x3, vertical: Space.x3),
                    backgroundColor: c.surface,
                  ),
                  child: Text(idea, style: t.bodyMedium),
                ),
              ),
          ],
        ),
      ),
    );
  }
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
      margin: const EdgeInsets.fromLTRB(Space.x3, 0, Space.x3, Space.x3),
      padding: const EdgeInsets.all(Space.x3),
      decoration: BoxDecoration(
        color: c.warningSoft,
        borderRadius: BorderRadius.circular(Radii.md),
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
