/// 积木第 4 版的“语法树”：和语言无关，五种语言的生成器（gen_*.dart）只吃这棵树。设计稿 docs/blocks-v4-language-design.md 第 4.2 节。
///
/// 纯数据，全部不可变。每个节点带 [LNode.src]（来源：哪一串、哪一块、哪个槽）和 [LNode.type]（**标的**类型，可无；
/// **推断出来的**类型不写在节点上，在 analyze.dart 的结果里按节点查——这样语法树可以是常量）。
///
/// 第 1 阶段生成器支持的：值、变量、运算、流程（见 gen.dart 的能力表）。函数 / 类 / 出错 / 异步这些节点的数据结构先定义在这里，
/// 生成器碰到会抛 `LangUnsupported`（说明是哪一种、第几阶段才有）。
library;

import 'package:lopicode/lang/types.dart';

/// 来源：校验问题、“看代码时点一行跳到积木”都靠它。三项都可以没有（手搭的语法树）。
class LSrc {
  const LSrc({this.script, this.block, this.slot});

  /// 哪一串（接口 id / 事件 id / 函数名）。
  final String? script;

  /// 哪一块积木（积木 id，或它在串里的路径）。
  final String? block;

  /// 哪个槽（参数名）。
  final String? slot;

  @override
  String toString() => [?script, ?block, ?slot].join(' › ');
}

sealed class LNode {
  const LNode({this.src, this.type});
  final LSrc? src;

  /// 标的类型（变量、参数、返回值上可选的小标签）；没标就是 null，按“任意”算。
  final LType? type;
}

/// 名字是哪一种（决定生成时叫什么）。
enum LNameKind {
  /// 用户起的名字（变量、常量、循环变量）：生成时带前缀 `v_`，撞不上任何语言的保留字。
  variable,

  /// 生成器 / 降级用的临时值：生成成 `lcT名字`，用户看不到，不参与名字解析。
  temp,

  /// 宿主给的名字（比如后端接口函数的参数“这次请求” `req`）：原样生成，不参与名字解析。
  host,
}

// ———————————————————————— 声明（模块顶层） ————————————————————————

/// 一个模块＝一个积木文件。
class LModule extends LNode {
  const LModule({this.name = '', this.uses = const [], this.decls = const [], this.body = const [], super.src});
  final String name;

  /// 用上的模块（第 7 阶段）。
  final List<String> uses;
  final List<LDecl> decls;

  /// “启动时”的语句。
  final List<LStmt> body;
}

sealed class LDecl extends LNode {
  const LDecl({super.src, super.type});
  String get name;
}

/// 模块级变量 / 常量。
class LVarDecl extends LDecl {
  const LVarDecl(this.name, this.init, {this.isConst = false, this.isPublic = false, super.src, super.type});
  @override
  final String name;
  final LExpr init;
  final bool isConst;
  final bool isPublic;
}

/// 参数。
class LParam {
  const LParam(this.name, {this.defaultValue, this.type, this.rest = false});
  final String name;

  /// 默认值：只许是直接填的值。
  final LLit? defaultValue;
  final LType? type;

  /// “剩下的全收”（只能是最后一个）。
  final bool rest;
}

/// 函数（第 2 阶段）。[type] 是返回类型标注。
class LFuncDecl extends LDecl {
  const LFuncDecl(this.name, this.params, this.body, {this.isPublic = false, super.src, super.type});
  @override
  final String name;
  final List<LParam> params;
  final List<LStmt> body;
  final bool isPublic;
}

class LFieldDecl {
  const LFieldDecl(this.name, this.init, {this.isPrivate = false, this.isStatic = false, this.type});
  final String name;
  final LExpr init;
  final bool isPrivate;
  final bool isStatic;
  final LType? type;
}

class LMethodDecl {
  const LMethodDecl(this.fn, {this.isStatic = false, this.isAbstract = false});
  final LFuncDecl fn;
  final bool isStatic;
  final bool isAbstract;
}

/// 类（第 5 阶段）。
class LClassDecl extends LDecl {
  const LClassDecl(this.name, {this.parent, this.interfaces = const [], this.fields = const [], this.ctor, this.methods = const [], super.src});
  @override
  final String name;
  final String? parent;
  final List<String> interfaces;
  final List<LFieldDecl> fields;

  /// “创建时”；没有就是什么都不做。
  final LFuncDecl? ctor;
  final List<LMethodDecl> methods;
}

class LSignature {
  const LSignature(this.name, this.params, {this.returns});
  final String name;
  final List<LParam> params;
  final LType? returns;
}

/// 接口（第 5 阶段）。
class LInterfaceDecl extends LDecl {
  const LInterfaceDecl(this.name, this.methods, {super.src});
  @override
  final String name;
  final List<LSignature> methods;
}

/// 宿主 / 原生库提供的函数的签名，没有函数体（第 3 阶段）。
class LNativeDecl extends LDecl {
  const LNativeDecl(this.name, this.params, {super.src, super.type});
  @override
  final String name;
  final List<LParam> params;
}

