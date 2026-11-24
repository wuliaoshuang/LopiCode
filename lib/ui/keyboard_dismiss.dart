// 设计约束（软键盘收起 → 输入框失焦）
// - 安卓上用系统手势 / 返回键收起键盘时，输入框不会自己失焦；这里只负责判断“现在该不该把焦点摘掉”，不碰界面。
// - 只有“这一次聚焦期间见过键盘升起（高度 > 0），之后又回到 0”才算键盘被收起。
//   从没见过键盘（外接实体键盘、桌面）不摘；键盘刚开始弹、高度还是 0 的那几帧不摘。
// - 键盘高度回到 0 不马上摘：换输入法时键盘会闪一下，先等 [kKeyboardSettle] 再看，键盘回来了就当没发生。
// - 切到后台、转屏的时候键盘消失得更久：等 [kKeyboardSettleSlow] 再看。离开前台期间键盘消失不算用户收起。

/// 键盘高度回到 0 之后等多久再确认“真的收起了”。
const Duration kKeyboardSettle = Duration(milliseconds: 200);

/// 刚转屏、刚从后台回来时多等一会儿（系统要重新摆键盘）。
const Duration kKeyboardSettleSlow = Duration(milliseconds: 600);

/// 这次键盘高度变化之后该做什么。
enum KeyboardVerdict {
  /// 什么都不用做。
  none,

  /// 键盘高度回到 0 了：等 [kKeyboardSettle] 后用 [KeyboardDismissTracker.confirm] 确认。
  checkSoon,

  /// 说不准（刚转屏、刚从后台回来）：等 [kKeyboardSettleSlow] 后再用 [KeyboardDismissTracker.confirm] 问一次。
  checkLater,
}

/// 记住“这一次聚焦期间键盘有没有升起过”，据此判断键盘是不是被用户收起了。纯逻辑，好测。
class KeyboardDismissTracker {
  bool _focused = false;
  bool _sawKeyboard = false;
  bool _resumed = true;
  bool _unsettled = false;
  double? _width;

  /// 这一次聚焦期间见过键盘。
  bool get sawKeyboard => _sawKeyboard;

  bool get _armed => _focused && _sawKeyboard;

  /// 输入框得到 / 失去焦点。[inset] 是此刻的键盘高度（接着别的输入框聚焦时键盘可能本来就开着）。
  void onFocus({required bool focused, required double inset}) {
    if (focused == _focused) return;
    _focused = focused;
    _sawKeyboard = focused && inset > 0;
    _unsettled = false;
  }

  /// 键盘高度或屏幕尺寸变了。[width] 用来认出转屏。
  KeyboardVerdict onMetrics({required double inset, required double width}) {
    final turned = _width != null && width != _width;
    _width = width;
    if (!_focused) return KeyboardVerdict.none;
    if (inset > 0) _sawKeyboard = true;
    if (!_armed) return KeyboardVerdict.none;
    if (turned) {
      _unsettled = true;
      return KeyboardVerdict.checkLater;
    }
    if (inset > 0 || !_resumed) return KeyboardVerdict.none;
    return _unsettled ? KeyboardVerdict.checkLater : KeyboardVerdict.checkSoon;
  }

  /// 应用回到前台（[resumed] 为 true）或离开前台。离开期间键盘消失不算用户收起。
  KeyboardVerdict onLifecycle({required bool resumed}) {
    final back = resumed && !_resumed;
    _resumed = resumed;
    if (!back || !_armed) return KeyboardVerdict.none;
    _unsettled = true;
    return KeyboardVerdict.checkLater;
  }

  /// 等过一小会儿之后再问：键盘还是没回来就失焦（返回 true）。
  bool confirm({required double inset}) {
    _unsettled = false;
    return _armed && _resumed && inset <= 0;
  }
}
