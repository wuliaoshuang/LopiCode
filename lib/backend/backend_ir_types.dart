/// 后端“与语言无关的中间形式”的数据：几个上限、运行时小库的函数表、式子和语句的类、翻好的接口 / 整份后端。
/// 从 backend_ir.dart 拆出来的（那边只留“怎么翻”，并原样转出这个文件，别处照旧 import backend_ir.dart）。
library;

import 'package:lopicode/lang/ast.dart';
import 'package:lopicode/lang/ast_util.dart';
import 'package:lopicode/lowcode/logic_model.dart';

/// “重复”最多做这么多遍（运行时小库的 `times` 里封顶；各语言必须一致）。
const int kBeRepeatLimit = 10000;

/// 请求内容最多这么多字节，超过回 413。
const int kBeBodyLimit = 1048576;

/// 请求内容的 JSON，列表 / 对象最多套这么多层（`[[1]]` 是两层）；再深的整份当成空。各语言自己的上限差得很远（Python 一千层左右、Go 一万层、Java 看线程的栈），不定死就没法一致。
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

/// 积木第 4 版的式子（lib/lang 的语法树），夹在第 3 版的式子里。做成 [BeXLit] 的子类的原因同 [BeSLang]；[value] 没有用。
class BeXLang extends BeXLit {
  const BeXLang(this.expr) : super(null);
  final LExpr expr;
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

/// 积木第 4 版的语句（lib/lang 的语法树），夹在第 3 版的中间形式里：新积木（当…时重复、从…数到…、跳出循环…）翻成它。
/// 生成时交给 lib/lang 的生成器；里面要再套第 3 版的语句就用 `LHost`（backend_lang.dart 的 `beHostStmts`）。
/// 做成 [BeSNote] 的子类是为了不动 [BeS] 这一组封死的类（别处对它做了穷尽的 switch）；[text] 没有用。
class BeSLang extends BeSNote {
  const BeSLang(this.stmts) : super('');
  final List<LStmt> stmts;
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
    if (s is BeSLang) return lAlwaysReturns(s.stmts);
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
  const BeProgram({required this.name, required this.port, required this.collections, required this.routes, required this.skipped, this.functions = const []});

  final String name;
  final int port;
  final List<String> collections;
  final List<BeRouteProgram> routes;

  /// 没法生成的接口和原因（路径格式不对等），生成器把它们写成注释。
  final List<String> skipped;

  /// 文档级的函数（积木第 4 版·第 2 阶段，“我的积木”）：生成成顶层函数，每个接口里都能调。见 backend_lang.dart 的 `beWithFunctions`。
  final List<LFuncDecl> functions;

  bool get usesFetch => routes.any((r) => r.usesFetch);
}
