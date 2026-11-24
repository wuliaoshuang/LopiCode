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
}
