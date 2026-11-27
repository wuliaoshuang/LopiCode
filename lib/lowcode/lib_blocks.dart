/// 库积木的“文档无关”一层（积木第 5 版·第四轮）：一份“会用库的文档”（[LibUser]）用上了哪些库、每块库积木在编辑器里
/// 长什么样（规格、句子、口、“放进变量”槽）、积木盒里怎么分页。
///
/// 后端文档是它的一个使用者（lib/backend/backend_lib_table.dart 的 `BeLibTable`）；页面逻辑的文档会是第二个。
/// 这一层不认识任何一种文档：要什么都从 [LibUser] 拿。文档一改就重新建一张表；任何输入都不抛异常。
library;

import 'package:lopicode/blocks/block_host.dart';
import 'package:lopicode/lang/lib_model.dart';
import 'package:lopicode/lowcode/lib_page.dart';
import 'package:lopicode/lowcode/logic_blocks.dart';
import 'package:lopicode/lowcode/logic_model.dart';

/// 库积木的 op / e 的前缀。
const String kLibOpPrefix = 'lib:';

String libOp(String libId, String blockId) => '$kLibOpPrefix$libId#$blockId';

/// `lib:作者段/库名#编号` → 库标识和积木编号；不是库积木返回 null。
({String lib, String block})? libOpOf(Object? op) {
  if (op is! String || !op.startsWith(kLibOpPrefix)) return null;
  final at = op.indexOf('#');
  if (at <= kLibOpPrefix.length || at == op.length - 1) return null;
  return (lib: op.substring(kLibOpPrefix.length, at), block: op.substring(at + 1));
}

/// 库的定义画布上才有的两块积木（只在“原地展开”的定义里有意义）：做口里的积木、把结果放进用的人选的变量。
const String kLibMouthOp = 'libMouth';
const String kLibPutOp = 'libPut';

/// 库文档里才有的那一页。
const String kLibDefCategory = '做库积木';

/// 积木盒里库的帽子模板的 id：`libhat:` 加库积木的 op。
const String kLibHatTemplate = 'libhat:';

/// 一份文档最多用几个库（自定，防坏数据）。
const int kMaxLibUses = 16;

/// 这份文档用了一个库。
class LibUse {
  LibUse(this.id, [Map<String, Object?>? settings]) : settings = settings ?? {};
  final String id;

  /// 设置项编号 → 这份文档里填的值（没填的用库里写的默认值）。
  final Map<String, Object?> settings;

  Map<String, dynamic> toJson() => {'id': id, if (settings.isNotEmpty) 'settings': settings};
  LibUse clone() => LibUse(id, {...settings});

  static LibUse? tryParse(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    if (id is! String || !kLibIdPattern.hasMatch(id)) return null;
    final raw = json['settings'];
    return LibUse(id, {
      if (raw is Map)
        for (final e in raw.entries)
          if (e.key is String && _plainOrList(e.value)) e.key as String: e.value,
    });
  }
}

bool _plain(Object? v) => v == null || v is bool || v is String || (v is num && v.isFinite);
bool _plainOrList(Object? v) => _plain(v) || (v is List && v.every(_plain));

/// “会用库的文档”：库积木表只问它这几样。
abstract interface class LibUser {
  /// 用上了哪些库（按先后）。
  List<LibUse> get uses;

  /// 项目里读到的库（文档打开时挂上来的；不存盘）。
  List<LibLibrary> get loaded;
  set loaded(List<LibLibrary> value);

  /// 这份文档是哪一边的（库的“给谁用”对不上就不算用上）。
  LibSide get libSide;

  /// 这份文档自己就是一个库时，它的标识；不是库＝null。
  String? get libraryId;

  /// 库文档里：这个函数公开成的积木有哪些口（“做口里的积木”的下拉用）。
  List<String> libMouthsOf(String fnId);

  /// 文档里所有放积木的地方（数“库积木用了几处”用）。
  Iterable<List<LcBlock>> get libBodies;

  /// 文档里库的帽子串各自的 op。
  Iterable<String> get libHatOps;
}

