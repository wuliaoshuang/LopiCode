/// 后端积木 → “与语言无关的中间形式”。各语言的生成器（backend_target.dart）只看这个，不直接看积木。
///
/// 思路：**所有运算都是对运行时小库的一次函数调用**（`add(a, b)`、`eq(a, b)`、`dbGet("todos", id)`…），
/// 值一律是 JSON 值（空 / 是否 / 数字 / 文字 / 列表 / 对象）。这样“值的规矩”全写在每种语言的运行时小库里，
/// 翻译这一层没有运算符优先级、没有类型转换的问题；加一种语言＝照 [kBeRuntimeFns] 实现一遍小库，再说清楚几种语句怎么写。
///
/// 任何输入都不抛异常：没填好 / 不认识的地方当成“空”并留一行说明（[BeSNote]），生成的工程照样能启动。
library;

import 'package:lopicode/backend/backend_blocks.dart';
import 'package:lopicode/backend/backend_model.dart';
import 'package:lopicode/backend/backend_text.dart';
import 'package:lopicode/lowcode/logic_model.dart';

/// “重复”最多做这么多遍（运行时小库的 `times` 里封顶；各语言必须一致）。
const int kBeRepeatLimit = 10000;

/// 请求内容最多这么多字节，超过回 413。
const int kBeBodyLimit = 1048576;

/// 请求内容的 JSON，列表 / 对象最多套这么多层（`[[1]]` 是两层）；再深的整份当成空。
/// 定这一条是因为各语言自己的上限差得很远（Python 一千层左右、Go 一万层、Java 看线程的栈有多大），不定死就没法一致。
const int kBeJsonDepthLimit = 64;

/// “请求别的网址”最多等这么多秒。
const int kBeFetchTimeoutSeconds = 10;

