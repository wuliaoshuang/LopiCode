/// 用到第 4 版积木的接口怎么翻（积木第 4 版·第 1 阶段的“接线”）：整个接口翻成 lib/lang 的语法树，包成一句 `BeSLang`。
///
/// 一个接口里只要出现了新东西（`beBlocksUseLang`），就整个走这条路；没出现的接口照旧走 backend_ir.dart 的旧路，生成的代码一个字都不变。
/// 走新路时：
/// - 流程类的积木（如果 / 分情况 / 各种循环 / 跳出 / 跳过）一律翻成语法树的节点——“跳出循环在不在循环里”“后面的会不会执行”才算得对；
/// - 旧的“干活”积木（返回、数据集合、写日志、请求别的网址）照旧翻成 `BeS`，包成 `LHost` 夹在语法树里，生成时交回旧路去写；
/// - 式子：旧的照旧是 `BeX`（进语法树时用 `beToLangExpr` 转一下），新的翻成语法树的式子包在 `BeXLang` 里，互相可以套。
///
/// 每个节点带“来源”（[BeLangSpot]：哪块积木的哪一格），校验（backend_validate_lang.dart）靠它把问题画回积木上。
/// 校验用的是“影子”模式（[shadow]）：多出几句只给检查器看的读 / 写（旧语句在检查器眼里是不透明的），不用来生成代码。
library;

import 'package:lopicode/backend/backend_blocks.dart';
import 'package:lopicode/backend/backend_blocks_strict.dart';
import 'package:lopicode/backend/backend_core.dart';
import 'package:lopicode/backend/backend_function.dart';
import 'package:lopicode/backend/backend_ir.dart';
import 'package:lopicode/backend/backend_lang.dart';
import 'package:lopicode/backend/backend_lower_core.dart';
import 'package:lopicode/backend/backend_model.dart';
import 'package:lopicode/backend/backend_text.dart';
import 'package:lopicode/lang/ast.dart';
import 'package:lopicode/lang/ast_util.dart';
import 'package:lopicode/lang/types.dart';
import 'package:lopicode/lang/types_json.dart';
import 'package:lopicode/lowcode/logic_model.dart';

/// 语法树节点的来源：哪块积木（路径）、哪一格（参数名；段参数是 `@段号:名字`；null＝整块）。
class BeLangSpot {
  const BeLangSpot(this.path, this.arg);
  final LcBlockPath path;
  final String? arg;
}

/// 语法树里一个式子的来处：积木文档里的那个值（[value]），它放在谁里面（[holder]：积木、外面那层式子、列表）、叫什么（[key]）。
class BeLangOrigin {
  const BeLangOrigin(this.value, this.holder, this.key);
  final Object? value;
  final Object? holder;
  final Object? key;
}

/// “新建变量 / 常量”上标的类型（严格规矩才看；存在积木的 `type` 参数里，没标就没有这个键）。
LType? beLetType(LcBlock b) => b.args[kBeLetTypeArg] is Map ? lTypeFromJson(b.args[kBeLetTypeArg]) : null;
const String kBeLetTypeArg = 'type';

/// 旧的翻译器（backend_ir.dart 的 `_Lowerer`）借给这边用的几样。
abstract interface class BeLowerHost {
  /// 一个式子 → `BeX`（新旧都行；没填好的当成空并记一句说明）。
  BeX expr(Object? e, [int depth]);

  /// 旧的“干活”积木（不带口）→ 旧语句。不认识的返回空表并记一句说明。
  List<BeS> leaf(LcBlock b);

  /// 文档里声明过的变量：是就记成“这个接口用到了”并返回 true。
  bool useDocVar(String name);

  /// 换一张“没填好”的说明表，返回原来那张。
  List<String> swapNotes(List<String> fresh);
  void addNote(String note);

  /// 文档里的函数（“我的积木”）；没有返回 null。
  BeFunction? function(String id);
}