/// 一块库积木在编辑器里的样子。
class LibEntry {
  LibEntry(this.lib, this.block, {this.pick = false}) : op = libOp(lib.id, block.id);

  /// 页面逻辑里：“页面”库积木上“从页面里挑一个”的槽（控件、状态、属性、页面）画成下拉，值是直接的字。
  final bool pick;

  /// 这个槽是不是“从页面里挑一个”，是的话挑什么（node / state / prop / page）。
  String? pickOf(String slot) => pick && lib.id == kLcPageLibId && block.kindOf(slot) == LibSlotKind.literal ? lcPagePickOf(block.id, slot) : null;

  final LibLibrary lib;
  final LibBlock block;
  final String op;

  late final List<String> _slots = [
    ...{
      for (final part in parseLookTemplate(block.look.template))
        if (part.isSlot) part.text,
    },
  ];

  /// 口的名字（最多两个：第一个是积木的开头口，第二个是收尾口）。
  late final List<String> mouths = [
    for (final s in _slots)
      if (block.kindOf(s) == LibSlotKind.mouth) s,
  ];

  /// 积木上的槽（不算口）。
  late final List<String> params = [
    for (final s in _slots)
      if (block.kindOf(s) != LibSlotKind.mouth) s,
  ];

  bool get isHat => block.shape == CustomBlockShape.hat;
  bool get isValue => block.isValue;

  /// 去掉口以后的那句话。
  late final String template = [
    for (final part in parseLookTemplate(block.look.template))
      if (!part.isSlot) part.text.replaceAll('{', '{{').replaceAll('}', '}}') else if (block.kindOf(part.text) != LibSlotKind.mouth) '{${part.text}}',
  ].join().trim();

  late final BlockCustom custom = BlockCustom(op, block.look.copyWith(template: template, shape: isHat ? CustomBlockShape.statement : block.shape), params);

  late final List<LcArgSpec> args = [
    for (final a in bkLookArgs(custom))
      switch (block.kindOf(a.name)) {
        LibSlotKind.assign => LcArgSpec(a.name, a.name, LcArgKind.variable, optional: true),
        _ => pickOf(a.name) == null ? a : LcArgSpec(a.name, kLibPickHints[pickOf(a.name)] ?? a.name, LcArgKind.choice),
      },
  ];

  late final LcBlockSpec blockSpec = LcBlockSpec(
    op,
    block.look.name,
    lib.name,
    args,
    bodyLabel: mouths.isEmpty ? null : mouths.first,
    elseLabel: mouths.length > 1 ? mouths[1] : null,
    hint: block.look.hint,
  );
  late final LcExprSpec exprSpec = LcExprSpec(op, block.look.name, lib.name, args, hint: block.look.hint);
  late final String sentence = bkLookSentence(custom.look, params);

  /// 新拿出来的一块，各槽先放什么。
  Map<String, dynamic> newArgs(Object? Function(CustomBlockSlot slot) slotValue) => {
    for (final p in params)
      p: switch (block.kindOf(p)) {
        LibSlotKind.assign => '',
        _ => pickOf(p) == null ? slotValue(block.look.slotFor(p)) : '',
      },
  };
}

class LibTable {
  LibTable(this.user);
  final LibUser user;

  /// 这份文档是不是页面逻辑（“页面”库积木上挑控件、状态的槽画成下拉）。
  bool get pick => false;

  /// 用上了、项目里有、读得懂、“给谁用”对得上的库，按“用上”的先后。
  late final List<LibLibrary> libs = [
    for (final u in user.uses)
      if (user.loaded.where((l) => l.id == u.id).firstOrNull case final l? when l.ok && l.sideProblem(user.libSide) == null) l,
  ];

  late final Map<String, LibEntry> _entries = {
    for (final l in libs)
      for (final b in l.blocks) libOp(l.id, b.id): LibEntry(l, b, pick: pick),
  };

