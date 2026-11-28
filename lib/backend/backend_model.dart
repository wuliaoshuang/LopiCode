/// 后端积木的数据模型：一份 `backend.lc.json`＝服务名、端口、语言、变量、数据集合、接口（每个接口是一串积木）。
///
/// 这里只管数据的形状、读写和最基本的增删（读的时候容错：坏字段逐条跳过，整份坏了回一份空白文档加一句说明，
/// 绝不抛异常）。有哪些积木在 backend_blocks.dart，校验在 backend_validate.dart，翻成各语言在 backend_target.dart。
/// JSON 结构的约定见 docs/blocks-v3-design.md 的“后端积木”一节。
library;

import 'dart:convert';
import 'dart:io';

import 'package:lopicode/backend/backend_blocks_core.dart';
import 'package:lopicode/backend/backend_blocks_func.dart';
import 'package:lopicode/backend/backend_blocks_lang.dart';
import 'package:lopicode/backend/backend_core.dart';
import 'package:lopicode/backend/backend_function.dart';
import 'package:lopicode/backend/backend_lib_doc.dart';
import 'package:lopicode/core/safe_file.dart';
import 'package:lopicode/lang/lib_model.dart';
import 'package:lopicode/lang/rules.dart';
import 'package:lopicode/lowcode/lib_blocks.dart';
import 'package:lopicode/lowcode/lib_front_builtin.dart';
import 'package:lopicode/lowcode/lib_page.dart';
import 'package:lopicode/lowcode/logic_model.dart';

/// 存盘文件名。
const String kBackendFileName = 'backend.lc.json';

/// 接口能用的请求方式。
const List<String> kBeMethods = ['GET', 'POST', 'PUT', 'PATCH', 'DELETE'];

/// 默认端口和语言。
const int kBeDefaultPort = 8080;
const String kBeDefaultLanguage = 'node';

/// 集合名、路径参数名的规矩和变量名一样：英文字母 / 数字 / 下划线，不用数字开头，最多 32 个字符。
final RegExp beNamePattern = LcVariable.namePattern;

/// 接口 id、语言 id 只留这些字符（会拼进生成代码的函数名、文件名）。
final RegExp _idPattern = RegExp(r'^[A-Za-z0-9_]{1,32}$');

/// 路径里一段普通文字能用的字符。
final RegExp _literalSegment = RegExp(r'^[A-Za-z0-9_.~-]+$');

/// 路径的一段：普通文字，或 `:名字`（路径参数）。
typedef BePathSegment = ({bool isParam, String text});

/// 把接口路径拆成一段段。格式不对返回 null。
///
/// 规矩：以 `/` 开头；每段是 `字母数字 _ . ~ -` 组成的文字，或 `:参数名`；不许有空段（`//`），末尾不带 `/`（只有根路径 `/` 例外）。
List<BePathSegment>? parseBePath(String path) {
  if (path == '/') return const [];
  if (!path.startsWith('/') || path.length > 200) return null;
  final out = <BePathSegment>[];
  for (final seg in path.substring(1).split('/')) {
    if (seg.startsWith(':')) {
      final name = seg.substring(1);
      if (!beNamePattern.hasMatch(name)) return null;
      out.add((isParam: true, text: name));
    } else {
      if (!_literalSegment.hasMatch(seg)) return null;
      out.add((isParam: false, text: seg));
    }
  }
  return out;
}

/// 路径里的参数名（按出现顺序）；路径格式不对返回空表。
List<String> bePathParams(String path) => [
  for (final s in parseBePath(path) ?? const <BePathSegment>[])
    if (s.isParam) s.text,
];

/// 用来判断“两个接口是不是同一个地址”的写法：参数名抹掉（`/todos/:id` 和 `/todos/:x` 是同一个）。格式不对返回 null。
String? bePathShape(String path) {
  final segs = parseBePath(path);
  if (segs == null) return null;
  return '/${[for (final s in segs) s.isParam ? ':' : s.text].join('/')}';
}

/// 一个数据集合：里面一条是一个对象，自动带数字 `id`（从 1 递增）。存在内存里，进程重启就没了。
class BeCollection {
  BeCollection({required this.name});

  String name;

  Map<String, dynamic> toJson() => {'name': name};

  static BeCollection? tryParse(Object? json) {
    if (json is! Map) return null;
    final name = json['name'];
    if (name is! String || !beNamePattern.hasMatch(name)) return null;
    return BeCollection(name: name);
  }
}

