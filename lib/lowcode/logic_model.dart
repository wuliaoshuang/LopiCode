/// 低代码页面的“逻辑”数据模型：页面变量 + 事件处理（每个处理是一串积木）。
///
/// 这里只管数据的形状和读写（读的时候容错：旧文件、坏字段都不许让页面打不开）。
/// 有哪些积木、每块要什么参数、怎么翻成 JavaScript，在 `logic_blocks.dart` / `logic_js.dart`。
/// JSON 结构的完整约定见 docs/lowcode-v2-design.md。
library;

import 'package:lopicode/lowcode/logic_variable.dart';

export 'package:lopicode/lowcode/logic_variable.dart';

/// 多口积木里的一段（“否则如果 <条件> 那么 { … }”“是 (1) 时 { … }”“出错了 { … }”）：自己的参数 + 自己那个口里的积木。
/// 一种积木有没有段、每段带哪些参数，由它的规格（`LcBlockSpec.arms`）说；这里只管存。
class LcArm {
  LcArm({Map<String, dynamic>? args, List<LcBlock>? body}) : args = args ?? {}, body = body ?? [];

  final Map<String, dynamic> args;
  final List<LcBlock> body;

  Map<String, dynamic> toJson() => {
    if (args.isNotEmpty) 'args': args,
    if (body.isNotEmpty) 'body': [for (final b in body) b.toJson()],
  };

  LcArm clone() {
    final copied = LcBlock._copyJson(args, 0);
    return LcArm(args: copied is Map<String, dynamic> ? copied : {}, body: [for (final b in body) b.clone()]);
  }

  /// 不是对象就返回 null（调用方跳过这一段）。
  static LcArm? tryParse(Object? json, int depth) {
    if (json is! Map) return null;
    final args = json['args'];
    return LcArm(args: args is Map ? {for (final e in args.entries) '${e.key}': LcBlock._hydrate(e.value, depth, 0)} : {}, body: LcBlock.parseList(json['body'], depth));
  }
}

/// 段里的参数在编辑器里怎么称呼：`@<第几段>:<参数名>`（积木自己的参数直接用参数名）。
/// 槽位、校验问题、落点都用这个名字指到“第几段的哪个参数”。
String lcArmArg(int arm, String name) => '@$arm:$name';

/// 把 [lcArmArg] 拆回来；不是段参数返回 null。
({int arm, String name})? lcArmArgOf(String key) {
  if (!key.startsWith('@')) return null;
  final colon = key.indexOf(':');
  if (colon < 2) return null;
  final arm = int.tryParse(key.substring(1, colon));
  return arm == null || arm < 0 ? null : (arm: arm, name: key.substring(colon + 1));
}

/// 一块积木。`op` 是积木种类；`args` 是参数（字面量或表达式对象 `{"e": ...}`）；
/// `body` / `orElse` 是嵌在里面的积木（“如果”“重复”这类才有）。
///
/// 多口积木（“否则如果”“分情况”“试着做”）在 `body` 和 `orElse` 之间还有任意多段 [arms]：
/// `body`＝开头那个口，`arms`＝中间可增减的段（每段自带参数），`orElse`＝收尾那个口。
/// [noElse]＝用户把可有可无的收尾口（“否则”）收起来了。两样都只在用到时才写进 JSON，旧文档一个字节都不变。
class LcBlock {
  LcBlock({required this.op, Map<String, dynamic>? args, List<LcBlock>? body, List<LcBlock>? orElse, List<LcArm>? arms, this.noElse = false})
    : args = args ?? {},
      body = body ?? [],
      orElse = orElse ?? [],
      arms = arms ?? [];

  final String op;
  final Map<String, dynamic> args;
  final List<LcBlock> body;
  final List<LcBlock> orElse;
  final List<LcArm> arms;
  bool noElse;

  static const int maxDepth = 12;

  /// 一块积木最多几段（读文件时多出来的丢掉；编辑器里加到这么多就不让加了）。
  static const int maxArms = 32;

