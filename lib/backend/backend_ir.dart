/// 后端积木 → “与语言无关的中间形式”。各语言的生成器（backend_target.dart）只看这个，不直接看积木。
///
/// 思路：**所有运算都是对运行时小库的一次函数调用**（`add(a, b)`、`eq(a, b)`、`dbGet("todos", id)`…），
/// 值一律是 JSON 值（空 / 是否 / 数字 / 文字 / 列表 / 对象）。这样“值的规矩”全写在每种语言的运行时小库里，
/// 翻译这一层没有运算符优先级、没有类型转换的问题；加一种语言＝照 [kBeRuntimeFns] 实现一遍小库，再说清楚几种语句怎么写。
///
/// 任何输入都不抛异常：没填好 / 不认识的地方当成“空”并留一行说明（[BeSNote]），生成的工程照样能启动。
library;

import 'package:lopicode/backend/backend_blocks.dart';
import 'package:lopicode/backend/backend_function.dart';
import 'package:lopicode/backend/backend_ir_types.dart';
import 'package:lopicode/backend/backend_lower_func.dart';
import 'package:lopicode/backend/backend_lower_lang.dart';
import 'package:lopicode/backend/backend_model.dart';
import 'package:lopicode/backend/backend_text.dart';
import 'package:lopicode/lowcode/logic_model.dart';

export 'package:lopicode/backend/backend_ir_types.dart';
export 'package:lopicode/backend/backend_lower_func.dart' show beLangShadow;

/// 变量的初始值（按声明的类型收一遍，内存里的对象可能被改得对不上）。
Object beInitialValue(LcVariable v) {
  final value = v.initial;
  return switch (v.type) {
    'number' => value is num && value.isFinite ? value : 0,
    'bool' => value == true,
    _ => value is String ? value : '',
  };
}

/// 把后端文档翻成中间形式。
BeProgram lowerBackend(BeDocument doc) {
  final skipped = <String>[];
  final routes = <BeRouteProgram>[];
  final names = <String>{};
  for (final r in doc.routes) {
    final title = describeBeRoute(r);
    if (!kBeMethods.contains(r.method)) {
      skipped.add('$title：请求方式不认识');
      continue;
    }
    if (parseBePath(r.path) == null) {
      skipped.add('$title：路径格式不对');
      continue;
    }
    final base = 'route_${r.id.replaceAll(RegExp('[^A-Za-z0-9_]'), '_')}';
    var name = base;
    for (var n = 2; !names.add(name); n++) {
      name = '${base}_$n';
    }
    final lower = _Lowerer(doc, r);
    final body = lower.body();
    routes.add(
      BeRouteProgram(
        id: r.id,
        fnName: name,
        method: r.method,
        path: r.path,
        title: title,
        variables: [
          for (final v in doc.variables)
            if (lower.used.contains(v.name)) v,
        ],
        body: body,
        usesFetch: lower.usesFetch,
      ),
    );
  }
  final collections = <String>[];
  for (final c in doc.collections) {
    if (beNamePattern.hasMatch(c.name) && !collections.contains(c.name)) collections.add(c.name);
  }
  return BeProgram(name: doc.name, port: doc.port >= 1 && doc.port <= 65535 ? doc.port : kBeDefaultPort, collections: collections, routes: routes, skipped: skipped, functions: beLowerFunctions(doc));
}

const Map<String, String> _binFns = {'+': 'add', '-': 'sub', '*': 'mul', '/': 'div', '%': 'mod', '==': 'eq', '!=': 'ne', '<': 'lt', '<=': 'le', '>': 'gt', '>=': 'ge', 'and': 'allOf', 'or': 'anyOf'};

/// 一串积木走新路时用的翻译器（见 backend_lower_lang.dart）；没用到第 4 版积木的接口返回 null。[shadow]＝给校验用的影子模式；[inFunction]＝这一串是函数的定义（一定走新路，看不见文档里的变量）。[all]＝没用到第 4 版积木也走新路（只给规矩版本 2 的类型检查用，不用来生成）。
BeLangLower? beLangLowerOf(BeDocument doc, BeRoute route, {bool shadow = false, bool inFunction = false, bool all = false}) =>
    _Lowerer(doc, route, shadow: shadow, inFunction: inFunction, always: all)._lang;

class _Lowerer implements BeLowerHost {
  _Lowerer(this.doc, this.route, {bool shadow = false, this.inFunction = false, bool always = false}) : _params = bePathParams(route.path).toSet() {
    if (inFunction || always || beBlocksUseLang(route.body)) _lang = BeLangLower(this, route, shadow: shadow);
  }

  final bool inFunction;
  @override
  BeFunction? function(String id) => doc.function(id);

  /// 这个接口用到了第 4 版的积木：整个接口走新路。
  BeLangLower? _lang;

  /// 整个接口的函数体。
  List<BeS> body() {
    final lang = _lang;
    return lang == null ? blocks(route.body, 0) : [BeSLang(lang.stmts(route.body, const [], 0))];
  }

  @override
  bool useDocVar(String name) {
    if (inFunction || doc.variable(name) == null) return false;
    used.add(name);
    return true;
  }

