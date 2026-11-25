// 假宿主的第 2 阶段扩展：函数定义（带参数小块的帽子）、匿名函数（带口的值 + 短写法）、自定义积木（“我的积木”）。
// 老的 FakeHost 一点没变；这里的东西只有用 FakeFnHost 才有。存盘：定义那一串多一个 `def`（{id, look, params}），
// 匿名函数的口里的积木在表达式的 `@body` 里。
import 'package:lopicode/blocks/block_host.dart';
import 'package:lopicode/lang/custom_block_edit.dart';
import 'package:lopicode/lang/lang.dart' show LParam;
import 'package:lopicode/lowcode/logic_blocks.dart';
import 'package:lopicode/lowcode/logic_model.dart';

import 'blocks_fake_host.dart';

const Map<String, LcBlockSpec> _fnBlockSpecs = {
  'return': LcBlockSpec('return', '返回', '函数', [LcArgSpec('value', '值', LcArgKind.expr)]),
  'run': LcBlockSpec('run', '执行', '函数', [LcArgSpec('fn', '函数', LcArgKind.expr)]),
};

const Map<String, LcExprSpec> _fnExprSpecs = {
  // 读一个参数：参数小块拖出来就是它。
  'param': LcExprSpec('param', '参数', '函数', [LcArgSpec('name', '参数', LcArgKind.variable)]),
  // 匿名函数：带口的值。
  'fn': LcExprSpec('fn', '函数', '函数', [], paramsArg: 'params', hasMouth: true),
  // 短写法：一个式子。
  'fnShort': LcExprSpec('fnShort', '短函数', '函数', [LcArgSpec('body', '结果', LcArgKind.expr)], paramsArg: 'params'),
  'listMap': LcExprSpec('listMap', '每一项变一下', '列表', [LcArgSpec('list', '列表', LcArgKind.expr), LcArgSpec('fn', '怎么变', LcArgKind.expr)]),
};

const Map<String, String> _fnSentences = {'return': '返回 {value}', 'run': '执行 {fn}', 'fn': '函数 {@params}', 'fnShort': '{@params} → {body}', 'listMap': '把 {list} 的每一项变一下 {fn}'};

Map<String, dynamic> fxParam(String name) => fxExpr('param', {'name': name});
Map<String, dynamic> fxFn(List<String> params, [List<LcBlock> body = const []]) => fxExpr('fn', {
  'params': [...params],
  kLcExprBody: [...body],
});
Map<String, dynamic> fxFnShort(List<String> params, Object body) => fxExpr('fnShort', {
  'params': [...params],
  'body': body,
});
Map<String, dynamic> fxListMap(Object list, Object fn) => fxExpr('listMap', {'list': list, 'fn': fn});

/// 造一串“定义”。
FakeScript fakeDef(String scriptId, String id, CustomBlockLook look, List<BlockParam> params, {List<LcBlock>? body, double? x, double? y}) =>
    FakeScript(scriptId, body: body, x: x, y: y, def: {'id': id, 'look': look.toJson(), 'params': _paramsJson(params)});

List<Map<String, dynamic>> _paramsJson(List<BlockParam> params) => [
  for (final p in params) {'name': p.name, 'default': ?p.defaultValue, if (p.rest) 'rest': true},
];

class FakeFnHost extends FakeHost implements BlockCustomHost {
  FakeFnHost({super.scripts, this.wrappable = true});

  /// 关掉＝不支持“包成积木”（长按语句积木没有菜单）。
  final bool wrappable;
  int _nextDef = 1;

  // —— 定义 ——

  FakeScript? _defScript(String id) => fakeScripts.where((s) => s.def?['id'] == id).firstOrNull;

  List<BlockParam> paramsOf(FakeScript s) => [
    for (final p in (s.def?['params'] as List? ?? const []))
      if (p is Map) BlockParam('${p['name']}', defaultValue: p['default'], rest: p['rest'] == true),
  ];

  CustomBlockLook lookOf(FakeScript s) => customBlockLookFromJson(s.def?['look']) ?? const CustomBlockLook('？');

