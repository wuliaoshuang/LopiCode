/// 库（积木第 5 版·库 1）：一个库＝一个文件夹，里面是清单（`lib.json`）、模块文件（语法树的文字写法）、积木表。
/// 内置库和用户库是**同一种格式**、走同一个读入器（[libRead]）；差别只有“是不是内置”这一个开关管的三件事：
/// 旧名对照、自动用上、能不能直接声明宿主接口。格式的完整说明见 docs/blocks-v5-parts/library-format.md。
///
/// 这里只有纯数据和纯函数：输入是“相对路径 → 文件内容”的表（从磁盘读、从安装包里读、测试里直接写，都先变成这张表）。
/// 任何输入都不抛异常；读不了的地方记进 [LibLibrary.problems]，有问题的库不能用（[LibLibrary.ok] 是否）。
library;

import 'dart:convert';

import 'package:lopicode/lang/ast.dart';
import 'package:lopicode/lang/custom_block.dart';
import 'package:lopicode/lang/host_v2.dart';
import 'package:lopicode/lang/lc_text.dart';
import 'package:lopicode/lang/lib_check.dart';
import 'package:lopicode/lang/types.dart';

/// 清单的文件名、清单里 `kind` 的固定值、现在认识的格式版本。
const String kLibManifestFile = 'lib.json';
const String kLibKind = 'lopicode-lib';
const int kLibFormat = 1;

/// 上限（自定，防坏数据）：一个库最多几个模块、几块积木、几个设置项；一个文件最多多少字。
const int kLibMaxModules = 32;
const int kLibMaxBlocks = 400;
const int kLibMaxSettings = 64;
const int kLibMaxFileChars = 400000;

/// 库的标识：`作者段/库名`，两段都是小写字母、数字、连字符，字母开头，每段最多 32 个字符。
final RegExp kLibIdPattern = RegExp(r'^[a-z][a-z0-9-]{0,31}/[a-z][a-z0-9-]{0,31}$');

/// 定义一块积木的四种办法（C 分册 7.2、7.3）。
enum LibHow {
  /// 调一个函数：`of` 是函数名。
  call,

  /// 调对象的方法：`of` 是方法名，`args` 的第一项是那个对象，其余是实参。
  method,

  /// 调类自己的方法（不用先有对象）：`of` 是 `类名.方法名`。
  static,

  /// 模板展开：用的地方原地换成 `expand` 里写的那一段。
  expand,
}

/// 库里多出来的槽种类（外观里的槽种类不够用的那几种；外观里照旧按“值槽”存，这里另记）。
enum LibSlotKind {
  /// 普通的值（默认）。
  value,

  /// 只许直接填的文字 / 数字（帽子上的路径、集合名：生成前就要知道）。
  literal,

  /// “放进变量”：槽里选一个变量，积木把结果写进去；可以空着。
  assign,

  /// 口：里面放一串积木。
  mouth,
}

/// 调用型积木的一个实参从哪来。
sealed class LibArg {
  const LibArg();
}

/// 槽里的东西。
class LibArgSlot extends LibArg {
  const LibArgSlot(this.slot);
  final String slot;
}

/// 隐含的东西：所在的帽子（或外面的口）递进来的，积木上没有这一格。
class LibArgContext extends LibArg {
  const LibArgContext(this.name);
  final String name;
}

/// 这份文档里这个库的某个设置项的值。
class LibArgSetting extends LibArg {
  const LibArgSetting(this.id);
  final String id;
}

/// 预先填死的值（空 / 是否 / 数 / 文字）。
class LibArgPreset extends LibArg {
  const LibArgPreset(this.value);
  final Object? value;
}

/// 一块库积木。
class LibBlock {
  const LibBlock({
    required this.id,
    required this.module,
    required this.look,
    required this.how,
    this.of = '',
    this.args = const [],
    this.expand = '',
    this.slotKinds = const {},
    this.into,
    this.needs = const [],
    this.provides = const {},
    this.legacyFn,
    this.legacyArgs = const [],
    this.category = '',
  });

  /// 积木编号（库里唯一；存进用户文档的就是 `库标识:编号`）。
  final String id;

  /// 它背后的定义在哪个模块。
  final String module;
  final CustomBlockLook look;
  final LibHow how;

  /// 调用型：调谁（见 [LibHow]）。展开型不用。
  final String of;
  final List<LibArg> args;

  /// 展开型：模板（语法树的文字写法，可以用 `(槽 名)` `(隐含 名)` `(设置 编号)` `(口 名)` `(放进 槽名 式子)`）。
  final String expand;

