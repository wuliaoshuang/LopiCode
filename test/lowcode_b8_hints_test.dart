// 第四轮 B8：搭建台里其余的提示条，逐句点出来——每一句都得：看得见、点得到（没被面板、弹层挡住）、整条在工具条上面、
// 不盖撤销重做（support/lowcode_builder.dart 的 lbHintAbove）。
// 这里点的：长按菜单“复制”、多选“下移”到头、库里的组件“存进库…”、导出 Flutter 代码写不进去、从相册选图的三种失败、
// 新建页面失败、编辑组件页里的“复制”和“现在改的是变体…”、“跟状态同步”选了不是状态本身的东西。
// 别的几句加在它们原来的测试里（底部导航 / 顶栏共用与取消共用、不在这页显示、换页、保存失败、多选复制）；
// 多选跨层、多选上移到头、类名起了不能用的名字在 lowcode_b7_hints_test.dart。
// 截图时把“测试里投影画成实心黑边”关掉（见 docs/api-notes.md “debugDisableShadows”），看到的才是手机上的样子。
library;

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/core/path_guard.dart';
import 'package:lopicode/core/safe_file.dart';
import 'package:lopicode/core/templates.dart';
import 'package:lopicode/lowcode/bind_model.dart';
import 'package:lopicode/lowcode/builder_screen.dart';
import 'package:lopicode/lowcode/comp_lib_builtin.dart';
import 'package:lopicode/project_session.dart';
import 'package:lopicode/ui/chat_panels.dart';
import 'package:material_ui/material_ui.dart';

import 'support/b8_ui.dart';
import 'support/bind_sample.dart';
import 'support/comp_samples.dart';
import 'support/harness.dart';
import 'support/lowcode_builder.dart';

/// 测试环境把投影画成实心色块（debugDisableShadows）：拍照前按真机的画法重画一遍，拍完改回去。
/// 光改开关不够——已经画好的那一层不会自己重画，要挨个叫它们重画。
Future<void> _shot(WidgetTester tester, String name) async {
  void repaintAll() {
    void visit(RenderObject o) {
      o.markNeedsPaint();
      o.visitChildren(visit);
    }

    tester.binding.renderViews.forEach(visit);
  }

  debugDisableShadows = false;
  try {
    repaintAll();
    await tester.pump();
    await lbShot(tester, b8ShotDir, name);
  } finally {
    debugDisableShadows = true;
    repaintAll();
    await tester.pump();
  }
}

Future<void> _longMenu(WidgetTester tester, String id, String label) async {
  await b8LongPress(tester, lbNode(id));
  await b8TapText(tester, label);
}

