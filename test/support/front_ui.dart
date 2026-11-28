// 新的页面逻辑页逐步点击的测试共用：开搭建页 → “更多 › 积木逻辑”；在积木编辑器里按住、拖、放、点下拉；
// 存盘以后把这份页面导出成三种网页真编译、在 jsdom 里真跑一串步骤。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/backend/backend_block_host.dart';
import 'package:lopicode/blocks/block_editor_view.dart';
import 'package:lopicode/blocks/block_geometry.dart';
import 'package:lopicode/core/safe_file.dart';
import 'package:lopicode/core/templates.dart';
import 'package:lopicode/lowcode/builder_screen.dart';
import 'package:lopicode/lowcode/front_store.dart';
import 'package:lopicode/lowcode/logic_model.dart';
import 'package:lopicode/lowcode/model.dart';
import 'package:lopicode/project_session.dart';
import 'package:material_ui/material_ui.dart';

import 'dev_tools.dart';
import 'harness.dart';
import 'lowcode_builder.dart';
import 'page_front_check.dart';

Finder fk(String key) => find.byKey(ValueKey(key));

/// 建一个低代码项目、把 [doc] 写成页面文件、打开搭建页（390×844），再点“更多 › 积木逻辑”。
Future<ProjectSession> fuOpen(WidgetTester tester, LcDocument doc, {ThemeMode mode = ThemeMode.light, Future<void> Function(ProjectSession session)? before}) async {
  usePhoneViewport(tester);
  late TestEnv env;
  late ProjectSession session;
  await tester.runAsync(() async {
    env = await TestEnv.create();
    final project = await env.services.projects.create('我的小站', ProjectTemplate.lowcode);
    session = ProjectSession(env.services, project);
    File(session.guard.resolve(kLowcodePageFile)).writeAsStringSync(doc.encode());
    await before?.call(session);
  });
  addTearDown(() async {
    await pendingWrites();
    session.dispose();
    await env.dispose();
  });
  await tester.pumpWidget(
    appFor(
      env,
      BuilderScreen(key: UniqueKey(), session: session),
      mode: mode,
      font: lbFontsLoaded ? kTestFont : null,
    ),
  );
  await settle(tester, rounds: 6);
  await tester.tap(find.byTooltip('更多').first);
  await tester.pumpAndSettle();
  await tester.tap(find.text('积木逻辑'));
  await settle(tester, rounds: 6);
  return session;
}

/// 最上面那一页的积木编辑器（进库的画布时上面会再盖一页）。
BlockEditorViewState fuEd(WidgetTester tester) => tester.state<BlockEditorViewState>(find.byType(BlockEditorView).last);
BeBlockHost fuHost(WidgetTester tester) => fuEd(tester).widget.host as BeBlockHost;

/// 等到条件成立（真实读写一步一步推），有上限。
Future<void> fuUntil(WidgetTester tester, bool Function() done, String what) async {
  for (var i = 0; i < 1500 && !done(); i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 3)));
    await tester.pump(const Duration(milliseconds: 20));
  }
  expect(done(), isTrue, reason: '等不到：$what');
  await settle(tester, rounds: 2);
}

/// 面板是按需搭的：滚不到的那几行还不存在。把最上面那张面板滚到看得见 [key]。
Future<void> fuSee(WidgetTester tester, String key) async {
  if (fk(key).evaluate().isNotEmpty || find.byType(BottomSheet).evaluate().isEmpty) return;
  final scrollable = find.descendant(of: find.byType(BottomSheet).last, matching: find.byType(Scrollable)).first;
  try {
    await tester.scrollUntilVisible(fk(key), 120, scrollable: scrollable);
  } on StateError {
    // 往下滚到底也没有：面板长了以后，上面那几行滚出去就不在了，往回滚着找。
    await tester.scrollUntilVisible(fk(key), -120, scrollable: scrollable);
  }
  await tester.pumpAndSettle();
}

