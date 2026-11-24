// 低代码画布（第 2 版）：样式换算的单元测试 + 画布在 390×844 上的界面测试。
// 设置环境变量 LOPI_SHOTS=1 时把截图写到 docs/screenshots/lc-canvas-*.png。
//   LOPI_SHOTS=1 flutter test --no-pub test/lowcode_canvas_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/core/templates.dart';
import 'package:lopicode/lowcode/builder_screen.dart';
import 'package:lopicode/lowcode/canvas_css.dart';
import 'package:lopicode/lowcode/canvas_view.dart';
import 'package:lopicode/lowcode/logic_edit.dart';
import 'package:lopicode/lowcode/logic_screen.dart';
import 'package:lopicode/lowcode/model.dart';
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

/// 存盘里的页面（搭建页每次修改都会存）。
Future<LcDocument> savedDoc(WidgetTester tester, ProjectSession session) async {
  await settle(tester, rounds: 3);
  late LcDocument doc;
  await tester.runAsync(() async => doc = LcDocument.parse(File(session.guard.resolve(kLowcodePageFile)).readAsStringSync()));
  return doc;
}

Finder node(String id) => find.byKey(ValueKey('lowcode-node-$id'));
Finder handle(String name) => find.byKey(ValueKey('lowcode-handle-$name'));
CanvasViewState canvas(WidgetTester tester) => tester.state<CanvasViewState>(find.byType(CanvasView));
bool undoEnabled(WidgetTester tester) => tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.undo)).onPressed != null;

Future<void> select(WidgetTester tester, String id) async {
  await tester.tap(node(id));
  await settle(tester, rounds: 2);
}

