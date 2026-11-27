/// 把积木和表达式翻成 JavaScript 的“通用部分”：流程（如果 / 重复 / 等待 / 请求）、运算、类型转换、转义。
///
/// “变量怎么读写、控件属性怎么读写”每种导出不一样（普通网页是 state 对象 + DOM；Vue 是 ref.value；React 是 useState），
/// 所以抽成 [JsTarget] 让各家自己实现，这里只管其余的。普通网页的实现和整份脚本的拼装在 logic_js.dart。
///
/// 安全规矩（有专门的注入测试守着）：
/// - 模型里来的字符串只通过 [jsString] 进脚本；进注释的只通过 [jsComment]。
/// - 变量、控件必须是文档里真有的才翻成代码，否则翻成注释跳过——任何情况下都不抛异常，生成的脚本语法始终正确。
library;

import 'dart:convert';

import 'package:lopicode/lowcode/logic_blocks.dart';
import 'package:lopicode/lowcode/logic_model.dart';
import 'package:lopicode/lowcode/logic_text.dart';
import 'package:lopicode/lowcode/model.dart';

/// “重复”最多做这么多遍，免得填错一个数把页面卡死。
const int kRepeatLimit = 10000;

/// 把任意字符串变成一个 JavaScript 字符串字面量（带双引号）。
///
/// 在 JSON 字面量的基础上多转义三样：`</`（免得脚本内嵌进 HTML 时被 `</script>` 提前截断）、`<!--`（同理），
/// 以及 U+2028 / U+2029（老浏览器把它们当换行，会把字符串字面量截断）。
String jsString(String s) => jsonEncode(s).replaceAll('</', r'<\/').replaceAll('<!--', r'<\!--').replaceAll('\u2028', r'\u2028').replaceAll('\u2029', r'\u2029');

/// 把任意字符串收拾成可以放进注释的内容（`// …` 和 `/* … */` 都安全）：
/// 去掉所有换行类字符（否则后半截会变成代码）、拆开 `*/`（否则块注释提前结束）、拆开 `</` 和 `<!--`，过长截断。
String jsComment(String s, [int limit = 120]) {
  var out = s.replaceAll(RegExp('[\\x00-\\x1f\\x7f\u0085\u2028\u2029]+'), ' ').replaceAll('*/', '* /').replaceAll('</', '< /').replaceAll('<!--', '< !--').trim();
  final runes = out.runes.toList();
  if (runes.length > limit) out = '${String.fromCharCodes(runes.take(limit))}…';
  // 截断可能正好切在 “*” 和 “/” 中间、或拼出新的 “*/”；再保险一次。
  return out.replaceAll('*/', '* /');
}

final RegExp _identifier = RegExp(r'^[A-Za-z_$][A-Za-z0-9_$]*$');

/// 能不能直接写成 `对象.名字`。`__proto__` 虽然合乎写法但会碰到原型，算不能。
bool isJsIdentifier(String s) => _identifier.hasMatch(s) && s != '__proto__';

/// 能当“独立的变量名 / 函数名”用（Vue / React 导出要把页面变量变成真的 JS 变量时用）：
/// 合乎标识符写法，而且不是保留字。
bool isJsBindingName(String s) => isJsIdentifier(s) && !_reserved.contains(s);

const Set<String> _reserved = {
  'break', 'case', 'catch', 'class', 'const', 'continue', 'debugger', 'default', 'delete', 'do', 'else', 'enum', 'export', 'extends', 'false', 'finally', 'for', 'function', 'if', 'import', 'in',
  'instanceof', 'new', 'null', 'return', 'super', 'switch', 'this', 'throw', 'true', 'try', 'typeof', 'var', 'void', 'while', 'with', 'yield', 'let', 'static', 'implements', 'interface', 'package',
  'private', 'protected', 'public', 'await', 'async', 'arguments', 'eval', 'undefined', 'NaN', 'Infinity', //
};

/// 控件 id 能不能拼进选择器（`.n-<id>`）。文档读进来时已经保证了，这里是防内存里被改坏的。
final RegExp _safeNodeId = RegExp(r'^[A-Za-z0-9_]+$');
bool isSafeNodeId(String id) => _safeNodeId.hasMatch(id);

