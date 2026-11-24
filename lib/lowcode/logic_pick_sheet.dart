// 设计约束（积木逻辑里“选一个”的小面板 · 390×844）— 2026-11-24
// - 都是底部面板：一个标题、一列选项，每行只做一件事（点了就选中并关掉），行高 ≥ 44。
// - 选控件：按页面的层级缩进（每层 16px，最多缩 6 层）；不能选的（比如“输入变化”只能选输入框）灰掉但留在原位，层级才看得懂。
// - 选变量：列出页面变量（名字 + 类型）；最后一行“新建变量…”。可以不填的参数最上面多一行“不存进变量”。
// - 面板内容超过屏幕 85% 时自己滚动；键盘弹出时整体上移，不被挡住。
import 'package:lopicode/lowcode/logic_model.dart';
import 'package:lopicode/lowcode/logic_text.dart';
import 'package:lopicode/lowcode/logic_vars_sheet.dart';
import 'package:lopicode/lowcode/model.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:material_ui/material_ui.dart';

/// 打开一个底部面板（可随内容变高、键盘弹出时上移）。
Future<T?> showLcSheet<T>(BuildContext context, WidgetBuilder builder) => showModalBottomSheet<T>(context: context, isScrollControlled: true, builder: builder);

/// 底部面板的统一骨架：标题（可带一行说明）+ 可滚动的内容 + 固定在底下的按钮区。
class LcSheetFrame extends StatelessWidget {
  const LcSheetFrame({super.key, required this.title, this.note, this.header, required this.children, this.footer});
  final String title;
  final String? note;

  /// 标题下面、不跟着滚动的一块（面包屑、分类标签）。
  final Widget? header;
  final List<Widget> children;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final media = MediaQuery.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: (media.size.height - media.viewInsets.bottom) * 0.85),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(Space.x4, 0, Space.x4, Space.x2),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: t.titleLarge),
                    if (note != null) ...[const SizedBox(height: 2), Text(note!, style: t.bodySmall)],
                  ],
                ),
              ),
              ?header,
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.only(bottom: Space.x2),
                  children: children,
                ),
              ),
              if (footer != null) Padding(padding: const EdgeInsets.fromLTRB(Space.x4, Space.x2, Space.x4, Space.x3), child: footer),
            ],
          ),
        ),
      ),
    );
  }
}

/// 面板里的一行选项。
class LcOptionRow extends StatelessWidget {
  const LcOptionRow({super.key, required this.label, this.detail, this.leading, this.selected = false, this.enabled = true, this.indent = 0, required this.onTap});
  final String label;
  final String? detail;
  final Widget? leading;
  final bool selected;
  final bool enabled;
  final double indent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    return InkWell(
      onTap: enabled ? onTap : null,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Padding(
          padding: EdgeInsets.fromLTRB(Space.x4 + indent, Space.x1, Space.x4, Space.x1),
          child: Row(
            children: [
              if (leading != null) ...[leading!, const SizedBox(width: Space.x3)],
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.bodyLarge?.copyWith(color: !enabled ? c.textFaint.withValues(alpha: 0.6) : (selected ? c.accent : c.text), fontWeight: selected ? FontWeight.w600 : FontWeight.w400),
                    ),
                    if (detail != null) Text(detail!, maxLines: 2, overflow: TextOverflow.ellipsis, style: t.bodySmall),
                  ],
                ),
              ),
              if (selected) Icon(Icons.check_rounded, size: 20, color: c.accent),
            ],
          ),
        ),
      ),
    );
  }
}

/// 页面里的控件，按层级缩进排成一列。[enabled] 说哪些能选。
List<Widget> lcNodeRows(LcDocument doc, {String? selected, bool Function(LcNode node)? enabled, required void Function(LcNode node) onPick}) {
  final rows = <Widget>[];
  void walk(LcNode n, int depth) {
    rows.add(
      LcOptionRow(
        key: ValueKey('lc-node-${n.id}'),
        label: describeNode(doc, n.id),
        selected: n.id == selected,
        enabled: enabled?.call(n) ?? true,
        indent: 16.0 * depth.clamp(0, 6),
        onTap: () => onPick(n),
      ),
    );
    for (final child in n.children) {
      walk(child, depth + 1);
    }
  }

  walk(doc.root, 0);
  return rows;
}

