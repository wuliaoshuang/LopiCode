/// Flutter 导出“会动的那一路”的后半：状态、8 种绑定、状态样式、网格怎么写进生成的代码
/// （[DartLiveHook] 的实现；值式子翻成 Dart 的规矩和 bind_eval.dart / 导出的 JS 一样）。
library;

import 'package:lopicode/lowcode/bind_model.dart';
import 'package:lopicode/lowcode/css_codec.dart';
import 'package:lopicode/lowcode/css_color.dart';
import 'package:lopicode/lowcode/export_dart_hook.dart';
import 'package:lopicode/lowcode/export_dart_live_tree.dart';
import 'package:lopicode/lowcode/grid_css.dart';
import 'package:lopicode/lowcode/logic_expr.dart';
import 'package:lopicode/lowcode/logic_model.dart';
import 'package:lopicode/lowcode/model.dart';
import 'package:lopicode/lowcode/states.dart';
import 'package:lopicode/lowcode/theme_vars.dart';

String _ind(int n) => '  ' * n;

/// 状态在导出的代码里叫什么。
String dartStateIdent(String name) => 's_$name';

/// 一个值（状态的初值）写成 Dart 字面量。
String dartLiveLiteral(Object? v, [int depth = 0]) {
  if (depth > 32) return 'null';
  return switch (v) {
    final String s => dartLiveStr(s),
    final num n => n.isFinite ? '$n' : '0',
    final bool b => '$b',
    final List<dynamic> l => '<Object?>[${[for (final x in l) dartLiveLiteral(x, depth + 1)].join(', ')}]',
    final Map<dynamic, dynamic> m => '<String, Object?>{${[for (final e in m.entries) '${dartLiveStr('${e.key}')}: ${dartLiveLiteral(e.value, depth + 1)}'].join(', ')}}',
    _ => 'null',
  };
}

/// 把一个值式子翻成一句 Dart（值的类型是 Object?）。[resolve]：一个名字怎么读，不认识返回 null。
String dartLiveExpr(Object? e, String? Function(String name) resolve, [int depth = 0]) {
  if (depth >= kMaxExprDepth) return 'null';
  String sub(String key) => dartLiveExpr(exprField(e, key), resolve, depth + 1);
  switch (exprKind(e)) {
    case 'text':
      return dartLiveStr(exprString(e, 'v') ?? '');
    case 'num':
      final v = exprNum(e, 'v');
      return v == null || !v.isFinite ? 'null' : (v < 0 ? '($v)' : '$v');
    case 'bool':
      return '${exprBool(e, 'v') ?? false}';
    case 'var':
      final name = exprString(e, 'name');
      final base = name == null ? null : resolve(name);
      if (base == null) return 'null';
      final path = lcPathOf(exprField(e, 'path'));
      return path.isEmpty ? base : '_lcAt($base, const [${path.map(dartLiveStr).join(', ')}])';
    case 'len':
      return '_lcLen(${sub('x')})';
    case 'not':
      return '!_lcBool(${sub('x')})';
    case 'join':
      final items = exprField(e, 'items');
      final parts = [
        if (items is List)
          for (final item in items) '_lcText(${dartLiveExpr(item, resolve, depth + 1)})',
      ];
      return parts.isEmpty ? "''" : (parts.length == 1 ? parts.single : '(${parts.join(' + ')})');
    case 'bin':
      final op = exprString(e, 'op');
      final l = sub('l'), r = sub('r');
      switch (op) {
        case '+' || '-' || '*':
          return '(_lcNum($l) $op _lcNum($r))';
        case '/':
          return '_lcDiv($l, $r)';
        case '%':
          return '_lcMod($l, $r)';
        case '<' || '<=' || '>' || '>=':
          return '(_lcNum($l) $op _lcNum($r))';
        case '==':
          return '_lcEq($l, $r)';
        case '!=':
          return '!_lcEq($l, $r)';
        case 'and':
          return '(_lcBool($l) && _lcBool($r))';
        case 'or':
          return '(_lcBool($l) || _lcBool($r))';
      }
  }
  return 'null';
}

