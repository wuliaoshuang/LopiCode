// “常用”页的九宫格对齐（第四轮 B3 补的逐步点击测试；390×844）：选中一个横排，点九宫格的格子，
// 存盘里的“主轴 / 交叉轴对齐”跟着变；四种导出里对齐也跟着变。
import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/lowcode/export_html.dart';
import 'package:lopicode/lowcode/model.dart';
import 'package:lopicode/lowcode/style_resolve.dart';

import 'support/harness.dart';
import 'support/lowcode_builder.dart';
import 'support/node_find.dart';
import 'support/pages_sample.dart';

Map<String, String> _styleOf(LcDocument d, String id) => resolvedStyle(nodeIn(d.root, id)!, d.root);

void main() {
  setUpAll(() async => lbFontsLoaded = await loadRealFonts());

  testWidgets('横排：点右下那一格 → 靠右、靠下；再点正中 → 都居中；存盘和导出跟着变', (tester) async {
    // 横排被里面的控件占满，点不到它自己：打开时就选中它。
    final session = await lbOpen(tester, doc: pagesSample(), selected: 'line');
    await lbOpenCommon(tester);
    await lbTapShown(tester, lbKey('lc-align-2-2'));
    var saved = await lbSaved(tester, session);
    expect(_styleOf(saved, 'line')['justify-content'], 'flex-end');
    expect(_styleOf(saved, 'line')['align-items'], 'flex-end');

    await lbTapShown(tester, lbKey('lc-align-1-1'));
    saved = await lbSaved(tester, session);
    expect(_styleOf(saved, 'line')['justify-content'], 'center');
    expect(_styleOf(saved, 'line')['align-items'], 'center');
    final css = exportHtml(saved).css;
    expect(RegExp(r'line[^{}]*\{[^}]*justify-content: center').hasMatch(css), isTrue, reason: css);
    expect(RegExp(r'line[^{}]*\{[^}]*align-items: center').hasMatch(css), isTrue, reason: css);
  });
}