  bool get isEmpty => _entries.isEmpty;
  Iterable<LibEntry> get entries => _entries.values;
  LibEntry? of(Object? op) => op is String ? _entries[op] : null;
  List<LibEntry> ofLib(String id) => [
    for (final e in _entries.values)
      if (e.lib.id == id) e,
  ];

  /// 这个 op 是不是“库积木”的写法（不管库还在不在）。
  static bool isLibOp(Object? op) => libOpOf(op) != null;

  LcBlockSpec? blockSpec(String op) {
    final e = _entries[op];
    if (e != null) return e.isHat ? null : e.blockSpec;
    if (user.libraryId == null) return null;
    return switch (op) {
      kLibMouthOp => const LcBlockSpec(kLibMouthOp, '做口里的积木', kLibDefCategory, [LcArgSpec('name', '口', LcArgKind.choice)], hint: '用的人放进这个口里的积木，在这里做'),
      kLibPutOp => const LcBlockSpec(kLibPutOp, '交给用的人选的变量', kLibDefCategory, [LcArgSpec('value', '值', LcArgKind.expr)], hint: '用的人在“放进变量”那一格选了哪个变量，就写进哪个'),
      _ => null,
    };
  }

  LcExprSpec? exprSpec(String? kind) {
    final e = _entries[kind];
    return e != null && !e.isHat ? e.exprSpec : null;
  }

  String? sentenceOf(String op) =>
      _entries[op]?.sentence ??
      (user.libraryId == null
          ? null
          : switch (op) {
              kLibMouthOp => '做 {name} 里的积木',
              kLibPutOp => '把 {value} 交给用的人选的变量',
              _ => null,
            });

  bool isBool(Object? expr) => _entries[exprKind(expr)]?.block.shape == CustomBlockShape.boolean;

  /// 库文档里：这个函数公开成的积木有哪些口。
  List<String> mouthsOfFunction(String fnId) => user.libMouthsOf(fnId);

  /// 库积木在这份文档里用了几处（帽子串也算）。
  int usesOfLib(String libId) {
    var n = 0;
    bool mine(Object? op) => libOpOf(op)?.lib == libId;
    void walk(List<LcBlock> list, int depth) {
      if (depth > LcBlock.maxDepth + 2) return;
      for (final b in list) {
        if (mine(b.op)) n++;
        _exprs(b.args, (e) => n += mine(e['e']) ? 1 : 0);
        for (final a in b.arms) {
          _exprs(a.args, (e) => n += mine(e['e']) ? 1 : 0);
          walk(a.body, depth + 1);
        }
        walk(b.body, depth + 1);
        walk(b.orElse, depth + 1);
      }
    }

    for (final body in user.libBodies) {
      walk(body, 0);
    }
    for (final op in user.libHatOps) {
      if (mine(op)) n++;
    }
    return n;
  }
}

void _exprs(Object? v, void Function(Map<String, dynamic> e) f, [int depth = 0]) {
  if (depth > kMaxExprDepth * 2 + 4) return;
  if (v is List<LcBlock>) return;
  if (v is List) {
    for (final x in v) {
      _exprs(x, f, depth + 1);
    }
  } else if (v is Map) {
    final e = asExpr(v);
    if (e != null && e['e'] is String) f(e);
    for (final x in v.values) {
      _exprs(x, f, depth + 1);
    }
  }
}

/// 库的帽子在画布上、积木盒里的样子。
BlockHat libHatLook(LibEntry e, Map<String, dynamic> args, {String? Function(String pick, String value)? label}) => BlockHat([
  for (final part in parseLookTemplate(e.block.look.template))
    if (!part.isSlot)
      BlockHatPart.text(part.text)
    else if (e.block.kindOf(part.text) != LibSlotKind.mouth)
      if (e.pickOf(part.text) case final pick?)
        // 页面逻辑里：从页面里挑一个（控件……），显示它的名字。
        BlockHatPart.slot(part.text, _picked(pick, args[part.text], label), empty: libHatShow(args[part.text], '').isEmpty)
      else
        BlockHatPart.slot(
          part.text,
          libHatShow(args[part.text], part.text),
          empty: libHatShow(args[part.text], '').isEmpty,
          kind: args[part.text] is num ? LcArgKind.literalNumber : LcArgKind.literalText,
        ),
], colorKey: e.lib.id == kLcPageLibId ? BlockColorKey.event : BlockColorKey.custom);

