/// 页面逻辑 → 语言核心的程序（积木第 5 版·前端 1）。像后端的 backend_to_service.dart：把一页的逻辑翻成一个只用语言核心和库的程序，
/// 交给浏览器目标（lib/lang/gen2_browser.dart）生成。
///
/// - 每个处理＝内置“页面”库的一顶帽子（当控件被点击 / 当输入内容变化 / 当页面放上以后）。
/// - 旧积木按“页面”库积木上写的旧名对照（`legacy`）找到库积木、用库机制（`libApply`）展开；旧文件不改写。
///   “如果”“重复”是语言自己的东西，直接翻成语言核心的“如果”“当…时重复”。
/// - 旧积木的旧规矩（什么时候先转数字、转文字，什么时候用“三个等号”）照旧生成器 `JsLogicWriter` 的静态类型一条条对着来，
///   所以新路做的是同一串 JS 运算（见 D 分册 §6.3 和落地说明）。
/// - 用户库的积木（`lib:…`）照库机制展开；槽里放的还是页面的值。
///
/// 任何输入都不抛异常：翻不了的地方记一句（[LcCoreBuilt.skipped]），那一块跳过。
library;

import 'package:lopicode/lang/ast.dart';
import 'package:lopicode/lang/custom_block.dart';
import 'package:lopicode/lang/lib_apply.dart';
import 'package:lopicode/lang/lib_model.dart';
import 'package:lopicode/lang/types.dart';
import 'package:lopicode/lowcode/lib_blocks.dart' show libOpOf;
import 'package:lopicode/lowcode/lib_page.dart';
import 'package:lopicode/lowcode/logic_blocks.dart';
import 'package:lopicode/lowcode/logic_js_core.dart' show isSafeNodeId, kRepeatLimit;
import 'package:lopicode/lowcode/logic_libs.dart';
import 'package:lopicode/lowcode/logic_model.dart';
import 'package:lopicode/lowcode/logic_text.dart';
import 'package:lopicode/lowcode/model.dart';

/// 翻译的结果。
class LcCoreBuilt {
  const LcCoreBuilt({this.program, this.problems = const [], this.skipped = const [], this.props = const {}, this.states = const {}, this.libs = const []});

  /// 翻出来的程序（库的模块＋页面自己的模块）；[problems] 不空时也给，方便看是哪里。
  final LProgram? program;

  /// 整页翻不了的原因（库不在、库有问题……）。不空＝这一页不能导出逻辑。
  final List<String> problems;

  /// 跳过的积木各一句（和旧生成器里的“// 跳过…”是同一批情况）。
  final List<String> skipped;

  /// 逻辑里读或改到的控件属性（控件 id, 属性）：导出的人照这个准备读写表。
  final Set<(String, String)> props;

  /// 逻辑里读或改到的状态名。
  final Set<String> states;

  /// 程序里带上的库（“页面”库排第一个）。
  final List<LibLibrary> libs;
}

/// 页面自己那个模块的名字。
const String kLcCoreMainModule = 'main';

class _V {
  const _V(this.e, this.type);
  final LExpr e;

  /// 旧规矩里的静态类型（[LcType]）。
  final String type;
}

LExpr _any(LExpr e) => LAscribe(e, LType.any);
LExpr _not(LExpr e) => LUnary('not', e);

class _Fresh {
  int _n = 0;
  String call(String name) => '${name}_${++_n}';
}

class _Lower {
  _Lower(this.doc, this.lookup, this.pageUrl, this.userLibs);
  final LcDocument doc;
  final LcVariable? Function(String name)? lookup;
  final String Function(LcPage page) pageUrl;
  final List<LibLibrary> userLibs;

  final LibLibrary lib = lcPageLibrary();
  final _Fresh fresh = _Fresh();
  final List<String> skipped = [];
  final Set<(String, String)> props = {};
  final Set<String> states = {};

  /// 现在看得见的隐含的东西：名字 → 变量名。
  Map<String, String> context = {};

  LibCx get _cx => LibCx(context: context, settings: const {}, fresh: fresh.call);
  LcVariable? _variable(String name) => lookup == null ? doc.logic.variable(name) : lookup!(name);

