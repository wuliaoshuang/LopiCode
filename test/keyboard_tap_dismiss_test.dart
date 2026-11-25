// 点输入框外面的空白收键盘（霜霜真机反馈第四轮第 3 条，390×844）。
// 规则在 lib/ui/keyboard_tap_dismiss.dart；这里逐条钉住“该收的收、不该收的不收”。
import 'dart:convert';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/agent/chat_client.dart';
import 'package:lopicode/agent/model_config.dart';
import 'package:lopicode/core/project_store.dart';
import 'package:lopicode/core/templates.dart';
import 'package:lopicode/project_session.dart';
import 'package:lopicode/terminal/terminal_input.dart';
import 'package:lopicode/terminal/terminal_session.dart';
import 'package:lopicode/ui/chat_screen.dart';
import 'package:lopicode/ui/files_tab.dart';
import 'package:lopicode/ui/keyboard_dismiss.dart';
import 'package:lopicode/ui/keyboard_tap_dismiss.dart';
import 'package:lopicode/ui/mcp_edit_screen.dart';
import 'package:lopicode/ui/project_shell.dart';
import 'package:lopicode/ui/shell.dart';
import 'package:lopicode/ui/widgets.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xterm/xterm.dart';

import 'support/harness.dart';
import 'support/runtime_fakes.dart';

const double kKeyboard = 320;

class _PtyBackend implements TerminalBackend {
  _PtyBackend(this.pty);
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

void setKeyboard(WidgetTester tester, double inset) => tester.view.viewInsets = FakeViewPadding(bottom: inset);

/// 现在拿着焦点的是不是聊天输入框。
bool chatFocused(WidgetTester tester) {
  final field = find.descendant(of: find.byKey(const ValueKey('chat-input')), matching: find.byType(EditableText));
  return tester.widget<EditableText>(field).focusNode.hasPrimaryFocus;
}

/// 有系统输入框拿着焦点（键盘开着）。
bool anyFieldFocused() => FocusManager.instance.primaryFocus?.context?.widget is EditableText || (FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<EditableText>() != null);

void main() {
  late TestEnv env;
  late Project project;
  late ProjectSession session;

  /// 进聊天页；[turns] 轮对话把列表撑到能滚。
  Future<void> openChat(WidgetTester tester, {int turns = 3}) async {
    usePhoneViewport(tester);
    debugKeyboardNow = () => Duration(microseconds: tester.binding.clock.now().microsecondsSinceEpoch);
    addTearDown(() => debugKeyboardNow = null);
    addTearDown(tester.view.resetViewInsets);
    final long = List.filled(14, '这是一段比较长的回复，用来把聊天列表撑到一屏以上。').join('\n');
    await tester.runAsync(() async {
      env = await TestEnv.create(
        chatClient: () => ScriptedChatClient([
          for (var i = 0; i < 8; i++) [say(long), ChatDelta(finishReason: 'stop')],
        ]),
      );
      await env.services.models.upsert(
        name: '我的中转站',
        protocol: ChatProtocol.openaiChat,
        baseUrl: 'https://relay.example.cn/v1',
        apiKey: 'test',
        models: [ModelSpec(id: 'some-model', contextLength: 128000)],
      );
      project = await env.services.projects.create('我的小站', ProjectTemplate.web);
      session = ProjectSession(env.services, project);
      await session.loadChat();
      for (var i = 0; i < turns; i++) {
        await session.sendToAgent('第 ${i + 1} 个问题');
      }
      await Future<void>.delayed(const Duration(milliseconds: 150));
    });
    addTearDown(() async {
      session.dispose();
      await env.dispose();
    });
    await tester.pumpWidget(appFor(env, ProjectShell(project: project, session: session)));
    await settle(tester);
  }

  /// 点聊天输入框里打字的那一块（不是整个输入栏的中心：展开时中心落在工具栏上，收放动画中途落在留白上）。
  Future<void> tapChatField(WidgetTester tester) async {
    await tester.tap(find.descendant(of: find.byKey(const ValueKey('chat-input')), matching: find.byType(EditableText)));
    await tester.pump();
  }

  /// 点进输入框，键盘升起并停稳。
  Future<void> focusChat(WidgetTester tester) async {
    await tapChatField(tester);
    setKeyboard(tester, kKeyboard);
    await tester.pump(const Duration(milliseconds: 600));
    expect(chatFocused(tester), isTrue, reason: '前提：输入框已聚焦');
    expect(tester.testTextInput.isVisible, isTrue, reason: '前提：键盘已弹出');
  }

  /// 聊天列表左边留白里的一点：不在任何气泡、文字、按钮上。
  const blank = Offset(6, 300);

  group('根因', () {
    testWidgets('Flutter 在安卓上的默认行为：手指点输入框外面不失焦（所以她只能按键盘上的收起键）', (tester) async {
      usePhoneViewport(tester);
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                TextField(key: Key('f')),
                Expanded(child: SizedBox.expand()),
              ],
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('f')));
      await tester.pump();
      expect(anyFieldFocused(), isTrue);
      await tester.tapAt(const Offset(195, 600));
      await tester.pump();
      expect(anyFieldFocused(), isTrue, reason: '没有 KeyboardTapDismiss 时就是点不掉——这条钉住根因；哪天 Flutter 改了默认行为这里会提醒');
    });

