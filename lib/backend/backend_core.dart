/// 后端积木文档里“语言核心 2”的那一部分（积木第 5 版·核心 2·A3）：自己定义的类型（记录、枚举、变体、错误种类、类、接口）、
/// 模块顶上的变量、模块、“程序开始时”。只有规矩版本 2 的文档才有；一样都没有时存盘不写 `core` 这个键——旧文档读写一个字节不差。
///
/// 存盘格式写在 docs/blocks-v5-parts/B-impl-notes.md“A3：积木文档里怎么存”一节。读的时候取字段先判类型，坏的条目跳过，绝不抛异常。
library;

import 'package:lopicode/backend/backend_function.dart';
import 'package:lopicode/lang/errors.dart';
import 'package:lopicode/lang/types.dart';
import 'package:lopicode/lang/types_json.dart';
import 'package:lopicode/lowcode/logic_expr.dart';
import 'package:lopicode/lowcode/logic_model.dart';

/// 类型、字段、情况、方法的名字：汉字、英文字母、数字、下划线，不用数字开头，最长 32 个字。
final RegExp beCoreNamePattern = RegExp(r'^[A-Za-z_\u4e00-\u9fff][A-Za-z0-9_\u4e00-\u9fff]{0,31}$');

/// 一份文档最多几个类型、一个类型最多几个字段 / 情况 / 方法、最多几个模块。**按建议先做，可改。**
const int kBeMaxTypes = 64;
const int kBeMaxMembers = 32;
const int kBeMaxModules = 16;

/// “程序开始时”那一串的 id（固定）。
const String kBeMainId = 'main';

enum BeTypeKind {
  record('record', '记录'),
  enumeration('enum', '枚举'),
  variant('variant', '变体'),
  error('error', '错误种类'),
  klass('class', '类'),
  interface('interface', '接口');

  const BeTypeKind(this.tag, this.label);
  final String tag;
  final String label;
}

/// 一个字段：记录的、变体某种情况带的、错误种类多带的、类的。
class BeField {
  BeField(this.name, this.type, {this.isPrivate = false, this.isStatic = false, this.init});
  String name;
  LType type;

  /// 类的字段才有意义：只有类自己和子类里面能用。
  bool isPrivate;

  /// 类的字段才有意义：是“类本身的”，不是每个对象各一份。
  bool isStatic;

  /// 类的字段的初始值（一个值积木的 JSON）；null＝按类型给默认的（0、空文字、否、空）。
  Object? init;

  Map<String, dynamic> toJson() => {'name': name, 'type': lTypeToJson(type), if (isPrivate) 'private': true, if (isStatic) 'static': true, 'init': ?init};

  BeField clone() => BeField(name, type, isPrivate: isPrivate, isStatic: isStatic, init: deepCopyJson(init));

  static BeField? tryParse(Object? json) {
    if (json is! Map) return null;
    final name = json['name'];
    if (name is! String || !beCoreNamePattern.hasMatch(name)) return null;
    final init = json['init'];
    return BeField(name, lTypeFromJson(json['type']), isPrivate: json['private'] == true, isStatic: json['static'] == true, init: init is Map ? deepCopyJson(init) : null);
  }
}

/// 枚举 / 变体的一种情况（枚举的没有带的东西）。
class BeCase {
  BeCase(this.name, [List<BeField>? fields]) : fields = fields ?? [];
  String name;
  final List<BeField> fields;

  Map<String, dynamic> toJson() => {
    'name': name,
    if (fields.isNotEmpty) 'fields': [for (final f in fields) f.toJson()],
  };

  BeCase clone() => BeCase(name, [for (final f in fields) f.clone()]);

  static BeCase? tryParse(Object? json) {
    if (json is! Map) return null;
    final name = json['name'];
    if (name is! String || !beCoreNamePattern.hasMatch(name)) return null;
    return BeCase(name, _list(json['fields'], BeField.tryParse));
  }
}

List<T> _list<T>(Object? raw, T? Function(Object? item) one, [int max = kBeMaxMembers]) {
  final out = <T>[];
  if (raw is List) {
    for (final item in raw) {
      final parsed = one(item);
      if (parsed != null && out.length < max) out.add(parsed);
    }
  }
  return out;
}

List<String> _names(Object? raw) => [
  if (raw is List)
    for (final n in raw)
      if (n is String && n.isNotEmpty) n,
];

/// 类的一个方法、“创建时”、接口里的一条签名（接口的没有积木）、“程序开始时”：一串积木，带名字和参数。
class BeMethod with LcBlockTree {
  BeMethod({required this.id, required this.name, List<BeParam>? params, this.returns, this.isStatic = false, List<LcBlock>? body, double? x, double? y}) : params = params ?? [], body = body ?? [] {
    this.x = x;
    this.y = y;
  }

