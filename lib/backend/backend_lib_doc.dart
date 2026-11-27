/// 用户自己写库（积木第 5 版·库 1 的后半）在后端文档里多出来的三样数据：
///
/// - [BeLibInfo]（文档顶层的 `library`）：这份文档**本身是一个库**。库里的函数就是“我的积木”，类、变量、模块照旧放在核心里，
///   这里只记库的清单信息（标识、版本、作者、说明、设置项）和“哪些定义公开成了积木、积木长什么样”（[BeLibDef]）。
/// - [BeLibUse]（文档顶层的 `uses`）：这份文档**用了哪些库**、每个库的设置项在这份文档里填了什么。
/// - [BeLibHat]（文档顶层的 `hats`）：画布上以库的帽子积木开头的一串。
///
/// 三样都是没有就不写键——没碰库的旧文档读进来再存出去一个字节不差。读的时候容错：坏的逐条跳过，不抛异常。
/// 库积木在文档里的写法：语句 `{"op": "lib:作者段/库名#积木编号", "args": {槽名: 值}}`，当值用 `{"e": "lib:…#…", 槽名: 值}`。
/// 落盘格式（库文件夹）怎么从这里出来见 backend_lib_build.dart；格式说明见 docs/blocks-v5-parts/library-format.md 第 9–12 节。
library;

import 'package:lopicode/backend/backend_function.dart';
import 'package:lopicode/lang/custom_block.dart';
import 'package:lopicode/lang/lc_write.dart';
import 'package:lopicode/lang/lib_model.dart';
import 'package:lopicode/lowcode/logic_expr.dart';
import 'package:lopicode/lowcode/logic_model.dart';

/// 库积木的 op / e 的前缀。
const String kBeLibOpPrefix = 'lib:';

String beLibOp(String libId, String blockId) => '$kBeLibOpPrefix$libId#$blockId';

/// `lib:作者段/库名#编号` → 库标识和积木编号；不是库积木返回 null。
({String lib, String block})? beLibOpOf(Object? op) {
  if (op is! String || !op.startsWith(kBeLibOpPrefix)) return null;
  final at = op.indexOf('#');
  if (at <= kBeLibOpPrefix.length || at == op.length - 1) return null;
  return (lib: op.substring(kBeLibOpPrefix.length, at), block: op.substring(at + 1));
}

/// 库的定义画布上才有的两块积木（只在“原地展开”的定义里有意义）：做口里的积木、把结果放进用的人选的变量。
const String kBeLibMouthOp = 'libMouth';
const String kBeLibPutOp = 'libPut';

/// 调用型积木加了“放进变量”槽时，那个槽叫什么。
const String kBeLibIntoSlot = '结果';

/// 一份文档最多用几个库、一个库最多公开几块积木、最多几串帽子（自定，防坏数据）。
const int kBeMaxLibUses = 16;
const int kBeMaxLibDefs = 200;
const int kBeMaxLibHats = 64;

/// 这份文档用了一个库。
class BeLibUse {
  BeLibUse(this.id, [Map<String, Object?>? settings]) : settings = settings ?? {};
  final String id;

  /// 设置项编号 → 这份文档里填的值（没填的用库里写的默认值）。
  final Map<String, Object?> settings;

  Map<String, dynamic> toJson() => {'id': id, if (settings.isNotEmpty) 'settings': settings};
  BeLibUse clone() => BeLibUse(id, {...settings});

  static BeLibUse? tryParse(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    if (id is! String || !kLibIdPattern.hasMatch(id)) return null;
    final raw = json['settings'];
    return BeLibUse(id, {
      if (raw is Map)
        for (final e in raw.entries)
          if (e.key is String && _plainOrList(e.value)) e.key as String: e.value,
    });
  }
}

bool _plain(Object? v) => v == null || v is bool || v is String || (v is num && v.isFinite);
bool _plainOrList(Object? v) => _plain(v) || (v is List && v.every(_plain));