/// 运行时小库必须提供的函数：名字 → 参数与规矩。每种语言都要实现这张表里的每一个（`test/support/backend_conformance.dart`
/// 会检查有没有漏），名字可以按语言习惯改写（由生成器的 `call` 决定），**行为必须逐字节一致**。
///
/// 说明里的“数字化”＝数字原样；文字去掉两头的空格 / 制表 / 换行后是十进制数（`-1.5`、`.5`、`1e3`）就取它，否则 0；
/// 是→1、否→0；其余（空、列表、对象）→0；结果不是有限的数也当 0。
/// “文字化”＝空→空文字；是 / 否→`true` / `false`；数字按“数字的写法”；文字原样；列表 / 对象→它的 JSON。
/// “数字的写法”＝整数且绝对值小于 1e15 → 不带小数点；否则保留 12 位有效数字（正好一半时远离 0）、去掉末尾的 0，
/// 指数在 -7 到 14 之间写成普通小数，其余写成 `1.5e-10`、`1e21`（指数不带加号、不补 0）。
/// “JSON”＝对象的键按 Unicode 码点从小到大排；数字按“数字的写法”；文字只转义 `"`、`\`、U+0000–U+001F（`\b \f \n \r \t`，其余 `\u00xx` 小写）；
/// 不加空格；UTF-8。
const Map<String, String> kBeRuntimeFns = {
  'add': '(a, b) → 数字：两边数字化后相加；结果不是有限的数 → 0',
  'sub': '(a, b) → 数字：相减，规矩同 add',
  'mul': '(a, b) → 数字：相乘，规矩同 add',
  'div': '(a, b) → 数字：相除；除以 0 → 0',
  'mod': '(a, b) → 数字：取余，符号跟被除数（-7 余 3 是 -1）；除以 0 → 0',
  'eq': '(a, b) → 是否：类型一样直接比（列表 / 对象比 JSON）；不一样就都文字化再比',
  'ne': '(a, b) → 是否：eq 取反',
  'lt': '(a, b) → 是否：两边数字化后 a < b',
  'le': '(a, b) → 是否：a <= b',
  'gt': '(a, b) → 是否：a > b',
  'ge': '(a, b) → 是否：a >= b',
  'allOf': '(a, b) → 是否：两边都算“是”',
  'anyOf': '(a, b) → 是否：至少一边算“是”',
  'isNot': '(x) → 是否：x 不算“是”',
  'truthy': '(x) → 语言自己的布尔：空、否、0、空文字算“否”，其余（含空列表、空对象）算“是”',
  'join': '(...项) → 文字：每项文字化后连起来',
  'size': '(x) → 数字：列表的项数 / 文字的字数（按 Unicode 码点）/ 对象的字段数；其余 0',
  'isNull': '(x) → 是否：x 是空',
  'obj': '(键1, 值1, 键2, 值2, …) → 对象；键重复时后面的盖掉前面的',
  'field': '(对象, 键) → 那个字段的值；不是对象或没有这个字段 → 空',
  'pathParam': '(请求, 名字) → 路径里 :名字 那一段（已做百分号解码）；没有 → 空',
  'query': '(请求, 名字) → 网址参数（+ 当空格、做百分号解码；重名取第一个）；没带 → 空',
  'bodyField': '(请求, 名字) → field(body(请求), 名字)',
  'body': '(请求) → 请求内容按 JSON 解出来的值；没有内容、不是合法 UTF-8、不是合法 JSON、列表 / 对象套了超过 $kBeJsonDepthLimit 层 → 空',
  'header': '(请求, 名字) → 请求头的值（名字不分大小写）；没带 → 空',
  'dbAll': '(集合名) → 列表：全部记录，按加入的顺序',
  'dbGet': '(集合名, id) → id 数字化后等于它的那条；找不到 → 空',
  'dbFind': '(集合名, 键, 值) → 列表：eq(field(记录, 键), 值) 的那些',
  'dbCount': '(集合名) → 数字：有几条',
  'dbInsert': '(集合名, 值) → 新记录：值是对象就拷它的字段（不是就当空对象），id 设成下一个号（从 1 起，删了也不回收）',
  'dbUpdate': '(集合名, id, 值) → 改好的记录或空：把值（对象）的字段盖到那条上，id 不许改；找不到 / 值不是对象 → 不动',
  'dbDelete': '(集合名, id) → 是否删了',
  'now': '() → 文字：现在的世界标准时间，形如 2026-11-24T06:00:00Z',
  'log': '(x) → 无：把 x 文字化后写一行到标准输出',
  'times': '(x) → 语言自己的整数：数字化后去掉小数部分，夹在 0 到 $kBeRepeatLimit 之间',
  'items': '(x) → 语言自己的列表：x 是列表就是它（循环中途集合变了不影响这一轮），否则空列表',
  'sendJson': '(状态, 值) → 响应：状态数字化取整，不在 200–599 里当 200；内容是值的 JSON，application/json; charset=utf-8；204 / 304 不带内容',
  'sendText': '(状态, 值) → 响应：内容是值的文字化，text/plain; charset=utf-8；其余同 sendJson',
  'fetch':
      '(方式, 网址, 数据) → 文字或空：只许 http / https，主机那一段带 @（用户名密码）的不请求；网址里字母数字和 -._~:/?#[]@!\$&\'()*+,;= 之外的字符、'
      '后面不是两位十六进制的 % 先按 UTF-8 做百分号转义；POST 且数据不是空时把它的 JSON 当请求内容；最多等 $kBeFetchTimeoutSeconds 秒；2xx 返回响应文字（按 UTF-8 读，坏的地方换成 U+FFFD，开头的 BOM 去掉一个），其余一律空',
};

/// 返回“语言自己的布尔”或“是否”值的函数：它们的结果可以直接放进 if 的条件，不用再包一层 truthy。
/// （静态类型的语言里，这些函数应当声明成返回 bool。）
const Set<String> kBeBoolFns = {'eq', 'ne', 'lt', 'le', 'gt', 'ge', 'allOf', 'anyOf', 'isNot', 'truthy', 'isNull'};

// —— 表达式 ——

sealed class BeX {
  const BeX();
}

/// 字面量：null / bool / num（一定是有限的数）/ String。
class BeXLit extends BeX {
  const BeXLit(this.value);
  final Object? value;
}

/// 读变量（一定是这个接口用到、已声明的变量）。
class BeXVar extends BeX {
  const BeXVar(this.name);
  final String name;
}

/// 读临时值（[BeSLet] 存的）。
class BeXTmp extends BeX {
  const BeXTmp(this.slot);
  final int slot;
}

/// “这次请求”本身（传给 pathParam / query 等函数）。
class BeXReq extends BeX {
  const BeXReq();
}

/// 调运行时小库的函数。`fn` 一定在 [kBeRuntimeFns] 里。
class BeXCall extends BeX {
  const BeXCall(this.fn, this.args);
  final String fn;
  final List<BeX> args;
}

// —— 语句 ——

sealed class BeS {
  const BeS();
}

/// 一行注释（积木的中文读法，或“这里没填好”的说明）。
class BeSNote extends BeS {
  const BeSNote(this.text);
  final String text;
}

