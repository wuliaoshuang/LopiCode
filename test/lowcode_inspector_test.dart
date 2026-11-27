// 低代码编辑器第 5 版第 2 期（面板合并与就地编辑）的界面测试，390×844。
// 合一面板（常用 / 样式 / 事件，不挡画布、跟着选中走）、预设档、就地改字、长按菜单＋剪贴板、选上一层、
// 图层面板（不自动关 / 折叠 / 拖动排序）、图片从相册和项目文件选。三条验收的步数在“验收”那一组里数。
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/core/safe_file.dart';
import 'package:lopicode/core/templates.dart';
import 'package:lopicode/lowcode/builder_screen.dart';
import 'package:lopicode/lowcode/canvas_view.dart';
import 'package:lopicode/lowcode/editor_clipboard.dart';
import 'package:lopicode/lowcode/editor_workbench_widgets.dart';
import 'package:lopicode/lowcode/inspector_sheet.dart';
import 'package:lopicode/lowcode/layers_sheet.dart';
import 'package:lopicode/lowcode/lift_gesture_widgets.dart';
import 'package:lopicode/lowcode/logic_screen.dart';
import 'package:lopicode/lowcode/model.dart';
import 'package:lopicode/project_session.dart';
import 'package:lopicode/ui/chat_panels.dart';
import 'package:material_ui/material_ui.dart';

import 'support/harness.dart';

/// 一张 1×1 的真 PNG。
final Uint8List kPng = base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==');

Finder k(String key) => find.byKey(ValueKey(key));
Finder node(String id) => k('lowcode-node-$id');
CanvasViewState canvas(WidgetTester tester) => tester.state<CanvasViewState>(find.byType(CanvasView));
EditorWorkbenchState bench(WidgetTester tester) => tester.state<EditorWorkbenchState>(find.byType(EditorWorkbench));

/// 起始页面（root › n1 标题、n2 说明、n3 卡片 › n4 输入框、n5 “提交”按钮）；[doc] 给了就用它。
Future<ProjectSession> openBuilder(WidgetTester tester, {LcDocument? doc}) async {
  usePhoneViewport(tester);
  lcClipboardClear();
  late TestEnv env;
  late ProjectSession session;
  await tester.runAsync(() async {
    env = await TestEnv.create();
    final project = await env.services.projects.create('我的小站', ProjectTemplate.lowcode);
    session = ProjectSession(env.services, project);
    if (doc != null) File(session.guard.resolve(kLowcodePageFile)).writeAsStringSync(doc.encode());
  });
  addTearDown(() async {
    pickImagesOverride = null;
    await pendingWrites();
    session.dispose();
    await env.dispose();
  });
  await tester.pumpWidget(appFor(env, BuilderScreen(session: session)));
  await settle(tester, rounds: 6);
  return session;
}

/// 存盘以后页面文件里的文档。
Future<LcDocument> saved(WidgetTester tester, ProjectSession session) async {
  await waitLowcodeSaved(tester);
  late String text;
  await tester.runAsync(() async => text = File(session.guard.resolve(kLowcodePageFile)).readAsStringSync());
  return LcDocument.parse(text);
}

/// 把面板里的一项滚进来（滚完要等一帧，位置才是新的）。
Future<void> show(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pump();
}

Future<void> tap(WidgetTester tester, Finder f) async {
  await tester.tap(f);
  await settle(tester, rounds: 2);
}

/// 长按不挪就松手。
Future<void> longPress(WidgetTester tester, Finder f) async {
  final g = await tester.startGesture(tester.getCenter(f));
  await tester.pump(kLcLiftAfter + const Duration(milliseconds: 40));
  await tester.pump();
  await g.up();
  await tester.pumpAndSettle();
}

bool undoEnabled(WidgetTester tester) => tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.undo)).onPressed != null;

Future<void> undo(WidgetTester tester) => tap(tester, find.byTooltip('撤销'));

LcDocument imageDoc() => LcDocument(
  title: '图',
  root: LcNode(
    id: 'root',
    type: 'page',
    props: Map.of(lcSpecs['page']!.defaults),
    children: [
      LcNode(id: 'img', type: 'image', props: Map.of(lcSpecs['image']!.defaults)..remove('src')),
      LcNode(id: 't', type: 'text', props: {'text': '字'}),
    ],
  ),
);