Future<void> fuTap(WidgetTester tester, String key) async {
  await fuSee(tester, key);
  expect(fk(key), findsWidgets, reason: '界面上没有 $key');
  final f = fk(key).last;
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await settle(tester, rounds: 2);
}

/// 弹出的输入框里填字、点“确定”。
Future<void> fuType(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField).last, text);
  await tester.tap(find.text('确定').last);
  await settle(tester, rounds: 2);
}

/// 顶栏“更多”里点一项（页面逻辑页是 lf-more，库的画布是 be-more）。
Future<void> fuMore(WidgetTester tester, String item, {String button = 'lf-more'}) async {
  await tester.tap(fk(button).last);
  await tester.pumpAndSettle();
  await tester.tap(fk('be-menu-$item').last);
  await settle(tester, rounds: 3);
}

/// 积木盒：切到某一页（[category] 是分类的 id）。页签条是按需搭的：没露出来的页签还不存在，一点点往左拖到它出来。
Future<void> fuTab(WidgetTester tester, String category) async {
  final tab = fk('bk-palette-tab-$category');
  final tabs = fk('bk-palette-tabs').last;
  bool shown() => tab.evaluate().isNotEmpty && tab.hitTestable().evaluate().isNotEmpty;
  await tester.drag(tabs, const Offset(1200, 0));
  await tester.pumpAndSettle();
  for (var i = 0; i < 30 && !shown(); i++) {
    await tester.drag(tabs, const Offset(-120, 0));
    await tester.pumpAndSettle();
  }
  expect(shown(), isTrue, reason: '积木盒里没有「$category」这一页');
  await tester.tap(tab.hitTestable().last);
  await tester.pumpAndSettle();
}

/// 从积木盒里按住一样东西拿出来（手势还按着）。
Future<(TestGesture, Offset)> fuLift(WidgetTester tester, String category, String itemKey) async {
  await fuTab(tester, category);
  expect(fk('bk-palette-item-$itemKey'), findsWidgets, reason: '积木盒「$category」页里没有 $itemKey');
  final item = fk('bk-palette-item-$itemKey').last;
  await tester.ensureVisible(item);
  await tester.pumpAndSettle();
  final from = tester.getTopLeft(item) + const Offset(10, 20);
  final g = await tester.startGesture(from);
  await tester.pump(const Duration(milliseconds: 220));
  expect(fuEd(tester).drag, isNotNull, reason: '按住应该就拿出来了');
  return (g, from);
}

Future<void> fuGlide(WidgetTester tester, TestGesture g, Offset from, Offset Function() to) async {
  for (var i = 1; i <= 6; i++) {
    await g.moveTo(Offset.lerp(from, to(), i / 6)!);
    await tester.pump(const Duration(milliseconds: 16));
  }
  await g.moveTo(to());
  await tester.pump(const Duration(milliseconds: 16));
  await g.up();
  await tester.pumpAndSettle();
}

/// 拖一顶帽子到画布空的地方。
Future<void> fuDropHat(WidgetTester tester, String category, String itemKey, Offset at) async {
  final (g, from) = await fuLift(tester, category, itemKey);
  final canvas = tester.getTopLeft(fk('bk-canvas').last);
  await fuGlide(tester, g, from, () => canvas + at);
}

/// 拖一块语句积木到 [id] 这一串里 [parent] 下面第 [index] 个位置。
Future<void> fuDropStmt(WidgetTester tester, String category, String itemKey, String id, LcBlockPath parent, int index, {int arm = -1}) async {
  await fuShow(tester, id);
  final (g, from) = await fuLift(tester, category, itemKey);
  await fuGlide(tester, g, from, () {
    final s = fuEd(tester);
    final placed = s.drag!.base.placed(id)!;
    final snap = placed.layout.snaps.firstWhere((x) => x.kind == BkSnapKind.statement && bkSameBlockPath(x.parent, parent) && x.arm == arm && !x.inElse && x.index == index);
    return s.globalOf(s.toView(placed.origin + snap.anchor + s.grabOffset));
  });
}

