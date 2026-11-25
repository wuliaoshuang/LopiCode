/// 第 4 版·阶段 2 加的几样“宿主说了算”的东西的形状（纯数据 + 纯逻辑，不带界面）：
///
/// - [BlockParam] / [BlockHatParams]：帽子上的参数小块（“定义 [问好] (名字) (次数＝1) ＋”）。
/// - [BlockCustom]：一块自定义积木（模型里的名字 + 外观 + 参数表）。外观直接用语言核心的 `CustomBlockLook`
///   （lib/lang/custom_block.dart：形状、文案模板、每个槽的种类、颜色、说明），模板解析和校验也用那边的，不另写一份。
/// - [BlockCustomHost]：“我的积木”的全部回调（新建、改、删、看定义、包成积木）。宿主不给＝没有“我的积木”页。
library;

import 'package:lopicode/lang/custom_block.dart';
import 'package:lopicode/lowcode/logic_blocks.dart';
import 'package:lopicode/lowcode/logic_model.dart';

export 'package:lopicode/lang/custom_block.dart';

/// 帽子上的一个参数。
class BlockParam {
  const BlockParam(this.name, {this.defaultValue, this.rest = false});
  final String name;

  /// 默认值（文字 / 数字 / 是否）；null＝没有默认值。
  final Object? defaultValue;

  /// “剩下的全收”（不定个数）；只有最后一个参数可以是。
  final bool rest;

  BlockParam copyWith({String? name, Object? defaultValue, bool clearDefault = false, bool? rest}) =>
      BlockParam(name ?? this.name, defaultValue: clearDefault ? null : (defaultValue ?? this.defaultValue), rest: rest ?? this.rest);

  /// 小块上写的字：`名字`、`次数＝1`、`…其余`。
  String get chipText {
    final d = defaultValue;
    final shown = d == null ? '' : '＝${d is bool ? (d ? '是' : '否') : (d is num ? bkLookNumber(d) : (d is String && d.isEmpty ? '“”' : '$d'))}';
    return '${rest ? '…' : ''}$name$shown';
  }
}

/// 帽子的参数表，和这种帽子的参数能做什么。
class BlockHatParams {
  const BlockHatParams(this.params, {this.defaults = true, this.rest = true, this.max = 12});
  final List<BlockParam> params;

  /// 参数能不能给默认值 / 最后一个能不能设成“剩下的全收”；最多几个参数。
  final bool defaults;
  final bool rest;
  final int max;
}

String bkLookNumber(num v) => v.isFinite && v == v.roundToDouble() && v.abs() < 1e15 ? '${v.round()}' : '$v';

/// 参数的名字合不合适：不能空、不能太长、不能带花括号和换行（会和文案模板的写法撞上）。返回 null＝可以；否则是原因。
String? bkParamNameProblem(String name, Iterable<String> others) {
  final n = name.trim();
  if (n.isEmpty) return '名字不能空着';
  if (n.runes.length > 24) return '名字太长了（最多 24 个字）';
  if (n.contains(RegExp(r'[{}\r\n]'))) return '名字里不能有花括号和换行';
  if (others.contains(n)) return '已经有一个叫“$n”的参数了';
  return null;
}

/// 给新参数起一个不重名的名字：`参数1`、`参数2`…
String bkFreshParamName(Iterable<String> taken, {String base = '参数'}) {
  for (var i = 1; ; i++) {
    final n = '$base$i';
    if (!taken.contains(n)) return n;
  }
}

/// 带参数表的值（[LcExprSpec.paramsArg]）现在的参数名；字段不对＝空表（不改模型）。
List<String> bkExprParams(Map<String, dynamic> expr, LcExprSpec spec) {
  final v = spec.paramsArg == null ? null : expr[spec.paramsArg];
  return v is List ? [for (final x in v) if (x is String && x.isNotEmpty) x] : const [];
}

// ———————————————————————— 自定义积木 ————————————————————————

/// 一块自定义积木：模型里叫什么、长什么样、有哪些参数。
class BlockCustom {
  const BlockCustom(this.id, this.look, this.params);

