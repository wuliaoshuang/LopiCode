// 设计约束（消息操作的三个底部面板 · 390×844）
// - “更多”：一行一个动作——图标 + 名称，下面一句灰色说明（有才写）。现在不能用的那行变灰，说明换成原因。删除是红色，排最后。
// - “删除”：先说清影响，再选删法。两种删法各占一行（单选），不能用的那种变灰并写原因；
//   下面一段灰字写后果（Agent 之后看不到、不撤销文件改动、用量不变）；最下面一排：取消（弱）、删除（红色实心，唯一的主操作）。
// - “分享”：先选范围（这一条 / 这一轮，分段按钮占一行），再选怎么分享，一行一种：复制为 Markdown、存成文件。
//   不调安卓的系统分享面板（2026-11-25 跟霜霜说定：先导出文本复制，不加原生代码、不加插件）。
//   最下面一句灰字：像密钥的内容会换成 ***。
import 'package:flutter/services.dart';
import 'package:lopicode/session/message_ops.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/message_action_bar.dart';
import 'package:material_ui/material_ui.dart';

export 'package:lopicode/session/message_ops.dart' show DeleteScope;

class _SheetTitle extends StatelessWidget {
  const _SheetTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(Space.x6, 0, Space.x6, Space.x2),
    child: Align(
      alignment: Alignment.centerLeft,
      child: Text(text, style: Theme.of(context).textTheme.titleMedium),
    ),
  );
}

/// “更多”：操作栏上放不下的动作。选中的动作作为返回值交回去（由操作栏执行）。
class MessageMoreSheet extends StatelessWidget {
  const MessageMoreSheet({super.key, required this.target, required this.actions});
  final MessageTarget target;
  final List<MessageAction> actions;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final a in actions)
            Builder(
              builder: (context) {
                final blocked = a.disabledReason?.call(target);
                final hint = blocked ?? a.hint?.call(target);
                final fg = blocked != null ? c.textFaint : (a.danger ? c.danger : c.text);
                return ListTile(
                  key: ValueKey('more-${a.slot.name}'),
                  enabled: blocked == null,
                  leading: Icon(a.icon(target), color: fg),
                  title: Text(a.label(target), style: t.bodyLarge?.copyWith(color: fg)),
                  subtitle: hint == null ? null : Text(hint, style: t.bodySmall),
                  onTap: () => Navigator.pop(context, a),
                );
              },
            ),
          const SizedBox(height: Space.x2),
        ],
      ),
    );
  }
}

/// 删除确认：选“只删这一条”还是“删掉这一整轮”。点“删除”返回选的那种；取消返回 null。
class MessageDeleteSheet extends StatefulWidget {
  const MessageDeleteSheet({super.key, required this.target, required this.preview});
  final MessageTarget target;
  final DeletePreview preview;

  @override
  State<MessageDeleteSheet> createState() => _MessageDeleteSheetState();
}