/// 小库函数的参数顺序（积木的参数名和小库的参数名一样的那些）。
const Map<String, List<String>> _rtArgs = {
  'random': ['a', 'b'],
  'copy': ['x'],
  'charAt': ['s', 'i'],
  'substring': ['s', 'from', 'to'],
  'indexOf': ['s', 'sub'],
  'replace': ['s', 'from', 'to'],
  'repeatText': ['s', 'n'],
  'split': ['s', 'sep'],
  'template': ['s', 'dict'],
  'toJson': ['x'],
  'fromJson': ['s'],
  'range': ['a', 'b', 'step'],
  'listGet': ['xs', 'i'],
  'listPop': ['xs'],
  'listContains': ['xs', 'v'],
  'listIndexOf': ['xs', 'v'],
  'listSlice': ['xs', 'from', 'to'],
  'listConcat': ['a', 'b'],
  'listJoin': ['xs', 'sep'],
  'dictGet': ['d', 'k'],
  'dictHas': ['d', 'k'],
  'dictMerge': ['a', 'b'],
  // 语句
  'listPush': ['xs', 'v'],
  'listInsert': ['xs', 'i', 'v'],
  'listSet': ['xs', 'i', 'v'],
  'listRemove': ['xs', 'i'],
  'dictSet': ['d', 'k', 'v'],
  'dictRemove': ['d', 'k'],
};

/// “一块顶多块”的积木：`fn` 能选哪些小库函数、别的参数按什么顺序传。
const Map<String, (List<String>, List<String>)> _families = {
  'round': (['round', 'floor', 'ceil'], ['x']),
  'math': (['abs', 'sqrt'], ['x']),
  'minmax': (['max', 'min'], ['a', 'b']),
  'convert': (['toNumber', 'toText', 'toBool'], ['x']),
  'textHas': (['contains', 'startsWith', 'endsWith'], ['s', 'sub']),
  'textCase': (['trim', 'upper', 'lower'], ['s']),
  'listOrder': (['listReverse', 'listSort'], ['xs']),
  'dictPart': (['dictKeys', 'dictValues', 'dictPairs'], ['d']),
};

class BeLangLower {
  BeLangLower(this.host, this.route, {this.shadow = false}) : locals = beLocalNames(route.body, beNamePattern);

  final BeLowerHost host;
  final BeRoute route;

  /// 影子模式（只给校验用）：名字不管新建没新建都照写（检查器才报得出“看不见”），旧语句读 / 写的名字另补几句给检查器看。
  final bool shadow;

  /// 这个接口里新积木新建的名字 → 是不是常量。
  final Map<String, bool> locals;

  /// 来源表：节点的 `src.block` 是这里的下标。
  final List<BeLangSpot> spots = [];

  int _switches = 0;

  /// 文档里定义的类型（核心 2 的积木要查；没给也能翻）。
  BeCore? core;

  /// 单独的一个值（字段、模块顶上变量的初始值）→ 语法树。
  LExpr value(Object? v) => _lx(v);

  BeCoreCx _coreCx(LExpr Function(Object? value, Object? holder, Object? key, {String? arg}) lx) => BeCoreCx(lx: lx, src: _src, note: host.addNote, core: core, temp: () => ++_switches, pure: pure);
  LcBlockPath _path = const [];
  String? _arg;

  /// 正在翻的是哪块积木、它套在第几层（式子里的匿名函数要靠它找到自己的口）。
  LcBlock? _owner;
  int _depth = 0;

  LSrc _src([String? arg]) {
    spots.add(BeLangSpot(_path, arg ?? _arg));
    return LSrc(script: route.id, block: '${spots.length - 1}', slot: arg ?? _arg);
  }

  LSrc _blockSrc() {
    spots.add(BeLangSpot(_path, null));
    return LSrc(script: route.id, block: '${spots.length - 1}');
  }

  /// 只出语言核心的东西（“看代码”走版本 2 的生成器时用）：小库调用写成 `LRt`，“写到日志”“加上”也翻成核心的节点。
  bool pure = false;