  Map<String, dynamic> toJson() => {
    'op': op,
    if (args.isNotEmpty) 'args': args,
    if (body.isNotEmpty) 'body': [for (final b in body) b.toJson()],
    if (arms.isNotEmpty) 'arms': [for (final a in arms) a.toJson()],
    if (orElse.isNotEmpty) 'else': [for (final b in orElse) b.toJson()],
    if (noElse) 'noElse': true,
  };

  /// 深拷贝：参数、嵌在里面的积木全都是新对象，改副本不影响原件。
  LcBlock clone() {
    final copied = _copyJson(args, 0);
    return LcBlock(
      op: op,
      args: copied is Map<String, dynamic> ? copied : {},
      body: [for (final b in body) b.clone()],
      orElse: [for (final b in orElse) b.clone()],
      arms: [for (final a in arms) a.clone()],
      noElse: noElse,
    );
  }

  /// 浅拷贝后换掉其中几样（编辑器重建一块积木时用，免得漏抄字段）。
  LcBlock copyWith({Map<String, dynamic>? args, List<LcBlock>? body, List<LcBlock>? orElse, List<LcArm>? arms}) =>
      LcBlock(op: op, args: args ?? this.args, body: body ?? this.body, orElse: orElse ?? this.orElse, arms: arms ?? this.arms, noElse: noElse);

  /// 嵌在这块积木里的全部积木（开头口、各段、收尾口，按画出来的顺序；再加上参数里“带口的值”里的）。
  Iterable<LcBlock> get children {
    final inExprs = exprMouths;
    if (arms.isEmpty && inExprs.isEmpty) return body.followedBy(orElse);
    return [...body, for (final a in arms) ...a.body, ...orElse, for (final m in inExprs) ...m];
  }

  /// 某个口里的那串积木：`arm >= 0` 是第几段；`arm <= -2` 是参数里第几个“带口的值”（见 [lcExprMouthArm]）；
  /// 否则 `inElse` 是收尾口，不然是开头口。段 / 值不存在返回 null。
  List<LcBlock>? mouth({bool inElse = false, int arm = -1}) {
    if (arm >= 0) return arm < arms.length ? arms[arm].body : null;
    if (arm <= -2) {
      final all = exprMouths;
      final k = lcExprMouthIndex(arm);
      return k < all.length ? all[k] : null;
    }
    return inElse ? orElse : body;
  }

  /// 这块积木的参数里（含各段的参数）所有“带口的值”的口，按固定的先后（参数表的先后，从外到里）。
  /// 只算直接属于这块的：口里的积木自己参数里的不算（那是它们自己的）。
  List<List<LcBlock>> get exprMouths {
    final out = <List<LcBlock>>[];
    _findMouths(args, out, 0);
    for (final a in arms) {
      _findMouths(a.args, out, 0);
    }
    return out;
  }

  static void _findMouths(Object? v, List<List<LcBlock>> out, int depth) {
    if (depth > 64 || v is List<LcBlock>) return;
    if (v is Map) {
      final body = v[kLcExprBody];
      if (body is List<LcBlock>) out.add(body);
      for (final x in v.values) {
        _findMouths(x, out, depth + 1);
      }
    } else if (v is List) {
      for (final x in v) {
        _findMouths(x, out, depth + 1);
      }
    }
  }

  /// 浅拷贝，把第 `k` 个“带口的值”的口换成 `child`（参数表沿路是新对象，别的口和原来共用）。预览用。
  LcBlock withExprMouth(int k, List<LcBlock> child) {
    var n = 0;
    Object? copy(Object? v, int depth) {
      if (depth > 64 || v is List<LcBlock>) return v;
      if (v is Map) {
        final out = <String, dynamic>{};
        for (final e in v.entries) {
          if (e.key == kLcExprBody && e.value is List<LcBlock>) {
            out[kLcExprBody] = n++ == k ? child : e.value;
          } else {
            out['${e.key}'] = e.value;
          }
        }
        // 口先数完（和 [_findMouths] 一个顺序），再往里走。
        for (final key in out.keys.toList()) {
          if (key != kLcExprBody) out[key] = copy(out[key], depth + 1);
        }
        return out;
      }
      if (v is List) return <dynamic>[for (final x in v) copy(x, depth + 1)];
      return v;
    }

    final newArgs = copy(args, 0)! as Map<String, dynamic>;
    return copyWith(
      args: newArgs,
      arms: arms.isEmpty ? null : [for (final a in arms) LcArm(args: copy(a.args, 0)! as Map<String, dynamic>, body: a.body)],
    );
  }