/// 拖一个值到 [id] 这一串里 [block] 那块积木的 [arg] 槽。
Future<void> fuDropValue(WidgetTester tester, String category, String itemKey, String id, LcBlockPath block, String arg, {BkExprPath via = const []}) async {
  await fuShow(tester, id);
  final (g, from) = await fuLift(tester, category, itemKey);
  await fuGlide(tester, g, from, () {
    final s = fuEd(tester);
    final placed = s.drag!.base.placed(id)!;
    final snap = placed.layout.snaps.firstWhere((x) => x.kind == BkSnapKind.expr && x.arg == arg && bkSameExprPath(x.exprPath, via) && bkSameBlockPath(x.parent, block));
    // 手上那块的“探针”（左上角往右 6、往下半个高）对准槽的正中：槽套着槽时，探针落在里面那个槽里才算放进里面那个。
    return s.globalOf(s.toView(placed.origin + snap.rect.center - Offset(6, s.drag!.probeY) + s.grabOffset));
  });
}

/// 把某一串挪到看得见的地方。
Future<void> fuShow(WidgetTester tester, String id) async {
  final s = fuEd(tester);
  final origin = s.layout.placed(id)!.origin;
  s.setPan(Offset(16 - origin.dx * s.zoom, 12 - origin.dy * s.zoom));
  // ignore: invalid_use_of_protected_member 测试里摆好画布位置，只为重画一下
  s.setState(() {});
  await tester.pumpAndSettle();
}

/// 屏幕上：帽子上的一个槽。
Offset fuHatSlot(WidgetTester tester, String id, String slotId) {
  final s = fuEd(tester);
  final placed = s.layout.placed(id)!;
  for (final (b, sl) in placed.layout.allSlots) {
    if (b.isHat && sl.hatSlotId == slotId) return s.globalOf(s.toView(placed.origin + sl.rect.center));
  }
  throw StateError('没找到帽子上的槽 $slotId');
}

/// 屏幕上：某一串里某块积木的某个参数。
Offset fuArg(WidgetTester tester, String id, LcBlockPath path, String name, {BkExprPath via = const []}) {
  final s = fuEd(tester);
  final placed = s.layout.placed(id)!;
  for (final (b, sl) in placed.layout.allSlots) {
    if (b.isHat || !bkSameBlockPath(b.path, path) || sl.arg != name || !bkSameExprPath(sl.exprPath, via)) continue;
    final e = sl.expr;
    return s.globalOf(s.toView(placed.origin + (e != null ? e.rect.centerLeft + const Offset(9, 0) : sl.rect.center)));
  }
  throw StateError('没找到参数 $name（这一串里有：${[for (final (b, sl) in placed.layout.allSlots) '${b.path}/${sl.arg}/${sl.exprPath}']}）');
}

/// 点一个槽 → 就地输入框里填 [value]。
Future<void> fuInline(WidgetTester tester, Offset at, String value) async {
  await tester.tapAt(at);
  await tester.pumpAndSettle();
  expect(fk('bk-inline-input'), findsOneWidget, reason: '点这个槽应该出就地输入框');
  await tester.enterText(fk('bk-inline-input'), value);
  await tester.testTextInput.receiveAction(TextInputAction.done);
  await tester.pumpAndSettle();
}

/// 点一个槽 → 下拉里挑 [value]。
Future<void> fuPick(WidgetTester tester, Offset at, String value) async {
  await tester.tapAt(at);
  await tester.pumpAndSettle();
  final item = fk('bk-menu-$value');
  expect(item, findsOneWidget, reason: '下拉里没有 $value');
  await tester.ensureVisible(item);
  await tester.tap(item);
  await tester.pumpAndSettle();
}