Future<void> moreAction(WidgetTester tester, String label) async {
  await tester.tap(find.byTooltip('更多操作'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
  await settle(tester, rounds: 2);
}

Future<void> topMenu(WidgetTester tester, String label) async {
  await tester.tap(find.byTooltip('更多'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

LcNode text(String s, {Map<String, String>? style, String id = ''}) => LcNode(id: id, type: 'text', props: {'text': s}, style: style);

/// 一张用了各种样式的页面（截图和“不抛异常”都用它）。
LcDocument richDoc() => LcDocument(
  title: '样式大全',
  root: LcNode(
    id: 'root',
    type: 'page',
    props: Map.of(lcSpecs['page']!.defaults),
    children: [
      text(
        '大标题 · 下划线',
        style: {'font-size': '1.5em', 'font-weight': '700', 'color': 'rgb(41, 98, 203)', 'letter-spacing': '2px', 'text-decoration-line': 'underline', 'text-align': 'center', 'align-self': 'stretch'},
      ),
      LcNode(
        id: '',
        type: 'container',
        props: {'width': 'fill'},
        style: {
          'padding-top': '8px',
          'padding-right': '16px',
          'padding-bottom': '24px',
          'padding-left': '32px',
          'margin-top': '4px',
          'margin-bottom': '12px',
          'border-top-width': '4px',
          'border-top-style': 'solid',
          'border-top-color': '#e0457b',
          'border-left-width': '1px',
          'border-left-style': 'dashed',
          'border-left-color': '#e0457b',
          'border-top-left-radius': '16px',
          'border-bottom-right-radius': '24px',
          'background-color': '#fff7e6',
          'box-shadow': '0 4px 12px rgba(0,0,0,0.25)',
          'color': '#7a4b00',
          'font-style': 'italic',
        },
        children: [
          text('四边不同的内边距、上边框、两个圆角、阴影'),
          text('半透明 60%', style: {'opacity': '0.6', 'line-height': '2'}),
        ],
      ),
      LcNode(
        id: '',
        type: 'row',
        props: {'width': 'fill', 'gap': 8},
        style: {'justify-content': 'space-between', 'align-items': 'stretch', 'background-color': '#eef3ff', 'padding-top': '8px', 'padding-bottom': '8px'},
        children: [
          text('两端', id: 'j1', style: {'background-color': '#c9d8ff', 'padding-left': '8px', 'padding-right': '8px'}),
          text('对齐', id: 'j2', style: {'background-color': '#c9d8ff', 'padding-left': '8px', 'padding-right': '8px', 'font-size': '28px'}),
          text('拉伸', id: 'j3', style: {'background-color': '#c9d8ff', 'padding-left': '8px', 'padding-right': '8px'}),
        ],
      ),
      LcNode(
        id: '',
        type: 'container',
        props: {'width': 'fill'},
        style: {'flex-direction': 'row-reverse', 'flex-wrap': 'wrap', 'row-gap': '6px', 'column-gap': '6px'},
        children: [
          for (var i = 1; i <= 7; i++)
            LcNode(
              id: '',
              type: 'button',
              props: {...lcSpecs['button']!.defaults, 'text': '第 $i 个'},
              style: i == 2 ? {'border-top-width': '2px', 'border-top-style': 'solid', 'border-top-color': '#000', 'background-color': '#ffd24d', 'color': '#000'} : null,
            ),
        ],
      ),
      LcNode(
        id: '',
        type: 'row',
        props: {'width': 'fill', 'gap': 8},
        children: [
          text('占 1 份', id: 'g1', style: {'flex-grow': '1', 'background-color': '#d9f5e5', 'text-align': 'center'}),
          text('占 2 份', id: 'g2', style: {'flex-grow': '2', 'background-color': '#b5ebd0', 'text-align': 'center'}),
          text('删除线', style: {'text-decoration-line': 'line-through'}),
        ],
      ),
      LcNode(
        id: 'pct',
        type: 'container',
        style: {
          'width': '60%',
          'height': '48px',
          'overflow-x': 'hidden',
          'overflow-y': 'hidden',
          'background-color': '#ffe3e3',
          'border-top-left-radius': '50%',
          'border-top-right-radius': '50%',
          'border-bottom-right-radius': '50%',
          'border-bottom-left-radius': '50%',
        },
        children: [text('宽 60%、高 48、超出裁掉。这一行很长很长很长很长很长很长很长很长很长很长很长很长')],
      ),
      text('已隐藏的文字', style: {'display': 'none'}),
      text('相对定位：右移 24', style: {'position': 'relative', 'left': '24px', 'top': '4px', 'background-color': '#e9e2ff'}),
      text('绝对定位（按普通位置画）', style: {'position': 'absolute', 'top': '0', 'left': '0'}),
      text('靠右', style: {'align-self': 'flex-end', 'max-width': '120px', 'min-height': '40px', 'background-color': '#e2f1ff'}),
      LcNode(
        id: '',
        type: 'input',
        props: Map.of(lcSpecs['input']!.defaults),
        style: {'background-color': '#fffbe6', 'border-top-style': 'solid', 'border-top-width': '2px', 'border-top-color': '#d98a0b'},
      ),
      LcNode(id: '', type: 'component', props: {'ref': 'c1'}),
      LcNode(id: '', type: 'divider', style: {'border-top-style': 'solid', 'border-top-width': '3px', 'border-top-color': '#2962cb'}),
      LcNode(id: '', type: 'list', props: Map.of(lcSpecs['list']!.defaults), style: {'font-weight': 'bold', 'color': '#058654'}),
    ],
  ),
);

/// 各种怪值：换算不了的、类型不对的、自相矛盾的、大得离谱的。画布要一条条忽略，不能崩。
const List<Map<String, String>> weirdStyles = [
  {'width': 'calc(100% - 8px)', 'height': 'var(--h)', 'margin-top': '-40px', 'padding-left': 'auto'},
  {'width': '999999999px', 'height': '1e30px', 'font-size': '-3px', 'line-height': 'banana'},
  {'width': '0', 'height': '0', 'min-width': '500px', 'max-width': '10px', 'min-height': '300px', 'max-height': '1px'},
  {'opacity': '7', 'flex-grow': 'NaN', 'z-index': 'top', 'font-weight': '12345'},
  {'border-top-width': '9999px', 'border-top-style': 'groove', 'border-top-color': 'notacolor', 'border-left-style': 'solid', 'border-left-color': 'red', 'border-top-left-radius': '50%'},
  {'box-shadow': '0 0 0 0, 1px 1px red', 'background-color': 'url(x)', 'color': 'transparent'},
  {'box-shadow': 'inset 0 0 99999px 99999px red', 'letter-spacing': '-100px', 'text-align': 'middle'},
  {'display': 'grid', 'flex-direction': 'diagonal', 'flex-wrap': 'wrap-reverse', 'justify-content': 'stretch', 'align-items': 'baseline', 'row-gap': '-5px', 'column-gap': '200%'},
  {'position': 'fixed', 'top': '-9999px', 'left': '50%', 'align-self': 'stretch', 'flex-grow': '3'},
  {'position': 'relative', 'right': '100000px', 'bottom': 'calc(1px)', 'overflow-x': 'scroll'},
  {'height': '100%', 'width': '150%', 'flex-grow': '1', 'align-self': 'center'},
  {'flex-direction': 'column-reverse', 'align-items': 'stretch', 'height': '10px', 'flex-wrap': 'wrap'},
  {'flex-direction': 'row', 'align-items': 'stretch', 'justify-content': 'space-evenly', 'width': '20px'},
  {'display': 'none', 'opacity': '0', 'width': '1px'},
  {'margin-left': '100000px', 'padding-top': '100000px', 'border-top-left-radius': '100000px 5px'},
];

/// 每一组怪值都套在：一个文本、一个按钮、一个输入框、一个带子项的容器、一个行（里面也套一遍）上。
LcDocument weirdDoc() {
  final children = <LcNode>[];
  for (final style in weirdStyles) {
    LcNode leaf(String type) => LcNode(id: '', type: type, props: {...lcSpecs[type]!.defaults}, style: Map.of(style));
    children
      ..add(leaf('text'))
      ..add(leaf('button'))
      ..add(leaf('input'))
      ..add(leaf('image'))
      ..add(leaf('divider'))
      ..add(leaf('spacer'))
      ..add(leaf('list'))
      ..add(LcNode(id: '', type: 'container', props: {'gap': 4}, style: Map.of(style), children: [leaf('text'), leaf('button'), leaf('input')]))
      ..add(
        LcNode(
          id: '',
          type: 'row',
          props: {'gap': 4, 'width': 'fill'},
          style: Map.of(style),
          children: [
            leaf('text'),
            leaf('input'),
            leaf('spacer'),
            LcNode(id: '', type: 'column', style: Map.of(style), children: [leaf('text')]),
          ],
        ),
      )
      ..add(LcNode(id: '', type: 'row', props: {'gap': 4, 'align': 'stretch'}, children: [leaf('text'), leaf('card'), leaf('divider'), leaf('image')]));
  }
  return LcDocument(
    title: '怪值',
    root: LcNode(id: 'root', type: 'page', props: Map.of(lcSpecs['page']!.defaults), children: children),
  );
}

void main() {
  setUpAll(() async => fontsLoaded = await loadRealFonts());

  group('canvas_css：样式换算', () {
    const scale = CssScale(fontSize: 20, pageWidth: 400, pageHeight: 800);

    test('长度换算成像素', () {
      expect(cssPx('12px', scale), 12);
      expect(cssPx('1.5PX', scale), 1.5);
      expect(cssPx('0', scale), 0);
      expect(cssPx('-8px', scale), -8);
      expect(cssPx('50%', scale, percentOf: 300), 150);
      expect(cssPx('50%', scale), isNull, reason: '不知道参照谁，百分比换算不了');
      expect(cssPx('50%', scale, percentOf: double.infinity), isNull);
      expect(cssPx('2em', scale), 40);
      expect(cssPx('2rem', scale), 32);
      expect(cssPx('10vw', scale), 40);
      expect(cssPx('10vh', scale), 80);
    });

    test('怪值一律当没写，不抛异常', () {
      for (final v in [null, '', '  ', 'auto', 'calc(100% - 8px)', 'var(--x)', '12pt', 'px', '12 px', 'banana', 'NaNpx', '1e400px', '--', '12px 4px']) {
        expect(cssPx(v, scale, percentOf: 100), isNull, reason: '$v');
        expect(cssSizePx(v, scale, percentOf: 100), isNull, reason: '$v');
      }
      expect(cssPx('999999999px', scale), kCanvasMaxPx, reason: '大得离谱的压到上限');
      expect(cssSizePx('-1px', scale), isNull, reason: '尺寸不能是负的');
      expect(cssNumber('abc'), isNull);
      expect(cssNumber('NaN'), isNull);
      expect(cssNumber(' 2.5 '), 2.5);
    });

    test('不透明度、字重、行高', () {
      expect(cssOpacity(null), 1);
      expect(cssOpacity('0.4'), 0.4);
      expect(cssOpacity('40%'), 0.4);
      expect(cssOpacity('7'), 1);
      expect(cssOpacity('-2'), 0);
      expect(cssOpacity('x'), 1);
      expect(cssFontWeight('normal'), 400);
      expect(cssFontWeight('bold'), 700);
      expect(cssFontWeight('600'), 600);
      expect(cssFontWeight('650'), 700);
      expect(cssFontWeight('12345'), isNull);
      expect(cssFontWeight('bolder'), isNull);
      expect(cssLineHeight('1.5', scale), 1.5);
      expect(cssLineHeight('30px', scale), 1.5);
      expect(cssLineHeight('150%', scale), 1.5);
      expect(cssLineHeight('normal', scale), isNull);
      expect(cssLineHeight('0', scale), isNull);
      expect(cssLineHeight('-2', scale), isNull);
    });

    test('四边：各不相同；负值和 auto 按 0', () {
      final style = {'margin-top': '4px', 'margin-right': '10%', 'margin-bottom': '-6px', 'margin-left': 'auto'};
      expect(cssEdges(style, 'margin', scale, percentOf: 200), const CssEdges(4, 20, 0, 0));
      expect(cssEdges(const {}, 'padding', scale).isZero, isTrue);
      expect(const CssEdges(1, 2, 3, 4) + const CssEdges(10, 20, 30, 40), const CssEdges(11, 22, 33, 44));
      expect(const CssEdges(1, 2, 3, 4).horizontal, 6);
      expect(const CssEdges(1, 2, 3, 4).vertical, 4);
    });

    test('边框：没写样式就没有边框；宽度关键字', () {
      expect(cssBorderSide({'border-top-width': '2px'}, 'top', scale), isNull, reason: 'CSS 里边框样式默认是 none');
      expect(cssBorderSide({'border-top-width': '2px', 'border-top-style': 'none'}, 'top', scale), isNull);
      expect(cssBorderSide({'border-top-width': '0', 'border-top-style': 'solid'}, 'top', scale), isNull);
      final b = cssBorderSide({'border-top-width': '2px', 'border-top-style': 'dashed', 'border-top-color': '#ff0000'}, 'top', scale)!;
      expect(b.width, 2);
      expect(b.argb, 0xFFFF0000);
      expect(cssBorderSide({'border-left-style': 'solid'}, 'left', scale)!.width, 3, reason: '没写宽度＝medium');
      expect(cssBorderSide({'border-left-style': 'solid', 'border-left-width': 'thin'}, 'left', scale)!.width, 1);
      expect(cssBorderSide({'border-left-style': 'solid', 'border-left-color': 'nope'}, 'left', scale)!.argb, isNull);
      expect(cssBorderWidths({'border-top-width': '2px', 'border-top-style': 'solid', 'border-bottom-width': '5px'}, scale), const CssEdges(2, 0, 0, 0));
    });

    test('圆角、阴影', () {
      expect(cssRadii({'border-top-left-radius': '8px', 'border-bottom-right-radius': '50%', 'border-top-right-radius': '10%', 'border-bottom-left-radius': '6px 12px'}, scale), [8, 0, 9999, 6]);
      final s = cssShadow({'box-shadow': '0 4px 12px 2px rgba(0,0,0,0.5)'}, scale)!;
      expect([s.x, s.y, s.blur, s.spread], [0, 4, 12, 2]);
      expect(s.argb! >> 24, closeTo(128, 1));
      expect(cssShadow({'box-shadow': 'none'}, scale), isNull);
      expect(cssShadow({'box-shadow': 'inset 0 0 4px red'}, scale), isNull, reason: '内阴影画布不画');
      expect(cssShadow({'box-shadow': '0 0 4px red, 0 0 8px blue'}, scale), isNull, reason: '多层不画');
      expect(cssShadow(const {}, scale), isNull);
    });

    test('排列方式与对齐', () {
      expect(cssFlow(const {}, rowByDefault: true).row, isTrue);
      expect(cssFlow(const {}, rowByDefault: false).row, isFalse);
      final f = cssFlow({'flex-direction': 'row-reverse', 'flex-wrap': 'wrap'}, rowByDefault: false);
      expect([f.row, f.reverse, f.wrap], [true, true, true]);
      expect(cssFlow({'flex-direction': 'diagonal'}, rowByDefault: true).row, isTrue, reason: '认不出就用默认');
      expect(cssJustify('space-between'), CssJustify.between);
      expect(cssJustify('flex-end'), CssJustify.end);
      expect(cssJustify('wat'), isNull);
      expect(cssAlign('stretch'), CssAlign.stretch);
      expect(cssAlign('baseline'), CssAlign.start);
      expect(cssAlign('auto'), isNull);
    });

    test('盒子尺寸：百分比参照父内容区；最小值压过最大值', () {
      final b = cssBoxSize({'width': '50%', 'height': '50%', 'min-width': '300px', 'max-width': '100px'}, scale, availWidth: 200);
      expect(b.width, 100);
      expect(b.height, isNull, reason: '父容器高度不知道，百分比高度不生效');
      expect([b.minWidth, b.maxWidth], [300, 300]);
      expect(cssBoxSize({'height': '50%'}, scale, availWidth: 200, availHeight: 80).height, 40);
      expect(cssBoxSize({'width': 'auto', 'height': 'calc(1px)'}, scale, availWidth: 200).isEmpty, isTrue);
    });

    test('裁剪、装饰线、相对定位', () {
      expect(cssClips({'overflow-x': 'hidden'}), isTrue);
      expect(cssClips({'overflow-y': 'visible'}), isFalse);
      expect(cssClips(const {}), isFalse);
      expect(cssDecorationLines({'text-decoration-line': 'underline line-through'}), {'underline', 'line-through'});
      expect(cssDecorationLines({'text-decoration': 'overline dotted red'}), {'overline'});
      expect(cssDecorationLines({'text-decoration-line': 'none'}), isEmpty);
      expect(cssRelativeShift({'left': '10px', 'right': '99px', 'bottom': '5px'}, scale), (dx: 10.0, dy: -5.0));
      expect(cssRelativeShift({'right': '8px'}, scale), (dx: -8.0, dy: 0.0));
      expect(cssRelativeShift({'left': 'auto'}, scale), (dx: 0.0, dy: 0.0));
    });

    test('拖柄改尺寸：只动拖的那个方向，取整，有下限', () {
      expect(resizeByHandle(startWidth: 100, startHeight: 40, dx: 20.4, dy: 9.6, hx: 1, hy: 1), (width: 120, height: 50));
      expect(resizeByHandle(startWidth: 100, startHeight: 40, dx: 20, dy: 10, hx: 1, hy: 0), (width: 120, height: null));
      expect(resizeByHandle(startWidth: 100, startHeight: 40, dx: 20, dy: 10, hx: 0, hy: 1), (width: null, height: 50));
      expect(resizeByHandle(startWidth: 100, startHeight: 40, dx: 20, dy: 10, hx: -1, hy: -1), (width: 80, height: 30), reason: '左 / 上的拖柄往右 / 下拖是变小');
      expect(resizeByHandle(startWidth: 100, startHeight: 40, dx: -500, dy: -500, hx: 1, hy: 1), (width: 8, height: 8));
      expect(resizeByHandle(startWidth: 100, startHeight: 40, dx: double.nan, dy: double.infinity, hx: 1, hy: 1), (width: 100, height: kCanvasMaxPx.round()));
    });
  });

  group('画布界面', () {
    testWidgets('旧页面（没有 style）：排版和第 1 版一样，没有异常', (tester) async {
      await openBuilder(tester);
      expect(tester.takeException(), isNull);
      // 第 1 版画布上量到的尺寸（改造前截图里就是这样）：页面内边距 16、卡片内边距 16、按钮 64×48。
      expect(tester.getTopLeft(node('n1')).dx, 16);
      expect(tester.getSize(node('n3')).width, 390 - 32);
      expect(tester.getSize(node('n4')).width, 390 - 64);
      expect(tester.getSize(node('n5')), const Size(64, 48));
      expect(tester.getTopLeft(node('n5')).dx, 32);
      // 标题、说明、卡片之间是页面的间距 12；卡片里输入框和按钮之间是 8。
      expect(tester.getTopLeft(node('n2')).dy - tester.getBottomLeft(node('n1')).dy, 12);
      expect(tester.getTopLeft(node('n3')).dy - tester.getBottomLeft(node('n2')).dy, 12);
      expect(tester.getTopLeft(node('n5')).dy - tester.getBottomLeft(node('n4')).dy, 8);
      expect(find.byKey(const ValueKey('lowcode-zoom-label')), findsOneWidget);
      expect(find.text('100%'), findsOneWidget);
      // 没选中：没有拖柄、没有操作条
      expect(handle('se'), findsNothing);
      expect(find.text('属性'), findsNothing);
    });

    testWidgets('选中按钮：出现拖柄和尺寸；选中页面：没有拖柄', (tester) async {
      await openBuilder(tester);
      await select(tester, 'n5');
      for (final name in ['nw', 'ne', 'sw', 'se', 'n', 's']) {
        expect(handle(name), findsOneWidget, reason: name);
      }
      expect(handle('w'), findsNothing, reason: '按钮只有 48 高，左右两边的拖柄让给四个角');
      expect(find.text('64 × 48'), findsOneWidget);
      // 拖柄能按的范围至少 32
      expect(tester.getSize(handle('se')), const Size(32, 32));
      expect(tester.takeException(), isNull);

      await tester.tapAt(const Offset(195, 560)); // 页面空白处＝选中页面
      await settle(tester, rounds: 2);
      expect(find.text('页面'), findsOneWidget);
      expect(handle('se'), findsNothing);
      expect(find.byTooltip('更多操作'), findsNothing, reason: '页面不能移动 / 复制 / 删除');
    });

    testWidgets('拖右下角拖柄：写进 style 的 width / height，只多一条撤销', (tester) async {
      final session = await openBuilder(tester);
      await select(tester, 'n5');
      expect(undoEnabled(tester), isFalse);

      // 拖到一半：画布已经按新尺寸画了，但页面数据还没动
      final g = await tester.startGesture(tester.getCenter(handle('se')));
      await g.moveBy(const Offset(25, 0));
      await g.moveBy(const Offset(15, 30));
      await tester.pump();
      await tester.pump();
      expect(tester.getSize(node('n5')), const Size(104, 78));
      expect(find.text('104 × 78'), findsOneWidget);
      expect(undoEnabled(tester), isFalse, reason: '拖动过程中不记撤销');
      await g.up();
      await settle(tester, rounds: 2);

      var doc = await savedDoc(tester, session);
      expect(doc.find('n5')!.style, {'width': '104px', 'height': '78px'});
      expect(tester.getSize(node('n5')), const Size(104, 78));
      expect(undoEnabled(tester), isTrue);

      await tester.tap(find.byTooltip('撤销'));
      await settle(tester, rounds: 2);
      expect(undoEnabled(tester), isFalse, reason: '整次拖动只记了一条');
      doc = await savedDoc(tester, session);
      expect(doc.find('n5')!.style, isEmpty);
      expect(tester.getSize(node('n5')), const Size(64, 48));
      expect(tester.takeException(), isNull);
    });

    testWidgets('只拖下边：只写 height；撑满的卡片拖右边后不再撑满', (tester) async {
      final session = await openBuilder(tester);
      await select(tester, 'n5');
      await tester.drag(handle('s'), const Offset(30, 22));
      await settle(tester, rounds: 2);
      expect((await savedDoc(tester, session)).find('n5')!.style, {'height': '70px'});

      await select(tester, 'n3');
      final before = tester.getSize(node('n3'));
      await tester.drag(handle('e'), const Offset(-100, 0));
      await settle(tester, rounds: 2);
      expect((await savedDoc(tester, session)).find('n3')!.style, {'width': '${(before.width - 100).round()}px'});
      expect(tester.getSize(node('n3')).width, before.width - 100);
      expect(tester.takeException(), isNull);
    });

    testWidgets('带各种 style 的页面：能画出来，没有异常', (tester) async {
      await openBuilder(tester, doc: richDoc());
      expect(tester.takeException(), isNull);
      expect(find.text('已隐藏'), findsOneWidget, reason: 'display: none 的组件留在画布上，带角标');
      expect(find.text('绝对定位'), findsOneWidget);
      // 相对定位右移了 24
      expect(tester.getTopLeft(find.text('相对定位：右移 24')).dx, 16 + 24);
      // 宽 60%：页面内容区 358 的 60%
      expect(tester.getSize(node('pct')).width, closeTo(358 * 0.6, 0.01));
      expect(tester.getSize(node('pct')).height, 48);
      // 能选中隐藏的组件
      await tester.tap(find.text('已隐藏的文字'), warnIfMissed: false);
      await settle(tester, rounds: 2);
      expect(find.text('文本'), findsWidgets);
      expect(handle('se'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('两端对齐：第一个贴左、最后一个贴右；占 1 份 / 2 份按比例分', (tester) async {
      await openBuilder(tester, doc: richDoc());
      expect(tester.getTopLeft(find.text('两端')).dx, 16 + 8, reason: '页面内边距 16 + 自己的左内边距 8');
      expect(tester.getTopRight(find.text('拉伸')).dx, 390 - 16 - 8);
      // 行里“拉伸”：三个子项一样高（跟最高的 28px 字那个一样）
      final h = {
        for (final id in ['j1', 'j2', 'j3']) tester.getSize(node(id)).height,
      };
      expect(h.length, 1, reason: '$h');
      final one = tester.getSize(node('g1')).width, two = tester.getSize(node('g2')).width;
      expect(two, closeTo(one * 2, 0.01));
      expect(tester.takeException(), isNull);
    });

    testWidgets('各种怪值 style：画布不崩；逐个选中也不崩', (tester) async {
      final doc = weirdDoc();
      await openBuilder(tester, doc: doc);
      expect(tester.takeException(), isNull);
      // 缩小、放大后也不崩
      canvas(tester).zoomTo(0.25);
      await tester.pump();
      expect(tester.takeException(), isNull);
      canvas(tester).zoomTo(3);
      await tester.pump();
      expect(tester.takeException(), isNull);
      canvas(tester).fitToScreen();
      await tester.pump();
      // 选中每一种怪值的容器和行（选中层要量尺寸、画间距示意）
      for (final child in doc.root.children.where((c) => c.isContainer)) {
        final el = node(child.id);
        expect(el, findsOneWidget);
        tester.widget<GestureDetector>(el).onTap!();
        await tester.pump();
        await tester.pump();
        expect(tester.takeException(), isNull, reason: '选中 ${child.id}（${child.style}）');
      }
    });

    testWidgets('缩放：按钮、双指、适应屏幕；缩放后点选仍然选中对的组件', (tester) async {
      await openBuilder(tester);
      await tester.tap(find.byTooltip('缩小'));
      await tester.pump();
      expect(find.text('75%'), findsOneWidget);
      await tester.tap(find.byTooltip('缩小'));
      await tester.pump();
      expect(find.text('50%'), findsOneWidget);
      expect(canvas(tester).scale, 0.5);
      // 页面缩到一半宽，横向居中
      expect(tester.getRect(node('n5')).size, const Size(32, 24));
      expect(tester.getRect(find.byKey(const ValueKey('lowcode-page'))).left, closeTo(390 / 4, 0.01));

      // 缩小后点按钮：选中的是按钮，拖柄能按的范围还是 32
      await tester.tapAt(tester.getCenter(node('n5')));
      await settle(tester, rounds: 2);
      expect(find.text('按钮'), findsWidgets);
      expect(find.widgetWithText(FilledButton, '属性'), findsOneWidget);
      expect(tester.getRect(handle('se')).width, closeTo(32, 0.01));
      expect(find.text('64 × 48'), findsOneWidget, reason: '尺寸标签显示的是页面上的像素，不随缩放变');
      // 缩小后拖拖柄：手指移 40，页面上是 80（手指移得太少系统不当成拖动）
      await tester.drag(handle('se'), const Offset(40, 20));
      await settle(tester, rounds: 2);
      expect(find.text('144 × 88'), findsOneWidget);

      // 点说明文字：换成选中文本
      await tester.tapAt(tester.getCenter(node('n2')));
      await settle(tester, rounds: 2);
      expect(find.text('文本'), findsWidgets);

      await tester.tap(find.byTooltip('适应屏幕'));
      await tester.pump();
      expect(find.text('100%'), findsOneWidget);
      expect(tester.getRect(find.byKey(const ValueKey('lowcode-page'))).left, 0);

      // 双指张开：放大
      final blank = tester.getRect(find.byKey(const ValueKey('lowcode-canvas'))).center + const Offset(0, 120);
      final a = await tester.startGesture(blank - const Offset(40, 0), pointer: 11);
      final b = await tester.startGesture(blank + const Offset(40, 0), pointer: 12);
      for (var i = 0; i < 6; i++) {
        await a.moveBy(const Offset(-10, 0));
        await b.moveBy(const Offset(10, 0));
        await tester.pump();
      }
      await a.up();
      await b.up();
      await tester.pump();
      expect(canvas(tester).scale, greaterThan(1.5));
      expect(canvas(tester).scale, lessThanOrEqualTo(kCanvasMaxScale));
      // 放大后点选照样准
      await tester.tap(find.byTooltip('适应屏幕'));
      await tester.pump();
      canvas(tester).zoomTo(2, focal: Offset.zero);
      await settle(tester, rounds: 2);
      await tester.tapAt(tester.getCenter(node('n1')));
      await settle(tester, rounds: 2);
      expect(tester.getRect(handle('se')).width, closeTo(32, 0.01));
      expect(tester.takeException(), isNull);
    });

    testWidgets('缩放范围 25%–300%；页面宽度预设', (tester) async {
      await openBuilder(tester);
      canvas(tester).zoomTo(0.01);
      await tester.pump();
      expect(canvas(tester).scale, kCanvasMinScale);
      expect(tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.remove)).onPressed, isNull);
      canvas(tester).zoomTo(99);
      await tester.pump();
      expect(canvas(tester).scale, kCanvasMaxScale);
      expect(find.text('300%'), findsOneWidget);

      await tester.tap(find.byTooltip('页面宽度'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('768 像素'));
      await tester.pumpAndSettle();
      await settle(tester, rounds: 2);
      expect(canvas(tester).pageWidth, 768);
      expect(canvas(tester).scale, closeTo(390 / 768, 0.001), reason: '换宽度后自动适应屏幕');
      expect(find.text('51%'), findsOneWidget);
      expect(tester.getRect(node('n3')).width, closeTo((768 - 32) * 390 / 768, 0.01));

      await tester.tap(find.byTooltip('页面宽度'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('360 像素'));
      await tester.pumpAndSettle();
      await settle(tester, rounds: 2);
      expect(find.text('100%'), findsOneWidget);
      final page = tester.getRect(find.byKey(const ValueKey('lowcode-page')));
      expect(page.width, 360);
      expect(page.left, 15, reason: '比屏幕窄的页面横向居中');
      expect(tester.takeException(), isNull);
    });

    testWidgets('页面比可视区高：单指拖动能滚到底，滚不出界', (tester) async {
      final doc = LcDocument(
        title: '长页面',
        root: LcNode(id: 'root', type: 'page', props: Map.of(lcSpecs['page']!.defaults), children: [for (var i = 1; i <= 40; i++) text('第 $i 行')]),
      );
      await openBuilder(tester, doc: doc);
      final view = tester.getRect(find.byKey(const ValueKey('lowcode-canvas')));
      expect(tester.getRect(node('n40')).top, greaterThan(view.bottom), reason: '最后一行一开始在屏幕外');
      final top = tester.getRect(node('n1')).top;
      await tester.dragFrom(view.center, const Offset(0, -200));
      await tester.pump(const Duration(seconds: 3));
      expect(tester.getRect(node('n1')).top, lessThan(top - 150));
      for (var i = 0; i < 8; i++) {
        await tester.dragFrom(view.center, const Offset(0, -300));
        await tester.pump(const Duration(seconds: 3));
      }
      final page = tester.getRect(find.byKey(const ValueKey('lowcode-page')));
      expect(page.bottom, closeTo(view.bottom, 0.01), reason: '滚到底就停，页面底边贴着可视区底边');
      expect(tester.getRect(node('n40')).bottom, lessThanOrEqualTo(view.bottom));
      // 往回拖过头：停在顶部；横向拖不动
      for (var i = 0; i < 8; i++) {
        await tester.dragFrom(view.center, const Offset(120, 400));
        await tester.pump(const Duration(seconds: 3));
      }
      expect(tester.getRect(find.byKey(const ValueKey('lowcode-page'))).topLeft, view.topLeft);
      expect(tester.takeException(), isNull);
    });

    testWidgets('长按拖动还在：从组件栏拖新组件进来、长按画布上的组件重排', (tester) async {
      final session = await openBuilder(tester);
      // 组件栏的“文本”长按拖到卡片下面的空白处（页面末尾）
      final chip = await tester.startGesture(tester.getCenter(find.text('文本')));
      await tester.pump(const Duration(milliseconds: 400));
      await chip.moveBy(const Offset(0, -30));
      await tester.pump();
      // 拖动中：插入位出现
      expect(find.byKey(const ValueKey('lc-slot-root-3')), findsOneWidget);
      await chip.moveTo(tester.getCenter(find.byKey(const ValueKey('lc-slot-root-3'))));
      await tester.pump(const Duration(milliseconds: 200));
      await chip.up();
      await settle(tester, rounds: 3);
      var doc = await savedDoc(tester, session);
      expect([for (final c in doc.root.children) c.type], ['text', 'text', 'card', 'text']);
      expect(find.byKey(const ValueKey('lc-slot-root-3')), findsNothing, reason: '松手后插入位收起');

      // 长按第一行标题，拖到最后
      final title = await tester.startGesture(tester.getCenter(node('n1')));
      await tester.pump(const Duration(milliseconds: 500));
      await title.moveBy(const Offset(0, 30));
      await tester.pump();
      final last = find.byKey(const ValueKey('lc-slot-root-4'));
      expect(last, findsOneWidget);
      await title.moveTo(tester.getCenter(last));
      await tester.pump(const Duration(milliseconds: 200));
      await title.up();
      await settle(tester, rounds: 3);
      doc = await savedDoc(tester, session);
      expect(doc.root.children.last.id, 'n1');
      expect(find.byKey(const ValueKey('lc-slot-root-4')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('“更多操作”里的上移 / 下移 / 复制 / 删除', (tester) async {
      final session = await openBuilder(tester);
      await select(tester, 'n2');
      await moreAction(tester, '上移');
      expect([for (final c in (await savedDoc(tester, session)).root.children) c.id], ['n2', 'n1', 'n3']);
      await moreAction(tester, '下移');
      expect([for (final c in (await savedDoc(tester, session)).root.children) c.id], ['n1', 'n2', 'n3']);
      await moreAction(tester, '复制');
      var doc = await savedDoc(tester, session);
      expect([for (final c in doc.root.children) c.type], ['text', 'text', 'text', 'card']);
      expect(doc.root.children[2].strProp('text'), doc.root.children[1].strProp('text'));
      // 复制后选中的是新的那个；删掉它
      await moreAction(tester, '删除');
      doc = await savedDoc(tester, session);
      expect([for (final c in doc.root.children) c.id], ['n1', 'n2', 'n3']);
      expect(find.text('属性'), findsNothing, reason: '删除后取消选中');
      expect(tester.takeException(), isNull);
    });

    testWidgets('删除被积木逻辑用到的组件：先问；确认后一并清掉，撤销一次全部回来', (tester) async {
      final start = LcDocument.starter('我的小站');
      final json = start.toJson()
        ..['logic'] = {
          'variables': [
            {'name': 'count', 'type': 'number', 'initial': 0},
          ],
          'handlers': [
            {
              'id': 'h1',
              'event': 'click',
              'target': 'n5',
              'body': [
                {
                  'op': 'setProp',
                  'args': {
                    'node': 'n1',
                    'prop': 'text',
                    'value': {'e': 'prop', 'node': 'n4', 'prop': 'value'},
                  },
                },
              ],
            },
            {'id': 'h2', 'event': 'load', 'body': <Object>[]},
          ],
        };
      final withLogic = LcDocument.fromJson(json);
      expect(withLogic.logic.nodeRefCount('n5'), 1);
      expect(withLogic.logic.nodeRefCount('n4'), 1);
      final session = await openBuilder(tester, doc: withLogic);

      // 删卡片：它里面的输入框（n4）和按钮（n5）各被用到 1 处
      await select(tester, 'n3');
      await moreAction(tester, '删除');
      expect(find.textContaining('有 2 处积木逻辑在用这个组件'), findsOneWidget);
      // 取消：什么都不变
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      var doc = await savedDoc(tester, session);
      expect(doc.find('n3'), isNotNull);
      expect(doc.logic.handlers.length, 2);
      expect(undoEnabled(tester), isFalse);

      await moreAction(tester, '删除');
      await tester.tap(find.widgetWithText(TextButton, '删除'));
      await tester.pumpAndSettle();
      doc = await savedDoc(tester, session);
      expect(doc.find('n3'), isNull);
      expect([for (final h in doc.logic.handlers) h.id], ['h2'], reason: '挂在按钮上的处理整个清掉');
      expect(doc.logic.nodeRefCount('n4') + doc.logic.nodeRefCount('n5'), 0);

      await tester.tap(find.byTooltip('撤销'));
      doc = await savedDoc(tester, session);
      expect(doc.find('n5'), isNotNull);
      expect(doc.logic.handlers.length, 2);
      expect(doc.logic.nodeRefCount('n5'), 1);
      expect(doc.logic.nodeRefCount('n4'), 1);
      expect(undoEnabled(tester), isFalse, reason: '清逻辑和删组件是同一条撤销');

      // 没被用到的组件：不问，直接删
      await select(tester, 'n2');
      await moreAction(tester, '删除');
      expect(find.textContaining('积木逻辑在用'), findsNothing);
      expect((await savedDoc(tester, session)).find('n2'), isNull);
      expect(tester.takeException(), isNull);
    });

    testWidgets('新入口：样式 / 事件 / 积木逻辑 / 自定义组件 / 导出 Vue / React 都能点开', (tester) async {
      await openBuilder(tester);
      await select(tester, 'n5');
      // 原来的“属性”还在
      await tester.tap(find.widgetWithText(FilledButton, '属性'));
      await tester.pumpAndSettle();
      expect(find.text('按钮属性'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(OutlinedButton, '样式'));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);

      await tester.tap(find.byTooltip('事件'));
      await tester.pumpAndSettle();
      expect(tester.widget<LogicScreen>(find.byType(LogicScreen)).initialNodeId, 'n5');
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(LogicScreen), findsNothing);
      expect(find.text('属性'), findsOneWidget, reason: '回来以后选中还在');

      await topMenu(tester, '积木逻辑');
      expect(tester.widget<LogicScreen>(find.byType(LogicScreen)).initialNodeId, isNull);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      for (final label in ['自定义组件', '导出 Vue / React']) {
        await topMenu(tester, label);
        await settle(tester, rounds: 2);
        expect(find.byType(BottomSheet), findsOneWidget, reason: label);
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.byType(BottomSheet), findsNothing, reason: label);
      }
      // 原来的菜单项都还在
      await tester.tap(find.byTooltip('更多'));
      await tester.pumpAndSettle();
      for (final label in ['在预览里打开网页', '导出 Flutter 代码', '修改页面标题']) {
        expect(find.text(label), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('间距示意可以关；点画布外的灰底取消选中', (tester) async {
      await openBuilder(tester);
      canvas(tester).zoomTo(0.5);
      await tester.pump();
      await tester.tapAt(tester.getCenter(node('n3')));
      await settle(tester, rounds: 2);
      expect(find.text('属性'), findsOneWidget);
      expect(find.byTooltip('间距示意：开'), findsOneWidget);
      await tester.tap(find.byTooltip('间距示意：开'));
      await tester.pump();
      expect(find.byTooltip('间距示意：关'), findsOneWidget);
      expect(handle('se'), findsOneWidget, reason: '关的只是间距示意，拖柄还在');
      // 页面只占左右中间一半，点最左边的灰底
      final view = tester.getRect(find.byKey(const ValueKey('lowcode-canvas')));
      await tester.tapAt(view.centerLeft + const Offset(20, 0));
      await settle(tester, rounds: 2);
      expect(find.text('属性'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('截图', () {
    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      final suffix = mode == ThemeMode.light ? 'light' : 'dark';

      testWidgets('默认、选中、缩小到 50% ($suffix)', (tester) async {
        // 给卡片加一点外边距，间距示意里橙色、绿色都看得到
        final doc = LcDocument.starter('我的小站');
        doc.find('n3')!.style.addAll({'margin-top': '12px', 'margin-bottom': '20px'});
        await openBuilder(tester, doc: doc, mode: mode);
        await shot(tester, 'lc-canvas-default-$suffix');
        await select(tester, 'n3');
        await shot(tester, 'lc-canvas-selected-$suffix');
        await select(tester, 'n5');
        await shot(tester, 'lc-canvas-selected-button-$suffix');
        canvas(tester).zoomTo(0.5);
        await settle(tester, rounds: 2);
        await shot(tester, 'lc-canvas-zoom50-$suffix');
        canvas(tester).fitToScreen();
        await settle(tester, rounds: 2);
        canvas(tester).zoomTo(2, focal: const Offset(100, 150));
        await settle(tester, rounds: 2);
        await shot(tester, 'lc-canvas-zoom200-$suffix');
      });

      testWidgets('带丰富 style 的页面 ($suffix)', (tester) async {
        await openBuilder(tester, doc: richDoc(), mode: mode);
        await shot(tester, 'lc-canvas-rich-$suffix');
        await tester.tap(find.text('四边不同的内边距、上边框、两个圆角、阴影'), warnIfMissed: false);
        await settle(tester, rounds: 2);
        await shot(tester, 'lc-canvas-rich-selected-$suffix');
        await tester.tap(find.byTooltip('更多操作'));
        await tester.pumpAndSettle();
        await shot(tester, 'lc-canvas-more-menu-$suffix');
      });
    }
  });
}