/// 一个接口：请求方式 + 路径 + 一串积木。
class BeRoute with LcBlockTree {
  BeRoute({required this.id, required this.method, required this.path, List<LcBlock>? body, double? x, double? y}) : body = body ?? [] {
    this.x = x;
    this.y = y;
  }

  @override
  String id;
  String method;
  String path;
  @override
  final List<LcBlock> body;

  Map<String, dynamic> toJson() => {
    'id': id,
    'method': method,
    'path': path,
    if (x != null) 'x': x,
    if (y != null) 'y': y,
    'body': [for (final b in body) b.toJson()],
  };

  BeRoute clone() => BeRoute(id: id, method: method, path: path, body: [for (final b in body) b.clone()], x: x, y: y);

  /// 请求方式不认识、路径不是文字的跳过；路径**格式**不对的留着（校验会指出来，让人能改），不丢数据。
  static BeRoute? tryParse(Object? json) {
    if (json is! Map) return null;
    final method = json['method'];
    final path = json['path'];
    if (method is! String || path is! String) return null;
    final upper = method.toUpperCase();
    if (!kBeMethods.contains(upper)) return null;
    final id = json['id'];
    final x = json['x'];
    final y = json['y'];
    return BeRoute(
      id: id is String ? id : '',
      method: upper,
      path: path,
      body: LcBlock.parseList(json['body'], 0),
      x: x is num && x.isFinite ? x.toDouble() : null,
      y: y is num && y.isFinite ? y.toDouble() : null,
    );
  }
}

/// 读文件的结果：文档一定有；`note` 不为 null＝读的时候出了状况（整份读不懂、跳过了几条），可以给人看。
typedef BeParseResult = ({BeDocument doc, String? note});

class BeDocument implements LibUser {
  BeDocument({
    this.name = '我的后端',
    int port = kBeDefaultPort,
    String language = kBeDefaultLanguage,
    List<LcVariable>? variables,
    List<BeCollection>? collections,
    List<BeRoute>? routes,
    List<BeFunction>? functions,
    BeCore? core,
    int rules = kLangRulesLoose,
    this.library,
    List<BeLibUse>? uses,
    this.serviceLib = '',
    List<BeLibHat>? hats,
    List<LibLibrary> loaded = const [],
    this.front = false,
  }) : _loaded = loaded, // ignore: prefer_initializing_formals 对外的参数名要叫 loaded，不叫 _loaded
       port = _validPort(port) ? port : kBeDefaultPort,
       rules = rules < kLangRulesLoose ? kLangRulesLoose : rules,
       language = _idPattern.hasMatch(language) ? language : kBeDefaultLanguage,
       variables = variables ?? [],
       collections = collections ?? [],
       routes = routes ?? [],
       functions = functions ?? [],
       uses = uses ?? [],
       hats = hats ?? [],
       core = core ?? BeCore() {
    _normalize();
  }

  String name;
  int port;

  /// 目标语言的 id（见 backend_target.dart 的 `backendTargets`）。没有对应生成器的 id 也留着（可能是新版本写的）。
  String language;

  /// 变量：每次请求开始时重置成初始值。`type` 只决定初始值，运行时可以放任何值（对象、列表也行）。
  final List<LcVariable> variables;
  final List<BeCollection> collections;
  final List<BeRoute> routes;

  /// 函数 / “我的积木”（积木第 4 版·第 2 阶段，见 backend_function.dart）。每个接口、每个函数里都能调。
  final List<BeFunction> functions;

  /// 核心 2 的东西：自己定义的类型、模块顶上的变量、模块、“程序开始时”（见 backend_core.dart）。一样都没有时存盘不写。
  final BeCore core;

  /// 有没有用到核心 2 才有的东西（类型、模块、“程序开始时”，或者哪一串里用了核心 2 的积木）。用到了版本号写 4。
  bool get usesCore => !core.isEmpty || routes.any((r) => beBlocksUseCore(r.body)) || functions.any((f) => beBlocksUseCore(f.body));

  /// 这份文档本身是一个库（见 backend_lib_doc.dart）；null＝普通的后端文档。
  BeLibInfo? library;

  /// 用了哪些库（应用自带的“接口服务”不在这里，它是自动带上的）。
  @override
  final List<BeLibUse> uses;

