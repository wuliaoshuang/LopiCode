// 新建项目面板（手机 390×844）：模板分组、选了要语言的模板才出现语言、创建后文件落盘。
// LOPI_SHOTS=1 时把浅色 / 深色截图写到 docs/screenshots/tp-*.png。
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/backend/backend_model.dart';
import 'package:lopicode/backend/backend_project.dart';
import 'package:lopicode/backend/backend_targets.dart';
import 'package:lopicode/core/path_guard.dart';
import 'package:lopicode/core/project_store.dart';
import 'package:lopicode/core/templates.dart';
import 'package:lopicode/templates/code_starters.dart';
import 'package:lopicode/ui/file_icon.dart';
import 'package:lopicode/ui/new_project_sheet.dart';
import 'package:lopicode/ui/project_list_screen.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;

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

Finder tpl(ProjectTemplate t) => find.byKey(ValueKey('tpl-${t.id}'));
Finder lang(String id) => find.byKey(ValueKey('tpl-lang-$id'));
final Finder list = find.descendant(of: find.byKey(const ValueKey('tpl-list')), matching: find.byType(Scrollable)).first;

/// 滚到看得见再点（列表靠后的项可能只在缓存区里）。
Future<void> tapVisible(WidgetTester tester, Finder target, {bool up = false}) async {
  await tester.scrollUntilVisible(target, up ? -120 : 120, scrollable: list);
  await tester.ensureVisible(target);
  await tester.pump(const Duration(milliseconds: 300));
  await tester.tap(target);
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  setUpAll(() async => fontsLoaded = await loadRealFonts());

  /// 打开项目列表 → 添加工作区 → 新建项目。返回被打开的项目会记到 `opened`。
  Future<TestEnv> openSheet(WidgetTester tester, List<Project> opened, {ThemeMode mode = ThemeMode.light}) async {
    usePhoneViewport(tester);
    late TestEnv env;
    await tester.runAsync(() async => env = await TestEnv.create());
    addTearDown(env.dispose);
    await tester.pumpWidget(
      appFor(
        env,
        ProjectListScreen(onOpen: opened.add),
        mode: mode,
        font: kTestFont,
      ),
    );
    await settle(tester);
    await tester.tap(find.widgetWithText(FilledButton, '添加工作区').first);
    await settle(tester, rounds: 3);
    await tester.tap(find.text('新建项目'));
    await settle(tester, rounds: 3);
    expect(find.byType(NewProjectSheet), findsOneWidget);
    return env;
  }

  /// 点“创建”，等到项目建完并被打开（建项目是一串真实的文件读写，步数跟模板文件数有关，所以是等结果而不是数轮数）。
  Future<void> create(WidgetTester tester, List<Project> opened) async {
    await tester.tap(find.widgetWithText(FilledButton, '创建'));
    for (var i = 0; i < 80 && opened.isEmpty; i++) {
      await settle(tester, rounds: 10, ms: 5);
    }
    await settle(tester, rounds: 10, ms: 5);
    expect(opened, hasLength(1), reason: '点了“创建”以后项目没有被打开');
  }

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    final suffix = mode == ThemeMode.light ? 'light' : 'dark';

    testWidgets('面板：分组列表 → 选后端积木出现语言 → 选代码模板 → 全栈 ($suffix)', (tester) async {
      await openSheet(tester, [], mode: mode);

      // 一打开：分组标题、模板名和说明都在，默认选前端网页，不出现语言
      for (final g in [TemplateGroup.blank, TemplateGroup.frontend, TemplateGroup.backendBlocks]) {
        expect(find.text(g.label), findsOneWidget);
      }
      for (final t in [ProjectTemplate.empty, ProjectTemplate.web, ProjectTemplate.lowcode]) {
        expect(find.descendant(of: tpl(t), matching: find.text(t.label)), findsOneWidget);
        expect(find.descendant(of: tpl(t), matching: find.text(t.description)), findsOneWidget);
        expect(
          find.descendant(of: tpl(t), matching: find.byType(FileIcon)),
          findsOneWidget,
          reason: '每个模板一个图标',
        );
      }
      expect(find.byKey(const ValueKey('tpl-languages')), findsNothing);
      expect(find.widgetWithText(FilledButton, '创建'), findsOneWidget);
      await shot(tester, 'tp-01-templates-$suffix');

      // 选后端积木：语言出现在它下面，列的就是现有的生成器，默认选第一种
      await tapVisible(tester, tpl(ProjectTemplate.backendBlocks));
      await tester.scrollUntilVisible(find.byKey(const ValueKey('tpl-language-note')), 120, scrollable: list);
      await tester.pump(const Duration(milliseconds: 300));
      for (final t in backendTargets) {
        expect(find.descendant(of: lang(t.id), matching: find.text(t.label)), findsOneWidget);
        expect(find.descendant(of: lang(t.id), matching: find.text('未实测')), t.verified ? findsNothing : findsOneWidget);
      }
      expect(tester.getTopLeft(find.byKey(const ValueKey('tpl-languages'))).dy, greaterThan(tester.getTopLeft(tpl(ProjectTemplate.backendBlocks)).dy));
      expect(find.widgetWithText(FilledButton, '创建'), findsOneWidget, reason: '“创建”固定在底部，不跟着滚走');
      await shot(tester, 'tp-02-backend-blocks-$suffix');

      // 语言胶囊够大好点（至少 40 高），都在屏幕里
      for (final t in backendTargets) {
        final r = tester.getRect(lang(t.id));
        expect(r.height, greaterThanOrEqualTo(40), reason: t.id);
        expect(r.left >= 0 && r.right <= 390, isTrue, reason: '${t.id} 超出屏幕');
      }

      // 选代码模板：语言换成十种起步工程；没实测过的标出来，说明也如实
      await tapVisible(tester, tpl(ProjectTemplate.backendCode));
      expect(find.byKey(const ValueKey('tpl-languages')), findsOneWidget, reason: '语言只跟着选中的模板出现一份');
      await tester.scrollUntilVisible(find.byKey(const ValueKey('tpl-language-note')), 120, scrollable: list);
      await tester.pump(const Duration(milliseconds: 300));
      for (final s in codeStarters) {
        expect(lang(s.id), findsOneWidget, reason: s.id);
        expect(
          find.descendant(of: lang(s.id), matching: find.text('未实测')),
          s.verified ? findsNothing : findsOneWidget,
          reason: s.id,
        );
      }
      expect(tester.widget<Text>(find.byKey(const ValueKey('tpl-language-note'))).data, contains('已在电脑上实际运行验证过'));
      await shot(tester, 'tp-03-backend-code-$suffix');

      await tester.ensureVisible(lang('rust'));
      await tester.tap(lang('rust'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.scrollUntilVisible(find.byKey(const ValueKey('tpl-language-note')), 120, scrollable: list);
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.widget<Text>(find.byKey(const ValueKey('tpl-language-note'))).data, contains('还没有实际运行过'));
      await shot(tester, 'tp-04-backend-code-unverified-$suffix');

      // 全栈
      await tapVisible(tester, tpl(ProjectTemplate.fullstack));
      await tester.scrollUntilVisible(find.byKey(const ValueKey('tpl-language-note')), 120, scrollable: list);
      await tester.pump(const Duration(milliseconds: 300));
      expect(lang(backendTargets.first.id), findsOneWidget);
      expect(lang('rust'), findsNothing);
      await shot(tester, 'tp-05-fullstack-$suffix');

      // 选回不用语言的模板：语言收起来
      await tapVisible(tester, tpl(ProjectTemplate.empty), up: true);
      expect(find.byKey(const ValueKey('tpl-languages')), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('直接点“创建”：默认是前端网页，名字用模板名，文件落盘并打开', (tester) async {
    final opened = <Project>[];
    await openSheet(tester, opened);
    await create(tester, opened);
    expect(find.byType(NewProjectSheet), findsNothing);
    expect((opened.single.name, opened.single.template, opened.single.language), ('我的前端网页', ProjectTemplate.web, null));
    await tester.runAsync(() async {
      expect(File(p.join(opened.single.dir, 'index.html')).existsSync(), isTrue);
      expect(File(p.join(opened.single.dir, 'script.js')).existsSync(), isTrue);
    });
  });

  testWidgets('后端积木 + Python：backend.lc.json、生成的代码、README 落盘，project.json 记下语言', (tester) async {
    final opened = <Project>[];
    await openSheet(tester, opened);
    await tester.enterText(find.byType(TextField), '  待办接口  ');
    await tapVisible(tester, tpl(ProjectTemplate.backendBlocks));
    await tester.ensureVisible(lang('python'));
    await tester.tap(lang('python'));
    await tester.pump(const Duration(milliseconds: 300));
    await create(tester, opened);

    final project = opened.single;
    expect((project.name, project.template, project.language), ('待办接口', ProjectTemplate.backendBlocks, 'python'));
    await tester.runAsync(() async {
      final doc = BeDocument.parse(File(p.join(project.dir, kBackendFileName)).readAsStringSync());
      expect((doc.note, doc.doc.name, doc.doc.language), (null, '待办接口', 'python'));
      expect(File(p.join(project.dir, backendTargetFor('python')!.entryFile)).existsSync(), isTrue);
      expect(File(p.join(project.dir, 'README.md')).readAsStringSync(), contains('curl'));
      expect(File(p.join(project.dir, backendTargetFor('node')!.entryFile)).existsSync(), isFalse, reason: '没选的语言不生成');
      final meta = jsonDecode(File(p.join(project.dir, PathGuard.reservedDir, 'project.json')).readAsStringSync()) as Map;
      expect((meta['template'], meta['language']), ('backend-blocks', 'python'));
      final info = await detectBackendProject(project.dir);
      expect((info?.language, info?.errorCount), ('python', 0));
    });
    // 列表里看得到新项目
    expect(find.text('待办接口'), findsOneWidget);
  });

  testWidgets('后端代码 + Go：来回切模板不丢语言选择；起步工程落盘，不带积木', (tester) async {
    final opened = <Project>[];
    await openSheet(tester, opened);
    await tapVisible(tester, tpl(ProjectTemplate.backendCode));
    await tester.ensureVisible(lang('go'));
    await tester.tap(lang('go'));
    await tester.pump(const Duration(milliseconds: 300));
    await tapVisible(tester, tpl(ProjectTemplate.web), up: true);
    await tapVisible(tester, tpl(ProjectTemplate.backendCode));
    await create(tester, opened);

    final project = opened.single;
    expect((project.name, project.template, project.language), ('我的后端服务（代码）', ProjectTemplate.backendCode, 'go'));
    await tester.runAsync(() async {
      for (final f in codeStarterFor('go')!.files(project.name).entries) {
        expect(File(p.join(project.dir, f.key)).readAsStringSync(), f.value, reason: f.key);
      }
      expect(File(p.join(project.dir, kBackendFileName)).existsSync(), isFalse);
      expect(await detectBackendProject(project.dir), isNull);
    });
  });

  testWidgets('前端 + 后端：web/ 和 server/ 都落盘，认得出 server/ 里的后端', (tester) async {
    final opened = <Project>[];
    await openSheet(tester, opened);
    await tapVisible(tester, tpl(ProjectTemplate.fullstack));
    await create(tester, opened);

    final project = opened.single;
    final first = backendTargets.first;
    expect((project.template, project.language), (ProjectTemplate.fullstack, first.id));
    await tester.runAsync(() async {
      for (final f in ['README.md', 'index.html', 'web/index.html', 'web/app.js', 'web/style.css', 'server/$kBackendFileName', 'server/${first.entryFile}']) {
        expect(File(p.join(project.dir, f)).existsSync(), isTrue, reason: f);
      }
      final info = await detectBackendProject(project.dir);
      expect((info?.dir, info?.language), ('server', first.id));
      expect(info?.terminalCommand, startsWith('cd server && '));
    });
  });

  testWidgets('点面板外面关掉：不建项目', (tester) async {
    final opened = <Project>[];
    final env = await openSheet(tester, opened);
    await tapVisible(tester, tpl(ProjectTemplate.fullstack));
    await tester.tapAt(const Offset(195, 30));
    await settle(tester, rounds: 3);
    expect(find.byType(NewProjectSheet), findsNothing);
    expect(opened, isEmpty);
    late List<Project> listed;
    await tester.runAsync(() async => listed = await env.services.projects.list());
    expect(listed, isEmpty);
  });

  testWidgets('键盘弹出来：面板让开键盘，“创建”还点得到，不溢出', (tester) async {
    await openSheet(tester, []);
    tester.view.viewInsets = const FakeViewPadding(bottom: 320);
    addTearDown(tester.view.resetViewInsets);
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull);
    final button = tester.getRect(find.widgetWithText(FilledButton, '创建'));
    expect(button.bottom, lessThanOrEqualTo(844 - 320));
    expect(button.top, greaterThan(0));
    await shot(tester, 'tp-06-keyboard-light');
  });
}
