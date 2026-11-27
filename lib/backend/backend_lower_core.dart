/// 核心 2 的积木怎么翻成语法树（积木第 5 版·核心 2·A3）：错误、记录、枚举 / 变体、“看是哪种情况”、类与对象；
/// 以及文档里定义的类型、模块顶上的变量、模块怎么变成声明（`LRecordDecl`、`LClassDecl`…、`LProgram`）。
///
/// 积木里面套着的值、口里的积木还是 backend_lower_lang.dart 翻；它把“怎么翻一格”“怎么翻一个口”借给这边（[BeCoreCx]）。
/// 这里不碰界面、不改文档；任何输入都不抛异常（没填好的当成空、跳过并留一句说明）。
library;

import 'package:lopicode/backend/backend_blocks_core.dart';
import 'package:lopicode/backend/backend_core.dart';
import 'package:lopicode/backend/backend_function.dart';
import 'package:lopicode/backend/backend_lower_wait.dart';
import 'package:lopicode/backend/backend_model.dart';
import 'package:lopicode/lang/ast.dart';
import 'package:lopicode/lang/errors.dart';
import 'package:lopicode/lang/rt.dart';
import 'package:lopicode/lang/types.dart';
import 'package:lopicode/lowcode/logic_model.dart';

/// backend_lower_lang.dart 借过来的几样。
class BeCoreCx {
  const BeCoreCx({required this.lx, required this.src, required this.note, required this.core, required this.temp, this.pure = false});

  /// 积木文档里的一个值 → 语法树的式子（顺手记来处）：[holder]＝装着它的东西，[key]＝在里面叫什么；[arg]＝积木上的哪个参数（值里面的不用给）。
  final LExpr Function(Object? value, Object? holder, Object? key, {String? arg}) lx;

  /// 这一块 / 这一格的来源（[arg] 不给＝整块；值里面不用给）。
  final LSrc Function([String? arg]) src;
  final void Function(String note) note;

  /// 文档里定义的类型（新建错误时按定义的顺序排字段要用）；没有也能翻。
  final BeCore? core;

  /// 只出语言核心的东西（见 `BeLangLower.pure`）。
  final bool pure;

  /// 要一个不重样的号（“看是哪种情况”先把要看的值存进临时变量）。
  final int Function() temp;
}

/// 旧式子转出来的东西里，调小库的那一层（`LNative`）换成语言核心的小库调用（`LRt`）——版本 2 的生成器只认后者。
/// 语言核心的小库里没有的（数据集合、请求那些）原样留着，[bePureProblem] 会把它认出来。
LExpr bePureExpr(LExpr x, {required bool pure}) {
  if (!pure || x is! LNative) return x;
  final args = [for (final a in x.args) bePureExpr(a, pure: true)];
  return kLangCoreFns.containsKey(x.name) || kLangRtFns.containsKey(x.name) ? LRt(x.name, args) : LNative(x.name, args);
}

String? _name(Object? v) => v is String && beCoreNamePattern.hasMatch(v) ? v : null;

List<LExpr> _list(BeCoreCx cx, Object? raw, {String? arg}) => [
  if (raw is List)
    for (final (i, item) in raw.indexed) cx.lx(item, raw, i, arg: arg),
];

List<LFieldInit> _inits(BeCoreCx cx, Object? raw, {String? arg}) {
  final out = <LFieldInit>[];
  if (raw is! List) return out;
  for (final p in raw) {
    final key = p is Map && p['e'] == 'pair' ? _name(p['key']) : null;
    if (key == null) {
      cx.note('有一个字段没填名字，已跳过');
      continue;
    }
    out.add(LFieldInit(key, cx.lx((p as Map)['value'], p, 'value', arg: arg)));
  }
  return out;
}