  /// 挂上了就“走库”（见 [BeLibBridge]）。
  BeLibBridge? bridge;

  LExpr _toLang(BeX x) => bridge?.expr(x) ?? bePureExpr(beToLangExpr(x, request: kBeRequestName), pure: pure);
  List<LStmt> _host(List<BeS> list) => bridge?.stmts(list) ?? beHostStmts(list);

  /// 语法树里的式子 → 它是积木文档里的哪个值翻来的（文档里那个对象本身）。规矩版本 2 的类型检查靠它把问题、
  /// 一键修对回到具体哪一格上（backend_type_bridge.dart）；别处不用。
  final Map<LExpr, BeLangOrigin> origins = Map.identity();

  /// 给类型检查用（配合影子模式）：旧的“干活”积木往变量里放的东西说不准是什么，记成“任意”而不是“空”。
  bool typed = false;

  /// 积木文档里的一个值 → 语法树的式子，顺手记下它的来处。
  /// [holder]＝装着这个值的东西（积木、外面那层式子、列表），[key]＝在它里面叫什么（参数名、字段名、第几项）。
  LExpr _lx(Object? value, [int depth = 0, Object? holder, Object? key]) {
    final x = _toLang(host.expr(value, depth));
    // “空”的字面量是同一个常量对象到处用，记不准是哪一处，不记。
    if (!(x is LLit && x.value == null) && (value is Map || holder != null)) origins[x] = BeLangOrigin(value, holder, key);
    return x;
  }

  /// 这个名字现在能不能用：文档里声明的变量，或这个接口里新建的名字。影子模式下合规矩的名字都算（看不看得见交给检查器）。
  bool knows(Object? name) {
    if (name is! String || !beNamePattern.hasMatch(name)) return false;
    if (host.useDocVar(name)) return true;
    return shadow || locals.containsKey(name);
  }

  // —— 式子 ——

  /// 新的式子（和走新路时要换个翻法的旧式子）→ `BeX`；不归这边管的返回 null，旧的翻译器照旧翻。
  BeX? expr(Object? e, int depth) {
    final kind = exprKind(e);
    if (kind == null) return null;
    LExpr sub(String key) => _lx(exprField(e, key), depth + 1, e, key);
    BeX lang(LExpr x) => BeXLang(x);
    BeX hole(String why) {
      host.addNote(why);
      return const BeXLit(null);
    }

    switch (kind) {
      case 'var':
        final name = exprField(e, 'name');
        if (name is! String || !beNamePattern.hasMatch(name) || host.useDocVar(name)) return null;
        return shadow || locals.containsKey(name) ? lang(LName(name, src: _src())) : null;
      case 'pow':
        return lang(LBinary('**', sub('a'), sub('b'), src: _src()));
      case 'obj':
        final fields = exprField(e, 'fields');
        final entries = <LDictEntry>[];
        if (fields is List) {
          for (final f in fields) {
            final key = exprKind(f) == 'pair' ? exprString(f, 'key') : null;
            if (key == null || key.isEmpty) {
              host.addNote('字典里有一个字段没填名字，已跳过');
              continue;
            }
            entries.add(LDictEntry(LLit(key), _lx(exprField(f, 'value'), depth + 1, f, 'value')));
          }
        }
        return lang(LDictLit(entries));
      case 'null':
        return lang(const LLit(null));
      case 'neg':
        return lang(LUnary('neg', sub('x')));
      case 'logic':
        final op = exprString(e, 'op');
        return op == 'and' || op == 'or' ? lang(LLogic(op!, sub('l'), sub('r'))) : hole('“并且 / 或者”没选好，当成空的');
      case 'cond':
        return lang(LCond(sub('cond'), sub('then'), sub('orElse')));
      case 'isType':
        final type = exprString(e, 'type');
        return kBeTypeNames.contains(type) ? lang(LRt('isType', [sub('x'), LLit(type)])) : hole('类型没选好，当成空的');
      case 'listLit':
        final items = exprField(e, 'items');
        return lang(
          LListLit([
            if (items is List)
              for (final (i, item) in items.indexed) _lx(item, depth + 1, items, i),
          ]),
        );
      case 'index':
        return lang(LIndex(sub('of'), sub('key')));
      // 只在查类型的时候（[typed]）：老的“运算 / 比较”“不是”也翻成语言核心的式子，这样 `"12" * 2` 查得出来、结果的类型也推得出来。
      case 'bin' when typed:
        final op = exprString(e, 'op');
        if (op == 'and' || op == 'or') return lang(LLogic(op!, sub('l'), sub('r')));
        return kArithmeticOps.contains(op) || kCompareOps.contains(op) ? lang(LBinary(op!, sub('l'), sub('r'), src: _src())) : null;
      case 'not' when typed:
        return lang(LUnary('not', sub('x')));
    }
    final c2 = beCoreExpr(kind, e, _coreCx((v, holder, key, {arg}) => _lx(v, depth + 1, holder, key)));
    if (c2 != null) return lang(c2);
    final strict = kBeStrictRtArgs[kind];
    if (strict != null) return lang(LRt(kind, [for (final a in strict) sub(a)], src: _src()));
    final func = _funcExpr(kind, e!, depth, sub);
    if (func != null) return lang(func);
    final family = _families[kind];
    if (family != null) {
      final fn = exprString(e, 'fn');
      if (!family.$1.contains(fn)) return hole('“${beExprSpecs[kind]?.label ?? kind}”没选好是哪一种，当成空的');
      return lang(LRt(fn!, [for (final a in family.$2) sub(a)]));
    }
    final args = _rtArgs[kind];
    if (args != null && beLangExprSpecs.containsKey(kind)) return lang(LRt(kind, [for (final a in args) sub(a)]));
    return null;
  }

