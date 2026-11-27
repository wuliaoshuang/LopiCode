/// 两块类型积木（“当成某类型用”“标上类型”）和原生绑定积木（“调宿主接口”）：目录、下拉、默认值、念出来的话、怎么翻成语法树。
/// （第三块类型积木“看是哪一类值”早就有：`isType`，在“运算”页的“类型”一组。）
///
/// 和核心 2、核心 3 的积木一样只在规矩版本 2（严格规矩）的文档里出现，接在 backend_blocks_core.dart 的那几张表后面。
/// - 类型存成语言核心文字写法里的那种写法（`整数`、`(列表 文字)`、`名片`），下拉里给的是常用的那些：基础类型、它们的列表和字典、
///   文档里定义的类型和它们的列表。更复杂的（函数类型、可空、套两层的）下拉里没有，文字写法的库里照样能写。
/// - “调宿主接口”只在库的画布上出现，而且要“自己的库能直接用宿主接口”那个开关（rules.dart 的 `userLibHostEntry`）开着：
///   关着时积木盒里没有它；文档里已经有的（别处来的源文件）每一块都报清楚的问题，不会悄悄做出一份用不了的库。
library;

import 'package:lopicode/backend/backend_blocks_core.dart';
import 'package:lopicode/backend/backend_blocks_raw.dart';
import 'package:lopicode/backend/backend_core.dart';
import 'package:lopicode/backend/backend_lower_core.dart';
import 'package:lopicode/backend/backend_model.dart';
import 'package:lopicode/blocks/block_host.dart';
import 'package:lopicode/lang/ast.dart';
import 'package:lopicode/lang/host_front.dart';
import 'package:lopicode/lang/host_v2.dart';
import 'package:lopicode/lang/lc_text.dart';
import 'package:lopicode/lang/lc_write.dart';
import 'package:lopicode/lang/lib_native.dart';
import 'package:lopicode/lang/rt_v2.dart';
import 'package:lopicode/lang/rules.dart';
import 'package:lopicode/lang/types.dart';
import 'package:lopicode/lowcode/logic_blocks.dart';
import 'package:lopicode/lowcode/logic_model.dart';

const String kBeCast = 'castTo';
const String kBeAscribe = 'ascribe';
const String kBeHostCall = 'hostCall';
const String kBeHostCallStmt = 'hostCallStmt';

const LcArgSpec _x = LcArgSpec('x', '谁', LcArgKind.expr);
const LcArgSpec _to = LcArgSpec('to', '哪个类型', LcArgKind.choice);
const LcArgSpec _host = LcArgSpec('name', '哪个接口', LcArgKind.choice);
const LcArgSpec _args = LcArgSpec('args', '带上', LcArgKind.exprList);

const Map<String, LcExprSpec> beTypeOpExprSpecs = {
  kBeCast: LcExprSpec(kBeCast, '当成某类型用', kBeCatType, [_x, _to], hint: '运行到这里会查一下它是不是这个类型，不是就出错；永远成不了的，搭的时候就报'),
  kBeAscribe: LcExprSpec(kBeAscribe, '标上类型', kBeCatType, [_x, _to], hint: '告诉检查“这个值按这个类型看”，运行时不多做事；放不进去搭的时候就报'),
  kBeHostCall: LcExprSpec(kBeHostCall, '调宿主接口（要结果）', kBeCatType, [_host, _args], hint: '直接调应用给的最底下的接口，拿它交回的东西。只有库里能用'),
};

const Map<String, LcBlockSpec> beTypeOpBlockSpecs = {
  kBeHostCallStmt: LcBlockSpec(kBeHostCallStmt, '调宿主接口', kBeCatType, [_host, _args], hint: '直接调应用给的最底下的接口，结果不要。只有库里能用'),
};

const Map<String, String> beTypeOpExprSentences = {kBeCast: '把 {x} 当成 {to}', kBeAscribe: '{x} 标成 {to}', kBeHostCall: '宿主接口 {name} {args}'};
const Map<String, String> beTypeOpBlockSentences = {kBeHostCallStmt: '调宿主接口 {name} {args}'};

