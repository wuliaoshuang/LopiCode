/// 积木编辑器和“用它的人”之间的接口。编辑器（lib/blocks）不认识低代码页面，也不认识后端工程，只认 [BlockHost]：
/// 前端（lib/lowcode/logic_block_host.dart）、后端（lib/backend）各实现一个。
///
/// 约定见 docs/blocks-v3-design.md 的“对外接口”一节；改签名先改那一节。
///
/// 用的时候记住三件事：
/// 1. **不要跨一次改动留着 [LcBlockTree] / [LcBlock] 对象**——宿主撤销重做后可能整份换对象。
///    记“脚本 id + 路径”，要用时从 [BlockHost.script] 重新找。
/// 2. **所有改动都包在 [BlockHost.edit] 里**（一次调用＝一条撤销记录＝一次落盘）。
///    自动排布算出来的位置不是改动，不许写回模型。
/// 3. 宿主的内容变了（改动、撤销、外面改了页面）会调 [BlockHost.onChanged]，并且 [BlockHost.revision] 加一。
library;

import 'package:lopicode/lowcode/logic_blocks.dart';
import 'package:lopicode/lowcode/logic_model.dart';

/// 分类用哪种颜色。编辑器自己有一张色表（lib/blocks/block_colors.dart），宿主只说“用哪一种”，不直接给颜色，
/// 这样浅色深色、立体感的几档深浅都由编辑器统一管。不在表里的键按 [unknown] 画。
abstract final class BlockColorKey {
  static const String event = 'event';
  static const String variable = 'variable';
  static const String widget = 'widget';
  static const String control = 'control';
  static const String action = 'action';
  static const String network = 'network';
  static const String value = 'value';
  static const String operator = 'operator';
  static const String data = 'data';
  static const String request = 'request';
  static const String response = 'response';
  static const String unknown = 'unknown';

  static const List<String> all = [event, variable, widget, control, action, network, value, operator, data, request, response, unknown];
}

/// 帽子块（一串积木最上面那块：“当 [按钮 提交] 被点击”“GET [/todos/:id]”）上的一段：文字，或一个可以点的槽位。
class BlockHatPart {
  /// 一段不能点的文字。
  const BlockHatPart.text(this.text) : slotId = null, empty = false, kind = LcArgKind.choice;

  /// 一个槽位。`slotId` 由宿主定（例如 target / method / path），点它时编辑器拿它去问 [BlockHost.hatSlotOptions]。
  /// `text` 是现在显示的字；`empty`＝还没选（画成空槽并显示 `text` 当提示）。
  /// `kind`：[LcArgKind.literalText] / [LcArgKind.literalNumber]＝直接输入；其余＝从可选项里挑。
  const BlockHatPart.slot(String this.slotId, this.text, {this.empty = false, this.kind = LcArgKind.choice});

  final String text;
  final String? slotId;
  final bool empty;
  final LcArgKind kind;

  bool get isSlot => slotId != null;
}

/// 一串积木的帽子长什么样。
class BlockHat {
  const BlockHat(this.parts, {this.colorKey = BlockColorKey.event});
  final List<BlockHatPart> parts;
  final String colorKey;
}

/// 积木盒里可以拖出来的一种帽子（拖出来＝新建一串）。
class BlockHatTemplate {
  const BlockHatTemplate(this.id, this.hat, {this.hint = ''});

  /// 交给 [BlockHost.addScript] 的名字（前端是事件名 click / input / load；后端是请求方式）。
  final String id;

  /// 在积木盒里照这个画。
  final BlockHat hat;
  final String hint;
}

/// 积木盒的一页。一页里可以同时有帽子、语句积木、表达式；按这个顺序排。
class BlockCategory {
  const BlockCategory({required this.id, required this.label, required this.colorKey, this.hats = const [], this.blocks = const [], this.exprs = const []});

  final String id;
  final String label;

  /// 见 [BlockColorKey]。
  final String colorKey;
  final List<BlockHatTemplate> hats;

  /// 语句积木的 op。
  final List<String> blocks;

  /// 表达式的 e。
  final List<String> exprs;

  bool get isEmpty => hats.isEmpty && blocks.isEmpty && exprs.isEmpty;
}

/// 参数的一个可选项（变量、控件、集合、固定选项、帽子槽位都用它）。
class BlockOption {
  const BlockOption(this.value, this.label, {this.hint = ''});

  /// 存进模型的值。
  final String value;

  /// 给人看的名字。
  final String label;
  final String hint;
}

/// 一条校验结果。
class BlockIssue {
  const BlockIssue({required this.message, this.isError = true, this.scriptId, this.path = const [], this.arg});

