/// 低代码页面的“逻辑”数据模型：页面变量 + 事件处理（每个处理是一串积木）。
///
/// 这里只管数据的形状和读写（读的时候容错：旧文件、坏字段都不许让页面打不开）。
/// 有哪些积木、每块要什么参数、怎么翻成 JavaScript，在 `logic_blocks.dart` / `logic_js.dart`。
/// JSON 结构的完整约定见 docs/lowcode-v2-design.md。
library;

/// 页面变量。`type`：text / number / bool。
class LcVariable {
  LcVariable({required this.name, this.type = 'text', Object? initial}) : initial = _coerce(type, initial);

  String name;
  String type;
  Object initial;

  static const List<String> types = ['text', 'number', 'bool'];
  static final RegExp namePattern = RegExp(r'^[A-Za-z_][A-Za-z0-9_]{0,31}$');

  static Object _coerce(String type, Object? v) => switch (type) {
    'number' => v is num ? v : 0,
    'bool' => v is bool && v,
    _ => v is String ? v : '',
  };

  Map<String, dynamic> toJson() => {'name': name, 'type': type, 'initial': initial};

  /// 字段不对就返回 null（调用方跳过这一条）。
  static LcVariable? tryParse(Object? json) {
    if (json is! Map) return null;
    final name = json['name'];
    if (name is! String || !namePattern.hasMatch(name)) return null;
    final type = json['type'];
    return LcVariable(name: name, type: type is String && types.contains(type) ? type : 'text', initial: json['initial']);
  }
}

/// 一块积木。`op` 是积木种类；`args` 是参数（字面量或表达式对象 `{"e": ...}`）；
/// `body` / `orElse` 是嵌在里面的积木（“如果”“重复”这类才有）。
class LcBlock {
  LcBlock({required this.op, Map<String, dynamic>? args, List<LcBlock>? body, List<LcBlock>? orElse}) : args = args ?? {}, body = body ?? [], orElse = orElse ?? [];

  final String op;
  final Map<String, dynamic> args;
  final List<LcBlock> body;
  final List<LcBlock> orElse;

  static const int maxDepth = 12;

  Map<String, dynamic> toJson() => {
    'op': op,
    if (args.isNotEmpty) 'args': args,
    if (body.isNotEmpty) 'body': [for (final b in body) b.toJson()],
    if (orElse.isNotEmpty) 'else': [for (final b in orElse) b.toJson()],
  };

  /// 深拷贝：参数、嵌在里面的积木全都是新对象，改副本不影响原件。
  LcBlock clone() {
    final copied = _copyJson(args, 0);
    return LcBlock(op: op, args: copied is Map<String, dynamic> ? copied : {}, body: [for (final b in body) b.clone()], orElse: [for (final b in orElse) b.clone()]);
  }

  /// 这块积木往下（含自己）一共有几层。
  int get height {
    var h = 0;
    for (final b in body.followedBy(orElse)) {
      final bh = b.height;
      if (bh > h) h = bh;
    }
    return h + 1;
  }

  /// 参数里是 JSON 值（字面量 / Map / List）；超过 64 层的截掉（正常数据到不了，防自己套自己的坏数据）。
  static Object? _copyJson(Object? v, int depth) {
    if (depth > 64) return null;
    if (v is Map) return <String, dynamic>{for (final e in v.entries) '${e.key}': _copyJson(e.value, depth + 1)};
    if (v is List) return <dynamic>[for (final item in v) _copyJson(item, depth + 1)];
    return v is String || v is num || v is bool ? v : null;
  }

  static LcBlock? tryParse(Object? json, int depth) {
    if (json is! Map || depth > maxDepth) return null;
    final op = json['op'];
    if (op is! String || op.isEmpty) return null;
    final args = json['args'];
    return LcBlock(op: op, args: args is Map ? {for (final e in args.entries) '${e.key}': e.value} : {}, body: parseList(json['body'], depth + 1), orElse: parseList(json['else'], depth + 1));
  }

  static List<LcBlock> parseList(Object? json, int depth) {
    if (json is! List) return [];
    return [for (final item in json) ?tryParse(item, depth)];
  }
}

/// 积木在一个处理里的位置：从处理的 `body` 开始一步步往里走。
/// 每一步是“在第几块”，以及（从第二步起）“是上一块的 body 还是 else 里的”。第一步的 `inElse` 不看。
///
/// 例：`[(inElse: false, index: 2), (inElse: true, index: 0)]` ＝ 第 3 块的“否则”里的第 1 块。
typedef LcBlockStep = ({bool inElse, int index});
typedef LcBlockPath = List<LcBlockStep>;

/// 造一步路径（少写点字）。
LcBlockStep lcStep(int index, {bool inElse = false}) => (inElse: inElse, index: index);

/// 一个事件处理：`event` 是 click / input / load；`target` 是触发它的组件 id（load 没有）。
class LcHandler {
  LcHandler({required this.id, required this.event, this.target, List<LcBlock>? body}) : body = body ?? [];

  String id;
  String event;
  String? target;
  final List<LcBlock> body;

  static const List<String> events = ['click', 'input', 'load'];

