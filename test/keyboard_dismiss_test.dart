// 软键盘收起 → 输入框失焦（霜霜真机反馈第三轮第 1 条）：键盘一开始往下走就失焦，不等降到 0。
// 上半：判定逻辑（keyboard_dismiss.dart）的单元测试，喂“高度序列＋时间戳”。
// 下半：390×844（像素比 3）浅色 / 深色的界面测试。
//   LOPI_SHOTS=1 flutter test test/keyboard_dismiss_test.dart   # 同时写截图到 docs/screenshots/kbdismiss-*.png
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/agent/agent_tools.dart';
import 'package:lopicode/theme/app_theme.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/chat_composer.dart';
import 'package:lopicode/ui/keyboard_dismiss.dart';
import 'package:material_ui/material_ui.dart';

import 'support/composer_gallery.dart';
import 'support/harness.dart';

Duration _ms(num v) => Duration(microseconds: (v * 1000).round());

/// 一条“键盘高度随时间变化”的记录，喂给判定逻辑，记下每一步的结论。
class _Feed {
  _Feed({double focusInset = 0}) {
    t.onFocus(focused: true, inset: focusInset, now: now);
    inset = focusInset;
  }

  final t = KeyboardDismissTracker();
  double width = 390;
  Duration now = Duration.zero;
  double inset = 0;

  /// 第一次得到“现在就失焦”的时刻和当时的高度。
  Duration? firedAt;
  double? firedInset;
  final verdicts = <KeyboardVerdict>[];

  void wait(num ms) => now += _ms(ms);

  /// 过 [after] 毫秒后上报一次高度。
  KeyboardVerdict put(double h, {num after = 16}) {
    wait(after);
    inset = h;
    final v = t.onMetrics(inset: h, width: width, now: now);
    verdicts.add(v);
    if (v == KeyboardVerdict.dismissNow && firedAt == null) {
      firedAt = now;
      firedInset = h;
    }
    return v;
  }

  /// 从当前高度匀速走到 [to]，一共 [ms] 毫秒，每 [frame] 毫秒上报一次。
  void glide(double to, {required num ms, num frame = 16}) {
    final from = inset;
    final n = (ms / frame).ceil();
    for (var i = 1; i <= n; i++) {
      put(i == n ? to : from + (to - from) * i / n, after: frame);
    }
  }

  /// 键盘正常升起并停稳。
  void riseAndRest({double to = 320}) {
    glide(to, ms: 250);
    wait(1000);
  }

  bool get fired => firedAt != null;
}

class _Voice implements ChatVoiceInput {
  bool listening = false;
  int stopCalls = 0;
  @override
  bool get isListening => listening;
  @override
  Future<bool> initialize() async => true;
  @override
  Future<void> listen({required void Function(String words) onResult, required void Function(bool listening) onListeningChanged, required void Function(String message) onError}) async {
    listening = true;
    onListeningChanged(true);
  }

  @override
  Future<void> stop() async {
    stopCalls++;
    listening = false;
  }

  @override
  void dispose() {}
}

const double _dpr = 3;

/// 模拟软键盘高度（逻辑像素）。
void _keyboard(WidgetTester tester, double height) => tester.view.viewInsets = FakeViewPadding(bottom: height * _dpr);

/// 逐帧把键盘高度走一遍。
Future<void> _frames(WidgetTester tester, List<double> heights) async {
  for (final h in heights) {
    _keyboard(tester, h);
    await tester.pump(const Duration(milliseconds: 16));
  }
}

