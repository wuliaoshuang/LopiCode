// 把一条命令起出来的“整棵进程树”找出来并结束掉。
//
// 为什么要它：以前超时只杀我们直接起的那一个进程。
// - 本机 shell：`sh -c '...'` 被杀以后，它起的子进程（sleep、node、python…）会被系统收养，接着跑、接着占端口。
// - Ubuntu（PRoot）：我们起的是 PRoot。PRoot 的 `--kill-on-exit` 只管“里面的主命令自己退出时把其余的一起结束”
//   （对照 proot 加这个选项的补丁说明核对过：`Kill all processes on command exit`，触发点是主命令退出）；
//   PRoot 自己被强杀时走不到那一步，里面的进程会脱离出来继续跑（这一点是参考 RikkaHub 的说明，真机未核对）。
//   所以不能直接杀 PRoot：要趁它还活着，把它里面的进程一个个结束掉，最后一个退出后 PRoot 自己就退出了。
//
// 怎么认“这条命令的进程”（三条线，取并集；都只认得出我们自己起的东西）：
// 1. 进程树：从我们起的那个进程往下，按“父进程号”一层层找；
// 2. 被 PRoot 跟踪的：`/proc/<pid>/status` 里 `TracerPid` 是 PRoot 进程号的（PRoot 里的所有进程，脱离了进程树的也算）；
// 3. 记号：起命令时往环境变量里放一个独一无二的记号（[kCommandTagEnv]），子子孙孙都会带着它；
//    父进程先死、被系统收养的进程，前两条线找不到，靠这条。
//
// 只在有 /proc 的系统上（Linux、安卓）能找；别的系统退回“只结束我们起的那一个进程”。
// Dart 起进程时不能指定“新进程组 / 新会话”（能指定的那种模式拿不到退出码），所以没有用进程组号的做法。
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

/// 记号放在这个环境变量里。
const String kCommandTagEnv = 'LOPICODE_CMD_TAG';

/// 停止时先客气地请它退出，等这么久还没退再强行结束。
const Duration kStopGrace = Duration(milliseconds: 1500);

/// 强行结束最多扫几轮（命令可能正在起新进程）、每轮之间等多久。
const int kKillRounds = 10;
const Duration kKillRoundWait = Duration(milliseconds: 200);

final Random _random = Random.secure();

/// 造一个新的记号。
String newCommandTag() => 'lc${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}${_random.nextInt(1 << 32).toRadixString(36)}';

/// 这台机器上能不能按 /proc 找进程。
bool get processScanSupported => (Platform.isLinux || Platform.isAndroid) && Directory('/proc/self').existsSync();

class _Proc {
  _Proc(this.pid, this.parent, this.tracer);
  final int pid;
  final int parent;
  final int tracer;
}

int _field(String status, String name) {
  final at = status.indexOf('\n$name:');
  if (at < 0) return 0;
  final end = status.indexOf('\n', at + 1);
  return int.tryParse(status.substring(at + name.length + 2, end < 0 ? status.length : end).trim()) ?? 0;
}

List<_Proc> _scan() {
  final out = <_Proc>[];
  final List<FileSystemEntity> entries;
  try {
    entries = Directory('/proc').listSync(followLinks: false);
  } on FileSystemException {
    return out;
  }
  for (final e in entries) {
    final id = int.tryParse(e.path.substring(e.path.lastIndexOf('/') + 1));
    if (id == null) continue;
    try {
      final status = File('${e.path}/status').readAsStringSync();
      if (status.contains('\nState:\tZ')) continue; // 已经结束、只等父进程来收的：不算
      out.add(_Proc(id, _field(status, 'PPid'), _field(status, 'TracerPid')));
    } on FileSystemException {
      // 刚好退出了，或者不是我们能看的进程：跳过
    } on FormatException {
      // 名字里有怪字符：跳过
    }
  }
  return out;
}

bool _carriesTag(int id, String needle) {
  try {
    return latin1.decode(File('/proc/$id/environ').readAsBytesSync()).split('\u0000').contains(needle);
  } on FileSystemException {
    return false; // 别人的进程（没权限看）、已经退出的
  }
}

/// 一条命令的进程树。[rootPid] 是我们直接起的那个进程；[rootIsTracer]＝它是 PRoot（真正的命令在它里面）。
class CommandProcessTree {
  CommandProcessTree(this.rootPid, {this.tag, this.rootIsTracer = false});

  final int rootPid;
  final String? tag;
  final bool rootIsTracer;