  BlockCustom _customOf(FakeScript s) {
    final look = lookOf(s);
    var hasValue = false;
    s.visitBlocks((b, _) => hasValue = hasValue || b.op == 'return');
    return BlockCustom('${s.def!['id']}', look.copyWith(shape: resolveLookShape(look.shape, hasValue: hasValue)), [for (final p in paramsOf(s)) p.name]);
  }

  BlockCustom? _custom(String id) {
    final s = _defScript(id);
    return s == null ? null : _customOf(s);
  }

  @override
  BlockCustomHost? get custom => this;

  @override
  List<BlockCustom> get customs => [
    for (final s in fakeScripts)
      if (s.def != null) _customOf(s),
  ];

  // —— 规格 ——

  @override
  List<BlockCategory> get categories => [
    ...super.categories,
    const BlockCategory(
      id: 'function',
      label: '函数',
      colorKey: BlockColorKey.function,
      hats: [
        BlockHatTemplate('define', BlockHat([BlockHatPart.text('定义'), BlockHatPart.slot('name', '新函数', kind: LcArgKind.literalText)], colorKey: BlockColorKey.function)),
      ],
      blocks: ['return', 'run'],
      exprs: ['fn', 'fnShort', 'listMap'],
    ),
  ];

  @override
  LcBlockSpec? blockSpec(String op) {
    final c = _custom(op);
    if (c != null) return c.isValue ? null : bkLookBlockSpec(c);
    return _fnBlockSpecs[op] ?? super.blockSpec(op);
  }

  @override
  LcExprSpec? exprSpec(String kind) {
    final c = _custom(kind);
    if (c != null) return c.isValue ? bkLookExprSpec(c) : null;
    return _fnExprSpecs[kind] ?? super.exprSpec(kind);
  }

  @override
  String? blockSentence(String op) {
    final c = _custom(op);
    return c != null ? bkLookSentence(c.look, c.params) : (_fnSentences[op] ?? super.blockSentence(op));
  }

  @override
  String? exprSentence(String kind) {
    final c = _custom(kind);
    return c != null ? bkLookSentence(c.look, c.params) : (_fnSentences[kind] ?? super.exprSentence(kind));
  }

  @override
  String blockColorKey(String op) => _custom(op)?.look.colorKey ?? (_fnBlockSpecs.containsKey(op) ? BlockColorKey.function : super.blockColorKey(op));
  @override
  String exprColorKey(String kind) => _custom(kind)?.look.colorKey ?? (kind == 'listMap' ? BlockColorKey.list : (_fnExprSpecs.containsKey(kind) ? BlockColorKey.function : super.exprColorKey(kind)));

  @override
  bool isBooleanExpr(Map<String, dynamic> expr) => _custom('${expr['e']}')?.look.shape == CustomBlockShape.boolean || super.isBooleanExpr(expr);

  @override
  List<BlockOption> options(LcArgSpec arg, {LcBlockTree? tree, LcBlock? block, Map<String, dynamic>? expr}) {
    if (arg.kind != LcArgKind.variable) return super.options(arg, tree: tree, block: block, expr: expr);
    final names = <String>{
      if (tree is FakeScript) ...[for (final p in paramsOf(tree)) p.name],
      if (tree is FakeScript) ..._lambdaParams(tree),
    };
    return [for (final n in names) BlockOption(n, n)];
  }

  Set<String> _lambdaParams(FakeScript s) {
    final out = <String>{};
    _eachExpr(s, (e) {
      final ps = e['params'];
      if (ps is List) out.addAll(ps.whereType<String>());
    });
    return out;
  }

  // —— 帽子 ——

  @override
  BlockHat hatOf(LcBlockTree tree) {
    if (tree is! FakeScript || tree.def == null) return super.hatOf(tree);
    final name = lookOf(tree).name;
    return BlockHat([const BlockHatPart.text('定义'), BlockHatPart.slot('name', name.isEmpty ? '名字' : name, empty: name.isEmpty, kind: LcArgKind.literalText)], colorKey: BlockColorKey.function);
  }

  @override
  String hatSlotValue(LcBlockTree tree, String slotId) => tree is FakeScript && tree.def != null ? lookOf(tree).name : super.hatSlotValue(tree, slotId);

