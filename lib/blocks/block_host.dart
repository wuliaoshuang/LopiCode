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

import 'dart:async';

import 'package:lopicode/blocks/block_look.dart';
import 'package:lopicode/lowcode/logic_blocks.dart';
import 'package:lopicode/lowcode/logic_model.dart';

export 'package:lopicode/blocks/block_look.dart';

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

  // 第 4 版语言核心的分类（设计稿 9.1）。变量、运算、流程沿用上面的 variable / operator / control。
  static const String function = 'function';
  static const String text = 'text';
  static const String list = 'list';
  static const String dict = 'dict';
  static const String classes = 'class';
  static const String error = 'error';
  static const String async = 'async';
  static const String custom = 'custom';

  static const List<String> all = [event, variable, widget, control, action, network, value, operator, data, request, response, unknown, function, text, list, dict, classes, error, async, custom];
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

/// 积木盒里拿得出来的东西是哪一种。
enum BlockPaletteKind { hat, block, expr }

/// 指到积木盒里的一样东西：`id` 是帽子模板的 id / 积木的 op / 表达式的 e。
/// `preset`＝拿出来时顺手把这几个“固定选项”参数设好（“一块顶多块”的积木搜到某一种时用：搜“乘”拿出来的就是 ×）。
class BlockItemRef {
  const BlockItemRef(this.kind, this.id, {this.preset = const {}});
  const BlockItemRef.hat(this.id) : kind = BlockPaletteKind.hat, preset = const {};
  const BlockItemRef.block(this.id, {this.preset = const {}}) : kind = BlockPaletteKind.block;
  const BlockItemRef.expr(this.id, {this.preset = const {}}) : kind = BlockPaletteKind.expr;

  final BlockPaletteKind kind;
  final String id;
  final Map<String, String> preset;

  /// 存设置、当 key 用的名字（不带 preset）：`block:if`、`expr:bin`、`hat:click`。
  String get token => '${kind.name}:$id';

  /// 把 [token] 读回来；格式不对返回 null。
  static BlockItemRef? parse(Object? token) {
    if (token is! String) return null;
    final colon = token.indexOf(':');
    if (colon <= 0 || colon == token.length - 1) return null;
    for (final k in BlockPaletteKind.values) {
      if (k.name == token.substring(0, colon)) return BlockItemRef(k, token.substring(colon + 1));
    }
    return null;
  }
}

/// 积木盒一页里的一个小标题分组（第二级分类）：“造”“取”“改”“查”这种。
class BlockGroup {
  const BlockGroup(this.label, {this.hats = const [], this.blocks = const [], this.exprs = const []});

  /// 小标题上的字。
  final String label;
  final List<BlockHatTemplate> hats;
  final List<String> blocks;
  final List<String> exprs;

  bool get isEmpty => hats.isEmpty && blocks.isEmpty && exprs.isEmpty;
}

/// 积木盒的一页（第一级分类，一页一种颜色）。一页里可以同时有帽子、语句积木、表达式；按这个顺序排。
/// 积木多的页可以再分小标题（[groups]）：先排不在任何分组里的（[hats] / [blocks] / [exprs]），再一组一组往下排。
class BlockCategory {
  const BlockCategory({required this.id, required this.label, required this.colorKey, this.hats = const [], this.blocks = const [], this.exprs = const [], this.groups = const []});

  final String id;
  final String label;

  /// 见 [BlockColorKey]。
  final String colorKey;
  final List<BlockHatTemplate> hats;

  /// 语句积木的 op。
  final List<String> blocks;

  /// 表达式的 e。
  final List<String> exprs;

  /// 页内的小标题分组（第二级分类）；空＝这一页不分组。
  final List<BlockGroup> groups;

  bool get isEmpty => hats.isEmpty && blocks.isEmpty && exprs.isEmpty && groups.every((g) => g.isEmpty);

  /// 这一页全部的帽子 / 积木 / 表达式（不分组的在前，各组依次在后）。
  List<BlockHatTemplate> get allHats => groups.isEmpty ? hats : [...hats, for (final g in groups) ...g.hats];
  List<String> get allBlocks => groups.isEmpty ? blocks : [...blocks, for (final g in groups) ...g.blocks];
  List<String> get allExprs => groups.isEmpty ? exprs : [...exprs, for (final g in groups) ...g.exprs];
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
  const BlockIssue({
    required this.message,
    this.isError = true,
    this.scriptId,
    this.path = const [],
    this.arg,
    this.exprPath,
    this.rule = '',
    this.problem = '',
    this.fix = '',
    this.group = '',
    this.spot = '',
  });

  /// 完整的一句话（在哪 + 什么问题）。
  final String message;

  /// 错误（有它就不生成代码）还是警告（照常生成）。
  final bool isError;

  /// 哪一串（null＝不属于某一串，例如变量的问题）。
  final String? scriptId;

  /// 哪一块（空＝这一串本身，也就是帽子）。
  final LcBlockPath path;

  /// 哪个参数（能定位到时）；帽子上的是帽子槽的 id。
  final String? arg;

