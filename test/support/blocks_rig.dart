// 积木编辑器（BlockEditorView）界面测试共用的台子：一份文档 + 撤销历史 + 前端宿主，外加几个找坐标、做手势的帮手。
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/blocks/block_canvas_layout.dart';
import 'package:lopicode/blocks/block_editor_view.dart';
import 'package:lopicode/blocks/block_geometry.dart';
import 'package:lopicode/lowcode/logic_block_host.dart';
import 'package:lopicode/lowcode/logic_model.dart';
import 'package:lopicode/lowcode/logic_screen.dart';
import 'package:lopicode/lowcode/model.dart';
import 'package:lopicode/theme/app_theme.dart';
import 'package:material_ui/material_ui.dart';

import '../screens_test.dart' show fontsLoaded;
import 'harness.dart';

class Rig {
  Rig(this.doc) : history = LcHistory(doc) {
    host = LogicBlockHost(
      doc: doc,
      onEdit: apply,
      canUndoOf: () => history.canUndo,
      canRedoOf: () => history.canRedo,
      onUndo: () {
        final d = history.undo();
        if (d != null) doc = d;
        return d;
      },
      onRedo: () {
        final d = history.redo();
        if (d != null) doc = d;
        return d;
      },
    );
  }

  LcDocument doc;
  final LcHistory history;
  late final LogicBlockHost host;
  final GlobalKey<BlockEditorViewState> key = GlobalKey();

  /// 进了几次“统一改动入口”（＝几条撤销记录、几次落盘）。
  int edits = 0;

  /// 和搭建页一样：每次改动先换一份新的文档对象再改（谁偷偷留着旧对象就会改到废纸上）。
  void apply(void Function(LcDocument d) change) {
    doc = LcDocument.parse(doc.encode());
    change(doc);
    history.record(doc);
    edits++;
  }

  BlockEditorViewState? _found;
  BlockEditorViewState get s => key.currentState ?? _found!;

  /// 撤销 / 重做交回来了几次（搭建页这时会落盘）。
  int restores = 0;

