/// 核心 2 的积木目录（积木第 5 版·核心 2·A3）：错误、记录、枚举 / 变体、“看是哪种情况”、类与对象。
///
/// 只在规矩版本 2 的文档里出现：单独一张表、不并进 `beBlockSpecs` / `beExprSpecs`（老规矩的文档里没有它们，积木盒、校验、
/// 生成都和以前一样）。类型、种类、情况、字段、方法这些“选哪个”的下拉，选项跟着文档走（`choices` 是空的＝宿主现给）。
/// 积木怎么翻成语法树在 backend_lower_core.dart；怎么存在 docs/blocks-v5-parts/B-impl-notes.md“A3”一节。
library;

import 'package:lopicode/backend/backend_blocks.dart';
import 'package:lopicode/backend/backend_blocks_wait.dart';
import 'package:lopicode/backend/backend_core.dart';
import 'package:lopicode/lang/errors.dart';
import 'package:lopicode/lang/types.dart';
import 'package:lopicode/lowcode/logic_model.dart';

const String kBeCatError = '错误';
const String kBeCatType = '类型';

/// “出错时”那一节的“只接哪一种”：这个值＝什么错都接。
const String kBeCatchAny = '@any';

/// “看是哪种情况”里几种不是枚举 / 变体的情况：可空的值（空 / 有值）、“任意”的值（是哪一类）。
const String kBeCaseNull = '@null';
const String kBeCaseSome = '@some';
const String kBeCaseIsPrefix = '@is:';
const List<String> kBeCaseIsTypes = ['number', 'text', 'bool', 'list', 'dict'];
const Map<String, String> kBeCaseLabels = {kBeCaseNull: '空', kBeCaseSome: '有值', '@is:number': '数字', '@is:text': '文字', '@is:bool': '是 / 否', '@is:list': '列表', '@is:dict': '字典'};

const LcArgSpec _type = LcArgSpec('type', '哪个类型', LcArgKind.choice);
const LcArgSpec _args = LcArgSpec('args', '带上', LcArgKind.exprList);
const LcArgSpec _fields = LcArgSpec('fields', '字段', LcArgKind.exprList);
const LcArgSpec _member = LcArgSpec('name', '哪个', LcArgKind.choice);
const LcArgSpec _of = LcArgSpec('of', '谁', LcArgKind.expr);

const LcArmSpec kBeTryArms = LcArmSpec('出错时', [LcArgSpec('kind', '只接', LcArgKind.choice), LcArgSpec('name', '放进', LcArgKind.literalText, optional: true)], max: 8, tailOptional: true);
const LcArmSpec kBeMatchArms = LcArmSpec('是…时', [LcArgSpec('case', '情况', LcArgKind.choice), LcArgSpec('binds', '带出', LcArgKind.literalText, optional: true)], min: 1, tailOptional: true);

const Map<String, LcBlockSpec> beCoreBlockSpecs = {
  'try': LcBlockSpec('try', '试着做', kBeCatError, [], bodyLabel: '试着做', elseLabel: '最后总要', arms: kBeTryArms, hint: '里面出了错就跳到“出错时”；从上往下第一节对得上的接。“最后总要”不管出没出错都做'),
  'throw': LcBlockSpec('throw', '抛出', kBeCatError, [LcArgSpec('value', '什么', LcArgKind.expr)], hint: '放一句话，或者一个错误对象'),
  'match': LcBlockSpec('match', '看是哪种情况', kBeCatType, [LcArgSpec('value', '看谁', LcArgKind.expr)], elseLabel: '其他情况', arms: kBeMatchArms, hint: '枚举、变体、可能是空的值、“任意”的值都能看；每种情况一段，带的东西放进变量'),
  'setField': LcBlockSpec('setField', '改字段', kBeCatType, [_of, _member, LcArgSpec('value', '改成', LcArgKind.expr)], hint: '改对象的字段（记录建好不能改，用“复制并改”）'),
  'callMethodStmt': LcBlockSpec('callMethodStmt', '让对象做', kBeCatType, [_of, _member, _args], hint: '调对象的方法，结果不要'),
  'superInit': LcBlockSpec('superInit', '调父类的创建时', kBeCatType, [_args], hint: '只能是子类“创建时”的第一句'),
  'superCallStmt': LcBlockSpec('superCallStmt', '调父类的方法', kBeCatType, [_member, _args], hint: '重写的方法里，接着做父类原来的那一段'),
  ...beWaitBlockSpecs,
};

