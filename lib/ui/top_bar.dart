// 设计约束（全应用唯一的一套顶栏 · 390×844，浅色 + 深色）— 2026-11-24 霜霜真机反馈第二轮第 5 条
// - 所有整页的顶栏都是 PageBar（外壳里的页面经 shell.dart 的 ShellAppBar 套一层，只是多了汉堡按钮和工作区名）。不许某一页另画一个。
// - 高度一律 64（不含状态栏）——就是“添加渠道”页那个高度。左圆按钮 44，离左边 16、上下各 10。
// - 悬浮：顶栏没有底色、没有分隔线、没有整条阴影；左圆按钮和右边的操作胶囊是悬浮的小块（卡片色底 + 1px 细边 + 很轻的阴影），
//   标题只有文字（14 / 常规字重，贴着左按钮左对齐，可带一行 12 的弱色小字，太长省略号截断）。
// - 页面内容从屏幕最顶铺起（Scaffold.extendBodyBehindAppBar），起始留出 PageBar.insetOf（状态栏 + 64）；滚动时内容从顶栏下面穿过。
//   不能滚的正文（终端、编辑器、固定页签）用 BelowBar 整块摆在顶栏下沿之下，不钻到按钮下面。
// - 可读性只有一种做法：顶栏后面一层从页面底色到透明的渐隐遮罩（BarScrim）。状态栏那一段是实的页面底色（状态栏干净），
//   标题那一段遮 98%，从按钮下沿附近开始淡出，到顶栏下沿再往下 20 处全透明。不给标题加胶囊（画布页也不加）。
// - 遮罩不接手指：顶栏空白处的触摸落到下面的内容上（画布页可以在那儿拖画布）。按钮点击区域 44。
// - 顶栏里所有图标按钮按下的反馈是同一个：正好盖住按钮的圆（44）。按钮自己定大小，不跟着外面给的高度被拉长。
// - 状态栏透明，图标颜色跟浅 / 深色主题走。
import 'dart:math' as math;

import 'package:flutter/services.dart' show SystemUiOverlayStyle;
import 'package:lopicode/theme/breakpoints.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:material_ui/material_ui.dart';

/// 圆按钮 / 胶囊共用的外观：卡片色底、细边、很轻的阴影。
BoxDecoration floatingDecoration(AppColors c, {BorderRadius? radius}) => BoxDecoration(
  color: c.barButtonBg,
  shape: radius == null ? BoxShape.circle : BoxShape.rectangle,
  borderRadius: radius,
  border: Border.all(color: c.border, width: c.hairline),
  boxShadow: [BoxShadow(color: c.shadowOf(0x0F / 255), blurRadius: 12, offset: const Offset(0, 2))],
);

/// 顶栏里所有图标按钮共用的样子：一个 44 的圆，按下的反馈正好盖住这个圆。
///
/// 左边的圆按钮和右边胶囊里的按钮都用它，所以两边按下去是一模一样的。
ButtonStyle barIconButtonStyle(AppColors c) => IconButton.styleFrom(
  minimumSize: const Size.square(RoundIconButton.kSize),
  fixedSize: const Size.square(RoundIconButton.kSize),
  padding: EdgeInsets.zero,
  shape: const CircleBorder(),
  foregroundColor: c.text,
  disabledForegroundColor: c.textFaint.withValues(alpha: 0.45),
  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
  visualDensity: VisualDensity.standard,
);

/// 悬浮的圆按钮（顶栏左侧的汉堡 / 返回）。
///
/// 大小由自己定：外面给多高（顶栏是 64）它都只占中间 [size] 见方，按下的反馈也就只在这个圆里。
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
    return Center(
      widthFactor: 1,
      heightFactor: 1,
      child: SizedBox.square(
        dimension: size,
        child: DecoratedBox(
          decoration: floatingDecoration(c),
          child: IconButton(
            tooltip: tooltip,
            style: barIconButtonStyle(c).copyWith(minimumSize: WidgetStatePropertyAll(Size.square(size)), fixedSize: WidgetStatePropertyAll(Size.square(size))),
            onPressed: onPressed,
            icon: Icon(icon, size: 22),
          ),
        ),
      ),
    );
  }
}