// ———————————————————————— 语句 ————————————————————————

sealed class LStmt extends LNode {
  const LStmt({super.src, super.type});
}

/// 新建变量 / 常量。没有块级作用域：在哪一层“如果 / 循环”里新建，出了那一层还在；声明提到函数开头。
class LLet extends LStmt {
  const LLet(this.name, this.value, {this.isConst = false, this.kind = LNameKind.variable, super.src, super.type});
  final String name;
  final LExpr value;

  /// 常量：之后不许再赋值（校验 L11 拦；生成的代码里和变量一样）。
  final bool isConst;

  /// [LNameKind.temp]：就地存一个临时值（之后用同名的 [LName] 读），不提声明。
  final LNameKind kind;
}

/// “能赋值的位置”。
sealed class LTarget extends LNode {
  const LTarget({super.src});
}

/// 变量。
class LTName extends LTarget {
  const LTName(this.name, {super.src});
  final String name;
}

/// 列表的某一项 / 字典的某个键。位置不存在（列表）或 [of] 不是列表 / 字典：运行时抛错。
class LTIndex extends LTarget {
  const LTIndex(this.of, this.key, {super.src});
  final LExpr of;
  final LExpr key;
}

/// 对象的字段（第 5 阶段）。
class LTField extends LTarget {
  const LTField(this.of, this.name, {super.src});
  final LExpr of;
  final String name;
}

class LAssign extends LStmt {
  const LAssign(this.target, this.value, {super.src});
  final LTarget target;
  final LExpr value;
}

/// 只为效果算一个式子。
class LExprStmt extends LStmt {
  const LExprStmt(this.expr, {super.src});
  final LExpr expr;
}

class LIfArm {
  const LIfArm(this.cond, this.body);
  final LExpr cond;
  final List<LStmt> body;
}

/// 如果 … 否则如果 … 否则。[arms] 至少一段。“按 (x) 分情况”也是它（见 [lSwitch]）。
class LIf extends LStmt {
  const LIf(this.arms, {this.orElse = const [], super.src});
  final List<LIfArm> arms;
  final List<LStmt> orElse;
}

/// 当 … 时重复；[cond] 是 null＝一直重复。不封顶。
class LWhile extends LStmt {
  const LWhile(this.cond, this.body, {super.src});
  final LExpr? cond;
  final List<LStmt> body;
}

/// [name] 从 [from] 数到 [to]，每次加 [step]。含两头；步长是负数往下数；步长 0 一遍也不做。
/// 三个数在进循环前算好一次；第 k 遍的值是 `from + k × step`（不累加，免得小数越加越偏）。
class LForCount extends LStmt {
  const LForCount(this.name, this.from, this.to, this.step, this.body, {super.src});
  final String name;
  final LExpr from;
  final LExpr to;
  final LExpr step;
  final List<LStmt> body;
}

/// 对列表的每一项。循环中途改列表不影响这一轮；不是列表就一遍也不做。
class LForEach extends LStmt {
  const LForEach(this.list, this.item, this.body, {this.index, this.reuse = false, super.src});
  final LExpr list;
  final String item;

  /// 可选的序号变量（从 0 起）。
  final String? index;

  /// true＝[item] 是一个已有的变量，每一项赋给它（第 3 版后端 `forEach` 的做法）；false＝循环自己的变量。
  final bool reuse;
  final List<LStmt> body;
}

/// 对字典的每一对。键按 Unicode 码点从小到大；循环中途改字典不影响这一轮要走哪些键（值按当时的读）。
class LForPairs extends LStmt {
  const LForPairs(this.dict, this.key, this.value, this.body, {super.src});
  final LExpr dict;
  final String key;
  final String value;
  final List<LStmt> body;
}

/// 重复 N 次（运行时封顶 10000 遍）。
class LRepeat extends LStmt {
  const LRepeat(this.times, this.body, {super.src});
  final LExpr times;
  final List<LStmt> body;
}

class LBreak extends LStmt {
  const LBreak({super.src});
}

class LContinue extends LStmt {
  const LContinue({super.src});
}

/// 返回。[value] 是 null＝什么都不返回。
class LReturn extends LStmt {
  const LReturn(this.value, {super.src});
  final LExpr? value;
}

/// 抛出错误（第 6 阶段）。
class LThrow extends LStmt {
  const LThrow(this.message, {super.src});
  final LExpr message;
}

/// 试着做 / 出错了 / 最后总要（第 6 阶段）。
class LTry extends LStmt {
  const LTry(this.body, {this.errorName, this.errorClass, this.onError = const [], this.finallyBody = const [], super.src});
  final List<LStmt> body;
  final String? errorName;
  final String? errorClass;
  final List<LStmt> onError;
  final List<LStmt> finallyBody;
}

/// 宿主自己的语句：语言核心不懂它，生成时原样交给宿主去写（`LangHost.stmt`），检查时跳过。
/// 后端用它把“返回响应”这种只有后端才有的语句夹在新节点里。
class LHost extends LStmt {
  const LHost(this.payload, {this.returns = false, super.src});
  final Object payload;