const Map<String, LcExprSpec> beCoreExprSpecs = {
  'errNew': LcExprSpec('errNew', '新建错误', kBeCatError, [
    LcArgSpec('kind', '种类', LcArgKind.choice),
    LcArgSpec('message', '消息', LcArgKind.expr, valueType: LcType.text),
    _fields,
  ], hint: '一个错误对象：种类、消息，自己定义的种类还能带字段'),
  'getField': LcExprSpec('getField', '读字段', kBeCatType, [_of, _member], hint: '错误的消息 / 种类、记录的字段、对象的字段'),
  'recNew': LcExprSpec('recNew', '新建记录', kBeCatType, [_type, _fields], hint: '每个字段都要给；建好以后不能改'),
  'recCopy': LcExprSpec('recCopy', '复制并改', kBeCatType, [_of, _fields], hint: '得到一份新的记录，写出来的字段换成新值'),
  'enumVal': LcExprSpec('enumVal', '枚举的值', kBeCatType, [_type, LcArgSpec('case', '情况', LcArgKind.choice)], hint: '枚举的其中一个'),
  'varNew': LcExprSpec('varNew', '造一种情况', kBeCatType, [_type, LcArgSpec('case', '情况', LcArgKind.choice), _args], hint: '变体的其中一种情况，带上它要的东西'),
  'classNew': LcExprSpec('classNew', '新建对象', kBeCatType, [_type, _args], hint: '照“创建时”要的参数给'),
  'callMethod': LcExprSpec('callMethod', '对象的方法', kBeCatType, [_of, _member, _args], hint: '调对象的方法，拿它交回的东西'),
  'superCall': LcExprSpec('superCall', '父类的方法', kBeCatType, [_member, _args], hint: '重写的方法里，拿父类原来那一段交回的东西'),
  'this': LcExprSpec('this', '我自己', kBeCatType, [], hint: '正在做事的这个对象；只能用在方法和“创建时”里'),
  'isA': LcExprSpec('isA', '是不是某类', kBeCatType, [LcArgSpec('x', '谁', LcArgKind.expr), _type], hint: '是这个类（或它的子类）、实现了这个接口'),
  'classRef': LcExprSpec('classRef', '类本身', kBeCatType, [_type], hint: '读、改、调“类本身的”字段和方法时放在“谁”那一格'),
  ...beWaitExprSpecs,
};

const Map<String, String> beCoreBlockSentences = {
  'try': '试着做',
  'throw': '抛出 {value}',
  'match': '看 {value} 是哪种情况',
  'setField': '把 {of} 的 {name} 改成 {value}',
  'callMethodStmt': '让 {of} 做 {name} {args}',
  'superInit': '调父类的创建时 {args}',
  'superCallStmt': '调父类的 {name} {args}',
  ...beWaitBlockSentences,
};

const Map<String, String> beCoreArmSentences = {'try': '出错时 只接 {kind} 放进 {name}', 'match': '是 {case} 时 带出 {binds}'};

const Map<String, String> beCoreExprSentences = {
  'errNew': '新建错误 {kind} 消息 {message} {fields}',
  'getField': '{of} 的 {name}',
  'recNew': '新建 {type} {fields}',
  'recCopy': '复制 {of} 并改 {fields}',
  'enumVal': '{type} 的 {case}',
  'varNew': '造 {type} 的 {case} {args}',
  'classNew': '新建 {type} {args}',
  'callMethod': '{of} 的 {name} {args}',
  'superCall': '父类的 {name} {args}',
  'this': '我自己',
  'isA': '{x} 是不是 {type}',
  'classRef': '{type} 这个类',
  ...beWaitExprSentences,
};

bool beIsCoreOp(Object? op) => beCoreBlockSpecs.containsKey(op);
bool beIsCoreExpr(Object? kind) => beCoreExprSpecs.containsKey(kind);

