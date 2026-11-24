import 'package:lopicode/format/format.dart';
import 'package:lopicode/lowcode/export_html.dart';

/// 把导出的网页文件过一遍格式化器再落盘。
///
/// 格式化器自带保险：排完和原文对不上、或者解析不了，就原样返回——所以这里最坏的结果只是“没排版”，
/// 不会把导出的文件弄坏。`exportHtml` 本身的输出不变（旧页面的导出结果仍与以前逐字节相同），
/// 只有写进项目的文件是排过版的。
LcHtmlExport tidyHtmlExport(LcHtmlExport export) {
  return LcHtmlExport(formatCode(export.html, 'html').text, formatCode(export.css, 'css').text, export.js.isEmpty ? '' : formatCode(export.js, 'js').text);
}
