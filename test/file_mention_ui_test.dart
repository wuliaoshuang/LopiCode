// 聊天输入框“打 @ 选文件”和“语音入口暂时隐藏”的界面测试（390×844，浅色 + 深色）。
//   LOPI_SHOTS=1 flutter test --no-pub test/file_mention_ui_test.dart   # 同时写截图到 docs/screenshots/fb4-composer-*.png
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/agent/agent_tools.dart';
import 'package:lopicode/core/path_guard.dart';
import 'package:lopicode/core/project_store.dart';
import 'package:lopicode/core/templates.dart';
import 'package:lopicode/project_session.dart';
import 'package:lopicode/session/file_mentions.dart';
import 'package:lopicode/theme/app_theme.dart';
import 'package:lopicode/ui/chat_composer.dart';
import 'package:lopicode/ui/chrome.dart';
import 'package:lopicode/ui/file_icon.dart';
import 'package:lopicode/ui/file_mention.dart';
import 'package:lopicode/ui/file_picker_sheet.dart';
import 'package:lopicode/ui/keyboard_dismiss.dart';
import 'package:lopicode/ui/project_shell.dart';
import 'package:lopicode/ui/shell.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;

import 'support/harness.dart';

final bool writeShots = Platform.environment['LOPI_SHOTS'] == '1';
bool fontsLoaded = false;

Future<void> shot(WidgetTester tester, String name) async {
  expect(tester.takeException(), isNull, reason: '$name 渲染时出了异常');
  if (!writeShots || !fontsLoaded) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(shotKey));
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    File('docs/screenshots/$name.png')
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync(data!.buffer.asUint8List());
  });
}

class _CountingVoice implements ChatVoiceInput {
  int initCalls = 0;
  int disposeCalls = 0;
  @override
  bool get isListening => false;
  @override
  Future<bool> initialize() async {
    initCalls++;
    return true;
  }

  @override
  Future<void> listen({required void Function(String words) onResult, required void Function(bool listening) onListeningChanged, required void Function(String message) onError}) async {}
  @override
  Future<void> stop() async {}
  @override
  void dispose() => disposeCalls++;
}

const _files = ['README.md', 'index.html', 'lib/main.dart', 'lib/ui/home_screen.dart', 'lib/ui/settings_screen.dart', 'styles/app.css', 'test/main_test.dart'];

class _Rig {
  _Rig(this.text, this.focus);
  final TextEditingController text;
  final FocusNode focus;

  /// “点了输入框外面”的次数（和输入框同一组的 TapRegion 看到的，另一位同事收键盘用的就是这类办法）。
  int outsideTaps = 0;
  int scans = 0;
  int sends = 0;
}