  /// 按编辑器里的参数名（见 [lcArmArg]）找到装这个参数的那张表和表里的名字；段不存在返回 null。
  ({Map<String, dynamic> map, String name})? argHome(String key) {
    final a = lcArmArgOf(key);
    if (a == null) return (map: args, name: key);
    return a.arm < arms.length ? (map: arms[a.arm].args, name: a.name) : null;
  }

  /// 按编辑器里的参数名读 / 写参数（段参数也行）。
  Object? argValue(String key) {
    final home = argHome(key);
    return home?.map[home.name];
  }

  bool setArgValue(String key, Object? value) {
    final home = argHome(key);
    if (home == null) return false;
    home.map[home.name] = value;
    return true;
  }

  /// 这块积木往下（含自己）一共有几层。
  int get height {
    var h = 0;
    for (final b in children) {
      final bh = b.height;
      if (bh > h) h = bh;
    }
    return h + 1;
  }

  /// 参数里是 JSON 值（字面量 / Map / List）；超过 64 层的截掉（正常数据到不了，防自己套自己的坏数据）。
  static Object? _copyJson(Object? v, int depth) {
    if (depth > 64) return null;
    // “带口的值”里的那串积木：不是 JSON，照积木的办法深拷贝。
    if (v is List<LcBlock>) return <LcBlock>[for (final b in v) b.clone()];
    if (v is Map) return <String, dynamic>{for (final e in v.entries) '${e.key}': _copyJson(e.value, depth + 1)};
    if (v is List) return <dynamic>[for (final item in v) _copyJson(item, depth + 1)];
    return v is String || v is num || v is bool ? v : null;
  }

  static LcBlock? tryParse(Object? json, int depth) {
    if (json is! Map || depth > maxDepth) return null;
    final op = json['op'];
    if (op is! String || op.isEmpty) return null;
    final args = json['args'];
    final arms = json['arms'];
    return LcBlock(
      op: op,
      args: args is Map ? {for (final e in args.entries) '${e.key}': _hydrate(e.value, depth, 0)} : {},
      body: parseList(json['body'], depth + 1),
      orElse: parseList(json['else'], depth + 1),
      arms: arms is List ? [for (final a in arms.take(maxArms)) ?LcArm.tryParse(a, depth + 1)] : null,
      noElse: json['noElse'] == true,
    );
  }

  static List<LcBlock> parseList(Object? json, int depth) {
    if (json is! List) return [];
    return [for (final item in json) ?tryParse(item, depth)];
  }

  /// 读参数时把“带口的值”（表达式对象里的 [kLcExprBody]）里的那串积木读成真的积木。
  /// 没有这种值的参数原样返回（同一个对象，一个字不动）：旧文档读进来、存出去和以前完全一样。
  static Object? _hydrate(Object? v, int depth, int guard) {
    if (guard > 64 || v is List<LcBlock>) return v;
    if (v is List) {
      List<dynamic>? out;
      for (var i = 0; i < v.length; i++) {
        final n = _hydrate(v[i], depth, guard + 1);
        if (!identical(n, v[i])) (out ??= [...v])[i] = n;
      }
      return out ?? v;
    }
    if (v is Map) {
      Map<String, dynamic>? out;
      for (final e in v.entries) {
        final mouth = e.key == kLcExprBody && v['e'] is String && e.value is List && e.value is! List<LcBlock>;
        final n = mouth ? parseList(e.value, depth + 1) : _hydrate(e.value, depth, guard + 1);
        if (!identical(n, e.value)) (out ??= {for (final x in v.entries) '${x.key}': x.value})['${e.key}'] = n;
      }
      return out ?? v;
    }
    return v;
  }
}