/// 一段翻好的 JavaScript 表达式。
class JsExpr {
  const JsExpr(this.code, this.type, {this.atomic = true});

  final String code;

  /// 静态类型（[LcType]）；用来决定要不要包一层转换。
  final String type;

  /// 是不是“一整块”（字面量、函数调用、属性访问）。不是的话放进别的运算里要加括号。
  final bool atomic;

  /// 可以安全地当运算数用的写法。
  String get wrapped => atomic ? code : '($code)';
}

/// 各种导出自己实现的部分：变量和控件属性怎么读、怎么写。
///
/// 生成的代码里，本文件自己起的名字都以 `lc` 开头（`lcNum`、循环变量 `lcI1`、请求回调的 `lcRes` / `lcBody` / `lcError`），
/// 处理函数的参数叫 `event`。实现里要把页面变量变成真的 JS 变量名的（Vue / React），请避开 `lc` 开头的名字和 `event`。
///
/// 约定：传进来的 `valueJs` 已经转成了合适的类型（变量按声明的类型；控件属性里“是否显示”是布尔，其余是文本）；
/// 返回的语句每行一个元素、不带缩进、自己带分号；不支持的情况返回一行注释（用 [jsComment] 收拾内容）。
abstract class JsTarget {
  const JsTarget();

  /// 读变量的表达式。只会收到文档里声明过的变量。
  String readVar(LcVariable v);

  /// 给变量赋值的语句。
  List<String> writeVar(LcVariable v, String valueJs);

  /// 读控件属性（`prop` 一定在 [kReadableProps] 里，控件一定在页面里、id 一定安全）。
  JsExpr readProp(LcNode node, String prop);

  /// 改控件属性（`prop` 一定在 [kWritableProps] 里）。
  List<String> writeProp(LcNode node, String prop, String valueJs);

  /// “去页面”怎么写。普通网页：每页一个 .html，换地址就行；Vue / React 改地址栏里 # 后面那段，外壳跟着换页（各自覆盖）。
  List<String> goPage(LcDocument doc, LcPage page) => ['location.href = ${jsString('${lcPageFileBase(doc, page.id)}.html')};'];

  /// input 事件里“输入的内容”。处理函数的参数名固定叫 `event`。
  String eventValue() => 'lcEventValue(event)';
}

/// 和导出方式无关的小工具函数（数字 / 文本转换、相等比较、读输入事件的内容）。
/// 翻出来的表达式会用到它们，所以每种导出都要把这段放进生成的文件里。
const String lcJsRuntime = r'''
// 转成数字：输入框里读到的是文字，做加减乘除前要先转。转不了的（空的、不是数字的文字）当 0。
function lcNum(v) {
  const n = typeof v === "string" ? Number(v.trim()) : Number(v);
  return Number.isFinite(n) ? n : 0;
}

// 转成文字。数字去掉浮点误差（0.1 + 0.2 显示成 0.3）。
function lcText(v) {
  if (v === null || v === undefined) return "";
  if (typeof v === "number") return String(Number(v.toPrecision(12)));
  return String(v);
}

// “等于”：类型一样直接比；不一样就都转成文字再比（所以输入框里的 "5" 等于数字 5）。
function lcEq(a, b) {
  return typeof a === typeof b ? a === b : lcText(a) === lcText(b);
}

// 输入事件里，输入框现在的内容。
function lcEventValue(event) {
  const el = event && event.target;
  return el && el.value !== null && el.value !== undefined ? String(el.value) : "";
}
''';

/// 把积木 / 表达式翻成 JavaScript。一个实例翻一份文件（循环变量的编号在实例里累加，保证不重名）。
class JsLogicWriter {
  JsLogicWriter(this.doc, this.target, {this.lookup});

  final LcDocument doc;
  final JsTarget target;

