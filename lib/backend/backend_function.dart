/// 后端文档里的“函数 / 我的积木”（积木第 4 版·第 2 阶段）：一个函数＝一串“定义 …”帽子下面的积木 ＋ 参数表 ＋ 外观。
///
/// 存盘（`backend.lc.json` 顶层的 `functions`，没有函数就不写这个键——旧文档读进来再存出去一个字节不差）：
///
/// ```json
/// {"id": "f1", "look": {…CustomBlockLook…}, "params": [{"name": "名字"}, {"name": "次数", "default": 1}, {"name": "其余", "rest": true}],
///  "x": 24, "y": 300, "body": [积木…]}
/// ```
///
/// 调用它的积木：语句是 `{"op": "call:f1", "args": {"名字": 值, …}}`，当值用是 `{"e": "call:f1", "名字": 值, …}`
/// ——按 id 认（改名不用动调用），实参按**参数名**存。
/// 读的时候容错：坏的条目逐条跳过，坏的参数、坏的外观当默认，绝不抛异常。
library;

import 'package:lopicode/lang/custom_block.dart';
import 'package:lopicode/lowcode/logic_model.dart';

/// 调用自定义积木的 op / e 的前缀：`call:<函数 id>`。
const String kBeCallPrefix = 'call:';

/// 一个函数最多几个参数（和编辑器里匿名函数的上限一样；多出来的读的时候丢掉）。**按建议先做，可改。**
const int kBeMaxParams = 6;

/// 一份文档最多几个函数（再多积木盒里也找不过来）。**按建议先做，可改。**
const int kBeMaxFunctions = 64;

/// 函数 id 只留这些字符。
final RegExp _idPattern = RegExp(r'^[A-Za-z0-9_]{1,32}$');

String beCallOp(String id) => '$kBeCallPrefix$id';

/// `call:f1` → `f1`；不是调用返回 null。
String? beCallId(Object? op) => op is String && op.length > kBeCallPrefix.length && op.startsWith(kBeCallPrefix) ? op.substring(kBeCallPrefix.length) : null;

/// 参数名里不能用的：`e`（表达式对象里它是“种类”那个键）和 `@` 开头的（留给 `@body` 这类保留键）。
bool beParamNameReserved(String name) => name == 'e' || name.startsWith('@');

/// 把用户起的名字（函数名、参数名，常常是中文）变成能写进五种语言代码里的名字：
/// 英文字母、数字、下划线、汉字原样留着，别的字符一律换成下划线；空的、数字开头的前面垫一个下划线。
/// 生成器会再加前缀（函数 `f_`、变量 `v_`），所以不怕撞上各语言的保留字。
String beIdent(String name) {
  final sb = StringBuffer();
  for (final r in name.trim().runes) {
    final ok = (r >= 0x30 && r <= 0x39) || (r >= 0x41 && r <= 0x5A) || (r >= 0x61 && r <= 0x7A) || r == 0x5F || (r >= 0x4E00 && r <= 0x9FFF);
    sb.write(ok ? String.fromCharCode(r) : '_');
  }
  final s = sb.toString();
  return s.isEmpty || (s.codeUnitAt(0) >= 0x30 && s.codeUnitAt(0) <= 0x39) ? '_$s' : s;
}

/// 默认值只许是直接填的：文字、有限的数字、是 / 否。别的当没有。
Object? beParamDefault(Object? v) => v is String || v is bool || (v is num && v.isFinite) ? v : null;

/// 函数的一个参数。
class BeParam {
  BeParam(this.name, {Object? defaultValue, this.rest = false}) : defaultValue = beParamDefault(defaultValue);

  String name;

  /// 默认值（文字 / 数字 / 是否）；null＝没有。
  Object? defaultValue;

  /// “剩下的全收”。
  bool rest;

  Map<String, dynamic> toJson() => {'name': name, 'default': ?defaultValue, if (rest) 'rest': true};

  BeParam clone() => BeParam(name, defaultValue: defaultValue, rest: rest);

  static BeParam? tryParse(Object? json) {
    if (json is! Map) return null;
    final name = json['name'];
    if (name is! String || name.trim().isEmpty) return null;
    return BeParam(name.trim(), defaultValue: json['default'], rest: json['rest'] == true);
  }
}

/// 一个函数（画布上一串“定义 [名字] (参数…)”）。名字在外观里（[CustomBlockLook.name]）。
class BeFunction with LcBlockTree {
  BeFunction({required this.id, required this.look, List<BeParam>? params, List<LcBlock>? body, double? x, double? y}) : params = params ?? [], body = body ?? [] {
    this.x = x;
    this.y = y;
  }

  @override
  String id;
  CustomBlockLook look;
  final List<BeParam> params;
  @override
  final List<LcBlock> body;

  String get name => look.name;
  List<String> get paramNames => [for (final p in params) p.name];

  /// 这个函数在生成的代码里叫什么（各语言再加 `f_`）。
  String get ident => beIdent(look.name);

  Map<String, dynamic> toJson() => {
    'id': id,
    'look': look.toJson(),
    'params': [for (final p in params) p.toJson()],
    if (x != null) 'x': x,
    if (y != null) 'y': y,
    'body': [for (final b in body) b.toJson()],
  };

  BeFunction clone() => BeFunction(id: id, look: look, params: [for (final p in params) p.clone()], body: [for (final b in body) b.clone()], x: x, y: y);

  /// 不是对象的跳过；外观坏了给一个叫“积木”的默认外观；参数坏的逐个跳过、重名的只留第一个、超过上限的丢掉。
  static BeFunction? tryParse(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final x = json['x'];
    final y = json['y'];
    final params = <BeParam>[];
    final rawParams = json['params'];
    if (rawParams is List) {
      for (final raw in rawParams) {
        final p = BeParam.tryParse(raw);
        if (p != null && params.length < kBeMaxParams && !params.any((o) => o.name == p.name)) params.add(p);
      }
    }
    return BeFunction(
      id: id is String ? id : '',
      look: customBlockLookFromJson(json['look']) ?? const CustomBlockLook('积木'),
      params: params,
      body: LcBlock.parseList(json['body'], 0),
      x: x is num && x.isFinite ? x.toDouble() : null,
      y: y is num && y.isFinite ? y.toDouble() : null,
    );
  }

  static bool validId(String id) => _idPattern.hasMatch(id);
}

/// 给新函数挑一个没人用的 id：`f1`、`f2`…（[used] 里是已经占了的，含接口的 id）。
String beFreeFunctionId(Set<String> used) {
  var n = 1;
  while (used.contains('f$n')) {
    n++;
  }
  return 'f$n';
}