  /// 属于这条命令的进程号。不含 PRoot 自己（[rootIsTracer] 时），不含本应用。
  Set<int> members() {
    final all = _scan();
    final found = <int>{};
    final byParent = <int, List<int>>{};
    for (final proc in all) {
      byParent.putIfAbsent(proc.parent, () => []).add(proc.pid);
      if (rootIsTracer && proc.tracer == rootPid) found.add(proc.pid);
    }
    final todo = [rootPid, ...found];
    while (todo.isNotEmpty) {
      for (final kid in byParent[todo.removeLast()] ?? const <int>[]) {
        if (found.add(kid)) todo.add(kid);
      }
    }
    final mark = tag;
    if (mark != null) {
      final needle = '$kCommandTagEnv=$mark';
      for (final proc in all) {
        if (!found.contains(proc.pid) && proc.pid != rootPid && _carriesTag(proc.pid, needle)) found.add(proc.pid);
      }
    }
    if (!rootIsTracer && all.any((proc) => proc.pid == rootPid)) found.add(rootPid);
    return found
      ..remove(pid)
      ..remove(1)
      ..remove(0)
      ..removeWhere((id) => rootIsTracer && id == rootPid);
  }

  /// PRoot 里的“主命令”：它起的第一个进程。
  int? _main(Set<int> among) {
    for (final proc in _scan()) {
      if (proc.parent == rootPid && among.contains(proc.pid)) return proc.pid;
    }
    return null;
  }

  static void _signal(Iterable<int> ids, ProcessSignal signal) {
    for (final id in ids) {
      if (id > 1 && id != pid) Process.killPid(id, signal);
    }
  }

  /// 立刻强行结束整棵树（不等）。应用退出、工作区关掉时用：那时候没机会再等了。
  void killNow() {
    if (!processScanSupported) {
      Process.killPid(rootPid, ProcessSignal.sigkill);
      return;
    }
    _signal(members(), ProcessSignal.sigkill);
    // PRoot：里面的进程都结束后它自己会退出；这里不再等，补一刀免得它留下。
    if (rootIsTracer) Process.killPid(rootPid, ProcessSignal.sigkill);
  }

  /// 把整棵树结束掉。[exited] 是我们起的那个进程的“已退出”。
  /// [grace] 大于 0：先发“请退出”，等这么久；还在就强行结束，多扫几轮。
  Future<void> terminate({required Future<void> exited, Duration grace = Duration.zero}) async {
    var gone = false;
    unawaited(exited.then((_) => gone = true, onError: (_) => gone = true));
    Future<void> wait(Duration d) => Future.any([exited.catchError((_) {}), Future<void>.delayed(d)]);

    if (!processScanSupported) {
      if (grace > Duration.zero) {
        Process.killPid(rootPid);
        await wait(grace);
      }
      if (!gone) Process.killPid(rootPid, ProcessSignal.sigkill);
      return;
    }
    if (grace > Duration.zero) {
      final all = members();
      // PRoot 里先请“主命令以外”的退出：主命令一退出，--kill-on-exit 会立刻强杀其余的，它们就没机会自己收尾了。
      // 本机 shell 没有这回事：全部一起请。
      final polite = rootIsTracer ? all.difference({?_main(all)}) : all;
      _signal(polite.isEmpty ? all : polite, ProcessSignal.sigterm);
      final until = DateTime.now().add(grace);
      while (DateTime.now().isBefore(until)) {
        await wait(const Duration(milliseconds: 100));
        if (gone && members().isEmpty) return;
      }
    }
    for (var round = 0; round < kKillRounds; round++) {
      final all = members();
      if (all.isEmpty && gone) return;
      if (all.isEmpty) {
        await wait(kKillRoundWait); // PRoot 里已经空了：等它自己退出
      } else {
        _signal(all, ProcessSignal.sigkill);
        await Future<void>.delayed(const Duration(milliseconds: 40));
      }
    }
    if (!gone) Process.killPid(rootPid, ProcessSignal.sigkill);
  }
}

/// 把还带着记号 [tag] 的进程全部强行结束，返回结束了几个。
/// 应用被杀后重开时用：上次留下的后台命令如果还有进程活着，凭记号找出来清掉。
int killTaggedProcesses(String tag) {
  if (!processScanSupported || tag.isEmpty) return 0;
  final needle = '$kCommandTagEnv=$tag';
  var killed = 0;
  for (final proc in _scan()) {
    if (proc.pid > 1 && proc.pid != pid && _carriesTag(proc.pid, needle) && Process.killPid(proc.pid, ProcessSignal.sigkill)) killed++;
  }
  return killed;
}