  @override
  bool setHatSlot(LcBlockTree tree, String slotId, String value) {
    if (tree is! FakeScript || tree.def == null || value.trim().isEmpty) return false;
    tree.def!['look'] = lookOf(tree).copyWith(name: value.trim()).toJson();
    return true;
  }

  @override
  BlockHatParams? hatParams(LcBlockTree tree) => tree is FakeScript && tree.def != null ? BlockHatParams(paramsOf(tree), max: 6) : null;

  @override
  bool setHatParams(LcBlockTree tree, List<BlockParam> params, {({String from, String to})? renamed}) {
    if (tree is! FakeScript || tree.def == null) return false;
    final old = paramsOf(tree);
    // 按名字认；改了名的那个靠 renamed 认。
    final origin = <int?>[
      for (final p in params)
        () {
          final i = old.indexWhere((o) => o.name == (renamed != null && p.name == renamed.to ? renamed.from : p.name));
          return i < 0 ? null : i;
        }(),
    ];
    _reshape(tree, lookOf(tree), params, origin);
    return true;
  }

  @override
  int hatParamUses(LcBlockTree tree, String name) => tree is FakeScript && tree.def != null ? usesOf('${tree.def!['id']}') : 0;

  @override
  Map<String, dynamic>? paramExpr(String name) => fxParam(name);

  @override
  void exprParamRenamed(LcBlockTree tree, Map<String, dynamic> expr, String from, String to) {
    Object? rename(Map<String, dynamic> e) {
      if (e['e'] == 'param' && e['name'] == from) e['name'] = to;
      return e;
    }

    for (final k in expr.keys.toList()) {
      if (k != kLcExprBody) expr[k] = _rewrite(expr[k], rename);
    }
    _eachBlock(lcExprBody(expr) ?? const <LcBlock>[], (x) => _rewriteBlock(x, rename));
  }

  @override
  LcBlockTree? addScript(String templateId, {double? x, double? y}) {
    if (templateId != 'define') return super.addScript(templateId, x: x, y: y);
    final s = fakeDef(nextScriptId(), 'my${_nextDef++}', CustomBlockLook(_freshName('新函数')), const [], x: x, y: y);
    fakeScripts.add(s);
    return s;
  }

  String _freshName(String base) {
    final taken = {for (final c in customs) c.look.name};
    if (!taken.contains(base)) return base;
    for (var i = 2; ; i++) {
      if (!taken.contains('$base$i')) return '$base$i';
    }
  }

  // —— 新积木 ——

  @override
  LcBlock newBlock(String op) {
    final c = _custom(op);
    if (c != null) return LcBlock(op: op, args: {for (final s in c.slots) s.name: slotValue(s)});
    return switch (op) {
      'return' => LcBlock(op: op, args: {'value': fxText('')}),
      'run' => LcBlock(op: op, args: {'fn': fxFn(const [])}),
      _ => super.newBlock(op),
    };
  }

  @override
  Map<String, dynamic> newExpr(String kind) {
    final c = _custom(kind);
    if (c != null) return fxExpr(kind, {for (final s in c.slots) s.name: slotValue(s)});
    return switch (kind) {
      'fn' => fxFn(['x']),
      'fnShort' => fxFnShort(['x'], fxParam('x')),
      'listMap' => fxListMap(fxExpr('listNew'), fxFnShort(['x'], fxParam('x'))),
      'param' => fxParam('x'),
      _ => super.newExpr(kind),
    };
  }

  @override
  Object? slotValue(CustomBlockSlot slot) {
    final d = slot.defaultValue;
    return switch (slot.kind) {
      CustomSlotKind.choice => slot.options.contains(d) ? d : (slot.options.isEmpty ? '' : slot.options.first),
      CustomSlotKind.boolean => fxBool(d == true),
      _ => d is num ? fxNum(d) : (d is bool ? fxBool(d) : fxText(d is String ? d : '')),
    };
  }

  // —— 我的积木 ——

