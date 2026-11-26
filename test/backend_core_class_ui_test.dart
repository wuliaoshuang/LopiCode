// 积木第 5 版·核心 2·A3：类与接口在后端积木页上（390×844）。
//   LOPI_SHOTS=1 flutter test --no-pub test/backend_core_class_ui_test.dart   # 截图写到 ../preview/core/a3/（不进 git）
//
// 子类：选父类 → “照抄上面的签名”一点就有了一样的方法（连默认值）→ 加“创建时”自动放好第一块“调父类的创建时”→
// 进它的画布，积木盒“类型”页多出“我自己”和“父类”一组，都拖得出来。接口：卡片上列方法签名，类勾上它以后同样能照抄。
import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/backend/backend_core.dart';
import 'package:lopicode/blocks/block_dock.dart';
import 'package:lopicode/lowcode/logic_model.dart';
import 'package:material_ui/material_ui.dart';

import 'backend_core_ui_test.dart' show open, out, tapK, typeName;
import 'backend_lang_ui_test.dart' show dropStatement, dropValue;
import 'backend_screen_test.dart' show be, doc, flushed, k, liftFromPalette, more, saved;
import 'screens_test.dart' show fontsLoaded, shot;
import 'support/backend_core_samples.dart';
import 'support/backend_func_blocks.dart' show pm, ret;
import 'support/backend_lang_blocks.dart' hide text;
import 'support/harness.dart' show loadRealFonts;

/// 一个可以被继承的类（“创建时”要一个参数、一个带默认值的方法）、一个接口（一个方法）。
J seed() => coreDoc(
  '类',
  types: [
    typeDef(
      't1',
      'class',
      '动物',
      open: true,
      fields: [field('名字', tText)],
      ctor: method('m1', kBeCtorName, [tpar('名字', tText)], [setF(me(), '名字', pm('名字'))]),
      methods: [
        method('m2', '叫', [tpar('次数', tInt, def: 3)], [ret(tx('…'))], returns: tText),
      ],
    ),
    typeDef(
      't2',
      'interface',
      '会跑',
      methods: [
        method('m3', '跑', [tpar('多远', tInt)], const [], returns: tText),
      ],
    ),
  ],
  main: [log(tx('开始'))],
);