  /// 用哪个库顶替自带的“接口服务”（库的标识；那个库的清单里要写着 replaces）。空＝用自带的。
  String serviceLib;

  /// 画布上以库的帽子积木开头的那些串。
  final List<BeLibHat> hats;

  /// [uses] 里的库读进来的样子（不存盘：打开文档的人从项目的 `blocks/` 里读好了放进来，见 backend_lib_store.dart）。
  /// 翻译、检查、生成都从这里找库；[uses] 里写了、这里没有的＝“库不在项目里”。
  /// 前端这一边的文档永远带着自带的前端库（“页面”排第一个，后面是定时、请求……那五个要用才用的），不用项目里有。
  @override
  List<LibLibrary> get loaded => isFront ? [...lcFrontBuiltinAll(), ..._loaded.where((l) => !lcIsFrontBuiltin(l.id))] : _loaded;
  @override
  set loaded(List<LibLibrary> value) => _loaded = value;
  List<LibLibrary> _loaded;

  /// 前端这一边的文档自动用上内置库“页面”（排第一个）；不是前端的文档不许用它。改了“给谁用”以后调一下。
  void syncSide() {
    final has = uses.any((u) => u.id == kLcPageLibId);
    if (isFront && !has) uses.insert(0, BeLibUse(kLcPageLibId));
    if (!isFront) uses.removeWhere((u) => lcIsFrontBuiltin(u.id));
  }

  // —— “会用库的文档”（lib/lowcode/lib_blocks.dart 的 [LibUser]）要的几样 ——
  @override
  LibSide get libSide => isFront ? LibSide.frontend : LibSide.backend;

  /// 这份文档是一页的页面逻辑（存在页面文件的 `logic.front` 里，见 front_doc.dart）：没有接口、集合、端口、语言，
  /// 自动带上内置库“页面”而不是“接口服务”。存盘时写 `"side": "frontend"`；后端文档不写这一项。
  bool front;

  /// 前端这一边的文档：页面逻辑，或者“给谁用＝前端”的库。
  bool get isFront => front || library?.side == LibSide.frontend;
  @override
  String? get libraryId => library?.id;
  @override
  List<String> libMouthsOf(String fnId) => [
    for (final d in library?.blocks ?? const <BeLibDef>[])
      if (d.fn == fnId) ...d.mouths,
  ];
  @override
  Iterable<List<LcBlock>> get libBodies => [for (final r in routes) r.body, for (final f in functions) f.body, for (final t in core.trees) t.body, for (final h in hats) h.body];
  @override
  Iterable<String> get libHatOps => [for (final h in hats) h.op];

  LibLibrary? lib(String id) => loaded.where((l) => l.id == id).firstOrNull;
  BeLibUse? use(String id) => uses.where((u) => u.id == id).firstOrNull;
  BeLibHat? hat(String id) => hats.where((h) => h.id == id).firstOrNull;

  /// 有没有用到“用户自己写库”才有的东西。用到了版本号写 5。
  bool get usesLibs => library != null || uses.isNotEmpty || hats.isNotEmpty || serviceLib.isNotEmpty;

  /// 规矩版本（见 lang/rules.dart）：1＝老规矩（旧文档，行为不变）；2＝严格规矩。是 1 时存盘不写这个字段。
  int rules;

  static bool _validPort(int p) => p >= 1 && p <= 65535;

  /// 有没有用到第 4 版才有的积木（见 backend_blocks_lang.dart 的 `beBlocksUseLang`）。用到了存盘时版本号写 2，否则还是 1
  /// ——旧文档不改、或只用旧积木改，存出来和以前一个字节都不差。
  bool get usesLang => routes.any((r) => beBlocksUseLang(r.body));

  /// 有没有用到第 2 阶段才有的东西（函数、调用、匿名函数、拿函数当参数的列表操作）。用到了版本号写 3。
  bool get usesFunctions => functions.isNotEmpty || routes.any((r) => beBlocksUseFunc(r.body));

  Map<String, dynamic> toJson() => {
    'version': usesLibs
        ? 5
        : usesCore
        ? 4
        : (usesFunctions ? 3 : (usesLang ? 2 : 1)),
    'kind': 'backend',
    if (front) 'side': 'frontend',
    if (rules != kLangRulesLoose) kLangRulesField: rules,
    'name': name,
    'port': port,
    'language': language,
    'variables': [for (final v in variables) v.toJson()],
    'collections': [for (final c in collections) c.toJson()],
    'routes': [for (final r in routes) r.toJson()],
    if (functions.isNotEmpty) 'functions': [for (final f in functions) f.toJson()],
    if (!core.isEmpty) 'core': core.toJson(),
    if (library != null) 'library': library!.toJson(),
    if (uses.isNotEmpty) 'uses': [for (final u in uses) u.toJson()],
    if (serviceLib.isNotEmpty) 'serviceLib': serviceLib,
    if (hats.isNotEmpty) 'hats': [for (final h in hats) h.toJson()],
  };