/// 核心 2 的值 → 语法树；不是的返回 null。
LExpr? beCoreExpr(String kind, Object? e, BeCoreCx cx) {
  if (e is! Map || !beIsCoreExpr(kind)) return null;
  LExpr sub(String key) => cx.lx(e[key], e, key);
  const hole = LLit(null);
  String? pick(String key, String what) {
    final n = _name(e[key]);
    if (n == null) cx.note('$what没选好，当成空的');
    return n;
  }

  switch (kind) {
    case 'errNew':
      final k = pick('kind', '错误的种类');
      if (k == null) return hole;
      final inits = _inits(cx, e['fields']);
      final order = cx.core == null ? null : [for (final f in beErrorFields(cx.core!, k)) f.name];
      // 自己定义的错误种类：“创建时”的参数是 消息、然后是各个字段（照定义的先后）；少给的后面会报参数个数不对。
      final args = order == null ? [for (final i in inits) i.value] : [for (final n in order) ...inits.where((i) => i.name == n).take(1).map((i) => i.value)];
      return LNew(k, [sub('message'), ...args], src: cx.src());
    case 'getField':
      final n = pick('name', '字段');
      return n == null ? hole : LField(sub('of'), n, src: cx.src());
    case 'recNew':
      final t = pick('type', '记录');
      return t == null ? hole : LRecordNew(t, _inits(cx, e['fields']), src: cx.src());
    case 'recCopy':
      return LRecordCopy(sub('of'), _inits(cx, e['fields']), src: cx.src());
    case 'enumVal':
      final t = pick('type', '枚举'), c = t == null ? null : pick('case', '情况');
      return c == null ? hole : LEnumValue(t!, c, src: cx.src());
    case 'varNew':
      final t = pick('type', '变体'), c = t == null ? null : pick('case', '情况');
      return c == null ? hole : LVariantNew(t!, c, _list(cx, e['args']), src: cx.src());
    case 'classNew':
      final t = pick('type', '类');
      return t == null ? hole : LNew(t, _list(cx, e['args']), src: cx.src());
    case 'callMethod':
      final n = pick('name', '方法');
      return n == null ? hole : LSend(sub('of'), n, _list(cx, e['args']), src: cx.src());
    case 'superCall':
      final n = pick('name', '方法');
      return n == null ? hole : LSuperSend(n, _list(cx, e['args']), src: cx.src());
    case 'this':
      return LThis(src: cx.src());
    case 'isA':
      final t = pick('type', '类');
      return t == null ? hole : LIsA(sub('x'), t, src: cx.src());
    case 'classRef':
      final t = pick('type', '类');
      return t == null ? hole : LName(t, src: cx.src());
  }
  return beWaitExpr(kind, e, cx);
}

const Map<String, LType?> _isTypes = {'number': null, 'text': LType.text, 'bool': LType.boolean, 'list': LType.listOf(LType.any), 'dict': LType.dictOf(LType.any)};

/// “看是哪种情况”看的是哪一类东西：枚举 / 变体（'case'）、可空的值（'null'）、“任意”的值（'any'）。按第一段选的情况定。
String beMatchMode(LcBlock b) {
  final first = b.arms.isEmpty ? null : b.arms.first.args['case'];
  if (first == kBeCaseNull || first == kBeCaseSome) return 'null';
  if (first is String && first.startsWith(kBeCaseIsPrefix)) return 'any';
  return 'case';
}

/// 核心 2 的语句 → 语法树；不是的返回 null。[inner]＝翻这块积木的一个口。
List<LStmt>? beCoreBlock(LcBlock b, BeCoreCx cx, List<LStmt> Function(List<LcBlock> list, {bool inElse, int arm}) inner, RegExp varPattern) {
  if (cx.pure && b.op == 'log') {
    return [
      LExprStmt(LRt('log', [cx.lx(b.args['value'], b, 'value', arg: 'value')]), src: cx.src()),
    ];
  }
  if (!beIsCoreOp(b.op)) return null;
  LExpr arg(String name) => cx.lx(b.args[name], b, name, arg: name);
  List<LStmt> skip(String why) {
    cx.note('已跳过：$why');
    return const [];
  }

  String? varName(Object? v) => v is String && varPattern.hasMatch(v) ? v : null;
  switch (b.op) {
    case 'try':
      final handlers = <LCatch>[];
      for (var k = 0; k < b.arms.length; k++) {
        final kind = b.arms[k].args['kind'];
        handlers.add(
          LCatch(
            inner(b.arms[k].body, arm: k),
            kind: kind == kBeCatchAny || kind == '' || kind == null ? null : (_name(kind) ?? '（没选好）'),
            name: varName(b.arms[k].args['name']),
          ),
        );
      }
      return [LTry(inner(b.body), handlers: handlers, finallyBody: b.noElse ? const [] : inner(b.orElse, inElse: true), src: cx.src())];
    case 'throw':
      return [LThrow(arg('value'), src: cx.src())];
    case 'match':
      return _match(b, cx, inner, arg('value'), varName);
    case 'setField':
      final n = _name(b.args['name']);
      if (n == null) return skip('字段没选好');
      return [LAssign(LTField(arg('of'), n), arg('value'), src: cx.src())];
    case 'callMethodStmt':
      final n = _name(b.args['name']);
      if (n == null) return skip('方法没选好');
      return [
        LExprStmt(
          LSend(arg('of'), n, _list(cx, b.args['args'], arg: 'args'), src: cx.src()),
          src: cx.src(),
        ),
      ];
    case 'superInit':
      return [
        LExprStmt(
          LSuperSend.ctor(_list(cx, b.args['args'], arg: 'args'), src: cx.src()),
          src: cx.src(),
        ),
      ];
    case 'superCallStmt':
      final n = _name(b.args['name']);
      if (n == null) return skip('方法没选好');
      return [
        LExprStmt(
          LSuperSend(n, _list(cx, b.args['args'], arg: 'args'), src: cx.src()),
          src: cx.src(),
        ),
      ];
  }
  return beWaitBlock(b, cx, inner, varName);
}

