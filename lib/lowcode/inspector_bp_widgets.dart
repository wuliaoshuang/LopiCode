// 设计约束（低代码 · 合一面板顶上的“屏宽”提示条 · 390×844）
// - 只在画布切到“平板”或“桌面”时出现；手机（默认）时不占地方。
// - 一行只做一件事：说清楚“现在改的记到哪儿”。浅强调底（和“状态”的提示条一个样子，都是“你现在改的不是平常那份”）。
//   “样式”页：只记这一档和手机不一样的地方，右边“清掉”（这一档写过东西才有）。
//   “样式”页上又选了一个状态（按下 / 禁用…）：屏宽、状态两件事并成这一条说（第四轮 B6，原来是上下两条），
//   放在状态那一行药丸下面（顶替“状态”自己的那条提示），右边的“清掉”清的是这个状态。
//   “常用”页（第四轮 B1 起）：样子类的设置只记这一档；内容类的不分屏宽，那几行的名字下面有一行小灰字“不分屏宽”
//   （[LcBpRowScope] 告诉每一行现在是哪一档，样子类的行用 [LcPerBp] 包着）。右边“清掉”同“样式”页。
// - 取用的 tokens：Space.x1/x2/x3、Radii.sm、accentSoft、text。
import 'package:lopicode/lowcode/responsive.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:material_ui/material_ui.dart';

class LcBpNote extends StatelessWidget {
  const LcBpNote({super.key, required this.bp, required this.onStylePage, required this.filled, this.onClear, this.stateLabel, this.stateSplit = false, this.stateFilled = false, this.onClearState});

  /// 画布现在看的那一档（tablet / desktop）。
  final String bp;

  /// 现在是不是“样式”页。
  final bool onStylePage;

  /// 这一档给这个组件写过东西没有。
  final bool filled;
  final VoidCallback? onClear;

  /// 正在改某个状态的样子时它叫什么（状态样式不分屏宽，要说一声）；平时是 null。
  final String? stateLabel;

  /// 这个状态的样子能不能分屏宽设（按下 / 禁用 / 聚焦能；类名成立那种不能）。
  final bool stateSplit;

  /// 正在改某个状态时，这一条同时顶替“状态”那条提示（第四轮 B6：两条并成一条）：这个状态写过东西没有、点“清掉”做什么。
  final bool stateFilled;
  final VoidCallback? onClearState;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final name = lcBpLabel(bp);
    final text = !onStylePage
        ? '现在改的样子（间距、圆角、字号、对齐、颜色…）只在$name及更宽的屏上生效（≥${kLcBpMinWidth[bp]}）。标着“不分屏宽”的在哪儿改都一样。'
        : stateLabel != null && stateSplit
        ? '现在改的是“$stateLabel”时的样子，只在$name及更宽的屏上生效（≥${kLcBpMinWidth[bp]}）：只记和手机上不一样的地方。'
        : stateLabel != null
        ? '“$stateLabel”时的样子不分屏宽：现在改的在手机上也生效。'
        : '现在改的只在$name及更宽的屏上生效（≥${kLcBpMinWidth[bp]}）：只记和手机不一样的地方。';
    final Widget action = stateLabel != null
        ? (stateFilled ? TextButton(key: const Key('lc-state-clear'), onPressed: onClearState, child: const Text('清掉')) : const SizedBox(height: 40))
        : (filled ? TextButton(key: const Key('lc-bp-clear'), onPressed: onClear, child: const Text('清掉')) : const SizedBox(height: 40));
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.x3),
      child: Container(
        key: const Key('lc-bp-note'),
        padding: const EdgeInsets.fromLTRB(Space.x3, Space.x1, Space.x1, Space.x1),
        decoration: BoxDecoration(color: c.accentSoft, borderRadius: BorderRadius.circular(Radii.sm)),
        child: Row(
          children: [
            Expanded(
              child: Text(text, style: t.bodySmall?.copyWith(color: c.text)),
            ),
            action,
          ],
        ),
      ),
    );
  }
}

/// 告诉“常用”页里的每一行：画布现在看的是哪一档（null＝手机）。
class LcBpRowScope extends InheritedWidget {
  const LcBpRowScope({super.key, required this.bp, required super.child});
  final String? bp;

  /// 这一行要不要标“不分屏宽”：在平板 / 桌面档、而且不在 [LcPerBp] 里面。
  static bool tagHere(BuildContext context) {
    if (context.dependOnInheritedWidgetOfExactType<LcPerBp>() != null) return false;
    return context.dependOnInheritedWidgetOfExactType<LcBpRowScope>()?.bp != null;
  }

  @override
  bool updateShouldNotify(LcBpRowScope old) => old.bp != bp;
}

/// 包着的这一行改的是样子：能分屏宽，不标“不分屏宽”。
class LcPerBp extends InheritedWidget {
  const LcPerBp({super.key, required super.child});

  @override
  bool updateShouldNotify(LcPerBp old) => false;
}

/// 一行小灰字“不分屏宽”（放在行名下面，或者一整块设置的最上面）。
class LcNoBpTag extends StatelessWidget {
  const LcNoBpTag({super.key, this.block = false});

  /// 整块用（导航项、选项这种一大块）：写全一点。
  final bool block;

  @override
  Widget build(BuildContext context) {
    if (!LcBpRowScope.tagHere(context)) return const SizedBox.shrink();
    return Text(
      block ? '这一块不分屏宽：在哪个屏宽改都一样。' : '不分屏宽',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(color: context.colors.textFaint),
    );
  }
}
