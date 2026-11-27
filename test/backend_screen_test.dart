// 后端积木页（BackendScreen）与“搭建”页外壳（BuilderHubScreen）的界面测试（390×844，浅色 + 深色）。
//   LOPI_SHOTS=1 flutter test --no-pub test/backend_screen_test.dart   # 同时把截图写到 docs/screenshots/be-*.png
//
// 整个应用外壳（ProjectShell）真的搭起来，项目是照模板真建在临时目录里的：
// 读写 backend.lc.json、重新生成代码都是真实文件；终端用假的伪终端，只看“往里打了哪条命令”。
// 不联网、不安装任何东西。
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/backend/backend_edit.dart';
import 'package:lopicode/backend/backend_launch.dart';
import 'package:lopicode/backend/backend_model.dart';
import 'package:lopicode/backend/backend_targets.dart';
import 'package:lopicode/blocks/block_dock.dart';
import 'package:lopicode/blocks/block_editor_view.dart';
import 'package:lopicode/blocks/block_geometry.dart';
import 'package:lopicode/core/project_store.dart';
import 'package:lopicode/core/templates.dart';
import 'package:lopicode/lang/rules.dart';
import 'package:lopicode/lowcode/builder_screen.dart';
import 'package:lopicode/lowcode/logic_expr.dart';
import 'package:lopicode/lowcode/logic_model.dart';
import 'package:lopicode/lowcode/model.dart';
import 'package:lopicode/project_session.dart';
import 'package:lopicode/templates/project_templates.dart';
import 'package:lopicode/ui/backend_run_sheet.dart';
import 'package:lopicode/ui/backend_screen.dart';
import 'package:lopicode/ui/chrome.dart';
import 'package:lopicode/ui/project_shell.dart';
import 'package:lopicode/ui/shell.dart';
import 'package:lopicode/ui/terminal_tab.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;

import 'screens_test.dart' show fontsLoaded, shot;
import 'support/harness.dart';
import 'support/runtime_fakes.dart';

Finder k(String key) => find.byKey(ValueKey(key));

late TestEnv env;
late Project project;
late ProjectSession session;

/// 假终端：每开一个记一个，`typed` 是往里打过的全部字。
final List<FakePty> ptys = [];
String typed(FakePty pty) => utf8.decode(pty.written);

File at(String rel) => File(p.join(project.dir, rel));
String text(String rel) => at(rel).readAsStringSync();
BeDocument saved([String rel = kBackendFileName]) => BeDocument.fromJson(jsonDecode(text(rel)) as Map<String, dynamic>).doc;

BackendScreenState be(WidgetTester tester) => tester.state<BackendScreenState>(find.byType(BackendScreen));
BlockEditorViewState ed(WidgetTester tester) => tester.state<BlockEditorViewState>(find.byType(BlockEditorView));
BeDocument doc(WidgetTester tester) => be(tester).host!.doc;
BeRoute routeOf(WidgetTester tester, String method, String path) => doc(tester).routes.firstWhere((r) => r.method == method && r.path == path);

/// 照模板真建一个项目并打开应用外壳。`before` 在打开之前改文件（做坏文件、加页面）。
Future<void> boot(WidgetTester tester, ProjectTemplate template, {String? language, ThemeMode mode = ThemeMode.light, ShellDest initial = ShellDest.builder, void Function()? before}) async {
  usePhoneViewport(tester);
  ptys.clear();
  await tester.runAsync(() async {
    env = await TestEnv.create();
    project = await createProjectFromTemplate(env.services.projects, '小后端', template, language: language);
    before?.call();
    session = ProjectSession(env.services, project);
    session.ptySpawner = (exe, {required workingDirectory, required environment, required rows, required columns}) {
      final pty = FakePty();
      ptys.add(pty);
      return pty;
    };
    await session.loadChat();
  });
  addTearDown(() async {
    await tester.runAsync(() async {
      session.dispose();
      await env.dispose();
    });
  });
  await tester.pumpWidget(
    appFor(
      env,
      ProjectShell(project: project, session: session, initial: initial),
      mode: mode,
      font: fontsLoaded ? kTestFont : null,
    ),
  );
  await settle(tester, rounds: 8);
}

/// 等到条件成立；一直不成立就失败。真实的文件读写每一步都要“真等一下 + 推一帧”才往下走，
/// 重新生成代码有上百步，所以这里一小步一小步地推，成立了马上停。
Future<void> until(WidgetTester tester, bool Function() done, String what) async {
  for (var i = 0; i < 1500 && !done(); i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 2)));
    await tester.pump(const Duration(milliseconds: 10));
  }
  expect(done(), isTrue, reason: '等不到：$what');
}

/// 等防抖到点、存盘和重新生成都做完。
Future<void> flushed(WidgetTester tester) async {
  await tester.pump(kBackendSaveDelay + const Duration(milliseconds: 50));
  await until(tester, () => find.byType(BackendScreen).evaluate().isEmpty || be(tester).idle, '存盘和重新生成做完');
  await tester.pump(const Duration(milliseconds: 100));
}

Future<void> tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump(const Duration(milliseconds: 50));
  await tester.tap(finder);
  await settle(tester, rounds: 2);
}

Future<void> tapKey(WidgetTester tester, String key) => tap(tester, k(key));

Future<void> tapNav(WidgetTester tester, ShellDest d) async {
  await tester.tap(k('nav-${ShellDest.bottom.indexOf(d)}'));
  await settle(tester, rounds: 6);
}

/// 顶栏“更多”里点一项。
Future<void> more(WidgetTester tester, String item) async {
  await tester.tap(k('be-more'));
  await tester.pumpAndSettle();
  await tester.tap(k('be-menu-$item'));
  await tester.pumpAndSettle();
}

/// 积木盒：切到某一类。
Future<void> paletteTab(WidgetTester tester, String category) async {
  final tab = k('bk-palette-tab-$category');
  final tabs = k('bk-palette-tabs');
  await tester.drag(tabs, const Offset(600, 0));
  await tester.pumpAndSettle();
  for (var i = 0; i < 10 && tab.hitTestable().evaluate().isEmpty; i++) {
    await tester.drag(tabs, const Offset(-120, 0));
    await tester.pumpAndSettle();
  }
  await tester.tap(tab);
  await tester.pumpAndSettle();
}