    testWidgets('同一个页面包上 KeyboardTapDismiss：点外面就失焦；鼠标按下立刻失焦', (tester) async {
      usePhoneViewport(tester);
      await tester.pumpWidget(
        const MaterialApp(
          home: KeyboardTapDismiss(
            child: Scaffold(
              body: Column(
                children: [
                  TextField(key: Key('f')),
                  Expanded(child: SizedBox.expand()),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('f')));
      await tester.pump();
      final g = await tester.startGesture(const Offset(195, 600));
      await tester.pump();
      expect(anyFieldFocused(), isTrue, reason: '按下时还不收，抬手才收');
      await g.up();
      await tester.pump();
      expect(anyFieldFocused(), isFalse);

      await tester.tap(find.byKey(const Key('f')));
      await tester.pump();
      expect(anyFieldFocused(), isTrue);
      final m = await tester.startGesture(const Offset(195, 600), kind: PointerDeviceKind.mouse);
      await tester.pump();
      expect(anyFieldFocused(), isFalse, reason: '鼠标照系统原来的做法：按下就失焦');
      await m.up();
    });
  });

  group('聊天页', () {
    testWidgets('聚焦后点列表空白 → 失焦、键盘收起；再点输入框能重新弹出键盘', (tester) async {
      await openChat(tester);
      await focusChat(tester);
      await tester.tapAt(blank);
      await tester.pump();
      expect(chatFocused(tester), isFalse, reason: '点空白要失焦');
      expect(tester.testTextInput.isVisible, isFalse, reason: '键盘收起');
      expect(find.byKey(const ValueKey('model-button')), findsNothing, reason: '没草稿：输入栏收回一行');

      // 键盘还在往下走的时候就又点输入框：能重新聚焦，不被“键盘在下降”再摘掉
      for (final k in [300.0, 240.0, 160.0]) {
        setKeyboard(tester, k);
        await tester.pump(const Duration(milliseconds: 16));
      }
      await tapChatField(tester);
      for (final k in [100.0, 60.0, 120.0, 240.0, 320.0]) {
        setKeyboard(tester, k);
        await tester.pump(const Duration(milliseconds: 16));
      }
      await tester.pump(const Duration(milliseconds: 700));
      expect(chatFocused(tester), isTrue, reason: '重新点输入框后保持聚焦');
      expect(tester.testTextInput.isVisible, isTrue);
      expect(tester.takeException(), isNull);
    });

    testWidgets('点空白失焦后，键盘一路降到 0：没有别的副作用（草稿、展开状态都不变）', (tester) async {
      await openChat(tester);
      await focusChat(tester);
      await tester.enterText(find.byType(TextField), '写到一半');
      await tester.pump();
      await tester.tapAt(blank);
      await tester.pump();
      expect(chatFocused(tester), isFalse);
      for (final k in [310.0, 250.0, 170.0, 90.0, 30.0, 0.0]) {
        setKeyboard(tester, k);
        await tester.pump(const Duration(milliseconds: 16));
      }
      await tester.pump(const Duration(milliseconds: 800));
      expect(chatFocused(tester), isFalse);
      expect(find.text('写到一半'), findsOneWidget, reason: '草稿不丢');
      expect(find.byKey(const ValueKey('model-button')), findsOneWidget, reason: '有草稿保持展开');
      expect(tester.takeException(), isNull);
    });

    testWidgets('点发送：消息发出去，输入框不失焦、键盘不收', (tester) async {
      await openChat(tester, turns: 1);
      await focusChat(tester);
      await tester.enterText(find.byType(TextField), '再问一句');
      await tester.pump();
      final before = session.chat.length;
      await tester.tap(find.byKey(const ValueKey('send-button')));
      await tester.pump();
      expect(chatFocused(tester), isTrue, reason: '发送不收键盘，可以接着打字');
      expect(tester.testTextInput.isVisible, isTrue);
      await settle(tester);
      expect(session.chat.length, greaterThan(before), reason: '消息真的发出去了');
      expect(chatFocused(tester), isTrue, reason: '回复流式输出、列表自动滚到底：不收键盘');
    });

    testWidgets('点输入区工具栏的按钮：按下抬起都不失焦，按钮照常打开自己的面板', (tester) async {
      await openChat(tester, turns: 1);
      await focusChat(tester);
      for (final key in ['plus-button', 'permission-button', 'model-button']) {
        final g = await tester.startGesture(tester.getCenter(find.byKey(ValueKey(key))));
        await g.up();
        expect(chatFocused(tester), isTrue, reason: '$key：点它不该把输入框的焦点摘掉');
        await tester.pumpAndSettle();
        expect(find.byType(BottomSheet), findsOneWidget, reason: '$key：面板照常打开');
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.byType(BottomSheet), findsNothing);
        if (!chatFocused(tester)) await focusChat(tester);
      }
    });

    testWidgets('点输入框上方的候选列表（/ 指令）：不失焦', (tester) async {
      await openChat(tester, turns: 1);
      await focusChat(tester);
      await tester.enterText(find.byType(TextField), '/pl');
      await tester.pump();
      expect(find.text('/plan'), findsOneWidget);
      await tester.tap(find.text('/plan'));
      await tester.pump();
      expect(chatFocused(tester), isTrue, reason: '候选列表在输入区里');
      await settle(tester);
      expect(session.planMode, isTrue, reason: '指令照常执行');
      // 计划模式提示条也在输入区里：点“退出”不收键盘
      await tester.tap(find.text('退出'));
      await tester.pump();
      expect(chatFocused(tester), isTrue);
      await settle(tester);
      expect(session.planMode, isFalse);
    });

    testWidgets('手指拖动聊天列表：照常滚动，并收键盘', (tester) async {
      await openChat(tester);
      await focusChat(tester);
      final pos = tester.state<ScrollableState>(find.descendant(of: find.byType(ChatScreen), matching: find.byType(Scrollable)).first).position;
      expect(pos.maxScrollExtent, greaterThan(200), reason: '前提：列表能滚');
      final start = pos.pixels;
      await tester.dragFrom(const Offset(195, 250), const Offset(0, -120));
      await tester.pump();
      expect(pos.pixels, greaterThan(start + 60), reason: '滚动没被吞');
      expect(chatFocused(tester), isFalse, reason: '拖动聊天内容收键盘');
      expect(tester.takeException(), isNull);

      // 已经在最顶上还往下拉（列表不动，只有越界回弹）：一样收
      pos.jumpTo(0);
      await tester.pump();
      await focusChat(tester);
      await tester.dragFrom(const Offset(195, 250), const Offset(0, 120));
      await tester.pump();
      expect(chatFocused(tester), isFalse, reason: '拉到头了也算在拖聊天内容');
      await tester.pumpAndSettle();
    });

    testWidgets('程序自己滚（流式输出自动滚到底）不收键盘', (tester) async {
      await openChat(tester);
      await focusChat(tester);
      final pos = tester.state<ScrollableState>(find.descendant(of: find.byType(ChatScreen), matching: find.byType(Scrollable)).first).position;
      pos.jumpTo(pos.maxScrollExtent - 150);
      await tester.pump();
      pos.jumpTo(pos.maxScrollExtent);
      await tester.pump();
      expect(chatFocused(tester), isTrue);
    });

    testWidgets('输入框里的字多了，在输入框里上下拖着看：不收键盘', (tester) async {
      await openChat(tester);
      await focusChat(tester);
      await tester.enterText(find.byType(TextField), List.generate(12, (i) => '第 $i 行').join('\n'));
      await tester.pump();
      await tester.dragFrom(tester.getCenter(find.descendant(of: find.byKey(const ValueKey('chat-input')), matching: find.byType(EditableText))), const Offset(0, 60));
      await tester.pump();
      expect(chatFocused(tester), isTrue);
      expect(tester.takeException(), isNull);
    });

    testWidgets('在空白处长按、横着拖、双指捏：都不收键盘', (tester) async {
      await openChat(tester);
      await focusChat(tester);
      // 长按：事件自带的时间走过了 500ms
      final g = await tester.startGesture(blank);
      await tester.pump(const Duration(milliseconds: 600));
      await g.up(timeStamp: const Duration(milliseconds: 600));
      await tester.pump();
      expect(chatFocused(tester), isTrue, reason: '长按不是轻点');
      // 横着拖（列表不滚）
      await tester.dragFrom(const Offset(120, 300), const Offset(80, 0));
      await tester.pump();
      expect(chatFocused(tester), isTrue, reason: '横向拖动不收');
      // 双指
      final a = await tester.startGesture(const Offset(6, 260), pointer: 71);
      final b = await tester.startGesture(const Offset(6, 340), pointer: 72);
      await a.up();
      await b.up();
      await tester.pump();
      expect(chatFocused(tester), isTrue, reason: '双指手势不收');
      // 之后轻点一下照常收
      await tester.tapAt(blank);
      await tester.pump();
      expect(chatFocused(tester), isFalse);
    });

    testWidgets('长按消息文字选字：选得上，不被打断', (tester) async {
      await openChat(tester);
      await focusChat(tester);
      final msg = find.descendant(of: find.byType(ChatScreen), matching: find.byType(SelectableText)).first;
      await tester.longPress(msg);
      await tester.pump(const Duration(milliseconds: 300));
      final sel = tester.widget<EditableText>(find.descendant(of: msg, matching: find.byType(EditableText))).controller.selection;
      expect(sel.isValid && !sel.isCollapsed, isTrue, reason: '长按选中了一个词');
      expect(tester.takeException(), isNull);
      // 选中状态下再去拖动列表、等几帧：选区还在
      await tester.pump(const Duration(milliseconds: 300));
      final sel2 = tester.widget<EditableText>(find.descendant(of: msg, matching: find.byType(EditableText))).controller.selection;
      expect(sel2, sel);
    });

    testWidgets('点顶栏按钮：按钮照常响应；点汉堡打开侧边栏照旧收键盘', (tester) async {
      await openChat(tester);
      await focusChat(tester);
      await tester.tap(find.byTooltip('更多'));
      await tester.pumpAndSettle();
      expect(find.text('导出对话'), findsOneWidget, reason: '同一下点击：菜单照常弹出');
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      if (!chatFocused(tester)) await focusChat(tester);
      final left = tester.getRect(find.byType(ChatScreen)).left;
      await tester.tap(find.byTooltip('打开侧边栏').hitTestable());
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(chatFocused(tester), isFalse);
      expect(tester.getRect(find.byType(ChatScreen)).left, greaterThan(left + 100), reason: '侧边栏照常推开');
    });
  });

  group('表单页、对话框', () {
    Future<void> show(WidgetTester tester, Widget page) async {
      usePhoneViewport(tester);
      await tester.runAsync(() async => env = await TestEnv.create());
      addTearDown(() => env.dispose());
      await tester.pumpWidget(appFor(env, page));
      await settle(tester);
    }

    testWidgets('设置表单页（MCP 服务器）：点空白失焦；点另一个输入框是换焦点不是收键盘；点按钮照常响应并收键盘', (tester) async {
      await show(tester, const McpServerEditScreen());
      final name = find.byKey(const Key('mcp-name'));
      final url = find.byKey(const Key('mcp-url'));
      bool focusedIn(Finder f) => tester.widget<EditableText>(find.descendant(of: f, matching: find.byType(EditableText))).focusNode.hasPrimaryFocus;

      await tester.tap(name);
      await tester.pump();
      expect(focusedIn(name), isTrue);
      await tester.tap(url);
      await tester.pump();
      expect(focusedIn(url), isTrue, reason: '点另一个输入框：焦点换过去');
      expect(tester.testTextInput.isVisible, isTrue, reason: '键盘一直开着');

      // 两个输入框之间的缝 / 页面右边缘：空白
      final r = tester.getRect(url);
      await tester.tapAt(Offset(2, r.bottom + 4));
      await tester.pump();
      expect(focusedIn(url), isFalse, reason: '点空白失焦');
      expect(tester.testTextInput.isVisible, isFalse);

      // 表单页拖动不收：要一边看键盘一边翻
      await tester.tap(name);
      await tester.pump();
      await tester.dragFrom(const Offset(195, 500), const Offset(0, -80));
      await tester.pump();
      expect(focusedIn(name), isTrue, reason: '普通表单页拖动滚动不收键盘');

      // 点表单里别的控件（连接方式的分段按钮）：它照常响应，同时收键盘
      final seg = find.byKey(const Key('mcp-transport'));
      await tester.ensureVisible(seg);
      await tester.pump();
      if (!focusedIn(name)) {
        await tester.tap(name);
        await tester.pump();
      }
      // ignore: avoid_dynamic_calls — 只读一下选中项，不想为它引入 MCP 的类型
      Object selected() => (tester.widget(seg) as dynamic).selected.first as Object;
      final before = selected();
      await tester.tap(find.descendant(of: seg, matching: find.byType(Text)).last);
      await tester.pump();
      expect(selected(), isNot(before), reason: '同一下点击，分段按钮照常切换');
      expect(anyFieldFocused(), isFalse, reason: '点表单里别的控件：收键盘');
      expect(tester.takeException(), isNull);
    });

    testWidgets('对话框里的输入框：点对话框里的空白收键盘、对话框还在；点“确定”照常提交', (tester) async {
      String? result;
      await show(
        tester,
        Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async => result = await promptDialog(context, title: '新建文件', hint: '文件名'),
                child: const Text('开'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('开'));
      await tester.pumpAndSettle();
      expect(anyFieldFocused(), isTrue, reason: '对话框一打开输入框就聚焦');
      await tester.enterText(find.byType(TextField), 'a.txt');
      await tester.tap(find.text('新建文件')); // 标题：对话框里的空白处
      await tester.pump();
      expect(anyFieldFocused(), isFalse);
      expect(find.byType(AlertDialog), findsOneWidget, reason: '只收键盘，不关对话框');
      await tester.tap(find.byType(TextField));
      await tester.pump();
      expect(anyFieldFocused(), isTrue, reason: '再点输入框能回来');
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();
      expect(result, 'a.txt');
    });

    testWidgets('KeyboardKeep 包住的按钮：点了不收键盘，按钮照常响应', (tester) async {
      var taps = 0;
      await show(
        tester,
        Scaffold(
          body: Column(
            children: [
              const SizedBox(height: 120),
              const TextField(key: Key('f')),
              KeyboardKeep(
                child: TextButton(onPressed: () => taps++, child: const Text('插入')),
              ),
              TextButton(onPressed: () => taps += 10, child: const Text('别的')),
            ],
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('f')));
      await tester.pump();
      await tester.tap(find.text('插入'));
      await tester.pump();
      expect(taps, 1);
      expect(anyFieldFocused(), isTrue);
      await tester.tap(find.text('别的'));
      await tester.pump();
      expect(taps, 11);
      expect(anyFieldFocused(), isFalse);
    });
  });

  group('约定（AGENTS.md“点输入框外面的空白收键盘”那一条）', () {
    test('全应用只接一处：lib/app.dart 包着 KeyboardTapDismiss；没有页面自己传 onTapOutside 把规则顶掉', () {
      expect(File('lib/app.dart').readAsStringSync(), contains('KeyboardTapDismiss('));
      final offenders = <String>[];
      for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
        final path = f.path.replaceAll(r'\', '/');
        if (path.endsWith('ui/keyboard_tap_dismiss.dart')) continue;
        // @ 文件候选列表：它不是输入框，是和输入框同组的点按区域，用 onTapOutside 只为了“点到外面就收起候选”，不碰焦点和键盘。
        if (path.endsWith('ui/file_mention.dart')) continue;
        final src = f.readAsStringSync();
        if (RegExp(r'\bonTapOutside\s*:').hasMatch(src) || RegExp(r'\bonTapUpOutside\s*:').hasMatch(src)) offenders.add(path);
      }
      expect(offenders, isEmpty, reason: '输入框不要自己传 onTapOutside：要留住键盘用 KeyboardKeep / KeyboardDock');
    });

    test('聊天页的 KeyboardDock 紧跟在聊天内容后面、在输入区各条之前（挪走就失效）', () {
      final src = File('lib/ui/chat_screen.dart').readAsStringSync();
      final dock = src.indexOf('const KeyboardDock()');
      expect(dock, greaterThan(0));
      expect(RegExp('const KeyboardDock\\(\\)').allMatches(src).length, 1);
      expect(dock, greaterThan(src.indexOf('ListView.builder(')), reason: '在聊天列表之后');
      for (final below in ['PendingArea(', 'QueueStrip(', 'AttachmentStrip(', 'SlashSuggestions(', 'ChatComposer(']) {
        expect(src.indexOf(below, src.indexOf('Widget build(BuildContext context)')), greaterThan(dock), reason: '$below 要在 KeyboardDock 下面');
      }
    });
  });

  group('不归这套规则管的', () {
    testWidgets('终端：点终端叫出键盘；之后点终端里外任何地方，焦点和键盘都不被收掉', (tester) async {
      usePhoneViewport(tester);
      await tester.runAsync(() async => env = await TestEnv.create());
      addTearDown(() => env.dispose());
      final term = TerminalSession(title: '测试', backend: _PtyBackend(FakePty()));
      final focus = FocusNode();
      addTearDown(focus.dispose);
      await tester.pumpWidget(
        appFor(
          env,
          Scaffold(
            body: Column(
              children: [
                const SizedBox(height: 120, child: Center(child: Text('终端上方'))),
                Expanded(
                  child: TerminalInputView(
                    session: term,
                    focusNode: focus,
                    theme: TerminalThemes.defaultTheme,
                    textStyle: const TerminalStyle(fontSize: 13, height: 1.3),
                    padding: const EdgeInsets.all(8),
                    mode: TerminalImeMode.direct,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();
      await term.ensureStarted();
      await tester.pump();
      await tester.tapAt(const Offset(200, 400));
      await tester.pump(const Duration(milliseconds: 400));
      expect(focus.hasFocus, isTrue);
      expect(tester.testTextInput.isVisible, isTrue);
      await tester.tapAt(const Offset(200, 500));
      await tester.pump(const Duration(milliseconds: 400));
      expect(focus.hasFocus, isTrue, reason: '点终端区域不收');
      await tester.tapAt(const Offset(200, 60));
      await tester.pump(const Duration(milliseconds: 400));
      expect(focus.hasFocus, isTrue, reason: '终端的键盘归 terminal_input.dart 管，这套规则不碰它');
      expect(tester.testTextInput.isVisible, isTrue);
      expect(tester.takeException(), isNull);
    });

    testWidgets('文件编辑器页：查找框聚焦时点页签条、“保存”、编辑区，都不收键盘', (tester) async {
      await openChat(tester, turns: 0);
      await tester.tap(find.byKey(ValueKey('nav-${ShellDest.bottom.indexOf(ShellDest.files)}')));
      await settle(tester, rounds: 8);
      await tester.tap(find.text('index.html'));
      await settle(tester, rounds: 6);
      await tester.tap(find.byTooltip('编辑器菜单'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('查找'));
      await tester.pumpAndSettle();
      final field = find.descendant(of: find.byType(FilesTab), matching: find.byType(TextField)).first;
      await tester.tap(field);
      await tester.pump();
      expect(anyFieldFocused(), isTrue);
      await tester.tap(find.text('已保存'));
      await tester.pump();
      expect(anyFieldFocused(), isTrue, reason: '编辑器页整页是输入区');
      await tester.tap(find.byTooltip('文件列表'), warnIfMissed: false);
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });
}
