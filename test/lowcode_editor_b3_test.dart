// 低代码编辑器第 5 版第 3 期第 3 段（B3）：自定义组件带插槽在编辑器里的那些事，和第 2 段留下的几处补上。390×844。
//   LOPI_SHOTS=1 LOPI_SHOT_DIR=某目录 flutter test --no-pub test/lowcode_editor_b3_test.dart   出截图
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/lowcode/component_editing.dart';
import 'package:lopicode/lowcode/model.dart';
import 'package:material_ui/material_ui.dart';

import 'support/harness.dart';
import 'support/lowcode_builder.dart';
import 'support/slot_sample.dart';

final String shotDir = Platform.environment['LOPI_SHOT_DIR'] ?? '.tmp/editor-b3-shots';
Future<void> shot(WidgetTester tester, String name) => lbShot(tester, shotDir, name);

Map<String, Object?> n(String id, String type, [Map<String, Object?> props = const {}, List<Object?> children = const []]) => {
  'id': id,
  'type': type,
  if (props.isNotEmpty) 'props': props,
  if (children.isNotEmpty) 'children': children,
};

/// 一个还没有插槽的组件“盒子”：卡片（k1）里一行标题（k2）和一列（k3，里面一行字 k4）。页面上两个实例。
LcDocument plainDoc({List<Object?> extra = const []}) => LcDocument.parse(
  jsonEncode({
    'version': 3,
    'title': 'Box',
    'root': n(
      'root',
      'page',
      {'padding': 16, 'gap': 12},
      [
        n('hi', 'text', {'text': '你好'}),
        n('a', 'component', {'ref': 'c1'}),
        n('b', 'component', {'ref': 'c1'}),
        ...extra,
      ],
    ),
    'components': [
      {
        'id': 'c1',
        'name': '盒子',
        'root': n(
          'k1',
          'card',
          {'padding': 12, 'gap': 8, 'width': 'fill'},
          [
            n('k2', 'text', {'text': '标题', 'bold': true}),
            n(
              'k3',
              'column',
              {'gap': 6, 'width': 'fill'},
              [
                n('k4', 'text', {'text': '默认的字'}),
              ],
            ),
          ],
        ),
      },
    ],
  }),
);

Future<void> more(WidgetTester tester, String label) async {
  await lbTap(tester, find.byTooltip('更多操作'));
  await lbTapShown(tester, find.text(label).last);
  await settle(tester, rounds: 2);
}

Future<void> editComponent(WidgetTester tester, String instanceId) async {
  await lbTap(tester, lbNode(instanceId));
  await more(tester, '编辑组件');
  expect(find.text('编辑组件'), findsOneWidget);
}

int onCanvas(String text) => find.descendant(of: lbKey('lowcode-page'), matching: find.text(text)).evaluate().length;

