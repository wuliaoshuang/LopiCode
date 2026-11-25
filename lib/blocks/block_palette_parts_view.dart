// 设计约束（积木盒里的小零件，390 宽，浅色 + 深色）— 2026-11-25
// - 这些都是配角：搜索入口、搜索框、小标题、搜不到时的话、加星的小菜单。只用中性色（文字 / 次要文字 / 浅底），不用彩色——彩色留给积木。
// - 搜索入口：分类那一行最左边一个放大镜，触控范围 44×48，图标 20、次要色。
// - 搜索框：占满分类那一行（一行只做一件事）。36 高的胶囊，浅底无边框；左边放大镜、右边 ×（触控 44）。× ＝退出搜索。
// - 小标题：12 号、600 字重、次要色；上面留 20（第一段不留），下面留 8。
// - 搜不到 / 还没输入：一两行次要色的话，靠左，不画插图。
// - 加星菜单：贴着样品弹出，只有一项（星形图标 + 一句话）。
import 'package:lopicode/theme/tokens.dart';
import 'package:material_ui/material_ui.dart';

class BkPaletteSearchButton extends StatelessWidget {
  const BkPaletteSearchButton({super.key, required this.onTap});
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: '搜积木',
    child: GestureDetector(
      key: const ValueKey('bk-palette-search'),
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        width: 44,
        height: 48,
        child: Center(child: Icon(Icons.search_rounded, size: 20, color: context.colors.textMuted)),
      ),
    ),
  );
}

class BkPaletteSearchBar extends StatelessWidget {
  const BkPaletteSearchBar({super.key, required this.controller, required this.focusNode, required this.onChanged, required this.onClose});
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final style = Theme.of(context).textTheme.bodyMedium?.copyWith(color: c.text);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 36,
              padding: const EdgeInsets.only(left: 10, right: 12),
              decoration: BoxDecoration(color: c.surfaceMuted, borderRadius: BorderRadius.circular(18)),
              child: Row(
                children: [
                  Icon(Icons.search_rounded, size: 18, color: c.textMuted),
                  const SizedBox(width: 6),
                  Expanded(
                    child: TextField(
                      key: const ValueKey('bk-palette-search-field'),
                      controller: controller,
                      focusNode: focusNode,
                      textInputAction: TextInputAction.search,
                      cursorColor: c.accent,
                      style: style,
                      decoration: InputDecoration(
                        isDense: true,
                        isCollapsed: true,
                        contentPadding: EdgeInsets.zero,
                        filled: false,
                        hintText: '搜积木：如果、循环、加…',
                        hintStyle: style?.copyWith(color: c.textFaint),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                      ),
                      onChanged: onChanged,
                    ),
                  ),
                ],
              ),
            ),
          ),
          IconButton(
            key: const ValueKey('bk-palette-search-close'),
            tooltip: '退出搜索',
            onPressed: onClose,
            icon: Icon(Icons.close_rounded, size: 20, color: c.textMuted),
            constraints: const BoxConstraints(minWidth: 44, minHeight: 36),
            padding: EdgeInsets.zero,
          ),
        ],
      ),
    );
  }
}

class BkPaletteHeading extends StatelessWidget {
  const BkPaletteHeading(this.label, {super.key, required this.first, required this.color});
  final String label;
  final bool first;
  final Color color;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(top: first ? 0 : 20, bottom: 8),
    child: Text(
      label,
      key: ValueKey('bk-palette-heading-$label'),
      style: TextStyle(fontSize: 12, height: 1.3, fontWeight: FontWeight.w600, color: color),
    ),
  );
}

/// 搜索页没有积木可放时的话：还没输入＝教怎么搜；输入了没搜到＝说没找到。
class BkPaletteSearchHint extends StatelessWidget {
  const BkPaletteSearchHint({super.key, required this.query});
  final String query;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final q = query.trim();
    final body = Theme.of(context).textTheme.bodyMedium;
    if (q.isEmpty) {
      return Text(
        '搜积木上的字，也可以搜“循环”“判断”这样的说法。',
        key: const ValueKey('bk-palette-search-idle'),
        style: body?.copyWith(color: c.textMuted),
      );
    }
    return Column(
      key: const ValueKey('bk-palette-search-empty'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '没有找到“$q”',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: body?.copyWith(color: c.text, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        Text('换个说法试试，或者点右边的 × 回到分类里翻。', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: c.textMuted)),
      ],
    );
  }
}

/// 长按积木盒里的一样东西弹出的菜单里的一项。
enum BkCustomAction { star, create, edit, define, remove }

