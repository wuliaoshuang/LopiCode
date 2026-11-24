// “导出 Vue / React”面板的界面测试（390×844，浅色 + 深色）。
//   LOPI_SHOTS=1 flutter test --no-pub test/lowcode_export_sheet_test.dart   # 同时把截图写到 docs/screenshots/lc-export-*.png
//
// 文件是真的写到临时项目目录里再读回来比对的；越界的路径在写任何文件之前就被拦下。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/core/path_guard.dart';
import 'package:lopicode/core/project_store.dart';
import 'package:lopicode/core/templates.dart';
import 'package:lopicode/lowcode/code_sheet.dart';
import 'package:lopicode/lowcode/export_framework_common.dart';
import 'package:lopicode/lowcode/export_react.dart';
import 'package:lopicode/lowcode/export_sheet.dart';
import 'package:lopicode/lowcode/export_vue.dart';
import 'package:lopicode/project_session.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;

import 'screens_test.dart' show fontsLoaded, shot;
import 'support/harness.dart';
import 'support/lowcode_samples.dart';

Finder k(String key) => find.byKey(ValueKey(key));

void main() {
  setUpAll(() async {
    fontsLoaded = await loadRealFonts();
  });

  Future<(TestEnv, Project, ProjectSession)> open(WidgetTester tester) async {
    usePhoneViewport(tester);
    late TestEnv env;
    late Project project;
    late ProjectSession session;
    await tester.runAsync(() async {
      env = await TestEnv.create();
      project = await env.services.projects.create('我的小站', ProjectTemplate.lowcode);
      session = ProjectSession(env.services, project);
      await session.loadChat();
      await Future<void>.delayed(const Duration(milliseconds: 150));
    });
    addTearDown(() async {
      session.dispose();
      await env.dispose();
    });
    return (env, project, session);
  }

  /// 一个空页面 + 一个按钮，点了就打开导出面板（和搭建页菜单里的做法一样）。
  Future<void> pumpHost(WidgetTester tester, TestEnv env, ProjectSession session, ThemeMode mode) async {
    final doc = frameworkSample();
    await tester.pumpWidget(
      appFor(
        env,
        Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () => showFrameworkExport(context, doc: doc, session: session),
                child: const Text('打开导出'),
              ),
            ),
          ),
        ),
        mode: mode,
        font: kTestFont,
      ),
    );
    await settle(tester);
    await tester.tap(find.text('打开导出'));
    await tester.pumpAndSettle();
  }

  Map<String, String> readTree(String root) => {
    for (final f in Directory(root).listSync(recursive: true).whereType<File>()) p.relative(f.path, from: root).replaceAll(r'\', '/'): f.readAsStringSync(),
  };

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    final suffix = mode == ThemeMode.light ? 'light' : 'dark';

    testWidgets('看文件清单和代码 → 导出 Vue → 切到 React 再导出 ($suffix)', (tester) async {
      final (env, project, session) = await open(tester);
      await pumpHost(tester, env, session, mode);
      final vue = exportVue(frameworkSample());
      final react = exportReact(frameworkSample());

      // Vue：两个文件，带行数；说明里有“没编译过”和简化项
      expect(find.text('导出 Vue / React'), findsOneWidget);
      for (final f in vue.files) {
        expect(k('lc-export-file-${f.path}'), findsOneWidget);
        expect(find.descendant(of: k('lc-export-file-${f.path}'), matching: find.text('${f.lineCount} 行')), findsOneWidget);
      }
      final notes = tester.widget<Text>(k('lc-export-notes')).data!;
      expect(notes, contains(kExportNotCompiledNote));
      expect(notes, contains(kNoteNoBinding));
      expect(k('lc-export-result'), findsNothing);
      await shot(tester, 'lc-export-vue-$suffix');

      // 点一个文件看代码
      await tester.tap(k('lc-export-file-CounterDemo.vue'));
      await tester.pumpAndSettle();
      final code = tester.widget<CodeSheetBody>(find.byType(CodeSheetBody));
      expect(code.title, 'CounterDemo.vue');
      expect(code.code, vue.files.first.content);
      expect(code.note, '导出后在项目的 export/vue/CounterDemo.vue');
      await shot(tester, 'lc-export-code-$suffix');
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(CodeSheetBody), findsNothing);

      // 导出到项目：文件真的写进去了，内容和 exportVue 的一模一样
      final exportDir = p.join(project.dir, 'export');
      expect(Directory(exportDir).existsSync(), isFalse);
      await tester.tap(k('lc-export-write'));
      await settle(tester);
      expect(tester.widget<Text>(k('lc-export-result')).data, '已导出 2 个文件到 export/vue/');
      late Map<String, String> written;
      await tester.runAsync(() async => written = readTree(exportDir));
      expect(written, {for (final f in vue.files) 'vue/${f.path}': f.content});
      await shot(tester, 'lc-export-done-$suffix');

      // 切到 React：清单换了，上次的结果提示收起来
      await tester.tap(find.text('React'));
      await tester.pumpAndSettle();
      expect(k('lc-export-result'), findsNothing);
      expect(k('lc-export-file-CounterDemo.vue'), findsNothing);
      for (final f in react.files) {
        expect(k('lc-export-file-${f.path}'), findsOneWidget);
      }
      expect(tester.widget<Text>(k('lc-export-notes')).data, contains('StrictMode'));
      await shot(tester, 'lc-export-react-$suffix');
      await tester.tap(k('lc-export-write'));
      await settle(tester);
      expect(tester.widget<Text>(k('lc-export-result')).data, '已导出 5 个文件到 export/react/');
      await tester.runAsync(() async => written = readTree(exportDir));
      expect(written, {for (final f in vue.files) 'vue/${f.path}': f.content, for (final f in react.files) 'react/${f.path}': f.content});
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('写不进去：说出真正的原因，按钮恢复可点', (tester) async {
    final (env, project, session) = await open(tester);
    // export 这个名字被一个普通文件占了，目录建不出来
    await tester.runAsync(() async => File(p.join(project.dir, 'export')).writeAsString('占位'));
    await pumpHost(tester, env, session, ThemeMode.light);
    await tester.tap(k('lc-export-write'));
    await settle(tester);
    final result = tester.widget<Text>(k('lc-export-result')).data!;
    expect(result, startsWith('写文件失败'));
    expect(result, contains('export/vue'));
    expect(result, isNot(contains(project.dir)), reason: '提示里用项目内的相对路径，不带手机上的绝对路径');
    expect(tester.widget<FilledButton>(k('lc-export-write')).onPressed, isNotNull);
    await shot(tester, 'lc-export-failed-light');
  });

  testWidgets('越界的路径：一个文件都不写', (tester) async {
    final (_, project, session) = await open(tester);
    const good = LcExportFile(path: 'Ok.vue', content: 'x');
    for (final bad in const ['../escape.vue', '/abs.vue', 'a/../../b.vue', r'..\b.vue', '.lopicode/x.vue', 'a b.vue', 'noext', '']) {
      Object? error;
      await tester.runAsync(() async {
        try {
          await writeFrameworkExport(
            session,
            kVueExportDir,
            const LcFrameworkExport(
              files: [
                good,
                LcExportFile(path: 'placeholder', content: ''),
              ],
              notes: [],
            ).withSecond(bad),
          );
        } on PathGuardException catch (e) {
          error = e;
        }
      });
      expect(error, isA<PathGuardException>(), reason: bad);
    }
    // 目录本身越界也不行（守卫拦的）
    Object? error;
    await tester.runAsync(() async {
      try {
        await writeFrameworkExport(session, '../outside', const LcFrameworkExport(files: [good], notes: []));
      } on PathGuardException catch (e) {
        error = e;
      }
    });
    expect(error, isA<PathGuardException>());
    await tester.runAsync(() async {
      expect(Directory(p.join(project.dir, 'export')).existsSync(), isFalse, reason: '路径没全部查过之前不该写任何文件');
      expect(File(p.join(p.dirname(project.dir), 'escape.vue')).existsSync(), isFalse);
      expect(Directory(p.join(p.dirname(project.dir), 'outside')).existsSync(), isFalse);
    });
  });

  test('两种导出给出的路径都是“大驼峰英文名 + 固定目录”，标题再怪也一样', () {
    final json = frameworkSampleJson()..['title'] = '../../etc/passwd\u0000 <x>';
    ((json['components']! as List).first as Map)['name'] = r'..\..\evil/../x';
    for (final e in [exportVue(docOf(json)), exportReact(docOf(json))]) {
      for (final f in e.files) {
        expect(RegExp(r'^(components/)?[A-Za-z][A-Za-z0-9-]*\.(vue|jsx|css)$').hasMatch(f.path), isTrue, reason: f.path);
      }
    }
  });
}

extension on LcFrameworkExport {
  /// 把第二个文件的路径换掉（造越界样本用）。
  LcFrameworkExport withSecond(String path) => LcFrameworkExport(
    files: [
      files.first,
      LcExportFile(path: path, content: 'x'),
    ],
    notes: notes,
  );
}
