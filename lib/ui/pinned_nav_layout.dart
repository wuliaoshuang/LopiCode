// 设计约束（底部导航钉在屏幕底 · 390×844）— 2026-11-24 霜霜真机反馈第 4 条
// - 底部导航永远画在屏幕最底部的原位（含底部安全区）：软键盘升起时不隐藏、不被顶起、没有升降动画，键盘直接盖在它上面。
//   所以键盘收起的任何一帧，导航都已经在原位，不会“从底下冒出来”。
// - 页面内容的底边 = 屏幕底 − max(键盘高度, 导航高度 + 底部安全区)：没键盘时内容贴着导航上沿；
//   键盘比导航高的那一刻起，内容贴着键盘上沿，跟着键盘动画逐帧走，中间没有空白也没有重叠。
// - 键盘高度（viewInsets.bottom）本身就从屏幕底算起、已含底部安全区，所以两者取大者，不相加：安全区不会被算两次，也不会漏。
// - 里面的页面看到的是“已经避让完”的环境（底部键盘占位、底部安全区都是 0），不用也不该再自己避让一次。
// - 提示条（SnackBar）仍由这一层的 Scaffold 显示：没键盘时在导航上方，有键盘时在键盘上方。
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

class PinnedNavLayout extends StatelessWidget {
  const PinnedNavLayout({super.key, required this.nav, required this.navHeight, required this.body});

  /// 底部导航。它自己用 SafeArea 留底部安全区（IconBottomNav 就是这样）。
  final Widget nav;

  /// 导航不含底部安全区的高度。
  final double navHeight;
  final Widget body;

  /// 页面内容底边要让开多少（从屏幕底算起）。
  static double bottomObstruction(MediaQueryData media, double navHeight) => math.max(media.viewInsets.bottom, navHeight + media.viewPadding.bottom);

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final navExtent = navHeight + media.viewPadding.bottom;
    return Stack(
      children: [
        // 把“要让开的高度”当作键盘占位交给 Scaffold：它照常缩短内容区、托起提示条，并把占位从里面页面的环境里去掉。
        Positioned.fill(
          child: MediaQuery(
            data: media.copyWith(
              viewInsets: media.viewInsets.copyWith(bottom: bottomObstruction(media, navHeight)),
              padding: media.padding.copyWith(bottom: 0),
              viewPadding: media.viewPadding.copyWith(bottom: 0),
            ),
            child: Scaffold(body: body),
          ),
        ),
        // 导航：键盘升起时系统会把 padding.bottom 清零，这里还给它原本的底部安全区，高度和位置才不会变。
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: navExtent,
          child: MediaQuery(
            data: media.copyWith(
              viewInsets: media.viewInsets.copyWith(bottom: 0),
              padding: media.padding.copyWith(bottom: media.viewPadding.bottom),
            ),
            // 导航不在 Scaffold 里了，按钮的点按反馈需要一层 Material 垫着。
            child: Material(type: MaterialType.transparency, child: nav),
          ),
        ),
      ],
    );
  }
}
