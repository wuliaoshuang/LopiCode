// 代码区域的高亮 + 缩放：逐个入口走一遍真实路径（2026-11-25 霜霜：代码区域没有高亮、不能缩放）。
// test/code_zoom_test.dart 管共用的三样东西本身；这里管“每个用到代码的地方真的接上了”：
// 页面逻辑的看代码、后端积木的看代码（五种语言）、导出预览（Vue / React 的每个文件）、打包页的工作流模板，
// 以及缩放不挡单指的事（长按选字、点一下放光标）。390×844，浅色 + 深色。
//   LOPI_SHOTS=1 flutter test test/code_zoom_regions_test.dart   # 同时写截图到 docs/screenshots/
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/backend/backend_block_host.dart';
import 'package:lopicode/backend/backend_targets.dart';
import 'package:lopicode/backend/backend_templates.dart';
import 'package:lopicode/blocks/block_host.dart';
import 'package:lopicode/blocks/block_panels_sheet.dart';
import 'package:lopicode/build/build_screen.dart';
import 'package:lopicode/core/project_store.dart';
import 'package:lopicode/core/stores.dart';
import 'package:lopicode/core/templates.dart';
import 'package:lopicode/lowcode/code_sheet.dart';
import 'package:lopicode/lowcode/export_react.dart';
import 'package:lopicode/lowcode/export_sheet.dart';
import 'package:lopicode/lowcode/export_vue.dart';
import 'package:lopicode/lowcode/logic_block_host.dart';
import 'package:lopicode/project_session.dart';
import 'package:lopicode/state/code_font.dart';
import 'package:lopicode/ui/code_editor.dart';
import 'package:lopicode/ui/code_highlight.dart';
import 'package:lopicode/ui/code_view.dart';
import 'package:material_ui/material_ui.dart';
import 'package:re_editor/re_editor.dart';

import 'code_zoom_test.dart' as base show fontsLoaded;
import 'code_zoom_test.dart' show colorsOf, goCode, shot;
import 'screens_test.dart' show inShell;
import 'support/harness.dart';
import 'support/lowcode_samples.dart';

Finder k(String key) => find.byKey(Key(key));
Finder vk(String key) => find.byKey(ValueKey(key));

