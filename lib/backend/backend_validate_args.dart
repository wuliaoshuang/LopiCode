part of 'backend_validate.dart';

/// 一格一格地查参数和式子：从 backend_validate.dart 原样挪出来的，那边放不下了。
extension _ValidatorArgs on _Validator {
  /// 检查一个参数（积木的或表达式的）。`present`＝JSON 里有没有这个字段；`ownerKind`＝它属于哪种表达式（积木的参数为 null）。
  /// `xp`＝它在积木参数里的位置。
  void _arg(LcArgSpec a, Object? value, bool present, {required String? ownerKind, int depth = 0, List<Object> xp = const []}) {
    final was = _xp;
    _xp = xp;
    _argAt(a, value, present, ownerKind, depth, xp);
    _xp = was;
  }

  void _argAt(LcArgSpec a, Object? value, bool present, String? ownerKind, int depth, List<Object> xp) {
    final missing = !present || value == null;
    switch (a.kind) {
      case LcArgKind.expr:
        if (missing) {
          if (!a.optional) _error(LcIssueCode.missingArg, '“${a.label}”还没填', arg: a.name);
        } else if (!isExpr(value)) {
          _error(LcIssueCode.badArg, '“${a.label}”应该是一个值', arg: a.name);
        } else {
          _expr(value, a.name, depth, inObj: false);
        }
      case LcArgKind.exprList:
        if (missing) {
          _error(LcIssueCode.missingArg, '“${a.label}”还没填', arg: a.name);
        } else if (value is! List) {
          _error(LcIssueCode.badArg, '“${a.label}”应该是一串值', arg: a.name);
        } else {
          final inObj = ownerKind == 'obj' || (a.name == 'fields' && beIsCoreExpr(ownerKind));
          final keys = <String>{};
          for (var i = 0; i < value.length; i++) {
            final item = value[i];
            _xp = [...xp, i];
            if (!isExpr(item)) {
              _error(LcIssueCode.badArg, '“${a.label}”里有一项不是值', arg: a.name);
              continue;
            }
            if (inObj && exprKind(item) != 'pair') {
              _error(BeIssueCode.badPair, '“对象”里只能放“名字: 值”这样的字段', arg: a.name);
              continue;
            }
            _expr(item, a.name, depth, inObj: inObj);
            final key = exprString(item, 'key');
            if (inObj && key != null && key.isNotEmpty && !keys.add(key)) {
              _warn(BeIssueCode.badPair, '对象里有两个字段都叫 $key，后面的会盖掉前面的', arg: a.name);
            }
          }
        }
      case LcArgKind.variable:
        if (missing || value == '') {
          if (!a.optional) _error(LcIssueCode.missingArg, '还没选变量', arg: a.name);
        } else if (value is! String) {
          _error(LcIssueCode.badArg, '“${a.label}”应该是变量的名字', arg: a.name);
        } else if (_inFn && !_locals.containsKey(value)) {
          _error(LcIssueCode.unknownVar, doc.variable(value) == null ? '变量 $value 在这块积木里还没有新建' : '变量 $value 是接口里用的，自定义积木里看不见', arg: a.name, fix: '在这块积木里用“新建变量”，或者给它加一个参数、调用时把值传进来。');
        } else if (doc.variable(value) == null && !_locals.containsKey(value)) {
          _error(LcIssueCode.unknownVar, '变量 $value 还没有声明（先到“变量”里加一个）', arg: a.name);
        }
      case LcArgKind.collection:
        if (missing || value == '') {
          _error(LcIssueCode.missingArg, '还没选集合', arg: a.name);
        } else if (value is! String) {
          _error(LcIssueCode.badArg, '“${a.label}”应该是集合的名字', arg: a.name);
        } else if (doc.collection(value) == null) {
          _error(BeIssueCode.unknownCollection, '集合 $value 还没有（先到“数据集合”里加一个）', arg: a.name);
        }
      case LcArgKind.node:
        _error(LcIssueCode.badArg, '后端积木里没有“控件”', arg: a.name);
      case LcArgKind.choice:
        if (missing) {
          _error(LcIssueCode.missingArg, '“${a.label}”还没选', arg: a.name);
        } else if (value is! String || (!a.choices.contains(value) && !(a.choices.isEmpty && value.isNotEmpty && langRulesStrict(doc.rules)))) {
          _error(LcIssueCode.badArg, a.choices.isEmpty ? '“${a.label}”还没选' : '“${a.label}”只能是 ${a.choices.join(' / ')}', arg: a.name);
        }
      case LcArgKind.literalText:
        if (a.optional && (missing || value == '')) {
          // 可填可不填的名字（“对每一项”的序号、备注）空着不报。
        } else if (value is! String) {
          _error(missing ? LcIssueCode.missingArg : LcIssueCode.badArg, '“${a.label}”应该是一段文字', arg: a.name);
        } else if (value.isEmpty && ownerKind != 'text') {
          // 文字字面量可以是空的；名字、字段名空着多半是忘了填。
          _error(LcIssueCode.missingArg, '“${a.label}”还没填', arg: a.name);
        }
      case LcArgKind.literalNumber:
        if (value is! num || !value.isFinite) _error(missing ? LcIssueCode.missingArg : LcIssueCode.badArg, '“${a.label}”应该是一个数字', arg: a.name);
      case LcArgKind.literalBool:
        if (value is! bool) _error(missing ? LcIssueCode.missingArg : LcIssueCode.badArg, '“${a.label}”应该是“是”或“否”', arg: a.name);
    }
  }

