// 终端软键盘输入：提交的字立刻进会话；攒着的字画在光标后面、不被光标挡住；回车、退格都送达。
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/terminal/terminal_input.dart';
import 'package:lopicode/terminal/terminal_session.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xterm/xterm.dart';

import 'support/harness.dart';
import 'support/runtime_fakes.dart';

class PtyBackend implements TerminalBackend {
  PtyBackend(this.pty);
  final FakePty pty;
  @override
  String get label => '测试';
  @override
  Stream<String> get output => pty.output.transform(const Utf8Decoder(allowMalformed: true));
  @override
  Future<void> start({required int columns, required int rows}) async {}
  @override
  void write(String data) => pty.write(utf8.encode(data));
  @override
  void resize(int columns, int rows) {}
  @override
  Future<void> close() async {}
  @override
  bool get isRunning => true;
}

TextEditingValue composing(String text) => TextEditingValue(
  text: '  $text',
  selection: TextSelection.collapsed(offset: 2 + text.length),
  composing: TextRange(start: 2, end: 2 + text.length),
);
TextEditingValue committed(String text) =>
    TextEditingValue(text: '  $text', selection: TextSelection.collapsed(offset: 2 + text.length));

void main() {
  group('ImeTranslator（输入法内容 → 终端按键）', () {
    late List<String> log;
    late ImeTranslator ime;
    setUp(() {
      log = [];
      ime = ImeTranslator(onText: (t) => log.add('T:$t'), onBackspace: () => log.add('BS'), onEnter: () => log.add('CR'));
    });

    test('直接提交的字立刻写入，并要求重置编辑框', () {
      expect(ime.update(committed('l')), isTrue);
      expect(log, ['T:l']);
    });

    test('直接输入模式：输入法把英文字母攒着不提交，也边打边写进终端', () {
      expect(ime.update(composing('l')), isFalse);
      expect(ime.update(composing('ls')), isFalse);
      expect(log, ['T:l', 'T:s'], reason: '不能等到提交才写入');
      expect(ime.pending, isEmpty, reason: '已经进终端的字不再另画一份');
      // 提交时内容没变：不重复写
      expect(ime.update(committed('ls')), isTrue);
      expect(log, ['T:l', 'T:s']);
    });

    test('攒着的英文被输入法改了（联想替换）：退掉不一样的部分再补', () {
      ime.update(composing('gti'));
      log.clear();
      ime.update(committed('git '));
      expect(log, ['BS', 'BS', 'T:it ']);
    });

    test('攒着的时候按退格：终端里也退一格', () {
      ime.update(composing('ls'));
      log.clear();
      ime.update(composing('l'));
      expect(log, ['BS']);
      // 攒着的全删光
      ime.update(const TextEditingValue(text: '  ', selection: TextSelection.collapsed(offset: 2)));
      expect(log, ['BS', 'BS']);
    });

    test('拼音选字：攒着的不写入，选定后一次写入', () {
      ime.mode = TerminalImeMode.chinese;
      ime.update(composing('ni'));
      ime.update(composing('nihao'));
      expect(log, isEmpty);
      expect(ime.pending, 'nihao');
      expect(ime.update(committed('你好')), isTrue);
      expect(log, ['T:你好']);
      expect(ime.pending, isEmpty);
    });

    test('直接输入模式下攒的是中文：不提前写，等选定', () {
      ime.update(composing('你'));
      expect(log, isEmpty);
      expect(ime.pending, '你');
      ime.update(committed('你好'));
      expect(log, ['T:你好']);
    });

    test('先攒了英文、输入法又换成中文候选：把提前写的退掉', () {
      ime.update(composing('ni'));
      ime.update(composing('你'));
      expect(log, ['T:ni', 'BS', 'BS']);
      expect(ime.pending, '你');
    });

    test('垫的空格被删：是退格', () {
      expect(ime.update(const TextEditingValue(text: ' ', selection: TextSelection.collapsed(offset: 1))), isTrue);
      expect(log, ['BS']);
    });

    test('输入法把回车当字符塞进来：变成回车键；动作键也是回车', () {
      ime.update(committed('ls\n'));
      expect(log, ['T:ls', 'CR']);
      log.clear();
      ime.action();
      expect(log, ['CR']);
    });
  });

  group('TerminalInputView（390×844）', () {
    late FakePty pty;
    late TerminalSession session;
    late FocusNode focus;

    Future<void> mount(WidgetTester tester, {TerminalImeMode mode = TerminalImeMode.direct}) async {
      usePhoneViewport(tester);
      pty = FakePty();
      session = TerminalSession(title: '测试', backend: PtyBackend(pty));
      focus = FocusNode();
      addTearDown(focus.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TerminalInputView(
              session: session,
              focusNode: focus,
              theme: TerminalThemes.defaultTheme,
              textStyle: const TerminalStyle(fontSize: 13, height: 1.3),
              padding: const EdgeInsets.all(8),
              mode: mode,
            ),
          ),
        ),
      );
      await tester.pump();
      await session.ensureStarted();
      session.append('\$ ');
      await tester.pump();
    }

    String written() => utf8.decode(pty.written);

    testWidgets('点一下屏幕：拿到焦点、弹出键盘；直接输入用“可见密码”键盘类型', (tester) async {
      await mount(tester);
      expect(focus.hasFocus, isFalse);
      expect(tester.testTextInput.isVisible, isFalse);
      await tester.tapAt(const Offset(200, 300));
      await tester.pump(const Duration(milliseconds: 400)); // 过了双击的判定时间
      expect(focus.hasFocus, isTrue, reason: '有焦点光标才是实心的');
      expect(tester.testTextInput.isVisible, isTrue);
      expect(tester.testTextInput.setClientArgs!['inputType']['name'], 'TextInputType.visiblePassword');
      expect(tester.testTextInput.setClientArgs!['inputAction'], 'TextInputAction.done');

      // 键盘被用户收起后（焦点还在），再点一下要能重新弹出来
      tester.testTextInput.hide();
      expect(tester.testTextInput.isVisible, isFalse);
      await tester.tapAt(const Offset(200, 300));
      await tester.pump(const Duration(milliseconds: 400)); // 过了双击的判定时间
      expect(tester.testTextInput.isVisible, isTrue);
    });

    testWidgets('软键盘打字、回车、退格都写进会话；攒着的英文也立刻写入', (tester) async {
      await mount(tester);
      await tester.tapAt(const Offset(200, 300));
      await tester.pump(const Duration(milliseconds: 400)); // 过了双击的判定时间
      tester.testTextInput.updateEditingValue(committed('l'));
      await tester.pump();
      expect(written(), 'l');
      // 输入法攒着不提交
      tester.testTextInput.updateEditingValue(composing('s'));
      await tester.pump();
      expect(written(), 'ls', reason: '预编辑状态的英文也要立刻进终端');
      expect(find.byKey(const Key('terminal-composing')), findsNothing);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(written(), 'ls\r');
      tester.testTextInput.updateEditingValue(const TextEditingValue(text: ' ', selection: TextSelection.collapsed(offset: 1)));
      await tester.pump();
      expect(written(), 'ls\r\x7f');
      // 换行动作（有的输入法发 newline）也算回车
      await tester.testTextInput.receiveAction(TextInputAction.newline);
      expect(written(), 'ls\r\x7f\r');
    });

    testWidgets('中文输入：攒着的字从光标格开始画，光标跟到字的后面，不挡第一个字', (tester) async {
      await mount(tester, mode: TerminalImeMode.chinese);
      await tester.tapAt(const Offset(200, 300));
      await tester.pump(const Duration(milliseconds: 400)); // 过了双击的判定时间
      expect(tester.testTextInput.setClientArgs!['inputType']['name'], 'TextInputType.text');

      final view = tester.state<TerminalViewState>(find.byType(TerminalView));
      final cell = view.globalCursorRect;

      tester.testTextInput.updateEditingValue(composing('ni'));
      await tester.pump();
      expect(written(), isEmpty, reason: '拼音还没选字，不写入');
      final text1 = tester.getRect(find.byKey(const Key('terminal-composing-text')));
      final cursor1 = tester.getRect(find.byKey(const Key('terminal-composing-cursor')));
      expect(text1.left, moreOrLessEquals(cell.left, epsilon: 0.5), reason: '字从原来光标所在的格子开始');
      expect(text1.top, moreOrLessEquals(cell.top, epsilon: 0.5));
      expect(cursor1.left, greaterThanOrEqualTo(text1.right - 0.01), reason: '光标在字的后面，不盖住任何一个字');

      tester.testTextInput.updateEditingValue(composing('nihao'));
      await tester.pump();
      final cursor2 = tester.getRect(find.byKey(const Key('terminal-composing-cursor')));
      expect(cursor2.left, greaterThan(cursor1.left), reason: '字变多，光标跟着往后走');

      tester.testTextInput.updateEditingValue(committed('你好'));
      await tester.pump();
      expect(written(), '你好');
      expect(find.byKey(const Key('terminal-composing')), findsNothing);
    });

    testWidgets('终端回显后光标前进（写进去的字由 shell 回显，光标随之移动）', (tester) async {
      await mount(tester);
      final view = tester.state<TerminalViewState>(find.byType(TerminalView));
      final before = view.globalCursorRect.left;
      session.append('ls');
      await tester.pump();
      expect(view.globalCursorRect.left, greaterThan(before));
    });
  });
}