/// 画布上以库的帽子积木开头的一串。[op] 是那块帽子积木（`lib:…#…`），[args] 是帽子上各槽填的东西。
class BeLibHat with LcBlockTree {
  BeLibHat({required this.id, required this.op, Map<String, dynamic>? args, List<LcBlock>? body, double? x, double? y}) : args = args ?? {}, body = body ?? [] {
    this.x = x;
    this.y = y;
  }
  @override
  String id;
  final String op;
  final Map<String, dynamic> args;
  @override
  final List<LcBlock> body;

  Map<String, dynamic> toJson() => {
    'id': id,
    'op': op,
    if (args.isNotEmpty) 'args': args,
    if (x != null) 'x': x,
    if (y != null) 'y': y,
    'body': [for (final b in body) b.toJson()],
  };

  BeLibHat clone() => BeLibHat(id: id, op: op, args: {for (final e in args.entries) e.key: deepCopyJson(e.value)}, body: [for (final b in body) b.clone()], x: x, y: y);

  static BeLibHat? tryParse(Object? json) {
    if (json is! Map) return null;
    final op = json['op'];
    if (beLibOpOf(op) == null) return null;
    final id = json['id'], x = json['x'], y = json['y'], args = json['args'];
    return BeLibHat(
      id: id is String ? id : '',
      op: op as String,
      args: args is Map
          ? {
              for (final e in args.entries)
                if (e.key is String) e.key as String: deepCopyJson(e.value),
            }
          : null,
      body: LcBlock.parseList(json['body'], 0),
      x: x is num && x.isFinite ? x.toDouble() : null,
      y: y is num && y.isFinite ? y.toDouble() : null,
    );
  }
}

/// 一块库积木背后那个定义的一个参数，用的时候从哪来。
enum BeLibFrom {
  /// 积木上的一个值槽（默认）。
  slot,

  /// 积木上一个只许直接填文字 / 数字的槽（帽子上的名字、路径这种）。
  literal,

  /// 隐含的东西：外面的帽子（或带口的积木）递进来的，积木上没有这一格。[BeLibParam.key]＝叫什么。
  context,

  /// 这份文档里这个库的某个设置项。[BeLibParam.key]＝设置项编号。
  setting,

  /// 预先填死的值。[BeLibParam.value]。
  preset,
}

class BeLibParam {
  const BeLibParam(this.from, {this.key = '', this.value});
  final BeLibFrom from;
  final String key;
  final Object? value;

  bool get onBlock => from == BeLibFrom.slot || from == BeLibFrom.literal;

  Map<String, dynamic> toJson() => {'from': from.name, if (key.isNotEmpty) 'key': key, if (from == BeLibFrom.preset) 'value': value};

  static BeLibParam? tryParse(Object? json) {
    if (json is! Map) return null;
    final from = BeLibFrom.values.where((f) => f.name == json['from']).firstOrNull;
    if (from == null) return null;
    final key = json['key'], value = json['value'];
    return BeLibParam(from, key: key is String ? key : '', value: _plain(value) ? value : null);
  }
}

/// 公开成的一块积木。背后是谁：
/// - [LibHow.call] / [LibHow.expand]：[fn]＝函数（“我的积木”）的 id；
/// - [LibHow.method] / [LibHow.static]：[typeId]＝类的 id，[method]＝方法的 id。
class BeLibDef {
  BeLibDef({
    required this.id,
    required this.how,
    this.fn = '',
    this.typeId = '',
    this.method = '',
    this.look,
    Map<String, BeLibParam>? params,
    this.into = false,
    List<String>? mouths,
    Map<String, String>? provides,
    this.shape,
  }) : params = params ?? {},
       mouths = mouths ?? [],
       provides = provides ?? {};

  /// 积木编号（库里唯一，字母开头的字母数字；用它的文档里存的就是它，所以定了就不改）。
  final String id;
  LibHow how;
  String fn;
  String typeId;
  String method;