void main() {
  setUpAll(() async => fontsLoaded = await loadRealFonts());
  tearDown(BkDockMemory.clear);

  for (final (mode, suffix) in [(ThemeMode.light, 'light'), (ThemeMode.dark, 'dark')]) {
    testWidgets('别的几种类型：自己的错误种类（继承内置种类、加字段）、枚举加情况、变体的情况带东西、新建接口加方法；类的字段设“内部”“类本身的”、方法设“类本身的”（$suffix）', (tester) async {
      await open(tester, mode: mode, seed: seed());
      final host = be(tester).host!;
      Future<void> done() async {
        await tester.tap(k('be-sheet-done').last);
        await tester.pumpAndSettle();
      }

      BeTypeDef last() => doc(tester).core.types.last;

      // 错误种类：父类选内置的“找不到”，加一个字段。
      await more(tester, 'types');
      await tapK(tester, 'be-core-add');
      await tapK(tester, 'be-core-add-error');
      await tapK(tester, 'be-core-name');
      await typeName(tester, '没货');
      await tapK(tester, 'be-core-parent');
      await tapK(tester, 'be-core-parent-找不到');
      await tapK(tester, 'be-core-add-field');
      expect((last().kind, last().name, last().parent, last().fields.length), (BeTypeKind.error, '没货', '找不到', 1));
      await shot(tester, '$out/7-error-kind-$suffix');
      await done();

      // 枚举：加情况、改名、删掉一种。
      await tapK(tester, 'be-core-add');
      await tapK(tester, 'be-core-add-enum');
      await tapK(tester, 'be-core-add-case');
      final first = last().cases.first.name;
      await tapK(tester, 'be-core-case-$first');
      await typeName(tester, '春');
      expect(last().cases.first.name, '春');
      final n = last().cases.length;
      await tapK(tester, 'be-core-case-remove-${last().cases.last.name}');
      expect(last().cases, hasLength(n - 1));
      await shot(tester, '$out/7-enum-$suffix');
      await done();

      // 变体：给一种情况加带的东西。
      await tapK(tester, 'be-core-add');
      await tapK(tester, 'be-core-add-variant');
      await tapK(tester, 'be-core-add-case');
      await tapK(tester, 'be-core-add-field-${last().cases.first.name}');
      expect(last().kind, BeTypeKind.variant);
      expect(last().cases.first.fields, hasLength(1));
      await shot(tester, '$out/7-variant-$suffix');
      await done();

      // 接口：加一个方法（只有签名）。
      await tapK(tester, 'be-core-add');
      await tapK(tester, 'be-core-add-interface');
      await tapK(tester, 'be-core-add-method');
      expect(last().kind, BeTypeKind.interface);
      expect(last().methods.single.body, isEmpty);
      await done();

      // 类“动物”：字段设成“内部”、再设成“类本身的”；方法设成“类本身的”。
      await tapK(tester, 'be-core-type-动物');
      await tapK(tester, 'be-core-field-more-名字');
      await tapK(tester, 'be-core-field-private-名字');
      await tapK(tester, 'be-core-add-field');
      final extra = doc(tester).core.typeNamed('动物')!.fields.last.name;
      await tapK(tester, 'be-core-field-more-$extra');
      await tapK(tester, 'be-core-field-static-$extra');
      await tapK(tester, 'be-core-method-叫');
      await tapK(tester, 'be-core-static');
      final animal = doc(tester).core.typeNamed('动物')!;
      expect((animal.fields.first.isPrivate, animal.fields.last.isStatic, animal.methods.single.isStatic), (true, true, true));
      await shot(tester, '$out/7-class-members-$suffix');
      await done();
      await done();
      await done();

      // 新建的种类、类型在积木的下拉里选得到：“出错时 只接”有“没货”。
      expect(host.core.errorKinds, contains('没货'));

      final after = doc(tester).encode();
      var steps = 0;
      while (host.canUndo) {
        host.undo();
        steps++;
      }
      await tester.pumpAndSettle();
      expect(doc(tester).core.types, hasLength(2));
      for (var i = 0; i < steps; i++) {
        host.redo();
      }
      await tester.pumpAndSettle();
      expect(doc(tester).encode(), after);
      await flushed(tester);
      expect(saved().core.typeNamed('没货')?.parent, '找不到');
    });

    testWidgets('子类和接口：选父类、照抄签名、自动放好“调父类的创建时”、类画布里拖“我自己”和“父类”一组；撤销重做（$suffix）', (tester) async {
      await open(tester, mode: mode, seed: seed());
      final host = be(tester).host!;
      expect(host.issues.where((i) => i.isError), isEmpty);

      // 接口的卡片：方法签名一行一个。
      await more(tester, 'types');
      await tapK(tester, 'be-core-type-会跑');
      expect(k('be-core-method-跑'), findsOneWidget);
      expect(find.textContaining('多远'), findsWidgets, reason: '签名写在行上');
      expect(k('be-core-add-field'), findsNothing, reason: '接口没有字段');
      expect(k('be-core-open-canvas'), findsNothing, reason: '接口没有画布（只有签名）');
      await shot(tester, '$out/6-interface-$suffix');
      await tester.tap(k('be-sheet-done').last);
      await tester.pumpAndSettle();

      // 新建一个类“狗”：父类选“动物”，勾上“会跑”。
      await tapK(tester, 'be-core-add');
      await tapK(tester, 'be-core-add-class');
      await tapK(tester, 'be-core-name');
      await typeName(tester, '狗');
      await tapK(tester, 'be-core-parent');
      await tapK(tester, 'be-core-parent-动物');
      await tapK(tester, 'be-core-iface-会跑');
      var dog = doc(tester).core.typeNamed('狗')!;
      expect(dog.parent, '动物');
      expect(dog.interfaces, ['会跑']);
      expect(host.issues.where((i) => i.isError).map((i) => i.rule), contains('T11'), reason: '说了自己会跑、还没有“跑”：标红');

      // “照抄上面的签名”：父类的“叫”、接口的“跑”各一行，点了就有一模一样的方法。
      expect(k('be-core-copy-叫'), findsOneWidget);
      expect(k('be-core-copy-跑'), findsOneWidget);
      await shot(tester, '$out/6-copy-$suffix');
      await tapK(tester, 'be-core-copy-叫');
      await tapK(tester, 'be-core-copy-跑');
      dog = doc(tester).core.typeNamed('狗')!;
      final bark = dog.methods.firstWhere((m) => m.name == '叫');
      expect((bark.params.single.name, bark.params.single.defaultValue, bark.returns?.show()), ('次数', 3, '文字'));
      final run = dog.methods.firstWhere((m) => m.name == '跑');
      expect((run.params.single.name, run.returns?.show()), ('多远', '文字'));
      expect(k('be-core-copy-叫'), findsNothing, reason: '抄过的不再列');
      expect(host.issues.where((i) => i.rule == 'T11' || i.rule == 'T18'), isEmpty, reason: '签名对上了');

      // 加“创建时”：父类的要参数，第一块“调父类的创建时”自动放好。
      await tapK(tester, 'be-core-add-ctor');
      dog = doc(tester).core.typeNamed('狗')!;
      expect(dog.ctor!.body.first.op, 'superInit');
      expect(host.issues.where((i) => i.rule == 'T27'), isEmpty);
      await shot(tester, '$out/6-subclass-$suffix');

      // 进它的画布：积木盒“类型”页有“我自己”和“父类”一组，都拖得出来。
      await tapK(tester, 'be-core-open-canvas');
      expect(host.canvasType?.name, '狗');
      for (final op in ['superInit', 'superCallStmt']) {
        final (g, from) = await liftFromPalette(tester, '类型', 'block-$op');
        await dropStatement(tester, g, from, bark.id, const [], 0);
        expect(doc(tester).core.typeNamed('狗')!.methods.first.body.first.op, op, reason: '$op 拖进来了');
        if (op == 'superInit') {
          host.undo();
          await tester.pumpAndSettle();
        }
      }
      {
        final (g, from) = await liftFromPalette(tester, '类型', 'block-setField');
        await dropStatement(tester, g, from, bark.id, const [], 0);
      }
      for (final (kind, slot) in [('this', 'of'), ('superCall', 'value')]) {
        final (g, from) = await liftFromPalette(tester, '类型', 'expr-$kind');
        await dropValue(tester, g, from, bark.id, [lcStep(0)], slot);
        await tester.pumpAndSettle();
      }
      final set = doc(tester).core.typeNamed('狗')!.methods.first.body.first;
      expect((set.op, (set.args['of'] as Map)['e'], (set.args['value'] as Map)['e']), ('setField', 'this', 'superCall'), reason: '“我自己”“父类的方法”都拖进来了');
      await shot(tester, '$out/6-subclass-canvas-$suffix');
      await tapK(tester, 'be-canvas-back');

      // 撤销到底再重做回来：文档一样；存盘的也是它。
      final after = doc(tester).encode();
      var steps = 0;
      while (host.canUndo) {
        host.undo();
        steps++;
      }
      await tester.pumpAndSettle();
      expect(doc(tester).core.typeNamed('狗'), isNull);
      for (var i = 0; i < steps; i++) {
        host.redo();
      }
      await tester.pumpAndSettle();
      expect(doc(tester).encode(), after);
      await flushed(tester);
      expect(saved().core.typeNamed('狗')?.parent, '动物');
    });
  }
}