void main() {
  setUpAll(() async => base.fontsLoaded = await loadRealFonts());

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    final suffix = mode == ThemeMode.light ? 'light' : 'dark';

    Future<TestEnv> boot(WidgetTester tester, Widget home) async {
      usePhoneViewport(tester);
      late TestEnv env;
      await tester.runAsync(() async => env = await TestEnv.create());
      addTearDown(() => tester.runAsync(env.dispose));
      await tester.pumpWidget(appFor(env, home, mode: mode, font: kTestFont));
      await settle(tester, rounds: 2);
      return env;
    }

    /// 一个按钮，点了就弹 [open]（和各页面里的做法一样：都是从页面上弹底部面板）。
    Widget opener(void Function(BuildContext) open) => Scaffold(
      body: Builder(
        builder: (context) => Center(
          child: TextButton(onPressed: () => open(context), child: const Text('开')),
        ),
      ),
    );

    Future<void> openSheet(WidgetTester tester) async {
      await tester.tap(find.text('开'));
      await tester.pumpAndSettle();
    }

    Future<void> closeSheet(WidgetTester tester) async {
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(CodeSheetBody), findsNothing);
    }

    SelectableText codeText(WidgetTester tester) => tester.widget<SelectableText>(k('code-view-text'));

    /// 代码很长时 CodeView 的中心在屏幕外面，所以捏的是外面那层 CodeZoom（它就是屏幕上看得见的那一块）。
    /// 两根手指在 [target] 上从 [from] 捏到 [to]，然后松手。
    Future<void> pinchOnce(WidgetTester tester, Finder target, {required double from, required double to}) async {
      final center = tester.getCenter(target);
      final a = await tester.startGesture(center - Offset(from / 2, 0), pointer: 31);
      final b = await tester.startGesture(center + Offset(from / 2, 0), pointer: 32);
      await tester.pump();
      for (var i = 1; i <= 6; i++) {
        final d = from + (to - from) * i / 6;
        await a.moveTo(center - Offset(d / 2, 0));
        await b.moveTo(center + Offset(d / 2, 0));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await a.up();
      await b.up();
      await tester.pump();
    }

    testWidgets('积木“看代码”：页面逻辑是带颜色的 JS；后端五种语言各自带颜色；捏合后关掉再开还是那个字号 ($suffix)', (tester) async {
      final logic = LogicBlockHost(doc: frameworkSample(), onEdit: (change) {});
      BlockHost host = logic;
      final env = await boot(tester, opener((c) => showBlockCode(c, host)));

      await openSheet(tester);
      expect(tester.widget<CodeSheetBody>(find.byType(CodeSheetBody)).language, 'js');
      expect(codeText(tester).textSpan!.toPlainText(), logic.codeText.replaceAll('\t', '    '));
      expect(colorsOf(codeText(tester).textSpan!).length, greaterThanOrEqualTo(3), reason: '页面逻辑的 JS 要上色');
      expect(codeText(tester).style?.fontSize, 14);
      await shot(tester, '126-logic-code-$suffix');

      await pinchOnce(tester, find.byType(CodeZoom), from: 100, to: 130);
      expect(env.services.container.read(codeFontProvider), 18);
      expect(env.services.settings.get<num>(SettingKeys.codeFontSize), 18);
      await closeSheet(tester);

      for (final t in backendTargets) {
        final be = BeBlockHost(doc: backendStarterDocument('样本')..language = t.id);
        host = be;
        await openSheet(tester);
        final sheet = tester.widget<CodeSheetBody>(find.byType(CodeSheetBody));
        expect(sheet.language, CodeHighlighter.languageFor(t.entryFile), reason: t.id);
        expect(sheet.code, be.codeText, reason: '“复制全部”拿的是原文');
        expect(colorsOf(codeText(tester).textSpan!).length, greaterThanOrEqualTo(3), reason: '${t.id} 的看代码要上色');
        expect(codeText(tester).style?.fontSize, 18, reason: '重开还是捏好的字号');
        if (t.id == 'go') await shot(tester, '127-backend-code-go-$suffix');
        await closeSheet(tester);
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('导出预览：Vue / React 的每个文件点开都按文件名上色、能捏合 ($suffix)', (tester) async {
      usePhoneViewport(tester);
      late TestEnv env;
      late ProjectSession session;
      await tester.runAsync(() async {
        env = await TestEnv.create();
        final project = await env.services.projects.create('我的小站', ProjectTemplate.lowcode);
        session = ProjectSession(env.services, project);
        await session.loadChat();
        await Future<void>.delayed(const Duration(milliseconds: 150));
      });
      addTearDown(() async {
        session.dispose();
        await env.dispose();
      });
      final doc = frameworkSample();
      await tester.pumpWidget(
        appFor(
          env,
          opener((c) => showFrameworkExport(c, doc: doc, session: session)),
          mode: mode,
          font: kTestFont,
        ),
      );
      await settle(tester);
      await tester.tap(find.text('开'));
      await tester.pumpAndSettle();

      Future<void> checkFiles(List<String> paths) async {
        for (final path in paths) {
          await tester.ensureVisible(vk('lc-export-file-$path'));
          await tester.tap(vk('lc-export-file-$path'));
          await tester.pumpAndSettle();
          final sheet = tester.widget<CodeSheetBody>(find.byType(CodeSheetBody));
          expect(sheet.language, CodeHighlighter.languageFor(path), reason: path);
          expect(sheet.language, isNot('text'), reason: '$path 要有高亮');
          expect(colorsOf(codeText(tester).textSpan!).length, greaterThanOrEqualTo(2), reason: '$path 要上色');
          if (path.endsWith('.vue')) {
            await shot(tester, '128-export-code-vue-$suffix');
            await pinchOnce(tester, find.byType(CodeZoom), from: 120, to: 90);
            expect(codeText(tester).style?.fontSize, lessThan(14), reason: '导出预览也能捏合');
          }
          await tester.binding.handlePopRoute();
          await tester.pumpAndSettle();
        }
      }

      await checkFiles([for (final f in exportVue(doc).files) f.path]);
      await tester.tap(find.text('React'));
      await tester.pumpAndSettle();
      await checkFiles([for (final f in exportReact(doc).files) f.path]);
      expect(tester.takeException(), isNull);
    });

    testWidgets('打包页“查看现成模板”：工作流是带颜色的 YAML，能捏合 ($suffix)', (tester) async {
      usePhoneViewport(tester);
      late TestEnv env;
      late Project project;
      late ProjectSession session;
      await tester.runAsync(() async {
        env = await TestEnv.create();
        project = await env.services.projects.create('我的小站', ProjectTemplate.web);
        session = ProjectSession(env.services, project);
        await session.loadChat();
        await env.services.settings.set(SettingKeys.apkBuildMode, 'github');
        await Future<void>.delayed(const Duration(milliseconds: 150));
      });
      addTearDown(() async {
        session.dispose();
        await env.dispose();
      });
      await tester.pumpWidget(
        appFor(
          env,
          inShell(BuildScreen(session: session)),
          mode: mode,
          font: kTestFont,
        ),
      );
      await settle(tester);
      final entry = find.textContaining('查看现成模板');
      await tester.scrollUntilVisible(entry, 120, scrollable: find.byType(Scrollable).first);
      await tester.ensureVisible(entry);
      await tester.pump();
      await tester.tap(entry);
      await tester.pumpAndSettle();
      final sheet = tester.widget<CodeSheetBody>(find.byType(CodeSheetBody));
      expect(sheet.language, 'yaml');
      expect(colorsOf(codeText(tester).textSpan!).length, greaterThanOrEqualTo(2), reason: '工作流模板要上色');
      await shot(tester, '129-build-workflow-$suffix');
      await pinchOnce(tester, find.byType(CodeZoom), from: 100, to: 150);
      expect(codeText(tester).style?.fontSize, 21);
      expect(env.services.settings.get<num>(SettingKeys.codeFontSize), 21);
      expect(tester.takeException(), isNull);
    });

    testWidgets('缩放不挡单指的事：只读代码长按能选中一个词；编辑器点一下放光标、长按选词、能照常打字 ($suffix)', (tester) async {
      final env = await boot(
        tester,
        const Scaffold(
          body: CodeSheetBody(title: 't', note: 'n', code: goCode, language: 'go'),
        ),
      );
      // 长按第一行的 package：选中了一段，字号没变，也没有字号提示。
      final topLeft = tester.getTopLeft(k('code-view-text'));
      await tester.longPressAt(topLeft + const Offset(20, 8));
      await tester.pump(const Duration(milliseconds: 300));
      final state = tester.state<EditableTextState>(find.descendant(of: k('code-view-text'), matching: find.byType(EditableText)));
      final sel = state.textEditingValue.selection;
      expect(sel.isCollapsed, isFalse, reason: '长按要能选字');
      expect(sel.textInside(state.textEditingValue.text), 'package');
      expect(env.services.container.read(codeFontProvider), 14);
      expect(k('code-zoom-badge'), findsNothing);
      // 选区工具条等浮层收掉再换页面。
      await tester.tapAt(const Offset(195, 30));
      await tester.pumpAndSettle();

      final c = CodeLineEditingController.fromText('alpha beta\ngamma delta\n');
      final f = CodeFindController(c);
      addTearDown(() {
        f.dispose();
        c.dispose();
      });
      await tester.pumpWidget(
        appFor(
          env,
          Scaffold(
            body: LopiCodeEditor(path: 'a.js', controller: c, findController: f, wordWrap: true),
          ),
          mode: mode,
          font: kTestFont,
        ),
      );
      await settle(tester, rounds: 2);
      final box = tester.getRect(find.byType(CodeEditor));
      // 点第二行靠后的位置：光标到了第二行。
      await tester.tapAt(box.topLeft + const Offset(200, 40), kind: PointerDeviceKind.touch);
      await tester.pump(const Duration(milliseconds: 400));
      expect(c.selection.isCollapsed, isTrue);
      expect(c.selection.baseIndex, 1, reason: '点一下把光标放到点的那一行');
      // 长按第一行的词：选中一段。
      await tester.longPressAt(box.topLeft + const Offset(70, 18));
      await tester.pump(const Duration(milliseconds: 400));
      expect(c.selection.isCollapsed, isFalse, reason: '编辑器里长按要能选词');
      expect(c.selection.baseIndex, 0);
      expect(env.services.container.read(codeFontProvider), 14, reason: '单指操作不改字号');
      expect(k('code-zoom-badge'), findsNothing);
      // 捏合以后照常能改内容。
      await pinchOnce(tester, find.byType(CodeEditor), from: 120, to: 154);
      expect(env.services.container.read(codeFontProvider), 18);
      c.replaceSelection('X');
      await tester.pump();
      expect(c.text.contains('X'), isTrue);
      // 编辑器自己的短定时器（双击判定、聚焦后的延时回调、选区工具条）走完。
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
    });
  }
}
