// edit_file 工具（局部改文件）和“改文件前先拍一张快照”的小工具。
//
// 权限不在这里判断：edit_file 在 AgentToolbox.coreKinds 里和 write_file 一样是 ToolKind.write，
// 仅可查看 / 计划模式 / 预设没勾 都由 AgentToolbox.blockReason 一处拦；
// 路径越界由 PathGuard 拦，团队写入范围由调用方传进来的 [checkScope]（AgentToolbox 的那一个）拦。
// 这里只管：读文件 → 找原文换新文（lib/agent/edit_match.dart）→ 写回 → 说清楚改了什么。
import 'dart:convert';
import 'dart:io';

import 'package:lopicode/agent/agent_tools.dart';
import 'package:lopicode/agent/edit_match.dart';
import 'package:lopicode/agent/line_diff.dart';
import 'package:lopicode/core/path_guard.dart';

/// 改之前的文件超过这么多字节就不读进来做对比（照样能写，只是没有红绿对比）。
const int kSnapshotMaxBytes = 2 * 1024 * 1024;

const String kEditFileTool = 'edit_file';

/// 发给模型的工具定义。
final Map<String, dynamic> editFileSpec = toolSpec(
  kEditFileTool,
  '修改项目里一个已有的文本文件的一部分：把 old_text 换成 new_text，文件其余部分不动。改已有文件优先用这个，不要用 write_file 整份重写。'
  'old_text 要照文件里的原样给（先 read_file 看过再改），并且只能对上一处——对上多处会拒绝，请多带几行上下文，或者把 replace_all 设为 true。'
  '缩进、行尾空格略有出入也能找到；找不到时会告诉你最接近的位置。',
  {
    'path': {'type': 'string', 'description': '项目内的相对路径'},
    'old_text': {'type': 'string', 'description': '要被换掉的原文（照文件原样，建议带上前后各一两行）'},
    'new_text': {'type': 'string', 'description': '换成的新内容；传空字符串表示删掉这一段'},
    'replace_all': {'type': 'boolean', 'description': '是否把所有出现的地方都换掉，默认 false（只允许对上一处）'},
  },
  ['path', 'old_text', 'new_text'],
);

/// 改动前的文件快照：有没有、文本是什么；没法按文本比时 [opaque] 说明原因。
class FileSnapshot {
  const FileSnapshot({required this.existed, this.text, this.opaque});
  final bool existed;
  final String? text;
  final String? opaque;

  static Future<FileSnapshot> of(File file) async {
    if (!await file.exists()) return const FileSnapshot(existed: false);
    final length = await file.length();
    if (length > kSnapshotMaxBytes) return const FileSnapshot(existed: true, opaque: '原文件太大，没有生成对比');
    final bytes = await file.readAsBytes();
    if (bytes.take(8000).contains(0)) return const FileSnapshot(existed: true, opaque: '原文件是二进制文件，没有生成对比');
    return FileSnapshot(existed: true, text: utf8.decode(bytes, allowMalformed: true));
  }

  /// 写成 [after] 以后的改动（[after]＝null 表示删掉了）。
  FileChange changeTo(String path, String? after) {
    final kind = after == null ? ChangeKind.deleted : (existed ? ChangeKind.modified : ChangeKind.created);
    if (after != null && after.length <= 8000 && after.contains('\u0000')) {
      return FileChange(path: path, kind: kind, note: '写入的是二进制内容，没有生成对比');
    }
    return diffFileChange(path, kind: kind, before: existed ? text : null, after: after, opaque: opaque);
  }
}

/// 删掉一个目录：清单里只记一笔，没有对比。
FileChange dirDeleted(String path) => FileChange(path: path.endsWith('/') ? path : '$path/', kind: ChangeKind.deleted, note: '删除了整个目录');

bool _flag(Object? v) => v == true || (v is String && v.trim().toLowerCase() == 'true');

/// 执行 edit_file。[checkScope]：团队任务的写入范围检查（范围外抛 [ToolArgError]）。
Future<ToolOutcome> runEditFile(PathGuard guard, Map<String, dynamic> args, {required void Function(String full) checkScope}) async {
  final path = AgentToolbox.argString(args, 'path');
  final full = guard.resolve(path);
  if (full == guard.root) throw ToolArgError('path 不能是项目根目录');
  checkScope(full);
  final oldText = AgentToolbox.argString(args, 'old_text', allowEmpty: true);
  final newText = AgentToolbox.argString(args, 'new_text', allowEmpty: true);
  if (await Directory(full).exists()) throw ToolArgError('$path 是一个目录');
  final file = File(full);
  if (!await file.exists()) return ToolOutcome('错误：文件不存在：$path。edit_file 只能改已有的文件，新建请用 write_file', ok: false);
  if (await file.length() > kEditMaxChars * 4) {
    return ToolOutcome('错误：$path 太大（局部修改的上限是 $kEditMaxChars 字符），没有改动', ok: false);
  }
  final bytes = await file.readAsBytes();
  if (bytes.take(8000).contains(0)) return ToolOutcome('错误：$path 是二进制文件，不能按文本修改', ok: false);
  final String content;
  try {
    content = utf8.decode(bytes);
  } on FormatException {
    return ToolOutcome('错误：$path 不是 UTF-8 编码的文本，改了会弄坏它，没有改动', ok: false);
  }
  // 开头的 BOM 解码时会被去掉，写回时补上。
  final bom = bytes.length >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF;
  final result = applyEdit(content, oldText, newText, replaceAll: _flag(args['replace_all']));
  switch (result) {
    case EditFail(:final message):
      return ToolOutcome('错误：$message', ok: false);
    case final EditOk ok:
      if (ok.content.length > AgentToolbox.maxWriteChars) {
        return ToolOutcome('错误：改完以后文件太大（${ok.content.length} 字符，上限 ${AgentToolbox.maxWriteChars}），没有改动', ok: false);
      }
      await file.writeAsString(bom ? '\uFEFF${ok.content}' : ok.content);
      final rel = guard.relative(full);
      final change = diffFileChange(rel, kind: ChangeKind.modified, before: content, after: ok.content);
      final how = ok.level == MatchLevel.anchors ? '${ok.level.label}，中间行相似度 ${((ok.similarity ?? 1) * 100).round()}%' : ok.level.label;
      final fuzzy = ok.level == MatchLevel.exact ? '' : '\n（old_text 和文件不完全一样，是按“${ok.level.label}”找到的；新内容已按文件里原来的缩进对齐。拿不准就用 read_file 看一眼改得对不对。）';
      return ToolOutcome('已修改 $rel：替换了 ${ok.count} 处（$how），改动在${ok.where}${change.stat.isEmpty ? '' : '，${change.stat} 行'}。$fuzzy', changedFiles: true, change: change);
  }
}
