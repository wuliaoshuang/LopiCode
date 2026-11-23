import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:lopicode/core/stores.dart';
import 'package:lopicode/runtime/linux_runtime.dart';
import 'package:lopicode/runtime/linux_shell_backend.dart';
import 'package:lopicode/runtime/proot_command.dart';
import 'package:lopicode/terminal/pty_native.dart';
import 'package:lopicode/terminal/terminal_session.dart';
import 'package:path/path.dart' as p;

/// 一步检查的结果。
class DiagStep {
DiagStep(this.title);
final String title;
final List<String> lines = [];

/// true 通过，false 没通过，null 只是记录信息。
bool? ok;
void add(String line) => lines.add(line);
}

/// 一条普通进程命令跑完的样子。
class DiagRun {
const DiagRun({required this.exitCode, required this.stdout, required this.stderr, required this.elapsed, this.timedOut = false, this.startError});
final int? exitCode;
final String stdout;
final String stderr;
final Duration elapsed;
final bool timedOut;
final String? startError;

bool get printedOk =>!timedOut && startError == null && exitCode == 0;
}

typedef DiagProcessRunner =
Future<DiagRun> Function(String executable, List<String> arguments, {Map<String, String>? environment, required Duration timeout});

/// 不走伪终端，用普通进程跑一条命令：到时间没结束就杀掉，输出照样留着。
Future<DiagRun> runDiagProcess(
String executable,
List<String> arguments, {
Map<String, String>? environment,
required Duration timeout,
}) async {
final watch = Stopwatch()..start();
final Process process;
try {
process = await Process.start(
executable,
arguments,
environment: environment,
includeParentEnvironment: environment == null,
);
} on ProcessException catch (e) {
return DiagRun(exitCode: null, stdout: '', stderr: '', elapsed: watch.elapsed, startError: e.message);
}
unawaited(process.stdin.close().catchError((_) {}));
final out = StringBuffer();
final err = StringBuffer();
const decoder = Utf8Decoder(allowMalformed: true);
final outDone = process.stdout.transform(decoder).listen(out.write, onError: (_) {}).asFuture<void>();
final errDone = process.stderr.transform(decoder).listen(err.write, onError: (_) {}).asFuture<void>();
var timedOut = false;
final code = await process.exitCode.timeout(
timeout,
onTimeout: () {
timedOut = true;
process.kill(ProcessSignal.sigkill);
return -9;
},
);
// 被杀掉的进程可能留下还握着管道的子进程：最多再等一小会儿。
await Future.wait([outDone, errDone]).timeout(const Duration(seconds: 1), onTimeout: () => const []);
return DiagRun(exitCode: timedOut? null: code, stdout: out.toString(), stderr: err.toString(), elapsed: watch.elapsed, timedOut: timedOut);
}

