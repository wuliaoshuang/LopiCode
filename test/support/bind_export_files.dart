import 'package:lopicode/lowcode/export_dart.dart';
import 'package:lopicode/lowcode/export_pages.dart';
import 'package:lopicode/lowcode/export_react.dart';
import 'package:lopicode/lowcode/export_vue.dart';
import 'package:lopicode/lowcode/model.dart';

/// 一份文档四种导出的全部文件：`html/…`、`vue/…`、`react/…`、`flutter/page.dart`。
Map<String, String> allExportFiles(LcDocument doc) => {
  for (final p in exportHtmlPages(doc)) ...{'html/${p.htmlName}': p.files.html, 'html/${p.cssName}': p.files.css, if (p.files.js.isNotEmpty) 'html/${p.jsName}': p.files.js},
  for (final f in exportVue(doc).files) 'vue/${f.path}': f.content,
  for (final f in exportReact(doc).files) 'react/${f.path}': f.content,
  'flutter/page.dart': exportDart(doc),
};

/// 只要某一种的（去掉前缀）。
Map<String, String> exportFilesOf(LcDocument doc, String kind) => {
  for (final e in allExportFiles(doc).entries)
    if (e.key.startsWith('$kind/')) e.key.substring(kind.length + 1): e.value,
};