/// 从积木盒里按住一样东西拿出来。
Future<(TestGesture, Offset)> liftFromPalette(WidgetTester tester, String category, String itemKey) async {
  await paletteTab(tester, category);
  final item = k('bk-palette-item-$itemKey');
  await tester.ensureVisible(item);
  await tester.pumpAndSettle();
  final from = tester.getTopLeft(item) + const Offset(10, 20);
  final g = await tester.startGesture(from);
  await tester.pump(const Duration(milliseconds: 220));
  expect(ed(tester).drag, isNotNull, reason: '按住应该就拿出来了');
  return (g, from);
}

Future<void> glideAndDrop(WidgetTester tester, TestGesture g, Offset from, Offset Function() to) async {
  for (var i = 1; i <= 6; i++) {
    await g.moveTo(Offset.lerp(from, to(), i / 6)!);
    await tester.pump(const Duration(milliseconds: 16));
  }
  await g.moveTo(to());
  await tester.pump(const Duration(milliseconds: 16));
  await g.up();
  await tester.pumpAndSettle();
}

/// 屏幕上：某个接口的帽子上的一个槽（method / path）。
Offset hatSlot(WidgetTester tester, String routeId, String slotId) {
  final s = ed(tester);
  final placed = s.layout.placed(routeId)!;
  for (final (b, sl) in placed.layout.allSlots) {
    if (b.isHat && sl.hatSlotId == slotId) return s.globalOf(s.toView(placed.origin + sl.rect.center));
  }
  throw StateError('没找到帽子上的槽 $slotId');
}

/// 屏幕上：某个接口里某块积木的某个参数。
Offset argAt(WidgetTester tester, String routeId, LcBlockPath path, String name) {
  final s = ed(tester);
  final placed = s.layout.placed(routeId)!;
  for (final (b, sl) in placed.layout.allSlots) {
    if (b.isHat || !bkSameBlockPath(b.path, path) || sl.arg != name || sl.exprPath.isNotEmpty) continue;
    final e = sl.expr;
    return s.globalOf(s.toView(placed.origin + (e != null ? e.rect.centerLeft + const Offset(9, 0) : sl.rect.center)));
  }
  throw StateError('没找到参数 $name');
}

Future<void> typeInline(WidgetTester tester, String value) async {
  await tester.enterText(k('bk-inline-input'), value);
  await tester.testTextInput.receiveAction(TextInputAction.done);
  await tester.pumpAndSettle();
}

