// 轻提示小胶囊的底色不写死：从页面主题变量起步那一套的正文色算出来，结果和导出网页里的 rgba(34, 36, 53, .92) 是同一个色。
import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/lowcode/canvas_v3_widgets.dart';

void main() {
  test('画布上轻提示的底色＝正文色盖上 92% 不透明（和导出网页里那一个相同）', () {
    expect(lcToastBg().toARGB32(), 0xEB222435);
  });
}