List<LStmt> _match(LcBlock b, BeCoreCx cx, List<LStmt> Function(List<LcBlock> list, {bool inElse, int arm}) inner, LExpr subject, String? Function(Object?) varName) {
  final mode = beMatchMode(b);
  final orElse = b.noElse ? null : inner(b.orElse, inElse: true);
  if (mode == 'case') {
    final arms = <LMatchArm>[];
    for (var k = 0; k < b.arms.length; k++) {
      final c = _name(b.arms[k].args['case']);
      if (c == null) {
        cx.note('有一段没选是哪种情况，已跳过');
        continue;
      }
      arms.add(LMatchArm(c, [for (final n in beBindNames(b.arms[k].args['binds'])) ?varName(n)], inner(b.arms[k].body, arm: k)));
    }
    return [LMatch(subject, arms, orElse: orElse, src: cx.src())];
  }
  // 可空的值、“任意”的值：语言核心的“看是哪种情况”只认枚举和变体，这两种翻成“先存起来，再一段段如果”。
  final temp = '看的值${cx.temp()}';
  LName seen() => LName(temp);
  final ifs = <LIfArm>[];
  List<LStmt>? some, none;
  for (var k = 0; k < b.arms.length; k++) {
    final c = b.arms[k].args['case'];
    final bind = beBindNames(b.arms[k].args['binds']).map(varName).firstOrNull;
    final body = inner(b.arms[k].body, arm: k);
    if (mode == 'null' && c == kBeCaseNull) {
      none ??= body;
    } else if (mode == 'null' && c == kBeCaseSome) {
      some ??= [
        if (bind != null) LLet(bind, LRt('must', [seen()])),
        ...body,
      ];
    } else if (mode == 'any' && c is String && c.startsWith(kBeCaseIsPrefix) && _isTypes.containsKey(c.substring(kBeCaseIsPrefix.length))) {
      final type = c.substring(kBeCaseIsPrefix.length);
      final to = _isTypes[type];
      ifs.add(LIfArm(LRt('isType', [seen(), LLit(type)]), [if (bind != null) LLet(bind, to == null ? seen() : LCast(seen(), to)), ...body]));
    } else {
      cx.note('有一段选的情况和第一段不是一类，已跳过');
    }
  }
  final rest = orElse ?? const <LStmt>[];
  if (none != null) {
    ifs.add(LIfArm(LBinary('==', seen(), _lit(null)), none));
  } else if (some != null) {
    ifs.add(LIfArm(LBinary('!=', seen(), _lit(null)), some));
    some = null;
  }
  return [LLet(temp, subject, isConst: true, src: cx.src('value')), if (ifs.isEmpty) ...rest else LIf(ifs, orElse: some ?? rest, src: cx.src())];
}

// ———————————————————————— 声明 ————————————————————————

/// 文档里核心 2 的东西翻成的声明：每个带着它在“归哪个模块 / 公开”表里的名字。
class BeCoreUnit {
  BeCoreUnit(this.decls, this.main);
  final List<({String key, LDecl decl})> decls;

  /// “程序开始时”翻出来的语句（没有＝空）。
  final List<LStmt> main;
}

List<LParam> beCoreParams(List<BeParam> params) => [for (final p in params) LParam(beIdent(p.name), defaultValue: p.defaultValue == null ? null : LLit(p.defaultValue), type: p.type)];

// 每次都造新的节点（所以不写 const）：类型检查的结果按“是不是同一个节点”记，共用一个节点会互相盖掉。
LExpr _lit(Object? v) => LLit(v);
// ignore: prefer_const_constructors 同上：每个用到“我自己”的地方要是不同的节点
LExpr _me() => LThis();

LExpr? _default(LType t) => t.nullable
    ? _lit(null)
    : switch (t.kind) {
        LKind.integer => _lit(0),
        LKind.number => _lit(0.0),
        LKind.text => _lit(''),
        LKind.bool => _lit(false),
        _ => null,
      };

