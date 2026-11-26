// 积木第 5 版·核心 2·A3：新积木、类型与类、模块、一键修在后端积木页上的样子（390×844，浅色 + 深色）。
//   LOPI_SHOTS=1 flutter test --no-pub test/backend_core_ui_test.dart   # 截图写到 ../preview/core/a3/（不进 git）
//
// 整个应用外壳真的搭起来：严格规矩的文档 → 积木盒多出“错误”“类型”两页，每块都拖得出来 →
// “试着做”加一节、调顺序 → “类型与类”里建记录 / 类、加字段、改名、进类的画布再回来 → “模块”里建模块、勾公开 →
// 标红的积木点小卡里的修法就好 → 这些都能撤销、重做。老规矩的文档菜单和积木盒一项不多。
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/backend/backend_core.dart';
import 'package:lopicode/backend/backend_model.dart';
import 'package:lopicode/blocks/block_dock.dart';
import 'package:lopicode/blocks/block_geometry.dart';
import 'package:lopicode/core/templates.dart';
import 'package:lopicode/lowcode/logic_model.dart';
import 'package:material_ui/material_ui.dart';

import 'backend_lang_ui_test.dart' show control, dropStatement, dropValue;
import 'backend_screen_test.dart' show at, be, boot, doc, ed, flushed, k, liftFromPalette, more, paletteTab, saved, text;
import 'backend_type_ui_test.dart' show badge;
import 'screens_test.dart' show fontsLoaded, shot;
import 'support/backend_core_samples.dart';
import 'support/backend_lang_blocks.dart' hide text;
import 'support/harness.dart' show loadRealFonts;

const String out = '../../../preview/core/a3';

final J _point = typeDef('t1', 'record', '点', fields: [field('x', tInt), field('y', tInt)]);
final J _color = typeDef('t2', 'enum', '颜色', cases: [kase('红'), kase('绿'), kase('蓝')]);

/// 一份严格规矩的文档：一个记录、一个枚举、“程序开始时”里几块积木（其中一块“看是哪种情况”没列全、一处新建记录少字段）。
J seedDoc() => coreDoc(
  '核心2',
  types: [_point, _color],
  main: [
    log(tx('开始')),
    tryB(
      [thro(tx('坏了'))],
      [
        catchArm('@any', 'e', [log(getF(vr('e'), '消息'))]),
      ],
    ),
    match(ex('enumVal', {'type': '颜色', 'case': '红'}), [
      caseArm('红', '', [log(tx('红'))]),
    ]),
    let(
      'p',
      ex('recNew', {
        'type': '点',
        'fields': [pair('x', nm(1))],
      }),
    ),
    log(getF(vr('p'), 'x')),
  ],
);

Future<void> open(WidgetTester tester, {ThemeMode mode = ThemeMode.light, J? seed}) async {
  await boot(
    tester,
    ProjectTemplate.backendBlocks,
    language: 'node',
    mode: mode,
    before: () {
      final was = jsonDecode(text(kBackendFileName)) as Map<String, dynamic>;
      at(kBackendFileName).writeAsStringSync(jsonEncode({...(seed ?? seedDoc()), 'name': was['name'], 'port': was['port']}));
    },
  );
  ed(tester).jumpTo(kBeMainId, const []);
  await tester.pumpAndSettle();
  ed(tester).select(null);
  await tester.pumpAndSettle();
}

Future<void> lower(WidgetTester tester) async {
  await tester.drag(k('bk-palette-grip'), const Offset(0, 300), warnIfMissed: false);
  await tester.pumpAndSettle();
}

Future<void> typeName(WidgetTester tester, String value) async {
  await tester.enterText(find.byType(TextField).last, value);
  await tester.tap(find.text('确定'));
  await tester.pumpAndSettle();
}

Future<void> tapK(WidgetTester tester, String key) async {
  await tester.ensureVisible(k(key));
  await tester.pumpAndSettle();
  await tester.tap(k(key));
  await tester.pumpAndSettle();
}

List<LcBlock> mainBody(WidgetTester tester) => doc(tester).core.main!.body;
List<String> reds(WidgetTester tester) => [
  for (final i in be(tester).host!.issues)
    if (i.isError) i.problem,
];

