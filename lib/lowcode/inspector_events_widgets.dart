// 设计约束（低代码 · 合一面板的“事件”页 · 390×844）
// - 内容主次：一行一个事件。有逻辑的写“N 块积木 ›”，整行可点（进积木编辑器）；没逻辑的右边是一个“＋ 加逻辑”。
// - 唯一主操作：没有——“＋ 加逻辑”是描边的次要按钮，一页可能有两三个。
// - “加逻辑”替她把“当 某某 被点击”那块帽子建好再跳过去，不用她自己去积木盒里找。
// - 下面一组“快捷动作（不用进积木）”：一行一个最常见的事（点击时打开网址 / 弹出提示 / 打开弹窗 / 关闭弹窗），右边是现在填的值或“设置”；
//   点了弹一个填字的框，清空＝去掉。存下来的就是普通积木（见 quick_actions.dart），上面那行的积木数会跟着变。
// - 打开 / 关闭弹窗不填字：点了出一张单子，一行一个页面里的弹窗（写它的标题），最下面一行“不要这个动作”。
//   页面里还没有弹窗时这两行是灰的，右边写“先加一个弹窗”，点不动。
// - 取用的 tokens：Space.x2/x3、textMuted、textFaint、accent、border。
import 'package:lopicode/lowcode/edit_types.dart';
import 'package:lopicode/lowcode/logic_model.dart';
import 'package:lopicode/lowcode/model.dart';
import 'package:lopicode/lowcode/quick_actions.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/widgets.dart';
import 'package:material_ui/material_ui.dart';

/// 这种组件能触发哪些事件。
List<String> lcEventsFor(String type) => switch (type) {
  'page' => const ['load'],
  'input' => const ['input', 'click'],
  _ => const ['click'],
};

const Map<String, String> kLcEventLabels = {'click': '点击时', 'input': '输入时', 'load': '页面打开时'};

int _blocks(List<LcBlock> body) => body.fold(0, (sum, b) => sum + 1 + _blocks(b.body) + _blocks(b.orElse));

class InspectorEventsPage extends StatelessWidget {
  const InspectorEventsPage({super.key, required this.doc, required this.node, required this.onOpen, required this.onAdd, this.onEdit});

  /// 改文档（快捷动作用）。不给＝没有“快捷动作”那一组。
  final LcEdit? onEdit;

  final LcDocument doc;
  final LcNode node;

  /// 去看这个组件的逻辑。
  final VoidCallback onOpen;

