/// 后端文档的“连带修改”：变量 / 集合改名时同步引用、改接口路径时同步路径参数的名字、查某个东西还有没有人在用。
///
/// 单纯的结构操作（按路径插入 / 删除 / 移动积木）在 `LcBlockTree`（lib/lowcode/logic_model.dart），
/// 增删接口 / 变量 / 集合在 backend_model.dart；这里的操作要知道“哪个参数是变量名、哪个是集合名”，所以照着积木目录来。
library;

import 'package:lopicode/backend/backend_blocks.dart';
import 'package:lopicode/backend/backend_model.dart';
import 'package:lopicode/lowcode/logic_model.dart';

/// 走一遍一块积木参数里所有的表达式（含嵌在里面的），`visit` 拿到的是可以原地改的 Map。
void _visitExprs(Object? value, void Function(Map<Object?, Object?> expr) visit, [int depth = 0]) {
  if (depth > kMaxExprDepth * 2) return;
  if (value is Map) {
    if (isExpr(value)) visit(value);
    for (final v in value.values) {
      _visitExprs(v, visit, depth + 1);
    }
  } else if (value is List) {
    for (final v in value) {
      _visitExprs(v, visit, depth + 1);
    }
  }
}

/// 把一处处“名字引用”都过一遍：积木自己的参数和表达式里的参数，只要种类是 `kind`（变量名 / 集合名）就交给 `visit`。
/// `visit` 返回新名字就改，返回 null 不动。
void _visitNames(Iterable<BeRoute> routes, LcArgKind kind, String? Function(String name) visit) {
  void slot(Map<Object?, Object?> holder, List<LcArgSpec> specs) {
    for (final a in specs) {
      if (a.kind != kind) continue;
      final v = holder[a.name];
      if (v is! String) continue;
      final next = visit(v);
      if (next != null) holder[a.name] = next;
    }
  }

  for (final r in routes) {
    r.visitBlocks((b, _) {
      slot(b.args, beBlockSpecs[b.op]?.args ?? const []);
      _visitExprs(b.args, (e) => slot(e, beExprSpecs[e['e']]?.args ?? const []));
    });
  }
}

extension BeDocumentEdit on BeDocument {
  int _count(LcArgKind kind, String name) {
    var n = 0;
    _visitNames(routes, kind, (v) {
      if (v == name) n++;
      return null;
    });
    return n;
  }

  /// 有多少处用到了这个变量（设置 / 加上 / 放进它 / 读它）。删之前可以先问一句。
  int variableRefCount(String name) => _count(LcArgKind.variable, name);

  /// 有多少处用到了这个集合。
  int collectionRefCount(String name) => _count(LcArgKind.collection, name);

  /// 变量改名，所有用到它的地方一起改。新名字不合规矩、已经被别的变量用了、或没有这个变量，就什么都不改，返回 false。
  bool renameVariable(String oldName, String newName) {
    final v = variable(oldName);
    if (v == null || !beNamePattern.hasMatch(newName)) return false;
    if (oldName == newName) return true;
    if (variable(newName) != null) return false;
    v.name = newName;
    _visitNames(routes, LcArgKind.variable, (n) => n == oldName ? newName : null);
    return true;
  }

  /// 删变量。用到它的积木**不动**（校验会把它们标成“变量还没有声明”，由人决定怎么改）。返回是否删了。
  bool removeVariable(String name) {
    final before = variables.length;
    variables.removeWhere((v) => v.name == name);
    return variables.length != before;
  }

  /// 改变量的类型，初始值跟着换成新类型的默认值（原来的值能直接用就留着）。类型不认识返回 false。
  bool retypeVariable(String name, String type) {
    final i = variables.indexWhere((v) => v.name == name);
    if (i < 0 || !LcVariable.types.contains(type)) return false;
    variables[i] = LcVariable(name: name, type: type, initial: variables[i].initial);
    return true;
  }

  /// 改变量的初始值（按它的类型收一遍：类型对不上就用该类型的默认值）。没有这个变量返回 false。
  bool setVariableInitial(String name, Object? initial) {
    final i = variables.indexWhere((v) => v.name == name);
    if (i < 0) return false;
    variables[i] = LcVariable(name: name, type: variables[i].type, initial: initial);
    return true;
  }

  /// 集合改名，所有用到它的地方一起改。规矩同 [renameVariable]。
  bool renameCollection(String oldName, String newName) {
    final c = collection(oldName);
    if (c == null || !beNamePattern.hasMatch(newName)) return false;
    if (oldName == newName) return true;
    if (collection(newName) != null) return false;
    c.name = newName;
    _visitNames(routes, LcArgKind.collection, (n) => n == oldName ? newName : null);
    return true;
  }

  /// 删集合。用到它的积木不动（校验会标出来）。返回是否删了。
  bool removeCollection(String name) {
    final before = collections.length;
    collections.removeWhere((c) => c.name == name);
    return collections.length != before;
  }

  /// 改接口的请求方式。方式不认识或没有这个接口返回 false。
  bool setRouteMethod(String id, String method) {
    final r = route(id);
    final upper = method.toUpperCase();
    if (r == null || !kBeMethods.contains(upper)) return false;
    r.method = upper;
    return true;
  }

  /// 改接口的路径。路径格式不对、或没有这个接口，就什么都不改，返回 false。
  ///
  /// 如果新旧路径的参数个数一样、只是名字变了（`/todos/:id` → `/todos/:todoId`），这个接口里读旧名字的“路径参数”跟着改名；
  /// 个数变了就不动积木（校验会把对不上的标出来）。
  bool setRoutePath(String id, String path) {
    final r = route(id);
    if (r == null || parseBePath(path) == null) return false;
    final before = bePathParams(r.path);
    final after = bePathParams(path);
    r.path = path;
    if (before.length != after.length || before.toSet().length != before.length) return true;
    final renames = <String, String>{
      for (var i = 0; i < before.length; i++)
        if (before[i] != after[i]) before[i]: after[i],
    };
    if (renames.isEmpty) return true;
    r.visitBlocks((b, _) {
      _visitExprs(b.args, (e) {
        final next = e['e'] == 'pathParam' ? renames[e['name']] : null;
        if (next != null) e['name'] = next;
      });
    });
    return true;
  }

  /// 把接口挪到第 `newIndex` 个（接口按从上到下的顺序匹配，顺序有意义）。没有这个接口返回 false。
  bool moveRoute(String id, int newIndex) {
    final i = routes.indexWhere((r) => r.id == id);
    if (i < 0) return false;
    final r = routes.removeAt(i);
    routes.insert(newIndex.clamp(0, routes.length), r);
    return true;
  }

  /// 复制一个接口（积木全是新对象），放在原件后面；路径后面加一段 `/copy`（免得一复制就报“地址重复”）。没有这个接口返回 null。
  BeRoute? duplicateRoute(String id) {
    final i = routes.indexWhere((r) => r.id == id);
    if (i < 0) return null;
    final src = routes[i];
    final ids = {for (final r in routes) r.id};
    var n = 1;
    while (ids.contains('r$n')) {
      n++;
    }
    final copy = BeRoute(id: 'r$n', method: src.method, path: src.path == '/' ? '/copy' : '${src.path}/copy', body: [for (final b in src.body) b.clone()]);
    routes.insert(i + 1, copy);
    return copy;
  }
}