/// “带口的值”（匿名函数这种：一个值，里面有一个能放积木的口）把口里的那串积木存在表达式对象的这个字段里。
/// 名字以 `@` 开头：不会和任何参数名撞上。存盘是普通的积木列表；读进来以后是 `List<LcBlock>`。
const String kLcExprBody = '@body';

/// 表达式里的口（没有、或不是读好的积木列表返回 null）。
List<LcBlock>? lcExprBody(Object? expr) {
  if (expr is! Map) return null;
  final v = expr[kLcExprBody];
  return v is List<LcBlock> ? v : null;
}

/// 路径里“在上一块参数里的第 k 个带口的值的口里”这一步的 `arm`：-2、-3、…（-1 留给“不是段”）。
int lcExprMouthArm(int k) => -2 - k;
int lcExprMouthIndex(int arm) => -2 - arm;

/// 积木在一个处理里的位置：从处理的 `body` 开始一步步往里走。
/// 每一步是“在第几块”，以及（从第二步起）“在上一块的哪个口里”：`arm >= 0` 是第几段的口；
/// 否则 `inElse` 是收尾口（“否则”），不然是开头口（“那么”）。第一步的 `inElse` / `arm` 不看。
///
/// 例：`[lcStep(2), lcStep(0, inElse: true)]` ＝ 第 3 块的“否则”里的第 1 块；
/// `[lcStep(2), lcStep(0, arm: 1)]` ＝ 第 3 块的第 2 段“否则如果”里的第 1 块。
typedef LcBlockStep = ({bool inElse, int index, int arm});
typedef LcBlockPath = List<LcBlockStep>;

/// 造一步路径（少写点字）。一律用它造，不要手写这个 record（以后再加字段不用到处改）。
LcBlockStep lcStep(int index, {bool inElse = false, int arm = -1}) => (inElse: inElse, index: index, arm: arm);

/// 两步是不是指同一个口里的同一个位置。
bool lcSameStep(LcBlockStep a, LcBlockStep b) => a.index == b.index && lcSameMouth(a, b);

/// 两步是不是在同一个口里（不比第几块）。
bool lcSameMouth(LcBlockStep a, LcBlockStep b) => a.arm != -1 || b.arm != -1 ? a.arm == b.arm : a.inElse == b.inElse;

