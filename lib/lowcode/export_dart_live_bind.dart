/// Flutter 导出“会动的那一路”的后半：状态、8 种绑定、状态样式、网格怎么写进生成的代码
/// （[DartLiveHook] 的实现；值式子翻成 Dart 的规矩和 bind_eval.dart / 导出的 JS 一样）。
library;

import 'package:lopicode/lowcode/bind_model.dart';
import 'package:lopicode/lowcode/box_off.dart';
import 'package:lopicode/lowcode/css_codec.dart';
import 'package:lopicode/lowcode/css_color.dart';
import 'package:lopicode/lowcode/export_dart.dart';
import 'package:lopicode/lowcode/export_dart_hook.dart';
import 'package:lopicode/lowcode/export_dart_live_events.dart';
import 'package:lopicode/lowcode/export_dart_live_tree.dart';
import 'package:lopicode/lowcode/grid_css.dart';
import 'package:lopicode/lowcode/inspector_write.dart';
import 'package:lopicode/lowcode/logic_expr.dart';
import 'package:lopicode/lowcode/logic_model.dart';
import 'package:lopicode/lowcode/model.dart';
import 'package:lopicode/lowcode/states.dart';
import 'package:lopicode/lowcode/states_bp.dart';
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

  /// 组件事件接的动作（export_dart_live_events.dart）；这一页没有就是 null。
  DartLiveEvents? events;

  /// 读一个状态的那句 Dart、它的声明（给 [events] 用）。
  String? stateRead(String name) => pageStates.containsKey(name) ? dartStateIdent(name) : (projectStates.containsKey(name) ? 'LcAppState.$name' : null);
  LcVariable? stateOf(String name) => _state(name);

  final DartLiveSubs subs;
  final DartLiveVars vars;
  final Set<String> notes;

  /// 这一页自己的状态、没被盖住的项目级状态。
  final Map<String, LcVariable> pageStates, projectStates;

  final List<Set<String>> _locals = [];

  /// 和 [_locals] 一层对一层：这一层“重复”带出的名字里，真被读到过的那几个。
  final List<Set<String>> _localsUsed = [];

  String? _resolve(String name) {
    for (var i = _locals.length - 1; i >= 0; i--) {
      if (_locals[i].contains(name)) {
        _localsUsed[i].add(name);
        return 'v_$name';
      }
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
    if (n.isUnknown || (!lcHasBindings(n) && _pressProps(n).isEmpty)) return n;
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
    // 类名开关：Flutter 里没有类名，按“条件成立时用另一组属性”接上（只认和样式绑定一样的那几条）。
    for (final c in lcClassIfOf(n)) {
      if (c.style.isEmpty) {
        notes.add('类名开关 ${c.name}（它还没配“成立时的样子”，Flutter 里没有“类名”这个东西，所以这条在 Flutter 里什么也不做；在编辑器里给它配上样子就会导出）。');
        continue;
      }
      final on = '_lcBool(${expr(c.when)})';
      for (final d in c.style.entries) {
        final prop = _styleBindProps[d.key];
        if (prop == null) {
          notes.add('类名开关 ${c.name} 的样子里的 ${d.key}（Flutter 这边只认底色、文字颜色、字号、内外边距、圆角、间距、宽、高这几条）。');
          continue;
        }
        final old = (props ?? n.props)[prop];
        final value = dartLiveStr(lcSubstVars(d.value, vars.values));
        if (prop == 'bg' || prop == 'color') {
          final fallback = subs.colorCode(old) ?? (old is String && cssColorToArgb(old) != null ? dartLiveColor(cssColorToArgb(old)!) : null);
          (props ??= {...n.props})[prop] = subs.color('_lcColor($on ? $value : null${fallback == null ? '' : ', $fallback'})');
        } else if (prop == 'width' || prop == 'height' || prop == 'fontSize') {
          // 字号和宽高一样：原来没写就是“用默认的”，条件不成立时不能落成 0（字会看不见）。
          final fallback = subs.numberCode(old) ?? (old is num ? dartLiveNum(old) : null);
          (props ??= {...n.props})[prop] = subs.number(fallback == null ? '_lcPxOrNull($on ? $value : null)' : '_lcPx($on ? $value : null, $fallback)');
        } else {
          final fallback = subs.numberCode(old) ?? (old is num ? dartLiveNum(old) : '0');
          (props ??= {...n.props})[prop] = subs.number('_lcPx($on ? $value : null, $fallback)');
        }
      }
    }
    // “按下”时的样子（按钮走它自己的口子，见 _withStates）：按着的时候换一组属性，外面包一层记“按没按着”的壳。
    for (final e in _pressProps(n).entries) {
      final old = (props ?? n.props)[e.key];
      if (e.key == 'bg' || e.key == 'color') {
        final fallback = subs.colorCode(old) ?? (old is String && cssColorToArgb(old) != null ? dartLiveColor(cssColorToArgb(old)!) : 'null');
        (props ??= {...n.props})[e.key] = subs.color('(lcDown ? ${e.value} : $fallback)');
      } else {
        final fallback = subs.numberCode(old) ?? (old is num ? dartLiveNum(old) : null);
        if (fallback == null && (e.key == 'width' || e.key == 'height' || e.key == 'fontSize')) {
          (props ??= {...n.props})[e.key] = subs.number('(lcDown ? ${e.value} : null)');
        } else {
          (props ??= {...n.props})[e.key] = subs.number('(lcDown ? ${e.value} : ${fallback ?? '0'})');
        }
      }
    }
    return props == null ? n : dartLiveCopy(n, props: props);
  }

  // —— 状态样式 ——

  /// 这个组件（不是按钮、输入框）“按下”时要换的属性 → 按着时的值（已经是 Dart 写法）。只认和样式绑定一样的那几条。
  final Map<String, Map<String, String>> _pressCache = {};
  static const Set<String> _pressTypes = {'container', 'row', 'column', 'card', 'text', 'image', 'icon', 'list', 'listItem'};

  Map<String, String> _pressProps(LcNode n) => _pressCache[n.id] ??= () {
    // 只管经 node() 画出来的这几种（那里才包得上壳）；按钮有自己的写法；顶栏、弹窗、输入类不在这条路上。
    if (!_pressTypes.contains(n.type)) return const <String, String>{};
    final pressed = canonicalDeclarations(lcStateStyle(n, 'pressed'));
    if (pressed.isEmpty) return const <String, String>{};
    final out = <String, String>{};
    final left = {...pressed};
    for (final prop in const ['bg', 'color', 'fontSize', 'padding', 'margin', 'radius', 'gap', 'width', 'height']) {
      final names = prop == 'width' ? const ['width'] : legacyPropCssNames(prop);
      final values = {for (final name in names) pressed[name]};
      if (values.length != 1 || values.single == null) continue; // 四个角 / 四条边不一样的：没有对得上的一个数
      final raw = values.single!;
      final String? code;
      if (prop == 'bg' || prop == 'color') {
        code = _colorOf(raw);
      } else {
        final m = RegExp(r'^(-?\d+(?:\.\d+)?)(px)?$').firstMatch(lcSubstVars(raw, vars.values).trim());
        code = m == null ? null : dartLiveNum(num.parse(m[1]!));
      }
      if (code == null) continue;
      out[prop] = code;
      names.forEach(left.remove);
    }
    if (left.isNotEmpty && out.isNotEmpty) {
      notes.add('“按下”时的样子里的 ${left.keys.join('、')}（Flutter 这边按下时只换底色、文字颜色、字号、内外边距、圆角、间距、宽、高这几条）。');
    }
    return out;
  }();

  /// 包一层记“按没按着”的壳（撑满用的 Expanded / Flexible 留在最外面）。
  String _pressWrap(LcNode n, String code, int indent) {
    // 这时候按下的值还是占位记号（最后才换成 lcDown 那句），所以只看有没有，不看代码里的字。
    if (_pressProps(n).isEmpty) return code;
    final m = RegExp(r'^(Expanded|Flexible)\(\n(\s*)child: ').firstMatch(code);
    final tail = ',\n${_ind(indent)})';
    if (m != null && code.endsWith(tail)) {
      return '${m[1]}(\n${m[2]}child: _LcPress(builder: (context, lcDown) => ${code.substring(m.end, code.length - tail.length)})$tail';
    }
    return '_LcPress(builder: (context, lcDown) => $code)';
  }

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
    if (lcHasBpStates(n)) notes.add('有些状态样式是分屏宽设的（平板 / 桌面上按下、禁用、聚焦时另一个样子）：Flutter 这边没有导出这一部分，各种屏宽上都用手机的那一份。');
    if (!lcHasStates(n)) return code;
    // 不是按钮的：按下时那几条已经在 _shown / _pressWrap 里接上了。
    final viaPress = _pressProps(n).isNotEmpty;
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
    if (viaPress && disabled.isEmpty && focused.isEmpty) handled = true;
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
    final list = rep == null ? '' : '_lcList(${expr(rep.list)})';
    if (rep != null) {
      if (rep.empty != null) empty = 'if ($list.isEmpty) Text(${dartLiveStr(rep.empty!)})';
      _locals.add({rep.index, rep.item});
      _localsUsed.add({});
    }
    try {
      final conds = wrap ? [?lcShowIfExpr(n), ?lcRenderIfExpr(n)] : const <Map<String, dynamic>>[];
      if (conds.isNotEmpty) prefix += 'if (${conds.map((c) => '_lcBool(${expr(c)})').join(' && ')}) ';
      final shown = _shown(n);
      final off = lcBindable(n.type, 'disabled') == null ? null : lcDataExpr(n, 'disabled');
      String make(LcNode x) {
        final code = dartLiveExtras(n, _withStates(n, core(x, parent, indent)), indent, notes);
        final tip = lcBoxCanOff(x) ? lcDataExpr(n, 'alt') : null;
        final boxed = dartBoxExtras(x, events?.attach(n, code, indent, off: lcBoxOff(x)) ?? code, indent, labelCode: tip == null ? null : '_lcText(${expr(tip)})');
        return _pressWrap(n, boxed, indent);
      }

      var widget = off == null
          ? make(shown)
          // 禁用绑了状态：禁用的、没禁用的各生成一份，运行时挑。
          : '(_lcBool(${expr(off)}) ? ${make(dartLiveCopy(shown, props: {...shown.props, 'disabled': true}))} : ${make(dartLiveCopy(shown, props: {...shown.props, 'disabled': false}))})';
      final g = _gridOf(parent);
      if (g != null) {
        final span = lcGridSpan(n.style).clamp(1, g.$1);
        widget = 'SizedBox(width: _lcCell(lcGridW, $span, ${g.$2}), child: $widget)';
      }
      if (rep != null) {
        // 序号、这一项没读到的不声明（不然导出的文件里有“写了没用上”的警告）。
        final used = _localsUsed.last;
        final item = used.contains(rep.item) ? 'v_${rep.item}' : '_';
        prefix = (used.contains(rep.index) ? 'for (final (v_${rep.index}, $item) in $list.indexed) ' : 'for (final $item in $list) ') + prefix;
      }
      return [?empty, '$prefix$widget'].join(',\n${_ind(indent)}');
    } finally {
      if (rep != null) {
        _locals.removeLast();
        _localsUsed.removeLast();
      }
    }
  }
}
