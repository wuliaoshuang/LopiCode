/// 把导出的主题文本存成工作区里的文件：`exports/主题-名字-日期-时间.lopitheme.json`。
/// 位置和“整段对话导出”“消息存成文件”是同一个 exports/ 目录（lib/session/chat_export.dart），在“文件”页能看到。
library;

import 'dart:convert';
import 'dart:io';

import 'package:lopicode/core/path_guard.dart';

/// 主题文件的扩展名。
const String kThemeFileSuffix = '.lopitheme.json';

/// 名字里能进文件名的部分：去掉路径分隔符和各系统不许用的字符，空了就叫“主题”，最多 24 个字。
String themeFileStem(String name) {
  final cleaned = name.trim().replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), '').replaceAll(RegExp(r'\s+'), '-').replaceAll(RegExp(r'^\.+'), '');
  final stem = cleaned.isEmpty ? '主题' : cleaned;
  return String.fromCharCodes(stem.runes.take(24));
}

/// 写进工作区的 exports/，返回相对路径。同一秒里已经有同名文件就在后面加序号，不盖掉上一份。
Future<String> writeThemeExport(PathGuard guard, String text, {required String name, DateTime? now}) async {
  final t = now ?? DateTime.now();
  String two(int v) => v.toString().padLeft(2, '0');
  final base = 'exports/主题-${themeFileStem(name)}-${t.year}${two(t.month)}${two(t.day)}-${two(t.hour)}${two(t.minute)}${two(t.second)}';
  var rel = '$base$kThemeFileSuffix';
  for (var n = 2; n < 100 && await File(guard.resolve(rel)).exists(); n++) {
    rel = '$base-$n$kThemeFileSuffix';
  }
  final file = File(guard.resolve(rel));
  await file.parent.create(recursive: true);
  await file.writeAsString(text);
  return rel;
}

/// 文本按 UTF-8 存下来有多少字节。
int themeTextBytes(String text) => utf8.encode(text).length;

/// 给人看的大小：不到 1MB 写 KB，否则写 MB。
String formatThemeBytes(int bytes) => bytes < 1024 * 1024 ? '${(bytes / 1024).toStringAsFixed(1)} KB' : '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
