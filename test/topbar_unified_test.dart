// 全应用统一的悬浮顶栏（390×844，状态栏 30，浅色 + 深色）— 2026-11-24 霜霜真机反馈第二轮第 5 条的守门：
// 所有页面的顶栏高度相同（64，不含状态栏）、位置相同、没有底色和分隔线；内容起始不被顶栏挡住；能滚的内容滚动后到了顶栏下面；
// 不能滚的正文（终端、文件）整块摆在顶栏下沿之下；键盘弹起、侧边栏推开时顶栏还在原位 / 跟着主界面走。
//   LOPI_SHOTS=1 flutter test --no-pub test/topbar_unified_test.dart   # 同时把截图写到 docs/screenshots/05-*.png
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/agent/provider_presets.dart';
import 'package:lopicode/build/build_widgets.dart';
import 'package:lopicode/core/stores.dart';
import 'package:lopicode/core/templates.dart';
import 'package:lopicode/lowcode/builder_screen.dart';
import 'package:lopicode/lowcode/canvas_view.dart';
import 'package:lopicode/ui/automation_screen.dart';
import 'package:lopicode/ui/error_guard.dart';
import 'package:lopicode/ui/files_tab.dart';
import 'package:lopicode/ui/model_setup.dart';
import 'package:lopicode/ui/project_shell.dart';
import 'package:lopicode/ui/settings_ai.dart';
import 'package:lopicode/ui/settings_pages.dart';
import 'package:lopicode/ui/settings_screen.dart';
import 'package:lopicode/ui/settings_widgets.dart';
import 'package:lopicode/ui/shell.dart';
import 'package:lopicode/ui/terminal_tab.dart';
import 'package:lopicode/ui/third_party_screen.dart';
import 'package:lopicode/ui/top_bar.dart';
import 'package:material_ui/material_ui.dart';

import 'screens_test.dart' show fontsLoaded, shot;
import 'shell_test.dart' show openProject;
import 'support/harness.dart';

const double kStatus = 30;

/// 状态栏 + 顶栏：内容起始要让开这么多。
const double kInset = kStatus + PageBar.kHeight;

Finder k(String key) => find.byKey(ValueKey(key));

/// 现在看得见的那个顶栏（它自己透明、不接手指，靠“里面的左圆按钮点得到”来认）。
Finder shownBar() => find.ancestor(of: find.byType(RoundIconButton).hitTestable(), matching: find.byType(PageBar));

/// 假装有 30 高的状态栏（整个应用、包括推进来的页面都看得到）。
void useStatusBar(WidgetTester tester) {
  usePhoneViewport(tester);
  tester.view.padding = const FakeViewPadding(top: kStatus);
  tester.view.viewPadding = const FakeViewPadding(top: kStatus);
}

