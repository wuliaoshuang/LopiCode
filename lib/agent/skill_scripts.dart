// 技能里附带的脚本：认出哪些是脚本、告诉模型它们在哪、怎么跑。
//
// 规矩（2026-11-25，参考 RikkaHub 把技能目录挂进 Linux 环境的做法，只学做法）：
// - 技能目录以“副本”的形式挂进 Ubuntu 环境的 [kGuestSkillsDir]（见 skill_mirror.dart）：PRoot 没有只读挂载，
//   所以挂进去的是一份镜像，环境里怎么改都碰不到手机上真正的技能文件，每次进环境前镜像还会按原件重新对齐。
// - 跑脚本就是普通的 run_command：确认卡、权限档位、计划模式一样不少，不因为是技能就免确认。
// - 运行环境没装好：技能照旧只是文字，说明里写清脚本现在跑不了。
// - 这里只读文件名和开头两个字节（认 `#!`），不执行任何东西。
import 'dart:io';

import 'package:lopicode/agent/command_runner.dart';
import 'package:path/path.dart' as p;

/// 技能目录在 Ubuntu 环境里的位置：`/skills/<技能名>/…`。
const String kGuestSkillsDir = '/skills';

/// 一个技能最多带这么多个文件、合计这么大；超了就不放进运行环境（仍然可以当文字说明用）。
const int kSkillMaxFiles = 200;
const int kSkillMaxBytes = 4 * 1024 * 1024;

/// 说明里最多列出几个脚本的路径，多的只说还有几个。
const int kSkillNoteMaxScripts = 20;

/// 按扩展名认脚本（没有扩展名的看文件开头是不是 `#!`）。
const Set<String> kScriptExtensions = {'.sh', '.bash', '.zsh', '.py', '.js', '.mjs', '.cjs', '.ts', '.rb', '.pl', '.php', '.lua', '.awk', '.sed', '.go', '.java', '.kts'};

/// 一个技能目录里除了 SKILL.md 以外的文件。路径都是相对技能目录的、用 `/` 分隔，按名字排好序。
class SkillFiles {
  const SkillFiles({this.scripts = const [], this.others = const [], this.bytes = 0, this.tooBig = false});
  static const none = SkillFiles();

  final List<String> scripts;
  final List<String> others;
  final int bytes;

  /// 文件太多 / 太大：不放进运行环境。
  final bool tooBig;

  bool get hasExtras => scripts.isNotEmpty || others.isNotEmpty;
}

bool _looksLikeScript(File file, String rel) {
  final ext = p.extension(rel).toLowerCase();
  if (kScriptExtensions.contains(ext)) return true;
  if (ext.isNotEmpty) return false;
  RandomAccessFile? raf;
  try {
    raf = file.openSync();
    final head = raf.readSync(2);
    return head.length == 2 && head[0] == 0x23 && head[1] == 0x21; // #!
  } on FileSystemException {
    return false; // 读不了：不当脚本
  } finally {
    raf?.closeSync();
  }
}

/// 扫一个技能目录。不跟符号链接（免得把技能目录外面的东西带进来），以 `.` 开头的不算。
/// 目录不存在、读不了都返回 [SkillFiles.none]，不抛异常。
SkillFiles scanSkillFilesSync(String dir) {
  final root = Directory(dir);
  final scripts = <String>[], others = <String>[];
  var bytes = 0, count = 0;
  try {
    if (!root.existsSync()) return SkillFiles.none;
    for (final e in root.listSync(recursive: true, followLinks: false)) {
      if (e is! File) continue;
      final rel = p.relative(e.path, from: dir).split(p.separator).join('/');
      if (rel == 'SKILL.md' || rel.split('/').any((part) => part.startsWith('.'))) continue;
      count++;
      bytes += e.lengthSync();
      if (count > kSkillMaxFiles || bytes > kSkillMaxBytes) return SkillFiles(bytes: bytes, tooBig: true);
      (_looksLikeScript(e, rel) ? scripts : others).add(rel);
    }
  } on FileSystemException {
    return SkillFiles.none;
  }
  scripts.sort();
  others.sort();
  return SkillFiles(scripts: List.unmodifiable(scripts), others: List.unmodifiable(others), bytes: bytes);
}

/// 给 shell 用的单引号写法（路径里有空格、中文、引号都不会被拆开）。
String shellQuote(String s) => "'${s.replaceAll("'", r"'\''")}'";