const Map<String, String> _styleBindProps = {
  'background-color': 'bg',
  'background': 'bg',
  'color': 'color',
  'font-size': 'fontSize',
  'padding': 'padding',
  'margin': 'margin',
  'border-radius': 'radius',
  'gap': 'gap',
  'width': 'width',
  'height': 'height',
};

/// 生成一页（一档屏宽）时的接入点实现。
class DartLiveGen implements DartLiveHook {
  DartLiveGen({required this.subs, required this.vars, required this.notes, required this.pageStates, required this.projectStates});

  final DartLiveSubs subs;
  final DartLiveVars vars;
  final Set<String> notes;

  /// 这一页自己的状态、没被盖住的项目级状态。
  final Map<String, LcVariable> pageStates, projectStates;

  final List<Set<String>> _locals = [];

  String? _resolve(String name) {
    for (final scope in _locals.reversed) {
      if (scope.contains(name)) return 'v_$name';
    }
    if (pageStates.containsKey(name)) return dartStateIdent(name);
    if (projectStates.containsKey(name)) return 'LcAppState.$name';
    return null;
  }

  String expr(Object? e) => dartLiveExpr(e, _resolve);

  LcVariable? _state(String name) => pageStates[name] ?? projectStates[name];

  // —— 双向 ——

  String? _modelTarget(LcNode n) {
    final name = lcModelOf(n);
    return name != null && lcModelProp(n.type) != null && _state(name) != null ? name : null;
  }

  @override
  String? modelRead(LcNode n) {
    final name = _modelTarget(n);
    return name == null ? null : _resolve(name);
  }

  @override
  String modelWrite(LcNode n, String value) {
    final name = _modelTarget(n)!;
    final v = _state(name)!;
    // 派生的状态是算出来的，写不回去。
    if (v.isDerived) return 'null';
    final put = v.type == 'number' ? '_lcNum($value)' : value;
    return pageStates.containsKey(name) ? 'update(() => ${dartStateIdent(name)} = $put)' : 'LcAppState.update(() => LcAppState.$name = $put)';
  }

  @override
  List<String>? fieldArgs(LcNode n) {
    final read = modelRead(n);
    if (read == null) return null;
    final isNum = _state(_modelTarget(n)!)!.type == 'number';
    return ['controller: _lcField(${dartLiveStr(n.id)}, $read${isNum ? ', number: true' : ''})', 'onChanged: (value) => ${modelWrite(n, 'value')}'];
  }

  // —— 文字 / 属性 ——

  @override
  String? boundText(LcNode n, String prop) {
    final e = lcBindable(n.type, prop) == null ? null : lcDataExpr(n, prop);
    return e == null ? null : '_lcText(${expr(e)})';
  }

  @override
  String? boundList(LcNode n) {
    final e = lcBindable(n.type, 'items') == null ? null : lcDataExpr(n, 'items');
    return e == null ? null : '_lcList(${expr(e)})';
  }

  /// 绑了的文字属性、绑了的样式换成占位值。
  LcNode _shown(LcNode n) {
    if (n.isUnknown || !lcHasBindings(n)) return n;
    Map<String, dynamic>? props;
    for (final prop in lcBoundProps(n)) {
      final spec = lcBindable(n.type, prop);
      final e = lcDataExpr(n, prop);
      if (spec == null || e == null || spec.type != 'text' || prop == 'src') continue;
      (props ??= {...n.props})[prop] = subs.text('_lcText(${expr(e)})');
    }
    for (final b in lcStyleBinds(n).entries) {
      final prop = _styleBindProps[b.key];
      if (prop == null) {
        notes.add('样式绑定里的 ${b.key}（Flutter 这边只认底色、文字颜色、字号、内外边距、圆角、间距、宽、高这几条；别的 CSS 属性没有对得上的写法）。');
        continue;
      }
      final old = (props ?? n.props)[prop];
      if (prop == 'bg' || prop == 'color') {
        final fallback = subs.colorCode(old) ?? (old is String && cssColorToArgb(old) != null ? dartLiveColor(cssColorToArgb(old)!) : null);
        (props ??= {...n.props})[prop] = subs.color('_lcColor(${expr(b.value)}${fallback == null ? '' : ', $fallback'})');
      } else if (prop == 'width' || prop == 'height') {
        final fallback = subs.numberCode(old) ?? (old is num ? dartLiveNum(old) : null);
        (props ??= {...n.props})[prop] = subs.number(fallback == null ? '_lcPxOrNull(${expr(b.value)})' : '_lcPx(${expr(b.value)}, $fallback)');
      } else {
        final fallback = subs.numberCode(old) ?? (old is num ? dartLiveNum(old) : '0');
        (props ??= {...n.props})[prop] = subs.number('_lcPx(${expr(b.value)}, $fallback)');
      }
    }
    for (final c in lcClassIfOf(n)) {
      notes.add('类名开关 ${c.name}（Flutter 里没有“类名”这个东西，而且编辑器里现在也没有给类名配样子的地方；要它在 Flutter 里起作用，请改用“显示条件”或“样式绑定”）。');
    }
    return props == null ? n : dartLiveCopy(n, props: props);
  }