  @override
  String id;
  String name;
  final List<BeParam> params;

  /// 标的“交回什么”；null＝没标（自己推）。
  LType? returns;

  /// “类本身的”方法。
  bool isStatic;
  @override
  final List<LcBlock> body;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    if (params.isNotEmpty) 'params': [for (final p in params) p.toJson()],
    if (returns != null) 'returns': lTypeToJson(returns!),
    if (isStatic) 'static': true,
    if (x != null) 'x': x,
    if (y != null) 'y': y,
    if (body.isNotEmpty) 'body': [for (final b in body) b.toJson()],
  };

  BeMethod clone() => BeMethod(id: id, name: name, params: [for (final p in params) p.clone()], returns: returns, isStatic: isStatic, body: [for (final b in body) b.clone()], x: x, y: y);

  static BeMethod? tryParse(Object? json) {
    if (json is! Map) return null;
    final name = json['name'];
    if (name is! String || !beCoreNamePattern.hasMatch(name)) return null;
    final id = json['id'], x = json['x'], y = json['y'];
    return BeMethod(
      id: id is String ? id : '',
      name: name,
      params: _list(json['params'], BeParam.tryParse, kBeMaxParams),
      returns: json['returns'] is Map ? lTypeFromJson(json['returns']) : null,
      isStatic: json['static'] == true,
      body: LcBlock.parseList(json['body'], 0),
      x: x is num && x.isFinite ? x.toDouble() : null,
      y: y is num && y.isFinite ? y.toDouble() : null,
    );
  }
}

/// “创建时”在类里固定叫这个名字。
const String kBeCtorName = '创建时';

/// 一个自己定义的类型。
class BeTypeDef {
  BeTypeDef({
    required this.id,
    required this.kind,
    required this.name,
    List<BeField>? fields,
    List<BeCase>? cases,
    this.parent,
    List<String>? interfaces,
    this.isOpen = false,
    this.ctor,
    List<BeMethod>? methods,
  }) : fields = fields ?? [],
       cases = cases ?? [],
       interfaces = interfaces ?? [],
       methods = methods ?? [];

  String id;
  final BeTypeKind kind;
  String name;

  /// 记录、错误种类、类的字段。
  final List<BeField> fields;

  /// 枚举、变体的情况。
  final List<BeCase> cases;

  /// 类：父类的名字；错误种类：继承哪一种错误（null＝“错误”）。
  String? parent;

  /// 类：实现了哪些接口（名字）。
  final List<String> interfaces;

  /// 类、错误种类：可以被继承。
  bool isOpen;

  /// 类的“创建时”（null＝没有）。
  BeMethod? ctor;

  /// 类的方法；接口的签名（没有积木）。
  final List<BeMethod> methods;

  bool get isClassLike => kind == BeTypeKind.klass || kind == BeTypeKind.error;

  /// 这个类型里的每一串积木（“创建时”、各个方法）。
  List<BeMethod> get trees => kind == BeTypeKind.klass ? [?ctor, ...methods] : const [];

  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind.tag,
    'name': name,
    if (fields.isNotEmpty) 'fields': [for (final f in fields) f.toJson()],
    if (cases.isNotEmpty) 'cases': [for (final c in cases) c.toJson()],
    'parent': ?parent,
    if (interfaces.isNotEmpty) 'interfaces': interfaces,
    if (isOpen) 'open': true,
    if (ctor != null) 'ctor': ctor!.toJson(),
    if (methods.isNotEmpty) 'methods': [for (final m in methods) m.toJson()],
  };

  BeTypeDef clone() => BeTypeDef(
    id: id,
    kind: kind,
    name: name,
    fields: [for (final f in fields) f.clone()],
    cases: [for (final c in cases) c.clone()],
    parent: parent,
    interfaces: [...interfaces],
    isOpen: isOpen,
    ctor: ctor?.clone(),
    methods: [for (final m in methods) m.clone()],
  );

  static BeTypeDef? tryParse(Object? json) {
    if (json is! Map) return null;
    final name = json['name'];
    final kind = BeTypeKind.values.where((k) => k.tag == json['kind']).firstOrNull;
    if (kind == null || name is! String || !beCoreNamePattern.hasMatch(name)) return null;
    final id = json['id'], parent = json['parent'];
    return BeTypeDef(
      id: id is String ? id : '',
      kind: kind,
      name: name,
      fields: _list(json['fields'], BeField.tryParse),
      cases: _list(json['cases'], BeCase.tryParse),
      parent: parent is String && parent.isNotEmpty ? parent : null,
      interfaces: _names(json['interfaces']),
      isOpen: json['open'] == true,
      ctor: BeMethod.tryParse(json['ctor']),
      methods: _list(json['methods'], BeMethod.tryParse),
    );
  }
}

