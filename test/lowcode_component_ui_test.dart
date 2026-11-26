// 自定义组件（E 块）的界面测试，390×844。
// 设置环境变量 LOPI_SHOTS=1 时把截图写到 docs/screenshots/lc-comp-*.png。
//   LOPI_SHOTS=1 flutter test --no-pub test/lowcode_component_ui_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/core/templates.dart';
import 'package:lopicode/lowcode/builder_screen.dart';
import 'package:lopicode/lowcode/canvas_component_widgets.dart';
import 'package:lopicode/lowcode/canvas_view.dart';
import 'package:lopicode/lowcode/component_model.dart';
import 'package:lopicode/lowcode/model.dart';
import 'package:lopicode/lowcode/palette_widgets.dart';
import 'package:lopicode/project_session.dart';
import 'package:material_ui/material_ui.dart';

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
    final file = File('docs/screenshots/$name.png');
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(data!.buffer.asUint8List());
  });
}

/// 建一个低代码项目并打开搭建页。[doc] 不给就是模板自带的起始页面
/// （节点 id：root › n1 标题、n2 说明、n3 卡片 › n4 输入框、n5 “提交”按钮）。
Future<ProjectSession> openBuilder(WidgetTester tester, {LcDocument? doc, ThemeMode mode = ThemeMode.light, String? selected}) async {
  usePhoneViewport(tester);
  late TestEnv env;
  late ProjectSession session;
  await tester.runAsync(() async {
    env = await TestEnv.create();
    final project = await env.services.projects.create('我的小站', ProjectTemplate.lowcode);
    session = ProjectSession(env.services, project);
    if (doc != null) File(session.guard.resolve(kLowcodePageFile)).writeAsStringSync(doc.encode());
  });
  addTearDown(() async {
    session.dispose();
    await env.dispose();
  });
  await tester.pumpWidget(
    appFor(
      env,
      BuilderScreen(session: session, initialSelection: selected),
      mode: mode,
      font: fontsLoaded ? kTestFont : null,
    ),
  );
  await settle(tester, rounds: 6);
  return session;
}

Future<LcDocument> savedDoc(WidgetTester tester, ProjectSession session) async {
  // 搭建页改完停手 0.4 秒才存：先把这段时间走完。
  await waitLowcodeSaved(tester);
  late LcDocument doc;
  await tester.runAsync(() async => doc = LcDocument.parse(File(session.guard.resolve(kLowcodePageFile)).readAsStringSync()));
  return doc;
}

Finder node(String id) => find.byKey(ValueKey('lowcode-node-$id'));
Finder key(String k) => find.byKey(ValueKey(k));
bool undoEnabled(WidgetTester tester) => tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.undo).first).onPressed != null;

Future<void> select(WidgetTester tester, String id) async {
  await tester.tap(node(id));
  await settle(tester, rounds: 2);
}

/// 选中一个“正中间被旁边选中框的拖柄盖住”的组件：拖柄能按的范围（44）比看到的大，紧挨着的小组件的正中间会落在它里面。
/// 这时点一下走的是拖柄的“点穿”（CanvasSelectionOverlay.onTapThrough → 选中手指下面的组件），不是组件自己接的点击——
/// 所以先确认点到的确实是拖柄，再点，再确认选中的确实换成了 [id]（以前直接 tap(node(id))，测试框架会警告“点击可能没点中”）。
Future<void> selectUnderHandle(WidgetTester tester, String id) async {
  final at = tester.getCenter(node(id));
  final handles = find.byWidgetPredicate((w) => w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith('lowcode-handle-'));
  final hit = tester.hitTestOnBinding(at).path.map((e) => e.target).toSet();
  expect(handles.evaluate().any((e) => hit.contains(e.renderObject)), isTrue, reason: '$id 的正中间应该落在旁边选中框拖柄能按的范围里');
  await tester.tapAt(at);
  await settle(tester, rounds: 2);
  expect(tester.widget<CanvasView>(find.byType(CanvasView).last).selected, id, reason: '点在拖柄上没挪＝选中它下面的组件');
}

