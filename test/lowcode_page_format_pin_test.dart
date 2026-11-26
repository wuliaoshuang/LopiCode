// 页面文件格式钉住。
//
// 2026-11-26 编辑器第 3 期把格式升到了第 3 版（霜霜同意的，只升这一次；说明见 docs/lowcode-page-format-v3.md）。
// 升版时改了这里 5 处断言，逐条记在 docs/lowcode-page-format-v3.md 的“改了哪些老断言”一节。
//
// - test/fixtures/lowcode/page-v1.lc.json / page-v2.lc.json：两份“旧文件”。
// - 同名的 .saved.lc.json：格式还是第 2 版时它们打开再存出来的样子（由当时的读写代码生成，不许重新生成）。
// - 同名的 .saved-v3.lc.json：现在打开再存出来的样子。和 .saved.lc.json 比只多两样：版本号是 3；
//   老代码存盘时丢掉的那几个看不懂的属性，现在留在节点的 oldProps 里（不丢东西）。
// - 界面这一层：打开不写；在新布局里点一下添加、长按拖动、拖柄改尺寸，存出来的内容和“直接对文档做同样的修改”一字不差；
//   编辑器自己的东西（“常用”）不进页面文件。
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/core/safe_file.dart';
import 'package:lopicode/core/templates.dart';
import 'package:lopicode/lowcode/builder_screen.dart';
import 'package:lopicode/lowcode/canvas_view.dart';
import 'package:lopicode/lowcode/editor_recents.dart';
import 'package:lopicode/lowcode/model.dart';
import 'package:lopicode/lowcode/style_model.dart';
import 'package:lopicode/project_session.dart';
import 'package:material_ui/material_ui.dart';

import 'support/harness.dart';

String fixture(String name) => File('test/fixtures/lowcode/$name').readAsStringSync();

Future<ProjectSession> openWith(WidgetTester tester, String source) async {
  usePhoneViewport(tester);
  late TestEnv env;
  late ProjectSession session;
  await tester.runAsync(() async {
    env = await TestEnv.create();
    final project = await env.services.projects.create('我的小站', ProjectTemplate.lowcode);
    session = ProjectSession(env.services, project);
    File(session.guard.resolve(kLowcodePageFile)).writeAsStringSync(source);
  });
  addTearDown(() async {
    await pendingWrites();
    session.dispose();
    await env.dispose();
  });
  await tester.pumpWidget(appFor(env, BuilderScreen(session: session)));
  await settle(tester, rounds: 6);
  return session;
}

/// 等“停手才存”那一段走完，读回页面文件的原文。
Future<String> savedText(WidgetTester tester, ProjectSession session) async {
  await waitLowcodeSaved(tester);
  late String text;
  await tester.runAsync(() async => text = File(session.guard.resolve(kLowcodePageFile)).readAsStringSync());
  return text;
}

Finder node(String id) => find.byKey(ValueKey('lowcode-node-$id'));

