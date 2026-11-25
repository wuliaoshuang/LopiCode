// 积木盒第 4 版（390×844，浅色 + 深色）：两级分类（页签 + 小标题）、“常用”页（用得最多 + 加星 + 入门）、搜索（按字、按别名、
// 一块顶多块、没搜到、拖出来、键盘弹起）、颜色。宿主是测试专用的假宿主；最后两条确认真的前端宿主、后端宿主不改也照常工作。
//   LOPI_SHOTS=1 flutter test --no-pub test/blocks_palette_v4_test.dart   # 同时把截图写到 docs/screenshots/bk7-*.png
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/backend/backend_block_host.dart';
import 'package:lopicode/backend/backend_templates.dart';
import 'package:lopicode/blocks/block_canvas_view.dart';
import 'package:lopicode/blocks/block_colors.dart';
import 'package:lopicode/blocks/block_dock.dart';
import 'package:lopicode/blocks/block_geometry.dart';
import 'package:lopicode/blocks/block_host.dart';
import 'package:lopicode/blocks/block_palette_model.dart';
import 'package:lopicode/blocks/block_palette_view.dart';
import 'package:lopicode/blocks/block_stars.dart';
import 'package:lopicode/core/stores.dart';
import 'package:lopicode/lowcode/logic_block_host.dart';
import 'package:lopicode/lowcode/logic_model.dart';
import 'package:material_ui/material_ui.dart';

import 'screens_test.dart' show fontsLoaded, shot;
import 'support/blocks_fake_host.dart';
import 'support/blocks_fake_rig.dart';
import 'support/blocks_fixture.dart';
import 'support/harness.dart';

Finder k(String key) => find.byKey(ValueKey(key));

List<String> tokens(List<BlockItemRef> items) => [for (final i in items) bkItemKey(i)];

/// 一份用了不少积木的文档：say ×3、if ×1、set ×2、repeat ×1；表达式 text ×3、cmp ×2、var ×3、num ×5…
List<LcBlock> busyBody() => [
  LcBlock(op: 'set', args: {'name': '分数', 'value': fxNum(0)}),
  LcBlock(op: 'set', args: {'name': '次数', 'value': fxNum(1)}),
  fxSampleIf(),
  LcBlock(op: 'repeat', args: {'times': fxNum(3)}),
];

double contrast(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  return (la > lb ? la + 0.05 : lb + 0.05) / (la > lb ? lb + 0.05 : la + 0.05);
}

