// 三条线合并后的接线（积木第 4 版 × 代码高亮与缩放 × Agent 补强）：
// - 带函数的后端积木“看代码”：五种语言都按入口文件名上色；
// - 改动对比、步骤详情、完整输出跟着“代码字号”走、小一号（默认 14 → 12），在步骤详情里双指捏合能调。
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/agent/line_diff.dart';
import 'package:lopicode/backend/backend_block_host.dart';
import 'package:lopicode/backend/backend_model.dart';
import 'package:lopicode/backend/backend_targets.dart';
import 'package:lopicode/blocks/block_host.dart';
import 'package:lopicode/blocks/block_panels_sheet.dart';
import 'package:lopicode/core/stores.dart';
import 'package:lopicode/lowcode/code_sheet.dart';
import 'package:lopicode/session/chat_models.dart';
import 'package:lopicode/state/code_font.dart';
import 'package:lopicode/ui/chat_extras.dart';
import 'package:lopicode/ui/code_highlight.dart';
import 'package:lopicode/ui/code_view.dart';
import 'package:lopicode/ui/step_detail.dart';
import 'package:material_ui/material_ui.dart';

import 'code_zoom_test.dart' show colorsOf;
import 'support/backend_func_blocks.dart';
import 'support/backend_lang_blocks.dart';
import 'support/harness.dart';

BeDocument funcDoc() => parseLangBlocksDocument({
  ...langBlocksDocumentJson([
    route('r1', 'GET', '/x', [
      callS('f1', {'x': nm(1)}),
      json(nm(1)),
    ]),
  ]),
  'functions': [
    fnDef('f1', '加倍', [par('x')], [ret(op2('*', pm('x'), nm(2)))]),
  ],
});

final FileChange kChange = diffFileChange('lib/a.dart', kind: ChangeKind.modified, before: 'int a = 1;\nint b = 2;\nint c = 3;\n', after: 'int a = 1;\nint b = 20;\nint c = 3;\nint d = 4;\n').slim;

final ToolItem kEditStep = ToolItem('c1', 'edit_file', jsonEncode({'path': 'lib/a.dart', 'old_text': 'int b = 2;', 'new_text': 'int b = 20;'}), result: '已修改 lib/a.dart：替换了 1 处。', change: kChange);

void main() {
  Future<TestEnv> boot(WidgetTester tester, Widget home) async {
    usePhoneViewport(tester);
    late TestEnv env;
    await tester.runAsync(() async => env = await TestEnv.create());
    addTearDown(() => tester.runAsync(env.dispose));
    await tester.pumpWidget(appFor(env, home));
    await settle(tester, rounds: 2);
    return env;
  }

  test('小一号的代码字：比代码字号小 2，不小于最小字号', () {
    expect(compactCodeFont(kCodeFontDefault), 12, reason: '默认和原来写死的 12 号一样');
    expect(compactCodeFont(kCodeFontMax), 22);
    expect(compactCodeFont(kCodeFontMin), kCodeFontMin);
    expect(compactCodeFont(11), kCodeFontMin);
  });

  testWidgets('带函数的后端积木“看代码”：五种语言都按入口文件名上色，字号是代码字号', (tester) async {
    late BlockHost host;
    await boot(
      tester,
      Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: TextButton(onPressed: () => showBlockCode(context, host), child: const Text('开')),
          ),
        ),
      ),
    );
    for (final t in backendTargets) {
      final be = BeBlockHost(doc: funcDoc()..language = t.id);
      expect(be.doc.functions, hasLength(1));
      expect(be.codeFileName, t.entryFile, reason: t.id);
      host = be;
      await tester.tap(find.text('开'));
      await tester.pumpAndSettle();
      final sheet = tester.widget<CodeSheetBody>(find.byType(CodeSheetBody));
      expect(sheet.language, CodeHighlighter.languageFor(t.entryFile), reason: t.id);
      expect(sheet.language, isNot('text'), reason: t.id);
      expect(sheet.code, be.codeText);
      final text = tester.widget<SelectableText>(find.byKey(const Key('code-view-text')));
      expect(colorsOf(text.textSpan!).length, greaterThanOrEqualTo(3), reason: '${t.id}：带函数的代码要上色');
      expect(text.style?.fontSize, kCodeFontDefault);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('步骤详情和里面的改动对比：默认 12 号，跟着代码字号变；在详情里双指捏合能调并存下来', (tester) async {
    final env = await boot(
      tester,
      Scaffold(
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [StepDetail(tool: kEditStep)],
          ),
        ),
      ),
    );
    double diffSize() => tester.widget<Text>(find.descendant(of: find.byKey(const ValueKey('diff-rows')), matching: find.text('int b = 20;'))).style!.fontSize!;
    double detailSize() => tester.widget<SelectableText>(find.descendant(of: find.byType(StepDetail), matching: find.byType(SelectableText)).first).style!.fontSize!;
    expect(diffSize(), 12);
    expect(detailSize(), 12);

    env.services.container.read(codeFontProvider.notifier).set(18);
    await tester.pump();
    expect(diffSize(), 16);
    expect(detailSize(), 16);

    // 双指捏合：100 → 150，18 × 1.5 = 27，夹到最大 24。
    final center = tester.getCenter(find.byKey(const ValueKey('step-detail-scroll')));
    final a = await tester.startGesture(center - const Offset(50, 0), pointer: 41);
    final b = await tester.startGesture(center + const Offset(50, 0), pointer: 42);
    await tester.pump();
    for (var i = 1; i <= 5; i++) {
      await a.moveTo(center - Offset(50 + 5.0 * i, 0));
      await b.moveTo(center + Offset(50 + 5.0 * i, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(find.byKey(const Key('code-zoom-badge')), findsOneWidget, reason: '只有一层 CodeZoom，不会出两个数字');
    await a.up();
    await b.up();
    await tester.pump();
    expect(env.services.container.read(codeFontProvider), kCodeFontMax);
    expect(diffSize(), compactCodeFont(kCodeFontMax));
    await settle(tester, rounds: 1);
    expect(env.services.settings.get<num>(SettingKeys.codeFontSize), kCodeFontMax);
    expect(tester.takeException(), isNull);
  });

  testWidgets('完整输出页：默认 12 号，跟着代码字号变，包着一层捏合缩放', (tester) async {
    final env = await boot(tester, CommandOutputPage(path: '.lopicode/outputs/a.txt', load: (_) async => '第一行\n第二行\n'));
    await tester.pumpAndSettle();
    double size() => tester.widget<SelectableText>(find.byKey(const ValueKey('output-full-text'))).style!.fontSize!;
    expect(size(), 12);
    expect(find.ancestor(of: find.byKey(const ValueKey('output-full-text')), matching: find.byType(CodeZoom)), findsOneWidget);
    env.services.container.read(codeFontProvider.notifier).set(20);
    await tester.pump();
    expect(size(), 18);
    await settle(tester, rounds: 1);
    expect(tester.takeException(), isNull);
  });
}