  @override
  String? create(CustomBlockLook look, List<String> params) {
    final id = 'my${_nextDef++}';
    while (_defScript('my$_nextDef') != null) {
      _nextDef++;
    }
    // 值槽“先放什么”同时当参数的默认值（帽子上看得见“次数＝1”）。
    fakeScripts.add(fakeDef(nextScriptId(), id, look, [for (final p in params) BlockParam(p, defaultValue: look.slotFor(p).kind == CustomSlotKind.value ? look.slotFor(p).defaultValue : null)]));
    return id;
  }

  @override
  bool update(String id, CustomBlockLook look, List<String> params, List<int?> origin) {
    final s = _defScript(id);
    if (s == null) return false;
    final old = paramsOf(s);
    _reshape(
      s,
      look,
      [
        for (final (i, p) in params.indexed)
          () {
            final o = i < origin.length ? origin[i] : null;
            return o != null && o >= 0 && o < old.length ? old[o].copyWith(name: p) : BlockParam(p);
          }(),
      ],
      origin,
      lookIsNew: true,
    );
    return true;
  }

  /// 定义的参数表变了：帽子、外观、函数体里读参数的地方、各处调用的槽一起跟着变（用语言核心的 remap）。
  void _reshape(FakeScript s, CustomBlockLook look, List<BlockParam> params, List<int?> origin, {bool lookIsNew = false}) {
    final id = '${s.def!['id']}';
    final old = paramsOf(s);
    LParam lp(BlockParam p) => LParam(p.name, rest: p.rest);
    final oldL = [for (final p in old) lp(p)], newL = [for (final p in params) lp(p)];
    final nextLook = lookIsNew ? look : remapLook(look, oldParams: oldL, newParams: newL, origin: origin);
    s.def!
      ..['look'] = nextLook.toJson()
      ..['params'] = _paramsJson(params);
    final renames = {
      for (final (i, p) in params.indexed)
        if (i < origin.length && origin[i] != null && old[origin[i]!].name != p.name) old[origin[i]!].name: p.name,
    };
    if (renames.isNotEmpty) {
      _eachBlock(
        s.body,
        (b) => _rewriteBlock(b, (e) {
          if (e['e'] == 'param' && renames.containsKey(e['name'])) e['name'] = renames[e['name']];
          return e;
        }),
      );
    }
    Map<String, dynamic> remap(Map<String, dynamic> args) {
      final r = remapCallArgsByName<Object?>(
        oldParams: oldL,
        newParams: newL,
        origin: origin,
        args: {
          for (final p in old)
            if (args.containsKey(p.name)) p.name: args[p.name],
        },
        fill: (p) => slotValue(nextLook.slotFor(p.name)),
      );
      return {for (final e in r.args) e.key: e.value};
    }

    for (final t in fakeScripts) {
      _eachBlock(t.body, (b) {
        if (b.op == id) {
          final next = remap(b.args);
          b.args
            ..clear()
            ..addAll(next);
        }
        _rewriteBlock(b, (e) {
          if (e['e'] != id) return e;
          final next = remap({...e}..remove('e'));
          e
            ..removeWhere((k, _) => k != 'e')
            ..addAll(next);
          return e;
        });
      });
    }
  }

  @override
  int usesOf(String id) {
    var n = 0;
    for (final s in fakeScripts) {
      s.visitBlocks((b, _) => n += b.op == id ? 1 : 0);
      _eachExpr(s, (e) => n += e['e'] == id ? 1 : 0);
    }
    return n;
  }

  @override
  bool remove(String id) {
    final s = _defScript(id);
    if (s == null) return false;
    fakeScripts.remove(s);
    for (final t in fakeScripts) {
      _dropCalls(t.body, id);
      _eachBlock(t.body, (b) => _rewriteBlock(b, (e) => e['e'] == id ? fxText('') : e));
    }
    return true;
  }

  void _dropCalls(List<LcBlock> list, String id) {
    list.removeWhere((b) => b.op == id);
    for (final b in list) {
      for (final child in _lists(b)) {
        _dropCalls(child, id);
      }
    }
  }

  @override
  String? definitionOf(String id) => _defScript(id)?.id;

  @override
  bool get canWrap => wrappable;

