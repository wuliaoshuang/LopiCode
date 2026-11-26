// 低代码编辑器第 5 版第 3 期第 2 段（B2）：11 个新组件在编辑器里的那些事，390×844。
// 画布画法、往插槽里拖、标签页点着切、“只看这个弹层”、常用页的行和“选项 / 页签 / 导航项”的增删改排。
//   LOPI_SHOTS=1 LOPI_SHOT_DIR=某目录 flutter test --no-pub test/lowcode_editor_b2_test.dart   出截图
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/lowcode/canvas_view.dart';
import 'package:lopicode/lowcode/export_html.dart';
import 'package:lopicode/lowcode/items_edit.dart';
import 'package:lopicode/lowcode/model.dart';
import 'package:lopicode/lowcode/model_v3_components.dart';
import 'package:lopicode/lowcode/multi_select.dart';
import 'package:lopicode/lowcode/overlay_focus.dart';
import 'package:lopicode/lowcode/quick_actions.dart';
import 'package:lopicode/lowcode/slots.dart';
import 'package:lopicode/lowcode/states.dart';
import 'package:material_ui/material_ui.dart';

import 'support/harness.dart';
import 'support/lowcode_builder.dart';
import 'support/v3_components_sample.dart';

final String shotDir = Platform.environment['LOPI_SHOT_DIR'] ?? '.tmp/editor-b2-shots';
Future<void> shot(WidgetTester tester, String name) => lbShot(tester, shotDir, name);

Map<String, Object?> n(String id, String type, [Map<String, Object?> props = const {}, List<Object?> children = const [], String? slot]) => {
  'id': id,
  'type': type,
  if (props.isNotEmpty) 'props': props,
  if (children.isNotEmpty) 'children': children,
  'slot': ?slot,
};

/// 小页面：root › hi 文字、li 列表行（空的）、tb 标签页（a › tbA 文字；b 空）、box 容器（› inBox 文字）、dlg 弹窗（空的）。
LcDocument smallDoc() => LcDocument.parse(
  jsonEncode({
    'version': 3,
    'title': '小页面',
    'root': n(
      'root',
      'page',
      {'padding': 16, 'gap': 12},
      [
        n('hi', 'text', {'text': '你好'}),
        n('li', 'listItem', {'title': '通知', 'width': 'fill'}),
        n(
          'tb',
          'tabs',
          {
            'tabs': [
              {'id': 'a', 'label': '甲'},
              {'id': 'b', 'label': '乙'},
            ],
            'current': 'a',
            'width': 'fill',
          },
          [
            n('tbA', 'text', {'text': '甲里的字'}, const [], 'a'),
          ],
        ),
        n(
          'box',
          'container',
          {'padding': 8},
          [
            n('inBox', 'text', {'text': '盒子里的字'}),
          ],
        ),
        n('dlg', 'dialog', {'title': '提示', 'text': '这里写内容', 'okText': '确定'}),
      ],
    ),
  }),
);

/// 网格用的小页面：root › g 容器（撑满）› g1–g4 四个文字。
LcDocument gridDoc() => LcDocument.parse(
  jsonEncode({
    'version': 3,
    'title': '网格',
    'root': n(
      'root',
      'page',
      {'padding': 16},
      [
        n(
          'g',
          'container',
          {'width': 'fill', 'gap': 8},
          [
            for (final i in [1, 2, 3, 4]) n('g$i', 'text', {'text': '第 $i 格'}),
          ],
        ),
      ],
    ),
  }),
);

LcNode rd() => LcDocument.parse(
  jsonEncode({
    'version': 3,
    'title': 't',
    'root': n('root', 'page', const {}, [
      n('r', 'radio', {
        'options': [
          {'value': 'a', 'label': '甲'},
          {'value': 'b', 'label': '乙'},
        ],
        'value': 'a',
      }),
    ]),
  }),
).find('r')!;