  /// 不是普通值槽的那些槽：槽名 → 种类。
  final Map<String, LibSlotKind> slotKinds;

  /// 调用型：结果写进哪个“放进变量”槽选的变量（没选变量就只调不存）。
  final String? into;

  /// 它要用到的“隐含的东西”的名字（校验时拦：不在给这个东西的帽子下面不许用）。
  final List<String> needs;

  /// 它给口里的积木递的“隐含的东西”：名字 → 模板里的变量名。
  final Map<String, String> provides;

  /// 旧名对照（只有内置库生效）：规矩版本 1 的小库里叫什么函数、那个函数的参数依次是这块积木的哪个槽
  /// （`@隐含名` ＝那一位是隐含的东西，比如“这次请求”）。
  final String? legacyFn;
  final List<String> legacyArgs;
  final String category;

  LibSlotKind kindOf(String slot) => slotKinds[slot] ?? LibSlotKind.value;

  /// 形状（外观上写的是什么就是什么；“自动”在库里按语句算）。
  CustomBlockShape get shape => look.shape == CustomBlockShape.auto ? CustomBlockShape.statement : look.shape;
  bool get isValue => shape == CustomBlockShape.value || shape == CustomBlockShape.boolean;
}

/// 库公开的一个类型（给积木盒、类型选择器看的；定义本身在模块里）。
class LibType {
  const LibType(this.name, this.module, {this.hint = ''});
  final String name;
  final String module;
  final String hint;
}

/// 库的一个设置项：每份用了这个库的文档各存一份值。
class LibSetting {
  const LibSetting({required this.id, required this.name, required this.type, this.defaultValue, this.min, this.max, this.hint = '', this.legacyKey});
  final String id;
  final String name;
  final LType type;

  /// 空 / 是否 / 数 / 文字 / 这些的列表。
  final Object? defaultValue;
  final num? min;
  final num? max;
  final String hint;

  /// 旧文档顶层的哪个键是它（`port`、`collections`；只有内置库生效）。
  final String? legacyKey;
}

/// 读好的一个库。
class LibLibrary {
  const LibLibrary({
    required this.id,
    required this.name,
    required this.version,
    required this.builtin,
    this.format = kLibFormat,
    this.summary = '',
    this.rules = 2,
    this.modules = const [],
    this.blocks = const [],
    this.types = const [],
    this.settings = const [],
    this.init = '',
    this.start = '',
    this.provides = const {},
    this.autoUse = const [],
    this.hosts = const [],
    this.nativeAllowed = false,
    this.nativeFiles = const [],
    this.problems = const [],
    this.author = '',
    this.requires = const [],
    this.nativeWaits = const [],
  });

  final String id;
  final String name;
  final String version;
  final bool builtin;
  final int format;
  final String summary;

  /// 这个库是照哪一版规矩写的（现在只有 2：严格规矩）。
  final int rules;
  final List<LModule> modules;
  final List<LibBlock> blocks;
  final List<LibType> types;
  final List<LibSetting> settings;

  /// 两个时刻的模板（C 分册 7.7）：[init] 放在入口模块“程序开始时”的最前面，[start] 放在最后面（开端口这种）。
  final String init;
  final String start;

  /// [init] 给整份文档递的“隐含的东西”：名字 → [init] 里的变量名。
  final Map<String, String> provides;

  /// 哪种文档自动用上它（`backend` / `page`；只有内置库生效）。
  final List<String> autoUse;

  /// 用到的宿主接口（读库时按模块里的“宿主”声明算出来的，不信清单里写的）。
  final List<String> hosts;

  /// “允许手写代码”的开关，和库里带的手写代码文件（现在只读进来、不生成，见格式文档第 8 节）。
  final bool nativeAllowed;
  final List<String> nativeFiles;

  /// 作者（给人看的；清单的 `author`）。
  final String author;

  /// 要靠哪些别的库（清单的 `requires`，库的标识）：它的模块里用了那些库公开的名字。用它的文档也得带上那些库。
  final List<String> requires;

  /// 手写代码里“要等”的函数名（清单 `native.waits`）。没列到的手写函数一律当“不用等”。
  /// 现在手写代码整条路还没通（见格式文档第 8 节），这里只读进来给预览页如实显示。
  final List<String> nativeWaits;

  /// 读的时候发现的问题（给人看的话）。有一条就不能用。
  final List<String> problems;

  bool get ok => problems.isEmpty;