  /// 给这个事件加逻辑（建好帽子再跳过去）。
  final void Function(String event) onAdd;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final handlers = doc.logic.handlersFor(node.id).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final event in lcEventsFor(node.type))
          () {
            final mine = handlers.where((h) => h.event == event).toList();
            final count = mine.fold(0, (sum, h) => sum + _blocks(h.body));
            final label = Text(kLcEventLabels[event] ?? event, style: t.bodyLarge);
            if (mine.isEmpty) {
              return SizedBox(
                height: 52,
                child: Row(
                  children: [
                    Expanded(child: label),
                    OutlinedButton.icon(key: Key('lc-event-add-$event'), onPressed: () => onAdd(event), icon: const Icon(Icons.add, size: 18), label: const Text('加逻辑')),
                  ],
                ),
              );
            }
            return InkWell(
              key: Key('lc-event-open-$event'),
              onTap: onOpen,
              child: SizedBox(
                height: 52,
                child: Row(
                  children: [
                    Expanded(child: label),
                    Text(count == 0 ? '还没接积木' : '$count 块积木', style: t.bodyMedium?.copyWith(color: c.textMuted)),
                    Icon(Icons.chevron_right, size: 20, color: c.textMuted),
                  ],
                ),
              ),
            );
          }(),
        if (onEdit != null && lcHasQuickActions(node)) ...[
          const SizedBox(height: Space.x2),
          Divider(height: 1, color: c.border),
          const SizedBox(height: Space.x3),
          Text('快捷动作（不用进积木）', style: t.labelMedium?.copyWith(color: c.textMuted)),
          for (final a in kLcQuickActions)
            () {
              final value = lcQuickValue(doc, node.id, a);
              // 要“选一样东西”的动作：弹窗（这一页里的）、页面（项目里别的页）。没有可选的、又没设过，就是灰的。
              final choices = a.picksPage
                  ? [
                      for (final p in doc.pages)
                        if (!identical(p, doc.page)) (p.id, p.title),
                    ]
                  : [for (final d in a.picksDialog ? lcDialogsOf(doc) : const <LcNode>[]) (d.id, lcDialogName(d))];
              final off = a.picksId && choices.isEmpty && value == null;
              final picked = a.picksDialog && value != null ? doc.find(value) : null;
              final shown = value == null
                  ? null
                  : a.picksPage
                  ? (doc.pageTitle(value) ?? '页面已经删了')
                  : a.picksDialog
                  ? (picked?.type == 'dialog' ? lcDialogName(picked!) : '弹窗已经删了')
                  : value;
              return InkWell(
                key: Key('lc-quick-${a.id}'),
                onTap: off
                    ? null
                    : () async {
                        final v = a.picksId
                            ? await _pickOne(context, a.label, choices, value, page: a.picksPage)
                            : await promptDialog(context, title: a.label, initial: value ?? '', hint: '${a.hint}（清空＝不要这个动作）', confirmLabel: '保存');
                        if (v == null) return;
                        onEdit!((d) => lcSetQuick(d, node.id, a, v));
                      },
                child: SizedBox(
                  height: 48,
                  child: Row(
                    children: [
                      Text(a.label, style: t.bodyLarge?.copyWith(color: off ? c.textFaint : null)),
                      const SizedBox(width: Space.x3),
                      Expanded(
                        child: Text(
                          off ? (a.picksPage ? '先加一个页面' : '先加一个弹窗') : shown ?? '设置',
                          textAlign: TextAlign.right,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: t.bodyMedium?.copyWith(color: off ? c.textFaint : (value == null ? c.accent : c.textMuted)),
                        ),
                      ),
                      if (!off) Icon(Icons.chevron_right, size: 20, color: c.textMuted),
                    ],
                  ),
                ),
              );
            }(),
        ],
        const SizedBox(height: Space.x3),
        Text('逻辑在积木编辑器里写；从那边按返回会回到这里，选中的还是这个组件。', style: t.bodySmall?.copyWith(color: c.textFaint)),
      ],
    );
  }
}

/// 选页面里的哪个弹窗 / 项目里的哪一页（[choices]：id 和给人看的名字）。返回选中的 id；选“不要这个动作”返回空字；没选（点外面关掉）返回 null。
Future<String?> _pickOne(BuildContext context, String title, List<(String, String)> choices, String? current, {required bool page}) => showModalBottomSheet<String>(
  context: context,
  builder: (context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: Space.x3),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.x4, Space.x2, Space.x4, Space.x2),
            child: Text(title, style: t.titleMedium),
          ),
          for (final (i, (id, name)) in choices.indexed)
            ListTile(
              key: Key(page ? 'lc-quick-page-$id' : 'lc-quick-dialog-$i'),
              leading: Icon(page ? Icons.description_outlined : Icons.web_asset_outlined, color: c.textMuted),
              title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
              trailing: id == current ? Icon(Icons.check, color: c.accent) : null,
              onTap: () => Navigator.pop(context, id),
            ),
          if (current != null)
            ListTile(
              key: Key(page ? 'lc-quick-page-none' : 'lc-quick-dialog-none'),
              title: Text('不要这个动作', style: TextStyle(color: c.danger)),
              onTap: () => Navigator.pop(context, ''),
            ),
        ],
      ),
    );
  },
);