void main() {
  group('验收', () {
    testWidgets('改按钮文字：点一下已经选中的按钮就能直接打字（1 步）；没选中时是点两下', (tester) async {
      final session = await openBuilder(tester);
      await tap(tester, node('n5')); // 选中
      expect(k('lc-inline-edit'), findsNothing);
      await tap(tester, node('n5')); // ← 这一步
      expect(k('lc-inline-edit'), findsOneWidget);
      final field = tester.widget<TextField>(k('lc-inline-edit'));
      expect(field.controller!.text, '提交');
      expect(field.controller!.selection, const TextSelection(baseOffset: 0, extentOffset: 2), reason: '原来的字全选着，直接打字就替换');
      expect(field.focusNode!.hasFocus, isTrue);
      await tester.enterText(k('lc-inline-edit'), '立即报名');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await settle(tester, rounds: 2);
      expect(k('lc-inline-edit'), findsNothing);
      expect((await saved(tester, session)).find('n5')!.props['text'], '立即报名');
      expect(find.descendant(of: node('n5'), matching: find.text('立即报名')), findsOneWidget);
      // 整次只记一条撤销
      await undo(tester);
      expect((await saved(tester, session)).find('n5')!.props['text'], '提交');
      expect(undoEnabled(tester), isFalse);
    });

    testWidgets('改内边距：面板开着时，选中 → 点档（2 步）；页面文件里写的是和旧“属性”面板一样的 padding', (tester) async {
      final session = await openBuilder(tester);
      // 先开过一次面板（之后它跟着选中走）。
      await tap(tester, node('n1'));
      await tap(tester, find.widgetWithText(FilledButton, '常用'));
      expect(k('lc-inspector'), findsOneWidget);
      // 第 1 步：点画布上的卡片——面板没关，直接换成卡片的。
      await tap(tester, node('n3'));
      expect(tester.widget<Text>(k('lc-inspector-title')).data, '卡片');
      // 第 2 步：点档。
      await tap(tester, k('lc-preset-padding-24'));
      final doc = await saved(tester, session);
      expect(doc.find('n3')!.props['padding'], 24);
      expect(doc.find('n3')!.style.containsKey('padding'), isFalse);
      await undo(tester);
      expect((await saved(tester, session)).find('n3')!.props['padding'], isNot(24));
    });

    testWidgets('取消选中面板让开，再选中它自己回来（仍是 2 步）；亲手收起以后不再自己出来', (tester) async {
      await openBuilder(tester);
      await tap(tester, node('n3'));
      await tap(tester, find.widgetWithText(FilledButton, '常用'));
      canvas(tester).widget.onSelect(null);
      await settle(tester, rounds: 2);
      expect(k('lc-inspector'), findsNothing);
      await tap(tester, node('n1'));
      expect(k('lc-inspector'), findsOneWidget);
      expect(tester.widget<Text>(k('lc-inspector-title')).data, '文本');
      await tap(tester, k('lc-inspector-close'));
      expect(k('lc-inspector'), findsNothing);
      await tap(tester, node('n2'));
      expect(k('lc-inspector'), findsNothing);
      expect(k('lc-selection-bar'), findsOneWidget);
    });

    testWidgets('图片能从相册放进来：拷进项目的 images/，地址写相对路径，画布上显示出来', (tester) async {
      final session = await openBuilder(tester, doc: imageDoc());
      var asked = 0;
      pickImagesOverride = ({required bool camera}) async {
        asked++;
        expect(camera, isFalse);
        return [PickedImage('IMG_0001.png', kPng)];
      };
      await tap(tester, node('img'));
      await tap(tester, find.widgetWithText(FilledButton, '常用'));
      await tester.tap(k('lc-common-src-gallery'));
      await settle(tester, rounds: 6);
      expect(asked, 1);
      final doc = await saved(tester, session);
      expect(doc.find('img')!.props['src'], 'images/IMG_0001.png');
      late bool exists;
      late List<int> bytes;
      late String html;
      await tester.runAsync(() async {
        final f = File(session.guard.resolve('images/IMG_0001.png'));
        exists = f.existsSync();
        bytes = exists ? f.readAsBytesSync() : const [];
        html = File(session.guard.resolve('index.html')).readAsStringSync();
      });
      expect(exists, isTrue);
      expect(bytes, kPng);
      expect(html, contains('src="images/IMG_0001.png"'), reason: '导出的网页和图片文件在同一层，直接能显示');
      final image = tester.widget<Image>(find.descendant(of: node('img'), matching: find.byType(Image)));
      expect((image.image as FileImage).file.path, session.guard.resolve('images/IMG_0001.png'));
      // 取消选图：什么都不变
      pickImagesOverride = ({required bool camera}) async => [];
      await tester.tap(k('lc-common-src-gallery'));
      await settle(tester, rounds: 4);
      expect((await saved(tester, session)).find('img')!.props['src'], 'images/IMG_0001.png');
    });
  });

  group('合一面板', () {
    testWidgets('选中条：选上一层 + 名字在左；常用（实心）/ 样式（描边）/ 逻辑（文字）/ ⋯ 在右，打开的是同一张面板的三页', (tester) async {
      await openBuilder(tester);
      await tap(tester, node('n5'));
      Finder inBar(Finder f) => find.descendant(of: k('lc-selection-bar'), matching: f);
      final xs = [
        tester.getCenter(inBar(find.byTooltip('选上一层'))).dx,
        tester.getCenter(inBar(find.text('按钮'))).dx,
        tester.getCenter(inBar(find.widgetWithText(FilledButton, '常用'))).dx,
        tester.getCenter(inBar(find.widgetWithText(OutlinedButton, '样式'))).dx,
        tester.getCenter(inBar(find.widgetWithText(TextButton, '逻辑'))).dx,
        tester.getCenter(inBar(find.byTooltip('更多操作'))).dx,
      ];
      expect(xs, [...xs]..sort());
      expect(tester.getRect(inBar(find.byTooltip('更多操作'))).right, lessThanOrEqualTo(390));
      expect(find.text('属性'), findsNothing, reason: '“属性”和“样式”合成一张了');

      await tap(tester, inBar(find.widgetWithText(OutlinedButton, '样式')));
      expect(bench(tester).inspector!.page, InspectorPage.style);
      expect(k('lc-tab-size'), findsOneWidget);
      await tap(tester, k('lc-page-common'));
      expect(bench(tester).inspector!.page, InspectorPage.common);
      expect(k('lc-common-text'), findsOneWidget);
      await tap(tester, k('lc-page-events'));
      expect(k('lc-event-add-click'), findsOneWidget);
      expect(find.byType(InspectorPanel), findsOneWidget);
    });

    testWidgets('面板不挡画布：贴在工具条上面，上面露着的画布能点；选中的组件被滚到面板上方；撤销一直够得着', (tester) async {
      await openBuilder(tester);
      await tap(tester, node('n5'));
      await tap(tester, find.widgetWithText(FilledButton, '常用'));
      await tester.pumpAndSettle();
      final panel = tester.getRect(k('lc-inspector')), toolbar = tester.getRect(k('lc-toolbar'));
      expect(panel.bottom, toolbar.top);
      expect(panel.top, greaterThan(300), reason: '上面至少留出三百多像素的画布');
      expect(tester.getRect(node('n5')).bottom, lessThanOrEqualTo(panel.top), reason: '选中的按钮没被面板盖住');
      expect(find.byTooltip('撤销').hitTestable(), findsOneWidget);
      // 改一个值 → 画布马上变，撤销能点
      await tap(tester, k('lc-common-variant-outline'));
      expect(undoEnabled(tester), isTrue);
      await undo(tester);
      expect(k('lc-inspector'), findsOneWidget, reason: '撤销以后面板还在');
    });

    testWidgets('返回键先收面板，不退出搭建页；再按才是原来的返回', (tester) async {
      await openBuilder(tester);
      await tap(tester, node('n1'));
      await tap(tester, find.widgetWithText(FilledButton, '常用'));
      await tester.binding.handlePopRoute();
      await settle(tester, rounds: 2);
      expect(k('lc-inspector'), findsNothing);
      expect(find.byType(BuilderScreen), findsOneWidget);
    });

    testWidgets('各类型的“常用”页都画得出来、不溢出；每一项都有地方改', (tester) async {
      final doc = LcDocument.starter('全');
      for (final type in ['container', 'row', 'column', 'card', 'text', 'button', 'image', 'input', 'list', 'divider', 'spacer']) {
        doc.insert(doc.root.id, doc.newNode(type));
      }
      await openBuilder(tester, doc: doc);
      await tap(tester, node(doc.root.children.first.id));
      await tap(tester, find.widgetWithText(FilledButton, '常用'));
      final ids = <String>[doc.root.id];
      void walk(LcNode n) {
        for (final c in n.children) {
          ids.add(c.id);
          walk(c);
        }
      }

      walk(doc.root);
      for (final id in ids) {
        canvas(tester).widget.onSelect(id);
        await settle(tester, rounds: 2);
        expect(tester.takeException(), isNull, reason: '$id（${doc.find(id)!.type}）的常用页出了异常');
        expect(tester.widget<Text>(k('lc-inspector-title')).data, doc.find(id)!.spec.label);
        await tap(tester, k('lc-page-style'));
        expect(tester.takeException(), isNull, reason: '$id 的样式页出了异常');
        await tap(tester, k('lc-page-common'));
      }
    });

    testWidgets('预设档：常用几档一行；“…”展开整条刻度和数字框；刻度外的值也能填；能清掉', (tester) async {
      final session = await openBuilder(tester);
      await tap(tester, node('n3'));
      await tap(tester, find.widgetWithText(FilledButton, '常用'));
      for (final v in [0, 8, 16, 24]) {
        expect(k('lc-preset-padding-$v'), findsOneWidget);
      }
      expect(k('lc-scale-padding-48'), findsNothing);
      await tap(tester, k('lc-preset-padding-more'));
      await show(tester, k('lc-scale-padding-48'));
      await tap(tester, k('lc-scale-padding-48'));
      expect((await saved(tester, session)).find('n3')!.props['padding'], 48);
      await show(tester, k('lc-num-padding'));
      await tester.enterText(k('lc-num-padding'), '13');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await settle(tester, rounds: 3);
      expect((await saved(tester, session)).find('n3')!.props['padding'], 13);
      await tap(tester, k('lc-num-padding-plus'));
      await tester.pump(const Duration(milliseconds: 450)); // 加减和打字一样，停手 0.4 秒才交（按住连加只记一条撤销）
      await settle(tester, rounds: 2);
      expect((await saved(tester, session)).find('n3')!.props['padding'], 14);
    });

    testWidgets('“事件”页：列出这个组件能响应的事；“加逻辑”建好帽子直接进积木页；回来以后“逻辑”带小圆点', (tester) async {
      final session = await openBuilder(tester);
      await tap(tester, node('n5'));
      expect(k('lc-action-dot'), findsNothing);
      await tap(tester, find.widgetWithText(TextButton, '逻辑'));
      expect(k('lc-event-add-click'), findsOneWidget);
      expect(k('lc-event-add-load'), findsNothing, reason: '按钮没有“页面打开时”');
      await tester.tap(k('lc-event-add-click'));
      await tester.pumpAndSettle();
      expect(find.byType(LogicScreen), findsOneWidget);
      final doc = await saved(tester, session);
      expect(doc.logic.handlersFor('n5').map((h) => h.event).toList(), ['click']);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(LogicScreen), findsNothing);
      await tap(tester, k('lc-inspector-close'));
      expect(k('lc-action-dot'), findsOneWidget);
    });

    testWidgets('面板里改到一半就点了另一个组件：没提交的字算在原来那个组件上', (tester) async {
      final session = await openBuilder(tester);
      await tap(tester, node('n1'));
      await tap(tester, find.widgetWithText(FilledButton, '常用'));
      await tester.enterText(k('lc-common-text'), '新标题');
      await tester.pump(const Duration(milliseconds: 50)); // 还没到自动提交的时间
      await tap(tester, node('n2'));
      final doc = await saved(tester, session);
      expect(doc.find('n1')!.props['text'], '新标题');
      expect(doc.find('n2')!.props['text'], isNot('新标题'));
    });
  });

  group('就地改字', () {
    testWidgets('文字、按钮、输入框（改提示文字）能就地改；别的组件点第二下没有输入框', (tester) async {
      final session = await openBuilder(tester);
      for (final (id, value) in [('n1', '大标题'), ('n4', '写点什么')]) {
        await tap(tester, node(id));
        await tap(tester, node(id));
        expect(k('lc-inline-edit'), findsOneWidget, reason: id);
        await tester.enterText(k('lc-inline-edit'), value);
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await settle(tester, rounds: 2);
      }
      final doc = await saved(tester, session);
      expect(doc.find('n1')!.props['text'], '大标题');
      expect(doc.find('n4')!.props['placeholder'], '写点什么');
      // 卡片的正中间落在里面还选中着的输入框的拖柄上（拖柄能按的范围比看到的大）：这一下走的是拖柄的“点穿”，
      // 照样选中手指下面的卡片——所以按位置点，不用 tap(node)（那样测试框架会警告“点击可能没点中”）。
      await tester.tapAt(tester.getCenter(node('n3')));
      await settle(tester, rounds: 2);
      expect(tester.widget<CanvasView>(find.byType(CanvasView)).selected, 'n3');
      await tester.tapAt(tester.getRect(node('n3')).topLeft + const Offset(4, 4));
      await settle(tester, rounds: 2);
      expect(k('lc-inline-edit'), findsNothing);
    });

    testWidgets('输入框就盖在组件原来的位置上；点别处＝提交；没改就不记撤销', (tester) async {
      final session = await openBuilder(tester);
      await tap(tester, node('n1'));
      await tap(tester, node('n1'));
      final nodeRect = tester.getRect(node('n1')), edit = tester.getRect(k('lc-inline-edit'));
      expect((edit.top - nodeRect.top).abs(), lessThan(12));
      expect(edit.left, greaterThanOrEqualTo(nodeRect.left - 1));
      // 没改，点别处
      await tap(tester, node('n2'));
      expect(k('lc-inline-edit'), findsNothing);
      expect(undoEnabled(tester), isFalse);
      // 改了，点别处
      await tap(tester, node('n1'));
      await tap(tester, node('n1'));
      await tester.enterText(k('lc-inline-edit'), '改过了');
      await tap(tester, node('n2'));
      expect(k('lc-inline-edit'), findsNothing);
      expect((await saved(tester, session)).find('n1')!.props['text'], '改过了');
    });
  });

  group('长按菜单和剪贴板', () {
    testWidgets('长按不挪就松手＝出菜单（并选中它）；一开始“粘贴”是灰的；菜单里没有上移 / 下移，“⋯”里有', (tester) async {
      await openBuilder(tester);
      await longPress(tester, node('n5'));
      for (final label in ['复制', '粘贴到它后面', '重复一份', '包成容器', '存成组件', '删除']) {
        expect(find.widgetWithText(PopupMenuItem<String>, label), findsOneWidget, reason: label);
      }
      expect(find.text('上移'), findsNothing);
      expect(tester.widget<PopupMenuItem<String>>(find.widgetWithText(PopupMenuItem<String>, '粘贴到它后面')).enabled, isFalse);
      final ys = [
        for (final l in ['复制', '重复一份', '包成容器', '删除']) tester.getCenter(find.text(l)).dy,
      ];
      expect(ys, [...ys]..sort(), reason: '删除在最后');
      await tester.tapAt(const Offset(5, 5)); // 点外面关掉
      await tester.pumpAndSettle();
      expect(find.descendant(of: k('lc-selection-bar'), matching: find.text('按钮')), findsOneWidget);
      await tap(tester, find.byTooltip('更多操作'));
      await tester.pumpAndSettle();
      for (final label in ['复制', '粘贴到它后面', '重复一份', '包成容器', '存成组件', '上移', '下移', '删除']) {
        expect(find.widgetWithText(PopupMenuItem<String>, label), findsOneWidget, reason: label);
      }
    });

    testWidgets('复制 → 长按别的组件 → 粘贴到它后面：多出一份一样的，一条撤销；复制本身不记撤销', (tester) async {
      final session = await openBuilder(tester);
      await longPress(tester, node('n5'));
      await tester.tap(find.widgetWithText(PopupMenuItem<String>, '复制'));
      await tester.pumpAndSettle();
      expect(undoEnabled(tester), isFalse);
      // “已复制”那句提示浮在选中条上面，不盖工具条：撤销 / 重做 / 图层照样点得到
      expect(find.textContaining('已复制'), findsOneWidget);
      expect(tester.getRect(find.textContaining('已复制')).bottom, lessThanOrEqualTo(tester.getRect(k('lc-toolbar')).top));
      for (final tip in ['图层', '撤销', '重做', '预览']) {
        expect(find.byTooltip(tip).hitTestable(), findsOneWidget, reason: tip);
      }
      await longPress(tester, node('n1'));
      expect(tester.widget<PopupMenuItem<String>>(find.widgetWithText(PopupMenuItem<String>, '粘贴到它后面')).enabled, isTrue);
      await tester.tap(find.widgetWithText(PopupMenuItem<String>, '粘贴到它后面'));
      await tester.pumpAndSettle();
      var doc = await saved(tester, session);
      expect(doc.root.children.map((n) => n.type).toList(), ['text', 'button', 'text', 'card']);
      expect(doc.root.children[1].props['text'], '提交');
      expect(doc.root.children[1].id, isNot('n5'));
      await undo(tester);
      doc = await saved(tester, session);
      expect(doc.root.children.map((n) => n.type).toList(), ['text', 'text', 'card']);
    });

    testWidgets('重复一份、包成容器、删除', (tester) async {
      final session = await openBuilder(tester);
      await longPress(tester, node('n2'));
      await tester.tap(find.widgetWithText(PopupMenuItem<String>, '重复一份'));
      await tester.pumpAndSettle();
      var doc = await saved(tester, session);
      expect(doc.root.children.map((n) => n.type).toList(), ['text', 'text', 'text', 'card']);
      await longPress(tester, node('n1'));
      await tester.tap(find.widgetWithText(PopupMenuItem<String>, '包成容器'));
      await tester.pumpAndSettle();
      doc = await saved(tester, session);
      expect(doc.root.children.first.type, 'container');
      expect(doc.root.children.first.children.single.id, 'n1');
      expect(
        find.descendant(of: k('lc-selection-bar'), matching: find.text('容器')),
        findsOneWidget,
        reason: '包完选中的是新容器',
      );
      await longPress(tester, node('n2'));
      await tester.tap(find.widgetWithText(PopupMenuItem<String>, '删除'));
      await tester.pumpAndSettle();
      doc = await saved(tester, session);
      expect(doc.find('n2'), isNull);
    });

    testWidgets('长按以后挪了（超过 8 像素）是拖动，不出菜单', (tester) async {
      await openBuilder(tester);
      final g = await tester.startGesture(tester.getCenter(node('n2')));
      await tester.pump(kLcLiftAfter + const Duration(milliseconds: 40));
      await tester.pump();
      await g.moveBy(const Offset(0, 30));
      await tester.pump(const Duration(milliseconds: 16));
      await g.moveBy(const Offset(0, -30));
      await tester.pump(const Duration(milliseconds: 16));
      await g.up();
      await tester.pumpAndSettle();
      expect(find.byType(PopupMenuItem<String>), findsNothing);
    });

    testWidgets('页面本身：剪贴板里有东西时“⋯”里只有“粘贴到页面里”', (tester) async {
      final session = await openBuilder(tester);
      canvas(tester).widget.onSelect('root');
      await settle(tester, rounds: 2);
      expect(find.byTooltip('更多操作'), findsNothing);
      expect(find.byTooltip('选上一层'), findsNothing);
      await longPress(tester, node('n1'));
      await tester.tap(find.widgetWithText(PopupMenuItem<String>, '复制'));
      await tester.pumpAndSettle();
      canvas(tester).widget.onSelect('root');
      await settle(tester, rounds: 2);
      await tap(tester, find.byTooltip('更多操作'));
      await tester.pumpAndSettle();
      expect(find.byType(PopupMenuItem<String>), findsOneWidget);
      await tester.tap(find.widgetWithText(PopupMenuItem<String>, '粘贴到页面里'));
      await tester.pumpAndSettle();
      final doc = await saved(tester, session);
      expect(doc.root.children.map((n) => n.type).toList(), ['text', 'text', 'card', 'text']);
    });
  });

  group('选上一层', () {
    testWidgets('一下一层：按钮 → 卡片 → 页面；到页面就没有这个按钮了', (tester) async {
      await openBuilder(tester);
      await tap(tester, node('n5'));
      Finder name(String s) => find.descendant(of: k('lc-selection-bar'), matching: find.text(s));
      await tap(tester, k('lc-select-parent'));
      expect(name('卡片'), findsOneWidget);
      expect(canvas(tester).widget.selected, 'n3');
      await tap(tester, k('lc-select-parent'));
      expect(name('页面'), findsOneWidget);
      expect(k('lc-select-parent'), findsNothing);
      expect(tester.getSize(k('lc-selection-bar')).height, kEditorSelectionBarHeight);
    });
  });

  group('图层面板', () {
    testWidgets('点一行：选中、画布跟过去、面板不关；带逻辑的行有 ⚡', (tester) async {
      final doc = LcDocument.starter('层');
      doc.logic.addHandler('click', target: 'n5');
      await openBuilder(tester, doc: doc);
      await tap(tester, find.byTooltip('图层'));
      await tester.pumpAndSettle();
      expect(find.byType(LayerSheet), findsOneWidget);
      expect(find.text('图层 · 6 个组件'), findsOneWidget);
      expect(k('lc-layer-logic-n5'), findsOneWidget);
      expect(k('lc-layer-logic-n1'), findsNothing);
      await tap(tester, k('lc-layer-n5'));
      expect(find.byType(LayerSheet), findsOneWidget, reason: '点一行面板不关');
      expect(canvas(tester).widget.selected, 'n5');
      await tap(tester, k('lc-layer-n1'));
      expect(find.byType(LayerSheet), findsOneWidget);
      expect(canvas(tester).widget.selected, 'n1');
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(LayerSheet), findsNothing);
      expect(find.descendant(of: k('lc-selection-bar'), matching: find.text('文本')), findsOneWidget);
    });

    testWidgets('折叠：里面的行收起来；折叠状态记在编辑器自己的文件里，页面文件一个字不变；重新打开还折着', (tester) async {
      final session = await openBuilder(tester);
      late String before;
      await tester.runAsync(() async => before = File(session.guard.resolve(kLowcodePageFile)).readAsStringSync());
      await tap(tester, find.byTooltip('图层'));
      await tester.pumpAndSettle();
      expect(k('lc-layer-fold-n1'), findsNothing, reason: '没有内容的没有折叠箭头');
      await tap(tester, k('lc-layer-fold-n3'));
      expect(k('lc-layer-n4'), findsNothing);
      expect(k('lc-layer-n5'), findsNothing);
      expect(find.text('2 个在里面'), findsOneWidget);
      await settle(tester, rounds: 4);
      late String state, after;
      await tester.runAsync(() async {
        state = File(session.guard.resolve('.lopicode/lowcode-editor.json', allowReserved: true)).readAsStringSync();
        after = File(session.guard.resolve(kLowcodePageFile)).readAsStringSync();
      });
      expect((jsonDecode(state) as Map)['layersCollapsed'], ['n3']);
      expect(after, before);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tap(tester, find.byTooltip('图层'));
      await tester.pumpAndSettle();
      expect(k('lc-layer-n4'), findsNothing, reason: '重新打开还折着');
      await tap(tester, k('lc-layer-fold-n3'));
      expect(k('lc-layer-n4'), findsOneWidget);
    });

    testWidgets('拖动排序：按住一行往上拖，蓝线提示落点，松手才挪，一条撤销；拖到容器右半边＝放进去', (tester) async {
      final session = await openBuilder(tester);
      await tap(tester, find.byTooltip('图层'));
      await tester.pumpAndSettle();
      // n2（说明）拖到 n1（标题）前面
      var g = await tester.startGesture(tester.getCenter(k('lc-layer-n2')));
      await tester.pump(kLcLiftAfter + const Duration(milliseconds: 60));
      final target = tester.getRect(k('lc-layer-n1'));
      await g.moveTo(Offset(60, target.top + 8));
      await tester.pump();
      expect(k('lc-layer-drop-line'), findsOneWidget);
      expect((tester.getRect(k('lc-layer-drop-line')).center.dy - target.top).abs(), lessThan(3));
      expect((await saved(tester, session)).root.children.first.id, 'n1', reason: '没松手不挪');
      await g.up();
      await settle(tester, rounds: 3);
      expect(k('lc-layer-drop-line'), findsNothing);
      var doc = await saved(tester, session);
      expect(doc.root.children.map((n) => n.id).toList(), ['n2', 'n1', 'n3']);
      expect(find.byType(LayerSheet), findsOneWidget);
      final ys = [
        for (final id in ['n2', 'n1', 'n3']) tester.getCenter(k('lc-layer-$id')).dy,
      ];
      expect(ys, [...ys]..sort(), reason: '面板里的顺序跟着变了');
      // n1 拖到卡片那一行的右半边：放进卡片里
      g = await tester.startGesture(tester.getCenter(k('lc-layer-n1')));
      await tester.pump(kLcLiftAfter + const Duration(milliseconds: 60));
      await g.moveTo(Offset(320, tester.getCenter(k('lc-layer-n3')).dy));
      await tester.pump();
      expect(k('lc-layer-drop-line'), findsNothing, reason: '放进去是整行高亮，不是线');
      await g.up();
      await settle(tester, rounds: 3);
      doc = await saved(tester, session);
      expect(doc.root.children.map((n) => n.id).toList(), ['n2', 'n3']);
      expect(doc.find('n3')!.children.map((n) => n.id).toList(), ['n4', 'n5', 'n1']);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await undo(tester);
      doc = await saved(tester, session);
      expect(doc.root.children.map((n) => n.id).toList(), ['n2', 'n1', 'n3'], reason: '一次拖动一条撤销');
    });
  });

  group('图片', () {
    testWidgets('从项目文件选：列出项目里的图片，点一张就用它', (tester) async {
      final session = await openBuilder(tester, doc: imageDoc());
      await tester.runAsync(() async {
        for (final f in ['images/banner.png', 'pic/logo.png']) {
          File(session.guard.resolve(f))
            ..parent.createSync(recursive: true)
            ..writeAsBytesSync(kPng);
        }
      });
      await tap(tester, node('img'));
      await tap(tester, find.widgetWithText(FilledButton, '常用'));
      await tester.tap(k('lc-common-src-project'));
      await settle(tester, rounds: 6);
      await tester.pumpAndSettle();
      expect(find.text('项目里的图片 · 2 张'), findsOneWidget);
      await tester.tap(k('lc-project-image-pic/logo.png'));
      await tester.pumpAndSettle();
      expect((await saved(tester, session)).find('img')!.props['src'], 'pic/logo.png');
      expect(find.text('项目里的图片 · 2 张'), findsNothing);
    });

    testWidgets('项目里一张图都没有：说清楚怎么办', (tester) async {
      await openBuilder(tester, doc: imageDoc());
      await tap(tester, node('img'));
      await tap(tester, find.widgetWithText(FilledButton, '常用'));
      await tester.tap(k('lc-common-src-project'));
      await settle(tester, rounds: 6);
      await tester.pumpAndSettle();
      expect(find.text('项目里还没有图片'), findsOneWidget);
    });

    testWidgets('地址写坏了（跑出项目、文件不在）：画布显示坏图，不崩', (tester) async {
      final doc = imageDoc();
      doc.find('img')!.props['src'] = '../../secret.png';
      doc.insert('root', LcNode(id: 'img2', type: 'image', props: {'src': 'images/没有.png', 'height': 80}));
      await openBuilder(tester, doc: doc);
      await settle(tester, rounds: 3);
      expect(tester.takeException(), isNull);
      expect(find.descendant(of: node('img'), matching: find.byIcon(Icons.broken_image_outlined)), findsOneWidget);
      expect(find.descendant(of: node('img2'), matching: find.byIcon(Icons.broken_image_outlined)), findsOneWidget);
    });
  });
}