/// 这一页的顶栏是统一的那一个：位置、高度一样；没有底色、分隔线、整条阴影；只有一层不接手指、往下淡到透明的遮罩。
void expectFloatingBar(WidgetTester tester, String what, {double left = 0}) {
  final b = shownBar();
  expect(b, findsOneWidget, reason: what);
  final rect = tester.getRect(b);
  expect(rect, Rect.fromLTWH(left, 0, 390, kInset), reason: '$what：顶栏从屏幕最顶算起，高 = 状态栏 + ${PageBar.kHeight}');
  expect(
    tester.getRect(find.descendant(of: b, matching: find.byType(RoundIconButton))),
    Rect.fromLTWH(left + 16, kStatus + 10, 44, 44),
    reason: '$what：左圆按钮的位置',
  );
  for (final e in find.descendant(of: b, matching: find.byWidgetPredicate((w) => w is DecoratedBox || w is ColoredBox || w is Container || w is Material)).evaluate()) {
    final w = e.widget;
    if (w.key == const ValueKey('bar-scrim')) continue;
    final painted = switch (w) {
      DecoratedBox(:final decoration) => decoration is BoxDecoration && (decoration.color != null || decoration.gradient != null || decoration.border != null || decoration.boxShadow != null),
      ColoredBox(:final color) => color.a > 0,
      Container(:final decoration, :final color) => color != null || decoration != null,
      Material(:final type) => type != MaterialType.transparency,
      _ => false,
    };
    if (!painted) continue;
    final r = tester.getRect(find.byElementPredicate((x) => x == e));
    expect(r.width, lessThan(260), reason: '$what：顶栏里不许有横贯整条的底色 / 分隔线 / 阴影（${w.runtimeType} $r）');
  }
  expect(
    find.descendant(of: b, matching: find.byType(Divider)),
    findsNothing,
    reason: what,
  );
  final scrim = find.descendant(of: b, matching: k('bar-scrim'));
  expect(scrim, findsOneWidget, reason: what);
  expect(
    find.ancestor(of: scrim, matching: find.byType(IgnorePointer)),
    findsWidgets,
    reason: '$what：遮罩不接手指',
  );
  final g = (tester.widget<DecoratedBox>(scrim).decoration as BoxDecoration).gradient! as LinearGradient;
  expect(g.colors.first.a, 1, reason: '$what：状态栏那一段是实的页面底色');
  expect(g.colors.last.a, 0, reason: '$what：往下淡到全透明，没有边');
  // 标题只有文字：外面没有胶囊。
  final title = find.descendant(of: b, matching: find.byType(BarTitle));
  if (title.evaluate().isNotEmpty) {
    var boxed = false;
    tester.element(title.first).visitAncestorElements((e) {
      if (e.widget is PageBar) return false;
      if (e.widget case DecoratedBox(:final BoxDecoration decoration) when decoration.color != null || decoration.border != null) boxed = true;
      return true;
    });
    expect(boxed, isFalse, reason: '$what：标题外面没有底色胶囊');
  }
  // 页面的 Scaffold 让内容从屏幕最顶铺起。
  final scaffold = find.ancestor(of: b, matching: find.byType(Scaffold)).first;
  final s = tester.widget<Scaffold>(scaffold);
  if (s.appBar != null) expect(s.extendBodyBehindAppBar, isTrue, reason: '$what：内容要从顶栏下面铺起');
}

/// 把一页当成“推进来的页面”打开（左上角是返回）。
Future<TestEnv> pushPage(WidgetTester tester, Widget Function(BuildContext) page, {ThemeMode mode = ThemeMode.light}) async {
  useStatusBar(tester);
  late TestEnv env;
  await tester.runAsync(() async => env = await TestEnv.create());
  addTearDown(() => env.dispose());
  await tester.pumpWidget(
    appFor(
      env,
      Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: page)),
              child: const Text('进去'),
            ),
          ),
        ),
      ),
      mode: mode,
      font: fontsLoaded ? kTestFont : null,
    ),
  );
  await tester.tap(find.text('进去'));
  await settle(tester, rounds: 3);
  await tester.pump(const Duration(seconds: 1)); // 进场动画走完
  return env;
}

