// 打包页先认项目类型：网页类走 APK，后端类走“构建与部署”，其它类保持现状（远程打 APK）。
// 规则和顺序见 docs/build-deploy-design.md 第 1 节。同步、只看文件在不在，不起进程。
import 'dart:convert';
import 'dart:io';

import 'package:lopicode/core/templates.dart';
import 'package:path/path.dart' as p;

enum ProjectKind {
  web('web', '网页'),
  backend('backend', '后端'),
  other('other', '其它（Flutter / 原生等）');

  const ProjectKind(this.id, this.label);
  final String id;
  final String label;

  /// 设置里存的值 → 类型；没存过 / 认不出来是 null（＝自动识别）。
  static ProjectKind? fromSetting(String value) => switch (value) {
    'web' => web,
    'backend' => backend,
    'other' => other,
    _ => null,
  };
}

/// 后端用的语言。前五种有完整支持；[other]＝认出是后端但语言不在这五种里。id 和运行环境清单（runtime_sources.dart）是同一套。
enum DeployLang {
  node('node', 'Node.js'),
  python('python', 'Python'),
  go('go', 'Go'),
  java('java', 'Java'),
  php('php', 'PHP'),
  other('other', '其它语言');

  const DeployLang(this.id, this.label);
  final String id;
  final String label;

  static DeployLang byId(String? id) => DeployLang.values.firstWhere((l) => l.id == id, orElse: () => DeployLang.other);
}

/// Java 工程的结构。只有 [flat] 能在手机上直接 javac + jar。
enum JavaLayout { flat, maven, gradle, packaged }

class DeployProject {
  const DeployProject({
    required this.kind,
    required this.auto,
    required this.reason,
    this.lang = DeployLang.other,
    this.dir = '',
    this.fromBlocks = false,
    this.javaLayout,
    this.javaMain,
    this.entry,
    this.hasPackageJson = false,
    this.hasRequirements = false,
    this.hasComposer = false,
  });

  final ProjectKind kind;

  /// true＝自动认出来的；false＝她手动选的。
  final bool auto;

  /// 为什么这么认（一句大白话）。
  final String reason;
  final DeployLang lang;

  /// 后端所在的目录，相对工作区（空＝根目录）。
  final String dir;

  /// 是不是后端积木生成的。
  final bool fromBlocks;
  final JavaLayout? javaLayout;

  /// Java 的主类（[JavaLayout.flat] 才有；找不到是 null）。
  final String? javaMain;

  /// 入口文件（Node / Python / PHP 没有依赖清单时，SSH 的默认命令拿它做语法检查）。
  final String? entry;
  final bool hasPackageJson;
  final bool hasRequirements;
  final bool hasComposer;

  /// 页面上“项目类型”那一行显示的字。
  String get title => kind == ProjectKind.backend ? '${kind.label} · ${lang.label}' : kind.label;
}

/// 后端可能在的目录，按这个顺序找。
const List<String> kDeployBackendDirs = ['', 'server', 'backend', 'api'];
const List<String> _webOutputDirs = ['dist', 'build', 'out', 'www', 'public', 'web'];
const List<String> _nodeEntries = ['server.js', 'index.js', 'app.js', 'main.js'];

/// 把名字收拾成只含字母数字和 `._-`（进文件名、进命令行都安全）；收拾完是空的就用 `app`。
String deploySafeName(String raw) {
  final s = raw.replaceAll(RegExp('[^A-Za-z0-9._-]+'), '-').replaceAll(RegExp('^[-.]+|[-.]+\$'), '');
  return s.isEmpty ? 'app' : s;
}