void main() {
  setUpAll(() async => fontsLoaded = await loadRealFonts());
  tearDown(BkDockMemory.clear);

  group('纯逻辑', () {
    test('一页怎么分段：不在分组里的在前（没有小标题），再一组一段；空组不要；旧式的页（没有分组）就是一段', () {
      final host = FakeHost();
      BlockCategory cat(String id) => host.categories.firstWhere((c) => c.id == id);
      final control = bkCategorySections(cat('control'));
      expect([for (final s in control) s.label], ['判断', '循环']);
      expect(tokens(control[0].items), ['block-if', 'block-switch']);
      expect(tokens(control[1].items), ['block-repeat', 'block-while', 'block-forEach', 'block-break', 'block-continue']);
      final plain = bkCategorySections(cat('variable'));
      expect(plain.single.label, isNull);
      expect(tokens(plain.single.items), ['block-set', 'block-change', 'expr-var']);
      const mixed = BlockCategory(
        id: 'm',
        label: '混',
        colorKey: BlockColorKey.list,
        blocks: ['say'],
        groups: [
          BlockGroup('空的'),
          BlockGroup('有的', exprs: ['num']),
        ],
      );
      expect([for (final s in bkCategorySections(mixed)) s.label], [null, '有的']);
      expect(mixed.isEmpty, isFalse);
      expect(const BlockCategory(id: 'e', label: '空', colorKey: BlockColorKey.list, groups: [BlockGroup('空的')]).isEmpty, isTrue);
      expect(
        const BlockCategory(
          id: 'g',
          label: '只有组',
          colorKey: BlockColorKey.list,
          groups: [
            BlockGroup('有', blocks: ['say']),
          ],
        ).isEmpty,
        isFalse,
      );
      // 分组里的积木也算这一页的颜色。
      expect(host.blockColorKey('if'), BlockColorKey.control);
      expect(host.exprColorKey('listGet'), BlockColorKey.list);
      expect(host.exprColorKey('arith'), BlockColorKey.operator);
    });

    test('用了几次：语句、表达式（含套在里面的、段参数里的）都数；帽子不数', () {
      final host = FakeHost(scripts: [FakeScript('s1', body: busyBody())]);
      final u = bkUsage(host);
      expect(u['block:say'], 3);
      expect(u['block:set'], 2);
      expect(u['block:if'], 1);
      expect(u['expr:cmp'], 3, reason: '头上一个 + 两段各一个');
      expect(u['expr:var'], 3);
      expect(u['expr:num'], 6);
      expect(u['expr:text'], 3);
      expect(u.keys.any((t) => t.startsWith('hat:')), isFalse);
    });

    test('“常用”页：用得最多的排前面（一样多按积木盒里的先后），最多 12 块；加了星的单独一段、不重复出现', () {
      final host = FakeHost(scripts: [FakeScript('s1', body: busyBody())]);
      var s = bkCommonSections(host, const []);
      expect(s.single.label, '这里用得最多');
      expect(tokens(s.single.items), ['expr-var', 'expr-cmp', 'block-say', 'block-set', 'block-if', 'block-repeat'], reason: '光杆的数字 / 文字不算：每个空槽里本来就有');
      s = bkCommonSections(host, const ['block:switch', 'expr:num', 'block:gone', 'hat:start']);
      expect([for (final x in s) x.label], ['加了星的', '这里用得最多']);
      expect(tokens(s[0].items), ['block-switch', 'expr-num', 'hat-start'], reason: '按加星的先后；积木盒里已经没有的不显示');
      expect(tokens(s[1].items).contains('expr-num'), isFalse);
      // 超过 12 种：只留 12。
      final many = FakeHost(
        scripts: [
          FakeScript('s1', body: [for (final op in fakeBlockSpecs.keys) FakeHost().newBlock(op)]),
        ],
      );
      expect(bkCommonSections(many, const []).single.items, hasLength(bkCommonMax));
    });

    test('新文档的“常用”页：宿主给的入门积木；宿主没给就每页拿第一样', () {
      final host = FakeHost();
      var s = bkCommonSections(host, const []);
      expect(s.single.label, '入门');
      expect(tokens(s.single.items), ['hat-start', 'block-say', 'block-set', 'block-if', 'block-repeat', 'expr-arith']);
      s = bkCommonSections(host, const ['block:if']);
      expect([for (final x in s) x.label], ['加了星的', '入门']);
      expect(tokens(s[1].items).contains('block-if'), isFalse);
      // 只有帽子的空串也算新文档。
      expect(bkCommonSections(FakeHost(scripts: [FakeScript('s1')]), const []).single.label, '入门');
      // 真的前端宿主没声明入门积木：每页第一样。
      final doc = sampleDoc()..logic.handlers.clear();
      final logic = LogicBlockHost(doc: doc, onEdit: (c) => c(doc));
      final first = bkCommonSections(logic, const []).single;
      expect(first.label, '入门');
      expect(first.items, hasLength(logic.categories.where((c) => !c.isEmpty).length));
      expect(first.items.first.kind, BlockPaletteKind.hat);
    });

    test('加星清单：坏的读成空的 / 丢掉坏的那几项；加、去；最多 24 颗', () {
      expect(bkCleanStars(null), isEmpty);
      expect(bkCleanStars('block:if'), isEmpty);
      expect(bkCleanStars({'a': 1}), isEmpty);
      expect(
        bkCleanStars([
          'block:if',
          3,
          null,
          'nope',
          'weird:x',
          'block:',
          ':if',
          'block:if',
          'expr:num',
          ['x'],
        ]),
        ['block:if', 'expr:num'],
      );
      expect(bkCleanStars([for (var i = 0; i < 100; i++) 'block:b$i']), hasLength(bkStarMax));
      expect(bkToggleStar(const ['block:if'], 'expr:num'), ['block:if', 'expr:num']);
      expect(bkToggleStar(const ['block:if', 'expr:num'], 'block:if'), ['expr:num']);
      expect(bkToggleStar([for (var i = 0; i < bkStarMax; i++) 'block:b$i'], 'expr:num'), isNull);
      expect(BlockItemRef.parse('expr:a:b')!.id, 'a:b');
    });

    test('搜索：按积木上的字、按别名；像的排前面；大小写和空格不管；空的词和搜不到都是空表', () {
      final host = FakeHost();
      expect(tokens(bkSearchPalette(host, '重复')), ['block-repeat', 'block-while'], reason: '“重复 … 次”开头就是，排在“当 … 时重复”前面');
      expect(tokens(bkSearchPalette(host, '循环')), ['block-repeat', 'block-while', 'block-forEach'], reason: '三块的别名');
      expect(tokens(bkSearchPalette(host, 'FOR')), ['block-repeat', 'block-forEach']);
      expect(tokens(bkSearchPalette(host, ' for each ')), ['block-forEach']);
      expect(tokens(bkSearchPalette(host, '否则')), ['block-if'], reason: '口上的字也算积木上的字');
      expect(tokens(bkSearchPalette(host, '都不是')), ['block-switch']);
      expect(tokens(bkSearchPalette(host, '出错')), ['block-try']);
      expect(tokens(bkSearchPalette(host, '错')), ['block-try', 'block-throw'], reason: '一样像的按积木盒里的先后');
      expect(tokens(bkSearchPalette(host, '开始')), ['hat-start']);
      expect(tokens(bkSearchPalette(host, '长度')), ['expr-textLen', 'expr-listLen']);
      // 积木上的字比别名靠前：“判断”是“如果”的别名。
      expect(tokens(bkSearchPalette(host, '如果')), ['block-if']);
      expect(tokens(bkSearchPalette(host, '判断')), ['block-if']);
      expect(bkSearchPalette(host, ''), isEmpty);
      expect(bkSearchPalette(host, '   '), isEmpty);
      expect(bkSearchPalette(host, '量子纠缠'), isEmpty);
      expect(bkSearchPalette(host, '{'), isEmpty, reason: '那句话里槽的记号不算字');
    });

    test('一块顶多块：整块搜到给整块；只搜到某一种，给那一种（带预设，拿出来就是它）', () {
      final host = FakeHost();
      expect(tokens(bkSearchPalette(host, '算术')), ['expr-arith']);
      expect(tokens(bkSearchPalette(host, '计算')), ['expr-arith']);
      expect(tokens(bkSearchPalette(host, '乘')), ['expr-arith~op=*']);
      expect(tokens(bkSearchPalette(host, '×')), ['expr-arith~op=*'], reason: '下拉上显示的字也能搜');
      expect(tokens(bkSearchPalette(host, '大写')), ['expr-textCase~mode=upper']);
      expect(tokens(bkSearchPalette(host, '大小写')), ['expr-textCase'], reason: '这块自己的标题里就有：给整块');
      expect(tokens(bkSearchPalette(host, 'upper')), ['expr-textCase~mode=upper']);
      expect(tokens(bkSearchPalette(host, '于')), ['expr-cmp~op===', 'expr-cmp~op=!=', 'expr-cmp~op=<', 'expr-cmp~op=>']);
      final found = bkSearchPalette(host, '乘').single;
      expect(found.preset, {'op': '*'});
      expect(found.token, 'expr:arith', reason: '加星、统计按整块算');
      // 真的前端宿主没声明变体：不崩，搜标题照常。
      final doc = sampleDoc();
      final logic = LogicBlockHost(doc: doc, onEdit: (c) => c(doc));
      expect(bkSearchPalette(logic, '如果').map((i) => i.token), contains('block:if'));
      expect(bkSearchPalette(logic, '乘'), isEmpty);
    });

    test('颜色：20 种都有浅色、深色两套；积木上的字对比度都够 4.5；假宿主相邻两页分得清', () {
      for (final dark in [false, true]) {
        final p = BkPalette.of(dark: dark);
        for (final key in BlockColorKey.all) {
          final tone = p.tone(key);
          expect(contrast(tone.text, tone.fill), greaterThanOrEqualTo(4.5), reason: '$key ${dark ? '深' : '浅'}色：字和底');
        }
        // 新加的 8 种和原来的 12 种里，没有两种颜色一模一样。
        final fills = {for (final key in BlockColorKey.all) p.tone(key).fill.toARGB32()};
        expect(fills, hasLength(BlockColorKey.all.length));
        // 积木盒里挨着的两页（设计稿 9.1 的顺序）色相至少差 25°，或者明暗差得开。
        const order = [
          BlockColorKey.variable,
          BlockColorKey.operator,
          BlockColorKey.control,
          BlockColorKey.function,
          BlockColorKey.text,
          BlockColorKey.list,
          BlockColorKey.dict,
          BlockColorKey.classes,
          BlockColorKey.error,
          BlockColorKey.async,
          BlockColorKey.custom,
        ];
        for (var i = 1; i < order.length; i++) {
          final a = HSLColor.fromColor(p.tone(order[i - 1]).fill).hue, b = HSLColor.fromColor(p.tone(order[i]).fill).hue;
          final d = (a - b).abs();
          expect(d > 180 ? 360 - d : d, greaterThanOrEqualTo(25), reason: '${order[i - 1]} 和 ${order[i]} 挨着');
        }
      }
      expect(BlockColorKey.all, hasLength(20));
    });
  });

  group('界面', () {
    testWidgets('“常用”排第一、默认就在这一页；页签后面是宿主的各页；一页里有小标题分组', (tester) async {
      final rig = FakeRig(busyBody());
      await rig.pump(tester);
      expect(k('bk-palette-page-@common'), findsOneWidget);
      expect(tester.getTopLeft(k('bk-palette-tab-@common')).dx, lessThan(tester.getTopLeft(k('bk-palette-tab-event')).dx));
      expect(tester.getTopLeft(k('bk-palette-search')).dx, 0, reason: '放大镜固定在这一行最左边');
      expect(tester.getSize(k('bk-palette-search')), const Size(44, 48));
      expect(k('bk-palette-heading-这里用得最多'), findsOneWidget);
      expect(rig.shownItems(tester).take(3), ['expr-var', 'expr-cmp', 'block-say']);

      await rig.openTab(tester, 'control');
      expect(k('bk-palette-page-control'), findsOneWidget);
      expect(k('bk-palette-heading-判断'), findsOneWidget);
      expect(k('bk-palette-heading-循环'), findsOneWidget);
      final h1 = tester.getRect(k('bk-palette-heading-判断')), h2 = tester.getRect(k('bk-palette-heading-循环'));
      final ifRect = tester.getRect(rig.item('block-if')), swRect = tester.getRect(rig.item('block-switch')), rpRect = tester.getRect(rig.item('block-repeat'));
      expect(h1.bottom, lessThanOrEqualTo(ifRect.top));
      expect(swRect.bottom, lessThan(h2.top));
      expect(h2.bottom, lessThanOrEqualTo(rpRect.top));
      // 组和组之间的空，比标题到它自己的积木的空大。
      expect(h2.top - swRect.bottom, greaterThan(rpRect.top - h2.bottom));
      expect(h1.left, 16);

      // 没分组的页没有小标题。
      await rig.openTab(tester, 'variable');
      expect(find.byWidgetPredicate((w) => w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith('bk-palette-heading-')), findsNothing);
      expect(rig.shownItems(tester), ['block-set', 'block-change', 'expr-var']);
      expect(tester.takeException(), isNull);
    });

    testWidgets('手柄条和三档高度没变：44 / 248 / 顶到头；页签那一行还是 48 高', (tester) async {
      final rig = FakeRig(busyBody());
      await rig.pump(tester);
      Rect dock() => tester.getRect(k('bk-dock'));
      expect(dock().height, 248);
      expect(tester.getSize(k('bk-palette-handle')).height, 44);
      expect(tester.getSize(k('bk-palette-tabs-grip')).height, 48);
      expect(tester.getRect(k('bk-palette-grip')).center.dx, 195);
      await tester.tap(k('bk-palette-handle'), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(dock().height, 44);
      await tester.tap(k('bk-palette-handle'), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(dock().height, 248);
      await tester.drag(k('bk-palette-grip'), const Offset(0, -700), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(dock().top, 0);
      // 顶到头时搜索照样能用。
      await tester.tap(k('bk-palette-search'));
      await tester.pumpAndSettle();
      expect(k('bk-palette-search-field'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('停在哪一页不会因为拖了画布上的积木、就地改了字而丢（原来会跳回第一页）', (tester) async {
      final rig = FakeRig(busyBody());
      await rig.pump(tester);
      await rig.openTab(tester, 'list');
      expect(k('bk-palette-page-list'), findsOneWidget);
      final from = rig.grip([lcStep(0)]);
      final g = await rig.lift(tester, from);
      expect(k('bk-trash'), findsOneWidget, reason: '拖画布上的积木时底下换成垃圾桶');
      expect(find.byType(BlockPaletteView), findsNothing);
      await rig.glide(tester, g, from, from + const Offset(40, 10));
      await rig.drop(tester, g);
      expect(k('bk-palette-page-list'), findsOneWidget, reason: '放下以后还在“列表”页');
      expect(tester.takeException(), isNull);
    });

    testWidgets('加星：按住一块不挪就松手 → 弹出“加到常用”；加了以后在“常用”页最前面；再按一次能拿掉；存进给的地方', (tester) async {
      final store = MemoryBlockStars();
      final rig = FakeRig(busyBody());
      await rig.pump(tester, stars: store);
      await rig.openTab(tester, 'error');
      final at = tester.getTopLeft(rig.item('block-try')) + const Offset(10, 20);
      var g = await tester.startGesture(at);
      await tester.pump(const Duration(milliseconds: 220));
      expect(rig.s.drag, isNotNull, reason: '按住就拿起来了');
      await g.up();
      await tester.pumpAndSettle();
      expect(rig.s.drag, isNull, reason: '没挪就松手：不是拖');
      expect(rig.host.edits, 0);
      expect(find.text('加到常用'), findsOneWidget);
      await tester.tap(k('bk-palette-star-toggle'));
      await tester.pumpAndSettle();
      expect(store.value, ['block:try']);
      expect(store.saves, 1);
      expect(find.text('加到“常用”了。'), findsOneWidget);

      await rig.openTab(tester, '@common');
      expect(k('bk-palette-heading-加了星的'), findsOneWidget);
      expect(rig.shownItems(tester).first, 'block-try');
      expect(tester.getRect(k('bk-palette-heading-加了星的')).top, lessThan(tester.getRect(k('bk-palette-heading-这里用得最多')).top));

      // 在“常用”页按住它：这回是“从常用拿掉”。点菜单外面＝不动。
      g = await tester.startGesture(tester.getTopLeft(rig.item('block-try')) + const Offset(10, 20));
      await tester.pump(const Duration(milliseconds: 220));
      await g.up();
      await tester.pumpAndSettle();
      expect(find.text('从常用拿掉'), findsOneWidget);
      await tester.tapAt(const Offset(300, 120));
      await tester.pumpAndSettle();
      expect(store.value, ['block:try']);
      g = await tester.startGesture(tester.getTopLeft(rig.item('block-try')) + const Offset(10, 20));
      await tester.pump(const Duration(milliseconds: 220));
      await g.up();
      await tester.pumpAndSettle();
      await tester.tap(k('bk-palette-star-toggle'));
      await tester.pumpAndSettle();
      expect(store.value, isEmpty);
      expect(k('bk-palette-heading-加了星的'), findsNothing);
      expect(rig.host.edits, 0, reason: '加星不动文档');
      expect(tester.takeException(), isNull);
    });

    testWidgets('按住以后挪了＝拖出来，不弹加星；点一下还是快捷添加', (tester) async {
      final rig = FakeRig(busyBody());
      await rig.pump(tester);
      await rig.openTab(tester, 'text');
      final from = tester.getTopLeft(rig.item('block-say')) + const Offset(10, 20);
      final g = await tester.startGesture(from);
      await tester.pump(const Duration(milliseconds: 220));
      await rig.glide(tester, g, from, rig.snap(const [], 0));
      await rig.drop(tester, g);
      expect(find.text('加到常用'), findsNothing);
      expect(rig.tree.body.first.op, 'say');
      expect(rig.host.edits, 1);
      await tester.tap(rig.item('block-say'));
      await tester.pumpAndSettle();
      expect(rig.host.edits, 2);
      expect(find.text('加到常用'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('加星持久化：存进应用设置（按编辑器种类分键），重开还在；设置里是坏东西不崩', (tester) async {
      final dir = await tester.runAsync(() => Directory.systemTemp.createTemp('lopi_stars_'));
      addTearDown(() => dir!.deleteSync(recursive: true));
      final settings = SettingsStore(File('${dir!.path}/settings.json'));
      await tester.runAsync(settings.load);
      final stars = SettingsBlockStars(settings, 'fake');
      expect(stars.key, 'blocks.stars.fake');

      var rig = FakeRig(busyBody());
      await rig.pump(tester, stars: stars);
      await rig.openTab(tester, 'error');
      final g = await tester.startGesture(tester.getTopLeft(rig.item('block-throw')) + const Offset(10, 20));
      await tester.pump(const Duration(milliseconds: 220));
      await g.up();
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(k('bk-palette-star-toggle'));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(settings.get<List<dynamic>>('blocks.stars.fake'), ['block:throw']);
      expect(settings.get<Object>('blocks.stars.logic'), isNull, reason: '别的编辑器的星不受影响');

      // 重新读盘、重开编辑器：星还在。
      await tester.runAsync(() => settings.set('blocks.stars.fake', settings.get<Object>('blocks.stars.fake'))); // 等写盘落定
      final again = SettingsStore(File('${dir.path}/settings.json'));
      await tester.runAsync(again.load);
      await tester.pumpWidget(const SizedBox());
      rig = FakeRig(busyBody());
      await rig.pump(tester, stars: SettingsBlockStars(again, 'fake'));
      expect(k('bk-palette-heading-加了星的'), findsOneWidget);
      expect(rig.shownItems(tester).first, 'block-throw');

      // 设置里这一项被改坏了：当成没有星，不崩；再加星会把它写成好的。
      for (final bad in <Object>[
        'oops',
        7,
        {'a': 1},
        [
          1,
          null,
          'x',
          {'y': 2},
        ],
      ]) {
        await tester.runAsync(() => again.set('blocks.stars.fake', bad));
        await tester.pumpWidget(const SizedBox());
        rig = FakeRig(busyBody());
        await rig.pump(tester, stars: SettingsBlockStars(again, 'fake'));
        expect(k('bk-palette-page-@common'), findsOneWidget);
        expect(k('bk-palette-heading-加了星的'), findsNothing);
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('搜索：点放大镜，这一行换成搜索框；按字、按别名搜；结果能点、能拖；× 退出回到原来那一页', (tester) async {
      final rig = FakeRig(busyBody());
      await rig.pump(tester);
      await rig.openTab(tester, 'dict');
      await tester.tap(k('bk-palette-search'));
      await tester.pumpAndSettle();
      expect(k('bk-palette-search-field'), findsOneWidget);
      expect(k('bk-palette-tabs'), findsNothing, reason: '一行只做一件事：页签让给搜索框');
      expect(tester.getSize(k('bk-palette-tabs-grip')).height, 48);
      expect(k('bk-palette-search-idle'), findsOneWidget);
      expect(tester.testTextInput.isVisible, isTrue, reason: '点开就能打字');

      await tester.enterText(k('bk-palette-search-field'), '循环');
      await tester.pumpAndSettle();
      expect(k('bk-palette-page-@search'), findsOneWidget);
      expect(rig.shownItems(tester), ['block-repeat', 'block-while', 'block-forEach']);

      await tester.enterText(k('bk-palette-search-field'), '乘');
      await tester.pumpAndSettle();
      expect(rig.shownItems(tester), ['expr-arith~op=*']);
      expect(find.descendant(of: rig.item('expr-arith~op=*'), matching: find.byType(CustomPaint)), findsWidgets);

      // 结果直接拖出来：放进第一块“把 … 设为”的值槽，拿出来的就是 ×。键盘收起，词和结果留着。
      final from = tester.getTopLeft(rig.item('expr-arith~op=*')) + const Offset(10, 20);
      final g = await tester.startGesture(from);
      await tester.pump(const Duration(milliseconds: 220));
      expect(rig.s.drag, isNotNull);
      final p = rig.s.drag!.base.placed('s1')!;
      final target = p.layout.snaps.firstWhere((x) => x.arg == 'value' && x.exprPath.isEmpty && bkSameBlockPath(x.parent, [lcStep(0)]));
      final to = rig.s.globalOf(rig.s.toView(p.origin + target.rect.topLeft + rig.s.grabOffset + const Offset(2, 0)));
      await rig.glide(tester, g, from, to);
      await rig.drop(tester, g);
      final times = rig.tree.body[0].args['value'] as Map;
      expect(times['e'], 'arith');
      expect(times['op'], '*');
      expect(rig.host.edits, 1);
      expect(k('bk-palette-search-field'), findsOneWidget);
      expect(rig.shownItems(tester), ['expr-arith~op=*']);

      // 没搜到。
      await tester.enterText(k('bk-palette-search-field'), '量子纠缠');
      await tester.pumpAndSettle();
      expect(k('bk-palette-search-empty'), findsOneWidget);
      expect(find.text('没有找到“量子纠缠”'), findsOneWidget);
      expect(rig.shownItems(tester), isEmpty);

      // 点一下结果＝快捷添加。
      await tester.enterText(k('bk-palette-search-field'), '跳出');
      await tester.pumpAndSettle();
      rig.s.select(BlockSelection('s1', [lcStep(0)]));
      await tester.pumpAndSettle();
      await tester.tap(rig.item('block-break'));
      await tester.pumpAndSettle();
      expect(rig.host.edits, 2);

      await tester.tap(k('bk-palette-search-close'));
      await tester.pumpAndSettle();
      expect(k('bk-palette-search-field'), findsNothing);
      expect(k('bk-palette-page-dict'), findsOneWidget, reason: '回到搜索前的那一页');
      await tester.tap(k('bk-palette-search'));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(k('bk-palette-search-field')).controller!.text, isEmpty, reason: '重新打开是空的');
      expect(tester.takeException(), isNull);
    });

    testWidgets('搜索时键盘弹起：积木盒整个在键盘上面，高度还是默认档；手柄条、搜索框、结果都看得见；键盘收起回到原位', (tester) async {
      final rig = FakeRig(busyBody());
      await rig.pump(tester);
      addTearDown(tester.view.resetViewInsets);
      Rect dock() => tester.getRect(k('bk-dock'));
      expect(dock(), const Rect.fromLTWH(0, 844 - 248, 390, 248));
      await tester.tap(k('bk-palette-search'));
      await tester.pumpAndSettle();
      for (final kb in [0.0, 120.0, 300.0, 336.0, 300.0]) {
        tester.view.viewInsets = FakeViewPadding(bottom: kb * tester.view.devicePixelRatio);
        await tester.pumpAndSettle();
        expect(dock(), Rect.fromLTWH(0, 844 - kb - 248, 390, 248), reason: '键盘 $kb');
        expect(tester.takeException(), isNull);
      }
      await tester.enterText(k('bk-palette-search-field'), '如果');
      await tester.pumpAndSettle();
      final field = tester.getRect(k('bk-palette-search-field')), item = tester.getRect(rig.item('block-if'));
      expect(field.bottom, lessThan(844 - 300));
      expect(item.top, greaterThan(field.bottom));
      expect(item.top, lessThan(844 - 300), reason: '第一个结果在键盘上面');
      expect(tester.getRect(k('bk-palette-handle')).top, dock().top);
      // 面板原来顶到头：键盘升起后顶到头的高度跟着变矮，不被键盘盖住。
      await tester.drag(k('bk-palette-grip'), const Offset(0, -700), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(dock().top, 0);
      expect(dock().bottom, 844 - 300);
      tester.view.viewInsets = FakeViewPadding.zero;
      await tester.pumpAndSettle();
      expect(dock().bottom, 844);
      expect(tester.takeException(), isNull);
    });

    testWidgets('真的前端宿主不改：没有小标题、没有入门声明也照常——多一个“常用”页，原来各页的内容和顺序不变；后端宿主（第 1 阶段接线后）有小标题、入门积木、多口的“如果”', (tester) async {
      final doc = sampleDoc();
      final logic = LogicBlockHost(doc: doc, onEdit: (c) => c(doc));
      for (final c in logic.categories) {
        expect(c.groups, isEmpty);
        expect(bkCategorySections(c).length, lessThanOrEqualTo(1));
      }
      expect(logic.starterItems, isEmpty);
      expect(logic.variantsOf(const BlockItemRef.expr('bin')), isEmpty);
      expect(logic.aliasesOf(const BlockItemRef.block('if')), isEmpty);
      expect(logic.armSentence('if'), isNull);
      expect(logic.blockSpec('if')!.hasArms, isFalse);
      final common = bkCommonSections(logic, const []);
      expect(common.single.label, '这里用得最多');
      expect(common.single.items.length, lessThanOrEqualTo(bkCommonMax));

      final be = BeBlockHost(doc: backendStarterDocument('样本'));
      // 接线以后后端宿主声明了两级分类、入门积木和多口的“如果”（原来这里断言的是“没有”）。
      expect([
        for (final c in be.categories)
          if (c.groups.isNotEmpty) c.id,
      ], containsAll(['流程', '列表', '文字']));
      expect(be.starterItems, isNotEmpty);
      expect(bkCommonSections(be, const []).single.items, isNotEmpty);
      expect(bkSearchPalette(be, 'JSON'), isNotEmpty);
      expect(bkSearchPalette(be, '循环'), isNotEmpty);
      expect(be.blockSpec('if')!.hasArms, isTrue);
    });
  });

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    final suffix = mode == ThemeMode.light ? 'light' : 'dark';
    testWidgets('截图：两级分类、常用（有星 / 新文档）、搜索有结果 / 没结果 / 键盘弹起（$suffix）', (tester) async {
      addTearDown(tester.view.resetViewInsets);
      final store = MemoryBlockStars(['block:try', 'expr:textCase']);
      var rig = FakeRig(busyBody());
      await rig.pump(tester, mode: mode, stars: store);
      await tester.drag(k('bk-palette-grip'), const Offset(0, -160), warnIfMissed: false);
      await tester.pumpAndSettle();
      await shot(tester, 'bk7-common-$suffix');
      await rig.openTab(tester, 'control');
      await shot(tester, 'bk7-groups-control-$suffix');
      await rig.openTab(tester, 'list');
      await shot(tester, 'bk7-groups-list-$suffix');
      await rig.openTab(tester, 'operator');
      await shot(tester, 'bk7-groups-operator-$suffix');

      await tester.tap(k('bk-palette-search'));
      await tester.pumpAndSettle();
      await shot(tester, 'bk7-search-idle-$suffix');
      await tester.enterText(k('bk-palette-search-field'), '循环');
      await tester.pumpAndSettle();
      await shot(tester, 'bk7-search-found-$suffix');
      await tester.enterText(k('bk-palette-search-field'), '量子纠缠');
      await tester.pumpAndSettle();
      await shot(tester, 'bk7-search-empty-$suffix');
      tester.view.viewInsets = FakeViewPadding(bottom: 300 * tester.view.devicePixelRatio);
      await tester.enterText(k('bk-palette-search-field'), '于');
      await tester.pumpAndSettle();
      await shot(tester, 'bk7-search-keyboard-$suffix');
      tester.view.viewInsets = FakeViewPadding.zero;

      await tester.pumpWidget(const SizedBox());
      rig = FakeRig();
      await rig.pump(tester, mode: mode);
      await shot(tester, 'bk7-common-starter-$suffix');

      // 颜色总览：每一页的页签都点一遍（每种颜色的积木都画出来过）。
      for (final id in ['text', 'dict', 'error']) {
        await rig.openTab(tester, id);
        await shot(tester, 'bk7-page-$id-$suffix');
      }
    });
  }
}