/// “一串积木”的按路径操作（找、插、删、挪、遍历）。谁有一个 `body` 就能混进来用：
/// 前端的事件处理（[LcHandler]）和后端的接口（lib/backend）共用这一套，积木编辑器也只认它。
///
/// `x` / `y` 是这串积木在积木画布上的位置（左上角，逻辑像素）；null＝还没摆过，编辑器打开时自动排。
mixin LcBlockTree {
  String get id;
  List<LcBlock> get body;
  double? x;
  double? y;

  /// 按路径找积木；路径不对（越界、空）返回 null。
  LcBlock? blockAt(LcBlockPath path) {
    if (path.isEmpty) return null;
    var list = body;
    LcBlock? block;
    for (var i = 0; i < path.length; i++) {
      if (i > 0) {
        final inner = block!.mouth(inElse: path[i].inElse, arm: path[i].arm);
        if (inner == null) return null;
        list = inner;
      }
      final index = path[i].index;
      if (index < 0 || index >= list.length) return null;
      block = list[index];
    }
    return block;
  }

  /// 一串积木所在的那个列表：`parent` 为空＝处理自己的 body；否则是那块积木的 body（或 `inElse` 时的 else）。
  /// `arm >= 0`＝那块积木第几段的口（见 [LcBlock.arms]）。
  List<LcBlock>? listAt(LcBlockPath parent, {bool inElse = false, int arm = -1}) {
    if (parent.isEmpty) return body;
    return blockAt(parent)?.mouth(inElse: inElse, arm: arm);
  }

  /// 路径最后一步所在的那个列表。
  List<LcBlock>? _homeOf(LcBlockPath path) => listAt(path.sublist(0, path.length - 1), inElse: path.last.inElse, arm: path.last.arm);

  /// 把积木插进去；`index` 省略＝放最后。位置不存在、或插进去以后嵌套超过 [LcBlock.maxDepth] 层就不插，返回 false
  /// （超过的层数存盘后再读会被丢掉，所以这里先拦住）。
  bool insertBlock(LcBlockPath parent, LcBlock block, {bool inElse = false, int arm = -1, int? index}) {
    final list = listAt(parent, inElse: inElse, arm: arm);
    if (list == null) return false;
    // parent 有几步，新积木就在第几层（从 0 数）；它自己往下还有 height - 1 层。
    if (parent.length + block.height - 1 > LcBlock.maxDepth) return false;
    list.insert((index ?? list.length).clamp(0, list.length), block);
    return true;
  }

  /// 删掉一块（连同嵌在里面的）；返回被删的那块，路径不对返回 null。
  LcBlock? removeBlock(LcBlockPath path) {
    if (path.isEmpty) return null;
    final list = _homeOf(path);
    final index = path.last.index;
    if (list == null || index < 0 || index >= list.length) return null;
    return list.removeAt(index);
  }

  /// 把一块积木挪到别处（可以跨层）。不能挪进自己里面；`index` 是“挪走之前”目标列表里的位置。
  bool moveBlock(LcBlockPath from, LcBlockPath toParent, {bool inElse = false, int arm = -1, int? index}) {
    final block = blockAt(from);
    final target = listAt(toParent, inElse: inElse, arm: arm);
    if (block == null || target == null) return false;
    if (toParent.length >= from.length && _samePrefix(from, toParent)) return false; // 目标在自己里面
    if (toParent.length + block.height - 1 > LcBlock.maxDepth) return false;
    final source = _homeOf(from);
    if (source == null) return false;
    var i = (index ?? target.length).clamp(0, target.length);
    if (identical(source, target) && from.last.index < i) i -= 1;
    source.removeAt(from.last.index);
    target.insert(i.clamp(0, target.length), block);
    return true;
  }

  /// 在同一串里上移 / 下移一位。
  bool shiftBlock(LcBlockPath path, int delta) {
    if (path.isEmpty) return false;
    final list = _homeOf(path);
    final i = path.last.index;
    if (list == null || i < 0 || i >= list.length) return false;
    final j = i + delta;
    if (j < 0 || j >= list.length) return false;
    list.insert(j, list.removeAt(i));
    return true;
  }

  /// `inner` 的前 `outer.length` 步是不是正好就是 `outer`（＝inner 在 outer 那块积木里面，或就是它）。
  bool _samePrefix(LcBlockPath outer, LcBlockPath inner) {
    for (var i = 0; i < outer.length; i++) {
      if (outer[i].index != inner[i].index) return false;
      if (i > 0 && !lcSameMouth(outer[i], inner[i])) return false;
    }
    return true;
  }

  /// 从外到里走一遍所有积木（先自己，再 body，再各段，再 else），带上各自的路径。
  void visitBlocks(void Function(LcBlock block, LcBlockPath path) visit) {
    void walk(List<LcBlock> list, LcBlockPath parent, bool inElse, int arm) {
      for (var i = 0; i < list.length; i++) {
        final path = [...parent, lcStep(i, inElse: inElse, arm: arm)];
        final b = list[i];
        visit(b, path);
        walk(b.body, path, false, -1);
        for (var a = 0; a < b.arms.length; a++) {
          walk(b.arms[a].body, path, false, a);
        }
        walk(b.orElse, path, true, -1);
        final inExprs = b.exprMouths;
        for (var k = 0; k < inExprs.length; k++) {
          walk(inExprs[k], path, false, lcExprMouthArm(k));
        }
      }
    }

    walk(body, const [], false, -1);
  }
}

/// 一个事件处理：`event` 是 click / input / load；`target` 是触发它的组件 id（load 没有）。
class LcHandler with LcBlockTree {
  LcHandler({required this.id, required this.event, this.target, List<LcBlock>? body, double? x, double? y}) : body = body ?? [] {
    this.x = x;
    this.y = y;
  }

  @override
  String id;
  String event;
  String? target;
  @override
  final List<LcBlock> body;

  static const List<String> events = ['click', 'input', 'load'];

