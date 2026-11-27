// 第四轮 B5：内置组件库，从头到尾一步步点——
// 右上角 ⋮ ›“组件库”› 最上面一行“内置组件库”› 点开看 ›“卡片”下面点“复制一份来改”
// → ⋮ ›“自定义组件”› 副本那一行的 ⋮ ›“编辑内容”› 在画布上往里加一个文字 › 完成 → 存盘里副本变了。
// 组件盒：“表单”里点“步进器”→ 页面上多一个实例，定义这时候才装进文档（带着来源，只读）；
// 选中它 ›“更多操作”›“编辑组件”› 提示它是库里的 ›“复制一份来改”› 进编辑页。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/core/safe_file.dart';
import 'package:lopicode/core/templates.dart';
import 'package:lopicode/lowcode/builder_screen.dart';
import 'package:lopicode/lowcode/comp_lib.dart';
import 'package:lopicode/lowcode/comp_lib_builtin.dart';
import 'package:lopicode/lowcode/palette_widgets.dart';
import 'package:lopicode/project_session.dart';
import 'package:material_ui/material_ui.dart';

import 'support/comp_samples.dart';
import 'support/harness.dart';
import 'support/lowcode_builder.dart';

final String _shotDir = Platform.environment['LOPI_SHOT_DIR'] ?? '.tmp/b5-shots';

Future<void> _until(WidgetTester tester, Finder f, String what) async {
  for (var i = 0; i < 40 && f.evaluate().isEmpty; i++) {
    await settle(tester, rounds: 1);
  }
  expect(f, findsWidgets, reason: '等不到 $what');
}

Future<void> _tap(WidgetTester tester, Finder f, [String what = '要点的东西']) async {
  await _until(tester, f, what);
  await tester.tap(f.first, warnIfMissed: false);
  await tester.pump();
  await settle(tester, rounds: 4);
}

Future<void> _back(WidgetTester tester) async {
  await tester.binding.handlePopRoute();
  await tester.pump();
  await settle(tester, rounds: 4);
}

Future<void> _menu(WidgetTester tester, String label) async {
  await _tap(tester, find.byTooltip('更多').last);
  await _tap(tester, find.widgetWithText(PopupMenuItem<String>, label));
}

Future<void> _add(WidgetTester tester, String group, String itemKey) async {
  final panel = find.byType(PalettePanel);
  if (panel.evaluate().isEmpty || tester.state<PalettePanelState>(panel).collapsed) await _tap(tester, lbKey('lc-tool-add').last);
  await _tap(tester, lbKey('palette-group-$group'));
  // 一类里东西多了要滑一下才看得到（手机上用手滑；这里滚到它露出来再点）
  await _until(tester, lbKey('palette-item-$itemKey'), '组件盒里的 $itemKey');
  await lbShow(tester, lbKey('palette-item-$itemKey'));
  await settle(tester, rounds: 2);
  await _tap(tester, lbKey('palette-item-$itemKey'), '组件盒里的 $itemKey');
}

Future<ProjectSession> _open(WidgetTester tester) async {
  usePhoneViewport(tester);
  late TestEnv env;
  late ProjectSession a;
  await tester.runAsync(() async {
    env = await TestEnv.create();
    a = ProjectSession(env.services, await env.services.projects.create('项目甲', ProjectTemplate.lowcode));
    File(a.guard.resolve(kLowcodePageFile)).writeAsStringSync(compUserDoc(const []).encode());
  });
  addTearDown(() async {
    await pendingWrites();
    a.dispose();
    await env.dispose();
  });
  await tester.pumpWidget(
    appFor(
      env,
      BuilderScreen(key: UniqueKey(), session: a),
      font: lbFontsLoaded ? kTestFont : null,
    ),
  );
  await settle(tester, rounds: 6);
  return a;
}

