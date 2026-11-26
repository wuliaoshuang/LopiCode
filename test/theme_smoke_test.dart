// “主要页面 × 全部内置主题”冒烟：每套内置主题下把主要页面各渲染一遍（390×844），不能有异常或溢出。
//   flutter test --no-pub test/theme_smoke_test.dart
//   LOPI_SHOTS=1 flutter test --no-pub test/theme_smoke_test.dart   # 同时出截图
// 截图写到 LOPI_SHOT_DIR（没设就是 .tmp/theme-shots/），文件名 theme-<主题 id>-<页面>.png；不进 git。
//
// 覆盖的页面：聊天页（确认卡、做完的步骤组展开、步骤详情里的命令与报错）、“＋”底部面板、侧边栏、
// 项目列表、新建项目面板、文件页、代码编辑器（查找栏）、终端（16 色都打出来）、后端积木页、看代码面板、
// 低代码编辑器（底部工具条、选中、合一面板、组件盒、图层、长按菜单；第 5 版第 1、2 期）、严格规矩文档的类型标红、设置首页、外观子页、主题列表页、对话框、提示条、
// 主题管理页、主题编辑器、背景图片设置页（2026-11-26 合并后加）。
// 打包页单独在 test/theme_pack_smoke_test.dart（本地打包合进来后状态多了，这个文件放不下）。
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/appearance/theme_builtin.dart';
import 'package:lopicode/backend/backend_model.dart';
import 'package:lopicode/blocks/block_editor_view.dart';
import 'package:lopicode/blocks/block_issue_view.dart';
import 'package:lopicode/core/project_store.dart';
import 'package:lopicode/core/templates.dart';
import 'package:lopicode/lang/types.dart';
import 'package:lopicode/lang/types_json.dart';
import 'package:lopicode/lowcode/logic_model.dart';
import 'package:lopicode/project_session.dart';
import 'package:lopicode/state/themes_state.dart';
import 'package:lopicode/templates/project_templates.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/backdrop_settings_screen.dart';
import 'package:lopicode/ui/backend_screen.dart';
import 'package:lopicode/ui/project_list_screen.dart';
import 'package:lopicode/ui/project_shell.dart';
import 'package:lopicode/ui/settings_pages.dart';
import 'package:lopicode/ui/settings_screen.dart';
import 'package:lopicode/ui/settings_theme.dart';
import 'package:lopicode/ui/shell.dart';
import 'package:lopicode/ui/theme_editor_screen.dart';
import 'package:lopicode/ui/themes_screen.dart';
import 'package:lopicode/ui/widgets.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:re_editor/re_editor.dart';
import 'package:xterm/xterm.dart';

import 'support/backend_func_blocks.dart' as fb;
import 'support/backend_lang_blocks.dart' as bk;
import 'support/harness.dart';
import 'support/runtime_fakes.dart';

final bool writeShots = Platform.environment['LOPI_SHOTS'] == '1';
final String shotDir = Platform.environment['LOPI_SHOT_DIR'] ?? '.tmp/theme-shots';
bool fontsLoaded = false;

/// 一段各类记号都有的 JS：看高亮分不分得开。
const String kDemoJs = r'''// 待办清单：增、删、统计
import { readFile } from 'node:fs/promises';

const MAX_ITEMS = 100;
const pattern = /^\s*[-*]\s+(.+)$/;

/** 一条待办。 */
export class Todo {
  constructor(title, done = false) {
    this.title = title;
    this.done = done;
  }

  toggle() {
    this.done = !this.done;
    return this;
  }
}

async function load(path) {
  const text = await readFile(path, 'utf8');
  const items = [];
  for (const line of text.split('\n')) {
    const m = pattern.exec(line);
    if (m === null) continue;
    items.push(new Todo(m[1], false));
  }
  if (items.length > MAX_ITEMS) {
    throw new Error(`太多了：${items.length} 条`);
  }
  return items;
}

load('todo.md').then((list) => console.log(list.length, true, null));
''';

