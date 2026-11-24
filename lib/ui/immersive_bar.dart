// 设计约束（“搭建”相关页面的沉浸式顶栏 · 390×844，浅色 + 深色）— 2026-11-24 按霜霜真机反馈做
// - 只给有画布的页面用（低代码画布、积木逻辑、后端积木、编辑组件）。别的页面还是 chrome.dart 的 PageBar，不许换成这个。
// - 顶栏自己什么都不画：没有底色、没有分隔线、没有整条阴影。画布从屏幕最顶（状态栏后面）铺起，顶栏浮在它上面。
// - 一行三样，都是悬浮的（卡片色底 + 细边 + 很轻的阴影，和 PageBar 的圆按钮 / 胶囊同一套）：
//   左圆按钮（汉堡 / 返回，44）、贴着它的标题小胶囊（标题 + 可选的一行小字，太长省略号截断）、右边这一页的操作胶囊。
//   标题放进小胶囊是因为它下面会有积木 / 控件滑过去，光有文字看不清；对话等页面的标题仍然只有文字。
// - 三样之间的空白是透明的，手指落在那里等于落在画布上（可以拖画布、点积木）；按钮照常可点，点击区域 44。
// - 状态栏透明，图标颜色跟浅 / 深色主题走。
// - 用法：页面不设 Scaffold.appBar，把它放在 Stack 最上面一层 `Positioned(top: 0, left: 0, right: 0)`；
//   画布把 [extentOf]（状态栏 + 64）当成“上面被盖住的高度”来算初始位置和定位。
import 'package:flutter/services.dart' show SystemUiOverlayStyle;
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/chrome.dart';
import 'package:lopicode/ui/shell.dart';
import 'package:material_ui/material_ui.dart';

class ImmersiveBar extends StatelessWidget {
  const ImmersiveBar({super.key, required this.title, this.subtitle, this.actions});

  /// 不算状态栏的高度（和 [PageBar] 一样）。
  static const double kHeight = PageBar.kHeight;

  /// 三样悬浮的东西之间隔多远。比 PageBar 的 12 小一档：右边有四个按钮时（后端积木页），
  /// 标题小胶囊里的那行小字（“Node.js · 7 个接口”）才放得下、不被截断。
  static const double kGap = Space.x2;

  /// 标题小胶囊里文字离左右边多远（理由同上：再大，四个按钮时小字就放不下了）。
  static const double kTitleInset = 10;

  final String title;

  /// 标题下面的一行小字；在外壳里不传时是工作区的名字（和 [ShellAppBar] 一样）。
  final String? subtitle;
  final List<Widget>? actions;

  /// 悬浮顶栏的下沿离屏幕顶多远（状态栏 + [kHeight]）：画布把这一段当成被盖住的。
  static double extentOf(BuildContext context) => MediaQuery.paddingOf(context).top + kHeight;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final light = Theme.of(context).brightness == Brightness.light;
    final lead = shellLeading(context);
    final acts = actions?.where((w) => w is! SizedBox).toList() ?? const <Widget>[];
    final sub = subtitle ?? ShellScope.maybeOf(context)?.projectName;
    const radius = BorderRadius.all(Radius.circular(RoundIconButton.kSize / 2));
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: (light ? SystemUiOverlayStyle.dark : SystemUiOverlayStyle.light).copyWith(statusBarColor: Colors.transparent),
      // 这一层往下没有任何会“接住手指”的整块东西：空白处的触摸直接落到下面的画布上。
      child: Padding(
        padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top),
        child: SizedBox(
          height: kHeight,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.x4),
            child: Row(
              children: [
                if (lead != null) ...[lead, const SizedBox(width: kGap)],
                Expanded(
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: RoundIconButton.kSize, maxHeight: RoundIconButton.kSize),
                      child: DecoratedBox(
                        key: const ValueKey('immersive-title'),
                        decoration: floatingDecoration(c, radius: radius),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: kTitleInset),
                          child: Align(
                            widthFactor: 1,
                            alignment: AlignmentDirectional.centerStart,
                            child: BarTitle(title: title, subtitle: sub),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                if (acts.isNotEmpty) ...[const SizedBox(width: kGap), ActionPill(children: acts)],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 把页面正文和悬浮顶栏叠起来：正文铺满（从屏幕最顶开始），顶栏浮在最上面。
///
/// 正文里的画布自己用 [ImmersiveBar.extentOf] 让开顶栏；不是画布的正文（空状态、转圈）居中摆着，不用管。
class ImmersiveBody extends StatelessWidget {
  const ImmersiveBody({super.key, required this.bar, required this.child});
  final ImmersiveBar bar;
  final Widget child;

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      child,
      Positioned(top: 0, left: 0, right: 0, child: bar),
    ],
  );
}
