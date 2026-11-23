// 存盘文件的两条规矩（AGENTS.md 里也写了）：
// 1. 写：先写到同目录的临时文件，写完再改名盖过去。中途断电 / 被杀，原文件还是完整的旧内容，不会剩半截。
// 2. 读：文件在但读不懂（半截、乱码、不是预期的形状）时，先把它另存一份 `.bad-时间` 再回退默认值，
//    不让下一次保存把唯一的原件悄悄盖掉。
import 'dart:convert';
import 'dart:io';

import 'package:lopicode/core/crash_log.dart';

/// 同一个文件的写入排队做，免得两次写抢同一个临时文件。
final Map<String, Future<void>> _writeQueue = {};

/// 原子写：临时文件 → flush → 改名。目录不存在会先建。
Future<void> writeFileAtomic(File file, List<int> bytes) {
  final key = file.absolute.path;
  final previous = _writeQueue[key] ?? Future<void>.value();
  late final Future<void> mine;
  mine = previous.catchError((Object _) {}).then((_) => _writeNow(file, bytes)).whenComplete(() {
    if (identical(_writeQueue[key], mine)) _writeQueue.remove(key);
  });
  _writeQueue[key] = mine;
  return mine;
}

Future<void> _writeNow(File file, List<int> bytes) async {
  await file.parent.create(recursive: true);
  final tmp = File('${file.path}.tmp');
  try {
    await tmp.writeAsBytes(bytes, flush: true);
    await tmp.rename(file.path);
  } on FileSystemException {
    // 改名失败（个别文件系统不让盖）：清掉临时文件，把错误交给调用方
    try {
      if (await tmp.exists()) await tmp.delete();
    } on FileSystemException {
      // 清不掉就留着，下次写会盖掉它
    }
    rethrow;
  }
}

Future<void> writeStringAtomic(File file, String text) => writeFileAtomic(file, utf8.encode(text));

Future<void> writeJsonAtomic(File file, Object? value) => writeStringAtomic(file, jsonEncode(value));

/// 最多留几份坏文件备份（再多就删最旧的，免得占地方）。
const int kMaxBadBackups = 3;

/// 读一个 JSON 存盘文件。
///
/// - 文件不存在 → null。
/// - 读得懂且 [accept] 认可（不传就都认）→ 解出来的值。
/// - 读不懂 / 形状不对 → 把原文件另存为 `名字.bad-时间戳`，记一条日志，返回 null（调用方回退默认值）。
///
/// 绝不抛异常：存盘文件坏了不能让应用起不来。
Future<Object?> readJsonFile(File file, {bool Function(Object? decoded)? accept, String? label}) async {
  final String text;
  try {
    if (!await file.exists()) return null;
    text = await file.readAsString();
  } on Exception catch (e, st) {
    // 读都读不了（权限、不是合法 UTF-8…）
    CrashLog.instance.record(e, st, source: '读取 ${label ?? file.uri.pathSegments.last}');
    await _backupBad(file);
    return null;
  }
  if (text.trim().isEmpty) {
    // 空文件：多半是上次写到一半。没内容可备份，直接当没有。
    return null;
  }
  try {
    final decoded = jsonDecode(text);
    if (accept == null || accept(decoded)) return decoded;
    CrashLog.instance.note('${label ?? file.uri.pathSegments.last} 的内容不是预期的格式，已备份并改用默认值');
  } on FormatException catch (e) {
    CrashLog.instance.note('${label ?? file.uri.pathSegments.last} 读不懂（${e.message}），已备份并改用默认值');
  }
  await _backupBad(file);
  return null;
}

Future<void> _backupBad(File file) async {
  try {
    if (!await file.exists()) return;
    final stamp = DateTime.now().toUtc().toIso8601String().replaceAll(RegExp(r'[^0-9]'), '').substring(0, 14);
    var target = File('${file.path}.bad-$stamp');
    for (var i = 1; await target.exists(); i++) {
      target = File('${file.path}.bad-$stamp-$i');
    }
    await file.copy(target.path);
    // 只留最新的几份
    final prefix = '${file.uri.pathSegments.last}.bad-';
    final olds = [
      await for (final e in file.parent.list())
        if (e is File && e.uri.pathSegments.last.startsWith(prefix)) e,
    ]..sort((a, b) => a.path.compareTo(b.path));
    for (final old in olds.take(olds.length > kMaxBadBackups ? olds.length - kMaxBadBackups : 0)) {
      await old.delete();
    }
  } on FileSystemException {
    // 备份不了也不能影响启动
  }
}
