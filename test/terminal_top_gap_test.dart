// 第四轮真机反馈第 5 条：终端顶部总是有一大片空白（提示符在会话行下面四五行高的地方）。
//
// 根因：xterm 的 TerminalView 把 MediaQuery.padding 当成自己的内边距再留一遍；终端页在“内容铺到顶栏后面”的 Scaffold 里，
// 那里的 padding.top = 状态栏 + 顶栏（真机约 109），外面的 BelowBar 已经让过一次。这里钉住：
// - 逻辑层：屏幕还空着时，开头的空行 / 回车不上屏；清屏符、键盘升降的重画都不把提示符顶下去；“清屏”以后第一行还是提示符；
// - 界面层（390×844，带 45 的状态栏）：提示符那一行贴着会话行下沿；键盘升降、切页签、开第二个终端、转屏、刷很多行以后都正常。
//
// 用到的“bash 真实输出”是 2026-11-25 在开发机上用真的伪终端跑 bash 5.2.21（和 Ubuntu 24.04 同一版）录下来的，只把主机名换成了 localhost。
// 测试跑在宿主机上：伪终端、PRoot 都是假的，不联网、不下载。
//   LOPI_SHOTS=1 flutter test --no-pub test/terminal_top_gap_test.dart   # 同时写截图到 docs/screenshots/term-*.png
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:lopicode/app.dart';
import 'package:lopicode/app_services.dart';
import 'package:lopicode/core/project_store.dart';
import 'package:lopicode/core/stores.dart';
import 'package:lopicode/core/templates.dart';
import 'package:lopicode/project_session.dart';
import 'package:lopicode/runtime/linux_runtime.dart';
import 'package:lopicode/terminal/terminal_input.dart';
import 'package:lopicode/terminal/terminal_session.dart';
import 'package:lopicode/ui/project_shell.dart';
import 'package:lopicode/ui/shell.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:xterm/xterm.dart';

import 'support/harness.dart';
import 'support/runtime_fakes.dart';

final bool writeShots = Platform.environment['LOPI_SHOTS'] == '1';
bool fontsLoaded = false;

const prompt = 'root@localhost:/workspace# ';

/// bash 一启动送来的（打开“括号粘贴”模式，然后是提示符）。
const bashStart = '\x1b[?2004h$prompt';

/// 终端改了行数以后 bash 重画提示符送来的。
const bashRedraw = '\r\x1b[K\r$prompt';

/// 在空提示符上按回车，bash 送来的。
const bashEnter = '\r\n\x1b[?2004l\r\x1b[?2004h$prompt';

/// 会话行下沿到提示符那一行上沿，最多允许这么多（现在是 4：终端自己的上内边距）。自己定的。
const double kMaxTopGap = 8;

/// 真机的状态栏高度大约这么多。
const double kStatusBar = 45;

class FakeBackend implements TerminalBackend {
  final StreamController<String> out = StreamController.broadcast();
  final List<String> written = [];
  bool running = true;

  @override
  String get label => '假';
  @override
  Stream<String> get output => out.stream;
  @override
  bool get isRunning => running;
  @override
  Future<void> start({required int columns, required int rows}) async {}
  @override
  void write(String data) => written.add(data);
  @override
  void resize(int columns, int rows) {}
  @override
  Future<void> close() async => out.close();
}

class FakeBash extends FakeBackend implements LineEditingShell {
  @override
  bool redrawsOnCtrlL = true;
}

String lineAt(Terminal t, int index) => t.buffer.lines[index].getText().trimRight();

/// 第一行就是提示符，光标在第 0 行，没有被顶进回滚区的行。
void expectPromptOnTop(Terminal t, {String first = 'root@localhost:/workspace#', String? reason}) {
  expect(t.buffer.lines.length, t.viewHeight, reason: '${reason ?? ''}：没有多出来的行');
  expect(lineAt(t, 0), first, reason: '${reason ?? ''}：第一行就是提示符');
  expect(t.buffer.cursorY, 0, reason: '${reason ?? ''}：光标在第 0 行');
  expect(t.buffer.absoluteCursorY, 0, reason: reason);
}

Future<void> tick() => Future<void>.delayed(Duration.zero);

class _NoNetwork extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) => throw StateError('测试里不许联网：${request.url}');
}