/// 在组件盒里点一个组件（[itemKey]：内置的是类型名，自定义组件是 `component:<id>`）。组件盒没开 / 收着就先点“添加”。
Future<void> paletteAdd(WidgetTester tester, String itemKey) async {
  final panel = find.byType(PalettePanel);
  if (panel.evaluate().isEmpty || tester.state<PalettePanelState>(panel).collapsed) {
    await tester.tap(key('lc-tool-add').last);
    await tester.pumpAndSettle();
  }
  final group = itemKey.startsWith('component:') ? 'mine' : 'recent';
  await tester.tap(key('palette-group-$group'));
  await tester.pumpAndSettle();
  await tester.tap(key('palette-item-$itemKey'));
  await tester.pumpAndSettle();
}

Future<void> tapText(WidgetTester tester, String label) async {
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

Future<void> tapKey(WidgetTester tester, String k) async {
  await tester.ensureVisible(key(k));
  await tester.pumpAndSettle();
  await tester.tap(key(k));
  await tester.pumpAndSettle();
}

Future<void> moreAction(WidgetTester tester, String label) async {
  await tester.tap(find.byTooltip('更多操作'));
  await tester.pumpAndSettle();
  await tapText(tester, label);
  await settle(tester, rounds: 2);
}

Future<void> openComponentSheet(WidgetTester tester) async {
  await tester.tap(find.byTooltip('更多'));
  await tester.pumpAndSettle();
  await tapText(tester, '自定义组件');
}

/// 组件清单里某个组件行尾“⋮”里的一项。
Future<void> componentMenu(WidgetTester tester, String name, String label) async {
  await tester.tap(find.byTooltip('$name 的更多操作'));
  await tester.pumpAndSettle();
  await tapText(tester, label);
}

/// “编辑属性”面板里某个属性行尾的“⋮”（面板可能滚到了下面，先滚回来）。
Future<void> propMenu(WidgetTester tester, String name) async {
  final list = find.ancestor(of: key('comp-prop-add'), matching: find.byType(Scrollable));
  if (find.byTooltip('$name 的更多操作').evaluate().isEmpty) {
    await tester.drag(list.first, const Offset(0, 600));
    await tester.pumpAndSettle();
  }
  await tester.ensureVisible(find.byTooltip('$name 的更多操作'));
  await tester.pumpAndSettle();
  await tester.tap(find.byTooltip('$name 的更多操作'));
  await tester.pumpAndSettle();
}

Future<void> closeSheet(WidgetTester tester) async {
  await tester.binding.handlePopRoute();
  await tester.pumpAndSettle();
  await settle(tester, rounds: 2);
}

/// 画布上（不含面板、对话框里）某段文字出现了几次。
int onCanvas(WidgetTester tester, String text) => find.descendant(of: find.byKey(const ValueKey('lowcode-page')), matching: find.text(text)).evaluate().length;

/// “问候卡”组件 c1：卡片 k1 › 文本 k2（text 接 title）、按钮 k3（bg 接 tint）。页面里放两个实例 a、b。
LcDocument cardDoc({bool withInstances = true}) => LcDocument(
  title: '组件演示',
  root: LcNode(
    id: 'root',
    type: 'page',
    props: Map.of(lcSpecs['page']!.defaults),
    children: [
      LcNode(id: 'n1', type: 'text', props: {'text': '页面标题', 'fontSize': 20, 'bold': true}),
      if (withInstances) ...[
        LcNode(id: 'a', type: 'component', props: {'ref': 'c1'}),
        LcNode(id: 'b', type: 'component', props: {'ref': 'c1'}),
      ],
    ],
  ),
  components: [
    LcComponentDef(
      id: 'c1',
      name: '问候卡',
      props: [
        LcComponentProp(name: 'title', defaultValue: '你好'),
        LcComponentProp(name: 'tint', type: 'color', defaultValue: '#058654'),
      ],
      root: LcNode(
        id: 'k1',
        type: 'card',
        props: Map.of(lcSpecs['card']!.defaults),
        children: [
          LcNode(id: 'k2', type: 'text', props: {'text': '原文', 'fontSize': 16}, bind: {'text': 'title'}),
          LcNode(id: 'k3', type: 'button', props: {...lcSpecs['button']!.defaults, 'text': '去看看'}, bind: {'bg': 'tint'}),
        ],
      ),
    ),
  ],
);

void main() {
  setUpAll(() async => fontsLoaded = await loadRealFonts());

  testWidgets('存成组件：画布上变成实例、外观不变；点里面选中的是实例；撤销一步回到之前', (tester) async {
    final session = await openBuilder(tester);
    await select(tester, 'n3');
    final before = tester.getRect(node('n3'));
    final buttonBefore = tester.getRect(find.text('提交'));
    expect(undoEnabled(tester), isFalse);

    await moreAction(tester, '存成组件');
    expect(find.text('存成组件'), findsOneWidget);
    // 名字不合规矩：不关对话框，就地说明。
    await tester.enterText(key('comp-ask-text'), '   ');
    await tapText(tester, '完成');
    expect(find.text('组件名不能为空'), findsOneWidget);
    await tester.enterText(key('comp-ask-text'), '表单卡');
    await tapText(tester, '完成');
    await settle(tester, rounds: 2);

    var doc = await savedDoc(tester, session);
    expect(doc.components.single.name, '表单卡');
    expect(doc.find('n3')!.type, 'component');
    expect(doc.find('n5'), isNull);
    // 外观不变：整块和里面按钮的位置大小都和原来一样。
    expect(tester.getRect(node('n3')), before);
    expect(tester.getRect(find.text('提交')), buttonBefore);
    // 里面的控件不能单独选中：没有它们自己的点选区，点按钮选中的是实例。
    expect(node('n3__k2'), findsNothing);
    expect(node('n3__k3'), findsNothing);
    await select(tester, 'n1');
    await tester.tapAt(tester.getCenter(find.text('提交')));
    await settle(tester, rounds: 2);
    expect(
      find.descendant(of: find.byType(BuilderScreen), matching: find.text('表单卡')),
      findsOneWidget,
      reason: '选中操作条上显示的是组件名',
    );
    await shot(tester, 'lc-comp-saved-light');

    // 一次操作一条撤销：撤销一步就回到存成组件之前。
    expect(undoEnabled(tester), isTrue);
    await tester.tap(find.byTooltip('撤销'));
    await settle(tester, rounds: 2);
    expect(undoEnabled(tester), isFalse);
    doc = await savedDoc(tester, session);
    expect(doc.components, isEmpty);
    expect(doc.find('n3')!.type, 'card');
    expect(doc.find('n5')!.type, 'button');
    expect(tester.getRect(node('n3')), before);
  });

  testWidgets('有积木逻辑在用的控件：存不了，说明原因，文档不变', (tester) async {
    final doc = LcDocument.starter('小站');
    doc.logic.handlers.add(LcDocument.parse('{"root":{"type":"page"},"logic":{"handlers":[{"id":"h1","event":"click","target":"n5","body":[]}]}}').logic.handlers.single);
    final session = await openBuilder(tester, doc: doc);
    await select(tester, 'n3');
    await moreAction(tester, '存成组件');
    expect(find.textContaining('积木逻辑在用'), findsOneWidget);
    await tapText(tester, '知道了');
    expect((await savedDoc(tester, session)).components, isEmpty);
    // 面板里的按钮也是灰的，并写着原因。
    await openComponentSheet(tester);
    expect(tester.widget<FilledButton>(find.ancestor(of: find.textContaining('存成组件'), matching: find.bySubtype<FilledButton>()).first).onPressed, isNull);
    expect(find.textContaining('积木逻辑在用'), findsOneWidget);
    await shot(tester, 'lc-comp-sheet-blocked-light');
  });

  testWidgets('组件面板：空状态；从面板存成组件；再插入一个实例；组件栏点一下也能加', (tester) async {
    final session = await openBuilder(tester);
    await openComponentSheet(tester);
    expect(find.text('还没有自定义组件'), findsOneWidget);
    expect(find.textContaining('更多操作 → 存成组件'), findsOneWidget);
    expect(key('comp-save-selected'), findsNothing, reason: '什么都没选：不出现“存成组件”按钮');
    await shot(tester, 'lc-comp-sheet-empty-light');
    await closeSheet(tester);

    await select(tester, 'n3');
    await openComponentSheet(tester);
    expect(find.text('把选中的卡片存成组件'), findsOneWidget);
    await tapKey(tester, 'comp-save-selected');
    await tester.enterText(key('comp-ask-text'), '表单卡');
    await tapText(tester, '完成');
    await settle(tester, rounds: 2);
    expect(find.text('自定义组件'), findsNothing, reason: '存完面板自己关掉');
    expect(onCanvas(tester, '提交'), 1);

    // 从面板插入：选中的是实例（不是容器），新实例加在它后面并被选中。
    await openComponentSheet(tester);
    expect(find.text('用了 1 次 · 没有可配置属性'), findsOneWidget);
    await tapKey(tester, 'comp-insert-c1');
    await settle(tester, rounds: 2);
    var doc = await savedDoc(tester, session);
    expect(doc.root.children.map((n) => n.type), ['text', 'text', 'component', 'component']);
    expect(onCanvas(tester, '提交'), 2);

    // 组件盒的“我的”里有它，点一下再加一个。
    await paletteAdd(tester, 'component:c1');
    await settle(tester, rounds: 2);
    doc = await savedDoc(tester, session);
    expect(doc.root.children.where((n) => n.type == 'component').length, 3);
    expect(doc.root.children.where((n) => n.type == 'component').every((n) => n.props['ref'] == 'c1'), isTrue);
    expect(onCanvas(tester, '提交'), 3);
    await shot(tester, 'lc-comp-palette-light');
  });

  testWidgets('改属性默认值：两个实例都变；改一个实例的值只变它；恢复默认', (tester) async {
    final session = await openBuilder(tester, doc: cardDoc());
    expect(onCanvas(tester, '你好'), 2);
    expect(onCanvas(tester, '原文'), 0, reason: '接了属性的文字显示属性的值，不是控件自己的');

    await openComponentSheet(tester);
    expect(find.text('用了 2 次 · 2 个可配置属性'), findsOneWidget);
    await shot(tester, 'lc-comp-sheet-light');
    await componentMenu(tester, '问候卡', '编辑属性');
    expect(find.text('「问候卡」的属性'), findsOneWidget);
    await shot(tester, 'lc-comp-props-light');
    await tapKey(tester, 'comp-prop-title');
    await tester.enterText(find.descendant(of: key('comp-ask-value'), matching: find.byType(TextField)), '大家好');
    await tapText(tester, '保存');
    await settle(tester, rounds: 2);
    expect(find.text('文字 · 默认 “大家好”'), findsOneWidget);
    await closeSheet(tester);
    await closeSheet(tester);
    expect(onCanvas(tester, '大家好'), 2);
    expect((await savedDoc(tester, session)).component('c1')!.prop('title')!.defaultValue, '大家好');

    // 只改实例 a 传的值。
    await select(tester, 'a');
    await tapText(tester, '常用');
    expect(tester.widget<Text>(key('lc-inspector-title')).data, '问候卡');
    expect(key('comp-reset-title'), findsNothing);
    await tester.enterText(find.descendant(of: key('comp-value-title'), matching: find.byType(TextField)), '只有我');
    await settle(tester, rounds: 2);
    expect(onCanvas(tester, '只有我'), 1);
    expect(onCanvas(tester, '大家好'), 1);
    var doc = await savedDoc(tester, session);
    expect(doc.find('a')!.props['values'], {'title': '只有我'});
    expect(doc.find('b')!.props.containsKey('values'), isFalse);
    // 颜色：点一个色块。
    await tapKey(tester, 'comp-swatch-#DC3545');
    await settle(tester, rounds: 2);
    expect((await savedDoc(tester, session)).find('a')!.props['values'], {'title': '只有我', 'tint': '#DC3545'});
    await shot(tester, 'lc-comp-instance-props-light');

    await tapKey(tester, 'comp-reset-title');
    await settle(tester, rounds: 2);
    expect(onCanvas(tester, '大家好'), 2);
    doc = await savedDoc(tester, session);
    expect(doc.find('a')!.props['values'], {'tint': '#DC3545'});
    expect(tester.widget<TextField>(find.descendant(of: key('comp-value-title'), matching: find.byType(TextField))).controller!.text, '大家好');
  });

  testWidgets('编辑属性：添加属性、接到控件上、改名、删除（要确认）；每步一条撤销', (tester) async {
    final session = await openBuilder(tester, doc: cardDoc());
    await openComponentSheet(tester);
    await componentMenu(tester, '问候卡', '编辑属性');

    await tapKey(tester, 'comp-prop-add');
    await tester.enterText(key('comp-ask-text'), '按钮字');
    await tapText(tester, '下一步');
    expect(find.textContaining('只能用英文字母'), findsOneWidget);
    await tester.enterText(key('comp-ask-text'), 'label');
    await tapText(tester, '下一步');
    await tapText(tester, '文字');
    await settle(tester, rounds: 2);
    var doc = await savedDoc(tester, session);
    expect(doc.component('c1')!.prop('label')!.type, 'text');

    // 把按钮的文字接到 label 上。
    await tapKey(tester, 'comp-bind-k3-text');
    expect(find.text('tint · 颜色'), findsOneWidget, reason: '文字什么类型的属性都能接');
    await tapText(tester, 'label · 文字');
    await settle(tester, rounds: 2);
    doc = await savedDoc(tester, session);
    expect(doc.component('c1')!.root.children[1].bind, {'bg': 'tint', 'text': 'label'});

    // 背景色只能接颜色类型的属性。
    await tapKey(tester, 'comp-bind-k1-bg');
    expect(find.text('tint · 颜色'), findsOneWidget);
    expect(find.text('label · 文字'), findsNothing);
    await tapText(tester, '不接（现在这样）');

    // 改名：绑定跟着改。
    await propMenu(tester, 'label');
    await tapText(tester, '改名');
    await tester.enterText(key('comp-ask-text'), 'cta');
    await tapText(tester, '保存');
    await settle(tester, rounds: 2);
    doc = await savedDoc(tester, session);
    expect(doc.component('c1')!.root.children[1].bind['text'], 'cta');

    // 删除要确认。
    await propMenu(tester, 'cta');
    await tapText(tester, '删除');
    expect(find.text('删除属性 cta'), findsOneWidget);
    await tapText(tester, '取消');
    expect((await savedDoc(tester, session)).component('c1')!.prop('cta'), isNotNull);
    await propMenu(tester, 'cta');
    await tapText(tester, '删除');
    await tapText(tester, '删除');
    await settle(tester, rounds: 2);
    doc = await savedDoc(tester, session);
    expect(doc.component('c1')!.prop('cta'), isNull);
    expect(doc.component('c1')!.root.children[1].bind, {'bg': 'tint'});
    await closeSheet(tester);
    await closeSheet(tester);

    // 做了 4 次修改（加、接、改名、删）：撤销 4 步正好回到最初。
    for (var i = 0; i < 4; i++) {
      expect(undoEnabled(tester), isTrue, reason: '第 ${i + 1} 步撤销');
      await tester.tap(find.byTooltip('撤销'));
      await settle(tester, rounds: 2);
    }
    expect(undoEnabled(tester), isFalse);
    expect((await savedDoc(tester, session)).encode(), cardDoc().encode());
  });

  testWidgets('删除有实例的组件：先问怎么办；拆成普通控件 / 连实例一起删 / 取消', (tester) async {
    final session = await openBuilder(tester, doc: cardDoc());
    await openComponentSheet(tester);
    await componentMenu(tester, '问候卡', '删除');
    expect(find.text('还有 2 处在用它。用到的地方怎么办？'), findsOneWidget);
    await shot(tester, 'lc-comp-delete-light');
    await tapText(tester, '取消');
    expect((await savedDoc(tester, session)).components.length, 1);

    await componentMenu(tester, '问候卡', '删除');
    await tapKey(tester, 'comp-delete-detach');
    await settle(tester, rounds: 2);
    var doc = await savedDoc(tester, session);
    expect(doc.components, isEmpty);
    expect(doc.find('a')!.type, 'card');
    expect(doc.find('b')!.type, 'card');
    expect(find.text('还没有自定义组件'), findsOneWidget);
    await closeSheet(tester);
    expect(onCanvas(tester, '你好'), 2, reason: '拆开以后内容还在');
    expect(tester.takeException(), isNull);

    // 撤销一步：组件和两个实例都回来。
    await tester.tap(find.byTooltip('撤销'));
    await settle(tester, rounds: 2);
    doc = await savedDoc(tester, session);
    expect(doc.components.length, 1);
    expect(doc.find('a')!.type, 'component');

    await openComponentSheet(tester);
    await componentMenu(tester, '问候卡', '删除');
    await tapKey(tester, 'comp-delete-remove');
    await settle(tester, rounds: 2);
    doc = await savedDoc(tester, session);
    expect(doc.components, isEmpty);
    expect(doc.root.children.map((n) => n.id), ['n1']);
    await closeSheet(tester);
    expect(onCanvas(tester, '你好'), 0);
  });

  testWidgets('没人用的组件：确认后直接删；组件改名（重名拒绝）', (tester) async {
    final session = await openBuilder(tester, doc: cardDoc(withInstances: false));
    await openComponentSheet(tester);
    await componentMenu(tester, '问候卡', '改名');
    await tester.enterText(key('comp-ask-text'), '字' * 31);
    await tapText(tester, '保存');
    expect(find.text('组件名最多 30 个字'), findsOneWidget);
    await tester.enterText(key('comp-ask-text'), '招呼卡');
    await tapText(tester, '保存');
    await settle(tester, rounds: 2);
    expect((await savedDoc(tester, session)).components.single.name, '招呼卡');
    await componentMenu(tester, '招呼卡', '删除');
    expect(find.textContaining('没有地方在用它'), findsOneWidget);
    await tapText(tester, '删除');
    await settle(tester, rounds: 2);
    expect((await savedDoc(tester, session)).components, isEmpty);
  });

  testWidgets('拆开成普通控件：要确认；拆完里面的控件可以单独选中', (tester) async {
    final session = await openBuilder(tester, doc: cardDoc());
    await select(tester, 'a');
    await moreAction(tester, '拆开成普通控件');
    expect(find.textContaining('不再跟着组件「问候卡」一起变'), findsOneWidget);
    await tapText(tester, '取消');
    expect((await savedDoc(tester, session)).find('a')!.type, 'component');
    await moreAction(tester, '拆开成普通控件');
    await tapText(tester, '拆开');
    await settle(tester, rounds: 2);
    final doc = await savedDoc(tester, session);
    expect(doc.find('a')!.type, 'card');
    expect(doc.find('b')!.type, 'component');
    final inner = doc.find('a')!.children.first.id;
    await select(tester, inner);
    expect(find.descendant(of: find.byType(BuilderScreen), matching: find.text('文本')), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('编辑组件内容：进编辑页加一个控件、改文字，回来两个实例都变；主页面撤销能退回', (tester) async {
    final session = await openBuilder(tester, doc: cardDoc());
    await select(tester, 'a');
    await moreAction(tester, '编辑组件');
    expect(find.text('编辑组件'), findsOneWidget);
    expect(find.text('完成'), findsOneWidget);
    expect(find.text('逻辑'), findsNothing, reason: '组件里的控件不支持积木逻辑');
    // 画布上是组件的内容；接了属性的文字在这里显示控件自己的内容。
    expect(node('k1'), findsOneWidget);
    expect(node('k2'), findsOneWidget);

    // 最外层：不能删、不能移动。“更多操作”里只有一项“把内容设成插槽”（第 3 期第 3 段加的），没有删除、移动、复制。
    await select(tester, 'k1');
    expect(find.text('卡片（最外层）'), findsOneWidget);
    await tester.tap(find.byTooltip('更多操作'));
    await tester.pumpAndSettle();
    expect(find.byType(PopupMenuItem<String>), findsNWidgets(2), reason: '设成插槽、粘贴到里面（灰的）');
    expect(find.text('把内容设成插槽'), findsOneWidget);
    for (final gone in ['删除', '上移', '下移', '复制', '重复一份']) {
      expect(find.text(gone), findsNothing, reason: gone);
    }
    await tester.tapAt(const Offset(195, 60));
    await tester.pumpAndSettle();
    // 选中最外层（容器）时点组件盒里的“文本”：加进它里面。
    await paletteAdd(tester, 'text');
    await settle(tester, rounds: 2);
    var doc = await savedDoc(tester, session);
    expect(doc.component('c1')!.root.children.map((n) => n.type), ['text', 'button', 'text']);
    await shot(tester, 'lc-comp-editor-light');

    // 改按钮的文字（刚加的文本还选中着，它的拖柄盖着按钮的正中间）。
    await selectUnderHandle(tester, 'k3');
    await tapText(tester, '常用');
    await tester.enterText(find.widgetWithText(TextField, '去看看'), '马上去');
    await settle(tester, rounds: 2);
    await closeSheet(tester);
    // 里面的控件可以删（按钮还选中着，它的拖柄盖着上面那行文本的正中间）。
    await selectUnderHandle(tester, 'k2');
    expect(find.byTooltip('更多操作'), findsOneWidget);
    // 最外层现在也有“更多操作”了（设成插槽的入口），所以点开看一眼：里面的控件的菜单里有“删除”。
    await tester.tap(find.byTooltip('更多操作'));
    await tester.pumpAndSettle();
    expect(find.text('删除'), findsOneWidget);
    await tester.tapAt(const Offset(195, 60));
    await tester.pumpAndSettle();

    await tapKey(tester, 'comp-editor-done');
    await settle(tester, rounds: 2);
    expect(find.text('编辑组件'), findsNothing, reason: '回到了搭建页');
    expect(find.byType(BuilderScreen), findsOneWidget);
    expect(onCanvas(tester, '马上去'), 2);
    expect(onCanvas(tester, '一段文本'), 2);
    doc = await savedDoc(tester, session);
    expect(doc.component('c1')!.id, 'c1');
    expect(doc.component('c1')!.props.length, 2);
    expect(doc.component('c1')!.root.children[0].bind, {'text': 'title'}, reason: '原来的绑定还在');
    expect(doc.find('a')!.type, 'component');

    // 编辑页里做了两次修改：主页面撤销两步回到最初。
    await tester.tap(find.byTooltip('撤销'));
    await settle(tester, rounds: 2);
    expect(onCanvas(tester, '去看看'), 2);
    await tester.tap(find.byTooltip('撤销'));
    await settle(tester, rounds: 2);
    expect(undoEnabled(tester), isFalse);
    expect((await savedDoc(tester, session)).encode(), cardDoc().encode());
  });

  testWidgets('编辑组件内容：最外层旁边放不了别的控件；编辑页自己的撤销', (tester) async {
    final doc = cardDoc();
    // 最外层换成一个不是容器的控件。
    doc.components.single.root = LcNode(id: 'k1', type: 'text', props: {'text': '只有一行字'});
    final session = await openBuilder(tester, doc: doc);
    await openComponentSheet(tester);
    await componentMenu(tester, '问候卡', '编辑内容');
    await paletteAdd(tester, 'button');
    expect(find.textContaining('组件最外层只能有一个控件'), findsOneWidget);
    await tapText(tester, '知道了');
    expect((await savedDoc(tester, session)).component('c1')!.root.children, isEmpty);

    await select(tester, 'k1');
    await tapText(tester, '常用');
    await tester.enterText(find.widgetWithText(TextField, '只有一行字'), '改过了');
    await settle(tester, rounds: 2);
    await closeSheet(tester);
    expect((await savedDoc(tester, session)).component('c1')!.root.props['text'], '改过了');
    await tester.tap(find.byTooltip('撤销'));
    await settle(tester, rounds: 2);
    expect((await savedDoc(tester, session)).component('c1')!.root.props['text'], '只有一行字');
    await tester.tap(find.byTooltip('重做'));
    await settle(tester, rounds: 2);
    expect((await savedDoc(tester, session)).component('c1')!.root.props['text'], '改过了');
    expect(tester.takeException(), isNull);
  });

  testWidgets('定义不存在 / 循环：画布画占位不崩；属性面板说明；拖动时实例里没有插入位', (tester) async {
    final doc = cardDoc();
    doc.root.children.add(LcNode(id: 'gone', type: 'component', props: {'ref': 'c9'}));
    doc.components.add(
      LcComponentDef(
        id: 'c2',
        name: '绕圈',
        root: LcNode(
          id: 'k1',
          type: 'column',
          children: [
            LcNode(id: 'k2', type: 'component', props: {'ref': 'c2'}),
          ],
        ),
      ),
    );
    doc.root.children.add(LcNode(id: 'loop', type: 'component', props: {'ref': 'c2'}));
    await openBuilder(tester, doc: doc);
    expect(tester.takeException(), isNull);
    expect(find.byType(CanvasComponentPlaceholder), findsNWidgets(2));
    expect(find.text('组件不存在'), findsOneWidget);
    expect(find.textContaining('展开不了'), findsOneWidget);
    await shot(tester, 'lc-comp-missing-light');

    await select(tester, 'gone');
    await tapText(tester, '常用');
    expect(find.textContaining('定义已经不存在了'), findsOneWidget);
    await closeSheet(tester);

    // 长按拖动一个普通控件到实例（卡片 a 是容器）上面停住：落点始终在页面里，放不进实例里面。
    final gesture = await tester.startGesture(tester.getCenter(node('n1')));
    await tester.pump(const Duration(milliseconds: 320));
    await gesture.moveTo(tester.getCenter(node('a')));
    await tester.pump();
    final canvas = tester.state<CanvasViewState>(find.byType(CanvasView));
    expect(canvas.dropTarget?.parentId, 'root');
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.moveBy(const Offset(0, 2));
    await tester.pump();
    expect(canvas.dropTarget?.parentId, 'root', reason: '停再久也不会放进实例里面');
    await gesture.up();
    await settle(tester, rounds: 2);
    expect(tester.takeException(), isNull);
  });

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    final tag = mode == ThemeMode.dark ? 'dark' : 'light';
    testWidgets('截图（$tag）：面板、属性、实例属性、编辑页在 390×844 上没有溢出', (tester) async {
      final doc = cardDoc();
      doc.find('a')!.props['values'] = {'title': '早上好', 'tint': '#3B6FE0'};
      await openBuilder(tester, doc: doc, mode: mode, selected: 'a');
      await shot(tester, 'lc-comp-canvas-$tag');
      await openComponentSheet(tester);
      await shot(tester, 'lc-comp-sheet-$tag');
      await componentMenu(tester, '问候卡', '编辑属性');
      await shot(tester, 'lc-comp-props-$tag');
      await tapKey(tester, 'comp-prop-tint');
      await shot(tester, 'lc-comp-default-color-$tag');
      await tapText(tester, '取消');
      await closeSheet(tester);
      await closeSheet(tester);
      await tapText(tester, '常用');
      await shot(tester, 'lc-comp-instance-props-$tag');
      await closeSheet(tester);
      await moreAction(tester, '编辑组件');
      await select(tester, 'k3');
      await shot(tester, 'lc-comp-editor-$tag');
      expect(tester.takeException(), isNull);
    });
  }
}
