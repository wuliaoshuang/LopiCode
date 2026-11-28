// 自带的两个库“在画布上看（只读）”（积木第 5 版·第四轮·A3b 第 5 件）：一步步点进去——页面逻辑 › 更多 › 积木库… › 应用自带的库 ›
// 在画布上看（只读）；看得到说明、函数清单、没翻成积木的明细；画布只能看，文档一个字不变。考的是默认状态（两个开关都关着）。
// 十套主题各过一遍（冒烟）。
//   LOPI_SHOTS=1 flutter test --no-pub test/backend_lib_view_test.dart   # 截图写到 ../preview/front/a3b/
import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/appearance/theme_builtin.dart';
import 'package:lopicode/backend/lib_service_module.dart';
import 'package:lopicode/blocks/block_canvas_view.dart';
import 'package:lopicode/blocks/block_editor_view.dart';
import 'package:lopicode/core/safe_file.dart';
import 'package:lopicode/lang/lib_model.dart';
import 'package:lopicode/lang/rules.dart';
import 'package:lopicode/lowcode/lib_page_module.dart';
import 'package:lopicode/state/themes_state.dart';
import 'package:lopicode/ui/backend_lib_view_screen.dart';
import 'package:material_ui/material_ui.dart';

import 'support/front_ui.dart';
import 'support/harness.dart';
import 'support/lowcode_builder.dart';
import 'support/page_front_samples.dart';

void main() {
  setUpAll(() async => lbFontsLoaded = await loadRealFonts());

  testWidgets('页面逻辑 › 更多 › 积木库… › “页面”和“接口服务”都能在画布上看；只读', (tester) async {
    expect((kLibNativeCodeEnabled, kUserLibHostEnabled), (false, false), reason: '这条路考的是默认状态');
    await fuOpen(tester, frontPage([btn('b1', '问'), txt('t1')], [], frontDoc()));
    final before = fuHost(tester).doc.encode();

    // 1 更多 › 积木库… › 应用自带 › 页面 › 在画布上看（只读）
    await fuMore(tester, 'libs');
    await fuUntil(tester, () => fk('be-lib-new').evaluate().isNotEmpty, '积木库面板读完项目里的库');
    await fuTap(tester, 'be-lib-builtin-page');
    expect(fk('be-lib-builtin-page-sheet'), findsOneWidget);
    await fuShot(tester, 'view-1-page-sheet');
    await fuTap(tester, 'be-lib-builtin-page-view');
    expect(fk('be-lib-view'), findsOneWidget);
    expect(find.byType(BlockCanvasView), findsOneWidget);
    expect(find.byType(BlockEditorView).hitTestable(), findsNothing, reason: '只读的这一页没有编辑器、没有积木盒');
    expect(find.textContaining('只能看'), findsOneWidget);
    expect(find.textContaining('个函数'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await settle(tester, rounds: 8);
    await fuShot(tester, 'view-2-page-canvas');

    // 2 “函数”：列出所有函数，点一个画布挪过去并选中它
    await fuTap(tester, 'be-lib-view-pick');
    expect(fk('be-lib-view-fns'), findsOneWidget);
    await fuShot(tester, 'view-3-page-fns');
    await fuTap(tester, 'be-lib-view-fn-去页面');
    expect(fk('be-lib-view-fns'), findsNothing);
    final canvas = tester.state<BlockCanvasViewState>(find.byType(BlockCanvasView));
    expect(canvas.selection, isNotNull);
    await fuShot(tester, 'view-4-page-goto');

    // 3 点说明那一条：明细（换了哪些说法、哪几处没翻成积木）
    await fuTap(tester, 'be-lib-view-summary');
    expect(fk('be-lib-view-detail'), findsOneWidget);
    expect(find.textContaining('局部变量换了名字'), findsOneWidget);
    expect(find.textContaining('没有对应积木的地方（4 处）'), findsOneWidget);
    await fuShot(tester, 'view-5-page-detail');
    await fuCloseSheets(tester, 'be-lib-view-detail');

    // 4 返回；“接口服务”在页面逻辑里用不了，但一样能看
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(fk('be-lib-view'), findsNothing);
    await fuTap(tester, 'be-lib-builtin');
    expect(fk('be-lib-builtin-fork'), findsNothing, reason: '默认状态没有“复制一份来改”');
    await fuTap(tester, 'be-lib-builtin-view');
    expect(fk('be-lib-view'), findsOneWidget);
    expect(find.textContaining('处没有对应的积木'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await settle(tester, rounds: 8);
    await fuShot(tester, 'view-6-service-canvas');
    await fuTap(tester, 'be-lib-view-summary');
    await fuShot(tester, 'view-7-service-detail');
    await fuCloseSheets(tester, 'be-lib-view-detail');
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    // 5 看了一圈，页面逻辑这份文档一个字没变
    expect(fuHost(tester).doc.encode(), before);
  });

  group('十套主题冒烟：只读画布', () {
    for (final theme in kBuiltinThemes) {
      testWidgets('${theme.name}：“接口服务”在画布上看、明细面板', (tester) async {
        usePhoneViewport(tester);
        late TestEnv env;
        await tester.runAsync(() async {
          env = await TestEnv.create();
          expect(await env.services.container.read(themesProvider.notifier).select(theme.id), isNull);
        });
        addTearDown(() async {
          await pendingWrites();
          await env.dispose();
        });
        await tester.pumpWidget(
          appFor(
            env,
            const BeLibViewScreen(title: '接口服务', moduleText: kBeServiceModuleLc, side: LibSide.backend),
            mode: theme.dark ? ThemeMode.dark : ThemeMode.light,
            font: lbFontsLoaded ? kTestFont : null,
          ),
        );
        await settle(tester, rounds: 3);
        expect(find.byType(BlockCanvasView), findsOneWidget);
        expect(tester.takeException(), isNull, reason: '${theme.name} 渲染出了异常（溢出也算）');
        await fuShot(tester, 'view-theme-${theme.id}');
        await tester.tap(fk('be-lib-view-summary'));
        await tester.pumpAndSettle();
        expect(fk('be-lib-view-detail'), findsOneWidget);
        expect(tester.takeException(), isNull, reason: '${theme.name} 明细面板渲染出了异常');
        if (identical(theme, kBuiltinThemes.first)) expect(kLcPageModuleLc, isNotEmpty);
      });
    }
  });
}