/// 把类型、模块顶上的变量、“程序开始时”翻成声明。[body]＝翻一串积木（方法、“创建时”、“程序开始时”）；[value]＝翻一个单独的值（字段、变量的初始值）。
BeCoreUnit beCoreUnit(BeDocument doc, {required List<LStmt> Function(BeMethod tree, BeTypeDef? owner) body, required LExpr Function(Object? value) value}) {
  final core = doc.core;
  final out = <({String key, LDecl decl})>[];
  bool pub(String key) => core.publics.contains(key);
  List<LTypedField> typed(List<BeField> fs) => [for (final f in fs) LTypedField(f.name, f.type)];
  for (final t in core.types) {
    final src = LSrc(script: t.id);
    final LDecl d;
    switch (t.kind) {
      case BeTypeKind.record:
        d = LRecordDecl(t.name, typed(t.fields), isPublic: pub(t.id), src: src);
      case BeTypeKind.enumeration:
        d = LEnumDecl(t.name, [for (final c in t.cases) c.name], isPublic: pub(t.id), src: src);
      case BeTypeKind.variant:
        d = LVariantDecl(t.name, [for (final c in t.cases) LVariantCase(c.name, typed(c.fields))], isPublic: pub(t.id), src: src);
      case BeTypeKind.error:
        // 自己定义的错误种类＝父类是错误的类：“创建时”收 消息 和各个字段，先调父类的，再把自己的字段放好。
        final up = [for (final f in beErrorFields(core, t.parent)) f.name];
        d = LClassDecl(
          t.name,
          parent: t.parent ?? kErrBase,
          isOpen: t.isOpen,
          isPublic: pub(t.id),
          fields: [for (final f in t.fields) LFieldDecl(f.name, _default(f.type), type: f.type)],
          ctor: LFuncDecl(
            '创建',
            [const LParam(kErrMessageField, type: LType.text), for (final f in beErrorFields(core, t.name)) LParam(f.name, type: f.type)],
            [
              LExprStmt(LSuperSend.ctor([const LName(kErrMessageField), for (final n in up) LName(n)])),
              for (final f in t.fields) LAssign(LTField(_me(), f.name), LName(f.name)),
            ],
            src: src,
          ),
          src: src,
        );
      case BeTypeKind.klass:
        final ctor = t.ctor;
        d = LClassDecl(
          t.name,
          parent: t.parent,
          interfaces: t.interfaces,
          isOpen: t.isOpen,
          isPublic: pub(t.id),
          fields: [for (final f in t.fields) LFieldDecl(f.name, f.init == null ? _default(f.type) : value(f.init), type: f.type, isPrivate: f.isPrivate, isStatic: f.isStatic)],
          ctor: ctor == null ? null : LFuncDecl('创建', beCoreParams(ctor.params), body(ctor, t), src: LSrc(script: ctor.id)),
          methods: [
            for (final m in t.methods)
              LMethodDecl(
                LFuncDecl(
                  m.name,
                  beCoreParams(m.params),
                  body(m, t),
                  src: LSrc(script: m.id),
                  type: m.returns,
                ),
                isStatic: m.isStatic,
              ),
          ],
          src: src,
        );
      case BeTypeKind.interface:
        d = LInterfaceDecl(
          t.name,
          [for (final m in t.methods) LSignature(m.name, beCoreParams(m.params), returns: m.returns)],
          isPublic: pub(t.id),
          src: src,
        );
    }
    out.add((key: t.id, decl: d));
  }
  for (final g in core.globals) {
    out.add((
      key: g.key,
      decl: LVarDecl(
        g.name,
        value(g.init),
        isConst: g.isConst,
        isPublic: pub(g.key),
        src: LSrc(script: g.key),
        type: g.type,
      ),
    ));
  }
  final main = core.main;
  return BeCoreUnit(out, main == null ? const [] : body(main, null));
}

/// 有模块的文档：把全部声明按“归哪个模块”分好，拼成一个程序。没有模块返回 null。
LProgram? beCoreProgram(BeCore core, List<({String key, LDecl decl})> decls, List<LStmt> main) {
  final entry = core.entryModule;
  if (entry == null) return null;
  return LProgram([
    for (final m in core.modules)
      LModule(
        name: m.name,
        uses: m.uses,
        decls: [
          for (final d in decls)
            if (identical(core.moduleOf(d.key), m)) d.decl,
        ],
        body: identical(m, entry) ? main : const [],
        src: LSrc(script: 'mod:${m.name}'),
      ),
  ], entry: entry.name);
}