  /// 存盘用的文字（带缩进，方便人看和版本对比）。
  String encode() => const JsonEncoder.withIndent('  ').convert(toJson());

  BeDocument clone() => BeDocument(
    name: name,
    port: port,
    language: language,
    variables: [for (final v in variables) LcVariable(name: v.name, type: v.type, initial: v.initial)],
    collections: [for (final c in collections) BeCollection(name: c.name)],
    routes: [for (final r in routes) r.clone()],
    functions: [for (final f in functions) f.clone()],
    core: core.clone(),
    rules: rules,
    library: library?.clone(),
    uses: [for (final u in uses) u.clone()],
    serviceLib: serviceLib,
    hats: [for (final h in hats) h.clone()],
    loaded: _loaded,
    front: front,
  );

  /// 从文件内容读。读不懂（不是 JSON、不是对象、不是后端文档）→ 空白文档 + 说明；坏的条目逐条跳过并在说明里报数。绝不抛异常。
  static BeParseResult parse(String source) {
    Object? json;
    try {
      json = jsonDecode(source);
    } on FormatException catch (e) {
      return (doc: BeDocument(), note: '后端文件读不懂（${e.message}），先按空白的打开');
    }
    return fromJson(json);
  }

  /// 从解好的 JSON 读（规矩同 [parse]）。
  static BeParseResult fromJson(Object? json) {
    if (json is! Map) return (doc: BeDocument(), note: '后端文件的内容不是预期的格式，先按空白的打开');
    final kind = json['kind'];
    if (kind != null && kind != 'backend') return (doc: BeDocument(), note: '这个文件不是后端积木文件，先按空白的打开');
    var skipped = 0;
    List<T> list<T>(Object? raw, T? Function(Object? item) one) {
      if (raw is! List) return [];
      final out = <T>[];
      for (final item in raw) {
        final parsed = one(item);
        parsed == null ? skipped++ : out.add(parsed);
      }
      return out;
    }

    final name = json['name'];
    final port = json['port'];
    final language = json['language'];
    final doc = BeDocument(
      name: name is String && name.trim().isNotEmpty ? name : '我的后端',
      port: port is int ? port : kBeDefaultPort,
      language: language is String ? language : kBeDefaultLanguage,
      variables: list(json['variables'], LcVariable.tryParse),
      collections: list(json['collections'], BeCollection.tryParse),
      routes: list(json['routes'], BeRoute.tryParse),
      functions: list(json['functions'], BeFunction.tryParse),
      core: BeCore.fromJson(json['core'], beNamePattern),
      rules: langRulesFromJson(json[kLangRulesField]),
      library: BeLibInfo.tryParse(json['library']),
      uses: list(json['uses'], BeLibUse.tryParse),
      serviceLib: json['serviceLib'] is String && kLibIdPattern.hasMatch(json['serviceLib'] as String) ? json['serviceLib'] as String : '',
      hats: list(json['hats'], BeLibHat.tryParse),
      front: json['side'] == 'frontend',
    );
    return (doc: doc, note: skipped == 0 ? null : '后端文件里有 $skipped 条读不懂的内容，已跳过');
  }