/// 搜索用的别名。
const Map<String, List<String>> beTypeOpAliases = {
  'expr:$kBeCast': ['类型', '转成', '当作', '强转', 'as', 'cast'],
  'expr:$kBeAscribe': ['类型', '标注', '注明', 'type'],
  'expr:$kBeHostCall': ['宿主', '原生', '接口', 'native'],
  'block:$kBeHostCallStmt': ['宿主', '原生', '接口', 'native'],
};

bool beIsHostCall(Object? kindOrOp) => kindOrOp == kBeHostCall || kindOrOp == kBeHostCallStmt;

// ———————————————————————— 类型的下拉 ————————————————————————

const List<LType> _basics = [LType.number, LType.integer, LType.text, LType.boolean, LType.any];

/// 类型 → 存在积木里的那个字（语言核心文字写法里的类型写法）。
String beTypeKey(LType t) => lcTypeText(t) ?? '任意';

/// 存在积木里的字 → 类型；读不出来返回 null。
LType? beTypeOfKey(Object? key) {
  if (key is! String || key.trim().isEmpty) return null;
  try {
    final parsed = lcParse(key);
    return parsed.length == 1 ? LcReader(const []).ty(parsed.single) : null;
  } on Object {
    return null;
  }
}

/// 下拉里的类型：基础的、它们的列表和字典、文档里定义的类型和它们的列表。
List<BlockOption> beTypeOptions(BeCore core) {
  final named = [for (final t in core.types) LType.ref(t.name)];
  return [
    for (final t in _basics) BlockOption(beTypeKey(t), t.show()),
    for (final t in _basics) BlockOption(beTypeKey(LType.listOf(t)), LType.listOf(t).show(), hint: '列表'),
    for (final t in _basics) BlockOption(beTypeKey(LType.dictOf(t)), LType.dictOf(t).show(), hint: '字典'),
    for (final t in named) BlockOption(beTypeKey(t), t.show(), hint: '这份文档里定义的'),
    for (final t in named) BlockOption(beTypeKey(LType.listOf(t)), LType.listOf(t).show(), hint: '列表'),
  ];
}

/// 下拉里选中的那个字怎么显示（不在下拉里的——文字写法的库里写的复杂类型——也念得出来）。
String? beTypeLabel(Object? key) => beTypeOfKey(key)?.show();

// ———————————————————————— 宿主接口的下拉 ————————————————————————

/// 这一边的库能声明的宿主接口（“都行”的库不能碰宿主接口：一个都没有）。
Map<String, LRtSig> beHostTable(LibSide side) => switch (side) {
  LibSide.frontend => {
    for (final e in kHostFront.entries)
      if (!kHostFrontBuiltinOnly.contains(e.key)) e.key: e.value,
  },
  LibSide.backend => kHostV2,
  LibSide.both => const {},
};

List<BlockOption> beHostOptions(LibSide side) => [for (final e in beHostTable(side).entries) BlockOption(e.key, e.key, hint: e.value.label)];

/// 这块“调宿主接口”现在用不了的原因；能用返回 null。[doc]＝它所在的文档。
String? beHostCallProblem(BeDocument doc, Object? name) {
  final lib = doc.library;
  if (lib == null) return '“调宿主接口”只能用在库里（这份文档不是库）';
  if (!userLibHostEntry) return '这块积木直接调宿主接口。这一版自己的库还不能直接碰宿主接口，只有应用自带的库可以：带着它，这个库出不了库文件、谁也用不了';
  if (lib.side == LibSide.both) return '这个库写的是“后端和前端都行”，两边都能用的库只能用语言核心，不能调宿主接口';
  if (name is! String || name.isEmpty) return '还没选调哪个宿主接口';
  if (!beHostTable(lib.side).containsKey(name)) return '${lib.side.label}这一边没有叫「$name」的宿主接口';
  return null;
}

