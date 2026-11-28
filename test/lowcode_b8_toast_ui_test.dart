// 第四轮 B8：轻提示（弹窗的第三种样子）一步步点出来——
// 组件盒“布局”里点“轻提示”→ 画布换成“正在编辑轻提示”（页面下方一颗深色小胶囊，没有遮罩）→ 面板里改那句话、改几秒消失
// → 退出 → 选按钮 › 事件 ›“点击时打开弹窗”› 选这个轻提示 → 项目里导出的网页带着它。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/lowcode/model_v3_components.dart';
import 'package:material_ui/material_ui.dart';

import 'support/b8_ui.dart';
import 'support/harness.dart';
import 'support/lowcode_builder.dart';

void main() {
  setUpAll(() async => lbFontsLoaded = await loadRealFonts());

  testWidgets('轻提示：组件盒里放一个 → 改话、改秒数 → 给按钮接上“点了就出来” → 导出的网页里有', (tester) async {
    final s = await lbOpen(
      tester,
      doc: b8Page([
        b8Node('save', 'button', {'text': '保存'}),
      ]),
    );
    await b8Add(tester, 'layout', 'toast');
    var doc = await lbSaved(tester, s);
    final toast = doc.root.children.last;
    expect(toast.type, 'dialog');
    expect(lcIsToast(toast), isTrue);
    expect(toast.props['text'], '已保存');
    // 画布：只看这个轻提示；一颗小胶囊在页面下半边，没有“确定”按钮
    await b8Until(tester, lbKey('lc-overlay-bar'), '“正在编辑轻提示”横条');
    expect(find.textContaining('正在编辑轻提示：已保存'), findsOneWidget);
    expect(find.text('确定'), findsNothing);
    // 只看弹层时画布上没有页面那一层，拿屏幕（390×844）来比。
    final pill = tester.getRect(lbNode(toast.id).first);
    expect(pill.center.dy, greaterThan(422), reason: '在屏幕下半边：$pill');
    expect(pill.width, lessThan(390 - 32));
    expect(pill.left, greaterThanOrEqualTo(0));
    expect(pill.right, lessThanOrEqualTo(390));
    await lbShot(tester, b8ShotDir, 'b8-toast-canvas');

    // 面板：只有那句话、样子、几秒消失、一打开就出现、怎么让它出现
    await lbOpenCommon(tester);
    expect(lbKey('lc-common-variant-toast'), findsOneWidget);
    expect(lbKey('lc-common-seconds-2'), findsOneWidget);
    expect(lbKey('lc-toast-how'), findsOneWidget);
    expect(find.text('确定按钮'), findsNothing);
    expect(find.text('点外关闭'), findsNothing);
    await tester.enterText(find.descendant(of: find.byKey(ValueKey('${toast.id}-text')), matching: find.byType(EditableText)), '存好了');
    await tester.pump(const Duration(milliseconds: 450));
    await settle(tester, rounds: 3);
    await lbTapShown(tester, lbKey('lc-common-seconds-3'));
    doc = await lbSaved(tester, s);
    expect(doc.find(toast.id)!.props['text'], '存好了');
    expect(doc.find(toast.id)!.props['seconds'], 3);
    expect(find.textContaining('正在编辑轻提示：存好了'), findsOneWidget);
    await lbShot(tester, b8ShotDir, 'b8-toast-inspector');

    // 样子一行能换成普通弹窗、再换回来（同一个东西的三种样子）
    await lbTapShown(tester, lbKey('lc-common-variant-alert'));
    expect(lcIsToast((await lbSaved(tester, s)).find(toast.id)!), isFalse);
    await b8Until(tester, find.text('确定按钮'), '弹窗的那几行');
    await lbTapShown(tester, lbKey('lc-common-variant-toast'));
    expect(lcIsToast((await lbSaved(tester, s)).find(toast.id)!), isTrue);

    // 退出，给“保存”按钮接上
    await b8Tap(tester, lbKey('lc-overlay-exit'));
    await b8Until(tester, find.textContaining('轻提示 · 存好了'), '页面里的轻提示小标签');
    await b8Tap(tester, lbNode('save'));
    await lbOpenCommon(tester);
    await lbTap(tester, find.text('事件'));
    await lbTapShown(tester, lbKey('lc-quick-openDialog'));
    expect(find.textContaining('轻提示“存好了”'), findsWidgets);
    await lbShot(tester, b8ShotDir, 'b8-toast-pick');
    await lbTap(tester, lbKey('lc-quick-dialog-0'));
    doc = await lbSaved(tester, s);
    expect(doc.logic.handlersFor('save').single.body.single.args['node'], toast.id);

    // 项目里导出的网页（应用内“预览”读的就是它）
    final files = await b8PreviewFiles(tester, s);
    expect(files['index.html'], contains('data-variant="toast"'));
    expect(files['index.html'], contains('存好了'));
    expect(files['style.css'], contains('@keyframes lc-toast'));
    expect(tester.takeException(), isNull);
  });
}
