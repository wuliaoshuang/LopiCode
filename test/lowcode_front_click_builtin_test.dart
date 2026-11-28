// 页面逻辑页里一步步点出来的路（积木第 5 版·第四轮·A4）：应用自带的前端库。
// 搭建页“更多 › 积木逻辑”›“更多 › 积木库…”› 应用自带里的“本地保存”›“在这份文档里用它”› 在画布上看（只读）›
// 积木盒多出“本地保存”一页 › 拖它的积木 › 存盘 › 存盘的那一页导出成三种网页真编译真跑。两个安全开关都是默认的关着。
// 另：十套主题各把自带前端库的面板摆一遍（冒烟）。
//   LOPI_SHOTS=1 flutter test --no-pub test/lowcode_front_click_builtin_test.dart   # 截图写到 ../preview/front/a4/
@Tags(['needs-webdev'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/appearance/theme_builtin.dart';
import 'package:lopicode/blocks/block_canvas_view.dart';
import 'package:lopicode/blocks/block_look.dart';
import 'package:lopicode/lang/rules.dart';
import 'package:lopicode/lowcode/lib_front_builtin.dart';
import 'package:lopicode/lowcode/logic_model.dart';
import 'package:lopicode/state/themes_state.dart';
import 'package:material_ui/material_ui.dart';

import 'support/backend_lang_blocks.dart';
import 'support/front_libs_samples.dart';
import 'support/front_ui.dart';
import 'support/harness.dart';
import 'support/lowcode_builder.dart';
import 'support/page_front_samples.dart';

Future<void> _shot(WidgetTester tester, String name) => lbShot(tester, '../preview/front/a4', name);

void main() {
  setUpAll(() async => lbFontsLoaded = await loadRealFonts());

  testWidgets('积木库… › 本地保存 › 用它 › 只读地看 › 拖它的积木 › 存盘 › 三种网页真编译真跑', (tester) async {
    expect((kLibNativeCodeEnabled, kUserLibHostEnabled), (false, false), reason: '这条路考的是默认状态');
    final session = await fuOpen(tester, frontPage([btn('b1', '存'), txt('t1')], [], frontDoc()));
    final page = fuHost(tester);
    expect(page.categories.where((c) => c.id == 'lib:lopi/storage'), isEmpty, reason: '没用上以前积木盒里没有这一页');

    // 1 更多 › 积木库…：应用自带一栏里，“页面”后面是五个要用才用的库
    await fuMore(tester, 'libs');
    await fuUntil(tester, () => fk('be-lib-new').evaluate().isNotEmpty, '积木库面板读完项目里的库');
    for (final short in const ['timer', 'http', 'storage', 'store', 'bus']) {
      await fuSee(tester, 'be-lib-builtin-$short');
    }
    await _shot(tester, 'click-1-libs');

    // 2 点开“本地保存”：说明、公开的积木、开关
    await fuTap(tester, 'be-lib-builtin-storage');
    expect(fk('be-lib-front-storage-sheet'), findsOneWidget);
    expect(tester.widget<SwitchListTile>(fk('be-lib-use')).value, isFalse);
    await _shot(tester, 'click-2-storage-sheet');

    // 3 在画布上看（只读）
    await fuTap(tester, 'be-lib-front-view');
    expect(fk('be-lib-view'), findsOneWidget);
    expect(find.byType(BlockCanvasView), findsOneWidget);
    expect(tester.takeException(), isNull);
    await settle(tester, rounds: 8);
    await _shot(tester, 'click-3-storage-canvas');
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(fk('be-lib-view'), findsNothing);

    // 4 在这份文档里用它
    await fuTap(tester, 'be-lib-use');
    await fuUntil(tester, () => page.doc.use('lopi/storage') != null, '用上这个库');
    expect(tester.widget<SwitchListTile>(fk('be-lib-use')).value, isTrue);
    await _shot(tester, 'click-4-storage-on');
    await fuCloseSheets(tester, 'be-libs');
    final cat = page.categories.firstWhere((c) => c.id == 'lib:lopi/storage');
    expect(cat.label, '本地保存');
    final blocks = [...cat.blocks, for (final g in cat.groups) ...g.blocks];
    expect(blocks, contains('lib:lopi/storage#set'));

    // 5 点“存”：把〔草稿一〕存到本地，名字叫〔草稿〕；再把 t1 的文字改成〔存好了〕
    await fuDropHat(tester, 'lib:lopi/page:事件', 'hat-libhat:lib:lopi/page#onClick', const Offset(40, 40));
    final h1 = page.doc.hats.last.id;
    await fuShow(tester, h1);
    await fuPick(tester, fuHatSlot(tester, h1, 'node'), 'b1');
    await fuDropStmt(tester, 'lib:lopi/storage', 'block-lib:lopi/storage#set', h1, const [], 0);
    await _shot(tester, 'click-5-dropped');
    await fuInline(tester, fuArg(tester, h1, [lcStep(0)], 'value'), '草稿一');
    await fuInline(tester, fuArg(tester, h1, [lcStep(0)], 'key'), '草稿');
    await fuDropStmt(tester, 'lib:lopi/page:控件', 'block-lib:lopi/page#propSet', h1, const [], 1);
    await fuPick(tester, fuArg(tester, h1, [lcStep(1)], 'node'), 't1');
    await fuPick(tester, fuArg(tester, h1, [lcStep(1)], 'prop'), 'text');
    await fuInline(tester, fuArg(tester, h1, [lcStep(1)], 'value'), '存好了');
    expect(fuErrors(tester), isEmpty);
    await _shot(tester, 'click-6-canvas');

    // 6 存盘 → 导出成三种网页真编译真跑：点“存”以后浏览器的本地存储里真有这一项
    final saved = await fuSavedAndRun(tester, session, [click('b1'), textIs('t1', '存好了'), storedUntil('草稿', '"草稿一"')]);
    expect(saved.logic.uses.map((u) => u['id']), contains('lopi/storage'), reason: '用上的自带库记在页面文件里');
  });

  testWidgets('匿名函数的参数小卡：标类型、不标；标了的写在小块上、存进文档', (tester) async {
    await fuOpen(
      tester,
      frontPage(
        [btn('b1', '算'), txt('t1')],
        [],
        frontDoc(
          hats: [
            onClick('h1', 'b1', [
              let(
                'f',
                ex('lambdaExpr', {
                  'params': ['x'],
                  'body': op2('*', ex('param', {'name': 'x'}), nm(2)),
                }),
              ),
            ]),
          ],
        ),
      ),
    );
    await fuShow(tester, 'h1');
    final owner = [lcStep(0)];
    Map<String, dynamic> fn() => fuHost(tester).doc.hat('h1')!.body.first.args['value'] as Map<String, dynamic>;
    expect(fn()[kExprParamTypes], isNull);

    // 点参数小块 → 小卡里多一行“类型” → 挑“整数”
    await tester.tapAt(fuChip(tester, 'h1', 0, owner: owner));
    await tester.pumpAndSettle();
    expect(fk('bk-param-card'), findsOneWidget);
    expect(fk('bk-param-type'), findsOneWidget);
    await _shot(tester, 'param-1-card');
    await tester.tap(fk('bk-param-type'));
    await tester.pumpAndSettle();
    expect(fk('bk-param-types'), findsOneWidget);
    await _shot(tester, 'param-2-types');
    await tester.tap(fk('bk-param-type-整数'));
    await tester.pumpAndSettle();
    await tester.tap(fk('bk-param-ok'));
    await tester.pumpAndSettle();
    expect(fn()[kExprParamTypes], ['整数']);
    expect(find.textContaining('x：整数'), findsWidgets, reason: '小块上写着类型');
    expect(fuErrors(tester), isEmpty);
    await _shot(tester, 'param-3-typed');

    // 再点开 → 不标：文档里那张表整个没了
    await tester.tapAt(fuChip(tester, 'h1', 0, owner: owner));
    await tester.pumpAndSettle();
    await tester.tap(fk('bk-param-type'));
    await tester.pumpAndSettle();
    await tester.tap(fk('bk-param-type-none'));
    await tester.pumpAndSettle();
    await tester.tap(fk('bk-param-ok'));
    await tester.pumpAndSettle();
    expect(fn()[kExprParamTypes], isNull);
    expect(tester.takeException(), isNull);
  });

  group('十套主题冒烟：自带前端库的面板', () {
    for (final (i, theme) in kBuiltinThemes.indexed) {
      testWidgets('${theme.name}：积木库面板、自带前端库的面板（开着、关着）', (tester) async {
        final lib = kLcFrontBuiltins[i % kLcFrontBuiltins.length];
        final short = lib.id.split('/').last;
        await fuOpen(
          tester,
          frontPage([btn('b1', '存'), txt('t1')], [], frontDoc()),
          mode: theme.dark ? ThemeMode.dark : ThemeMode.light,
          before: (session) async => expect(await session.app.container.read(themesProvider.notifier).select(theme.id), isNull),
        );
        await fuMore(tester, 'libs');
        await fuUntil(tester, () => fk('be-lib-new').evaluate().isNotEmpty, '积木库面板读完项目里的库');
        expect(tester.takeException(), isNull, reason: '${theme.name} 积木库面板渲染出了异常（溢出也算）');
        await fuTap(tester, 'be-lib-builtin-$short');
        expect(fk('be-lib-front-$short-sheet'), findsOneWidget);
        expect(tester.takeException(), isNull, reason: '${theme.name} 面板（关着）渲染出了异常');
        await fuTap(tester, 'be-lib-use');
        await fuUntil(tester, () => fuHost(tester).doc.use(lib.id) != null, '用上这个库');
        expect(tester.takeException(), isNull, reason: '${theme.name} 面板（开着）渲染出了异常');
        await _shot(tester, 'theme-${theme.id}-$short');
      });
    }
  });
}