/// 装好了 Ubuntu 环境的安卓（不许用本机 shell）。
class Env {
  Env(this.tmp, this.services);
  final Directory tmp;
  final AppServices services;

  static Future<Env> create() async {
    final tmp = Directory.systemTemp.createTempSync('lopi_ttop_');
    final settings = SettingsStore(File(p.join(tmp.path, 'settings.json')));
    final runtime = LinuxRuntime(
      settings: settings,
      baseDir: p.join(tmp.path, 'runtime'),
      host: FakeRuntimeHost(nativeDir: makeFakeNativeDir(tmp)),
      httpClient: _NoNetwork.new,
      localShellAllowed: false,
      processGroups: () => const [0],
    );
    markInstalled(runtime);
    await runtime.init();
    return Env(tmp, AppServices(settings: settings, secrets: MemorySecretStore(), projects: ProjectStore(p.join(tmp.path, 'projects')), runtime: runtime));
  }

  void dispose() {
    services.dispose();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  }
}

class Rig {
  Rig(this.env, this.session, this.ptys);
  final Env env;
  final ProjectSession session;
  final List<FakePty> ptys;
}

/// 打开工作区的终端页（深 / 浅色），带真机那样的状态栏；Ubuntu 的伪终端是假的。
Future<Rig> openTerminal(WidgetTester tester, {ThemeMode mode = ThemeMode.dark}) async {
  usePhoneViewport(tester);
  tester.view.padding = const FakeViewPadding(top: kStatusBar);
  tester.view.viewPadding = const FakeViewPadding(top: kStatusBar);
  final env = (await tester.runAsync(Env.create))!;
  addTearDown(env.dispose);
  final project = (await tester.runAsync(() => env.services.projects.create('我的后端服务（积木）', ProjectTemplate.web)))!;
  final ptys = <FakePty>[];
  late ProjectSession session;
  await tester.runAsync(() async {
    session = ProjectSession(env.services, project);
    await session.loadChat();
    session.linuxPtySpawner = (exe, args, {required workingDirectory, required environment, required rows, required columns}) {
      final pty = FakePty();
      ptys.add(pty);
      return pty;
    };
  });
  // 第一个会话在注入假伪终端之前就建好了：换一个用假伪终端的
  session.addTerminal();
  session.closeTerminal(0);
  await tester.pumpWidget(
    RepaintBoundary(
      key: shotKey,
      child: LopiCodeApp(
        services: env.services,
        home: ProjectShell(project: project, session: session, initial: ShellDest.terminal),
        fontFamily: kTestFont,
        forceThemeMode: mode,
      ),
    ),
  );
  await settle(tester);
  return Rig(env, session, ptys);
}

Future<void> closeRig(WidgetTester tester, Rig rig) async {
  await tester.runAsync(() async => rig.session.dispose());
  await tester.pump(const Duration(seconds: 1));
}

Future<void> emit(WidgetTester tester, FakePty pty, String text) async {
  pty.emit(text);
  await settle(tester, rounds: 2);
}

final sessionsRow = find.byKey(const Key('terminal-sessions'));
final termView = find.byType(TerminalView);
final keysRow = find.byKey(const Key('terminal-keys'));

Rect cursorRect(WidgetTester tester) => tester.state<TerminalViewState>(termView).globalCursorRect;

/// 提示符（光标所在那一行）贴着会话行下沿，而且整行都在终端区域里、没被按键行盖住。
void expectPromptUnderTabs(WidgetTester tester, {required String reason}) {
  final tabsBottom = tester.getRect(sessionsRow).bottom;
  final view = tester.getRect(termView);
  final cursor = cursorRect(tester);
  expect(view.top, moreOrLessEquals(tabsBottom, epsilon: 0.01), reason: '$reason：终端区域紧接会话行');
  expect(cursor.top - tabsBottom, inInclusiveRange(0, kMaxTopGap), reason: '$reason：提示符离会话行下沿不超过 $kMaxTopGap');
  expect(cursor.bottom, lessThanOrEqualTo(tester.getRect(keysRow).top), reason: '$reason：提示符没被按键行盖住');
}

