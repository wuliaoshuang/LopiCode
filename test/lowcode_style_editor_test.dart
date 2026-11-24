// 样式编辑面板（低代码第 2 版 B2 块）的界面测试：390×844，浅色 + 深色。
// 每个分组改了以后 node.style 里是期望的规范条目；撤销记录的合并；原始 CSS；取色；负值 / 非法输入；节点消失；键盘。
//   LOPI_SHOTS=1 flutter test --no-pub test/lowcode_style_editor_test.dart   # 同时把截图写到 docs/screenshots/lc-style-*.png
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/lowcode/css_codec.dart';
import 'package:lopicode/lowcode/model.dart';
import 'package:lopicode/lowcode/style_color_sheet.dart';
import 'package:lopicode/lowcode/style_editor_sheet.dart';
import 'package:lopicode/lowcode/style_groups_widgets.dart';
import 'package:lopicode/lowcode/style_model.dart';
import 'package:lopicode/lowcode/style_resolve.dart';
import 'package:lopicode/theme/app_theme.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:material_ui/material_ui.dart';

import 'support/harness.dart';

final bool writeShots = Platform.environment['LOPI_SHOTS'] == '1';
bool fontsLoaded = false;

/// 测试里的“搭建页”：手里一份文档，onEdit 直接改它并计数（一次 onEdit ＝ 一条撤销记录）。
class Host {
  Host(this.doc);
  LcDocument doc;
  int edits = 0;

  /// 模拟撤销 / 重做之后搭建页换了文档对象：每次改之前先换成一份新解析出来的。
  bool swapDoc = false;
  LcNode? node(String id) => doc.find(id);
  Map<String, String> style(String id) => doc.find(id)!.style;
}

LcDocument sampleDoc() => LcDocument(
  title: '测试页',
  root: LcNode(
    id: 'root',
    type: 'page',
    props: {'padding': 16, 'gap': 12, 'bg': '#F6FBFD'},
    children: [
      LcNode(
        id: 'card',
        type: 'card',
        props: {'padding': 16, 'gap': 8, 'bg': '#FFFFFF', 'radius': 12, 'width': 'fill'},
        children: [
          LcNode(id: 'b1', type: 'button', props: {'text': '提交', 'bg': '#058654', 'color': '#FFFFFF', 'radius': 8, 'padding': 12, 'fontSize': 16}),
          LcNode(id: 't1', type: 'text', props: {'text': '一段文本', 'fontSize': 16, 'color': '#222435'}),
        ],
      ),
    ],
  ),
);