  void _skip(LcBlock b, String why) => skipped.add('跳过「${describeBlock(b, doc)}」：$why');

  LibBlock _old(String fn) => lib.legacy(fn)!;

  LExpr _call(String legacyFn, Map<String, LExpr> values) => libApply(lib, _old(legacyFn), LibUse(values: values), _cx).value ?? const LLit(null);
  List<LStmt> _do(String legacyFn, Map<String, LExpr> values, {Map<String, List<LStmt>> mouths = const {}, Map<String, String> provided = const {}}) =>
      libApply(lib, _old(legacyFn), LibUse(values: values, mouths: mouths, provided: provided), _cx).stmts;

  // —— 旧规矩的转换（和 JsLogicWriter 的 toNum / toText / toBool / coerce 一条条对着）——
  _V toNum(_V v) => v.type == LcType.number ? v : _V(_call('lcNum', {'value': _any(v.e)}), LcType.number);
  _V toText(_V v) => v.type == LcType.text ? v : _V(_call('lcText', {'value': _any(v.e)}), LcType.text);
  _V toBool(_V v) => v.type == LcType.boolean ? v : _V(_call('lcBool', {'value': _any(v.e)}), LcType.boolean);
  _V coerce(_V v, String type) => switch (type) {
    LcType.number => toNum(v),
    LcType.boolean => toBool(v),
    LcType.text => toText(v),
    _ => v,
  };

  /// 语言核心里要一个“是否”的地方：旧规矩是 JS 的真假。
  LExpr cond(_V v) => _call('lcBool', {'value': _any(v.e)});
  _V _op(String op, _V a, _V b, String type) => _V(_call('bin', {'op': LLit(op), 'a': _any(a.e), 'b': _any(b.e)}), type);
  _V _hole() => const _V(LLit(null), LcType.any);

  _V expr(Object? e, String event, [int depth = 0]) {
    if (depth >= kMaxExprDepth) return _hole();
    final kind = exprKind(e);
    switch (kind) {
      case null:
        return _hole();
      case 'text':
        final v = exprString(e, 'v');
        return v == null ? _hole() : _V(LLit(v), LcType.text);
      case 'num':
        final v = exprNum(e, 'v');
        if (v == null || !v.isFinite) return _hole();
        return _V(LLit(v is int || (v == v.roundToDouble() && v.abs() < 1e15) ? v.round() : v), LcType.number);
      case 'bool':
        final v = exprBool(e, 'v');
        return v == null ? _hole() : _V(LLit(v), LcType.boolean);
      case 'var':
        final name = exprString(e, 'name');
        final v = name == null ? null : _variable(name);
        if (v == null) return _hole();
        states.add(v.name);
        return _V(_call('var', {'name': LLit(v.name)}), LcVariable.types.contains(v.type) && !v.isDerived ? v.type : LcType.any);
      case 'prop':
        final id = exprString(e, 'node');
        final prop = exprString(e, 'prop');
        final node = id == null ? null : doc.find(id);
        if (node == null || !isSafeNodeId(node.id)) return _hole();
        if (prop == null || !kReadableProps.contains(prop)) return _hole();
        if (!propFitsNode(prop, node.type)) return const _V(LLit(''), LcType.text);
        props.add((node.id, prop));
        return _V(_call('prop', {'node': LLit(node.id), 'prop': LLit(prop)}), prop == 'visible' ? LcType.boolean : LcType.text);
      case 'event':
        if (event != 'input' || !context.containsKey('事件')) return const _V(LLit(''), LcType.text);
        return _V(_call('event', const {}), LcType.text);
      case 'bin':
        return _bin(e, event, depth);
      case 'not':
        return _V(_not(cond(expr(exprField(e, 'x'), event, depth + 1))), LcType.boolean);
      case 'join':
        final items = exprField(e, 'items');
        final parts = [
          if (items is List)
            for (final item in items) toText(expr(item, event, depth + 1)),
        ];
        if (parts.isEmpty) return const _V(LLit(''), LcType.text);
        return parts.skip(1).fold(parts.first, (acc, p) => _op('+', acc, p, LcType.text));
      default:
        final hit = _userBlock(kind);
        if (hit == null) return _hole();
        if (!hit.block.isValue) return _hole();
        final got = _applyUser(hit.lib, hit.block, (s) => exprField(e, s), event, depth: depth + 1);
        return _V(got.value ?? const LLit(null), LcType.any);
    }
  }

