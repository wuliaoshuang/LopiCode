// 改动对比、步骤行的 +/−、“这次改过的文件”清单、确认卡里的预览：390×844 浅色 + 深色各渲染一遍（不能有异常或溢出），并走关键操作。
//   LOPI_SHOTS=1 flutter test test/diff_ui_test.dart   # 同时写截图到 docs/screenshots/
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/agent/agent_tools.dart';
import 'package:lopicode/agent/line_diff.dart';
import 'package:lopicode/agent/usage.dart';
import 'package:lopicode/core/project_store.dart';
import 'package:lopicode/core/templates.dart';
import 'package:lopicode/project_session.dart';
import 'package:lopicode/session/chat_rows.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/changed_files.dart';
import 'package:lopicode/ui/chat_cards.dart';
import 'package:lopicode/ui/chat_row_view.dart';
import 'package:lopicode/ui/diff_view.dart';
import 'package:lopicode/ui/project_shell.dart';
import 'package:lopicode/ui/step_diff.dart';
import 'package:material_ui/material_ui.dart';

import 'agent_test.dart' show RecordingRunner;
import 'agent_ui_test.dart' show waitReal;
import 'screens_test.dart' show shot, fontsLoaded;
import 'session_system_test.dart' show RoutingClient, Turn, reply, use;
import 'support/harness.dart';

FileChange ch(String path, String? before, String? after) =>
    diffFileChange(path, kind: before == null ? ChangeKind.created : (after == null ? ChangeKind.deleted : ChangeKind.modified), before: before, after: after).slim;

const String kOldDart = '''
import 'package:flutter/material.dart';

class Counter extends StatefulWidget {
  const Counter({super.key});

  @override
  State<Counter> createState() => _CounterState();
}

class _CounterState extends State<Counter> {
  int _count = 0;

  void _add() {
    setState(() => _count++);
  }

  @override
  Widget build(BuildContext context) {
    return Text('\$_count');
  }
}
''';

final String kNewDart = kOldDart
    .replaceFirst('  int _count = 0;\n', '  int _count = 0;\n  int _step = 1; // 每次加多少，长一点的注释用来看横向滚动：这一行在手机上放不下，要能左右滑动才看得全\n')
    .replaceFirst('setState(() => _count++);', 'setState(() => _count += _step);')
    .replaceFirst("return Text('\$_count');", "return Text('计数：\$_count');");

final FileChange kEdit = ch('lib/widgets/counter.dart', kOldDart, kNewDart);
final FileChange kCreated = ch('lib/theme/dark.css', null, 'body.dark {\n  background: #111;\n  color: #eee;\n}\n');
final FileChange kDeleted = ch('old/legacy.js', 'var a = 1;\nvar b = 2;\nconsole.log(a + b);\n', null);
const FileChange kBinary = FileChange(path: 'assets/logo.png', kind: ChangeKind.modified, note: '原文件是二进制文件，没有生成对比');

String args(Map<String, dynamic> a) => jsonEncode(a);

final List<ChatItem> kTurn = [
  const UserItem('计数器每次加的步长做成可配置的，再加一份深色样式'),
  const AssistantItem('我先看一下计数器。'),
  const ToolItem('c1', 'read_file', '{"path":"lib/widgets/counter.dart"}', result: kOldDart),
  ToolItem(
    'c2',
    'edit_file',
    args({'path': 'lib/widgets/counter.dart', 'old_text': 'int _count = 0;', 'new_text': 'int _count = 0;\nint _step = 1;'}),
    result: '已修改 lib/widgets/counter.dart：替换了 1 处（精确匹配），改动在第 12–13 行，+3 −2 行。',
    change: kEdit,
  ),
  ToolItem('c3', 'write_file', args({'path': 'lib/theme/dark.css', 'content': 'body.dark {}'}), result: '已写入 lib/theme/dark.css（52 字符）', change: kCreated),
  ToolItem(
    'c4',
    'edit_file',
    args({'path': 'lib/main.dart', 'old_text': 'runApp(const App());', 'new_text': 'runApp(const App(dark: true));'}),
    result: '错误：在文件里没有找到 old_text（精确匹配、忽略行首尾空白、首末行锚点都试过），文件没有改动。',
    ok: false,
  ),
  ToolItem('c5', 'write_file', args({'path': 'assets/logo.png', 'content': 'x'}), result: '已写入 assets/logo.png（1 字符）', change: kBinary),
  const AssistantItem('步长做成了 _step，深色样式在 lib/theme/dark.css。'),
  ChangedFilesItem([kBinary, kCreated, kEdit, kDeleted]),
  UsageItem(TurnUsage()),
];