  /// 按名字找变量。平常只找这一页的；用了项目级状态的导出给一个“先找这一页、再找项目级”的（第 5 期）。
  /// 名字怎么找到状态：不给就只认这一页的变量；用了项目级状态的页面给一个“先页面、后项目”的找法。
  final LcVariable? Function(String name)? lookup;
  LcVariable? _variable(String name) => lookup == null ? doc.logic.variable(name) : lookup!(name);
  int _loops = 0;

  /// 翻一个表达式。`event` 是它所在处理的事件（只有 input 里才有“输入的内容”）。
  /// 缺了、坏了、不认识的都翻成 `null /* 原因 */`，不抛异常。
  JsExpr expr(Object? e, {String event = 'load'}) => _expr(e, event, 0);

  /// 翻一串积木，返回一行行代码（最外层不缩进，里面每层两个空格）。
  List<String> blocks(List<LcBlock> list, {String event = 'load'}) => _blocks(list, event, 0);

  // —— 类型转换 ——

  JsExpr toNum(JsExpr e) => e.type == LcType.number ? e : JsExpr('lcNum(${e.code})', LcType.number);
  JsExpr toText(JsExpr e) => e.type == LcType.text ? e : JsExpr('lcText(${e.code})', LcType.text);
  JsExpr toBool(JsExpr e) => e.type == LcType.boolean ? e : JsExpr('!!${e.wrapped}', LcType.boolean);
  JsExpr coerce(JsExpr e, String type) => switch (type) {
    LcType.number => toNum(e),
    LcType.boolean => toBool(e),
    LcType.text => toText(e),
    _ => e,
  };

  JsExpr _hole(String why) => JsExpr('null /* ${jsComment(why)} */', LcType.any);

  JsExpr _expr(Object? e, String event, int depth) {
    if (depth >= kMaxExprDepth) return _hole('值套得太深，这里当成空的');
    final kind = exprKind(e);
    switch (kind) {
      case null:
        return _hole('这里还没填');
      case 'text':
        final v = exprString(e, 'v');
        return v == null ? _hole('文字没填') : JsExpr(jsString(v), LcType.text);
      case 'num':
        final v = exprNum(e, 'v');
        if (v == null || !v.isFinite) return _hole('数字没填');
        return JsExpr(_numLiteral(v), LcType.number, atomic: v >= 0);
      case 'bool':
        final v = exprBool(e, 'v');
        return v == null ? _hole('“是 / 否”没填') : JsExpr('$v', LcType.boolean);
      case 'var':
        final name = exprString(e, 'name');
        final v = name == null ? null : _variable(name);
        return v == null ? _hole('没有声明的变量 ${name ?? ''}') : JsExpr(target.readVar(v), LcVariable.types.contains(v.type) && !v.isDerived ? v.type : LcType.any);
      case 'prop':
        final id = exprString(e, 'node');
        final prop = exprString(e, 'prop');
        final node = id == null ? null : doc.find(id);
        if (node == null || !isSafeNodeId(node.id)) return _hole('找不到控件');
        if (prop == null || !kReadableProps.contains(prop)) return _hole('不认识的属性 ${prop ?? ''}');
        return target.readProp(node, prop);
      case 'event':
        if (event != 'input') return JsExpr('"" /* ${jsComment('只有“输入内容变化时”才有输入的内容')} */', LcType.text);
        return JsExpr(target.eventValue(), LcType.text);
      case 'bin':
        return _bin(e, event, depth);
      case 'not':
        // JavaScript 的 ! 自己会按“真假”来看，不用先转布尔。
        return JsExpr('!${_expr(exprField(e, 'x'), event, depth + 1).wrapped}', LcType.boolean);
      case 'join':
        final items = exprField(e, 'items');
        final parts = [
          if (items is List)
            for (final item in items) toText(_expr(item, event, depth + 1)),
        ];
        if (parts.isEmpty) return const JsExpr('""', LcType.text);
        if (parts.length == 1) return parts.single;
        return JsExpr([for (final p in parts) p.wrapped].join(' + '), LcType.text, atomic: false);
      default:
        return _hole('不认识的值 $kind');
    }
  }