Future<Host> openEditor(WidgetTester tester, {String nodeId = 'b1', ThemeMode mode = ThemeMode.light, LcDocument? doc, bool realFont = false}) async {
  usePhoneViewport(tester);
  final host = Host(doc ?? sampleDoc());
  final font = realFont && fontsLoaded ? kTestFont : null;
  await tester.pumpWidget(
    RepaintBoundary(
      key: shotKey,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(Brightness.light, fontFamily: font),
        darkTheme: buildAppTheme(Brightness.dark, fontFamily: font),
        themeMode: mode,
        home: StatefulBuilder(
          builder: (context, setState) {
            final n = host.node(nodeId);
            return Scaffold(
              body: SafeArea(
                child: ListView(
                  padding: const EdgeInsets.all(Space.x4),
                  children: [
                    Text('画布（测试宿主）· 改了 ${host.edits} 次', style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: Space.x2),
                    Text(n == null ? '（组件不在了）' : declarationsToCss(resolvedStyle(n, host.doc.parentOf(nodeId))), key: const Key('host-css'), style: Theme.of(context).textTheme.bodySmall),
                    TextButton(
                      key: const Key('host-open'),
                      onPressed: () => showStyleEditor(
                        context,
                        doc: host.doc,
                        nodeId: nodeId,
                        onEdit: (change) => setState(() {
                          if (host.swapDoc) host.doc = LcDocument.parse(host.doc.encode());
                          change(host.doc);
                          host.edits++;
                        }),
                      ),
                      child: const Text('打开样式面板'),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(const Key('host-open')));
  await tester.pumpAndSettle();
  return host;
}

Finder k(String key) => find.byKey(Key(key));

/// 点一个控件（先滚到看得见），再等连续操作的合并时间过去。
Future<void> tapKey(WidgetTester tester, String key, {bool settle = true}) async {
  await tester.ensureVisible(k(key));
  await tester.pump();
  await tester.tap(k(key));
  if (settle) {
    await tester.pump(kStyleCommitDelay + const Duration(milliseconds: 50));
    await tester.pumpAndSettle();
  } else {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

Future<void> goTab(WidgetTester tester, StyleTab tab) => tapKey(tester, 'lc-tab-${tab.name}');

/// 往数字框里敲字，等合并时间过去。
Future<void> typeNum(WidgetTester tester, String id, String text) async {
  await tester.ensureVisible(k('lc-num-$id'));
  await tester.pump();
  await tester.enterText(k('lc-num-$id'), text);
  await tester.pump(kStyleCommitDelay + const Duration(milliseconds: 50));
  await tester.pumpAndSettle();
}

/// 点开下拉再选一项（按菜单上的字）。
Future<void> pickMenu(WidgetTester tester, String key, String label) async {
  await tester.ensureVisible(k(key));
  await tester.pump();
  await tester.tap(k(key));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

/// 点开一个颜色按钮，输入十六进制，点“用这个颜色”。
Future<void> pickColor(WidgetTester tester, String id, String hex) async {
  await tapKey(tester, 'lc-color-$id');
  await tester.enterText(k('lc-color-hex'), hex);
  await tester.pump();
  await tester.tap(k('lc-color-ok'));
  await tester.pumpAndSettle();
}

bool isRed(WidgetTester tester, String id) {
  final field = tester.widget<TextField>(k('lc-num-$id'));
  final border = field.decoration?.enabledBorder;
  return border is OutlineInputBorder && border.borderSide.color == AppColors.light.danger;
}

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

void main() {
  setUpAll(() async => fontsLoaded = await loadRealFonts());
  setUp(debugClearRecentColors);

  testWidgets('尺寸：填宽度、换成 %、换成 auto（数值框禁用）、清除；更多里有最小 / 最大', (tester) async {
    final host = await openEditor(tester);
    expect(find.text('按钮 样式'), findsOneWidget);
    await typeNum(tester, 'width', '50');
    expect(host.style('b1'), {'width': '50px'});
    expect(host.edits, 1);
    expect(k('lc-tab-dot-size'), findsOneWidget, reason: '改过的分组带小圆点');
    expect(k('lc-tab-dot-text'), findsNothing);

    await pickMenu(tester, 'lc-len-width-unit', '%');
    expect(host.style('b1')['width'], '50%');
    expect(host.edits, 2);

    await pickMenu(tester, 'lc-len-width-unit', 'auto（自动）');
    expect(host.style('b1')['width'], 'auto');
    expect(tester.widget<TextField>(k('lc-num-width')).enabled, isFalse, reason: 'auto 时数值框禁用');

    await tapKey(tester, 'lc-len-width-clear');
    expect(host.style('b1'), isEmpty, reason: '清除＝从 style 里删掉这一条');

    await tapKey(tester, 'lc-more-size');
    await typeNum(tester, 'max-width', '320');
    expect(host.style('b1'), {'max-width': '320px'});
  });

  testWidgets('间距：联动改内边距写四条；关掉联动只动上边；显示的是最终值并提示“继承自属性”', (tester) async {
    final host = await openEditor(tester);
    await goTab(tester, StyleTab.spacing);
    // 按钮的 padding: 12 是简写属性里来的：示意图上显示 12，下面那一行提示来源。
    expect(find.descendant(of: k('lc-box-padding-top'), matching: find.text('12')), findsOneWidget);
    expect(find.text('继承自属性'), findsOneWidget);
    expect(find.text('内边距（四边）'), findsOneWidget);

    await typeNum(tester, 'box', '20');
    expect(host.style('b1'), {'padding-top': '20px', 'padding-right': '20px', 'padding-bottom': '20px', 'padding-left': '20px'});
    expect(find.text('继承自属性'), findsNothing);
    expect(host.edits, 1);

    await tapKey(tester, 'lc-box-link');
    await tapKey(tester, 'lc-box-padding-top');
    expect(find.text('上内边距'), findsOneWidget);
    await typeNum(tester, 'box', '4');
    expect(host.style('b1'), {'padding-top': '4px', 'padding-right': '20px', 'padding-bottom': '20px', 'padding-left': '20px'});

    // 清除上边：回落到属性里的 12。
    await tapKey(tester, 'lc-len-box-clear');
    expect(host.style('b1').containsKey('padding-top'), isFalse);
    expect(find.descendant(of: k('lc-box-padding-top'), matching: find.text('12')), findsOneWidget);
  });

  testWidgets('负值规则：外边距、定位可以为负；内边距、尺寸敲不进负号', (tester) async {
    final host = await openEditor(tester);
    await goTab(tester, StyleTab.spacing);
    await tapKey(tester, 'lc-box-margin-left');
    expect(find.text('外边距（四边）'), findsOneWidget);
    await tapKey(tester, 'lc-box-link');
    await typeNum(tester, 'box', '-8');
    expect(host.style('b1'), {'margin-left': '-8px'});

    await tapKey(tester, 'lc-box-padding-left');
    await tapKey(tester, 'lc-box-link');
    await typeNum(tester, 'box', '-5');
    expect(tester.widget<TextField>(k('lc-num-box')).controller!.text, '5', reason: '内边距的负号敲不进去');
    expect(host.style('b1')['padding-left'], '5px');
    // 减到 0 就停住。
    for (var i = 0; i < 8; i++) {
      await tapKey(tester, 'lc-len-box-minus', settle: false);
    }
    await tester.pump(kStyleCommitDelay);
    expect(host.style('b1')['padding-left'], '0px');

    await goTab(tester, StyleTab.size);
    await typeNum(tester, 'height', '-3');
    expect(host.style('b1')['height'], '3px');

    await goTab(tester, StyleTab.position);
    await tapKey(tester, 'lc-opt-position-absolute');
    expect(host.style('b1')['position'], 'absolute');
    await typeNum(tester, 'top', '-4');
    expect(host.style('b1')['top'], '-4px');
  });

  testWidgets('非法输入：框标红、不提交；离开输入框后恢复', (tester) async {
    final host = await openEditor(tester);
    await typeNum(tester, 'width', '12');
    expect(host.edits, 1);
    await typeNum(tester, 'width', '1.2.3');
    expect(isRed(tester, 'width'), isTrue);
    expect(host.style('b1')['width'], '12px', reason: '非法的不提交');
    expect(host.edits, 1);
    await typeNum(tester, 'width', '.');
    expect(isRed(tester, 'width'), isTrue);
    expect(host.edits, 1);
    // 改对了红框就消失。
    await typeNum(tester, 'width', '1.5');
    expect(isRed(tester, 'width'), isFalse);
    expect(host.style('b1')['width'], '1.5px');

    // 外边距可以为负，但光一个负号不是数。
    await goTab(tester, StyleTab.spacing);
    await tapKey(tester, 'lc-box-margin-top');
    final before = host.edits;
    await typeNum(tester, 'box', '-');
    expect(isRed(tester, 'box'), isTrue);
    expect(host.edits, before);
    expect(host.style('b1').keys.where((key) => key.startsWith('margin')), isEmpty);
  });

  testWidgets('撤销记录的合并：连续点 5 次加号只记 1 条；停下来再点另算一条；换单位这类一下一条', (tester) async {
    final host = await openEditor(tester);
    await goTab(tester, StyleTab.text);
    for (var i = 0; i < 5; i++) {
      await tapKey(tester, 'lc-len-font-size-plus', settle: false);
    }
    expect(host.edits, 0, reason: '还在连续操作里，先不提交');
    expect(tester.widget<TextField>(k('lc-num-font-size')).controller!.text, '21', reason: '面板自己显示预览值');
    await tester.pump(kStyleCommitDelay);
    expect(host.edits, 1);
    expect(host.style('b1')['font-size'], '21px');

    await tapKey(tester, 'lc-len-font-size-plus', settle: false);
    await tapKey(tester, 'lc-len-font-size-plus', settle: false);
    // 连续操作没停就点了一个“立刻提交”的（加粗）：一起算一条。
    await tapKey(tester, 'lc-opt-font-weight-700', settle: false);
    expect(host.edits, 2);
    expect(host.style('b1'), {'font-size': '23px', 'font-weight': '700'});
    await tester.pump(kStyleCommitDelay);
    expect(host.edits, 2, reason: '已经提交过，定时器不再多记一条');
  });

  testWidgets('关面板时把没提交的交出去；搭建页换了文档对象也照样改在新对象上', (tester) async {
    final host = await openEditor(tester);
    host.swapDoc = true;
    final first = host.doc;
    await typeNum(tester, 'width', '80');
    expect(identical(host.doc, first), isFalse);
    expect(host.style('b1')['width'], '80px');
    expect(first.find('b1')!.style, isEmpty, reason: '不去改打开时拿到的旧对象');
    await typeNum(tester, 'height', '40');
    expect(host.style('b1'), {'width': '80px', 'height': '40px'});

    await tester.enterText(k('lc-num-height'), '44');
    await tester.pump(const Duration(milliseconds: 50));
    expect(host.edits, 2);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(host.edits, 3);
    expect(host.style('b1')['height'], '44px');
    expect(find.text('按钮 样式'), findsNothing);
  });

  testWidgets('边框：宽 2px、虚线、红色 → 12 条 border-*，导出合并成一条 border', (tester) async {
    final host = await openEditor(tester);
    await goTab(tester, StyleTab.border);
    await typeNum(tester, 'border-width', '2');
    // 只有宽度没有样式的边框画不出来：顺手补了实线。
    expect(host.style('b1').length, 8);
    expect(host.style('b1')['border-left-style'], 'solid');
    await tapKey(tester, 'lc-opt-border-style-dashed');
    await pickColor(tester, 'border-color', '#ff0000');
    final style = host.style('b1');
    expect(style.length, 12);
    for (final side in cssSides) {
      expect(style['border-$side-width'], '2px');
      expect(style['border-$side-style'], 'dashed');
      expect(style['border-$side-color'], '#ff0000');
    }
    expect(LcStyle(style).toCss(), 'border: 2px dashed #ff0000;');

    // 分开改：只动右边。
    await tapKey(tester, 'lc-link-border-width');
    await typeNum(tester, 'border-right-width', '6');
    expect(host.style('b1')['border-right-width'], '6px');
    expect(host.style('b1')['border-top-width'], '2px');
  });

  testWidgets('圆角：四角联动 / 分开', (tester) async {
    final host = await openEditor(tester);
    await goTab(tester, StyleTab.radius);
    expect(tester.widget<TextField>(k('lc-num-border-radius')).controller!.text, '8', reason: '显示属性里的圆角');
    await typeNum(tester, 'border-radius', '16');
    expect(host.style('b1'), {for (final c in cssCorners) 'border-$c-radius': '16px'});
    await tapKey(tester, 'lc-link-border-radius');
    await typeNum(tester, 'border-top-left-radius', '0');
    expect(host.style('b1')['border-top-left-radius'], '0px');
    expect(host.style('b1')['border-bottom-right-radius'], '16px');
    await pickMenu(tester, 'lc-len-border-top-right-radius-unit', '%');
    expect(host.style('b1')['border-top-right-radius'], '16%');
  });

  testWidgets('背景与取色：输入 #1a2b3c 写进合法颜色；非法输入不能提交；透明、清除、最近用过；不透明度一次拖动一条记录', (tester) async {
    final host = await openEditor(tester);
    await goTab(tester, StyleTab.background);
    expect(find.text('#058654'), findsOneWidget, reason: '显示属性里的背景色');
    await pickColor(tester, 'background-color', '#1a2b3c');
    expect(host.style('b1'), {'background-color': '#1a2b3c'});
    expect(cssColorOk(host.style('b1')['background-color']!), isTrue);
    expect(host.edits, 1);

    // 非法：#12 不是合法写法，“用这个颜色”点不动；直接关掉什么都不改。
    await tapKey(tester, 'lc-color-background-color');
    expect(k('lc-color-recent-#1a2b3c'), findsOneWidget, reason: '最近用过的颜色');
    await tester.enterText(k('lc-color-hex'), '#12');
    await tester.pump();
    expect(find.text('写成 #RGB、#RRGGBB 或 #RRGGBBAA'), findsOneWidget);
    expect(tester.widget<FilledButton>(k('lc-color-ok')).onPressed, isNull);
    await tester.enterText(k('lc-color-hex'), 'xyz');
    await tester.pump();
    expect(tester.widget<TextField>(k('lc-color-hex')).controller!.text, '', reason: '不是十六进制的字敲不进去');
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(host.edits, 1);
    expect(host.style('b1')['background-color'], '#1a2b3c');

    // #RGB 和带透明度的 #RRGGBBAA。
    await pickColor(tester, 'background-color', '#abc');
    expect(host.style('b1')['background-color'], '#aabbcc');
    await pickColor(tester, 'background-color', '#11223380');
    expect(host.style('b1')['background-color'], '#11223380');

    // 点色块只换当前颜色，点“用这个颜色”才提交。
    await tapKey(tester, 'lc-color-background-color');
    await tester.tap(k('lc-color-swatch-#2962cb'));
    await tester.pump();
    expect(tester.widget<TextField>(k('lc-color-hex')).controller!.text, '#2962cb', reason: '色块就是它本身那个不透明的颜色');
    expect(host.style('b1')['background-color'], '#11223380', reason: '还没点“用这个颜色”，不提交');
    await tester.tap(k('lc-color-ok'));
    await tester.pumpAndSettle();
    expect(host.style('b1')['background-color'], '#2962cb');

    await tapKey(tester, 'lc-color-background-color');
    await tester.tap(k('lc-color-transparent'));
    await tester.pumpAndSettle();
    expect(host.style('b1')['background-color'], 'transparent');
    await tapKey(tester, 'lc-color-background-color');
    await tester.tap(k('lc-color-clear'));
    await tester.pumpAndSettle();
    expect(host.style('b1'), isEmpty);

    final before = host.edits;
    await tester.drag(k('lc-opacity'), const Offset(-40, 0));
    await tester.pumpAndSettle();
    expect(host.edits, before + 1, reason: '一次拖动只记一条');
    final opacity = LcStyle(host.style('b1')).number('opacity')!;
    expect(opacity, inExclusiveRange(0, 1));
    expect(find.text('${(opacity * 100).round()}%'), findsOneWidget);
    await tapKey(tester, 'lc-opacity-clear');
    expect(host.style('b1'), isEmpty);
  });

  testWidgets('文字：颜色、字号、粗细、对齐、行高、斜体、装饰线、字间距', (tester) async {
    final host = await openEditor(tester, nodeId: 't1');
    await goTab(tester, StyleTab.text);
    await pickColor(tester, 'color', '#C6212F');
    await typeNum(tester, 'font-size', '20');
    await tapKey(tester, 'lc-opt-font-weight-700');
    await tapKey(tester, 'lc-opt-text-align-center');
    await tapKey(tester, 'lc-num-line-height-plus');
    await tapKey(tester, 'lc-switch-font-style');
    await tapKey(tester, 'lc-opt-text-decoration-line-underline');
    await tapKey(tester, 'lc-more-text');
    await typeNum(tester, 'letter-spacing', '-0.5');
    expect(host.style('t1'), {
      'color': '#c6212f',
      'font-size': '20px',
      'font-weight': '700',
      'text-align': 'center',
      'line-height': '1.5',
      'font-style': 'italic',
      'text-decoration-line': 'underline',
      'letter-spacing': '-0.5px',
    });
    // 再点一下选中的＝清除；关掉斜体＝删掉。
    await tapKey(tester, 'lc-opt-font-weight-700');
    await tapKey(tester, 'lc-switch-font-style');
    expect(host.style('t1').containsKey('font-weight'), isFalse);
    expect(host.style('t1').containsKey('font-style'), isFalse);
    await pickMenu(tester, 'lc-menu-font-weight', '300');
    expect(host.style('t1')['font-weight'], '300');
  });

  testWidgets('阴影：开关、四个数值、颜色、内阴影；多层阴影显示原文并提示去 CSS 里改', (tester) async {
    final host = await openEditor(tester);
    await goTab(tester, StyleTab.shadow);
    expect(k('lc-num-shadow-x'), findsNothing);
    await tapKey(tester, 'lc-shadow-on');
    expect(host.style('b1'), {'box-shadow': '0px 2px 8px 0px #00000033'});
    await typeNum(tester, 'shadow-x', '-3');
    await typeNum(tester, 'shadow-blur', '12');
    await tapKey(tester, 'lc-shadow-inset');
    await pickColor(tester, 'shadow', '#000000');
    expect(host.style('b1')['box-shadow'], 'inset -3px 2px 12px 0px #000000');
    await tapKey(tester, 'lc-shadow-on');
    expect(host.style('b1'), isEmpty);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    final doc = sampleDoc();
    doc.find('b1')!.style['box-shadow'] = '0 1px 2px red, 0 4px 8px blue';
    final host2 = await openEditor(tester, doc: doc);
    await goTab(tester, StyleTab.shadow);
    expect(find.text('0 1px 2px red, 0 4px 8px blue'), findsOneWidget);
    expect(find.textContaining('去改 box-shadow'), findsOneWidget);
    expect(k('lc-num-shadow-x'), findsNothing);
    expect(host2.edits, 0);
  });

  testWidgets('布局：容器有方向 / 换行 / 分布 / 对齐 / 间距；普通组件只有自身的几项；隐藏', (tester) async {
    final host = await openEditor(tester, nodeId: 'card');
    await goTab(tester, StyleTab.layout);
    expect(find.text('卡片 样式'), findsOneWidget);
    await tapKey(tester, 'lc-opt-flex-direction-row');
    await tapKey(tester, 'lc-switch-flex-wrap');
    await tapKey(tester, 'lc-opt-justify-content-space-between');
    await tapKey(tester, 'lc-opt-align-items-center');
    await typeNum(tester, 'gap', '20');
    await tapKey(tester, 'lc-num-flex-grow-plus');
    expect(host.style('card'), {'flex-direction': 'row', 'flex-wrap': 'wrap', 'justify-content': 'space-between', 'align-items': 'center', 'row-gap': '20px', 'column-gap': '20px', 'flex-grow': '1'});
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    final host2 = await openEditor(tester);
    await goTab(tester, StyleTab.layout);
    expect(k('lc-opt-flex-direction-row'), findsNothing, reason: '按钮不是容器');
    await pickMenu(tester, 'lc-menu-align-self', '居中');
    await pickMenu(tester, 'lc-menu-display', '隐藏');
    expect(host2.style('b1'), {'align-self': 'center', 'display': 'none'});
    expect(find.textContaining('现在是“隐藏”'), findsOneWidget);
    await pickMenu(tester, 'lc-menu-display', '恢复默认');
    expect(host2.style('b1'), {'align-self': 'center'});
  });

  testWidgets('定位：选了定位方式才有上右下左；层级；溢出', (tester) async {
    final host = await openEditor(tester);
    await goTab(tester, StyleTab.position);
    expect(k('lc-num-top'), findsNothing);
    await tapKey(tester, 'lc-opt-position-sticky');
    await typeNum(tester, 'top', '0');
    await pickMenu(tester, 'lc-len-left-unit', 'auto（自动）');
    await typeNum(tester, 'z-index', '-2');
    await pickMenu(tester, 'lc-menu-overflow-x', '裁掉');
    await pickMenu(tester, 'lc-menu-overflow-y', '超出才滚动');
    expect(host.style('b1'), {'position': 'sticky', 'top': '0px', 'left': 'auto', 'z-index': '-2', 'overflow-x': 'hidden', 'overflow-y': 'auto'});
    // 层级只收整数。
    await typeNum(tester, 'z-index', '1.5');
    expect(host.style('b1')['z-index'], '15', reason: '小数点敲不进去');
  });

  testWidgets('原始 CSS：拆开存、认不出的保留成自定义 CSS（可删）、危险条目被拒并提示；重置要二次确认', (tester) async {
    final host = await openEditor(tester);
    await typeNum(tester, 'width', '100');
    await tapKey(tester, 'lc-style-css');
    expect(tester.widget<TextField>(k('lc-css-input')).controller!.text, 'width: 100px;');
    expect(find.textContaining('这些是从“属性”面板里设的值翻出来的'), findsOneWidget);
    expect(tester.widget<Text>(k('lc-css-legacy')).data, contains('padding: 12px;'));

    await tester.enterText(k('lc-css-input'), 'margin: 8px 4px; border: 1px solid red; foo-bar: baz; color: red; } body{display:none');
    await tester.pump();
    // 应用前就能看到会变成什么、哪些不收。
    expect(tester.widget<Text>(k('lc-css-preview')).data, contains('共 18 条样式'));
    expect(tester.widget<Text>(k('lc-css-preview')).data, contains('1 条是面板不认识的'));
    expect(k('lc-css-dropped'), findsOneWidget);
    final before = host.edits;
    await tester.tap(k('lc-css-apply'));
    await tester.pumpAndSettle();
    expect(host.edits, before + 1, reason: '整体替换是一条撤销记录');

    final style = host.style('b1');
    expect(style['margin-top'], '8px');
    expect(style['margin-right'], '4px');
    expect(style['margin-bottom'], '8px');
    expect(style['margin-left'], '4px');
    for (final side in cssSides) {
      expect(style['border-$side-width'], '1px');
      expect(style['border-$side-style'], 'solid');
      expect(style['border-$side-color'], 'red');
    }
    expect(style['foo-bar'], 'baz');
    expect(style['color'], 'red');
    expect(style.containsKey('width'), isFalse, reason: '整体替换：原来的 width 没写就没了');
    expect(style.containsKey('display'), isFalse);
    expect(style.values.any((v) => RegExp(r'[{}<>;]').hasMatch(v)), isFalse);
    expect(style.length, 18);

    // 面板上：没收下的有提示；最后有“自定义 CSS”小节。
    expect(k('lc-style-dropped'), findsOneWidget);
    expect(find.textContaining('不会收下'), findsOneWidget);
    expect(find.textContaining('display:none'), findsOneWidget);
    await tester.ensureVisible(k('lc-custom-foo-bar'));
    expect(find.text('自定义 CSS'), findsOneWidget);
    expect(find.text('foo-bar: baz'), findsOneWidget);
    await tapKey(tester, 'lc-custom-del-foo-bar');
    expect(host.style('b1').containsKey('foo-bar'), isFalse);
    expect(find.text('自定义 CSS'), findsNothing);
    expect(host.style('b1').length, 17);

    await tapKey(tester, 'lc-style-dropped-close');
    expect(k('lc-style-dropped'), findsNothing);

    // 重置：先问一句，取消不动，确认才清。
    await tapKey(tester, 'lc-style-reset');
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(host.style('b1').length, 17);
    await tapKey(tester, 'lc-style-reset');
    await tester.tap(find.text('重置').last);
    await tester.pumpAndSettle();
    expect(host.style('b1'), isEmpty);
    expect(tester.widget<TextButton>(k('lc-style-reset')).onPressed, isNull, reason: '没有可重置的就点不动');
  });

  testWidgets('组件在面板开着时没了：显示“已经不在了”，能关，不崩', (tester) async {
    final host = await openEditor(tester);
    await goTab(tester, StyleTab.text);
    await tapKey(tester, 'lc-len-font-size-plus', settle: false);
    // 还有一步没提交，组件就被删了（比如搭建页撤销了“添加”）。
    host.doc.remove('b1');
    await tester.pump(kStyleCommitDelay);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('这个组件已经不在了'), findsOneWidget);
    expect(host.node('b1'), isNull);
    await tester.tap(k('lc-style-close'));
    await tester.pumpAndSettle();
    expect(find.text('这个组件已经不在了'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('打开时组件就不在：直接显示“已经不在了”', (tester) async {
    await openEditor(tester, nodeId: 'nope');
    expect(find.text('这个组件已经不在了'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('键盘弹出：不溢出，被编辑的那一行滚到键盘上面', (tester) async {
    await openEditor(tester);
    await goTab(tester, StyleTab.spacing);
    await tester.ensureVisible(k('lc-num-box'));
    await tester.showKeyboard(k('lc-num-box'));
    tester.view.viewInsets = const FakeViewPadding(bottom: 320);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final rect = tester.getRect(k('lc-num-box'));
    expect(rect.bottom, lessThanOrEqualTo(kPhone.height - 320), reason: '输入框要在键盘上面：$rect');
    expect(rect.top, greaterThan(0));
    await tester.enterText(k('lc-num-box'), '24');
    await tester.pump(kStyleCommitDelay);
    expect(tester.takeException(), isNull);

    // 原始 CSS 和取色面板里敲字也不溢出。
    await tapKey(tester, 'lc-style-css');
    await tester.showKeyboard(k('lc-css-input'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(tester.getRect(k('lc-css-apply')).bottom, lessThanOrEqualTo(kPhone.height - 320), reason: '“应用”要点得到');
  });

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    final suffix = mode == ThemeMode.light ? 'light' : 'dark';

    testWidgets('截图与渲染检查（$suffix）：每个分组、取色、原始 CSS', (tester) async {
      final doc = sampleDoc();
      // 每个分组都放一点自己设的东西，截图里看得到“自己设的 / 继承的 / 没设的”三种样子。
      LcStyle(doc.find('card')!.style)
        ..set('width', '80%')
        ..set('margin', '8px auto')
        ..set('padding-top', '24px')
        ..set('border', '1px solid #d8dcdf')
        ..set('border-top-left-radius', '24px')
        ..set('opacity', '0.9')
        ..set('color', '#27282f')
        ..set('font-weight', '600')
        ..set('text-align', 'center')
        ..set('box-shadow', '0px 4px 16px 0px #0000001f')
        ..set('justify-content', 'space-between')
        ..set('position', 'relative')
        ..set('top', '-4px')
        ..set('z-index', '2')
        ..set('backdrop-filter', 'blur(4px)');
      await openEditor(tester, nodeId: 'card', mode: mode, doc: doc, realFont: true);
      for (final tab in StyleTab.values) {
        await goTab(tester, tab);
        await shot(tester, 'lc-style-${tab.name}-$suffix');
      }
      // 拉高到 92%，看长分组的全貌和最后的“自定义 CSS”。
      await goTab(tester, StyleTab.layout);
      final before = tester.getTopLeft(find.text('卡片 样式')).dy;
      await tester.drag(find.text('卡片 样式'), const Offset(0, -400));
      await tester.pumpAndSettle();
      final after = tester.getTopLeft(find.text('卡片 样式')).dy;
      expect(after, lessThan(before - 150), reason: '往上拖标题，面板要变高');
      expect(after, greaterThan(kPhone.height * 0.08), reason: '最高到 92%，上面留一条画布');
      await shot(tester, 'lc-style-layout-tall-$suffix');
      await goTab(tester, StyleTab.text);
      await tapKey(tester, 'lc-more-text');
      await shot(tester, 'lc-style-text-tall-$suffix');
      await goTab(tester, StyleTab.position);
      await tester.ensureVisible(k('lc-custom-backdrop-filter'));
      await tester.pumpAndSettle();
      await shot(tester, 'lc-style-custom-$suffix');

      await goTab(tester, StyleTab.background);
      await pickColor(tester, 'background-color', '#F7BC2E');
      await tapKey(tester, 'lc-color-background-color');
      await shot(tester, 'lc-style-color-$suffix');
      await tester.enterText(k('lc-color-hex'), '#12');
      await tester.pump();
      await shot(tester, 'lc-style-color-bad-$suffix');
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      await tapKey(tester, 'lc-style-css');
      await shot(tester, 'lc-style-css-$suffix');
      await tester.enterText(k('lc-css-input'), 'margin: 8px 4px;\nborder: 1px solid red;\nfoo-bar: baz;\ncolor: red; } body{display:none');
      await tester.pump();
      await shot(tester, 'lc-style-css-dropped-$suffix');
      await tester.tap(k('lc-css-apply'));
      await tester.pumpAndSettle();
      await shot(tester, 'lc-style-applied-$suffix');
    });

    testWidgets('截图（$suffix）：组件不在了', (tester) async {
      await openEditor(tester, nodeId: 'nope', mode: mode, realFont: true);
      await shot(tester, 'lc-style-gone-$suffix');
    });
  }
}

/// 写进去的颜色是不是面板自己认得出的合法颜色。
bool cssColorOk(String css) => parseHexColor(css) != null;
