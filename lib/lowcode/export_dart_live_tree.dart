/// Flutter 导出“会动的那一路”的前半：占位值、主题变量表、每一档屏宽要生成的那棵树。
///
/// Flutter 的生成器（export_dart.dart）一直只读简写属性（底色、文字颜色、字号、内外边距、圆角、间距、宽高、对齐…）。
/// 这里在生成之前先做一步：按“这一档屏宽的最终样式”把样式里写的东西折回简写属性（只在一份副本上，不改文档）。
/// 值是主题变量、或者要到运行时才知道（绑定）的，先放一个**占位值**（一个文档里没出现过的数 / 颜色 / 文字），
/// 生成完再把占位值换成真正的那句 Dart（[DartLiveSubs.apply]）——这样生成器本身几乎不用动。
library;

import 'package:lopicode/lowcode/css_codec.dart';
import 'package:lopicode/lowcode/css_color.dart';
import 'package:lopicode/lowcode/grid_css.dart';
import 'package:lopicode/lowcode/inspector_bp_write.dart';
import 'package:lopicode/lowcode/inspector_write.dart';
import 'package:lopicode/lowcode/model.dart';
import 'package:lopicode/lowcode/style_resolve.dart';
import 'package:lopicode/lowcode/theme_vars.dart';

String dartLiveNum(num v) => v == v.roundToDouble() ? '${v.round()}' : '$v';
String dartLiveStr(String v) => "'${v.replaceAll('\\', r'\\').replaceAll("'", r"\'").replaceAll(r'$', r'\$').replaceAll('\r', '').replaceAll('\n', r'\n')}'";

/// 占位值的登记表（一次导出一份）。
class DartLiveSubs {
  DartLiveSubs(String docText) {
    final upper = docText.toUpperCase();
    _numBase = const [9173, 8291, 7459, 6387, 5923].firstWhere((b) => !docText.contains('$b'), orElse: () => 9173);
    var prefix = 'FD';
    for (var k = 0xFD; k > 0; k--) {
      final p = k.toRadixString(16).padLeft(2, '0').toUpperCase();
      if (!upper.contains('#$p')) {
        prefix = p;
        break;
      }
    }
    _colorPrefix = prefix;
    final busy = docText.contains('\uE000') || docText.contains('\uE001');
    _open = busy ? '\uF8F0' : '\uE000';
    _close = busy ? '\uF8F1' : '\uE001';
  }

  late final int _numBase;
  late final String _colorPrefix;
  late final String _open, _close;
  final List<String> _nums = [], _colors = [], _texts = [];

  int _slot(List<String> list, String code) {
    final at = list.indexOf(code);
    if (at >= 0) return at;
    list.add(code);
    return list.length - 1;
  }

  /// 一个数的占位值；[code] 是值为 double 的一句 Dart。
  int number(String code) => _numBase * 100000 + _slot(_nums, code);

  /// 一个颜色的占位值（`#RRGGBB`）；[code] 是值为 Color 的一句 Dart。
  String color(String code) => '#$_colorPrefix${_slot(_colors, code).toRadixString(16).padLeft(4, '0').toUpperCase()}';

  /// 一段文字的占位值；[code] 是值为 String 的一句 Dart。
  String text(String code) => '$_open${_slot(_texts, code)}$_close';

  /// [v] 要是占位的数，返回它代表的那句 Dart；不是返回 null。
  String? numberCode(Object? v) {
    if (v is! int) return null;
    final k = v - _numBase * 100000;
    return k >= 0 && k < _nums.length ? _nums[k] : null;
  }

  String? colorCode(Object? v) {
    if (v is! String || v.length != 7 || !v.startsWith('#$_colorPrefix')) return null;
    final k = int.tryParse(v.substring(3), radix: 16);
    return k != null && k < _colors.length ? _colors[k] : null;
  }

  late final RegExp _numRe = RegExp('\\b$_numBase(\\d{5})\\b');
  late final RegExp _colorRe = RegExp('Color\\(0x([0-9A-F]{2})$_colorPrefix([0-9A-F]{4})\\)');
  late final RegExp _textRe = RegExp('$_open(\\d+)$_close');
  static final RegExp _const = RegExp(r'\bconst ');

  String _plain(String s) => s
      .replaceAll(_const, '')
      .replaceAllMapped(_colorRe, (m) {
        final k = int.parse(m[2]!, radix: 16);
        if (k >= _colors.length) return m[0]!;
        return m[1] == 'FF' ? _colors[k] : '_lcAlpha(${_colors[k]}, 0x${m[1]})';
      })
      .replaceAllMapped(_numRe, (m) {
        final k = int.parse(m[1]!);
        return k < _nums.length ? _nums[k] : m[0]!;
      });

  String _string(String content) {
    final ms = _textRe.allMatches(content).where((m) => int.parse(m[1]!) < _texts.length).toList();
    if (ms.isEmpty) return "'$content'";
    if (ms.length == 1 && ms.single.start == 0 && ms.single.end == content.length) return _texts[int.parse(ms.single[1]!)];
    final out = StringBuffer("'");
    var at = 0;
    for (final m in ms) {
      out
        ..write(content.substring(at, m.start))
        ..write('\${${_texts[int.parse(m[1]!)]}}');
      at = m.end;
    }
    out
      ..write(content.substring(at))
      ..write("'");
    return '$out';
  }