  _V _bin(Object? e, String event, int depth) {
    final op = exprString(e, 'op');
    final l = expr(exprField(e, 'l'), event, depth + 1);
    final r = expr(exprField(e, 'r'), event, depth + 1);
    if (kArithmeticOps.contains(op)) return _op(op!, toNum(l), toNum(r), LcType.number);
    switch (op) {
      case '<' || '<=' || '>' || '>=':
        return _op(op!, toNum(l), toNum(r), LcType.boolean);
      case '==' || '!=':
        if (l.type == r.type && l.type != LcType.any) return _op(op == '==' ? '===' : '!==', l, r, LcType.boolean);
        final eq = _call('lcEq', {'a': _any(l.e), 'b': _any(r.e)});
        return _V(op == '==' ? eq : _not(eq), LcType.boolean);
      case 'and' || 'or':
        return _V(LLogic(op == 'and' ? 'and' : 'or', cond(l), cond(r)), LcType.boolean);
      default:
        return _hole();
    }
  }

  // —— 用户库的积木 ——

  ({LibLibrary lib, LibBlock block})? _userBlock(String op) {
    final ref = libOpOf(op);
    if (ref == null) return null;
    final l = ref.lib == lib.id ? lib : userLibs.where((x) => x.id == ref.lib).firstOrNull;
    if (l == null) {
      skipped.add('用到了库「${ref.lib}」的积木，可是这一页没有用上这个库（或者库不在项目里）');
      return null;
    }
    final block = l.block(ref.block);
    if (block == null) skipped.add('库「${l.name}」里没有积木「${ref.block}」（库换过版本了？）');
    return block == null ? null : (lib: l, block: block);
  }

  LibApplied _applyUser(LibLibrary l, LibBlock block, Object? Function(String slot) raw, String event, {List<List<LcBlock>> mouths = const [], int depth = 0}) {
    final values = <String, LExpr>{}, targets = <String, String>{}, lowered = <String, List<LStmt>>{};
    final provided = libProvided(block, fresh.call);
    var mouth = 0;
    for (final part in parseLookTemplate(block.look.template)) {
      if (!part.isSlot || values.containsKey(part.text) || targets.containsKey(part.text) || lowered.containsKey(part.text)) continue;
      final slot = part.text, v = raw(slot);
      switch (block.kindOf(slot)) {
        case LibSlotKind.mouth:
          final k = mouth++;
          final saved = context;
          context = {...context, ...provided};
          lowered[slot] = k < mouths.length ? blocks(mouths[k], event, depth + 1) : const [];
          context = saved;
        case LibSlotKind.assign:
          // “放进变量”在页面里没有对着的东西（页面只有状态）：这一格先不接，结果不存。
          break;
        case LibSlotKind.literal:
          values[slot] = v is String || v is num || v is bool ? LLit(v) : expr(v, event, depth).e;
        case LibSlotKind.value:
          values[slot] = block.look.slotFor(slot).kind == CustomSlotKind.choice && v is String ? LLit(v) : _any(expr(v, event, depth).e);
      }
    }
    final got = libApply(l, block, LibUse(values: values, mouths: lowered, targets: targets, provided: provided), LibCx(context: context, settings: _settingsOf(l), fresh: fresh.call));
    if (got.problem != null) skipped.add(got.problem!);
    return got;
  }

  Map<String, Object?> _settingsOf(LibLibrary l) {
    for (final u in doc.logic.uses) {
      if (u['id'] == l.id && u['settings'] is Map) return {for (final e in (u['settings'] as Map).entries) '${e.key}': e.value};
    }
    return const {};
  }

  // —— 积木 ——