  @override
  List<String> swapNotes(List<String> fresh) {
    final was = _notes;
    _notes = fresh;
    return was;
  }

  @override
  void addNote(String note) => _notes.add(note);

  @override
  List<BeS> leaf(LcBlock b) => _block(b, 0);

  final BeDocument doc;
  final BeRoute route;
  final Set<String> _params;

  /// 用到的变量名。
  final Set<String> used = {};
  bool usesFetch = false;
  int _loops = 0;
  int _slots = 0;

  /// 正在翻的这块积木里“没填好”的说明。
  List<String> _notes = [];

  static const BeX _null = BeXLit(null);

  BeX _hole(String why) {
    _notes.add(why);
    return _null;
  }

  /// 变量名：声明过、名字合规矩才算数。
  String? _varName(Object? name) {
    if (name is! String || !beNamePattern.hasMatch(name)) return null;
    if (inFunction || doc.variable(name) == null) return (_lang?.knows(name) ?? false) ? name : null;
    used.add(name);
    return name;
  }

  String? _collection(Object? name) => name is String && beNamePattern.hasMatch(name) && doc.collection(name) != null ? name : null;

  @override
  BeX expr(Object? e, [int depth = 0]) {
    if (depth >= kMaxExprDepth) return _hole('值套得太深，当成空的');
    final viaLang = _lang?.expr(e, depth);
    if (viaLang != null) return viaLang;
    BeX sub(String key) => expr(exprField(e, key), depth + 1);
    BeX named(String fn, String what) {
      final name = exprString(e, 'name');
      return name == null || name.isEmpty ? _hole('$what没填名字，当成空的') : BeXCall(fn, [const BeXReq(), BeXLit(name)]);
    }

    BeX db(String fn, List<BeX> Function() rest) {
      final c = _collection(exprField(e, 'collection'));
      return c == null ? _hole('集合还没有，当成空的') : BeXCall(fn, [BeXLit(c), ...rest()]);
    }

    final kind = exprKind(e);
    switch (kind) {
      case null:
        return _hole('有一处还没填，当成空的');
      case 'text':
        final v = exprString(e, 'v');
        return v == null ? _hole('文字没填，当成空的') : BeXLit(v);
      case 'num':
        final v = exprNum(e, 'v');
        return v == null || !v.isFinite ? _hole('数字没填，当成空的') : BeXLit(v);
      case 'bool':
        final v = exprBool(e, 'v');
        return v == null ? _hole('“是 / 否”没填，当成空的') : BeXLit(v);
      case 'var':
        final name = _varName(exprField(e, 'name'));
        return name == null ? _hole('读了没有声明的变量，当成空的') : BeXVar(name);
      case 'pathParam':
        final name = exprString(e, 'name');
        if (name != null && name.isNotEmpty && !_params.contains(name)) return _hole('路径里没有叫 $name 的参数，当成空的');
        return named('pathParam', '路径参数');
      case 'query':
        return named('query', '网址参数');
      case 'bodyField':
        return named('bodyField', '请求内容的字段');
      case 'header':
        return named('header', '请求头');
      case 'body':
        return const BeXCall('body', [BeXReq()]);
      case 'dbAll':
        return db('dbAll', () => const []);
      case 'dbCount':
        return db('dbCount', () => const []);
      case 'dbGet':
        return db('dbGet', () => [sub('id')]);
      case 'dbFind':
        final key = exprString(e, 'key');
        if (key == null || key.isEmpty) return _hole('“集合里符合的”没填字段，当成空的');
        return db('dbFind', () => [BeXLit(key), sub('value')]);
      case 'bin':
        final fn = _binFns[exprString(e, 'op')];
        if (fn == null) return _hole('不认识的运算，当成空的');
        return BeXCall(fn, [sub('l'), sub('r')]);
      case 'not':
        return BeXCall('isNot', [sub('x')]);
      case 'join':
        final items = exprField(e, 'items');
        return BeXCall('join', [
          if (items is List)
            for (final item in items) expr(item, depth + 1),
        ]);
      case 'len':
        return BeXCall('size', [sub('x')]);
      case 'isNull':
        return BeXCall('isNull', [sub('x')]);
      case 'now':
        return const BeXCall('now', []);
      case 'obj':
        final fields = exprField(e, 'fields');
        final args = <BeX>[];
        if (fields is List) {
          for (final f in fields) {
            final key = exprKind(f) == 'pair' ? exprString(f, 'key') : null;
            if (key == null || key.isEmpty) {
              _notes.add('对象里有一个字段没填名字，已跳过');
              continue;
            }
            args
              ..add(BeXLit(key))
              ..add(expr(exprField(f, 'value'), depth + 1));
          }
        }
        return BeXCall('obj', args);
      case 'pair':
        return _hole('“一个字段”只能放在“对象”里，当成空的');
      case 'field':
        final key = exprString(e, 'key');
        if (key == null || key.isEmpty) return _hole('“对象的字段”没填字段名，当成空的');
        return BeXCall('field', [sub('of'), BeXLit(key)]);
      default:
        // 新的式子单独出现在旧接口里是不会的（有它就整个走新路）；这里只剩真不认识的。
        return _hole('不认识的值 $kind，当成空的');
    }
  }