  /// `arg` 是这个表达式最终属于积木的哪个参数（报问题时定位用）。`inObj`＝它是不是直接放在“对象”的字段里。
  void _expr(Object? expr, String arg, int depth, {required bool inObj}) {
    if (depth >= kMaxExprDepth) {
      _error(LcIssueCode.tooDeep, '值套得太深了（最多 $kMaxExprDepth 层）', arg: arg);
      return;
    }
    final kind = exprKind(expr);
    final spec = table.exprSpec(kind);
    if (spec == null && beCallId(kind) != null) {
      _error(BeFuncIssueCode.unknownFunction, '这里用的自定义积木，定义已经不在了；生成代码时会当成空的', arg: arg, fix: '长按这个值换成别的；想留着就到“我的积木”里重新做一块，再换上。');
      return;
    }
    if (spec == null && beLibOpOf(kind) != null) {
      _error(BeIssueCode.badLibrary, _libGone(kind!), arg: arg, fix: '到“积木库”里把这个库用上（或者重新导入）；不要了就长按这个值换成别的。');
      return;
    }
    if (kind == null || spec == null || expr is! Map) {
      _warn(LcIssueCode.unknownExpr, '不认识的值 ${kind ?? ''}，生成代码时会当成空的', arg: arg);
      return;
    }
    if (kind == kBeHostCall) {
      final why = beHostCallProblem(doc, expr['name']);
      if (why != null) _error(BeIssueCode.badLibrary, why, arg: arg, fix: '长按这个值换成别的；要碰宿主的事，等这条路放开以后再做。');
    }
    if (kind == kBeRawExpr) _raw(expr['src'], isExpr: true, arg: arg);
    if ((kind == kBeCast || kind == kBeAscribe) && beTypeOfKey(expr['to']) == null) {
      _error(LcIssueCode.unknownExpr, '还没选好类型（${expr['to'] ?? ''} 读不出来）', arg: arg, fix: '点这块积木上的类型，重新挑一个。');
    }
    final base = _xp;
    final noValue = beCallNoValueProblem(table, kind);
    if (noValue != null) _warn(BeFuncIssueCode.badReturn, noValue, arg: arg, fix: '在它的定义里加一块“返回 (值)”；或者把它单独当一句用。');
    if (kind == 'pair' && !inObj) {
      _error(BeIssueCode.badPair, '“一个字段”只能放在“对象”里', arg: arg);
    }
    for (final a in spec.args) {
      if (!expr.containsKey(a.name) && table.argFallsBack(kind, a.name)) continue;
      _arg(a, expr[a.name], expr.containsKey(a.name), ownerKind: kind, depth: depth + 1, xp: [...base, a.name]);
    }
    final bad = beFuncExprProblem(doc, kind, expr, _known);
    if (bad != null) _error(bad.$1, bad.$2, arg: arg, fix: bad.$3);
    if (kind == 'pathParam') {
      final name = expr['name'];
      if (name is String && name.isNotEmpty && !_params.contains(name)) {
        final have = _params.isEmpty ? '这个接口的路径里没有参数' : '路径里有的是 ${_params.join('、')}';
        _error(BeIssueCode.unknownPathParam, '路径里没有叫 $name 的参数（$have）；读到的会是空的', arg: arg);
      }
    }
  }

  /// “文字原样”：读不出来要说；里面直接调了宿主接口的，和“调宿主接口”积木一个规矩。
  void _raw(Object? src, {required bool isExpr, String? arg}) {
    if ((isExpr ? beRawReadExpr(src) : beRawReadStmt(src)) == null) {
      _error(LcIssueCode.badArg, '这一处的文字写法读不出来', arg: arg, fix: '删掉这一块，用积木重新搭。');
      return;
    }
    for (final n in beRawHosts(src, isExpr: isExpr)) {
      final why = beHostCallProblem(doc, n);
      if (why != null) {
        _error(BeIssueCode.badLibrary, why, arg: arg, fix: '删掉这一块，换成语言核心的积木来做；要碰宿主的事，等这条路放开以后再做。');
        return;
      }
    }
  }
}