  /// 它会不会结束这个函数（“返回响应”会）。
  final bool returns;
}

/// 一行注释（积木的中文读法，或“这里没填好”的说明）。
class LNote extends LStmt {
  const LNote(this.text, {super.src});
  final String text;
}

// ———————————————————————— 式子 ————————————————————————

sealed class LExpr extends LNode {
  const LExpr({super.src, super.type});
}

/// 字面量：null / bool / num（要是有限的数，否则当 0）/ String。
class LLit extends LExpr {
  const LLit(this.value, {super.src});
  final Object? value;
}

class LListLit extends LExpr {
  const LListLit(this.items, {super.src});
  final List<LExpr> items;
}

class LDictEntry {
  const LDictEntry(this.key, this.value);

  /// 键：算出来以后转成文字。
  final LExpr key;
  final LExpr value;
}

/// 字典。键重复时后面的盖掉前面的。
class LDictLit extends LExpr {
  const LDictLit(this.entries, {super.src});
  final List<LDictEntry> entries;
}

/// 读一个名字。
class LName extends LExpr {
  const LName(this.name, {this.kind = LNameKind.variable, super.src});
  final String name;
  final LNameKind kind;
}

/// 对象.字段（第 5 阶段）。
class LField extends LExpr {
  const LField(this.of, this.name, {super.src});
  final LExpr of;
  final String name;
}

/// 列表[位置] / 字典[键] / 文字[第几个字]。读不到得空。
class LIndex extends LExpr {
  const LIndex(this.of, this.key, {super.src});
  final LExpr of;
  final LExpr key;
}

/// 一元运算：`not`（不是）、`neg`（取负）。
class LUnary extends LExpr {
  const LUnary(this.op, this.x, {super.src});
  final String op;
  final LExpr x;
}

/// 二元运算：`+ - * / % **` 和 `== != < <= > >=`。并且 / 或者是 [LLogic]。
class LBinary extends LExpr {
  const LBinary(this.op, this.l, this.r, {super.src});
  final String op;
  final LExpr l;
  final LExpr r;
}

/// 并且（`and`）/ 或者（`or`）：**短路**——前面已经能定结果时后面的不算。结果是“是 / 否”。
class LLogic extends LExpr {
  const LLogic(this.op, this.l, this.r, {super.src});
  final String op;
  final LExpr l;
  final LExpr r;
}

/// 值版的“如果”：只算选中的那一边。
class LCond extends LExpr {
  const LCond(this.cond, this.then, this.orElse, {super.src});
  final LExpr cond;
  final LExpr then;
  final LExpr orElse;
}

/// 调函数（第 2 阶段）。
class LCall extends LExpr {
  const LCall(this.callee, this.args, {super.src});
  final LExpr callee;
  final List<LExpr> args;
}

/// 调方法（第 5 阶段）。
class LSend extends LExpr {
  const LSend(this.obj, this.method, this.args, {super.src});
  final LExpr obj;
  final String method;
  final List<LExpr> args;
}

class LSuperSend extends LExpr {
  const LSuperSend(this.method, this.args, {super.src});
  final String method;
  final List<LExpr> args;
}

class LNew extends LExpr {
  const LNew(this.cls, this.args, {super.src});
  final String cls;
  final List<LExpr> args;
}

class LIsA extends LExpr {
  const LIsA(this.x, this.cls, {super.src});
  final LExpr x;
  final String cls;
}

/// 匿名函数（第 2 阶段）。两种写法：带函数体的（[body]）；只有一个式子的短写法（[expr] 不是 null，这时 [body] 不用）。
class LLambda extends LExpr {
  const LLambda(this.params, this.body, {this.expr, super.src});

  /// 短写法：`(x) → 式子`。
  const LLambda.short(this.params, LExpr this.expr, {super.src}) : body = const [];
  final List<LParam> params;
  final List<LStmt> body;

  /// 短写法的那个式子；带函数体的是 null。
  final LExpr? expr;

  /// 统一成函数体来看：短写法就是“返回 (式子)”。
  List<LStmt> get stmts => expr == null ? body : [LReturn(expr, src: src)];
}

class LThis extends LExpr {
  const LThis({super.src});
}

/// 等（第 6 阶段）。
class LAwait extends LExpr {
  const LAwait(this.x, {super.src});
  final LExpr x;
}

/// 开始做（第 6 阶段）。
class LSpawn extends LExpr {
  const LSpawn(this.body, {super.src});
  final List<LStmt> body;
}

/// 调运行时小库的函数。`fn` 要在 rt.dart 的表里（语言核心的，或宿主登记的）。
class LRt extends LExpr {
  const LRt(this.fn, this.args, {super.src});
  final String fn;
  final List<LExpr> args;
}

/// 调宿主 / 原生库的函数（第 3 阶段）。
class LNative extends LExpr {
  const LNative(this.name, this.args, {super.src});
  final String name;
  final List<LExpr> args;
}
