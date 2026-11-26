// 积木第 4 版·第 1 阶段：在真的后端积木页里用新积木（390×844，浅色 + 深色）。
//   LOPI_SHOTS=1 flutter test --no-pub test/backend_lang_ui_test.dart   # 同时把截图写到 docs/screenshots/be4-*.png
//
// 整个应用外壳真的搭起来（同 backend_screen_test.dart）：从积木盒的“常用”页、分类页、搜索结果里把新积木拖进接口，
// 给多口的“如果”加段删段、往槽里放值、看到校验标记、看代码；存盘和生成的代码都是真实文件。
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/backend/backend_model.dart';
import 'package:lopicode/backend/backend_targets.dart';
import 'package:lopicode/blocks/block_dock.dart';
import 'package:lopicode/blocks/block_geometry.dart';
import 'package:lopicode/blocks/block_palette_model.dart';
import 'package:lopicode/core/templates.dart';
import 'package:lopicode/lang/rules.dart';
import 'package:lopicode/lowcode/logic_model.dart';
import 'package:material_ui/material_ui.dart';

import 'backend_screen_test.dart' show at, be, boot, doc, ed, flushed, glideAndDrop, k, liftFromPalette, paletteTab, saved, text, until;
import 'screens_test.dart' show fontsLoaded, shot;
import 'support/backend_lang_blocks.dart' hide text;
import 'support/harness.dart';

/// 把手上拿着的语句放进某个口的某个位置。
Future<void> dropStatement(WidgetTester tester, TestGesture g, Offset from, String id, LcBlockPath parent, int index, {int arm = -1}) => glideAndDrop(tester, g, from, () {
  final s = ed(tester);
  final placed = s.drag!.base.placed(id)!;
  final snap = placed.layout.snaps.firstWhere((x) => x.kind == BkSnapKind.statement && bkSameBlockPath(x.parent, parent) && x.arm == arm && !x.inElse && x.index == index);
  return s.globalOf(s.toView(placed.origin + snap.anchor + s.grabOffset));
});

/// 把手上拿着的值放进某块积木的某个槽。
Future<void> dropValue(WidgetTester tester, TestGesture g, Offset from, String id, LcBlockPath block, String arg) => glideAndDrop(tester, g, from, () {
  final s = ed(tester);
  final placed = s.drag!.base.placed(id)!;
  final snap = placed.layout.snaps.firstWhere((x) => x.kind == BkSnapKind.expr && x.arg == arg && x.exprPath.isEmpty && bkSameBlockPath(x.parent, block));
  return s.globalOf(s.toView(placed.origin + snap.rect.topLeft + s.grabOffset + const Offset(2, 0)));
});

/// 屏幕上：某块多口积木上的小按钮。
Offset control(WidgetTester tester, String id, LcBlockPath path, BkControlKind kind, {int arm = -1}) {
  final s = ed(tester);
  final placed = s.layout.placed(id)!;
  final c = placed.layout.blockAt(path)!.controls.firstWhere((c) => c.kind == kind && c.arm == arm);
  return s.globalOf(s.toView(placed.origin + c.rect.center));
}

/// 搜索结果里按住一样东西拿出来。
Future<(TestGesture, Offset)> liftFromSearch(WidgetTester tester, String word, String itemKey) async {
  await tester.tap(k('bk-palette-search'));
  await tester.pumpAndSettle();
  await tester.enterText(k('bk-palette-search-field'), word);
  await tester.pumpAndSettle();
  final item = k('bk-palette-item-$itemKey');
  expect(item, findsOneWidget, reason: '搜“$word”要能搜到 $itemKey');
  await tester.ensureVisible(item);
  await tester.pumpAndSettle();
  final from = tester.getTopLeft(item) + const Offset(10, 20);
  final g = await tester.startGesture(from);
  await tester.pump(const Duration(milliseconds: 220));
  expect(ed(tester).drag, isNotNull, reason: '按住应该就拿出来了');
  return (g, from);
}

List<String> rules(WidgetTester tester) => [for (final i in be(tester).host!.issues) i.rule];

/// 截图用的一个接口：否则如果链 + 循环 + 列表字典操作。
J showcaseRoute() {
  final score = ex('index', {'of': vr('scores'), 'key': vr('i')});
  J mark(String word) => blk('dictSet', {'d': vr('result'), 'k': vr('i'), 'v': tx(word)});
  return route('show', 'GET', '/score', [
    let('scores', ls([nm(92), nm(71), nm(48)])),
    push('scores', nm(100)),
    let('result', dc({})),
    blk(
      'forCount',
      {'name': 'i', 'from': nm(0), 'to': nm(3), 'step': nm(1)},
      [
        iff(
          op2('>=', score, nm(90)),
          [mark('优秀')],
          arms: [
            arm({'cond': op2('>=', score, nm(60))}, [mark('及格')]),
          ],
          orElse: [blk('continue')],
        ),
      ],
    ),
    json(vr('result')),
  ]);
}

