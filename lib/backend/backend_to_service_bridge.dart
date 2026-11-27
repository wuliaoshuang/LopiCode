part of 'backend_to_service.dart';

// “走库”的翻法：旧积木按旧名对照找到库积木、用库机制展开；用户库的积木也在这里展开。
// 从 backend_to_service.dart 原样挪出来的，那边放不下了。

/// 用户的名字只有英文字母、数字、下划线（`beNamePattern`）；库这边起的名字都带汉字，所以撞不上。
class _Fresh {
  int _n = 0;
  String call(String name) => '${name}_${++_n}';
}

/// 一次翻译里记的事。
class _Flags {
  /// 有没有用到“接口服务”库的积木。
  bool service = false;
}

class _Bridge implements BeLibBridge {
  _Bridge(this.doc, this.flags, this.lib, this.settings, this.fresh, this.problems, Map<String, String> base) : context = {...base};
  final BeDocument doc;
  final _Flags flags;
  final LibLibrary lib;
  final Map<String, Object?> settings;
  final _Fresh fresh;
  final List<String> problems;

  /// 现在看得见的隐含的东西：名字 → 变量名。
  final Map<String, String> context;
  final Map<int, String> _temps = {};

  LibCx get _cx => LibCx(context: context, settings: settings, fresh: fresh.call);

  LExpr _bad(String why) {
    if (!problems.contains(why)) problems.add(why);
    return const LLit(null);
  }

  /// 旧名对照里按旧参数顺序排的槽：`@名字`＝那一位是隐含的东西（库自己会拿），不占槽。
  Map<String, LExpr> _values(LibBlock b, List<BeX> args) => {
    for (var i = 0; i < b.legacyArgs.length && i < args.length; i++)
      if (!b.legacyArgs[i].startsWith('@')) b.legacyArgs[i]: expr(args[i]),
  };

  @override
  LExpr expr(BeX x) {
    switch (x) {
      case BeXLang(:final expr):
        return expr;
      case BeXLit(:final value):
        return LLit(value);
      case BeXVar(:final name):
        return LName(name);
      case BeXTmp(:final slot):
        final name = _temps[slot];
        return name == null ? _bad('用到了一个还没存的临时值') : LName(name);
      case BeXReq():
        final name = context[kBeServiceRequest];
        return name == null ? _bad('“这次请求”只有在接口里才有，“我的积木”里用不了') : LName(name);
      case BeXCall(:final fn, :final args):
        final block = lib.legacy(fn);
        if (block != null) {
          flags.service = true;
          if (!block.isValue) return _bad('「${block.look.name}」不是一个值');
          final got = libApply(lib, block, LibUse(values: _values(block, args)), _cx);
          final value = got.value;
          if (value == null) return _bad(got.problem ?? '「${block.look.name}」用不了');
          return value;
        }
        if (fn == 'obj') {
          return LAscribe(LDictLit([for (var i = 0; i + 1 < args.length; i += 2) LDictEntry(expr(args[i]), LAscribe(expr(args[i + 1]), LType.any))]), const LType.dictOf(LType.any));
        }
        if (kLangCoreFns.containsKey(fn) || kLangRtFns.containsKey(fn)) return LRt(fn, [for (final a in args) expr(a)]);
        return _bad('「$fn」还没有接到库上');
    }
  }

  List<LStmt> _use(LibBlock block, BeXCall call, {String? into}) {
    flags.service = true;
    final target = block.slotKinds.entries.where((e) => e.value == LibSlotKind.assign).firstOrNull?.key;
    final got = libApply(lib, block, LibUse(values: _values(block, call.args), targets: {if (into != null && target != null) target: into}), _cx);
    if (got.problem != null) {
      _bad(got.problem!);
      return const [];
    }
    final value = got.value;
    if (value == null) return got.stmts;
    return [into == null ? LExprStmt(value) : LAssign(LTName(into), value)];
  }

  @override
  List<LStmt>? mouthBlock(String legacyFn, List<LExpr> args, {Map<String, List<LStmt>> mouths = const {}, String? into}) {
    final block = lib.legacy(legacyFn);
    if (block == null) return null;
    flags.service = true;
    final target = block.slotKinds.entries.where((e) => e.value == LibSlotKind.assign).firstOrNull?.key;
    final values = {
      for (var i = 0; i < block.legacyArgs.length && i < args.length; i++)
        if (!block.legacyArgs[i].startsWith('@')) block.legacyArgs[i]: args[i],
    };
    final got = libApply(lib, block, LibUse(values: values, mouths: mouths, targets: {if (into != null && target != null) target: into}), _cx);
    if (got.problem != null) _bad(got.problem!);
    return got.stmts;
  }

  @override
  List<LStmt> stmts(List<BeS> list) => [for (final s in list) ..._one(s)];

  // —— 用户库的积木 ——

