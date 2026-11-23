import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

class TarException implements Exception {
  TarException(this.message);
  final String message;
  @override
  String toString() => message;
}

class TarResult {
  int files = 0;
  int directories = 0;
  int symlinks = 0;
  int hardlinks = 0;
  int skipped = 0;
  int bytes = 0;
}

/// 给一批文件加可执行权限。默认调用系统的 chmod（Android 和 Linux 都有）。
typedef MakeExecutable = Future<void> Function(List<String> paths);

Future<void> chmodExecutable(List<String> paths) async {
  for (var i = 0; i < paths.length; i += 200) {
    final batch = paths.sublist(i, i + 200 > paths.length ? paths.length : i + 200);
    final result = await Process.run('chmod', ['755', ...batch]);
    if (result.exitCode != 0) throw TarException('设置可执行权限失败：${result.stderr}'.trim());
  }
}

/// 把 .tar.gz 解到 [destination]。边读边解，不把整个包读进内存。
///
/// 手机上的限制决定了几处取舍：
/// - 应用目录里不允许建硬链接，包里的硬链接按“复制一份”处理；
/// - 文件属主一律不管（进环境后由 PRoot 假装成 root）；
/// - 权限只保留“可执行”这一位，目录权限不照搬（照搬只读目录以后就写不进去了）；
/// - 设备文件、管道跳过（/dev 进环境时整个绑定手机的）。
/// 路径想跳出目标目录的条目直接拒绝。
Future<TarResult> extractTarGz(
  File archive,
  Directory destination, {
  void Function(int consumed, int total)? onProgress,
  MakeExecutable makeExecutable = chmodExecutable,
  bool Function()? isCancelled,
}) async {
  final total = await archive.length();
  var consumed = 0;
  final raw = archive.openRead().map((chunk) {
    consumed += chunk.length;
    onProgress?.call(consumed, total);
    return chunk;
  });
  final reader = _ChunkReader(raw.transform(gzip.decoder));
  final result = TarResult();
  final root = p.normalize(destination.absolute.path);
  await Directory(root).create(recursive: true);
  final executables = <String>[];
  final pendingLinks = <(String, String)>[];
  String? longName;
  String? longLink;
  Map<String, String> pax = {};

  String resolve(String name) {
    final cleaned = p.normalize(p.join(root, name));
    if (cleaned != root && !p.isWithin(root, cleaned)) throw TarException('压缩包里有越界的路径：$name');
    return cleaned;
  }

  try {
    while (true) {
      if (isCancelled?.call() ?? false) throw TarException('已取消解压');
      final header = await reader.read(512);
      if (header == null) break;
      if (header.every((b) => b == 0)) break;
      var name = _text(header, 0, 100);
      final prefix = _text(header, 345, 155);
      if (prefix.isNotEmpty && _text(header, 257, 5) == 'ustar') name = '$prefix/$name';
      final mode = _octal(header, 100, 8);
      var size = _octal(header, 124, 12);
      final type = header[156] == 0 ? '0' : String.fromCharCode(header[156]);
      var link = _text(header, 157, 100);
      final padded = (size + 511) ~/ 512 * 512;

      if (type == 'L' || type == 'K' || type == 'x' || type == 'g') {
        final data = await reader.read(padded);
        if (data == null) throw TarException('压缩包不完整（扩展头被截断）');
        final body = data.sublist(0, size);
        if (type == 'L') longName = _cstring(body);
        if (type == 'K') longLink = _cstring(body);
        if (type == 'x') pax = _parsePax(body);
        continue;
      }
      name = pax['path'] ?? longName ?? name;
      link = pax['linkpath'] ?? longLink ?? link;
      if (pax['size'] != null) size = int.parse(pax['size']!);
      longName = null;
      longLink = null;
      pax = {};
      final dataLength = (size + 511) ~/ 512 * 512;

      if (name.isEmpty || name == '.' || name == './') {
        await reader.skip(dataLength);
        continue;
      }
      final path = resolve(name);
      switch (type) {
        case '5':
          await Directory(path).create(recursive: true);
          result.directories++;
          await reader.skip(dataLength);
        case '0' || '7':
          await Directory(p.dirname(path)).create(recursive: true);
          await _removeExisting(path);
          final sink = File(path).openWrite();
          var left = size;
          try {
            while (left > 0) {
              final chunk = await reader.readUpTo(left);
              if (chunk == null) throw TarException('压缩包不完整（$name 被截断）');
              sink.add(chunk);
              left -= chunk.length;
            }
          } finally {
            await sink.close();
          }
          await reader.skip(dataLength - size);
          if (mode & 0x49 != 0) executables.add(path); // 0111：任何一位可执行
          result.files++;
          result.bytes += size;
        case '2':
          await Directory(p.dirname(path)).create(recursive: true);
          await _removeExisting(path);
          await Link(path).create(link);
          result.symlinks++;
          await reader.skip(dataLength);
        case '1':
          pendingLinks.add((path, resolve(link)));
          await reader.skip(dataLength);
        default:
          result.skipped++;
          await reader.skip(dataLength);
      }
    }
  } on FormatException catch (e) {
    throw TarException('压缩包损坏：${e.message}');
  } on FileSystemException catch (e) {
    throw TarException('写文件失败：${e.osError?.message ?? e.message}（${e.path ?? ''}）');
  } finally {
    await reader.cancel();
  }

  try {
    for (final (path, source) in pendingLinks) {
      final file = File(source);
      if (!await file.exists()) throw TarException('压缩包里的硬链接指向不存在的文件：$source');
      await Directory(p.dirname(path)).create(recursive: true);
      await _removeExisting(path);
      await file.copy(path);
      if (executables.contains(source)) executables.add(path);
      result.hardlinks++;
    }
  } on FileSystemException catch (e) {
    throw TarException('写文件失败：${e.osError?.message ?? e.message}（${e.path ?? ''}）');
  }
  if (executables.isNotEmpty) await makeExecutable(executables);
  return result;
}

