// 设计约束（选中积木时的“类型一行字”，390 宽，浅色 + 深色）— 2026-11-26
// - 默认什么都不显示；只有选中的这块积木有类型可说（严格规矩的文档）才出现，贴在选中小条下面、靠右。
// - 这一行只做一件事：说类型。例：`总和：整数`、`加倍：(整数) → 整数`。一行放不下就横向滚，不换行。
// - 层级：字是次要信息（小一号、次要色里偏深），不和上面那条的问题说明抢；能改的时候末尾跟一个文字按钮“标类型”（主操作）。
// - 类型名一律中文（整数、列表〈文字〉），不出现英文类型名。
import 'package:lopicode/theme/tokens.dart';
import 'package:material_ui/material_ui.dart';

class BkTypeLine extends StatelessWidget {
  const BkTypeLine({super.key, required this.text, this.onEdit});
  final String text;

  /// 给了就在末尾出“标类型”。
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    return Material(
      color: c.surface,
      elevation: 2,
      shadowColor: c.shadowOf(0.25),
      shape: const StadiumBorder(),
      clipBehavior: Clip.antiAlias,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.only(left: 14, right: onEdit == null ? 14 : 4, top: 9, bottom: 9),
              child: Text(
                text,
                key: const ValueKey('bk-type-line'),
                maxLines: 1,
                softWrap: false,
                style: t.bodySmall?.copyWith(color: c.text, fontFeatures: const [FontFeature.tabularFigures()]),
              ),
            ),
          ),
          if (onEdit != null)
            TextButton(
              key: const ValueKey('bk-type-edit'),
              onPressed: onEdit,
              style: TextButton.styleFrom(minimumSize: const Size(44, 36), padding: const EdgeInsets.symmetric(horizontal: 12), visualDensity: VisualDensity.compact),
              child: const Text('标类型'),
            ),
        ],
      ),
    );
  }
}