void main() {
  setUpAll(() async => fontsLoaded = await loadRealFonts());

  for (final theme in kBuiltinThemes) {
    final mode = theme.dark ? ThemeMode.dark : ThemeMode.light;

    Future<void> shot(WidgetTester tester, String page) async {
      expect(tester.takeException(), isNull, reason: '${theme.name} · $page 渲染时出了异常（溢出也算）');
      if (!writeShots || !fontsLoaded) return;
      // 测试环境默认把投影画成一圈实心黑边（debugDisableShadows）；出截图这一下按真机的画法（柔和的投影）重画，截完改回去。
      Future<void> repaint({required bool realShadows}) async {
        debugDisableShadows = !realShadows;
        void mark(RenderObject o) {
          o.markNeedsPaint();
          o.visitChildren(mark);
        }

        tester.binding.renderViews.forEach(mark);
        await tester.pump();
      }

      await repaint(realShadows: true);
      try {
        final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(shotKey));
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 2);
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          File('$shotDir/theme-${theme.id}-$page.png')
            ..parent.createSync(recursive: true)
            ..writeAsBytesSync(data!.buffer.asUint8List());
        });
      } finally {
        await repaint(realShadows: false);
      }
    }

    /// 建环境并选用这套主题。
    Future<TestEnv> makeEnv(WidgetTester tester, {Future<TestEnv> Function()? create}) async {
      usePhoneViewport(tester);
      late TestEnv env;
      await tester.runAsync(() async {
        env = create == null ? await TestEnv.create() : await create();
        final failed = await env.services.container.read(themesProvider.notifier).select(theme.id);
        expect(failed, isNull);
      });
      return env;
    }

    Future<(TestEnv, Project, ProjectSession)> open(
      WidgetTester tester,
      ProjectTemplate template, {
      String? language,
      Future<TestEnv> Function()? create,
      void Function(Project)? before,
      bool fakePty = false,
    }) async {
      final env = await makeEnv(tester, create: create);
      late Project project;
      late ProjectSession session;
      await tester.runAsync(() async {
        project = await createProjectFromTemplate(env.services.projects, '我的小站', template, language: language);
        before?.call(project);
        session = ProjectSession(env.services, project);
        if (fakePty) {
          session.ptySpawner = (exe, {required workingDirectory, required environment, required rows, required columns}) => FakePty();
        }
        await session.loadChat();
        await Future<void>.delayed(const Duration(milliseconds: 150));
      });
      addTearDown(() async {
        await tester.runAsync(() async {
          session.dispose();
          await env.dispose();
        });
      });
      return (env, project, session);
    }

    Future<void> show(WidgetTester tester, TestEnv env, Widget home, {int rounds = 8}) async {
      await tester.pumpWidget(appFor(env, home, mode: mode, font: kTestFont));
      await settle(tester, rounds: rounds);
    }

    group('${theme.name}（${theme.id}）', () {
      testWidgets('这套主题真的用上了：页面底色、强调色是它的', (tester) async {
        final env = await makeEnv(tester);
        addTearDown(() => tester.runAsync(env.dispose));
        late AppColors colors;
        late ThemeSpec spec;
        await show(
          tester,
          env,
          Builder(
            builder: (context) {
              colors = context.colors;
              spec = context.themeSpec;
              return const Scaffold(body: SizedBox.shrink());
            },
          ),
          rounds: 2,
        );
        expect(spec.id, theme.id);
        expect(colors.accent, theme.uiColor(UiKey.accent));
        expect(colors.canvas, theme.uiColor(UiKey.canvas));
        expect(Theme.of(tester.element(find.byType(Scaffold).last)).brightness, theme.dark ? Brightness.dark : Brightness.light);
      });

      testWidgets('聊天页：确认卡、做完的步骤、步骤详情；“＋”面板；侧边栏', (tester) async {
        final (env, project, session) = await open(
          tester,
          ProjectTemplate.web,
          create: () => TestEnv.create(
            chatClient: () => ScriptedChatClient([
              [say('好的，我先看看项目里有什么。'), call(0, 'list_files', '{}')],
              [
                say('我来加一个深色主题的样式，然后跑一下检查。'),
                call(0, 'write_file', '{"path":"dark.css","content":"body.dark {\\n  background: #111;\\n  color: #eee;\\n}\\n"}'),
                call(1, 'run_command', '{"command":"ls -la"}'),
              ],
              [say('已经加好 dark.css。在 index.html 里引入它就能生效；点右上角的按钮可以切换。')],
            ]),
          ),
        );
        await show(tester, env, ProjectShell(project: project, session: session, initial: ShellDest.chat));
        await shot(tester, 'chat-empty');

        await tester.tap(find.byKey(const ValueKey('plus-button')));
        await settle(tester, rounds: 3);
        expect(find.byKey(const ValueKey('plus-plan')), findsOneWidget);
        await shot(tester, 'sheet');
        await tester.tapAt(const Offset(195, 60));
        await settle(tester, rounds: 3);

        await tester.tap(find.byTooltip('打开侧边栏'));
        await settle(tester, rounds: 3);
        await shot(tester, 'drawer');
        await tester.tapAt(const Offset(370, 400));
        for (var i = 0; i < 12; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }

        late Future<void> sending;
        await tester.runAsync(() async {
          sending = session.sendToAgent('帮我加一个深色主题');
          for (var i = 0; i < 40 && session.pendingApproval == null; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 50));
          }
        });
        await settle(tester, rounds: 3);
        expect(session.pendingApproval, isNotNull);
        expect(find.text('允许这一次'), findsOneWidget);
        await shot(tester, 'chat-approval');

        await tester.tap(find.text('允许这一次'));
        await tester.runAsync(() => sending.timeout(const Duration(seconds: 20)));
        await settle(tester, rounds: 3);
        expect(find.textContaining('已经加好 dark.css'), findsOneWidget);
        // 展开步骤组，再点开“写入 dark.css”看参数（代码块）。
        final summary = find.textContaining('执行了');
        if (summary.evaluate().isNotEmpty) {
          await tester.tap(summary.first);
          await tester.pumpAndSettle();
          final write = find.text('写入 dark.css');
          if (write.evaluate().isNotEmpty) {
            await tester.tap(write.first);
            await tester.pumpAndSettle();
          }
        }
        await shot(tester, 'chat');
      });

      testWidgets('项目列表、新建项目面板；对话框；提示条', (tester) async {
        final env = await makeEnv(tester);
        addTearDown(() => tester.runAsync(env.dispose));
        await tester.runAsync(() async {
          await env.services.projects.create('个人主页', ProjectTemplate.web);
          await env.services.projects.create('活动报名页', ProjectTemplate.lowcode);
          await env.services.projects.create('脚本练习', ProjectTemplate.empty);
        });
        await show(tester, env, ProjectListScreen(onOpen: (_) {}), rounds: 40);
        expect(find.text('个人主页'), findsOneWidget);
        await shot(tester, 'projects');

        final context = tester.element(find.byType(ProjectListScreen));
        // 对话框（危险操作那种，确认按钮是红的）。
        final answer = confirmDialog(context, title: '删除“个人主页”？', message: '项目里的所有文件和对话记录都会被删除，无法恢复。', confirmLabel: '删除', danger: true);
        await tester.pumpAndSettle();
        expect(find.text('删除“个人主页”？'), findsOneWidget);
        await shot(tester, 'dialog');
        await tester.tap(find.text('取消'));
        await tester.pumpAndSettle();
        expect(await answer, isFalse);

        // 提示条。
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已复制到剪贴板')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 800));
        expect(find.text('已复制到剪贴板'), findsOneWidget);
        await shot(tester, 'snack');
        ScaffoldMessenger.of(context).clearSnackBars();
        await tester.pumpAndSettle();

        // 新建项目面板（底部面板）。
        await tester.tap(find.byTooltip('添加工作区').evaluate().isNotEmpty ? find.byTooltip('添加工作区').first : find.byType(FloatingActionButton).first);
        await settle(tester, rounds: 3);
        if (find.text('新建项目').evaluate().isNotEmpty) {
          await tester.tap(find.text('新建项目'));
          await settle(tester, rounds: 3);
        }
        await shot(tester, 'new-project');
      });

      testWidgets('文件页、代码编辑器（高亮、查找栏）', (tester) async {
        final (env, project, session) = await open(tester, ProjectTemplate.web, before: (project) => File(p.join(project.dir, 'todo.js')).writeAsStringSync(kDemoJs));
        await show(tester, env, ProjectShell(project: project, session: session, initial: ShellDest.files), rounds: 20);
        expect(find.text('todo.js'), findsWidgets);
        await shot(tester, 'files');
        await tester.tap(find.text('todo.js').first);
        await settle(tester, rounds: 20, ms: 5);
        expect(tester.widget<CodeEditor>(find.byType(CodeEditor)).controller!.text, contains('class Todo'));
        await shot(tester, 'code');

        await tester.tap(find.byTooltip('编辑器菜单'));
        await settle(tester, rounds: 3);
        await shot(tester, 'editor-menu');
        await tester.tap(find.text('查找并替换'));
        await settle(tester, rounds: 3);
        await tester.enterText(find.byKey(const Key('find-input')), 'items');
        await settle(tester, rounds: 6);
        await shot(tester, 'code-find');
      });

      testWidgets('终端：16 色都打出来', (tester) async {
        final (env, project, session) = await open(tester, ProjectTemplate.web);
        await show(tester, env, ProjectShell(project: project, session: session, initial: ShellDest.terminal));
        await tester.runAsync(() async {
          session.terminals[session.activeTerminal].run('ls');
          await Future<void>.delayed(const Duration(milliseconds: 600));
        });
        const names = ['黑', '红', '绿', '黄', '蓝', '紫', '青', '白'];
        final out = StringBuffer('\r\n');
        for (var i = 0; i < 8; i++) {
          out.write('\x1b[3${i}m${names[i]} normal \x1b[9${i}m亮${names[i]} bright\x1b[0m\r\n');
        }
        out.write('\x1b[1m粗体\x1b[0m \x1b[7m 反色 \x1b[0m \x1b[42;30m 绿底 \x1b[0m \x1b[41;97m 红底 \x1b[0m\r\n');
        session.terminals[session.activeTerminal].terminal.write(out.toString());
        await settle(tester, rounds: 2);
        expect(find.byType(TerminalView), findsOneWidget);
        await shot(tester, 'terminal');
      });

      testWidgets('后端积木页：整页、单个接口近看、看代码面板', (tester) async {
        final (env, project, session) = await open(tester, ProjectTemplate.backendBlocks, language: 'node', fakePty: true);
        await show(tester, env, ProjectShell(project: project, session: session, initial: ShellDest.builder));
        expect(find.byType(BackendScreen), findsOneWidget);
        expect(find.byKey(const ValueKey('bk-canvas')), findsOneWidget);
        await shot(tester, 'blocks');

        await tester.tap(find.byKey(const ValueKey('bk-code')));
        await tester.pumpAndSettle();
        await shot(tester, 'codeview');
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const ValueKey('be-more')));
        await tester.pumpAndSettle();
        await shot(tester, 'blocks-menu');
      });

      testWidgets('后端积木页 · 严格规矩的文档：类型问题标红、点角标出小卡和修法按钮', (tester) async {
        final (env, project, session) = await open(
          tester,
          ProjectTemplate.backendBlocks,
          language: 'node',
          fakePty: true,
          before: (project) {
            // 一份带类型问题的文档（规矩版本 2）：参数要整数给了文字、要文字给了整数、条件位放了整数。
            final file = File(p.join(project.dir, kBackendFileName));
            final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
            json['rules'] = 2;
            json['functions'] = [
              fb.fnDef(
                'f1',
                '加倍',
                [
                  {'name': 'x', 'type': lTypeToJson(LType.integer)},
                ],
                [fb.ret(bk.op2('*', fb.pm('x'), bk.nm(2)))],
              ),
              fb.fnDef(
                'f2',
                '喊',
                [
                  {'name': '话', 'type': lTypeToJson(LType.text)},
                ],
                [fb.ret(fb.pm('话'))],
              ),
            ];
            json['routes'] = [
              bk.route('r1', 'GET', '/a', [
                bk.let('total', fb.call('f1', {'x': bk.tx('12')})),
                bk.let('b', fb.call('f2', {'话': bk.nm(3)})),
                bk.iff(bk.nm(1), [bk.json(bk.vr('total'))], noElse: true),
                bk.json(bk.nm(1)),
              ]),
            ];
            file.writeAsStringSync(jsonEncode(json));
          },
        );
        await show(tester, env, ProjectShell(project: project, session: session, initial: ShellDest.builder));
        final editor = tester.state<BlockEditorViewState>(find.byType(BlockEditorView));
        await tester.drag(find.byKey(const ValueKey('bk-palette-grip')), const Offset(0, 300), warnIfMissed: false);
        await tester.pumpAndSettle();
        editor.jumpTo('r1', const []);
        await tester.pumpAndSettle();
        editor.select(null);
        await tester.pumpAndSettle();
        final host = tester.state<BackendScreenState>(find.byType(BackendScreen)).host!;
        expect(host.issues.where((i) => i.rule.startsWith('T')), hasLength(3), reason: '三处类型问题都标出来了');
        await shot(tester, 'blocks-type-marks');

        // 点第 1 块的角标：小卡（提示语、编号、修法按钮）。
        final placed = editor.layout.placed('r1')!;
        final block = placed.layout.blockAt([lcStep(0)])!;
        await tester.tapAt(editor.globalOf(editor.toView(placed.origin + bkIssueBadgeCenter(block, editor.kit.metrics))));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('bk-issue-card')), findsOneWidget);
        await shot(tester, 'blocks-type-card');
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();

        // 问题列表（每条带修法按钮）。
        await tester.tap(find.byKey(const ValueKey('bk-issues')));
        await tester.pumpAndSettle();
        await shot(tester, 'blocks-type-list');
      });

      testWidgets('低代码编辑器：画布与底部工具条、选中、合一面板、组件盒、图层、长按菜单', (tester) async {
        final (env, project, session) = await open(tester, ProjectTemplate.lowcode);
        await show(tester, env, ProjectShell(project: project, session: session, initial: ShellDest.builder));
        Finder key(String k) => find.byKey(ValueKey(k));
        Future<void> back() async {
          await tester.binding.handlePopRoute();
          await tester.pumpAndSettle();
          await settle(tester, rounds: 2);
        }

        expect(key('lc-tool-add'), findsOneWidget, reason: '底部工具条在');
        await shot(tester, 'lowcode');

        // 选中“提交”按钮：选中框、尺寸标签、工具条换成选中后的那一排。
        await tester.tap(key('lowcode-node-n5'), warnIfMissed: false);
        await settle(tester, rounds: 2);
        await shot(tester, 'lowcode-selected');

        // 合一面板：常用页、样式页。
        await tester.tap(find.text('常用').last);
        await tester.pumpAndSettle();
        expect(key('lc-inspector'), findsOneWidget);
        await shot(tester, 'lowcode-props');
        await tester.tap(key('lc-page-style'));
        await tester.pumpAndSettle();
        await shot(tester, 'lowcode-style');
        await back();
        expect(key('lc-inspector'), findsNothing);

        // 组件盒。
        await tester.tap(key('lc-tool-add'));
        await tester.pumpAndSettle();
        expect(key('palette-search'), findsOneWidget);
        await shot(tester, 'lowcode-palette');
        await tester.tap(find.byTooltip('关闭组件盒').last);
        await tester.pumpAndSettle();

        // 图层面板。
        await tester.tap(find.byTooltip('图层').last);
        await tester.pumpAndSettle();
        expect(key('lc-layer-n5'), findsOneWidget);
        await shot(tester, 'lowcode-layers');
        await back();

        // 长按菜单（按住不挪就松手）。
        final g = await tester.startGesture(tester.getCenter(key('lowcode-node-n5')));
        await tester.pump(const Duration(milliseconds: 340));
        await tester.pump();
        await g.up();
        await tester.pumpAndSettle();
        expect(find.text('复制'), findsWidgets);
        await shot(tester, 'lowcode-node-menu');
        await back();
      });

      // 打包页（本地表单、进行中、成功、失败、不适用、钥匙页、两种远程方式）在 test/theme_pack_smoke_test.dart。

      testWidgets('设置首页、外观子页、主题列表页', (tester) async {
        final env = await makeEnv(tester);
        addTearDown(() => tester.runAsync(env.dispose));
        await show(tester, env, const SettingsScreen(), rounds: 4);
        expect(find.text('设置'), findsWidgets);
        await shot(tester, 'settings');

        await show(tester, env, const AppearanceScreen(), rounds: 3);
        expect(tester.widget<Text>(find.byKey(Key(theme.dark ? 'appearance-theme-dark-value' : 'appearance-theme-light-value'))).data, theme.name);
        await shot(tester, 'appearance');
        await tester.tap(find.byKey(Key(theme.dark ? 'appearance-theme-dark' : 'appearance-theme-light')));
        await tester.pumpAndSettle();
        expect(find.byType(ThemePickScreen), findsOneWidget);
        for (final t in kBuiltinThemes.where((t) => t.dark == theme.dark)) {
          expect(find.byKey(Key('theme-pick-${t.id}')), findsOneWidget, reason: '${t.name} 在列表里');
        }
        await shot(tester, 'theme-pick');
      });

      testWidgets('主题管理页、主题编辑器（各预览块、一项颜色的取色面板）、背景图片设置页', (tester) async {
        final env = await makeEnv(tester);
        addTearDown(() => tester.runAsync(env.dispose));
        await show(tester, env, const ThemesScreen(), rounds: 4);
        await tester.scrollUntilVisible(
          find.byKey(Key('themes-card-${theme.id}')),
          200,
          scrollable: find.descendant(of: find.byKey(const Key('themes-list')), matching: find.byType(Scrollable)).first,
        );
        expect(find.byKey(Key('themes-inuse-${theme.id}')), findsOneWidget, reason: '${theme.name} 在管理页里，标着“正在使用”');
        await shot(tester, 'themes');

        // 编辑器：内置主题进来是只读，照样把预览和字段列表都渲染出来
        await show(tester, env, ThemeEditorScreen(theme: theme), rounds: 4);
        expect(find.byKey(const Key('theme-editor-list')), findsOneWidget);
        await shot(tester, 'editor');
        for (final (label, kind) in [('代码', 'code'), ('积木', 'blocks'), ('搭建', 'lowcode'), ('终端', 'terminal')]) {
          await tester.tap(find.descendant(of: find.byKey(const Key('theme-preview-kind')), matching: find.text(label)));
          await tester.pumpAndSettle();
          expect(find.byKey(Key('theme-preview-$kind')), findsOneWidget);
          await shot(tester, 'editor-$kind');
        }

        await show(tester, env, const BackdropSettingsScreen(), rounds: 6);
        expect(find.byKey(const Key('bg-settings-list')), findsOneWidget);
        await shot(tester, 'backdrop-settings');
      });
    });
  }
}
