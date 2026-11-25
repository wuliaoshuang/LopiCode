// 命令输出太长时转存成文件：完整输出放到工作区的 `.lopicode/outputs/` 里，回给模型的只有开头 + 结尾 + 文件路径。
// 别的工具的超长结果也存在这里（文件名以 `tool-` 开头，见 tool_output_spill.dart）；后台命令的日志（`bg-`）有自己的规矩，这里不碰。
//
// 规矩：
// - 文件只由应用自己写（原子写）；Agent 只能用 read_file 读这个目录，不能写、不能删（见 agent_tools.dart 的 _read）。
// - 自动清理：最多留 [kKeepOutputFiles] 份，总大小不超过 [kMaxOutputsBytes]，超了从最旧的删。
// - 存不了（磁盘满、目录建不出来）不影响命令结果：退回原来的“只留结尾”。
import 'dart:io';

import 'package:lopicode/core/path_guard.dart';
import 'package:lopicode/core/safe_file.dart';
import 'package:path/path.dart' as p;

/// 转存目录（工作区内的相对路径）。
const String kOutputsDir = '${PathGuard.reservedDir}/outputs';

/// 最多留几份转存的输出。
const int kKeepOutputFiles = 20;

/// 转存的输出合计最多占多少字节（20 MB）。
const int kMaxOutputsBytes = 20 * 1024 * 1024;

/// 超长时回给模型的开头、结尾各多少字符（合起来就是命令输出的上限 8000）。
const int kOutputHeadChars = 2000;
const int kOutputTailChars = 6000;

/// [rel]（已经规范化的工作区内相对路径）是不是转存目录里的文件。
bool isCommandOutputPath(String rel) => rel.startsWith('$kOutputsDir/') && rel.endsWith('.txt') && !rel.substring(kOutputsDir.length + 1).contains('/');

final RegExp _pathInResult = RegExp('${RegExp.escape(kOutputsDir)}/(?:cmd|tool)-[0-9a-z-]+\\.txt');

/// 从工具结果的文字里找出转存文件的路径（步骤详情的“查看完整输出”用）；没有转存过是 null。
String? spilledOutputPathOf(String? result) => result == null ? null : _pathInResult.firstMatch(result)?.group(0);

/// 超长输出回给模型的样子：开头 + 结尾，中间说明省了多少、完整的在哪、怎么读。
/// [rel] 为 null（没存成）时只说省略了多少。
String spilledOutputText(String output, String? rel) {
  final head = output.substring(0, kOutputHeadChars);
  final tail = output.substring(output.length - kOutputTailChars);
  final skipped = output.length - kOutputHeadChars - kOutputTailChars;
  final lines = '\n'.allMatches(output).length + 1;
  final where = rel == null ? '（完整输出没能存成文件）' : '完整输出（共 ${output.length} 字符、$lines 行）已存到 $rel。需要看中间的内容时，用 read_file 读这个文件，并用 start_line / end_line 一段一段读，不要一次读完。';
  return '$head\n\n…（输出太长，中间省略了 $skipped 字符。$where）…\n\n$tail';
}

class CommandOutputStore {
  CommandOutputStore(this.guard);
  final PathGuard guard;

  static int _seq = 0;

  Directory get _dir => Directory(guard.resolve(kOutputsDir, allowReserved: true));

  /// 把完整输出存成文件，返回工作区内的相对路径；存不了返回 null。
  Future<String?> save(String command, String output) => _write('cmd', '\$ $command\n\n$output');

  /// 把别的工具的完整结果原样存成文件（不加抬头：行号和结果里的一致），返回相对路径；存不了返回 null。
  Future<String?> saveToolResult(String text) => _write('tool', text);

  Future<String?> _write(String kind, String content) async {
    try {
      final stamp = DateTime.now().toUtc().toIso8601String().replaceAll(RegExp('[^0-9]'), '').substring(0, 14);
      final name = '$kind-$stamp-${(_seq++).toRadixString(36)}.txt';
      final file = File(p.join(_dir.path, name));
      await writeStringAtomic(file, content);
      await cleanup();
      return '$kOutputsDir/$name';
    } on FileSystemException {
      return null;
    } on PathGuardException {
      return null;
    }
  }

  /// 读一份转存的输出（界面“查看完整输出”用）。被清理掉了、读不了返回 null。
  Future<String?> read(String rel) async {
    try {
      final full = guard.resolve(rel, allowReserved: true);
      if (!isCommandOutputPath(guard.relative(full))) return null;
      final file = File(full);
      if (!await file.exists()) return null;
      return await file.readAsString();
    } on FileSystemException {
      return null;
    } on PathGuardException {
      return null;
    } on FormatException {
      return null;
    }
  }

  /// 文件名（`cmd-时间-序号.txt` / `tool-时间-序号.txt`）里的先后：时间，再按序号的数值（序号是 36 进制，不能按字面比）。
  static (String, int)? _orderOf(String name) {
    final m = RegExp(r'^(?:cmd|tool)-(\d{14})-([0-9a-z]+)\.txt$').firstMatch(name);
    return m == null ? null : (m.group(1)!, int.parse(m.group(2)!, radix: 36));
  }

  /// 清理：命令输出和别的工具的结果合在一起算，只留最近 [kKeepOutputFiles] 份，合计不超过 [kMaxOutputsBytes]；最新的一份总是留着。
  /// 后台命令的日志（bg-）不归这里管。
  Future<void> cleanup() async {
    final dir = _dir;
    if (!await dir.exists()) return;
    final files = <(File, FileStat)>[];
    final order = <String, (String, int)>{};
    await for (final e in dir.list(followLinks: false)) {
      final at = e is File ? _orderOf(p.basename(e.path)) : null;
      if (e is! File || at == null) continue;
      order[e.path] = at;
      files.add((e, await e.stat()));
    }
    // 新的在前。
    files.sort((a, b) {
      final x = order[a.$1.path]!, y = order[b.$1.path]!;
      final byTime = y.$1.compareTo(x.$1);
      return byTime != 0 ? byTime : y.$2.compareTo(x.$2);
    });
    var total = 0;
    for (var i = 0; i < files.length; i++) {
      total += files[i].$2.size;
      if (i > 0 && (i >= kKeepOutputFiles || total > kMaxOutputsBytes)) {
        try {
          await files[i].$1.delete();
        } on FileSystemException {
          // 删不掉：下次再清
        }
      }
    }
  }
}
