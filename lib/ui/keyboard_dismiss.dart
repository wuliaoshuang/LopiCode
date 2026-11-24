// 设计约束（软键盘收起 → 输入框失焦）
// - 安卓上用系统手势 / 返回键收起键盘时，输入框不会自己失焦；这里只负责判断“现在该不该把焦点摘掉”，不碰界面。
//   喂进来的是“键盘高度（逻辑像素）＋时间戳”，不依赖任何界面类，好测。
// - 键盘一开始往下走就摘（[KeyboardVerdict.dismissNow]），不等它降到 0：
//   从稳定的高度开始，连续 [kDescentSteps] 次上报都在变矮（相邻两次间隔不超过 [kDescentFrameGap]，也就是在走动画），
//   而且一共矮了至少 [kDescentMinDrop]，就算“开始收起”。高度直接跳到 0（有的机型没有动画）同样马上摘。
// - 不算收起的：
//   · 键盘升起过程（高度在变高）；刚升完 [kPeakCalm] 之内的回落（升起动画冲过头再落回来）。
//   · 只变矮一次就停住、还大于 0：输入法候选栏收起、切到表情 / 符号面板，都是一步跳到新高度。
//   · 转屏、刚回到前台：系统要重新摆键盘，这段时间不看下降，高度是 0 就等 [kKeyboardSettleSlow] 再确认。
//   · 离开前台期间键盘消失。
//   · 这一次聚焦期间从没见过键盘（外接实体键盘、桌面、悬浮键盘不上报高度——悬浮键盘收起了也不会失焦，已知限制）。
// - 刚聚焦的 [kFocusGrace] 之内不看下降：上一次键盘还在往下走的时候用户又点了输入框，那几帧“变矮”是旧动画的尾巴，
//   不能刚聚焦就又被摘掉。这期间高度到了 0 只是等一会儿再确认，键盘升回来就当没发生。
// - 失焦之后（不管是这里摘的、点语音摘的还是别处摘的）什么都不看，所以“自己摘焦点 → 键盘下降”不会被再处理一遍。
// - 已知取舍：系统里换另一个输入法应用时，旧键盘是真的收起了，这里分不出来，会失焦，要再点一下输入框。
//   个别输入法如果把“候选栏收起 / 切面板”做成逐帧变矮的动画，也会被当成收起。
import 'package:flutter/foundation.dart';

/// 抗抖：连续下降累计至少这么多逻辑像素才算数（小于它的当成上报抖动）。
const double kDescentMinDrop = 6;

/// 至少连续这么多次上报都在变矮才算“在往下走”。只变矮一次的是候选栏 / 面板一步跳变。
const int kDescentSteps = 2;

/// 相邻两次变矮的间隔超过它，就不算同一段下降动画（60Hz 一帧约 16ms，留足掉帧的余量）。
const Duration kDescentFrameGap = Duration(milliseconds: 100);

/// 键盘最后一次变高之后，过这么久才把当前高度当成“稳定的峰值”。
const Duration kPeakCalm = Duration(milliseconds: 150);

/// 刚聚焦的这段时间里不看下降。
const Duration kFocusGrace = Duration(milliseconds: 300);

/// 拿不准的时候（刚升完就到 0），高度到 0 之后等多久再确认“真的收起了”。
const Duration kKeyboardSettle = Duration(milliseconds: 200);

/// 刚转屏、刚从后台回来、刚聚焦时多等一会儿（系统要重新摆键盘）。
const Duration kKeyboardSettleSlow = Duration(milliseconds: 600);

/// 只给测试用：换掉取时间的办法（界面测试里的时钟是假的，要跟着 pump 走）。
@visibleForTesting
Duration Function()? debugKeyboardNow;

final Stopwatch _uptime = Stopwatch()..start();

/// 单调时钟：只用来比先后和间隔。
Duration keyboardNow() => debugKeyboardNow?.call() ?? _uptime.elapsed;

/// 这次键盘高度变化之后该做什么。
enum KeyboardVerdict {
  /// 什么都不用做。
  none,

  /// 键盘开始收起（或直接没了）：现在就失焦。
  dismissNow,

  /// 键盘高度到 0 了但拿不准：等 [kKeyboardSettle] 后用 [KeyboardDismissTracker.confirm] 确认。
  checkSoon,