  Map<String, dynamic> toJson() => {
    'id': id,
    'event': event,
    if (target != null) 'target': target,
    if (x != null) 'x': x,
    if (y != null) 'y': y,
    'body': [for (final b in body) b.toJson()],
  };

  LcHandler clone() => LcHandler(id: id, event: event, target: target, body: [for (final b in body) b.clone()], x: x, y: y);

  static LcHandler? tryParse(Object? json) {
    if (json is! Map) return null;
    final event = json['event'];
    if (event is! String || !events.contains(event)) return null;
    final id = json['id'];
    final target = json['target'];
    final x = json['x'];
    final y = json['y'];
    return LcHandler(
      id: id is String ? id : '',
      event: event,
      target: target is String && target.isNotEmpty ? target : null,
      body: LcBlock.parseList(json['body'], 0),
      x: x is num && x.isFinite ? x.toDouble() : null,
      y: y is num && y.isFinite ? y.toDouble() : null,
    );
  }
}

class LcLogic {
  LcLogic({List<LcVariable>? variables, List<LcHandler>? handlers}) : variables = variables ?? [], handlers = handlers ?? [] {
    _normalize();
  }

  final List<LcVariable> variables;
  final List<LcHandler> handlers;

  bool get isEmpty => variables.isEmpty && handlers.isEmpty;

  Map<String, dynamic> toJson() => {
    'variables': [for (final v in variables) v.toJson()],
    'handlers': [for (final h in handlers) h.toJson()],
  };

  /// 容错读取：不是对象就当没有逻辑；坏的变量 / 处理 / 积木逐条跳过。
  factory LcLogic.fromJson(Object? json) {
    if (json is! Map) return LcLogic();
    final vars = json['variables'];
    final hs = json['handlers'];
    return LcLogic(
      variables: [
        if (vars is List)
          for (final v in vars) ?LcVariable.tryParse(v, wide: true),
      ],
      handlers: [
        if (hs is List)
          for (final h in hs) ?LcHandler.tryParse(h),
      ],
    );
  }

  /// 变量重名只留第一个；处理的 id 缺了 / 重了就补一个 `h数字`。
  void _normalize() {
    final names = <String>{};
    variables.removeWhere((v) => !names.add(v.name));
    final ids = <String>{};
    var next = 1;
    for (final h in handlers) {
      if (h.id.isEmpty || !RegExp(r'^[A-Za-z0-9_]+$').hasMatch(h.id) || !ids.add(h.id)) {
        while (ids.contains('h$next')) {
          next++;
        }
        h.id = 'h$next';
        ids.add(h.id);
      }
    }
  }

  LcVariable? variable(String name) {
    for (final v in variables) {
      if (v.name == name) return v;
    }
    return null;
  }

  Iterable<LcHandler> handlersFor(String nodeId) => handlers.where((h) => h.target == nodeId);

  LcHandler? handler(String id) {
    for (final h in handlers) {
      if (h.id == id) return h;
    }
    return null;
  }

  /// 新建一个处理并加到最后；id 自动取一个没用过的 `h数字`。`event` 不认识返回 null。
  LcHandler? addHandler(String event, {String? target}) {
    if (!LcHandler.events.contains(event)) return null;
    final ids = {for (final h in handlers) h.id};
    var n = 1;
    while (ids.contains('h$n')) {
      n++;
    }
    final h = LcHandler(id: 'h$n', event: event, target: event == 'load' ? null : target);
    handlers.add(h);
    return h;
  }

  bool removeHandler(String id) {
    final before = handlers.length;
    handlers.removeWhere((h) => h.id == id);
    return handlers.length != before;
  }

  /// 加一个变量；名字不合规矩或重名返回 null。
  LcVariable? addVariable(String name, {String type = 'text', Object? initial}) {
    if (!LcVariable.namePattern.hasMatch(name) || variable(name) != null || !LcVariable.stateTypes.contains(type)) return null;
    final v = LcVariable(name: name, type: type, initial: initial);
    variables.add(v);
    return v;
  }

  LcLogic clone() => LcLogic(
    variables: [for (final v in variables) v.clone()],
    handlers: [for (final h in handlers) h.clone()],
  );
}
