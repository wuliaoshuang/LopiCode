import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/agent/agent_tools.dart';
import 'package:lopicode/session/chat_models.dart';
import 'package:lopicode/theme/app_theme.dart';
import 'package:lopicode/ui/chat_composer.dart';
import 'package:lopicode/ui/keyboard_dismiss.dart';
import 'package:material_ui/material_ui.dart';

import 'support/harness.dart';

class _FakeVoice implements ChatVoiceInput {
  bool available = true;
  bool listening = false;
  bool disposed = false;
  int stopCalls = 0;
  void Function(String)? _onResult;
  void Function(bool)? _onListeningChanged;
  void Function(String)? _onError;

  @override
  bool get isListening => listening;

  @override
  Future<bool> initialize() async => available;

  @override
  Future<void> listen({required void Function(String words) onResult, required void Function(bool listening) onListeningChanged, required void Function(String message) onError}) async {
    _onResult = onResult;
    _onListeningChanged = onListeningChanged;
    _onError = onError;
    listening = true;
    onListeningChanged(true);
  }

  void emit(String words) => _onResult?.call(words);

  void fail(String message) {
    listening = false;
    _onListeningChanged?.call(false);
    _onError?.call(message);
  }

  @override
  Future<void> stop() async {
    stopCalls++;
    listening = false;
    _onListeningChanged?.call(false);
  }

  @override
  void dispose() => disposed = true;
}

class _Calls {
  int sends = 0;
  int models = 0;
  int permissions = 0;
  int plus = 0;
  int stops = 0;
  int rings = 0;
}

Future<({TextEditingController controller, FocusNode focus, _FakeVoice voice, _Calls calls})> _pump(
  WidgetTester tester, {
  _FakeVoice? voice,
  bool busy = false,
  String draft = '',
  bool ring = false,
}) async {
  usePhoneViewport(tester);
  debugKeyboardNow = () => Duration(microseconds: tester.binding.clock.now().microsecondsSinceEpoch);
  addTearDown(() => debugKeyboardNow = null);
  final input = voice ?? _FakeVoice();
  final controller = TextEditingController(text: draft);
  final focus = FocusNode();
  final calls = _Calls();
  addTearDown(controller.dispose);
  addTearDown(focus.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(Brightness.light),
      home: Scaffold(
        body: Column(
          children: [
            const Expanded(child: SizedBox.shrink()),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: controller,
              builder: (context, value, _) => ChatComposer(
                controller: controller,
                focusNode: focus,
                busy: busy,
                canSend: value.text.trim().isNotEmpty,
                modelName: 'DeepSeek Chat',
                permission: PermissionLevel.workspace,
                voiceInput: input,
                context_: ring ? const ContextUsage(42000, 128000, estimated: false) : null,
                onContext: ring ? () => calls.rings++ : null,
                onPlus: () => calls.plus++,
                onModel: () => calls.models++,
                onPermission: () => calls.permissions++,
                onSend: () => calls.sends++,
                onLongSend: () => calls.sends++,
                onStop: () => calls.stops++,
              ),
            ),
          ],
        ),
      ),
    ),
  );
  return (controller: controller, focus: focus, voice: input, calls: calls);
}

/// 模拟软键盘高度（逻辑像素；测试里像素比是 1）。
void _keyboard(WidgetTester tester, double height) {
  tester.view.viewInsets = FakeViewPadding(bottom: height);
}

/// 键盘升到 [height] 并停稳（过了“刚聚焦 / 刚升完”那一小段）。
Future<void> _risen(WidgetTester tester, [double height = 320]) async {
  _keyboard(tester, height);
  await tester.pump(const Duration(milliseconds: 500));
}

/// 看得见的胶囊（带边框的那一块，不含外边距）。
final Finder _capsule = find.descendant(of: find.byKey(const ValueKey('chat-input')), matching: find.byType(DecoratedBox)).first;

/// 展开态才有的“模型”按钮。
final Finder _expanded = find.byKey(const ValueKey('model-button'));

