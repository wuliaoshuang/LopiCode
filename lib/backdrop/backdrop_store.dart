// 背景图片的入库和存盘。
//
// - 图片只放在应用私有目录 `<设置所在目录>/appearance/background/` 下，设置里只记文件名，绝不引用外部路径。
// - 入库时校验文件头：只收 JPG / PNG / WebP。GIF 不收（动图当背景又费电又晃眼）；
//   安卓上原生那头遇到 GIF、HEIC 这些会先取第一帧转成 JPG / PNG 再交过来，所以真机上选 GIF 得到的是一张静态图。
// - 上限：原文件 ≤ 20MB；解码后长边 > 2560 像素的缩到 2560 再存（dart:ui 只会编 PNG，所以缩过的存成 PNG）。
// - 文件名带内容哈希；换图 / 移除后用 [BackdropStore.cleanup] 删掉没人引用的旧文件。
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:lopicode/backdrop/backdrop_model.dart';
import 'package:lopicode/core/safe_file.dart';
import 'package:path/path.dart' as p;

/// 原图文件最大多少字节才收（20MB）。
const int kBackdropMaxFileBytes = 20 * 1024 * 1024;

/// 存下来的图长边最多多少像素。
const int kBackdropMaxSide = 2560;

enum BackdropFormat {
  jpg('jpg'),
  png('png'),
  webp('webp'),
  gif('gif');

  const BackdropFormat(this.ext);
  final String ext;
}

/// 看文件头认格式；认不出返回 null。
BackdropFormat? sniffBackdropFormat(List<int> b) {
  bool at(int i, List<int> sig) {
    if (b.length < i + sig.length) return false;
    for (var k = 0; k < sig.length; k++) {
      if (b[i + k] != sig[k]) return false;
    }
    return true;
  }

  if (at(0, const [0xFF, 0xD8, 0xFF])) return BackdropFormat.jpg;
  if (at(0, const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])) return BackdropFormat.png;
  if (at(0, const [0x52, 0x49, 0x46, 0x46]) && at(8, const [0x57, 0x45, 0x42, 0x50])) return BackdropFormat.webp;
  if (at(0, const [0x47, 0x49, 0x46, 0x38])) return BackdropFormat.gif;
  return null;
}

/// 入库没成；[message] 能直接给用户看。
class BackdropImportException implements Exception {
  const BackdropImportException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// 入库好的一张图。
class ImportedBackdrop {
  const ImportedBackdrop({required this.file, required this.width, required this.height});

  /// 文件名（在 [BackdropStore.imageDir] 下）。
  final String file;
  final int width;
  final int height;
}

class BackdropStore {
  BackdropStore(this.baseDir);

  /// `<设置所在目录>/appearance`。
  final String baseDir;

  File get settingsFile => File(p.join(baseDir, 'background.json'));
  Directory get imageDir => Directory(p.join(baseDir, 'background'));
  File imageFile(String name) => File(p.join(imageDir.path, name));

  /// 读设置。文件没有 / 坏了都回默认值（坏文件由 readJsonFile 另存一份）。
  Future<BackdropSettings> load() async {
    final j = await readJsonFile(settingsFile, accept: (v) => v is Map, label: '背景图片设置');
    return BackdropSettings.fromJson(j);
  }

  Future<void> save(BackdropSettings s) => writeJsonAtomic(settingsFile, s.toJson());

  /// 把 [source]（缓存里的一份）校验后搬进私有目录。[deleteSource]：成不成都把源文件删掉（它只是缓存副本）。
  Future<ImportedBackdrop> importFile(File source, {bool deleteSource = true}) async {
    try {
      return await _import(source);
    } finally {
      if (deleteSource) {
        try {
          if (await source.exists()) await source.delete();
        } on FileSystemException {
          // 缓存副本删不掉不要紧，系统会清缓存
        }
      }
    }
  }

  Future<ImportedBackdrop> _import(File source) async {
    final Uint8List bytes;
    try {
      if (!await source.exists()) throw const BackdropImportException('选中的图片不见了，请再选一次。');
      final size = await source.length();
      if (size == 0) throw const BackdropImportException('这个图片文件是空的。');
      if (size > kBackdropMaxFileBytes) {
        throw BackdropImportException('这张图太大了（${(size / 1024 / 1024).toStringAsFixed(1)}MB，上限 ${kBackdropMaxFileBytes ~/ (1024 * 1024)}MB）。换一张小一点的。');
      }
      bytes = await source.readAsBytes();
    } on FileSystemException catch (e) {
      throw BackdropImportException('读不出这张图（${e.osError?.message ?? e.message}）。');
    }
    final format = sniffBackdropFormat(bytes);
    if (format == null) throw const BackdropImportException('这个文件不是能用的图片。请选 JPG、PNG 或 WebP。');
    if (format == BackdropFormat.gif) throw const BackdropImportException('不支持 GIF 动图当背景。请选 JPG、PNG 或 WebP。');

    // 真的解一遍：文件头对、内容坏了的在这里拦下；顺便拿到（已按拍摄方向摆正的）宽高。
    var out = bytes;
    var ext = format.ext;
    int width, height;
    try {
      final first = await _decode(bytes);
      width = first.width;
      height = first.height;
      first.dispose();
      final longSide = width > height ? width : height;
      if (width <= 0 || height <= 0) throw const BackdropImportException('这张图解不开，文件可能坏了。');
      if (longSide > kBackdropMaxSide) {
        final scale = kBackdropMaxSide / longSide;
        final w = (width * scale).round().clamp(1, kBackdropMaxSide);
        final h = (height * scale).round().clamp(1, kBackdropMaxSide);
        final small = await _decode(bytes, width: w, height: h);
        final data = await small.toByteData(format: ui.ImageByteFormat.png);
        width = small.width;
        height = small.height;
        small.dispose();
        if (data == null) throw const BackdropImportException('这张图缩小时出错了，换一张试试。');
        out = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
        ext = BackdropFormat.png.ext;
      }
    } on BackdropImportException {
      rethrow;
    } on Exception {
      throw const BackdropImportException('这张图解不开，文件可能坏了。');
    }

    final name = 'bg-${sha256.convert(out).toString().substring(0, 16)}.$ext';
    try {
      await writeFileAtomic(imageFile(name), out);
    } on FileSystemException catch (e) {
      throw BackdropImportException('存不下这张图（${e.osError?.message ?? e.message}）。手机存储空间可能不够了。');
    }
    return ImportedBackdrop(file: name, width: width, height: height);
  }

  static Future<ui.Image> _decode(Uint8List bytes, {int? width, int? height}) async {
    final codec = await ui.instantiateImageCodec(bytes, targetWidth: width, targetHeight: height);
    try {
      return (await codec.getNextFrame()).image;
    } finally {
      codec.dispose();
    }
  }

  /// 删掉图片目录里没被 [keep] 引用的文件（旧图、没用上的图、写到一半的临时文件）。删不掉的跳过。
  Future<void> cleanup(Set<String> keep) async {
    try {
      if (!await imageDir.exists()) return;
      await for (final e in imageDir.list()) {
        if (e is! File || keep.contains(p.basename(e.path))) continue;
        try {
          await e.delete();
        } on FileSystemException {
          // 占着就先留着，下次清理再删
        }
      }
    } on FileSystemException {
      // 目录都列不了：没什么可清的
    }
  }
}
