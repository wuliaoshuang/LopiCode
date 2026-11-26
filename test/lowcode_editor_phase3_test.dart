// 低代码编辑器第 5 版第 3 期第 1 段（B1）：格式第 3 版在界面上的那些事，390×844。
// “新版做的”提示、只打开不改写、常用页的新行（图标 / 禁用 / 说明文字 / 类型 / 默认值 / 标签 / 必填）、
// 图层（搜索 / 改名 / 眼睛 / 锁）、多选、快捷动作，和第一轮留下的四个小毛病。
//   LOPI_SHOTS=1 LOPI_SHOT_DIR=某目录 flutter test --no-pub test/lowcode_editor_phase3_test.dart   出截图
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/core/safe_file.dart';
import 'package:lopicode/core/templates.dart';
import 'package:lopicode/lang/types.dart';
import 'package:lopicode/lowcode/builder_bars_widgets.dart';
import 'package:lopicode/lowcode/builder_screen.dart';
import 'package:lopicode/lowcode/canvas_view.dart';
import 'package:lopicode/lowcode/editor_clipboard.dart';
import 'package:lopicode/lowcode/export_html.dart';
import 'package:lopicode/lowcode/inline_text_widgets.dart';
import 'package:lopicode/lowcode/layers_tree.dart';
import 'package:lopicode/lowcode/lift_gesture_widgets.dart';
import 'package:lopicode/lowcode/logic_expr.dart';
import 'package:lopicode/lowcode/logic_model.dart';
import 'package:lopicode/lowcode/model.dart';
import 'package:lopicode/lowcode/multi_select.dart';
import 'package:lopicode/lowcode/newer_notice_widgets.dart';
import 'package:lopicode/lowcode/quick_actions.dart';
import 'package:lopicode/project_session.dart';
import 'package:material_ui/material_ui.dart';

import 'support/harness.dart';

final bool writeShots = Platform.environment['LOPI_SHOTS'] == '1';
final String shotDir = Platform.environment['LOPI_SHOT_DIR'] ?? '.tmp/editor-b1-shots';
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

Finder k(String key) => find.byKey(ValueKey(key));
Finder node(String id) => k('lowcode-node-$id');
CanvasViewState canvas(WidgetTester tester) => tester.state<CanvasViewState>(find.byType(CanvasView));