Future<_Rig> _pump(
  WidgetTester tester, {
  Brightness brightness = Brightness.light,
  String? font,
  MentionScanner? scanner,
  List<String> files = _files,
  bool truncated = false,
  PathGuard? guard,
  bool? showVoice,
  ChatVoiceInput? voice,
  bool withGuard = true,
  String draft = '',
}) async {
  usePhoneViewport(tester);
  debugKeyboardNow = () => Duration(microseconds: tester.binding.clock.now().microsecondsSinceEpoch);
  addTearDown(() => debugKeyboardNow = null);
  final rig = _Rig(TextEditingController(text: draft), FocusNode());
  addTearDown(rig.text.dispose);
  addTearDown(rig.focus.dispose);
  final g = guard ?? PathGuard(Directory.systemTemp.path);
  await tester.pumpWidget(
    RepaintBoundary(
      key: shotKey,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(brightness, fontFamily: font),
        home: Scaffold(
          body: SafeArea(
            child: Column(
              children: [
                const Expanded(
                  child: ColoredBox(key: ValueKey('blank'), color: Color(0x00000000), child: SizedBox.expand()),
                ),
                TapRegion(groupId: EditableText, onTapOutside: (_) => rig.outsideTaps++, child: const SizedBox.shrink()),
                ValueListenableBuilder<TextEditingValue>(
                  valueListenable: rig.text,
                  builder: (context, value, _) => ChatComposer(
                    controller: rig.text,
                    focusNode: rig.focus,
                    busy: false,
                    canSend: value.text.trim().isNotEmpty,
                    modelName: 'DeepSeek Chat',
                    permission: PermissionLevel.workspace,
                    voiceInput: voice,
                    showVoice: showVoice ?? kChatVoiceEnabled,
                    mentionGuard: withGuard ? g : null,
                    mentionScanner:
                        scanner ??
                        (_) async {
                          rig.scans++;
                          return MentionScan(files, truncated: truncated);
                        },
                    context_: const ContextUsage(42000, 128000, estimated: false),
                    onContext: () {},
                    onPlus: () {},
                    onModel: () {},
                    onPermission: () {},
                    onSend: () => rig.sends++,
                    onLongSend: () {},
                    onStop: () {},
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return rig;
}

Future<void> _type(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField), text);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
}

final _panel = find.byKey(const ValueKey('mention-panel'));
Finder _row(String path) => find.byKey(ValueKey('mention-$path'));

void main() {
  setUpAll(() async => fontsLoaded = await loadRealFonts());

  group('打 @ 选文件', () {
    testWidgets('打出 @：输入框正上方出现工作区文件，一行一个（图标 + 文件名 + 灰色目录），行高不小于 44', (tester) async {
      final rig = await _pump(tester);
      expect(_panel, findsNothing, reason: '没打 @ 时不占地方');
      await _type(tester, '@');
      expect(_panel, findsOneWidget);
      expect(rig.scans, 1);
      expect(_row('README.md'), findsOneWidget);
      expect(_row('lib/main.dart'), findsOneWidget);
      // 一行：图标 + 文件名 + 目录
      final row = _row('lib/ui/home_screen.dart');
      expect(find.descendant(of: row, matching: find.byType(FileIcon)), findsOneWidget);
      expect(find.descendant(of: row, matching: find.text('home_screen.dart')), findsOneWidget);
      final dir = tester.widget<Text>(find.descendant(of: row, matching: find.text('lib/ui')));
      final nameText = tester.widget<Text>(find.descendant(of: row, matching: find.text('home_screen.dart')));
      expect(dir.style?.color, isNot(nameText.style?.color), reason: '目录是次要信息，比文件名淡');
      expect(tester.getSize(row).height, greaterThanOrEqualTo(44));
      expect(tester.getSize(row).height, kMentionRowHeight);
      // 位置：贴在输入框上方、同宽、在屏幕里
      final panel = tester.getRect(_panel);
      final input = tester.getRect(find.byKey(const ValueKey('chat-input')));
      expect(panel.bottom, lessThanOrEqualTo(input.top));
      expect(input.top - panel.bottom, lessThanOrEqualTo(16));
      expect(panel.top, greaterThanOrEqualTo(0));
      expect(tester.takeException(), isNull);
    });

    testWidgets('继续打字按文件名 / 路径筛；没有匹配时写“没有匹配的文件”', (tester) async {
      await _pump(tester);
      await _type(tester, '@main');
      expect(_row('lib/main.dart'), findsOneWidget);
      expect(_row('test/main_test.dart'), findsOneWidget);
      expect(_row('README.md'), findsNothing);
      await _type(tester, '@lib/ui');
      expect(_row('lib/ui/home_screen.dart'), findsOneWidget);
      expect(_row('lib/main.dart'), findsNothing);
      await _type(tester, '@zzzz');
      expect(_panel, findsOneWidget);
      expect(find.byKey(const ValueKey('mention-empty')), findsOneWidget);
      expect(find.text('没有匹配的文件。'), findsOneWidget);
      expect(tester.getSize(find.byKey(const ValueKey('mention-empty'))).height, greaterThanOrEqualTo(44), reason: '不是空白一片');
    });

    testWidgets('夹在字中间的 @（邮箱）不弹；空白 / 换行后的 @ 才弹', (tester) async {
      final rig = await _pump(tester);
      await _type(tester, 'a@b.com');
      expect(_panel, findsNothing);
      await _type(tester, '发给 me@example');
      expect(_panel, findsNothing);
      expect(rig.scans, 0, reason: '没弹就不扫文件');
      await _type(tester, '看一下 @ind');
      expect(_row('index.html'), findsOneWidget);
      await _type(tester, '第一行\n@ind');
      expect(_row('index.html'), findsOneWidget);
    });

    testWidgets('点一项：@xxx 换成 @路径，焦点和键盘不动，候选收起；点候选不算点了输入框外面', (tester) async {
      final rig = await _pump(tester);
      await _type(tester, '改一下 @home');
      expect(rig.focus.hasFocus, isTrue);
      final before = rig.outsideTaps;
      await tester.tap(_row('lib/ui/home_screen.dart'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(rig.text.text, '改一下 @lib/ui/home_screen.dart ');
      expect(rig.text.selection, TextSelection.collapsed(offset: rig.text.text.length));
      expect(rig.text.value.composing, TextRange.empty);
      expect(rig.focus.hasFocus, isTrue, reason: '选完接着打字，键盘不收');
      expect(_panel, findsNothing);
      expect(rig.outsideTaps, before, reason: '候选和输入框是同一块（TextFieldTapRegion）');
      expect(rig.sends, 0);
      // 对照：点空白处才算外面
      await _type(tester, '@');
      await tester.tap(find.byKey(const ValueKey('blank')));
      await tester.pump();
      expect(rig.outsideTaps, before + 1);
    });

    testWidgets('已经引用过的文件再选一次：不重复加，并说一声', (tester) async {
      final rig = await _pump(tester);
      await _type(tester, '@index.html 和 @ind');
      await tester.tap(_row('index.html'));
      await tester.pump();
      expect(rig.text.text, '@index.html 和 ');
      expect(find.text('这个文件已经引用过了，没有重复添加。'), findsOneWidget);
      expect(rig.focus.hasFocus, isTrue);
    });

    testWidgets('收起：打空格、删掉 @、光标移走、失焦', (tester) async {
      final rig = await _pump(tester);
      await _type(tester, '@ma');
      expect(_panel, findsOneWidget);
      await _type(tester, '@ma ');
      expect(_panel, findsNothing, reason: '打了空格');
      await _type(tester, '@ma');
      expect(_panel, findsOneWidget);
      await _type(tester, 'ma');
      expect(_panel, findsNothing, reason: '@ 被删掉了');
      await _type(tester, '你好 @ma');
      expect(_panel, findsOneWidget);
      rig.text.selection = const TextSelection.collapsed(offset: 1);
      await tester.pump();
      expect(_panel, findsNothing, reason: '光标移走');
      rig.text.selection = const TextSelection.collapsed(offset: 6);
      await tester.pump();
      expect(_panel, findsOneWidget, reason: '光标回到 @ma 后面又弹出');
      rig.focus.unfocus();
      await tester.pump();
      expect(_panel, findsNothing, reason: '失焦');
      expect(rig.text.text, '你好 @ma', reason: '草稿不动');
    });

    testWidgets('收起：按返回键只收候选（不退出页面），草稿不动；接着打字再弹', (tester) async {
      final rig = await _pump(tester);
      await _type(tester, '@ma');
      expect(_panel, findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(_panel, findsNothing);
      expect(find.byType(ChatComposer), findsOneWidget, reason: '页面还在');
      expect(rig.text.text, '@ma');
      expect(rig.focus.hasFocus, isTrue);
      await _type(tester, '@mai');
      expect(_panel, findsOneWidget);
    });

    testWidgets('收起：点列表和输入框以外的地方；点输入框自己不收', (tester) async {
      final rig = await _pump(tester);
      await _type(tester, '@ma');
      await tester.tap(find.byType(TextField));
      await tester.pump();
      expect(_panel, findsOneWidget, reason: '点输入框不算外面');
      await tester.tap(find.byKey(const ValueKey('blank')));
      await tester.pump();
      expect(_panel, findsNothing);
      expect(rig.text.text, '@ma');
    });

    testWidgets('中文输入法组字：@ 还在组字里不弹；拼音在 @ 后面时只筛不改草稿；上屏后按上屏的字筛', (tester) async {
      final rig = await _pump(tester, files: const ['文件说明.md', 'wenjian.txt', 'main.dart']);
      await tester.showKeyboard(find.byType(TextField));
      // @ 自己还没上屏
      tester.testTextInput.updateEditingValue(const TextEditingValue(text: '@', selection: TextSelection.collapsed(offset: 1), composing: TextRange(start: 0, end: 1)));
      await tester.pump();
      expect(_panel, findsNothing);
      // @ 上屏了，后面在打拼音
      const composing = TextEditingValue(text: '@wenjian', selection: TextSelection.collapsed(offset: 8), composing: TextRange(start: 1, end: 8));
      tester.testTextInput.updateEditingValue(composing);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(_panel, findsOneWidget);
      expect(_row('wenjian.txt'), findsOneWidget);
      expect(_row('main.dart'), findsNothing);
      expect(rig.text.value, composing, reason: '组字期间不改草稿、不动组字范围');
      // 上屏成汉字
      tester.testTextInput.updateEditingValue(const TextEditingValue(text: '@文件', selection: TextSelection.collapsed(offset: 3)));
      await tester.pump();
      expect(_row('文件说明.md'), findsOneWidget);
      expect(_row('wenjian.txt'), findsNothing);
      // 邮箱里组字也不弹
      tester.testTextInput.updateEditingValue(const TextEditingValue(text: 'a@ni', selection: TextSelection.collapsed(offset: 4), composing: TextRange(start: 2, end: 4)));
      await tester.pump();
      expect(_panel, findsNothing);
    });

    testWidgets('文件很多：最多露出 5 行半、可以滚；匹配太多和没扫完各有一句说明', (tester) async {
      final many = [for (var i = 0; i < 120; i++) 'src/file_${i.toString().padLeft(3, '0')}.dart'];
      await _pump(tester, files: many, truncated: true);
      await _type(tester, '@');
      final list = find.byKey(const ValueKey('mention-list'));
      expect(tester.getSize(list).height, kMentionRowHeight * kMentionVisibleRows);
      expect(_row('src/file_000.dart'), findsOneWidget);
      expect(_row('src/file_030.dart'), findsNothing);
      await tester.scrollUntilVisible(
        _row('src/file_030.dart'),
        200,
        scrollable: find.descendant(of: list, matching: find.byType(Scrollable)),
      );
      expect(_row('src/file_030.dart'), findsOneWidget);
      expect(find.textContaining('匹配的文件有 120 个，只显示前 $kMentionMaxResults 个，继续输入可缩小范围。'), findsOneWidget);
      expect(find.textContaining('工作区文件太多，只找了前 120 个；没列出来的可以直接打出路径。'), findsOneWidget);
      expect(tester.getRect(_panel).top, greaterThanOrEqualTo(0));
      // 继续输入缩小范围后，“匹配太多”那句没了
      await _type(tester, '@file_03');
      expect(find.textContaining('只显示前'), findsNothing);
      expect(find.textContaining('工作区文件太多'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('还在找文件时照样能打字；旧的一次扫描回来得晚也不盖新结果', (tester) async {
      final pending = <Completer<MentionScan>>[];
      final rig = await _pump(
        tester,
        scanner: (_) {
          final c = Completer<MentionScan>();
          pending.add(c);
          return c.future;
        },
      );
      await _type(tester, '@');
      expect(find.byKey(const ValueKey('mention-loading')), findsOneWidget);
      await _type(tester, '@ol');
      expect(rig.text.text, '@ol', reason: '扫描没回来也不耽误打字');
      expect(pending, hasLength(1), reason: '打字不重复扫');
      // 收起再弹出：开了第二次扫描
      await _type(tester, '@ol ');
      await _type(tester, '@ol');
      expect(pending, hasLength(2));
      pending[1].complete(const MentionScan(['new.txt']));
      await tester.pump();
      expect(_row('new.txt'), findsNothing, reason: '按 ol 筛掉了');
      await _type(tester, '@');
      expect(_row('new.txt'), findsOneWidget);
      pending[0].complete(const MentionScan(['old.txt']));
      await tester.pump();
      await tester.pump();
      expect(_row('old.txt'), findsNothing, reason: '旧结果丢掉');
      expect(_row('new.txt'), findsOneWidget);
    });

    testWidgets('页面关掉以后扫描才回来：不报错', (tester) async {
      final c = Completer<MentionScan>();
      await _pump(tester, scanner: (_) => c.future);
      await _type(tester, '@');
      await tester.pumpWidget(const SizedBox.shrink());
      c.complete(const MentionScan(['late.txt']));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('读不了工作区、扫描抛异常：一行字说原因', (tester) async {
      await _pump(tester, scanner: (_) async => const MentionScan([], error: '读不了工作区的文件：Permission denied'));
      await _type(tester, '@');
      expect(find.text('读不了工作区的文件：Permission denied'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await _pump(tester, scanner: (_) async => throw const FileSystemException('boom'));
      await _type(tester, '@');
      expect(find.byKey(const ValueKey('mention-error')), findsOneWidget);
      expect(find.textContaining('读不了工作区的文件'), findsOneWidget);
      expect(find.text('读不了工作区的文件：Permission denied'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('同一个位置换了另一个草稿（控制器换了）：按新草稿重新判断，旧的扫描结果不留着', (tester) async {
      usePhoneViewport(tester);
      final a = TextEditingController();
      final b = TextEditingController();
      final focus = FocusNode();
      addTearDown(a.dispose);
      addTearDown(b.dispose);
      addTearDown(focus.dispose);
      var current = a;
      var scans = 0;
      late StateSetter rebuild;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(Brightness.light),
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                rebuild = setState;
                return Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    FileMentionLayer(
                      controller: current,
                      focusNode: focus,
                      guard: PathGuard(Directory.systemTemp.path),
                      scanner: (_) async {
                        scans++;
                        return MentionScan(['scan$scans.txt']);
                      },
                    ),
                    TextField(controller: current, focusNode: focus),
                  ],
                );
              },
            ),
          ),
        ),
      );
      await _type(tester, '@');
      expect(_row('scan1.txt'), findsOneWidget);
      rebuild(() => current = b);
      await tester.pump();
      expect(_panel, findsNothing, reason: '新草稿是空的');
      rebuild(() => current = a);
      await tester.pump();
      await tester.pump();
      expect(scans, 2);
      expect(_row('scan2.txt'), findsOneWidget);
      expect(_row('scan1.txt'), findsNothing);
    });

    testWidgets('空工作区：写“工作区里还没有文件”', (tester) async {
      await _pump(tester, files: const []);
      await _type(tester, '@');
      expect(find.text('工作区里还没有文件。'), findsOneWidget);
    });

    testWidgets('工作区外面的路径加不进去（路径守卫拦下，说明原因，草稿不动）', (tester) async {
      final tmp = Directory.systemTemp.createTempSync('lopi_mention_ui_');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final rig = await _pump(tester, guard: PathGuard(tmp.path), files: const ['../outside.txt', '.lopicode/project.json']);
      await _type(tester, '@out');
      await tester.tap(_row('../outside.txt'));
      await tester.pump();
      expect(rig.text.text, '@out');
      expect(find.textContaining('路径越出了项目目录'), findsOneWidget);
      await _type(tester, '@proj');
      await tester.tap(_row('.lopicode/project.json'));
      await tester.pump();
      // 上一条提示先退场，新的才出来
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(rig.text.text, '@proj');
      expect(find.textContaining('应用内部目录'), findsOneWidget);
    });

    testWidgets('键盘弹起时：候选在输入框上方，没被键盘挡住，也没顶出屏幕', (tester) async {
      await _pump(tester);
      tester.view.viewInsets = const FakeViewPadding(bottom: 336);
      addTearDown(tester.view.resetViewInsets);
      await _type(tester, '@');
      final panel = tester.getRect(_panel);
      final input = tester.getRect(find.byKey(const ValueKey('chat-input')));
      expect(input.bottom, lessThanOrEqualTo(844 - 336));
      expect(panel.bottom, lessThanOrEqualTo(input.top));
      expect(panel.top, greaterThanOrEqualTo(0));
      expect(tester.getSize(find.byKey(const ValueKey('mention-list'))).height, kMentionRowHeight * kMentionVisibleRows);
      expect(tester.takeException(), isNull, reason: '不溢出');
    });

    testWidgets('真的扫一遍临时工作区：依赖和内部目录不出现', (tester) async {
      final tmp = Directory.systemTemp.createTempSync('lopi_mention_real_');
      addTearDown(() => tmp.deleteSync(recursive: true));
      for (final f in ['index.html', 'src/app.js', 'node_modules/x/index.js', '.git/config', '.lopicode/project.json']) {
        File(p.join(tmp.path, f))
          ..parent.createSync(recursive: true)
          ..writeAsStringSync('x');
      }
      final guard = PathGuard(tmp.path);
      await _pump(tester, guard: guard, scanner: scanMentionFiles);
      await _type(tester, '@');
      await settle(tester, rounds: 3);
      expect(_row('index.html'), findsOneWidget);
      expect(_row('src/app.js'), findsOneWidget);
      expect(find.textContaining('node_modules'), findsNothing);
      expect(find.text('config'), findsNothing);
      expect(find.text('project.json'), findsNothing);
    });

    testWidgets('没给工作区（别处复用输入栏）时没有这个功能', (tester) async {
      await _pump(tester, withGuard: false);
      await _type(tester, '@');
      expect(_panel, findsNothing);
      expect(find.byType(FileMentionLayer), findsNothing);
    });
  });

  group('语音入口暂时隐藏', () {
    testWidgets('默认：收起和展开都没有麦克风，不创建语音识别，位置由旁边的控件补上', (tester) async {
      expect(kChatVoiceEnabled, isFalse);
      final voice = _CountingVoice();
      await _pump(tester, voice: voice);
      expect(find.byKey(const ValueKey('voice-button')), findsNothing);
      expect(find.byTooltip('语音输入'), findsNothing);
      // 收起：输入框 → 用量小环 → 发送，紧挨着，没有空洞
      final ring = tester.getRect(find.byKey(const Key('context-ring')));
      final send = tester.getRect(find.ancestor(of: find.byKey(const ValueKey('send-button')), matching: find.byType(OverflowBox)));
      final field = tester.getRect(find.byType(TextField));
      expect(send.left - ring.right, lessThan(1), reason: '小环和发送之间没有留麦克风的空位');
      expect(ring.left - field.right, lessThan(1));
      // 展开
      await _type(tester, '帮我改一下');
      expect(find.byKey(const ValueKey('voice-button')), findsNothing);
      final ring2 = tester.getRect(find.byKey(const Key('context-ring')));
      final send2 = tester.getRect(find.ancestor(of: find.byKey(const ValueKey('send-button')), matching: find.byType(OverflowBox)));
      expect(send2.left - ring2.right, lessThan(1));
      expect(find.byKey(const ValueKey('model-button')), findsOneWidget);
      // 拆掉输入栏
      await tester.pumpWidget(const SizedBox.shrink());
      expect(voice.initCalls, 0, reason: '没有入口就不会初始化语音识别，也就不会申请麦克风权限');
      expect(voice.disposeCalls, 0, reason: '藏着的时候从头到尾不碰语音识别');
    });

    testWidgets('开关打开：麦克风回来，排在发送左边，原功能照旧', (tester) async {
      final voice = _CountingVoice();
      await _pump(tester, voice: voice, showVoice: true);
      final mic = find.byKey(const ValueKey('voice-button'));
      expect(mic, findsOneWidget);
      final send = tester.getRect(find.ancestor(of: find.byKey(const ValueKey('send-button')), matching: find.byType(OverflowBox)));
      expect(tester.getRect(mic).right, lessThanOrEqualTo(send.left + 0.5));
      await tester.tap(mic);
      await tester.pump();
      expect(voice.initCalls, 1);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(voice.disposeCalls, 1);
    });
  });

  group('接进真实聊天页', () {
    Future<(TestEnv, Project, ProjectSession)> open(WidgetTester tester) async {
      usePhoneViewport(tester);
      late TestEnv env;
      late Project project;
      late ProjectSession session;
      await tester.runAsync(() async {
        env = await TestEnv.create();
        project = await env.services.projects.create('我的小站', ProjectTemplate.web);
        session = ProjectSession(env.services, project);
        await session.loadChat();
        await Future<void>.delayed(const Duration(milliseconds: 150));
      });
      addTearDown(() async {
        session.dispose();
        await env.dispose();
      });
      await tester.pumpWidget(appFor(env, ProjectShell(project: project, session: session, initial: ShellDest.chat)));
      await settle(tester);
      return (env, project, session);
    }

    testWidgets('聊天页里没有麦克风；打 @ 选出来的和“＋ › 引用项目文件”插进去的一模一样', (tester) async {
      await open(tester);
      expect(find.byKey(const ValueKey('voice-button')), findsNothing);

      // 走 @
      await tester.enterText(find.byType(TextField), '@index');
      await settle(tester, rounds: 3);
      expect(_panel, findsOneWidget);
      expect(_row('index.html'), findsOneWidget);
      expect(find.byKey(const ValueKey('mention-.lopicode/project.json')), findsNothing);
      final nav = tester.getRect(find.byType(IconBottomNav));
      expect(tester.getRect(_panel).bottom, lessThanOrEqualTo(nav.top), reason: '不被底部导航挡住');
      // 返回键：只收候选，人还在聊天页
      await tester.binding.handlePopRoute();
      await settle(tester, rounds: 2);
      expect(_panel, findsNothing);
      expect(find.byType(ChatComposer), findsOneWidget);
      expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, '@index');
      await tester.enterText(find.byType(TextField), '@inde');
      await settle(tester, rounds: 3);
      await tester.tap(_row('index.html'));
      await settle(tester, rounds: 2);
      final viaAt = tester.widget<TextField>(find.byType(TextField)).controller!.text;
      expect(viaAt, '@index.html ');
      expect(_panel, findsNothing);
      expect(find.byKey(const ValueKey('voice-button')), findsNothing, reason: '展开态也没有');

      // 走加号
      await tester.enterText(find.byType(TextField), '');
      await settle(tester, rounds: 2);
      await tester.tap(find.byKey(const ValueKey('plus-button')));
      await settle(tester, rounds: 3);
      await tester.tap(find.byKey(const ValueKey('plus-ref')));
      await settle(tester, rounds: 4);
      await tester.tap(find.widgetWithText(ListTile, 'index.html'));
      await settle(tester, rounds: 3);
      final viaPlus = tester.widget<TextField>(find.byType(TextField)).controller!.text;
      expect(viaPlus, viaAt, reason: '两条路进来的是同一种引用');
      // 逻辑层那个插入函数和加号的写法也对得上
      expect(insertMention('', 0, 'index.html').text, viaPlus);
      expect(tester.takeException(), isNull);
    });
  });

  group('“＋”里的文件面板和 @ 用同一套文件清单', () {
    testWidgets('装过依赖的项目：自己的文件照样列得出来，依赖和版本库不出现；挑图片时附件目录里的图还在', (tester) async {
      usePhoneViewport(tester);
      late TestEnv env;
      late ProjectSession session;
      await tester.runAsync(() async {
        env = await TestEnv.create();
        final project = await env.services.projects.create('我的小站', ProjectTemplate.web);
        session = ProjectSession(env.services, project);
        void put(String rel) => File(p.join(project.dir, rel))
          ..parent.createSync(recursive: true)
          ..writeAsStringSync('x');
        // 以前的列法最多列 500 项、依赖目录也算：这么多依赖文件会把 zz_mine.txt 挤出去。
        for (var i = 0; i < 600; i++) {
          put('node_modules/pkg/f$i.js');
        }
        put('.git/config');
        put('zz_mine.txt');
        put('.lopicode-attachments/old.png');
        put('img/logo.png');
      });
      addTearDown(() async {
        session.dispose();
        await env.dispose();
      });
      Future<void> show({required bool imagesOnly}) async {
        await tester.pumpWidget(
          appFor(
            env,
            Scaffold(
              body: FilePickerSheet(session: session, imagesOnly: imagesOnly),
            ),
          ),
        );
        await settle(tester, rounds: 5);
      }

      await show(imagesOnly: false);
      await tester.scrollUntilVisible(find.text('zz_mine.txt'), 200, scrollable: find.byType(Scrollable).first);
      expect(find.text('zz_mine.txt'), findsOneWidget, reason: '钉住：依赖文件不再把自己的文件挤出清单');
      expect(find.textContaining('node_modules'), findsNothing);
      expect(find.textContaining('.git/'), findsNothing);
      expect(find.textContaining('.lopicode-attachments'), findsNothing);
      expect(find.byKey(const ValueKey('picker-truncated')), findsNothing);

      await show(imagesOnly: true);
      expect(find.text('img/logo.png'), findsOneWidget);
      expect(find.text('.lopicode-attachments/old.png'), findsOneWidget, reason: '挑图片时以前附过的图照旧能选');
      expect(find.text('zz_mine.txt'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  for (final brightness in Brightness.values) {
    final name = brightness.name;
    testWidgets('截图 · $name', (tester) async {
      final font = fontsLoaded ? kTestFont : null;
      await _pump(tester, brightness: brightness, font: font);
      await shot(tester, 'fb4-composer-01-collapsed-no-mic-$name');
      tester.view.viewInsets = const FakeViewPadding(bottom: 336);
      addTearDown(tester.view.resetViewInsets);
      await _type(tester, '帮我看看 @');
      await shot(tester, 'fb4-composer-02-mention-list-$name');
      await _type(tester, '帮我看看 @screen');
      await shot(tester, 'fb4-composer-03-mention-filter-$name');
      await _type(tester, '帮我看看 @zzz');
      await shot(tester, 'fb4-composer-04-mention-empty-$name');
      await tester.pumpWidget(const SizedBox.shrink());
      final many = [for (var i = 0; i < 120; i++) 'src/pages/page_${i.toString().padLeft(3, '0')}.vue'];
      await _pump(tester, brightness: brightness, font: font, files: many, truncated: true);
      await _type(tester, '@');
      await shot(tester, 'fb4-composer-05-mention-many-$name');
    });
  }
}