  /// 参数里的哪个位置（槽位路径，见 block_geometry.dart 的 BkExprPath）；null＝说不出是哪一格。
  final List<Object>? exprPath;

  /// 稳定的规则编号（如 G01）；宿主没给是空的。
  final String rule;

  /// 只说问题本身的那半句（小卡、问题列表用）；宿主没给就用 [message]。
  final String problem;

  /// 建议怎么改；没有是空的。
  final String fix;

  /// 属于哪一组（事件 / 接口的读法，或“变量”“服务设置”）：问题列表按它分组。
  final String group;

  /// 组里的哪一处（“第 2 块（…）”）；帽子本身的问题为空。
  final String spot;

  /// 给人看的原因：有 [problem] 用它，没有用整句。
  String get reason => problem.isEmpty ? message : problem;
}

/// 把校验器给的问题（两套积木共用 [LcLogicIssue]）换成编辑器认的样子。
BlockIssue blockIssueOf(LcLogicIssue i) => BlockIssue(
  message: i.message,
  isError: i.isError,
  scriptId: i.handlerId,
  path: i.path,
  arg: i.arg,
  exprPath: i.exprPath,
  rule: i.rule,
  problem: i.problem,
  fix: i.advice,
  group: i.scope,
  spot: i.spot,
);

/// 校验结果的缓存（两个宿主共用）：内容没变不重查；连着两遍都超过 [budget] 以后，再有改动 [read] 就不当场查，
/// 先给上一次的结果，停手 [delay] 后查一遍并调 `onLate`（宿主拿它去通知界面重画）。
class BlockIssueCache {
  BlockIssueCache(this._compute, this._revision, [this._onLate, this.budget = const Duration(milliseconds: 8)]);

  /// 查一遍超过这么久就算“慢”。实测数见 docs/blocks-v3-design.md 的“校验规则表”一节；正常大小的页面走不到“停手后再查”这条路。
  final Duration budget;
  static const Duration delay = Duration(milliseconds: 180);

  final List<BlockIssue> Function() _compute;
  final int Function() _revision;
  final void Function()? _onLate;

  List<BlockIssue> _last = const [];
  int _rev = -1;
  Timer? _timer;

  /// 最近一次查用了多久。
  Duration lastCost = Duration.zero;

  /// 连着几次都超了预算（偶尔慢一次不算：刚启动、系统正忙都会慢一下）。
  int _slowRuns = 0;

  /// 是不是有一次“停手后再查”在等着。
  bool get pending => _timer != null;

  List<BlockIssue> read() {
    if (_rev == _revision()) return _last;
    if (_rev < 0 || _slowRuns < 2) return fresh();
    _timer?.cancel();
    _timer = Timer(delay, () {
      _timer = null;
      fresh();
      _onLate?.call();
    });
    return _last;
  }

