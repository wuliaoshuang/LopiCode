// 设计约束（公共外观 · 390×844）— 照霜霜 2026-11-23 给的两张参考图
// - 顶部没有“一整条栏”：左、右各一个悬浮的白色圆按钮（44），中间是居中的标题。按钮有 1px 细边 + 很轻的阴影。
//   右边这一页自己的操作装进同样高度的白色胶囊里；只有一个操作时它就是一个圆。
// - 页面底色两种：对话等主页面用 bg（近白）；设置这类页面用 canvas（浅灰），上面叠白色大圆角卡片（28）。
// - 卡片里一行只做一件事：左线性图标 + 名称（可带一行弱化的说明或右侧的当前值）+ 右箭头；行间是缩进的细分隔线。
// - 底部导航只有图标、没有文字：选中 = 实心深色，未选中 = 描边、同样的深色。没有底色分界线。
import 'package:flutter/services.dart' show SystemUiOverlayStyle;
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/widgets.dart';
import 'package:material_ui/material_ui.dart';

/// 圆按钮 / 胶囊共用的外观：白底、细边、很轻的阴影。
BoxDecoration floatingDecoration(AppColors c, {BorderRadius? radius}) => BoxDecoration(
  color: c.surface,
  shape: radius == null ? BoxShape.circle : BoxShape.rectangle,
  borderRadius: radius,
  border: Border.all(color: c.border),
  boxShadow: const [BoxShadow(color: Color(0x0F000000), blurRadius: 12, offset: Offset(0, 2))],
);

/// 悬浮的白色圆按钮（顶栏左右两侧）。
class RoundIconButton extends StatelessWidget {
  const RoundIconButton({super.key, required this.icon, required this.tooltip, required this.onPressed, this.size = kSize});
  static const double kSize = 44;
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      width: size,
      height: size,
      decoration: floatingDecoration(c),
      child: IconButton(
        tooltip: tooltip,
        padding: EdgeInsets.zero,
        onPressed: onPressed,
        icon: Icon(icon, size: 22, color: c.text),
      ),
    );
  }
}

/// 把这一页的操作（若干 IconButton / PopupMenuButton）装进一个白色胶囊。
class ActionPill extends StatelessWidget {
  const ActionPill({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      height: RoundIconButton.kSize,
      constraints: const BoxConstraints(minWidth: RoundIconButton.kSize),
      decoration: floatingDecoration(c, radius: BorderRadius.circular(RoundIconButton.kSize / 2)),
      clipBehavior: Clip.antiAlias,
      child: IconTheme.merge(
        data: IconThemeData(color: c.text, size: 22),
        child: IconButtonTheme(
          data: IconButtonThemeData(
            style: IconButton.styleFrom(
              minimumSize: const Size(42, 42),
              fixedSize: const Size(42, 42),
              padding: EdgeInsets.zero,
              foregroundColor: c.text,
              disabledForegroundColor: c.textFaint.withValues(alpha: 0.45),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: children),
        ),
      ),
    );
  }
}

/// 统一的顶部：左圆按钮 + 居中标题 + 右侧操作胶囊。
///
/// [fade] 为真时不画实底，而是一条从页面底色到透明的渐变——配合 `extendBodyBehindAppBar`，内容从按钮下面滚过去并渐隐。
class PageBar extends StatelessWidget implements PreferredSizeWidget {
  const PageBar({super.key, this.title, this.titleText, this.subtitle, this.leading, this.actions, this.bottom, this.fade = false, this.background, this.backTooltip = '返回'});

  static const double kHeight = 64;

  /// 自定义的标题控件；和 [titleText] 二选一。
  final Widget? title;
  final String? titleText;
  final String? subtitle;

  /// 左边的按钮；不传时能返回就是返回按钮。
  final Widget? leading;
  final List<Widget>? actions;
  final PreferredSizeWidget? bottom;
  final bool fade;
  final Color? background;
  final String backTooltip;