  // —— 函数（第 2 阶段）——

  List<LParam> _lambdaParams(Object? e) {
    final raw = exprField(e, 'params');
    final names = <String>[];
    if (raw is List) {
      for (final p in raw) {
        if (p is String && p.trim().isNotEmpty && !names.contains(beIdent(p))) names.add(beIdent(p));
      }
    }
    return [for (final n in names) LParam(n)];
  }

  /// 调用的实参表：按定义的参数顺序一个个取（实参按参数名存）。“剩下的全收”的槽里放的是“列表”积木就把每一项各当一个实参，放别的就当一个。
  /// [holder]＝这次调用本身（值积木是那个式子，语句积木是那块积木）。
  List<LExpr> _callArgs(BeFunction f, Object? Function(String name) read, int depth, Object holder) {
    final arg = _arg;
    final out = <LExpr>[];
    LExpr one(String name, Object? value, [Object? inList, int? i]) {
      _arg = name;
      return inList == null ? _lx(value, depth + 1, holder, name) : _lx(value, depth + 1, inList, i);
    }

    for (final p in f.params) {
      final value = read(p.name);
      if (!p.rest) {
        out.add(value == null ? LLit(p.defaultValue) : one(p.name, value));
      } else if (exprKind(value) == 'listLit') {
        final items = exprField(value, 'items');
        if (items is List) out.addAll([for (final (i, item) in items.indexed) one(p.name, item, items, i)]);
      } else if (value != null) {
        out.add(one(p.name, value));
      }
    }
    _arg = arg;
    return out;
  }

  List<LExpr> _listArgs(Object? list, int depth) => [
    if (list is List)
      for (final (i, item) in list.indexed) _lx(item, depth + 1, list, i),
  ];

