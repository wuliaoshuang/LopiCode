// 文件编辑器的“格式化”（390×844，浅色 / 深色）：乱糟糟的 .css / .json → ⋮ → 格式化 → 变整齐、能撤销回去；
// 坏 JSON 内容不变且有提示；不支持的类型菜单项是灰的。
// 设置环境变量 LOPI_SHOTS=1 时把截图写到 docs/screenshots/：
//   LOPI_SHOTS=1 flutter test --no-pub test/editor_format_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/core/project_store.dart';
import 'package:lopicode/core/templates.dart';
import 'package:lopicode/project_session.dart';
import 'package:lopicode/ui/code_editor.dart';
import 'package:lopicode/ui/code_highlight.dart';
import 'package:lopicode/ui/editor_format.dart';
import 'package:lopicode/ui/project_shell.dart';
import 'package:lopicode/ui/shell.dart';
import 'package:material_ui/material_ui.dart';
import 'package:re_editor/re_editor.dart';

import 'support/harness.dart';

final bool writeShots = Platform.environment['LOPI_SHOTS'] == '1';
bool fontsLoaded = false;

Future<void> shot(WidgetTester tester, String name) async {
  expect(tester.takeException(), isNull, reason: '$name 渲染时出了异常');
  if (!writeShots || !fontsLoaded) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(shotKey));
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('docs/screenshots/$name.png');
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(data!.buffer.asUint8List());
  });
}

const String messyCss = '.card{display:flex;padding:8px 12px;border-radius:12px}\n        .card  .title ,.card h2{font-weight:600;color:#12202b}\n@media (min-width:600px){.card{padding:16px}}\n';
const String tidyCss =
    '.card {\n  display: flex;\n  padding: 8px 12px;\n  border-radius: 12px;\n}\n\n.card .title, .card h2 {\n  font-weight: 600;\n  color: #12202b;\n}\n\n@media (min-width:600px) {\n  .card {\n    padding: 16px;\n  }\n}\n';
const String messyJson = '{"name":"我的小站","version":1.0,\n      "tags":["a","b"],"nested":{"ok":true}}';
const String tidyJson = '{\n  "name": "我的小站",\n  "version": 1.0,\n  "tags": [\n    "a",\n    "b"\n  ],\n  "nested": {\n    "ok": true\n  }\n}\n';
const String badJson = '{\n  "name": "我的小站",\n  "tags": ["a", "b",],\n}\n';
const String notes = '# 笔记\n\n   随便   写的\n';