  @override
  Size get preferredSize => Size.fromHeight(kHeight + (bottom?.preferredSize.height ?? 0));

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final bg = background ?? Theme.of(context).scaffoldBackgroundColor;
    final lead = leading ?? (Navigator.canPop(context) ? RoundIconButton(icon: Icons.arrow_back_ios_new_rounded, tooltip: backTooltip, onPressed: () => Navigator.maybePop(context)) : null);
    final acts = actions?.where((w) => w is! SizedBox).toList() ?? const <Widget>[];
    Widget? middle = title;
    if (middle == null && titleText != null) {
      middle = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            titleText!,
            style: t.titleLarge?.copyWith(fontWeight: FontWeight.w400),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (subtitle != null && subtitle!.isNotEmpty)
            Text(
              subtitle!,
              style: t.bodySmall?.copyWith(color: c.textFaint),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
        ],
      );
    } else if (middle != null) {
      middle = DefaultTextStyle.merge(
        style: t.titleLarge?.copyWith(fontWeight: FontWeight.w400),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        child: middle,
      );
    }
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: Theme.of(context).brightness == Brightness.light ? SystemUiOverlayStyle.dark : SystemUiOverlayStyle.light,
      child: DecoratedBox(
        decoration: fade
            ? BoxDecoration(
                gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [bg, bg.withValues(alpha: 0.92), bg.withValues(alpha: 0)], stops: const [0, 0.45, 1]),
              )
            : BoxDecoration(color: bg),
        child: SafeArea(
          bottom: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: kHeight,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Space.x4),
                  child: NavigationToolbar(
                    leading: lead,
                    middle: middle,
                    trailing: acts.isEmpty ? null : ActionPill(children: acts),
                    centerMiddle: true,
                    middleSpacing: Space.x3,
                  ),
                ),
              ),
              ?bottom,
            ],
          ),
        ),
      ),
    );
  }
}

/// “卡片分组”页面里的一张白色大圆角卡片。[children] 之间自动加缩进的细分隔线。
class GroupCard extends StatelessWidget {
  const GroupCard({super.key, required this.children, this.padding, this.dividers = true, this.margin});
  final List<Widget> children;
  final EdgeInsetsGeometry? padding;
  final bool dividers;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0 && dividers) rows.add(Divider(height: 1, thickness: 1, indent: Space.x4, endIndent: Space.x4, color: c.border));
      rows.add(children[i]);
    }
    return Container(
      margin: margin ?? const EdgeInsets.only(bottom: Space.x4),
      decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(Radii.card)),
      clipBehavior: Clip.antiAlias,
      child: Material(
        type: MaterialType.transparency,
        child: Padding(
          padding: padding ?? EdgeInsets.zero,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: rows),
        ),
      ),
    );
  }
}

/// 卡片里的一行：线性图标 + 名称 + （当前值）+ 右箭头。
class GroupRow extends StatelessWidget {
  const GroupRow({super.key, required this.icon, required this.title, this.value, this.subtitle, this.onTap, this.trailing, this.danger = false});
  final IconData icon;
  final String title;

  /// 右侧弱化显示的当前值。
  final String? value;

  /// 名称下面的一行说明。
  final String? subtitle;
  final VoidCallback? onTap;

  /// 代替右箭头的控件（开关等）。
  final Widget? trailing;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 64),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.x4, vertical: Space.x3),
          child: Row(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Space.x1),
                child: Icon(icon, size: 26, color: danger ? c.danger : c.text),
              ),
              const SizedBox(width: Space.x4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: t.bodyLarge?.copyWith(fontSize: FontSize.lg, height: 1.3, color: danger ? c.danger : c.text),
                    ),
                    if (subtitle != null && subtitle!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          subtitle!,
                          style: t.bodySmall?.copyWith(color: c.textFaint),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                ),
              ),
              if (value != null && value!.isNotEmpty) ...[
                const SizedBox(width: Space.x3),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 132),
                  child: Text(
                    value!,
                    style: t.bodyMedium?.copyWith(color: c.textFaint),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.end,
                  ),
                ),
              ],
              const SizedBox(width: Space.x2),
              trailing ?? (onTap == null ? const SizedBox.shrink() : Icon(Icons.chevron_right, size: 24, color: c.textFaint.withValues(alpha: 0.7))),
            ],
          ),
        ),
      ),
    );
  }
}

/// 卡片组上方的小标题。
class GroupLabel extends StatelessWidget {
  const GroupLabel(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(Space.x4, Space.x2, Space.x4, Space.x2),
    child: Text(text, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: context.colors.textFaint)),
  );
}