void main() {
  // 这个文件考的是老规矩（规矩版本 1）的行为：新建的文档现在默认是严格规矩，这里钉回 1，测完改回去。
  setUp(() => beNewDocRules = kLangRulesLoose);
  tearDown(() => beNewDocRules = kLangRulesForNewDocs);

  setUpAll(() async => fontsLoaded = await loadRealFonts());

  testWidgets('新建“后端服务（积木）”项目 → 搭建页直接是后端积木页：画布、样本接口、语言；看代码是这种语言的入口文件', (tester) async {
    await boot(tester, ProjectTemplate.backendBlocks, language: 'node');
    expect(find.byType(BackendScreen), findsOneWidget);
    expect(find.byType(BuilderScreen), findsNothing);
    expect(k('hub-switch'), findsNothing, reason: '只有后端：不出现“页面 / 后端”切换');
    expect(k('bk-canvas'), findsOneWidget);
    expect(find.text('后端积木'), findsOneWidget);
    expect(find.text('Node.js · 7 个接口'), findsOneWidget);
    expect([for (final r in doc(tester).routes) '${r.method} ${r.path}'], containsAll(['GET /hello', 'GET /todos', 'POST /todos', 'GET /todos/:id']));
    expect(ed(tester).layout.scripts.length, 7, reason: '七个接口都排在画布上');
    final navTop = tester.getRect(find.byType(IconBottomNav)).top;
    expect(tester.getRect(find.byType(BackendScreen)).bottom, navTop, reason: '积木盒在底部导航上方');
    await shot(tester, 'be-screen-light');

    await tester.tap(k('bk-code'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Node.js'), findsWidgets);
    expect(find.textContaining(be(tester).host!.codeText.trim().split('\n').first), findsWidgets, reason: '面板里就是生成的 server.js');
    await shot(tester, 'be-code-light');
    expect(text('server.js'), be(tester).host!.codeText, reason: '和磁盘上那份一样');
    expect(tester.takeException(), isNull);
  });

  testWidgets('搭一个新接口：从积木盒拖出 POST 帽子、拖一块“返回 JSON”进去、就地改路径和状态码 → backend.lc.json 和生成的代码都跟上；路径填错说原因', (tester) async {
    await boot(tester, ProjectTemplate.backendBlocks, language: 'node');
    final s = ed(tester);
    // 把样本接口挪出视野，在空地方搭（免得叠在一起点错）。
    s.setPan(const Offset(0, -4000));
    await tester.pumpAndSettle();
    final canvas = tester.getTopLeft(k('bk-canvas'));

    var (g, from) = await liftFromPalette(tester, 'event', 'hat-POST');
    await glideAndDrop(tester, g, from, () => canvas + const Offset(60, 120));
    final id = doc(tester).routes.last.id;
    expect((doc(tester).routes.length, doc(tester).routes.last.method, doc(tester).routes.last.path), (8, 'POST', '/new'), reason: '样本里已经有 POST /todos，新接口叫 /new');
    expect(doc(tester).routes.last.x, isNotNull, reason: '放在松手的地方');

    (g, from) = await liftFromPalette(tester, '返回', 'block-respondJson');
    await glideAndDrop(tester, g, from, () {
      final placed = ed(tester).drag!.base.placed(id)!;
      final snap = placed.layout.snaps.firstWhere((x) => x.kind == BkSnapKind.statement && x.parent.isEmpty && x.index == 0);
      return ed(tester).globalOf(ed(tester).toView(placed.origin + snap.anchor + ed(tester).grabOffset));
    });
    expect([for (final b in doc(tester).route(id)!.body) b.op], ['respondJson'], reason: '拼在帽子下面');

    // 路径填错：不改，说原因。
    await tester.tapAt(hatSlot(tester, id, 'path'));
    await tester.pumpAndSettle();
    await typeInline(tester, 'echo');
    expect(find.textContaining('路径要用 / 开头'), findsOneWidget);
    expect(doc(tester).route(id)!.path, '/new');
    ScaffoldMessenger.of(tester.element(find.byType(BackendScreen))).clearSnackBars();
    await tester.pumpAndSettle();

    await tester.tapAt(hatSlot(tester, id, 'path'));
    await tester.pumpAndSettle();
    await typeInline(tester, '/echo/:word');
    expect(doc(tester).route(id)!.path, '/echo/:word');
    await tester.tapAt(argAt(tester, id, [lcStep(0)], 'status'));
    await tester.pumpAndSettle();
    await typeInline(tester, '201');
    expect(doc(tester).route(id)!.body.single.args['status'], exNum(201));
    // 请求方式是下拉。
    await tester.tapAt(hatSlot(tester, id, 'method'));
    await tester.pumpAndSettle();
    await tester.tap(k('bk-menu-PUT'));
    await tester.pumpAndSettle();
    expect(doc(tester).route(id)!.method, 'PUT');
    expect(be(tester).idle, isFalse, reason: '还在防抖里，没存');
    expect(saved().route(id), isNull);

    await flushed(tester);
    await until(tester, () => text('server.js').contains('/echo/:word'), '生成的代码更新');
    final onDisk = saved();
    final r = onDisk.route(id)!;
    expect((r.method, r.path), ('PUT', '/echo/:word'));
    expect(r.body.single.op, 'respondJson');
    expect(r.body.single.args['status'], exNum(201));
    expect(text('server.js'), contains('201'));
    expect(text('server.js'), be(tester).host!.codeText);
    expect(find.text('Node.js · 8 个接口'), findsOneWidget);
    expect(be(tester).host!.issues.where((i) => i.isError), isEmpty);

    // 撤销 → 也会存下去。
    await tester.tap(k('bk-undo'));
    await tester.pumpAndSettle();
    expect(doc(tester).route(id)!.method, 'POST');
    await flushed(tester);
    await until(tester, () => saved().route(id)!.method == 'POST', '撤销后的内容落盘');
    expect(tester.takeException(), isNull);
  });

  testWidgets('深色：有错误的积木在画布上标红，副标题和底部提示说代码没有更新；启动被拦', (tester) async {
    await boot(tester, ProjectTemplate.backendBlocks, language: 'node', mode: ThemeMode.dark);
    final host = be(tester).host!;
    final hello = routeOf(tester, 'GET', '/hello').id;
    host.edit(() => host.script(hello)!.body.insert(0, LcBlock(op: 'setVar', args: {'name': '没有这个变量', 'value': exText('')})));
    await tester.pump();
    await flushed(tester);
    await until(tester, () => find.text('1 个错误，没更新').evaluate().isNotEmpty, '副标题说代码没有更新');
    expect(k('be-blocked-snack'), findsOneWidget);
    await shot(tester, '8-be-blocked-dark');
    ScaffoldMessenger.of(tester.element(k('bk-canvas'))).hideCurrentSnackBar();
    await tester.pumpAndSettle();
    await tester.tap(k('be-run'));
    await tester.pumpAndSettle();
    expect(k('bk-errors-gate'), findsOneWidget);
    expect(find.byType(BeRunSheet), findsNothing);
    await shot(tester, '8-be-gate-dark');
    await tester.tap(k('bk-errors-gate-close'));
    await tester.pumpAndSettle();
    expect(k('bk-errors-gate'), findsNothing);
    expect(find.byType(BeRunSheet), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('点积木盒也能加；积木有错误：模型照样保存，但代码不更新——副标题明说，启动被拦下并指向问题列表；修好以后自动重新生成', (tester) async {
    await boot(tester, ProjectTemplate.backendBlocks, language: 'node');
    await paletteTab(tester, 'event');
    await tapKey(tester, 'bk-palette-item-hat-GET');
    expect(doc(tester).routes.last.path, '/new');
    await paletteTab(tester, '调试');
    await tapKey(tester, 'bk-palette-item-block-log');
    expect(doc(tester).routes.last.body.single.op, 'log');
    await flushed(tester);
    await until(tester, () => text('server.js').contains("'/new'") || text('server.js').contains('"/new"') || text('server.js').contains('/new'), '新接口进了代码');

    final host = be(tester).host!;
    final hello = routeOf(tester, 'GET', '/hello').id;
    host.edit(() => host.script(hello)!.body.insert(0, LcBlock(op: 'setVar', args: {'name': '没有这个变量', 'value': exText('')})));
    await tester.pump();
    await flushed(tester);
    final codeBefore = text('server.js');
    await until(tester, () => text(kBackendFileName).contains('没有这个变量'), '有错误也保存模型');
    await until(tester, () => find.text('1 个错误，没更新').evaluate().isNotEmpty, '副标题说代码没有更新');
    expect(find.text('有 1 个错误，代码没有更新'), findsOneWidget, reason: '底部的提示是完整的一句');
    // 刚出错时底部提示一次，带“查看问题”。
    expect(k('be-blocked-snack'), findsOneWidget);
    expect(find.text('查看问题'), findsOneWidget);
    expect(text('server.js'), codeBefore, reason: '有错误不生成新代码：上一次生成的原样留着');
    // 积木上有标记、顶栏的问题数是红的。
    expect(find.descendant(of: k('bk-issues'), matching: find.byType(Badge)), findsOneWidget);
    await shot(tester, '8-be-blocked-light');

    // 启动被拦下：不开运行面板，说明原因，主按钮“查看问题”。
    ScaffoldMessenger.of(tester.element(k('bk-canvas'))).hideCurrentSnackBar();
    await tester.pumpAndSettle();
    await tester.tap(k('be-run'));
    await tester.pumpAndSettle();
    expect(k('bk-errors-gate'), findsOneWidget);
    expect(find.text('有 1 个错误，代码没有更新'), findsWidgets);
    expect(find.textContaining('现在不能启动'), findsOneWidget);
    expect(find.byType(BeRunSheet), findsNothing);
    await shot(tester, '8-be-gate-light');
    await tester.tap(k('bk-errors-gate-open'));
    await tester.pumpAndSettle();
    expect(k('bk-errors-gate'), findsNothing);
    expect(find.text('1 个问题'), findsOneWidget);
    expect(find.textContaining('没有这个变量'), findsWidgets);
    await shot(tester, '8-be-issues-light');
    // 点那一条：跳到那块积木并选中。
    final idx = host.issues.indexWhere((i) => i.isError);
    await tester.tap(k('bk-issue-$idx'));
    await tester.pumpAndSettle();
    expect(ed(tester).selection!.scriptId, hello);
    expect(ed(tester).selection!.path.single.index, 0);

    // 修好（删掉那块）：自动重新生成，副标题恢复，启动不再被拦。
    host.edit(() => host.script(hello)!.body.removeAt(0));
    await tester.pump();
    await flushed(tester);
    await until(tester, () => find.text('1 个错误，没更新').evaluate().isEmpty, '修好以后副标题恢复');
    await until(tester, () => text('server.js').contains('/new'), '修好以后重新生成');
    await tester.tap(k('be-run'));
    await tester.pumpAndSettle();
    expect(k('bk-errors-gate'), findsNothing);
    expect(find.byType(BeRunSheet), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('切换语言：写进文档并重新生成——旧语言的生成文件清掉，新语言的出现；没实测的语言标“未实测”', (tester) async {
    await boot(tester, ProjectTemplate.backendBlocks, language: 'node');
    expect(at('server.js').existsSync(), isTrue);
    await more(tester, 'language');
    expect(k('be-lang-current'), findsOneWidget);
    for (final t in backendTargets) {
      expect(k('be-lang-${t.id}'), findsOneWidget, reason: t.id);
      expect(k('be-lang-unverified-${t.id}'), t.verified ? findsNothing : findsOneWidget, reason: t.id);
    }
    // 2026-11-26 改：PHP 真跑过了，不再标“未实测”（原来断言这里有标）。
    expect(k('be-lang-unverified-php'), findsNothing);
    await shot(tester, 'be-language-light');
    await tapKey(tester, 'be-lang-python');
    expect(doc(tester).language, 'python');
    await flushed(tester);
    await until(tester, () => at('server.py').existsSync() && !at('server.js').existsSync(), '换成 Python 的文件');
    expect(saved().language, 'python');
    expect(find.text('Python · 7 个接口'), findsOneWidget);
    expect(text('server.py'), be(tester).host!.codeText);
    expect(Directory(project.dir).listSync().whereType<File>().where((f) => f.path.endsWith('.js')), isEmpty, reason: 'Node 的生成文件都清掉了');

    // 换到 PHP：2026-11-26 起它也真跑过了，菜单里不再标“（未实测）”（原来断言有）。
    await more(tester, 'language');
    await tapKey(tester, 'be-lang-php');
    await flushed(tester);
    await until(tester, () => at('server.php').existsSync() && !at('server.py').existsSync(), '换成 PHP 的文件');
    await tester.tap(k('be-more'));
    await tester.pumpAndSettle();
    expect(find.textContaining('（未实测）'), findsNothing);
    expect(find.textContaining('语言：PHP'), findsOneWidget);
    await tester.tapAt(const Offset(10, 400));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('手改过生成的文件：不覆盖，提示可点开，列出文件；选“覆盖”才盖掉', (tester) async {
    await boot(tester, ProjectTemplate.backendBlocks, language: 'node');
    await tester.runAsync(() async => at('server.js').writeAsStringSync('${text('server.js')}\n// 我自己加的一行\n'));
    await paletteTab(tester, 'event');
    await tapKey(tester, 'bk-palette-item-hat-DELETE');
    final id = doc(tester).routes.last.id;
    await flushed(tester);
    await until(tester, () => saved().route(id) != null, '模型存下去');
    await until(tester, () => k('be-conflict-snack').evaluate().isNotEmpty, '出现“没有覆盖”的提示');
    expect(find.text('有 1 个文件你手改过，没有覆盖。'), findsOneWidget);
    expect(find.text('1 个文件没覆盖'), findsOneWidget, reason: '副标题也说');
    expect(text('server.js'), contains('我自己加的一行'));
    expect(text('server.js'), isNot(contains('/new')), reason: '没有覆盖');
    await shot(tester, 'be-conflict-light');

    await tester.pumpAndSettle();
    await tester.tap(find.text('查看'));
    await tester.pumpAndSettle();
    expect(k('be-regen-conflict-server.js'), findsOneWidget);
    await shot(tester, 'be-regen-light');
    await tapKey(tester, 'be-regen-overwrite');
    await until(tester, () => !text('server.js').contains('我自己加的一行'), '覆盖');
    expect(text('server.js'), contains('/new'));
    await settle(tester, rounds: 3);
    expect(find.text('1 个文件没覆盖'), findsNothing);
    expect(find.text('Node.js · 8 个接口'), findsOneWidget);

    // 没有冲突时“代码生成情况”也点得开，不会让人覆盖什么。
    await more(tester, 'regen');
    expect(k('be-regen-overwrite'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('变量与集合面板：新建、改名（用到的积木跟着改）、删除前说有几处在用；服务设置改端口', (tester) async {
    await boot(tester, ProjectTemplate.backendBlocks, language: 'node');
    await more(tester, 'data');
    expect(k('be-col-row-todos'), findsOneWidget);
    expect(k('be-var-row-todo'), findsOneWidget);
    await shot(tester, 'be-data-light');

    final uses = doc(tester).collectionRefCount('todos');
    expect(uses, greaterThan(3));
    await tapKey(tester, 'be-col-row-todos');
    expect(
      find.descendant(of: find.byType(AlertDialog), matching: find.textContaining('$uses 处')),
      findsOneWidget,
      reason: '对话框里说有几处在用',
    );
    await tester.enterText(k('be-col-name'), '1坏名字');
    await tapKey(tester, 'be-col-save');
    expect(k('be-col-name'), findsOneWidget, reason: '名字不合规矩：不关，就地说');
    await tester.enterText(k('be-col-name'), 'tasks');
    await tapKey(tester, 'be-col-save');
    expect([for (final c in doc(tester).collections) c.name], ['tasks']);
    expect(doc(tester).collectionRefCount('tasks'), uses, reason: '用到它的积木全跟着改了');
    expect(doc(tester).collectionRefCount('todos'), 0);
    expect(k('be-col-row-tasks'), findsOneWidget);

    final varUses = doc(tester).variableRefCount('todo');
    await tapKey(tester, 'be-var-row-todo');
    await tester.enterText(k('lc-var-name'), 'item');
    await tap(tester, find.widgetWithText(TextButton, '保存'));
    expect([for (final v in doc(tester).variables) v.name], ['item']);
    expect(doc(tester).variableRefCount('item'), varUses);

    await tapKey(tester, 'be-col-add');
    await tester.enterText(k('be-col-name'), 'users');
    await tapKey(tester, 'be-col-save');
    expect([for (final c in doc(tester).collections) c.name], ['tasks', 'users']);

    // 删正在用的集合：先问，取消就不删。
    await tapKey(tester, 'be-col-row-tasks');
    await tapKey(tester, 'be-col-delete');
    expect(find.textContaining('有 $uses 处在用它'), findsOneWidget);
    await tap(tester, find.widgetWithText(TextButton, '取消'));
    expect(doc(tester).collection('tasks'), isNotNull);
    // 没人用的直接删。
    await tapKey(tester, 'be-col-row-users');
    await tapKey(tester, 'be-col-delete');
    expect(doc(tester).collection('users'), isNull);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    await more(tester, 'settings');
    await tester.enterText(k('be-set-port'), '70000');
    await tapKey(tester, 'be-set-save');
    expect(k('be-set-port'), findsOneWidget, reason: '端口不对：不关');
    await tester.enterText(k('be-set-port'), '3210');
    await tester.enterText(k('be-set-name'), '待办服务');
    await tapKey(tester, 'be-set-save');
    expect((doc(tester).port, doc(tester).name), (3210, '待办服务'));

    await flushed(tester);
    await until(tester, () => saved().port == 3210, '落盘');
    final onDisk = saved();
    expect([for (final c in onDisk.collections) c.name], ['tasks']);
    expect(onDisk.collectionRefCount('tasks'), uses);
    expect(text('server.js'), contains('tasks'));
    expect(text('server.js'), isNot(contains("'todos'")));
    expect(text('server.js'), contains('3210'));
    expect(be(tester).host!.issues.where((i) => i.isError), isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('运行：面板写清工具、命令、地址、接口与 curl；点“在终端启动”→ 切到终端页，在“后端”终端里打出那条命令；再点一次先 Ctrl+C、不多开终端', (tester) async {
    await boot(tester, ProjectTemplate.backendBlocks, language: 'node');
    final node = backendTargetFor('node')!;
    final command = node.startCommand.join(' ');
    await tester.tap(k('be-run'));
    await tester.pumpAndSettle();
    expect(find.descendant(of: k('be-run-command'), matching: find.text(command)), findsOneWidget);
    expect(find.descendant(of: k('be-run-url'), matching: find.text('http://localhost:8080')), findsOneWidget);
    expect(find.textContaining('“运行环境”'), findsWidgets, reason: 'Node 可以去运行环境一键装');
    expect(k('be-run-runtime'), findsOneWidget);
    expect(find.textContaining('Ctrl'), findsWidgets);
    await shot(tester, 'be-run-light');
    final hello = routeOf(tester, 'GET', '/hello');
    await tester.scrollUntilVisible(
      k('be-run-curl-${hello.id}'),
      120,
      scrollable: find.descendant(of: find.byType(BottomSheet), matching: find.byType(Scrollable)).first,
    );
    expect(find.descendant(of: k('be-run-curl-${hello.id}'), matching: find.textContaining('curl')), findsOneWidget);
    expect(find.descendant(of: k('be-run-curl-${hello.id}'), matching: find.textContaining('localhost:8080/hello')), findsOneWidget);
    final before = session.terminals.length;
    expect(ptys.where((x) => typed(x).contains(command)), isEmpty, reason: '只是看面板：不执行任何东西');

    await tapKey(tester, 'be-run-start');
    await settle(tester, rounds: 6);
    expect(find.byType(TerminalTab).hitTestable(), findsOneWidget, reason: '切到了终端页');
    expect(session.terminals.length, before + 1, reason: '新开了一个专门跑后端的终端');
    expect(session.terminals.last.title, kBackendTerminalTitle);
    expect(session.activeTerminal, session.terminals.length - 1, reason: '当前就是它');
    await until(tester, () => ptys.any((x) => typed(x).contains(command)), '命令打进终端');
    final pty = ptys.firstWhere((x) => typed(x).contains(command));
    expect(typed(pty), '$command\r');

    await tapNav(tester, ShellDest.builder);
    await tester.tap(k('be-run'));
    await tester.pumpAndSettle();
    await tapKey(tester, 'be-run-start');
    await settle(tester, rounds: 6);
    await until(tester, () => typed(pty) == '$command\r\x03$command\r', '第二次：先 Ctrl+C 再启动');
    expect(session.terminals.length, before + 1, reason: '复用同一个“后端”终端');
    expect(tester.takeException(), isNull);
  });

  // 2026-11-26 改：命令前面多了 `env PHP_CLI_SERVER_WORKERS=4`；PHP 真跑过了，面板不再说“没实际运行过”（原来断言有这句）。
  testWidgets('PHP：端口写在命令里，用的是文档里的端口；工具没装会自动装', (tester) async {
    await boot(tester, ProjectTemplate.backendBlocks, language: 'php');
    final host = be(tester).host!;
    host.edit(() => host.doc.port = 3210);
    await tester.pump();
    await tester.tap(k('be-run'));
    await tester.pumpAndSettle();
    expect(find.descendant(of: k('be-run-command'), matching: find.text('env PHP_CLI_SERVER_WORKERS=4 php -S 0.0.0.0:3210 server.php')), findsOneWidget);
    expect(find.textContaining('还没有实际运行过'), findsNothing);
    expect(find.textContaining('会先自动装好 PHP 8.3 再启动'), findsOneWidget, reason: '真机反馈第三轮：不用她自己装了');
    expect(find.textContaining('自己在终端里装'), findsNothing);
    expect(k('be-run-runtime'), findsOneWidget, reason: '运行环境里现在有 PHP 的一键安装');
    await shot(tester, 'be-run-php-light');
    await tapKey(tester, 'be-run-start');
    await settle(tester, rounds: 6);
    await until(tester, () => ptys.any((x) => typed(x).isNotEmpty), '命令打进终端');
    expect([for (final x in ptys) typed(x)].where((t) => t.isNotEmpty), ['env PHP_CLI_SERVER_WORKERS=4 php -S 0.0.0.0:3210 server.php\r']);
    expect(saved().port, 3210, reason: '启动前先把没存的改动存下去');
    expect(text('README.md'), contains('0.0.0.0:3210'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('全栈项目：后端在 server/ 里；加了页面以后顶上出现“页面 / 后端”切换，两边互不打扰；启动命令先进 server 目录', (tester) async {
    await boot(tester, ProjectTemplate.fullstack, language: 'python');
    // 全栈模板的网页是手写的 web/，没有 page.lc.json：一开始只有后端可搭。
    expect(at('server/$kBackendFileName').existsSync(), isTrue);
    expect(find.byType(BackendScreen), findsOneWidget);
    expect(k('hub-switch'), findsNothing);
    expect(find.text('Python · 7 个接口'), findsOneWidget);

    await tester.runAsync(() async => at(kLowcodePageFile).writeAsStringSync(LcDocument.starter('首页').encode()));
    session.filesChanged();
    await until(tester, () => k('hub-switch').evaluate().isNotEmpty, '出现切换');
    await settle(tester, rounds: 6);
    expect(find.byType(BuilderScreen), findsOneWidget, reason: '默认先看页面');
    expect(find.byTooltip('图层').hitTestable(), findsOneWidget);
    await shot(tester, 'be-fullstack-page-light');

    await tester.tap(find.descendant(of: k('hub-switch'), matching: find.text('后端')));
    await settle(tester, rounds: 6);
    expect(find.byType(BackendScreen).hitTestable(), findsOneWidget);
    expect(find.byTooltip('图层').hitTestable(), findsNothing);
    final navTop = tester.getRect(find.byType(IconBottomNav)).top;
    expect(tester.getRect(find.byType(BackendScreen)).bottom, navTop);
    await shot(tester, 'be-fullstack-backend-light');
    final state = be(tester);
    final host = state.host!;
    host.edit(() => host.doc.port = 9090);
    await tester.pump();

    // 切到页面再切回来：后端页还是那一个（没存的改动、撤销记录都在）。
    await tester.tap(find.descendant(of: k('hub-switch'), matching: find.text('页面')));
    await settle(tester, rounds: 3);
    await tester.tap(find.descendant(of: k('hub-switch'), matching: find.text('后端')));
    await settle(tester, rounds: 3);
    expect(be(tester), same(state));
    expect(host.canUndo, isTrue);

    final python = backendTargetFor('python')!;
    await tester.tap(k('be-run'));
    await tester.pumpAndSettle();
    final command = '(cd server && ${python.startCommand.join(' ')})';
    expect(find.descendant(of: k('be-run-command'), matching: find.text(command)), findsOneWidget);
    await tapKey(tester, 'be-run-start');
    await settle(tester, rounds: 6);
    await until(tester, () => ptys.any((x) => typed(x).isNotEmpty), '命令打进终端');
    expect([for (final x in ptys) typed(x)].where((t) => t.isNotEmpty), ['$command\r']);
    expect(saved('server/$kBackendFileName').port, 9090);
    expect(at('server/server.py').existsSync(), isTrue);
    expect(at('server.py').existsSync(), isFalse, reason: '生成在 server/ 里，不在根目录');

    // 从终端回到搭建页：还停在“后端”这一边。
    await tapNav(tester, ShellDest.builder);
    expect(find.byType(BackendScreen).hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('什么都没有的项目：空状态里可以“新建后端积木”→ 根目录建好样本和代码，直接进后端积木页', (tester) async {
    await boot(tester, ProjectTemplate.empty);
    expect(k('hub-empty'), findsOneWidget);
    expect(find.text('新建页面'), findsOneWidget);
    await shot(tester, 'be-hub-empty-light');
    await tapKey(tester, 'hub-new-backend');
    await until(tester, () => find.byType(BackendScreen).evaluate().isNotEmpty && k('bk-canvas').evaluate().isNotEmpty, '进后端积木页');
    expect(at(kBackendFileName).existsSync(), isTrue);
    final t = backendTargetFor(saved().language)!;
    expect(at(t.entryFile).existsSync(), isTrue);
    expect(saved().routes.length, 7);
    expect(saved().name, '小后端');
    expect(k('hub-switch'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('什么都没有的项目：“新建页面”还是原来的低代码页面', (tester) async {
    await boot(tester, ProjectTemplate.empty);
    await tapKey(tester, 'hub-new-page');
    await until(tester, () => find.byType(BuilderScreen).evaluate().isNotEmpty, '进页面搭建');
    await settle(tester, rounds: 4);
    expect(at(kLowcodePageFile).existsSync(), isTrue);
    expect(find.byTooltip('图层'), findsOneWidget);
    expect(find.byType(BackendScreen), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('留在后台时 backend.lc.json 在别处被改了：没有未保存改动 → 重新读；有 → 以这里为准并说一声', (tester) async {
    await boot(tester, ProjectTemplate.backendBlocks, language: 'node');
    final state = be(tester);

    // 1) 人在别的页签（这一页留在后台），Agent 改了文件。
    await tapNav(tester, ShellDest.files);
    final other = saved()
      ..port = 4000
      ..addRoute('GET', '/from-agent');
    await tester.runAsync(() async => at(kBackendFileName).writeAsStringSync('${other.encode()}\n'));
    session.filesChanged();
    await settle(tester, rounds: 4);
    await tapNav(tester, ShellDest.builder);
    await until(tester, () => find.byType(BackendScreen).evaluate().isNotEmpty && be(tester).host != null, '回到后端积木页');
    expect(doc(tester).port, 4000);
    expect(doc(tester).routes.any((r) => r.path == '/from-agent'), isTrue);
    expect(find.text('Node.js · 8 个接口'), findsOneWidget);

    // 2) 人就在这一页上，文件被改了：当场换成新内容，撤销记录作废（撤销不会把别人的改动撤掉）。
    final host = be(tester).host!;
    host.edit(() => host.doc.name = '改了个名');
    await tester.pump();
    await flushed(tester);
    await until(tester, () => saved().name == '改了个名', '自己的改动先落盘');
    expect(host.canUndo, isTrue);
    final again = saved()..addRoute('GET', '/second');
    await tester.runAsync(() async => at(kBackendFileName).writeAsStringSync('${again.encode()}\n'));
    session.filesChanged();
    await until(tester, () => doc(tester).routes.any((r) => r.path == '/second'), '当场读到新内容');
    expect(find.textContaining('在别处被改了，已重新读取'), findsOneWidget);
    expect(be(tester).host, same(host), reason: '宿主原地换文档，编辑器不重建');
    expect(host.canUndo, isFalse);
    expect(find.text('Node.js · 9 个接口'), findsOneWidget);
    ScaffoldMessenger.of(tester.element(find.byType(BackendScreen))).clearSnackBars();
    await tester.pumpAndSettle();

    // 3) 这里有还没保存的改动时文件被改：以这里为准，说一声，随后把这里的存下去。
    host.edit(() => host.doc.port = 5000);
    await tester.pump();
    final theirs = saved()..addRoute('GET', '/theirs');
    await tester.runAsync(() async => at(kBackendFileName).writeAsStringSync('${theirs.encode()}\n'));
    session.filesChanged();
    await until(tester, () => find.textContaining('以这里的为准').evaluate().isNotEmpty, '提示以这里为准');
    await flushed(tester);
    await until(tester, () => saved().port == 5000, '这里的改动落盘');
    expect(saved().routes.any((r) => r.path == '/theirs'), isFalse, reason: '那边的被这里的盖掉了');
    expect(doc(tester).port, 5000);

    // 自己存盘引起的“文件变了”通知不会让它重读自己（撤销记录还在）。
    expect(host.canUndo, isTrue);
    expect(state.mounted, isFalse, reason: '从别的页签回来时搭建页是重建的（和页面搭建一样）');
    expect(tester.takeException(), isNull);
  });

  testWidgets('坏的 backend.lc.json：不崩、不留备份文件，说明原因，给“去文件页修 / 重置为样本”；修好以后自己恢复', (tester) async {
    await boot(tester, ProjectTemplate.backendBlocks, language: 'node', before: () => File(p.join(project.dir, kBackendFileName)).writeAsStringSync('{ 坏的'));
    expect(find.byType(BackendScreen), findsOneWidget);
    expect(k('be-problem'), findsOneWidget);
    expect(find.text('后端积木文件打不开'), findsOneWidget);
    expect(find.textContaining('不是合法的 JSON'), findsOneWidget);
    await shot(tester, 'be-problem-light');
    expect(text(kBackendFileName), '{ 坏的', reason: '没有动它');
    expect(Directory(project.dir).listSync().where((e) => e.path.contains('.bad')), isEmpty);

    // 各种读不懂的内容：都只是换一句说明。
    for (final (bad, why) in [('', 'JSON'), ('[1, 2]', '应该是一个对象'), ('{"kind": "page"}', '不是后端积木文件'), ('null', '应该是一个对象'), ('{"routes": 5}', '')]) {
      await tester.runAsync(() async => at(kBackendFileName).writeAsStringSync(bad));
      session.filesChanged();
      await settle(tester, rounds: 4);
      expect(tester.takeException(), isNull, reason: bad);
      if (why.isNotEmpty) {
        expect(k('be-problem'), findsOneWidget, reason: bad);
        expect(find.textContaining(why), findsOneWidget, reason: bad);
      }
    }

    // 在别处修好了：自己恢复成画布。
    final good = backendStarterDocument0();
    await tester.runAsync(() async => at(kBackendFileName).writeAsStringSync('${good.encode()}\n'));
    session.filesChanged();
    await until(tester, () => k('bk-canvas').evaluate().isNotEmpty && doc(tester).name == '修好了', '修好后恢复');
    expect(doc(tester).routes.length, 1);

    // 又坏了 → 去文件页修。
    await tester.runAsync(() async => at(kBackendFileName).writeAsStringSync('{ 又坏了'));
    session.filesChanged();
    await until(tester, () => k('be-problem').evaluate().isNotEmpty, '又坏了');
    await tapKey(tester, 'be-go-files');
    await settle(tester, rounds: 4);
    expect(find.text(kBackendFileName).hitTestable(), findsWidgets, reason: '到了文件页');

    // 回来 → 重置为样本（先确认）。
    await tapNav(tester, ShellDest.builder);
    await until(tester, () => k('be-reset').evaluate().isNotEmpty, '还是打不开');
    await tapKey(tester, 'be-reset');
    expect(find.text('重置为样本？'), findsOneWidget);
    await tap(tester, find.widgetWithText(TextButton, '重置'));
    await until(tester, () => k('bk-canvas').evaluate().isNotEmpty, '重置后是画布');
    await flushed(tester);
    await until(tester, () => text(kBackendFileName).contains('/todos'), '样本落盘');
    expect(saved().routes.length, 7);
    expect(tester.takeException(), isNull);
  });

  testWidgets('文件页：打开 backend.lc.json，编辑器菜单里有“用积木打开”→ 单独打开后端积木页；别的文件没有这一项', (tester) async {
    await boot(tester, ProjectTemplate.backendBlocks, language: 'node', initial: ShellDest.files);
    await tap(tester, find.text(kBackendFileName));
    await settle(tester, rounds: 4);
    await tester.tap(find.byTooltip('编辑器菜单'));
    await tester.pumpAndSettle();
    await tester.tap(k('editor-open-blocks'));
    await settle(tester, rounds: 6);
    expect(find.byType(BackendScreen), findsOneWidget);
    expect(k('bk-canvas'), findsOneWidget);
    expect(find.text('Node.js · 7 个接口'), findsOneWidget);

    // 从这里启动：先关掉这一页，再切到终端页。
    await tester.tap(k('be-run'));
    await tester.pumpAndSettle();
    await tapKey(tester, 'be-run-start');
    await settle(tester, rounds: 6);
    expect(find.byType(BackendScreen), findsNothing);
    expect(find.byType(TerminalTab).hitTestable(), findsOneWidget);
    await until(tester, () => ptys.any((x) => typed(x).isNotEmpty), '命令打进终端');
    expect([for (final x in ptys) typed(x)].where((t) => t.isNotEmpty), ['${backendTargetFor('node')!.startCommand.join(' ')}\r']);

    expect(isBackendBlocksFile('README.md'), isFalse);
    expect(isBackendBlocksFile('server/backend.lc.json'), isTrue);
    expect(isBackendBlocksFile(r'server\backend.lc.json'), isTrue);
    expect(isBackendBlocksFile('my-backend.lc.json'), isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('深色冒烟：后端积木页、更多菜单、语言、变量与集合、运行面板、全栈切换、空状态', (tester) async {
    await boot(tester, ProjectTemplate.fullstack, language: 'go', mode: ThemeMode.dark, before: () => File(p.join(project.dir, kLowcodePageFile)).writeAsStringSync(LcDocument.starter('首页').encode()));
    expect(k('hub-switch'), findsOneWidget);
    await tester.tap(find.descendant(of: k('hub-switch'), matching: find.text('后端')));
    await settle(tester, rounds: 6);
    expect(find.text('Go · 7 个接口'), findsOneWidget);
    await shot(tester, 'be-fullstack-backend-dark');

    await tester.tap(k('be-more'));
    await tester.pumpAndSettle();
    await shot(tester, 'be-more-dark');
    await tester.tap(k('be-menu-language'));
    await tester.pumpAndSettle();
    await shot(tester, 'be-language-dark');
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await more(tester, 'data');
    await shot(tester, 'be-data-dark');
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.tap(k('be-run'));
    await tester.pumpAndSettle();
    expect(find.textContaining('会先自动装好 Go 1.26.11（下载约 61 MB，装好后占约 240 MB）再启动'), findsOneWidget, reason: '真机反馈第三轮：Go 不用自己装了');
    expect(find.textContaining('自己在终端里装'), findsNothing);
    await shot(tester, 'be-run-dark');
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('深色冒烟：只有后端的项目整页；什么都没有的空状态', (tester) async {
    await boot(tester, ProjectTemplate.backendBlocks, language: 'node', mode: ThemeMode.dark);
    await shot(tester, 'be-screen-dark');
    final get = routeOf(tester, 'GET', '/todos/:id');
    ed(tester).jumpTo(get.id, const []);
    await tester.pumpAndSettle();
    await shot(tester, 'be-route-dark');
    expect(tester.takeException(), isNull);
  });

  testWidgets('浅色：帽子“当收到 GET /todos/:id”近看；各类积木的积木盒', (tester) async {
    await boot(tester, ProjectTemplate.backendBlocks, language: 'node');
    final get = routeOf(tester, 'GET', '/todos/:id');
    ed(tester).jumpTo(get.id, const []);
    await tester.pumpAndSettle();
    await shot(tester, 'be-route-light');
    for (final c in ['返回', '数据', '请求', '流程', '对象']) {
      await paletteTab(tester, c);
      await shot(tester, 'be-palette-$c-light');
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('深色：什么都没有的空状态', (tester) async {
    await boot(tester, ProjectTemplate.empty, mode: ThemeMode.dark);
    expect(k('hub-empty'), findsOneWidget);
    await shot(tester, 'be-hub-empty-dark');
    expect(tester.takeException(), isNull);
  });

  testWidgets('积木盒面板在后端积木页一样能上下拖：收到只剩手柄条、顶到页面顶；撤销 / 重做 / 缩放在手柄条上；切到别的页再回来高度还在', (tester) async {
    addTearDown(BkDockMemory.clear);
    await boot(tester, ProjectTemplate.backendBlocks, language: 'node');
    Rect dock() => tester.getRect(k('bk-dock'));
    // 把样本接口挪出视野，在空地方搭。
    ed(tester).setPan(const Offset(0, -4000));
    await tester.pumpAndSettle();
    final page = tester.getRect(find.byType(BlockEditorView));
    expect(dock().height, 248);
    expect(dock().bottom, page.bottom);
    // 撤销 / 重做 / 缩放都在手柄条里，画布上没有浮条。
    final handle = tester.getRect(k('bk-palette-handle'));
    for (final key in ['bk-undo', 'bk-redo', 'bk-zoom']) {
      final r = tester.getRect(k(key));
      expect(handle.contains(r.center), isTrue, reason: key);
      expect(r.width, greaterThanOrEqualTo(44), reason: key);
      expect(r.height, greaterThanOrEqualTo(44), reason: key);
    }
    // 手柄条左边不空着：“积木盒”名字在把手左边，把手在页面正中。
    final grip = tester.getRect(k('bk-palette-grip'));
    expect(grip.center.dx, page.center.dx);
    final title = tester.getRect(k('bk-dock-title'));
    expect(handle.contains(title.center), isTrue);
    expect(title.right, lessThan(grip.left));
    expect(title.height, greaterThanOrEqualTo(44));
    expect(find.descendant(of: k('bk-dock-title'), matching: find.text('积木盒')), findsOneWidget);

    Future<void> pull(double dy) async {
      final g = await tester.startGesture(tester.getCenter(k('bk-palette-grip')));
      for (var i = 0; i < 8; i++) {
        await g.moveBy(Offset(0, dy / 8));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await g.up();
      await tester.pumpAndSettle();
    }

    // 往上：顶到页面顶（盖住顶栏），底部导航不受影响。
    await pull(-1500);
    expect(dock().top, page.top);
    expect(k('be-run').hitTestable(), findsNothing);
    expect(k('nav-0').hitTestable(), findsOneWidget);
    // 全展开时拿一块积木：面板让开，照样放到画布上。
    final before = doc(tester).routes.length;
    final (g, from) = await liftFromPalette(tester, 'event', 'hat-POST');
    await tester.pump(const Duration(milliseconds: 400));
    expect(dock().height, 248);
    await glideAndDrop(tester, g, from, () => tester.getTopLeft(k('bk-canvas')) + const Offset(200, 330));
    expect(doc(tester).routes.length, before + 1);

    // 往下：只剩手柄条；撤销还能点。
    await pull(1500);
    expect(dock().height, 44);
    expect(dock().bottom, page.bottom);
    await tapKey(tester, 'bk-undo');
    expect(doc(tester).routes.length, before);
    expect(dock().height, 44);

    // 切到别的页再回来：还是收起的。
    await tapNav(tester, ShellDest.files);
    await tapNav(tester, ShellDest.builder);
    expect(dock().height, 44);
    await flushed(tester);
    expect(tester.takeException(), isNull);
  });
}

/// 只有一个接口的最小文档（“在别处修好了”用）。
BeDocument backendStarterDocument0() => BeDocument(name: '修好了')..addRoute('GET', '/ok');