List<String> fuErrors(WidgetTester tester) => [for (final i in fuHost(tester).issues.where((i) => i.isError)) i.message];

/// 存盘的那份页面，导出成三种网页真编译（0 错 0 警告），各在 jsdom 里把 [steps] 真跑一遍。没装开发机验证环境就说明白并跳过这一步。
Future<LcDocument> fuSavedAndRun(WidgetTester tester, ProjectSession session, List<Map<String, Object?>> steps) async {
  final saved = await lbSaved(tester, session);
  expect(saved.logic.front, isNotNull, reason: '存盘里应该是新的页面逻辑');
  if (skipWithoutWebdev != false) {
    markTestSkipped('$skipWithoutWebdev');
    return saved;
  }
  await tester.runAsync(() async {
    for (final kind in kFrontKinds.keys) {
      final doc = LcDocument.parse(saved.encode());
      await lcAttachLibs(session.guard, doc);
      await frontCheckAll(kind, doc, [steps]);
    }
  });
  return saved;
}

/// 屏幕上：帽子（[owner] 不给）或某块积木上的第 [index] 个参数小块。
Offset fuChip(WidgetTester tester, String id, int index, {LcBlockPath? owner}) {
  final s = fuEd(tester);
  final placed = s.layout.placed(id)!;
  final chips = [
    for (final (b, x) in placed.layout.allSlots)
      if (x.look == BkSlotLook.param && x.param != null && (owner == null ? b.isHat : (!b.isHat && bkSameBlockPath(b.path, owner)))) x,
  ];
  return s.globalOf(s.toView(placed.origin + chips[index].rect.center));
}

/// 按住画布上 [from] 这个点的东西（参数小块、值）拿起来，放进 [id] 这一串里 [block] 那块积木的 [arg] 槽。
Future<void> fuMoveValue(WidgetTester tester, Offset from, String id, LcBlockPath block, String arg, {BkExprPath via = const []}) async {
  final g = await tester.startGesture(from);
  await tester.pump(const Duration(milliseconds: 300));
  expect(fuEd(tester).drag, isNotNull, reason: '长按应该已经拿起来了');
  await fuGlide(tester, g, from, () {
    final s = fuEd(tester);
    final placed = s.drag!.base.placed(id)!;
    final snap = placed.layout.snaps.firstWhere((x) => x.kind == BkSnapKind.expr && x.arg == arg && bkSameExprPath(x.exprPath, via) && bkSameBlockPath(x.parent, block));
    // 手上那块的“探针”（左上角往右 6、往下半个高）对准槽的正中：槽套着槽时，探针落在里面那个槽里才算放进里面那个。
    return s.globalOf(s.toView(placed.origin + snap.rect.center - Offset(6, s.drag!.probeY) + s.grabOffset));
  });
}

/// 截一张 390×844 的图，放到预览目录（不进 git；`LOPI_SHOTS=1` 才写）。
Future<void> fuShot(WidgetTester tester, String name) => lbShot(tester, '../preview/front/a3b', name);

/// 把盖在上面的面板一张张关掉，直到 [key] 这张不在了。
Future<void> fuCloseSheets(WidgetTester tester, String key) async {
  for (var i = 0; i < 6 && fk(key).evaluate().isNotEmpty; i++) {
    await tester.binding.handlePopRoute();
    await settle(tester, rounds: 2);
  }
  expect(fk(key), findsNothing, reason: '面板 $key 关不掉');
}

/// 在积木盒“我的积木”页新建一块积木：名字、一个参数。
Future<void> fuNewBlock(WidgetTester tester, String name, String param) async {
  await fuTab(tester, '@custom');
  await fuTap(tester, 'bk-palette-custom-new');
  await tester.enterText(fk('bk-look-name'), name);
  await fuTap(tester, 'bk-look-param-add');
  await tester.enterText(fk('bk-look-param-name-0'), param);
  await tester.pumpAndSettle();
  await fuTap(tester, 'bk-look-done');
}
