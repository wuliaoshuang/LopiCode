// 聊天输入栏的样子：真实字体下收起态仍是 48 高（真机字体行高比测试默认字体大，之前就是被它撑到 61 的）。
//   LOPI_SHOTS=1 flutter test test/chat_composer_shots_test.dart   # 同时写截图到 docs/screenshots/composer-*.png
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/composer_gallery.dart';
import 'support/harness.dart';

void main() {
  final shots = Platform.environment['LOPI_SHOTS'] == '1';
  var fonts = false;
  setUpAll(() async => fonts = await loadRealFonts());

  for (final brightness in Brightness.values) {
    testWidgets('输入栏三种样子 · ${brightness.name}', (tester) async {
      tester.view.physicalSize = const Size(390, 300) * 3;
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ComposerGallery(brightness: brightness, font: fonts ? kTestFont : null));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      final inputs = find.byKey(const ValueKey('chat-input'));
      expect(inputs, findsNWidgets(3));
      // 量看得见的那一块（带边框，不含外边距）
      Size capsule(int i) => tester.getSize(find.descendant(of: inputs.at(i), matching: find.byType(DecoratedBox)).first);
      expect(capsule(0).height, 48, reason: '收起');
      expect(capsule(1).height, 48, reason: '收起带用量小环');
      expect(capsule(2).height, greaterThan(90), reason: '有草稿：展开两行');
      if (shots && fonts) await writeShot(tester, 'composer-after-${brightness.name}');
    });
  }
}
