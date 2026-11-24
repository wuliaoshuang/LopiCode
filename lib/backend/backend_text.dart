/// 把后端的积木、表达式、接口读成一句人话。积木界面、校验信息、生成代码里的注释都用它。
library;

import 'package:lopicode/backend/backend_blocks.dart';
import 'package:lopicode/backend/backend_model.dart';
import 'package:lopicode/lowcode/logic_model.dart';

/// `keepEdges`：文字字面量两头的空格是内容的一部分，要留着给人看见。
String _clip(String s, [int limit = 12, bool keepEdges = false]) {
  // 换行、制表符收成空格：这些话会放进单行的列表项和注释里。
  final collapsed = s.replaceAll(RegExp(r'[\r\n\t\u0085\u2028\u2029]+'), ' ');
  final flat = keepEdges ? collapsed : collapsed.replaceAll(RegExp(r'\s+'), ' ').trim();
  final runes = flat.runes.toList();
  return runes.length <= limit ? flat : '${String.fromCharCodes(runes.take(limit))}…';
}

String _name(Object? v, String missing) => v is String && v.isNotEmpty ? _clip(v, 32) : '（$missing）';
String _var(Object? name) => _name(name, '还没选变量');
String _col(Object? name) => '集合 ${_name(name, '还没选集合')}';

const Map<String, String> _opSigns = {'+': '+', '-': '-', '*': '×', '/': '÷', '%': '除以后余', '==': '=', '!=': '≠', '<': '<', '<=': '≤', '>': '>', '>=': '≥', 'and': '并且', 'or': '或者'};

String _number(num v) => v is int || v == v.roundToDouble() && v.abs() < 1e15 ? '${v.round()}' : '$v';

/// 表达式读成人话：`路径参数 id`、`集合 todos 里 id 是 路径参数 id 的那条`、`{title: “买菜”, done: 否}`。
/// 缺了的地方写“（空）”，不认识的写“不认识的值（种类）”。
String describeBeExpr(Object? expr) => _expr(expr, 0, false);

String _expr(Object? expr, int depth, bool nested) {
  if (depth > kMaxExprDepth) return '…';
  String sub(String key, [bool inner = true]) => _expr(exprField(expr, key), depth + 1, inner);
  final kind = exprKind(expr);
  switch (kind) {
    case null:
      return '（空）';
    case 'text':
      final v = exprString(expr, 'v');
      return v == null ? '（空）' : '“${_clip(v, 24, true)}”';
    case 'num':
      final v = exprNum(expr, 'v');
      return v == null ? '（空）' : _number(v);
    case 'bool':
      final v = exprBool(expr, 'v');
      return v == null ? '（空）' : (v ? '是' : '否');
    case 'var':
      return _var(exprString(expr, 'name'));
    case 'pathParam':
      return '路径参数 ${_name(exprString(expr, 'name'), '没填名字')}';
    case 'query':
      return '网址参数 ${_name(exprString(expr, 'name'), '没填名字')}';
    case 'bodyField':
      return '请求内容的 ${_name(exprString(expr, 'name'), '没填字段')}';
    case 'body':
      return '整个请求内容';
    case 'header':
      return '请求头 ${_name(exprString(expr, 'name'), '没填名字')}';
    case 'dbAll':
      return '${_col(exprString(expr, 'collection'))} 的全部';
    case 'dbGet':
      return '${_col(exprString(expr, 'collection'))} 里 id 是 ${sub('id')} 的那条';
    case 'dbFind':
      return '${_col(exprString(expr, 'collection'))} 里 ${_name(exprString(expr, 'key'), '没填字段')} 等于 ${sub('value')} 的那些';
    case 'dbCount':
      return '${_col(exprString(expr, 'collection'))} 的条数';
    case 'bin':
      final op = exprString(expr, 'op') ?? '';
      final text = '${sub('l')} ${_opSigns[op] ?? '?'} ${sub('r')}';
      // 套在别的运算里要加括号，不然 “a + b × c” 看不出先算哪个。
      return nested ? '（$text）' : text;
    case 'not':
      return '不是（${sub('x', false)}）';
    case 'join':
      final items = exprField(expr, 'items');
      final parts = [
        if (items is List)
          for (final item in items) _expr(item, depth + 1, true),
      ];
      return parts.isEmpty ? '拼接（空）' : '拼接（${parts.join('、')}）';
    case 'len':
      return '${sub('x')} 有几个';
    case 'isNull':
      return '${sub('x')} 是空的';
    case 'now':
      return '现在的时间';
    case 'obj':
      final fields = exprField(expr, 'fields');
      final parts = [
        if (fields is List)
          for (final f in fields) _expr(f, depth + 1, false),
      ];
      return parts.isEmpty ? '空对象 {}' : '{${parts.join(', ')}}';
    case 'pair':
      return '${_name(exprString(expr, 'key'), '没填名字')}: ${sub('value', false)}';
    case 'field':
      return '${sub('of')} 的 ${_name(exprString(expr, 'key'), '没填字段')}';
    default:
      return '不认识的值（${_clip(kind)}）';
  }
}

