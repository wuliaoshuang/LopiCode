// 设计约束（左侧竖排导航 · 中屏、宽屏）— 2026-11-28 霜霜：“适配平板”
// - 窗口宽到 600 以上，底部导航换成左边一列：还是那五项、同样的图标和短标签、同样的颜色规矩（选中 navActive、未选中 navInactive）、
//   点了同样短震一下。项的 key 也和底部导航一样（nav-0…nav-4）。
// - 这一列贴着屏幕左边，从状态栏下面排起；键盘弹出不动它（它在 Scaffold 外面）。窗口很矮（分屏）排不下时这一列自己能滚。
// - 右边是页面；[side] 是常驻在导航和页面之间的一栏（宽屏的对话页放侧边栏：工作区、对话列表、设置）。
// - 页面看到的环境里左边安全区已经去掉（导航占了），底部键盘占位由这一层的 Scaffold 接走，和手机上外层 Scaffold 的做法一样。
import 'package:lopicode/theme/breakpoints.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/chrome.dart';
import 'package:lopicode/ui/nav_haptics.dart';
import 'package:material_ui/material_ui.dart';

class IconNavRail extends StatelessWidget {
  const IconNavRail({super.key, required this.items, required this.current, required this.onTap});
  static const double kItemHeight = 64;
  final List<BottomNavItem> items;

  /// 当前选中项；不在五项里的页面（预览、运行环境）传 -1。
  final int current;
  final void Function(int index) onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ColoredBox(
      color: c.navBg,
      child: SafeArea(
        right: false,
        child: SizedBox(
          width: Breakpoints.rail,
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: Space.x2),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < items.length; i++)
                  Semantics(
                    key: ValueKey('nav-$i'),
                    label: items[i].label,
                    selected: i == current,
                    button: true,
                    child: Tooltip(
                      message: items[i].label,
                      child: InkResponse(
                        radius: 32,
                        onTap: () {
                          navTapHaptic(); // 和底部导航一样：点哪一项都短震一下
                          onTap(i);
                        },
                        child: SizedBox(
                          height: kItemHeight,
                          width: Breakpoints.rail,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              IconTheme(
                                data: IconThemeData(size: 24, color: i == current ? c.navActive : c.navInactive),
                                child: Center(child: i == current ? items[i].selectedIcon : items[i].icon),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                items[i].label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: FontSize.xs, height: 1.1, color: i == current ? c.navActive : c.navInactive, fontWeight: i == current ? FontWeight.w600 : FontWeight.w400),
                              ),
                            ],
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

/// 中屏、宽屏的外壳排法：左边竖排导航，可选的常驻一栏，右边是页面。
class RailNavLayout extends StatelessWidget {
  const RailNavLayout({super.key, required this.nav, required this.body, this.side});
  final Widget nav;

  /// 常驻在导航右边的一栏（宽 [Breakpoints.side]）；不传就没有。
  final Widget? side;
  final Widget body;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 导航不在 Scaffold 里，按钮的点按反馈需要一层 Material 垫着。
        Material(type: MaterialType.transparency, child: nav),
        Expanded(
          child: MediaQuery.removePadding(
            context: context,
            removeLeft: true,
            child: Scaffold(
              body: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (side != null) ...[SizedBox(key: const ValueKey('shell-side'), width: Breakpoints.side, child: side), VerticalDivider(width: 1, thickness: 1, color: c.border)],
                  Expanded(child: body),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