  List<BlockIssue> fresh() {
    _timer?.cancel();
    _timer = null;
    final rev = _revision();
    if (_rev == rev) return _last;
    final watch = Stopwatch()..start();
    _last = _compute();
    lastCost = watch.elapsed;
    _slowRuns = lastCost > budget ? _slowRuns + 1 : 0;
    _rev = rev;
    return _last;
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }
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
      if (c.allBlocks.contains(op)) return c.colorKey;
    }
    return BlockColorKey.unknown;
  }

  String exprColorKey(String kind) {
    for (final c in categories) {
      if (c.allExprs.contains(kind)) return c.colorKey;
    }
    return BlockColorKey.unknown;
  }

  /// 积木上的话怎么排：一句带 `{参数名}` 的模板，例如 `把 {name} 设为 {value}`。
  /// 返回 null＝用通用排法（积木名 + 每个参数“参数名 [槽]”+ body 的叫法）。模板里没提到的参数会接在后面。可覆盖。
  String? blockSentence(String op) => null;

  /// 多口积木每一段的横栏上的话（见 [LcArmSpec]），例如 `否则如果 {cond} 那么`、`是 {value} 时`；`{参数名}` 是段自己的参数。
  /// 返回 null＝用通用排法（段名 + 每个参数的槽）。可覆盖。
  String? armSentence(String op) => null;

  /// 表达式上的话，同上，例如 `{l} {op} {r}`、`不是 {x}`。可覆盖。
  String? exprSentence(String kind) => null;

  /// 这个表达式算出来是不是“是 / 否”（是＝画成六边形）。可覆盖。
  bool isBooleanExpr(Map<String, dynamic> expr) => false;

  // —— 积木盒 ——

  /// 积木的别名（搜索用）：积木上没写、但人会这么找它的词，例如“重复”的别名 `循环` `for` `遍历`。可覆盖。
  List<String> aliasesOf(BlockItemRef item) => const [];

  /// “一块顶多块”：这块积木靠积木上的下拉能变成的那几种（每种一个带 `preset` 的 [BlockItemRef]，如 `expr:bin` 的 ＋ − × ÷）。
  /// 积木盒里它只占一个位置；搜索时每一种都能按自己的字（下拉上显示的字 + [aliasesOf] 给这一种的别名）搜到，拿出来就是那一种。
  /// 空表＝没有变体。可覆盖。
  List<BlockItemRef> variantsOf(BlockItemRef item) => const [];

  /// 新文档（一块积木都还没有）时“常用”页放哪些：一套入门积木。空表＝编辑器从各页挑前几块。可覆盖。
  List<BlockItemRef> get starterItems => const [];

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

  // —— 第 4 版·阶段 2：带参数的帽子、参数小块、自定义积木（都有默认实现，不用的宿主不必管）——

  /// 这一串的帽子是不是“定义”帽子（带一排参数小块：能加减、改名、给默认值、拖出来当值用）。
  /// 不是返回 null（默认）。参数小块排在帽子那几段（[hatOf]）的后面。
  BlockHatParams? hatParams(LcBlockTree tree) => null;

  /// 把帽子的参数表整个换成 `params`。`renamed`＝这次是把哪个参数改了名（宿主顺手把函数体里用到它的地方、各处调用一起改）。
  /// 要在 [edit] 里调。不合适就不改，返回 false。
  bool setHatParams(LcBlockTree tree, List<BlockParam> params, {({String from, String to})? renamed}) => false;

  /// 帽子上的某个参数在别处（各处调用的槽）用了几次：删参数前提示“有 N 处在用，槽里的东西会丢掉”。
  int hatParamUses(LcBlockTree tree, String name) => 0;

  /// 参数小块拖出来变成的那个值（“读这个参数”）。返回 null＝参数小块不能拖出来。
  Map<String, dynamic>? paramExpr(String name) => null;

  /// 带参数表的值（[LcExprSpec.paramsArg]，匿名函数）改了某个参数的名字：宿主顺手把它里面用到这个参数的地方一起改。
  /// 在 [edit] 里被调（参数表已经改好了）。默认什么都不做。
  void exprParamRenamed(LcBlockTree tree, Map<String, dynamic> expr, String from, String to) {}

  /// 自定义积木（“我的积木”）。返回 null（默认）＝这个宿主没有这回事，积木盒里不出现“我的积木”页。
  BlockCustomHost? get custom => null;

  /// 新建一串（从积木盒拖出一个帽子）。`templateId` 是 [BlockHatTemplate.id]；`x / y` 是放在画布的哪里。
  /// 要在 [edit] 里调。不认识的模板返回 null。
  LcBlockTree? addScript(String templateId, {double? x, double? y});

  /// 删掉一串（连同里面所有积木）。要在 [edit] 里调。
  bool removeScript(String id);

  // —— 造新的 ——

  /// 新建一块积木 / 一个表达式，参数填好默认值（宿主会顺手挑第一个变量、控件之类）。
  LcBlock newBlock(String op);
  Map<String, dynamic> newExpr(String kind);

  /// 给多口积木新加的一段（见 [LcArmSpec]）：参数填好默认值。默认按段的参数说明填（表达式用 [defaultExpr]，固定选项挑第一个）。
  /// 要在 [edit] 里用。可覆盖。
  LcArm newArm(LcBlock block) {
    final spec = blockSpec(block.op)?.arms;
    return LcArm(
      args: {
        for (final a in spec?.args ?? const <LcArgSpec>[])
          if (a.kind == LcArgKind.expr) a.name: defaultExpr(a) else if (a.kind == LcArgKind.choice && a.choices.isNotEmpty) a.name: a.choices.first else if (!a.optional) a.name: '',
      },
    );
  }

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

  /// 现在有哪些问题：一定是照现在的内容查出来的（内容没变不重查，结果按 [revision] 记着）。
  /// 问题列表、“能不能生成 / 启动”都看这个。
  List<BlockIssue> get issues;

  /// 画布上画标记用的：每次改动后自动重查（拖动、平移、缩放不会重查）；积木非常多、查一遍连着都很慢时，
  /// 连续改动期间先给上一次的结果，停手后再查并通知重画（见 [BlockIssueCache]）。默认同 [issues]。可覆盖。
  List<BlockIssue> get liveIssues => issues;

  /// 不再显示这个宿主了：有“停手后再查”的定时器就取消。默认什么都不做。可覆盖。
  void stopIssueTimer() {}

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
  // 槽名可以是任何字（自定义积木的槽名是用户起的，常常是中文）；但只有“正好是某个参数的名字”才算槽——
  // 不是参数名、也不像标识符的花括号原样留在字里（和以前一样，不把那句话切开）。
  final re = RegExp(r'\{([^{}\n]+)\}');
  final ident = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$');
  var at = 0;
  void text(String s) {
    final t = s.trim();
    if (t.isNotEmpty) parts.add(BlockSentencePart.text(t));
  }

  for (final m in re.allMatches(template)) {
    final raw = m[1]!;
    final name = args.any((a) => a.name == raw) ? raw : raw.trim();
    final isArg = args.any((a) => a.name == name);
    if (!isArg && !ident.hasMatch(raw)) continue;
    text(template.substring(at, m.start));
    if (isArg && used.add(name)) {
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

/// 段的通用排法：段名，后面每个参数一个槽。
String defaultArmSentence(LcArmSpec spec) => [spec.label, for (final a in spec.args) '{${a.name}}'].join(' ');

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