void main() {
  // 这个文件考的是老规矩（规矩版本 1）的行为：新建的文档现在默认是严格规矩，这里钉回 1，测完改回去。
  setUp(() => beNewDocRules = kLangRulesLoose);
  tearDown(() => beNewDocRules = kLangRulesForNewDocs);

  setUpAll(() async => fontsLoaded = await loadRealFonts());
  tearDown(BkDockMemory.clear);

  testWidgets('从“常用”页、分类页、搜索结果把新积木拖进接口；给“如果”加一段、往段的槽里放值、删掉这一段；存盘是版本 2，代码跟上，看代码看得到', (tester) async {
    await boot(tester, ProjectTemplate.backendBlocks, language: 'node');
    final s = ed(tester);
    s.setPan(const Offset(0, -4000));
    await tester.pumpAndSettle();
    final canvas = tester.getTopLeft(k('bk-canvas'));
    var (g, from) = await liftFromPalette(tester, 'event', 'hat-GET');
    await glideAndDrop(tester, g, from, () => canvas + const Offset(40, 100));
    final id = doc(tester).routes.last.id;
    List<LcBlock> body() => doc(tester).route(id)!.body;

    // 帽子上的字和槽要画出来（“当收到 GET /new”）：画的时候只画“头上的”那几个，帽子也得算进去。
    // 多口积木合进来以后帽子曾经是空白一块（字和槽都排了版，但没算成头上的）。
    final hat = ed(tester).layout.placed(id)!.layout.hat!;
    expect((hat.labels.length, hat.slots.length), (1, 2));
    expect((hat.headLabels, hat.headSlots), (1, 2));

    // “常用”页：样本里用过“如果”，在这一页拿得到。拖出来的是多口的（底下有“＋”）。
    (g, from) = await liftFromPalette(tester, bkCommonCategoryId, 'block-if');
    await dropStatement(tester, g, from, id, const [], 0);
    expect([for (final b in body()) b.op], ['if']);
    expect(body().single.arms, isEmpty);

    // 分类页“流程”：当…时重复 → 放进“如果”的第一个口。
    (g, from) = await liftFromPalette(tester, '流程', 'block-while');
    await dropStatement(tester, g, from, id, [lcStep(0)], 0);
    expect([for (final b in body().single.body) b.op], ['while']);

    // 搜索“循环”（别名）：搜得到“跳出循环”，拖进 while 里。
    (g, from) = await liftFromSearch(tester, '循环', 'block-break');
    await dropStatement(tester, g, from, id, [lcStep(0), lcStep(0)], 0);
    expect([for (final b in body().single.body.single.body) b.op], ['break']);
    await tester.tap(k('bk-palette-search-close'));
    await tester.pumpAndSettle();

    // 点“＋”：加一段“否则如果”（“否则”已经在了，不弹菜单）。
    await tester.tapAt(control(tester, id, [lcStep(0)], BkControlKind.add));
    await tester.pumpAndSettle();
    expect(body().single.arms, hasLength(1));
    expect(body().single.arms.single.body, isEmpty);

    // 往这一段的条件槽里放“并且 / 或者”（分类页“运算”）。
    (g, from) = await liftFromPalette(tester, '运算', 'expr-logic');
    await dropValue(tester, g, from, id, [lcStep(0)], lcArmArg(0, 'cond'));
    expect((body().single.arms.single.args['cond'] as Map)['e'], 'logic');

    // 存盘：用到新积木，文件升到版本 2；代码里有 while / break / else if。
    await flushed(tester);
    await until(tester, () => text('server.js').contains('else if'), '新积木进了代码');
    expect((jsonDecode(text(kBackendFileName)) as Map)['version'], 2);
    expect(saved().route(id)!.body.single.arms, hasLength(1));
    expect(text('server.js'), contains('while ('));
    expect(text('server.js'), contains('break;'));
    expect(at('lc_lang.js').existsSync(), isTrue, reason: '语言核心的小库跟着生成');

    // 看代码：面板里就是刚生成的这一份。
    await tester.tap(k('bk-code'));
    await tester.pumpAndSettle();
    expect(be(tester).host!.codeText, text('server.js'));
    expect(be(tester).host!.codeText, contains('else if'));
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    // 删掉这一段（里面是空的：直接删）。
    await tester.tapAt(control(tester, id, [lcStep(0)], BkControlKind.removeArm, arm: 0));
    await tester.pumpAndSettle();
    expect(body().single.arms, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('校验标记：“跳出循环”放在循环外面 → 积木上有标记、问题数是红的、代码不更新；挪进循环里就好了，自动重新生成', (tester) async {
    await boot(tester, ProjectTemplate.backendBlocks, language: 'node');
    ed(tester).setPan(const Offset(0, -4000));
    await tester.pumpAndSettle();
    final canvas = tester.getTopLeft(k('bk-canvas'));
    var (g, from) = await liftFromPalette(tester, 'event', 'hat-GET');
    await glideAndDrop(tester, g, from, () => canvas + const Offset(40, 100));
    final id = doc(tester).routes.last.id;
    (g, from) = await liftFromPalette(tester, '流程', 'block-forever');
    await dropStatement(tester, g, from, id, const [], 0);
    await flushed(tester);
    final before = text('server.js');
    expect(rules(tester), contains('L13'), reason: '一直重复里没有出口：警告');
    expect(before, contains('while (true)'), reason: '警告不拦生成');

    (g, from) = await liftFromPalette(tester, '流程', 'block-break');
    await dropStatement(tester, g, from, id, const [], 1);
    expect([for (final b in doc(tester).route(id)!.body) b.op], ['forever', 'break']);
    await tester.pump();
    await flushed(tester);
    expect(rules(tester), contains('L04'));
    final issue = be(tester).host!.issues.firstWhere((i) => i.rule == 'L04');
    expect((issue.scriptId, issue.path.single.index, issue.isError), (id, 1, true));
    expect(issue.problem, contains('循环里面'));
    expect(issue.fix, isNotEmpty);
    await until(tester, () => find.text('1 个错误，没更新').evaluate().isNotEmpty, '副标题说代码没有更新');
    expect(find.descendant(of: k('bk-issues'), matching: find.byType(Badge)), findsOneWidget);
    expect(text('server.js'), before, reason: '有错误不生成新代码');
    expect(text(kBackendFileName), contains('"break"'), reason: '有错误也保存模型');

    // 把它拖进“一直重复”里：错误和警告都没了，代码更新。
    final sEd = ed(tester);
    final placed = sEd.layout.placed(id)!;
    final grip = sEd.globalOf(sEd.toView(placed.origin + placed.layout.blockAt([lcStep(1)])!.head.centerLeft + const Offset(7, 0)));
    g = await tester.startGesture(grip);
    await tester.pump(const Duration(milliseconds: 300));
    expect(sEd.drag, isNotNull, reason: '长按应该已经拿起来了');
    await dropStatement(tester, g, grip, id, [lcStep(0)], 0);
    expect([for (final b in doc(tester).route(id)!.body.single.body) b.op], ['break']);
    await tester.pump();
    await flushed(tester);
    expect(rules(tester), isNot(contains('L04')));
    expect(rules(tester), isNot(contains('L13')));
    await until(tester, () => text('server.js') != before, '修好以后自动重新生成');
    expect(text('server.js'), contains('break;'));
    expect(tester.takeException(), isNull);
  });

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    final suffix = mode == ThemeMode.light ? 'light' : 'dark';
    testWidgets('截图：用了新积木的一串、积木盒“流程”“列表”页、“常用”页、搜“循环”的结果（$suffix）', (tester) async {
      await boot(
        tester,
        ProjectTemplate.backendBlocks,
        language: 'node',
        mode: mode,
        before: () {
          final json = jsonDecode(text(kBackendFileName)) as Map<String, dynamic>;
          (json['routes'] as List).add(showcaseRoute());
          at(kBackendFileName).writeAsStringSync(jsonEncode(json));
        },
      );
      expect(
        [
          for (final i in be(tester).host!.issues)
            if (i.scriptId == 'show') '${i.rule} ${i.message}',
        ],
        isEmpty,
        reason: '截图用的接口本身没有问题',
      );
      // 先把积木盒收到只剩手柄，让这一串整个露出来。
      await tester.drag(k('bk-palette-grip'), const Offset(0, 300), warnIfMissed: false);
      await tester.pumpAndSettle();
      // 把这个接口的帽子放到顶栏正下方，整串尽量都露出来。
      final s = ed(tester);
      final origin = s.layout.placed('show')!.origin;
      s.jumpTo('show', const []);
      // 缩小一档、帽子贴着顶栏下沿：否则如果链 + 循环 + 列表字典操作一屏看全。
      s.setZoom(0.8, Offset.zero);
      s.setPan(Offset(16 - origin.dx * s.zoom, 12 - origin.dy * s.zoom));
      // ignore: invalid_use_of_protected_member 截图前摆好画布位置，只为重画一下
      s.setState(() {});
      await tester.pumpAndSettle();
      await shot(tester, 'be4-chain-$suffix');
      await tester.drag(k('bk-palette-grip'), const Offset(0, -420), warnIfMissed: false);
      await tester.pumpAndSettle();
      await paletteTab(tester, bkCommonCategoryId);
      await shot(tester, 'be4-common-$suffix');
      for (final c in ['流程', '列表']) {
        await paletteTab(tester, c);
        await shot(tester, 'be4-palette-$c-$suffix');
      }
      await tester.tap(k('bk-palette-search'));
      await tester.pumpAndSettle();
      await tester.enterText(k('bk-palette-search-field'), '循环');
      await tester.pumpAndSettle();
      expect(k('bk-palette-item-block-while'), findsOneWidget);
      await shot(tester, 'be4-search-$suffix');
      expect(tester.takeException(), isNull);
    });
  }
}
