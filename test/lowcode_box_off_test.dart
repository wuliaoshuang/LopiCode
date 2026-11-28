// 第四轮 B7：容器的“禁用”“说明文字”，图标按钮（内置组件库）的“禁用”“说明文字”。
// 前半（不依赖外部环境）：模型、四种导出里各写成什么；没设这两样的容器一个字不多；旧的内置定义原地换新。
// 中间：Flutter 检入样本和导出器一致，真装进界面——禁用的变淡、点了不算数；说明文字是 Tooltip。
// 后半（开发机才有环境，找不到明确跳过）：三种网页导出真编译 0 错 0 警告；Node + jsdom 真跑——
// 禁用着的容器点它、点它里面的字都不算数；绑了状态的锁上以后点不动。
// 最后：搭建页里一步步点——选中容器 ›“常用”› 开“禁用”、填“说明文字”；选中图标按钮 › 开“禁用”。
// 没覆盖的：真浏览器、真手机、读屏软件真读出来什么。
@Tags(['external'])
library;

import 'dart:convert';
import 'dart:io';

// 导出的页面用的是 Flutter 自带的那套 Material：这里也得用它来装。
// ignore: deprecated_member_use
import 'package:flutter/material.dart' as m;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/lowcode/bind_model.dart';
import 'package:lopicode/lowcode/box_off.dart';
import 'package:lopicode/lowcode/comp_lib.dart';
import 'package:lopicode/lowcode/comp_lib_builtin.dart';
import 'package:lopicode/lowcode/component_model.dart';
import 'package:lopicode/lowcode/export_dart.dart';
import 'package:lopicode/lowcode/model.dart';

import 'generated/box_off_page.dart';
import 'support/bind_export_files.dart';
import 'support/box_off_sample.dart';
import 'support/comp_samples.dart';
import 'support/comp_steps.dart';
import 'support/dev_tools.dart';
import 'support/harness.dart';
import 'support/lowcode_builder.dart';

const _entry = {'html': 'index.html', 'vue': 'BoxOff.vue', 'react': 'BoxOff.jsx'};
const _label = {'html': '普通网页', 'vue': 'Vue 3', 'react': 'React'};
final String _shotDir = Platform.environment['LOPI_SHOT_DIR'] ?? '.tmp/b7-shots';

LcDocument _plain(Map<String, Object?> boxProps) => LcDocument.parse(
  jsonEncode({
    'version': 3,
    'title': 'P',
    'root': cn('root', 'page', {}, [
      cn('box', 'container', boxProps, [
        cn('t', 'text', {'text': '字'}),
      ]),
    ]),
  }),
);

Future<void> _tap(WidgetTester tester, Finder f, [String what = '要点的东西']) async {
  for (var i = 0; i < 40 && f.evaluate().isEmpty; i++) {
    await settle(tester, rounds: 1);
  }
  expect(f, findsWidgets, reason: '等不到 $what');
  await tester.tap(f.first, warnIfMissed: false);
  await tester.pump();
  await settle(tester, rounds: 4);
}

