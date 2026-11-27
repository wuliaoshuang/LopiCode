// 新的页面逻辑页的界面测试（390×844）：从搭建页“更多 › 积木逻辑”进来；积木盒里有“页面”库四页和语言核心各页；
// “更多”里有类型与类、模块、积木库；拖事件帽子、建函数、建类、列表状态增删，存盘后页面文件里有 front；
// 旧页面顶栏有“升级到新的页面逻辑…”，点了先问、升了换成新的逻辑页。十套主题各过一遍（冒烟）。
//   LOPI_SHOTS=1 flutter test --no-pub test/lowcode_front_ui_test.dart   # 截图写到 ../preview/front/a3/
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/appearance/theme_builtin.dart';
import 'package:lopicode/backend/backend_block_host.dart';
import 'package:lopicode/backend/backend_lib_doc.dart';
import 'package:lopicode/backend/backend_lib_store.dart';
import 'package:lopicode/backend/backend_model.dart';
import 'package:lopicode/backend/front_doc.dart';
import 'package:lopicode/blocks/block_editor_view.dart';
import 'package:lopicode/core/safe_file.dart';
import 'package:lopicode/core/templates.dart';
import 'package:lopicode/lowcode/builder_screen.dart';
import 'package:lopicode/lowcode/logic_expr.dart';
import 'package:lopicode/lowcode/logic_model.dart';
import 'package:lopicode/lowcode/logic_screen.dart';
import 'package:lopicode/lowcode/model.dart';
import 'package:lopicode/project_session.dart';
import 'package:lopicode/state/themes_state.dart';
import 'package:lopicode/ui/logic_front_screen.dart';
import 'package:material_ui/material_ui.dart';

import 'support/backend_core_samples.dart';
import 'support/backend_func_blocks.dart';
import 'support/backend_lang_blocks.dart';
import 'support/harness.dart' hide call;
import 'support/lib_files.dart';
import 'support/lib_switches.dart';
import 'support/lowcode_builder.dart';
import 'support/page_core_samples.dart';
import 'support/page_front_samples.dart';
import 'support/page_front_samples2.dart';

const String _shots = '../preview/front/a3';

Future<ProjectSession> _open(WidgetTester tester, LcDocument doc, {String? themeId, ThemeMode mode = ThemeMode.light}) async {
  usePhoneViewport(tester);
  late TestEnv env;
  late ProjectSession session;
  await tester.runAsync(() async {
    env = await TestEnv.create();
    if (themeId != null) expect(await env.services.container.read(themesProvider.notifier).select(themeId), isNull);
    final project = await env.services.projects.create('我的小站', ProjectTemplate.lowcode);
    session = ProjectSession(env.services, project);
    File(session.guard.resolve(kLowcodePageFile)).writeAsStringSync(doc.encode());
  });
  addTearDown(() async {
    await pendingWrites();
    session.dispose();
    await env.dispose();
  });
  await tester.pumpWidget(
    appFor(
      env,
      BuilderScreen(key: UniqueKey(), session: session),
      mode: mode,
      font: lbFontsLoaded ? kTestFont : null,
    ),
  );
  await settle(tester, rounds: 6);
  return session;
}

/// 搭建页“更多 › 积木逻辑”。
Future<void> _openLogic(WidgetTester tester) async {
  await tester.tap(find.byTooltip('更多').first);
  await tester.pumpAndSettle();
  await tester.tap(find.text('积木逻辑'));
  await settle(tester, rounds: 6);
}

BeBlockHost _host(WidgetTester tester) => tester.state<BlockEditorViewState>(find.byType(BlockEditorView)).widget.host as BeBlockHost;

