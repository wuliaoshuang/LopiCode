/// 表达式（积木参数里“要一个值”的地方放的 JSON 对象 `{"e": "...", ...}`）的读写小工具。
///
/// 表达式直接以 Map 的形式存在积木的 `args` 里（这样读旧文件、存新文件都不用转换，认不出的种类也不会丢）。
/// 坏处是到处都要判断类型，所以集中在这里：读一律先判断类型（不用 `as` 强转，坏数据不许让应用崩），
/// 造一律走工厂函数（字段名只在这一个文件里写一遍）。
/// 约定见 docs/lowcode-v2-design.md。
library;

/// 表达式嵌套最多这么多层。读文件时不限制表达式深度，所以校验和翻代码都要自己封顶，免得坏数据把栈撑爆。
const int kMaxExprDepth = 24;

/// 表达式算出来是什么类型：text / number / bool；说不准（没声明的变量、不认识的表达式）是 any。
abstract final class LcType {
  static const String text = 'text';
  static const String number = 'number';
  static const String boolean = 'bool';
  static const String any = 'any';
}

/// 算术、比较、逻辑三组二元运算符。
const List<String> kArithmeticOps = ['+', '-', '*', '/', '%'];
const List<String> kCompareOps = ['==', '!=', '<', '<=', '>', '>='];
const List<String> kLogicOps = ['and', 'or'];
const List<String> kBinOps = [...kArithmeticOps, ...kCompareOps, ...kLogicOps];

/// 表达式能读控件的哪些属性；积木能改控件的哪些属性。
const List<String> kReadableProps = ['text', 'value', 'visible'];
const List<String> kWritableProps = ['text', 'value', 'visible', 'bg', 'color', 'src', 'placeholder'];

/// 是不是一个表达式对象（是 Map 而且有字符串的 `e`）。
bool isExpr(Object? v) => exprKind(v) != null;

/// 表达式的种类（`e` 字段）；不是表达式返回 null。
String? exprKind(Object? expr) {
  if (expr is! Map) return null;
  final e = expr['e'];
  return e is String && e.isNotEmpty ? e : null;
}

/// 取表达式的某个字段，不管类型。不是 Map 返回 null。
Object? exprField(Object? expr, String key) => expr is Map ? expr[key] : null;

/// 取字符串字段（`var` 的 name、`prop` 的 node / prop、`bin` 的 op、`text` 的 v）；类型不对返回 null。
String? exprString(Object? expr, String key) {
  final v = exprField(expr, key);
  return v is String ? v : null;
}

/// 取数字字段（`num` 的 v）；类型不对返回 null。
num? exprNum(Object? expr, String key) {
  final v = exprField(expr, key);
  return v is num ? v : null;
}

/// 取布尔字段（`bool` 的 v）；类型不对返回 null。
bool? exprBool(Object? expr, String key) {
  final v = exprField(expr, key);
  return v is bool ? v : null;
}

/// 取子表达式（`bin` 的 l / r、`not` 的 x）；那个位置不是表达式返回 null。
/// 返回的就是原来那个 Map（改它等于改原表达式）。
Map<String, dynamic>? exprChild(Object? expr, String key) => asExpr(exprField(expr, key));

/// `join` 的 items：不是数组返回空表；数组里不是表达式的项跳过。
List<Map<String, dynamic>> exprItems(Object? expr) {
  final items = exprField(expr, 'items');
  if (items is! List) return const [];
  return [for (final item in items) ?asExpr(item)];
}

/// 把一个“看起来是表达式”的值收成 `Map<String, dynamic>`；不是表达式返回 null。
/// 已经是这个类型就原样返回，不复制。
Map<String, dynamic>? asExpr(Object? v) {
  if (!isExpr(v)) return null;
  if (v is Map<String, dynamic>) return v;
  if (v is Map) return {for (final e in v.entries) '${e.key}': e.value};
  return null;
}

// —— 工厂 ——

Map<String, dynamic> exText(String v) => {'e': 'text', 'v': v};
Map<String, dynamic> exNum(num v) => {'e': 'num', 'v': v};
Map<String, dynamic> exBool(bool v) => {'e': 'bool', 'v': v};
Map<String, dynamic> exVar(String name) => {'e': 'var', 'name': name};

/// 读控件的属性。`prop`：text / value / visible。
Map<String, dynamic> exProp(String node, String prop) => {'e': 'prop', 'node': node, 'prop': prop};

/// input 事件里＝输入框当前的内容。
Map<String, dynamic> exEvent() => {'e': 'event'};

/// 二元运算。`op` 见 [kBinOps]。
Map<String, dynamic> exBin(String op, Map<String, dynamic> l, Map<String, dynamic> r) => {'e': 'bin', 'op': op, 'l': l, 'r': r};
Map<String, dynamic> exNot(Map<String, dynamic> x) => {'e': 'not', 'x': x};

/// 把几个值拼成一段文字。
Map<String, dynamic> exJoin(List<Map<String, dynamic>> items) => {'e': 'join', 'items': items};

/// 深拷贝一份 JSON 值（Map / List / 字面量）。表达式、积木参数复制时用，免得两块积木共用同一个 Map。
/// 层数超过 [kMaxExprDepth] 的两倍就截成 null（正常数据到不了；防自己套自己的坏数据）。
Object? deepCopyJson(Object? v, [int depth = 0]) {
  if (depth > kMaxExprDepth * 2) return null;
  if (v is Map) return <String, dynamic>{for (final e in v.entries) '${e.key}': deepCopyJson(e.value, depth + 1)};
  if (v is List) return <dynamic>[for (final item in v) deepCopyJson(item, depth + 1)];
  if (v is String || v is num || v is bool) return v;
  return null;
}

/// 深拷贝一个表达式；不是表达式返回 null。
Map<String, dynamic>? copyExpr(Object? expr) {
  if (!isExpr(expr)) return null;
  final copy = deepCopyJson(expr);
  return copy is Map<String, dynamic> ? copy : null;
}

/// 静态推断表达式的类型。`varType` 用来查变量声明的类型（没声明返回 null）。
/// 规则和翻出来的 JavaScript 一致：算术一定是数字，比较 / 逻辑 / not 一定是布尔，join 和读控件文字一定是文本。
String exprType(Object? expr, String? Function(String name) varType) {
  switch (exprKind(expr)) {
    case 'text':
      return LcType.text;
    case 'num':
      return LcType.number;
    case 'bool':
      return LcType.boolean;
    case 'var':
      final name = exprString(expr, 'name');
      return (name == null ? null : varType(name)) ?? LcType.any;
    case 'prop':
      return exprString(expr, 'prop') == 'visible' ? LcType.boolean : LcType.text;
    case 'event' || 'join':
      return LcType.text;
    case 'bin':
      final op = exprString(expr, 'op');
      if (kArithmeticOps.contains(op)) return LcType.number;
      if (kCompareOps.contains(op) || kLogicOps.contains(op)) return LcType.boolean;
      return LcType.any;
    case 'not':
      return LcType.boolean;
    default:
      return LcType.any;
  }
}