  List<LcBlock>? _tail(LcBlockTree tree, LcBlockPath from) {
    if (from.isEmpty) return null;
    final list = tree.listAt(from.sublist(0, from.length - 1), inElse: from.last.inElse, arm: from.last.arm);
    return list == null || from.last.index >= list.length ? null : list.sublist(from.last.index);
  }

  @override
  List<String> outerNames(LcBlockTree tree, LcBlockPath from) {
    final names = <String>[];
    _eachBlock(
      _tail(tree, from) ?? const [],
      (b) => _rewriteBlock(b, (e) {
        if (e['e'] == 'var' && !names.contains(e['name'])) names.add('${e['name']}');
        return e;
      }),
    );
    return names;
  }

  @override
  String? wrap(LcBlockTree tree, LcBlockPath from, CustomBlockLook look, List<String> params) {
    final tail = _tail(tree, from);
    final list = from.isEmpty ? null : tree.listAt(from.sublist(0, from.length - 1), inElse: from.last.inElse, arm: from.last.arm);
    if (tail == null || list == null) return null;
    final id = create(look.copyWith(shape: CustomBlockShape.statement), params);
    final def = id == null ? null : _defScript(id);
    if (id == null || def == null) return null;
    list.removeRange(from.last.index, list.length);
    def.body.addAll(tail);
    _eachBlock(def.body, (b) => _rewriteBlock(b, (e) => e['e'] == 'var' && params.contains(e['name']) ? fxParam('${e['name']}') : e));
    list.add(LcBlock(op: id, args: {for (final p in params) p: fxVar(p)}));
    return id;
  }

  @override
  List<BlockLookProblem> check(CustomBlockLook look, List<String> params, {String? editing}) => [
    if (fakeBlockSpecs.values.any((s) => s.label == look.name.trim())) BlockLookProblem(BlockLookField.name, '“${look.name.trim()}”是内置积木的名字，换一个'),
  ];

  // —— 校验：读了一个这里没有的参数 ——

  @override
  List<BlockIssue> get issues {
    final out = [...super.issues];
    for (final s in fakeScripts) {
      final known = {for (final p in paramsOf(s)) p.name, ..._lambdaParams(s)};
      s.visitBlocks((b, path) {
        _rewriteBlock(b, (e) {
          if (e['e'] == 'param' && !known.contains(e['name'])) out.add(BlockIssue(message: '这里没有叫“${e['name']}”的参数', scriptId: s.id, path: path, rule: 'F03'));
          return e;
        });
      });
    }
    return out;
  }

  // —— 走一遍 ——

  /// 这块积木里所有能放语句的口（含槽里“带口的值”的口）。
  List<List<LcBlock>> _lists(LcBlock b) => [b.body, b.orElse, for (final a in b.arms) a.body, ...b.exprMouths];

  void _eachBlock(List<LcBlock> list, void Function(LcBlock b) f) {
    for (final b in list) {
      f(b);
      for (final child in _lists(b)) {
        _eachBlock(child, f);
      }
    }
  }

  void _eachExpr(FakeScript s, void Function(Map<String, dynamic> e) f) => _eachBlock(
    s.body,
    (b) => _rewriteBlock(b, (e) {
      f(e);
      return e;
    }),
  );

  /// 把这块积木自己的参数（含各段的）里的每个值过一遍 `f`，返回什么就换成什么。不进口里的积木（它们由 [_eachBlock] 单独走）。
  void _rewriteBlock(LcBlock b, Object? Function(Map<String, dynamic> e) f) {
    for (final args in [b.args, for (final a in b.arms) a.args]) {
      for (final k in args.keys.toList()) {
        args[k] = _rewrite(args[k], f);
      }
    }
  }

  Object? _rewrite(Object? v, Object? Function(Map<String, dynamic> e) f) {
    if (v is List && v is! List<LcBlock>) {
      for (var i = 0; i < v.length; i++) {
        v[i] = _rewrite(v[i], f);
      }
      return v;
    }
    final e = asExpr(v);
    if (e == null) return v;
    for (final k in e.keys.toList()) {
      if (k != kLcExprBody) e[k] = _rewrite(e[k], f);
    }
    return f(e);
  }
}
