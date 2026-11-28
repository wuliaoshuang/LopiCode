// 低代码搭建页的界面测试共用的那几样（第 3 期第 2 段起新写的测试用；更早的测试文件各自带着一份，没动）。
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/core/safe_file.dart';
import 'package:lopicode/core/templates.dart';
import 'package:lopicode/lowcode/builder_screen.dart';
import 'package:lopicode/lowcode/canvas_view.dart';
import 'package:lopicode/lowcode/editor_clipboard.dart';
import 'package:lopicode/lowcode/model.dart';
import 'package:lopicode/project_session.dart';
import 'package:material_ui/material_ui.dart';

import 'harness.dart';

final bool lbWriteShots = Platform.environment['LOPI_SHOTS'] == '1';
bool lbFontsLoaded = false;

/// 截一张（只有 LOPI_SHOTS=1 才真写文件）；顺带确认渲染没出异常。
Future<void> lbShot(WidgetTester tester, String dir, String name) async {
  expect(tester.takeException(), isNull, reason: '$name 渲染时出了异常');
  if (!lbWriteShots || !lbFontsLoaded) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(shotKey));
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('$dir/$name.png');
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(data!.buffer.asUint8List());
  });
}

Finder lbKey(String key) => find.byKey(ValueKey(key));
Finder lbNode(String id) => lbKey('lowcode-node-$id');
CanvasViewState lbCanvas(WidgetTester tester) => tester.state<CanvasViewState>(find.byType(CanvasView));

/// 建一个低代码项目、把 [doc] 写成页面文件、打开搭建页（390×844）。
Future<ProjectSession> lbOpen(WidgetTester tester, {LcDocument? doc, String? text, ThemeMode mode = ThemeMode.light, String? selected}) async {
  usePhoneViewport(tester);
  lcClipboardClear();
  late TestEnv env;
  late ProjectSession session;
  await tester.runAsync(() async {
    env = await TestEnv.create();
    final project = await env.services.projects.create('我的小站', ProjectTemplate.lowcode);
    session = ProjectSession(env.services, project);
    final raw = text ?? doc?.encode();
    if (raw != null) File(session.guard.resolve(kLowcodePageFile)).writeAsStringSync(raw);
  });
  addTearDown(() async {
    await pendingWrites();
    session.dispose();
    await env.dispose();
  });
  await tester.pumpWidget(
    appFor(
      env,
      // 同一个测试里连着开几个页面：每次都是全新的一页（不然上一页的状态会被接着用）
      BuilderScreen(key: UniqueKey(), session: session, initialSelection: selected),
      mode: mode,
      font: lbFontsLoaded ? kTestFont : null,
    ),
  );
  await settle(tester, rounds: 6);
  return session;
}

/// 存盘里的页面（改完停手一会儿才存：先等存完）。
Future<LcDocument> lbSaved(WidgetTester tester, ProjectSession session) async {
  await waitLowcodeSaved(tester);
  expect(find.textContaining('没存上', skipOffstage: false), findsNothing, reason: '存盘失败了');
  late String text;
  await tester.runAsync(() async => text = File(session.guard.resolve(kLowcodePageFile)).readAsStringSync());
  return LcDocument.parse(text);
}

Future<void> lbTap(WidgetTester tester, Finder f) async {
  expect(f, findsWidgets, reason: '要点的东西不在界面上');
  await tester.tap(f, warnIfMissed: false);
  await settle(tester, rounds: 2);
}

/// 长按 [at] 把东西拿起来（280 毫秒，多等一点）。返回的手势还按着。
Future<TestGesture> lbLift(WidgetTester tester, Offset at) async {
  final g = await tester.startGesture(at);
  await tester.pump(const Duration(milliseconds: 320));
  await tester.pump();
  return g;
}

Future<void> lbOpenPalette(WidgetTester tester) async {
  await tester.tap(lbKey('lc-tool-add'));
  await tester.pumpAndSettle();
}

Finder lbPaletteItem(String key) => lbKey('palette-item-$key');

/// 打开合一面板的“常用”页（已经开着就不动）。
Future<void> lbOpenCommon(WidgetTester tester) async {
  if (lbKey('lc-inspector').evaluate().isEmpty) await lbTap(tester, find.widgetWithText(FilledButton, '常用'));
  expect(lbKey('lc-inspector'), findsOneWidget);
}

/// 把面板里的某一行滚出来。
Future<void> lbShow(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pump();
}

/// 面板里的东西：先滚出来再点（面板只露半屏，靠上靠下的行可能被挡着）。
Future<void> lbTapShown(WidgetTester tester, Finder f) async {
  await lbShow(tester, f);
  await lbTap(tester, f);
}

/// 搭建台里的一句提示条（字里含 [text]）：在界面上、点得到（没被面板、弹层挡住），整条在工具条上面，撤销、重做没被它盖住。
/// [undoShown]＝这个界面上此刻本来就有撤销、重做（盖着确认框、组件编辑页的时候没有，就不查这一条）。
void lbHintAbove(WidgetTester tester, String text, {bool undoShown = true}) {
  final hint = find.textContaining(text);
  expect(hint, findsOneWidget, reason: '“$text”：提示没出来');
  expect(hint.hitTestable(), findsOneWidget, reason: '“$text”：提示被别的东西挡住了');
  final bar = lbKey('lc-toolbar');
  if (bar.evaluate().isNotEmpty) {
    expect(tester.getRect(hint).bottom, lessThanOrEqualTo(tester.getRect(bar.last).top), reason: '“$text”：提示盖到工具条上了');
  }
  final size = tester.view.physicalSize / tester.view.devicePixelRatio;
  final r = tester.getRect(hint);
  expect(r.left >= 0 && r.right <= size.width && r.top >= 0 && r.bottom <= size.height, isTrue, reason: '“$text”：提示有一部分在屏幕外 $r');
  if (!undoShown) return;
  for (final tip in ['撤销', '重做']) {
    expect(find.byTooltip(tip).hitTestable(), findsWidgets, reason: '“$text”：$tip 被挡住了');
  }
}