/// 积木读成一句人话，只说这一块自己（里面嵌的积木不展开，用“…”带过）：
/// “返回 200 和 集合 todos 的全部”“往 集合 todos 里加一条 整个请求内容，放进 todo”。
String describeBeBlock(LcBlock b) {
  String arg(String name) => describeBeExpr(b.args[name]);
  String into(String prefix) {
    final v = b.args['into'];
    return v is String && v.isNotEmpty ? '$prefix ${_clip(v, 32)}' : '';
  }

  switch (b.op) {
    case 'respondJson':
      return '返回 ${arg('status')} 和数据 ${arg('value')}';
    case 'respondText':
      return '返回 ${arg('status')} 和文字 ${arg('value')}';
    case 'dbInsert':
      return '往 ${_col(b.args['collection'])} 里加一条 ${arg('value')}${into('，放进')}';
    case 'dbUpdate':
      return '把 ${_col(b.args['collection'])} 里 id 是 ${arg('id')} 的那条改成 ${arg('value')}';
    case 'dbDelete':
      return '删掉 ${_col(b.args['collection'])} 里 id 是 ${arg('id')} 的那条';
    case 'setVar':
      return '把 ${_var(b.args['name'])} 设为 ${arg('value')}';
    case 'changeVar':
      return '把 ${_var(b.args['name'])} 加上 ${arg('by')}';
    case 'if':
      return b.orElse.isEmpty ? '如果 ${arg('cond')} 那么…' : '如果 ${arg('cond')} 那么…否则…';
    case 'repeat':
      return '重复 ${arg('times')} 次…';
    case 'forEach':
      return '对 ${arg('list')} 里的每一项（放进 ${_var(b.args['item'])}）依次做…';
    case 'log':
      return '写到日志 ${arg('value')}';
    case 'fetch':
      final method = b.args['method'] == 'POST' ? 'POST' : 'GET';
      final data = method == 'POST' && isExpr(b.args['data']) ? '，提交 ${arg('data')}' : '';
      return '用 $method 请求 ${arg('url')}$data${into('，结果放进')}';
    default:
      return '不认识的积木（${_clip(b.op)}）';
  }
}

/// 接口读成一句话：“GET /todos/:id”。这也是积木画布上“帽子”的字。
String describeBeRoute(BeRoute r) => '${r.method} ${_clip(r.path, 60)}';

/// 请求方式的中文说明（给选择菜单当副标题）。
String describeBeMethod(String method) => switch (method) {
  'GET' => '取数据',
  'POST' => '新增 / 提交',
  'PUT' => '整条替换',
  'PATCH' => '改一部分',
  'DELETE' => '删除',
  _ => method,
};

/// 积木的位置读成人话：“第 2 块 › 否则 › 第 1 块”。中间的“那么 / 否则 / 成功后…”按每一层积木自己的叫法来。
String describeBeBlockPath(LcBlockTree tree, LcBlockPath path) {
  final parts = <String>[];
  var list = tree.body;
  LcBlock? parent;
  for (var i = 0; i < path.length; i++) {
    if (parent != null) {
      final spec = beBlockSpecs[parent.op];
      parts.add(path[i].inElse ? (spec?.elseLabel ?? '否则') : (spec?.bodyLabel ?? '里面'));
      list = path[i].inElse ? parent.orElse : parent.body;
    }
    parts.add('第 ${path[i].index + 1} 块');
    final index = path[i].index;
    if (index < 0 || index >= list.length) break;
    parent = list[index];
  }
  return parts.join(' › ');
}