void main() {
  setUpAll(() async => fontsLoaded = await loadRealFonts());

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    final suffix = mode == ThemeMode.light ? 'light' : 'dark';

    testWidgets('格式化：变整齐、能撤销、坏文件不动、不支持的类型是灰的 ($suffix)', (tester) async {
      usePhoneViewport(tester);
      late TestEnv env;
      late Project project;
      late ProjectSession session;
      await tester.runAsync(() async {
        env = await TestEnv.create();
        project = await env.services.projects.create('我的小站', ProjectTemplate.web);
        File('${project.dir}/messy.css').writeAsStringSync(messyCss);
        File('${project.dir}/data.json').writeAsStringSync(messyJson);
        File('${project.dir}/bad.json').writeAsStringSync(badJson);
        File('${project.dir}/notes.md').writeAsStringSync(notes);
        session = ProjectSession(env.services, project);
        await session.loadChat();
        await Future<void>.delayed(const Duration(milliseconds: 150));
      });
      addTearDown(() async {
        session.dispose();
        await env.dispose();
      });
      await tester.pumpWidget(
        appFor(
          env,
          ProjectShell(project: project, session: session, initial: ShellDest.files),
          mode: mode,
          font: kTestFont,
        ),
      );
      await settle(tester, rounds: 20, ms: 5);

      CodeLineEditingController controller() => tester.widget<CodeEditor>(find.byType(CodeEditor)).controller!;
      Future<void> openFile(String name) async {
        if (find.byTooltip('文件列表').evaluate().isNotEmpty) {
          await tester.tap(find.byTooltip('文件列表'));
          await settle(tester, rounds: 3);
        }
        await tester.tap(find.text(name).first);
        await settle(tester, rounds: 20, ms: 5);
      }

      Future<void> openMenu() async {
        await tester.tap(find.byTooltip('编辑器菜单'));
        await settle(tester, rounds: 3);
      }

      Future<void> menu(String item) async {
        await openMenu();
        await tester.tap(find.text(item));
        await settle(tester, rounds: 4);
      }

      PopupMenuItem<String> item(String value) => tester.widgetList<PopupMenuItem<String>>(find.byType(PopupMenuItem<String>)).firstWhere((w) => w.value == value);

      // —— 乱糟糟的 CSS ——
      await openFile('messy.css');
      expect(controller().text, messyCss);
      expect(find.text('已保存'), findsOneWidget);
      await shot(tester, '70-editor-messy-$suffix');
      await openMenu();
      expect(item('format').enabled, isTrue);
      expect(item('undo').enabled, isFalse);
      await shot(tester, '71-editor-menu-$suffix');
      await tester.tap(find.text('格式化'));
      await settle(tester, rounds: 4);
      expect(controller().text, tidyCss);
      expect(find.text('已格式化'), findsOneWidget);
      expect(find.text('保存'), findsOneWidget, reason: '格式化算一次修改，要能保存');
      await shot(tester, '72-editor-formatted-$suffix');

      // 一步撤销回原样，再重做回来
      await openMenu();
      expect(item('undo').enabled, isTrue);
      await tester.tap(find.text('撤销'));
      await settle(tester, rounds: 4);
      expect(controller().text, messyCss);
      expect(find.text('已保存'), findsOneWidget);
      await menu('重做');
      expect(controller().text, tidyCss);

      // 已经整齐的再点一次：只提示，内容不变，也不多出一步撤销
      await menu('格式化');
      expect(find.text('已经是整齐的'), findsOneWidget);
      expect(controller().text, tidyCss);
      await menu('撤销');
      expect(controller().text, messyCss);
      await menu('重做');

      // 保存落盘
      await tester.tap(find.text('保存'));
      await settle(tester, rounds: 6);
      expect(File('${project.dir}/messy.css').readAsStringSync(), tidyCss);

      // —— 乱糟糟的 JSON ——
      await openFile('data.json');
      expect(controller().text, messyJson);
      await menu('格式化');
      expect(controller().text, tidyJson);
      expect(find.text('已格式化'), findsOneWidget);
      await menu('撤销');
      expect(controller().text, messyJson);

      // —— 坏 JSON：内容不变，有提示 ——
      await openFile('bad.json');
      await menu('格式化');
      expect(controller().text, badJson);
      expect(find.textContaining('没有格式化：第 3 行'), findsOneWidget);
      expect(find.text('已保存'), findsOneWidget, reason: '失败不算修改');
      await openMenu();
      expect(item('undo').enabled, isFalse, reason: '失败不留撤销记录');
      await shot(tester, '73-editor-format-failed-$suffix');
      await tester.tapAt(const Offset(20, 400)); // 点菜单外面关掉
      await settle(tester, rounds: 3);

      // —— 不支持的类型：菜单项是灰的，点了没反应 ——
      await openFile('notes.md');
      await openMenu();
      expect(item('format').enabled, isFalse);
      await shot(tester, '74-editor-format-disabled-$suffix');
      await tester.tap(find.text('格式化'), warnIfMissed: false);
      await settle(tester, rounds: 3);
      expect(controller().text, notes);
    });
  }

  test('格式化后光标留在原来那一行；行数变少了落在最后一行', () {
    final c = CodeLineEditingController.fromText('{"a":1,\n"b":2,\n"c":3}');
    addTearDown(c.dispose);
    c.selection = const CodeLineSelection.collapsed(index: 2, offset: 3);
    expect(formatInEditor(c, 'x.json'), '已格式化');
    expect(c.text, '{\n  "a": 1,\n  "b": 2,\n  "c": 3\n}\n');
    expect(c.selection, const CodeLineSelection.collapsed(index: 2, offset: 0));
    expect(c.canUndo, isTrue);
    c.undo();
    expect(c.text, '{"a":1,\n"b":2,\n"c":3}');

    final d = CodeLineEditingController.fromText('a{}\n\n\n\n\n\n\n');
    addTearDown(d.dispose);
    d.selection = const CodeLineSelection.collapsed(index: 6, offset: 0);
    expect(formatInEditor(d, 'x.css'), '已格式化');
    expect(d.text, 'a {}\n');
    expect(d.selection.extentIndex, 1);
  });

  test('格式化的提示语：不支持 / 失败 / 有一段原样保留', () {
    final c = CodeLineEditingController.fromText('随便');
    addTearDown(c.dispose);
    expect(canFormat('a.md'), isFalse);
    expect(formatInEditor(c, 'a.md'), '这种文件不支持格式化');
    expect(c.canUndo, isFalse);

    final bad = CodeLineEditingController.fromText('a {\n  color: red;\n');
    addTearDown(bad.dispose);
    expect(formatInEditor(bad, 'a.css'), startsWith('没有格式化：第 1 行'));
    expect(bad.text, 'a {\n  color: red;\n');
    expect(bad.canUndo, isFalse);

    final vue = CodeLineEditingController.fromText('<template><p>a</p></template>\n<script lang="ts">\nlet a:number=1\n</script>');
    addTearDown(vue.dispose);
    expect(formatInEditor(vue, 'App.vue'), '已格式化；lang="ts" 的 <script> 暂不格式化，原样保留');
    expect(vue.text, '<template>\n  <p>a</p>\n</template>\n\n<script lang="ts">\nlet a:number=1\n</script>\n');
    expect(formatInEditor(vue, 'App.vue'), '没有可以调整的地方（lang="ts" 的 <script> 暂不格式化，原样保留）');
  });

  test('高亮和文件图标认的扩展名', () {
    expect(CodeHighlighter.languageFor('App.vue'), 'vue');
    expect(CodeHighlighter.languageFor('a.scss'), 'scss');
    expect(CodeHighlighter.languageFor('a.less'), 'less');
    expect(CodeHighlighter.languageFor('a.jsx'), 'js');
    expect(CodeHighlighter.languageFor('a.cjs'), 'js');
    expect(CodeHighlighter.languageFor('a.tsx'), 'ts');
    expect(CodeHighlighter.languageFor('a.html'), 'html');
    expect(CodeHighlighter.languageFor('README'), 'text');
    expect(highlightModeFor('App.vue')?.$1, 'xml');
    expect(highlightModeFor('a.scss')?.$1, 'scss');
    expect(highlightModeFor('a.less')?.$1, 'less');
    expect(highlightModeFor('a.jsx')?.$1, 'javascript');
    expect(highlightModeFor('a.tsx')?.$1, 'typescript');
    expect(highlightModeFor('a.css')?.$1, 'css');
    expect(highlightModeFor('a.bin'), isNull);
  });

  for (final name in ['App.vue', 'a.scss', 'a.less']) {
    testWidgets('$name 能打开并上色，不出异常', (tester) async {
      usePhoneViewport(tester);
      final c = CodeLineEditingController.fromText(
        '<template>\n  <p class="a">{{ n }}</p>\n</template>\n<script>\nexport default { data() { return { n: 1 } } }\n</script>\n<style lang="scss">\n\$c: red;\n.a { .b { color: \$c; } }\n</style>\n',
      );
      final f = CodeFindController(c);
      addTearDown(() {
        f.dispose();
        c.dispose();
      });
      late TestEnv env;
      await tester.runAsync(() async => env = await TestEnv.create());
      addTearDown(env.dispose);
      await tester.pumpWidget(
        appFor(
          env,
          Scaffold(
            body: LopiCodeEditor(path: name, controller: c, findController: f, wordWrap: true),
          ),
        ),
      );
      await settle(tester, rounds: 6);
      expect(tester.takeException(), isNull);
      expect(find.byType(CodeEditor), findsOneWidget);
    });
  }
}
