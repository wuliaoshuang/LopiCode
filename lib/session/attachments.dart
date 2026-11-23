// 聊天里的图片附件：能带哪些、存到哪。
import 'dart:io';

import 'package:lopicode/core/path_guard.dart';
import 'package:path/path.dart' as p;

/// 一条消息最多带几张图片。
const int kMaxAttachments = 9;

/// 单张图片的大小上限。
const int kMaxAttachmentBytes = 8 * 1024 * 1024;

/// 工作区里放附件的目录。
const String kAttachmentsDir = '.lopicode-attachments';

/// 按扩展名判断图片类型；不是支持的图片返回 null。
String? imageMimeOf(String name) => switch (p.extension(name).toLowerCase()) {
  '.png' => 'image/png',
  '.jpg' || '.jpeg' => 'image/jpeg',
  '.gif' => 'image/gif',
  '.webp' => 'image/webp',
  _ => null,
};

/// 把选中的图片存进工作区的附件目录，返回消息里要带的 `{path, mime}`。
Future<Map<String, dynamic>> saveAttachment(PathGuard guard, List<int> bytes, String name) async {
  final mime = imageMimeOf(name);
  if (mime == null) throw const FormatException('只支持 png、jpg、gif、webp 图片');
  if (bytes.length > kMaxAttachmentBytes) throw const FormatException('图片太大（上限 8MB）');
  final rel = '$kAttachmentsDir/${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}${p.extension(name).toLowerCase()}';
  final file = File(guard.resolve(rel));
  await file.parent.create(recursive: true);
  await file.writeAsBytes(bytes);
  return {'path': rel, 'mime': mime};
}

/// 引用工作区里已有的图片文件当附件（工作区外的路径会被路径守卫拦下）。
Map<String, dynamic> attachWorkspaceFile(PathGuard guard, String rel) {
  final mime = imageMimeOf(rel);
  if (mime == null) throw const FormatException('只支持 png、jpg、gif、webp 图片');
  guard.resolve(rel);
  return {'path': rel, 'mime': mime};
}