  // —— 状态样式 ——

  String? _colorOf(String? css) {
    if (css == null) return null;
    final ref = vars.colorRef(lcVarNameIn(css));
    if (ref != null) return ref;
    final argb = cssColorToArgb(lcSubstVars(css, vars.values));
    return argb == null ? null : dartLiveColor(argb);
  }

  static final RegExp _styleFrom = RegExp(r'style: FilledButton\.styleFrom\((.*)\),\n');
  static final RegExp _border = RegExp(r'( *)border: OutlineInputBorder\(borderRadius: (BorderRadius\.circular\([^\n]*\))\),\n');

  String _withStates(LcNode n, String code) {
    if (!lcHasStates(n)) return code;
    final pressed = canonicalDeclarations(lcStateStyle(n, 'pressed')), disabled = canonicalDeclarations(lcStateStyle(n, 'disabled')), focused = canonicalDeclarations(lcStateStyle(n, 'focused'));
    var handled = false;
    var out = code;
    if (n.type == 'button') {
      final m = _styleFrom.firstMatch(code);
      String? part(String css, String arg, String prop) {
        final p = _colorOf(pressed[css]), d = _colorOf(disabled[css]);
        if (p == null && d == null) return null;
        final base = subs.colorCode(n.props[prop]) ?? (n.strProp(prop) == null ? null : _colorOf(n.strProp(prop)));
        // 禁用时没设就交回默认（null）；按下时没设就是平时的颜色。
        return '$arg: WidgetStateProperty.resolveWith<Color?>((states) => states.contains(WidgetState.disabled) ? ${d ?? 'null'} : (states.contains(WidgetState.pressed) ? ${p ?? base ?? 'null'} : ${base ?? 'null'}))';
      }

      final parts = [?part('background-color', 'backgroundColor', 'bg'), ?part('color', 'foregroundColor', 'color')];
      if (m != null && parts.isNotEmpty) {
        out = code.replaceRange(m.start, m.end, 'style: FilledButton.styleFrom(${m[1]}).copyWith(${parts.join(', ')}),\n');
        handled = true;
      }
    } else if (n.type == 'input' || n.type == 'textarea') {
      final m = _border.firstMatch(code);
      final c = _colorOf(focused['border-top-color'] ?? focused['border-color']);
      if (m != null && c != null) {
        out = code.replaceRange(m.end, m.end, '${m[1]}focusedBorder: OutlineInputBorder(borderRadius: ${m[2]}, borderSide: BorderSide(color: $c, width: 2)),\n');
        handled = true;
      }
    }
    if (!handled) {
      notes.add('有些状态样式（Flutter 这边导出的是：按钮“按下 / 禁用”时的底色和文字颜色、输入框“聚焦”时的边框颜色。别的组件、别的属性在 Flutter 里没有现成的“某个状态下换样子”的口子，要给每个控件包一层自己记“按下没有”的壳，这一版没有做）。');
    }
    return out;
  }

  // —— 网格 ——