  /// 把生成好的代码里的占位值换成真正的 Dart，并去掉 `const`（值到运行时才有，不能再是常量）。
  /// 字符串里的字、注释里的字不动。
  String apply(String code) {
    final out = StringBuffer(), plain = StringBuffer();
    void flush() {
      out.write(_plain('$plain'));
      plain.clear();
    }

    var i = 0;
    while (i < code.length) {
      final ch = code[i];
      if (ch == "'") {
        var j = i + 1;
        while (j < code.length && code[j] != "'") {
          j += code[j] == r'\' ? 2 : 1;
        }
        flush();
        out.write(_string(code.substring(i + 1, j.clamp(0, code.length))));
        i = j + 1;
      } else if (ch == '/' && i + 1 < code.length && code[i + 1] == '/') {
        final end = code.indexOf('\n', i);
        flush();
        out.write(code.substring(i, end < 0 ? code.length : end));
        i = end < 0 ? code.length : end;
      } else {
        plain.write(ch);
        i++;
      }
    }
    flush();
    return '$out';
  }
}

/// 主题变量在导出的代码里叫什么、是什么。
class DartLiveVars {
  DartLiveVars(this.values) {
    final used = <String>{};
    for (final name in values.keys) {
      final value = lcSubstVars(values[name]!, values).trim();
      final parts = name.split('-').where((p) => p.isNotEmpty).toList();
      var ident = parts.isEmpty ? 'v' : parts.first + [for (final p in parts.skip(1)) p[0].toUpperCase() + p.substring(1)].join();
      if (!RegExp(r'^[a-z][A-Za-z0-9]*$').hasMatch(ident)) ident = 'v${used.length}';
      for (var k = 2; !used.add(ident); k++) {
        ident = '${ident.replaceFirst(RegExp(r'\d+$'), '')}$k';
      }
      final px = dartLivePx(value);
      final argb = px == null ? cssColorToArgb(value) : null;
      if (px != null) {
        _fields[name] = (ident, 'double', dartLiveNum(px));
      } else if (argb != null) {
        _fields[name] = (ident, 'Color', dartLiveColor(argb));
      } else {
        other[name] = value;
      }
    }
  }

  final Map<String, String> values;
  final Map<String, (String, String, String)> _fields = {};

  /// 认不出来的变量（不是长度也不是颜色）：名字 → 值。
  final Map<String, String> other = {};

  bool get isEmpty => _fields.isEmpty && other.isEmpty;

  /// 这个变量是数（长度）时，指到它的那句 Dart；不是返回 null。
  String? numberRef(String? name) => _fields[name]?.$2 == 'double' ? 'LcVars.${_fields[name]!.$1}' : null;

  String? colorRef(String? name) => _fields[name]?.$2 == 'Color' ? 'LcVars.${_fields[name]!.$1}' : null;

  /// 导出文件里集中放变量的那个类。
  String classCode(Map<String, String> labels) {
    final lines = [for (final e in _fields.entries) '  /// ${labels[e.key] ?? kLcStarterLabels[e.key] ?? e.key}（--${e.key}）\n  static const ${e.value.$2} ${e.value.$1} = ${e.value.$3};\n'];
    final skipped = [for (final e in other.entries) '  // --${e.key}: ${e.value.replaceAll(RegExp(r'[\r\n]'), ' ')}（不是长度也不是颜色，Flutter 这边用不上）\n'];
    return '''

/// 主题变量：全应用只此一处。改这里的值，用到它的地方都跟着变。
abstract final class LcVars {
${lines.join('\n')}${skipped.join()}}
''';
  }
}

final RegExp _px = RegExp(r'^(-?\d+(?:\.\d+)?)(px)?$');

/// `12px` / `0` → 12 / 0；别的写法返回 null。
num? dartLivePx(String? value) {
  final m = _px.firstMatch(value?.trim() ?? '');
  if (m == null || (m[2] == null && double.parse(m[1]!) != 0)) return null;
  final d = double.parse(m[1]!);
  return d == d.roundToDouble() ? d.round() : d;
}

String dartLiveColor(int argb) => 'Color(0x${argb.toRadixString(16).padLeft(8, '0').toUpperCase()})';

const List<String> _numProps = ['padding', 'margin', 'radius', 'gap', 'fontSize', 'height', 'width'];
const List<String> _colorProps = ['bg', 'color'];
const Map<String, String> _alignBack = {'flex-start': 'start', 'start': 'start', 'center': 'center', 'flex-end': 'end', 'end': 'end', 'stretch': 'stretch'};
const Map<String, String> _justifyBack = {'flex-start': 'start', 'start': 'start', 'center': 'center', 'flex-end': 'end', 'end': 'end', 'space-between': 'between'};
const Set<String> _textAligns = {'left', 'right', 'center', 'justify', 'start', 'end'};
const Set<String> _flexTypes = {'container', 'column', 'row'};

