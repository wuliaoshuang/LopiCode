// 第四轮 B8（下）：导出这一头——
// 6. Flutter 导出里“按下”的样子不只按钮有：容器、文字、卡片按住时换底色 / 文字颜色 / 字号 / 内边距 / 圆角，松手回去。
// 7. “重复”的列表是空的时候显示一块内容：就是它后面一个带“存在条件”的容器，四种导出都认；没用它的页面导出不变。
// 前半不依赖外部环境；中间是 Flutter 检入样本真装进界面；后半（开发机才有环境，找不到明确跳过）三种网页真编译、jsdom 真跑。
// 没覆盖的：真浏览器、真手机。
@Tags(['external'])
library;

import 'dart:async';
import 'dart:io';

// 导出的页面用的是 Flutter 自带的那套 Material：这里也得用它来装。
// ignore: deprecated_member_use
import 'package:flutter/material.dart' as m;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/lowcode/bind_model.dart';
import 'package:lopicode/lowcode/export_dart.dart';
import 'package:lopicode/lowcode/model.dart';
import 'package:lopicode/lowcode/repeat_empty.dart';

import 'generated/b8_page.dart';
import 'support/b8_sample.dart';
import 'support/bind_export_files.dart';
import 'support/bind_sample.dart';
import 'support/dev_tools.dart';
import 'support/v3_components_sample.dart';

const _entry = {'html': 'index.html', 'vue': 'B8.vue', 'react': 'B8.jsx'};
const _label = {'html': '普通网页', 'vue': 'Vue 3', 'react': 'React'};

Color? _bgAround(WidgetTester tester, String text) {
  for (final e in tester.widgetList(find.ancestor(of: find.text(text), matching: find.byWidgetPredicate((w) => w is Container || w is DecoratedBox || w is m.Material || w is ColoredBox)))) {
    final c = switch (e) {
      final Container x => x.color ?? (x.decoration is BoxDecoration ? (x.decoration! as BoxDecoration).color : null),
      final DecoratedBox x => x.decoration is BoxDecoration ? (x.decoration as BoxDecoration).color : null,
      final ColoredBox x => x.color,
      final m.Material x => x.color,
      _ => null,
    };
    if (c != null) return c;
  }
  return null;
}