/// 模块顶上的变量：程序开始时按写的先后赋初值。
class BeGlobal {
  BeGlobal(this.name, this.init, {this.isConst = false, this.type});
  String name;

  /// 初始值（一个值积木的 JSON）。
  Object? init;
  bool isConst;
  LType? type;

  /// 在“谁归哪个模块”“公开”的表里它叫什么。
  String get key => 'g:$name';

  Map<String, dynamic> toJson() => {'name': name, 'init': ?init, if (isConst) 'const': true, if (type != null) 'type': lTypeToJson(type!)};

  BeGlobal clone() => BeGlobal(name, deepCopyJson(init), isConst: isConst, type: type);

  static BeGlobal? tryParse(Object? json, RegExp namePattern) {
    if (json is! Map) return null;
    final name = json['name'];
    if (name is! String || !namePattern.hasMatch(name)) return null;
    final init = json['init'];
    return BeGlobal(name, init is Map ? deepCopyJson(init) : null, isConst: json['const'] == true, type: json['type'] is Map ? lTypeFromJson(json['type']) : null);
  }
}

/// 一个模块：名字、用到了谁、哪些东西归它（类型 id、“我的积木”id、`g:变量名`）。没归到哪个模块的东西算入口模块的。
class BeModule {
  BeModule(this.name, {List<String>? uses, Set<String>? owns}) : uses = uses ?? [], owns = owns ?? {};
  String name;
  final List<String> uses;
  final Set<String> owns;

  Map<String, dynamic> toJson() => {'name': name, if (uses.isNotEmpty) 'uses': uses, if (owns.isNotEmpty) 'owns': owns.toList()};

  BeModule clone() => BeModule(name, uses: [...uses], owns: {...owns});

  static BeModule? tryParse(Object? json) {
    if (json is! Map) return null;
    final name = json['name'];
    if (name is! String || name.trim().isEmpty || name.length > 32) return null;
    return BeModule(name, uses: _names(json['uses']), owns: _names(json['owns']).toSet());
  }
}

/// 文档里核心 2 的全部内容。
class BeCore {
  BeCore({List<BeTypeDef>? types, List<BeGlobal>? globals, List<BeModule>? modules, this.entry, Set<String>? publics, this.main})
    : types = types ?? [],
      globals = globals ?? [],
      modules = modules ?? [],
      publics = publics ?? {};

  final List<BeTypeDef> types;
  final List<BeGlobal> globals;

  /// 空＝整个文档就是一个模块。
  final List<BeModule> modules;

  /// 入口模块的名字（有模块时才有意义；null / 对不上＝第一个）。
  String? entry;

  /// 勾了“公开”的东西（类型 id、“我的积木”id、`g:变量名`）。
  final Set<String> publics;

  /// “程序开始时”（null＝没有）。
  BeMethod? main;

  bool get isEmpty => types.isEmpty && globals.isEmpty && modules.isEmpty && publics.isEmpty && main == null;

  Map<String, dynamic> toJson() => {
    if (types.isNotEmpty) 'types': [for (final t in types) t.toJson()],
    if (globals.isNotEmpty) 'globals': [for (final g in globals) g.toJson()],
    if (modules.isNotEmpty) 'modules': [for (final m in modules) m.toJson()],
    if (modules.isNotEmpty && entry != null) 'entry': entry,
    if (publics.isNotEmpty) 'public': publics.toList(),
    if (main != null)
      'main': {
        if (main!.x != null) 'x': main!.x,
        if (main!.y != null) 'y': main!.y,
        'body': [for (final b in main!.body) b.toJson()],
      },
  };

  BeCore clone() => BeCore(
    types: [for (final t in types) t.clone()],
    globals: [for (final g in globals) g.clone()],
    modules: [for (final m in modules) m.clone()],
    entry: entry,
    publics: {...publics},
    main: main?.clone(),
  );

  static BeCore fromJson(Object? json, RegExp varPattern) {
    if (json is! Map) return BeCore();
    final entry = json['entry'], main = json['main'];
    final x = main is Map ? main['x'] : null, y = main is Map ? main['y'] : null;
    return BeCore(
      types: _list(json['types'], BeTypeDef.tryParse, kBeMaxTypes),
      globals: _list(json['globals'], (g) => BeGlobal.tryParse(g, varPattern), kBeMaxTypes),
      modules: _list(json['modules'], BeModule.tryParse, kBeMaxModules),
      entry: entry is String && entry.isNotEmpty ? entry : null,
      publics: _names(json['public']).toSet(),
      main: main is Map
          ? BeMethod(id: kBeMainId, name: '程序开始时', body: LcBlock.parseList(main['body'], 0), x: x is num && x.isFinite ? x.toDouble() : null, y: y is num && y.isFinite ? y.toDouble() : null)
          : null,
    );
  }

