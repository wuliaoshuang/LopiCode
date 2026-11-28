/// 新的页面逻辑里“对着页面才查得出”的问题（积木第 5 版·前端 1·下半）。
///
/// 积木文档自己的检查（类型、名字、库……）在 backend_validate.dart；这里只查要看页面才知道的：
///
/// - 帽子挂的控件不在这一页了；
/// - “当〔组件实例〕发出〔事件〕”：挂的不是组件实例，或者那个组件没有这个事件；
/// - “这一项”“第几项”“这一项的…”用在了不是“重复”出来的控件的事件里；
/// - “事件带来的…”用在了不是组件事件的地方；
/// - “去页面”：页面不在了；那一页要读的参数这里没带。
///
/// 不依赖界面；任何输入都不抛异常。
library;

import 'package:lopicode/backend/backend_blocks_typeops.dart';
import 'package:lopicode/backend/backend_model.dart';
import 'package:lopicode/backend/backend_type_bridge.dart';
import 'package:lopicode/backend/front_doc.dart';
import 'package:lopicode/lang/lang.dart';
import 'package:lopicode/lowcode/bind_model.dart';
import 'package:lopicode/lowcode/component_model.dart';
import 'package:lopicode/lowcode/lib_blocks.dart' show libOpOf;
import 'package:lopicode/lowcode/lib_page.dart';
import 'package:lopicode/lowcode/logic_expr.dart' show kMaxExprDepth;
import 'package:lopicode/lowcode/logic_model.dart';
import 'package:lopicode/lowcode/logic_validate.dart';
import 'package:lopicode/lowcode/model.dart';

/// 这几块只在“重复”出来的控件的事件里才有意义。
const Set<String> _itemBlocks = {'eventItem', 'eventIndex', 'eventItemField'};
const Set<String> _nodeHats = {'onClick', 'onInput', 'onEmit'};

String? _pageBlock(Object? op) {
  final ref = libOpOf(op);
  return ref != null && ref.lib == kLcPageLibId ? ref.block : null;
}

String _lit(Object? v) => v is String ? v : (v is Map && v['e'] == 'text' && v['v'] is String ? v['v'] as String : '');

LcNode? _find(LcNode root, String id) {
  if (root.id == id) return root;
  for (final c in root.children) {
    final r = _find(c, id);
    if (r != null) return r;
  }
  return null;
}

/// 这个控件自己或者它外面哪一层是“重复”出来的。
bool _inRepeat(LcNode root, String id) {
  bool walk(LcNode n, bool inside) {
    final here = inside || lcRepeatOf(n) != null;
    if (n.id == id) return here;
    return n.children.any((c) => walk(c, here));
  }

  return walk(root, false);
}

/// 组件对外发的事件名：定义上写的 `events`，加上定义里各控件 `emit` 里写的。
Set<String> lcComponentEvents(LcComponentDef def) {
  final out = <String>{};
  final events = def.more['events'];
  if (events is List) {
    for (final e in events) {
      if (e is Map && e['name'] is String) out.add(e['name'] as String);
    }
  }
  void walk(LcNode n, int depth) {
    final emit = n.more['emit'];
    if (emit is Map) {
      for (final v in emit.values) {
        if (v is Map && v['event'] is String) out.add(v['event'] as String);
      }
    }
    if (depth > 64) return;
    for (final c in n.children) {
      walk(c, depth + 1);
    }
  }

  walk(def.root, 0);
  return out;
}

/// 这一页的新逻辑里读了哪些“这次带来的参数”（名字是写死的那些）。
Set<String> lcFrontParamsRead(BeDocument front) {
  final out = <String>{};
  void expr(Object? v, int depth) {
    if (depth > kMaxExprDepth * 2 + 4) return;
    if (v is List<LcBlock>) return;
    if (v is List) {
      for (final x in v) {
        expr(x, depth + 1);
      }
    } else if (v is Map) {
      if (_pageBlock(v['e']) == 'pageParam') {
        final name = _lit(v['name']);
        if (name.isNotEmpty) out.add(name);
      }
      for (final x in v.values) {
        expr(x, depth + 1);
      }
    }
  }

  void walk(List<LcBlock> list, int depth) {
    if (depth > LcBlock.maxDepth + 2) return;
    for (final b in list) {
      expr(b.args, 0);
      for (final a in b.arms) {
        expr(a.args, 0);
        walk(a.body, depth + 1);
      }
      walk(b.body, depth + 1);
      walk(b.orElse, depth + 1);
    }
  }

  for (final body in front.libBodies) {
    walk(body, 0);
  }
  return out;
}