  LibBlock? block(String id) => blocks.where((b) => b.id == id).firstOrNull;
  LibSetting? setting(String id) => settings.where((s) => s.id == id).firstOrNull;

  /// 旧小库的函数名 → 积木（只有内置库有）。
  LibBlock? legacy(String fn) => builtin ? blocks.where((b) => b.legacyFn == fn).firstOrNull : null;

  /// 模块的名字。
  List<String> get moduleNames => [for (final m in modules) m.name];
}

// ———————————————————————— 读 ————————————————————————

String? _text(Object? v, {int max = 200}) => v is String && v.trim().isNotEmpty && v.length <= max ? v : null;
List<Object?> _list(Object? v) => v is List ? v : const [];
Map<Object?, Object?> _map(Object? v) => v is Map ? v : const {};
bool _plain(Object? v) => v == null || v is bool || v is num || v is String;

Object? _json(String? src) {
  if (src == null) return null;
  try {
    return jsonDecode(src);
  } on FormatException {
    return null;
  }
}

/// 类型的文字写法（`整数`、`(字典 任意)`、`(可空 文字)`）→ 类型；写坏了返回 null。
LType? libTypeFromText(Object? src) {
  if (src is! String || src.trim().isEmpty || src.length > 400) return null;
  try {
    final parsed = lcParse(src);
    return parsed.length == 1 ? LcReader(const []).ty(parsed.single) : null;
  } on Object {
    return null;
  }
}

LibArg? _arg(Object? raw, Set<String> slots) {
  if (raw is String) return slots.contains(raw) ? LibArgSlot(raw) : null;
  if (raw is! Map || raw.length != 1) return null;
  final key = raw.keys.single, value = raw.values.single;
  return switch (key) {
    'context' when value is String && value.isNotEmpty => LibArgContext(value),
    'setting' when value is String && value.isNotEmpty => LibArgSetting(value),
    'preset' when _plain(value) => LibArgPreset(value),
    _ => null,
  };
}

LibBlock? _block(Object? raw, List<String> problems, Set<String> moduleNames) {
  if (raw is! Map) {
    problems.add('积木表里有一项不是积木，读不了');
    return null;
  }
  final id = _text(raw['id'], max: 64);
  if (id == null || !RegExp(r'^[A-Za-z][A-Za-z0-9_]*$').hasMatch(id)) {
    problems.add('有一块积木没有编号，或者编号不是字母开头的字母数字');
    return null;
  }
  void bad(String why) => problems.add('积木「$id」：$why');
  final look = customBlockLookFromJson(raw['look']);
  if (look == null) {
    bad('没有外观（look）');
    return null;
  }
  final slotNames = {
    for (final p in parseLookTemplate(look.template))
      if (p.isSlot) p.text,
  };
  final kinds = <String, LibSlotKind>{};
  for (final e in _map(raw['slotKinds']).entries) {
    final kind = LibSlotKind.values.where((k) => k.name == e.value).firstOrNull;
    if (e.key is! String || kind == null) {
      bad('槽的种类写得不对：${e.key}');
    } else if (!slotNames.contains(e.key)) {
      bad('槽的种类里写了外观上没有的槽「${e.key}」');
    } else {
      kinds[e.key as String] = kind;
    }
  }
  final how = LibHow.values.where((h) => h.name == raw['how']).firstOrNull;
  if (how == null) {
    bad('没写清是哪种定义办法（how 要是 call / method / static / expand）');
    return null;
  }
  final module = _text(raw['module'], max: 64) ?? (moduleNames.length == 1 ? moduleNames.single : '');
  if (!moduleNames.contains(module)) bad('它说的模块「$module」库里没有');
  final args = <LibArg>[];
  for (final a in _list(raw['args'])) {
    final arg = _arg(a, slotNames);
    if (arg == null) {
      bad('实参表里有一项读不懂（要是槽名，或者 {"context": 名} / {"setting": 编号} / {"preset": 值}）');
    } else {
      args.add(arg);
    }
  }
  final into = raw['into'];
  if (into != null && (into is! String || kinds[into] != LibSlotKind.assign)) bad('into 要指向一个“放进变量”的槽');
  final provides = <String, String>{};
  for (final e in _map(raw['provides']).entries) {
    if (e.key is String && e.value is String) provides[e.key as String] = e.value as String;
  }
  final legacy = _map(raw['legacy']);
  return LibBlock(
    id: id,
    module: module,
    look: look,
    how: how,
    of: _text(raw['of'], max: 128) ?? '',
    args: args,
    expand: raw['expand'] is String ? raw['expand'] as String : '',
    slotKinds: kinds,
    into: into is String ? into : null,
    needs: [for (final n in _list(raw['needs'])) ?_text(n, max: 64)],
    provides: provides,
    legacyFn: _text(legacy['fn'], max: 64),
    legacyArgs: [for (final a in _list(legacy['args'])) ?_text(a, max: 64)],
    category: _text(raw['category'], max: 64) ?? '',
  );
}

