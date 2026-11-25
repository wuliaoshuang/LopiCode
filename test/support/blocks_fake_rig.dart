// 假宿主（blocks_fake_host.dart）+ 积木编辑器的测试台子：390×844，找坐标、做手势的帮手。多口积木、积木盒升级的界面测试共用。
import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/blocks/block_canvas_layout.dart';
import 'package:lopicode/blocks/block_editor_view.dart';
import 'package:lopicode/blocks/block_geometry.dart';
import 'package:lopicode/blocks/block_palette_model.dart';
import 'package:lopicode/lowcode/logic_model.dart';
import 'package:lopicode/theme/app_theme.dart';
import 'package:material_ui/material_ui.dart';

import '../screens_test.dart' show fontsLoaded;
import 'blocks_fake_host.dart';
import 'harness.dart';

LcBlock fxSay(String t) => LcBlock(op: 'say', args: {'text': fxText(t)});

/// 如果 (分数 > 90) 那么 {说 优秀} 否则如果 (分数 > 60) {说 及格} 否则如果 (分数 > 30) {} 否则 {说 加油}
LcBlock fxSampleIf() => LcBlock(
  op: 'if',
  args: {'cond': fxCmp(fxVar('分数'), '>', fxNum(90))},
  body: [fxSay('优秀')],
  arms: [
    LcArm(args: {'cond': fxCmp(fxVar('分数'), '>', fxNum(60))}, body: [fxSay('及格')]),
    LcArm(args: {'cond': fxCmp(fxVar('分数'), '>', fxNum(30))}),
  ],
  orElse: [fxSay('加油')],
);

LcBlock fxSampleSwitch() => LcBlock(
  op: 'switch',
  args: {'x': fxVar('次数')},
  arms: [
    LcArm(args: {'value': fxNum(1)}, body: [fxSay('第一次')]),
    LcArm(args: {'value': fxNum(2)}, body: [fxSay('第二次')]),
    LcArm(args: {'value': fxNum(3)}, body: [fxSay('第三次')]),
  ],
  orElse: [fxSay('好多次了')],
);

class FakeRig {
  FakeRig([List<LcBlock>? body]) : host = FakeHost(scripts: body == null ? null : [FakeScript('s1', body: body, x: 0, y: 0)]);

  final FakeHost host;
  final GlobalKey<BlockEditorViewState> key = GlobalKey();
  BlockEditorViewState get s => key.currentState!;
  LcBlockTree get tree => host.script('s1')!;
  LcBlock get first => tree.body.first;

  Future<void> pump(WidgetTester tester, {ThemeMode mode = ThemeMode.light, BlockStars? stars, bool settle = true}) async {
    usePhoneViewport(tester);
    await tester.pumpWidget(
      RepaintBoundary(
        key: shotKey,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildAppTheme(Brightness.light, fontFamily: fontsLoaded ? kTestFont : null),
          darkTheme: buildAppTheme(Brightness.dark, fontFamily: fontsLoaded ? kTestFont : null),
          themeMode: mode,
          home: BlockEditorView(key: key, host: host, title: '逻辑', stars: stars),
        ),
      ),
    );
    if (settle) await tester.pumpAndSettle();
  }

  BkPlaced get placed => s.layout.placed('s1')!;
  BkBlock block(LcBlockPath path) => placed.layout.blockAt(path)!;
  Offset _screen(Offset inScript) => s.globalOf(s.toView(placed.origin + inScript));

  /// 屏幕上：某块积木的“把手”（头部最左边，不会点到槽）。
  Offset grip(LcBlockPath path) => _screen(block(path).head.centerLeft + const Offset(7, 0));

  /// 屏幕上：某块多口积木上的小按钮（＋ / −）的中心。
  Offset control(LcBlockPath path, BkControlKind kind, {int arm = -1}) => _screen(block(path).controls.firstWhere((c) => c.kind == kind && c.arm == arm).rect.center);

  /// 屏幕上：某块积木某个参数槽的中心（段的参数用 `lcArmArg(段号, 名字)`）。
  Offset slot(LcBlockPath path, String arg) => _screen(block(path).slots.firstWhere((x) => x.arg == arg && x.exprPath.isEmpty).rect.center);

  /// 正在拖的时候：把手上那一截对到某个口里的某个位置，手指该去屏幕的哪里。
  Offset snap(LcBlockPath parent, int index, {bool inElse = false, int arm = -1}) {
    final p = s.drag!.base.placed('s1')!;
    final x = p.layout.snaps.firstWhere((x) => x.kind == BkSnapKind.statement && bkSameBlockPath(x.parent, parent) && x.arm == arm && (arm >= 0 || x.inElse == inElse) && x.index == index);
    return s.globalOf(s.toView(p.origin + x.anchor + s.grabOffset));
  }

  /// 长按（0.28 秒）拿起来，再挪一小段。
  Future<TestGesture> lift(WidgetTester tester, Offset from) async {
    final g = await tester.startGesture(from);
    await tester.pump(const Duration(milliseconds: 300));
    expect(s.drag, isNotNull, reason: '长按应该已经拿起来了');
    await g.moveBy(const Offset(6, 6));
    await tester.pump(const Duration(milliseconds: 16));
    return g;
  }

  Future<void> glide(WidgetTester tester, TestGesture g, Offset from, Offset to, {int steps = 6}) async {
    for (var i = 1; i <= steps; i++) {
      await g.moveTo(Offset.lerp(from, to, i / steps)!);
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  Future<void> drop(WidgetTester tester, TestGesture g) async {
    await g.up();
    await tester.pumpAndSettle();
  }

  /// 点积木盒的某一页（页签那一行是横着滑的：先滑回最左边，再往右找）。
  Future<void> openTab(WidgetTester tester, String id) async {
    final tab = find.byKey(ValueKey('bk-palette-tab-$id'));
    final tabs = find.byKey(const ValueKey('bk-palette-tabs'));
    await tester.drag(tabs, const Offset(800, 0));
    await tester.pumpAndSettle();
    for (var i = 0; i < 10 && tab.hitTestable().evaluate().isEmpty; i++) {
      await tester.drag(tabs, const Offset(-120, 0));
      await tester.pumpAndSettle();
    }
    await tester.tap(tab);
    await tester.pumpAndSettle();
  }

  /// 积木盒现在这一页上看得见的样品（按 key 里的名字，如 `block-if`、`expr-arith~op=*`），从上到下、从左到右。
  List<String> shownItems(WidgetTester tester) {
    final found = [
      for (final e in find.byWidgetPredicate((w) => w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith('bk-palette-item-')).evaluate())
        (tester.getTopLeft(find.byWidget(e.widget)), (e.widget.key! as ValueKey<String>).value.substring('bk-palette-item-'.length)),
    ]..sort((a, b) => a.$1.dy != b.$1.dy ? a.$1.dy.compareTo(b.$1.dy) : a.$1.dx.compareTo(b.$1.dx));
    return [for (final f in found) f.$2];
  }

  Finder item(String name) => find.byKey(ValueKey('bk-palette-item-$name'));
}