void main() {
  setUpAll(() async => lbFontsLoaded = await loadRealFonts());

  testWidgets('画布上的几句：长按“复制”、多选“下移”到头、库里的组件“存进库…”、导出 Flutter 代码写不进去', (tester) async {
    final page = b8Page([
      b8Node('a', 'text', {'text': '甲'}),
      b8Node('b', 'button', {'text': '乙'}),
      b8Node('st', 'component', {'ref': lcBuiltinDefId('stepper')}),
    ]);
    expect(lcEnsureBuiltin(page, lcBuiltinDefId('stepper')), isTrue);
    final s = await lbOpen(tester, doc: page);
    await _longMenu(tester, 'a', '复制');
    lbHintAbove(tester, '已复制，长按别的组件可以“粘贴到它后面”');
    await _shot(tester, 'b8-hint-copy');
    await b8HintGone(tester);

    // 多选最后两个，下移：已经在最后面了
    await _longMenu(tester, 'b', '多选');
    await b8Tap(tester, lbNode('st'));
    await b8Tap(tester, lbKey('lc-multi-more'));
    await b8TapText(tester, '下移');
    lbHintAbove(tester, '已经在最后面了');
    await b8HintGone(tester);
    await b8Tap(tester, lbKey('lc-multi-done'));

    // 库里来的组件：更多操作 › 存进库…
    await b8Tap(tester, lbNode('st'));
    await b8Tap(tester, find.byTooltip('更多操作'));
    await b8Tap(tester, find.widgetWithText(PopupMenuItem<String>, '存进库…'));
    lbHintAbove(tester, '它本来就是库「');
    await _shot(tester, 'b8-hint-already-lib');
    await b8HintGone(tester);

    // 导出 Flutter 代码：项目里 export 是个文件，目录建不出来
    await tester.runAsync(() async => File(s.guard.resolve('export')).writeAsStringSync('占位'));
    await b8Menu(tester, '导出 Flutter 代码');
    await b8Until(tester, find.textContaining('写入 export/page.dart 失败：'), '写不进去的提示');
    lbHintAbove(tester, '写入 export/page.dart 失败：');
    await _shot(tester, 'b8-hint-export-failed');
    expect(tester.takeException(), isNull);
  });

  testWidgets('从相册选图的三种失败：存不进项目（系统说的原因）、路径不让写、相册打不开——提示盖在面板上面看得见', (tester) async {
    await lbOpen(
      tester,
      doc: b8Page([
        b8Node('img', 'image', {'src': '', 'height': 120}),
      ]),
    );
    addTearDown(() => pickImagesOverride = null);
    await b8Tap(tester, lbNode('img'));
    await lbOpenCommon(tester);
    final cases = <(Exception, String)>[
      (const FileSystemException('写不了', 'assets/x.png', OSError('No space left on device', 28)), '图片存不进项目：No space left on device'),
      (PathGuardException('这个位置不在项目里'), '图片存不进项目：这个位置不在项目里'),
      (PlatformException(code: 'no_gallery', message: '没有相册'), '打不开相册：'),
    ];
    for (final (error, text) in cases) {
      pickImagesOverride = ({required bool camera}) async => throw error;
      await lbTapShown(tester, lbKey('lc-common-src-gallery'));
      await b8Until(tester, find.textContaining(text), text);
      await settle(tester, rounds: 6); // 等提示条滑进来停稳
      lbHintAbove(tester, text);
      if (error is FileSystemException) await _shot(tester, 'b8-hint-image-failed');
      await b8HintGone(tester);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('新建页面失败：说出原因（这时还没有工具条，提示在屏幕里、点得到）', (tester) async {
    usePhoneViewport(tester);
    late TestEnv env;
    late ProjectSession a;
    await tester.runAsync(() async {
      env = await TestEnv.create();
      a = ProjectSession(env.services, await env.services.projects.create('项目甲', ProjectTemplate.lowcode));
      // 页面文件没了、index.html 是个目录：新建时写不进去
      File(a.guard.resolve(kLowcodePageFile)).deleteSync();
      final html = File(a.guard.resolve('index.html'));
      if (html.existsSync()) html.deleteSync();
      Directory(html.path).createSync();
    });
    addTearDown(() async {
      await pendingWrites();
      a.dispose();
      await env.dispose();
    });
    await tester.pumpWidget(
      appFor(
        env,
        BuilderScreen(key: UniqueKey(), session: a),
        font: lbFontsLoaded ? kTestFont : null,
      ),
    );
    await settle(tester, rounds: 6);
    await b8Tap(tester, find.widgetWithText(FilledButton, '新建页面'));
    await b8Until(tester, find.textContaining('新建页面失败：'), '新建失败的提示');
    lbHintAbove(tester, '新建页面失败：', undoShown: false);
    await _shot(tester, 'b8-hint-create-failed');
    expect(tester.takeException(), isNull);
  });

  testWidgets('编辑组件页里的两句：长按“复制”、点一个变体“现在改的是变体…”', (tester) async {
    await lbOpen(tester, doc: compUserDoc([productCardDef()]));
    await b8Tap(tester, lbNode('p1'));
    await b8Tap(tester, find.byTooltip('更多操作'));
    await b8Tap(tester, find.widgetWithText(PopupMenuItem<String>, '编辑组件'));
    await b8Until(tester, lbKey('comp-editor-done'), '编辑组件页');
    await b8Menu(tester, '变体');
    await b8Tap(tester, lbKey('comp-variant-row-kind-hot'));
    await b8Until(tester, lbKey('comp-editor-variant-done'), '正在改变体');
    lbHintAbove(tester, '现在改的是变体「');
    await _shot(tester, 'b8-hint-variant');
    await b8HintGone(tester);
    await b8Tap(tester, lbKey('comp-editor-variant-done'));

    // 长按组件里的一个东西 › 复制
    const first = 'name'; // 组件里的那行名字（最前面那个是插槽占位，菜单不一样）
    await b8LongPress(tester, lbNode(first).last);
    await b8TapText(tester, '复制');
    lbHintAbove(tester, '已复制，长按别的组件可以“粘贴到它后面”');
    expect(tester.takeException(), isNull);
  });

  testWidgets('输入框“跟状态同步”选了一段拼出来的文字：说要选一个状态本身，没绑上', (tester) async {
    final sample = bindSample();
    // 样例里的搜索框本来绑着 keyword：先在样例里解掉，测“从没绑到想绑”这条路。
    const input = 'kw';
    lcSetModel(sample.find(input)!, null);
    final session = await lbOpen(tester, doc: sample);
    await b8Tap(tester, lbNode(input));
    await lbOpenCommon(tester);
    await lbTapShown(tester, lbKey('lc-data-model'));
    await b8Tap(tester, lbKey('lc-bind-mode-template'));
    await tester.enterText(lbKey('lc-bind-template'), '你好，{user}');
    await settle(tester, rounds: 2);
    await lbTapShown(tester, lbKey('lc-bind-use'));
    await b8Until(tester, find.textContaining('跟状态同步要选一个状态本身'), '提示');
    await settle(tester, rounds: 6);
    lbHintAbove(tester, '跟状态同步要选一个状态本身', undoShown: false);
    await _shot(tester, 'b8-hint-model-need-state');
    expect(lbKey('lc-bound-model'), findsNothing);
    expect(lcModelOf((await lbSaved(tester, session)).find(input)!), isNull);
    expect(tester.takeException(), isNull);
  });
}