DeployProject detectDeployProject(String root, {ProjectTemplate template = ProjectTemplate.empty, String? templateLanguage, ProjectKind? override}) {
  bool has(String rel) => File(p.join(root, rel)).existsSync();
  bool hasDir(String rel) => Directory(p.join(root, rel)).existsSync();
  final found = _findBackend(root, templateLanguage: templateLanguage);

  DeployProject backend(bool auto, String reason) =>
      found?.copy(auto: auto, reason: reason) ?? DeployProject(kind: ProjectKind.backend, auto: auto, reason: reason, lang: DeployLang.byId(templateLanguage));
  DeployProject plain(ProjectKind kind, bool auto, String reason) => DeployProject(kind: kind, auto: auto, reason: reason);

  if (override != null) {
    const why = '你手动选的';
    return override == ProjectKind.backend ? backend(false, why) : plain(override, false, why);
  }
  if (has('pubspec.yaml')) return plain(ProjectKind.other, true, '有 pubspec.yaml，是 Flutter 项目');
  final gradle = has('build.gradle') || has('build.gradle.kts') || has('settings.gradle') || has('settings.gradle.kts');
  if (gradle && (has('app/src/main/AndroidManifest.xml') || has('src/main/AndroidManifest.xml'))) {
    return plain(ProjectKind.other, true, '有 Gradle 和 AndroidManifest.xml，是原生安卓项目');
  }
  if (template == ProjectTemplate.backendBlocks || template == ProjectTemplate.backendCode) return backend(true, '用“${template.label}”模板建的');
  final webStillThere = has('index.html') || has(kLowcodePageFile) || has('web/index.html');
  if ((template == ProjectTemplate.web || template == ProjectTemplate.lowcode || template == ProjectTemplate.fullstack) && webStillThere) {
    return plain(ProjectKind.web, true, template == ProjectTemplate.fullstack ? '用“前端 + 后端”模板建的，默认打包网页那一半；要部署后端就把类型改成“后端”' : '用“${template.label}”模板建的');
  }
  if (has(kLowcodePageFile)) return plain(ProjectKind.web, true, '有低代码页面');
  if (has('index.html')) return plain(ProjectKind.web, true, '根目录有 index.html');
  if (_hasBuildScript(File(p.join(root, 'package.json')))) return plain(ProjectKind.web, true, 'package.json 里有 build 脚本，是要构建的前端工程');
  if (found != null) return found;
  for (final dir in _webOutputDirs) {
    if (hasDir(dir) && has('$dir/index.html')) return plain(ProjectKind.web, true, '$dir 目录里有 index.html');
  }
  return plain(ProjectKind.other, true, '没认出网页，也没认出后端');
}

extension on DeployProject {
  DeployProject copy({required bool auto, required String reason}) => DeployProject(
    kind: kind,
    auto: auto,
    reason: reason,
    lang: lang,
    dir: dir,
    fromBlocks: fromBlocks,
    javaLayout: javaLayout,
    javaMain: javaMain,
    entry: entry,
    hasPackageJson: hasPackageJson,
    hasRequirements: hasRequirements,
    hasComposer: hasComposer,
  );
}

/// 在根目录和几个常见子目录里找后端特征；都没有返回 null。
DeployProject? _findBackend(String root, {String? templateLanguage}) {
  for (final dir in kDeployBackendDirs) {
    final base = dir.isEmpty ? root : p.join(root, dir);
    if (!Directory(base).existsSync()) continue;
    // 子目录是指到外面去的符号链接：不认。
    if (dir.isNotEmpty && FileSystemEntity.isLinkSync(base)) continue;
    bool has(String rel) => File(p.join(base, rel)).existsSync();
    final names = _fileNames(base);
    bool any(String ext) => names.any((n) => n.endsWith(ext));
    final where = dir.isEmpty ? '根目录' : '$dir 目录';

    DeployProject make(DeployLang lang, String mark, {bool blocks = false}) {
      final java = lang == DeployLang.java ? _javaLayout(base, names) : null;
      final entry = switch (lang) {
        DeployLang.node => _nodeEntries.where(has).firstOrNull ?? _firstWith(names, '.js'),
        DeployLang.python => ['main.py', 'app.py', 'server.py'].where(has).firstOrNull ?? _firstWith(names, '.py'),
        DeployLang.php => ['index.php', 'server.php'].where(has).firstOrNull ?? _firstWith(names, '.php'),
        _ => null,
      };
      return DeployProject(
        kind: ProjectKind.backend,
        auto: true,
        reason: '$where有 $mark',
        lang: lang,
        dir: dir,
        fromBlocks: blocks,
        javaLayout: java?.layout,
        javaMain: java?.main,
        entry: entry,
        hasPackageJson: has('package.json'),
        hasRequirements: has('requirements.txt'),
        hasComposer: has('composer.json'),
      );
    }

    if (has('backend.lc.json')) {
      final lang = _blocksLanguage(File(p.join(base, 'backend.lc.json'))) ?? templateLanguage;
      return make(DeployLang.byId(lang), 'backend.lc.json（后端积木）', blocks: true);
    }
    if (has('go.mod') || has('main.go')) return make(DeployLang.go, has('go.mod') ? 'go.mod' : 'main.go');
    final gradle = has('build.gradle') || has('build.gradle.kts');
    if (has('pom.xml') || gradle || any('.java') || Directory(p.join(base, 'src', 'main', 'java')).existsSync()) {
      return make(DeployLang.java, has('pom.xml') ? 'pom.xml' : (gradle ? 'build.gradle' : 'Java 源码'));
    }
    if (has('requirements.txt') || has('pyproject.toml') || any('.py')) return make(DeployLang.python, has('requirements.txt') ? 'requirements.txt' : 'Python 源码');
    if (has('composer.json') || any('.php')) return make(DeployLang.php, has('composer.json') ? 'composer.json' : 'PHP 源码');
    if (has('package.json') || _nodeEntries.any(has)) return make(DeployLang.node, has('package.json') ? 'package.json' : _nodeEntries.firstWhere(has));
  }
  return null;
}