  /// 模型里的名字：当语句用时是积木的 `op`，当值用时是表达式的 `e`。
  final String id;
  final CustomBlockLook look;

  /// 参数名，按定义里的顺序。外观里没单独设置的参数按“普通的值槽”算（[CustomBlockLook.slotFor]）。
  final List<String> params;

  /// 每个参数的槽设置，按参数的顺序，一个不少。
  List<CustomBlockSlot> get slots => [for (final p in params) look.slotFor(p)];

  /// 画成值（胶囊 / 六边形）还是语句。“自动”在这里按语句算——宿主给过来的应该是已经定好的形状（`resolveLookShape`）。
  bool get isValue => look.shape == CustomBlockShape.value || look.shape == CustomBlockShape.boolean;
}

/// 换成积木排版认的那种句子（`BlockHost.blockSentence` / `exprSentence` 直接返回它）：槽还是 `{名字}`；
/// 字里的花括号后面垫一个看不见的零宽字符，免得被当成槽；不是参数的 `{x}`、重复出现的槽也当字；换行换成空格。
String bkLookSentence(CustomBlockLook look, List<String> params) {
  final used = <String>{};
  final sb = StringBuffer();
  for (final seg in parseLookTemplate(look.templateFor(params))) {
    if (seg.isSlot && params.contains(seg.text) && used.add(seg.text)) {
      sb.write('{${seg.text}}');
    } else {
      sb.write((seg.isSlot ? '{${seg.text}}' : seg.text).replaceAll('{', '{\u200B').replaceAll(RegExp(r'[\r\n]+'), ' '));
    }
  }
  return sb.toString();
}

/// 每个参数对应的参数说明（积木排版、下拉菜单都认这个）。参数名＝槽名。
List<LcArgSpec> bkLookArgs(BlockCustom custom) => [
  for (final s in custom.slots)
    switch (s.kind) {
      CustomSlotKind.boolean => LcArgSpec(s.name, s.name, LcArgKind.expr, valueType: LcType.boolean),
      CustomSlotKind.choice => LcArgSpec(s.name, s.name, LcArgKind.choice, choices: s.options, choiceLabels: s.options),
      // 值槽；第 3 阶段才有的槽（内联口、回调口）现在也按值槽画，不崩。
      _ => LcArgSpec(s.name, s.name, LcArgKind.expr),
    },
];

/// “我的积木”在积木盒里的分类名。
const String kBlockCustomCategory = '我的积木';

/// 这块自定义积木当语句 / 当值时的规格（`BlockHost.blockSpec` / `exprSpec` 直接返回它）。
LcBlockSpec bkLookBlockSpec(BlockCustom c) => LcBlockSpec(c.id, c.look.name, kBlockCustomCategory, bkLookArgs(c), hint: c.look.hint);
LcExprSpec bkLookExprSpec(BlockCustom c) => LcExprSpec(c.id, c.look.name, kBlockCustomCategory, bkLookArgs(c), hint: c.look.hint);

/// “新建积木”页上的一个问题，和它该显示在哪一行下面。
enum BlockLookField { name, template, slot, options }

class BlockLookProblem {
  const BlockLookProblem(this.field, this.message, {this.slot});
  final BlockLookField field;
  final String message;

  /// 哪个参数的问题（[BlockLookField.slot] / [BlockLookField.options] 才有）。
  final String? slot;
}