  JsExpr _bin(Object? e, String event, int depth) {
    final op = exprString(e, 'op');
    final l = _expr(exprField(e, 'l'), event, depth + 1);
    final r = _expr(exprField(e, 'r'), event, depth + 1);
    if (kArithmeticOps.contains(op)) {
      // 算术一律按数字算（“+”不拼字符串，拼字符串用 join）：不是数字的先过 lcNum。
      final code = '${toNum(l).wrapped} $op ${toNum(r).wrapped}';
      // 除法和取余可能得到“无穷大 / 不是数”（除以 0），一旦存进变量后面就全算不对了，所以再过一遍 lcNum 收成 0。
      if (op == '/' || op == '%') return JsExpr('lcNum($code)', LcType.number);
      return JsExpr(code, LcType.number, atomic: false);
    }
    switch (op) {
      case '<' || '<=' || '>' || '>=':
        return JsExpr('${toNum(l).wrapped} $op ${toNum(r).wrapped}', LcType.boolean, atomic: false);
      case '==' || '!=':
        // 两边类型确定而且一样，直接用 ===；否则走 lcEq（会把数字和文字拉平了比）。
        if (l.type == r.type && l.type != LcType.any) {
          return JsExpr('${l.wrapped} ${op == '==' ? '===' : '!=='} ${r.wrapped}', LcType.boolean, atomic: false);
        }
        return JsExpr('${op == '==' ? '' : '!'}lcEq(${l.code}, ${r.code})', LcType.boolean);
      case 'and' || 'or':
        return JsExpr('${toBool(l).wrapped} ${op == 'and' ? '&&' : '||'} ${toBool(r).wrapped}', LcType.boolean, atomic: false);
      default:
        return _hole('不认识的运算 ${op ?? ''}');
    }
  }

  static String _numLiteral(num v) => v is int || (v == v.roundToDouble() && v.abs() < 1e15) ? '${v.round()}' : '$v';

  List<String> _skip(LcBlock b, String why) => ['// 跳过「${jsComment(describeBlock(b, doc), 80)}」：${jsComment(why)}'];

  List<String> _indent(List<String> lines) => [for (final l in lines) '  $l'];

  List<String> _blocks(List<LcBlock> list, String event, int depth) {
    if (list.isEmpty) return const [];
    // 和读文件时的上限一致：再深的存盘后本来也会丢。
    if (depth > LcBlock.maxDepth) return ['// 积木套得太深，这里面的 ${list.length} 块没有翻译'];
    return [for (final b in list) ..._block(b, event, depth)];
  }

  List<String> _block(LcBlock b, String event, int depth) {
    JsExpr arg(String name) => _expr(b.args[name], event, 0);
    List<String> inner(List<LcBlock> list) => _indent(_blocks(list, event, depth + 1));
    LcVariable? variable(String key) {
      final name = b.args[key];
      return name is String ? _variable(name) : null;
    }

    switch (b.op) {
      case 'setVar':
        final v = variable('name');
        if (v == null) return _skip(b, '变量没有声明');
        return target.writeVar(v, coerce(arg('value'), v.type).code);
      case 'changeVar':
        final v = variable('name');
        if (v == null) return _skip(b, '变量没有声明');
        if (v.type != 'number') return _skip(b, '这个变量不是数字');
        return target.writeVar(v, '${target.readVar(v)} + ${toNum(arg('by')).wrapped}');
      case 'setProp':
        final id = b.args['node'];
        final prop = b.args['prop'];
        final node = id is String ? doc.find(id) : null;
        if (node == null || !isSafeNodeId(node.id)) return _skip(b, '找不到控件');
        if (prop is! String || !kWritableProps.contains(prop)) return _skip(b, '不认识的属性');
        return target.writeProp(node, prop, coerce(arg('value'), prop == 'visible' ? LcType.boolean : LcType.text).code);
      case 'if':
        return [
          'if (${arg('cond').code}) {',
          ...inner(b.body),
          if (b.orElse.isNotEmpty) ...['} else {', ...inner(b.orElse)],
          '}',
        ];
      case 'repeat':
        final n = ++_loops;
        return ['for (let lcI$n = 0, lcN$n = Math.min(${toNum(arg('times')).code}, $kRepeatLimit); lcI$n < lcN$n; lcI$n++) {', ...inner(b.body), '}'];
      case 'wait':
        // 简化：只有“然后”里面的积木会等；排在这块后面的积木不等，马上接着做。
        return ['setTimeout(function () {', ...inner(b.body), '}, Math.max(0, ${toNum(arg('ms')).code}));'];
      case 'alert':
        return ['alert(${toText(arg('message')).code});'];
      case 'navigate':
        return ['location.href = ${toText(arg('url')).code};'];
      case kLcGoPageOp:
        final id = b.args['page'];
        final page = id is String ? doc.pageById(id) : null;
        if (page == null) return _skip(b, '要去的页面已经不在了');
        return target.goPage(doc, page);
      case 'log':
        return ['console.log(${arg('value').code});'];
      case 'fetch':
        return _fetch(b, event, depth);
      default:
        return ['// 不认识的积木：${jsComment(b.op, 60)}（已跳过）'];
    }
  }