List<String> _fileNames(String dir) {
  try {
    return [
      for (final e in Directory(dir).listSync(followLinks: false))
        if (e is File) p.basename(e.path),
    ]..sort();
  } on FileSystemException {
    return const []; // 读不了目录：当作里面什么都没有
  }
}

String? _firstWith(List<String> names, String ext) => names.where((n) => n.endsWith(ext)).firstOrNull;

({JavaLayout layout, String? main}) _javaLayout(String base, List<String> names) {
  if (File(p.join(base, 'pom.xml')).existsSync()) return (layout: JavaLayout.maven, main: null);
  if (File(p.join(base, 'build.gradle')).existsSync() || File(p.join(base, 'build.gradle.kts')).existsSync()) return (layout: JavaLayout.gradle, main: null);
  final sources = names.where((n) => n.endsWith('.java')).toList();
  if (sources.isEmpty) return (layout: JavaLayout.packaged, main: null);
  String? main;
  for (final name in sources) {
    final text = _readSmall(File(p.join(base, name)));
    if (text == null) continue;
    if (RegExp(r'^\s*package\s+[\w.]+\s*;', multiLine: true).hasMatch(text)) return (layout: JavaLayout.packaged, main: null);
    if (main == null && RegExp(r'static\s+void\s+main\s*\(').hasMatch(text)) main = name.substring(0, name.length - 5);
  }
  // 后端积木生成的入口永远是 Main；有好几个 main 时优先它。
  if (sources.contains('Main.java') && RegExp(r'static\s+void\s+main\s*\(').hasMatch(_readSmall(File(p.join(base, 'Main.java'))) ?? '')) main = 'Main';
  return (layout: JavaLayout.flat, main: main);
}

String? _readSmall(File file) {
  try {
    if (file.lengthSync() > 2 * 1024 * 1024) return null;
    return file.readAsStringSync();
  } on Object {
    return null; // 读不了 / 不是文本：当作没有
  }
}

String? _blocksLanguage(File file) {
  final text = _readSmall(file);
  if (text == null) return null;
  try {
    final j = jsonDecode(text);
    final lang = j is Map ? j['language'] : null;
    return lang is String ? lang : null;
  } on FormatException {
    return null;
  }
}

bool _hasBuildScript(File packageJson) {
  final text = packageJson.existsSync() ? _readSmall(packageJson) : null;
  if (text == null) return false;
  try {
    final j = jsonDecode(text);
    final scripts = j is Map ? j['scripts'] : null;
    final build = scripts is Map ? scripts['build'] : null;
    return build is String && build.trim().isNotEmpty;
  } on FormatException {
    return false;
  }
}
