// 积木第 4 版·第 2 阶段的截图（390×844，浅色 + 深色，真的后端积木页）：
//   LOPI_SHOTS=1 flutter test --no-pub test/backend_func_shots_test.dart   # 写到 .tmp/blocks-v4-preview/stage2/*.png
// 不带 LOPI_SHOTS 时只走一遍流程、确认不出异常。
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/backend/backend_targets.dart';
import 'package:lopicode/blocks/block_dock.dart';
import 'package:lopicode/blocks/block_palette_model.dart';
import 'package:lopicode/core/templates.dart';
import 'package:lopicode/lang/rules.dart';
import 'package:lopicode/lowcode/logic_model.dart';
import 'package:material_ui/material_ui.dart';

import 'backend_func_ui_test.dart' show holdBlock, seed;
import 'backend_screen_test.dart' show be, boot, doc, ed, flushed, k, paletteTab;
import 'blocks_custom_ui_test.dart' show press, reveal, type;
import 'screens_test.dart' show fontsLoaded, writeShots;
import 'support/backend_func_blocks.dart';
import 'support/backend_lang_blocks.dart';
import 'support/harness.dart' hide call;

const String kStage2Dir = '.tmp/blocks-v4-preview/stage2';

Future<void> snap(WidgetTester tester, String name) async {
  expect(tester.takeException(), isNull, reason: '$name 渲染时出了异常');
  if (!writeShots || !fontsLoaded) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(shotKey));
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('$kStage2Dir/$name.png');
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(data!.buffer.asUint8List());
  });
}

/// 截图用的三块自定义积木（语句 / 值 / 是否各一）和一个把它们都用上的接口。
List<J> showFunctions() => [
  {
    ...fnDef(
      'f1',
      '打招呼',
      [par('谁'), par('次数', def: 1)],
      [
        blk(
          'forCount',
          {'name': 'i', 'from': nm(0), 'to': pm('次数'), 'step': nm(1)},
          [
            blk('log', {
              'value': cat([tx('你好，'), pm('谁')]),
            }),
          ],
        ),
      ],
    ),
    'look': {
      'name': '打招呼',
      'shape': 'auto',
      'template': '向 {谁} 打招呼 {次数} 次',
      'slots': [
        {'name': '次数', 'defaultValue': 1},
      ],
    },
    'x': 0,
    'y': 2000,
  },
  {
    ...fnDef('f2', '加倍', [par('数')], [ret(op2('*', pm('数'), nm(2)))]),
    'look': {'name': '加倍', 'shape': 'auto', 'template': '{数} 的两倍', 'colorKey': 'operator'},
    'x': 0,
    'y': 3120,
  },
  {
    ...fnDef('f3', '是偶数', [par('n')], [ret(op2('==', op2('%', pm('n'), nm(2)), nm(0)))]),
    'look': {'name': '是偶数', 'shape': 'auto', 'template': '{n} 是偶数'},
    'x': 0,
    'y': 3280,
  },
];

J showRoute() => {
  ...route('show', 'GET', '/greet', [
    callS('f1', {'谁': q('name'), '次数': nm(2)}),
    let(
      'xs',
      hof(
        'listMap',
        ls([nm(1), nm(2), nm(3)]),
        lam(
          ['x'],
          [
            ret(call('f2', {'数': pm('x')})),
          ],
        ),
      ),
    ),
    iff(call('f3', {'n': nm(4)}), [json(vr('xs'))], orElse: [json(tx('单数'))]),
  ]),
  'x': 0,
  'y': 2190,
};

J wrapRoute() => {
  ...route('wrap', 'POST', '/notes', [
    let('note', ex('bodyField', {'name': 'text'})),
    let('all', ls([])),
    push('all', vr('note')),
    blk('log', {
      'value': cat([tx('记下了：'), vr('note')]),
    }),
  ]),
  'x': 0,
  'y': 3600,
};

Future<void> frame(WidgetTester tester, String id, {double zoom = 1, double top = 12}) async {
  final s = ed(tester);
  final origin = s.layout.placed(id)!.origin;
  s.setZoom(zoom, Offset.zero);
  s.setPan(Offset(16 - origin.dx * s.zoom, top - origin.dy * s.zoom));
  // ignore: invalid_use_of_protected_member 截图前摆好画布位置，只为重画一下
  s.setState(() {});
  await tester.pumpAndSettle();
}

Future<void> dockDown(WidgetTester tester) async {
  await tester.drag(k('bk-palette-grip'), const Offset(0, 300), warnIfMissed: false);
  await tester.pumpAndSettle();
}

Future<void> dockUp(WidgetTester tester) async {
  await tester.drag(k('bk-palette-grip'), const Offset(0, -420), warnIfMissed: false);
  await tester.pumpAndSettle();
}

/// 测试环境默认把投影画成一圈实心黑边（debugDisableShadows）；出截图时按真机的画法（柔和的投影）画，测完改回去。
Future<void> realShadows(Future<void> Function() body) async {
  debugDisableShadows = !writeShots;
  try {
    await body();
  } finally {
    debugDisableShadows = true;
  }
}

