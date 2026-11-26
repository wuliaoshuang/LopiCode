// 低代码编辑器“走一圈”：把主要界面挨个点开，确认都不出异常；390×844。
//   LOPI_SHOTS=1 LOPI_SHOT_DIR=某目录 flutter test --no-pub test/lowcode_editor_tour_test.dart
// 带 LOPI_SHOTS=1 时把每个界面的截图写到 LOPI_SHOT_DIR（不给就是 docs/screenshots/editor-tour/）。
// 给霜霜圈问题、前后对比用的那套图就是这里出的（改之前的在 da5ae2c 上出，改之后的按第 5 版第 1 期的新布局走）。
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/core/templates.dart';
import 'package:lopicode/lowcode/builder_screen.dart';
import 'package:lopicode/lowcode/canvas_view.dart';
import 'package:lopicode/lowcode/component_model.dart';
import 'package:lopicode/lowcode/logic_expr.dart';
import 'package:lopicode/lowcode/logic_model.dart';
import 'package:lopicode/lowcode/model.dart';
import 'package:lopicode/project_session.dart';
import 'package:lopicode/ui/chat_panels.dart';
import 'package:material_ui/material_ui.dart';

import 'support/harness.dart';

final bool writeShots = Platform.environment['LOPI_SHOTS'] == '1';
final String shotDir = Platform.environment['LOPI_SHOT_DIR'] ?? 'docs/screenshots/editor-tour';
bool fontsLoaded = false;

Future<void> shot(WidgetTester tester, String name) async {
  expect(tester.takeException(), isNull, reason: '$name 渲染时出了异常');
  if (!writeShots || !fontsLoaded) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(shotKey));
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('$shotDir/$name.png');
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(data!.buffer.asUint8List());
  });
}