  // —— 查 ——

  BeTypeDef? type(String id) => types.where((t) => t.id == id).firstOrNull;
  BeTypeDef? typeNamed(Object? name) => name is String ? types.where((t) => t.name == name).firstOrNull : null;
  BeGlobal? global(String name) => globals.where((g) => g.name == name).firstOrNull;
  BeModule? module(String name) => modules.where((m) => m.name == name).firstOrNull;

  /// 每一串积木：各个类的“创建时”和方法，加上“程序开始时”。
  List<BeMethod> get trees => [for (final t in types) ...t.trees, ?main];

  BeMethod? tree(String id) => trees.where((m) => m.id == id).firstOrNull;

  /// 这一串是哪个类的（不是类里的返回 null）。
  /// 这一串在问题列表里叫什么。
  String labelOf(BeMethod tree) {
    if (tree.id == kBeMainId) return '程序开始时';
    final owner = ownerOf(tree.id);
    return '类「${owner?.name ?? ''}」的${identical(owner?.ctor, tree) ? '“创建时”' : '方法「${tree.name}」'}';
  }

  BeTypeDef? ownerOf(String treeId) => types.where((t) => t.trees.any((m) => m.id == treeId)).firstOrNull;

  /// 入口模块（没有模块＝null）。
  BeModule? get entryModule => modules.isEmpty ? null : (modules.where((m) => m.name == entry).firstOrNull ?? modules.first);

  /// 这个东西归哪个模块（没有模块＝null）。
  BeModule? moduleOf(String key) => modules.isEmpty ? null : (modules.where((m) => m.owns.contains(key)).firstOrNull ?? entryModule);

  /// 错误的种类能选哪些：内置的，加上自己定义的错误种类、父类是错误的类。
  List<String> get errorKinds => [
    ...kErrBuiltinNames,
    for (final t in types)
      if (isError(t)) t.name,
  ];

  /// 这个类型是不是一种错误（顺着父类往上找到了内置的错误）。
  bool isError(BeTypeDef t) {
    if (t.kind == BeTypeKind.error) return true;
    if (t.kind != BeTypeKind.klass) return false;
    final seen = <String>{};
    String? p = t.parent;
    while (p != null && seen.add(p)) {
      if (langIsBuiltinError(p)) return true;
      final up = typeNamed(p);
      if (up == null) return false;
      if (up.kind == BeTypeKind.error) return true;
      p = up.parent;
    }
    return false;
  }

  /// 顺着父类往上的每一个类型（不含自己；绕圈了就停）。
  List<BeTypeDef> parentsOf(BeTypeDef t) {
    final out = <BeTypeDef>[];
    final seen = {t.name};
    var p = typeNamed(t.parent);
    while (p != null && seen.add(p.name)) {
      out.add(p);
      p = typeNamed(p.parent);
    }
    return out;
  }

  /// 补 id：类型 `t数字`、方法 `m数字`；缺了 / 重了 / 和 [taken]（接口、函数的 id）撞了就换。重名的类型、变量、模块只留第一个。
  void normalize(Set<String> taken) {
    final names = <String>{};
    types.removeWhere((t) => !names.add(t.name));
    final gs = <String>{};
    globals.removeWhere((g) => !gs.add(g.name));
    final ms = <String>{};
    modules.removeWhere((m) => !ms.add(m.name));
    final used = {...taken, kBeMainId};
    String free(String prefix) {
      var n = 1;
      while (used.contains('$prefix$n')) {
        n++;
      }
      return '$prefix$n';
    }

    final ok = RegExp(r'^[A-Za-z0-9_]{1,32}$');
    for (final t in types) {
      if (!ok.hasMatch(t.id) || !used.add(t.id)) used.add(t.id = free('t'));
      for (final m in [?t.ctor, ...t.methods]) {
        if (!ok.hasMatch(m.id) || !used.add(m.id)) used.add(m.id = free('m'));
      }
    }
    main?.id = kBeMainId;
  }

  /// 没用过的 id（给新类型 `t`、新方法 `m`）。
  String freeId(String prefix, Set<String> taken) {
    final used = {
      ...taken,
      for (final t in types) ...[t.id, ?t.ctor?.id, for (final m in t.methods) m.id],
    };
    var n = 1;
    while (used.contains('$prefix$n')) {
      n++;
    }
    return '$prefix$n';
  }
}