void main() {
  // 中途包：带手写代码的库的启用、自己的库直接用宿主接口默认都关着（rules.dart）；这里测的是开着时的样子，每条先打开、测完改回默认。
  libSwitchesOn();
  setUpAll(() async => lbFontsLoaded = await loadRealFonts());

  testWidgets('从零：进新的逻辑页 → 积木盒各页都在 → 帽子、函数、类、列表状态 → 存盘里是新的页面逻辑', (tester) async {
    final session = await _open(tester, LcDocument.starter('测试页'));
    await _openLogic(tester);
    expect(find.byType(LogicFrontScreen), findsOneWidget, reason: '还没有任何逻辑的页面：直接进新的逻辑页');
    expect(find.byType(LogicScreen), findsNothing);
    expect(find.text('页面逻辑'), findsWidgets);
    final host = _host(tester);

    // 积木盒：“页面”库四页排最前，后面是语言核心（含 错误、类型、要等的事）。
    final labels = [for (final c in host.categories) c.label];
    expect(labels.take(4), ['事件', '状态', '控件', '页面']);
    for (final want in ['变量', '运算', '流程', '函数', '文字', '列表', '字典', '错误', '类型', '要等的事']) {
      expect(labels, contains(want), reason: '积木盒里要有「$want」这一页（现在有：$labels）');
    }
    for (final gone in ['请求', '返回', '数据', '网络']) {
      expect(labels, isNot(contains(gone)), reason: '后端才有的「$gone」不该出现在页面逻辑里');
    }
    expect(find.byKey(const ValueKey('bk-palette-tab-lib:lopi/page:事件')), findsOneWidget);
    await lbShot(tester, _shots, 'front-empty');

    // 更多：类型与类、模块、积木库
    await tester.tap(find.byKey(const ValueKey('lf-more')));
    await tester.pumpAndSettle();
    for (final k in ['be-menu-types', 'be-menu-modules', 'be-menu-libs', 'lf-menu-strict-on']) {
      expect(find.byKey(ValueKey(k)), findsOneWidget, reason: '更多菜单里要有 $k');
    }
    await lbShot(tester, _shots, 'front-menu');
    await tester.tap(find.byKey(const ValueKey('be-menu-types')));
    await settle(tester, rounds: 4);
    expect(find.textContaining('类型与类'), findsWidgets);
    await lbShot(tester, _shots, 'front-types');
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    // 积木库面板开得了（项目里还没有库）
    await tester.tap(find.byKey(const ValueKey('lf-more')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('be-menu-libs')));
    for (var i = 0; i < 200 && find.byKey(const ValueKey('be-lib-new')).evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(find.byKey(const ValueKey('be-libs')), findsOneWidget);
    expect(find.byKey(const ValueKey('be-lib-new')), findsOneWidget);
    await tester.pumpAndSettle();
    await lbShot(tester, _shots, 'front-libs');
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    // 从积木盒点一顶“当〔控件〕被点击”的帽子
    await tester.tap(find.byKey(const ValueKey('bk-palette-tab-lib:lopi/page:事件')));
    await tester.pumpAndSettle();
    final before = host.doc.hats.length;
    final hatItem = find.byWidgetPredicate(
      (w) => w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith('bk-palette-item-') && (w.key! as ValueKey<String>).value.contains('onClick'),
    );
    expect(hatItem, findsOneWidget, reason: '“事件”页里有“当控件被点击”这顶帽子');
    await tester.tap(hatItem);
    await tester.pumpAndSettle();
    expect(host.doc.hats.length, before + 1);
    final hat = host.doc.hats.last;
    expect(hat.op, 'lib:lopi/page#onClick');

    // 挑控件的下拉里是这一页的控件；选“提交”按钮
    final nodes = host.hatSlotOptions(host.scripts.firstWhere((t) => t.id == hat.id), 'node');
    expect(nodes, isNotEmpty);
    final button = nodes.firstWhere((o) => o.label.contains('提交'));
    // 函数、类、列表状态：经宿主放进去（各自的编辑界面是后端那边同一套部件，另有测试）
    final parsed = BeDocument.fromJson(
      frontDoc(
        functions: [
          tfn('f1', '加倍', [tpar('x', tNum)], [ret(op2('*', pm('x'), nm(2)))], returns: tNum),
        ],
        types: [
          typeDef(
            'c1',
            'class',
            '计数器',
            fields: [field('数', tNum, init: nm(0))],
            methods: [
              method('c1m', '加', [tpar('k', tNum)], [setF(me(), '数', op2('+', getF(me(), '数'), pm('k')))]),
            ],
          ),
        ],
      ),
    ).doc;
    host.edit(() {
      hat.args['node'] = button.value;
      host.doc.functions.addAll(parsed.functions);
      host.doc.core.types.addAll(parsed.core.types);
      hat.body.addAll([
        LcBlock.tryParse(let('c', newObj('计数器', [])), 0)!,
        LcBlock.tryParse(
          sendS(vr('c'), '加', [
            call('f1', {'x': nm(2)}),
          ]),
          0,
        )!,
        LcBlock.tryParse(blk(pg('alert'), {'message': toText(getF(vr('c'), '数'))}), 0)!,
      ]);
    });
    await settle(tester, rounds: 4);
    expect([for (final i in host.issues.where((i) => i.isError)) i.message], isEmpty, reason: '这份逻辑应该没有标红');
    expect(labels.length, lessThanOrEqualTo(host.categories.length));
    await lbShot(tester, _shots, 'front-script');

    // 看代码：浏览器里的 JavaScript
    expect(host.codeLanguage, '浏览器里的 JavaScript');
    expect(host.codeText, contains('function lcProgram(lc, lcHost)'));
    expect(host.codeText, contains('f_加倍'));

    // 存盘：页面文件里是新的页面逻辑；空壳处理对得上；导出的网页脚本走新路
    final saved = await lbSaved(tester, session);
    expect(saved.logic.front, isNotNull);
    final front = lcFrontOf(saved.logic)!;
    expect(front.hats.single.args['node'], button.value);
    expect(front.functions.single.look.name, '加倍');
    expect([for (final h in saved.logic.handlers) '${h.event} ${h.target ?? ''}'], ['load ', 'click ${button.value}']);
    late String js;
    await tester.runAsync(() async => js = File(session.guard.resolve('logic.js')).readAsStringSync());
    expect(js, contains('function lcProgram(lc, lcHost)'));
  });

  testWidgets('积木库：前端库和“都行”库能启用、积木进积木盒、用上以后存盘导出走新路；只给后端的库灰掉并写原因；“要等的事”能用', (tester) async {
    final session = await _open(tester, LcDocument.starter('测试页'));
    await tester.runAsync(() async {
      expect(await beLibWriteFolder(session.guard, 'test/page-kit', kPageKitFiles), isNull);
      expect(await beLibWriteFolder(session.guard, 'test/front-kit', kFrontKitFiles), isNull);
      expect(await beLibWriteFolder(session.guard, 'demo/kit', libFilesFromDir('test/fixtures/libs/demo-kit')), isNull);
    });
    await _openLogic(tester);
    final host = _host(tester);
    Future<void> until(bool Function() done, String what) async {
      for (var i = 0; i < 400 && !done(); i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(done(), isTrue, reason: what);
      await tester.pumpAndSettle();
    }

    Future<void> openLibs() async {
      await tester.tap(find.byKey(const ValueKey('lf-more')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('be-menu-libs')));
      await until(() => find.byKey(const ValueKey('be-lib-test/front-kit')).evaluate().isNotEmpty, '积木库面板里列出项目里的库');
    }

    Future<void> useLib(String id) async {
      await tester.ensureVisible(find.byKey(ValueKey('be-lib-$id')));
      await tester.tap(find.byKey(ValueKey('be-lib-$id')));
      await until(() => find.byKey(const ValueKey('be-lib-use')).evaluate().isNotEmpty, '库的详情里有“在这份文档里用它”');
    }

    await openLibs();
    for (final k in ['be-lib-test/page-kit', 'be-lib-demo/kit', 'be-lib-new', 'be-lib-import']) {
      expect(find.byKey(ValueKey(k)), findsOneWidget, reason: k);
    }
    await lbShot(tester, _shots, 'front-libs-list');

    // 只给后端的库：开关灰着，下面写着原因
    await useLib('demo/kit');
    final off = tester.widget<SwitchListTile>(find.byKey(const ValueKey('be-lib-use')));
    expect(off.onChanged, isNull, reason: '只给后端的库在页面逻辑里不能启用');
    expect(find.textContaining('只给后端用的库'), findsWidgets);
    await lbShot(tester, _shots, 'front-libs-backend-only');
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    // 前端库、“都行”库：打开开关
    for (final id in ['test/front-kit', 'test/page-kit']) {
      if (find.byKey(ValueKey('be-lib-$id')).evaluate().isEmpty) await openLibs();
      await useLib(id);
      expect(tester.widget<SwitchListTile>(find.byKey(const ValueKey('be-lib-use'))).onChanged, isNotNull);
      await tester.tap(find.byKey(const ValueKey('be-lib-use')));
      await until(() => host.doc.use(id) != null, '启用 $id');
      if (id == 'test/front-kit') await lbShot(tester, _shots, 'front-libs-on');
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
    }
    while (find.byKey(const ValueKey('be-libs')).evaluate().isNotEmpty) {
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
    }
    await until(() => host.categories.any((c) => c.label == '喊话') && host.categories.any((c) => c.label == '页工具'), '两个库各自在积木盒里有一页（现在有：${[for (final c in host.categories) c.label]}）');

    // 用上库的积木＋“要等的事”里的“等一会儿”
    final button = host.pageCx!.nodes.firstWhere((o) => o.label.contains('提交'));
    host.edit(() {
      host.doc.hats.add(
        BeLibHat(
          id: 'h1',
          op: pg('onClick'),
          args: {'node': button.value},
          body: [
            LcBlock.tryParse(blk('sleep', {'ms': nm(5)}), 0)!,
            LcBlock.tryParse(
              blk('lib:test/front-kit#shout', {
                'text': toText(kit('addTwice', {'x': nm(1), 'step': nm(2)})),
              }),
              0,
            )!,
          ],
        ),
      );
    });
    await settle(tester, rounds: 4);
    expect([for (final i in host.issues.where((i) => i.isError)) i.message], isEmpty, reason: '用了两个库和“等一会儿”，不该有标红');
    expect(host.codeText, contains('function lcProgram(lc, lcHost)'));
    await lbShot(tester, _shots, 'front-libs-used');

    final saved = await lbSaved(tester, session);
    expect([for (final u in saved.logic.uses) u['id']], containsAll(['test/front-kit', 'test/page-kit']));
    late String js;
    await tester.runAsync(() async => js = File(session.guard.resolve('logic.js')).readAsStringSync());
    expect(js, contains('function lcProgram(lc, lcHost)'));
    expect(js, isNot(contains('这一页的逻辑没有导出')));
  });

  testWidgets('旧页面：还是旧的逻辑页，顶栏有“升级到新的页面逻辑…”；升级后换成新的逻辑页，处理一块块换好', (tester) async {
    final doc = LcDocument.starter('测试页');
    final target = doc.root.children.isEmpty ? doc.root.id : doc.root.children.first.id;
    doc.logic.variables.add(LcVariable(name: 'n', type: 'number', initial: 0));
    doc.logic.handlers.add(
      LcHandler(
        id: 'h1',
        event: 'click',
        target: target,
        body: [
          LcBlock(op: 'changeVar', args: {'name': 'n', 'by': exNum(1)}),
          LcBlock(
            op: 'if',
            args: {'cond': exBin('>', exVar('n'), exNum(2))},
            body: [
              LcBlock(
                op: 'alert',
                args: {
                  'message': exJoin([exText('到 '), exVar('n')]),
                },
              ),
            ],
          ),
        ],
      ),
    );
    final oldText = doc.encode();
    final session = await _open(tester, doc);
    await _openLogic(tester);
    expect(find.byType(LogicScreen), findsOneWidget, reason: '有旧处理的页面：还是旧的逻辑页');
    expect(find.byType(LogicFrontScreen), findsNothing);
    expect(find.byKey(const ValueKey('lc-top-upgrade')), findsOneWidget);
    await lbShot(tester, _shots, 'old-with-upgrade');

    // 点升级 → 先问；取消：什么都不变，回到旧的逻辑页
    await tester.tap(find.byKey(const ValueKey('lc-top-upgrade')));
    await settle(tester, rounds: 4);
    expect(find.text('升级到新的页面逻辑'), findsOneWidget);
    expect(find.textContaining('存盘以后不能降回'), findsOneWidget);
    expect(find.textContaining('升级后没有要改的地方'), findsOneWidget);
    await lbShot(tester, _shots, 'upgrade-ask');
    await tester.tap(find.text('取消'));
    await settle(tester, rounds: 4);
    expect(find.byType(LogicScreen), findsOneWidget);
    late String now;
    await tester.runAsync(() async => now = File(session.guard.resolve(kLowcodePageFile)).readAsStringSync());
    expect(now, oldText, reason: '没升级：页面文件一个字不变');

    // 再点升级 → 确认
    await tester.tap(find.byKey(const ValueKey('lc-top-upgrade')));
    await settle(tester, rounds: 4);
    await tester.tap(find.text('升级').last);
    await settle(tester, rounds: 6);
    expect(find.byType(LogicFrontScreen), findsOneWidget, reason: '升级完直接进新的逻辑页');
    final host = _host(tester);
    expect(host.doc.hats.single.op, 'lib:lopi/page#onClick');
    expect(host.doc.hats.single.args['node'], target);
    expect([for (final b in host.doc.hats.single.body) b.op], ['lib:lopi/page#stateSet', 'if']);
    expect([for (final i in host.issues.where((i) => i.isError)) i.message], isEmpty);
    await lbShot(tester, _shots, 'upgraded');
    final saved = await lbSaved(tester, session);
    expect(saved.logic.front, isNotNull);
    expect(saved.logic.handlers.every((h) => h.body.isEmpty), isTrue, reason: '旧处理只剩空壳');
  });

  group('十套主题冒烟', () {
    for (final theme in kBuiltinThemes) {
      testWidgets('${theme.name}：新的逻辑页（有积木）、更多菜单、积木盒“事件”页', (tester) async {
        await _open(tester, frontSampleCore(), themeId: theme.id, mode: theme.dark ? ThemeMode.dark : ThemeMode.light);
        await _openLogic(tester);
        expect(find.byType(LogicFrontScreen), findsOneWidget);
        expect(tester.takeException(), isNull, reason: '${theme.name} 渲染出了异常（溢出也算）');
        await lbShot(tester, _shots, 'theme-${theme.id}-front');
        await tester.tap(find.byKey(const ValueKey('bk-palette-tab-lib:lopi/page:事件')));
        await tester.pumpAndSettle();
        await lbShot(tester, _shots, 'theme-${theme.id}-front-events');
        await tester.tap(find.byKey(const ValueKey('lf-more')));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('be-menu-libs')), findsOneWidget);
        await lbShot(tester, _shots, 'theme-${theme.id}-front-menu');
      });
    }
  });
}