/// 那一页说了每个带来的参数要是什么类型：把“这次带来的参数〔名字〕”直接放进“当成某类型用”或“标上类型”里就算说了。
/// 名字 → 类型（存在积木里的那个字）。同一个参数说了两种的、说成“任意”的、说成那一页自己定义的类型的，都不算（这边查不了）。
Map<String, String> lcFrontParamTypes(BeDocument front) {
  final out = <String, String>{};
  final clash = <String>{};
  final own = {for (final t in front.core.types) t.name};
  void expr(Object? v, int depth) {
    if (depth > kMaxExprDepth * 2 + 4) return;
    if (v is List<LcBlock>) return;
    if (v is List) {
      for (final x in v) {
        expr(x, depth + 1);
      }
    } else if (v is Map) {
      final x = v['x'], to = v['to'];
      if ((v['e'] == kBeCast || v['e'] == kBeAscribe) && x is Map && _pageBlock(x['e']) == 'pageParam' && to is String) {
        final name = _lit(x['name']);
        final type = beTypeOfKey(to);
        final usable = name.isNotEmpty && type != null && to != beTypeKey(LType.any) && !own.any(to.contains);
        if (usable && out.putIfAbsent(name, () => to) != to) clash.add(name);
      }
      for (final x in v.values) {
        expr(x, depth + 1);
      }
    }
  }

  void walk(List<LcBlock> list, int depth) {
    if (depth > LcBlock.maxDepth + 2) return;
    for (final b in list) {
      expr(b.args, 0);
      for (final a in b.arms) {
        expr(a.args, 0);
        walk(a.body, depth + 1);
      }
      walk(b.body, depth + 1);
      walk(b.orElse, depth + 1);
    }
  }

  for (final body in front.libBodies) {
    walk(body, 0);
  }
  clash.forEach(out.remove);
  return out;
}

class _Check {
  _Check(this.doc, this.page, this.front);
  final LcDocument doc;
  final LcPage page;
  final BeDocument front;
  final List<LcLogicIssue> issues = [];

  String _scope = '';
  String? _tree;
  LcBlockPath _path = const [];

  void _error(String code, String problem, {String? arg}) {
    final spot = _path.isEmpty ? '' : '第 ${_path.first.index + 1} 块${_path.length > 1 ? '里面' : ''}';
    issues.add(
      LcLogicIssue(
        level: LcIssueLevel.error,
        code: code,
        problem: problem,
        where: '$_scope$spot',
        handlerId: _tree,
        path: _path,
        arg: arg,
        exprPath: arg == null ? null : const [],
        scope: _scope,
        spot: spot,
      ),
    );
  }

  void run() {
    for (final h in front.hats) {
      final id = lcFrontHatBlock(h);
      _tree = h.id;
      _path = const [];
      _scope = '帽子「${lcPageLibrary().block(id ?? '')?.look.name ?? '事件'}」';
      var repeated = false, emits = false;
      if (id != null && _nodeHats.contains(id)) {
        final nodeId = _lit(h.args['node']);
        final node = nodeId.isEmpty ? null : _find(page.root, nodeId);
        if (nodeId.isNotEmpty && node == null) {
          _error(LcIssueCode.nodeNotFound, '这顶帽子挂的控件不在这一页了（可能已经删掉）', arg: 'node');
        } else if (node != null) {
          repeated = _inRepeat(page.root, node.id);
          if (id == 'onEmit') emits = _emit(node, _lit(h.args['event']));
        }
      }
      _blocks(h.body, const [], repeated: repeated, emits: emits, inHat: true);
    }
    _scope = '';
    _tree = null;
    for (final f in front.functions) {
      _tree = f.id;
      _scope = '积木「${f.name}」';
      _blocks(f.body, const [], repeated: true, emits: true, inHat: false);
    }
  }

  /// “当〔组件实例〕发出〔事件〕”对不对；对＝true。
  bool _emit(LcNode node, String event) {
    final ref = node.props['ref'];
    final def = node.type == 'component' && ref is String ? doc.component(ref) : null;
    if (def == null) {
      _error(LcIssueCode.badArg, '“发出事件”只有自定义组件的实例才有：这里挂的不是组件实例', arg: 'node');
      return false;
    }
    if (event.isEmpty) return false; // “还没填”那一条积木文档自己的检查会报
    final known = lcComponentEvents(def);
    if (!known.contains(event)) {
      _error(LcIssueCode.badArg, '组件「${def.name}」没有叫「$event」的事件${known.isEmpty ? '（它还没有往外发任何事件，先到“编辑组件”里定）' : '（它有：${known.join('、')}）'}', arg: 'event');
      return false;
    }
    return true;
  }

