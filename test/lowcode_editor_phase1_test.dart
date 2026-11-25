// 低代码编辑器第 5 版第 1 期（布局与手势）的界面测试，390×844。
// 新布局（工具条 + 选中条）、组件盒（搜索 / 分类 / 常用）、长按 280ms + 震动、蓝线落点（页面不动、边缘自动滚、删除区）、
// 拖柄 44 + 标签不遮挡、点一下添加后滚过去、保存 / 导出失败写出原因、性能三处。
// 设置 LOPI_SHOTS=1 时把截图写到 docs/screenshots/lc-editor-*.png。
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/core/safe_file.dart';
import 'package:lopicode/core/templates.dart';
import 'package:lopicode/lowcode/builder_screen.dart';
import 'package:lopicode/lowcode/canvas_drag_widgets.dart';
import 'package:lopicode/lowcode/canvas_overlay_widgets.dart';
import 'package:lopicode/lowcode/canvas_render_widgets.dart';
import 'package:lopicode/lowcode/canvas_view.dart';
import 'package:lopicode/lowcode/editor_drag.dart';
import 'package:lopicode/lowcode/editor_workbench_widgets.dart';
import 'package:lopicode/lowcode/lift_gesture_widgets.dart';
import 'package:lopicode/lowcode/model.dart';
import 'package:lopicode/lowcode/palette_catalog.dart';
import 'package:lopicode/lowcode/palette_widgets.dart';
import 'package:lopicode/lowcode/style_resolve.dart';
import 'package:lopicode/project_session.dart';
import 'package:lopicode/ui/top_bar.dart';
import 'package:material_ui/material_ui.dart';

import 'support/harness.dart';

final bool writeShots = Platform.environment['LOPI_SHOTS'] == '1';
bool fontsLoaded = false;

/// 最近一次 openBuilder 用的测试环境（要在同一个项目上再开一个搭建页时用）。
late TestEnv lastEnv;

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

/// 起始页面（root › n1 标题、n2 说明、n3 卡片 › n4 输入框、n5 “提交”按钮）；[doc] 给了就用它。
Future<ProjectSession> openBuilder(WidgetTester tester, {LcDocument? doc, ThemeMode mode = ThemeMode.light}) async {
  usePhoneViewport(tester);
  late TestEnv env;
  late ProjectSession session;
  await tester.runAsync(() async {
    env = lastEnv = await TestEnv.create();
    final project = await env.services.projects.create('我的小站', ProjectTemplate.lowcode);
    session = ProjectSession(env.services, project);
    if (doc != null) File(session.guard.resolve(kLowcodePageFile)).writeAsStringSync(doc.encode());
  });
  addTearDown(() async {
    await pendingWrites();
    session.dispose();
    await env.dispose();
  });
  await tester.pumpWidget(
    appFor(
      env,
      BuilderScreen(session: session),
      mode: mode,
      font: fontsLoaded ? kTestFont : null,
    ),
  );
  await settle(tester, rounds: 6);
  return session;
}

/// 一张很长的页面：[count] 行文字（id t0、t1…），一屏放不下。
LcDocument longDoc(int count) => LcDocument(
  title: '长页面',
  root: LcNode(
    id: 'root',
    type: 'page',
    props: Map.of(lcSpecs['page']!.defaults),
    children: [
      for (var i = 0; i < count; i++) LcNode(id: 't$i', type: 'text', props: {'text': '第 ${i + 1} 行'}),
    ],
  ),
);

/// 500 个组件的页面（不算页面本身）：50 张卡片，每张连自己 10 个（文字、行里三样、分隔线、输入框、按钮）。
LcDocument bigDoc() {
  var n = 0;
  LcNode make(String type, [Map<String, Object?>? props, List<LcNode>? children, Map<String, String>? style]) =>
      LcNode(id: 'b${n++}', type: type, props: {...?props}, style: style, children: children);
  final root = LcNode(id: 'root', type: 'page', props: Map.of(lcSpecs['page']!.defaults));
  for (var i = 0; i < 50; i++) {
    root.children.add(
      make(
        'card',
        {'padding': 12, 'gap': 8, 'width': 'fill'},
        [
          make('text', {'text': '卡片 ${i + 1}', 'size': 18, 'weight': 'bold'}),
          make('text', {'text': '一段说明文字，带一点样式。'}, null, {'color': '#556', 'line-height': '1.6'}),
          make(
            'row',
            {'gap': 8, 'width': 'fill'},
            [
              make('text', {'text': '左'}, null, {'flex-grow': '1'}),
              make('text', {'text': '中'}),
              make('button', {'text': '好', 'variant': 'filled'}),
            ],
            {'align-items': 'center'},
          ),
          make('divider'),
          make('input', {'label': '备注', 'placeholder': '写点什么', 'width': 'fill'}),
          make('button', {'text': '更多', 'variant': 'outlined'}),
        ],
      ),
    );
  }
  expect(n, 500);
  return LcDocument(title: '500 个组件', root: root);
}

/// 存盘里的页面（改完停手 0.4 秒才存：先把这段时间走完）。
Future<LcDocument> savedDoc(WidgetTester tester, ProjectSession session) async {
  await tester.pump(const Duration(milliseconds: 500));
  await settle(tester, rounds: 3);
  late LcDocument doc;
  await tester.runAsync(() async => doc = LcDocument.parse(File(session.guard.resolve(kLowcodePageFile)).readAsStringSync()));
  return doc;
}

Finder k(String key) => find.byKey(ValueKey(key));
Finder node(String id) => k('lowcode-node-$id');
Finder item(String key) => k('palette-item-$key');
CanvasViewState canvas(WidgetTester tester) => tester.state<CanvasViewState>(find.byType(CanvasView));
EditorWorkbenchState bench(WidgetTester tester) => tester.state<EditorWorkbenchState>(find.byType(EditorWorkbench));

Future<void> select(WidgetTester tester, String id) async {
  await tester.tap(node(id));
  await settle(tester, rounds: 2);
}

/// 按住慢慢拖（一步 20 像素、一帧一步），慢慢松手：和手指真拖一样，不带“甩”的速度。
Future<void> slide(WidgetTester tester, Finder target, double dy) async {
  final g = await tester.startGesture(tester.getCenter(target));
  final steps = (dy.abs() / 20).ceil();
  for (var i = 0; i < steps; i++) {
    await g.moveBy(Offset(0, dy / steps));
    await tester.pump(const Duration(milliseconds: 16));
  }
  await tester.pump(const Duration(milliseconds: 300));
  await g.up();
  await tester.pumpAndSettle();
}

