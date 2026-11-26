/// 规矩版本 2 的类型检查“说出来的东西”：规则表、问题、一键修、运行时检查点、边界上的转换。纯数据，界面和生成器都从这里拿。
///
/// 设计：docs/blocks-v5-parts/B-type-system.md 第 5.2、6.2、6.4、8、10.4 节。交接说明：docs/blocks-v5-parts/B-impl-notes.md。
library;

import 'package:lopicode/lang/ast.dart';
import 'package:lopicode/lang/types.dart';

enum LTypeLevel {
  /// 错：不让生成、不让运行。
  error,

  /// 警告：能生成，多半不是想要的。
  warning,

  /// 提醒：不是错。
  hint,
}

class LTypeRule {
  const LTypeRule(this.code, this.title, this.level, this.advice);
  final String code;

  /// 一句话说这条规则报什么。
  final String title;
  final LTypeLevel level;

  /// 默认的“怎么改”。
  final String advice;
}

/// 类型规则表（T 开头）。级别是规矩版本 2 里的级别。
const Map<String, LTypeRule> kTypeRules = {
  'T01': LTypeRule('T01', '这里要一种东西，放进来的是另一种', LTypeLevel.error, '换成要的那种，或者用“变成文字”“取整”这类积木转一下'),
  'T02': LTypeRule('T02', '可能是空，没判断就用了', LTypeLevel.error, '先用“如果 … 不是空”判断，或者包一层“是空就用 …”'),
  'T03': LTypeRule('T03', '“看是哪种情况”没写全', LTypeLevel.error, '把少的情况补上，或者加一个“其余”'),
  'T04': LTypeRule('T04', '新建记录缺了字段，或者多了没有的字段', LTypeLevel.error, '把缺的字段补上；多出来的删掉'),
  'T05': LTypeRule('T05', '泛型要求的条件不满足（比如要能比大小）', LTypeLevel.error, '换成满足条件的东西，或者在类型变量上说明“能比大小”'),
  'T06': LTypeRule('T06', '运算的两边不对（要数字，或者两边要同一种）', LTypeLevel.error, '把两边换成数字；数字和文字不能混着算、混着比'),
  'T07': LTypeRule('T07', '参数的个数不对', LTypeLevel.error, '照这个函数要的个数给'),
  'T08': LTypeRule('T08', '没有这个名字（变量、字段、方法、情况）', LTypeLevel.error, '检查名字有没有写错，或者先把它建出来'),
  'T09': LTypeRule('T09', '条件这里要“是/否”', LTypeLevel.error, '换成一个比较（比如 … ≠ 0）或者“是/否”的值'),
  'T10': LTypeRule('T10', '记录建好以后不能改', LTypeLevel.error, '用“复制并改”得到一份新的'),
  'T11': LTypeRule('T11', '说自己实现了接口，但方法没有实现全', LTypeLevel.error, '把接口要的方法补上，返回的东西要对得上'),
  'T12': LTypeRule('T12', '看不出里面放什么，先当成“任意”', LTypeLevel.hint, '给它标一下类型，或者往里放一个东西'),
  'T13': LTypeRule('T13', '给别人用的函数 / 类型没有标全', LTypeLevel.warning, '把参数和返回值的类型都标上，别人用的时候才有提示'),
  'T14': LTypeRule('T14', '往“任意”里的列表 / 字典加东西，改不到原来那份', LTypeLevel.warning, '直接改原来那个列表 / 字典，或者改完以后再放回去'),
  'T15': LTypeRule('T15', '这个“当成 …”永远不会成功', LTypeLevel.error, '换成它真的可能是的类型'),
  'T16': LTypeRule('T16', '整数写得太大了', LTypeLevel.error, '整数最大只能到 9007199254740991；更大的用小数'),
  'T17': LTypeRule('T17', '继承了一个没勾“可以被继承”的类', LTypeLevel.error, '在父类上勾“可以被继承”，或者不要继承它'),
  'T18': LTypeRule('T18', '重写的方法和父类的对不上', LTypeLevel.error, '参数的个数、类型和返回的东西要和父类的一样'),
};

/// 一键修的种类（界面层据此出按钮、改积木；这里只出数据）。设计 6.2 的七种＋几种顺手能给的。
enum LFixKind {
  /// 外面包一层“变成文字”。
  wrapToText,

  /// 外面包一层“取整”。
  wrapToInt,

  /// 外面包一层“变成整数（变不了就是空）”；之后还要处理空。
  wrapParseInt,

  /// 外面包一层“是空就用 ▢”。
  wrapOrElse,

  /// 外面包一层“一定不是空”（是空就在运行时报错）。
  wrapMust,

  /// 换成“▢ ≠ 0”。
  compareNotZero,

  /// “看是哪种情况”：把缺的情况补上（空的）。参数 `cases`。
  addMatchCases,

  /// “看是哪种情况”：加一个“其余”。
  addMatchElse,

  /// 新建记录：把缺的字段补上（空槽）。参数 `fields`。
  addRecordFields,