Future<ProjectSession> openBuilder(WidgetTester tester, LcDocument doc, {ThemeMode mode = ThemeMode.light, String? selected}) async {
  usePhoneViewport(tester);
  late TestEnv env;
  late ProjectSession session;
  await tester.runAsync(() async {
    env = await TestEnv.create();
    final project = await env.services.projects.create('我的小站', ProjectTemplate.lowcode);
    session = ProjectSession(env.services, project);
    File(session.guard.resolve(kLowcodePageFile)).writeAsStringSync(doc.encode());
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

Finder node(String id) => find.byKey(ValueKey('lowcode-node-$id'));
Finder k(String key) => find.byKey(ValueKey(key));

Future<void> select(WidgetTester tester, String id) async {
  await tester.tap(node(id), warnIfMissed: false);
  await settle(tester, rounds: 2);
}

Future<void> tapText(WidgetTester tester, String label) async {
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

Future<void> tapTip(WidgetTester tester, String tip) async {
  await tester.tap(find.byTooltip(tip).last);
  await tester.pumpAndSettle();
}

/// 长按不挪就松手（出菜单）。
Future<void> longPress(WidgetTester tester, String id) async {
  final g = await tester.startGesture(tester.getCenter(node(id)));
  await tester.pump(const Duration(milliseconds: 340));
  await tester.pump();
  await g.up();
  await tester.pumpAndSettle();
}

/// 截图里当“相册照片”用的一张图：两种颜色的斜向渐变，320×200。
Future<Uint8List> tourPhoto(Color a, Color b) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  const size = Size(320, 200);
  canvas.drawRect(Offset.zero & size, Paint()..shader = ui.Gradient.linear(Offset.zero, size.bottomRight(Offset.zero), [a, b]));
  canvas.drawCircle(const Offset(240, 70), 36, Paint()..color = const Color(0x66FFFFFF));
  final image = await recorder.endRecording().toImage(320, 200);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

Future<void> back(WidgetTester tester) async {
  await tester.binding.handlePopRoute();
  await tester.pumpAndSettle();
  await settle(tester, rounds: 2);
}

/// 起始页面（root › n1 标题、n2 说明、n3 卡片 › n4 输入框、n5 “提交”按钮）＋一个自定义组件“问候卡”及它的一个实例 ＋ 一段点击逻辑。
LcDocument tourDoc() {
  final doc = LcDocument.starter('我的小站');
  doc.find('n3')!.style.addAll({'margin-top': '12px', 'margin-bottom': '20px'});
  doc.components.add(
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
  );
  doc.root.children.add(LcNode(id: 'inst', type: 'component', props: {'ref': 'c1'}));
  doc.logic.addVariable('count', type: 'number');
  doc.logic.addHandler('click', target: 'n5')!.body.addAll([
    LcBlock(op: 'changeVar', args: {'name': 'count', 'by': exNum(1)}),
    LcBlock(
      op: 'setProp',
      args: {
        'node': 'n1',
        'prop': 'text',
        'value': exJoin([exText('点了 '), exVar('count'), exText(' 次')]),
      },
    ),
  ]);
  return doc;
}

LcDocument emptyDoc() => LcDocument(
  title: '空页面',
  root: LcNode(id: 'root', type: 'page', props: Map.of(lcSpecs['page']!.defaults)),
);

void main() {
  setUpAll(() async => fontsLoaded = await loadRealFonts());

  testWidgets('画布：空页面', (tester) async {
    await openBuilder(tester, emptyDoc());
    await shot(tester, 'canvas-empty-light');
  });

  testWidgets('画布：放了组件、选中按钮、选中卡片、拖动中（蓝线 / 放进容器 / 删除区）', (tester) async {
    await openBuilder(tester, tourDoc());
    await shot(tester, 'canvas-filled-light');
    await select(tester, 'n5');
    await shot(tester, 'canvas-selected-button-light');
    await select(tester, 'n3');
    await shot(tester, 'canvas-selected-card-light');
    await dragTour(tester, 'light');
  });

  testWidgets('组件盒：常用、分类、搜索、搜不到、收到最矮；屏宽与缩放面板', (tester) async {
    await openBuilder(tester, tourDoc());
    await tester.tap(k('lc-tool-add'));
    await tester.pumpAndSettle();
    await shot(tester, 'palette-recent-light');
    await tester.tap(k('palette-group-layout'));
    await tester.pumpAndSettle();
    await shot(tester, 'palette-layout-light');
    await tester.enterText(k('palette-search'), '按钮');
    await tester.pumpAndSettle();
    await shot(tester, 'palette-search-light');
    await tester.enterText(k('palette-search'), '火箭');
    await tester.pumpAndSettle();
    await shot(tester, 'palette-noresult-light');
    await tapTip(tester, '清空');
    // 点一下添加：加到页面末尾，滚过去、选中、面板收到最矮
    await tester.tap(k('palette-group-recent'));
    await tester.pumpAndSettle();
    await tester.tap(k('palette-item-image'));
    await settle(tester, rounds: 4);
    await shot(tester, 'palette-added-light');
    // 面板收到最矮时“关闭”按钮被裁掉了：先点“添加”拉回来再关
    await tester.tap(k('lc-tool-add'));
    await tester.pumpAndSettle();
    await tapTip(tester, '关闭组件盒');
    await tapTip(tester, '更多');
    await tapText(tester, '屏宽与缩放');
    await shot(tester, 'view-sheet-light');
    await back(tester);
  });

  testWidgets('菜单：选中后的“更多操作”、顶栏“更多”', (tester) async {
    await openBuilder(tester, tourDoc(), selected: 'n5');
    await tapTip(tester, '更多操作');
    await shot(tester, 'menu-node-light');
    await back(tester);
    await tapTip(tester, '更多');
    await shot(tester, 'menu-top-light');
    await back(tester);
  });

  testWidgets('面板：常用、样式各组、取色、原始 CSS、事件、图层', (tester) async {
    await openBuilder(tester, tourDoc(), selected: 'n5');
    await tapText(tester, '常用');
    await shot(tester, 'props-button-light');
    // 预设档展开
    await tester.tap(k('lc-common-variant-outline'));
    await tester.pumpAndSettle();
    await shot(tester, 'common-button-outline-light');
    // 面板开着直接点画布上别的组件：面板跟着换
    await select(tester, 'n3');
    await tester.pumpAndSettle();
    await shot(tester, 'common-card-light');
    await tester.tap(k('lc-preset-padding-more'));
    await tester.pumpAndSettle();
    await shot(tester, 'common-card-preset-open-light');
    await select(tester, 'n1');
    await tester.pumpAndSettle();
    await shot(tester, 'common-text-light');
    await select(tester, 'n4');
    await tester.pumpAndSettle();
    await shot(tester, 'common-input-light');
    tester.widget<CanvasView>(find.byType(CanvasView)).onSelect('root');
    await settle(tester, rounds: 2);
    await tester.pumpAndSettle();
    await shot(tester, 'common-page-light');
    await select(tester, 'n5');
    await tester.pumpAndSettle();
    await tester.tap(k('lc-page-style'));
    await tester.pumpAndSettle();
    await shot(tester, 'style-size-light');
    for (final tab in ['spacing', 'text', 'layout']) {
      await tester.ensureVisible(k('lc-tab-$tab'));
      await tester.pumpAndSettle();
      await tester.tap(k('lc-tab-$tab'));
      await tester.pumpAndSettle();
      await shot(tester, 'style-$tab-light');
    }
    await tester.ensureVisible(k('lc-tab-background'));
    await tester.pumpAndSettle();
    await tester.tap(k('lc-tab-background'));
    await tester.pumpAndSettle();
    await tester.tap(k('lc-color-background-color'));
    await tester.pumpAndSettle();
    await shot(tester, 'style-color-light');
    await back(tester);
    await tester.tap(k('lc-style-css'));
    await tester.pumpAndSettle();
    await shot(tester, 'style-css-light');
    await back(tester);
    await tester.tap(k('lc-page-events'));
    await tester.pumpAndSettle();
    await shot(tester, 'events-light');
    await back(tester);
    expect(k('lc-inspector'), findsNothing);
    await tapTip(tester, '图层');
    await shot(tester, 'layers-light');
    await tester.tap(k('lc-layer-fold-n3'));
    await tester.pumpAndSettle();
    await shot(tester, 'layers-folded-light');
    await tester.tap(k('lc-layer-fold-n3'));
    await tester.pumpAndSettle();
    final g = await tester.startGesture(tester.getCenter(k('lc-layer-n2')));
    await tester.pump(const Duration(milliseconds: 340));
    await g.moveTo(Offset(60, tester.getRect(k('lc-layer-n1')).top + 8));
    await tester.pump();
    await shot(tester, 'layers-dragging-light');
    await g.moveTo(Offset(320, tester.getCenter(k('lc-layer-n3')).dy));
    await tester.pump();
    await shot(tester, 'layers-dragging-into-light');
    await g.cancel();
    await tester.pumpAndSettle();
    await back(tester);
  });

  testWidgets('就地改字、长按菜单、选上一层', (tester) async {
    await openBuilder(tester, tourDoc(), selected: 'n5');
    await select(tester, 'n5');
    await tester.pumpAndSettle();
    await shot(tester, 'inline-edit-button-light');
    await tester.enterText(k('lc-inline-edit'), '立即报名');
    await tester.pump();
    await shot(tester, 'inline-edit-button-typed-light');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settle(tester, rounds: 2);
    await select(tester, 'n1');
    await select(tester, 'n1');
    await tester.pumpAndSettle();
    await shot(tester, 'inline-edit-text-light');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settle(tester, rounds: 2);
    await longPress(tester, 'n5');
    await shot(tester, 'node-menu-light');
    await tapText(tester, '复制');
    await settle(tester, rounds: 2);
    await shot(tester, 'node-menu-copied-light');
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await longPress(tester, 'n1');
    await shot(tester, 'node-menu-paste-light');
    await back(tester);
    await select(tester, 'n5');
    await tester.tap(k('lc-select-parent'));
    await tester.pumpAndSettle();
    await shot(tester, 'select-parent-light');
  });

  testWidgets('图片：从相册选、项目文件', (tester) async {
    final doc = tourDoc();
    doc.insert('root', LcNode(id: 'pic', type: 'image', props: Map.of(lcSpecs['image']!.defaults)..remove('src')), 0);
    final session = await openBuilder(tester, doc, selected: 'pic');
    late Uint8List photo, photo2;
    await tester.runAsync(() async {
      photo = await tourPhoto(const Color(0xFF2E7D6B), const Color(0xFFF2C14E));
      photo2 = await tourPhoto(const Color(0xFF3B5BA9), const Color(0xFFE9967A));
      for (final (name, bytes) in [('images/banner.png', photo2), ('images/logo.png', photo), ('pic/cover.png', photo2)]) {
        File(session.guard.resolve(name))
          ..parent.createSync(recursive: true)
          ..writeAsBytesSync(bytes);
      }
    });
    pickImagesOverride = ({required bool camera}) async => [PickedImage('IMG_20261126.png', photo)];
    addTearDown(() => pickImagesOverride = null);
    await tapText(tester, '常用');
    await shot(tester, 'image-common-empty-light');
    await tester.tap(k('lc-common-src-gallery'));
    await settle(tester, rounds: 8);
    await tester.pumpAndSettle();
    await shot(tester, 'image-from-gallery-light');
    await tester.tap(k('lc-common-src-project'));
    await settle(tester, rounds: 8);
    await tester.pumpAndSettle();
    await shot(tester, 'image-project-sheet-light');
    await back(tester);
  });

  testWidgets('积木逻辑、看代码、导出', (tester) async {
    await openBuilder(tester, tourDoc(), selected: 'n5');
    await tapText(tester, '逻辑');
    await tester.tap(find.byWidgetPredicate((w) => w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith('lc-event-')).first);
    await tester.pumpAndSettle();
    await settle(tester, rounds: 2);
    await shot(tester, 'logic-light');
    await tester.tap(k('bk-code'));
    await tester.pumpAndSettle();
    await shot(tester, 'logic-code-light');
    await back(tester);
    await back(tester);
    await back(tester); // 收起合一面板
    await tapTip(tester, '更多');
    await tapText(tester, '导出 Vue / React');
    await settle(tester, rounds: 2);
    await shot(tester, 'export-framework-light');
    await back(tester);
    await tapTip(tester, '更多');
    await tapText(tester, '导出 Flutter 代码');
    await settle(tester, rounds: 3);
    await tester.pumpAndSettle();
    await shot(tester, 'export-flutter-light');
    await back(tester);
  });

  testWidgets('自定义组件：清单、实例属性、编辑页', (tester) async {
    await openBuilder(tester, tourDoc(), selected: 'inst');
    await shot(tester, 'component-instance-light');
    await tapTip(tester, '更多');
    await tapText(tester, '自定义组件');
    await shot(tester, 'component-sheet-light');
    await back(tester);
    await tapText(tester, '常用');
    await shot(tester, 'component-instance-props-light');
    await back(tester);
    await tapTip(tester, '更多操作');
    await tapText(tester, '编辑组件');
    await settle(tester, rounds: 2);
    await select(tester, 'k3');
    await shot(tester, 'component-editor-light');
    await back(tester);
  });

  testWidgets('深色：画布、选中、组件盒、拖动、样式面板', (tester) async {
    await openBuilder(tester, tourDoc(), mode: ThemeMode.dark);
    await shot(tester, 'canvas-filled-dark');
    await select(tester, 'n5');
    await shot(tester, 'canvas-selected-button-dark');
    await tapText(tester, '常用');
    await shot(tester, 'common-button-dark');
    await tester.tap(k('lc-page-style'));
    await tester.pumpAndSettle();
    await shot(tester, 'style-size-dark');
    await back(tester);
    await select(tester, 'n5');
    await tester.pumpAndSettle();
    await shot(tester, 'inline-edit-button-dark');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settle(tester, rounds: 2);
    await longPress(tester, 'n5');
    await shot(tester, 'node-menu-dark');
    await back(tester);
    await tapTip(tester, '图层');
    await shot(tester, 'layers-dark');
    await back(tester);
    await select(tester, 'n3');
    await shot(tester, 'canvas-selected-card-dark');
    await tester.tap(k('lc-tool-add'));
    await tester.pumpAndSettle();
    await shot(tester, 'palette-recent-dark');
    await tester.enterText(k('palette-search'), '按钮');
    await tester.pumpAndSettle();
    await shot(tester, 'palette-search-dark');
    await tapTip(tester, '清空');
    await tapTip(tester, '关闭组件盒');
    await dragTour(tester, 'dark');
  });
}

/// 长按画布上的标题拖起来：拖到卡片下面（蓝线）→ 在卡片上停住（放进里面）→ 拖到底部删除区。最后取消，什么都不改。
Future<void> dragTour(WidgetTester tester, String suffix) async {
  final card = tester.getRect(node('n3'));
  final gesture = await tester.startGesture(tester.getCenter(node('n1')));
  await tester.pump(const Duration(milliseconds: 320));
  await tester.pump();
  await gesture.moveTo(Offset(150, card.bottom + 6));
  await tester.pump();
  await shot(tester, 'canvas-dragging-$suffix');
  await gesture.moveTo(Offset(150, (tester.getRect(node('n4')).bottom + tester.getRect(node('n5')).top) / 2));
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump();
  await shot(tester, 'canvas-dragging-inside-$suffix');
  await gesture.moveTo(tester.getCenter(k('lc-drop-zone')));
  await tester.pump();
  await shot(tester, 'canvas-dragging-delete-$suffix');
  await gesture.cancel();
  await settle(tester, rounds: 2);
}