  List<LStmt> blocks(List<LcBlock> list, String event, [int depth = 0]) {
    if (list.isEmpty || depth > LcBlock.maxDepth) return const [];
    return [for (final b in list) ..._block(b, event, depth)];
  }

  List<LStmt> _write(LcVariable v, _V value) {
    states.add(v.name);
    return _do('setVar', {'name': LLit(v.name), 'value': _any(value.e)});
  }

  List<LStmt> _block(LcBlock b, String event, int depth) {
    _V arg(String name) => expr(b.args[name], event);
    List<LStmt> inner(List<LcBlock> list) => blocks(list, event, depth + 1);
    LcVariable? variable(String key) {
      final name = b.args[key];
      return name is String ? _variable(name) : null;
    }

    switch (b.op) {
      case 'setVar':
        final v = variable('name');
        if (v == null) return _none(b, '状态没有声明');
        if (v.isDerived) return _none(b, '${v.name} 是派生值，算出来的，不能改');
        return _write(v, coerce(arg('value'), v.type));
      case 'changeVar':
        final v = variable('name');
        if (v == null) return _none(b, '状态没有声明');
        if (v.type != 'number') return _none(b, '这个状态不是数字');
        states.add(v.name);
        return _write(v, _op('+', _V(_call('var', {'name': LLit(v.name)}), LcType.number), toNum(arg('by')), LcType.number));
      case 'setProp':
        final id = b.args['node'];
        final prop = b.args['prop'];
        final node = id is String ? doc.find(id) : null;
        if (node == null || !isSafeNodeId(node.id)) return _none(b, '找不到控件');
        if (prop is! String || !kWritableProps.contains(prop)) return _none(b, '不认识的属性');
        if (!propFitsNode(prop, node.type)) return _none(b, '这种控件没有“${describeProp(prop)}”');
        props.add((node.id, prop));
        return _do('setProp', {'node': LLit(node.id), 'prop': LLit(prop), 'value': _any(coerce(arg('value'), prop == 'visible' ? LcType.boolean : LcType.text).e)});
      case 'if':
        return [
          LIf([LIfArm(cond(arg('cond')), inner(b.body))], orElse: inner(b.orElse)),
        ];
      case 'repeat':
        // 旧规矩：for (i = 0, n = Math.min(转数字(次数), 上限); i < n; i++)——“重复 2.5 次”做 3 遍。
        final i = fresh('第几遍'), n = fresh('遍数');
        const anyNum = LcType.number;
        return [
          LLet(n, _op('min', toNum(arg('times')), const _V(LLit(kRepeatLimit), anyNum), anyNum).e),
          LLet(i, _any(const LLit(0))),
          LWhile(cond(_op('<', _V(LName(i), anyNum), _V(LName(n), anyNum), LcType.boolean)), [
            ...inner(b.body),
            LAssign(LTName(i), _op('+', _V(LName(i), anyNum), const _V(LLit(1), anyNum), anyNum).e),
          ]),
        ];
      case 'wait':
        return _do('wait', {'ms': _any(toNum(arg('ms')).e)}, mouths: {'body': inner(b.body)});
      case 'alert':
        return _do('alert', {'message': _any(toText(arg('message')).e)});
      case 'navigate':
        return _do('navigate', {'url': _any(toText(arg('url')).e)});
      case kLcGoPageOp:
        final id = b.args['page'];
        final page = id is String ? doc.pageById(id) : null;
        if (page == null) return _none(b, '要去的页面已经不在了');
        return _do('navigate', {'url': LLit(pageUrl(page))});
      case 'log':
        return _do('log', {'value': _any(arg('value').e)});
      case 'fetch':
        return _fetch(b, event, depth);
      default:
        final hit = _userBlock(b.op);
        if (hit == null) {
          if (libOpOf(b.op) == null) skipped.add('不认识的积木：${b.op}（已跳过）');
          return const [];
        }
        final got = _applyUser(hit.lib, hit.block, (s) => b.args[s], event, mouths: [b.body, b.orElse], depth: depth);
        final v = got.value;
        return v != null ? [LExprStmt(v)] : got.stmts;
    }
  }

