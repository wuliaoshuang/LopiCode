// 给 Ubuntu 环境的 /etc/group 补上“这个应用进程所在的组”的名字。
//
// 为什么要补：安卓给每个应用进程挂了几个附加组（联网权限 inet=3003、everybody=9997，
// 还有按应用编号派生的 20xxx / 50xxx）。PRoot 的 `-0` 只把“我是谁”伪装成 root，附加组还是真的。
// Ubuntu 的 /etc/group 里没有这些编号，于是任何去查组名的程序都会报
// `groups: cannot find name for group ID 3003`——交互式 bash 一启动就会查一次
// （/etc/bash.bashrc 里“sudo 提示”那一段调了 `groups`），所以每次开终端都冒出几行。
//
// 做法：每次启动 PRoot 之前，看一眼当前进程有哪些组，/etc/group 里缺哪个补哪个（名字 aid_编号）。
// 已经有的不动，原有内容一个字节都不改，只在末尾追加。
//
// 学的是 Termux proot-distro、dsh-Go 的做法（都是往 /etc/group 里登记安卓的组），代码是自己写的。
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// 补进去的组叫什么：`aid_3003`。（AID 是安卓对这些编号的叫法。）
String guestGroupName(int gid) => 'aid_$gid';

/// 组编号的合法范围。4294967295 是“没有”的意思，不算。
bool _validGid(int? gid) => gid != null && gid >= 0 && gid < 0xffffffff;

/// 从 `/proc/self/status` 的内容里读出当前进程的组：`Gid:` 行的四个编号在前，`Groups:` 行的附加组在后，去重。
///
/// 两行都没有（不是 Linux、内容读坏了）返回 null，调用方换别的办法；有这两行但没有附加组，返回只含主组的列表。
List<int>? parseProcessGroups(String status) {
  final found = <int>{};
  var sawLine = false;
  for (final raw in const LineSplitter().convert(status)) {
    final colon = raw.indexOf(':');
    if (colon <= 0) continue;
    final key = raw.substring(0, colon).trim();
    if (key != 'Gid' && key != 'Groups') continue;
    sawLine = true;
    for (final token in raw.substring(colon + 1).trim().split(RegExp(r'\s+'))) {
      final gid = int.tryParse(token);
      if (_validGid(gid)) found.add(gid!);
    }
  }
  return sawLine ? found.toList() : null;
}

/// 从 `id -G` 的输出（一行、空格隔开的编号）里读出组。读不出任何编号返回 null。
List<int>? parseIdGroups(String output) {
  final found = <int>{};
  for (final token in output.trim().split(RegExp(r'\s+'))) {
    final gid = int.tryParse(token);
    if (_validGid(gid)) found.add(gid!);
  }
  return found.isEmpty ? null : found.toList();
}

/// 当前进程的组。先读 `/proc/self/status`；读不到（个别系统不给读）再问系统自带的 `id -G`；都不行返回 null。
List<int>? readProcessGroups() {
  try {
    final groups = parseProcessGroups(File('/proc/self/status').readAsStringSync());
    if (groups != null) return groups;
  } on FileSystemException {
    // 读不到就走下面的兜底
  }
  try {
    final result = Process.runSync('id', ['-G']);
    if (result.exitCode == 0) return parseIdGroups('${result.stdout}');
  } on ProcessException {
    // 没有 id 命令：那就真的拿不到
  }
  return null;
}

/// 一个“每行用冒号分段”的账本文件（group、gshadow）里已经有哪些名字、哪些组编号。
/// 空行、注释、段数不够的怪行都原样留着，只是不参与统计。
({Set<String> names, Set<int> gids}) _scan(String content) {
  final names = <String>{};
  final gids = <int>{};
  for (final raw in content.split('\n')) {
    final line = raw.endsWith('\r') ? raw.substring(0, raw.length - 1) : raw;
    if (line.trim().isEmpty || line.trimLeft().startsWith('#')) continue;
    final fields = line.split(':');
    if (fields.first.isNotEmpty) names.add(fields.first);
    if (fields.length >= 3) {
      final gid = int.tryParse(fields[2].trim());
      if (gid != null) gids.add(gid);
    }
  }
  return (names: names, gids: gids);
}

String _append(String content, Iterable<String> lines) {
  final buffer = StringBuffer(content);
  if (content.isNotEmpty && !content.endsWith('\n')) buffer.write('\n');
  for (final line in lines) {
    buffer.write('$line\n');
  }
  return buffer.toString();
}

/// 往 /etc/group 的内容里补上 [gids] 中还没有名字的组。
///
/// 返回新内容和补了哪些（编号 → 名字）；一个都不用补时 `content` 是 null。
/// 原有内容原样保留（包括怪行和结尾有没有换行），新行只加在末尾，格式是 `aid_3003:x:3003:`。
/// 名字万一被别的组占了，就在后面加下划线，直到不重名。
({String? content, Map<int, String> added}) addMissingGroups(String content, Iterable<int> gids) {
  final seen = _scan(content);
  final added = <int, String>{};
  for (final gid in gids) {
    if (!_validGid(gid) || seen.gids.contains(gid) || added.containsKey(gid)) continue;
    var name = guestGroupName(gid);
    while (seen.names.contains(name)) {
      name = '${name}_';
    }
    seen.names.add(name);
    added[gid] = name;
  }
  if (added.isEmpty) return (content: null, added: added);
  return (content: _append(content, [for (final e in added.entries) '${e.value}:x:${e.key}:']), added: added);
}

