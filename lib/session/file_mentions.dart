// 聊天输入框里打 @ 选文件：什么时候算“在打 @”、工作区里有哪些文件可选、怎么筛、选中后草稿怎么改。
//
// 引用文件只有一种样子：草稿里的一段 `@相对路径 `（后面带一个空格）。“＋ › 引用项目文件”插进去的也是这个，
// 所以这里选出来的和加号里选出来的是同一种东西：一样显示在输入框里、一样随消息文字发出去、一样靠删字删掉。
// 纯逻辑，不带界面；界面在 lib/ui/file_mention.dart。
import 'dart:async';
import 'dart:io';

import 'package:lopicode/core/path_guard.dart';
import 'package:path/path.dart' as p;

/// 扫工作区时不进去的目录（哪一层出现都跳过）：应用内部目录、版本库、依赖、构建产物、缓存。
/// 这些目录里的文件又多又不是她自己写的；真要引用可以直接打出路径。
const Set<String> kMentionSkipDirs = {
  PathGuard.reservedDir,
  '.lopicode-attachments',
  '.git',
  '.svn',
  '.hg',
  'node_modules',
  'bower_components',
  'vendor',
  'build',
  'dist',
  'out',
  'target',
  '.dart_tool',
  '.gradle',
  '.idea',
  '.next',
  '.nuxt',
  '.cache',
  '.venv',
  'venv',
  '__pycache__',
  '.pytest_cache',
  '.mypy_cache',
};

/// 一次最多扫多少个文件。
const int kMentionScanMaxFiles = 5000;

/// 一次最多扫多久。
const Duration kMentionScanBudget = Duration(seconds: 2);

/// 候选列表里最多列多少个。
const int kMentionMaxResults = 50;

/// 输入法正在组字（拼音还没上屏、英文键盘的单词还带下划线）时，要不要拿组字里的字去筛。
/// 开着：边打边筛（不改草稿，所以不打断组字）；关掉：组字期间列表保持不动，上屏后再筛。
/// 不管开关：`@` 自己还在组字里的时候一律不弹。
const bool kMentionFilterWhileComposing = true;

/// 光标前面那段正在打的 `@xxx`。
class MentionTrigger {
  const MentionTrigger(this.at, this.end, this.query);

  /// `@` 在草稿里的位置。
  final int at;

  /// 光标位置（`@xxx` 的结尾，不含）。
  final int end;

  /// `@` 后面到光标之间的字（可能是空的）。
  final String query;

  @override
  bool operator ==(Object other) => other is MentionTrigger && other.at == at && other.end == end && other.query == query;

  @override
  int get hashCode => Object.hash(at, end, query);

  @override
  String toString() => 'MentionTrigger($at, $end, "$query")';
}

bool _isSpace(int unit) => unit == 0x20 || unit == 0x0A || unit == 0x0D || unit == 0x09 || unit == 0x3000 || unit == 0xA0;

/// 看光标前面是不是正在打 `@xxx`。不是就返回 null。
///
/// - 只认光标（没有选中一段字）；
/// - 从光标往前找，中间不能有空白，找到的 `@` 必须在草稿开头或者前面是空白 / 换行（`a@b.com` 不算）；
/// - [composingStart]、[composingEnd] 是输入法正在组字的范围（没有就都传 -1）：`@` 在组字范围里不算；
///   组字在 `@` 后面时，[filterWhileComposing] 关着就只认到组字开头为止。
MentionTrigger? mentionTriggerAt(String text, {required int selStart, required int selEnd, int composingStart = -1, int composingEnd = -1, bool filterWhileComposing = kMentionFilterWhileComposing}) {
  if (selStart < 0 || selStart != selEnd || selStart > text.length) return null;
  final composing = composingStart >= 0 && composingEnd > composingStart && composingEnd <= text.length;
  var at = -1;
  for (var i = selStart - 1; i >= 0; i--) {
    final unit = text.codeUnitAt(i);
    if (_isSpace(unit)) return null;
    if (unit == 0x40) {
      // 前面紧挨着别的字的 @（邮箱、a@b）不算，也不再往前找。
      if (i > 0 && !_isSpace(text.codeUnitAt(i - 1))) return null;
      at = i;
      break;
    }
  }
  if (at < 0) return null;
  if (composing) {
    if (at >= composingStart && at < composingEnd) return null;
    if (!filterWhileComposing && composingStart > at) {
      // 光标在组字里：只认已经上屏的那一截。
      if (selStart > composingStart) return MentionTrigger(at, selStart, text.substring(at + 1, composingStart));
    }
  }
  return MentionTrigger(at, selStart, text.substring(at + 1, selStart));
}

/// 扫出来的结果。
class MentionScan {
  const MentionScan(this.files, {this.truncated = false, this.error});

  /// 工作区里的文件（相对路径，用 `/`；不含目录）。浅的在前。
  final List<String> files;

  /// 没扫完（文件太多或超时）。
  final bool truncated;

  /// 扫不了的原因（给用户看的话）。
  final String? error;
}