  /// 完整的一句话（在哪 + 什么问题）。
  final String message;
  final bool isError;

  /// 哪一串（null＝不属于某一串，例如变量的问题）。
  final String? scriptId;

  /// 哪一块（空＝这一串本身，也就是帽子）。
  final LcBlockPath path;

  /// 哪个参数（能定位到时）。
  final String? arg;
}

/// 宿主接口。带 `// 可覆盖` 的有默认实现。
abstract class BlockHost {
  // —— 目录 ——

  /// 积木盒的分页，按显示顺序。
  List<BlockCategory> get categories;

  /// 查一种积木 / 表达式的说明；不认识返回 null（编辑器画成“不认识的积木”）。
  LcBlockSpec? blockSpec(String op);
  LcExprSpec? exprSpec(String kind);

  /// 这种积木 / 表达式用哪种颜色。默认：它在 [categories] 的哪一页就用哪页的颜色；哪页都不在是 unknown。可覆盖。
  String blockColorKey(String op) {
    for (final c in categories) {
      if (c.blocks.contains(op)) return c.colorKey;
    }
    return BlockColorKey.unknown;
  }

  String exprColorKey(String kind) {
    for (final c in categories) {
      if (c.exprs.contains(kind)) return c.colorKey;
    }
    return BlockColorKey.unknown;
  }

  /// 积木上的话怎么排：一句带 `{参数名}` 的模板，例如 `把 {name} 设为 {value}`。
  /// 返回 null＝用通用排法（积木名 + 每个参数“参数名 [槽]”+ body 的叫法）。模板里没提到的参数会接在后面。可覆盖。
  String? blockSentence(String op) => null;

  /// 表达式上的话，同上，例如 `{l} {op} {r}`、`不是 {x}`。可覆盖。
  String? exprSentence(String kind) => null;

  /// 这个表达式算出来是不是“是 / 否”（是＝画成六边形）。可覆盖。
  bool isBooleanExpr(Map<String, dynamic> expr) => false;

  // —— 脚本 ——

  /// 所有脚本（每串一个帽子 + 一串积木）。每次都要重新取，不要留着。
  List<LcBlockTree> get scripts;

  /// 按 id 找一串；没有返回 null。
  LcBlockTree? script(String id) {
    for (final s in scripts) {
      if (s.id == id) return s;
    }
    return null;
  }

  /// 这一串的帽子显示什么。
  BlockHat hatOf(LcBlockTree tree);

  /// 帽子上某个槽位现在的值（给就地输入框当初始内容）和可选项（直接输入的槽位返回空表）。
  String hatSlotValue(LcBlockTree tree, String slotId);
  List<BlockOption> hatSlotOptions(LcBlockTree tree, String slotId);

  /// 改帽子的槽位。要在 [edit] 里调。值不合适就不改，返回 false。
  bool setHatSlot(LcBlockTree tree, String slotId, String value);

  /// 新建一串（从积木盒拖出一个帽子）。`templateId` 是 [BlockHatTemplate.id]；`x / y` 是放在画布的哪里。
  /// 要在 [edit] 里调。不认识的模板返回 null。
  LcBlockTree? addScript(String templateId, {double? x, double? y});

  /// 删掉一串（连同里面所有积木）。要在 [edit] 里调。
  bool removeScript(String id);

  // —— 造新的 ——

  /// 新建一块积木 / 一个表达式，参数填好默认值（宿主会顺手挑第一个变量、控件之类）。
  LcBlock newBlock(String op);
  Map<String, dynamic> newExpr(String kind);

  /// 一个表达式槽被拖空以后放回什么。默认按参数想要的类型给一个字面量。可覆盖。
  Map<String, dynamic> defaultExpr(LcArgSpec arg) => defaultExprFor(arg.valueType);

  /// 往“一串值”的参数（`join` 的 items、后端 `obj` 的 fields）里加一项时放什么。`expr` 是那个表达式，`arg` 是那个参数。
  /// 默认同 [defaultExpr]。可覆盖。
  Map<String, dynamic> newListItem(Map<String, dynamic> expr, LcArgSpec arg) => defaultExpr(arg);

  // —— 参数 ——

  /// 编辑器刚改了一块积木的某个参数（`exprPath` 为空＝积木自己的参数；否则是参数里某个表达式的字段）。
  /// 宿主可以在这里顺手把别的参数调成对得上的（例如换了控件以后，“改什么”换成它有的属性）。
  /// 在 [edit] 里被调。默认什么都不做。可覆盖。
  void argChanged(LcBlockTree tree, LcBlock block, String arg, List<Object> exprPath) {}

