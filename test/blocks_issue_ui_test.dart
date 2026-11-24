// 积木语法检查的界面测试（390×844，浅色 + 深色）。
//   LOPI_SHOTS=1 flutter test --no-pub test/blocks_issue_ui_test.dart   # 同时把截图写到 docs/screenshots/8-issue-*.png
//
// 造有问题的积木 → 积木上出现标记（哪一格有问题也标）→ 点角标看到原因和建议 → 修好以后标记当场消失；
// 问题列表（错误在前、警告在后、按事件分组）点一条跳过去；积木逻辑页有错误时标题下面说“代码没有更新”。
import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/blocks/block_geometry.dart';
import 'package:lopicode/blocks/block_issue_view.dart';
import 'package:lopicode/lowcode/logic_blocks.dart';
import 'package:lopicode/lowcode/logic_model.dart';
import 'package:lopicode/lowcode/model.dart';
import 'package:material_ui/material_ui.dart';

import 'screens_test.dart' show fontsLoaded, shot;
import 'support/blocks_fixture.dart' show nodeIdOf;
import 'support/blocks_rig.dart';
import 'support/harness.dart';

Finder k(String key) => find.byKey(ValueKey(key));

/// 一串“点按钮时”：
///   0 把 count 加上 “abc”（错误：数字格里是文字）
///   1 如果 1（警告：条件是固定的数）→ 里面一句提示
///   2 设置变量 ghost（错误：没声明）
///   3 跳转到 “”（警告：网址没填）
/// 另一串“页面打开时”是空的（警告）。
LcDocument troubled() {
  final doc = LcDocument.starter('测试页');
  doc.logic.addVariable('count', type: 'number');
  final h = doc.logic.addHandler('click', target: nodeIdOf(doc, 'button'))!
    ..x = 16
    ..y = 104;
  h.body.addAll([
    LcBlock(op: 'changeVar', args: {'name': 'count', 'by': exText('abc')}),
    LcBlock(
      op: 'if',
      args: {'cond': exNum(1)},
      body: [
        LcBlock(op: 'alert', args: {'message': exText('你好')}),
      ],
    ),
    LcBlock(op: 'setVar', args: {'name': 'ghost', 'value': exNum(1)}),
    LcBlock(op: 'navigate', args: {'url': exText('')}),
  ]);
  doc.logic.addHandler('load')!
    ..x = 16
    ..y = 20;
  return doc;
}

/// 屏幕上：第 i 串某块积木的角标。空路径＝帽子。
Offset badge(Rig rig, int i, LcBlockPath path) {
  final p = rig.placed(i);
  final b = path.isEmpty ? p.layout.hat! : p.layout.blockAt(path)!;
  return rig.s.globalOf(rig.s.toView(p.origin + bkIssueBadgeCenter(b, rig.s.kit.metrics)));
}

bool? level(Rig rig, int i, LcBlockPath path) {
  final p = rig.placed(i);
  final b = path.isEmpty ? p.layout.hat! : p.layout.blockAt(path)!;
  return rig.s.issueMarks[p.id]?.levelOf(b);
}

/// 第 i 串某块积木的某个参数那一格有没有被标出来。
bool? slotLevel(Rig rig, int i, LcBlockPath path, String arg) {
  final p = rig.placed(i);
  for (final (b, sl) in p.layout.allSlots) {
    if (b.isHat || !bkSameBlockPath(b.path, path) || sl.arg != arg || sl.exprPath.isNotEmpty) continue;
    return rig.s.issueMarks[p.id]?.slotLevel(path, sl);
  }
  throw StateError('没找到参数 $arg');
}