class _MessageDeleteSheetState extends State<MessageDeleteSheet> {
  late DeleteScope _scope = widget.preview.single == null ? DeleteScope.turn : DeleteScope.message;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final p = widget.preview;
    final mine = widget.target.mine;
    final kids = widget.target.session.messageOps.childConversationsOf(p.turn).length;
    final parts = [if (p.turnMine > 0) '你的 ${p.turnMine} 条消息', if (p.turnReplies > 0) 'Agent 的 ${p.turnReplies} 段话', if (p.turnSteps > 0) '${p.turnSteps} 个步骤'];
    Widget option(DeleteScope scope, String title, String hint, {bool enabled = true}) {
      final on = _scope == scope;
      return ListTile(
        key: ValueKey('delete-${scope.name}'),
        enabled: enabled,
        selected: on,
        leading: Icon(on ? Icons.radio_button_checked : Icons.radio_button_unchecked, color: !enabled ? c.textFaint : (on ? c.accent : c.textMuted)),
        title: Text(title, style: t.bodyLarge?.copyWith(color: enabled ? c.text : c.textFaint)),
        subtitle: Text(hint, style: t.bodySmall),
        onTap: () => setState(() => _scope = scope),
      );
    }

    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _SheetTitle('删除消息'),
          option(DeleteScope.message, mine ? '只删这条消息' : '只删这段回复', p.singleBlocked ?? (mine ? '别的消息和 Agent 的回复都留着。' : '这一轮的步骤和别的内容都留着。'), enabled: p.single != null),
          option(DeleteScope.turn, '删掉这一整轮', '${parts.isEmpty ? '这一轮的内容' : parts.join('、')}一起删。${kids > 0 ? '这一轮派出的 $kids 个子代理对话也一起删。' : ''}'),
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.x6, Space.x2, Space.x6, Space.x4),
            child: Text('${p.archived ? '这条已经被压缩进摘要里：删掉后这里不再显示，但摘要里可能还留着它的意思。' : '删掉后，Agent 之后也看不到这些内容。'}\n不会撤销它对文件做过的修改，已经花掉的用量也不会变。删了不能恢复。', style: t.bodySmall?.copyWith(height: 1.5)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.x6, 0, Space.x6, Space.x4),
            child: Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    style: TextButton.styleFrom(foregroundColor: c.textMuted, minimumSize: const Size.fromHeight(48)),
                    child: const Text('取消'),
                  ),
                ),
                const SizedBox(width: Space.x3),
                Expanded(
                  child: FilledButton(
                    key: const ValueKey('delete-confirm'),
                    onPressed: () => Navigator.pop(context, _scope),
                    style: FilledButton.styleFrom(backgroundColor: c.danger, foregroundColor: c.surface, minimumSize: const Size.fromHeight(48)),
                    child: const Text('删除'),
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

/// 分享：选范围，再选怎么分享。做完自己关掉并提示结果。
class MessageShareSheet extends StatefulWidget {
  const MessageShareSheet({super.key, required this.target});
  final MessageTarget target;

  @override
  State<MessageShareSheet> createState() => _MessageShareSheetState();
}

class _MessageShareSheetState extends State<MessageShareSheet> {
  bool _turn = false;

  String? get _markdown => widget.target.session.messageOps.markdownOf(widget.target.id, wholeTurn: _turn);

  void _done(String text) {
    final messenger = ScaffoldMessenger.of(context);
    Navigator.pop(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _copy() async {
    final md = _markdown;
    if (md == null) return _done('这条消息已经不在记录里了。');
    await Clipboard.setData(ClipboardData(text: md));
    if (mounted) _done('已复制为 Markdown');
  }

  Future<void> _save() async {
    String? rel;
    try {
      rel = await widget.target.session.messageOps.saveMarkdown(widget.target.id, wholeTurn: _turn);
    } on Exception catch (e) {
      if (mounted) _done('没存成：$e');
      return;
    }
    if (mounted) _done(rel == null ? '这条消息已经不在记录里了。' : '已存到工作区：$rel（在“文件”页里能看到）');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    Widget row(String key, IconData icon, String title, String hint, VoidCallback onTap) => ListTile(
      key: ValueKey('share-$key'),
      leading: Icon(icon, color: c.text),
      title: Text(title),
      subtitle: Text(hint, style: t.bodySmall),
      onTap: onTap,
    );
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _SheetTitle('分享'),
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.x6, 0, Space.x6, Space.x2),
            child: SegmentedButton<bool>(
              key: const ValueKey('share-scope'),
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: false, label: Text('这一条')),
                ButtonSegment(value: true, label: Text('这一轮：提问 + 回复')),
              ],
              selected: {_turn},
              onSelectionChanged: (v) => setState(() => _turn = v.first),
            ),
          ),
          row('copy', Icons.content_copy_outlined, '复制为 Markdown', '粘贴到哪里都行', _copy),
          row('save', Icons.save_alt, '存成文件', '存到工作区的 exports/ 里，在“文件”页能看到', _save),
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.x6, Space.x2, Space.x6, Space.x4),
            child: Text('分享出去的内容里，像密钥、密码的部分会换成 ***。', style: t.bodySmall),
          ),
        ],
      ),
    );
  }
}