void main() {
  setUpAll(() async => lbFontsLoaded = await loadRealFonts());

  group('组件编辑页里的插槽', () {
    testWidgets('把一个容器的内容设成插槽：起名、设成默认插槽；定义的 slots 跟着有；回页面两个实例都能往里放', (tester) async {
      final session = await lbOpen(tester, doc: plainDoc());
      await editComponent(tester, 'a');
      await lbTap(tester, lbNode('k4'));
      expect(find.text('把内容设成插槽'), findsNothing);
      await lbTap(tester, find.byTooltip('更多操作'));
      expect(find.text('把内容设成插槽'), findsNothing, reason: '文本不是容器，没有这一项');
      await tester.tapAt(const Offset(195, 60));
      await settle(tester, rounds: 2);
      // 选中那一列（点它里面的字选中的是字：从选中条“上一层”过去）
      await lbTap(tester, find.byTooltip('选上一层'));
      expect(find.text('列'), findsWidgets);
      await more(tester, '把内容设成插槽');
      expect(lbKey('slot-name-field'), findsOneWidget);
      expect(tester.widget<Switch>(lbKey('slot-default-switch')).value, isTrue, reason: '第一个插槽默认就是默认插槽');
      await shot(tester, '01-slot-name-dialog');
      await tester.enterText(lbKey('slot-name-field'), '');
      await lbTap(tester, lbKey('slot-name-ok'));
      expect(find.text('给插槽起个名字'), findsOneWidget, reason: '名字空着不关对话框，原因写在框下面');
      await tester.enterText(lbKey('slot-name-field'), '内容');
      await lbTap(tester, lbKey('slot-name-ok'));
      await settle(tester, rounds: 3);
      expect(lbKey('slot-name-field'), findsNothing);
      expect(find.text('插槽 · 内容'), findsWidgets, reason: '画布上的角标 / 选中条');
      await shot(tester, '02-slot-made');
      var doc = await lbSaved(tester, session);
      var def = doc.component('c1')!;
      expect([for (final s in def.slots) (s.name, s.label)], [('default', '内容')]);
      final k3 = def.root.children[1];
      expect((k3.id, k3.type, k3.children.single.type, k3.children.single.children.single.id), ('k3', 'column', 'slot', 'k4'), reason: '容器还在，原来的内容成了默认内容');

      // 最外层的卡片也能设（第二个插槽：默认插槽的开关是灰的；重名不让）
      await lbTap(tester, lbNode('k2'));
      await lbTap(tester, find.byTooltip('选上一层'));
      expect(find.text('卡片（最外层）'), findsOneWidget);
      await more(tester, '把内容设成插槽');
      expect(tester.widget<Switch>(lbKey('slot-default-switch')).onChanged, isNull);
      expect(find.text('这个组件已经有默认插槽了'), findsOneWidget);
      await tester.enterText(lbKey('slot-name-field'), '内容');
      await lbTap(tester, lbKey('slot-name-ok'));
      expect(find.textContaining('已经有一个叫'), findsOneWidget);
      await lbTap(tester, find.text('取消'));
      await settle(tester, rounds: 2);
      await lbTap(tester, lbKey('comp-editor-done'));
      await settle(tester, rounds: 3);
      doc = await lbSaved(tester, session);
      def = doc.component('c1')!;
      expect(def.slots.length, 1);
      expect(doc.find('a')!.hasSlots && doc.find('b')!.hasSlots, isTrue);
      expect(onCanvas('默认的字'), 2, reason: '两个实例都没填：都显示默认内容');
    });

    testWidgets('改插槽名：实例里填的内容跟着；取消插槽：先说有几处填了，确认后内容挪到实例后面', (tester) async {
      final session = await lbOpen(tester, doc: slotCardPage());
      await editComponent(tester, 'b');
      expect(find.text('插槽 · 内容'), findsOneWidget);
      expect(find.text('插槽 · 底部按钮'), findsOneWidget);
      await shot(tester, '03-editor-two-slots');
      // 点默认内容选中的是它自己；上一层才是插槽
      await lbTap(tester, lbNode('k8'));
      await lbTap(tester, find.byTooltip('选上一层'));
      expect(find.widgetWithText(FilledButton, '改名'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, '常用'), findsNothing, reason: '插槽没有样子可改');
      await shot(tester, '04-slot-selected');
      await lbTap(tester, find.widgetWithText(FilledButton, '改名'));
      expect(tester.widget<TextField>(lbKey('slot-name-field')).controller!.text, '底部按钮');
      await tester.enterText(lbKey('slot-name-field'), 'actions');
      await lbTap(tester, lbKey('slot-name-ok'));
      await settle(tester, rounds: 3);
      var doc = await lbSaved(tester, session);
      expect([for (final s in doc.component('c1')!.slots) (s.name, s.label)], [('default', '内容'), ('actions', 'actions')]);
      expect([for (final c in doc.find('a')!.children) c.slot], [null, 'default', 'actions', 'actions'], reason: '改名跟着改，一个不丢');

      // 取消这个插槽
      await lbTap(tester, find.widgetWithText(OutlinedButton, '取消插槽'));
      expect(find.textContaining('有 1 个用到这个组件的地方在这个插槽里填了东西（共 2 个组件）'), findsOneWidget);
      expect(find.textContaining('挪到各自那个组件的后面，不会删掉'), findsOneWidget);
      await shot(tester, '05-unwrap-confirm');
      await lbTap(tester, find.widgetWithText(TextButton, '取消插槽'));
      await settle(tester, rounds: 3);
      doc = await lbSaved(tester, session);
      expect([for (final s in doc.component('c1')!.slots) s.name], ['default']);
      expect([for (final c in doc.root.children) c.id], ['head', 'a', 'b1', 'b2', 'b']);
      expect(doc.find('b1')!.slot, isNull);
      expect(doc.find('k8'), isNull);
      expect(doc.component('c1')!.root.children[2].children.single.id, 'k8', reason: '默认内容留在组件里原来的位置');
      // 撤销（组件编辑页里）：插槽回来；已经挪出去的内容不会被吞回去，也不丢
      await lbTap(tester, find.byTooltip('撤销'));
      await settle(tester, rounds: 3);
      doc = await lbSaved(tester, session);
      expect([for (final s in doc.component('c1')!.slots) s.name], ['default', 'actions']);
      expect(doc.find('b1'), isNotNull);
    });

    testWidgets('删掉一个有人填了内容的插槽（不走“取消插槽”）：拦下，说明原因，什么都没变', (tester) async {
      final session = await lbOpen(tester, doc: slotCardPage());
      await editComponent(tester, 'b');
      await lbTap(tester, lbNode('k8'));
      await lbTap(tester, find.byTooltip('选上一层'));
      await lbTap(tester, find.byTooltip('更多操作'));
      expect(find.byType(PopupMenuItem<String>), findsNWidgets(5), reason: '插槽的菜单只有：改插槽名、取消插槽、上移、下移、删除');
      expect(tester.getRect(find.text('删除')).bottom, lessThan(844 - 8), reason: '菜单一屏放得下，“删除”不用滚就点得到');
      await lbTap(tester, find.text('删除'));
      await settle(tester, rounds: 2);
      expect(find.textContaining('没地方放'), findsOneWidget);
      await shot(tester, '06-slot-delete-blocked');
      await lbTap(tester, find.text('知道了'));
      expect(find.text('插槽 · 底部按钮'), findsOneWidget, reason: '退回去了');
      final doc = await lbSaved(tester, session);
      expect(doc.component('c1')!.slots.length, 2);
      expect(doc.find('a')!.children.length, 4);
    });

    testWidgets('组件编辑页里不能放弹窗：点着加、拖着加都拦下并说明；粘贴进来的也拦', (tester) async {
      final session = await lbOpen(tester, doc: plainDoc());
      await editComponent(tester, 'a');
      await lbOpenPalette(tester);
      await lbTap(tester, lbKey('palette-group-layout'));
      // 拖着加
      final chip = await lbLift(tester, tester.getCenter(lbPaletteItem('dialog')));
      await chip.moveTo(tester.getCenter(lbNode('k4')) + const Offset(40, 0));
      await tester.pump();
      // 组件编辑页里只能放进容器：在卡片上停一会儿才算“要放进去”
      await tester.pump(const Duration(milliseconds: 700));
      await chip.moveBy(const Offset(2, 0));
      await tester.pump();
      expect(lbCanvas(tester).dropTarget, isNotNull);
      await chip.up();
      await settle(tester, rounds: 3);
      expect(find.text(kNoDialogInComponent), findsOneWidget);
      await shot(tester, '07-no-dialog-in-component');
      await lbTap(tester, find.text('知道了'));
      // 点着加
      await lbOpenPalette(tester);
      await lbTap(tester, lbKey('palette-group-layout'));
      await lbShow(tester, lbPaletteItem('dialog'));
      await lbTap(tester, lbPaletteItem('dialog'));
      expect(find.text(kNoDialogInComponent), findsOneWidget);
      await lbTap(tester, find.text('知道了'));
      final doc = await lbSaved(tester, session);
      bool hasDialog(LcNode n) => n.type == 'dialog' || n.children.any(hasDialog);
      expect(hasDialog(doc.component('c1')!.root), isFalse);
      // 不管从哪条路来的：写回定义这一步也拦
      final editing = componentEditingDocument(doc, 'c1')!;
      editing.insert('k3', editing.newNode('dialog'));
      expect(applyComponentEditing(doc, 'c1', editing).error, kNoDialogInComponent);
      expect(hasDialog(doc.component('c1')!.root), isFalse);
    });
  });

  group('页面上用带插槽的组件', () {
    testWidgets('没填的显示默认内容；把页面上的字拖进插槽：默认内容让位，存下来带着插槽名；再拖出来', (tester) async {
      final session = await lbOpen(tester, doc: slotCardPage());
      expect(onCanvas('暂无介绍'), 1, reason: '只有没填的那个实例显示默认内容');
      expect(onCanvas('加入购物车'), 1);
      expect(onCanvas('立即购买'), 1);
      await shot(tester, '10-page-filled-and-default');
      final head = await lbLift(tester, tester.getCenter(lbNode('head')));
      await head.moveTo(tester.getCenter(find.descendant(of: lbKey('lowcode-page'), matching: find.text('暂无介绍'))));
      await tester.pump();
      expect(lbCanvas(tester).dropTarget?.parentId, 'b#default');
      await shot(tester, '11-drag-into-slot');
      await head.up();
      await settle(tester, rounds: 3);
      var doc = await lbSaved(tester, session);
      expect([for (final c in doc.find('b')!.children) '${c.id}@${c.slot}'], ['head@default']);
      expect(onCanvas('暂无介绍'), 0);
      expect(onCanvas('今日推荐'), 1);
      // 填进去的能选中、能改
      await lbTap(tester, lbNode('head'));
      expect(find.widgetWithText(FilledButton, '常用'), findsOneWidget);
      await lbOpenCommon(tester);
      await tester.enterText(find.widgetWithText(TextField, '今日推荐'), '限时特价');
      await settle(tester, rounds: 3);
      doc = await lbSaved(tester, session);
      expect(doc.find('head')!.strProp('text'), '限时特价');
      await shot(tester, '12-slot-content-selected');
    });

    testWidgets('填进去的拖出来放回页面：slot 去掉，实例又显示默认内容', (tester) async {
      final session = await lbOpen(tester, doc: slotCardPage());
      final g = await lbLift(tester, tester.getCenter(lbNode('p1')));
      await g.moveTo(tester.getCenter(lbNode('head')) - const Offset(0, 8));
      await tester.pump();
      expect(lbCanvas(tester).dropTarget?.parentId, 'root');
      await g.up();
      await settle(tester, rounds: 3);
      final doc = await lbSaved(tester, session);
      expect(doc.parentOf('p1')!.id, 'root');
      expect(doc.find('p1')!.slot, isNull);
      expect([for (final c in doc.find('a')!.children) c.id], ['p2', 'b1', 'b2']);
    });

    testWidgets('空插槽（没填、也没有默认内容）是一个能往里拖的空位；组件盒里拖一个按钮进去', (tester) async {
      final json = slotCardJson();
      final root = ((json['components']! as List).single as Map)['root'] as Map;
      ((root['children'] as List)[2]['children'] as List)[0].remove('children');
      final session = await lbOpen(tester, text: jsonEncode(json));
      expect(lbKey('lc-slot-hint-b-footer'), findsOneWidget);
      expect(lbKey('lc-slot-hint-a-footer'), findsNothing, reason: '填了的不出空位');
      await shot(tester, '13-empty-slot-hint');
      await lbOpenPalette(tester);
      await lbTap(tester, lbKey('palette-group-basic'));
      final chip = await lbLift(tester, tester.getCenter(lbPaletteItem('button')));
      await chip.moveTo(tester.getCenter(lbKey('lc-slot-hint-b-footer')));
      await tester.pump();
      expect(lbCanvas(tester).dropTarget?.parentId, 'b#footer');
      await chip.up();
      await settle(tester, rounds: 3);
      final doc = await lbSaved(tester, session);
      expect([for (final c in doc.find('b')!.children) '${c.type}@${c.slot}'], ['button@footer']);
    });

    testWidgets('图层面板写着每样东西在哪个插槽里；删组件的确认框写着有几处填了东西', (tester) async {
      final session = await lbOpen(tester, doc: slotCardPage());
      await lbTap(tester, find.byTooltip('图层'));
      await settle(tester, rounds: 2);
      expect(find.textContaining('在「内容」里'), findsNWidgets(2));
      expect(find.textContaining('在「底部按钮」里'), findsNWidgets(2));
      await shot(tester, '14-layers-slots');
      await tester.tapAt(const Offset(195, 80));
      await settle(tester, rounds: 2);
      await lbTap(tester, find.byTooltip('更多'));
      await lbTap(tester, find.text('自定义组件'));
      await lbTap(tester, find.byTooltip('ProductCard 商品卡片 的更多操作'));
      await lbTap(tester, find.text('删除'));
      expect(find.textContaining('还有 2 处在用它，其中 1 处往它的插槽里填了东西'), findsOneWidget);
      await shot(tester, '15-delete-component-with-fills');
      await lbTap(tester, lbKey('comp-delete-detach'));
      await settle(tester, rounds: 3);
      final doc = await lbSaved(tester, session);
      expect(doc.components, isEmpty);
      expect(doc.find('p1'), isNotNull);
      expect(doc.find('b1'), isNotNull);
    });

    testWidgets('页面里出现插槽占位（别处粘来的、手写的）：画布上标出“只在组件里有用”，里面的内容照常显示', (tester) async {
      await lbOpen(
        tester,
        doc: plainDoc(
          extra: [
            n('stray', 'slot', const {}, [
              n('in', 'text', {'text': '占位里的字'}),
            ]),
          ],
        ),
      );
      expect(find.text('插槽（只在组件里有用）'), findsOneWidget);
      expect(onCanvas('占位里的字'), 1);
      await lbTap(tester, lbNode('in'));
      await lbTap(tester, find.byTooltip('选上一层'));
      expect(find.text('插槽（只在组件里有用）'), findsNWidgets(2), reason: '角标和选中条');
      await shot(tester, '16-stray-slot-on-page');
      // 点“常用”：不崩，只有一句说明（插槽没有可改的属性）。
      await lbOpenCommon(tester);
      expect(lbKey('lc-slot-common-note'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('拆开一个填了内容的实例：填的内容接在原来插槽的位置上，节点还是原来那几个', (tester) async {
      final session = await lbOpen(tester, doc: slotCardPage());
      await lbTap(tester, lbNode('a'));
      await more(tester, '拆开成普通控件');
      await lbTap(tester, find.text('拆开'));
      await settle(tester, rounds: 3);
      final doc = await lbSaved(tester, session);
      expect(doc.find('a')?.type, isNot('component'));
      for (final id in ['p1', 'p2', 'b1', 'b2']) {
        expect(doc.find(id), isNotNull, reason: '$id 不能丢');
        expect(doc.find(id)!.slot, isNull, reason: '拆开以后不再带插槽名');
      }
      bool anySlot(LcNode n) => n.type == 'slot' || n.children.any(anySlot);
      expect(anySlot(doc.root), isFalse, reason: '页面里不留占位节点');
      expect(doc.find('b')!.type, 'component', reason: '另一个实例不动');
      expect(onCanvas('草莓蛋糕'), 1);
    });
  });

  group('第 2 段留下的几处', () {
    testWidgets('存成组件：选中的东西里面有弹窗——拦下并说明', (tester) async {
      final session = await lbOpen(
        tester,
        doc: plainDoc(
          extra: [
            n('box', 'column', const {}, [
              n('t', 'text', {'text': '盒子里的字'}),
              n('dlg', 'dialog', {'title': '提示'}),
            ]),
          ],
        ),
      );
      await lbTap(tester, lbNode('t'));
      await lbTap(tester, find.byTooltip('选上一层'));
      await more(tester, '存成组件');
      expect(find.textContaining('1 个弹窗'), findsOneWidget);
      expect(find.textContaining('先把弹窗拖到外面'), findsOneWidget);
      await shot(tester, '20-save-with-dialog-blocked');
      await lbTap(tester, find.text('知道了'));
      expect((await lbSaved(tester, session)).components.length, 1);
    });

    testWidgets('“禁用”状态：文本这类不能禁用的组件，状态条下面多一句灰字；按钮没有这句', (tester) async {
      await lbOpen(
        tester,
        doc: plainDoc(
          extra: [
            n('btn', 'button', {'text': '按钮'}),
          ],
        ),
        selected: 'hi',
      );
      await lbOpenCommon(tester);
      await lbTap(tester, find.text('样式').last);
      expect(lbKey('lc-state-caveat'), findsNothing);
      await lbTap(tester, lbKey('lc-state-disabled'));
      expect(lbKey('lc-state-caveat'), findsOneWidget);
      expect(find.textContaining('这种组件不能禁用'), findsOneWidget);
      await shot(tester, '21-disabled-caveat');
      await lbTap(tester, lbKey('lc-state-pressed'));
      expect(lbKey('lc-state-caveat'), findsNothing);
      await lbOpen(
        tester,
        doc: plainDoc(
          extra: [
            n('btn', 'button', {'text': '按钮'}),
          ],
        ),
        selected: 'btn',
      );
      await lbOpenCommon(tester);
      await lbTap(tester, find.text('样式').last);
      await lbTap(tester, lbKey('lc-state-disabled'));
      expect(lbKey('lc-state-note'), findsOneWidget);
      expect(lbKey('lc-state-caveat'), findsNothing);
    });

    testWidgets('选中框的尺寸标签不盖住旁边的组件（小按钮上面有一行字；网格里跨两列的格子）', (tester) async {
      Future<void> check(LcDocument doc, String selected, List<String> others, String name) async {
        await lbOpen(tester, doc: doc, selected: selected);
        await settle(tester, rounds: 3);
        final label = tester.getRect(lbKey('lowcode-size-label'));
        for (final id in others) {
          expect(label.overlaps(tester.getRect(lbNode(id))), isFalse, reason: '标签 $label 盖住了 $id ${tester.getRect(lbNode(id))}');
        }
        // 自己的字靠左，几个字宽；标签不许压在这一段上
        final own = tester.getRect(lbNode(selected));
        expect(label.overlaps(Rect.fromLTWH(own.left, own.top, own.width < 80 ? own.width : 80, own.height).deflate(1)), isFalse, reason: '标签 $label 盖住了选中的组件自己的字（$own 的左头）');
        await shot(tester, name);
      }

      final small = LcDocument.parse(
        jsonEncode({
          'version': 3,
          'title': 'S',
          'root': n(
            'root',
            'page',
            {'padding': 16, 'gap': 12},
            [
              n('t1', 'text', {'text': '甲'}),
              n('b1', 'button', {'text': '乙'}),
              n('b2', 'button', {'text': '丙'}),
            ],
          ),
        }),
      );
      await check(small, 'b1', ['t1', 'b2'], '22-size-label-small-button');
      final grid = LcDocument.parse(
        jsonEncode({
          'version': 3,
          'title': 'G',
          'root': n(
            'root',
            'page',
            {'padding': 16},
            [
              {
                'id': 'g',
                'type': 'container',
                'style': {'display': 'grid', 'grid-template-columns': 'repeat(3, 1fr)', 'gap': '8px', 'width': '100%'},
                'children': [
                  {
                    'id': 'c1',
                    'type': 'text',
                    'props': {'text': '第 1 格'},
                    'style': {'grid-column': 'span 2'},
                  },
                  n('c2', 'text', {'text': '第 2 格'}),
                  n('c3', 'text', {'text': '第 3 格'}),
                  n('c4', 'text', {'text': '第 4 格'}),
                ],
              },
            ],
          ),
        }),
      );
      await check(grid, 'c1', ['c2', 'c3', 'c4'], '23-size-label-grid-span');
    });
  });
}