void main() {
  setUpAll(() async => fontsLoaded = await loadRealFonts());

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    final suffix = mode == ThemeMode.light ? 'light' : 'dark';
    late TestEnv env;

    Future<void> bootEnv(WidgetTester tester, {Turn? turn}) async {
      usePhoneViewport(tester);
      await tester.runAsync(() async => env = await TestEnv.create(chatClient: turn == null ? null : () => RoutingClient(turn, [])));
      addTearDown(() => env.dispose());
    }

    Future<void> showRows(WidgetTester tester, List<ChatItem> items, {bool busy = false, List<Widget> below = const []}) async {
      await tester.pumpWidget(
        appFor(
          env,
          Scaffold(
            body: SafeArea(
              child: Column(
                children: [
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.all(Space.x4),
                      children: [for (final row in deriveChatRows(items, busy: busy)) ChatRowView(row: row)],
                    ),
                  ),
                  ...below,
                ],
              ),
            ),
          ),
          mode: mode,
          font: kTestFont,
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
    }

    testWidgets('步骤行：改完的写“改 路径 +N −M”，新建写“新建”；没成功的照旧，没有数字 ($suffix)', (tester) async {
      await bootEnv(tester);
      await showRows(tester, kTurn);
      await tester.tap(find.byKey(const ValueKey('step-group-c1')));
      await tester.pumpAndSettle();
      expect(find.text('改 lib/widgets/counter.dart'), findsOneWidget);
      expect(find.text('新建 lib/theme/dark.css'), findsOneWidget);
      expect(find.text('修改 lib/main.dart'), findsOneWidget, reason: '没改成的还是原来的说法');
      expect(find.text('改 assets/logo.png'), findsOneWidget);
      expect(find.descendant(of: find.byKey(const ValueKey('step-stat-c2')), matching: find.text('+3 −2', findRichText: true)), findsOneWidget);
      expect(find.descendant(of: find.byKey(const ValueKey('step-stat-c3')), matching: find.text('+4', findRichText: true)), findsOneWidget);
      expect(find.byKey(const ValueKey('step-stat-c4')), findsNothing);
      expect(find.byKey(const ValueKey('step-stat-c5')), findsNothing, reason: '没有对比就没有数字');
      // 数字的颜色：加号绿、减号红
      final d = mode == ThemeMode.light ? DiffColors.light : DiffColors.dark;
      final stat = tester.widget<RichText>(find.descendant(of: find.byKey(const ValueKey('step-stat-c2')), matching: find.byType(RichText)));
      final colors = <Color?>[];
      stat.text.visitChildren((s) {
        if (s is TextSpan && (s.text ?? '').trim().isNotEmpty) colors.add(s.style?.color);
        return true;
      });
      expect(colors, [d.addFg, d.delFg]);
      await shot(tester, 'ap-edit-step-row-$suffix');
    });

    testWidgets('步骤详情：红绿对比（行号、底色、长行能横向滑）；新建标“新建”；二进制只有说明；整份内容不再重复贴 ($suffix)', (tester) async {
      await bootEnv(tester);
      await showRows(tester, kTurn);
      await tester.tap(find.byKey(const ValueKey('step-group-c1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('step-c2')));
      await tester.pumpAndSettle();
      expect(find.text('改动对比'), findsOneWidget);
      expect(find.byKey(const ValueKey('step-diff')), findsOneWidget);
      expect(find.text('  int _count = 0;'), findsOneWidget, reason: '不变的行');
      expect(find.textContaining('int _step = 1;'), findsOneWidget);
      expect(find.text('    setState(() => _count++);'), findsOneWidget);
      expect(find.textContaining('省略'), findsWidgets, reason: '隔得远的不变行不显示');
      // 增 / 删的底色
      final d = mode == ThemeMode.light ? DiffColors.light : DiffColors.dark;
      Color bgOf(Finder text) => tester.widget<ColoredBox>(find.ancestor(of: text, matching: find.byType(ColoredBox)).first).color;
      expect(bgOf(find.textContaining('int _step = 1;')), d.addBg);
      expect(bgOf(find.text('    setState(() => _count++);')), d.delBg);
      // 等宽字体
      expect(tester.widget<Text>(find.textContaining('int _step = 1;')).style?.fontFamily, kMonoFont);
      // 行号：删的那行是旧文件的 14，增的那行是新文件的 15
      final delRow = find.ancestor(of: find.text('    setState(() => _count++);'), matching: find.byType(Row)).first;
      expect(find.descendant(of: delRow, matching: find.text('14')), findsOneWidget);
      // 长行：不折行，整块能横向滑
      final scroll = tester.state<ScrollableState>(find.descendant(of: find.byKey(const ValueKey('diff-scroll')), matching: find.byType(Scrollable)));
      expect(scroll.position.maxScrollExtent, greaterThan(100));
      await shot(tester, 'ap-edit-diff-view-$suffix');
      await tester.drag(find.byKey(const ValueKey('diff-scroll')), const Offset(-200, 0));
      await tester.pumpAndSettle();
      expect(scroll.position.pixels, greaterThan(100));
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const ValueKey('step-c2')));
      await tester.pumpAndSettle();

      // 新建
      await tester.tap(find.byKey(const ValueKey('step-c3')));
      await tester.pumpAndSettle();
      expect(find.text('改动对比 · 新建'), findsOneWidget);
      expect(find.text('body.dark {'), findsOneWidget);
      expect(find.text('写入的内容'), findsNothing, reason: '有对比就不再贴整份内容');
      await shot(tester, 'ap-edit-diff-created-$suffix');
      await tester.tap(find.byKey(const ValueKey('step-c3')));
      await tester.pumpAndSettle();

      // 二进制：只有说明
      await tester.ensureVisible(find.byKey(const ValueKey('step-c5')));
      await tester.tap(find.byKey(const ValueKey('step-c5')));
      await tester.pumpAndSettle();
      expect(find.text('原文件是二进制文件，没有生成对比'), findsOneWidget);
      expect(find.byKey(const ValueKey('diff-rows')), findsNothing);
      expect(find.text('写入的内容'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('执行前 / 没执行成的 edit_file：步骤详情里先看到“打算这样改”的预览（没有行号） ($suffix)', (tester) async {
      await bootEnv(tester);
      final a = args({'path': 'lib/main.dart', 'old_text': 'void main() {\n  runApp(const App());\n}', 'new_text': 'void main() {\n  runApp(const App(dark: true));\n}'});
      await showRows(tester, [const UserItem('默认用深色'), ToolItem('p1', 'edit_file', a)], busy: true);
      expect(find.text('修改 lib/main.dart'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('step-p1')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('打算这样改（还没执行）'), findsOneWidget);
      expect(find.byKey(const ValueKey('step-diff-preview')), findsOneWidget);
      expect(find.text('  runApp(const App());'), findsOneWidget);
      expect(find.text('  runApp(const App(dark: true));'), findsOneWidget);
      expect(find.text('执行中…'), findsOneWidget);
      final rows = find.descendant(of: find.byKey(const ValueKey('diff-rows')), matching: find.byType(Text));
      expect(tester.widgetList<Text>(rows).where((t) => RegExp(r'^\d+$').hasMatch(t.data ?? '')), isEmpty, reason: '预览不画行号');
      await shot(tester, 'ap-edit-preview-before-run-$suffix');

      // 没执行成（被拒 / 找不到）：还是能看到它本来想怎么改
      await showRows(tester, [const UserItem('默认用深色'), ToolItem('p2', 'edit_file', a, result: '错误：在文件里没有找到 old_text', ok: false)]);
      await tester.tap(find.byKey(const ValueKey('step-p2')));
      await tester.pumpAndSettle();
      expect(find.text('打算这样改（没有执行）'), findsOneWidget);
      expect(find.text('报错'), findsOneWidget);

      // 参数还没写完整 / 不是 JSON：不崩，照旧显示原文
      await showRows(tester, [const UserItem('默认用深色'), const ToolItem('p3', 'edit_file', '{"path":"lib/main.dart","old_te')], busy: true);
      await tester.tap(find.byKey(const ValueKey('step-p3')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const ValueKey('step-diff-preview')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('对比很长：默认只露 $kDiffCollapsedLines 行，点“显示其余 N 行”才展开 ($suffix)', (tester) async {
      await bootEnv(tester);
      final big = ch('data/list.txt', null, [for (var i = 1; i <= 120; i++) '第 $i 条'].join('\n'));
      await tester.pumpWidget(
        appFor(
          env,
          Scaffold(
            body: SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(Space.x4),
                child: FileChangeBody(change: big),
              ),
            ),
          ),
          mode: mode,
          font: kTestFont,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('第 $kDiffCollapsedLines 条'), findsOneWidget);
      expect(find.text('第 ${kDiffCollapsedLines + 1} 条'), findsNothing);
      expect(find.text('显示其余 ${120 - kDiffCollapsedLines} 行'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const ValueKey('diff-show-all')));
      await tester.tap(find.byKey(const ValueKey('diff-show-all')));
      await tester.pumpAndSettle();
      expect(find.text('第 120 条'), findsOneWidget);
      expect(find.byKey(const ValueKey('diff-show-all')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('“改了 N 个文件”：回复下面一行；点开是清单（新建 / 修改 / 删除、+/−）；点文件看这一轮的合并对比 ($suffix)', (tester) async {
      await bootEnv(tester);
      await showRows(tester, kTurn);
      expect(find.text('改了 4 个文件'), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('changed-files')), matching: find.text('+7 −5', findRichText: true)), findsOneWidget);
      // 在回复下面、用量脚注上面
      final replyY = tester.getBottomLeft(find.textContaining('步长做成了')).dy;
      expect(tester.getTopLeft(find.byKey(const Key('changed-files'))).dy, greaterThan(replyY));
      expect(tester.getTopLeft(find.byKey(const Key('turn-footnote'))).dy, greaterThan(tester.getTopLeft(find.byKey(const Key('changed-files'))).dy));
      await shot(tester, 'ap-edit-changed-files-row-$suffix');

      await tester.tap(find.byKey(const Key('changed-files')));
      await tester.pumpAndSettle();
      expect(find.text('这一轮改过的文件'), findsOneWidget);
      expect(find.textContaining('共 4 个'), findsOneWidget);
      for (final (path, label) in [('assets/logo.png', '修改'), ('lib/theme/dark.css', '新建'), ('lib/widgets/counter.dart', '修改'), ('old/legacy.js', '删除')]) {
        final line = find.byKey(ValueKey('changed-file-$path'));
        expect(find.descendant(of: line, matching: find.text(path)), findsOneWidget);
        expect(find.descendant(of: line, matching: find.text(label)), findsOneWidget);
      }
      expect(find.descendant(of: find.byKey(const ValueKey('changed-file-old/legacy.js')), matching: find.text('−3', findRichText: true)), findsOneWidget);
      await shot(tester, 'ap-edit-changed-files-sheet-$suffix');

      await tester.tap(find.byKey(const ValueKey('changed-file-lib/widgets/counter.dart')));
      await tester.pumpAndSettle();
      expect(find.byType(FileDiffPage), findsOneWidget);
      expect(find.text('counter.dart'), findsOneWidget);
      expect(find.text('这一轮：修改'), findsOneWidget);
      expect(find.textContaining('int _step = 1;'), findsOneWidget);
      await shot(tester, 'ap-edit-changed-file-page-$suffix');
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      // 没有对比的文件也能点开，只有说明
      await tester.tap(find.byKey(const ValueKey('changed-file-assets/logo.png')));
      await tester.pumpAndSettle();
      expect(find.text('原文件是二进制文件，没有生成对比'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('路径很长的文件：清单里一行放得下，不溢出 ($suffix)', (tester) async {
      await bootEnv(tester);
      final long = ch('packages/feature_shopping_cart/lib/src/presentation/widgets/cart_item_quantity_stepper.dart', 'a\n', 'b\n');
      await showRows(tester, [
        const UserItem('改'),
        const AssistantItem('好了'),
        ChangedFilesItem([long]),
      ]);
      await tester.tap(find.byKey(const Key('changed-files')));
      await tester.pumpAndSettle();
      expect(find.textContaining('cart_item_quantity_stepper.dart'), findsOneWidget);
      expect(shortPath(long.path).length, lessThanOrEqualTo(34));
      expect(tester.takeException(), isNull);
    });

    testWidgets('确认卡（删除文件）：卡里先能看到会删掉什么，默认收着，点了才展开；按钮照旧 ($suffix)', (tester) async {
      await bootEnv(tester);
      final answers = <String>[];
      await showRows(
        tester,
        const [UserItem('把旧脚本删了')],
        below: [
          ApprovalCard(
            pending: PendingApproval(ApprovalRequest(tool: 'delete_file', title: '删除文件', detail: 'old/legacy.js', preview: kDeleted)),
            onAnswer: (allow, {always = false}) => answers.add('$allow/$always'),
          ),
        ],
      );
      expect(find.text('Agent 想删除文件，要允许吗？'), findsOneWidget);
      expect(find.text('看看会删掉什么'), findsOneWidget);
      expect(find.descendant(of: find.byType(ApprovalPreview), matching: find.text('−3', findRichText: true)), findsOneWidget);
      expect(find.byKey(const ValueKey('approval-preview-body')), findsNothing, reason: '默认不展开，卡片不被撑高');
      expect(find.byType(FilledButton), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('approval-preview-toggle')));
      await tester.pumpAndSettle();
      expect(find.text('console.log(a + b);'), findsOneWidget);
      expect(tester.getSize(find.byKey(const ValueKey('approval-preview-body'))).height, lessThanOrEqualTo(kApprovalPreviewMaxHeight));
      await shot(tester, 'ap-edit-approval-preview-$suffix');
      await tester.tap(find.text('拒绝'));
      await tester.tap(find.text('允许这一次'));
      expect(answers, ['false/false', 'true/false']);

      // 没有预览的确认卡（执行命令）不多出这一行
      await showRows(
        tester,
        const [UserItem('装依赖')],
        below: [
          ApprovalCard(
            pending: PendingApproval(ApprovalRequest(tool: 'run_command', title: '执行命令', detail: 'npm install')),
            onAnswer: (allow, {always = false}) {},
          ),
        ],
      );
      expect(find.byType(ApprovalPreview), findsNothing);
    });

    testWidgets('对话页整条链路：局部修改不出确认卡；做完有 +/− 和“改了 N 个文件”；删文件的确认卡带预览；重新打开都还在 ($suffix)', (tester) async {
      late Project project;
      late ProjectSession session;
      var n = 0;
      await bootEnv(
        tester,
        turn: (m, t) => switch (n++) {
          0 => use('edit_file', {'path': 'notes.txt', 'old_text': '第二行', 'new_text': '第二行（改）\n新加的一行'}),
          1 => use('write_file', {'path': 'dark.css', 'content': 'body.dark {\n  color: #eee;\n}\n'}),
          2 => use('delete_file', {'path': 'old.txt'}),
          _ => reply('都弄好了。'),
        },
      );
      await tester.runAsync(() async {
        project = await env.services.projects.create('我的小站', ProjectTemplate.web);
        File('${project.dir}/notes.txt').writeAsStringSync('第一行\n第二行\n第三行\n');
        File('${project.dir}/old.txt').writeAsStringSync('不要了\n');
        session = ProjectSession(env.services, project)..commandRunnerFactory = RecordingRunner.new;
        await session.loadChat();
      });
      addTearDown(() => session.dispose());
      await tester.pumpWidget(
        appFor(
          env,
          ProjectShell(project: project, session: session),
          mode: mode,
          font: kTestFont,
        ),
      );
      await settle(tester);
      await tester.enterText(find.byType(TextField), '改笔记、加深色样式、删掉旧文件');
      await tester.pump();
      await tester.tap(find.byTooltip('发送'));
      // 前两步（改、写）不出确认卡，直接走到删除才停下
      await waitReal(tester, () => session.pendingApproval != null, what: '删除的确认卡');
      expect(session.pendingApproval!.request.tool, 'delete_file');
      expect(await tester.runAsync(() => File('${project.dir}/notes.txt').readAsString()), '第一行\n第二行（改）\n新加的一行\n第三行\n');
      expect(find.text('看看会删掉什么'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('approval-preview-toggle')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('不要了'), findsOneWidget);
      await shot(tester, 'ap-edit-chat-live-approval-$suffix');
      await tester.tap(find.text('允许这一次'));
      await waitReal(tester, () => !session.agentBusy, what: '这一轮结束');

      Future<void> check() async {
        expect(find.text('改了 3 个文件'), findsOneWidget);
        expect(find.descendant(of: find.byKey(const Key('changed-files')), matching: find.text('+5 −2', findRichText: true)), findsOneWidget);
        await tester.tap(find.textContaining('执行了 3 步'));
        await tester.pumpAndSettle();
        expect(find.text('改 notes.txt'), findsOneWidget);
        expect(find.text('新建 dark.css'), findsOneWidget);
        expect(find.text('删除 old.txt'), findsOneWidget);
        await tester.tap(find.text('改 notes.txt'));
        await tester.pumpAndSettle();
        expect(find.text('改动对比'), findsOneWidget);
        expect(find.text('第二行（改）'), findsOneWidget);
      }

      await check();
      await shot(tester, 'ap-edit-chat-done-$suffix');

      // 重新打开这段对话（从存盘的记录重建）
      await tester.runAsync(() async {
        session.dispose();
        session = ProjectSession(env.services, project)..commandRunnerFactory = RecordingRunner.new;
        await session.loadChat();
      });
      await tester.pumpWidget(
        appFor(
          env,
          ProjectShell(key: UniqueKey(), project: project, session: session),
          mode: mode,
          font: kTestFont,
        ),
      );
      await settle(tester);
      await check();
      expect(tester.takeException(), isNull);
    });
  }
}
