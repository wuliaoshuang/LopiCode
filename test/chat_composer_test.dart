import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/agent/agent_tools.dart';
import 'package:lopicode/theme/app_theme.dart';
import 'package:lopicode/ui/chat_composer.dart';
import 'package:material_ui/material_ui.dart';

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
}

Future<({TextEditingController controller, _FakeVoice voice, _Calls calls})> _pump(WidgetTester tester, {_FakeVoice? voice, bool busy = false, String draft = ''}) async {
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
                onPlus: () => calls.plus++,
                onModel: () => calls.models++,
                onPermission: () => calls.permissions++,
                onSend: () => calls.sends++,
                onLongSend: () => calls.sends++,
                onStop: () {},
              ),
            ),
          ],
        ),
      ),
    ),
  );
  return (controller: controller, voice: input, calls: calls);
}

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
}