/// 把这一页的操作（若干 IconButton / PopupMenuButton）装进一个胶囊。
class ActionPill extends StatelessWidget {
  const ActionPill({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    const radius = BorderRadius.all(Radius.circular(RoundIconButton.kSize / 2));
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: RoundIconButton.kSize, minHeight: RoundIconButton.kSize, maxHeight: RoundIconButton.kSize),
      child: DecoratedBox(
        decoration: floatingDecoration(c, radius: radius),
        child: ClipRRect(
          borderRadius: radius,
          child: IconTheme.merge(
            data: IconThemeData(color: c.text, size: 22),
            child: IconButtonTheme(
              data: IconButtonThemeData(style: barIconButtonStyle(c)),
              child: Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: children),
            ),
          ),
        ),
      ),
    );
  }
}

/// 顶栏的标题：只有文字，没有底色、描边、阴影。一行标题 + 可选的一行更淡的小字，左对齐。
///
/// 它只是告诉人“这是哪儿”，不抢内容的戏，所以用常规字重、不比正文大。本身不可点。
class BarTitle extends StatelessWidget {
  const BarTitle({super.key, required this.title, this.subtitle});
  final String title;
  final String? subtitle;

  /// 标题一行的样子（自定义标题控件也用它）。
  static TextStyle? titleStyle(BuildContext context) => Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w400, height: 1.3);

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final sub = subtitle;
    return Semantics(
      header: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: titleStyle(context), maxLines: 1, overflow: TextOverflow.ellipsis),
          if (sub != null && sub.isNotEmpty)
            Text(
              sub,
              style: t.bodySmall?.copyWith(color: context.colors.textFaint, height: 1.25),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
        ],
      ),
    );
  }
}

/// 全应用唯一的顶栏：左圆按钮 + 贴着它左对齐的标题（只有文字）+ 右侧操作胶囊，全部悬浮在页面上。
///
/// 约定（2026-11-24 霜霜真机反馈第二轮，test/topbar_unified_test.dart 守着）：
/// - 高度一律 [kHeight]（不含状态栏）；自己不画底色、不画分隔线。
/// - 页面的 Scaffold 一律 `extendBodyBehindAppBar: true`：内容从屏幕最顶铺起，
///   用 [insetOf] 留出“状态栏 + 顶栏”的起始内边距，滚动时从顶栏下面穿过。
/// - 可读性：顶栏后面垫一层从页面底色（[background]）到透明的渐隐遮罩（[BarScrim]）。内容没滚上来时它和页面同色、看不出来；
///   滚上来的内容在标题后面淡出，不和标题糊在一起。遮罩不接手指，顶栏空白处的触摸落到下面的内容上。
class PageBar extends StatelessWidget implements PreferredSizeWidget {
  const PageBar({super.key, this.title, this.titleText, this.subtitle, this.leading, this.actions, this.bottom, this.background, this.backTooltip = '返回'});

  static const double kHeight = 64;

  /// 内容区顶部要留多少，才不被悬浮顶栏挡住（状态栏 + [kHeight] + 顶栏下面固定的那一条 [extra]）。全应用只从这里取。
  ///
  /// 在页面自己的 build 里（Scaffold 外面）和在 Scaffold 的正文里问，答案一样：
  /// 正文里 Scaffold 已经把状态栏从 viewPadding 里拿掉、把“状态栏 + 顶栏（连同它的 bottom）”放进了 padding.top，所以两边取大的。
  static double insetOf(BuildContext context, {double extra = 0}) {
    final mq = MediaQuery.of(context);
    return math.max(mq.viewPadding.top + kHeight, mq.padding.top) + BarExtra.of(context) + extra;
  }

  /// 自定义的标题控件；和 [titleText] 二选一。
  final Widget? title;
  final String? titleText;
  final String? subtitle;

  /// 左边的按钮；不传时能返回就是返回按钮。
  final Widget? leading;
  final List<Widget>? actions;
  final PreferredSizeWidget? bottom;

  /// 这一页的底色（渐隐遮罩用它）；不传是主题的页面底色。
  final Color? background;
  final String backTooltip;

  @override
  Size get preferredSize => Size.fromHeight(kHeight + (bottom?.preferredSize.height ?? 0));