  void _blocks(List<LcBlock> list, LcBlockPath parent, {required bool repeated, required bool emits, required bool inHat, bool inElse = false, int arm = -1, int depth = 0}) {
    if (depth > LcBlock.maxDepth + 2) return;
    for (var i = 0; i < list.length; i++) {
      final b = list[i];
      final path = [...parent, lcStep(i, inElse: inElse, arm: arm)];
      _path = path;
      _use(b.op, (s) => b.args[s], repeated: repeated, emits: emits);
      _expr(b.args, 0, repeated: repeated, emits: emits);
      for (var k = 0; k < b.arms.length; k++) {
        _path = path;
        _expr(b.arms[k].args, 0, repeated: repeated, emits: emits);
        _blocks(b.arms[k].body, path, repeated: repeated, emits: emits, inHat: inHat, arm: k, depth: depth + 1);
      }
      _blocks(b.body, path, repeated: repeated, emits: emits, inHat: inHat, depth: depth + 1);
      _blocks(b.orElse, path, repeated: repeated, emits: emits, inHat: inHat, inElse: true, depth: depth + 1);
    }
  }

  void _expr(Object? v, int depth, {required bool repeated, required bool emits}) {
    if (depth > kMaxExprDepth * 2 + 4) return;
    if (v is List<LcBlock>) return;
    if (v is List) {
      for (final x in v) {
        _expr(x, depth + 1, repeated: repeated, emits: emits);
      }
    } else if (v is Map) {
      _use(v['e'], (s) => v[s], repeated: repeated, emits: emits);
      for (final x in v.values) {
        _expr(x, depth + 1, repeated: repeated, emits: emits);
      }
    }
  }

  void _use(Object? op, Object? Function(String slot) arg, {required bool repeated, required bool emits}) {
    final id = _pageBlock(op);
    if (id == null) return;
    if (_itemBlocks.contains(id) && !repeated) {
      _error(LcIssueCode.badArg, '“${lcPageLibrary().block(id)?.look.name ?? '这一项'}”只能用在“重复”出来的控件的事件里：这顶帽子挂的控件不是重复出来的');
    }
    if (id == 'emitData' && !emits) _error(LcIssueCode.badArg, '“事件带来的…”只能用在“当〔组件〕发出〔事件〕”下面');
    if (id == 'goPage' || id == 'goPageWith') _go(id, _lit(arg('page')), arg('params'));
  }

  void _go(String id, String pageId, Object? params) {
    if (pageId.isEmpty) return; // “还没选”积木文档自己的检查会报
    final target = doc.pageById(pageId);
    if (target == null) {
      _error(LcIssueCode.badArg, '要去的页面不在了（可能已经删掉）', arg: 'page');
      return;
    }
    final targetFront = lcFrontOf(target.logic);
    if (targetFront == null) return;
    final wants = lcFrontParamsRead(targetFront);
    if (wants.isEmpty) return;
    final Set<String> given;
    if (id == 'goPage') {
      given = const {};
    } else if (params is Map && params['e'] == 'obj' && params['fields'] is List) {
      given = {
        for (final f in params['fields'] as List)
          if (f is Map && f['key'] is String) f['key'] as String,
      };
    } else {
      return; // 参数是算出来的：这里看不出带了哪些
    }
    final missing = wants.difference(given);
    if (missing.isNotEmpty) _error(LcIssueCode.missingArg, '「${target.title}」那一页要读带来的参数 ${missing.join('、')}，这里没带', arg: id == 'goPage' ? 'page' : 'params');
    if (params is! Map || params['fields'] is! List) return;
    final types = lcFrontParamTypes(targetFront);
    if (types.isEmpty) return;
    for (final f in params['fields'] as List) {
      final type = f is Map ? types[f['key']] : null;
      if (f is! Map || type == null || f['value'] is! Map) continue;
      if (_fits(f, type) == false) {
        _error(LcIssueCode.badArg, '「${target.title}」那一页把带来的参数 ${f['key']} 当成${beTypeLabel(type) ?? type}用，这里带的不是${beTypeLabel(type) ?? type}', arg: 'params');
      }
    }
  }

  int? _base;
  int? _mismatches() => beTypeCheck(front)?.findings.where((f) => f.issue.code == 'T01').length;

  /// 这一格的值放不放得进 [type]：临时给它套一层“标上类型”，看类型检查会不会多报一条“放不进去”。查不了（不是严格规矩…）＝null。
  bool? _fits(Map<dynamic, dynamic> field, String type) {
    final base = _base ??= _mismatches();
    if (base == null) return null;
    final old = field['value'];
    field['value'] = <String, dynamic>{'e': kBeAscribe, 'x': old, 'to': type};
    try {
      final now = _mismatches();
      return now == null ? null : now <= base;
    } on Object {
      return null;
    } finally {
      field['value'] = old;
    }
  }
}

/// 这一页的新逻辑对着页面查出来的问题（都是“错误”级）。不是新逻辑的页面＝空。
List<LcLogicIssue> lcFrontPageIssues(LcDocument doc, LcPage page, [BeDocument? front]) {
  final f = front ?? lcFrontOf(page.logic);
  if (f == null) return const [];
  return (_Check(doc, page, f)..run()).issues;
}