/// 往 /etc/gshadow 的内容里补上 [names] 中还没有的组（`aid_3003:!::`）。不用补返回 null。
String? addMissingGshadow(String content, Iterable<String> names) {
  final seen = _scan(content).names;
  final missing = [
    for (final name in names)
      if (seen.add(name)) name,
  ];
  return missing.isEmpty ? null : _append(content, [for (final name in missing) '$name:!::']);
}

class GuestGroupsResult {
  const GuestGroupsResult({this.added = const [], this.skipped});

  /// 这次补进 /etc/group 的组编号（没补是空的）。
  final List<int> added;

  /// 没法补的原因；正常（补了，或本来就齐）是 null。
  final String? skipped;
}

/// 把 [gids] 里缺名字的组补进 [rootfs] 的 etc/group（和 etc/gshadow，如果有这个文件）。
///
/// - 可以反复调用：都有了就只读一次文件，什么都不写；
/// - 写的时候先写到旁边的临时文件再改名，不会留下写了一半的 /etc/group；
/// - etc 目录不存在（环境还没装）、文件是链接或目录：不动，返回原因；
/// - etc 在而 group 文件不在：新建一个，带上 root 和要补的组；
/// - 任何读写失败都不抛异常——补不上只是多几行提示，不能因此进不了终端。
GuestGroupsResult ensureGuestGroups(String rootfs, List<int> gids) {
  if (gids.isEmpty) return const GuestGroupsResult();
  final etc = p.join(rootfs, 'etc');
  try {
    if (FileSystemEntity.typeSync(etc) != FileSystemEntityType.directory) return const GuestGroupsResult(skipped: '环境里没有 etc 目录');
    final groupPath = p.join(etc, 'group');
    final type = FileSystemEntity.typeSync(groupPath, followLinks: false);
    if (type != FileSystemEntityType.file && type != FileSystemEntityType.notFound) {
      return const GuestGroupsResult(skipped: '环境里的 /etc/group 不是普通文件');
    }
    // 用 latin1 读写：不管里面是什么字节都能原样读出来、原样写回去。
    final original = type == FileSystemEntityType.file ? File(groupPath).readAsStringSync(encoding: latin1) : 'root:x:0:\n';
    final patched = addMissingGroups(original, gids);
    final content = patched.content;
    if (content != null || type == FileSystemEntityType.notFound) _writeAtomic(groupPath, content ?? original);

    // gshadow 是 group 的“影子账本”。查组名用不到它，但两边对不上的话 grpck 会抱怨，顺手保持一致。
    final names = <String>[...patched.added.values];
    if (names.isNotEmpty) {
      final shadowPath = p.join(etc, 'gshadow');
      if (FileSystemEntity.typeSync(shadowPath, followLinks: false) == FileSystemEntityType.file) {
        final shadow = addMissingGshadow(File(shadowPath).readAsStringSync(encoding: latin1), names);
        if (shadow != null) _writeAtomic(shadowPath, shadow);
      }
    }
    return GuestGroupsResult(added: patched.added.keys.toList());
  } on FileSystemException catch (e) {
    return GuestGroupsResult(skipped: '改 /etc/group 失败：${e.osError?.message ?? e.message}');
  } on ArgumentError catch (e) {
    // latin1 编不回去（不该发生：读进来的就是 latin1）
    return GuestGroupsResult(skipped: '改 /etc/group 失败：${e.message}');
  }
}

void _writeAtomic(String path, String content) {
  final tmp = File('$path.lopicode-tmp');
  try {
    tmp.writeAsStringSync(content, encoding: latin1, flush: true);
    tmp.renameSync(path);
  } on FileSystemException {
    try {
      if (tmp.existsSync()) tmp.deleteSync();
    } on FileSystemException {
      // 临时文件删不掉不要紧，下次会覆盖
    }
    rethrow;
  }
}

/// 每次启动 PRoot 前调一下 [sync]：当前进程的组只读一次（进程活着的时候不会变），
/// /etc/group 每次都核对（环境可能刚重装过）。结果有变化才记一行日志，不刷屏。
class GuestGroupsKeeper {
  GuestGroupsKeeper({List<int>? Function()? read, this.log}) : _read = read ?? readProcessGroups;

  final List<int>? Function() _read;
  final void Function(String message)? log;

  List<int>? _gids;
  bool _loaded = false;
  String? _lastNote;

  GuestGroupsResult sync(String rootfs) {
    if (!_loaded) {
      _loaded = true;
      try {
        _gids = _read();
      } on Exception catch (e) {
        _gids = null;
        _note('读不到当前进程的组（$e），没法给 Ubuntu 补组名');
      }
      if (_gids == null && _lastNote == null) _note('读不到当前进程的组，没法给 Ubuntu 补组名；终端开头可能有几行 groups: cannot find name');
    }
    final gids = _gids;
    if (gids == null) return const GuestGroupsResult(skipped: '读不到当前进程的组');
    final result = ensureGuestGroups(rootfs, gids);
    if (result.added.isNotEmpty) {
      _note('已在 Ubuntu 的 /etc/group 里登记安卓的组：${result.added.join('、')}');
    } else if (result.skipped != null) {
      _note('没能给 Ubuntu 补组名：${result.skipped}');
    }
    return result;
  }

  void _note(String message) {
    if (message == _lastNote) return;
    _lastNote = message;
    log?.call(message);
  }
}