LcNode dartLiveCopy(LcNode n, {String? type, Map<String, dynamic>? props, List<LcNode>? children, Map<String, String>? style}) => LcNode(
  id: n.id,
  type: type ?? n.type,
  props: props ?? n.props,
  children: children ?? n.children,
  style: style ?? n.style,
  bind: n.bind,
  name: n.name,
  locked: n.locked,
  hidden: n.hidden,
  keptProps: n.keptProps,
  more: n.more,
  raw: n.raw,
)..instSlots = n.instSlots;

/// 一档屏宽要生成的树。
class DartLiveTier {
  DartLiveTier(this.bp, this.vars, this.subs, this.notes);

  /// null＝手机。
  final String? bp;
  final DartLiveVars vars;
  final DartLiveSubs subs;

  /// 导不出来的东西，一条一句（写进文件头）。
  final Set<String> notes;

  /// [root] 在这一档的样子（样式折回简写属性；这一档 `display: none` 的整块不出）。
  LcNode tree(LcNode root) => _walk(root, null) ?? root;

  LcNode? _walk(LcNode n, LcNode? parent) {
    final self = _fold(n, parent);
    if (self == null) return null;
    final kids = <LcNode>[];
    var same = identical(self, n);
    for (final c in n.children) {
      final k = _walk(c, self);
      if (k != null) kids.add(k);
      same = same && identical(k, c);
    }
    return same ? n : dartLiveCopy(self, children: kids);
  }

  LcNode? _fold(LcNode n, LcNode? parent) {
    if (n.isUnknown || n.type == 'component' || n.type == 'slot' || n.type == 'spacer') return n;
    final seen = bp == null ? n : lcSeenAtBp(n, bp!);
    if (seen.style.isEmpty) return n;
    final own = canonicalDeclarations(seen.style);
    if (own['display']?.trim() == 'none' && n.type != 'page') return null;
    final r = resolvedStyle(seen, parent);
    final props = <String, dynamic>{...n.props};
    String? one(List<String> names) {
      final vs = {for (final name in names) r[name]};
      if (vs.length == 1) return vs.first;
      notes.add('四边不一样的内外边距、圆角，横竖不一样的间距（Flutter 这边的生成器一直只认“四边一样”的写法；写了不一样的那个组件按简写属性里的值出）。');
      return null;
    }

    for (final prop in _numProps) {
      final names = prop == 'width' ? const ['width'] : legacyPropCssNames(prop);
      if (!names.any(own.containsKey)) continue;
      // 网格的列间距、行间距分开用（export_dart_live_bind.dart），不折成一个“间距”。
      if (prop == 'gap' && lcIsGrid(own)) continue;
      final raw = one(names)?.trim();
      if (raw == null) continue;
      final ref = vars.numberRef(lcVarNameIn(raw));
      final px = dartLivePx(lcSubstVars(raw, vars.values));
      if (ref != null) {
        props[prop] = subs.number(ref);
      } else if (px != null) {
        props[prop] = px;
      } else if (prop == 'width' && raw == '100%') {
        props[prop] = 'fill';
      }
    }
    for (final prop in _colorProps) {
      final name = legacyPropCssNames(prop).single;
      final raw = own.containsKey(name) ? r[name]?.trim() : null;
      if (raw == null) continue;
      final ref = vars.colorRef(lcVarNameIn(raw));
      final argb = cssColorToArgb(lcSubstVars(raw, vars.values));
      if (ref != null) {
        props[prop] = subs.color(ref);
      } else if (argb != null) {
        props[prop] = argb >>> 24 == 0xFF ? '#${(argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}' : subs.color(dartLiveColor(argb));
      }
    }
    if (own.containsKey('font-weight')) {
      final w = r['font-weight']?.trim();
      final heavy = (int.tryParse(w ?? '') ?? (w == 'bold' || w == 'bolder' ? 700 : 400)) >= 600;
      heavy ? props['bold'] = true : props.remove('bold');
    }
    if (own.containsKey('text-align') && _textAligns.contains(r['text-align']?.trim())) props['textAlign'] = r['text-align']!.trim();
    var type = n.type;
    if (n.isContainer) {
      final a = _alignBack[r['align-items']?.trim()], j = _justifyBack[r['justify-content']?.trim()];
      if (own.containsKey('align-items') && a != null) props['align'] = a;
      if (own.containsKey('justify-content') && j != null) props['justify'] = j;
      final dir = own['flex-direction']?.trim();
      if (_flexTypes.contains(type) && dir != null) type = dir.startsWith('row') ? 'row' : 'column';
      // 换了方向：没设过对齐的，按原来那种容器的默认对齐（网页上换方向不会换对齐）。
      if ((type == 'row') != (n.type == 'row') && props['align'] == null) props['align'] = n.type == 'row' ? 'center' : 'start';
      // 网格里的格子由 Wrap 排：容器自己不能再当“一行”（一行里的子组件会包 Expanded）。
      if (lcIsGrid(own) && type == 'row') type = 'column';
    }
    return dartLiveCopy(n, type: type, props: props, style: own);
  }
}