/// 选一个控件；返回它的 id，取消返回 null。
Future<String?> showLcNodePicker(BuildContext context, LcDocument doc, {required String title, String? note, String? selected, bool Function(LcNode node)? enabled}) => showLcSheet<String>(
  context,
  (sheet) => LcSheetFrame(
    title: title,
    note: note,
    children: lcNodeRows(doc, selected: selected, enabled: enabled, onPick: (n) => Navigator.pop(sheet, n.id)),
  ),
);

/// 几个固定值里选一个；返回选中的值。
Future<String?> showLcChoicePicker(BuildContext context, {required String title, required List<String> values, required String Function(String value) labelOf, String? selected}) =>
    showLcSheet<String>(
      context,
      (sheet) => LcSheetFrame(
        title: title,
        children: [for (final v in values) LcOptionRow(key: ValueKey('lc-choice-$v'), label: labelOf(v), selected: v == selected, onTap: () => Navigator.pop(sheet, v))],
      ),
    );

/// 选变量的结果：选了哪个名字（空＝不存进变量）；[create] 不为空＝这个变量是刚填的、还没建，调用方要在同一次改动里把它建出来。
typedef LcVarPick = ({String name, LcVarDraft? create});

/// 选一个变量（或当场新建一个）。
Future<LcVarPick?> showLcVariablePicker(BuildContext context, LcDocument doc, {required String title, String? selected, bool optional = false, String? suggestType}) => showLcSheet<LcVarPick>(
  context,
  (sheet) => LcSheetFrame(
    title: title,
    note: doc.logic.variables.isEmpty ? '这个页面还没有变量，先新建一个。' : null,
    children: [
      if (optional) LcOptionRow(key: const ValueKey('lc-var-none'), label: '不存进变量', selected: selected == null || selected.isEmpty, onTap: () => Navigator.pop(sheet, (name: '', create: null))),
      for (final v in doc.logic.variables)
        LcOptionRow(key: ValueKey('lc-var-${v.name}'), label: v.name, detail: describeVarType(v.type), selected: v.name == selected, onTap: () => Navigator.pop(sheet, (name: v.name, create: null))),
      LcOptionRow(
        key: const ValueKey('lc-var-new'),
        label: '新建变量…',
        leading: Icon(Icons.add_rounded, size: 20, color: sheet.colors.accent),
        onTap: () async {
          final draft = await showLcVariableDialog(sheet, taken: {for (final v in doc.logic.variables) v.name}, suggestType: suggestType);
          if (draft != null && draft.name.isNotEmpty && sheet.mounted) Navigator.pop(sheet, (name: draft.name, create: draft));
        },
      ),
    ],
  ),
);

/// 把刚填的新变量建出来（已经有同名的就不动）。
void lcApplyVarDraft(LcLogic logic, LcVarDraft? draft) {
  if (draft == null || logic.variable(draft.name) != null) return;
  logic.addVariable(draft.name, type: draft.type, initial: draft.initial);
}

/// 面板里“几个里选一个”的小标签。选中＝实心强调色 + 白字（不用主题默认的选中色：深色主题下那个颜色配白字看不清）。
class LcChoiceChip extends StatelessWidget {
  const LcChoiceChip({super.key, required this.label, required this.selected, required this.onSelected, this.avatar, this.tooltip});
  final String label;
  final bool selected;
  final VoidCallback onSelected;
  final Widget? avatar;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ChoiceChip(
      avatar: avatar,
      tooltip: tooltip,
      label: Text(label),
      labelStyle: TextStyle(color: selected ? c.onAccent : c.text, fontSize: FontSize.sm, fontWeight: selected ? FontWeight.w600 : FontWeight.w400),
      selected: selected,
      showCheckmark: false,
      selectedColor: c.accentFill,
      backgroundColor: c.surface,
      side: BorderSide(color: selected ? c.accentFill : c.border),
      onSelected: (_) => onSelected(),
    );
  }
}