  /// 某种参数（[LcArgKind.variable] / node / collection / choice）现在有哪些可选项。
  /// `tree`、`block`、`arg` 说明是在给哪一串的哪块积木的哪个参数挑（宿主可以据此筛选，比如“改文字”只列有文字的控件）；
  /// `expr` 不为 null＝这个参数在一个表达式上（`arg` 是表达式自己的字段名）。
  List<BlockOption> options(LcArgSpec arg, {LcBlockTree? tree, LcBlock? block, Map<String, dynamic>? expr});

  /// 参数的值显示成什么字（控件 id → “按钮“提交””，固定选项 → 中文名）。空值的提示语编辑器自己有。
  /// 默认：固定选项查 [LcArgSpec.choiceLabel]，其余原样。可覆盖。
  String optionLabel(LcArgSpec arg, String value) => arg.kind == LcArgKind.choice ? arg.choiceLabel(value) : value;

  // —— 校验与代码 ——

  /// 现在有哪些问题。
  List<BlockIssue> get issues;

  /// “看代码”面板里的字，和它是什么语言（标题用，例如 JavaScript / Python）。
  String get codeText;
  String get codeLanguage;

  // —— 改动、撤销、通知 ——

  /// 做一次改动：宿主先记撤销快照，再跑 `change`（里面用 [scripts] / [script] 取到的就是可以直接改的对象），
  /// 然后落盘、[revision] 加一、调 [onChanged]。`change` 里什么都没改也算一次（调用方自己判断要不要调）。
  void edit(void Function() change);

  bool get canUndo;
  bool get canRedo;
  void undo();
  void redo();

  /// 内容每变一次加一（改动、撤销、重做、外面换了文档）。编辑器用它判断排版要不要重算。
  int get revision;

  /// 内容变了以后调一下。只有一个位置，谁显示这个宿主谁占（离开时置回 null）。
  void Function()? onChanged;
}

/// 模板拆出来的一段：一段文字，或一个参数的位置。
class BlockSentencePart {
  const BlockSentencePart.text(this.text) : arg = null;
  const BlockSentencePart.arg(String this.arg) : text = '';
  final String text;
  final String? arg;
}

/// 把 `把 {name} 设为 {value}` 拆成几段。模板里没提到的参数（`args` 里有、模板里没有）接在最后，前面带上它的中文名。
/// `{` 没配上的照字面当文字。
List<BlockSentencePart> parseBlockSentence(String template, List<LcArgSpec> args) {
  final parts = <BlockSentencePart>[];
  final used = <String>{};
  final re = RegExp(r'\{([A-Za-z_][A-Za-z0-9_]*)\}');
  var at = 0;
  void text(String s) {
    final t = s.trim();
    if (t.isNotEmpty) parts.add(BlockSentencePart.text(t));
  }

  for (final m in re.allMatches(template)) {
    text(template.substring(at, m.start));
    final name = m[1]!;
    if (args.any((a) => a.name == name) && used.add(name)) {
      parts.add(BlockSentencePart.arg(name));
    } else {
      text(m[0]!);
    }
    at = m.end;
  }
  text(template.substring(at));
  for (final a in args) {
    if (used.contains(a.name)) continue;
    text(a.label);
    parts.add(BlockSentencePart.arg(a.name));
  }
  return parts;
}

/// 通用排法：积木名，后面每个参数“参数名 [槽]”（第一个参数不带名字，紧跟积木名），最后是 body 的叫法。
String defaultBlockSentence(LcBlockSpec spec) {
  final b = StringBuffer(spec.label);
  for (var i = 0; i < spec.args.length; i++) {
    final a = spec.args[i];
    b.write(i == 0 ? ' {${a.name}}' : ' ${a.label} {${a.name}}');
  }
  if (spec.bodyLabel != null) b.write(' ${spec.bodyLabel}');
  return b.toString();
}

/// 表达式的通用排法：没有参数就是名字本身；只有一个参数就只有那个槽；多个参数依次排开。
String defaultExprSentence(LcExprSpec spec) {
  if (spec.args.isEmpty) return spec.label;
  if (spec.args.length == 1) {
    final a = spec.args.first;
    final literal = a.kind == LcArgKind.literalText || a.kind == LcArgKind.literalNumber || a.kind == LcArgKind.literalBool || a.kind == LcArgKind.variable;
    return literal ? '{${a.name}}' : '${spec.label} {${a.name}}';
  }
  return [for (final a in spec.args) '{${a.name}}'].join(' ');
}