  /// 积木的样子。函数背后的可以不写＝用函数自己的外观；方法背后的要写。
  CustomBlockLook? look;

  /// 参数名 → 从哪来。没列到的＝积木上的值槽。
  final Map<String, BeLibParam> params;

  /// 多一个“放进变量”槽（[kBeLibIntoSlot]）：调用型＝把结果写进去；展开型＝定义里的“把 … 交给用的人选的变量”写进去。
  bool into;

  /// 展开型：口的名字（最多两个；定义里用“做口里的积木”指名）。
  final List<String> mouths;

  /// 展开型：给口里的积木递的“隐含的东西”：叫什么 → 定义里的变量名。
  final Map<String, String> provides;

  /// 形状。null＝照外观（函数的“自动”按定义定）。帽子、收尾型在这里选。
  CustomBlockShape? shape;

  Map<String, dynamic> toJson() => {
    'id': id,
    'how': how.name,
    if (fn.isNotEmpty) 'fn': fn,
    if (typeId.isNotEmpty) 'type': typeId,
    if (method.isNotEmpty) 'method': method,
    if (look != null) 'look': look!.toJson(),
    if (params.isNotEmpty) 'params': {for (final e in params.entries) e.key: e.value.toJson()},
    if (into) 'into': true,
    if (mouths.isNotEmpty) 'mouths': mouths,
    if (provides.isNotEmpty) 'provides': provides,
    if (shape != null) 'shape': shape!.name,
  };

  BeLibDef clone() => BeLibDef(id: id, how: how, fn: fn, typeId: typeId, method: method, look: look, params: {...params}, into: into, mouths: [...mouths], provides: {...provides}, shape: shape);

  static final RegExp idPattern = RegExp(r'^[A-Za-z][A-Za-z0-9_]{0,31}$');

  static BeLibDef? tryParse(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final how = LibHow.values.where((h) => h.name == json['how']).firstOrNull;
    if (id is! String || !idPattern.hasMatch(id) || how == null) return null;
    final fn = json['fn'], type = json['type'], method = json['method'], params = json['params'], mouths = json['mouths'], provides = json['provides'];
    return BeLibDef(
      id: id,
      how: how,
      fn: fn is String ? fn : '',
      typeId: type is String ? type : '',
      method: method is String ? method : '',
      look: customBlockLookFromJson(json['look']),
      params: {
        if (params is Map)
          for (final e in params.entries)
            if (e.key is String && BeLibParam.tryParse(e.value) != null) e.key as String: BeLibParam.tryParse(e.value)!,
      },
      into: json['into'] == true,
      mouths: [
        if (mouths is List)
          for (final m in mouths.take(2))
            if (m is String && m.isNotEmpty) m,
      ],
      provides: {
        if (provides is Map)
          for (final e in provides.entries)
            if (e.key is String && e.value is String) e.key as String: e.value as String,
      },
      shape: CustomBlockShape.values.where((s) => s.name == json['shape']).firstOrNull,
    );
  }
}

/// 这份文档是一个库：清单信息＋公开成积木的定义。库的名字就是文档的名字。
class BeLibInfo {
  BeLibInfo({required this.id, this.version = '1.0.0', this.author = '', this.summary = '', List<LibSetting>? settings, List<BeLibDef>? blocks, this.originId = '', this.originVersion = ''})
    : settings = settings ?? [],
      blocks = blocks ?? [];

  /// 库的标识 `作者段/库名`。
  String id;
  String version;
  String author;
  String summary;
  final List<LibSetting> settings;
  final List<BeLibDef> blocks;

  /// “复制一份来改”来的：从哪个库的哪一版复制的（只告知）。
  String originId;
  String originVersion;

  BeLibDef? def(String id) => blocks.where((b) => b.id == id).firstOrNull;