/// 列出工作区里能引用的文件。一层一层往下扫（浅的先出来），不跟符号链接，不进 [skipDirs]。
/// 扫到 [maxFiles] 个或用了 [budget] 这么久就停，[MentionScan.truncated] 记为 true。
/// 全程异步：每读一个目录都会让出一次，不卡打字。[now] 只给测试换时钟用。
Future<MentionScan> scanMentionFiles(
  PathGuard guard, {
  int maxFiles = kMentionScanMaxFiles,
  Duration budget = kMentionScanBudget,
  Set<String> skipDirs = kMentionSkipDirs,
  Duration Function()? now,
}) async {
  final watch = Stopwatch()..start();
  Duration clock() => now?.call() ?? watch.elapsed;
  final started = clock();
  bool late() => clock() - started >= budget;
  final out = <String>[];
  var truncated = false;
  final String root;
  try {
    root = guard.resolve('');
  } on PathGuardException catch (e) {
    return MentionScan(const [], error: e.message);
  }
  var level = <Directory>[Directory(root)];
  scan:
  while (level.isNotEmpty) {
    final next = <Directory>[];
    for (final dir in level) {
      if (late()) {
        truncated = true;
        break scan;
      }
      final files = <String>[];
      final dirs = <Directory>[];
      var seen = 0;
      try {
        await for (final e in dir.list(followLinks: false)) {
          // 一个目录里东西特别多时也要看表，不然一个大目录就能把时间用完。
          if (++seen % 200 == 0 && late()) {
            truncated = true;
            break;
          }
          final name = p.basename(e.path);
          if (e is Directory) {
            if (!skipDirs.contains(name)) dirs.add(e);
          } else if (e is File) {
            files.add(guard.relative(e.path));
          }
        }
      } on FileSystemException catch (e) {
        // 工作区本身读不了：把原因说出来。里面某个子目录读不了（没权限、刚被删）：跳过它，别的照扫。
        if (dir.path == root) return MentionScan(const [], error: '读不了工作区的文件：${e.osError?.message ?? e.message}');
        continue;
      }
      files.sort();
      for (final f in files) {
        if (out.length >= maxFiles) {
          truncated = true;
          break scan;
        }
        out.add(f);
      }
      if (truncated) break scan;
      dirs.sort((a, b) => a.path.compareTo(b.path));
      next.addAll(dirs);
    }
    level = next;
  }
  return MentionScan(out, truncated: truncated);
}

/// 筛出来的结果。
class MentionMatches {
  const MentionMatches(this.files, this.total);

  /// 要列出来的（最多 [kMentionMaxResults] 个）。
  final List<String> files;

  /// 一共匹配了多少个。
  final int total;

  bool get clipped => total > files.length;
}

/// 按文件名 / 路径筛（不分大小写）。排序：文件名开头匹配 → 文件名里有 → 路径里有；同一档里路径短的在前。
/// 没打字时按扫出来的顺序（浅的在前）。
MentionMatches filterMentionFiles(List<String> files, String query, {int limit = kMentionMaxResults}) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return MentionMatches(files.length > limit ? files.sublist(0, limit) : files, files.length);
  final ranked = <(int, String)>[];
  for (final f in files) {
    final lower = f.toLowerCase();
    final slash = lower.lastIndexOf('/');
    final name = slash < 0 ? lower : lower.substring(slash + 1);
    final rank = name.startsWith(q)
        ? 0
        : name.contains(q)
        ? 1
        : lower.contains(q)
        ? 2
        : -1;
    if (rank >= 0) ranked.add((rank, f));
  }
  ranked.sort((a, b) {
    if (a.$1 != b.$1) return a.$1 - b.$1;
    if (a.$2.length != b.$2.length) return a.$2.length - b.$2.length;
    return a.$2.compareTo(b.$2);
  });
  return MentionMatches([for (final r in ranked.take(limit)) r.$2], ranked.length);
}

/// 草稿里是不是已经引用过这个文件（一段完整的 `@路径`，前后是空白或草稿两头）。
/// [skipFrom]、[skipTo] 是正在打的那段 `@xxx`，不算在内。
bool draftHasMention(String text, String path, {int skipFrom = -1, int skipTo = -1}) {
  final token = '@$path';
  var from = 0;
  while (true) {
    final i = text.indexOf(token, from);
    if (i < 0) return false;
    final end = i + token.length;
    final inSkip = skipFrom >= 0 && i >= skipFrom && i < skipTo;
    final startOk = i == 0 || _isSpace(text.codeUnitAt(i - 1));
    final endOk = end == text.length || _isSpace(text.codeUnitAt(end));
    if (!inSkip && startOk && endOk) return true;
    from = i + 1;
  }
}

/// 把一个文件引用写进草稿的结果。
class MentionEdit {
  const MentionEdit(this.text, this.cursor, {required this.added});
  final String text;
  final int cursor;

  /// false＝这个文件已经引用过了，没有再加一遍。
  final bool added;
}

/// 在草稿的 [at] 处插入一个文件引用：`@路径 `，前面不是空白就先补一个空格。
/// “＋ › 引用项目文件”就是这个样子（lib/ui/chat_screen.dart 的 `_insertReference`），两边必须保持一致，测试钉着。
MentionEdit insertMention(String text, int at, String path) {
  final before = text.substring(0, at);
  final lead = before.isEmpty || _isSpace(before.codeUnitAt(before.length - 1)) ? '' : ' ';
  final insert = '$lead@$path ';
  return MentionEdit(before + insert + text.substring(at), at + insert.length, added: true);
}

/// 选中候选里的一个文件：把正在打的 `@xxx` 换成这个文件的引用。
/// 已经引用过就只把 `@xxx` 去掉，不加第二遍。
MentionEdit applyMention(String text, MentionTrigger trigger, String path) {
  final end = trigger.end.clamp(trigger.at, text.length);
  final without = text.substring(0, trigger.at) + text.substring(end);
  if (draftHasMention(text, path, skipFrom: trigger.at, skipTo: end)) {
    return MentionEdit(without, trigger.at, added: false);
  }
  return insertMention(without, trigger.at, path);
}
