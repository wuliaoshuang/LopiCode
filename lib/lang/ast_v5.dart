part of 'ast.dart';

// 积木第 5 版·核心 1（类型打底）新加的语法树节点。设计：docs/blocks-v5-parts/B-type-system.md 第 2、10 节；
// 交接说明：docs/blocks-v5-parts/B-impl-notes.md。
//
// 只加不改。新节点都挂在三个“第 5 版”的基类下面（[LTypeDecl]、[LStmtV5]、[LExprV5]），老代码里对语法树分情况的地方
// 只多一个分支（版本 1 的文档里不会出现这些节点）；新代码对这三个基类分情况时，编译器照样查“写没写全”。

/// 类型参数（泛型的 T）。
class LTypeParam {
  const LTypeParam(this.name, {this.bound});
  final String name;

  /// 约束：null＝没有；[kBoundComparable]＝能比大小；[kBoundKey]＝能当字典的键；别的＝实现了这个名字的接口。
  final String? bound;
}

/// “能比大小”（整数、小数、文字）。
const String kBoundComparable = 'comparable';

/// “能当字典的键”（第一版只有文字）。
const String kBoundKey = 'key';

/// “是数字”（整数或小数）。只有小库函数的签名用（绝对值、较大、较小）：整数进整数出、小数进小数出；“任意”放进来到运行时再查。
const String kBoundNumeric = 'numeric';

/// 一个带类型的字段（记录的字段、变体某种情况带的东西）。
class LTypedField {
  const LTypedField(this.name, this.type);
  final String name;
  final LType type;
}

// ———————————————————————— 声明 ————————————————————————

/// 类型的声明：记录、枚举、变体、别名。
sealed class LTypeDecl extends LDecl {
  const LTypeDecl({this.isPublic = false, this.codeName, super.src});

  /// 导出给别的模块 / 库用。
  final bool isPublic;

  /// 代码名（拉丁字母开头）：Java 的类型名会变成文件名、Go 的中文名出不了包，导出的类型必须有（GAP-B-1）。
  final String? codeName;
}

/// 记录：起了名字的一组字段。建好以后不能改，要改用“复制并改”（[LRecordCopy]）；相等按内容比。
class LRecordDecl extends LTypeDecl {
  const LRecordDecl(this.name, this.fields, {this.typeParams = const [], super.isPublic, super.codeName, super.src});
  @override
  final String name;
  final List<LTypedField> fields;
  final List<LTypeParam> typeParams;
}

/// 枚举：几个固定名字之一。
class LEnumDecl extends LTypeDecl {
  const LEnumDecl(this.name, this.cases, {super.isPublic, super.codeName, super.src});
  @override
  final String name;
  final List<String> cases;
}

class LVariantCase {
  const LVariantCase(this.name, [this.fields = const []]);
  final String name;
  final List<LTypedField> fields;
}

/// 变体（带标签的联合）：几种情况之一，每种情况带的东西不同。
class LVariantDecl extends LTypeDecl {
  const LVariantDecl(this.name, this.cases, {super.isPublic, super.codeName, super.src});
  @override
  final String name;
  final List<LVariantCase> cases;
}

/// 类型别名：只是另一个名字，不是新类型（Java 里逐处展开，GAP-B-3）。
class LAliasDecl extends LTypeDecl {
  const LAliasDecl(this.name, this.target, {super.isPublic, super.codeName, super.src});
  @override
  final String name;
  final LType target;
}

// ———————————————————————— 语句 ————————————————————————

sealed class LStmtV5 extends LStmt {
  const LStmtV5({super.src});

  /// 直接套在这句里的式子、语句串（给“挨个走一遍”的工具用）。
  List<LExpr> get childExprs;
  List<List<LStmt>> get childBlocks;

  /// 这句自己新建的名字。
  List<String> get binds;
}

class LMatchArm {
  const LMatchArm(this.caseName, this.binds, this.body);

  /// 哪种情况（枚举的名字 / 变体的分支名）。
  final String caseName;

  /// 变体：按顺序接这种情况带的东西（可以比带的少）。枚举：空。
  final List<String> binds;
  final List<LStmt> body;
}

/// “看 (x) 是哪种情况”：x 是枚举或变体。必须每种情况都写到，或者有“其余”（[orElse] 不是 null）。
class LMatch extends LStmtV5 {
  const LMatch(this.subject, this.arms, {this.orElse, super.src});
  final LExpr subject;
  final List<LMatchArm> arms;

  /// “其余”；null＝没写。
  final List<LStmt>? orElse;

  @override
  List<LExpr> get childExprs => [subject];
  @override
  List<List<LStmt>> get childBlocks => [for (final a in arms) a.body, ?orElse];
  @override
  List<String> get binds => [for (final a in arms) ...a.binds];
}

// ———————————————————————— 式子 ————————————————————————

sealed class LExprV5 extends LExpr {
  const LExprV5({super.src});

  /// 直接套在里面的式子。
  List<LExpr> get childExprs;
}

class LFieldInit {
  const LFieldInit(this.name, this.value);
  final String name;
  final LExpr value;
}

/// 新建记录：`新建 用户(名字: …, 年龄: …)`，按字段名对。
class LRecordNew extends LExprV5 {
  const LRecordNew(this.record, this.fields, {super.src});
  final String record;
  final List<LFieldInit> fields;
  @override
  List<LExpr> get childExprs => [for (final f in fields) f.value];
}

/// 复制并改：得到一份新的记录，[fields] 里的字段换成新值。
class LRecordCopy extends LExprV5 {
  const LRecordCopy(this.of, this.fields, {super.src});
  final LExpr of;
  final List<LFieldInit> fields;
  @override
  List<LExpr> get childExprs => [of, for (final f in fields) f.value];
}

/// 枚举的一个值：`灯.红`。
class LEnumValue extends LExprV5 {
  const LEnumValue(this.enumName, this.caseName, {super.src});
  final String enumName;
  final String caseName;
  @override
  List<LExpr> get childExprs => const [];
}

/// 造一个变体的值：`圆(1.5)`。[variant] 是变体的名字。
class LVariantNew extends LExprV5 {
  const LVariantNew(this.variant, this.caseName, this.args, {super.src});
  final String variant;
  final String caseName;
  final List<LExpr> args;
  @override
  List<LExpr> get childExprs => args;
}

/// 当成〈类型〉：运行时检查一次，不对就抛错（设计 B 5.2 第 2 条、第 8 节第 1、2、9 条）。结果的类型就是 [to]。
class LCast extends LExprV5 {
  const LCast(this.x, this.to, {super.src});
  final LExpr x;
  final LType to;
  @override
  List<LExpr> get childExprs => [x];
}

/// 标类型：告诉检查器“这个式子按 [to] 看”（比如把一个列表字面量标成 列表〈任意〉）。放不进去是设计期的错（T01），运行时不多做事。
class LAscribe extends LExprV5 {
  const LAscribe(this.x, this.to, {super.src});
  final LExpr x;
  final LType to;
  @override
  List<LExpr> get childExprs => [x];
}
