import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/format/format.dart';
import 'package:lopicode/lowcode/export_html.dart';
import 'package:lopicode/lowcode/export_tidy.dart';
import 'package:lopicode/lowcode/model.dart';

import 'support/lowcode_samples.dart';

void main() {
  for (final entry in {'起步页面': LcDocument.starter('页'), '带逻辑和组件的样本': frameworkSample()}.entries) {
    test('${entry.key}：落盘的网页文件排过版，再排一次不变，逻辑标记还在开头', () {
      final raw = exportHtml(entry.value);
      final out = tidyHtmlExport(raw);
      expect(formatCode(out.html, 'html').problem, isNull);
      expect(formatCode(out.html, 'html').changed, isFalse);
      expect(formatCode(out.css, 'css').changed, isFalse);
      // 排版只动空白：去掉所有空白后和原文一样。
      String squash(String s) => s.replaceAll(RegExp(r'\s+'), '');
      expect(squash(out.html), squash(raw.html));
      expect(squash(out.js), squash(raw.js));
      if (raw.js.isNotEmpty) {
        expect(out.js.startsWith(kLowcodeLogicMarker), isTrue);
        expect(formatCode(out.js, 'js').changed, isFalse);
      }
    });
  }
}