void main() {
  setUpAll(() async => fontsLoaded = await loadRealFonts());

  test('源码守门：只有一套顶栏；每个带顶栏的 Scaffold 都让内容从顶栏下面铺起', () {
    expect(File('lib/ui/immersive_bar.dart').existsSync(), isFalse, reason: '沉浸式顶栏已经并进 lib/ui/top_bar.dart');
    final bad = <String>[];
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        final code = line.trimLeft();
        if (code.startsWith('//')) continue;
        // 系统的 AppBar / SliverAppBar、自己另写一个 PreferredSizeWidget 顶栏：都不许。
        if (RegExp(r'(^|[^A-Za-z])(Sliver)?AppBar\(').hasMatch(line) && !line.contains('ShellAppBar(')) bad.add('${f.path}:${i + 1} 用了系统 AppBar');
        if (line.contains('toolbarHeight')) bad.add('${f.path}:${i + 1} 自己定了顶栏高度');
        if (code.startsWith('appBar:')) {
          if (!RegExp(r'appBar: (const )?(PageBar|ShellAppBar)\(').hasMatch(code)) bad.add('${f.path}:${i + 1} 顶栏不是 PageBar / ShellAppBar');
          if (i == 0 || !lines[i - 1].contains('extendBodyBehindAppBar: true')) bad.add('${f.path}:${i + 1} 少了 extendBodyBehindAppBar: true');
        }
      }
    }
    expect(bad, isEmpty, reason: bad.join('\n'));
    // 顶栏只有一个高度；ShellAppBar 只是 PageBar 外面套一层。
    expect(const ShellAppBar(title: 'x').preferredSize.height, PageBar.kHeight);
    expect(const PageBar(titleText: 'x').preferredSize.height, PageBar.kHeight);
  });

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    final suffix = mode == ThemeMode.light ? '浅色' : '深色';

    testWidgets('五个主页面：同一个悬浮顶栏；聊天内容从顶栏下滚过；终端 / 文件整块在顶栏下沿之下；侧边栏推开时顶栏跟着走 ($suffix)', (tester) async {
      useStatusBar(tester);
      late TestEnv env;
      final reply = [for (var i = 1; i <= 40; i++) '第 $i 行：这是一段比较长的回复，用来把对话撑得比一屏高。'].join('\n\n');
      await tester.runAsync(() async {
        env = await TestEnv.create(
          chatClient: () => ScriptedChatClient([
            [say(reply)],
          ]),
        );
      });
      final (_, project, session) = await openProject(tester, env: env, template: ProjectTemplate.web);
      // 打包页重做后没选过方式的默认是“本地打包”，那一页可能很短（项目不适用时只有一张卡），滚不到顶栏下面；
      // 这个用例看的是顶栏和滚动，先存成原来的默认值（GitHub Actions 的长表单）。
      await tester.runAsync(() => env.services.settings.set(SettingKeys.apkBuildMode, 'github'));
      await tester.pumpWidget(
        appFor(
          env,
          ProjectShell(project: project, session: session),
          mode: mode,
          font: fontsLoaded ? kTestFont : null,
        ),
      );
      await settle(tester);

      // 聊天（空）：空状态整块在顶栏下面。
      expectFloatingBar(tester, '聊天（空）');
      await shot(tester, '05-聊天-空-$suffix');

      await tester.enterText(find.byType(TextField), '写一段很长的话');
      await tester.pump();
      await tester.tap(find.byTooltip('发送'));
      await tester.runAsync(() async {
        for (var i = 0; i < 60 && (session.agentBusy || session.chat.length < 2); i++) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
      });
      await settle(tester, rounds: 4);
      FocusManager.instance.primaryFocus?.unfocus();
      await settle(tester, rounds: 2);
      expectFloatingBar(tester, '聊天（有消息）');
      final list = find.byType(Scrollable).hitTestable().first;
      final pos = tester.state<ScrollableState>(list).position;
      expect(pos.maxScrollExtent, greaterThan(400), reason: '对话比一屏高');
      expect(tester.getRect(list).top, 0, reason: '消息列表从屏幕最顶铺起');
      // 滚到最上面：第一条消息在顶栏下沿之下。
      pos.jumpTo(0);
      await tester.pump();
      final bubble = find.descendant(of: list, matching: find.text('写一段很长的话'));
      expect(tester.getRect(bubble).top, greaterThanOrEqualTo(kInset), reason: '起始时第一条消息不被顶栏挡住');
      await shot(tester, '05-聊天-顶部-$suffix');
      // 往上滚：消息到了顶栏下面，顶栏原地不动。
      pos.jumpTo(140);
      await tester.pump();
      expect(tester.getRect(bubble).top, lessThan(kInset - 40), reason: '滚动后内容到了顶栏下面');
      expectFloatingBar(tester, '聊天（滚动后）');
      await shot(tester, '05-聊天-滚动后内容在顶栏下方-$suffix');

      // 文件、终端：不是能滚的一列，整块从顶栏下沿开始。
      await tester.tap(k('nav-1'));
      await settle(tester, rounds: 6);
      expectFloatingBar(tester, '文件');
      expect(tester.getRect(find.byType(FilesTab)).top, kInset);
      await tester.tap(k('nav-2'));
      await settle(tester, rounds: 6);
      expectFloatingBar(tester, '终端');
      expect(tester.getRect(find.byType(TerminalTab)).top, kInset, reason: '终端（页签条 + 终端文字）不钻到顶栏下面');
      await shot(tester, '05-终端-$suffix');
      await tester.tap(k('nav-3'));
      await settle(tester, rounds: 8);
      expectFloatingBar(tester, '搭建');
      await tester.tap(k('nav-4'));
      await settle(tester, rounds: 6);
      expectFloatingBar(tester, '打包');
      final apkList = find.byType(Scrollable).hitTestable().first;
      expect(tester.getRect(apkList).top, 0);
      // 打包页重做后最上面是三选一（BuildModePicker），原来是两段的 SegmentedButton<bool>；要验的还是“第一块内容起始在顶栏下面、能滚到顶栏下面”。
      final first = find.descendant(of: apkList, matching: find.byType(BuildModePicker));
      expect(tester.getRect(first).top, greaterThan(kInset));
      // 三选一就在页面最上面、只有 44 高：滚 200 它整块出了屏幕（查找器不认屏幕外的）。滚 30，让它的上沿钻到顶栏下面、下半截还露着。
      tester.state<ScrollableState>(apkList).position.jumpTo(30);
      await tester.pump();
      expect(tester.getRect(first).top, lessThan(kInset), reason: '打包页的内容滚到顶栏下面');

      // 底部导航还钉在屏幕底。
      expect(tester.getRect(k('nav-0')).bottom, 844);

      // 侧边栏推开：顶栏跟着主界面一起右移。
      await tester.tap(find.byTooltip('打开侧边栏').hitTestable());
      await tester.pumpAndSettle();
      expect(tester.getRect(find.byType(PageBar).last).left, greaterThan(100), reason: '顶栏跟着主界面被推走');
      expect(tester.takeException(), isNull);
    });

    testWidgets('设置一级页：内容起始在顶栏下沿之下，滚动后从顶栏下面穿过 ($suffix)', (tester) async {
      await pushPage(tester, (_) => const SettingsScreen(), mode: mode);
      expectFloatingBar(tester, '设置');
      final scroll = find.byType(Scrollable).hitTestable().first;
      expect(tester.getRect(scroll).top, 0, reason: '内容区从屏幕最顶铺起');
      final firstGroup = find.byType(SettingsGroup).first;
      // 滚动内容的那一列：起始时顶边在顶栏下沿之下（留 8 的间距）。
      final content = find.descendant(of: scroll, matching: find.byType(Column)).first;
      expect(tester.getRect(content).top, kInset + 8, reason: '内容起始不被顶栏挡住');
      final before = tester.getRect(firstGroup).top;
      expect(before, greaterThanOrEqualTo(kInset), reason: '第一组不被顶栏挡住');
      await shot(tester, '05-设置-$suffix');
      await tester.drag(scroll, const Offset(0, -180));
      await tester.pumpAndSettle();

      expect(tester.getRect(firstGroup).top, lessThan(before - 150), reason: '内容跟着滚了');
      expect(tester.getRect(content).top, lessThan(kInset - 100), reason: '滚动后内容到了顶栏下面');
      expectFloatingBar(tester, '设置（滚动后）');
      await shot(tester, '05-设置-滚动后内容在顶栏下方-$suffix');
      expect(tester.takeException(), isNull);
    });

    testWidgets('添加渠道页：同一个高度；表单起始在顶栏下面；键盘弹起时顶栏不动；滚动后表单从顶栏下面穿过 ($suffix)', (tester) async {
      await pushPage(tester, (_) => ChannelEditScreen(preset: kProviderPresets.first), mode: mode);
      expectFloatingBar(tester, '添加渠道');
      expect(find.descendant(of: shownBar(), matching: find.text('添加渠道')), findsOneWidget);
      final firstGroup = find.byType(SettingsGroup).first;
      expect(tester.getRect(firstGroup).top, greaterThanOrEqualTo(kInset));
      await shot(tester, '05-添加渠道-$suffix');
      // 键盘弹起
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pumpAndSettle();
      expectFloatingBar(tester, '添加渠道（键盘弹起）');
      tester.view.viewInsets = FakeViewPadding.zero;
      await tester.pumpAndSettle();
      final scroll = find.byType(Scrollable).hitTestable().first;
      final pos = tester.state<ScrollableState>(scroll).position;
      expect(pos.maxScrollExtent, greaterThan(0), reason: '表单比一屏高，能滚');
      final before = tester.getRect(firstGroup).top;
      await tester.drag(scroll, const Offset(0, -260));
      await tester.pumpAndSettle();
      expect(tester.getRect(firstGroup).top, lessThan(kInset), reason: '滚动后表单到了顶栏下面');
      expect(tester.getRect(firstGroup).top, lessThan(before));
      expectFloatingBar(tester, '添加渠道（滚动后）');
      await shot(tester, '05-添加渠道-滚动后内容在顶栏下方-$suffix');
      // 滚到底：“保存”够得着。
      await tester.drag(scroll, const Offset(0, -3000));
      await tester.pumpAndSettle();
      expect(k('channel-save').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('搭建页（低代码画布）：同一个顶栏，画布到顶，页面起始在顶栏下沿 ($suffix)', (tester) async {
      useStatusBar(tester);
      final (env, project, session) = await openProject(tester);
      await tester.pumpWidget(
        appFor(
          env,
          Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => BuilderScreen(session: session))),
                  child: const Text('进去'),
                ),
              ),
            ),
          ),
          mode: mode,
          font: fontsLoaded ? kTestFont : null,
        ),
      );
      await tester.tap(find.text('进去'));
      await settle(tester, rounds: 6);
      await tester.pump(const Duration(seconds: 1));
      expect(project.name, '我的小站');
      expectFloatingBar(tester, '低代码搭建');
      final view = find.byType(CanvasView).hitTestable();
      expect(tester.getRect(view).top, 0, reason: '画布从屏幕最顶铺起');
      expect(tester.state<CanvasViewState>(view).pageRect.top, kInset, reason: '页面顶边起始在顶栏下沿');
      await shot(tester, '05-搭建-$suffix');
      await tester.dragFrom(const Offset(195, 400), const Offset(0, -120));
      await tester.pump(const Duration(seconds: 2));
      await settle(tester, rounds: 2);
      await shot(tester, '05-搭建-滚动后-$suffix');
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('二级 / 三级页和独立页面：顶栏都是同一个高度、同一个位置、没有底色', (tester) async {
    final pages = <String, Widget Function(BuildContext)>{
      '选择服务商': (_) => const ProviderPickerScreen(),
      '模型与渠道': (_) => const ChannelsScreen(),
      'Agent 行为': (_) => const AgentBehaviorScreen(),
      '对话显示': (_) => const ChatDisplayScreen(),
      '外观': (_) => const AppearanceScreen(),
      '自动化任务': (_) => const AutomationListScreen(),
      '新建自动化任务': (_) => const AutomationEditScreen(),
      '第三方声明': (_) => const ThirdPartyScreen(),
      '错误日志': (_) => const ErrorLogScreen(),
    };
    for (final entry in pages.entries) {
      await pushPage(tester, entry.value);
      await settle(tester, rounds: 2);
      expectFloatingBar(tester, entry.key);
      // 第一样内容（文字）不在顶栏后面。
      final body = find
          .descendant(of: find.byType(Scaffold).last, matching: find.byType(Text))
          .evaluate()
          .where((e) => find.ancestor(of: find.byElementPredicate((x) => x == e), matching: find.byType(PageBar)).evaluate().isEmpty);
      for (final e in body) {
        final r = tester.getRect(find.byElementPredicate((x) => x == e));
        expect(r.top, greaterThanOrEqualTo(kInset), reason: '${entry.key}：“${(e.widget as Text).data}”起始时被顶栏挡住了');
      }
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    }
    expect(tester.takeException(), isNull);
  });
}