  /// 说不准（刚转屏、刚从后台回来、刚聚焦）：等 [kKeyboardSettleSlow] 后再用 [KeyboardDismissTracker.confirm] 问一次。
  checkLater,
}

/// 记住这一次聚焦期间键盘高度是怎么变的，据此判断键盘是不是被用户收起了。纯逻辑。
class KeyboardDismissTracker {
  bool _focused = false;
  bool _sawKeyboard = false;
  bool _resumed = true;
  bool _unsettled = false;
  double? _width;

  /// 上一次上报的高度和时间。
  double _last = 0;
  Duration _lastAt = Duration.zero;

  /// 这个时刻之前的下降都不看（刚聚焦 / 刚升高 / 刚回前台）。
  Duration _calmAt = Duration.zero;

  /// 刚聚焦的宽限期到什么时候。
  Duration _graceUntil = Duration.zero;

  /// 当前这一段连续下降：起点高度、已经连着降了几次。
  double _top = 0;
  int _steps = 0;

  /// 这一次聚焦期间见过键盘。
  bool get sawKeyboard => _sawKeyboard;

  bool get _armed => _focused && _sawKeyboard;

  static Duration _later(Duration a, Duration b) => a > b ? a : b;

  /// 输入框得到 / 失去焦点。[inset] 是此刻的键盘高度（接着别的输入框聚焦时键盘可能本来就开着）。
  void onFocus({required bool focused, required double inset, required Duration now}) {
    if (focused == _focused) return;
    _focused = focused;
    _sawKeyboard = focused && inset > 0;
    _unsettled = false;
    _steps = 0;
    _last = inset;
    _lastAt = now;
    _graceUntil = now + kFocusGrace;
    _calmAt = _graceUntil;
  }

  /// 键盘高度或屏幕尺寸变了。[inset] 是逻辑像素；[width] 用来认出转屏。
  KeyboardVerdict onMetrics({required double inset, required double width, required Duration now}) {
    final turned = _width != null && width != _width;
    _width = width;
    final prev = _last;
    final gap = now - _lastAt;
    _last = inset;
    _lastAt = now;
    if (!_focused) return KeyboardVerdict.none;
    if (inset > 0) _sawKeyboard = true;
    if (inset > prev) {
      // 在变高：升起过程，或候选栏 / 面板变高。稳定下来之前的回落不算收起。
      _steps = 0;
      _calmAt = _later(_calmAt, now + kPeakCalm);
    }
    if (!_armed) return KeyboardVerdict.none;
    if (turned) {
      _unsettled = true;
      _steps = 0;
      return KeyboardVerdict.checkLater;
    }
    if (!_resumed) {
      _steps = 0;
      return KeyboardVerdict.none;
    }
    if (inset <= 0) {
      _steps = 0;
      if (_unsettled || now < _graceUntil) return KeyboardVerdict.checkLater;
      if (now < _calmAt) return KeyboardVerdict.checkSoon;
      return KeyboardVerdict.dismissNow;
    }
    if (_unsettled || inset >= prev) return KeyboardVerdict.none;
    // 变矮了，但还大于 0。
    if (now < _calmAt) {
      _steps = 0;
      return KeyboardVerdict.none;
    }
    if (_steps == 0 || gap > kDescentFrameGap) {
      _top = prev;
      _steps = 1;
    } else {
      _steps++;
    }
    if (_steps >= kDescentSteps && _top - inset >= kDescentMinDrop) {
      _steps = 0;
      return KeyboardVerdict.dismissNow;
    }
    return KeyboardVerdict.none;
  }

  /// 应用回到前台（[resumed] 为 true）或离开前台。离开期间键盘消失不算用户收起。
  KeyboardVerdict onLifecycle({required bool resumed, required Duration now}) {
    final back = resumed && !_resumed;
    _resumed = resumed;
    _steps = 0;
    if (!back || !_armed) return KeyboardVerdict.none;
    _unsettled = true;
    _calmAt = _later(_calmAt, now + kPeakCalm);
    return KeyboardVerdict.checkLater;
  }

  /// 等过一小会儿之后再问：键盘还是没回来就失焦（返回 true）。
  bool confirm({required double inset}) {
    _unsettled = false;
    return _armed && _resumed && inset <= 0;
  }
}
