// 积木第 5 版·核心 1：类型问题在后端积木页上的样子（390×844，浅色 + 深色）。
//   LOPI_SHOTS=1 flutter test --no-pub test/backend_type_ui_test.dart   # 截图写到 ../preview/types/（不进 git）
//
// 整个应用外壳真的搭起来：严格规矩的文档 → 积木上标红 → 点角标看到提示语原文和修法按钮 → 点了修好、撤销回来；
// 选中积木多一行类型、“标类型”；老规矩的文档从“更多”菜单升级；老规矩的文档别的地方和以前一样。
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/backend/backend_model.dart';
import 'package:lopicode/backend/backend_targets.dart';
import 'package:lopicode/backend/backend_validate.dart';
import 'package:lopicode/blocks/block_canvas_view.dart';
import 'package:lopicode/blocks/block_dock.dart';
import 'package:lopicode/blocks/block_host.dart';
import 'package:lopicode/blocks/block_issue_view.dart';
import 'package:lopicode/core/templates.dart';
import 'package:lopicode/lang/rules.dart';
import 'package:lopicode/lang/types.dart';
import 'package:lopicode/lang/types_json.dart';
import 'package:lopicode/lowcode/logic_model.dart';
import 'package:lopicode/ui/backend_screen.dart';
import 'package:material_ui/material_ui.dart';

import 'backend_screen_test.dart' show at, be, boot, doc, ed, k, more, paletteTab, saved, text, until;
import 'screens_test.dart' show fontsLoaded, shot;
import 'support/backend_func_blocks.dart';
import 'support/backend_lang_blocks.dart' hide text;
import 'support/harness.dart' show loadRealFonts;

const String out = '../../../preview/types';

J tpar(String name, LType t) => {'name': name, 'type': lTypeToJson(t)};

/// 一份带类型问题的文档：两块“我的积木”＋一个接口。
void seed(int rules) {
  final json = jsonDecode(text(kBackendFileName)) as Map<String, dynamic>;
  json['rules'] = rules;
  json['functions'] = [
    fnDef('f1', '加倍', [tpar('x', LType.integer)], [ret(op2('*', pm('x'), nm(2)))]),
    fnDef('f2', '喊', [tpar('话', LType.text)], [ret(pm('话'))]),
  ];
  json['routes'] = [
    route('r1', 'GET', '/a', [
      let('total', call('f1', {'x': tx('12')})),
      let('b', call('f2', {'话': nm(3)})),
      iff(nm(1), [json_(vr('total'))], noElse: true),
      let('n', call('f1', {'x': nm(3)})),
      json_(nm(1)),
    ]),
  ];
  at(kBackendFileName).writeAsStringSync(jsonEncode(json));
}

J json_(J v) => json(v);

Offset badge(WidgetTester tester, String id, LcBlockPath path) {
  final s = ed(tester);
  final p = s.layout.placed(id)!;
  final b = path.isEmpty ? p.layout.hat! : p.layout.blockAt(path)!;
  return s.globalOf(s.toView(p.origin + bkIssueBadgeCenter(b, s.kit.metrics)));
}

List<BlockIssue> typeIssues(WidgetTester tester) => [
  for (final i in be(tester).host!.issues)
    if (i.rule.startsWith('T')) i,
];