void main() {
  if (skipWithoutDom != false) {
    // ignore: avoid_print 跳过的原因要在测试输出里看得见
    print('【跳过】B8 样例的真编译 / 真跑：$skipWithoutDom');
  }

  group('“重复”为空时的一块内容：模型', () {
    test('加一块：放在被重复的组件后面，带“列表有 0 项”的存在条件，记着是谁的；原来那句话搬进去', () {
      final doc = bindSample();
      LcNode? rep;
      void walk(LcNode n) {
        if (rep == null && lcRepeatOf(n) != null) rep = n;
        n.children.forEach(walk);
      }

      walk(doc.root);
      expect(rep, isNotNull, reason: '样例里要有一个“重复”');
      final node = rep!;
      lcSetRepeat(node, listSrc: Map<String, dynamic>.from(node.more['repeat']['list'] as Map), item: lcRepeatOf(node)!.item, index: lcRepeatOf(node)!.index, empty: '什么都没有');
      final before = lcRepeatOf(node)!;
      final id = lcAddRepeatEmptyBlock(doc, node.id)!;
      final parent = doc.parentOf(node.id)!;
      expect(parent.children.indexWhere((c) => c.id == id), parent.children.indexOf(node) + 1);
      final box = doc.find(id)!;
      expect(box.type, 'container');
      expect(box.more[kLcEmptyOf], node.id);
      expect(lcRenderIfExpr(box), {
        'e': 'bin',
        'op': '==',
        'l': {'e': 'len', 'x': before.list},
        'r': {'e': 'num', 'v': 0},
      });
      expect(box.children.single.props['text'], '什么都没有');
      expect(lcRepeatOf(node)!.empty, isNull, reason: '那句话搬走了，不会两样一起出来');
      expect(lcRepeatOf(node)!.list, before.list);
      expect(lcAddRepeatEmptyBlock(doc, node.id), id, reason: '已经有了：不再加第二块');
      // 存盘再读：还认得
      final again = LcDocument.parse(doc.encode());
      expect(lcRepeatEmptyBlock(again, node.id)?.id, id);
      // 不重复了：那一块一起拿掉
      lcSetRepeat(again.find(node.id)!, listSrc: null);
      lcSyncRepeatEmptyBlock(again, node.id);
      expect(again.find(id), isNull);
    });

    test('没设重复的组件加不了；没用这个功能的页面什么都没多', () {
      final doc = bindSample();
      final before = doc.encode();
      expect(lcAddRepeatEmptyBlock(doc, doc.root.id), isNull);
      expect(doc.encode(), before);
      expect(before, isNot(contains(kLcEmptyOf)));
    });

    test('四种导出里都没有把“emptyOf”这个只给编辑器用的记号写出去', () {
      for (final e in allExportFiles(b8Doc()).entries) {
        expect(e.value, isNot(contains('emptyOf')), reason: e.key);
      }
    });
  });

  group('Flutter：“按下”的样子', () {
    test('容器 / 文字 / 卡片按下时换的属性写出来了，外面包了记“按没按着”的壳；认不了的那条写进说明；检入样本和导出器一致', () {
      final dart = exportDart(b8Doc(), className: 'B8Page');
      expect('_LcPress(builder: (context, lcDown) =>'.allMatches(dart).length, 3, reason: '容器、文字、卡片各一个');
      expect(dart, contains('class _LcPress extends StatefulWidget'));
      expect(dart, contains('lcDown ? Color(0xFFFFCC00)'));
      expect(dart, contains('lcDown ? Color(0xFFFF0000)'));
      expect(dart, contains('lcDown ? 20'));
      expect(dart, contains('“按下”时的样子里的 opacity'));
      expect(dart, isNot(contains('别的组件、别的属性在 Flutter 里没有现成的')), reason: '这一页的按下样式都接上了，不再说“没导出”');
      expect(File('test/generated/b8_page.dart').readAsStringSync(), dart, reason: '导出器改了：运行 dart run tool/gen_sample_export.dart 重新生成');
    });

    test('没写“按下”样子的页面：不带那层壳', () {
      expect(exportDart(bindSample(), className: 'BindHomePage'), isNot(contains('_LcPress')));
    });
  });

  testWidgets('Flutter 真装进界面：按住容器 / 文字换样子、松手回去；列表空的时候那一块在，点里面的按钮有了两项就没了，清空又回来', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const m.MaterialApp(home: B8Page()));
    await tester.pump();
    expect(tester.takeException(), isNull);

    // 文字：平时深色 16 号；按住红色 20 号
    Text word() => tester.widget<Text>(find.text('按住这行字'));
    expect(word().style?.color, const Color(0xFF222222));
    expect(word().style?.fontSize, 16);
    var g = await tester.startGesture(tester.getCenter(find.text('按住这行字')));
    await tester.pump();
    expect(word().style?.color, const Color(0xFFFF0000));
    expect(word().style?.fontSize, 20);
    await g.up();
    await tester.pump();
    expect(word().style?.color, const Color(0xFF222222));

    // 容器：平时浅灰底；按住黄底、变大（内边距 12 → 20）
    expect(_bgAround(tester, '按住我'), const Color(0xFFEEEEEE));
    final small = tester.getSize(find.byWidgetPredicate((w) => w is Container && w.padding == const EdgeInsets.all(12)).first);
    g = await tester.startGesture(tester.getCenter(find.text('按住我')));
    await tester.pump();
    expect(_bgAround(tester, '按住我'), const Color(0xFFFFCC00));
    expect(find.byWidgetPredicate((w) => w is Container && w.padding == const EdgeInsets.all(20)), findsWidgets);
    await g.up();
    await tester.pump();
    expect(_bgAround(tester, '按住我'), const Color(0xFFEEEEEE));
    expect(small.height, greaterThan(0));

    // 手指滑走（系统取消）也回去
    g = await tester.startGesture(tester.getCenter(find.text('按住我')));
    await tester.pump();
    await g.cancel();
    await tester.pump();
    expect(_bgAround(tester, '按住我'), const Color(0xFFEEEEEE));

    // “重复”为空时的那一块
    expect(find.text('还没有东西'), findsOneWidget);
    expect(find.text('苹果'), findsNothing);
    // Flutter 这一份不导出页面的积木逻辑（按钮的 onPressed 是空的，文件头写着）：照文件头说的，用 update 改状态。
    final page = tester.state<B8PageState>(find.byType(B8Page));
    expect(find.text('放两个进来'), findsOneWidget, reason: '那一块里的按钮画出来了');
    page.update(() => page.s_xs = page.s_two);
    await tester.pump();
    expect(find.text('苹果'), findsOneWidget);
    expect(find.text('香蕉'), findsOneWidget);
    expect(find.text('还没有东西'), findsNothing);
    page.update(() => page.s_xs = page.s_none);
    await tester.pump();
    expect(find.text('还没有东西'), findsOneWidget);
    expect(find.text('苹果'), findsNothing);

    // 轻提示：调导出的那个方法，屏幕下方出一句“已保存”，3 秒后自己没了
    expect(find.text('已保存'), findsNothing);
    unawaited(page.showDialog_toast(page.context));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));
    expect(find.text('已保存'), findsOneWidget);
    expect(find.byType(m.SnackBar), findsOneWidget);
    expect(find.byType(m.AlertDialog), findsNothing, reason: '不是弹窗：没有遮罩和按钮');
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.text('已保存'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  group('轻提示：导出里各写成什么', () {
    test('三种网页：一句话、没有遮罩和按钮；样式和秒数只在有轻提示的页面里写', () {
      final all = allExportFiles(b8Doc());
      final html = all['html/index.html']!;
      expect(html, contains('data-variant="toast"'));
      expect(html, contains('role="status"'));
      expect(html, contains('data-seconds="3"'));
      expect(html, contains('onanimationend='));
      final css = all['html/style.css']!;
      expect(css, contains('@keyframes lc-toast'));
      expect(css, contains('[data-seconds="3"] { animation-duration: 3s; }'));
      expect(all.entries.where((e) => e.key.startsWith('vue/')).map((e) => e.value).join(), contains('@animationend='));
      expect(all.entries.where((e) => e.key.startsWith('react/')).map((e) => e.value).join(), contains('onAnimationEnd='), reason: 'React 的写法是 onAnimationEnd');
    });

    test('只有普通弹窗的页面：一个字都没多（没有轻提示的规则）', () {
      for (final e in allExportFiles(v3AllPage()).entries) {
        expect(e.value, isNot(contains('lc-toast')), reason: e.key);
      }
    });

    test('Flutter：轻提示是 SnackBar，不是 AlertDialog', () {
      final dart = exportDart(b8Doc(), className: 'B8Page');
      expect(dart, contains('ScaffoldMessenger.of(context)'));
      expect(dart, contains('duration: Duration(seconds: 3)'));
      expect(dart, isNot(contains('AlertDialog(')));
    });
  });

  group('三种网页导出真编译真跑', () {
    for (final kind in ['html', 'vue', 'react']) {
      test('${_label[kind]}：真编译 0 错误 0 警告', () async {
        final r = await compileExport('compile_$kind.mjs', exportFilesOf(b8Doc(), kind), _entry[kind]!);
        expect(r.errors, isEmpty, reason: r.raw);
        expect(r.warnings, isEmpty, reason: r.raw);
        expect(r.ok, isTrue);
      }, skip: skipWithoutDom);

      test('${_label[kind]}：真跑——列表空的时候那一块在；有了东西就没了；清空又回来', () async {
        final doc = b8Doc();
        final steps = b8Steps(doc);
        final r = await runInDom(kind, exportFilesOf(doc, kind), _entry[kind]!, steps);
        expect(r.errors, isEmpty);
        expect(r.warnings, isEmpty);
        expect(r.done, steps.length);
        expect(r.ok, isTrue);
      }, skip: skipWithoutDom);
    }
  });
}