  /// 变量、集合重名只留第一个；接口的 id 缺了 / 不合规矩 / 重了就补一个 `r数字`。
  /// 函数最多留 [kBeMaxFunctions] 个（多出来的丢掉）。
  /// 函数的 id 先占位（调用是按它认的，不能动）：缺了 / 不合规矩 / 重了才补一个 `f数字`；接口的 id 和函数撞了，换的是接口的。
  void _normalize() {
    syncSide();
    final names = <String>{};
    variables.removeWhere((v) => !names.add(v.name));
    final cols = <String>{};
    collections.removeWhere((c) => !cols.add(c.name));
    if (functions.length > kBeMaxFunctions) functions.removeRange(kBeMaxFunctions, functions.length);
    final ids = <String>{};
    for (final f in functions) {
      if (BeFunction.validId(f.id)) ids.add(f.id);
    }
    final taken = <String>{};
    for (final f in functions) {
      if (!BeFunction.validId(f.id) || !taken.add(f.id)) {
        f.id = beFreeFunctionId({...ids, ...taken, for (final r in routes) r.id});
        ids.add(f.id);
        taken.add(f.id);
      }
    }
    for (final r in routes) {
      if (!_idPattern.hasMatch(r.id) || !ids.add(r.id)) {
        r.id = _freeRouteId(ids);
        ids.add(r.id);
      }
    }
    core.normalize(ids);
    final libIds = <String>{};
    uses.removeWhere((u) => !libIds.add(u.id));
    if (uses.length > kBeMaxLibUses) uses.removeRange(kBeMaxLibUses, uses.length);
    if (hats.length > kBeMaxLibHats) hats.removeRange(kBeMaxLibHats, hats.length);
    final all = {
      ...ids,
      kBeMainId,
      for (final t in core.types) ...[t.id, for (final m in t.trees) m.id],
    };
    for (final h in hats) {
      if (!_idPattern.hasMatch(h.id) || !all.add(h.id)) {
        var n = 1;
        while (all.contains('h$n')) {
          n++;
        }
        all.add(h.id = 'h$n');
      }
    }
  }

  static String _freeRouteId(Set<String> used) {
    var n = 1;
    while (used.contains('r$n')) {
      n++;
    }
    return 'r$n';
  }

  // —— 查 ——

  LcVariable? variable(String name) {
    for (final v in variables) {
      if (v.name == name) return v;
    }
    return null;
  }

  BeCollection? collection(String name) {
    for (final c in collections) {
      if (c.name == name) return c;
    }
    return null;
  }

  BeRoute? route(String id) {
    for (final r in routes) {
      if (r.id == id) return r;
    }
    return null;
  }

  BeFunction? function(String id) {
    for (final f in functions) {
      if (f.id == id) return f;
    }
    return null;
  }

  // —— 最基本的增删（连带改引用的操作在 backend_edit.dart）——

  /// 新建一个接口加到最后；id 自动取没用过的 `r数字`。请求方式不认识返回 null（路径格式不在这里拦，校验会报）。
  BeRoute? addRoute(String method, String path, {double? x, double? y}) {
    final upper = method.toUpperCase();
    if (!kBeMethods.contains(upper)) return null;
    final r = BeRoute(id: _freeRouteId({for (final r in routes) r.id, for (final f in functions) f.id}), method: upper, path: path, x: x, y: y);
    routes.add(r);
    return r;
  }

  bool removeRoute(String id) {
    final before = routes.length;
    routes.removeWhere((r) => r.id == id);
    return routes.length != before;
  }

  /// 加一个变量；名字不合规矩、重名、类型不认识返回 null。
  LcVariable? addVariable(String name, {String type = 'text', Object? initial}) {
    if (!beNamePattern.hasMatch(name) || variable(name) != null || !LcVariable.types.contains(type)) return null;
    final v = LcVariable(name: name, type: type, initial: initial);
    variables.add(v);
    return v;
  }

  /// 加一个集合；名字不合规矩或重名返回 null。
  BeCollection? addCollection(String name) {
    if (!beNamePattern.hasMatch(name) || collection(name) != null) return null;
    final c = BeCollection(name: name);
    collections.add(c);
    return c;
  }
}

/// 从工程目录读 `backend.lc.json`。文件不存在 → null；坏了 → 原件另存 `.bad-时间戳`、返回空白文档 + 说明（不抛异常）。
Future<BeParseResult?> loadBackendFile(File file) async {
  bool exists;
  try {
    exists = await file.exists();
  } on FileSystemException {
    exists = false; // 连看都看不了（权限等）：当成没有
  }
  if (!exists) return null;
  final json = await readJsonFile(file, accept: (d) => d is Map && (d['kind'] == null || d['kind'] == 'backend'), label: '后端积木文件');
  if (json == null) return (doc: BeDocument(), note: '后端文件读不懂或是空的，先按空白的打开（原文件如果有内容已另存一份备份）');
  return BeDocument.fromJson(json);
}

/// 写 `backend.lc.json`（原子写：先写临时文件再改名）。
Future<void> saveBackendFile(File file, BeDocument doc) => writeStringAtomic(file, '${doc.encode()}\n');