  /// 一个没用过的积木编号。
  String freeDefId() {
    var n = 1;
    while (blocks.any((b) => b.id == 'b$n')) {
      n++;
    }
    return 'b$n';
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'version': version,
    if (author.isNotEmpty) 'author': author,
    if (summary.isNotEmpty) 'summary': summary,
    if (settings.isNotEmpty) 'settings': [for (final s in settings) beLibSettingToJson(s)],
    if (blocks.isNotEmpty) 'blocks': [for (final b in blocks) b.toJson()],
    if (originId.isNotEmpty) 'origin': {'id': originId, 'version': originVersion},
  };

  BeLibInfo clone() =>
      BeLibInfo(id: id, version: version, author: author, summary: summary, settings: [...settings], blocks: [for (final b in blocks) b.clone()], originId: originId, originVersion: originVersion);

  static BeLibInfo? tryParse(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    if (id is! String || !kLibIdPattern.hasMatch(id)) return null;
    final version = json['version'], author = json['author'], summary = json['summary'], origin = json['origin'];
    final settings = <LibSetting>[];
    final rawSettings = json['settings'];
    if (rawSettings is List) {
      for (final raw in rawSettings.take(kLibMaxSettings)) {
        final s = beLibSettingFromJson(raw);
        if (s != null && !settings.any((x) => x.id == s.id)) settings.add(s);
      }
    }
    final blocks = <BeLibDef>[];
    final rawBlocks = json['blocks'];
    if (rawBlocks is List) {
      for (final raw in rawBlocks.take(kBeMaxLibDefs)) {
        final b = BeLibDef.tryParse(raw);
        if (b != null && !blocks.any((x) => x.id == b.id)) blocks.add(b);
      }
    }
    return BeLibInfo(
      id: id,
      version: version is String && RegExp(r'^\d+\.\d+\.\d+$').hasMatch(version) ? version : '1.0.0',
      author: author is String ? author : '',
      summary: summary is String ? summary : '',
      settings: settings,
      blocks: blocks,
      originId: origin is Map && origin['id'] is String ? origin['id'] as String : '',
      originVersion: origin is Map && origin['version'] is String ? origin['version'] as String : '',
    );
  }
}

/// 设置项 → 清单里的写法（和 `lib.json` 的 `settings` 一项一样；[libRead] 读的就是它）。
Map<String, dynamic> beLibSettingToJson(LibSetting s) => {
  'id': s.id,
  'name': s.name,
  'type': lcTypeText(s.type) ?? '任意',
  'default': s.defaultValue,
  if (s.min != null) 'min': s.min,
  if (s.max != null) 'max': s.max,
  if (s.hint.isNotEmpty) 'hint': s.hint,
};

LibSetting? beLibSettingFromJson(Object? raw) {
  if (raw is! Map) return null;
  final id = raw['id'], name = raw['name'], hint = raw['hint'], d = raw['default'];
  final type = libTypeFromText(raw['type']);
  if (id is! String || !BeLibDef.idPattern.hasMatch(id) || type == null || !_plainOrList(d)) return null;
  return LibSetting(
    id: id,
    name: name is String && name.trim().isNotEmpty ? name : id,
    type: type,
    defaultValue: d,
    min: raw['min'] is num ? raw['min'] as num : null,
    max: raw['max'] is num ? raw['max'] as num : null,
    hint: hint is String ? hint : '',
  );
}

/// 作者段 / 库名那一段合不合规矩（小写字母开头，小写字母、数字、连字符，最多 32 个）。
final RegExp kBeLibSegment = RegExp(r'^[a-z][a-z0-9-]{0,31}$');

/// 作者段不许冒充应用自带的。
bool beLibAuthorReserved(String author) => author == 'lopi' || author == 'local';

/// 这个函数有没有被公开成积木。
BeLibDef? beLibDefOfFunction(BeLibInfo? info, BeFunction f) => info?.blocks.where((b) => (b.how == LibHow.call || b.how == LibHow.expand) && b.fn == f.id).firstOrNull;