void main() {
  setUpAll(() async => lbFontsLoaded = await loadRealFonts());

  testWidgets('组件库面板：内置组件库点得开、看得到十四个；复制卡片来改，在画布上改完存得上', (tester) async {
    final a = await _open(tester);
    final before = (await lbSaved(tester, a)).encode();

    await _menu(tester, '组件库');
    await _until(tester, lbKey('complib-builtin'), '内置组件库那一行');
    expect(find.text('内置组件库'), findsOneWidget);
    expect(find.textContaining('应用自带 · 只读 · 14 个组件'), findsOneWidget);
    await lbShot(tester, _shotDir, 'b5-lib-list');
    await _tap(tester, lbKey('complib-builtin'));
    await _until(tester, lbKey('complib-peek'), '库里的组件');
    expect(find.textContaining('lopi/builtin · 1.0.0'), findsOneWidget);
    await lbShot(tester, _shotDir, 'b5-lib-peek');
    // 清单是滚着看的：一个个滚出来，十四个都在，各有一个“复制一份来改”
    for (final b in kBuiltinComps) {
      final f = lbKey('complib-fork-${b.id}');
      for (var i = 0; i < 30 && f.evaluate().isEmpty; i++) {
        await tester.drag(lbKey('complib-peek'), const Offset(0, -160));
        await tester.pump();
      }
      expect(f, findsOneWidget, reason: b.id);
    }
    await lbShot(tester, _shotDir, 'b5-lib-peek-end');
    // 关掉再点开（回到最上面）
    await _back(tester);
    await _tap(tester, lbKey('complib-builtin'));
    await _until(tester, lbKey('complib-fork-card'), '卡片的“复制一份来改”');
    // 只是看：文档一个字没动
    expect((await lbSaved(tester, a)).encode(), before);

    await _tap(tester, lbKey('complib-fork-card'));
    await _until(tester, find.textContaining('已复制成项目自己的「卡片 副本」'), '复制成功的提示');
    var doc = await lbSaved(tester, a);
    expect(doc.components.single.id, 'c1');
    expect(doc.components.single.name, '卡片 副本');
    expect(compLibOf(doc.components.single), isNull, reason: '副本是项目自己的');
    expect(doc.components.single.root.type, 'card');
    await _back(tester);

    // 自定义组件 › 副本 › 编辑内容 › 往里加一个文字
    await _menu(tester, '自定义组件');
    await _until(tester, lbKey('comp-item-c1'), '副本那一行');
    await _tap(tester, find.byTooltip('卡片 副本 的更多操作'));
    await _tap(tester, find.widgetWithText(PopupMenuItem<String>, '编辑内容'));
    await _until(tester, lbKey('comp-editor-done'), '编辑组件页');
    await lbShot(tester, _shotDir, 'b5-fork-editor');
    await _add(tester, 'basic', 'text');
    await _tap(tester, lbKey('comp-editor-done'));
    doc = await lbSaved(tester, a);
    expect(doc.components.single.root.children.map((n) => n.type), containsAll(['slot', 'text']));
    expect(tester.takeException(), isNull);
  });

  testWidgets('组件盒：点出步进器，定义这时才装进文档；它是只读的，“编辑组件”先复制一份', (tester) async {
    final a = await _open(tester);
    expect((await lbSaved(tester, a)).components, isEmpty);
    final ids0 = (await lbSaved(tester, a)).root.children.map((n) => n.id).toSet();

    await _tap(tester, lbKey('lc-tool-add').last);
    await _tap(tester, lbKey('palette-group-form'));
    await _until(tester, lbKey('palette-item-slider'), '“表单”里的滑块');
    await lbShot(tester, _shotDir, 'b5-palette-form');
    await _tap(tester, lbKey('palette-item-component:${lcBuiltinDefId('stepper')}'));
    var doc = await lbSaved(tester, a);
    expect(doc.components.single.id, lcBuiltinDefId('stepper'));
    expect(lcIsBuiltinDef(doc.components.single), isTrue);
    final inst = doc.root.children.firstWhere((n) => !ids0.contains(n.id));
    expect(inst.type, 'component');
    expect(inst.props['ref'], lcBuiltinDefId('stepper'));
    // “我的”里没有它（它在“表单”里）
    expect(lbKey('palette-group-form'), findsOneWidget);
    expect(lbKey('palette-group-mine'), findsNothing, reason: '没有自己做的组件，就没有“我的”这一类');
    await _back(tester);

    // 画布上有它：减号、数字、加号
    await _until(tester, lbNode(inst.id), '画布上的步进器');
    expect(find.text('1'), findsWidgets);
    await lbShot(tester, _shotDir, 'b5-stepper-on-canvas');

    // 撤销：实例和定义一起回去
    await _tap(tester, find.byTooltip('撤销'));
    doc = await lbSaved(tester, a);
    expect(doc.components, isEmpty);
    await _tap(tester, find.byTooltip('重做'));
    doc = await lbSaved(tester, a);
    expect(doc.components.single.id, lcBuiltinDefId('stepper'));

    // 编辑组件：它是库里的 → 复制一份来改 → 进编辑页
    await _tap(tester, lbNode(inst.id));
    await _tap(tester, find.byTooltip('更多操作'));
    await _tap(tester, find.widgetWithText(PopupMenuItem<String>, '编辑组件'));
    await _until(tester, find.textContaining('内置组件库'), '“它是库里的组件”的说明');
    await lbShot(tester, _shotDir, 'b5-readonly-ask');
    await _tap(tester, find.widgetWithText(TextButton, '复制一份来改'));
    await _until(tester, lbKey('comp-editor-done'), '编辑组件页');
    await _tap(tester, lbKey('comp-editor-done'));
    doc = await lbSaved(tester, a);
    expect(doc.components.map((c) => c.name), containsAll(['步进器', '步进器 副本']));
    expect(tester.takeException(), isNull);
  });

  testWidgets('六个 P1 组件：组件盒里各点一个上画布，都画得出来；链接在面板里改得了字，网格选得了列数', (tester) async {
    final a = await _open(tester);
    const where = {'iconButton': 'basic', 'link': 'basic', 'grid': 'layout', 'scroll': 'layout', 'stepper': 'form', 'formItem': 'form'};
    final made = <String, String>{};
    for (final e in where.entries) {
      final before = (await lbSaved(tester, a)).root.children.map((n) => n.id).toSet();
      // 每次先取消选中：不然新的会被放到刚才那个的里面或后面
      lbCanvas(tester).widget.onSelect(null);
      await settle(tester, rounds: 2);
      await _add(tester, e.value, 'component:${lcBuiltinDefId(e.key)}');
      final doc = await lbSaved(tester, a);
      final fresh = [
        for (final n in doc.root.children)
          if (!before.contains(n.id)) n,
      ];
      expect(fresh, hasLength(1), reason: '${e.key} 应该放在页面最外层');
      expect(fresh.single.props['ref'], lcBuiltinDefId(e.key));
      made[e.key] = fresh.single.id;
      expect(tester.takeException(), isNull, reason: '${e.key} 画的时候出了异常');
    }
    lbCanvas(tester).widget.onSelect(null);
    await settle(tester, rounds: 2);
    final doc0 = await lbSaved(tester, a);
    expect(doc0.components.map((c) => c.name).toSet(), {'图标按钮', '链接', '网格', '滚动区', '步进器', '表单项'});
    expect(find.text('链接'), findsWidgets);
    expect(find.text('标签'), findsWidgets);
    await lbShot(tester, _shotDir, 'b5-p1-all-on-canvas');

    // 链接：面板里改字
    await _tap(tester, lbNode(made['link']!));
    await lbOpenCommon(tester);
    await lbShow(tester, lbKey('comp-value-text'));
    await lbShot(tester, _shotDir, 'b5-link-panel');
    final field = find.descendant(of: lbKey('comp-value-text'), matching: find.byType(TextField));
    await tester.enterText(field, '看详情');
    await settle(tester, rounds: 3);
    expect((await lbSaved(tester, a)).find(made['link']!)!.props['values'], {'text': '看详情'});
    expect(find.text('看详情'), findsWidgets, reason: '画布上跟着变');
    await _back(tester);

    // 网格：选“3 列”
    await _tap(tester, lbNode(made['grid']!));
    await lbOpenCommon(tester);
    await lbShow(tester, lbKey('comp-instance-extras'));
    await lbTapShown(tester, lbKey('comp-variant-cols'));
    await _tap(tester, lbKey('comp-variant-pick-c3'));
    await lbShot(tester, _shotDir, 'b5-grid-cols');
    expect((await lbSaved(tester, a)).find(made['grid']!)!.more['variant'], {'cols': 'c3'});
    expect(tester.takeException(), isNull);
  });

  testWidgets('滑块：“表单”里点出来，画布上有；面板里改最大、现在的值、禁用，存得上', (tester) async {
    final a = await _open(tester);
    final before = (await lbSaved(tester, a)).root.children.map((n) => n.id).toSet();
    await _add(tester, 'form', 'slider');
    var doc = await lbSaved(tester, a);
    final sl = doc.root.children.firstWhere((n) => !before.contains(n.id));
    expect(sl.type, 'slider');
    expect(sl.props, {'value': 50, 'min': 0, 'max': 100, 'step': 1, 'width': 'fill'});
    await _back(tester);
    await _tap(tester, lbNode(sl.id));
    await lbOpenCommon(tester);
    await lbShow(tester, lbKey('lc-common-max'));
    await lbShot(tester, _shotDir, 'b5-slider-panel');
    await tester.enterText(lbKey('lc-common-max'), '10');
    await settle(tester, rounds: 2);
    await tester.enterText(lbKey('lc-common-value'), '0');
    await settle(tester, rounds: 2);
    await lbTapShown(tester, lbKey('lc-common-disabled'));
    doc = await lbSaved(tester, a);
    expect(doc.find(sl.id)!.props, {'value': 0, 'min': 0, 'max': 10, 'step': 1, 'width': 'fill', 'disabled': true});
    await lbShot(tester, _shotDir, 'b5-slider-on-canvas');
    expect(tester.takeException(), isNull);
  });
}
