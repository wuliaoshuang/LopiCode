// 旧页面的导出结果钉住（页面文件格式升第 3 版的时候加的）。
//
// test/fixtures/lowcode/export-baseline/ 下面是第 1 版、第 2 版样例页面和“登录页”样例，在格式还是第 2 版的代码上
// （提交 e8fb601）导出的网页 / Vue / React / Flutter 原文。以后不管格式和导出器怎么加东西，这些旧页面导出来必须一个字节都不变。
// 基准文件不许重新生成（除非霜霜明确同意旧页面的导出可以变）。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/lowcode/export_dart.dart';
import 'package:lopicode/lowcode/export_html.dart';
import 'package:lopicode/lowcode/export_react.dart';
import 'package:lopicode/lowcode/export_vue.dart';
import 'package:lopicode/lowcode/model.dart';

import 'support/sample_doc.dart';

const _dir = 'test/fixtures/lowcode/export-baseline';

Map<String, String> exportsOf(LcDocument doc) {
  final html = exportHtml(doc);
  return {
    'web/index.html': html.html,
    'web/style.css': html.css,
    'web/logic.js': html.js,
    'flutter/page.dart.txt': exportDart(doc, className: 'OldPage'),
    for (final f in exportVue(doc).files) 'vue/${f.path}': f.content,
    for (final f in exportReact(doc).files) 'react/${f.path}': f.content,
  };
}

void main() {
  final docs = <String, LcDocument Function()>{
    'page-v1': () => LcDocument.parse(File('test/fixtures/lowcode/page-v1.lc.json').readAsStringSync()),
    'page-v2': () => LcDocument.parse(File('test/fixtures/lowcode/page-v2.lc.json').readAsStringSync()),
    'sample': sample,
  };
  final generate = Platform.environment['LOPI_GEN_BASELINE'] == '1';

  for (final entry in docs.entries) {
    test('${entry.key}：网页 / Vue / React / Flutter 导出和格式第 2 版时逐字节一样', () {
      final out = exportsOf(entry.value());
      if (generate) {
        for (final f in out.entries) {
          File('$_dir/${entry.key}/${f.key}')
            ..createSync(recursive: true)
            ..writeAsStringSync(f.value);
        }
        return;
      }
      final base = Directory('$_dir/${entry.key}');
      final onDisk = [
        for (final f in base.listSync(recursive: true))
          if (f is File) f.path.substring(base.path.length + 1),
      ]..sort();
      expect((out.keys.toList()..sort()), onDisk, reason: '导出的文件清单变了');
      for (final f in out.entries) {
        expect(f.value, File('$_dir/${entry.key}/${f.key}').readAsStringSync(), reason: '${entry.key} 的 ${f.key} 变了');
      }
    });

    test('${entry.key}：存成第 3 版再打开，导出还是逐字节一样', () {
      if (generate) return;
      final again = LcDocument.parse(entry.value().encode());
      final out = exportsOf(again);
      for (final f in out.entries) {
        expect(f.value, File('$_dir/${entry.key}/${f.key}').readAsStringSync(), reason: '${entry.key} 的 ${f.key} 变了');
      }
    });
  }
}