  /// 第 2 阶段的式子；不是的返回 null。
  LExpr? _funcExpr(String kind, Object e, int depth, LExpr Function(String key) sub) {
    LExpr gone() {
      host.addNote('这块自定义积木的定义已经不在了，当成空的');
      return const LLit(null);
    }

    final callee = beCallId(kind);
    if (callee != null) {
      final f = host.function(callee);
      return f == null ? gone() : LCall(LName(f.ident), _callArgs(f, (n) => exprField(e, n), depth, e), src: _src());
    }
    switch (kind) {
      case 'param':
        final name = exprString(e, 'name');
        if (name == null || name.isEmpty) {
          host.addNote('参数没选好，当成空的');
          return const LLit(null);
        }
        return LName(beIdent(name), src: _src());
      case 'funcRef':
        final f = host.function(exprString(e, 'fn') ?? '');
        return f == null ? gone() : LName(f.ident, src: _src());
      case 'callValue':
        return LCall(sub('fn'), _listArgs(exprField(e, 'args'), depth), src: _src());
      case 'lambdaExpr':
        return LLambda.short(_lambdaParams(e), sub('body'), src: _src());
      case 'lambda':
        final body = lcExprBody(e) ?? const <LcBlock>[];
        final owner = _owner, path = _path, arg = _arg, at = _depth;
        final src = _src();
        // 这个口是这块积木上的第几个（按内容认，不按位置存：见 logic_model.dart 的 lcExprMouthArm）。
        final k = owner == null ? -1 : owner.exprMouths.indexWhere((m) => identical(m, body));
        final inner = k < 0 ? const <LStmt>[] : stmts(body, path, at + 1, arm: lcExprMouthArm(k));
        _owner = owner;
        _path = path;
        _arg = arg;
        _depth = at;
        return LLambda(_lambdaParams(e), inner, src: src);
      case 'listMap' || 'listFilter' || 'listFind' || 'listEvery' || 'listSome' || 'listSortBy':
        return LRt(kind, [sub('xs'), sub('fn')], src: _src());
      case 'listReduce':
        return LRt(kind, [sub('xs'), sub('fn'), sub('init')], src: _src());
    }
    return null;
  }

  /// 第 2 阶段的语句；不是的返回 null。
  List<LStmt>? _funcBlock(LcBlock b, LExpr Function(String name) arg, LSrc Function([String? name]) src) {
    final callee = beCallId(b.op);
    if (callee != null) {
      final f = host.function(callee);
      if (f == null) return _skip('这块自定义积木的定义已经不在了');
      return [LExprStmt(LCall(LName(f.ident), _callArgs(f, (n) => b.args[n], 0, b), src: src()), src: src())];
    }
    switch (b.op) {
      case 'return':
        return [LReturn(arg('value'), src: src())];
      case 'returnNothing':
        return [LReturn(null, src: src())];
      case 'callValueStmt':
        final fn = arg('fn');
        _arg = 'args';
        final args = _listArgs(b.args['args'], 0);
        _arg = null;
        return [LExprStmt(LCall(fn, args, src: src()), src: src())];
      case 'listEach':
        return [
          LExprStmt(LRt('listEach', [arg('xs'), arg('fn')], src: src()), src: src()),
        ];
    }
    return null;
  }

  // —— 语句 ——

  /// 一串积木 → 语法树的语句。[parent] 是装着这一串的那块积木的路径（最外层是空的），[inElse] / [arm] 说是它的哪个口。
  List<LStmt> stmts(List<LcBlock> list, LcBlockPath parent, int depth, {bool inElse = false, int arm = -1}) {
    if (list.isEmpty) return const [];
    if (depth > LcBlock.maxDepth) return [LNote('积木套得太深，这里面的 ${list.length} 块没有翻译')];
    final out = <LStmt>[];
    for (var i = 0; i < list.length; i++) {
      final b = list[i];
      final path = [...parent, lcStep(i, inElse: inElse, arm: arm)];
      final saved = host.swapNotes([]);
      _path = path;
      _arg = null;
      _owner = b;
      _depth = depth;
      final translated = _block(b, path, depth);
      if (b.op != 'note' && b.op != 'superInit') out.add(LNote(describeBeBlock(b)));
      for (final n in host.swapNotes(saved)) {
        out.add(LNote('（$n）'));
      }
      out.addAll(translated);
    }
    return out;
  }

  List<LStmt> _skip(String why) {
    host.addNote('已跳过：$why');
    return const [];
  }