/// 查一遍外观，问题按“该显示在哪”分好。规矩用语言核心的 `validateLook`（B01–B08），再加上界面这边才知道的：
/// 重名（`taken`＝别的自定义积木的名字）、名字太长、参数太多。警告（B09）不算。
/// 参数名本身合不合适另外查（[bkParamNameProblems]）；这里的 `params` 要是已经去掉了不合适的名字的。
List<BlockLookProblem> bkCheckLook(CustomBlockLook look, List<String> params, {Iterable<String> taken = const []}) {
  final out = <BlockLookProblem>[];
  final name = look.name.trim();
  if (name.isNotEmpty && name.runes.length > 24) out.add(const BlockLookProblem(BlockLookField.name, '名字太长了（最多 24 个字）'));
  if (name.isNotEmpty && taken.contains(name)) out.add(BlockLookProblem(BlockLookField.name, '已经有一块叫“$name”的积木了，换个名字'));
  if (params.length > kCustomBlockMaxSlots) out.add(const BlockLookProblem(BlockLookField.template, '参数太多了（最多 $kCustomBlockMaxSlots 个）'));
  for (final p in validateLook(look, params)) {
    if (!p.isError) continue;
    final field = switch (p.code) {
      'B01' => BlockLookField.name,
      'B06' || 'B07' => BlockLookField.options,
      'B05' => BlockLookField.slot,
      _ => BlockLookField.template,
    };
    out.add(BlockLookProblem(field, p.message, slot: field == BlockLookField.template ? null : p.slot));
  }
  return out;
}

/// 每个参数名合不合适（空的、太长、带花括号、和前面的重名）：和 `names` 一样长，合适的那一项是 null。
List<String?> bkParamNameProblems(List<String> names) {
  final seen = <String>[];
  return [
    for (final n in names)
      () {
        final why = bkParamNameProblem(n, seen);
        seen.add(n.trim());
        return why;
      }(),
  ];
}

/// “我的积木”的全部回调。写模型的那几个（[create] / [update] / [remove] / [wrap]）都在 `BlockHost.edit` 里被调：一次操作一条撤销记录。
abstract class BlockCustomHost {
  /// 现在有哪些自定义积木，按积木盒里排的先后。
  List<BlockCustom> get customs;

  /// 新建一块：宿主在画布上加一串“定义 …”，并让 [customs] 多一项。`params`＝参数名（按顺序）；
  /// `look.slots` 里每个参数的槽设置都列全了。返回新积木的 [BlockCustom.id]；没建成返回 null。
  String? create(CustomBlockLook look, List<String> params);

  /// 改一块的外观 / 参数。`origin[i]`＝新参数 i 原来是旧参数表里的第几个（改名、换顺序靠它认），null＝新加的；
  /// 旧参数没被任何一项指到＝删掉了。宿主负责让定义的帽子、各处调用的槽跟着变（语言核心的 `remapCallArgsByName`）。
  bool update(String id, CustomBlockLook look, List<String> params, List<int?> origin);

  /// 新拿出来的一块，这个槽里先放什么（宿主的 `newBlock` / `newExpr` 也照这个填，预览才和真的一样）：
  /// 值槽 / 是否槽＝一个表达式（给了默认值就是它的字面量，没给就是宿主的空槽 / “否”）；下拉＝选中的那一项（字符串）。
  Object? slotValue(CustomBlockSlot slot);

  /// 这块积木在别处用了几次（删之前提示；删参数前提示）。
  int usesOf(String id);

  /// 删掉这块积木（定义那一串，连同各处的调用——怎么处理调用由宿主定）。
  bool remove(String id);

  /// 定义在哪一串（“看它的定义”跳过去）；找不到返回 null。
  String? definitionOf(String id);

  /// 能不能“包成积木”；不能（默认）＝画布上长按语句积木没有那个菜单。
  bool get canWrap => false;

  /// “包成积木”：从 `from` 这块往下相连的那一截里，用到了哪些外面的变量（它们会变成新积木的参数）。
  List<String> outerNames(LcBlockTree tree, LcBlockPath from) => const [];

  /// “包成积木”：把 `from` 这块及其下面相连的积木搬进一个新定义，原处换成一次调用（参数槽里填上同名的外面的变量）。
  /// 返回新积木的 id；没成返回 null。
  String? wrap(LcBlockTree tree, LcBlockPath from, CustomBlockLook look, List<String> params) => null;

  /// 宿主自己的规矩（例如不能和内置积木重名）。`editing`＝正在改哪一块（新建为 null）。
  List<BlockLookProblem> check(CustomBlockLook look, List<String> params, {String? editing}) => const [];
}
