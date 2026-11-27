// 开发机验证环境（只在开发机上有，见 docs/api-notes.md 的“开发机验证环境”一节）：找得到就真编译 / 真跑，找不到就明确跳过。
// - 网页那一套（TypeScript、Vue 3、React、esbuild）：环境变量 LOPI_WEBDEV → ~/workspace/tools/webdev
// - 脚本在 tool/verify/ 下，只往标准输出写一行 JSON。都不联网。
import 'dart:convert';
import 'dart:io';

/// 装了 typescript / vue / react / esbuild 的目录；没有返回 null。
final String? webdevDir = () {
  final home = Platform.environment['HOME'] ?? '';
  for (final dir in [Platform.environment['LOPI_WEBDEV'] ?? '', '$home/workspace/tools/webdev']) {
    if (dir.isNotEmpty && Directory('$dir/node_modules').existsSync()) return dir;
  }
  return null;
}();

bool _runs(String exe, List<String> args) {
  try {
    return Process.runSync(exe, args).exitCode == 0;
  } on ProcessException {
    return false; // 这台机器没装：相关用例跳过
  }
}

final bool _hasNode = _runs('node', ['--version']);

/// 网页那一套能不能用；不能用时是跳过的原因（给 `skip:` 用），能用时是 false。
final Object skipWithoutWebdev = !_hasNode
    ? '找不到 node，跳过真编译'
    : webdevDir == null
    ? '找不到开发机验证环境（LOPI_WEBDEV 或 ~/workspace/tools/webdev），跳过真编译'
    : false;

/// 某个包在不在（比如 'typescript'、'vue'、'react'）。
bool webdevHas(String package) => webdevDir != null && File('$webdevDir/node_modules/$package/package.json').existsSync();

/// 一次真编译的结果。
class CompileResult {
  const CompileResult({required this.ok, required this.errors, required this.warnings, required this.html, required this.raw});
  final bool ok;
  final List<String> errors;
  final List<String> warnings;

  /// 服务端渲染出来的网页文字（没渲染成是空的）。
  final String html;
  final String raw;

  @override
  String toString() => 'ok=$ok errors=$errors warnings=$warnings';
}

/// 把一组文件写进临时目录，用 tool/verify/ 下的脚本真编译并渲染入口组件。用完目录就删。
Future<CompileResult> compileExport(String script, Map<String, String> files, String entry) async {
  final dir = Directory.systemTemp.createTempSync('lopi_webdev_');
  try {
    for (final f in files.entries) {
      File('${dir.path}/${f.key}')
        ..createSync(recursive: true)
        ..writeAsStringSync(f.value);
    }
    final r = await Process.run('node', ['${Directory.current.path}/tool/verify/$script', dir.path, entry], environment: {'LOPI_WEBDEV': webdevDir!});
    final out = (r.stdout as String).trim();
    if (out.isEmpty || !out.startsWith('{')) {
      return CompileResult(ok: false, errors: ['脚本没有给出结果（退出码 ${r.exitCode}）：${r.stderr}'], warnings: const [], html: '', raw: out);
    }
    final json = jsonDecode(out) as Map<String, Object?>;
    return CompileResult(
      ok: json['ok'] == true,
      errors: [for (final e in (json['errors'] as List?) ?? const []) '$e'],
      warnings: [for (final e in (json['warnings'] as List?) ?? const []) '$e'],
      html: '${json['html'] ?? ''}',
      raw: out,
    );
  } finally {
    dir.deleteSync(recursive: true);
  }
}

/// 用 tsc 编译一份 TypeScript（严格模式），编译过了再用 node 跑。
/// 返回（编译退出码、编译器说的话、运行的标准输出）。
Future<({int code, String messages, String stdout})> compileAndRunTs(String source, {String name = 'main'}) async {
  final dir = Directory.systemTemp.createTempSync('lopi_ts_');
  try {
    File('${dir.path}/$name.ts').writeAsStringSync(source);
    final tsc = await Process.run('node', [
      '${webdevDir!}/node_modules/typescript/bin/tsc',
      '--strict',
      '--target',
      'es2022',
      '--module',
      'commonjs',
      '--outDir',
      'out',
      '$name.ts',
    ], workingDirectory: dir.path);
    final messages = '${tsc.stdout}${tsc.stderr}';
    if (tsc.exitCode != 0) return (code: tsc.exitCode, messages: messages, stdout: '');
    final run = await Process.run('node', ['out/$name.js'], workingDirectory: dir.path);
    return (code: run.exitCode == 0 ? 0 : -run.exitCode, messages: '$messages${run.stderr}', stdout: run.stdout as String);
  } finally {
    dir.deleteSync(recursive: true);
  }
}

/// 装了 jsdom 的目录（在 Node 里当浏览器用，第 5 期的“真跑”要它）；没有返回 null。
final String? webdevDomDir = () {
  final home = Platform.environment['HOME'] ?? '';
  for (final dir in [Platform.environment['LOPI_WEBDEV_DOM'] ?? '', '$home/workspace/tools/webdev-dom']) {
    if (dir.isNotEmpty && File('$dir/node_modules/jsdom/package.json').existsSync()) return dir;
  }
  return null;
}();

/// “真跑”能不能做；不能时是跳过的原因。
final Object skipWithoutDom = skipWithoutWebdev != false
    ? skipWithoutWebdev
    : webdevDomDir == null
    ? '找不到 jsdom（LOPI_WEBDEV_DOM 或 ~/workspace/tools/webdev-dom），跳过真跑'
    : false;

/// 把导出的文件写进临时目录，在 jsdom 里照 [steps] 一步步做（tool/verify/run_dom.mjs）。[kind]：html / vue / react。[strict]＝React 外面包一层 StrictMode（开发时 React 会把开工那段多跑一遍，用来查“做了两遍事”）。
/// 返回（成不成、错误、警告、做完了几步）。
Future<({bool ok, List<String> errors, List<String> warnings, int done})> runInDom(
  String kind,
  Map<String, String> files,
  String entry,
  List<Map<String, Object?>> steps, {
  bool strict = false,
}) async {
  final dir = Directory.systemTemp.createTempSync('lopi_dom_');
  try {
    for (final f in files.entries) {
      File('${dir.path}/${f.key}')
        ..createSync(recursive: true)
        ..writeAsStringSync(f.value);
    }
    File('${dir.path}/.lc-steps.json').writeAsStringSync(jsonEncode(steps));
    final r = await Process.run(
      'node',
      ['${Directory.current.path}/tool/verify/run_dom.mjs', kind, dir.path, entry],
      environment: {'LOPI_WEBDEV': webdevDir!, 'LOPI_WEBDEV_DOM': webdevDomDir!, if (strict) 'LOPI_REACT_STRICT': '1'},
    );
    final out = (r.stdout as String).trim();
    if (out.isEmpty || !out.startsWith('{')) {
      return (ok: false, errors: ['脚本没有给出结果（退出码 ${r.exitCode}）：${r.stderr}'], warnings: const <String>[], done: 0);
    }
    final json = jsonDecode(out) as Map<String, Object?>;
    return (
      ok: json['ok'] == true,
      errors: [for (final e in (json['errors'] as List?) ?? const []) '$e'],
      warnings: [for (final e in (json['warnings'] as List?) ?? const []) '$e'],
      done: json['done'] is int ? json['done']! as int : 0,
    );
  } finally {
    dir.deleteSync(recursive: true);
  }
}
