// 设计约束（低代码 · 选中条的外壳 · 390×844）
// - 高 48，贴在工具条上面；选中了组件才有。
// - 内容主次：左边“选上一层”（↑，小图标，页面本身没有）＋类型图标＋名字（告诉她选中的是谁）；
//   右边是这个组件能做的事：最常点的一个实心（唯一主操作），其余描边 / 只有字，最后是“⋯”。
// - 一排最多三个带字的按钮加一个“⋯”，再多就收进“⋯”里；名字放不下就省略。
// - 取用的 tokens：Space.x1/x2/x3/x4、accent（图标、小圆点）、border（上沿）。
import 'package:lopicode/theme/tokens.dart';
import 'package:material_ui/material_ui.dart';

/// 选中条多高。
const double kEditorSelectionBarHeight = 48;

/// 选中条：左边图标＋名字，右边是这个组件能做的事。
///
/// [actions] 从左到右排；按钮用下面三个造：[primary]（实心，最常点的那个）、[outlined]、[plain]（只有字，可带小圆点）。
/// “⋯”之类的菜单直接放一个 PopupMenuButton 进来。
class EditorSelectionBar extends StatelessWidget {
  const EditorSelectionBar({super.key, required this.icon, required this.label, required this.actions, this.onParent});
  final IconData icon;
  final String label;
  final List<Widget> actions;

  /// “选上一层”：选中它外面那个容器（嵌套深时点不到外层用）。null＝没有上一层（页面本身），不显示。
  final VoidCallback? onParent;

  static ButtonStyle _compact() => FilledButton.styleFrom(
    minimumSize: const Size(0, 36),
    padding: const EdgeInsets.symmetric(horizontal: Space.x3),
  );

  static Widget primary(String label, VoidCallback? onPressed) => FilledButton(onPressed: onPressed, style: _compact(), child: Text(label));

  static Widget outlined(String label, VoidCallback? onPressed) => Padding(
    padding: const EdgeInsets.only(left: Space.x2),
    child: OutlinedButton(onPressed: onPressed, style: _compact(), child: Text(label)),
  );

  /// [dot]：右上角带一个小圆点（“这里已经有东西了”）。
  static Widget plain(String label, VoidCallback? onPressed, {bool dot = false}) => Builder(
    builder: (context) => TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        minimumSize: const Size(0, 36),
        padding: const EdgeInsets.symmetric(horizontal: Space.x3),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label),
          if (dot)
            Container(
              key: const ValueKey('lc-action-dot'),
              margin: const EdgeInsets.only(left: 4, bottom: 8),
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: context.colors.accent, shape: BoxShape.circle),
            ),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      key: const ValueKey('lc-selection-bar'),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(top: BorderSide(color: c.border)),
      ),
      padding: EdgeInsets.only(left: onParent == null ? Space.x4 : Space.x1, right: Space.x1),
      height: kEditorSelectionBarHeight,
      child: Row(
        children: [
          if (onParent != null)
            IconButton(
              key: const ValueKey('lc-select-parent'),
              tooltip: '选上一层',
              icon: const Icon(Icons.arrow_upward, size: 18),
              onPressed: onParent,
              constraints: const BoxConstraints.tightFor(width: 40, height: 44),
              padding: EdgeInsets.zero,
            ),
          Icon(icon, size: 18, color: c.accent),
          const SizedBox(width: Space.x2),
          Expanded(
            child: Text(label, style: Theme.of(context).textTheme.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          ...actions,
        ],
      ),
    );
  }
}