/// 起始页面（root › n1 标题、n2 说明、n3 卡片 › n4 输入框、n5 “提交”按钮）；[text] 给了就把它原样写成页面文件。
Future<ProjectSession> openBuilder(WidgetTester tester, {LcDocument? doc, String? text, ThemeMode mode = ThemeMode.light}) async {
  usePhoneViewport(tester);
  lcClipboardClear();
  late TestEnv env;
  late ProjectSession session;
  await tester.runAsync(() async {
    env = await TestEnv.create();
    final project = await env.services.projects.create('我的小站', ProjectTemplate.lowcode);
    session = ProjectSession(env.services, project);
    final raw = text ?? doc?.encode();
    if (raw != null) File(session.guard.resolve(kLowcodePageFile)).writeAsStringSync(raw);
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

Future<String> fileText(WidgetTester tester, ProjectSession session) async {
  late String text;
  await tester.runAsync(() async => text = File(session.guard.resolve(kLowcodePageFile)).readAsStringSync());
  return text;
}

Future<LcDocument> saved(WidgetTester tester, ProjectSession session) async {
  await waitLowcodeSaved(tester);
  return LcDocument.parse(await fileText(tester, session));
}

Future<void> tap(WidgetTester tester, Finder f) async {
  await tester.tap(f, warnIfMissed: false);
  await settle(tester, rounds: 2);
}

Future<void> tapText(WidgetTester tester, String label) async {
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

/// 打开合一面板的“常用”页（已经开着就不动）。
Future<void> openCommon(WidgetTester tester) async {
  if (k('lc-inspector').evaluate().isEmpty) await tap(tester, find.widgetWithText(FilledButton, '常用'));
  expect(k('lc-inspector'), findsOneWidget);
}

Future<void> show(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pump();
}

Future<void> longPress(WidgetTester tester, Finder f) async {
  final g = await tester.startGesture(tester.getCenter(f));
  await tester.pump(kLcLiftAfter + const Duration(milliseconds: 40));
  await tester.pump();
  await g.up();
  await tester.pumpAndSettle();
}

Future<void> back(WidgetTester tester) async {
  await tester.binding.handlePopRoute();
  await tester.pumpAndSettle();
  await settle(tester, rounds: 2);
}

/// 一层里有五个兄弟的页面：root › a 文字、b 按钮、c 按钮、box 容器（› d 文字）、e 输入框。
LcDocument flatDoc() => LcDocument.parse(
  jsonEncode({
    'version': 3,
    'title': '多选',
    'root': {
      'id': 'root',
      'type': 'page',
      'props': {'padding': 16, 'gap': 12},
      'children': [
        {
          'id': 'a',
          'type': 'text',
          'props': {'text': '甲'},
        },
        {
          'id': 'b',
          'type': 'button',
          'props': {'text': '乙'},
        },
        {
          'id': 'c',
          'type': 'button',
          'props': {'text': '丙'},
        },
        {
          'id': 'box',
          'type': 'container',
          'props': {'padding': 8},
          'children': [
            {
              'id': 'd',
              'type': 'text',
              'props': {'text': '丁'},
            },
          ],
        },
        {
          'id': 'e',
          'type': 'input',
          'props': {'placeholder': '戊'},
        },
      ],
    },
  }),
);

List<String> kids(LcDocument d, [String id = 'root']) => [for (final c in d.find(id)!.children) c.id];

void main() {
  setUpAll(() async => fontsLoaded = await loadRealFonts());

  group('多选（纯计算）', () {
    test('只能一起选同一层的；再点一下移出去；页面本身不能选', () {
      final d = flatDoc();
      final ids = <String>{};
      expect(lcMultiToggle(d, ids, 'b'), isNull);
      expect(lcMultiToggle(d, ids, 'e'), isNull);
      expect(lcMultiToggle(d, ids, 'd'), kLcMultiSameLevelOnly);
      expect(lcMultiToggle(d, ids, 'root'), isNotNull);
      expect(ids, {'b', 'e'});
      expect(lcMultiToggle(d, ids, 'b'), isNull);
      expect(ids, {'e'});
      // 全移出去以后可以换一层重新选。
      lcMultiToggle(d, ids, 'e');
      expect(lcMultiToggle(d, ids, 'd'), isNull);
    });

    test('按页面上的先后来，不按点选的先后；文档变了以后去掉不在的', () {
      final d = flatDoc();
      final ids = {'a', 'e', 'c'};
      expect([for (final n in lcMultiOrdered(d, ids)) n.id], ['a', 'c', 'e']);
      d.remove('c');
      d.move('e', 'box', 0);
      lcMultiPrune(d, ids);
      expect(ids, {'a'});
    });

    test('包成容器：容器在第一个原来的位置，里面的先后不变', () {
      final d = flatDoc();
      final box = lcMultiWrap(d, {'c', 'a'})!;
      expect(kids(d), [box, 'b', 'box', 'e']);
      expect(kids(d, box), ['a', 'c']);
      expect(d.find(box)!.props.containsKey('padding'), isFalse);
    });

    test('一起上移 / 下移：挨着的一起走；顶到头不动', () {
      final d = flatDoc();
      expect(lcMultiShift(d, {'b', 'c'}, 1), isTrue);
      expect(kids(d), ['a', 'box', 'b', 'c', 'e']);
      expect(lcMultiShift(d, {'b', 'c'}, -1), isTrue);
      expect(lcMultiShift(d, {'b', 'c'}, -1), isTrue);
      expect(kids(d), ['b', 'c', 'a', 'box', 'e']);
      expect(lcMultiShift(d, {'b', 'c'}, -1), isFalse);
      expect(kids(d), ['b', 'c', 'a', 'box', 'e']);
    });

    test('一起挪：挪进别的容器 / 在本层换位置，挪完挨在一起；不能挪进自己里面', () {
      final d = flatDoc();
      expect(lcMultiMoveTo(d, {'a', 'c'}, 'box', 1), isTrue);
      expect(kids(d), ['b', 'box', 'e']);
      expect(kids(d, 'box'), ['d', 'a', 'c']);
      final d2 = flatDoc();
      expect(lcMultiMoveTo(d2, {'a', 'c'}, 'root', 5), isTrue);
      expect(kids(d2), ['b', 'box', 'e', 'a', 'c']);
      final d3 = flatDoc();
      expect(lcMultiMoveTo(d3, {'a', 'c'}, 'root', 2), isTrue, reason: '落点在两个选中的中间：排在后面第一个没选中的前面');
      expect(kids(d3), ['b', 'a', 'c', 'box', 'e']);
      final d4 = flatDoc();
      expect(lcMultiCanDropInto(d4, {'box', 'a'}, 'box'), isFalse);
      expect(lcMultiMoveTo(d4, {'box', 'a'}, 'box', 0), isFalse);
      expect(kids(d4), ['a', 'b', 'c', 'box', 'e']);
    });

    test('一起复制再粘贴：按先后挨着贴，编号重新发；一起删除连逻辑一并清掉', () {
      final d = flatDoc();
      d.logic.addHandler('click', target: 'b')!.body.add(LcBlock(op: 'alert', args: {'message': exText('hi')}));
      expect(lcMultiCopy(d, {'c', 'a'}), isTrue);
      expect(lcClipboardCount, 2);
      final pasted = lcClipboardPasteAll(d, 'box');
      expect(pasted.length, 2);
      expect([for (final id in pasted) d.find(id)!.type], ['text', 'button']);
      expect(kids(d, 'box').sublist(1), pasted);
      expect(lcMultiLogicRefs(d, {'a', 'b'}), greaterThan(0));
      expect(lcMultiDelete(d, {'a', 'b'}), 2);
      expect(kids(d), ['c', 'box', 'e']);
      expect(d.logic.handlersFor('b'), isEmpty);
      lcClipboardClear();
    });

    test('一起改样式只列几个都有的项', () {
      final d = flatDoc();
      final both = lcMultiCommonFields(d, {'b', 'c'});
      expect(both, d.find('b')!.spec.fields);
      final mixed = lcMultiCommonFields(d, {'a', 'e'});
      expect(mixed, isNotEmpty);
      for (final f in mixed) {
        expect(d.find('a')!.spec.fields, contains(f));
        expect(d.find('e')!.spec.fields, contains(f));
      }
    });
  });

  group('图层（纯计算）', () {
    test('名字：起了名字显示名字，后面带类型；搜索搜名字、类型名、上面的字', () {
      final d = flatDoc();
      d.find('b')!.name = '主按钮';
      expect(layerTitle(d.find('b')!), '主按钮');
      expect(layerHint(d.find('b')!), '按钮 · 乙');
      expect(layerTitle(d.find('c')!), '按钮');
      expect(layerHint(d.find('c')!), '丙');
      final all = layerRows(d.root, {'box'});
      expect([for (final r in layerSearch(layerRows(d.root, const {}), '主按')) r.node.id], ['b']);
      expect([for (final r in layerSearch(layerRows(d.root, const {}), '按钮')) r.node.id], ['b', 'c']);
      expect([for (final r in layerSearch(layerRows(d.root, const {}), '丁')) r.node.id], ['d']);
      expect(layerSearch(all, ' '), all);
    });
  });

  group('快捷动作', () {
    test('存下来的就是普通积木；改、去掉都只动这一串；积木里改复杂了就不再算', () {
      final d = flatDoc();
      final go = kLcQuickActions.firstWhere((a) => a.op == 'navigate'), say = kLcQuickActions.firstWhere((a) => a.op == 'alert');
      expect(lcQuickValue(d, 'b', go), isNull);
      expect(lcSetQuick(d, 'b', go, ' https://example.com '), isTrue);
      expect(lcSetQuick(d, 'b', say, '你好'), isTrue);
      final hs = d.logic.handlersFor('b').toList();
      expect(hs.length, 2);
      expect(hs.first.event, 'click');
      expect(hs.first.body.single.op, 'navigate');
      expect(hs.first.body.single.args, {'url': exText('https://example.com')});
      expect(lcQuickValue(d, 'b', go), 'https://example.com');
      expect(lcSetQuick(d, 'b', go, 'https://example.com'), isFalse, reason: '没变不算改');
      expect(lcSetQuick(d, 'b', go, 'https://b.example'), isTrue);
      expect(d.logic.handlersFor('b').length, 2, reason: '改的是原来那一串，不另起一串');
      // 存盘再读回来还认得。
      final again = LcDocument.parse(d.encode());
      expect(lcQuickValue(again, 'b', go), 'https://b.example');
      expect(lcQuickValue(again, 'b', say), '你好');
      // 在积木里又接了一块：不再算快捷动作，那一串还在。
      lcQuickHandler(d, 'b', say)!.body.add(LcBlock(op: 'log', args: {'value': exText('x')}));
      expect(lcQuickValue(d, 'b', say), isNull);
      expect(d.logic.handlersFor('b').length, 2);
      expect(lcSetQuick(d, 'b', go, ''), isTrue);
      expect(d.logic.handlersFor('b').length, 1);
      expect(lcSetQuick(d, 'root', go, 'https://x'), isFalse, reason: '页面本身没有“点击”');
    });
  });

  group('小毛病', () {
    test('长按菜单摆在被按的组件下面；下面放不下摆上面；都放不下才在手指那儿', () {
      const screen = Size(390, 844);
      const at = Offset(100, 300);
      expect(lcNodeMenuTop(at: at, avoid: null, menuHeight: 300, screen: screen, topInset: 64), 300);
      expect(lcNodeMenuTop(at: at, avoid: const Rect.fromLTWH(20, 280, 200, 44), menuHeight: 300, screen: screen, topInset: 64), 328);
      expect(lcNodeMenuTop(at: const Offset(100, 700), avoid: const Rect.fromLTWH(20, 680, 200, 44), menuHeight: 300, screen: screen, topInset: 64), 376);
      expect(lcNodeMenuTop(at: at, avoid: const Rect.fromLTWH(0, 100, 390, 650), menuHeight: 300, screen: screen, topInset: 64), 300);
    });

    test('给人看的类型里不出现“待定”', () {
      expect(const LType.listOf(LType(LKind.hole, name: 'h1')).show(), '列表〈任意〉');
      expect(const LType(LKind.hole, name: 'h1').show(), isNot(contains('待定')));
    });
  });

  group('搭建页', () {
    testWidgets('旧版本的页面只打开不改：文件一个字节都不动；改了再存才变成第 3 版', (tester) async {
      final v2 = File('test/fixtures/lowcode/page-v2.lc.json').readAsStringSync();
      final session = await openBuilder(tester, text: v2);
      expect(find.byType(LcNewerNotice), findsNothing);
      await tap(tester, node('n1'));
      await tap(tester, find.byTooltip('图层'));
      await back(tester);
      await waitLowcodeSaved(tester);
      expect(await fileText(tester, session), v2);
      // 改一下（在图层里把第一个子组件藏起来）才存。
      final first = LcDocument.parse(v2).root.children.first.id;
      await tap(tester, find.byTooltip('图层'));
      await tap(tester, k('lc-layer-$first'));
      await tap(tester, k('lc-layer-eye-$first'));
      await back(tester);
      final after = await saved(tester, session);
      expect(after.fileVersion, 3);
      expect(after.find(first)!.hidden, isTrue);
    });

    testWidgets('比这一版新的页面：顶上明说“这个页面是新版做的”；照样能改，存盘不降版本号、看不懂的还在', (tester) async {
      final raw = jsonDecode(flatDoc().encode()) as Map<String, dynamic>
        ..['version'] = 5
        ..['futureThing'] = {'k': 1};
      ((raw['root'] as Map)['children'] as List).add({
        'id': 'z9',
        'type': 'hologram',
        'props': {'depth': 3},
      });
      final text = jsonEncode(raw);
      final session = await openBuilder(tester, text: text);
      expect(find.byType(LcNewerNotice), findsOneWidget);
      expect(find.textContaining('这个页面是新版做的'), findsOneWidget);
      expect(find.textContaining('新版组件（hologram）'), findsOneWidget, reason: '不认识的组件在画布上是一块占位');
      await shot(tester, '01-newer-notice');
      await waitLowcodeSaved(tester);
      expect(await fileText(tester, session), text, reason: '只打开不改写');
      await tap(tester, k('lc-newer-notice-ok'));
      expect(find.byType(LcNewerNotice), findsNothing);
      // 不认识的那块：能选中、能开面板、能在图层里看到，不出错；不能就地改字。
      await tap(tester, node('z9'));
      expect(find.descendant(of: k('lc-selection-bar'), matching: find.text('新版组件')), findsOneWidget);
      await tap(tester, node('z9'));
      expect(k('lc-inline-edit'), findsNothing);
      await openCommon(tester);
      await tapText(tester, '样式');
      await tapText(tester, '事件');
      expect(tester.takeException(), isNull);
      await tap(tester, k('lc-inspector-close'));
      await tap(tester, find.byTooltip('图层'));
      expect(k('lc-layer-z9'), findsOneWidget);
      await back(tester);
      await tap(tester, node('b'));
      await openCommon(tester);
      await show(tester, k('lc-common-disabled'));
      await tap(tester, k('lc-common-disabled'));
      await waitLowcodeSaved(tester);
      final out = jsonDecode(await fileText(tester, session)) as Map<String, dynamic>;
      expect(out['version'], 5);
      expect(out['futureThing'], {'k': 1});
      final last = ((out['root'] as Map)['children'] as List).last as Map;
      expect(last, {
        'id': 'z9',
        'type': 'hologram',
        'props': {'depth': 3},
      });
    });

    testWidgets('常用页：按钮的图标和禁用、图片的说明文字、输入框的类型 / 默认值 / 标签 / 必填 / 禁用', (tester) async {
      final doc = LcDocument.starter('我的小站');
      doc.insert('root', LcNode(id: 'pic', type: 'image', props: Map.of(lcSpecs['image']!.defaults)), 0);
      final session = await openBuilder(tester, doc: doc);
      await tap(tester, node('n5'));
      await openCommon(tester);
      await show(tester, k('lc-common-icon'));
      await shot(tester, '02-button-common');
      await tap(tester, k('lc-common-icon'));
      await tester.pumpAndSettle();
      await shot(tester, '03-icon-picker');
      await tap(tester, k('lc-icon-pick-send'));
      await tester.pumpAndSettle();
      expect(find.text('发送'), findsWidgets);
      await show(tester, k('lc-common-disabled'));
      await tap(tester, k('lc-common-disabled'));
      await shot(tester, '04-button-icon-disabled');
      var d = await saved(tester, session);
      expect(d.find('n5')!.props['icon'], 'send');
      expect(d.find('n5')!.props['disabled'], isTrue);
      // 画布上按钮带着图标。
      expect(find.descendant(of: node('n5'), matching: find.byIcon(Icons.send)), findsOneWidget);
      // 再选“不要”＝把这个属性去掉。
      await show(tester, k('lc-common-icon'));
      await tap(tester, k('lc-common-icon'));
      await tester.pumpAndSettle();
      await tap(tester, k('lc-icon-pick-none'));
      await tester.pumpAndSettle();
      d = await saved(tester, session);
      expect(d.find('n5')!.props.containsKey('icon'), isFalse);

      await tap(tester, node('n4'));
      await show(tester, k('lc-common-inputType-password'));
      await tap(tester, k('lc-common-inputType-password'));
      await show(tester, k('lc-common-value'));
      await tester.enterText(k('lc-common-value'), 'abc');
      await show(tester, k('lc-common-label'));
      await tester.enterText(k('lc-common-label'), '密码');
      await tester.pump(const Duration(milliseconds: 600));
      await show(tester, k('lc-common-required'));
      await tap(tester, k('lc-common-required'));
      await shot(tester, '05-input-common');
      d = await saved(tester, session);
      final input = d.find('n4')!.props;
      expect(input['inputType'], 'password');
      expect(input['value'], 'abc');
      expect(input['label'], '密码');
      expect(input['required'], isTrue);
      expect(
        find.descendant(of: node('n4'), matching: find.textContaining('密码')),
        findsWidgets,
        reason: '画布上输入框上面有标签',
      );
      // 清空标签＝去掉这个属性。
      await show(tester, k('lc-common-label'));
      await tester.enterText(k('lc-common-label'), '');
      await tester.pump(const Duration(milliseconds: 600));
      d = await saved(tester, session);
      expect(d.find('n4')!.props.containsKey('label'), isFalse);

      await tap(tester, node('pic'));
      await show(tester, k('lc-common-alt'));
      await tester.enterText(k('lc-common-alt'), '一只猫');
      await tester.pump(const Duration(milliseconds: 600));
      await shot(tester, '06-image-common');
      d = await saved(tester, session);
      expect(d.find('pic')!.props['alt'], '一只猫');
    });

    testWidgets('图层：搜索、改名、眼睛（画布上不画、导出还在）、锁（画布上点不中）', (tester) async {
      final session = await openBuilder(tester);
      await tap(tester, find.byTooltip('图层'));
      await shot(tester, '07-layers');
      // 没选中的行没有眼睛和锁；选中了才有。
      expect(k('lc-layer-eye-n5'), findsNothing);
      await tap(tester, k('lc-layer-n5'));
      expect(k('lc-layer-eye-n5'), findsOneWidget);
      expect(k('lc-layer-lock-n5'), findsOneWidget);
      expect(k('lc-layer-eye-root'), findsNothing, reason: '页面本身不能藏、不能锁');
      // 改名：点已经选中那一行的名字。
      await tap(tester, k('lc-layer-name-n5'));
      await tester.pumpAndSettle();
      expect(k('lc-layer-rename'), findsOneWidget);
      await tester.enterText(k('lc-layer-rename'), '  提交按钮  ');
      await shot(tester, '08-layers-rename');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(find.text('提交按钮'), findsOneWidget);
      // 搜索。
      await tester.enterText(k('lc-layer-search'), '提交按');
      await tester.pumpAndSettle();
      expect(k('lc-layer-n5'), findsOneWidget);
      expect(k('lc-layer-n1'), findsNothing);
      await shot(tester, '09-layers-search');
      await tester.enterText(k('lc-layer-search'), '找不到的东西');
      await tester.pumpAndSettle();
      expect(k('lc-layer-search-empty'), findsOneWidget);
      await tap(tester, k('lc-layer-search-clear'));
      expect(k('lc-layer-n1'), findsOneWidget);
      // 锁 n5、藏 n1。
      await tap(tester, k('lc-layer-lock-n5'));
      await tap(tester, k('lc-layer-n1'));
      await tap(tester, k('lc-layer-eye-n1'));
      await tap(tester, k('lc-layer-n2'));
      expect(k('lc-layer-eye-n1'), findsOneWidget, reason: '已经藏起来的，没选中也看得见那只眼睛（好点回来）');
      expect(k('lc-layer-lock-n5'), findsOneWidget);
      expect(k('lc-layer-lock-n1'), findsNothing);
      await shot(tester, '10-layers-eye-lock');
      await back(tester);
      final d = await saved(tester, session);
      expect(d.find('n5')!.name, '提交按钮');
      expect(d.find('n5')!.locked, isTrue);
      expect(d.find('n1')!.hidden, isTrue);
      expect(node('n1'), findsNothing, reason: '藏起来的在画布上不画');
      await shot(tester, '11-canvas-hidden-locked');
      // 导出的网页里它还在。
      expect(exportHtml(d).html, contains(d.find('n1')!.strProp('text')!));
      // 锁着的在画布上点不中：点它，选中的是它外面的卡片。
      await tester.tapAt(tester.getCenter(node('n5')));
      await settle(tester, rounds: 2);
      expect(find.descendant(of: k('lc-selection-bar'), matching: find.text('卡片')), findsOneWidget);
      expect(k('lc-inline-edit'), findsNothing);
      // 在图层里解锁以后又点得中。
      await tap(tester, find.byTooltip('图层'));
      await tap(tester, k('lc-layer-lock-n5'));
      await back(tester);
      await tester.tapAt(tester.getCenter(node('n5')));
      await settle(tester, rounds: 2);
      expect(find.descendant(of: k('lc-selection-bar'), matching: find.text('按钮')), findsOneWidget);
    });

    testWidgets('多选：长按菜单进入；点同层的加进来、跨层的说一句；一起上移、包成容器、撤销', (tester) async {
      final session = await openBuilder(tester, doc: flatDoc());
      await longPress(tester, node('b'));
      await shot(tester, '12-node-menu-multi');
      await tapText(tester, '多选');
      expect(find.text('已选 1 个'), findsOneWidget);
      expect(k('lc-multi-mark-b'), findsOneWidget);
      await tap(tester, node('c'));
      expect(find.text('已选 2 个'), findsOneWidget);
      await tap(tester, node('d'));
      expect(find.text(kLcMultiSameLevelOnly), findsOneWidget);
      expect(find.text('已选 2 个'), findsOneWidget);
      await shot(tester, '13-multi-two');
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      // 再点一下移出去、再点加回来；多选的时候点两下不会变成就地改字。
      await tap(tester, node('b'));
      expect(find.text('已选 1 个'), findsOneWidget);
      await tap(tester, node('b'));
      expect(k('lc-inline-edit'), findsNothing);
      expect(find.text('已选 2 个'), findsOneWidget);
      // 一起上移。
      await tap(tester, k('lc-multi-more'));
      await tester.pumpAndSettle();
      await shot(tester, '14-multi-more');
      await tapText(tester, '上移');
      var d = await saved(tester, session);
      expect(kids(d), ['b', 'c', 'a', 'box', 'e']);
      // 包成容器：退出多选，选中的是新容器。
      await tap(tester, k('lc-multi-more'));
      await tester.pumpAndSettle();
      await tapText(tester, '包成容器');
      d = await saved(tester, session);
      final box = kids(d).first;
      expect(d.find(box)!.type, 'container');
      expect(kids(d, box), ['b', 'c']);
      expect(k('lc-multi-done'), findsNothing);
      expect(find.descendant(of: k('lc-selection-bar'), matching: find.text('容器')), findsOneWidget);
      // 撤销一次回到包之前。
      await tap(tester, find.byTooltip('撤销'));
      d = await saved(tester, session);
      expect(kids(d), ['b', 'c', 'a', 'box', 'e']);
    });

    testWidgets('多选：一起改样式（只列都有的项）、一起复制、一起删除；“完成”退出', (tester) async {
      final session = await openBuilder(tester, doc: flatDoc());
      await tap(tester, node('b'));
      await tap(tester, find.byTooltip('更多操作'));
      await tester.pumpAndSettle();
      await tapText(tester, '多选');
      await tap(tester, node('c'));
      await tap(tester, k('lc-multi-style'));
      await tester.pumpAndSettle();
      expect(find.text('一起改样式 · 2 个'), findsOneWidget);
      await show(tester, k('lc-preset-padding-24'));
      await shot(tester, '15-multi-style');
      await tap(tester, k('lc-preset-padding-24'));
      await back(tester);
      var d = await saved(tester, session);
      expect(d.find('b')!.props['padding'], 24);
      expect(d.find('c')!.props['padding'], 24);
      expect(d.find('a')!.props.containsKey('padding'), isFalse);
      await tap(tester, find.byTooltip('撤销'));
      d = await saved(tester, session);
      expect(d.find('b')!.props.containsKey('padding'), isFalse, reason: '一起改是一条撤销');
      expect(find.text('已选 2 个'), findsOneWidget, reason: '撤销以后多选还在');
      // 复制。
      await tap(tester, k('lc-multi-copy'));
      expect(find.textContaining('已复制 2 个'), findsOneWidget);
      expect(lcClipboardCount, 2);
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      // 删除。
      await tap(tester, k('lc-multi-more'));
      await tester.pumpAndSettle();
      await tapText(tester, '删除');
      d = await saved(tester, session);
      expect(kids(d), ['a', 'box', 'e']);
      expect(k('lc-multi-done'), findsNothing);
      // 粘贴回来：两个挨着。
      await longPress(tester, node('a'));
      await tapText(tester, '粘贴到它后面');
      d = await saved(tester, session);
      expect([for (final id in kids(d)) d.find(id)!.strProp('text') ?? id], ['甲', '乙', '丙', 'box', 'e']);
      // 从图层面板进多选，“完成”回到画布。
      await tap(tester, find.byTooltip('图层'));
      await tap(tester, k('lc-layer-multi'));
      await tap(tester, k('lc-layer-a'));
      await tap(tester, k('lc-layer-e'));
      await tap(tester, k('lc-layer-d'));
      expect(tester.widget<Text>(k('lc-layer-multi-note')).data, kLcMultiSameLevelOnly);
      expect(find.text('多选 · 已选 2 个'), findsOneWidget);
      await shot(tester, '16-layers-multi');
      await tap(tester, k('lc-layer-multi-done'));
      await tester.pumpAndSettle();
      expect(find.text('已选 2 个'), findsOneWidget);
      await tap(tester, k('lc-multi-done'));
      expect(find.text('已选 2 个'), findsNothing);
      expect(k('lc-selection-bar'), findsNothing);
    });

    testWidgets('多选：长按拖其中一个＝几个一起挪', (tester) async {
      final session = await openBuilder(tester, doc: flatDoc());
      await longPress(tester, node('a'));
      await tapText(tester, '多选');
      await tap(tester, node('b'));
      // 拖 a 到最后一个（e）的下半截。
      final from = tester.getCenter(node('a'));
      final to = tester.getRect(node('e')).bottomCenter - const Offset(0, 4);
      final g = await tester.startGesture(from);
      await tester.pump(kLcLiftAfter + const Duration(milliseconds: 40));
      for (var i = 1; i <= 8; i++) {
        await g.moveTo(Offset.lerp(from, to, i / 8)!);
        await tester.pump(const Duration(milliseconds: 16));
      }
      await tester.pump(const Duration(milliseconds: 100));
      await g.up();
      await tester.pumpAndSettle();
      final d = await saved(tester, session);
      expect(kids(d), ['c', 'box', 'e', 'a', 'b']);
      expect(find.text('已选 2 个'), findsOneWidget);
    });

    testWidgets('快捷动作：事件页里直接设“点击时打开网址”，存成一串普通积木；清空就去掉', (tester) async {
      final session = await openBuilder(tester, doc: flatDoc());
      await tap(tester, node('c'));
      await openCommon(tester);
      await tapText(tester, '事件');
      expect(find.text('快捷动作（不用进积木）'), findsOneWidget);
      await shot(tester, '17-quick-actions');
      await tap(tester, k('lc-quick-navigate'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'https://example.com');
      await tapText(tester, '保存');
      await settle(tester, rounds: 2);
      expect(find.text('https://example.com'), findsOneWidget);
      expect(find.text('1 块积木'), findsOneWidget, reason: '上面“点击时”那一行跟着变');
      await shot(tester, '18-quick-actions-set');
      var d = await saved(tester, session);
      final h = d.logic.handlersFor('c').single;
      expect(h.event, 'click');
      expect(h.body.single.op, 'navigate');
      await tap(tester, k('lc-quick-navigate'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, '');
      await tapText(tester, '保存');
      await settle(tester, rounds: 2);
      d = await saved(tester, session);
      expect(d.logic.handlersFor('c'), isEmpty);
    });

    testWidgets('小毛病：预设档展开以后不再重复那几档；就地改字的框和按钮一样宽；长按菜单不盖住被按的组件', (tester) async {
      await openBuilder(tester, doc: flatDoc());
      // 就地改字：小按钮“乙”。
      await tap(tester, node('b'));
      final button = tester.getRect(node('b'));
      await tap(tester, node('b'));
      await tester.pumpAndSettle();
      final edit = tester.getRect(find.ancestor(of: k('lc-inline-edit'), matching: find.byType(Material)).first);
      expect(button.width, lessThan(120), reason: '这个按钮本来就比以前的最小宽度窄');
      expect(edit.width, closeTo(button.width, 1), reason: '框和按钮一样宽');
      expect(edit.left, closeTo(button.left, 1));
      expect(tester.getRect(k('lc-inline-edit')).center.dy, closeTo(edit.center.dy, 1), reason: '字在框里上下居中，不贴着上沿');
      expect(kInlineEditMinWidth, lessThan(48));
      await shot(tester, '19-inline-edit-small-button');
      // 字打多了跟着变宽，不超出屏幕。
      await tester.enterText(k('lc-inline-edit'), '一个很长很长很长很长很长很长很长很长很长很长很长很长很长的名字');
      await tester.pumpAndSettle();
      final wide = tester.getRect(find.ancestor(of: k('lc-inline-edit'), matching: find.byType(Material)).first);
      expect(wide.width, greaterThan(button.width));
      expect(wide.right, lessThanOrEqualTo(390));
      await tester.enterText(k('lc-inline-edit'), '乙');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await settle(tester, rounds: 2);

      // 长按菜单：在被按的组件下面，不盖住它。
      await longPress(tester, node('b'));
      final menu = tester.getRect(find.ancestor(of: find.text('重复一份'), matching: find.byType(Material)).first);
      final pressed = tester.getRect(node('b'));
      expect(menu.top, greaterThanOrEqualTo(pressed.bottom), reason: '菜单 $menu 盖住了被按的组件 $pressed');
      await shot(tester, '20-node-menu-below');
      await back(tester);

      // 预设档：展开以后上面那一行不再摆那几档。
      canvas(tester).widget.onSelect('box'); // 点它的正中间会点到里面的字
      await settle(tester, rounds: 2);
      await openCommon(tester);
      await show(tester, k('lc-preset-padding-more'));
      expect(k('lc-preset-padding-16'), findsOneWidget);
      await shot(tester, '21-preset-closed');
      await tap(tester, k('lc-preset-padding-more'));
      expect(k('lc-preset-padding-16'), findsNothing, reason: '展开以后快捷档收起来，只剩下面那条完整的刻度');
      expect(k('lc-preset-padding-now'), findsOneWidget);
      expect(k('lc-scale-padding-16'), findsOneWidget);
      expect(find.descendant(of: k('lc-preset-padding-more'), matching: find.text('收起')), findsOneWidget);
      await show(tester, k('lc-scale-padding-16')); // 展开的那条刻度滚进屏幕再截
      await shot(tester, '22-preset-open');
      await show(tester, k('lc-scale-padding-16'));
      await tap(tester, k('lc-scale-padding-16'));
      await show(tester, k('lc-preset-padding-more'));
      await tap(tester, k('lc-preset-padding-more'));
      expect(k('lc-preset-padding-16'), findsOneWidget);
    });

    testWidgets('深色：多选、图层、常用页新行、选图标都画得出来', (tester) async {
      await openBuilder(tester, doc: flatDoc(), mode: ThemeMode.dark);
      await longPress(tester, node('b'));
      await tapText(tester, '多选');
      await tap(tester, node('c'));
      await shot(tester, '31-multi-dark');
      await tap(tester, k('lc-multi-done'));
      await tap(tester, find.byTooltip('图层'));
      await tap(tester, k('lc-layer-b'));
      await shot(tester, '32-layers-dark');
      await back(tester);
      await tap(tester, node('b'));
      await openCommon(tester);
      await show(tester, k('lc-common-icon'));
      await tap(tester, k('lc-common-icon'));
      await tester.pumpAndSettle();
      await shot(tester, '33-icon-picker-dark');
      await tap(tester, k('lc-icon-pick-star'));
      await tester.pumpAndSettle();
      await shot(tester, '34-button-common-dark');
    });
  });
}