void main() {
  setUpAll(() async => lbFontsLoaded = await loadRealFonts());

  group('插槽（纯计算）', () {
    test('放进普通容器去掉 slot；放进带插槽的：认得就留着，不认得跟前一个兄弟，标签页进当前页签', () {
      final d = smallDoc();
      // 页签里的字拖到盒子里：不带着旧插槽名走
      expect(d.move('tbA', 'box', 0), isTrue);
      expect(d.find('tbA')!.slot, isNull);
      // 再拖回标签页（没指明插槽）：进当前页签
      d.find('tb')!.props['current'] = 'b';
      expect(d.move('tbA', 'tb', 0), isTrue);
      expect(d.find('tbA')!.slot, 'b');
      // 指明插槽放进列表行左边；再点“加在它后面”的新组件跟它一个插槽
      final icon = d.newNode('icon');
      expect(lcInsertAt(d, lcSlotBoxId('li', 'left'), icon), isTrue);
      expect(icon.slot, 'left');
      final sw = d.newNode('switch');
      expect(d.insert('li', sw, 1), isTrue);
      expect(sw.slot, 'left');
      expect([for (final c in lcSlotChildren(d.find('li')!, 'left')) c.type], ['icon', 'switch']);
      // 不存在的插槽：放不进去
      expect(lcInsertAt(d, lcSlotBoxId('li', 'nope'), d.newNode('text')), isFalse);
      expect(lcMoveTo(d, 'hi', lcSlotBoxId('li', 'nope'), 0), isFalse);
    });

    test('插槽里的第几个 ↔ 平铺子节点里的第几个：两个插槽的东西混着存也排得对', () {
      final d = smallDoc();
      final li = d.find('li')!;
      for (final (type, slot) in [('icon', 'left'), ('switch', 'right'), ('icon', 'left')]) {
        lcInsertAt(d, lcSlotBoxId('li', slot), d.newNode(type));
      }
      expect([for (final c in li.children) '${c.type}@${c.slot}'], ['icon@left', 'icon@left', 'switch@right']);
      // 把“你好”放到左边插槽的第 2 个位置（两个图标中间）
      expect(lcMoveTo(d, 'hi', lcSlotBoxId('li', 'left'), 1), isTrue);
      expect([for (final c in lcSlotChildren(li, 'left')) c.type], ['icon', 'text', 'icon']);
      expect([for (final c in lcSlotChildren(li, 'right')) c.type], ['switch']);
    });

    test('多选一起挪进插槽：都写上插槽名；挪出来到普通容器：都去掉', () {
      final d = smallDoc();
      d.insert('root', d.newNode('button'), 1);
      final ids = {'hi', d.root.children[1].id};
      expect(lcMultiCanDropInto(d, ids, lcSlotBoxId('dlg', 'footer')), isTrue);
      expect(lcMultiCanDropInto(d, ids, lcSlotBoxId('dlg', 'nope')), isFalse);
      expect(lcMultiMoveTo(d, ids, lcSlotBoxId('dlg', 'footer'), 0), isTrue);
      expect([for (final c in lcSlotChildren(d.find('dlg')!, 'footer')) c.type], ['text', 'button']);
      expect(lcMultiMoveTo(d, ids, 'box', 0), isTrue);
      expect([for (final c in d.find('box')!.children) c.slot], [null, null, null]);
    });

    test('包成容器：容器顶替它留在原来的插槽里', () {
      final d = smallDoc();
      final boxId = lcMultiWrap(d, {'tbA'});
      expect(d.find(boxId!)!.slot, 'a');
      expect(d.find('tbA')!.slot, isNull);
    });

    test('只看这个弹层：选中弹窗或它里面的就进；点空白不出；选中外面的、弹窗没了就出', () {
      final d = smallDoc();
      lcInsertAt(d, lcSlotBoxId('dlg', 'content'), d.newNode('input'));
      final inside = d.find('dlg')!.children.single.id;
      final f = LcOverlayFocus();
      expect(f.sync(d, 'hi'), isNull);
      expect(f.sync(d, inside)?.id, 'dlg');
      expect(f.sync(d, null)?.id, 'dlg', reason: '点空白（取消选中）不退出');
      expect(f.sync(d, 'dlg')?.id, 'dlg');
      expect(f.sync(d, 'hi'), isNull, reason: '图层里选了弹窗外面的');
      expect(f.sync(d, 'dlg')?.id, 'dlg');
      f.exit();
      expect(f.sync(d, null), isNull);
      expect(f.sync(d, 'dlg')?.id, 'dlg');
      d.remove('dlg');
      expect(f.sync(d, null), isNull, reason: '弹窗被删了');
    });
  });

  group('选项 / 页签 / 导航项的增删改排（纯计算）', () {
    test('选项：加的值不重复；值改成空的、重复的不写并说原因；改了值默认选中跟着改；删了选中的就没有默认', () {
      final r = rd();
      const k = LcItemsKind.options;
      expect(lcItemAdd(r, k), isTrue);
      expect(lcObjects(r, 'options').last, {'value': 'opt3', 'label': '选项 3'});
      expect(lcItemSet(r, k, 1, 'value', ''), '值不能空着');
      expect(lcItemSet(r, k, 1, 'value', 'a'), '这个值别的选项用了');
      expect(lcItemSet(r, k, 1, 'value', 'x' * 81), '值最长 80 个字');
      expect(lcObjects(r, 'options')[1]['value'], 'b', reason: '不合规矩的没写进去');
      expect(lcItemSet(r, k, 0, 'value', 'apple'), isNull);
      expect(r.props['value'], 'apple');
      expect(lcItemIsCurrent(r, k, 0), isTrue);
      lcItemSetCurrent(r, k, 0);
      expect(r.props.containsKey('value'), isFalse, reason: '再点一次＝不要默认选中');
      lcItemSetCurrent(r, k, 2);
      expect(lcItemMove(r, k, 2, -1), isTrue);
      expect([for (final o in lcObjects(r, 'options')) o['value']], ['apple', 'opt3', 'b']);
      expect(lcItemMove(r, k, 0, -1), isFalse);
      expect(lcItemRemove(r, k, 1), 0);
      expect(r.props.containsKey('value'), isFalse);
      expect(lcItemRemove(r, k, 0), 0);
      expect(lcItemRemove(r, k, 0), -1, reason: '至少留一项');
      // 改出来的永远合读文件的规矩
      expect(lcCleanV3('radio', 'options', r.props['options']), isNotNull);
      for (var i = 0; i < 60; i++) {
        lcItemAdd(r, k);
      }
      expect(lcObjects(r, 'options'), hasLength(kLcMaxOptions));
      expect(lcCleanV3('radio', 'options', r.props['options']), isNotNull);
    });

    test('页签：新页签的 id 自动发；删页签连里面的组件一起删；当前页签被删了换成第一个', () {
      final d = smallDoc();
      final tb = d.find('tb')!;
      const k = LcItemsKind.tabs;
      expect(lcItemAdd(tb, k), isTrue);
      expect(lcObjects(tb, 'tabs').last['id'], 't1');
      expect(lcItemSet(tb, k, 0, 'id', 'zzz'), isNotNull, reason: '页签 id 不让改');
      expect(lcItemSet(tb, k, 0, 'label', '首页'), isNull);
      expect(lcTabChildCount(tb, 0), 1);
      lcItemSetCurrent(tb, k, 0);
      expect(lcItemRemove(tb, k, 0), 1);
      expect(d.find('tbA'), isNull);
      expect(tb.props['current'], 'b');
      expect(lcCleanV3('tabs', 'tabs', tb.props['tabs']), isNotNull);
    });

    test('导航项：当前项排序、删除时跟着那一项走；最多 5 项', () {
      final nav = LcDocument.parse(
        jsonEncode({
          'version': 3,
          'title': 't',
          'root': n('root', 'page', const {}, [n('nav', 'bottomNav', lcV3Specs['bottomNav']!.defaults)]),
        }),
      ).find('nav')!;
      const k = LcItemsKind.nav;
      lcItemSetCurrent(nav, k, 1);
      expect(lcItemMove(nav, k, 1, 1), isTrue);
      expect(nav.props['current'], 2);
      expect(lcItemMove(nav, k, 1, 1), isTrue);
      expect(nav.props['current'], 1, reason: '别的项挪过来把它挤到前面');
      expect(lcItemRemove(nav, k, 0), 0);
      expect(nav.props['current'], 0);
      expect(lcItemSet(nav, k, 0, 'icon', ''), isNotNull);
      expect(lcItemSet(nav, k, 0, 'icon', 'settings'), isNull);
      for (var i = 0; i < 9; i++) {
        lcItemAdd(nav, k);
      }
      expect(lcObjects(nav, 'items'), hasLength(kLcMaxNavItems));
      expect(lcCleanV3('bottomNav', 'items', nav.props['items']), isNotNull);
    });
  });

  group('快捷动作：打开 / 关闭弹窗（纯计算）', () {
    final open = kLcQuickActions.firstWhere((a) => a.id == 'openDialog'), close = kLcQuickActions.firstWhere((a) => a.id == 'closeDialog');

    test('存成一块普通的“改控件 弹窗 的 显示”积木；打开和关闭各认各的；换弹窗、去掉；不是弹窗的不让设', () {
      final d = smallDoc();
      expect(lcDialogsOf(d).map((x) => x.id), ['dlg']);
      expect(lcSetQuick(d, 'hi', open, 'box'), isFalse, reason: '不是弹窗');
      expect(lcSetQuick(d, 'hi', open, 'nope'), isFalse, reason: '没有这个组件');
      expect(lcSetQuick(d, 'hi', open, 'dlg'), isTrue);
      expect(lcSetQuick(d, 'hi', open, 'dlg'), isFalse, reason: '没变');
      final b = d.logic.handlersFor('hi').single.body.single;
      expect(b.op, 'setProp');
      expect(b.args, {
        'node': 'dlg',
        'prop': 'visible',
        'value': {'e': 'bool', 'v': true},
      });
      expect(lcQuickValue(d, 'hi', open), 'dlg');
      expect(lcQuickValue(d, 'hi', close), isNull, reason: '打开的那一串不算关闭');
      expect(lcSetQuick(d, 'hi', close, 'dlg'), isTrue);
      expect(d.logic.handlersFor('hi'), hasLength(2));
      expect(lcSetQuick(d, 'hi', open, ''), isTrue);
      expect(lcQuickValue(d, 'hi', open), isNull);
      expect(lcQuickValue(d, 'hi', close), 'dlg');
    });

    test('样例页里手写的“点按钮打开弹窗”认得出是快捷动作；网页导出里真的有这一句', () {
      final d = v3AllPage();
      expect(lcQuickValue(d, 'open', open), 'dlg');
      expect(exportHtml(d).js, contains('lcSet("dlg", "visible", true)'));
    });
  });

  group('画布', () {
    testWidgets('四个样例页都画得出来（浅色 / 深色），逐个选中 11 种新组件不出异常', (tester) async {
      for (final e in v3ComponentSamples().entries) {
        await lbOpen(tester, doc: e.value());
        await shot(tester, 'page-${e.key}');
      }
      await lbOpen(tester, doc: v3AllPage());
      final seen = <String>{};
      void walk(LcNode x, List<LcNode> out) {
        if (lcV3Specs.containsKey(x.type) && seen.add(x.type)) out.add(x);
        for (final c in x.children) {
          walk(c, out);
        }
      }

      final firsts = <LcNode>[];
      walk(v3AllPage().root, firsts);
      expect(seen, lcV3Specs.keys.toSet(), reason: '样例页里 11 种都有');
      for (final x in firsts) {
        lbCanvas(tester).revealNode(x.id);
        await settle(tester, rounds: 2);
        expect(lbNode(x.id), findsWidgets, reason: '${x.type}（${x.id}）在画布上找不到');
        await lbTap(tester, lbNode(x.id).first);
        await shot(tester, 'comp-${x.type}');
        if (x.type == 'dialog') await lbTap(tester, lbKey('lc-overlay-exit'));
      }
      await lbOpen(tester, doc: v3SettingsPage(), mode: ThemeMode.dark);
      await shot(tester, 'page-设置页-dark');
    });

    testWidgets('往插槽里拖：组件盒的图标拖进列表行左边；画布上的字拖进右边；存下来带着插槽名', (tester) async {
      final session = await lbOpen(tester, doc: smallDoc());
      expect(lbKey('lc-slot-hint-li-left'), findsOneWidget);
      expect(lbKey('lc-slot-hint-li-right'), findsOneWidget);
      await lbOpenPalette(tester);
      await lbTap(tester, lbKey('palette-group-basic'));
      final chip = await lbLift(tester, tester.getCenter(lbPaletteItem('icon')));
      await chip.moveTo(tester.getCenter(lbKey('lc-slot-hint-li-left')));
      await tester.pump();
      expect(lbCanvas(tester).dropTarget?.parentId, 'li#left');
      await shot(tester, 'slot-drag-into-left');
      await chip.up();
      await settle(tester, rounds: 3);
      var doc = await lbSaved(tester, session);
      expect([for (final c in doc.find('li')!.children) '${c.type}@${c.slot}'], ['icon@left']);
      expect(lbKey('lc-slot-hint-li-left'), findsNothing, reason: '有东西了，空插槽的落点收起');

      // 关掉组件盒，长按“你好”拖进右边
      await tester.tapAt(const Offset(195, 120));
      await settle(tester, rounds: 2);
      final hi = await lbLift(tester, tester.getCenter(lbNode('hi')));
      await hi.moveTo(tester.getCenter(lbKey('lc-slot-hint-li-right')));
      await tester.pump();
      expect(lbCanvas(tester).dropTarget?.parentId, 'li#right');
      await hi.up();
      await settle(tester, rounds: 3);
      doc = await lbSaved(tester, session);
      expect([for (final c in doc.find('li')!.children) '${c.type}@${c.slot}'], ['icon@left', 'text@right']);
      expect(doc.root.children.first.id, 'li');
      await shot(tester, 'slot-list-item-filled');
    });

    testWidgets('标签页：画布上点页签就切过去（不改文件）；往当前页签里拖；选中别的页签里的组件自己切过去', (tester) async {
      final session = await lbOpen(tester, doc: smallDoc());
      final before = (await lbSaved(tester, session)).encode();
      expect(find.text('甲里的字'), findsOneWidget);
      await lbTap(tester, lbKey('lc-tab-tb-b'));
      expect(find.text('甲里的字'), findsNothing);
      expect(lbKey('lc-slot-hint-tb-b'), findsOneWidget);
      expect((await lbSaved(tester, session)).encode(), before, reason: '点页签只是换着看，不改页面文件');
      await shot(tester, 'tabs-switched');

      final hi = await lbLift(tester, tester.getCenter(lbNode('hi')));
      await hi.moveTo(tester.getCenter(lbKey('lc-slot-hint-tb-b')));
      await tester.pump();
      expect(lbCanvas(tester).dropTarget?.parentId, 'tb#b');
      await hi.up();
      await settle(tester, rounds: 3);
      final doc = await lbSaved(tester, session);
      expect([for (final c in doc.find('tb')!.children) '${c.id}@${c.slot}'], ['tbA@a', 'hi@b']);

      // 图层里点甲页签里的字：画布自己切回甲
      await lbTap(tester, find.byTooltip('图层'));
      await lbTap(tester, lbKey('lc-layer-tbA'));
      await tester.tapAt(const Offset(195, 60));
      await settle(tester, rounds: 3);
      expect(find.text('甲里的字'), findsOneWidget);
    });

    testWidgets('弹窗：点页面里的小标签＝只看这个弹层；能往内容区、底部拖；点空白不退出；点“退出”回页面', (tester) async {
      final session = await lbOpen(tester, doc: smallDoc());
      expect(lbKey('lc-overlay-bar'), findsNothing);
      await lbTap(tester, lbNode('dlg'));
      expect(lbKey('lc-overlay-bar'), findsOneWidget);
      expect(find.text('正在编辑弹窗：提示'), findsOneWidget);
      expect(find.text('你好'), findsNothing, reason: '只看这个弹层：页面上别的不画');
      expect(find.text('这里写内容'), findsOneWidget);
      expect(lbKey('lc-slot-hint-dlg-content'), findsOneWidget);
      expect(lbKey('lc-slot-hint-dlg-footer'), findsOneWidget);
      await shot(tester, 'dialog-editing');
      // 横条不盖弹窗面板
      final bar = tester.getRect(lbKey('lc-overlay-bar'));
      expect(tester.getRect(lbNode('dlg')).top, greaterThanOrEqualTo(bar.bottom));

      // 点一下添加（什么都没选中）：加进这个弹窗
      await tester.tapAt(Offset(195, bar.bottom + 6));
      await settle(tester, rounds: 2);
      expect(lbKey('lc-overlay-bar'), findsOneWidget, reason: '点空白不退出');
      await lbOpenPalette(tester);
      final chip = await lbLift(tester, tester.getCenter(lbPaletteItem('input')));
      await chip.moveTo(tester.getCenter(lbKey('lc-slot-hint-dlg-content')));
      await tester.pump();
      expect(lbCanvas(tester).dropTarget?.parentId, 'dlg#content');
      await chip.up();
      await settle(tester, rounds: 3);
      var doc = await lbSaved(tester, session);
      expect([for (final c in doc.find('dlg')!.children) '${c.type}@${c.slot}'], ['input@content']);
      await shot(tester, 'dialog-with-input');

      await tester.tapAt(Offset(195, bar.bottom + 6));
      await settle(tester, rounds: 2);
      await lbTap(tester, lbKey('lc-overlay-exit'));
      expect(lbKey('lc-overlay-bar'), findsNothing);
      expect(find.text('你好'), findsOneWidget);
      doc = await lbSaved(tester, session);
      expect(doc.find('dlg')!.children, hasLength(1));
    });

    testWidgets('点一下添加弹窗：永远加在页面最后，并直接进它的编辑状态', (tester) async {
      final session = await lbOpen(tester, doc: smallDoc(), selected: 'box');
      await lbOpenPalette(tester);
      await lbTap(tester, lbKey('palette-group-layout'));
      await lbShow(tester, lbPaletteItem('dialog'));
      await lbTap(tester, lbPaletteItem('dialog'));
      final doc = await lbSaved(tester, session);
      expect(doc.root.children.last.type, 'dialog');
      expect(doc.find('box')!.children, hasLength(1), reason: '没加进选中的容器里');
      expect(lbKey('lc-overlay-bar'), findsOneWidget);
    });

    testWidgets('“这个页面是新版做的”提示条不盖页面顶上的组件；点“知道了”页面回到原位', (tester) async {
      final text = jsonEncode({...jsonDecode(smallDoc().encode()) as Map<String, dynamic>, 'version': 9});
      await lbOpen(tester, text: text);
      final notice = tester.getRect(lbKey('lc-newer-notice'));
      final hi = tester.getRect(lbNode('hi'));
      expect(hi.top, greaterThanOrEqualTo(notice.bottom), reason: '页面顶边让到提示条下面');
      await shot(tester, 'newer-notice-not-covering');
      await lbTap(tester, lbKey('lc-newer-notice-ok'));
      expect(lbKey('lc-newer-notice'), findsNothing);
      expect(tester.getRect(lbNode('hi')).top, lessThan(hi.top));
    });
  });

  group('合一面板', () {
    testWidgets('单选组：选项能加、改名、改值（重复的不写、出红字）、排序、删，默认选中跟着走', (tester) async {
      final session = await lbOpen(tester, doc: v3SettingsPage(), selected: 'size');
      await lbOpenCommon(tester);
      expect(lbKey('lc-items-options'), findsOneWidget);
      await shot(tester, 'inspector-radio-options');
      final before = lcObjects((await lbSaved(tester, session)).find('size')!, 'options');
      await lbTapShown(tester, lbKey('lc-items-add'));
      var node = (await lbSaved(tester, session)).find('size')!;
      expect(lcObjects(node, 'options'), hasLength(before.length + 1));
      final last = before.length;
      await lbShow(tester, lbKey('lc-items-label-$last'));
      await tester.enterText(lbKey('lc-items-label-$last'), '特大');
      await tester.enterText(lbKey('lc-items-value-$last'), before.first['value'] as String);
      await settle(tester, rounds: 2);
      expect(lbKey('lc-items-error-$last'), findsOneWidget);
      await shot(tester, 'inspector-radio-options-error');
      await tester.enterText(lbKey('lc-items-value-$last'), 'xl');
      await settle(tester, rounds: 2);
      expect(lbKey('lc-items-error-$last'), findsNothing);
      await lbTapShown(tester, lbKey('lc-items-current-$last'));
      await lbTapShown(tester, lbKey('lc-items-up-$last'));
      node = (await lbSaved(tester, session)).find('size')!;
      expect(lcObjects(node, 'options')[last - 1], {'value': 'xl', 'label': '特大'});
      expect(node.props['value'], 'xl');
      await lbTapShown(tester, lbKey('lc-items-remove-${last - 1}'));
      node = (await lbSaved(tester, session)).find('size')!;
      expect(lcObjects(node, 'options'), hasLength(before.length));
      expect(node.props.containsKey('value'), isFalse);
      // 撤销一步：删掉的回来
      await lbTap(tester, find.byTooltip('撤销'));
      node = (await lbSaved(tester, session)).find('size')!;
      expect(node.props['value'], 'xl');
    });

    testWidgets('标签页：删有东西的页签先问；确认后连里面的组件一起删', (tester) async {
      final session = await lbOpen(tester, doc: smallDoc(), selected: 'tb');
      await lbOpenCommon(tester);
      expect(lbKey('lc-items-tabs'), findsOneWidget);
      expect(lbKey('lc-common-slot-tip'), findsOneWidget);
      await lbTapShown(tester, lbKey('lc-items-remove-0'));
      expect(find.text('里面的 1 个组件会一起删掉。删错了可以撤销。'), findsOneWidget);
      await shot(tester, 'inspector-tabs-remove-ask');
      await lbTapShown(tester, lbKey('lc-items-remove-ok'));
      final doc = await lbSaved(tester, session);
      expect(doc.find('tbA'), isNull);
      expect([for (final t in lcObjects(doc.find('tb')!, 'tabs')) t['id']], ['b']);
      expect(tester.widget<IconButton>(lbKey('lc-items-remove-0')).onPressed, isNull, reason: '只剩一个页签不能删');
    });

    testWidgets('事件页：页面里没有弹窗时两样弹窗动作是灰的；有了就能选，选完写着弹窗的标题，再点能去掉', (tester) async {
      final none = smallDoc()..remove('dlg');
      await lbOpen(tester, doc: none, selected: 'hi');
      await lbOpenCommon(tester);
      await lbTap(tester, find.text('事件'));
      await lbShow(tester, lbKey('lc-quick-openDialog'));
      expect(find.text('先加一个弹窗'), findsNWidgets(2));
      await lbTap(tester, lbKey('lc-quick-openDialog'));
      expect(lbKey('lc-quick-dialog-0'), findsNothing, reason: '灰的点不动');

      final session = await lbOpen(tester, doc: smallDoc(), selected: 'hi');
      await lbOpenCommon(tester);
      await lbTap(tester, find.text('事件'));
      await lbTapShown(tester, lbKey('lc-quick-openDialog'));
      await shot(tester, 'quick-dialog-pick');
      expect(lbKey('lc-quick-dialog-none'), findsNothing, reason: '还没设，没有“不要这个动作”');
      await lbTap(tester, lbKey('lc-quick-dialog-0'));
      var d = await lbSaved(tester, session);
      expect(d.logic.handlersFor('hi').single.body.single.args['node'], 'dlg');
      await lbShow(tester, lbKey('lc-quick-openDialog'));
      expect(find.descendant(of: lbKey('lc-quick-openDialog'), matching: find.text('提示')), findsOneWidget);
      await shot(tester, 'quick-dialog-set');
      await lbTapShown(tester, lbKey('lc-quick-openDialog'));
      await lbTap(tester, lbKey('lc-quick-dialog-none'));
      d = await lbSaved(tester, session);
      expect(d.logic.handlersFor('hi'), isEmpty);
    });

    testWidgets('状态样式：样式页顶上选“按下”，改的只记进 states.pressed；画布照这个状态画；清掉、换组件都回到平时', (tester) async {
      final session = await lbOpen(tester, doc: smallDoc(), selected: 'hi');
      await lbOpenCommon(tester);
      await lbTap(tester, find.text('样式').last);
      expect(lbKey('lc-state-bar'), findsOneWidget);
      expect(lbKey('lc-state-note'), findsNothing, reason: '平时不出那行提醒');
      await lbTap(tester, lbKey('lc-state-pressed'));
      expect(lbKey('lc-state-note'), findsOneWidget);
      expect(tester.widget<CanvasView>(find.byType(CanvasView)).statePreview, (nodeId: 'hi', state: 'pressed'));
      await lbTapShown(tester, lbKey('lc-tab-layout'));
      await lbTapShown(tester, lbKey('lc-num-flex-grow-plus'));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      var hi = (await lbSaved(tester, session)).find('hi')!;
      expect(lcStateStyle(hi, 'pressed'), {'flex-grow': '1'});
      expect(hi.style.containsKey('flex-grow'), isFalse, reason: '平时的样子没动');
      await lbShow(tester, lbKey('lc-state-bar'));
      expect(lbKey('lc-state-dot-pressed'), findsOneWidget, reason: '写过东西的状态有个小点');
      await shot(tester, 'state-pressed');
      await lbTapShown(tester, lbKey('lc-state-clear'));
      hi = (await lbSaved(tester, session)).find('hi')!;
      expect(hi.more.containsKey('states'), isFalse, reason: '清空了整个字段都不留');
      // 换一个组件：回到平时。
      await lbTap(tester, lbNode('inBox'));
      expect(lbKey('lc-state-note'), findsNothing);
      expect(tester.widget<CanvasView>(find.byType(CanvasView)).statePreview, isNull);
    });

    testWidgets('网格：容器的排法选“网格”出列数和两个间距；里面的组件多一行“跨几列”；画布按列排', (tester) async {
      final session = await lbOpen(tester, doc: gridDoc(), selected: 'g');
      await lbOpenCommon(tester);
      await lbTap(tester, find.text('样式').last);
      await lbTapShown(tester, lbKey('lc-tab-layout'));
      expect(lbKey('lc-num-grid-columns'), findsNothing, reason: '还是弹性');
      await lbTapShown(tester, lbKey('lc-opt-layout-mode-grid'));
      var g = (await lbSaved(tester, session)).find('g')!;
      expect(g.style['display'], 'grid');
      expect(g.style['grid-template-columns'], 'repeat(2, 1fr)');
      await lbTapShown(tester, lbKey('lc-num-grid-columns-plus'));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      g = (await lbSaved(tester, session)).find('g')!;
      expect(g.style['grid-template-columns'], 'repeat(3, 1fr)');
      // 画布：三列，前三个在同一行、第四个换到下一行最左。
      final r = [
        for (final id in ['g1', 'g2', 'g3', 'g4']) tester.getRect(lbNode(id)),
      ];
      expect(r[0].top, r[1].top);
      expect(r[1].top, r[2].top);
      expect(r[0].left < r[1].left && r[1].left < r[2].left, isTrue);
      expect(r[3].top > r[0].top, isTrue);
      expect(r[3].left, r[0].left);
      expect((r[0].width - r[1].width).abs() < 0.5, isTrue, reason: '每列一样宽');
      await shot(tester, 'grid-3-columns');
      // 里面的组件：跨两列。
      await lbTap(tester, lbNode('g1'));
      await lbTapShown(tester, lbKey('lc-num-grid-span-plus'));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      final d = await lbSaved(tester, session);
      expect(d.find('g1')!.style['grid-column'], 'span 2');
      final wide = tester.getRect(lbNode('g1')), next = tester.getRect(lbNode('g2'));
      expect(wide.width > next.width * 1.9, isTrue, reason: '跨两列的那个大约两倍宽');
      await shot(tester, 'grid-span-2');
      final html = exportHtml(d);
      expect(html.css, contains('grid-template-columns: repeat(3, 1fr)'));
      expect(html.css, contains('grid-column: span 2'));
      // 换回弹性：列写法去掉。
      await lbTap(tester, lbNode('g'));
      await lbTapShown(tester, lbKey('lc-opt-layout-mode-flex'));
      g = (await lbSaved(tester, session)).find('g')!;
      expect(g.style.containsKey('display'), isFalse);
      expect(g.style.containsKey('grid-template-columns'), isFalse);
    });

    testWidgets('带插槽的组件（列表行）样式页的布局组不出“排法”那几行：里面怎么排是它自己定的', (tester) async {
      await lbOpen(tester, doc: smallDoc(), selected: 'box');
      await lbOpenCommon(tester);
      await lbTap(tester, find.text('样式').last);
      await lbTapShown(tester, lbKey('lc-tab-layout'));
      expect(lbKey('lc-opt-layout-mode-grid'), findsOneWidget, reason: '普通容器有');
      await lbTap(tester, lbNode('li'));
      expect(lbKey('lc-opt-layout-mode-grid'), findsNothing);
    });

    testWidgets('11 种新组件的常用页都开得出来；弹窗的样子、开关写进文件，和默认一样就不写', (tester) async {
      final all = v3AllPage();
      final firsts = <String, String>{};
      void walk(LcNode x) {
        if (lcV3Specs.containsKey(x.type)) firsts.putIfAbsent(x.type, () => x.id);
        x.children.forEach(walk);
      }

      walk(all.root);
      for (final e in firsts.entries) {
        await lbOpen(tester, doc: v3AllPage(), selected: e.value);
        await lbOpenCommon(tester);
        await shot(tester, 'inspector-${e.key}');
      }
      final session = await lbOpen(tester, doc: smallDoc(), selected: 'dlg');
      await lbOpenCommon(tester);
      await lbTapShown(tester, lbKey('lc-common-variant-confirm'));
      expect(lbKey('lc-common-cancelText'), findsOneWidget);
      await lbTapShown(tester, lbKey('lc-common-dismissible'));
      var d = (await lbSaved(tester, session)).find('dlg')!;
      expect(d.props['variant'], 'confirm');
      expect(d.props['dismissible'], false);
      await lbTapShown(tester, lbKey('lc-common-dismissible'));
      await lbTapShown(tester, lbKey('lc-common-variant-alert'));
      d = (await lbSaved(tester, session)).find('dlg')!;
      expect(d.props.containsKey('variant'), isFalse);
      expect(d.props.containsKey('dismissible'), isFalse);
    });
  });
}