LibSetting? _setting(Object? raw, List<String> problems) {
  if (raw is! Map) return null;
  final id = _text(raw['id'], max: 64);
  final type = libTypeFromText(raw['type']);
  if (id == null || type == null) {
    problems.add('有一个设置项没有编号或类型写得不对');
    return null;
  }
  final d = raw['default'];
  if (!(_plain(d) || (d is List && d.every(_plain)))) {
    problems.add('设置项「$id」的默认值只能是空、是否、数、文字，或者它们的列表');
    return null;
  }
  return LibSetting(
    id: id,
    name: _text(raw['name'], max: 24) ?? id,
    type: type,
    defaultValue: d,
    min: raw['min'] is num ? raw['min'] as num : null,
    max: raw['max'] is num ? raw['max'] as num : null,
    hint: _text(raw['hint'], max: 200) ?? '',
    legacyKey: _text(raw['legacyKey'], max: 64),
  );
}

/// 读一个库。[files]＝相对路径 → 内容；[builtin]＝是不是应用自带的。
LibLibrary libRead(Map<String, String> files, {required bool builtin}) {
  final problems = <String>[];
  LibLibrary fail(String why, {String id = '', String name = ''}) => LibLibrary(id: id, name: name, version: '0.0.0', builtin: builtin, problems: [why, ...problems]);
  for (final e in files.entries) {
    if (e.value.length > kLibMaxFileChars) return fail('文件 ${e.key} 太大（最多 $kLibMaxFileChars 个字）');
  }
  final manifest = _json(files[kLibManifestFile]);
  if (manifest is! Map) return fail('没有清单 $kLibManifestFile，或者它不是合法的 JSON');
  if (manifest['kind'] != kLibKind) return fail('清单里的 kind 不是 $kLibKind，这不是一个库');
  final id = _text(manifest['id'], max: 65);
  if (id == null || !kLibIdPattern.hasMatch(id)) return fail('库的标识要写成“作者段/库名”（小写字母、数字、连字符，字母开头）');
  final name = _text(manifest['name'], max: 24) ?? id.split('/').last;
  final format = manifest['format'] is int ? manifest['format'] as int : kLibFormat;
  if (format > kLibFormat) problems.add('这个库是更新的应用做的（格式第 $format 版），这一版读不了');
  final version = _text(manifest['version'], max: 32);
  if (version == null || !RegExp(r'^\d+\.\d+\.\d+$').hasMatch(version)) problems.add('版本号要写成 大.中.小（比如 1.0.0）');
  final rules = manifest['rules'] is int ? manifest['rules'] as int : 2;
  if (rules != 2) problems.add('库只能照严格规矩（规矩版本 2）写');

  // 模块：一个文件里是一个或几个 `(模块 名 (用 …) 声明…)`。
  final modules = <LModule>[];
  for (final raw in _list(manifest['modules']).take(kLibMaxModules)) {
    final file = raw is Map ? _text(raw['file']) : _text(raw);
    final src = file == null ? null : files[file];
    if (src == null) {
      problems.add('清单里写的模块文件 ${file ?? '（没写名字）'} 不在库里');
      continue;
    }
    final read = lcTryProgram(src);
    final program = read.program;
    if (program == null) {
      problems.add('模块文件 $file 读不了：${read.problem}');
      continue;
    }
    for (final m in program.modules) {
      if (m.body.isNotEmpty) problems.add('模块「${m.name}」里有“程序开始时”：库的模块不许有（要在启动时做的事写进清单的 init / start）');
      if (modules.any((x) => x.name == m.name)) {
        problems.add('模块「${m.name}」出现了两次');
      } else {
        modules.add(m);
      }
    }
  }
  final moduleNames = {for (final m in modules) m.name};

  // 积木表：清单里 `blocks` 列的每个文件是 `{"blocks": […]}`。
  final blocks = <LibBlock>[];
  for (final raw in _list(manifest['blocks'])) {
    final file = _text(raw);
    final parsed = _json(file == null ? null : files[file]);
    if (parsed is! Map || parsed['blocks'] is! List) {
      problems.add('积木表文件 ${file ?? '（没写名字）'} 不在库里，或者不是 {"blocks": […]} 的样子');
      continue;
    }
    for (final b in parsed['blocks'] as List) {
      if (blocks.length >= kLibMaxBlocks) break;
      final block = _block(b, problems, moduleNames);
      if (block == null) continue;
      if (blocks.any((x) => x.id == block.id)) {
        problems.add('积木编号「${block.id}」用了两次');
      } else {
        blocks.add(block);
      }
    }
  }

  final settings = <LibSetting>[];
  for (final raw in _list(manifest['settings']).take(kLibMaxSettings)) {
    final s = _setting(raw, problems);
    if (s == null) continue;
    if (settings.any((x) => x.id == s.id)) {
      problems.add('设置项「${s.id}」出现了两次');
    } else {
      settings.add(s);
    }
  }
  final types = <LibType>[];
  for (final raw in _list(manifest['types'])) {
    final n = raw is Map ? _text(raw['name'], max: 64) : null;
    if (n == null) continue;
    final module = _text((raw as Map)['module'], max: 64) ?? (moduleNames.length == 1 ? moduleNames.single : '');
    types.add(LibType(n, module, hint: _text(raw['hint']) ?? ''));
  }
  final provides = <String, String>{};
  for (final e in _map(manifest['provides']).entries) {
    if (e.key is String && e.value is String) provides[e.key as String] = e.value as String;
  }

  // 原生绑定：模块里的“宿主”声明。只有内置库可以直接声明宿主接口；用户库只能经内置库去碰。
  final hosts = <String>{
    for (final m in modules)
      for (final d in m.decls)
        if (d is LNativeDecl) d.name,
  };
  for (final h in hosts) {
    if (!kHostV2.containsKey(h)) problems.add('模块里声明了宿主接口「$h」，这一版的应用没有它');
  }
  if (!builtin && hosts.isNotEmpty) problems.add('这个库直接声明了宿主接口（${hosts.join('、')}）。只有应用自带的库可以；自己写的库请调自带库公开的函数');
  final native = _map(manifest['native']);
  final nativeAllowed = native['allowed'] == true;
  final nativeFiles = [
    for (final f in files.keys)
      if (f.startsWith('native/')) f,
  ];
  if (nativeFiles.isNotEmpty && !nativeAllowed) problems.add('库里带了手写代码（${nativeFiles.length} 个文件），这一版的应用不会启用手写代码');
  if (nativeFiles.isNotEmpty && nativeAllowed) problems.add('库里带了手写代码。这一版的应用还不会把手写代码放进生成的工程里，所以这个库现在用不了');
  if (!builtin && (id.startsWith('lopi/') || id.startsWith('local/'))) problems.add('作者段 lopi、local 是应用自己留着用的，别的库不能用');

  final lib = LibLibrary(
    id: id,
    name: name,
    version: version ?? '0.0.0',
    builtin: builtin,
    format: format,
    summary: _text(manifest['summary'], max: 80) ?? '',
    rules: rules,
    modules: modules,
    blocks: blocks,
    types: types,
    settings: settings,
    init: manifest['init'] is String ? manifest['init'] as String : '',
    start: manifest['start'] is String ? manifest['start'] as String : '',
    provides: provides,
    autoUse: [
      if (builtin)
        for (final a in _list(manifest['autoUse'])) ?_text(a, max: 16),
    ],
    hosts: hosts.toList()..sort(),
    nativeAllowed: nativeAllowed,
    nativeFiles: nativeFiles,
    author: _text(manifest['author'], max: 64) ?? '',
    requires: [
      for (final r in _list(manifest['requires']).take(16))
        if (r is String && kLibIdPattern.hasMatch(r)) r,
    ],
    nativeWaits: [for (final w in _list(native['waits']).take(64)) ?_text(w, max: 64)],
  );
  problems.addAll(libCheck(lib));
  return LibLibrary(
    id: lib.id,
    name: lib.name,
    version: lib.version,
    builtin: builtin,
    format: format,
    summary: lib.summary,
    rules: rules,
    modules: modules,
    blocks: blocks,
    types: types,
    settings: settings,
    init: lib.init,
    start: lib.start,
    provides: provides,
    autoUse: lib.autoUse,
    hosts: lib.hosts,
    nativeAllowed: nativeAllowed,
    nativeFiles: nativeFiles,
    problems: problems,
    author: lib.author,
    requires: lib.requires,
    nativeWaits: lib.nativeWaits,
  );
}