/// 底部导航的一项。
class BottomNavItem {
  const BottomNavItem({required this.label, required this.icon, required this.selectedIcon});
  final String label;
  final Widget icon;
  final Widget selectedIcon;
}

/// 只有图标的底部导航。键盘弹出时它留在键盘下面（由外层 Scaffold 保证），不会被顶起来。
class IconBottomNav extends StatelessWidget {
  const IconBottomNav({super.key, required this.items, required this.current, required this.onTap});
  static const double kHeight = 56;
  final List<BottomNavItem> items;

  /// 当前选中项；不在五项里的页面（预览、运行环境）传 -1。
  final int current;
  final void Function(int index) onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ColoredBox(
      color: c.bg,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: kHeight,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.x6),
            child: Row(
              children: [
                for (var i = 0; i < items.length; i++)
                  Expanded(
                    child: Semantics(
                      key: ValueKey('nav-$i'),
                      selected: i == current,
                      button: true,
                      child: Tooltip(
                        message: items[i].label,
                        child: InkResponse(
                          radius: 28,
                          onTap: () => onTap(i),
                          child: SizedBox(
                            height: kHeight,
                            child: IconTheme(
                              data: IconThemeData(size: 26, color: c.text),
                              child: Center(child: i == current ? items[i].selectedIcon : items[i].icon),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 终端图标：圆角方框里一个 “>_”。Material 图标里它没有成对的描边 / 实心版本，所以自己画。
class TerminalGlyph extends StatelessWidget {
  const TerminalGlyph({super.key, required this.filled});
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final theme = IconTheme.of(context);
    final size = theme.size ?? 24;
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _TerminalPainter(color: theme.color ?? context.colors.text, knockout: context.colors.bg, filled: filled),
      ),
    );
  }
}

class _TerminalPainter extends CustomPainter {
  _TerminalPainter({required this.color, required this.knockout, required this.filled});
  final Color color;
  final Color knockout;
  final bool filled;

  @override
  void paint(Canvas canvas, Size size) {
    final u = size.width / 24;
    final box = RRect.fromRectAndRadius(Rect.fromLTRB(3 * u, 4 * u, 21 * u, 20 * u), Radius.circular(4 * u));
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2 * u
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = color;
    if (filled) {
      canvas.drawRRect(box, Paint()..color = color);
      stroke.color = knockout;
    } else {
      canvas.drawRRect(box, stroke);
    }
    canvas.drawPath(
      Path()
        ..moveTo(7.5 * u, 9 * u)
        ..lineTo(10.5 * u, 12 * u)
        ..lineTo(7.5 * u, 15 * u),
      stroke,
    );
    canvas.drawLine(Offset(12.5 * u, 15 * u), Offset(16.5 * u, 15 * u), stroke);
  }

  @override
  bool shouldRepaint(_TerminalPainter old) => old.color != color || old.filled != filled || old.knockout != knockout;
}

/// “卡片分组”页面的正文：把一串平铺的控件按 [SectionLabel] 切开，
/// 每个小标题留在浅灰底上，它后面的控件装进一张白色大圆角卡片。
///
/// [inner] 是卡片内边距：控件自己带左右边距（ListTile 之类）时用默认值；表单这类不带边距的传 `EdgeInsets.all(16)`。
class SectionedList extends StatelessWidget {
  const SectionedList({super.key, required this.children, this.inner = const EdgeInsets.symmetric(vertical: Space.x2), this.bottom = Space.x8, this.listKey});
  final List<Widget> children;
  final EdgeInsets inner;
  final double bottom;
  final Key? listKey;

  @override
  Widget build(BuildContext context) {
    final out = <Widget>[];
    var group = <Widget>[];
    void flush() {
      if (group.isEmpty) return;
      out.add(GroupCard(dividers: false, padding: inner, children: group));
      group = <Widget>[];
    }

    for (final w in children) {
      if (w is SectionLabel) {
        flush();
        out.add(GroupLabel(w.text));
      } else {
        group.add(w);
      }
    }
    flush();
    return ListView(key: listKey, padding: EdgeInsets.fromLTRB(Space.x4, Space.x2, Space.x4, bottom), children: out);
  }
}