void main() {
  setUpAll(() async => fontsLoaded = await loadRealFonts());

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    final suffix = mode == ThemeMode.light ? 'light' : 'dark';

    testWidgets('有问题的积木上有标记，哪一格有问题也标；点角标看原因和建议；修好以后标记当场消失 ($suffix)', (tester) async {
      final rig = Rig(troubled());
      await rig.pump(tester, mode: mode);

      // 错误＝true，警告＝false，没问题＝null。
      expect(level(rig, 0, const []), isNull, reason: '帽子没问题');
      expect(level(rig, 0, [lcStep(0)]), isTrue);
      expect(level(rig, 0, [lcStep(1)]), isFalse);
      expect(level(rig, 0, [lcStep(1), lcStep(0)]), isNull, reason: '里面那句没问题：不因为外面那块有警告就连坐');
      expect(level(rig, 0, [lcStep(2)]), isTrue);
      expect(level(rig, 0, [lcStep(3)]), isFalse);
      expect(level(rig, 1, const []), isFalse, reason: '空的事件：帽子上一个警告');
      // 具体哪一格。
      expect(slotLevel(rig, 0, [lcStep(0)], 'by'), isTrue);
      expect(slotLevel(rig, 0, [lcStep(0)], 'name'), isNull);
      expect(slotLevel(rig, 0, [lcStep(1)], 'cond'), isFalse);
      expect(slotLevel(rig, 0, [lcStep(2)], 'name'), isTrue);
      expect(slotLevel(rig, 0, [lcStep(2)], 'value'), isNull);
      expect(slotLevel(rig, 0, [lcStep(3)], 'url'), isFalse);
      // 顶栏：有错误，数字是全部问题数。
      expect(find.descendant(of: k('bk-issues'), matching: find.text('5')), findsOneWidget);
      await shot(tester, '8-issue-marks-$suffix');

      // 点错误积木的角标：选中它，弹出小卡，写着原因 + 建议 + 规则编号。
      await tester.tapAt(badge(rig, 0, [lcStep(2)]));
      await tester.pumpAndSettle();
      expect(k('bk-issue-card'), findsOneWidget);
      expect(find.descendant(of: k('bk-issue-card'), matching: find.textContaining('ghost')), findsOneWidget);
      expect(find.descendant(of: k('bk-issue-card'), matching: find.textContaining('建议：')), findsOneWidget);
      expect(find.descendant(of: k('bk-issue-card'), matching: find.textContaining('G03')), findsOneWidget);
      expect(rig.s.selection!.path.single.index, 2);
      expect(rig.edits, 0, reason: '看问题不算改动');
      await shot(tester, '8-issue-card-$suffix');
      // 点外面关掉。
      await tester.tapAt(const Offset(40, 800));
      await tester.pumpAndSettle();
      expect(k('bk-issue-card'), findsNothing);

      // 警告积木的角标也能点。
      await tester.tapAt(badge(rig, 0, [lcStep(1)]));
      await tester.pumpAndSettle();
      expect(find.descendant(of: k('bk-issue-card'), matching: find.textContaining('条件')), findsOneWidget);
      expect(find.descendant(of: k('bk-issue-card'), matching: find.textContaining('G10')), findsOneWidget);
      await tester.tapAt(const Offset(40, 800));
      await tester.pumpAndSettle();

      // 修好：把 ghost 换成声明过的变量 → 那块的标记当场没了，别的还在。
      rig.host.edit(() => rig.host.script(rig.h(0).id)!.body[2].args['name'] = 'count');
      await tester.pump();
      expect(level(rig, 0, [lcStep(2)]), isNull);
      expect(slotLevel(rig, 0, [lcStep(2)], 'name'), isNull);
      expect(level(rig, 0, [lcStep(0)]), isTrue);
      expect(find.descendant(of: k('bk-issues'), matching: find.text('4')), findsOneWidget);
      // 原来角标的位置现在点下去不再弹小卡。
      await tester.tapAt(badge(rig, 0, [lcStep(2)]));
      await tester.pumpAndSettle();
      expect(k('bk-issue-card'), findsNothing);

      // 全修好：顶栏变回对勾，没有数字。
      rig.host.edit(() {
        final h = rig.host.script(rig.h(0).id)!;
        h.body[0].args['by'] = exNum(1);
        h.body[1].args['cond'] = exBin('>', exVar('count'), exNum(3));
        h.body[3].args['url'] = exText('about.html');
        rig.host.script(rig.h(1).id)!.body.add(LcBlock(op: 'alert', args: {'message': exText('欢迎')}));
      });
      await tester.pumpAndSettle();
      expect(rig.host.issues, isEmpty);
      expect(rig.s.issueMarks, isEmpty);
      expect(find.descendant(of: k('bk-issues'), matching: find.byIcon(Icons.check_circle_outline_rounded)), findsOneWidget);
      await tester.tap(k('bk-issues'));
      await tester.pumpAndSettle();
      expect(find.text('没有发现问题'), findsOneWidget);
      expect(k('bk-issues-none'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('问题列表：错误在前、警告在后，按事件分组；点一条关掉列表、跳到那块积木并选中 ($suffix)', (tester) async {
      final rig = Rig(troubled());
      await rig.pump(tester, mode: mode);
      final issues = rig.host.issues;
      expect(issues.where((i) => i.isError), hasLength(2));
      expect(issues.where((i) => !i.isError), hasLength(3));

      await tester.tap(k('bk-issues'));
      await tester.pumpAndSettle();
      expect(find.text('5 个问题'), findsOneWidget);
      expect(find.text('错误 · 2'), findsOneWidget);
      expect(find.text('警告 · 3'), findsOneWidget);
      expect(find.textContaining('有 2 个错误，代码没有更新'), findsOneWidget);
      expect(tester.getTopLeft(k('bk-issues-errors')).dy, lessThan(tester.getTopLeft(k('bk-issues-warnings')).dy));
      // 每一条错误都排在每一条警告上面。
      // 列表是懒加载的：屏幕外的条目还没建出来，只比建出来的；两条错误一定都在。
      double? y(int i) => k('bk-issue-$i').evaluate().isEmpty ? null : tester.getTopLeft(k('bk-issue-$i')).dy;
      for (var e = 0; e < issues.length; e++) {
        if (!issues[e].isError) continue;
        expect(y(e), isNotNull, reason: '错误排在最前面，一打开就看得见');
        for (var w = 0; w < issues.length; w++) {
          final yw = y(w);
          if (!issues[w].isError && yw != null) expect(y(e), lessThan(yw), reason: '$e 在 $w 上面');
        }
      }
      // 组名＝哪个事件；空事件那一串单独一组。
      final groups = {for (final i in issues) i.group};
      expect(groups, hasLength(2));
      expect(find.text(issues.firstWhere((i) => i.isError).group), findsWidgets);
      expect(find.textContaining('建议：'), findsWidgets);
      await shot(tester, '8-issue-list-$suffix');

      // 点“页面打开时”那条警告：列表关掉，选中那一串的帽子，闪一下。
      final idx = issues.indexWhere((i) => i.scriptId == rig.h(1).id);
      await tester.scrollUntilVisible(
        k('bk-issue-$idx'),
        80,
        scrollable: find.descendant(of: find.byType(BottomSheet), matching: find.byType(Scrollable)).last,
      );
      await tester.ensureVisible(k('bk-issue-$idx'));
      await tester.pumpAndSettle();
      await tester.tap(k('bk-issue-$idx'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(rig.s.flashAnim.isAnimating, isTrue);
      await tester.pumpAndSettle();
      expect(find.text('5 个问题'), findsNothing);
      expect(rig.s.selection!.scriptId, rig.h(1).id);
      expect(rig.s.selection!.path, isEmpty);
      final canvas = tester.getRect(k('bk-canvas'));
      expect(rig.grip(1, const []).dy, inInclusiveRange(canvas.top, canvas.bottom - rig.s.coveredBottom), reason: '跳过去以后那块在看得见的地方');
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('跳到积木：画布缩得很小时顺手放回 1 倍；看得见的范围按编辑器当时真实的大小算', (tester) async {
    final doc = troubled();
    doc.logic.handlers.first.body.addAll([
      for (var i = 0; i < 14; i++) LcBlock(op: 'alert', args: {'message': exText('第 $i 句')}),
    ]);
    doc.logic.handlers.first.body.add(LcBlock(op: 'setVar', args: {'name': 'far', 'value': exNum(1)}));
    final rig = Rig(doc);
    await rig.pump(tester);
    rig.s.setZoom(0.5, const Offset(100, 100));
    await tester.pumpAndSettle();
    expect(rig.s.zoom, 0.5);
    final last = rig.h(0).body.length - 1;
    rig.s.jumpTo(rig.h(0).id, [lcStep(last)]);
    await tester.pumpAndSettle();
    expect(rig.s.zoom, 1.0);
    final canvas = tester.getRect(k('bk-canvas'));
    expect(rig.grip(0, [lcStep(last)]).dy, inInclusiveRange(canvas.top, canvas.bottom - rig.s.coveredBottom));
    expect(rig.s.selection!.path.single.index, last);
    expect(tester.takeException(), isNull);
  });

  testWidgets('积木逻辑页：有错误时标题下面写“N 个错误，没更新”，修好就消失；只有警告时不写', (tester) async {
    final rig = Rig(troubled());
    await rig.pumpLogic(tester);
    expect(find.text('2 个错误，没更新'), findsOneWidget);
    await shot(tester, '8-logic-blocked-light');
    final host = rig.s.host;
    host.edit(() {
      final h = host.script(rig.h(0).id)!;
      h.body[0].args['by'] = exNum(1);
      h.body[2].args['name'] = 'count';
    });
    await tester.pumpAndSettle();
    expect(host.issues.where((i) => i.isError), isEmpty);
    expect(host.issues, isNotEmpty, reason: '还剩警告');
    expect(find.textContaining('没更新'), findsNothing);
    // 看代码：有错误时说明这是预览；现在没有错误，不说。
    await tester.tap(k('bk-code'));
    await tester.pumpAndSettle();
    expect(find.textContaining('只读。改积木，代码会跟着变。'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('看代码：有错误时明说下面只是预览、项目里的文件还是上一次的', (tester) async {
    final rig = Rig(troubled());
    await rig.pump(tester);
    await tester.tap(k('bk-code'));
    await tester.pumpAndSettle();
    expect(find.textContaining('有 2 个错误，代码没有更新。下面只是照现在的积木翻出来的预览'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('老文档（缺字段、不认识的积木、控件已经删了）：打开不崩，问题只是标出来，文档一个字不改', (tester) async {
    final doc = LcDocument.parse('''
{"title":"老页面","root":{"id":"root","type":"page","children":[{"id":"n2","type":"button","props":{"text":"提交"}}]},
 "logic":{"variables":[{"name":"count"}],"handlers":[
   {"id":"h1","event":"click","target":"gone","body":[
     {"op":"setVar"},
     {"op":"repeat","args":{"times":"three"}},
     {"op":"someFutureBlock","args":{"x":1}},
     {"op":"if","args":{"cond":{"e":"mystery"}},"body":"oops"},
     {"op":"navigate","args":{"url":{"e":"text"}}}
   ]},
   {"id":"h2","event":"swipe","body":[]}
 ]}}''');
    final before = doc.encode();
    final rig = Rig(doc);
    await rig.pump(tester);
    expect(tester.takeException(), isNull);
    expect(rig.host.issues, isNotEmpty);
    expect(rig.s.issueMarks, isNotEmpty);
    await tester.tap(k('bk-issues'));
    await tester.pumpAndSettle();
    expect(find.textContaining('个问题'), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(rig.doc.encode(), before, reason: '只标出来，不自动改写');
    expect(rig.edits, 0);
  });
}