Future<void> openPalette(WidgetTester tester) async {
  await tester.tap(k('lc-tool-add'));
  await tester.pumpAndSettle();
}

/// 长按 [at] 拿起来（多等一点）。返回的手势还按着。
Future<TestGesture> lift(WidgetTester tester, Offset at) async {
  final g = await tester.startGesture(at);
  await tester.pump(kLcLiftAfter + const Duration(milliseconds: 40));
  await tester.pump();
  return g;
}

/// 记下这次测试里震了哪些（HapticFeedback 发给系统的那个参数）。
List<String> recordHaptics(WidgetTester tester) {
  final log = <String>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
    if (call.method == 'HapticFeedback.vibrate') log.add('${call.arguments}'.replaceFirst('HapticFeedbackType.', ''));
    return null;
  });
  addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
  return log;
}

Map<String, Rect> rectsOf(WidgetTester tester, Iterable<String> ids) => {for (final id in ids) id: tester.getRect(node(id))};

void main() {
  setUpAll(() async => fontsLoaded = await loadRealFonts());

  group('新布局', () {
    testWidgets('顶栏只有返回位、页面名（下面小字）、“⋮”；工具条在最底下：添加 / 图层 / 撤销 / 重做 / 预览，都够大，都在拇指边', (tester) async {
      await openBuilder(tester);
      final bar = find.byType(PageBar);
      expect(find.descendant(of: bar, matching: find.text('我的小站')), findsOneWidget);
      expect(find.descendant(of: bar, matching: find.text('自适应 · 已保存')), findsOneWidget);
      expect(find.descendant(of: bar, matching: find.byType(PopupMenuButton<String>)), findsOneWidget);
      for (final tip in ['撤销', '重做', '图层', '预览']) {
        expect(
          find.descendant(of: bar, matching: find.byTooltip(tip)),
          findsNothing,
          reason: '$tip 不在顶栏',
        );
      }
      final toolbar = tester.getRect(k('lc-toolbar'));
      expect(toolbar.height, kEditorToolbarHeight);
      expect(kEditorToolbarHeight, 56);
      expect(toolbar.bottom, 844);
      expect(toolbar.width, 390);
      // 从左到右的顺序
      final xs = [
        tester.getCenter(k('lc-tool-add')).dx,
        for (final tip in ['图层', '撤销', '重做', '预览']) tester.getCenter(find.byTooltip(tip)).dx,
      ];
      expect(xs, [...xs]..sort());
      for (final tip in ['图层', '撤销', '重做', '预览']) {
        final r = tester.getRect(find.ancestor(of: find.byTooltip(tip), matching: find.byType(IconButton)).first);
        expect(r.width, greaterThanOrEqualTo(44), reason: tip);
        expect(r.height, greaterThanOrEqualTo(44), reason: tip);
        expect(toolbar.contains(r.center), isTrue, reason: tip);
        expect(r.center.dy, greaterThan(844 * 0.9), reason: '$tip 在屏幕最下面一成里');
      }
      expect(tester.getSize(k('lc-tool-add')).height, greaterThanOrEqualTo(40));
      // 画布紧贴在工具条上面，中间没有别的东西；画布上不再浮着小条
      expect(tester.getRect(find.byType(CanvasView)).bottom, toolbar.top);
      expect(k('lc-selection-bar'), findsNothing);
      await shot(tester, 'lc-editor-layout-light');
    });

    testWidgets('选中以后多出一条 48 高的选中条（在画布和工具条之间）：左名字，右 属性 / 样式 / 逻辑 / ⋯；取消选中就收走', (tester) async {
      await openBuilder(tester);
      final before = tester.getRect(find.byType(CanvasView));
      await select(tester, 'n5');
      final bar = tester.getRect(k('lc-selection-bar')), toolbar = tester.getRect(k('lc-toolbar'));
      expect(bar.height, kEditorSelectionBarHeight);
      expect(kEditorSelectionBarHeight, 48);
      expect(bar.bottom, toolbar.top);
      expect(tester.getRect(find.byType(CanvasView)).bottom, bar.top);
      Finder inBar(Finder f) => find.descendant(of: k('lc-selection-bar'), matching: f);
      expect(inBar(find.text('按钮')), findsOneWidget);
      final xs = [
        tester.getCenter(inBar(find.text('按钮'))).dx,
        tester.getCenter(inBar(find.widgetWithText(FilledButton, '属性'))).dx,
        tester.getCenter(inBar(find.widgetWithText(OutlinedButton, '样式'))).dx,
        tester.getCenter(inBar(find.widgetWithText(TextButton, '逻辑'))).dx,
        tester.getCenter(inBar(find.byTooltip('更多操作'))).dx,
      ];
      expect(xs, [...xs]..sort());
      expect(tester.getRect(inBar(find.byTooltip('更多操作'))).right, lessThanOrEqualTo(390));
      expect(k('lc-action-dot'), findsNothing, reason: '这个按钮没有逻辑');
      // 上移、下移、复制、删除收在“⋯”里，不摊在条上
      for (final label in ['上移', '下移', '复制', '删除']) {
        expect(find.text(label), findsNothing);
      }
      await shot(tester, 'lc-editor-selected-light');
      // 选中页面：没有“更多操作”
      canvas(tester).widget.onSelect('root');
      await settle(tester, rounds: 2);
      expect(inBar(find.text('页面')), findsOneWidget);
      expect(find.byTooltip('更多操作'), findsNothing);
      canvas(tester).widget.onSelect(null);
      await settle(tester, rounds: 2);
      expect(k('lc-selection-bar'), findsNothing);
      expect(tester.getRect(find.byType(CanvasView)), before);
    });

    testWidgets('有逻辑的组件：“逻辑”带小圆点', (tester) async {
      final doc = LcDocument.starter('我的小站');
      final json = doc.toJson()
        ..['logic'] = {
          'handlers': [
            {'id': 'h1', 'event': 'click', 'target': 'n5', 'body': <Object>[]},
          ],
        };
      await openBuilder(tester, doc: LcDocument.fromJson(json));
      await select(tester, 'n5');
      expect(k('lc-action-dot'), findsOneWidget);
      await select(tester, 'n1');
      expect(k('lc-action-dot'), findsNothing);
    });

    testWidgets('顶栏小字跟着保存状态走：改了＝正在保存…，停手 0.4 秒后＝已保存；连着改三下只存一次', (tester) async {
      final session = await openBuilder(tester);
      final file = File(session.guard.resolve(kLowcodePageFile));
      final original = file.readAsStringSync();
      await openPalette(tester);
      for (var i = 0; i < 3; i++) {
        await tester.tap(item('text'), warnIfMissed: false);
        await tester.pump(const Duration(milliseconds: 60));
        bench(tester).palette!.expand();
        // 等面板升回来（180 毫秒）再点下一下。动画从它的第一帧起算，所以先空 pump 一帧。
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 190));
      }
      expect(find.text('自适应 · 正在保存…'), findsOneWidget);
      expect(file.readAsStringSync(), original, reason: '还在改：一次都没写');
      final doc = await savedDoc(tester, session);
      expect(doc.root.children.where((n) => n.type == 'text').length, 2 + 3);
      expect(find.text('自适应 · 已保存'), findsOneWidget);
    });
  });

  group('组件盒', () {
    testWidgets('点“添加”打开：搜索框、分类一行横着滑、下面一行 4 个格子；默认在“常用”，是起步的 8 个', (tester) async {
      await openBuilder(tester);
      expect(k('palette-panel'), findsNothing);
      await openPalette(tester);
      final panel = tester.getRect(k('palette-panel'));
      expect(panel.height, kPaletteNormalHeight);
      expect(panel.bottom, tester.getRect(k('lc-toolbar')).top, reason: '贴在工具条上面');
      expect(k('palette-search'), findsOneWidget);
      for (final g in ['recent', 'layout', 'basic', 'form', 'show']) {
        expect(k('palette-group-$g'), findsOneWidget, reason: g);
      }
      expect(k('palette-group-mine'), findsNothing, reason: '没有自定义组件时不显示“我的”');
      for (final type in kPaletteStarters) {
        expect(item(type), findsOneWidget, reason: type);
      }
      // 一行 4 个，格子约 80×72
      final first = [for (final type in kPaletteStarters.take(4)) tester.getRect(item(type))];
      expect({for (final r in first) r.top}.length, 1);
      expect(tester.getRect(item(kPaletteStarters[4])).top, greaterThan(first.first.top));
      for (final r in first) {
        expect(r.height, 72);
        expect(r.width, inInclusiveRange(76, 90));
      }
      await shot(tester, 'lc-editor-palette-light');
    });

    testWidgets('搜索：按名字、别名、拼音都找得到；没有就说没有；清空回到分类', (tester) async {
      await openBuilder(tester);
      await openPalette(tester);
      Future<void> type(String q) async {
        await tester.enterText(k('palette-search'), q);
        await tester.pumpAndSettle();
      }

      List<String> shown() => [
        for (final e in find.byWidgetPredicate((w) => w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith('palette-item-')).evaluate())
          (e.widget.key! as ValueKey<String>).value.substring('palette-item-'.length),
      ];

      await type('按钮');
      expect(shown(), ['button']);
      expect(find.text('找到 1 个'), findsOneWidget);
      expect(k('palette-group-layout'), findsNothing, reason: '搜索时不显示分类');
      await type('btn');
      expect(shown(), ['button']);
      await type('shurukuang');
      expect(shown(), ['input']);
      await type('横排');
      expect(shown(), ['row']);
      await type('火箭');
      expect(shown(), isEmpty);
      expect(find.text('没有名字或别名里带“火箭”的组件'), findsOneWidget);
      await shot(tester, 'lc-editor-palette-noresult-light');
      await tester.tap(find.byTooltip('清空'));
      await tester.pumpAndSettle();
      expect(k('palette-group-layout'), findsOneWidget);
      expect(shown(), kPaletteStarters);
      // 搜到以后点一下就加
      await type('分隔');
      await shot(tester, 'lc-editor-palette-search-light');
      await tester.tap(item('divider'));
      await settle(tester, rounds: 3);
      expect(canvas(tester).widget.doc.root.children.last.type, 'divider');
    });

    testWidgets('分类：点哪类显示哪类；自定义组件在“我的”里', (tester) async {
      final doc = LcDocument.starter('我的小站');
      final json = doc.toJson()
        ..['components'] = [
          {
            'id': 'c1',
            'name': '问候卡',
            'root': {'id': 'k1', 'type': 'card'},
          },
        ];
      await openBuilder(tester, doc: LcDocument.fromJson(json));
      await openPalette(tester);
      await tester.tap(k('palette-group-layout'));
      await tester.pumpAndSettle();
      for (final type in ['container', 'row', 'column', 'card', 'spacer']) {
        expect(item(type), findsOneWidget, reason: type);
      }
      expect(item('button'), findsNothing);
      await tester.tap(k('palette-group-form'));
      await tester.pumpAndSettle();
      expect(item('input'), findsOneWidget);
      expect(item('container'), findsNothing);
      await tester.ensureVisible(k('palette-group-mine'));
      await tester.pumpAndSettle();
      await tester.tap(k('palette-group-mine'));
      await tester.pumpAndSettle();
      expect(item('component:c1'), findsOneWidget);
      expect(find.descendant(of: item('component:c1'), matching: find.text('问候卡')), findsOneWidget);
    });

    testWidgets('常用：刚用过的排最前；记在项目里，关掉再打开还在', (tester) async {
      final session = await openBuilder(tester);
      await openPalette(tester);
      await tester.tap(k('palette-group-show'));
      await tester.pumpAndSettle();
      await tester.tap(item('divider'));
      await settle(tester, rounds: 3);
      bench(tester).palette!.expand();
      await tester.pumpAndSettle();
      await tester.tap(k('palette-group-recent'));
      await tester.pumpAndSettle();
      expect(tester.getRect(item('divider')).left, lessThan(tester.getRect(item('text')).left));
      expect(tester.getRect(item('divider')).top, tester.getRect(item('text')).top);
      await savedDoc(tester, session);
      await tester.runAsync(pendingWrites);
      // 换一个全新的搭建页（同一个项目）
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(appFor(lastEnv, BuilderScreen(key: UniqueKey(), session: session)));
      await settle(tester, rounds: 6);
      await openPalette(tester);
      expect(tester.getRect(item('divider')).left, lessThan(tester.getRect(item('text')).left));
    });

    testWidgets('面板可以拖高拖矮；最矮只剩手柄，再点“添加”拉回来；“关闭”收走', (tester) async {
      await openBuilder(tester);
      await openPalette(tester);
      final handle = k('palette-handle');
      // 三档停靠（和积木盒一样）：松手落到最近的一档。往上拖一大段＝最高那一档。
      await slide(tester, handle, -320);
      expect(tester.getRect(k('palette-panel')).height, greaterThan(kPaletteNormalHeight + 200));
      expect(tester.getRect(k('palette-panel')).top, greaterThanOrEqualTo(PageBar.kHeight), reason: '不盖住顶栏');
      await slide(tester, handle, 700);
      expect(tester.getRect(k('palette-panel')).height, kPaletteHandleHeight);
      expect(bench(tester).palette!.collapsed, isTrue);
      await tester.tap(k('lc-tool-add'));
      await tester.pumpAndSettle();
      expect(tester.getRect(k('palette-panel')).height, kPaletteNormalHeight);
      await tester.tap(find.byTooltip('关闭组件盒'));
      await tester.pumpAndSettle();
      expect(k('palette-panel'), findsNothing);
    });
  });

  group('点一下添加', () {
    testWidgets('长页面里点一下加到末尾：自动滚到新组件、选中它、面板收到最矮', (tester) async {
      await openBuilder(tester, doc: longDoc(40));
      final view = tester.getRect(find.byType(CanvasView));
      await openPalette(tester);
      await tester.tap(item('button'));
      await settle(tester, rounds: 4);
      final doc = canvas(tester).widget.doc;
      final added = doc.root.children.last;
      expect(added.type, 'button');
      expect(canvas(tester).widget.selected, added.id);
      expect(bench(tester).palette!.collapsed, isTrue);
      final r = tester.getRect(node(added.id));
      final shownBottom = tester.getRect(k('palette-panel')).top;
      expect(r.top, greaterThanOrEqualTo(view.top + PageBar.kHeight), reason: '不在顶栏后面');
      expect(r.bottom, lessThanOrEqualTo(shownBottom), reason: '不在面板 / 选中条后面');
      expect(find.descendant(of: k('lc-selection-bar'), matching: find.text('按钮')), findsOneWidget);
    });

    testWidgets('选中容器时加进它里面，选中普通组件时加在它后面（规则不变）；加完都滚到看得见的地方', (tester) async {
      await openBuilder(tester);
      await select(tester, 'n3');
      await openPalette(tester);
      await tester.tap(item('text'));
      await settle(tester, rounds: 4);
      var doc = canvas(tester).widget.doc;
      expect(doc.find('n3')!.children.last.type, 'text');
      expect(doc.find('n3')!.children.length, 3);
      await select(tester, 'n1');
      bench(tester).palette!.expand();
      await tester.pumpAndSettle();
      await tester.tap(item('image'));
      await settle(tester, rounds: 4);
      doc = canvas(tester).widget.doc;
      expect([for (final c in doc.root.children) c.type], ['text', 'image', 'text', 'card']);
      final r = tester.getRect(node(doc.root.children[1].id));
      expect(r.top, greaterThanOrEqualTo(PageBar.kHeight));
      expect(r.bottom, lessThanOrEqualTo(tester.getRect(k('palette-panel')).top));
    });
  });

  group('长按拿起（和积木画布一个手感）', () {
    test('两个数直接用积木画布的：280 毫秒、8 像素', () {
      expect(kLcLiftAfter, const Duration(milliseconds: 280));
      expect(kLcLiftSlop, 8);
    });

    testWidgets('按不够 280 毫秒松手＝点一下（选中），没拿起；按够了＝拿起，震一下（中等）', (tester) async {
      final haptics = recordHaptics(tester);
      await openBuilder(tester);
      final at = tester.getCenter(node('n1'));
      var g = await tester.startGesture(at);
      await tester.pump(const Duration(milliseconds: 240));
      expect(bench(tester).dragging, isFalse);
      await g.up();
      await settle(tester, rounds: 2);
      expect(bench(tester).dragging, isFalse);
      expect(canvas(tester).widget.selected, 'n1');
      expect(haptics, isEmpty);

      g = await tester.startGesture(at);
      await tester.pump(const Duration(milliseconds: 270));
      expect(bench(tester).dragging, isFalse, reason: '270 毫秒还没到');
      await tester.pump(const Duration(milliseconds: 20));
      await tester.pump();
      expect(bench(tester).dragging, isTrue, reason: '过了 280 毫秒');
      expect(haptics, ['mediumImpact']);
      await g.up();
      await settle(tester, rounds: 2);
      expect(bench(tester).dragging, isFalse);
    });

    testWidgets('没按够就挪了超过 8 像素＝不是长按：画布跟着平移，之后按再久也不拿起；挪 6 像素不算', (tester) async {
      final haptics = recordHaptics(tester);
      await openBuilder(tester, doc: longDoc(40));
      final at = tester.getCenter(node('t3'));
      final before = canvas(tester).view.value.offset;
      var g = await tester.startGesture(at);
      await tester.pump(const Duration(milliseconds: 60));
      await g.moveBy(const Offset(0, -30));
      await tester.pump(const Duration(milliseconds: 60));
      await g.moveBy(const Offset(0, -30));
      await tester.pump(const Duration(milliseconds: 400));
      expect(bench(tester).dragging, isFalse);
      expect(canvas(tester).view.value.offset.dy, lessThan(before.dy), reason: '是平移');
      await g.up();
      await settle(tester, rounds: 2);
      expect(haptics, isEmpty);

      // 手指轻微抖动（6 像素）不影响长按
      g = await tester.startGesture(tester.getCenter(node('t6')));
      await tester.pump(const Duration(milliseconds: 100));
      await g.moveBy(const Offset(4, 4));
      await tester.pump(const Duration(milliseconds: 220));
      await tester.pump();
      expect(bench(tester).dragging, isTrue);
      await g.up();
      await settle(tester, rounds: 2);
    });

    testWidgets('组件盒里的格子也是长按 280 毫秒拿起；拿起时面板收到最矮', (tester) async {
      final haptics = recordHaptics(tester);
      await openBuilder(tester);
      await openPalette(tester);
      final g = await tester.startGesture(tester.getCenter(item('button')));
      await tester.pump(const Duration(milliseconds: 240));
      expect(bench(tester).dragging, isFalse);
      await tester.pump(const Duration(milliseconds: 60));
      await tester.pumpAndSettle();
      expect(bench(tester).dragging, isTrue);
      expect(haptics, ['mediumImpact']);
      expect(bench(tester).palette!.collapsed, isTrue);
      await g.up();
      await settle(tester, rounds: 2);
    });
  });

  group('拖动：蓝线落点', () {
    testWidgets('拖动时页面一动不动（不撑开、不跳）；蓝线 3 像素；标签说放到哪、第几个；手指上面有缩略图；工具条换成删除区', (tester) async {
      final haptics = recordHaptics(tester);
      final session = await openBuilder(tester);
      const ids = ['n1', 'n2', 'n3', 'n4', 'n5'];
      final before = rectsOf(tester, ids);
      final pageBefore = canvas(tester).pageRect;
      final g = await lift(tester, tester.getCenter(node('n1')));
      expect(k('lc-drop-zone'), findsOneWidget);
      expect(k('lc-toolbar'), findsNothing);
      expect(find.text('拖到这里删除'), findsOneWidget);
      // 拖到卡片下面（页面最后）
      await g.moveTo(Offset(195, before['n3']!.bottom + 40));
      await tester.pump();
      expect(rectsOf(tester, ids), before, reason: '页面上每个组件都在原地');
      expect(canvas(tester).pageRect, pageBefore);
      final line = tester.getRect(k('lc-drop-line'));
      expect(line.height, closeTo(kDropLineWidth, 0.01));
      expect(line.top, greaterThanOrEqualTo(before['n3']!.bottom));
      expect(line.width, greaterThan(200));
      expect(find.descendant(of: k('lc-drop-label'), matching: find.text('放到 页面 里 · 第 3 个')), findsOneWidget);
      final ghost = tester.getRect(k('lc-drag-ghost'));
      expect(ghost.width, lessThanOrEqualTo(kDragGhostMaxWidth + 0.01));
      expect(ghost.bottom, lessThan(before['n3']!.bottom + 40), reason: '缩略图在手指上面，不被手指挡住');
      // 标签躲着手指：手指在线的右半边，标签贴线的左头；挪到左半边，标签换到右头，始终不和缩略图叠在一起
      await g.moveTo(Offset(300, before['n3']!.bottom + 40));
      await tester.pump();
      expect(tester.getRect(k('lc-drop-label')).right, lessThan(195));
      expect(tester.getRect(k('lc-drop-label')).overlaps(tester.getRect(k('lc-drag-ghost'))), isFalse);
      await g.moveTo(Offset(90, before['n3']!.bottom + 40));
      await tester.pump();
      expect(tester.getRect(k('lc-drop-label')).left, greaterThan(195));
      expect(tester.getRect(k('lc-drop-label')).overlaps(tester.getRect(k('lc-drag-ghost'))), isFalse);
      expect(rectsOf(tester, ids), before, reason: '横着挪手指，页面也不动');
      await g.moveTo(Offset(195, before['n3']!.bottom + 40));
      await tester.pump();
      expect(
        tester.widget<Opacity>(find.ancestor(of: node('n1'), matching: find.byType(Opacity)).first).opacity,
        lessThan(1),
        reason: '被拿起的那个在原地变淡',
      );
      await shot(tester, 'lc-editor-drag-light');
      // 换一个落点：轻震一下
      final clicks = haptics.where((h) => h == 'selectionClick').length;
      await g.moveTo(Offset(195, (before['n2']!.bottom + before['n3']!.top) / 2));
      await tester.pump();
      expect(canvas(tester).dropTarget!.noop, isFalse);
      expect(canvas(tester).dropTarget!.index, 2);
      expect(haptics.where((h) => h == 'selectionClick').length, clicks + 1);
      // 同一个落点里挪：不再震
      await g.moveBy(const Offset(20, 1));
      await tester.pump();
      expect(haptics.where((h) => h == 'selectionClick').length, clicks + 1);
      await g.moveTo(Offset(195, before['n3']!.bottom + 40));
      await tester.pump();
      await g.up();
      await settle(tester, rounds: 3);
      expect(haptics.first, 'mediumImpact');
      expect(haptics.last, 'lightImpact', reason: '放下：轻');
      expect(k('lc-drop-line'), findsNothing);
      expect(k('lc-drag-ghost'), findsNothing);
      expect(k('lc-toolbar'), findsOneWidget);
      expect([for (final c in (await savedDoc(tester, session)).root.children) c.id], ['n2', 'n3', 'n1']);
      expect(canvas(tester).widget.selected, 'n1', reason: '放下后选中被挪的那个');
    });

    testWidgets('放回原地（紧挨着自己）：什么都不变，不多一条撤销，不震“放下”', (tester) async {
      final haptics = recordHaptics(tester);
      final session = await openBuilder(tester);
      final g = await lift(tester, tester.getCenter(node('n2')));
      await g.moveBy(const Offset(10, 12));
      await tester.pump();
      expect(canvas(tester).dropTarget!.noop, isTrue);
      expect(k('lc-drop-line'), findsNothing, reason: '原地不画线');
      await g.up();
      await settle(tester, rounds: 3);
      expect(haptics, ['mediumImpact']);
      expect([for (final c in (await savedDoc(tester, session)).root.children) c.id], ['n1', 'n2', 'n3']);
      expect(tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.undo)).onPressed, isNull);
    });

    testWidgets('在容器上停 0.4 秒才算放进里面（描蓝边）；没停够是放在它前后', (tester) async {
      final session = await openBuilder(tester);
      final card = tester.getRect(node('n3')), input = tester.getRect(node('n4')), button = tester.getRect(node('n5'));
      final g = await lift(tester, tester.getCenter(node('n1')));
      final at = Offset(195, (input.bottom + button.top) / 2);
      await g.moveTo(at);
      await tester.pump();
      expect(canvas(tester).dropTarget!.parentId, 'root');
      expect(k('lc-drop-box'), findsNothing);
      await tester.pump(kDropDwell - const Duration(milliseconds: 50));
      expect(canvas(tester).dropTarget!.parentId, 'root', reason: '还没停够');
      await tester.pump(const Duration(milliseconds: 80));
      await tester.pump();
      expect(canvas(tester).dropTarget!.parentId, 'n3');
      expect(canvas(tester).dropTarget!.index, 1);
      expect(find.text('放到 卡片 里 · 第 2 个'), findsOneWidget);
      expect(tester.getRect(k('lc-drop-box')), card);
      final line = tester.getRect(k('lc-drop-line'));
      expect(line.center.dy, closeTo(at.dy, 1));
      await shot(tester, 'lc-editor-drag-inside-light');
      // 手指离开卡片再回来：要重新停
      await g.moveTo(Offset(195, card.bottom + 40));
      await tester.pump();
      expect(canvas(tester).dropTarget!.parentId, 'root');
      await g.moveTo(at);
      await tester.pump();
      expect(canvas(tester).dropTarget!.parentId, 'root');
      await tester.pump(kDropDwell + const Duration(milliseconds: 30));
      await tester.pump();
      await g.up();
      await settle(tester, rounds: 3);
      final doc = await savedDoc(tester, session);
      expect([for (final c in doc.find('n3')!.children) c.id], ['n4', 'n1', 'n5']);
    });

    testWidgets('空容器：不用等，整块高亮，直接放进去', (tester) async {
      final doc = LcDocument.starter('我的小站');
      final box = doc.newNode('container');
      doc.insert('root', box);
      final session = await openBuilder(tester, doc: doc);
      expect(find.text('空的 · 拖组件到这里'), findsOneWidget);
      await openPalette(tester);
      final g = await lift(tester, tester.getCenter(item('button')));
      await g.moveTo(tester.getCenter(node(box.id)));
      await tester.pump();
      expect(canvas(tester).dropTarget!.parentId, box.id);
      expect(k('lc-drop-line'), findsNothing);
      expect(tester.getRect(k('lc-drop-box')), tester.getRect(node(box.id)));
      expect(find.text('放到 容器 里 · 第 1 个'), findsOneWidget);
      await g.up();
      await settle(tester, rounds: 3);
      expect([for (final c in (await savedDoc(tester, session)).find(box.id)!.children) c.type], ['button']);
    });

    testWidgets('拖到底部删除区松手＝删除（重震）；撤销能回来', (tester) async {
      final haptics = recordHaptics(tester);
      final session = await openBuilder(tester);
      final g = await lift(tester, tester.getCenter(node('n2')));
      await g.moveTo(tester.getCenter(k('lc-drop-zone')));
      await tester.pump();
      expect(canvas(tester).dropTarget, isNull, reason: '在删除区上：没有落点');
      expect(k('lc-drop-line'), findsNothing);
      await shot(tester, 'lc-editor-drag-delete-light');
      await g.up();
      await settle(tester, rounds: 3);
      expect(haptics.last, 'heavyImpact');
      expect([for (final c in (await savedDoc(tester, session)).root.children) c.id], ['n1', 'n3']);
      await tester.tap(find.byTooltip('撤销'));
      await settle(tester, rounds: 2);
      expect([for (final c in (await savedDoc(tester, session)).root.children) c.id], ['n1', 'n2', 'n3']);
    });

    testWidgets('从组件盒拖出来的新组件拖到底部＝取消（什么都不加，不震“删除”）', (tester) async {
      final haptics = recordHaptics(tester);
      final session = await openBuilder(tester);
      await openPalette(tester);
      final g = await lift(tester, tester.getCenter(item('image')));
      expect(find.text('拖到这里取消'), findsOneWidget);
      await g.moveTo(tester.getCenter(k('lc-drop-zone')));
      await tester.pump();
      await g.up();
      await settle(tester, rounds: 3);
      expect(haptics, isNot(contains('heavyImpact')));
      expect([for (final c in (await savedDoc(tester, session)).root.children) c.id], ['n1', 'n2', 'n3']);
    });

    testWidgets('手势被系统打断：什么都不改，蓝线和删除区都收起', (tester) async {
      final session = await openBuilder(tester);
      final g = await lift(tester, tester.getCenter(node('n1')));
      await g.moveTo(const Offset(195, 500));
      await tester.pump();
      await g.cancel();
      await settle(tester, rounds: 3);
      expect(bench(tester).dragging, isFalse);
      expect(k('lc-drop-line'), findsNothing);
      expect(k('lc-toolbar'), findsOneWidget);
      expect([for (final c in (await savedDoc(tester, session)).root.children) c.id], ['n1', 'n2', 'n3']);
    });

    testWidgets('手指到画布上下 64 像素以内：页面自己滚；回到中间就停；滚到头不出界', (tester) async {
      await openBuilder(tester, doc: longDoc(60));
      final view = tester.getRect(find.byType(CanvasView));
      final g = await lift(tester, tester.getCenter(node('t2')));
      final start = canvas(tester).view.value.offset.dy;
      // 中间：不滚
      await g.moveTo(Offset(195, view.center.dy));
      await tester.pump(const Duration(milliseconds: 300));
      expect(canvas(tester).view.value.offset.dy, start);
      // 离底边 20：往下滚
      await g.moveTo(Offset(195, view.bottom - 20));
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      final scrolled = canvas(tester).view.value.offset.dy;
      expect(scrolled, lessThan(start - 100), reason: '半秒滚了一百多像素');
      expect(canvas(tester).dropTarget!.index, greaterThan(10), reason: '落点跟着滚到后面去了');
      // 回到中间：停
      await g.moveTo(Offset(195, view.center.dy));
      await tester.pump(const Duration(milliseconds: 300));
      final stopped = canvas(tester).view.value.offset.dy;
      await tester.pump(const Duration(milliseconds: 300));
      expect(canvas(tester).view.value.offset.dy, stopped);
      // 一直按在底边：滚到底就不动了
      await g.moveTo(Offset(195, view.bottom - 4));
      for (var i = 0; i < 400; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      final end = canvas(tester).view.value.offset.dy;
      expect(canvas(tester).pageRect.bottom, closeTo(view.height, 1), reason: '页面底边贴着画布底边');
      await tester.pump(const Duration(milliseconds: 200));
      expect(canvas(tester).view.value.offset.dy, end);
      expect(canvas(tester).dropTarget!.index, 60);
      // 靠顶边：往回滚（顶栏下面那 64 像素）
      await g.moveTo(const Offset(195, PageBar.kHeight + 10));
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(canvas(tester).view.value.offset.dy, greaterThan(end + 100));
      await g.up();
      await settle(tester, rounds: 3);
      expect(tester.takeException(), isNull);
    });
  });

  group('拖柄和尺寸标签', () {
    testWidgets('拖柄能按的范围是 44×44（缩放到 50% / 200% 在屏幕上还是 44）；看到的小方块还在角上', (tester) async {
      await openBuilder(tester);
      await select(tester, 'n3');
      for (final zoom in [1.0, 0.5, 2.0]) {
        while ((canvas(tester).scale - zoom).abs() > 0.01) {
          canvas(tester).zoomStep(canvas(tester).scale < zoom ? 1 : -1);
          await tester.pump();
        }
        await settle(tester, rounds: 2);
        final card = tester.getRect(node('n3'));
        final se = tester.getRect(k('lowcode-handle-se'));
        expect(se.width, closeTo(kCanvasHandleHit, 0.01), reason: '$zoom');
        expect(se.height, closeTo(kCanvasHandleHit, 0.01), reason: '$zoom');
        expect(se.contains(card.bottomRight), isTrue, reason: '角还在能按的范围里（$zoom）');
        // 能按的范围大部分在组件外面：不挡组件里面的东西
        expect(se.center.dx, greaterThan(card.right), reason: '$zoom');
        expect(se.center.dy, greaterThan(card.bottom), reason: '$zoom');
      }
    });

    testWidgets('在拖柄上只是点一下：当成点在它下面的组件上（拖柄不把旁边的小组件挡得点不着）', (tester) async {
      await openBuilder(tester);
      await select(tester, 'n2');
      // 说明文字左上角的拖柄盖着上面那行标题的一部分
      final nw = tester.getRect(k('lowcode-handle-nw'));
      final title = tester.getRect(node('n1'));
      final at = Offset(nw.right - 2, nw.top + 4);
      expect(nw.contains(at), isTrue);
      expect(title.contains(at), isTrue, reason: '这一点在标题上，也在拖柄能按的范围里');
      await tester.tapAt(at);
      await settle(tester, rounds: 2);
      expect(canvas(tester).widget.selected, 'n1');
      expect(tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.undo)).onPressed, isNull, reason: '点一下不改尺寸');
    });

    testWidgets('尺寸标签：大组件放在框里面的右下角；小组件放在框外，不盖住它；整个标签都在画布里', (tester) async {
      await openBuilder(tester);
      final view = tester.getRect(find.byType(CanvasView));
      await select(tester, 'n3');
      var label = tester.getRect(k('lowcode-size-label')), box = tester.getRect(node('n3'));
      expect(box.contains(label.topLeft) && box.contains(label.bottomRight - const Offset(0.1, 0.1)), isTrue, reason: '卡片：标签在框里');
      expect(label.center.dx, greaterThan(box.center.dx));
      expect(label.center.dy, greaterThan(box.center.dy));
      await select(tester, 'n5');
      label = tester.getRect(k('lowcode-size-label'));
      box = tester.getRect(node('n5'));
      expect(label.overlaps(box), isFalse, reason: '按钮太小：标签不盖住它');
      expect(view.contains(label.topLeft) && view.contains(label.bottomRight - const Offset(0.1, 0.1)), isTrue);
      await shot(tester, 'lc-editor-handles-light');
    });
  });

  group('失败写出原因', () {
    testWidgets('保存失败：提示里带真正的原因，顶栏小字变“没存上”；修好以后再改一下就存上了', (tester) async {
      final session = await openBuilder(tester);
      // 把导出的 index.html 换成一个目录：存盘时写不进去
      final html = File(session.guard.resolve('index.html'));
      await tester.runAsync(() async {
        html.deleteSync();
        Directory(html.path).createSync();
      });
      await openPalette(tester);
      await tester.tap(item('text'));
      await tester.pump(const Duration(milliseconds: 500));
      await settle(tester, rounds: 4);
      expect(find.textContaining('保存失败：'), findsOneWidget);
      final message = tester.widget<Text>(find.textContaining('保存失败：')).data!;
      expect(message, contains('index.html'), reason: '写了是哪个文件');
      expect(message.length, greaterThan('保存失败：'.length + 'index.html'.length + 4), reason: '带系统给的原因：$message');
      expect(message, isNot(contains('请重试')));
      expect(find.text('自适应 · 没存上'), findsOneWidget);
      await shot(tester, 'lc-editor-save-failed-light');
      await tester.runAsync(() async => Directory(html.path).deleteSync());
      bench(tester).palette!.expand();
      await tester.pumpAndSettle();
      await tester.tap(item('button'));
      final doc = await savedDoc(tester, session);
      expect(find.text('自适应 · 已保存'), findsOneWidget);
      expect(doc.root.children.map((n) => n.type).toList().sublist(3), ['text', 'button'], reason: '没存上的那一次也没丢');
      expect(html.existsSync(), isTrue);
    });

    testWidgets('导出 Flutter 代码写不进去：提示里带路径和原因，不弹“已保存”的代码面板', (tester) async {
      final session = await openBuilder(tester);
      // 项目里已经有一个叫 export 的文件：建不了 export/ 目录
      await tester.runAsync(() async => File(session.guard.resolve('export')).writeAsStringSync('x'));
      await tester.tap(find.byTooltip('更多'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('导出 Flutter 代码'));
      await settle(tester, rounds: 4);
      await tester.pumpAndSettle();
      expect(find.textContaining('写入 export/page.dart 失败：'), findsOneWidget);
      final message = tester.widget<Text>(find.textContaining('写入 export/page.dart 失败：')).data!;
      expect(message.length, greaterThan('写入 export/page.dart 失败：'.length + 4), reason: message);
      expect(find.text('Flutter 代码'), findsNothing);
    });
  });

  group('性能', () {
    testWidgets('平移、缩放画布：整页一次都不重搭', (tester) async {
      await openBuilder(tester, doc: longDoc(40));
      await select(tester, 't3');
      final builds = CanvasPage.debugBuilds;
      final styles = debugResolvedStyleCalls;
      final before = canvas(tester).view.value;
      final g = await tester.startGesture(const Offset(195, 500));
      for (var i = 0; i < 20; i++) {
        await g.moveBy(const Offset(0, -12));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await g.up();
      await tester.pump(const Duration(seconds: 2));
      canvas(tester).zoomStep(1);
      await tester.pump();
      canvas(tester).zoomStep(-1);
      await tester.pump();
      expect(canvas(tester).view.value.offset.dy, lessThan(before.offset.dy - 100), reason: '真的滚了');
      expect(CanvasPage.debugBuilds, builds, reason: '平移 / 缩放不重搭整页');
      expect(debugResolvedStyleCalls, styles, reason: '也不重新算样式');
      // 选中框跟着走
      expect(tester.getRect(k('lowcode-size-label')).top, lessThan(844));
    });

    testWidgets('整页重搭一次：每个组件的样式只算一遍', (tester) async {
      await openBuilder(tester);
      // 起始页面 6 个节点（页面、两行文字、卡片、输入框、按钮）。换一下选中触发一次整页重搭。
      final builds = CanvasPage.debugBuilds;
      final styles = debugResolvedStyleCalls;
      canvas(tester).widget.onSelect('n4');
      await tester.pump();
      await tester.pump();
      expect(CanvasPage.debugBuilds, builds + 1);
      // 画页面：6 个节点各算一次（以前同一个节点会算两遍）。另有 1 次是给选中的那个量间距示意用的，不在画页面里。
      expect(debugResolvedStyleCalls - styles, 6 + 1);
    });

    testWidgets('500 个组件的页面：平移 60 下，整页不重搭，平均每下远低于上限', (tester) async {
      await openBuilder(tester, doc: bigDoc());
      expect(canvas(tester).widget.doc.root.children.length, 50);
      // 先滚几下热身（第一次会编译着色器、填文字缓存，不算数）
      final warm = await tester.startGesture(const Offset(195, 500));
      for (var i = 0; i < 5; i++) {
        await warm.moveBy(const Offset(0, -10));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await warm.up();
      await tester.pump(const Duration(seconds: 1));
      final builds = CanvasPage.debugBuilds;
      final start = canvas(tester).view.value.offset.dy;
      const frames = 60;
      final g = await tester.startGesture(const Offset(195, 500));
      await g.moveBy(const Offset(0, -20)); // 先越过“这是拖动”的界线
      await tester.pump(const Duration(milliseconds: 16));
      final watch = Stopwatch()..start();
      for (var i = 0; i < frames; i++) {
        await g.moveBy(const Offset(0, -8));
        await tester.pump(const Duration(milliseconds: 16));
      }
      watch.stop();
      await g.up();
      await tester.pump(const Duration(seconds: 2));
      expect(CanvasPage.debugBuilds, builds, reason: '平移不重搭整页（这是快的原因，和机器快慢无关）');
      expect(start - canvas(tester).view.value.offset.dy, greaterThan(frames * 8 - 1), reason: '真的平移了这么多');
      final perFrame = watch.elapsedMicroseconds / frames / 1000;
      // 同一次运行里再量一下“整页重搭一帧”要多久（换选中会重搭整页），拿来当参照：机器忙的时候两个数一起变慢。
      const rebuilds = 10;
      final again = Stopwatch()..start();
      for (var i = 0; i < rebuilds; i++) {
        canvas(tester).widget.onSelect(i.isEven ? 'b0' : null);
        await tester.pump(const Duration(milliseconds: 16));
      }
      again.stop();
      expect(CanvasPage.debugBuilds, greaterThanOrEqualTo(builds + rebuilds));
      final perRebuild = again.elapsedMicroseconds / rebuilds / 1000;
      recordPanTiming(perFrame, perRebuild);
      // 上限怎么定的：见文件末尾 kPanBudgetMs / kPanVsRebuild 的说明。
      expect(perFrame, lessThan(kPanBudgetMs), reason: '平移一下平均 ${perFrame.toStringAsFixed(2)} 毫秒');
      expect(perFrame * kPanVsRebuild, lessThan(perRebuild), reason: '平移一下 ${perFrame.toStringAsFixed(2)} 毫秒，整页重搭一帧 ${perRebuild.toStringAsFixed(2)} 毫秒');
    }, semanticsEnabled: false);
  });

  group('截图（深色）', () {
    testWidgets('新布局、选中、组件盒、拖动', (tester) async {
      await openBuilder(tester, mode: ThemeMode.dark);
      await shot(tester, 'lc-editor-layout-dark');
      await select(tester, 'n5');
      await shot(tester, 'lc-editor-selected-dark');
      await openPalette(tester);
      await shot(tester, 'lc-editor-palette-dark');
      await tester.enterText(k('palette-search'), '分隔');
      await tester.pumpAndSettle();
      await shot(tester, 'lc-editor-palette-search-dark');
      await tester.tap(find.byTooltip('清空'));
      await tester.pumpAndSettle();
      final g = await lift(tester, tester.getCenter(node('n1')));
      await g.moveTo(Offset(195, tester.getRect(node('n3')).bottom + 40));
      await tester.pump();
      await shot(tester, 'lc-editor-drag-dark');
      await g.moveTo(tester.getCenter(k('lc-drop-zone')));
      await tester.pump();
      await shot(tester, 'lc-editor-drag-delete-dark');
      await g.cancel();
      await settle(tester, rounds: 2);
      expect(tester.takeException(), isNull);
    });
  });
}

/// “500 个组件平移一下”的两道时间上限（测试环境里一次 pump 的平均耗时）。
///
/// 怎么定的：2026-11-26 在开发机上量了三次（1.5 核，同时有别的任务在抢 CPU，负载 3–12）：
///   平移一下 2.07 / 10.16 / 30.20 毫秒；同一次运行里“整页重搭一帧”776 / 1463 / 2222 毫秒。
/// 绝对时间跟着机器忙不忙能差十几倍，所以主要看**比例**：平移至少比整页重搭快 [kPanVsRebuild]＝10 倍
/// （实测是 70–370 倍，留了 7 倍以上的余量；两个数在同一次运行里量，机器忙时一起变慢）。
/// 绝对上限 [kPanBudgetMs]＝200 毫秒只是兜底（实测最慢 30 毫秒的 6 倍多），防的是“比例对但都慢得离谱”。
/// 真正防退化的第一道是上面“debugBuilds 不涨”那条断言（和机器无关）：有人把重搭加回来，那条先拦住。
/// 这条测试关掉了读屏用的语义树（semanticsEnabled: false）：手机上不开读屏时就没有它，开着量会把它的开销算进来。
const double kPanBudgetMs = 200;
const double kPanVsRebuild = 10;

void recordPanTiming(double perFrameMs, double perRebuildMs) {
  final file = File('.tmp/pan-timing.log');
  try {
    file.parent.createSync(recursive: true);
    file.writeAsStringSync('${DateTime.now().toIso8601String()} 500 个组件：平移一下 ${perFrameMs.toStringAsFixed(2)} ms，整页重搭一帧 ${perRebuildMs.toStringAsFixed(2)} ms\n', mode: FileMode.append);
  } on FileSystemException {
    // 记不下来不要紧：这只是给人看的参考数。
  }
}