  List<LStmt> _none(LcBlock b, String why) {
    _skip(b, why);
    return const [];
  }

  List<LStmt> _fetch(LcBlock b, String event, int depth) {
    final block = _old('fetch');
    final provided = libProvided(block, fresh.call);
    final into = b.args['into'];
    final v = into is String && into.isNotEmpty ? _variable(into) : null;
    if (v == null && into is String && into.isNotEmpty) skipped.add('状态 $into 没有声明，请求的结果没有存');
    final saved = context;
    context = {...context, ...provided};
    final body = [
      if (v != null && !v.isDerived) ..._write(v, coerce(_V(libApply(lib, lib.block('fetchText')!, const LibUse(), _cx).value ?? const LLit(null), LcType.text), v.type)),
      ...blocks(b.body, event, depth + 1),
    ];
    context = saved;
    return _do(
      'fetch',
      {'method': LLit(b.args['method'] == 'POST' ? 'POST' : 'GET'), 'url': _any(toText(expr(b.args['url'], event)).e)},
      mouths: {'body': body, 'orElse': blocks(b.orElse, event, depth + 1)},
      provided: provided,
    );
  }

  /// 一个处理 → 一顶帽子。挂不上的（控件不在了、不认识的事件）不翻，和旧生成器一样“函数还在、没挂上”。
  List<LStmt> handler(LcHandler h) {
    final String id;
    final values = <String, LExpr>{};
    if (h.event == 'load') {
      id = 'onMounted';
    } else if (h.event == 'click' || h.event == 'input') {
      final node = h.target == null ? null : doc.find(h.target!);
      if (node == null || !isSafeNodeId(node.id)) {
        skipped.add('处理「${describeHandler(h, doc)}」没有挂到任何控件上（触发它的控件不在页面里）');
        return const [];
      }
      id = h.event == 'click' ? 'onClick' : 'onInput';
      values['node'] = LLit(node.id);
    } else {
      skipped.add('不认识的事件 ${h.event}，没有挂上');
      return const [];
    }
    final block = lib.block(id)!;
    final provided = libProvided(block, fresh.call);
    context = {...provided};
    final body = blocks(h.body, h.event);
    final got = libApply(lib, block, LibUse(values: values, mouths: {'body': body}, provided: provided), LibCx(context: context, settings: const {}, fresh: fresh.call));
    context = {};
    if (got.problem != null) skipped.add(got.problem!);
    return got.stmts;
  }
}

/// 把现在这一页的逻辑翻成语言核心的程序。
///
/// [lookup]：按名字找状态（用了项目级状态的页面给“先这一页、再项目级”的找法；不给就只认这一页的）。
/// [pageUrl]：“去页面”要去的地址（纯网页是 `页名.html`；Vue / React 是地址栏里 `#/页面 id`）。
LcCoreBuilt lcLogicToCore(LcDocument doc, {LcVariable? Function(String name)? lookup, required String Function(LcPage page) pageUrl}) {
  final problems = <String>[];
  final page = lcPageLibrary();
  if (!page.ok) return LcCoreBuilt(problems: ['内置库“页面”读不了：${page.problems.first}']);
  final userLibs = lcUsedLibs(doc.logic, problems);
  final lower = _Lower(doc, lookup, pageUrl, userLibs);
  final body = <LStmt>[];
  // 库的“启动时”先做（按用上的先后），再一个个处理登记。
  for (final l in userLibs) {
    final got = libMoment(l, l.init, LibCx(context: const {}, settings: lower._settingsOf(l), fresh: lower.fresh.call));
    if (got.problem != null) problems.add(got.problem!);
    body.addAll(got.stmts);
  }
  for (final h in doc.logic.handlers) {
    body.addAll(lower.handler(h));
  }
  final libs = [page, ...userLibs];
  return LcCoreBuilt(
    program: libProgram(libs, LModule(name: kLcCoreMainModule, body: body)),
    problems: problems,
    skipped: lower.skipped,
    props: lower.props,
    states: lower.states,
    libs: libs,
  );
}
