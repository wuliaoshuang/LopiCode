// 规矩版本 2 的生成器“真跑”用的小工具：找各语言的编译器 / 解释器，把生成的整套文件写进临时目录，编译、运行，交回标准输出的原始字节。
// 找不到哪个程序就交回跳过的原因（测试里明确跳过并打印）。都不联网。
import 'dart:io';

import 'proc_bounded.dart';

String? _which(List<String> candidates, List<String> probe) {
  for (final exe in candidates) {
    if (exe.isEmpty) continue;
    try {
      if (Process.runSync(exe, probe).exitCode == 0) return exe;
    } on ProcessException {
      continue; // 这个位置没有，试下一个
    }
  }
  return null;
}

final String _home = Platform.environment['HOME'] ?? '';
final String _javaHome = Platform.environment['JAVA_HOME'] ?? '';

/// 每种语言要用的程序；找不到的是 null。
final Map<String, String?> gen2Tools = {
  'node': _which(['node'], ['--version']),
  'python': _which(['python3'], ['--version']),
  'php': _which([Platform.environment['LOPI_PHP'] ?? '', '$_home/workspace/tools/php/bin/php', 'php'], ['--version']),
  'go': _which([Platform.environment['LOPI_GO'] ?? '', '$_home/workspace/tools/gosdk/go/bin/go', 'go'], ['version']),
  'javac': _which([if (_javaHome.isNotEmpty) '$_javaHome/bin/javac', 'javac'], ['-version']),
  'java': _which([if (_javaHome.isNotEmpty) '$_javaHome/bin/java', 'java'], ['-version']),
};

/// 这种语言现在跑不了的原因；能跑是 null。
String? gen2SkipReason(String language) {
  final need = language == 'java' ? ['javac', 'java'] : [language];
  final missing = [
    for (final n in need)
      if (gen2Tools[n] == null) n,
  ];
  return missing.isEmpty ? null : '这台机器找不到 ${missing.join('、')}，跳过 $language 的真跑';
}

/// 一次真跑的结果：[stdout] 是原始字节；[problem] 不是 null 说明没跑成（编译没过、超时…），里面是原因。
class Gen2Run {
  const Gen2Run(this.stdout, this.problem, {this.exitCode});
  final List<int> stdout;
  final String? problem;

  /// 程序的退出码（没跑成＝null）。约定：正常结束是 0；有没接住的错，打印“出错：…”以后是 1。
  final int? exitCode;
}

// JAVA_TOOL_OPTIONS 会让 java 往标准错误多写一行；编译和运行都不要它。输出一律按 UTF-8。
Map<String, String> _env(String work) => {
  for (final e in Platform.environment.entries)
    if (e.key != 'JAVA_TOOL_OPTIONS') e.key: e.value,
  'LC_ALL': 'C.UTF-8',
  'GOFLAGS': '-mod=mod',
  'GOPROXY': 'off',
  'GOCACHE': '${Directory.systemTemp.path}/lopi_gen2_gocache',
};

/// 跑一条命令；到时间没跑完就按进程号杀掉再报超时（见 proc_bounded.dart）。
Future<ProcessResult> _run(String exe, List<String> args, String dir, {int seconds = 240}) => runBounded(
  exe,
  args,
  workingDirectory: dir,
  environment: _env(dir),
  includeParentEnvironment: false,
  limit: Duration(seconds: seconds),
  binaryOut: true,
);

/// 把 [files]（相对路径 → 内容）写进临时目录，按 [language] 编译并运行。用完目录就删。
/// [extra]：另外要放进目录的文件（相对路径 → 原始字节），给“读文件”的测试准备不是文字的文件用。
Future<Gen2Run> gen2RunFiles(String language, Map<String, String> files, {Map<String, List<int>> extra = const {}}) async {
  final dir = Directory.systemTemp.createTempSync('lopi_gen2_');
  try {
    for (final f in files.entries) {
      File('${dir.path}/${f.key}')
        ..createSync(recursive: true)
        ..writeAsStringSync(f.value);
    }
    for (final f in extra.entries) {
      File('${dir.path}/${f.key}')
        ..createSync(recursive: true)
        ..writeAsBytesSync(f.value);
    }
    final ProcessResult r;
    switch (language) {
      case 'node':
        r = await _run(gen2Tools['node']!, ['main.js'], dir.path);
      case 'python':
        r = await _run(gen2Tools['python']!, ['main.py'], dir.path);
      case 'php':
        r = await _run(gen2Tools['php']!, ['main.php'], dir.path);
      case 'go':
        final b = await _run(gen2Tools['go']!, ['build', '-o', 'prog', '.'], dir.path, seconds: 600);
        if (b.exitCode != 0) return Gen2Run(const [], 'go build 没过：${b.stderr}');
        r = await _run('${dir.path}/prog', const [], dir.path);
      case 'java':
        final sources = [
          for (final f in files.keys)
            if (f.endsWith('.java')) f,
        ];
        // -Xlint:all -Werror：生成的代码连一条警告都不许有。
        final b = await _run(gen2Tools['javac']!, ['-J-Xmx256m', '-J-XX:+UseSerialGC', '-encoding', 'UTF-8', '-Xlint:all', '-Werror', '-d', 'out', ...sources], dir.path, seconds: 600);
        if (b.exitCode != 0) return Gen2Run(const [], 'javac 没过：${b.stderr}');
        // 这台开发机上 Java 要走纯 IPv4 的套接字才连得上本机回环地址（工作区 env.sh 的 JAVA_TOOL_OPTIONS 里本来就带这一项；
        // 上面把整个 JAVA_TOOL_OPTIONS 去掉了，这一项单独补回来）。只影响“请求别的网址”的测试。
        r = await _run(gen2Tools['java']!, ['-Djava.net.preferIPv4Stack=true', '-cp', 'out', 'Main'], dir.path);
      default:
        return Gen2Run(const [], '不认识的语言 $language');
    }
    // 退出码不在这里判：程序里没接住的错按约定打印“出错：…”（也是要逐字节比的输出的一部分），然后退出码是 1；要查的测试自己看 exitCode。
    return Gen2Run(r.stdout as List<int>, null, exitCode: r.exitCode);
  } on Exception catch (e) {
    return Gen2Run(const [], '没跑成：$e');
  } finally {
    dir.deleteSync(recursive: true);
  }
}