/// “一键诊断”：把“进不去 Ubuntu / 终端没反应”的可能原因挨个实测一遍，结果可以整段复制。
///
/// 报告里只有路径、命令输出、手机型号和系统版本，不读取也不输出任何密钥。
class RuntimeDiagnostics extends ChangeNotifier {
RuntimeDiagnostics(
this.runtime, {
this.runProcess = runDiagProcess,
PtySpawner? ptySpawner,
PtyArgsSpawner? ptyArgsSpawner,
this.commandTimeout = const Duration(seconds: 15),
this.ptyTimeout = const Duration(seconds: 6),
this.localShell,
}): _ptySpawner = ptySpawner?? FlutterPtyProcess.spawn,
_ptyArgsSpawner = ptyArgsSpawner?? FlutterPtyProcess.spawnWithArgs;

final LinuxRuntime runtime;
final DiagProcessRunner runProcess;
final PtySpawner _ptySpawner;
final PtyArgsSpawner _ptyArgsSpawner;
final Duration commandTimeout;
final Duration ptyTimeout;

/// 伪终端自检用的 shell；默认是手机自带的 sh。
final String? localShell;

bool running = false;
String progress = '';
final List<DiagStep> steps = [];

/// 最后的结论（一两句大白话）。
final List<String> conclusions = [];
DateTime? finishedAt;

bool get hasReport => steps.isNotEmpty &&!running;

/// 整份报告的文字（复制、截图都用它）。
String get report {
final b = StringBuffer('LopiCode 运行环境诊断');
if (finishedAt!= null) b.write(' ${finishedAt!.toIso8601String().substring(0, 19)}');
b.writeln();
if (conclusions.isNotEmpty) {
b.writeln('');
for (final c in conclusions) {
b.writeln('- $c');
}
}
for (final step in steps) {
final mark = switch (step.ok) { true => '通过', false => '没通过', null => '信息'};
b.writeln('\n== ${step.title}（$mark）==');
for (final line in step.lines) {
b.writeln(line);
}
}
return b.toString().trimRight();
}

DiagStep _begin(String title) {
final step = DiagStep(title);
steps.add(step);
progress = title;
notifyListeners();
return step;
}

static String _clip(String text, [int max = 3000]) {
final t = text.trimRight();
if (t.length <= max) return t;
return '…（前面省略 ${t.length - max} 个字符）\n${t.substring(t.length - max)}';
}

void _describeRun(DiagStep step, String command, DiagRun run) {
step.add('命令：$command');
if (run.startError!= null) {
step.add('启动不了：${run.startError}');
} else if (run.timedOut) {
step.add('${run.elapsed.inSeconds} 秒没结束，已强行停止（卡住了）');
} else {
step.add('退出码 ${run.exitCode}，用时 ${run.elapsed.inMilliseconds} 毫秒');
}
step.add('标准输出：${run.stdout.trim().isEmpty? '（空）': '\n${_clip(run.stdout)}'}');
step.add('错误输出：${run.stderr.trim().isEmpty? '（空）': '\n${_clip(run.stderr)}'}');
}

static String _stat(String path) {
final type = FileSystemEntity.typeSync(path, followLinks: false);
if (type == FileSystemEntityType.notFound) return '不存在';
if (type == FileSystemEntityType.link) {
String target;
try {
target = Link(path).targetSync();
} on FileSystemException catch (e) {
target = '读不出来（${e.osError?.message?? e.message}）';
}
final resolved = FileSystemEntity.typeSync(path);
return '链接 → $target（${resolved == FileSystemEntityType.notFound? '指向的东西从手机这边看不存在': '指向的东西存在'}）';
}
final stat = FileStat.statSync(path);
final kind = type == FileSystemEntityType.directory? '目录': '文件';
return '$kind，${stat.size} 字节，权限 ${stat.modeString()}';
}

ProotCommand _proot(List<String> guest, {required bool compat, bool verbose = false, String? projectDir}) {
final base = buildProotCommand(
nativeLibDir: runtime.nativeLibDir?? '',
libDir: runtime.hostLibDir,
rootfs: runtime.rootfsDir,
tmpDir: runtime.tmpDir,
guestCommand: guest,
projectDir: projectDir,
term: 'dumb',
noSeccomp: compat,
);
if (!verbose) return base;
return ProotCommand(
executable: base.executable,
arguments: base.arguments,
environment: {...base.environment, 'PROOT_VERBOSE': '9'},
);
}

static String _show(ProotCommand c) {
final env = c.environment.entries.where((e) => e.key!= 'LD_PRELOAD').map((e) => '${e.key}=${e.value}').join(' ');
return '$env ${c.executable} ${c.arguments.join(' ')}';
}

/// 跑完整套检查。[projectDir] 给了就顺便检查它在 Ubuntu 里（/workspace）看不看得见。
Future<void> run({String? projectDir}) async {
if (running) return;
running = true;
steps.clear();
conclusions.clear();
finishedAt = null;
notifyListeners();
try {
await _run(projectDir);
} catch (e) {
_begin('诊断自己出错了').add('$e');
} finally {
running = false;
progress = '';
finishedAt = DateTime.now();
runtime.log('一键诊断完成：${conclusions.isEmpty? '没有结论': conclusions.join('；')}');
notifyListeners();
}
}

Future<void> _run(String? projectDir) async {
// 1. 手机
var step = _begin('手机和系统');
final info = await runtime.host.deviceInfo();
for (final e in info.entries) {
step.add('${e.key}：${e.value}');
}
step.add('系统内核：${Platform.operatingSystemVersion}');
final uname = await runProcess(Platform.isAndroid? '/system/bin/uname': 'uname', const ['-a'], timeout: const Duration(seconds: 5));
step.add('uname -a：${uname.startError?? (uname.timedOut? '没结束': uname.stdout.trim())}');
final page = await runProcess(Platform.isAndroid? '/system/bin/getconf': 'getconf', const ['PAGE_SIZE'], timeout: const Duration(seconds: 5));
step.add('内存页大小：${page.startError?? (page.timedOut? '没结束': page.stdout.trim())}');
step.add('兼容模式开关：${runtime.settings.getBool(SettingKeys.runtimeCompat)? '已开': '没开'}；连续启动失败 ${runtime.launchFailures} 次');

// 2. 安装包里的文件
step = _begin('安装包自带的四个文件');
final native = runtime.nativeLibDir;
if (native == null) {
step
..add('拿不到安装包的原生库目录')
..ok = false;
} else {
step.add('目录：$native');
var all = true;
for (final name in ProotFiles.bundled) {
final s = _stat(p.join(native, name));
if (s == '不存在') all = false;
step.add('$name：$s');
}
step.ok = all;
}

// 3. 依赖库链接
step = _begin('libtalloc.so.2 链接');
final prepared = runtime.prepareLauncherLibs();
final linkPath = p.join(runtime.hostLibDir, ProotFiles.tallocSoname);
step.add('$linkPath：${_stat(linkPath)}');
if (prepared!= null) step.add('准备时报错：$prepared');
step.ok = prepared == null && FileSystemEntity.typeSync(linkPath)!= FileSystemEntityType.notFound;

// 4. 系统文件抽查
step = _begin('Ubuntu 系统文件抽查');
final rootfs = runtime.rootfsDir;
step.add('根目录：$rootfs（${_stat(rootfs)}）');
for (final rel in const ['bin', 'lib', 'usr/bin/env', 'usr/bin/bash', 'usr/bin/echo', 'usr/lib/aarch64-linux-gnu/ld-linux-aarch64.so.1', 'etc/os-release', 'tmp']) {
step.add('/$rel：${_stat(p.join(rootfs, rel))}');
}
step.add('PRoot 临时目录 ${runtime.tmpDir}：${_stat(runtime.tmpDir)}');
step.ok = File(p.join(rootfs, 'usr/bin/env')).existsSync() && File(p.join(rootfs, 'usr/bin/bash')).existsSync();

if (native == null) {
conclusions.add('拿不到安装包的原生库目录，后面的检查没法做。请重新安装完整的安装包。');
return;
}

// 5. PRoot 本体能不能跑
step = _begin('PRoot 本体（--version）');
final versionCmd = _proot(const [], compat: false);
final version = await runProcess(versionCmd.executable, const ['--version'], environment: versionCmd.environment, timeout: commandTimeout);
_describeRun(step, '${versionCmd.executable} --version', version);
step.ok = version.printedOk;
final prootRuns = version.printedOk;

// 6. 默认 / 兼容模式各跑一条最小命令，各带一次详细输出
final results = <bool, bool>{};
for (final compat in const [false, true]) {
final label = compat? '兼容模式': '默认模式';
step = _begin('进 Ubuntu 跑 echo（$label）');
final cmd = _proot(const ['/bin/echo', 'ok'], compat: compat);
final run = await runProcess(cmd.executable, cmd.arguments, environment: cmd.environment, timeout: commandTimeout);
_describeRun(step, _show(cmd), run);
results[compat] = step.ok = run.printedOk && run.stdout.contains('ok');

step = _begin('同一条命令的详细输出（$label）');
final verbose = _proot(const ['/bin/echo', 'ok'], compat: compat, verbose: true);
final vrun = await runProcess(verbose.executable, verbose.arguments, environment: verbose.environment, timeout: commandTimeout);
_describeRun(step, 'PROOT_VERBOSE=9 + 上一条', vrun);
}
final defaultOk = results[false]?? false;
final compatOk = results[true]?? false;
final useCompat =!defaultOk && compatOk;

// 7. bash 登录 shell
step = _begin('bash 登录 shell');
final bashCmd = _proot(guestRun('echo ok; id; uname -a'), compat: useCompat);
final bash = await runProcess(bashCmd.executable, bashCmd.arguments, environment: bashCmd.environment, timeout: commandTimeout);
_describeRun(step, "…/bin/bash -lc 'echo ok; id; uname -a'（${useCompat? '兼容模式': '默认模式'}）", bash);
final bashOk = step.ok = bash.printedOk && bash.stdout.contains('ok');

// 8. 项目目录
step = _begin('项目目录（/workspace）');
if (projectDir == null) {
step.add('这次没有打开的项目，跳过。');
} else {
final wsCmd = _proot(const ['/bin/ls', '-la', guestWorkspace], compat: useCompat, projectDir: projectDir);
final ws = await runProcess(wsCmd.executable, wsCmd.arguments, environment: wsCmd.environment, timeout: commandTimeout);
_describeRun(step, '…/bin/ls -la /workspace（手机上的目录：$projectDir）', ws);
step.ok = ws.printedOk;
}

// 9. 伪终端自检：和 PRoot 无关，只看“终端 + 键盘输入”这条路通不通
final ptyOk = await _ptySelfTest();

// 10. 伪终端里跑 PRoot（和真正开终端时同一条路）
step = _begin('伪终端里进 Ubuntu 跑 echo');
final ptyProot = await _ptyProot(step, compat: useCompat);
step.ok = ptyProot;

// 结论
if (!prootRuns) {
conclusions.add('PRoot 本体就没跑起来（见“PRoot 本体”那一项的输出），问题在安装包里的文件或依赖库，不在 Ubuntu。');
} else if (defaultOk && bashOk) {
conclusions.add('普通方式能进 Ubuntu，bash 也正常。');
} else if (useCompat) {
conclusions.add('默认模式进不去，兼容模式可以。已经记住：以后都用兼容模式。');
await runtime.rememberCompat('诊断发现默认模式不行、兼容模式可以');
runtime.resetLaunchFailures();
} else if (!defaultOk &&!compatOk) {
conclusions.add('默认模式和兼容模式都进不了 Ubuntu。请把这份诊断整段复制发给小塔塔，里面的详细输出能看出卡在哪一步。');
} else if (!bashOk) {
conclusions.add('能进 Ubuntu 跑简单命令，但 bash 登录 shell 不正常（见“bash 登录 shell”那一项）。');
}
conclusions.add(
ptyOk
? '伪终端和输入这条路是通的：写进去的命令有回显、有结果。'
: '伪终端自检没通过：问题在“终端 / 输入”这一层，和 Ubuntu 无关。',
);
if (prootRuns && (defaultOk || compatOk)) {
conclusions.add(ptyProot? '在伪终端里进 Ubuntu 也正常，新开一个终端会话应该就能用了。': '普通进程能进 Ubuntu，但放进伪终端就不行——问题出在“伪终端 + PRoot”这个组合上。');
}
}

Future<bool> _ptySelfTest() async {
final step = _begin('伪终端自检（手机自带的 sh）');
final shell = localShell?? LocalShellBackend.shellPath;
final PtyProcess pty;
try {
pty = _ptySpawner(shell, workingDirectory: runtime.baseDir, environment: const {'TERM': 'dumb'}, rows: 24, columns: 80);
} catch (e) {
step
..add('伪终端开不出来：$e')
..ok = false;
return false;
}
final seen = StringBuffer();
final sub = pty.output.cast<List<int>>().transform(const Utf8Decoder(allowMalformed: true)).listen(seen.write, onError: (_) {});
final watch = Stopwatch()..start();
// 写进去的是 $((40+2))，结果里才会出现 42：能分清“回显”和“命令真的执行了”。
const typed = r'echo lopi-$((40+2))';
await Future<void>.delayed(const Duration(milliseconds: 300));
pty.write(utf8.encode('$typed\r'));
while (watch.elapsed < ptyTimeout &&!seen.toString().contains('lopi-42')) {
await Future<void>.delayed(const Duration(milliseconds: 100));
}
final text = seen.toString();
final echoed = text.contains(typed);
final executed = text.contains('lopi-42');
try {
pty.write(utf8.encode('exit\r'));
} catch (_) {}
await Future<void>.delayed(const Duration(milliseconds: 200));
try {
pty.kill();
} catch (_) {}
await sub.cancel();
step
..add('shell：$shell')
..add('写进去：$typed 加回车')
..add('回显（屏幕上看得到自己打的字）：${echoed? '有': '没有'}')
..add('执行结果（出现 lopi-42）：${executed? '有': '没有'}，用时 ${watch.elapsedMilliseconds} 毫秒')
..add('收到的全部内容：${text.trim().isEmpty? '（空）': '\n${_clip(text, 800)}'}')
..ok = echoed && executed;
return echoed && executed;
}

Future<bool> _ptyProot(DiagStep step, {required bool compat}) async {
final cmd = _proot(const ['/bin/echo', 'lopi-pty-ok'], compat: compat);
step.add('模式：${compat? '兼容模式': '默认模式'}');
final PtyProcess pty;
try {
pty = _ptyArgsSpawner(cmd.executable, cmd.arguments, workingDirectory: runtime.baseDir, environment: cmd.environment, rows: 24, columns: 80);
} catch (e) {
step.add('伪终端里启动不了 PRoot：$e');
return false;
}
final seen = StringBuffer();
final sub = pty.output.cast<List<int>>().transform(const Utf8Decoder(allowMalformed: true)).listen(seen.write, onError: (_) {});
final watch = Stopwatch()..start();
int? code;
unawaited(pty.exitCode.then((c) => code = c));
while (watch.elapsed < commandTimeout && code == null) {
await Future<void>.delayed(const Duration(milliseconds: 100));
}
await Future<void>.delayed(const Duration(milliseconds: 150));
final exited = code;
if (exited == null) {
try {
pty.kill();
} catch (_) {}
}
await sub.cancel();
final text = seen.toString();
step
..add(exited == null? '${watch.elapsed.inSeconds} 秒没结束，已强行停止（卡住了）': '退出码 $exited，用时 ${watch.elapsedMilliseconds} 毫秒')
..add('输出：${text.trim().isEmpty? '（空）': '\n${_clip(text, 1500)}'}');
return exited == 0 && text.contains('lopi-pty-ok');
}
}