  /// 和搭建页一样打开整页的“积木逻辑”（LogicScreen）：push 进去、把撤销历史交给它。这时编辑器用的是它自己建的宿主（`s.host`）。
  Future<void> pumpLogic(WidgetTester tester, {String? initialNodeId, ThemeMode mode = ThemeMode.light}) async {
    usePhoneViewport(tester);
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      RepaintBoundary(
        key: shotKey,
        child: MaterialApp(
          navigatorKey: nav,
          debugShowCheckedModeBanner: false,
          theme: buildAppTheme(Brightness.light, fontFamily: fontsLoaded ? kTestFont : null),
          darkTheme: buildAppTheme(Brightness.dark, fontFamily: fontsLoaded ? kTestFont : null),
          themeMode: mode,
          home: const Scaffold(),
        ),
      ),
    );
    unawaited(
      nav.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => LogicScreen(
            doc: doc,
            onEdit: apply,
            initialNodeId: initialNodeId,
            history: history,
            onRestore: (d) {
              if (d == null) return;
              doc = d;
              restores++;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    _found = tester.state<BlockEditorViewState>(find.byType(BlockEditorView));
  }

  List<LcHandler> get handlers => doc.logic.handlers;
  LcHandler h(int i) => handlers[i];
  List<String> ops(int i) => [for (final b in h(i).body) b.op];

  /// `reduceMotion`＝系统开了“减弱动态效果”。
  Future<void> pump(WidgetTester tester, {ThemeMode mode = ThemeMode.light, String? focus, bool reduceMotion = false}) async {
    usePhoneViewport(tester);
    await tester.pumpWidget(
      RepaintBoundary(
        key: shotKey,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildAppTheme(Brightness.light, fontFamily: fontsLoaded ? kTestFont : null),
          darkTheme: buildAppTheme(Brightness.dark, fontFamily: fontsLoaded ? kTestFont : null),
          themeMode: mode,
          builder: reduceMotion ? (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(disableAnimations: true), child: child!) : null,
          home: BlockEditorView(key: key, host: host, title: '逻辑', focusScriptId: focus),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  BkPlaced placed(int i) => s.layout.scripts[i];

  /// 把第 i 串挪到看得见的地方（画布露出来的部分只有半屏多）。
  Future<void> show(WidgetTester tester, int i, [LcBlockPath path = const []]) async {
    s.jumpTo(h(i).id, path);
    await tester.pumpAndSettle();
    await tester.tapAt(tester.getTopLeft(find.byKey(const ValueKey('bk-canvas'))) + const Offset(378, 220));
    await tester.pumpAndSettle();
    expect(s.selection, isNull);
  }

  /// 屏幕上：第 i 串里某块积木的“把手”（头部最左边，不会点到槽）。空路径＝帽子。
  Offset grip(int i, LcBlockPath path) {
    final p = placed(i);
    final b = path.isEmpty ? p.layout.hat! : p.layout.blockAt(path)!;
    return s.globalOf(s.toView(p.origin + b.head.centerLeft + const Offset(7, 0)));
  }

  /// 屏幕上：第 i 串里某块积木上、满足条件的第一个槽的中心。
  Offset slot(int i, LcBlockPath path, bool Function(BkSlot s) test) {
    final p = placed(i);
    for (final (b, sl) in p.layout.allSlots) {
      final same = path.isEmpty ? b.isHat : (!b.isHat && bkSameBlockPath(b.path, path));
      if (same && test(sl)) return s.globalOf(s.toView(p.origin + sl.rect.center));
    }
    throw StateError('没找到槽');
  }

  /// 屏幕上：第 i 串里某块积木的某个参数（`ep` 指到参数里更深的表达式字段）。那里是拼好的表达式就给它身上靠左的一点，否则给槽的中心。
  Offset arg(int i, LcBlockPath path, String name, [BkExprPath ep = const []]) {
    final p = placed(i);
    for (final (b, sl) in p.layout.allSlots) {
      final same = path.isEmpty ? b.isHat : (!b.isHat && bkSameBlockPath(b.path, path));
      if (!same || sl.arg != name || !bkSameExprPath(sl.exprPath, ep) || sl.look == BkSlotLook.add) continue;
      final e = sl.expr;
      return s.globalOf(s.toView(p.origin + (e != null ? e.rect.centerLeft + const Offset(9, 0) : sl.rect.center)));
    }
    throw StateError('没找到参数 $name $ep');
  }

  /// 正在拖的时候：把手上那一截对到某个拼接点，手指该去屏幕的哪里。
  Offset stackSnap(String scriptId, LcBlockPath parent, int index, {bool inElse = false}) {
    final p = s.drag!.base.placed(scriptId)!;
    final snap = p.layout.snaps.firstWhere((x) => x.kind == BkSnapKind.statement && bkSameBlockPath(x.parent, parent) && x.inElse == inElse && x.index == index);
    return s.globalOf(s.toView(p.origin + snap.anchor + s.grabOffset));
  }

  /// 正在拖表达式的时候：对到某块积木某个参数的槽，手指该去哪里。
  Offset exprSnap(String scriptId, LcBlockPath block, String arg, [BkExprPath path = const []]) {
    final p = s.drag!.base.placed(scriptId)!;
    final snap = p.layout.snaps.firstWhere((x) => x.kind == BkSnapKind.expr && bkSameBlockPath(x.parent, block) && x.arg == arg && bkSameExprPath(x.exprPath, path));
    return s.globalOf(s.toView(p.origin + snap.rect.topLeft + s.grabOffset + const Offset(2, 0)));
  }

  /// 从画布上的一点拖起来（先挪过“算拖”的那一小段）。
  Future<TestGesture> lift(WidgetTester tester, Offset from) async {
    final g = await tester.startGesture(from);
    await tester.pump(const Duration(milliseconds: 20));
    await g.moveBy(const Offset(6, 6));
    await tester.pump(const Duration(milliseconds: 16));
    await g.moveBy(const Offset(6, 6));
    await tester.pump(const Duration(milliseconds: 16));
    expect(s.drag, isNotNull, reason: '应该已经拖起来了');
    return g;
  }

  /// 从积木盒里把一样东西按住拿出来。
  Future<TestGesture> liftFromPalette(WidgetTester tester, String category, String itemKey) async {
    final tab = find.byKey(ValueKey('bk-palette-tab-$category'));
    final tabs = find.byKey(const ValueKey('bk-palette-tabs'));
    // 分类那一行是横着滑的：先滑回最左边，再往右找。
    await tester.drag(tabs, const Offset(600, 0));
    await tester.pumpAndSettle();
    for (var i = 0; i < 8 && tab.hitTestable().evaluate().isEmpty; i++) {
      await tester.drag(tabs, const Offset(-120, 0));
      await tester.pumpAndSettle();
    }
    await tester.tap(tab);
    await tester.pumpAndSettle();
    final item = find.byKey(ValueKey('bk-palette-item-$itemKey'));
    await tester.ensureVisible(item);
    await tester.pumpAndSettle();
    final g = await tester.startGesture(tester.getTopLeft(item) + const Offset(10, 20));
    await tester.pump(const Duration(milliseconds: 220));
    expect(s.drag, isNotNull, reason: '按住应该就拿出来了');
    return g;
  }

  /// 分几步挪过去，中途推帧。
  Future<void> glide(WidgetTester tester, TestGesture g, Offset to, {int steps = 6}) async {
    final start = _last ?? to;
    for (var i = 1; i <= steps; i++) {
      await g.moveTo(Offset.lerp(start, to, i / steps)!);
      await tester.pump(const Duration(milliseconds: 16));
    }
    _last = to;
  }

  Offset? _last;

  /// 松手并等动画走完。
  Future<void> drop(WidgetTester tester, TestGesture g) async {
    await g.up();
    _last = null;
    await tester.pumpAndSettle();
  }
}

/// 拦下触感反馈，记下都调了哪几种（'HapticFeedbackType.selectionClick' 这样的字）。
List<String> captureHaptics(WidgetTester tester) {
  final calls = <String>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
    if (call.method == 'HapticFeedback.vibrate') calls.add('${call.arguments}');
    return null;
  });
  addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
  return calls;
}