/// 文档里用到的宿主接口的名字（照出现的先后）。只有库文档里才找。
List<String> beHostsUsed(BeDocument doc) {
  if (doc.library == null) return const [];
  final out = <String>[];
  void walk(Object? v) {
    if (v is Map) {
      // “文字原样”里直接写了“宿”的，和“调宿主接口”积木一样算。
      if (v['e'] == kBeRawExpr || v['op'] == kBeRawStmt) {
        final src = v['e'] != null ? v['src'] : (v['args'] is Map ? (v['args'] as Map)['src'] : null);
        for (final n in beRawHosts(src, isExpr: v['e'] != null)) {
          if (!out.contains(n)) out.add(n);
        }
      }
      if (beIsHostCall(v['e']) || beIsHostCall(v['op'])) {
        final args = v['e'] != null ? v : v['args'];
        final n = args is Map ? args['name'] : null;
        if (n is String && n.isNotEmpty && !out.contains(n)) out.add(n);
      }
      v.values.forEach(walk);
    } else if (v is List) {
      v.forEach(walk);
    }
  }

  walk(doc.toJson());
  return out;
}

/// 用到的宿主接口各要一句声明（参数、交回的类型照宿主接口表）。表里没有的不声明（检查会报）。
List<LNativeDecl> beHostDecls(BeDocument doc) {
  final lib = doc.library;
  if (lib == null) return const [];
  final table = beHostTable(lib.side);
  return [
    for (final n in beHostsUsed(doc))
      if (table[n] case final sig?) LNativeDecl(n, [for (final (i, t) in sig.params.indexed) LParam('p${i + 1}', type: t)], type: sig.ret),
  ];
}

// ———————————————————————— 新的一块、念出来的话 ————————————————————————

Map<String, dynamic>? newBeTypeOpExpr(String kind) => switch (kind) {
  kBeCast || kBeAscribe => {'e': kind, 'x': null, 'to': beTypeKey(LType.text)},
  kBeHostCall => {'e': kind, 'name': '', 'args': <dynamic>[]},
  _ => null,
};

LcBlock? newBeTypeOpBlock(String op) => op == kBeHostCallStmt ? LcBlock(op: op, args: {'name': '', 'args': <dynamic>[]}) : null;

String _typeWord(Object? key) => beTypeLabel(key) ?? '（没选类型）';
String _hostWord(Object? name) => name is String && name.isNotEmpty ? name : '（没选）';

String? describeBeTypeOpExpr(Object? expr, String Function(String key) sub) => switch (expr is Map ? expr['e'] : null) {
  kBeCast => '把 ${sub('x')} 当成 ${_typeWord((expr as Map)['to'])}',
  kBeAscribe => '${sub('x')} 标成 ${_typeWord((expr as Map)['to'])}',
  kBeHostCall => '宿主接口 ${_hostWord((expr as Map)['name'])}（…）',
  _ => null,
};

String? describeBeTypeOpBlock(LcBlock b) => b.op == kBeHostCallStmt ? '调宿主接口 ${_hostWord(b.args['name'])}（…）' : null;

// ———————————————————————— 翻成语法树 ————————————————————————

List<LExpr> _list(BeCoreCx cx, Object? raw) => [
  if (raw is List)
    for (final (i, item) in raw.indexed) cx.lx(item, raw, i),
];

/// 值 → 语法树；不是这里的返回 null。
LExpr? beTypeOpExpr(String kind, Map<dynamic, dynamic> e, BeCoreCx cx) {
  if (!beTypeOpExprSpecs.containsKey(kind)) return null;
  if (kind == kBeHostCall) {
    final n = e['name'];
    if (n is! String || n.isEmpty) {
      cx.note('宿主接口没选好，当成空的');
      return const LLit(null);
    }
    return LNative(n, _list(cx, e['args']), src: cx.src());
  }
  final to = beTypeOfKey(e['to']);
  final x = cx.lx(e['x'], e, 'x');
  if (to == null) {
    cx.note('类型没选好，原样用');
    return x;
  }
  return kind == kBeCast ? LCast(x, to, src: cx.src()) : LAscribe(x, to, src: cx.src());
}

/// 语句 → 语法树；不是这里的返回 null。
List<LStmt>? beTypeOpBlock(LcBlock b, BeCoreCx cx) {
  if (b.op != kBeHostCallStmt) return null;
  final n = b.args['name'];
  if (n is! String || n.isEmpty) {
    cx.note('宿主接口没选好，这一块跳过了');
    return const [];
  }
  return [LExprStmt(LNative(n, _list(cx, b.args['args'])), src: cx.src())];
}