/// 样品旁边的小菜单：加到常用 / 从常用拿掉；是自定义积木（`custom`）的再多三项：编辑、看定义、删除。
Future<BkCustomAction?> showBkStarMenu(BuildContext box, {required bool starred, bool custom = false}) {
  final render = box.findRenderObject();
  final overlay = Overlay.of(box).context.findRenderObject();
  if (render is! RenderBox || overlay is! RenderBox || !render.attached) return Future.value();
  final at = render.localToGlobal(Offset.zero, ancestor: overlay) & render.size;
  final c = box.colors;
  PopupMenuItem<BkCustomAction> item(BkCustomAction value, String key, IconData icon, String text, {bool danger = false}) => PopupMenuItem<BkCustomAction>(
    key: ValueKey(key),
    value: value,
    height: 44,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 20, color: danger ? c.danger : c.textMuted),
        const SizedBox(width: 8),
        Text(text, style: danger ? TextStyle(color: c.danger) : null),
      ],
    ),
  );
  return showMenu<BkCustomAction>(
    context: box,
    // 项多的时候菜单往上长：贴着样品的上沿，别盖住它。
    position: RelativeRect.fromRect(at.translate(8, custom ? -196 : -52), Offset.zero & overlay.size),
    shape: custom ? RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)) : null,
    items: [
      if (custom) ...[item(BkCustomAction.edit, 'bk-palette-custom-edit', Icons.edit_outlined, '编辑这块积木'), item(BkCustomAction.define, 'bk-palette-custom-define', Icons.my_location_rounded, '看它的定义')],
      item(BkCustomAction.star, 'bk-palette-star-toggle', starred ? Icons.star_outline_rounded : Icons.star_rounded, starred ? '从常用拿掉' : '加到常用'),
      if (custom) item(BkCustomAction.remove, 'bk-palette-custom-remove', Icons.delete_outline_rounded, '删除', danger: true),
    ],
  );
}

/// “我的积木”那一页最上面：“新建积木”按钮；一块都还没有时下面多一句话说它是干什么的。
class BkPaletteCustomHead extends StatelessWidget {
  const BkPaletteCustomHead({super.key, required this.empty, required this.onNew});
  final bool empty;
  final VoidCallback onNew;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        OutlinedButton.icon(
          key: const ValueKey('bk-palette-custom-new'),
          onPressed: onNew,
          icon: const Icon(Icons.add_rounded, size: 18),
          label: const Text('新建积木'),
          style: OutlinedButton.styleFrom(minimumSize: const Size(0, 40), padding: const EdgeInsets.symmetric(horizontal: 14), shape: const StadiumBorder()),
        ),
        if (empty)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              '把常用的几块包成一块自己的积木：起个名字、写一句文案，以后拖出来就能用。',
              key: const ValueKey('bk-palette-custom-empty'),
              style: t.bodySmall?.copyWith(color: c.textMuted, height: 1.5),
            ),
          ),
      ],
    );
  }
}

/// 按下态：手指按着的时候缩到 96%、略暗。只是看的，不拦手势。
class BkPressFeel extends StatefulWidget {
  const BkPressFeel({super.key, required this.child});
  final Widget child;

  @override
  State<BkPressFeel> createState() => _PressFeelState();
}

class _PressFeelState extends State<BkPressFeel> {
  bool _down = false;

  void _set(bool v) {
    if (_down != v && mounted) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    final time = MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 90);
    return Listener(
      onPointerDown: (_) => _set(true),
      onPointerUp: (_) => _set(false),
      onPointerCancel: (_) => _set(false),
      child: AnimatedScale(
        scale: _down ? 0.96 : 1,
        duration: time,
        curve: Curves.easeOut,
        child: AnimatedOpacity(opacity: _down ? 0.82 : 1, duration: time, child: widget.child),
      ),
    );
  }
}

/// 页签条一头的渐隐：从面板底色实心过渡到透明，盖在滑出去的页签上。[shown]＝这一头还有页签。
class BkPaletteTabsFade extends StatelessWidget {
  const BkPaletteTabsFade({super.key, required this.left, required this.shown, required this.color});

  final bool left;
  final bool shown;
  final Color color;

  /// 渐隐的宽度：左边（挨着放大镜）大约盖住一个字多一点，半个字不会像被切掉；右边是面板的边，窄一些就够。
  double get width => widthOf(left: left);
  static double widthOf({required bool left}) => left ? 36 : 28;

  @override
  Widget build(BuildContext context) {
    final colors = [color, color.withValues(alpha: 0.86), color.withValues(alpha: 0)];
    return Positioned(
      left: left ? 0 : null,
      right: left ? null : 0,
      top: 0,
      bottom: 0,
      width: width,
      child: IgnorePointer(
        child: AnimatedOpacity(
          key: ValueKey(left ? 'bk-palette-tabs-fade-left' : 'bk-palette-tabs-fade-right'),
          opacity: shown ? 1 : 0,
          duration: const Duration(milliseconds: 120),
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(begin: left ? Alignment.centerLeft : Alignment.centerRight, end: left ? Alignment.centerRight : Alignment.centerLeft, colors: colors, stops: const [0, 0.3, 1]),
            ),
          ),
        ),
      ),
    );
  }
}