/// “从页面里挑一个”的槽还空着时写的字。
const Map<String, String> kLibPickHints = {'node': '选控件', 'state': '选状态', 'prop': '选属性', 'page': '选页面'};

String _picked(String pick, Object? v, String? Function(String pick, String value)? label) {
  final value = libHatShow(v, '');
  if (value.isEmpty) return kLibPickHints[pick] ?? '选一个';
  return label?.call(pick, value) ?? value;
}

String libHatShow(Object? v, String fallback) => v is String && v.isNotEmpty ? v : (v is num || v is bool ? '$v' : fallback);

/// 内置“页面”库的积木在编辑器里用哪种颜色（库里写的是它自己的叫法）。
const Map<String, String> kLcPageColors = {'event': BlockColorKey.event, 'state': BlockColorKey.variable, 'ui': BlockColorKey.widget, 'page': BlockColorKey.action, 'old': BlockColorKey.unknown};

/// 库积木的颜色：“页面”库照上面那张表；别的库照库里写的。
String libEntryColor(LibEntry e) => e.lib.id == kLcPageLibId ? (kLcPageColors[e.block.look.colorKey] ?? BlockColorKey.custom) : e.block.look.colorKey;

/// “页面”库在积木盒里分成的几页（照库积木的分类；“旧积木”那一类只给旧文件用，不进积木盒）。
const List<(String, String)> kLcPageCategories = [('事件', BlockColorKey.event), ('状态', BlockColorKey.variable), ('控件', BlockColorKey.widget), ('页面', BlockColorKey.action)];

BlockCategory _libPage(LibTable table, String id, String label, String colorKey, bool Function(LibEntry e) keep, {LibHatLook? hat}) => BlockCategory(
  id: id,
  label: label,
  colorKey: colorKey,
  hats: [
    for (final e in table.ofLib(kLibOfCategory(id)))
      if (e.isHat && keep(e)) BlockHatTemplate('$kLibHatTemplate${e.op}', (hat ?? libHatLook)(e, const {}), hint: e.block.look.hint),
  ],
  blocks: [
    for (final e in table.ofLib(kLibOfCategory(id)))
      if (!e.isHat && !e.isValue && keep(e)) e.op,
  ],
  exprs: [
    for (final e in table.ofLib(kLibOfCategory(id)))
      if (e.isValue && keep(e)) e.op,
  ],
);

/// 分类页的 id 是 `lib:库标识`，“页面”库的几页是 `lib:lopi/page:分类`；取回库标识。
String kLibOfCategory(String categoryId) {
  final rest = categoryId.substring(4);
  return rest.startsWith('$kLcPageLibId:') ? kLcPageLibId : rest;
}

typedef LibHatLook = BlockHat Function(LibEntry e, Map<String, dynamic> args);

/// 接在积木盒后面的页：每个用上的库一页（“页面”库分成事件、状态、控件、页面四页）；库文档再多一页“做库积木”。
/// [first]＝只要“页面”库的那几页（页面逻辑把它们排在积木盒最前面）；false＝只要别的库；null＝全要。
List<BlockCategory> libCategories(LibTable table, {bool? first, LibHatLook? hat}) => [
  for (final l in table.libs)
    if (l.id == kLcPageLibId) ...[
      if (first != false)
        for (final (name, color) in kLcPageCategories) _libPage(table, 'lib:${l.id}:$name', name, color, (e) => e.block.category == name, hat: hat),
    ] else if (first != true)
      _libPage(table, 'lib:${l.id}', l.name, BlockColorKey.custom, (e) => true),
  if (first != true && table.user.libraryId != null) const BlockCategory(id: 'libdef', label: kLibDefCategory, colorKey: BlockColorKey.custom, blocks: [kLibMouthOp, kLibPutOp]),
];