  Map<String, dynamic> toJson() => {
    'id': id,
    'event': event,
    if (target != null) 'target': target,
    'body': [for (final b in body) b.toJson()],
  };

  LcHandler clone() => LcHandler(id: id, event: event, target: target, body: [for (final b in body) b.clone()]);

  /// 按路径找积木；路径不对（越界、空）返回 null。
  LcBlock? blockAt(LcBlockPath path) {
    if (path.isEmpty) return null;
    var list = body;
    LcBlock? block;
    for (var i = 0; i < path.length; i++) {
      if (i > 0) list = path[i].inElse ? block!.orElse : block!.body;
      final index = path[i].index;
      if (index < 0 || index >= list.length) return null;
      block = list[index];
    }
    return block;
  }

  /// 一串积木所在的那个列表：`parent` 为空＝处理自己的 body；否则是那块积木的 body（或 `inElse` 时的 else）。
  List<LcBlock>? listAt(LcBlockPath parent, {bool inElse = false}) {
    if (parent.isEmpty) return body;
    final block = blockAt(parent);
    if (block == null) return null;
    return inElse ? block.orElse : block.body;
  }

  /// 把积木插进去；`index` 省略＝放最后。位置不存在、或插进去以后嵌套超过 [LcBlock.maxDepth] 层就不插，返回 false
  /// （超过的层数存盘后再读会被丢掉，所以这里先拦住）。
  bool insertBlock(LcBlockPath parent, LcBlock block, {bool inElse = false, int? index}) {
    final list = listAt(parent, inElse: inElse);
    if (list == null) return false;
    // parent 有几步，新积木就在第几层（从 0 数）；它自己往下还有 height - 1 层。
    if (parent.length + block.height - 1 > LcBlock.maxDepth) return false;
    list.insert((index ?? list.length).clamp(0, list.length), block);
    return true;
  }

  /// 删掉一块（连同嵌在里面的）；返回被删的那块，路径不对返回 null。
  LcBlock? removeBlock(LcBlockPath path) {
    if (path.isEmpty) return null;
    final list = listAt(path.sublist(0, path.length - 1), inElse: path.last.inElse);
    final index = path.last.index;
    if (list == null || index < 0 || index >= list.length) return null;
    return list.removeAt(index);
  }

  /// 把一块积木挪到别处（可以跨层）。不能挪进自己里面；`index` 是“挪走之前”目标列表里的位置。
  bool moveBlock(LcBlockPath from, LcBlockPath toParent, {bool inElse = false, int? index}) {
    final block = blockAt(from);
    final target = listAt(toParent, inElse: inElse);
    if (block == null || target == null) return false;
    if (toParent.length >= from.length && _samePrefix(from, toParent)) return false; // 目标在自己里面
    if (toParent.length + block.height - 1 > LcBlock.maxDepth) return false;
    final source = listAt(from.sublist(0, from.length - 1), inElse: from.last.inElse);
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
    final list = listAt(path.sublist(0, path.length - 1), inElse: path.last.inElse);
    final i = path.last.index;
    if (list == null || i < 0 || i >= list.length) return false;
    final j = i + delta;
    if (j < 0 || j >= list.length) return false;
    list.insert(j, list.removeAt(i));
    return true;
  }

  /// `inner` 的前 `outer.length` 步是不是正好就是 `outer`（＝inner 在 outer 那块积木里面，或就是它）。
  static bool _samePrefix(LcBlockPath outer, LcBlockPath inner) {
    for (var i = 0; i < outer.length; i++) {
      if (outer[i].index != inner[i].index) return false;
      if (i > 0 && outer[i].inElse != inner[i].inElse) return false;
    }
    return true;
  }

  /// 从外到里走一遍所有积木（先自己，再 body，再 else），带上各自的路径。
  void visitBlocks(void Function(LcBlock block, LcBlockPath path) visit) {
    void walk(List<LcBlock> list, LcBlockPath parent, bool inElse) {
      for (var i = 0; i < list.length; i++) {
        final path = [...parent, lcStep(i, inElse: inElse)];
        visit(list[i], path);
        walk(list[i].body, path, false);
        walk(list[i].orElse, path, true);
      }
    }

    walk(body, const [], false);
  }

  static LcHandler? tryParse(Object? json) {
    if (json is! Map) return null;
    final event = json['event'];
    if (event is! String || !events.contains(event)) return null;
    final id = json['id'];
    final target = json['target'];
    return LcHandler(id: id is String ? id : '', event: event, target: target is String && target.isNotEmpty ? target : null, body: LcBlock.parseList(json['body'], 0));
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
          for (final v in vars) ?LcVariable.tryParse(v),
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
    if (!LcVariable.namePattern.hasMatch(name) || variable(name) != null || !LcVariable.types.contains(type)) return null;
    final v = LcVariable(name: name, type: type, initial: initial);
    variables.add(v);
    return v;
  }

  LcLogic clone() => LcLogic(
    variables: [for (final v in variables) LcVariable(name: v.name, type: v.type, initial: v.initial)],
    handlers: [for (final h in handlers) h.clone()],
  );
}
