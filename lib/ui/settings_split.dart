// 设计约束（设置 · 宽屏两栏）— 2026-11-28 霜霜：“适配平板”
// - 宽屏（≥840）：左边是设置的分组清单（一级页，宽 360），右边是点开的那一项；中屏和手机还是一页一页地进。
// - 左边点一项：右边整栏换成那一页（不是往上叠）；右边的页面里再往下点，才在右边叠着进，右边自己的返回箭头一层层退回来。
// - 系统返回键：右边叠着页面时先退右边的；右边退到底了才离开设置。
// - 右边一开始没东西时放一句提示，不放假内容。
// - 左右两栏的树位置固定（左边的清单挂着全局 key）：窗口从宽拉窄再拉宽，清单的滚动位置还在。
import 'package:lopicode/theme/breakpoints.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/widgets.dart';
import 'package:material_ui/material_ui.dart';

/// 设置清单在两栏里时，把“打开下一页”交给右边那一栏。
class SettingsSplitScope extends InheritedWidget {
  const SettingsSplitScope({super.key, required this.show, required super.child});

  /// 在右边那一栏里打开 [page]（整栏换掉）。
  final Future<T?> Function<T>(Widget page) show;

  static SettingsSplitScope? maybeOf(BuildContext context) => context.getInheritedWidgetOfExactType<SettingsSplitScope>();

  @override
  bool updateShouldNotify(SettingsSplitScope old) => false;
}

class SettingsSplit extends StatefulWidget {
  const SettingsSplit({super.key, required this.master});

  /// 设置的一级页（分组清单）。
  final Widget master;

  /// 左边清单那一栏的宽度。
  static const double kMasterWidth = 360;

  @override
  State<SettingsSplit> createState() => _SettingsSplitState();
}

class _SettingsSplitState extends State<SettingsSplit> {
  final _masterKey = GlobalKey();
  final _detail = GlobalKey<NavigatorState>();
  final _detailKey = GlobalKey();
  late final _watch = _DetailWatch(_onDetailChanged);

  /// 右边那一栏里现在有没有点开的页面。
  bool _hasDetail = false;

  void _onDetailChanged() {
    // 导航栈是在搭界面的过程中变的：推后一拍再记。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final has = _detail.currentState?.canPop() ?? false;
      if (has != _hasDetail) setState(() => _hasDetail = has);
    });
  }

  Future<T?> _show<T>(Widget page) {
    final nav = _detail.currentState;
    // 只有两栏时才往右边那一栏里开；窄的时候和原来一样整页进。
    if (nav == null || !Breakpoints.of(context).isExpanded) return Navigator.of(context).push<T>(MaterialPageRoute<T>(builder: (_) => page));
    return nav.pushAndRemoveUntil<T>(MaterialPageRoute<T>(builder: (_) => page), (r) => r.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final master = KeyedSubtree(key: _masterKey, child: widget.master);
    final expanded = Breakpoints.of(context).isExpanded;
    // 窄、中：就是原来的一级页。只有“宽的时候在右边点开过东西、又把窗口拉窄了”才接着显示那一页（它的返回箭头回到清单）。
    if (!expanded && !_hasDetail) return master;
    // 整块挂着全局 key：两栏和“拉窄后接着显示”之间换位置时，导航栈和“返回键先退谁”的状态都跟着走。
    final detail = KeyedSubtree(
      key: _detailKey,
      child: NavigatorPopHandler<Object?>(
        onPopWithResult: (_) => _detail.currentState?.maybePop(),
        child: Navigator(
          key: _detail,
          observers: [_watch],
          onGenerateRoute: (_) => MaterialPageRoute<void>(builder: (_) => const _Nothing()),
        ),
      ),
    );
    if (!expanded) {
      return Stack(
        fit: StackFit.expand,
        children: [
          Offstage(child: master),
          detail,
        ],
      );
    }
    final c = context.colors;
    return ColoredBox(
      color: c.canvas,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            key: const ValueKey('settings-master'),
            width: SettingsSplit.kMasterWidth,
            child: MediaQuery.removePadding(
              context: context,
              removeRight: true,
              child: SettingsSplitScope(show: _show, child: master),
            ),
          ),
          VerticalDivider(width: 1, thickness: 1, color: c.border),
          Expanded(
            key: const ValueKey('settings-detail'),
            child: MediaQuery.removePadding(context: context, removeLeft: true, child: detail),
          ),
        ],
      ),
    );
  }
}

class _DetailWatch extends NavigatorObserver {
  _DetailWatch(this.onChanged);
  final VoidCallback onChanged;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => onChanged();
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => onChanged();
  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) => onChanged();
  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) => onChanged();
}

class _Nothing extends StatelessWidget {
  const _Nothing();

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: context.colors.canvas,
    body: const EmptyState(icon: Icons.tune, title: '在左边选一项', message: '点左边的任意一项，它的设置就显示在这里。'),
  );
}