/// 一串积木里有没有核心 2 的积木 / 值。
bool beBlocksUseCore(List<LcBlock> list) {
  var found = false;
  bool inValue(Object? v, int depth) {
    if (depth > kMaxExprDepth * 2 + 4 || v is List<LcBlock>) return false;
    if (v is List) return v.any((x) => inValue(x, depth + 1));
    if (v is! Map) return false;
    return beIsCoreExpr(v['e']) || v.values.any((x) => inValue(x, depth + 1));
  }

  void walk(List<LcBlock> blocks, int depth) {
    if (found || depth > LcBlock.maxDepth + 2) return;
    for (final b in blocks) {
      if (beIsCoreOp(b.op) || b.args.values.any((v) => inValue(v, 0)) || b.arms.any((a) => a.args.values.any((v) => inValue(v, 0)))) {
        found = true;
        return;
      }
      walk(b.body, depth + 1);
      walk(b.orElse, depth + 1);
      for (final a in b.arms) {
        walk(a.body, depth + 1);
      }
      for (final m in b.exprMouths) {
        walk(m, depth + 1);
      }
    }
  }

  walk(list, 0);
  return found;
}

/// “带出”那一格里写的几个名字（逗号、顿号、空格隔开）。
List<String> beBindNames(Object? raw) => raw is! String
    ? const []
    : [
        for (final n in raw.split(RegExp(r'[,，、\s]+')))
          if (n.isNotEmpty) n,
      ];

/// 这种类型的默认值积木（新建记录补字段、新建对象补参数时垫上）。
Map<String, dynamic> beDefaultExprOf(LType t) {
  if (t.nullable) return {'e': 'null'};
  return switch (t.kind) {
    LKind.integer || LKind.number => exNum(0),
    LKind.bool => exBool(false),
    LKind.list => {'e': 'listLit', 'items': <dynamic>[]},
    LKind.dict => {'e': 'obj', 'fields': <dynamic>[]},
    _ => exText(''),
  };
}

Map<String, dynamic> _pairs(Iterable<BeField> fields) => {
  'fields': [for (final f in fields) bePair(f.name, beDefaultExprOf(f.type))],
};

/// 错误种类 [kind] 新建时除了消息还要给哪些字段（自己定义的错误种类才有；顺着父类从上往下排）。
List<BeField> beErrorFields(BeCore core, String? kind) {
  final t = core.typeNamed(kind);
  if (t == null || t.kind != BeTypeKind.error) return const [];
  return [
    for (final p in core.parentsOf(t).reversed)
      if (p.kind == BeTypeKind.error) ...p.fields,
    ...t.fields,
  ];
}

/// 类 [t] 的“创建时”要几个参数（自己没写就看父类的）。
List<String> beCtorParams(BeCore core, BeTypeDef t) {
  for (final c in [t, ...core.parentsOf(t)]) {
    if (c.kind == BeTypeKind.error) return [kErrMessageField, for (final f in beErrorFields(core, c.name)) f.name];
    if (c.ctor != null) return [for (final p in c.ctor!.params) p.name];
  }
  return langIsBuiltinError(t.parent) || core.parentsOf(t).any((p) => langIsBuiltinError(p.parent)) ? const [kErrMessageField] : const [];
}

/// 积木盒里拖出来的新的一块值；不是核心 2 的返回 null。[type]＝指定是哪个类型 / 种类（积木盒里一个类型一块）。
Map<String, dynamic>? newBeCoreExpr(String kind, BeCore core, {String? type}) {
  BeTypeDef? first(bool Function(BeTypeDef t) ok) => core.typeNamed(type) ?? core.types.where(ok).firstOrNull;
  switch (kind) {
    case 'errNew':
      final k = type ?? kErrBase;
      return {'e': kind, 'kind': k, 'message': exText('出错了'), ..._pairs(beErrorFields(core, k))};
    case 'getField':
      return {'e': kind, 'of': null, 'name': type ?? kErrMessageField};
    case 'recNew':
      final t = first((t) => t.kind == BeTypeKind.record);
      return {'e': kind, 'type': t?.name ?? '', ..._pairs(t?.fields ?? const [])};
    case 'recCopy':
      return {'e': kind, 'of': null, 'fields': <dynamic>[]};
    case 'enumVal':
      final t = first((t) => t.kind == BeTypeKind.enumeration);
      return {'e': kind, 'type': t?.name ?? '', 'case': t?.cases.firstOrNull?.name ?? ''};
    case 'varNew':
      final t = first((t) => t.kind == BeTypeKind.variant);
      final c = t?.cases.firstOrNull;
      return {
        'e': kind,
        'type': t?.name ?? '',
        'case': c?.name ?? '',
        'args': [for (final f in c?.fields ?? const <BeField>[]) beDefaultExprOf(f.type)],
      };
    case 'classNew':
      final t = first((t) => t.kind == BeTypeKind.klass);
      return {
        'e': kind,
        'type': t?.name ?? '',
        'args': [
          if (t != null)
            for (final _ in beCtorParams(core, t)) exText(''),
        ],
      };
    case 'callMethod':
      return {'e': kind, 'of': null, 'name': type ?? '', 'args': <dynamic>[]};
    case 'superCall':
      return {'e': kind, 'name': type ?? '', 'args': <dynamic>[]};
    case 'this':
      return {'e': kind};
    case 'isA':
      return {'e': kind, 'x': null, 'type': type ?? core.types.where((t) => t.isClassLike || t.kind == BeTypeKind.interface).firstOrNull?.name ?? kErrBase};
    case 'classRef':
      return {'e': kind, 'type': first((t) => t.kind == BeTypeKind.klass)?.name ?? ''};
  }
  return newBeWaitExpr(kind);
}