  /// 新建记录 / 复制并改：删掉记录里没有的那个字段。参数 `field`。
  removeRecordField,

  /// 改记录的字段 → 换成“复制并改”。参数 `field`。
  useRecordCopy,
}

class LFix {
  const LFix(this.kind, this.label, {this.target, this.params = const {}});
  final LFixKind kind;

  /// 按钮上的字。
  final String label;

  /// 对哪个节点下手（要包起来的式子、要补情况的“看是哪种情况”…）；它的 `src` 就是哪块积木哪个槽。
  final LNode? target;

  /// 参数（`cases` / `fields`：名字的列表；`field`：名字；`want`：要的类型的写法）。
  final Map<String, Object> params;

  @override
  String toString() => '${kind.name}${params.isEmpty ? '' : params}';
}

class LTypeIssue {
  const LTypeIssue(this.code, this.where, this.message, {required this.level, this.node, this.src, this.argIndex, this.fixes = const []});

  /// 规则号（T01…）。
  final String code;

  /// 在哪个函数里：“主”、函数名、“类.方法”、类名。
  final String where;

  /// 提示语原文。
  final String message;
  final LTypeLevel level;

  /// 出错的那个节点（式子或语句）。
  final LNode? node;

  /// 哪块积木哪个槽：[node] 自己带的位置；它没带就是包着它的那句的位置。
  final LSrc? src;

  /// 是调用的第几个参数（从 0 数）；不是参数的事＝null。
  final int? argIndex;
  final List<LFix> fixes;

  bool get isError => level == LTypeLevel.error;
  LTypeRule get rule => kTypeRules[code]!;

  /// 和推断原型打印的格式一样：`T01 主：「重复」的第 2 个参数要整数，放进来的是文字`。
  @override
  String toString() => '$code $where：$message';
}

/// 必须在运行时检查的 9 种地方（设计第 8 节，编号一致）。
enum LCheckKind {
  /// 1 任意 → 整数 / 小数 / 文字 / 是否 / 列表〈任意〉/ 字典〈任意〉/ 有名字的类型。
  anyToType,

  /// 2 任意里的列表 / 字典 → 列表〈T〉/ 字典〈T〉：逐项检查，得到新的一份。
  anyToContainer,

  /// 3 取 / 改列表第 i 项：越界。
  listIndex,

  /// 4 “一定不是空”。
  must,

  /// 5 整数加减乘（还有取负、乘方）：超出范围。
  intOverflow,

  /// 6 整除、余、除：除以 0。
  divideByZero,

  /// 7 小数 → 整数（取整）。
  floatToInt,

  /// 8 任意和任意做算术、比大小。
  dynamicArith,

  /// 9 当成 某个类 / 接口（向下转型）。
  downcast,
}

class LRuntimeCheck {
  const LRuntimeCheck(this.kind, this.node, {this.type, this.where = ''});
  final LCheckKind kind;

  /// 在哪个节点上查（式子，或“改第 i 项”那句）。
  final LNode node;

  /// 要查成什么类型（1、2、9）。
  final LType? type;
  final String where;

  @override
  String toString() => '${kind.name}${type == null ? '' : '→${type!.show()}'}';
}

/// 边界上要做的转换（生成器照它套小函数）。
enum LCoercionKind {
  /// 整数 → 小数。
  widen,

  /// 任意 → 确定类型：查一次（[LCheckKind.anyToType]）。
  check,

  /// 任意 → 列表〈T〉/ 字典〈T〉：逐项查，得到新的一份（[LCheckKind.anyToContainer]）。
  checkEach,

  /// 列表〈T〉/ 字典〈T〉 → 任意：拍一份快照（设计 5.2 第 5 条）。
  snapshot,

  /// 不可空 → 可空（Go 里要换一种表示）。
  toNullable,
}

class LCoercion {
  const LCoercion(this.kind, this.from, this.to);
  final LCoercionKind kind;
  final LType from;
  final LType to;

  /// 从 [from] 放进要 [to] 的地方要做什么；什么都不用做＝null。两个类型都得是收尾以后的（不含待定）。
  static LCoercion? between(LType from, LType to) {
    if (from == to || from.isNever || to.isNever) return null;
    if (from.isAny) {
      if (to.isAny) return null;
      final each = (to.kind == LKind.list || to.kind == LKind.dict) && !(to.of ?? LType.any).isAny;
      return LCoercion(each ? LCoercionKind.checkEach : LCoercionKind.check, from, to);
    }
    if (to.isAny) return from.kind == LKind.list || from.kind == LKind.dict ? LCoercion(LCoercionKind.snapshot, from, to) : null;
    if (from.kind == LKind.integer && to.kind == LKind.number) return LCoercion(LCoercionKind.widen, from, to);
    if (to.nullable && !from.nullable) return LCoercion(LCoercionKind.toNullable, from, to);
    return null;
  }

  @override
  String toString() => '${kind.name}:${from.show()}→${to.show()}';
}
