// 把磁盘上的一个库文件夹读成“相对路径 → 内容”的表（库的读入器 libRead 吃的就是这张表）。
import 'dart:io';

Map<String, String> libFilesFromDir(String dir) {
  final root = Directory(dir);
  return {for (final f in root.listSync(recursive: true).whereType<File>()) f.path.substring(root.path.length + 1).replaceAll(r'\', '/'): f.readAsStringSync()};
}