void main() {
  setUpAll(() async => lbFontsLoaded = await loadRealFonts());
  if (skipWithoutDom != false) {
    // ignore: avoid_print 跳过的原因要在测试输出里看得见
    print('【跳过】容器禁用的真编译 / 真跑：$skipWithoutDom');
  }

  group('模型', () {
    test('只有容器有；能绑到状态上', () {
      expect(lcBindable('container', 'disabled')?.type, 'bool');
      expect(lcBindable('container', 'alt')?.type, 'text');
      expect(lcBindable('row', 'disabled'), isNull);
      expect(lcBindable('card', 'alt'), isNull);
      final doc = boxOffDoc();
      expect(lcBoxOff(doc.find('b')!), isTrue);
      expect(lcBoxOff(doc.find('a')!), isFalse);
      expect(lcBoxGuarded(doc.find('c')!), isTrue, reason: '禁用绑了状态');
      expect(lcBoxLabel(doc.find('a')!), '加一');
      expect(lcBoxLabel(doc.find('c')!), isNull, reason: '说明文字绑了状态：没有写死的');
    });

    test('图标按钮多了两个属性；内置库版本 1.1.0', () {
      final def = boxOffDoc().component(lcBuiltinDefId('iconButton'))!;
      expect(def.props.map((p) => p.name), ['disabled', 'label']);
      expect(lcBuiltinPropLabel(def, 'disabled'), '禁用');
      expect(lcBuiltinPropLabel(def, 'label'), '说明文字');
      expect(kBuiltinCompLibVersion, '1.1.0');
    });

    test('文档里装着旧版（1.0.0）的图标按钮：打开时原地换新，实例不断、id 不变', () {
      final doc = boxOffDoc();
      final id = lcBuiltinDefId('iconButton');
      final i = doc.components.indexWhere((c) => c.id == id);
      final json = (jsonDecode(jsonEncode(doc.components[i].toJson())) as Map).cast<String, dynamic>();
      json.remove('props');
      (json[kCompLibMark] as Map)['version'] = '1.0.0';
      doc.components[i] = LcComponentDef.tryParse(json)!;
      expect(doc.components[i].props, isEmpty);
      expect(lcUpgradeBuiltins(doc), 1);
      expect(doc.components[i].id, id);
      expect(doc.components[i].props.map((p) => p.name), ['disabled', 'label']);
      expect(compLibOf(doc.components[i])?.version, '1.1.0');
      expect(lcUpgradeBuiltins(doc), 0, reason: '已经是新版：不动');
    });
  });

  group('四种导出', () {
    test('没设这两样的容器：四种导出和“根本没有这回事”时一个字不差', () {
      final a = allExportFiles(_plain({}));
      final b = allExportFiles(_plain({'disabled': false, 'alt': ''}));
      for (final k in a.keys) {
        expect(b[k], a[k], reason: k);
        expect(a[k], isNot(contains('aria-disabled')), reason: k);
        expect(a[k], isNot(contains('Tooltip(')), reason: k);
      }
    });

    test('没开禁用、没写说明文字的图标按钮：导出里一个字都不多', () {
      final doc = boxOffDoc();
      doc.root.children.removeWhere((n) => n.id != 'ib3' && n.id != 'hitText');
      final all = allExportFiles(LcDocument.parse(doc.encode()));
      for (final k in ['html/index.html', 'html/style.css', 'html/logic.js', 'flutter/page.dart']) {
        expect(all[k], isNot(contains('aria-disabled')), reason: k);
        // logic.js 的小工具里本来就有一句通用的 setAttribute("aria-label"…)（图片说明用的），不算这里多出来的。
        if (k != 'html/logic.js') expect(all[k], isNot(contains('aria-label')), reason: k);
        expect(all[k], isNot(contains('Tooltip(')), reason: k);
        expect(all[k], isNot(contains('Opacity(')), reason: k);
      }
    });

    test('写死的：网页带 aria-disabled / aria-label / title，公共样式变淡点不到；有逻辑时末尾带拦点击那一段', () {
      final all = allExportFiles(boxOffDoc());
      final html = all['html/index.html']!;
      expect(html, contains('aria-disabled="true" aria-label="关着的块" title="关着的块"'));
      expect(html, contains('aria-label="加一" title="加一"'));
      expect(all['html/style.css'], contains(kLcBoxOffCss));
      expect(all['html/logic.js'], contains('closest(\'[aria-disabled="true"]\')'));
      expect(all['vue/BoxOff.vue'], contains('@click.capture='));
      expect(all['react/BoxOff.jsx'], contains('onClickCapture='));
    });

    test('Flutter：禁用的变淡、不接点击；说明文字是 Tooltip（绑了状态的跟着状态走）', () {
      final dart = exportDart(boxOffDoc(), className: 'BoxOffPage');
      expect(dart, contains("Tooltip(message: '关着的块', child: Opacity(opacity: 0.5"));
      expect(dart, contains("Tooltip(message: '加一'"));
      expect(dart, contains('Tooltip(message: _lcText('), reason: '说明文字绑了状态');
      expect(File('test/generated/box_off_page.dart').readAsStringSync(), dart, reason: '导出器改了：运行 dart run tool/gen_sample_export.dart 重新生成');
    });

    testWidgets('Flutter 真装进界面：禁用着的图标按钮点了不加；没禁用的加；有 Tooltip', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const m.MaterialApp(home: BoxOffPage()));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('点了 0 次'), findsOneWidget);
      final icons = find.byIcon(m.Icons.add);
      expect(icons, findsNWidgets(3));
      await tester.tap(icons.at(0), warnIfMissed: false); // 写死禁用
      await tester.pump();
      expect(find.text('点了 0 次'), findsOneWidget);
      await tester.tap(icons.at(1)); // 禁用绑在状态上，这会儿没禁用
      await tester.pump();
      await tester.tap(icons.at(2));
      await tester.pump();
      expect(find.text('点了 2 次'), findsOneWidget);
      expect(find.byTooltip('收藏'), findsOneWidget);
      expect(find.byTooltip('点赞'), findsOneWidget);
      expect(find.byTooltip('关着的块'), findsOneWidget);
      expect(find.byTooltip('会锁上的块'), findsOneWidget, reason: '说明文字绑在状态 tip 上');
      final faded = find.ancestor(of: find.text('禁用的块'), matching: find.byType(Opacity));
      expect(tester.widget<Opacity>(faded.first).opacity, 0.5);
      expect(find.ancestor(of: find.text('能点的块'), matching: find.byType(Opacity)), findsNothing);
    });
  });

  group('三种网页导出真编译真跑', () {
    for (final kind in ['html', 'vue', 'react']) {
      final steps = kind == 'html' ? boxOffSteps() : compFileSteps(boxOffSteps(), kBoxOffDefs);
      test('${_label[kind]}：真编译 0 错误 0 警告', () async {
        final r = await compileExport('compile_$kind.mjs', exportFilesOf(boxOffDoc(), kind), _entry[kind]!);
        expect(r.errors, isEmpty, reason: r.raw);
        expect(r.warnings, isEmpty, reason: r.raw);
        expect(r.ok, isTrue);
      }, skip: skipWithoutDom);

      test('${_label[kind]}：真跑——禁用着的点了不算数，锁上以后绑着状态的也点不动', () async {
        final r = await runInDom(kind, exportFilesOf(boxOffDoc(), kind), _entry[kind]!, steps);
        expect(r.errors, isEmpty);
        expect(r.warnings, isEmpty);
        expect(r.done, steps.length);
        expect(r.ok, isTrue);
      }, skip: skipWithoutDom);
    }
  });

  group('搭建页里一步步点', () {
    testWidgets('选中容器 ›“常用”› 开“禁用”、填“说明文字”：存得上，画布上变淡；行、卡片没有这两行', (tester) async {
      final doc = LcDocument.parse(
        jsonEncode({
          'version': 3,
          'title': 'B7',
          'root': cn('root', 'page', {}, [
            cn(
              'box',
              'container',
              {'padding': 12, 'bg': '#EEF3F5'},
              [
                cn('t', 'text', {'text': '整块能点'}),
              ],
            ),
            cn('rw', 'row', {}, [
              cn('t2', 'text', {'text': '一行'}),
            ]),
          ]),
        }),
      );
      final session = await lbOpen(tester, doc: doc, selected: 'box');
      await lbOpenCommon(tester);
      await lbTapShown(tester, lbKey('lc-common-disabled'));
      final field = find.descendant(of: lbKey('box-alt'), matching: find.byType(EditableText));
      await lbShow(tester, field);
      await tester.enterText(field, '去购物车');
      await settle(tester, rounds: 3);
      final saved = await lbSaved(tester, session);
      expect(saved.find('box')!.props['disabled'], true);
      expect(saved.find('box')!.props['alt'], '去购物车');
      final faded = find.ancestor(of: find.text('整块能点'), matching: find.byType(Opacity));
      expect(faded.evaluate().map((e) => (e.widget as Opacity).opacity), contains(0.5), reason: '画布上变淡');
      await lbShot(tester, _shotDir, 'b7-box-off-panel');
      // 再拨回去：键去掉
      await lbTapShown(tester, lbKey('lc-common-disabled'));
      expect((await lbSaved(tester, session)).find('box')!.props.containsKey('disabled'), isFalse);
      expect(tester.takeException(), isNull);
    });

    testWidgets('选中一行（不是容器）›“常用”：没有“禁用”“说明文字”这两行', (tester) async {
      final doc = LcDocument.parse(
        jsonEncode({
          'version': 3,
          'title': 'B7',
          'root': cn('root', 'page', {}, [
            cn('rw', 'row', {}, [
              cn('t2', 'text', {'text': '一行'}),
            ]),
          ]),
        }),
      );
      await lbOpen(tester, doc: doc, selected: 'rw');
      await lbOpenCommon(tester);
      expect(lbKey('lc-common-wrap'), findsWidgets, reason: '面板开着、是这一行的');
      expect(lbKey('lc-common-disabled'), findsNothing);
      expect(lbKey('rw-alt'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('选中图标按钮 ›“常用”：属性叫“禁用”“说明文字”；开了禁用存进实例', (tester) async {
      final doc = boxOffDoc();
      doc.root.children.removeWhere((n) => n.id != 'ib3' && n.id != 'hitText');
      final session = await lbOpen(tester, doc: LcDocument.parse(doc.encode()), selected: 'ib3');
      await lbOpenCommon(tester);
      await lbShow(tester, lbKey('comp-value-disabled'));
      expect(find.textContaining('禁用 · '), findsWidgets);
      expect(find.textContaining('说明文字 · '), findsWidgets);
      await lbShot(tester, _shotDir, 'b7-icon-button-panel');
      await _tap(tester, find.descendant(of: lbKey('comp-value-disabled'), matching: find.byWidgetPredicate((w) => '${w.runtimeType}' == 'Switch')));
      expect((await lbSaved(tester, session)).find('ib3')!.props['values'], {'disabled': true});
      expect(tester.takeException(), isNull);
    });
  });
}