Future<void> _removeExisting(String path) async {
  final type = await FileSystemEntity.type(path, followLinks: false);
  switch (type) {
    case FileSystemEntityType.notFound:
      return;
    case FileSystemEntityType.directory:
      await Directory(path).delete(recursive: true);
    case FileSystemEntityType.link:
      await Link(path).delete();
    default:
      await File(path).delete();
  }
}

String _cstring(List<int> bytes) {
  final end = bytes.indexOf(0);
  return utf8.decode(end < 0 ? bytes : bytes.sublist(0, end), allowMalformed: true);
}

String _text(Uint8List header, int offset, int length) => _cstring(Uint8List.sublistView(header, offset, offset + length));

int _octal(Uint8List header, int offset, int length) {
  if (header[offset] & 0x80 != 0) {
    // GNU 的二进制写法（超大文件）
    var value = header[offset] & 0x7f;
    for (var i = 1; i < length; i++) {
      value = (value << 8) | header[offset + i];
    }
    return value;
  }
  final text = _text(header, offset, length).trim();
  if (text.isEmpty) return 0;
  return int.parse(text, radix: 8);
}

Map<String, String> _parsePax(List<int> body) {
  final out = <String, String>{};
  var i = 0;
  while (i < body.length) {
    final space = body.indexOf(0x20, i);
    if (space < 0) break;
    final length = int.tryParse(ascii.decode(body.sublist(i, space), allowInvalid: true));
    if (length == null || length <= 0 || i + length > body.length) break;
    final record = utf8.decode(body.sublist(space + 1, i + length - 1), allowMalformed: true);
    final eq = record.indexOf('=');
    if (eq > 0) out[record.substring(0, eq)] = record.substring(eq + 1);
    i += length;
  }
  return out;
}

/// 从字节流里按需要的长度取数据。
class _ChunkReader {
  _ChunkReader(Stream<List<int>> stream) : _it = StreamIterator(stream);
  final StreamIterator<List<int>> _it;
  List<int> _current = const [];
  int _offset = 0;

  Future<bool> _fill() async {
    while (_offset >= _current.length) {
      if (!await _it.moveNext()) return false;
      _current = _it.current;
      _offset = 0;
    }
    return true;
  }

  /// 最多取 [max] 字节（至少 1 字节）；流结束返回 null。
  Future<List<int>?> readUpTo(int max) async {
    if (!await _fill()) return null;
    final available = _current.length - _offset;
    final take = available < max ? available : max;
    final chunk = _current.sublist(_offset, _offset + take);
    _offset += take;
    return chunk;
  }

  /// 正好取 [length] 字节；一个字节都没有时返回 null，取到一半流断了抛错。
  Future<Uint8List?> read(int length) async {
    final out = Uint8List(length);
    var filled = 0;
    while (filled < length) {
      final chunk = await readUpTo(length - filled);
      if (chunk == null) {
        if (filled == 0) return null;
        throw TarException('压缩包不完整（提前结束）');
      }
      out.setRange(filled, filled + chunk.length, chunk);
      filled += chunk.length;
    }
    return out;
  }

  Future<void> skip(int length) async {
    var left = length;
    while (left > 0) {
      final chunk = await readUpTo(left);
      if (chunk == null) throw TarException('压缩包不完整（提前结束）');
      left -= chunk.length;
    }
  }

  Future<void> cancel() async {
    await _it.cancel();
  }
}