void main() {
  group('读写规则（不经过界面）', () {
    test('版本号是 3；最外层只有这几个字段，顺序不变', () {
      expect(LcDocument.currentVersion, 3);
      final v2 = jsonDecode(LcDocument.parse(fixture('page-v2.lc.json')).encode()) as Map<String, dynamic>;
      expect(v2.keys.toList(), ['version', 'title', 'root', 'logic', 'components']);
      final v1 = jsonDecode(LcDocument.parse(fixture('page-v1.lc.json')).encode()) as Map<String, dynamic>;
      expect(v1.keys.toList(), ['version', 'title', 'root']);
      expect(v1['version'], 3, reason: '旧文件存出来写当前版本号（原来就是这样）');
    });

    for (final name in ['page-v1', 'page-v2']) {
      test('$name：打开再存，和钉住的第 3 版样子一字不差；再来一遍不再变', () {
        final saved = LcDocument.parse(fixture('$name.lc.json')).encode();
        expect(saved, fixture('$name.saved-v3.lc.json'));
        expect(LcDocument.parse(saved).encode(), saved);
      });

      test('$name：第 3 版存出来的，去掉版本号和 oldProps 以后，和第 2 版时存出来的一字不差', () {
        final json = jsonDecode(fixture('$name.saved-v3.lc.json')) as Map<String, dynamic>;
        var dropped = 0;
        void strip(Object? n) {
          if (n is Map) {
            if (n.remove('oldProps') != null) dropped++;
            n.values.toList().forEach(strip);
          } else if (n is List) {
            n.forEach(strip);
          }
        }

        strip(json);
        json['version'] = 2;
        expect(const JsonEncoder.withIndent('  ').convert(json), fixture('$name.saved.lc.json'));
        expect(dropped, greaterThan(0), reason: '两份样例里都有老代码会丢的属性，现在应该留在 oldProps 里');
      });
    }

    test('旧文件存出来，节点的字段：只有 id / type / props / style / bind / oldProps / children，空的不写', () {
      void walk(Map<String, dynamic> n) {
        expect(n.keys.toSet().difference({'id', 'type', 'props', 'style', 'bind', 'oldProps', 'children'}), isEmpty, reason: '${n['id']}');
        for (final key in ['props', 'style', 'bind', 'children']) {
          if (n.containsKey(key)) expect(n[key], isNotEmpty, reason: '${n['id']}.$key');
        }
        for (final c in (n['children'] as List? ?? const [])) {
          walk(c as Map<String, dynamic>);
        }
      }

      for (final name in ['page-v1', 'page-v2']) {
        walk((jsonDecode(fixture('$name.saved-v3.lc.json')) as Map<String, dynamic>)['root'] as Map<String, dynamic>);
      }
    });
  });

  group('经过新布局的编辑器', () {
    for (final name in ['page-v1', 'page-v2']) {
      testWidgets('$name：只是打开、选中、平移、缩放、换屏宽档、开关组件盒——页面文件一个字节都不动', (tester) async {
        final source = fixture('$name.lc.json');
        final session = await openWith(tester, source);
        await tester.tap(node('n1'));
        await settle(tester, rounds: 2);
        final canvas = tester.state<CanvasViewState>(find.byType(CanvasView));
        canvas.zoomStep(1);
        canvas.fitToScreen();
        await tester.dragFrom(const Offset(195, 500), const Offset(0, -80));
        await tester.pump(const Duration(seconds: 1));
        await tester.tap(find.byKey(const ValueKey('lc-tool-add')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('palette-group-layout')));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('关闭组件盒'));
        await tester.pumpAndSettle();
        expect(await savedText(tester, session), source);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('旧文件（v1）：点一下添加、长按拖动换位置、拖柄改尺寸——存出来的和直接改文档一字不差', (tester) async {
      final source = fixture('page-v1.lc.json');
      final session = await openWith(tester, source);
      final expected = LcDocument.parse(source);

      // 1) 没选中时点组件盒的“文本”：加到页面末尾。
      await tester.tap(find.byKey(const ValueKey('lc-tool-add')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('palette-item-text')));
      await settle(tester, rounds: 3);
      final added = expected.newNode('text');
      expected.insert('root', added);
      expect(await savedText(tester, session), expected.encode());

      // 2) 长按第一行标题拖到页面最后。
      final g = await tester.startGesture(tester.getCenter(node('n1')));
      await tester.pump(const Duration(milliseconds: 320));
      await tester.pump();
      await g.moveTo(Offset(195, tester.getRect(node(added.id)).bottom + 30));
      await tester.pump();
      await g.up();
      await settle(tester, rounds: 3);
      expected.move('n1', 'root', expected.root.children.length);
      expect(await savedText(tester, session), expected.encode());

      // 3) 选中按钮，拖右下角的拖柄：只多出 style 里的 width / height。
      await tester.tap(node('n4'));
      await settle(tester, rounds: 2);
      final before = tester.getSize(node('n4'));
      await tester.drag(find.byKey(const ValueKey('lowcode-handle-se')), const Offset(40, 20));
      await settle(tester, rounds: 3);
      final style = LcStyle(expected.find('n4')!.style);
      style.setLength('width', LcLength.px((before.width + 40).roundToDouble()));
      style.setLength('height', LcLength.px((before.height + 20).roundToDouble()));
      final text = await savedText(tester, session);
      expect(text, expected.encode());

      // 编辑器自己记的东西不进页面文件。
      expect(text, isNot(contains('recent')));
      expect((jsonDecode(text) as Map<String, dynamic>).keys.toList(), ['version', 'title', 'root']);
      late List<String> recent;
      await tester.runAsync(() async {
        await pendingWrites();
        recent = await loadPaletteRecent(session.guard);
      });
      expect(recent, ['text'], reason: '“常用”记在 .lopicode/lowcode-editor.json 里');
      expect(tester.takeException(), isNull);
    });

    testWidgets('新文件（v2，带样式 / 逻辑 / 自定义组件）：编辑一下，没碰的部分原样留着', (tester) async {
      final source = fixture('page-v2.lc.json');
      final session = await openWith(tester, source);
      await tester.tap(node('n6'));
      await settle(tester, rounds: 2);
      await tester.tap(find.byKey(const ValueKey('lc-tool-add')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('palette-group-mine')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('palette-group-mine')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('palette-item-component:c1')));
      await settle(tester, rounds: 3);
      final expected = LcDocument.parse(source);
      final added = expected.newNode('component')..props['ref'] = 'c1';
      expected.insert('n6', added);
      final text = await savedText(tester, session);
      expect(text, expected.encode());
      final json = jsonDecode(text) as Map<String, dynamic>, old = jsonDecode(fixture('page-v2.saved.lc.json')) as Map<String, dynamic>;
      expect(json['logic'], old['logic']);
      expect(json['components'], old['components']);
      expect(json['version'], 3);
      expect(tester.takeException(), isNull);
    });
  });
}