void main() {
  setUpAll(() async => fontsLoaded = await loadRealFonts());
  tearDown(BkDockMemory.clear);

  testWidgets('积木盒：严格规矩的文档多出“错误”“类型”两页，每一块语句和值都拖得出来', (tester) async {
    await open(tester);
    await paletteTab(tester, '错误');
    await shot(tester, '$out/1-palette-error-light');
    await paletteTab(tester, '类型');
    await shot(tester, '$out/1-palette-type-light');

    // 语句：一块块拖到“程序开始时”的最前面。
    for (final (page, op) in [('错误', 'try'), ('错误', 'throw'), ('类型', 'match'), ('类型', 'setField'), ('类型', 'callMethodStmt')]) {
      final (g, from) = await liftFromPalette(tester, page, 'block-$op');
      await dropStatement(tester, g, from, kBeMainId, const [], 0);
      expect(mainBody(tester).first.op, op, reason: '$op 拖进来了');
      be(tester).host!.undo();
      await tester.pumpAndSettle();
      expect(mainBody(tester).first.op, 'log', reason: '撤销回去');
    }
    // 值：一个个拖进第一块“打印”的槽里。
    for (final (page, kind) in [
      ('错误', 'errNew'),
      ('类型', 'recNew'),
      ('类型', 'getField'),
      ('类型', 'recCopy'),
      ('类型', 'enumVal'),
      ('类型', 'varNew'),
      ('类型', 'classNew'),
      ('类型', 'callMethod'),
      ('类型', 'isA'),
      ('类型', 'classRef'),
    ]) {
      final (g, from) = await liftFromPalette(tester, page, 'expr-$kind');
      await dropValue(tester, g, from, kBeMainId, [lcStep(0)], 'value');
      expect((mainBody(tester).first.args['value'] as Map)['e'], kind, reason: '$kind 拖进来了');
      be(tester).host!.undo();
      await tester.pumpAndSettle();
    }
    expect((mainBody(tester).first.args['value'] as Map)['e'], 'text');
    // 新建记录拖出来就按第一个记录类型摆好了字段槽。
    final (g, from) = await liftFromPalette(tester, '类型', 'expr-recNew');
    await dropValue(tester, g, from, kBeMainId, [lcStep(0)], 'value');
    final made = mainBody(tester).first.args['value'] as Map;
    expect(made['type'], '点');
    expect([for (final p in made['fields'] as List) (p as Map)['key']], ['x', 'y']);
  });

  testWidgets('“试着做”：加一节“出错时”、加上“最后”、把一节往上挪、删掉；都能撤销重做', (tester) async {
    await open(tester);
    await lower(tester);
    final host = be(tester).host!;
    LcBlock tryBlock() => mainBody(tester)[1];
    expect(tryBlock().arms, hasLength(1));

    await tester.tapAt(control(tester, kBeMainId, [lcStep(1)], BkControlKind.add));
    await tester.pumpAndSettle();
    await tester.tap(k('bk-arm-menu-arm'));
    await tester.pumpAndSettle();
    expect([for (final a in tryBlock().arms) a.args['kind']], ['@any', '@any']);
    tryBlock(); // 第二节换成“找不到”（走宿主的写法，和下拉菜单选的是同一条路）
    host.edit(() => tryBlock().arms[1].args['kind'] = '找不到');
    await tester.pumpAndSettle();
    expect(reds(tester).any((m) => m.contains('轮不到')), isTrue, reason: '“任何错误”排在前面，后面那一节轮不到：${reds(tester)}');
    await shot(tester, '$out/2-try-unreachable-light');

    // 点第二节的“−”：分先后的积木先出小菜单，选“往上挪”。
    await tester.tapAt(control(tester, kBeMainId, [lcStep(1)], BkControlKind.removeArm, arm: 1));
    await tester.pumpAndSettle();
    await shot(tester, '$out/2-try-arm-menu-light');
    await tester.tap(k('bk-arm-menu-up'));
    await tester.pumpAndSettle();
    expect([for (final a in tryBlock().arms) a.args['kind']], ['找不到', '@any']);
    expect(reds(tester).any((m) => m.contains('轮不到')), isFalse);
    host.undo();
    await tester.pumpAndSettle();
    expect([for (final a in tryBlock().arms) a.args['kind']], ['@any', '找不到']);
    host.redo();
    await tester.pumpAndSettle();
    expect([for (final a in tryBlock().arms) a.args['kind']], ['找不到', '@any']);

    // 加上“最后”。
    expect(tryBlock().noElse, isTrue);
    await tester.tapAt(control(tester, kBeMainId, [lcStep(1)], BkControlKind.add));
    await tester.pumpAndSettle();
    await tester.tap(k('bk-arm-menu-tail'));
    await tester.pumpAndSettle();
    expect(tryBlock().noElse, isFalse);
    await shot(tester, '$out/2-try-full-light');

    // 删掉第二节。
    await tester.tapAt(control(tester, kBeMainId, [lcStep(1)], BkControlKind.removeArm, arm: 1));
    await tester.pumpAndSettle();
    await tester.tap(k('bk-arm-menu-remove'));
    await tester.pumpAndSettle();
    if (find.text('删除').evaluate().isNotEmpty) {
      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();
    }
    expect([for (final a in tryBlock().arms) a.args['kind']], ['找不到']);
    await flushed(tester);
    expect(saved().core.main!.body[1].arms.single.args['kind'], '找不到', reason: '存盘了');
  });

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    final suffix = mode == ThemeMode.light ? 'light' : 'dark';
    testWidgets('类型与类：建记录、加字段、改名、选类型；建类、进它的画布再回来；撤销重做（$suffix）', (tester) async {
      await open(tester, mode: mode);
      await lower(tester);
      final host = be(tester).host!;
      await more(tester, 'types');
      expect(k('be-core-types'), findsOneWidget);
      expect(k('be-core-type-点'), findsOneWidget);
      await shot(tester, '$out/3-types-$suffix');

      // 新建一个记录：直接进它的面板。
      await tapK(tester, 'be-core-add');
      await shot(tester, '$out/3-kinds-$suffix');
      await tapK(tester, 'be-core-add-record');
      expect(k('be-core-type-sheet'), findsOneWidget);
      final made = doc(tester).core.types.last;
      expect(made.kind, BeTypeKind.record);
      await tapK(tester, 'be-core-name');
      await typeName(tester, '订单');
      expect(doc(tester).core.types.last.name, '订单');
      await tapK(tester, 'be-core-add-field');
      await tapK(tester, 'be-core-add-field');
      final f = doc(tester).core.types.last.fields.last.name;
      await tapK(tester, 'be-core-field-$f');
      await typeName(tester, '数量');
      await tapK(tester, 'be-core-field-type-数量');
      await tapK(tester, 'be-type-integer');
      await tapK(tester, 'be-type-done');
      expect(doc(tester).core.typeNamed('订单')!.fields.last.type.show(), '整数');
      // 字段的类型能选自己定义的。
      final g = doc(tester).core.typeNamed('订单')!.fields.first.name;
      await tapK(tester, 'be-core-field-type-$g');
      await tapK(tester, 'be-type-ref-点');
      await tapK(tester, 'be-type-done');
      expect(doc(tester).core.typeNamed('订单')!.fields.first.type.name, '点');
      // 重名：改不了，面板顶上说为什么。
      await tapK(tester, 'be-core-name');
      await typeName(tester, '点');
      expect(k('be-sheet-problem'), findsOneWidget);
      expect(doc(tester).core.typeNamed('订单'), isNotNull);
      await shot(tester, '$out/3-record-$suffix');
      await tester.tap(k('be-sheet-done').last);
      await tester.pumpAndSettle();

      // 新建一个类：加字段、加“创建时”、加方法，打开它的画布。
      await tapK(tester, 'be-core-add');
      await tapK(tester, 'be-core-add-class');
      await tapK(tester, 'be-core-name');
      await typeName(tester, '动物');
      await tapK(tester, 'be-core-add-field');
      await tapK(tester, 'be-core-add-ctor');
      await tapK(tester, 'be-core-add-method');
      await tapK(tester, 'be-core-open');
      final animal = doc(tester).core.typeNamed('动物')!;
      expect(animal.ctor, isNotNull);
      expect(animal.methods, hasLength(1));
      expect(animal.isOpen, isTrue);
      // 方法的面板：加参数、标类型、默认值、交回什么。
      await tapK(tester, 'be-core-method-${animal.methods.single.name}');
      expect(k('be-core-method-sheet'), findsOneWidget);
      await tapK(tester, 'be-core-method-name');
      await typeName(tester, '叫');
      await tapK(tester, 'be-core-add-param');
      await tapK(tester, 'be-core-param-more-p1');
      await tapK(tester, 'be-core-param-default-p1');
      await typeName(tester, '3');
      await tapK(tester, 'be-core-returns');
      await tapK(tester, 'be-type-text');
      await tapK(tester, 'be-type-done');
      final m = doc(tester).core.typeNamed('动物')!.methods.single;
      expect((m.name, m.params.single.name, m.params.single.defaultValue, m.returns?.show()), ('叫', 'p1', 3, '文字'));
      await shot(tester, '$out/3-method-$suffix');
      await tester.tap(k('be-sheet-done').last);
      await tester.pumpAndSettle();
      await shot(tester, '$out/3-class-$suffix');
      await tapK(tester, 'be-core-open-canvas');
      expect(k('be-core-types'), findsNothing, reason: '面板都关了');
      expect(host.canvasType?.name, '动物');
      expect(k('be-canvas-back'), findsOneWidget);
      expect([for (final s in host.scripts) s.id], [animal.ctor!.id, animal.methods.single.id], reason: '画布上只有这个类的“创建时”和方法');
      await shot(tester, '$out/3-class-canvas-$suffix');
      // 类的画布里，“事件”页换成这个类能放的帽子。
      await tester.drag(k('bk-palette-grip'), const Offset(0, -300), warnIfMissed: false);
      await tester.pumpAndSettle();
      await paletteTab(tester, '类型');
      expect(k('bk-palette-item-expr-this'), findsOneWidget, reason: '类里面才有“我自己”');
      await shot(tester, '$out/3-class-palette-$suffix');
      await tester.tap(k('be-canvas-back'));
      await tester.pumpAndSettle();
      expect(host.canvasType, isNull);
      expect(k('be-canvas-back'), findsNothing);
      expect(host.scripts.any((s) => s.id == kBeMainId), isTrue);

      // 撤销到底再重做回来：文档一样。
      final after = doc(tester).encode();
      var steps = 0;
      while (host.canUndo) {
        host.undo();
        steps++;
      }
      await tester.pumpAndSettle();
      expect(doc(tester).core.types, hasLength(2), reason: '回到最开始的两个类型');
      for (var i = 0; i < steps; i++) {
        host.redo();
      }
      await tester.pumpAndSettle();
      expect(doc(tester).encode(), after);
      await flushed(tester);
      expect(saved().core.typeNamed('动物')?.methods.single.name, '叫');
    });

    testWidgets('模块：新建、改名、勾“用到了谁”、设公开、挪东西、设入口；模块顶上的变量带初值（$suffix）', (tester) async {
      await open(tester, mode: mode);
      await lower(tester);
      final host = be(tester).host!;
      await more(tester, 'modules');
      expect(k('be-modules'), findsOneWidget);
      await shot(tester, '$out/4-modules-empty-$suffix');
      await tapK(tester, 'be-module-add');
      await tapK(tester, 'be-module-add');
      final names = [for (final m in doc(tester).core.modules) m.name];
      expect(names, hasLength(2));
      expect(doc(tester).core.entryModule!.name, names.first, reason: '第一个建的是入口，原有的东西都归它');
      // 模块顶上的变量。
      await tapK(tester, 'be-global-add');
      final g = doc(tester).core.globals.single.name;
      await tapK(tester, 'be-global-more-$g');
      await tapK(tester, 'be-global-init-$g');
      await typeName(tester, '7');
      expect(doc(tester).core.globals.single.init, {'e': 'num', 'v': 7});
      await tapK(tester, 'be-global-$g');
      await typeName(tester, 'count');
      expect(doc(tester).core.globals.single.name, 'count');
      await shot(tester, '$out/4-modules-$suffix');

      // 第二个模块：改名、勾用到了第一个、设成入口。
      await tapK(tester, 'be-module-${names[1]}');
      expect(k('be-module-sheet'), findsOneWidget);
      await tapK(tester, 'be-module-name');
      await typeName(tester, '工具');
      expect(doc(tester).core.module('工具'), isNotNull);
      await tapK(tester, 'be-module-uses-${names[0]}');
      expect(doc(tester).core.module('工具')!.uses, [names[0]]);
      await tapK(tester, 'be-module-entry');
      expect(doc(tester).core.entryModule!.name, '工具');
      await tester.tap(k('be-sheet-done').last);
      await tester.pumpAndSettle();

      // 第一个模块：把“点”设成公开，把“颜色”挪到“工具”。
      await tapK(tester, 'be-module-${names[0]}');
      await tapK(tester, 'be-module-public-点');
      expect(doc(tester).core.publics, contains('t1'));
      await shot(tester, '$out/4-module-$suffix');
      await tapK(tester, 'be-module-move-颜色');
      await tapK(tester, 'be-module-move-颜色-工具');
      expect(doc(tester).core.module('工具')!.owns, contains('t2'));
      await tester.tap(k('be-sheet-done').last);
      await tester.pumpAndSettle();
      await tester.tap(k('be-sheet-done').last);
      await tester.pumpAndSettle();

      final after = doc(tester).encode();
      var steps = 0;
      while (host.canUndo) {
        host.undo();
        steps++;
      }
      expect(doc(tester).core.modules, isEmpty);
      expect(doc(tester).core.globals, isEmpty);
      for (var i = 0; i < steps; i++) {
        host.redo();
      }
      expect(doc(tester).encode(), after);
      await tester.pumpAndSettle();
      await flushed(tester);
      expect(saved().core.module('工具')?.uses, [names[0]]);
    });

    testWidgets('一键修：标红的“看是哪种情况”和“新建记录”，点小卡里的修法就好；撤销回来（$suffix）', (tester) async {
      await open(tester, mode: mode);
      await lower(tester);
      final host = be(tester).host!;
      expect(reds(tester), hasLength(2), reason: '${reds(tester)}');
      await shot(tester, '$out/5-marks-$suffix');

      await tester.tapAt(badge(tester, kBeMainId, [lcStep(2)]));
      await tester.pumpAndSettle();
      final card = k('bk-issue-card');
      expect(card, findsOneWidget);
      await shot(tester, '$out/5-card-match-$suffix');
      await tester.tap(k('bk-issue-fix-0'));
      await tester.pumpAndSettle();
      expect(card, findsNothing);
      expect([for (final a in mainBody(tester)[2].arms) a.args['case']], ['红', '绿', '蓝']);
      expect(reds(tester), hasLength(1));

      ed(tester).jumpTo(kBeMainId, [lcStep(3)]); // 上一块长高了，这块被挤到下面去了：先挪到看得见的地方
      await tester.pumpAndSettle();
      ed(tester).select(null);
      await tester.pumpAndSettle();
      await tester.tapAt(badge(tester, kBeMainId, [lcStep(3)]));
      await tester.pumpAndSettle();
      expect(card, findsOneWidget);
      await shot(tester, '$out/5-card-record-$suffix');
      await tester.tap(k('bk-issue-fix-0'));
      await tester.pumpAndSettle();
      expect(reds(tester), isEmpty);
      await shot(tester, '$out/5-fixed-$suffix');

      host.undo();
      host.undo();
      await tester.pumpAndSettle();
      expect(reds(tester), hasLength(2));
      host.redo();
      host.redo();
      await tester.pumpAndSettle();
      expect(reds(tester), isEmpty);
    });
  }

  testWidgets('看代码：只用语言核心积木的严格文档，五种语言都出得来代码', (tester) async {
    await open(tester, seed: coreSamples[2].doc);
    await lower(tester);
    final host = be(tester).host!;
    expect(reds(tester), isEmpty);
    for (final language in ['node', 'python', 'php', 'go', 'java']) {
      host.edit(() => host.doc.language = language);
      await tester.pumpAndSettle();
      expect(host.codeText, contains('点'), reason: '$language 出了代码');
      expect(host.codeText.split('\n').length, greaterThan(10), reason: '$language 不是一行说明');
      expect(host.codeFileName, isNotEmpty);
    }
    host.edit(() => host.doc.language = 'python');
    await tester.pumpAndSettle();
    await tester.tap(k('bk-code'));
    await tester.pumpAndSettle();
    await shot(tester, '$out/6-code-light');
  });

  testWidgets('老规矩的文档：菜单里没有“类型与类”“模块”，积木盒没有“错误”“类型”两页', (tester) async {
    await boot(tester, ProjectTemplate.backendBlocks, language: 'node');
    await tester.tap(k('be-more'));
    await tester.pumpAndSettle();
    expect(k('be-menu-types'), findsNothing);
    expect(k('be-menu-modules'), findsNothing);
    await tester.tapAt(const Offset(10, 400));
    await tester.pumpAndSettle();
    expect(k('bk-palette-tab-错误'), findsNothing);
    expect(k('bk-palette-tab-类型'), findsNothing);
    expect([for (final c in be(tester).host!.categories) c.id], isNot(contains('错误')));
  });
}
