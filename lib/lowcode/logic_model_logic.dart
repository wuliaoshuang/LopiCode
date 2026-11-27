part of 'logic_model.dart';

// 一页的逻辑（状态、处理、用上的库、新的页面逻辑）：从 logic_model.dart 原样挪出来的，那边放不下了。

class LcLogic {
  LcLogic({List<LcVariable>? variables, List<LcHandler>? handlers, List<Map<String, dynamic>>? uses, this.front}) : variables = variables ?? [], handlers = handlers ?? [], uses = uses ?? [] {
    _normalize();
  }

  final List<LcVariable> variables;
  final List<LcHandler> handlers;

  /// 用上的积木库（每条 `{id, settings?}`，原样存着；怎么读见 logic_libs.dart）。没用库的页面存盘不写这一项。
  final List<Map<String, dynamic>> uses;

  /// [uses] 里的库读进来的样子（不存盘：打开页面的人从项目的 `blocks/` 里读好了放进来）。
  List<LibLibrary> loaded = const [];

  /// 新的页面逻辑（积木第 5 版·前端 1）：一份“前端这一边”的积木文档，原样存着（怎么读、怎么编见 lib/backend/front_doc.dart）。
  /// null＝旧的页面逻辑（只有 [handlers] 里的旧处理）。有它的时候 [handlers] 里只是从它的事件帽子抄出来的空壳（给导出接线用）。
  Map<String, dynamic>? front;

  bool get isEmpty => variables.isEmpty && handlers.isEmpty && front == null;

  Map<String, dynamic> toJson() => {
    'variables': [for (final v in variables) v.toJson()],
    'handlers': [for (final h in handlers) h.toJson()],
    if (uses.isNotEmpty) 'uses': uses,
    'front': ?front,
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
      uses: [
        if (json['uses'] case final List<Object?> us)
          for (final u in us.take(16))
            if (u is Map && u['id'] is String) {for (final e in u.entries) '${e.key}': e.value},
      ],
      front: json['front'] is Map ? {for (final e in (json['front'] as Map).entries) '${e.key}': e.value} : null,
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
    uses: [
      for (final u in uses) {...u},
    ],
    front: front == null ? null : jsonDecode(jsonEncode(front)) as Map<String, dynamic>,
  )..loaded = loaded;
}
