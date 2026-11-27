// “要等的事”积木（核心 3）的主题冒烟：十套内置主题，每套把后端积木页上和它有关的状态摆一遍（390×844）——
// 不许抛异常、不许溢出。theme_smoke_test.dart 放不下了，单独一个文件。
//   flutter test --no-pub test/theme_wait_smoke_test.dart
//   LOPI_SHOTS=1 LOPI_SHOT_DIR=../preview/lang/a3 flutter test --no-pub test/theme_wait_smoke_test.dart   # 同时出 wait-<主题>-*.png
//
// 覆盖的状态：积木盒“要等的事”那一页（四组十块）、画布上一个把十块都用上的接口、看代码（严格文档真生成的入口文件）、
// 放错地方时的问题列表（T31 带“去掉‘等’”、T30）。
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/appearance/theme_builtin.dart';
import 'package:lopicode/backend/backend_blocks_wait.dart';
import 'package:lopicode/backend/backend_model.dart';
import 'package:lopicode/blocks/block_editor_view.dart';
import 'package:lopicode/core/project_store.dart';
import 'package:lopicode/core/templates.dart';
import 'package:lopicode/project_session.dart';
import 'package:lopicode/state/themes_state.dart';
import 'package:lopicode/templates/project_templates.dart';
import 'package:lopicode/ui/backend_screen.dart';
import 'package:lopicode/ui/project_shell.dart';
import 'package:lopicode/ui/shell.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;

import 'support/backend_func_blocks.dart';
import 'support/backend_lang_blocks.dart';
import 'support/backend_wait_sample.dart';
import 'support/harness.dart';
import 'support/runtime_fakes.dart';

final bool writeShots = Platform.environment['LOPI_SHOTS'] == '1';
final String shotDir = Platform.environment['LOPI_SHOT_DIR'] ?? '.tmp/theme-shots';
bool fontsLoaded = false;

void main() {
  setUpAll(() async => fontsLoaded = await loadRealFonts());

  for (final theme in kBuiltinThemes) {
    final mode = theme.dark ? ThemeMode.dark : ThemeMode.light;

    Future<void> shot(WidgetTester tester, String page) async {
      expect(tester.takeException(), isNull, reason: '${theme.name} · 要等的事 · $page 渲染时出了异常（溢出也算）');
      if (!writeShots || !fontsLoaded) return;
      final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(shotKey));
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 2);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        File('$shotDir/wait-${theme.id}-$page.png')
          ..parent.createSync(recursive: true)
          ..writeAsBytesSync(data!.buffer.asUint8List());
      });
    }

    /// 开一个后端积木项目，文档换成 [doc]（名字、端口留用模板的），打开积木页。
    Future<BackendScreenState> open(WidgetTester tester, J doc) async {
      usePhoneViewport(tester);
      late TestEnv env;
      late Project project;
      late ProjectSession session;
      await tester.runAsync(() async {
        env = await TestEnv.create();
        expect(await env.services.container.read(themesProvider.notifier).select(theme.id), isNull);
        project = await createProjectFromTemplate(env.services.projects, '我的小站', ProjectTemplate.backendBlocks, language: 'node');
        final file = File(p.join(project.dir, kBackendFileName));
        final was = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
        file.writeAsStringSync(jsonEncode({...doc, 'name': was['name'], 'port': was['port']}));
        session = ProjectSession(env.services, project);
        session.ptySpawner = (exe, {required workingDirectory, required environment, required rows, required columns}) => FakePty();
        await session.loadChat();
        await Future<void>.delayed(const Duration(milliseconds: 150));
      });
      addTearDown(() async {
        await tester.runAsync(() async {
          session.dispose();
          await env.dispose();
        });
      });
      await tester.pumpWidget(
        appFor(
          env,
          ProjectShell(project: project, session: session, initial: ShellDest.builder),
          mode: mode,
          font: kTestFont,
        ),
      );
      await settle(tester, rounds: 8);
      return tester.state<BackendScreenState>(find.byType(BackendScreen));
    }

    group('${theme.name}（${theme.id}）', () {
      testWidgets('要等的事：积木盒那一页、画布、看代码', (tester) async {
        final screen = await open(tester, waitSampleDoc());
        final host = screen.host!;
        final editor = tester.state<BlockEditorViewState>(find.byType(BlockEditorView));
        expect(host.issues.where((i) => i.isError), isEmpty, reason: '样例文档没有标红');

        final tabs = find.byKey(const ValueKey('bk-palette-tabs'));
        if (tabs.hitTestable().evaluate().isEmpty) {
          await tester.drag(find.byKey(const ValueKey('bk-palette-grip')), const Offset(0, -300), warnIfMissed: false);
          await tester.pumpAndSettle();
        }
        final tab = find.byKey(const ValueKey('bk-palette-tab-$kBeCatWait'));
        for (var i = 0; i < 16 && tab.hitTestable().evaluate().isEmpty; i++) {
          await tester.drag(tabs, const Offset(-120, 0));
          await tester.pumpAndSettle();
        }
        await tester.tap(tab);
        await tester.pumpAndSettle();
        await shot(tester, 'palette');

        await tester.drag(find.byKey(const ValueKey('bk-palette-grip')), const Offset(0, 300), warnIfMissed: false);
        await tester.pumpAndSettle();
        editor.jumpTo('r1', const []);
        await tester.pumpAndSettle();
        editor.select(null);
        await tester.pumpAndSettle();
        await shot(tester, 'canvas');

        // 看代码：严格文档真生成的入口文件，里面看得到“开始做”“等最多”翻成了什么。
        expect(host.codeText, contains('awaitMax'));
        await tester.tap(find.byKey(const ValueKey('bk-code')));
        await tester.pumpAndSettle();
        await shot(tester, 'code');
      });

      testWidgets('要等的事 · 放错地方：问题列表里说清楚，能修的带按钮', (tester) async {
        final screen = await open(tester, {
          ...waitSampleDoc(),
          'routes': [
            route('r1', 'GET', '/bad', [
              konst('n', ex('await', {'x': nm(3)})),
              konst('xs', hof('listMap', ls([nm(1), nm(2)]), arrow(['x'], slow(1, 5)))),
              text(cat([vr('n'), vr('xs')])),
            ]),
          ],
        });
        final rules = [for (final i in screen.host!.issues) i.rule];
        expect(rules, containsAll(['T31', 'T30']));
        await tester.drag(find.byKey(const ValueKey('bk-palette-grip')), const Offset(0, 300), warnIfMissed: false);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('bk-issues')));
        await tester.pumpAndSettle();
        expect(find.textContaining('去掉“等”'), findsWidgets);
        await shot(tester, 'issues');
      });
    });
  }
}