  List<String> _fetch(LcBlock b, String event, int depth) {
    final url = toText(_expr(b.args['url'], event, 0)).code;
    final method = b.args['method'] == 'POST' ? 'POST' : 'GET';
    final into = b.args['into'];
    final v = into is String && into.isNotEmpty ? _variable(into) : null;
    final store = v != null ? target.writeVar(v, coerce(const JsExpr('lcBody', LcType.text), v.type).code) : [if (into is String && into.isNotEmpty) '// ${jsComment('变量 $into 没有声明，结果没有存')}'];
    List<String> inner(List<LcBlock> list) => _indent(_indent(_blocks(list, event, depth + 1)));
    // 用 then 的两个参数分开“成功 / 失败”：这样“成功后”里的积木自己出错，不会再跑一遍“失败后”。
    return [
      'fetch($url, { method: "$method" })',
      '  .then(function (lcRes) {',
      '    if (!lcRes.ok) throw new Error("HTTP " + lcRes.status);',
      '    return lcRes.text();',
      '  })',
      '  .then(function (lcBody) {',
      ..._indent(_indent(store)),
      ...inner(b.body),
      '  }, function (lcError) {',
      ...inner(b.orElse),
      '  });',
    ];
  }
}

/// 翻一个表达式（一次性用法；要翻很多就自己建一个 [JsLogicWriter]）。
String exprToJs(Object? expr, JsTarget target, {required LcDocument doc, String event = 'load'}) => JsLogicWriter(doc, target).expr(expr, event: event).code;

/// 翻一串积木，返回多行文本。`indent` 是整体往右缩几层（每层两个空格）。
/// 注意：分开调用多次时“重复”的循环变量会重名（都从 lcI1 开始）；放在不同函数里没关系，要放进同一个函数请共用一个 [JsLogicWriter]。
String blocksToJs(List<LcBlock> blocks, JsTarget target, {required LcDocument doc, String event = 'load', int indent = 0}) {
  final pad = '  ' * indent;
  return [for (final l in JsLogicWriter(doc, target).blocks(blocks, event: event)) '$pad$l'].join('\n');
}

/// 每个处理对应的函数名（和 `doc.logic.handlers` 一一对应）：`onClick_n3_h1`、`onInput_n5_h2`、`onLoad_h3`。
/// 名字里只留字母、数字、下划线；万一重了在后面加序号。
List<String> logicHandlerNames(LcDocument doc) {
  final used = <String>{};
  String clean(String s) => s.replaceAll(RegExp('[^A-Za-z0-9_]'), '_');
  return [
    for (final h in doc.logic.handlers)
      () {
        final event = clean(h.event);
        final head = 'on${event.isEmpty ? 'Event' : event[0].toUpperCase() + event.substring(1)}';
        final target = h.target;
        final base = [head, if (h.event != 'load' && target != null && target.isNotEmpty) clean(target), clean(h.id)].join('_');
        var name = base;
        for (var n = 2; !used.add(name); n++) {
          name = '${base}_$n';
        }
        return name;
      }(),
  ];
}
