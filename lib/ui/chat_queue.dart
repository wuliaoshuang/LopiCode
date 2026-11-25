// 设计约束（输入框上方排队的消息 · 390×844）
// - 每条排队的消息一行：左边一个小标签（排队 / 插话）+ 一行文字 + 行尾一个“…”菜单；长按整行也开同一个菜单。
// - 操作都收在菜单里：立即发送 / 改为插话 / 编辑 / 撤回 / 删除。行上不摆按钮。
// - 暂停时最上面多一行：左边“已暂停”和一句原因，右边两个文字按钮“继续发送”“清空”。主操作是“继续发送”（强调色），“清空”弱化。
// - 编辑在底部面板里做：一个多行输入框 + “保存”；附件不在这里改，只写明“附件保留”。
// - 和确认卡、窄条是一家：中性底 + 细边，颜色只落在小标签和主操作上。
import 'package:lopicode/project_session.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/widgets.dart';
import 'package:material_ui/material_ui.dart';

/// 排队 / 插话的消息：每条一行，操作收进右边的菜单；暂停时顶上有“继续发送 / 清空”。
class QueueStrip extends StatelessWidget {
  const QueueStrip({super.key, required this.session});
  final ProjectSession session;

  Future<void> _edit(BuildContext context, QueuedMessage q) async {
    final text = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _EditQueuedSheet(message: q),
    );
    if (text != null) session.editQueued(q, text);
  }

  Future<void> _clear(BuildContext context) async {
    final n = session.queue.length;
    if (n > 1 && !await confirmDialog(context, title: '清空排队的消息？', message: '排着的 $n 条消息都会删掉，不会发出去。', confirmLabel: '清空', danger: true)) return;
    session.clearQueue();
  }

  void _act(BuildContext context, QueuedMessage q, String v) {
    switch (v) {
      case 'now':
        session.sendQueuedNow(q);
      case 'steer':
        session.steerQueued(q);
      case 'edit':
        _edit(context, q);
      case 'withdraw':
        session.withdrawQueued(q);
      case 'delete':
        session.deleteQueued(q);
    }
  }

  List<PopupMenuEntry<String>> _menu(BuildContext context, QueuedMessage q) => [
    const PopupMenuItem(value: 'now', child: Text('立即发送')),
    if (!q.steer && q.images.isEmpty && session.agentBusy) const PopupMenuItem(value: 'steer', child: Text('改为插话')),
    const PopupMenuItem(value: 'edit', child: Text('编辑')),
    const PopupMenuItem(value: 'withdraw', child: Text('撤回')),
    PopupMenuItem(
      value: 'delete',
      child: Text('删除', style: TextStyle(color: context.colors.danger)),
    ),
  ];

  Future<void> _longPress(BuildContext context, QueuedMessage q, Offset at) async {
    final size = MediaQuery.sizeOf(context);
    final v = await showMenu<String>(context: context, position: RelativeRect.fromLTRB(at.dx, at.dy, size.width - at.dx, size.height - at.dy), items: _menu(context, q));
    if (v != null && context.mounted) _act(context, q, v);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final paused = session.queuePaused;
    return Container(
      margin: const EdgeInsets.fromLTRB(Space.x4, 0, Space.x4, Space.x2),
      constraints: const BoxConstraints(maxHeight: 176),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(Radii.lg),
        border: Border.all(color: c.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (paused) ...[
            Padding(
              key: const Key('queue-paused'),
              padding: const EdgeInsets.only(left: Space.x3),
              child: Row(
                children: [
                  Icon(Icons.pause_circle_outline, size: 16, color: c.warning),
                  const SizedBox(width: Space.x2),
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        text: '已暂停',
                        style: t.bodySmall?.copyWith(color: c.text, fontWeight: FontWeight.w600),
                        children: [
                          TextSpan(
                            text: ' · 上一轮没做完',
                            style: t.bodySmall?.copyWith(color: c.textMuted, fontWeight: FontWeight.w400),
                          ),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  TextButton(key: const Key('queue-resume'), onPressed: session.resumeQueue, child: const Text('继续发送')),
                  TextButton(
                    key: const Key('queue-clear'),
                    style: TextButton.styleFrom(foregroundColor: c.textMuted),
                    onPressed: () => _clear(context),
                    child: const Text('清空'),
                  ),
                ],
              ),
            ),
            Divider(height: 1, thickness: 1, color: c.border),
          ],
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              children: [
                for (final q in session.queue)
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onLongPressStart: (d) => _longPress(context, q, d.globalPosition),
                    child: Padding(
                      padding: const EdgeInsets.only(left: Space.x3),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: Space.x2, vertical: 2),
                            decoration: BoxDecoration(color: c.surfaceMuted, borderRadius: BorderRadius.circular(Radii.sm)),
                            child: Text(q.steer ? '插话' : '排队', style: t.bodySmall?.copyWith(color: q.steer ? c.accent : c.textMuted)),
                          ),
                          const SizedBox(width: Space.x2),
                          Expanded(
                            child: Text(
                              '${q.images.isEmpty ? '' : '[${q.images.length} 张图] '}${q.text}',
                              style: t.bodySmall?.copyWith(color: paused ? c.textMuted : c.text),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          PopupMenuButton<String>(
                            tooltip: '处理这条消息',
                            icon: Icon(Icons.more_horiz, size: 20, color: c.textMuted),
                            onSelected: (v) => _act(context, q, v),
                            itemBuilder: (context) => _menu(context, q),
                          ),
                        ],
                      ),
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

class _EditQueuedSheet extends StatefulWidget {
  const _EditQueuedSheet({required this.message});
  final QueuedMessage message;

  @override
  State<_EditQueuedSheet> createState() => _EditQueuedSheetState();
}

class _EditQueuedSheetState extends State<_EditQueuedSheet> {
  late final _text = TextEditingController(text: widget.message.text);

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final images = widget.message.images.length;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(Space.x4, Space.x4, Space.x4, Space.x4 + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('编辑排队的消息', style: t.titleMedium),
            const SizedBox(height: Space.x3),
            TextField(key: const Key('queue-edit-field'), controller: _text, autofocus: true, minLines: 3, maxLines: 8),
            const SizedBox(height: Space.x2),
            Text(images > 0 ? '带着的 $images 张图会保留。' : '改完还在原来的位置排着；清空文字再保存就是删掉这条。', style: t.bodySmall?.copyWith(color: c.textFaint)),
            const SizedBox(height: Space.x4),
            FilledButton(key: const Key('queue-edit-save'), onPressed: () => Navigator.pop(context, _text.text), child: const Text('保存')),
          ],
        ),
      ),
    );
  }
}