void main() {
  // 这个文件考的是老规矩（规矩版本 1）的行为：新建的文档现在默认是严格规矩，这里钉回 1，测完改回去。
  setUp(() => beNewDocRules = kLangRulesLoose);
  tearDown(() => beNewDocRules = kLangRulesForNewDocs);

  setUpAll(() async => fontsLoaded = await loadRealFonts());
  tearDown(BkDockMemory.clear);

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    final suffix = mode == ThemeMode.light ? 'light' : 'dark';
    testWidgets(
      '截图：定义帽子 + 调用的画布、“我的积木”页签、“函数”“列表”页、新建积木页、看代码里的函数（$suffix）',
      (tester) => realShadows(() async {
        await boot(
          tester,
          ProjectTemplate.backendBlocks,
          language: 'node',
          mode: mode,
          before: seed(routes: [showRoute()], functions: showFunctions()),
        );
        expect(
          [
            for (final i in be(tester).host!.issues)
              if (i.isError || const {'show', 'f1', 'f2', 'f3'}.contains(i.scriptId)) '${i.rule} ${i.message}',
          ],
          isEmpty,
          reason: '截图用的文档本身没有问题',
        );
        await dockDown(tester);
        await frame(tester, 'f1', zoom: 0.9);
        await snap(tester, 'be5-canvas-$suffix');
        await frame(tester, 'f2', zoom: 1, top: 40);
        await snap(tester, 'be5-defs-$suffix');
        await dockUp(tester);
        await frame(tester, 'f1', zoom: 0.9);
        for (final (tab, name) in [(bkCustomCategoryId, 'mine'), ('函数', 'palette-fn'), ('列表', 'palette-list')]) {
          await paletteTab(tester, tab);
          if (tab == '列表') {
            // 拿函数当参数的那一组在这一页最下面：滑到它露出来再截。
            final title = find.text('每一项都交给一个函数');
            for (var i = 0; i < 20 && (title.evaluate().isEmpty || tester.getTopLeft(title).dy > 460); i++) {
              await tester.dragFrom(const Offset(195, 640), const Offset(0, -120));
              await tester.pumpAndSettle();
            }
            expect(title, findsOneWidget);
          }
          await snap(tester, 'be5-$name-$suffix');
        }

        // 新建积木页：填到一半的样子（名字、两个参数、一句文案）。
        await paletteTab(tester, bkCustomCategoryId);
        await tester.tap(k('bk-palette-custom-new'));
        await tester.pumpAndSettle();
        await type(tester, 'bk-look-name', '问好');
        await press(tester, 'bk-look-param-add');
        await type(tester, 'bk-look-param-name-0', '名字');
        await press(tester, 'bk-look-param-add');
        await type(tester, 'bk-look-param-name-1', '次数');
        await type(tester, 'bk-look-param-value-1', '1');
        await type(tester, 'bk-look-template', '向 {名字} 问好 {次数} 次');
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle();
        await reveal(tester, 'bk-look-name');
        await tester.drag(k('bk-look-form'), const Offset(0, 3000));
        await tester.pumpAndSettle();
        await snap(tester, 'be5-new-$suffix');
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        if (find.text('不保存').evaluate().isNotEmpty) {
          await tester.tap(find.text('不保存'));
          await tester.pumpAndSettle();
        }

        // 看代码：函数排在接口前面。
        await flushed(tester);
        await tester.tap(k('bk-code'));
        await tester.pumpAndSettle();
        expect(be(tester).host!.codeText, contains('f_'));
        await snap(tester, 'be5-code-$suffix');
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }),
    );

    testWidgets(
      '截图：包成积木之前（长按出来的菜单）、起名字、包完以后（$suffix）',
      (tester) => realShadows(() async {
        await boot(
          tester,
          ProjectTemplate.backendBlocks,
          language: 'node',
          mode: mode,
          before: seed(routes: [wrapRoute()]),
        );
        await dockDown(tester);
        await frame(tester, 'wrap', top: 24);
        await holdBlock(tester, 'wrap', [lcStep(2)]);
        expect(k('bk-block-menu-wrap'), findsOneWidget);
        // 小菜单贴在“要包进去的那一截”下面，不盖住它们。
        final s = ed(tester);
        final placed = s.layout.placed('wrap')!;
        final last = placed.layout.blockAt([lcStep(3)])!;
        final bottom = s.globalOf(s.toView(last.rect.shift(placed.origin).bottomLeft)).dy;
        expect(tester.getTopLeft(k('bk-block-menu-wrap')).dy, greaterThanOrEqualTo(bottom));
        await snap(tester, 'be5-wrap-before-$suffix');
        await tester.tap(k('bk-block-menu-wrap'));
        await tester.pumpAndSettle();
        await type(tester, 'bk-look-name', '记下来');
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle();
        await tester.drag(k('bk-look-form'), const Offset(0, 3000));
        await tester.pumpAndSettle();
        await snap(tester, 'be5-wrap-name-$suffix');
        await press(tester, 'bk-look-done');
        expect(doc(tester).functions.single.name, '记下来');
        await frame(tester, 'wrap', top: 24);
        await snap(tester, 'be5-wrap-after-$suffix');
        expect(tester.takeException(), isNull);
      }),
    );
  }
}