void main() {
  testWidgets('输入工具栏直接打开模型、权限和附件，文字就绪后可发送', (tester) async {
    final state = await _pump(tester);
    // 没点进去：收成一行，只有 ＋、提示、麦克风、发送
    expect(find.byKey(const ValueKey('plus-button')), findsOneWidget);
    expect(find.byKey(const ValueKey('voice-button')), findsOneWidget);
    expect(find.byKey(const ValueKey('send-button')), findsOneWidget);
    expect(find.byKey(const ValueKey('permission-button')), findsNothing);
    expect(find.byKey(const ValueKey('model-button')), findsNothing);
    expect(find.text('描述你的任务…'), findsOneWidget);
    final collapsedHeight = tester.getSize(find.byKey(const ValueKey('chat-input'))).height;

    // 点进去：展开成两行，权限和模型出现
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('permission-button')), findsOneWidget);
    expect(find.byKey(const ValueKey('model-button')), findsOneWidget);
    expect(find.byKey(const ValueKey('voice-button')), findsOneWidget);
    expect(tester.getSize(find.byKey(const ValueKey('chat-input'))).height, greaterThan(collapsedHeight));
    expect(tester.testTextInput.hasAnyClients, isTrue, reason: '换排法时输入框没丢焦点');

    await tester.tap(find.byKey(const ValueKey('model-button')));
    await tester.tap(find.byKey(const ValueKey('permission-button')));
    await tester.tap(find.byKey(const ValueKey('plus-button')));
    await tester.enterText(find.byType(TextField), '改一下首页');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('send-button')));
    await tester.pump();

    expect(state.calls.models, 1);
    expect(state.calls.permissions, 1);
    expect(state.calls.plus, 1);
    expect(state.calls.sends, 1);
  });

  testWidgets('语音结果接在已有草稿后面，发送前先停止识别', (tester) async {
    final voice = _FakeVoice();
    final state = await _pump(tester, voice: voice, draft: '帮我');
    await tester.tap(find.byKey(const ValueKey('voice-button')));
    await tester.pumpAndSettle();
    expect(voice.listening, isTrue);

    voice.emit('修改首页');
    await tester.pump();
    expect(state.controller.text, '帮我 修改首页');
    expect(find.byTooltip('停止语音输入'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('send-button')));
    await tester.pumpAndSettle();
    expect(voice.stopCalls, 1);
    expect(state.calls.sends, 1);

    state.controller.clear();
    voice.emit('迟到的尾部');
    await tester.pump();
    expect(state.controller.text, isEmpty);
  });

  testWidgets('设备不支持语音时保留草稿并说明原因', (tester) async {
    final voice = _FakeVoice()..available = false;
    final state = await _pump(tester, voice: voice, draft: '这段文字留着');
    await tester.tap(find.byKey(const ValueKey('voice-button')));
    await tester.pumpAndSettle();

    expect(state.controller.text, '这段文字留着');
    expect(voice.listening, isFalse);
    expect(find.textContaining('这台设备暂时不能语音输入'), findsOneWidget);
    expect(find.byTooltip('语音输入'), findsOneWidget);
  });

  testWidgets('识别失败后恢复麦克风状态，不丢已识别文字', (tester) async {
    final voice = _FakeVoice();
    final state = await _pump(tester, voice: voice);
    await tester.tap(find.byKey(const ValueKey('voice-button')));
    await tester.pumpAndSettle();
    voice.emit('你好');
    await tester.pump();
    voice.fail('没听清，请再说一次。');
    await tester.pump();

    expect(state.controller.text, '你好');
    expect(find.text('没听清，请再说一次。'), findsOneWidget);
    expect(find.byTooltip('语音输入'), findsOneWidget);
  });

  testWidgets('有草稿时即使没聚焦也保持展开；清空并失焦后收回一行', (tester) async {
    await _pump(tester);
    await tester.enterText(find.byType(TextField), '草稿');
    await tester.pumpAndSettle();
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('model-button')), findsOneWidget, reason: '有字就不收');

    await tester.enterText(find.byType(TextField), '');
    await tester.pumpAndSettle();
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('model-button')), findsNothing);
    expect(find.byKey(const ValueKey('plus-button')), findsOneWidget);
  });
  // 判定逻辑的单元测试和“一开始下降就失焦”的逐帧界面测试在 keyboard_dismiss_test.dart。
  group('软键盘收起后失焦', () {
    testWidgets('聚焦 → 键盘升起 → 键盘收起：失焦并收回一行；再点还能聚焦弹键盘', (tester) async {
      final state = await _pump(tester);
      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();
      expect(state.focus.hasFocus, isTrue);

      await _risen(tester);
      expect(state.focus.hasFocus, isTrue);
      expect(_expanded, findsOneWidget);

      _keyboard(tester, 0);
      await tester.pump();
      expect(state.focus.hasFocus, isFalse, reason: '键盘直接没了：立刻失焦，不再等');
      await tester.pumpAndSettle();
      expect(state.focus.hasFocus, isFalse);
      expect(_expanded, findsNothing, reason: '没草稿：收回一行胶囊');
      expect(tester.testTextInput.hasAnyClients, isFalse);

      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();
      expect(state.focus.hasFocus, isTrue);
      expect(tester.testTextInput.isVisible, isTrue, reason: '重新聚焦会再请求弹键盘');
      expect(_expanded, findsOneWidget);
      // 这次还没见过键盘（高度仍是 0）：不能马上又被摘掉
      await tester.pump(kKeyboardSettleSlow * 2);
      expect(state.focus.hasFocus, isTrue);
    });

    testWidgets('有草稿时键盘收起：失焦但保持展开，草稿不丢', (tester) async {
      final state = await _pump(tester);
      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();
      await _risen(tester);
      await tester.enterText(find.byType(TextField), '写到一半');
      await tester.pumpAndSettle();

      _keyboard(tester, 0);
      await tester.pump();
      expect(state.focus.hasFocus, isFalse);
      await tester.pumpAndSettle();
      expect(state.focus.hasFocus, isFalse);
      expect(_expanded, findsOneWidget);
      expect(state.controller.text, '写到一半');
    });

    testWidgets('键盘弹起过程中（0 → 逐渐变高）不失焦', (tester) async {
      final state = await _pump(tester);
      await tester.tap(find.byType(TextField));
      await tester.pump();
      // 刚聚焦的那几帧高度还是 0，系统也可能再报几次 0
      for (final h in <double>[0, 0, 12, 80, 200, 320]) {
        _keyboard(tester, h);
        await tester.pump(const Duration(milliseconds: 16));
        expect(state.focus.hasFocus, isTrue, reason: '高度 $h');
      }
      await tester.pump(kKeyboardSettleSlow * 2);
      expect(state.focus.hasFocus, isTrue);
      expect(_expanded, findsOneWidget);
    });

    testWidgets('从没出现过软键盘（实体键盘 / 桌面）：聚焦不被摘掉', (tester) async {
      final state = await _pump(tester);
      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();
      // 屏幕尺寸之类的变化也会报一次“键盘高度 0”
      _keyboard(tester, 0);
      await tester.pump(kKeyboardSettleSlow * 2);
      await tester.enterText(find.byType(TextField), 'abc');
      await tester.pump(kKeyboardSettleSlow * 2);
      expect(state.focus.hasFocus, isTrue);
      expect(state.controller.text, 'abc');
    });

    testWidgets('刚升完键盘就闪一下又回来：不失焦；停稳之后键盘没了（包括换另一个输入法）就立刻失焦', (tester) async {
      final state = await _pump(tester);
      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();
      _keyboard(tester, 320);
      await tester.pump();
      _keyboard(tester, 0);
      await tester.pump(const Duration(milliseconds: 80));
      _keyboard(tester, 300);
      await tester.pump(kKeyboardSettleSlow * 2);
      expect(state.focus.hasFocus, isTrue);

      // 已知取舍：停稳后键盘高度到 0 分不出是“收起”还是“换输入法闪一下”，一律当收起
      _keyboard(tester, 0);
      await tester.pump(const Duration(milliseconds: 80));
      expect(state.focus.hasFocus, isFalse);
    });

    testWidgets('语音输入进行中键盘收起：语音不被打断，仍保持展开', (tester) async {
      final voice = _FakeVoice();
      final state = await _pump(tester, voice: voice);
      await tester.tap(find.byKey(const ValueKey('voice-button')));
      await tester.pumpAndSettle();
      expect(voice.listening, isTrue);
      // 听写时又点进输入框，键盘升起后被收起
      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();
      await _risen(tester);
      _keyboard(tester, 0);
      await tester.pump();
      await tester.pumpAndSettle();

      expect(state.focus.hasFocus, isFalse);
      expect(voice.listening, isTrue);
      expect(voice.stopCalls, 0);
      expect(find.byTooltip('停止语音输入'), findsOneWidget);
      expect(_expanded, findsOneWidget);
      voice.emit('继续听写');
      await tester.pump();
      expect(state.controller.text, '继续听写');
    });

    testWidgets('转屏：键盘跟着回来就不失焦；一直没回来才失焦', (tester) async {
      final state = await _pump(tester);
      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();
      await _risen(tester);

      // 横过来：键盘先消失一下，再按新尺寸回来
      tester.view.physicalSize = const Size(844, 390);
      _keyboard(tester, 0);
      await tester.pump(kKeyboardSettle + const Duration(milliseconds: 50));
      expect(state.focus.hasFocus, isTrue, reason: '刚转屏要多等一会儿');
      _keyboard(tester, 200);
      await tester.pump(kKeyboardSettleSlow * 2);
      expect(state.focus.hasFocus, isTrue);

      // 竖回去：键盘这次没回来
      tester.view.physicalSize = kPhone;
      _keyboard(tester, 0);
      await tester.pump(kKeyboardSettleSlow + const Duration(milliseconds: 10));
      await tester.pumpAndSettle();
      expect(state.focus.hasFocus, isFalse);
      expect(_expanded, findsNothing);
    });

    testWidgets('切到别的应用再回来：键盘回来了保持聚焦，之后收起键盘照样失焦', (tester) async {
      final state = await _pump(tester);
      addTearDown(() => tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed));
      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();
      await _risen(tester);

      for (final s in const [AppLifecycleState.inactive, AppLifecycleState.hidden, AppLifecycleState.paused]) {
        tester.binding.handleAppLifecycleStateChanged(s);
      }
      _keyboard(tester, 0);
      await tester.pump(kKeyboardSettleSlow * 2);
      for (final s in const [AppLifecycleState.hidden, AppLifecycleState.inactive, AppLifecycleState.resumed]) {
        tester.binding.handleAppLifecycleStateChanged(s);
      }
      await tester.pump(const Duration(milliseconds: 100));
      _keyboard(tester, 320);
      await tester.pump(kKeyboardSettleSlow * 2);
      expect(state.focus.hasFocus, isTrue, reason: '离开前台期间键盘消失不算用户收起');
      expect(_expanded, findsOneWidget);

      _keyboard(tester, 0);
      await tester.pump();
      expect(state.focus.hasFocus, isFalse, reason: '回到前台并停稳之后，收起键盘立刻失焦');
      await tester.pumpAndSettle();
      expect(_expanded, findsNothing);
    });
  });

  group('胶囊尺寸', () {
    testWidgets('收起态连边框高 48，带不带用量小环都一样；各可点目标不小于 44×44', (tester) async {
      await _pump(tester);
      expect(tester.getSize(_capsule).height, 48);

      final state = await _pump(tester, ring: true, busy: true);
      final capsule = tester.getRect(_capsule);
      expect(capsule.height, 48);
      expect(_expanded, findsNothing);
      expect(tester.takeException(), isNull);

      for (final key in const [ValueKey('plus-button'), Key('context-ring'), ValueKey('voice-button')]) {
        final size = tester.getSize(find.byKey(key));
        expect(size.width, greaterThanOrEqualTo(44), reason: '$key 宽');
        expect(size.height, greaterThanOrEqualTo(44), reason: '$key 高');
        expect(capsule.contains(tester.getRect(find.byKey(key)).topLeft) && capsule.contains(tester.getRect(find.byKey(key)).bottomRight), isTrue, reason: '$key 在胶囊里');
      }
      // 提示文字和各图标垂直居中
      for (final f in [find.byKey(const ValueKey('plus-button')), find.byKey(const ValueKey('send-button')), find.byType(EditableText)]) {
        expect(tester.getCenter(f).dy, moreOrLessEquals(capsule.center.dy, epsilon: 0.6));
      }

      // 点每个目标 44×44 范围的角上也算数
      const corner = Offset(21, 21);
      await tester.tapAt(tester.getCenter(find.byKey(const ValueKey('plus-button'))) - corner);
      await tester.tapAt(tester.getCenter(find.byKey(const ValueKey('plus-button'))) + corner);
      expect(state.calls.plus, 2);
      await tester.tapAt(tester.getCenter(find.byKey(const Key('context-ring'))) - corner);
      await tester.tapAt(tester.getCenter(find.byKey(const Key('context-ring'))) + corner);
      expect(state.calls.rings, 2);
      // 发送圆钮看着是 36，点它外圈（44 的角上）也要生效；这里是“停止”
      await tester.tapAt(tester.getCenter(find.byKey(const ValueKey('send-button'))) - corner);
      await tester.tapAt(tester.getCenter(find.byKey(const ValueKey('send-button'))) + corner);
      expect(state.calls.stops, 2);
      await tester.tapAt(tester.getCenter(find.byKey(const ValueKey('voice-button'))) - corner);
      await tester.pumpAndSettle();
      expect(state.voice.listening, isTrue);
    });

    testWidgets('展开态：发送的可点范围同样是 44×44，各按钮不小于 44', (tester) async {
      final state = await _pump(tester, draft: '改一下首页', ring: true);
      expect(_expanded, findsOneWidget);
      const corner = Offset(21, 21);
      await tester.tapAt(tester.getCenter(find.byKey(const ValueKey('send-button'))) - corner);
      await tester.tapAt(tester.getCenter(find.byKey(const ValueKey('send-button'))) + corner);
      expect(state.calls.sends, 2);
      for (final key in const [ValueKey('plus-button'), ValueKey('permission-button'), ValueKey('model-button'), Key('context-ring'), ValueKey('voice-button')]) {
        final size = tester.getSize(find.byKey(key));
        expect(size.height, greaterThanOrEqualTo(44), reason: '$key 高');
        expect(size.width, greaterThanOrEqualTo(44), reason: '$key 宽');
      }
      expect(tester.takeException(), isNull);
    });
  });
}
