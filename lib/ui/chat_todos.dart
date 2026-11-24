// 设计约束（待办清单条 · 390×844）
// 做法参照 dsh-Go（输入框上方一条细条，点开是清单），代码、文案、布局自己写。
// - 收起：一行。小图标 + “待办 3/7” + “·” + 正在做的那一项（放不下省略）+ 展开箭头。行高 40，整行可点。
// - 展开：下面一项一行——做完的打勾变灰，正在做的是强调色小圆点、字重 500，没做的是空心圈。最多露 6 行，多了自己滚。
// - 中性底 + 细边，和旁边的状态条同族；只有“正在做”的圆点带颜色。
// - 全部做完后收起行写“待办 7/7 · 都做完了”。清单只跟当前这一轮：用户发了新消息就消失。
import 'package:lopicode/agent/todos.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:material_ui/material_ui.dart';

class TodoBar extends StatefulWidget {
  const TodoBar({super.key, required this.todos});
  final List<TodoEntry> todos;

  @override
  State<TodoBar> createState() => _TodoBarState();
}

class _TodoBarState extends State<TodoBar> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final todos = widget.todos;
    final done = todos.where((e) => e.status == TodoStatus.done).length;
    final current = todos.where((e) => e.status == TodoStatus.inProgress).firstOrNull ?? todos.where((e) => e.status == TodoStatus.pending).firstOrNull;
    final tail = done == todos.length ? '都做完了' : (current?.text ?? '');
    return Container(
      margin: const EdgeInsets.fromLTRB(Space.x4, 0, Space.x4, Space.x2),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(Radii.lg),
        border: Border.all(color: c.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            key: const ValueKey('todo-bar'),
            onTap: () => setState(() => _open = !_open),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 40),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: Space.x3),
                child: Row(
                  children: [
                    Icon(Icons.checklist, size: 16, color: c.textMuted),
                    const SizedBox(width: Space.x2),
                    Text(
                      '待办 $done/${todos.length}',
                      style: t.bodySmall?.copyWith(color: c.text, fontWeight: FontWeight.w600),
                    ),
                    if (tail.isNotEmpty) ...[
                      Text('  ·  ', style: t.bodySmall?.copyWith(color: c.textFaint)),
                      Expanded(
                        child: Text(
                          tail,
                          style: t.bodySmall?.copyWith(color: c.textMuted),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ] else
                      const Spacer(),
                    Icon(_open ? Icons.expand_more : Icons.expand_less, size: 18, color: c.textFaint),
                  ],
                ),
              ),
            ),
          ),
          if (_open) ...[
            Divider(height: 1, color: c.border),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 6 * 32 + Space.x2),
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(horizontal: Space.x3, vertical: Space.x1),
                children: [for (final (i, e) in todos.indexed) _TodoLine(key: ValueKey('todo-$i'), entry: e)],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _TodoLine extends StatelessWidget {
  const _TodoLine({super.key, required this.entry});
  final TodoEntry entry;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final (icon, iconColor, textColor) = switch (entry.status) {
      TodoStatus.done => (Icons.check, c.textFaint, c.textFaint),
      TodoStatus.inProgress => (Icons.circle, c.accent, c.text),
      TodoStatus.pending => (Icons.radio_button_unchecked, c.textFaint, c.textMuted),
    };
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 32),
      child: Row(
        children: [
          SizedBox(
            width: 16,
            child: Icon(icon, size: entry.status == TodoStatus.inProgress ? 8 : 14, color: iconColor),
          ),
          const SizedBox(width: Space.x2),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(
                entry.text,
                style: t.bodySmall?.copyWith(color: textColor, fontWeight: entry.status == TodoStatus.inProgress ? FontWeight.w500 : null),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