  /// 起名字的那一格：合规矩才算数。
  String? _newName(LcBlock b, String arg) {
    final name = b.args[arg];
    return name is String && beNamePattern.hasMatch(name) ? name : null;
  }

  List<LStmt> _block(LcBlock b, LcBlockPath path, int depth) {
    // 翻里面的积木会改 _path，所以每次用之前都重新对准这一块。
    LExpr at(String name, Object? value) {
      _path = path;
      _owner = b;
      _depth = depth;
      _arg = name;
      final x = _lx(value, 0, b, name);
      _arg = null;
      return x;
    }

    LExpr arg(String name) => at(name, b.args[name]);
    LSrc src([String? name]) {
      _path = path;
      return name == null ? _blockSrc() : _src(name);
    }

    final func = _funcBlock(b, arg, src);
    if (func != null) return func;

    List<LStmt> inner(List<LcBlock> list, {bool inElse = false, int arm = -1}) => stmts(list, path, depth + 1, inElse: inElse, arm: arm);

    LExpr coreLx(Object? v, Object? holder, Object? key, {String? arg}) {
      _path = path;
      _owner = b;
      _depth = depth;
      _arg = arg;
      final x = _lx(v, 0, holder, key);
      _arg = null;
      return x;
    }

    final c2 = beCoreBlock(b, BeCoreCx(lx: coreLx, src: src, note: host.addNote, core: core, temp: () => ++_switches, pure: pure), inner, beNamePattern);
    if (c2 != null) return c2;

    switch (b.op) {
      case 'let' || 'const':
        final name = _newName(b, 'name');
        if (name == null) return _skip('名字不合规矩');
        return [LLet(name, arg('value'), isConst: b.op == 'const', src: src('name'), type: typed ? beLetType(b) : null)];
      case 'setVar':
        final name = b.args['name'];
        if (!knows(name)) return _skip('变量没有声明');
        return [LAssign(LTName(name as String), arg('value'), src: src('name'))];
      case 'changeVar':
        final name = b.args['name'];
        if (!knows(name)) return _skip('变量没有声明');
        final by = arg('by');
        return [
          LAssign(
            LTName(name as String),
            pure ? LBinary('+', LName(name, src: src('name')), by) : LNative('add', [LName(name, src: src('name')), by]),
            src: src('name'),
          ),
        ];
      case 'setItem':
        return [LAssign(LTIndex(arg('of'), arg('key')), arg('value'), src: src())];
      case 'do':
        return [LExprStmt(arg('value'), src: src())];
      case 'note':
        final text = b.args['text'];
        return [LNote(text is String ? text : '')];
      case 'if':
        return [
          LIf(
            [LIfArm(arg('cond'), inner(b.body)), for (var k = 0; k < b.arms.length; k++) LIfArm(at(lcArmArg(k, 'cond'), b.arms[k].args['cond']), inner(b.arms[k].body, arm: k))],
            orElse: inner(b.orElse, inElse: true),
            src: src(),
          ),
        ];
      case 'switch':
        final temp = 'sw${++_switches}';
        final subject = arg('value');
        return lSwitch(
          temp,
          subject,
          [for (var k = 0; k < b.arms.length; k++) LIfArm(at(lcArmArg(k, 'value'), b.arms[k].args['value']), inner(b.arms[k].body, arm: k))],
          orElse: inner(b.orElse, inElse: true),
          src: src(),
        );
      case 'while':
        return [LWhile(arg('cond'), inner(b.body), src: src())];
      case 'forever':
        return [LWhile(null, inner(b.body), src: src())];
      case 'repeat':
        return [LRepeat(arg('times'), inner(b.body), src: src())];
      case 'forCount':
        final name = _newName(b, 'name');
        if (name == null) return _skip('“从…数到…”的变量名不合规矩');
        return [LForCount(name, arg('from'), arg('to'), arg('step'), inner(b.body), src: src('name'))];
      case 'forEach':
        final item = b.args['item'];
        if (!knows(item)) return _skip('“这一项放进变量”的变量没有声明');
        final index = b.args['index'];
        final hasIndex = index is String && index.isNotEmpty;
        if (hasIndex && _newName(b, 'index') == null) host.addNote('序号的名字不合规矩，没有记序号');
        return [LForEach(arg('list'), item as String, inner(b.body), index: hasIndex ? _newName(b, 'index') : null, reuse: true, src: src(hasIndex ? 'index' : 'item'))];
      case 'forPairs':
        final key = _newName(b, 'key'), value = _newName(b, 'value');
        if (key == null || value == null) return _skip('“对字典的每一对”的变量名不合规矩');
        return [LForPairs(arg('dict'), key, value, inner(b.body), src: src(key == value ? 'value' : 'key'))];
      case 'break':
        return [LBreak(src: src())];
      case 'continue':
        return [LContinue(src: src())];
      case 'listPush' || 'listInsert' || 'listSet' || 'listRemove' || 'dictSet' || 'dictRemove':
        return [
          LExprStmt(LRt(b.op, [for (final a in _rtArgs[b.op]!) arg(a)]), src: src()),
        ];
      case 'fetch' when bridge != null:
        // 走库：库里“请求别的网址”是一块带两个口的展开型积木，口里的积木原样放进去（里面的“返回”就是从接口返回）。
        final method = b.args['method'] == 'POST' ? 'POST' : 'GET';
        final into = b.args['into'];
        final url = arg('url');
        final data = method == 'POST' && isExpr(b.args['data']) ? arg('data') : const LLit(null);
        final okBody = inner(b.body), failBody = inner(b.orElse, inElse: true);
        final got = bridge!.mouthBlock('fetch', [LLit(method), url, data], mouths: {'body': okBody, 'orElse': failBody}, into: knows(into) ? into as String : null);
        return got == null ? _skip('“请求别的网址”还没有接到库上') : lStampSrc(got, src());
      case 'fetch':
        // 旧路翻出来是“存临时值 + 如果（没拿到）…否则…”；口里的积木换成这边翻的。
        final old = host.leaf(b.copyWith(body: const [], orElse: const []));
        final branch = old.whereType<BeSIf>().firstOrNull;
        if (branch == null) return _host(old);
        return [
          if (shadow) ..._shadow(b),
          ..._host([
            for (final s in old)
              if (s is! BeSIf) s,
          ]),
          LIf(
            [
              LIfArm(_toLang(branch.cond), [..._host(branch.then), ...inner(b.orElse, inElse: true)]),
            ],
            orElse: [..._host(branch.orElse), ...inner(b.body)],
            src: src(),
          ),
        ];
      default:
        // 走库：翻成了库里的调用，检查器看得见，不补影子；记上是哪一块（问题才标得到这一块上）。
        if (bridge != null) return lStampSrc(_host(host.leaf(b)), src());
        return [if (shadow) ..._shadow(b), ..._host(host.leaf(b))];
    }
  }

  /// 影子模式：旧的“干活”积木在检查器眼里是不透明的，把它读的式子、写的变量各补一句给检查器看（不生成代码）。
  List<LStmt> _shadow(LcBlock b) {
    final spec = beBlockSpecs[b.op];
    if (spec == null) return const [];
    final path = _path;
    _owner = b;
    final out = <LStmt>[];
    for (final a in spec.args) {
      final value = b.args[a.name];
      _path = path;
      _arg = a.name;
      if (a.kind == LcArgKind.expr && isExpr(value)) {
        out.add(LExprStmt(_lx(value, 0, b, a.name), src: _src()));
      } else if (a.kind == LcArgKind.variable && value is String && value.isNotEmpty && beNamePattern.hasMatch(value) && !host.useDocVar(value)) {
        out.add(LAssign(LTName(value), typed ? const LAscribe(LLit(null), LType.any) : const LLit(null), src: _src()));
      }
    }
    _arg = null;
    return out;
  }
}