/// 积木盒里拖出来的新的一块语句；不是核心 2 的返回 null。
LcBlock? newBeCoreBlock(String op, BeCore core) => switch (op) {
  'try' => LcBlock(
    op: op,
    arms: [
      LcArm(args: {'kind': kBeCatchAny, 'name': 'e'}),
    ],
    noElse: true,
  ),
  'throw' => LcBlock(op: op, args: {'value': exText('出错了')}),
  'match' => LcBlock(
    op: op,
    args: {'value': null},
    arms: [
      LcArm(args: {'case': '', 'binds': ''}),
    ],
    noElse: true,
  ),
  'setField' => LcBlock(op: op, args: {'of': null, 'name': '', 'value': exText('')}),
  'callMethodStmt' => LcBlock(op: op, args: {'of': null, 'name': '', 'args': <dynamic>[]}),
  'superInit' => LcBlock(op: op, args: {'args': <dynamic>[]}),
  'superCallStmt' => LcBlock(op: op, args: {'name': '', 'args': <dynamic>[]}),
  _ => newBeWaitBlock(op),
};

String _label(Object? v, [String missing = '（没选）']) => v is String && v.isNotEmpty ? (kBeCaseLabels[v] ?? (v == kBeCatchAny ? '任何错误' : v)) : missing;

/// 读成人话（问题列表里“第 2 块（…）”那半句用）；不是核心 2 的返回 null。
String? describeBeCoreExpr(Object? expr, String Function(String key) sub) {
  final e = expr is Map ? expr : const <String, dynamic>{};
  return switch (e['e']) {
    'errNew' => '新建错误 ${_label(e['kind'])}（${sub('message')}）',
    'getField' => '${sub('of')} 的 ${_label(e['name'])}',
    'recNew' => '新建 ${_label(e['type'])}',
    'recCopy' => '复制 ${sub('of')} 并改',
    'enumVal' => '${_label(e['type'])} 的 ${_label(e['case'])}',
    'varNew' => '造 ${_label(e['type'])} 的 ${_label(e['case'])}',
    'classNew' => '新建 ${_label(e['type'])}',
    'callMethod' => '${sub('of')} 的 ${_label(e['name'])}（…）',
    'superCall' => '父类的 ${_label(e['name'])}（…）',
    'this' => '我自己',
    'isA' => '${sub('x')} 是不是 ${_label(e['type'])}',
    'classRef' => '${_label(e['type'])} 这个类',
    _ => describeBeWaitExpr(expr, sub),
  };
}

String? describeBeCoreBlock(LcBlock b, String Function(String name) arg) => switch (b.op) {
  'try' => '试着做…${b.arms.isEmpty ? '' : '出错时…（共 ${b.arms.length} 节）'}${b.noElse ? '' : '最后总要…'}',
  'throw' => '抛出 ${arg('value')}',
  'match' => '看 ${arg('value')} 是哪种情况（共 ${b.arms.length} 段）',
  'setField' => '把 ${arg('of')} 的 ${_label(b.args['name'])} 改成 ${arg('value')}',
  'callMethodStmt' => '让 ${arg('of')} 做 ${_label(b.args['name'])}',
  'superInit' => '调父类的创建时',
  'superCallStmt' => '调父类的 ${_label(b.args['name'])}',
  _ => describeBeWaitBlock(b, arg),
};