  (int, String, String)? _gridOf(LcNode? n) {
    if (n == null || !n.isContainer || n.style.isEmpty || !lcIsGrid(n.style)) return null;
    String gap(String name) {
      final raw = n.style[name]?.trim();
      final ref = vars.numberRef(lcVarNameIn(raw));
      final px = dartLivePx(raw == null ? null : lcSubstVars(raw, vars.values));
      final byProp = subs.numberCode(n.props['gap']) ?? (n.numProp('gap') == null ? null : dartLiveNum(n.numProp('gap')!));
      return ref ?? (px == null ? byProp ?? '0' : dartLiveNum(px));
    }

    return (lcGridColumns(n.style), gap('column-gap'), gap('row-gap'));
  }

  @override
  String? grid(LcNode n, int indent, String children) {
    final g = _gridOf(n);
    if (g == null) return null;
    final i = indent;
    // 各项本来按 i + 2 级缩进排好了，这里要再往里两级。
    final shifted = children.isEmpty ? '' : '${_ind(2)}${children.substring(0, children.length - 1).replaceAll('\n', '\n${_ind(2)}')}\n';
    return 'LayoutBuilder(\n'
        '${_ind(i + 1)}builder: (context, box) {\n'
        '${_ind(i + 2)}// 网格：${g.$1} 列等宽。lcGridW 是一格的宽度。\n'
        '${_ind(i + 2)}final lcGridW = ((box.maxWidth.isFinite ? box.maxWidth : MediaQuery.sizeOf(context).width) - ${g.$2} * ${g.$1 - 1}) / ${g.$1};\n'
        '${_ind(i + 2)}return Wrap(\n'
        '${_ind(i + 3)}spacing: ${g.$2},\n'
        '${_ind(i + 3)}runSpacing: ${g.$3},\n'
        '${_ind(i + 3)}children: [\n$shifted${_ind(i + 3)}],\n'
        '${_ind(i + 2)});\n'
        '${_ind(i + 1)}},\n'
        '${_ind(i)})';
  }

  // —— 一个节点 ——

  @override
  String bar(LcNode bar, String Function(LcNode shown) gen) {
    final code = gen(_shown(bar));
    final conds = [?lcShowIfExpr(bar), ?lcRenderIfExpr(bar)];
    return conds.isEmpty ? code : '${conds.map((c) => '_lcBool(${expr(c)})').join(' && ')} ? $code : null';
  }

  /// 弹窗本身（标题、正文绑了的换成占位值）。
  LcNode dialog(LcNode d) => _shown(d);

  @override
  String node(LcNode n, LcNode? parent, int indent, DartNodeFn core) {
    final wrap = lcCanWrapBind(n);
    final rep = wrap ? lcRepeatOf(n) : null;
    var prefix = '';
    String? empty;
    if (rep != null) {
      final list = '_lcList(${expr(rep.list)})';
      prefix = 'for (final (v_${rep.index}, v_${rep.item}) in $list.indexed) ';
      if (rep.empty != null) empty = 'if ($list.isEmpty) Text(${dartLiveStr(rep.empty!)})';
      _locals.add({rep.index, rep.item});
    }
    try {
      final conds = wrap ? [?lcShowIfExpr(n), ?lcRenderIfExpr(n)] : const <Map<String, dynamic>>[];
      if (conds.isNotEmpty) prefix += 'if (${conds.map((c) => '_lcBool(${expr(c)})').join(' && ')}) ';
      final shown = _shown(n);
      final off = lcBindable(n.type, 'disabled') == null ? null : lcDataExpr(n, 'disabled');
      String make(LcNode x) => _withStates(n, core(x, parent, indent));
      var widget = off == null
          ? make(shown)
          // 禁用绑了状态：禁用的、没禁用的各生成一份，运行时挑。
          : '(_lcBool(${expr(off)}) ? ${make(dartLiveCopy(shown, props: {...shown.props, 'disabled': true}))} : ${make(dartLiveCopy(shown, props: {...shown.props, 'disabled': false}))})';
      final g = _gridOf(parent);
      if (g != null) {
        final span = lcGridSpan(n.style).clamp(1, g.$1);
        widget = 'SizedBox(width: _lcCell(lcGridW, $span, ${g.$2}), child: $widget)';
      }
      return [?empty, '$prefix$widget'].join(',\n${_ind(indent)}');
    } finally {
      if (rep != null) _locals.removeLast();
    }
  }
}