  /// 条件：结果已经是布尔的直接用，否则包一层 truthy。
  BeX _cond(Object? e) {
    final x = expr(e);
    return x is BeXCall && kBeBoolFns.contains(x.fn) ? x : BeXCall('truthy', [x]);
  }

  List<BeS> blocks(List<LcBlock> list, int depth) {
    if (list.isEmpty) return const [];
    // 和读文件时的上限一致：再深的存盘后本来也会丢。
    if (depth > LcBlock.maxDepth) return [BeSNote('积木套得太深，这里面的 ${list.length} 块没有翻译')];
    final out = <BeS>[];
    for (var i = 0; i < list.length; i++) {
      final b = list[i];
      final saved = _notes;
      _notes = [];
      final stmts = _block(b, depth);
      out.add(BeSNote(describeBeBlock(b)));
      for (final n in _notes) {
        out.add(BeSNote('（$n）'));
      }
      out.addAll(stmts);
      _notes = saved;
      if (beAlwaysReturns(stmts)) {
        // 后面的不翻译：反正不会执行，而且有的语言（Java）碰到“返回后面还有代码”直接编译不过。
        final rest = list.length - i - 1;
        if (rest > 0) out.add(BeSNote('（前面已经返回了，后面的 $rest 块不会执行，没有翻译）'));
        break;
      }
    }
    return out;
  }

  List<BeS> _skip(String why) {
    _notes.add('已跳过：$why');
    return const [];
  }

  List<BeS> _block(LcBlock b, int depth) {
    BeX arg(String name) => expr(b.args[name]);
    List<BeS> inner(List<LcBlock> list) => blocks(list, depth + 1);

    switch (b.op) {
      case 'respondJson' || 'respondText':
        return [
          BeSReturn(BeXCall(b.op == 'respondJson' ? 'sendJson' : 'sendText', [arg('status'), arg('value')])),
        ];
      case 'dbInsert':
        final c = _collection(b.args['collection']);
        if (c == null) return _skip('集合还没有');
        final call = BeXCall('dbInsert', [BeXLit(c), arg('value')]);
        final into = b.args['into'];
        if (into is! String || into.isEmpty) return [BeSDo(call)];
        final name = _varName(into);
        if (name == null) _notes.add('变量 ${_safe(into)} 没有声明，加好的那条没有存');
        return [name == null ? BeSDo(call) : BeSSet(name, call)];
      case 'dbUpdate':
        final c = _collection(b.args['collection']);
        if (c == null) return _skip('集合还没有');
        return [
          BeSDo(BeXCall('dbUpdate', [BeXLit(c), arg('id'), arg('value')])),
        ];
      case 'dbDelete':
        final c = _collection(b.args['collection']);
        if (c == null) return _skip('集合还没有');
        return [
          BeSDo(BeXCall('dbDelete', [BeXLit(c), arg('id')])),
        ];
      case 'setVar':
        final name = _varName(b.args['name']);
        if (name == null) return _skip('变量没有声明');
        return [BeSSet(name, arg('value'))];
      case 'changeVar':
        final name = _varName(b.args['name']);
        if (name == null) return _skip('变量没有声明');
        return [
          BeSSet(name, BeXCall('add', [BeXVar(name), arg('by')])),
        ];
      case 'if':
        return [BeSIf(_cond(b.args['cond']), inner(b.body), inner(b.orElse))];
      case 'repeat':
        final n = ++_loops;
        return [
          BeSRepeat(n, BeXCall('times', [arg('times')]), inner(b.body)),
        ];
      case 'forEach':
        final name = _varName(b.args['item']);
        if (name == null) return _skip('“这一项放进变量”的变量没有声明');
        final n = ++_loops;
        return [
          BeSForEach(n, BeXCall('items', [arg('list')]), name, inner(b.body)),
        ];
      case 'log':
        return [
          BeSDo(BeXCall('log', [arg('value')])),
        ];
      case 'fetch':
        usesFetch = true;
        final method = b.args['method'] == 'POST' ? 'POST' : 'GET';
        final data = method == 'POST' && isExpr(b.args['data']) ? arg('data') : _null;
        final slot = ++_slots;
        final into = b.args['into'];
        final name = into is String && into.isNotEmpty ? _varName(into) : null;
        if (into is String && into.isNotEmpty && name == null) _notes.add('变量 ${_safe(into)} 没有声明，结果没有存');
        return [
          BeSLet(slot, BeXCall('fetch', [BeXLit(method), arg('url'), data])),
          BeSIf(BeXCall('isNull', [BeXTmp(slot)]), inner(b.orElse), [if (name != null) BeSSet(name, BeXTmp(slot)), ...inner(b.body)]),
        ];
      default:
        return _skip('不认识的积木');
    }
  }

  static String _safe(String s) => s.length > 32 ? '${s.substring(0, 32)}…' : s;
}