  ({LibLibrary lib, LibBlock block})? _libBlockOf(String op) {
    final ref = beLibOpOf(op);
    if (ref == null) return null;
    final l = doc.use(ref.lib) == null ? null : doc.lib(ref.lib);
    if (l == null) {
      _bad('用到了库「${ref.lib}」的积木，可是这份文档没有用上这个库（或者库不在项目里）');
      return null;
    }
    final block = l.block(ref.block);
    if (block == null) _bad('库「${l.name}」里没有积木「${ref.block}」（库换过版本了？）');
    return block == null ? null : (lib: l, block: block);
  }

  LibApplied _applyLib(
    LibLibrary l,
    LibBlock block,
    LExpr Function(String slot) value,
    Object? Function(String slot) raw, {
    List<List<LcBlock>> mouths = const [],
    List<LStmt> Function(List<LcBlock> list, {bool inElse})? inner,
  }) {
    final values = <String, LExpr>{}, targets = <String, String>{}, lowered = <String, List<LStmt>>{};
    final provided = libProvided(block, fresh.call);
    var mouth = 0;
    for (final part in parseLookTemplate(block.look.template)) {
      if (!part.isSlot || values.containsKey(part.text) || targets.containsKey(part.text) || lowered.containsKey(part.text)) continue;
      final slot = part.text, v = raw(slot);
      switch (block.kindOf(slot)) {
        case LibSlotKind.mouth:
          final k = mouth++;
          final saved = {...context};
          for (final e in provided.entries) {
            context[e.key] = e.value;
          }
          lowered[slot] = k < mouths.length && inner != null ? inner(mouths[k], inElse: k == 1) : const [];
          context
            ..clear()
            ..addAll(saved);
        case LibSlotKind.assign:
          if (v is String && v.isNotEmpty) targets[slot] = v;
        case LibSlotKind.literal:
          values[slot] = v is String || v is num || v is bool ? LLit(v) : value(slot);
        case LibSlotKind.value:
          values[slot] = block.look.slotFor(slot).kind == CustomSlotKind.choice && v is String ? LLit(v) : value(slot);
      }
    }
    final got = libApply(l, block, LibUse(values: values, mouths: lowered, targets: targets, provided: provided), LibCx(context: context, settings: beLibSettingsOf(doc, l), fresh: fresh.call));
    if (got.problem != null) _bad(got.problem!);
    return got;
  }

  @override
  List<LStmt>? libBlock(LcBlock b, LExpr Function(String slot) value, List<LStmt> Function(List<LcBlock> list, {bool inElse}) inner, {required bool shadow}) {
    if (b.op == kBeLibMouthOp) {
      final name = b.args['name'];
      return shadow
          ? const []
          : [
              LExprStmt(LNative(kBeLibMouthMark, [LLit(name is String ? name : '')])),
            ];
    }
    if (b.op == kBeLibPutOp) {
      return [
        LExprStmt(shadow ? value('value') : LNative(kBeLibPutMark, [value('value')])),
      ];
    }
    if (beLibOpOf(b.op) == null) return null;
    final hit = _libBlockOf(b.op);
    if (hit == null) return const [];
    final got = _applyLib(hit.lib, hit.block, value, (s) => b.args[s], mouths: [b.body, b.orElse], inner: inner);
    final v = got.value;
    return v != null ? [LExprStmt(v)] : got.stmts;
  }

  @override
  LExpr? libExpr(String kind, LExpr Function(String slot) value, Object? Function(String slot) raw) {
    if (beLibOpOf(kind) == null) return null;
    final hit = _libBlockOf(kind);
    if (hit == null) return const LLit(null);
    if (!hit.block.isValue) return _bad('「${hit.block.look.name}」不是一个值');
    return _applyLib(hit.lib, hit.block, value, raw).value ?? const LLit(null);
  }

  List<LStmt> _one(BeS s) {
    switch (s) {
      case BeSLang(:final stmts):
        return stmts;
      case BeSNote(:final text):
        return [LNote(text)];
      case BeSSet(:final name, :final value):
        final block = value is BeXCall ? lib.legacy(value.fn) : null;
        if (block != null && !block.isValue) return _use(block, value as BeXCall, into: name);
        return [LAssign(LTName(name), expr(value))];
      case BeSLet(:final slot, :final value):
        final name = _temps[slot] = fresh('临时');
        return [LLet(name, expr(value))];
      case BeSDo(:final call):
        final block = lib.legacy(call.fn);
        return block != null ? _use(block, call) : [LExprStmt(expr(call))];
      case BeSReturn(:final response):
        final block = lib.legacy(response.fn);
        if (block == null) {
          _bad('「${response.fn}」还没有接到库上');
          return const [];
        }
        return _use(block, response);
      case BeSIf(:final cond, :final then, :final orElse):
        return [
          LIf([LIfArm(expr(cond), stmts(then))], orElse: stmts(orElse)),
        ];
      default:
        _bad('有一块旧积木还没有接到库上');
        return const [];
    }
  }
}