Future<void> open(WidgetTester tester, int rules, {ThemeMode mode = ThemeMode.light}) async {
  await boot(tester, ProjectTemplate.backendBlocks, language: 'node', mode: mode, before: () => seed(rules));
  await tester.drag(k('bk-palette-grip'), const Offset(0, 300), warnIfMissed: false);
  await tester.pumpAndSettle();
  ed(tester).jumpTo('r1', const []);
  await tester.pumpAndSettle();
  ed(tester).select(null);
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async => fontsLoaded = await loadRealFonts());
  tearDown(BkDockMemory.clear);

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    final suffix = mode == ThemeMode.light ? 'light' : 'dark';
    testWidgets('严格规矩：标红 → 小卡里提示语原文和修法 → 点了修好 → 撤销回来（$suffix）', (tester) async {
      await open(tester, 2, mode: mode);
      final host = be(tester).host!;
      final before = typeIssues(tester);
      expect([for (final i in before) i.problem], ['「加倍」的第 1 个参数要整数，放进来的是文字', '「喊」的第 1 个参数要文字，放进来的是整数', '这里要“是/否”，放进来的是整数']);
      expect(before.every((i) => i.isError && i.scriptId == 'r1' && i.arg != null), isTrue, reason: '都对到了具体哪一格');
      expect(host.errorCount, greaterThanOrEqualTo(3));
      await shot(tester, '$out/1-marks-$suffix');

      // 点第 1 块的角标：小卡里有原文、建议、编号和修法按钮。
      await tester.tapAt(badge(tester, 'r1', [lcStep(0)]));
      await tester.pumpAndSettle();
      final card = k('bk-issue-card');
      expect(card, findsOneWidget);
      expect(find.descendant(of: card, matching: find.textContaining('「加倍」的第 1 个参数要整数，放进来的是文字')), findsOneWidget);
      expect(find.descendant(of: card, matching: find.textContaining('T01')), findsOneWidget);
      expect(find.descendant(of: card, matching: find.text('变成整数（变不了就是空）')), findsOneWidget);
      await shot(tester, '$out/2-card-fix-$suffix');

      // 点修法：小卡关掉，积木真的换了；这一条换成“可能是空”，再点“是空就用”才干净。
      await tester.tap(find.descendant(of: card, matching: find.text('变成整数（变不了就是空）')));
      await tester.pumpAndSettle();
      expect(card, findsNothing);
      final x = (doc(tester).routes.first.body[0].args['value'] as Map)['x'] as Map;
      expect(x['e'], 'parseInt');
      expect(typeIssues(tester).first.problem, contains('可能是空'));
      await tester.tapAt(badge(tester, 'r1', [lcStep(0)]));
      await tester.pumpAndSettle();
      await shot(tester, '$out/3-card-null-$suffix');
      await tester.tap(find.descendant(of: card, matching: find.widgetWithText(FilledButton, '是空就用 …')));
      await tester.pumpAndSettle();
      expect(typeIssues(tester).length, 2);
      expect(((doc(tester).routes.first.body[0].args['value'] as Map)['x'] as Map)['e'], 'orElse');

      // 撤销两次：两条修法各是一条撤销记录，问题原样回来。
      expect(host.canUndo, isTrue);
      host.undo();
      host.undo();
      await tester.pumpAndSettle();
      expect([for (final i in typeIssues(tester)) i.problem], [for (final i in before) i.problem]);
      expect(((doc(tester).routes.first.body[0].args['value'] as Map)['x'] as Map)['e'], 'text');

      // 问题列表里也有修法按钮；点了列表关掉、问题少一条。
      await tester.tap(k('bk-issues'));
      await tester.pumpAndSettle();
      expect(find.text('变成文字'), findsOneWidget);
      await shot(tester, '$out/4-list-$suffix');
      await tester.tap(find.text('变成文字'));
      await tester.pumpAndSettle();
      expect(typeIssues(tester).length, 2);
      expect(((doc(tester).routes.first.body[1].args['value'] as Map)['话'] as Map)['e'], 'convert');
      await tester.tapAt(badge(tester, 'r1', [lcStep(2)]));
      await tester.pumpAndSettle();
      expect(find.descendant(of: card, matching: find.widgetWithText(FilledButton, '换成“… ≠ 0”')), findsOneWidget);
      await tester.tap(k('bk-issue-fix-0'));
      await tester.pumpAndSettle();
      expect(typeIssues(tester).length, 1);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('严格规矩：选中积木多一行类型；“标类型”改参数、结果、变量；积木盒多三块', (tester) async {
    await open(tester, 2);
    final host = be(tester).host!;
    // 没选中：不显示。
    expect(k('bk-type-line'), findsNothing);
    ed(tester).select(BlockSelection('r1', [lcStep(3)]));
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(k('bk-type-line')).data, 'n：整数');
    expect(k('bk-type-edit'), findsOneWidget);
    await shot(tester, '$out/5-type-line-var');
    // 给变量标“小数”。
    await tester.tap(k('bk-type-edit'));
    await tester.pumpAndSettle();
    expect(k('be-type-picker'), findsOneWidget);
    await shot(tester, '$out/6-type-picker');
    await tester.tap(k('be-type-number'));
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(k('be-type-now')).data, '现在：小数');
    await tester.tap(k('be-type-done'));
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(k('bk-type-line')).data, 'n：小数');
    await until(tester, () => (saved().routes.first.body[3].args['type'] as Map?)?['k'] == 'number', '变量的类型存盘');
    host.undo();
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(k('bk-type-line')).data, 'n：整数');

    // 调用积木：显示那块积木的参数和结果。
    ed(tester).jumpTo('f1', const []);
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(k('bk-type-line')).data, '加倍：(整数) → 整数');
    await shot(tester, '$out/7-type-line-def');
    await tester.tap(k('bk-type-edit'));
    await tester.pumpAndSettle();
    expect(k('be-types-sheet'), findsOneWidget);
    expect(find.descendant(of: k('be-type-param-x'), matching: find.text('整数')), findsOneWidget);
    expect(find.descendant(of: k('be-type-returns'), matching: find.text('没标')), findsOneWidget);
    await shot(tester, '$out/8-types-sheet');
    await tester.tap(k('be-type-param-x'));
    await tester.pumpAndSettle();
    await tester.tap(k('be-type-list'));
    await tester.pumpAndSettle();
    await tester.tap(k('be-type-nullable'));
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(k('be-type-now')).data, '现在：列表〈任意〉?');
    await shot(tester, '$out/9-type-picker-list');
    await tester.tap(k('be-type-text'));
    await tester.pumpAndSettle();
    await tester.tap(k('be-type-nullable'));
    await tester.pumpAndSettle();
    await tester.tap(k('be-type-done'));
    await tester.pumpAndSettle();
    expect(find.descendant(of: k('be-type-param-x'), matching: find.text('文字')), findsOneWidget);
    expect(host.doc.function('f1')!.params.single.type, LType.text);
    // 参数改成文字以后：用它的地方跟着重新查。
    expect([for (final i in typeIssues(tester)) i.problem].where((p) => p.contains('「加倍」的第 1 个参数')), ['「加倍」的第 1 个参数要文字，放进来的是整数'], reason: '第 1 块放的文字现在对了，第 4 块放的整数现在不对了');
    await tester.tapAt(const Offset(40, 60));
    await tester.pumpAndSettle();
    // 合并以后类型错误也拦在“生成”那一层：存盘时提示一次“有 N 个错误，代码没有更新”。提示条带按钮、不会自己消失，会盖住积木盒的页签，先收掉。
    expect(find.descendant(of: find.byType(SnackBar), matching: find.textContaining('个错误，代码没有更新')), findsOneWidget);
    ScaffoldMessenger.of(tester.element(find.byType(SnackBar))).hideCurrentSnackBar();
    await tester.pumpAndSettle();

    // 积木盒“运算”页多了三块；菜单里说“已开启”，没有升级入口。
    await tester.drag(k('bk-palette-grip'), const Offset(0, -300), warnIfMissed: false);
    await tester.pumpAndSettle();
    await paletteTab(tester, '运算');
    final ops = host.categories.firstWhere((c) => c.id == '运算');
    expect([for (final g in ops.groups) ...g.exprs], containsAll(['parseInt', 'orElse', 'must']));
    for (final kind in ['parseInt', 'orElse', 'must']) {
      expect(host.newExpr(kind)['e'], kind);
    }
    await tester.tap(k('be-more'));
    await tester.pumpAndSettle();
    expect(k('be-menu-strict-on'), findsOneWidget);
    expect(k('be-menu-strict'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    final suffix = mode == ThemeMode.light ? 'light' : 'dark';
    testWidgets('老规矩：和以前一样（没有类型问题、没有类型一行、积木盒不多）；从菜单升级 → 清单 → 确认 → 标红；撤销回老规矩（$suffix）', (tester) async {
      // “升级到严格规矩…”的入口现在默认藏着（kStrictRulesUpgradeEnabled）；这里把它打开，升级那条路照旧测。
      beStrictUpgradeEntry = true;
      addTearDown(() => beStrictUpgradeEntry = kStrictRulesUpgradeEnabled);
      await open(tester, 1, mode: mode);
      final host = be(tester).host!;
      // —— 版本 1 钉子 ——
      final plain = validateBackend(host.doc, languages: [for (final t in backendTargets) t.id], table: host.funcTable);
      expect(
        [for (final i in host.issues) '${i.rule}|${i.message}|${i.isError}|${i.isHint}|${i.actions.length}'],
        [for (final i in plain) '${i.rule}|${i.message}|${i.isError}|false|0'],
        reason: '老规矩：问题和原来的校验逐条一样，没有修法按钮',
      );
      expect(host.typeCheck, isNull);
      expect(
        [
          for (final c in host.categories)
            for (final g in c.groups) ...g.exprs,
        ].where((e) => const ['parseInt', 'orElse', 'must'].contains(e)),
        isEmpty,
      );
      for (final sel in <BlockSelection>[
        BlockSelection('r1', [lcStep(0)]),
        const BlockSelection('f1', <LcBlockStep>[]),
      ]) {
        expect(host.typeLineOf(sel.scriptId, sel.path), isNull);
        expect(host.typeEditableAt(sel.scriptId, sel.path), isFalse);
        ed(tester).select(sel);
        await tester.pumpAndSettle();
        expect(k('bk-selection-bar'), findsOneWidget);
        expect(k('bk-type-line'), findsNothing);
        expect(k('bk-type-edit'), findsNothing);
      }
      ed(tester).select(null);
      await tester.pumpAndSettle();
      expect(saved().rules, 1);

      // —— 升级 ——
      await tester.tap(k('be-more'));
      await tester.pumpAndSettle();
      expect(k('be-menu-strict'), findsOneWidget);
      await shot(tester, '$out/10-menu-$suffix');
      await tester.tap(k('be-menu-strict'));
      await tester.pumpAndSettle();
      expect(k('be-strict-sheet'), findsOneWidget);
      expect(tester.widget<Text>(k('be-strict-preview')).data, contains('3 处标红要改'));
      await shot(tester, '$out/11-upgrade-$suffix');
      // 先不升：什么都没变。
      await tester.tap(k('be-strict-cancel'));
      await tester.pumpAndSettle();
      expect(host.doc.rules, 1);
      expect(host.canUndo, isFalse);
      await more(tester, 'strict');
      await tester.tap(k('be-strict-go'));
      await tester.pumpAndSettle();
      expect(host.doc.rules, 2);
      expect(typeIssues(tester).length, 3);
      // 有标红：问题列表直接打开。
      expect(find.text('变成文字'), findsOneWidget);
      await tester.tapAt(const Offset(40, 60));
      await tester.pumpAndSettle();
      await until(tester, () => saved().rules == 2, '升级后存盘');
      // 撤销：回到老规矩。
      host.undo();
      await tester.pumpAndSettle();
      expect(host.doc.rules, 1);
      expect(typeIssues(tester), isEmpty);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('默认：老规矩的文档“⋯”菜单里没有“升级到严格规矩…”（等后端接上严格生成再打开）；别的菜单项都在', (tester) async {
    expect(kStrictRulesUpgradeEnabled, isFalse);
    expect(beStrictUpgradeEntry, isFalse);
    await open(tester, 1);
    await tester.tap(k('be-more'));
    await tester.pumpAndSettle();
    expect(k('be-menu-strict'), findsNothing);
    expect(find.text('升级到严格规矩…'), findsNothing);
    expect(k('be-menu-strict-on'), findsNothing);
    for (final item in ['language', 'data', 'settings', 'regen']) {
      expect(k('be-menu-$item'), findsOneWidget, reason: item);
    }
    expect(be(tester).host!.doc.rules, 1);
    expect(tester.takeException(), isNull);
  });
}