  @override
  Widget build(BuildContext context) {
    final bg = background ?? Theme.of(context).scaffoldBackgroundColor;
    final lead = leading ?? (Navigator.canPop(context) ? RoundIconButton(icon: Icons.arrow_back_ios_new_rounded, tooltip: backTooltip, onPressed: () => Navigator.maybePop(context)) : null);
    final acts = actions?.where((w) => w is! SizedBox).toList() ?? const <Widget>[];
    Widget? middle = title;
    if (middle == null && titleText != null) {
      middle = BarTitle(title: titleText!, subtitle: subtitle);
    } else if (middle != null) {
      middle = DefaultTextStyle.merge(style: BarTitle.titleStyle(context), maxLines: 1, overflow: TextOverflow.ellipsis, child: middle);
    }
    final light = Theme.of(context).brightness == Brightness.light;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: (light ? SystemUiOverlayStyle.dark : SystemUiOverlayStyle.light).copyWith(statusBarColor: Colors.transparent),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            bottom: -(BarScrim.kTail + BarExtra.of(context)),
            child: BarScrim(color: bg, statusBar: MediaQuery.paddingOf(context).top),
          ),
          SafeArea(
            bottom: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  height: kHeight,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: Space.x4),
                    // 一行：左按钮、标题（占满剩下的宽度，放不下就截断）、这一页的操作。
                    child: Row(
                      children: [
                        if (lead != null) ...[lead, const SizedBox(width: Space.x3)],
                        Expanded(
                          child: middle == null
                              ? const SizedBox.shrink()
                              : ConstrainedBox(
                                  constraints: const BoxConstraints(minHeight: RoundIconButton.kSize),
                                  child: Align(alignment: AlignmentDirectional.centerStart, child: middle),
                                ),
                        ),
                        if (acts.isNotEmpty) ...[const SizedBox(width: Space.x3), ActionPill(children: acts)],
                      ],
                    ),
                  ),
                ),
                ?bottom,
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 顶栏后面的渐隐遮罩：状态栏那一段是页面底色（实的），标题那一段几乎是实的，往下到顶栏下沿再多 [kTail] 淡到全透明。
/// 没有边、没有线；不接手指。
class BarScrim extends StatelessWidget {
  const BarScrim({super.key, required this.color, required this.statusBar});

  /// 渐隐比顶栏下沿多伸出去的一段（让边缘是“淡出”而不是一条线）。
  static const double kTail = 20;

  /// 标题那一段遮掉多少（1＝全遮）。
  static const double kTitleAlpha = 0.98;
  final Color color;
  final double statusBar;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: LayoutBuilder(
      builder: (context, box) {
        final h = box.maxHeight;
        // 按钮的下沿（状态栏 + 54）之上基本是实的，从标题文字的下沿附近开始淡出。
        final solidTo = ((h - BarScrim.kTail - 18) / h).clamp(0.0, 1.0);
        final status = (statusBar / h).clamp(0.0, solidTo);
        return DecoratedBox(
          key: const ValueKey('bar-scrim'),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                color,
                color.withValues(alpha: kTitleAlpha),
                color.withValues(alpha: kTitleAlpha),
                color.withValues(alpha: 0),
              ],
              stops: [status, status, solidTo, 1],
            ),
          ),
        );
      },
    ),
  );
}

/// 顶栏下面还固定着一条悬浮的东西（搭建页的“页面 / 后端”切换条）时，把它占的高度告诉里面的页面：
/// [PageBar.insetOf] 会把它算进去，顶栏的渐隐遮罩也跟着盖到它下面。
class BarExtra extends InheritedWidget {
  const BarExtra({super.key, required this.extra, required super.child});
  final double extra;

  static double of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<BarExtra>()?.extra ?? 0;

  @override
  bool updateShouldNotify(BarExtra old) => extra != old.extra;
}

/// 最简单的一页：底色 + 悬浮顶栏（只有返回和标题）+ 正文。正文自己留 [PageBar.insetOf]。
class BarPage extends StatelessWidget {
  const BarPage({super.key, required this.background, required this.title, required this.body});
  final Color background;
  final Widget title;
  final Widget body;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: background,
      extendBodyBehindAppBar: true,
      appBar: PageBar(background: background, title: title),
      body: ContentWidth(child: body),
    );
  }
}

/// 不能从顶栏下面滚过去的正文（终端、编辑器、带固定页签的页面）：整块从顶栏下沿开始摆（顶栏带 bottom 时从 bottom 的下沿）。
class BelowBar extends StatelessWidget {
  const BelowBar({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(top: PageBar.insetOf(context)),
    child: child,
  );
}