/// 给变量赋值。
class BeSSet extends BeS {
  const BeSSet(this.name, this.value);
  final String name;
  final BeX value;
}

/// 存一个临时值（之后用 [BeXTmp] 读；每个 slot 在一个接口里只存一次）。
class BeSLet extends BeS {
  const BeSLet(this.slot, this.value);
  final int slot;
  final BeX value;
}

/// 只为了效果调一次函数（dbUpdate、log…），结果不要。
class BeSDo extends BeS {
  const BeSDo(this.call);
  final BeXCall call;
}

/// `cond` 一定是返回布尔的调用（[kBeBoolFns]）。
class BeSIf extends BeS {
  const BeSIf(this.cond, this.then, this.orElse);
  final BeX cond;
  final List<BeS> then;
  final List<BeS> orElse;
}

/// 重复 `times` 次（`times` 一定是 `times(...)` 调用，结果是整数）。`n` 是这个循环在接口里的编号（给循环变量起名用）。
class BeSRepeat extends BeS {
  const BeSRepeat(this.n, this.times, this.body);
  final int n;
  final BeX times;
  final List<BeS> body;
}

/// 对列表里的每一项：先把它赋给变量 `item`，再做 `body`（`list` 一定是 `items(...)` 调用）。
class BeSForEach extends BeS {
  const BeSForEach(this.n, this.list, this.item, this.body);
  final int n;
  final BeX list;
  final String item;
  final List<BeS> body;
}

/// 这一串语句是不是“怎么走都会返回”（最后一句是返回，或者是两边都一定返回的“如果”）。
/// 生成器用它决定函数末尾要不要补一句“什么都不返回”（静态类型的语言需要）。循环不算：可能一遍都不做。
bool beAlwaysReturns(List<BeS> list) {
  for (final s in list.reversed) {
    if (s is BeSNote) continue;
    if (s is BeSReturn) return true;
    return s is BeSIf && beAlwaysReturns(s.then) && beAlwaysReturns(s.orElse);
  }
  return false;
}

/// 返回响应并结束这个接口（`response` 一定是 sendJson / sendText 调用）。
class BeSReturn extends BeS {
  const BeSReturn(this.response);
  final BeXCall response;
}

/// 一个接口翻好的样子。
class BeRouteProgram {
  const BeRouteProgram({required this.id, required this.fnName, required this.method, required this.path, required this.title, required this.variables, required this.body, required this.usesFetch});

  final String id;

  /// 处理函数的名字：`route_<id>`，只含字母、数字、下划线，整份里不重名。
  final String fnName;
  final String method;
  final String path;

  /// “GET /todos/:id”。
  final String title;

  /// 这个接口用到的变量（按声明顺序）；每次请求开始时设成初始值。
  final List<LcVariable> variables;
  final List<BeS> body;

  /// 里面有没有“请求别的网址”（有的语言要据此把函数写成异步的）。
  final bool usesFetch;
}

/// 整份后端翻好的样子。
class BeProgram {
  const BeProgram({required this.name, required this.port, required this.collections, required this.routes, required this.skipped});

  final String name;
  final int port;
  final List<String> collections;
  final List<BeRouteProgram> routes;

  /// 没法生成的接口和原因（路径格式不对等），生成器把它们写成注释。
  final List<String> skipped;

  bool get usesFetch => routes.any((r) => r.usesFetch);
}

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
    final body = lower.blocks(r.body, 0);
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
  return BeProgram(name: doc.name, port: doc.port >= 1 && doc.port <= 65535 ? doc.port : kBeDefaultPort, collections: collections, routes: routes, skipped: skipped);
}

const Map<String, String> _binFns = {'+': 'add', '-': 'sub', '*': 'mul', '/': 'div', '%': 'mod', '==': 'eq', '!=': 'ne', '<': 'lt', '<=': 'le', '>': 'gt', '>=': 'ge', 'and': 'allOf', 'or': 'anyOf'};

class _Lowerer {
  _Lowerer(this.doc, this.route) : _params = bePathParams(route.path).toSet();

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
    if (name is! String || !beNamePattern.hasMatch(name) || doc.variable(name) == null) return null;
    used.add(name);
    return name;
  }

  String? _collection(Object? name) => name is String && beNamePattern.hasMatch(name) && doc.collection(name) != null ? name : null;

  BeX expr(Object? e, [int depth = 0]) {
    if (depth >= kMaxExprDepth) return _hole('值套得太深，当成空的');
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
