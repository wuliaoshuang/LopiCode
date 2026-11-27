// 库界面测试共用：开一个后端积木项目（文档换成给的那份、先把几个库放进项目），打开后端积木页。
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/backend/backend_lib_store.dart';
import 'package:lopicode/backend/backend_model.dart';
import 'package:lopicode/core/project_store.dart';
import 'package:lopicode/core/templates.dart';
import 'package:lopicode/project_session.dart';
import 'package:lopicode/templates/project_templates.dart';
import 'package:lopicode/ui/backend_screen.dart';
import 'package:lopicode/ui/project_shell.dart';
import 'package:lopicode/ui/shell.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;

import 'backend_lang_blocks.dart';
import 'harness.dart';
import 'runtime_fakes.dart';

typedef LibUi = ({BackendScreenState screen, ProjectSession session, Project project});

/// [libs]＝先放进项目的库文档（走和应用里存库一样的函数）；[files]＝另外要放进工作区的文件（相对路径 → 字节）。
/// [before]＝项目建好、界面还没起来时要做的事（比如换主题）。
Future<LibUi> openLibUi(
  WidgetTester tester,
  J doc, {
  List<J> libs = const [],
  Map<String, List<int>> files = const {},
  ThemeMode mode = ThemeMode.light,
  String? font,
  Future<void> Function(TestEnv env)? before,
}) async {
  usePhoneViewport(tester);
  late TestEnv env;
  late Project project;
  late ProjectSession session;
  await tester.runAsync(() async {
    env = await TestEnv.create();
    await before?.call(env);
    project = await createProjectFromTemplate(env.services.projects, '我的小站', ProjectTemplate.backendBlocks, language: 'node');
    session = ProjectSession(env.services, project);
    for (final lib in libs) {
      final parsed = parseLangBlocksDocument(lib);
      final rel = beLibSourceRel(parsed.library!.id);
      final file = File(session.guard.resolve(rel));
      await file.parent.create(recursive: true);
      await saveBackendFile(file, parsed);
      final saved = await beLibSaveSource(session.guard, rel, parsed);
      expect(saved.problems, isEmpty, reason: '样例库应该出得了库文件');
    }
    for (final e in files.entries) {
      final f = File(p.join(project.dir, e.key));
      await f.parent.create(recursive: true);
      await f.writeAsBytes(e.value);
    }
    final file = File(p.join(project.dir, kBackendFileName));
    final was = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    file.writeAsStringSync(jsonEncode({...doc, 'name': was['name'], 'port': was['port']}));
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
      font: font,
    ),
  );
  await libSettle(tester);
  return (screen: tester.state<BackendScreenState>(find.byType(BackendScreen).last), session: session, project: project);
}

/// 等真实文件读写做完再排版（库的面板每一步都要读写磁盘）。
Future<void> libSettle(WidgetTester tester, {int rounds = 6}) async {
  await settle(tester, rounds: rounds);
  // 还在读盘（转圈）就接着等：读项目里的库要好多步真实读写。
  for (var i = 0; i < 60 && (find.byType(CircularProgressIndicator).evaluate().isNotEmpty || find.text('正在读项目里的库…').evaluate().isNotEmpty); i++) {
    await settle(tester, rounds: 1);
  }
  await tester.pumpAndSettle();
}

/// 读写磁盘的一长串（新建库、复制、导入、拿掉：几十上百步真实读写）：一小步一小步等，等到 [done] 为真为止。
Future<void> libUntil(WidgetTester tester, bool Function() done, {String what = ''}) async {
  for (var i = 0; i < 1500 && !done(); i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 3)));
    await tester.pump(const Duration(milliseconds: 20));
  }
  expect(done(), isTrue, reason: '等了很久也没等到：$what');
  await libSettle(tester, rounds: 3);
}

Finder lk(String key) => find.byKey(ValueKey(key));

/// 把最上面那张面板滚到看得见 [key]（面板是按需搭的，滚不到的那几行还不存在）。
Future<void> libSee(WidgetTester tester, String key) async {
  final f = lk(key);
  if (f.evaluate().isNotEmpty) return;
  await tester.scrollUntilVisible(
    f,
    120,
    scrollable: find.descendant(of: find.byType(BottomSheet).last, matching: find.byType(Scrollable)).first,
  );
  await tester.pumpAndSettle();
}

Future<void> libTap(WidgetTester tester, String key) async {
  final f = lk(key);
  if (f.hitTestable().evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      f,
      120,
      scrollable: find.descendant(of: find.byType(BottomSheet).last, matching: find.byType(Scrollable)).first,
    );
    await tester.ensureVisible(f);
    await tester.pumpAndSettle();
  }
  await tester.tap(f);
  await libSettle(tester, rounds: 3);
}

/// 在弹出的输入框里填字并点“确定”。
Future<void> libType(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField).last, text);
  await tester.tap(find.text('确定').last);
  await libSettle(tester, rounds: 3);
}