/// 用什么跑一个脚本（没有执行权限也能跑：镜像里的文件不保证带执行位）。
String scriptRunCommand(String path) {
  final q = shellQuote(path);
  return switch (p.extension(path).toLowerCase()) {
    '.py' => 'python3 $q',
    '.js' || '.mjs' || '.cjs' => 'node $q',
    '.rb' => 'ruby $q',
    '.pl' => 'perl $q',
    '.php' => 'php $q',
    '.lua' => 'lua $q',
    _ => 'bash $q',
  };
}

/// 脚本现在能在哪跑。
sealed class SkillScriptEnv {
  const SkillScriptEnv();
}

/// 命令进 Ubuntu 环境跑，技能镜像挂在 [dir]（一般是 [kGuestSkillsDir]）。
class SkillScriptsInGuest extends SkillScriptEnv {
  const SkillScriptsInGuest(this.dir);
  final String dir;
}

/// 命令在本机 shell 跑（桌面 / 开发调试）：脚本就在技能自己的目录里。
class SkillScriptsOnHost extends SkillScriptEnv {
  const SkillScriptsOnHost();
}

/// 现在执行不了命令（运行环境没装好）：脚本跑不了。
class SkillScriptsUnavailable extends SkillScriptEnv {
  const SkillScriptsUnavailable();
}

/// 可能把命令放进 Ubuntu 环境跑的执行器实现它。
abstract class HasSkillMount {
  /// [workingDirectory] 这个工作区的技能镜像挂在环境里的哪个目录；命令不进环境、没有技能、没挂上都是 null。
  String? skillsGuestDirFor(String workingDirectory);

  /// 现在命令是不是只进 Ubuntu 跑（这时没有镜像就等于脚本跑不了，不能退回手机上的路径）。
  bool get skillMountRequired;
}

/// 按执行器现在的状态判断脚本能在哪跑。
SkillScriptEnv skillScriptEnvOf(Object runner, String workingDirectory) {
  if (runner is HasCommandAvailability && runner.unavailableReason != null) return const SkillScriptsUnavailable();
  if (runner is HasSkillMount) {
    final dir = runner.skillsGuestDirFor(workingDirectory);
    if (dir != null) return SkillScriptsInGuest(dir);
    // 命令进 Ubuntu 但镜像没挂上（磁盘满之类）：按跑不了说，不给一个不存在的路径。
    if (runner.skillMountRequired) return const SkillScriptsUnavailable();
  }
  return const SkillScriptsOnHost();
}

/// 读技能全文时接在后面的那段说明：脚本在哪、怎么跑。没有脚本返回空字符串。
String skillScriptNote({required String name, required String hostDir, required SkillFiles files, required SkillScriptEnv env}) {
  if (files.tooBig) {
    return '\n\n【附带文件】这个技能附带的文件太多或太大（超过 $kSkillMaxFiles 个或 ${kSkillMaxBytes ~/ (1024 * 1024)}MB），没有放进运行环境，里面的脚本跑不了；请只照上面的文字说明做。';
  }
  final scripts = files.scripts;
  if (scripts.isEmpty) return '';
  final shown = scripts.take(kSkillNoteMaxScripts).toList();
  final more = scripts.length - shown.length;
  String listOf(String base) => [for (final s in shown) '- $base/$s', if (more > 0) '- ……还有 $more 个'].join('\n');
  switch (env) {
    case SkillScriptsUnavailable():
      return '\n\n【附带脚本】这个技能带 ${scripts.length} 个脚本（${shown.join('、')}${more > 0 ? ' 等' : ''}），但运行环境还没装好，现在跑不了。'
          '请只照上面的文字说明做；确实需要跑脚本时，告诉用户先到“终端”页或“运行环境”页装好运行环境。';
    case SkillScriptsInGuest(:final dir):
      final base = '$dir/$name';
      return '\n\n【附带脚本】这个技能带 ${scripts.length} 个脚本，在运行环境里的位置：\n${listOf(base)}\n'
          '要用时用 run_command 跑，例如：${scriptRunCommand('$base/${shown.first}')}\n'
          '（和别的命令一样要用户确认。$dir 里是技能文件的副本：只用来读和跑，改了不会保存；脚本产生的文件请写到工作区里。）';
    case SkillScriptsOnHost():
      final base = hostDir.split(p.separator).join('/');
      return '\n\n【附带脚本】这个技能带 ${scripts.length} 个脚本，位置：\n${listOf(base)}\n'
          '要用时用 run_command 跑，例如：${scriptRunCommand('$base/${shown.first}')}\n'
          '（和别的命令一样要用户确认。不要改技能目录里的文件。）';
  }
}
