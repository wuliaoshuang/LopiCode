// 设计约束（主题预览的第五种：搭建，也就是低代码编辑器 · 宽约 358、高 232）— 2026-11-26
// - 为什么有它：主题里“低代码编辑器”一节有 21 个颜色，别的四种预览里都看不到；没有这一块就只能闭着眼改。
// - 画的是编辑器自己的那层东西（选中框、拖放提示、标注），不是用户页面的内容：
//   左半边＝一个被选中的组件：外边距示意 → 选中框 + 名字标签 + 四角拖柄 → 内边距示意 → 下面的尺寸标签；
//   右半边从上到下一行一样：空容器（平时）、空容器（拖到上面）、插入线（平时 / 对准时）、
//   可放进去的容器的描边 + 拖着的小牌子、“组件不见了”的占位。
// - 21 项每一项都至少露一处。底下那张“页面”用这份主题的卡片色，旁边的留白用分组页面底色（都是主题里的，不写死）。
// - 只是样子：不接手指、不进读屏（外面的 ThemePreview 已经包了）。
import 'package:lopicode/appearance/theme_fields.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:material_ui/material_ui.dart';

class ThemeLowcodePreview extends StatelessWidget {
  const ThemeLowcodePreview({super.key, required this.spec});
  final ThemeSpec spec;

  @override
  Widget build(BuildContext context) {
    Color k(String key) => spec.lowcodeColor(key);
    final ui = context.colors;
    final label = Theme.of(context).textTheme.labelSmall;
    TextStyle small(Color color) => (label ?? const TextStyle()).copyWith(color: color, fontSize: 10, height: 1.2);

    Widget handle() => Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        color: k(LowcodeKey.handleFill),
        border: Border.all(color: k(LowcodeKey.selection), width: 1.5),
      ),
    );

    // 左：被选中的组件。
    final selected = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          key: const Key('lc-preview-name-tag'),
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
          color: k(LowcodeKey.selection),
          child: Text('卡片', style: small(k(LowcodeKey.selectionText))),
        ),
        // 外边距示意
        Container(
          color: k(LowcodeKey.marginRing),
          padding: const EdgeInsets.all(8),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                key: const Key('lc-preview-selection'),
                decoration: BoxDecoration(
                  color: ui.surface,
                  border: Border.all(color: k(LowcodeKey.selection), width: 1.5),
                ),
                // 内边距示意
                child: Container(
                  color: k(LowcodeKey.paddingRing),
                  padding: const EdgeInsets.all(8),
                  child: Container(
                    width: 96,
                    height: 54,
                    color: ui.surface,
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('标题', style: small(ui.text).copyWith(fontWeight: FontWeight.w600)),
                        Text('页面里的内容', style: small(ui.textMuted)),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(left: -4, top: -4, child: handle()),
              Positioned(right: -4, top: -4, child: handle()),
              Positioned(left: -4, bottom: -4, child: handle()),
              Positioned(right: -4, bottom: -4, child: handle()),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Container(
          key: const Key('lc-preview-size-tag'),
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
          decoration: BoxDecoration(color: k(LowcodeKey.sizeTagBg), borderRadius: BorderRadius.circular(3)),
          child: Text('128 × 86', style: small(k(LowcodeKey.sizeTagText))),
        ),
      ],
    );

    Widget drop(String text, Color bg, Color border, {Key? key}) => Container(
      key: key,
      height: 30,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: border),
      ),
      child: Text(text, style: small(k(LowcodeKey.dropText))),
    );
    Widget bar(Color color, {Key? key}) => Expanded(
      child: Container(
        key: key,
        height: 3,
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
      ),
    );

    // 右：拖放提示和标注，一行一样。
    final hints = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        drop('空容器', k(LowcodeKey.dropIdleBg), k(LowcodeKey.dropIdleBorder), key: const Key('lc-preview-drop-idle')),
        const SizedBox(height: 6),
        drop('拖到上面时', k(LowcodeKey.dropHoverBg), k(LowcodeKey.dropHoverBorder), key: const Key('lc-preview-drop-hover')),
        const SizedBox(height: 8),
        Row(
          children: [
            bar(k(LowcodeKey.insertBarIdle), key: const Key('lc-preview-insert-idle')),
            const SizedBox(width: 6),
            bar(k(LowcodeKey.insertBar), key: const Key('lc-preview-insert')),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          key: const Key('lc-preview-drop-outline'),
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            border: Border.all(color: k(LowcodeKey.dropOutline), width: 1.5),
            borderRadius: BorderRadius.circular(4),
          ),
          alignment: Alignment.centerLeft,
          child: Container(
            key: const Key('lc-preview-drag-chip'),
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(color: k(LowcodeKey.dragChipBg), borderRadius: BorderRadius.circular(10)),
            child: Text('拖着的按钮', style: small(k(LowcodeKey.dragChipText))),
          ),
        ),
        const SizedBox(height: 6),
        Container(
          key: const Key('lc-preview-missing'),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
          decoration: BoxDecoration(
            color: k(LowcodeKey.missingBg),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: k(LowcodeKey.missingBorder)),
          ),
          child: Row(
            children: [
              Icon(Icons.help_outline, size: 13, color: k(LowcodeKey.missingIcon)),
              const SizedBox(width: 4),
              Expanded(
                child: Text('组件不见了', style: small(k(LowcodeKey.missingText)), maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
        ),
      ],
    );

    return ColoredBox(
      color: ui.canvas,
      child: Padding(
        padding: const EdgeInsets.all(Space.x3),
        child: Container(
          decoration: BoxDecoration(
            color: ui.surface,
            border: Border.all(color: ui.border, width: ui.hairline),
          ),
          padding: const EdgeInsets.all(Space.x3),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              selected,
              const SizedBox(width: Space.x4),
              Expanded(child: hints),
            ],
          ),
        ),
      ),
    );
  }
}
