// 设计约束（点输入框外面 → 收键盘 · 纯逻辑）
// - 这里只判断“输入框外面的这一下，算不算一次该收键盘的点按”，不碰界面、不碰焦点；界面那一半在 keyboard_tap_dismiss.dart。
// - 算数的只有“轻点”：同一根手指按下、抬起，位置几乎没动（不超过 [kTapOutsideSlop]），按住的时间短于 [kTapOutsideHold]。
// - 不算的：
//   · 拖动（滚列表、拉侧边栏、拖选择手柄）——手指挪远了。
//   · 长按（选文字、弹菜单）——按得久。
//   · 两根手指（捏合缩放代码字号、画布）——第二根手指落下的那一刻，这一轮就作废，哪根先抬都不算。
//   · 落点在“输入区”里（发送、工具栏、附件条、候选列表……）——按下时由界面告诉这里 `keep`。
// - 按下后没等到抬起（手势被系统取消）不会卡住：取消会清掉记录；万一连取消也没收到，下一次按下直接顶掉旧记录。
import 'dart:ui' show Offset;

/// 按下到抬起之间手指最多挪这么远还算“点”（逻辑像素；和系统判断点按 / 拖动的界线一致）。
const double kTapOutsideSlop = 18;

/// 按住不到这么久才算“点”，再久就是长按（和系统的长按时间一致）。
const Duration kTapOutsideHold = Duration(milliseconds: 500);

/// 记住输入框外面的一次按下，抬起时判断要不要收键盘。
class TapOutsideJudge {
  int? _pointer;
  Offset _at = Offset.zero;
  Duration _time = Duration.zero;
  bool _keep = false;
  bool _spoiled = false;

  /// 手指在输入框外面按下了。[keep]＝落点在输入区里（点了不收）。[time] 用指针事件自带的时间。
  void down({required int pointer, required Offset position, required Duration time, bool keep = false}) {
    // 上一根手指还没抬、又落下一根：多指手势，这一轮都不算。隔了很久的旧记录是没等到抬起的残留，直接顶掉。
    final second = _pointer != null && _pointer != pointer && time - _time < kTapOutsideHold;
    _pointer = pointer;
    _at = position;
    _time = time;
    _keep = keep;
    _spoiled = second;
  }

  /// 手指抬起了。返回 true＝这是一次落在空白处的轻点，该收键盘。
  bool up({required int pointer, required Offset position, required Duration time}) {
    if (_pointer == null) return false;
    if (_pointer != pointer) {
      // 多指手势里先抬起来的那根：剩下那根也不算了。
      _spoiled = true;
      return false;
    }
    _pointer = null;
    if (_spoiled || _keep) return false;
    if ((position - _at).distance > kTapOutsideSlop) return false;
    return time - _time < kTapOutsideHold;
  }

  /// 手势被系统取消（等不到抬起了）。别的手指的取消也让这一轮作废。
  void cancel(int pointer) {
    if (_pointer == pointer) {
      _pointer = null;
    } else {
      _spoiled = true;
    }
  }
}
