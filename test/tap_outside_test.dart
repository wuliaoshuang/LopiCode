// 点输入框外面收键盘 · 纯逻辑（lib/ui/tap_outside.dart）：什么样的一下算“轻点空白”。

import 'package:flutter/gestures.dart' show kLongPressTimeout, kTouchSlop;
import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/ui/tap_outside.dart';

const Offset at = Offset(100, 300);
Duration ms(int v) => Duration(milliseconds: v);

void main() {
  late TapOutsideJudge j;
  setUp(() => j = TapOutsideJudge());

  test('界线和系统一致：挪动 18 以内、按住不到 500ms', () {
    expect(kTapOutsideSlop, kTouchSlop);
    expect(kTapOutsideHold, kLongPressTimeout);
  });

  test('轻点：按下抬起在同一处、时间短 → 收', () {
    j.down(pointer: 1, position: at, time: ms(1000));
    expect(j.up(pointer: 1, position: at, time: ms(1080)), isTrue);
  });

  test('手指轻微抖动（不超过界线）仍算轻点；超过就是拖动 → 不收', () {
    j.down(pointer: 1, position: at, time: ms(0));
    expect(
      j.up(pointer: 1, position: at + const Offset(10, 14), time: ms(90)),
      isTrue,
      reason: '挪了约 17.2',
    );
    j.down(pointer: 2, position: at, time: ms(200));
    expect(
      j.up(pointer: 2, position: at + const Offset(0, 19), time: ms(290)),
      isFalse,
      reason: '竖着拖：滚列表',
    );
    j.down(pointer: 3, position: at, time: ms(400));
    expect(
      j.up(pointer: 3, position: at + const Offset(-60, 2), time: ms(490)),
      isFalse,
      reason: '横着拖',
    );
  });

  test('长按（按住 500ms 及以上）不收，差一点到 500ms 的还算轻点', () {
    j.down(pointer: 1, position: at, time: ms(0));
    expect(j.up(pointer: 1, position: at, time: ms(500)), isFalse);
    j.down(pointer: 2, position: at, time: ms(1000));
    expect(j.up(pointer: 2, position: at, time: ms(1499)), isTrue);
  });

  test('落点在输入区里（keep）：不收', () {
    j.down(pointer: 1, position: at, time: ms(0), keep: true);
    expect(j.up(pointer: 1, position: at, time: ms(50)), isFalse);
    // 下一次点空白照常收：上一次的 keep 不残留
    j.down(pointer: 2, position: at, time: ms(100));
    expect(j.up(pointer: 2, position: at, time: ms(150)), isTrue);
  });

  test('两根手指（捏合）：哪根先抬都不收', () {
    j.down(pointer: 1, position: at, time: ms(0));
    j.down(pointer: 2, position: at + const Offset(80, 0), time: ms(40));
    expect(j.up(pointer: 1, position: at, time: ms(120)), isFalse);
    expect(j.up(pointer: 2, position: at + const Offset(80, 0), time: ms(130)), isFalse);
    // 反过来：后落下的先抬
    j.down(pointer: 3, position: at, time: ms(1000));
    j.down(pointer: 4, position: at + const Offset(80, 0), time: ms(1040));
    expect(j.up(pointer: 4, position: at + const Offset(80, 0), time: ms(1100)), isFalse);
    expect(j.up(pointer: 3, position: at, time: ms(1110)), isFalse);
    // 手指都抬了以后，新的一下照常算
    j.down(pointer: 5, position: at, time: ms(2000));
    expect(j.up(pointer: 5, position: at, time: ms(2050)), isTrue);
  });

  test('没有按下记录就抬起（按下时输入框还没聚焦）：不收', () {
    expect(j.up(pointer: 9, position: at, time: ms(10)), isFalse);
  });

  test('按下后手势被取消、没等到抬起：不卡住，下一次轻点照常收', () {
    j.down(pointer: 1, position: at, time: ms(0));
    j.cancel(1);
    expect(j.up(pointer: 1, position: at, time: ms(30)), isFalse);
    // 多指时别的手指被取消：这一轮也作废
    j.down(pointer: 6, position: at, time: ms(40));
    j.cancel(7);
    expect(j.up(pointer: 6, position: at, time: ms(60)), isFalse);
    // 没人通知取消的残留（隔了很久）：下一次按下直接顶掉，不当成“第二根手指”
    j.down(pointer: 2, position: at, time: ms(100));
    j.down(pointer: 3, position: at, time: ms(5000));
    expect(j.up(pointer: 3, position: at, time: ms(5060)), isTrue);
  });

  test('同一根手指重复上报按下：以最后一次为准', () {
    j.down(pointer: 1, position: at, time: ms(0));
    j.down(pointer: 1, position: at + const Offset(200, 0), time: ms(10));
    expect(j.up(pointer: 1, position: at + const Offset(200, 0), time: ms(60)), isTrue);
  });
}