Future<({TextEditingController text, FocusNode focus, _Voice voice})> _pump(WidgetTester tester, Brightness brightness, {String? font, String draft = ''}) async {
  usePhoneViewport(tester, pixelRatio: _dpr);
  debugKeyboardNow = () => Duration(microseconds: tester.binding.clock.now().microsecondsSinceEpoch);
  addTearDown(() => debugKeyboardNow = null);
  final text = TextEditingController(text: draft);
  final focus = FocusNode();
  final voice = _Voice();
  addTearDown(text.dispose);
  addTearDown(focus.dispose);
  await tester.pumpWidget(
    RepaintBoundary(
      key: shotKey,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(brightness, fontFamily: font),
        home: Builder(
          builder: (context) {
            final c = context.colors;
            final kb = MediaQuery.viewInsetsOf(context).bottom;
            return Stack(
              children: [
                Scaffold(
                  body: Column(
                    children: [
                      Expanded(
                        child: Center(
                          child: Text('键盘高度 ${kb.round()}', style: TextStyle(color: c.textMuted)),
                        ),
                      ),
                      ValueListenableBuilder<TextEditingValue>(
                        valueListenable: text,
                        builder: (context, value, _) => ChatComposer(
                          controller: text,
                          focusNode: focus,
                          busy: false,
                          canSend: value.text.trim().isNotEmpty,
                          modelName: 'DeepSeek Chat',
                          permission: PermissionLevel.workspace,
                          voiceInput: voice,
                          // 语音入口默认藏着；打开开关继续测“语音输入中键盘收起”。
                          showVoice: true,
                          onPlus: () {},
                          onModel: () {},
                          onPermission: () {},
                          onSend: () {},
                          onLongSend: () {},
                          onStop: () {},
                        ),
                      ),
                    ],
                  ),
                ),
                // 假键盘：只为截图里看得出键盘此刻在哪。
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: kb,
                  child: Material(
                    color: c.surfaceMuted,
                    child: Center(
                      child: Text('软键盘（示意）', style: TextStyle(color: c.textMuted)),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    ),
  );
  return (text: text, focus: focus, voice: voice);
}

/// 点进输入框，键盘升起并停稳。
Future<void> _focusAndRise(WidgetTester tester) async {
  await tester.tap(find.byType(TextField));
  await tester.pump();
  await _frames(tester, [40, 120, 220, 300, 320]);
  await tester.pump(const Duration(seconds: 1));
}

final Finder _capsule = find.descendant(of: find.byKey(const ValueKey('chat-input')), matching: find.byType(DecoratedBox)).first;
final Finder _expanded = find.byKey(const ValueKey('model-button'));

void main() {
  group('判定逻辑', () {
    test('正常快速收起（250ms 降完）：第二帧下降就触发，不等到 0', () {
      final f = _Feed()..riseAndRest();
      final start = f.now;
      f.glide(0, ms: 250);
      expect(f.firedAt, start + _ms(32), reason: '连续两次变矮即触发');
      expect(f.firedInset, greaterThan(250));
    });

    test('慢慢降 2 秒：刚开始降就触发（60Hz 第 3 帧、120Hz 第 5 帧），不是到 0 才触发', () {
      final a = _Feed()..riseAndRest();
      final start = a.now;
      a.glide(0, ms: 2000);
      expect(a.firedAt, start + _ms(48), reason: '每帧降 2.56：第 3 帧累计 7.7 ≥ $kDescentMinDrop');
      expect(a.firedInset, greaterThan(310));

      final b = _Feed()..riseAndRest();
      final start120 = b.now;
      b.glide(0, ms: 2000, frame: 8);
      expect(b.firedAt! - start120, lessThan(_ms(50)));
      expect(b.firedInset, greaterThan(310));
    });

    test('高度直接跳到 0（没有动画的机型）：立刻触发', () {
      final f = _Feed()..riseAndRest();
      expect(f.put(0, after: 500), KeyboardVerdict.dismissNow);
    });

    test('降一点又升回去：只降一次、或累计不到 $kDescentMinDrop 不触发；连续两帧累计降够了就触发', () {
      final f = _Feed()..riseAndRest();
      f
        ..put(318)
        ..put(320);
      f.wait(500);
      f
        ..put(317)
        ..put(315)
        ..put(320);
      expect(f.fired, isFalse, reason: '一次是 1 步，一次是 2 步但只降了 5');
      f.wait(500);
      f.put(310);
      expect(f.fired, isFalse);
      f.put(300);
      expect(f.fired, isTrue, reason: '连续两帧共降 20：按设计算开始收起');
    });

    test('候选栏变高变矮：一步跳变，不触发', () {
      final f = _Feed()..riseAndRest();
      f.put(368, after: 800);
      f.put(320, after: 800);
      f.put(368, after: 800);
      f.put(320, after: 30);
      f.put(368, after: 30);
      f.put(320, after: 30);
      f.wait(1000);
      expect(f.fired, isFalse);
      expect(f.verdicts.toSet(), {KeyboardVerdict.none});
      // 之后真的收起照样触发
      f.glide(0, ms: 250);
      expect(f.fired, isTrue);
    });

    test('切换表情 / 符号面板：高度跳变但仍大于 0，不触发；隔了很久的两次变矮也不算连续下降', () {
      final f = _Feed()..riseAndRest();
      f.put(260, after: 600);
      f.put(400, after: 600);
      f.put(320, after: 600);
      f.put(290, after: 500);
      f.put(260, after: 500);
      expect(f.fired, isFalse);
      expect(f.verdicts.toSet(), {KeyboardVerdict.none});
    });

    test('升起过程中的抖动、冲过头再落回：不触发', () {
      final f = _Feed();
      for (final h in <double>[0, 0, 12, 80, 75, 70, 200, 330, 326, 322, 320]) {
        f.put(h);
      }
      f.wait(1000);
      expect(f.fired, isFalse);
      expect(f.verdicts.toSet(), {KeyboardVerdict.none});
    });

    test('刚升完就到 0（来不及认定稳定）：不立刻摘，等一小会儿确认', () {
      final f = _Feed()..glide(320, ms: 250);
      expect(f.put(0, after: 50), KeyboardVerdict.checkSoon);
      expect(f.t.confirm(inset: 0), isTrue);
    });

    test('旋转：键盘跟着变矮、消失都不立刻触发，多等一会儿再确认；转完之后收起照样立刻触发', () {
      final f = _Feed()..riseAndRest();
      f.width = 844;
      expect(f.put(300), KeyboardVerdict.checkLater);
      for (final h in <double>[250, 200, 120, 0, 0]) {
        expect(f.put(h), isNot(KeyboardVerdict.dismissNow), reason: '高度 $h');
      }
      f.glide(200, ms: 200);
      expect(f.t.confirm(inset: 200), isFalse, reason: '键盘回来了');
      expect(f.fired, isFalse);
      f.wait(1000);
      f.glide(0, ms: 250);
      expect(f.fired, isTrue);
    });

    test('切到后台再回前台：离开期间键盘消失不算；回来后多等一会儿；之后收起照样立刻触发', () {
      final f = _Feed()..riseAndRest();
      expect(f.t.onLifecycle(resumed: false, now: f.now), KeyboardVerdict.none);
      f.glide(0, ms: 250);
      expect(f.fired, isFalse);
      expect(f.t.confirm(inset: 0), isFalse, reason: '还在后台');
      f.wait(5000);
      expect(f.t.onLifecycle(resumed: true, now: f.now), KeyboardVerdict.checkLater);
      expect(f.put(0), KeyboardVerdict.checkLater);
      f.glide(320, ms: 250);
      expect(f.t.confirm(inset: 320), isFalse);
      f.wait(1000);
      final start = f.now;
      f.glide(0, ms: 250);
      expect(f.firedAt, start + _ms(32));

      // 回来后键盘一直没回来：确认后失焦
      final g = _Feed()..riseAndRest();
      g.t.onLifecycle(resumed: false, now: g.now);
      g.put(0);
      expect(g.t.onLifecycle(resumed: true, now: g.now), KeyboardVerdict.checkLater);
      expect(g.t.confirm(inset: 0), isTrue);
    });

    test('悬浮键盘 / 实体键盘（从不上报高度）：不触发（已知限制：悬浮键盘收起后不会失焦）', () {
      final f = _Feed();
      for (var i = 0; i < 20; i++) {
        f.put(0, after: 200);
      }
      expect(f.verdicts.toSet(), {KeyboardVerdict.none});
      expect(f.t.sawKeyboard, isFalse);
      expect(f.t.confirm(inset: 0), isFalse);
    });

    test('上一次键盘还在下降时又点了输入框：旧动画的尾巴不触发，键盘升回来保持聚焦，之后收起照样一开始就触发', () {
      final f = _Feed(focusInset: 200);
      for (final h in <double>[170, 140, 110, 130, 180, 260, 320]) {
        expect(f.put(h), KeyboardVerdict.none, reason: '高度 $h');
      }
      f.wait(1000);
      final start = f.now;
      f.glide(0, ms: 250);
      expect(f.firedAt, start + _ms(32));

      // 尾巴一路降到 0 再升回来：只是晚点确认
      final g = _Feed(focusInset: 60);
      expect(g.put(30), KeyboardVerdict.none);
      expect(g.put(0), KeyboardVerdict.checkLater);
      g.glide(320, ms: 250);
      expect(g.t.confirm(inset: 320), isFalse);
      expect(g.fired, isFalse);
    });

    test('失焦之后（包括我们自己摘的）键盘继续下降：不再处理', () {
      final f = _Feed()..riseAndRest();
      f
        ..put(300)
        ..put(280);
      expect(f.fired, isTrue);
      f.t.onFocus(focused: false, inset: 280, now: f.now);
      final before = f.verdicts.length;
      f.glide(0, ms: 220);
      expect(f.verdicts.skip(before).toSet(), {KeyboardVerdict.none});
      expect(f.t.confirm(inset: 0), isFalse);
    });

    test('没聚焦时不管；重新聚焦要重新见到键盘；接着别的输入框聚焦时键盘本来就开着也算见过', () {
      final t = KeyboardDismissTracker();
      expect(t.onMetrics(inset: 300, width: 390, now: _ms(0)), KeyboardVerdict.none);
      expect(t.onMetrics(inset: 0, width: 390, now: _ms(16)), KeyboardVerdict.none);
      t.onFocus(focused: true, inset: 0, now: _ms(100));
      expect(t.onMetrics(inset: 0, width: 390, now: _ms(1000)), KeyboardVerdict.none);
      expect(t.confirm(inset: 0), isFalse);
      t
        ..onFocus(focused: false, inset: 0, now: _ms(2000))
        ..onFocus(focused: true, inset: 300, now: _ms(3000));
      expect(t.sawKeyboard, isTrue);
      expect(t.onMetrics(inset: 0, width: 390, now: _ms(3100)), KeyboardVerdict.checkLater, reason: '刚聚焦：晚点确认');
      t
        ..onFocus(focused: false, inset: 0, now: _ms(4000))
        ..onFocus(focused: true, inset: 300, now: _ms(5000));
      expect(t.onMetrics(inset: 280, width: 390, now: _ms(6000)), KeyboardVerdict.none);
      expect(t.onMetrics(inset: 260, width: 390, now: _ms(6016)), KeyboardVerdict.dismissNow);
    });
  });

  group('界面 390×844', () {
    final shots = Platform.environment['LOPI_SHOTS'] == '1';
    var fonts = false;
    setUpAll(() async => fonts = await loadRealFonts());

    for (final brightness in Brightness.values) {
      final name = brightness.name;

      testWidgets('没草稿：键盘刚开始往下走就失焦并收回一行；键盘剩下的下降不再折腾 · $name', (tester) async {
        final s = await _pump(tester, brightness, font: fonts ? kTestFont : null);
        expect(tester.getSize(find.byType(MaterialApp)), const Size(390, 844));
        await _focusAndRise(tester);
        expect(s.focus.hasFocus, isTrue);
        expect(_expanded, findsOneWidget);
        if (shots && fonts) await writeShot(tester, 'kbdismiss-1-open-$name');

        await _frames(tester, [300]);
        expect(s.focus.hasFocus, isTrue, reason: '只矮了一次：可能是候选栏 / 面板跳变');
        await _frames(tester, [280]);
        expect(s.focus.hasFocus, isFalse, reason: '第二帧还在降：立刻失焦，此时键盘还有 280 高');
        expect(tester.testTextInput.hasAnyClients, isFalse);
        await _frames(tester, [260, 240, 220, 200, 180, 160, 150]);
        await tester.pump(const Duration(milliseconds: 100));
        expect(_expanded, findsNothing, reason: '键盘还在半空（150）时已经收回一行');
        expect(tester.getSize(_capsule).height, 48);
        if (shots && fonts) await writeShot(tester, 'kbdismiss-2-descending-$name');

        tester.testTextInput.log.clear();
        await _frames(tester, [120, 90, 60, 30, 0]);
        await tester.pump(kKeyboardSettleSlow * 2);
        expect(s.focus.hasFocus, isFalse);
        expect(tester.testTextInput.log, isEmpty, reason: '失焦之后没有再去显示 / 隐藏键盘');
        expect(_expanded, findsNothing);
        expect(tester.getSize(_capsule).height, 48);
        expect(tester.takeException(), isNull);
      });

      testWidgets('失焦后键盘还在下降时又点输入框：聚焦保持住，不抖，键盘升回来后仍聚焦 · $name', (tester) async {
        final s = await _pump(tester, brightness);
        await _focusAndRise(tester);
        await _frames(tester, [300, 280, 240, 200]);
        expect(s.focus.hasFocus, isFalse);

        var flips = 0;
        s.focus.addListener(() => flips++);
        await tester.tap(find.byType(TextField));
        await tester.pump();
        expect(s.focus.hasFocus, isTrue);
        expect(tester.testTextInput.isVisible, isTrue, reason: '重新请求弹键盘');
        // 旧的下降动画还走了几帧，系统才把键盘升回来
        await _frames(tester, [170, 140, 110, 130, 180, 260, 320]);
        await tester.pump(kKeyboardSettleSlow * 2);
        expect(s.focus.hasFocus, isTrue);
        expect(flips, 1, reason: '只有“得到焦点”这一次变化');
        expect(_expanded, findsOneWidget);

        // 这之后再收起照样立刻失焦
        await _frames(tester, [300, 280]);
        expect(s.focus.hasFocus, isFalse);
      });

      testWidgets('有草稿：键盘开始下降就失焦，但保持展开，草稿不丢 · $name', (tester) async {
        final s = await _pump(tester, brightness, font: fonts ? kTestFont : null);
        await _focusAndRise(tester);
        await tester.enterText(find.byType(TextField), '把首页的按钮改成圆角');
        await tester.pump(const Duration(seconds: 1));
        expect(s.focus.hasFocus, isTrue);

        await _frames(tester, [300, 280]);
        expect(s.focus.hasFocus, isFalse);
        await _frames(tester, [240, 200, 150]);
        await tester.pump(const Duration(milliseconds: 100));
        expect(_expanded, findsOneWidget);
        expect(s.text.text, '把首页的按钮改成圆角');
        if (shots && fonts) await writeShot(tester, 'kbdismiss-3-draft-$name');
        await _frames(tester, [100, 50, 0]);
        await tester.pump(kKeyboardSettleSlow * 2);
        expect(_expanded, findsOneWidget);
        expect(tester.getSize(_capsule).height, greaterThan(90));
        expect(tester.takeException(), isNull);
      });

      testWidgets('语音输入中：键盘下降只摘焦点，语音不被打断，保持展开；点语音时自己摘焦点引起的下降不处理 · $name', (tester) async {
        final s = await _pump(tester, brightness);
        await _focusAndRise(tester);
        // 点语音：输入栏自己摘焦点，键盘随之下降
        await tester.tap(find.byKey(const ValueKey('voice-button')));
        await tester.pump();
        expect(s.focus.hasFocus, isFalse);
        await _frames(tester, [300, 260, 200, 120, 40, 0]);
        await tester.pump(const Duration(seconds: 1));
        expect(s.voice.listening, isTrue);
        expect(s.voice.stopCalls, 0);
        expect(_expanded, findsOneWidget, reason: '听写时保持展开');

        // 听写时又点进输入框，键盘升起后被收起
        await _focusAndRise(tester);
        expect(s.focus.hasFocus, isTrue);
        await _frames(tester, [300, 280]);
        expect(s.focus.hasFocus, isFalse);
        await _frames(tester, [200, 100, 0]);
        await tester.pump(const Duration(seconds: 1));
        expect(s.voice.listening, isTrue);
        expect(s.voice.stopCalls, 0);
        expect(find.byTooltip('停止语音输入'), findsOneWidget);
        expect(_expanded, findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('候选栏变高变矮、切面板、升起过程：都不失焦', (tester) async {
      final s = await _pump(tester, Brightness.light);
      await tester.tap(find.byType(TextField));
      await tester.pump();
      await _frames(tester, [0, 12, 80, 75, 70, 200, 330, 326, 322, 320]);
      await tester.pump(const Duration(seconds: 1));
      for (final h in <double>[368, 320, 260, 400, 320]) {
        _keyboard(tester, h);
        await tester.pump(const Duration(milliseconds: 600));
        expect(s.focus.hasFocus, isTrue, reason: '高度 $h');
      }
      expect(_expanded, findsOneWidget);
    });
  });
}