Future<void> shot(WidgetTester tester, String name) async {
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

void main() {
  setUpAll(() async => fontsLoaded = await loadRealFonts());

  group('逻辑：屏幕还空着时，开头的空行不上屏', () {
    test('dropLeadingLineBreaks 只去开头的回车换行，别的一个字不动', () {
      expect(dropLeadingLineBreaks(''), '');
      expect(dropLeadingLineBreaks('\r\n\n\r'), '');
      expect(dropLeadingLineBreaks('\r\n\r\nabc\r\n'), 'abc\r\n');
      expect(dropLeadingLineBreaks('abc\r\n'), 'abc\r\n');
      expect(dropLeadingLineBreaks(' \r\nabc'), ' \r\nabc', reason: '空格不算');
      expect(dropLeadingLineBreaks('\x1b[2J\r\nabc'), '\x1b[2J\r\nabc', reason: '控制符开头的原样交给终端');
    });

    final noises = <String, List<String>>{
      'bash 的真实开头': [bashStart],
      '开头两个空行': ['\r\n\r\n$bashStart'],
      '开头只有换行、分几段到': ['\n', '\n\n', '\r\n', bashStart],
      '开头一个回车': ['\r$bashStart'],
      '先清屏再提示符': ['\x1b[H\x1b[2J$bashStart'],
      '空行 + 清屏 + 提示符': ['\r\n\r\n', '\x1b[2J\x1b[3J\x1b[H', bashStart],
      '清屏（不回左上角）+ 空行': ['\x1b[H\x1b[2J', '\r\n$bashStart'],
    };
    for (final entry in noises.entries) {
      test('${entry.key}：第一行就是提示符，光标在第 0 行', () async {
        final backend = FakeBackend();
        final s = TerminalSession(title: 't', backend: backend);
        addTearDown(s.dispose);
        s.terminal.resize(47, 33);
        await s.ensureStarted();
        for (final chunk in entry.value) {
          backend.out.add(chunk);
          await tick();
        }
        if (entry.key.startsWith('清屏（不回左上角）')) {
          // 清屏符本身算“有内容”，之后的换行照常生效：这是程序自己要的排版，不替它改
          expect(lineAt(s.terminal, 1), 'root@localhost:/workspace#');
          return;
        }
        expectPromptOnTop(s.terminal, reason: entry.key);
        expect(s.text, 'root@localhost:/workspace#');
      });
    }

    test('开头是真的文字（比如报错）：一个字都不吞，提示符跟在后面', () async {
      final backend = FakeBackend();
      final s = TerminalSession(title: 't', backend: backend);
      addTearDown(s.dispose);
      s.terminal.resize(47, 33);
      await s.ensureStarted();
      backend.out.add('\r\nbash: 出了点事\r\n\r\n$bashStart');
      await tick();
      expect(lineAt(s.terminal, 0), 'bash: 出了点事');
      expect(lineAt(s.terminal, 1), '', reason: '文字后面的空行是程序自己的，留着');
      expect(lineAt(s.terminal, 2), 'root@localhost:/workspace#');
    });

    test('我们自己先写了一句说明：后面的输出原样上屏', () async {
      final backend = FakeBackend();
      final s = TerminalSession(title: 't', backend: backend)..append('先说一句\n');
      addTearDown(s.dispose);
      await s.ensureStarted();
      backend.out.add('\r\n$prompt');
      await tick();
      expect(lineAt(s.terminal, 0), '先说一句');
      expect(lineAt(s.terminal, 1), '');
      expect(lineAt(s.terminal, 2), 'root@localhost:/workspace#');
    });

    test('键盘升起再收起（行数 33→14→33，每一步 bash 都重画一次）：提示符一直在第 0 行', () async {
      final backend = FakeBackend();
      final s = TerminalSession(title: 't', backend: backend);
      addTearDown(s.dispose);
      s.terminal.resize(47, 33);
      await s.ensureStarted();
      backend.out.add(bashStart);
      await tick();
      for (final rows in [for (var r = 32; r >= 14; r--) r, for (var r = 15; r <= 33; r++) r]) {
        s.terminal.resize(47, rows);
        backend.out.add(bashRedraw);
        await tick();
        expectPromptOnTop(s.terminal, reason: '$rows 行');
      }
    });

    test('还没排版（80×24）就开始收输出，之后才拿到真实大小：提示符还在第 0 行', () async {
      final backend = FakeBackend();
      final s = TerminalSession(title: 't', backend: backend);
      addTearDown(s.dispose);
      await s.ensureStarted();
      backend.out.add('\r\n$bashStart');
      await tick();
      s.terminal.resize(47, 33);
      backend.out.add(bashRedraw);
      await tick();
      expectPromptOnTop(s.terminal, reason: '先收输出后排版');
    });

    test('刷了很多行：最新的提示符在最后一行，前面的都进了回滚区', () async {
      final backend = FakeBackend();
      final s = TerminalSession(title: 't', backend: backend);
      addTearDown(s.dispose);
      s.terminal.resize(47, 33);
      await s.ensureStarted();
      backend.out.add('${bashStart}seq 200\r\n${[for (var i = 1; i <= 200; i++) '$i\r\n'].join()}$prompt');
      await tick();
      final t = s.terminal;
      expect(lineAt(t, 0), 'root@localhost:/workspace# seq 200', reason: '第一行没丢');
      expect(t.buffer.cursorY, 32);
      expect(lineAt(t, t.buffer.absoluteCursorY), 'root@localhost:/workspace#');
      expect(t.buffer.lines.length, 202);
    });
  });

  group('逻辑：“清屏”以后第一行还是提示符', () {
    test('Ubuntu 的 bash：发 Ctrl+L，不发回车——打到一半的命令不会被执行，还留在第一行', () async {
      final backend = FakeBash();
      final s = TerminalSession(title: 't', backend: backend);
      addTearDown(s.dispose);
      s.terminal.resize(47, 33);
      await s.ensureStarted();
      backend.out.add('${bashStart}ls\r\na  b\r\n${prompt}rm -rf x');
      await tick();
      s.clear();
      expect(backend.written, ['\x0c']);
      expect(s.text, isEmpty, reason: '屏幕和回滚区先清掉');
      backend.out.add('\x1b[H\x1b[2J${prompt}rm -rf x'); // bash 对 Ctrl+L 的真实回应
      await tick();
      expectPromptOnTop(s.terminal, first: 'root@localhost:/workspace# rm -rf x', reason: '清屏后');
    });

    test('其他后端（SSH 等）：照旧发回车，回车带出来的空行不上屏', () async {
      final backend = FakeBackend();
      final s = TerminalSession(title: 't', backend: backend);
      addTearDown(s.dispose);
      s.terminal.resize(47, 33);
      await s.ensureStarted();
      backend.out.add('${bashStart}ls\r\na  b\r\n$prompt');
      await tick();
      s.clear();
      expect(backend.written, ['\r']);
      backend.out.add(bashEnter); // bash 对回车的真实回应：开头是 \r\n
      await tick();
      expectPromptOnTop(s.terminal, reason: '清屏后');
    });

    test('bash 退回本机 sh 以后不再发 Ctrl+L；shell 没在跑时什么都不发', () {
      final bash = FakeBash()..redrawsOnCtrlL = false;
      final a = TerminalSession(title: 'a', backend: bash)..clear();
      addTearDown(a.dispose);
      expect(bash.written, ['\r']);
      final dead = FakeBackend()..running = false;
      final b = TerminalSession(title: 'b', backend: dead)..clear();
      addTearDown(b.dispose);
      expect(dead.written, isEmpty);
    });

    test('基础模式（管道）认 Ctrl+L：清屏并在第一行重画提示符和打到一半的那行', () async {
      if (Platform.isWindows) return;
      final tmp = Directory.systemTemp.createTempSync('lopi_ttop_pipe_');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final backend = LocalShellBackend(tmp.path, spawner: (shell, {required workingDirectory, required environment, required rows, required columns}) => throw StateError('没有伪终端'));
      final seen = StringBuffer();
      final sub = backend.output.listen(seen.write);
      await backend.start(columns: 47, rows: 33);
      expect(backend.mode, LocalShellMode.pipe);
      backend.write('ec');
      await tick();
      seen.clear();
      backend.write('\x0c');
      await tick();
      expect(seen.toString(), '\x1b[H\x1b[2J\$ ec');
      await sub.cancel();
      await backend.close();
    });
  });

  group('界面 390×844（状态栏 $kStatusBar）', () {
    testWidgets('终端控件不再把系统边距当成自己的内边距（钉住根因）：外面说上边有 109 的系统边距，第一行照样贴着控件上沿', (tester) async {
      usePhoneViewport(tester);
      final backend = FakeBackend();
      final s = TerminalSession(title: 't', backend: backend);
      final focus = FocusNode();
      addTearDown(focus.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(size: kPhone, padding: EdgeInsets.only(top: 109, bottom: 34, left: 20)),
            child: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 390,
                height: 400,
                child: TerminalInputView(session: s, focusNode: focus, theme: TerminalThemes.defaultTheme, textStyle: const TerminalStyle(fontSize: 13, height: 1.3), padding: const EdgeInsets.all(4)),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      final cursor = cursorRect(tester);
      final cell = cursor.height;
      expect(cursor.top, 4, reason: '上边只有我们给的 4');
      expect(cursor.left, 4, reason: '左边也只有我们给的 4');
      // xterm 换算“点在第几列”时不再减系统边距：点第 3 列中间，算出来就是第 3 列（画面本来就不留这一份，两边对上了）
      final view = tester.state<TerminalViewState>(termView).renderTerminal;
      expect(view.getCellOffset(Offset(3.5 * cursor.width, 0.5 * cell)), const CellOffset(3, 0));
      expect(s.terminal.viewHeight, ((400 - 8) / cell).floor(), reason: '上下的系统边距不再吃掉行数');
      s.dispose();
      await tester.pumpWidget(const SizedBox());
    });

    for (final mode in [ThemeMode.dark, ThemeMode.light]) {
      final suffix = mode == ThemeMode.light ? 'light' : 'dark';
      testWidgets('新开的终端：提示符在第一行，紧贴会话行下沿 ($suffix)', (tester) async {
        final rig = await openTerminal(tester, mode: mode);
        expect(tester.getRect(sessionsRow).top, kStatusBar + 64, reason: '会话行在顶栏下沿（状态栏 + 64）');
        final t = rig.session.terminals.single.terminal;
        await emit(tester, rig.ptys.single, '\r\n$bashStart');
        expectPromptOnTop(t, reason: '新开');
        expectPromptUnderTabs(tester, reason: '新开');
        final view = tester.getRect(termView);
        final cell = cursorRect(tester).height;
        expect(t.viewHeight, ((view.height - 8) / cell).floor(), reason: '终端区域的高度全用来放行，没有被多留的边距吃掉');
        expect(tester.takeException(), isNull);
        await shot(tester, 'term-01-top-$suffix');
        await closeRig(tester, rig);
      });
    }

    testWidgets('键盘升起到收起的每一帧：提示符一直贴着会话行，光标没被键盘或按键行盖住', (tester) async {
      final rig = await openTerminal(tester);
      addTearDown(tester.view.resetViewInsets);
      final pty = rig.ptys.single;
      final t = rig.session.terminals.single.terminal;
      await emit(tester, pty, bashStart);
      final top = cursorRect(tester).top;
      for (final inset in <double>[0, 8, 30, 63, 64, 65, 90, 180, 300, 320, 310, 200, 100, 66, 64, 40, 12, 0]) {
        tester.view.viewInsets = FakeViewPadding(bottom: inset);
        await tester.pump(const Duration(milliseconds: 16));
        pty.emit(bashRedraw);
        await settle(tester, rounds: 1);
        expectPromptOnTop(t, reason: '键盘 $inset');
        expectPromptUnderTabs(tester, reason: '键盘 $inset');
        expect(cursorRect(tester).top, top, reason: '键盘 $inset：提示符没有上下跳');
        expect(cursorRect(tester).bottom, lessThanOrEqualTo(844 - inset), reason: '键盘 $inset：光标在键盘上面');
      }
      await shot(tester, 'term-02-after-keyboard-dark');
      await closeRig(tester, rig);
    });

    testWidgets('开第二个终端、切回第一个、去聊天页再回来：两个终端的提示符都在第一行', (tester) async {
      final rig = await openTerminal(tester);
      final first = rig.session.terminals.single;
      await emit(tester, rig.ptys[0], '${bashStart}echo one\r\none\r\n$prompt');
      final firstCursor = cursorRect(tester);

      rig.session.addTerminal();
      await settle(tester);
      expect(rig.ptys, hasLength(2), reason: '第二个终端的 shell 起来了');
      final second = rig.session.terminals[1];
      await emit(tester, rig.ptys[1], '\r\n$bashStart');
      expectPromptOnTop(second.terminal, reason: '第二个终端');
      expectPromptUnderTabs(tester, reason: '第二个终端');

      rig.session.selectTerminal(0);
      await settle(tester);
      expect(lineAt(first.terminal, 0), 'root@localhost:/workspace# echo one');
      expect(cursorRect(tester), firstCursor, reason: '切回第一个：内容和位置都没变');

      const nav = ShellDest.bottom;
      await tester.tap(find.byKey(ValueKey('nav-${nav.indexOf(ShellDest.files)}')));
      await settle(tester);
      await tester.tap(find.byKey(ValueKey('nav-${nav.indexOf(ShellDest.terminal)}')));
      await settle(tester);
      expect(cursorRect(tester), firstCursor, reason: '从别的页签回来：位置没变');
      rig.session.selectTerminal(1);
      await settle(tester);
      expectPromptOnTop(second.terminal, reason: '回来后的第二个终端');
      expectPromptUnderTabs(tester, reason: '回来后的第二个终端');
      expect(tester.takeException(), isNull);
      await closeRig(tester, rig);
    });

    testWidgets('转成横屏再转回来：提示符都在第一行、贴着会话行', (tester) async {
      final rig = await openTerminal(tester);
      final pty = rig.ptys.single;
      final t = rig.session.terminals.single.terminal;
      await emit(tester, pty, bashStart);
      final portrait = cursorRect(tester);
      final columns = t.viewWidth;

      tester.view.physicalSize = const Size(844, 390);
      tester.view.padding = const FakeViewPadding(top: 24);
      tester.view.viewPadding = const FakeViewPadding(top: 24);
      await tester.pump();
      pty.emit(bashRedraw);
      await settle(tester, rounds: 2);
      expect(t.viewWidth, greaterThan(columns), reason: '横屏列数变多');
      expectPromptOnTop(t, reason: '横屏');
      expectPromptUnderTabs(tester, reason: '横屏');
      expect(tester.takeException(), isNull);

      tester.view.physicalSize = kPhone;
      tester.view.padding = const FakeViewPadding(top: kStatusBar);
      tester.view.viewPadding = const FakeViewPadding(top: kStatusBar);
      await tester.pump();
      pty.emit(bashRedraw);
      await settle(tester, rounds: 2);
      expectPromptOnTop(t, reason: '转回竖屏');
      expect(cursorRect(tester), portrait, reason: '转回竖屏：回到原位');
      expect(tester.takeException(), isNull);
      await closeRig(tester, rig);
    });

    testWidgets('刷了很多行：最新的提示符在最下面一行、看得见；第一屏开头没有空白', (tester) async {
      final rig = await openTerminal(tester);
      final pty = rig.ptys.single;
      final t = rig.session.terminals.single.terminal;
      await emit(tester, pty, '${bashStart}seq 200\r\n${[for (var i = 1; i <= 200; i++) '$i\r\n'].join()}$prompt');
      final view = tester.getRect(termView);
      final cursor = cursorRect(tester);
      expect(t.buffer.cursorY, t.viewHeight - 1, reason: '提示符在最后一行');
      expect(cursor.bottom, lessThanOrEqualTo(view.bottom), reason: '最新一行没被按键行盖住');
      expect(view.bottom - cursor.bottom, lessThan(cursor.height + 8), reason: '最新一行贴着终端区域底部，下面没有多出空白');
      expect(cursor.top, greaterThan(tester.getRect(sessionsRow).bottom), reason: '也没被会话行盖住');

      // 再点“清屏”：回到第一行
      await tester.dragUntilVisible(find.text('清屏'), keysRow, const Offset(-120, 0));
      await tester.tap(find.text('清屏'));
      await tester.pump();
      expect(pty.written, [0x0c], reason: 'Ubuntu 的 bash：清屏发的是 Ctrl+L');
      await emit(tester, pty, '\x1b[H\x1b[2J$prompt');
      expectPromptOnTop(t, reason: '清屏后');
      expectPromptUnderTabs(tester, reason: '清屏后');
      await shot(tester, 'term-03-after-clear-dark');
      await closeRig(tester, rig);
    });
  });
}
