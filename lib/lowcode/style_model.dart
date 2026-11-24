/// 带类型的样式读写：在 `Map<String, String>`（就是 `LcNode.style`）上面包一层，给可视化编辑面板用。
///
/// 面板要的是“上边距是 8 像素”“文字颜色是这个色”，表里存的是 `margin-top: 8px` 这样的文字；
/// 这一层负责两边互转。转不了的（`calc(…)`、`var(…)`、多层阴影）一律保留原文，绝不悄悄改掉或丢掉。
library;

import 'package:lopicode/lowcode/css_codec.dart';
import 'package:lopicode/lowcode/css_color.dart';
import 'package:lopicode/lowcode/css_scan.dart';
import 'package:lopicode/lowcode/model.dart';

String _num(double v) => v == v.roundToDouble() ? '${v.round()}' : '$v';

/// 一个长度：数值＋单位、`auto`、或者解析不了的原始文本。
class LcLength {
  /// 数值＋单位，单位必须是 [units] 里的一个。
  const LcLength(double this.value, this.unit) : raw = null;
  const LcLength.px(double this.value) : unit = 'px', raw = null;
  const LcLength.auto() : value = null, unit = '', raw = 'auto';

  /// 解析不了的写法（`calc(100% - 8px)`、`var(--gap)`、`12pt`…），原样留着。
  const LcLength.raw(String this.raw) : value = null, unit = '';

  static const List<String> units = ['px', '%', 'em', 'rem', 'vw', 'vh'];
  static final RegExp _pattern = RegExp(r'^([+-]?(?:\d+\.?\d*|\.\d+))(px|%|em|rem|vw|vh)$', caseSensitive: false);

  final double? value;
  final String unit;
  final String? raw;

  bool get isAuto => raw == 'auto';

  /// 是不是“数值＋单位”（面板能用数字框编辑的那种）。
  bool get isNumeric => value != null;

  /// 空 / null → null（＝没设）。`0` 当成 `0px`。其余认不出的进 [LcLength.raw]。
  static LcLength? parse(String? text) {
    final t = text?.trim() ?? '';
    if (t.isEmpty) return null;
    if (t.toLowerCase() == 'auto') return const LcLength.auto();
    final m = _pattern.firstMatch(t);
    if (m != null) return LcLength(double.parse(m[1]!), m[2]!.toLowerCase());
    final zero = double.tryParse(t);
    if (zero == 0) return const LcLength.px(0);
    return LcLength.raw(t);
  }

  String toCss() => value == null ? raw! : '${_num(value!)}$unit';

  @override
  bool operator ==(Object other) => other is LcLength && other.value == value && other.unit == unit && other.raw == raw;

  @override
  int get hashCode => Object.hash(value, unit, raw);

  @override
  String toString() => toCss();
}

/// 四边（或四角）的值。四边的顺序是 上 右 下 左，四角是 左上 右上 右下 左下。
class LcSides<T> {
  const LcSides(this.top, this.right, this.bottom, this.left);
  const LcSides.all(T? v) : top = v, right = v, bottom = v, left = v;

  final T? top;
  final T? right;
  final T? bottom;
  final T? left;

  List<T?> get values => [top, right, bottom, left];

  /// 四个是不是一样（面板据此决定显示一个输入框还是四个）。四个都没设也算一样。
  bool get isUniform => top == right && right == bottom && bottom == left;
  bool get isEmpty => values.every((v) => v == null);
}

/// 单层阴影。多层的、解析不了的不用这个类，直接读写原始文本。
class LcShadow {
  const LcShadow({this.x = const LcLength.px(0), this.y = const LcLength.px(0), this.blur = const LcLength.px(0), this.spread = const LcLength.px(0), this.color, this.inset = false});

  final LcLength x;
  final LcLength y;
  final LcLength blur;
  final LcLength spread;

  /// 颜色原文；null＝没写（浏览器用文字颜色）。
  final String? color;
  final bool inset;

  /// `[inset] x y [模糊 [扩散]] [颜色]`，inset 和颜色的位置任意。`none`、多层（最外层有逗号）、认不出的返回 null。
  static LcShadow? parse(String? text) {
    final t = text?.trim() ?? '';
    if (t.isEmpty || t.toLowerCase() == 'none' || splitTopLevel(t, ',').length != 1) return null;
    final lengths = <LcLength>[];
    String? color;
    var inset = false;
    for (final token in cssTokens(t)) {
      final len = LcLength.parse(token);
      if (token.toLowerCase() == 'inset' && !inset) {
        inset = true;
      } else if (len != null && len.isNumeric) {
        lengths.add(len);
      } else if (color == null && isCssColor(token)) {
        color = token;
      } else {
        return null;
      }
    }
    if (lengths.length < 2 || lengths.length > 4) return null;
    const zero = LcLength.px(0);
    return LcShadow(x: lengths[0], y: lengths[1], blur: lengths.length > 2 ? lengths[2] : zero, spread: lengths.length > 3 ? lengths[3] : zero, color: color, inset: inset);
  }

  String toCss() => [if (inset) 'inset', x.toCss(), y.toCss(), blur.toCss(), spread.toCss(), ?color].join(' ');

  @override
  bool operator ==(Object other) => other is LcShadow && other.x == x && other.y == y && other.blur == blur && other.spread == spread && other.color == color && other.inset == inset;

  @override
  int get hashCode => Object.hash(x, y, blur, spread, color, inset);
}

/// 属性的取值类型：决定面板用什么控件。
enum LcStyleKind { length, color, choice, number, text, shadow }

/// 面板上的分组，按这个顺序排。
enum LcStyleGroup {
  size('尺寸'),
  margin('外边距'),
  padding('内边距'),
  border('边框'),
  radius('圆角'),
  background('背景'),
  text('文字'),
  shadow('阴影'),
  opacity('不透明度'),
  layout('布局'),
  position('定位'),
  overflow('溢出');

  const LcStyleGroup(this.label);
  final String label;
}

/// 登记表里的一条：一个认识的 CSS 属性。
class LcStyleProp {
  const LcStyleProp(this.name, this.label, this.group, this.kind, [this.options = const []]);
  final String name;
  final String label;
  final LcStyleGroup group;
  final LcStyleKind kind;

  /// [LcStyleKind.choice] 的可选值；长度类属性这里放允许的关键字（现在只有 auto）以外的就是空表。
  final List<String> options;
}

const _len = LcStyleKind.length;
const _choice = LcStyleKind.choice;
const _borderStyleOptions = ['none', 'solid', 'dashed', 'dotted', 'double'];
const _sideLabels = {'top': '上', 'right': '右', 'bottom': '下', 'left': '左'};
const _cornerLabels = {'top-left': '左上', 'top-right': '右上', 'bottom-right': '右下', 'bottom-left': '左下'};

/// 认识的属性，按分组、按面板上的显示顺序排好。不在这里的条目就是“自定义 CSS”。
final List<LcStyleProp> lcStyleProps = List.unmodifiable([
  const LcStyleProp('width', '宽度', LcStyleGroup.size, _len),
  const LcStyleProp('height', '高度', LcStyleGroup.size, _len),
  const LcStyleProp('min-width', '最小宽度', LcStyleGroup.size, _len),
  const LcStyleProp('max-width', '最大宽度', LcStyleGroup.size, _len),
  const LcStyleProp('min-height', '最小高度', LcStyleGroup.size, _len),
  const LcStyleProp('max-height', '最大高度', LcStyleGroup.size, _len),
  for (final s in cssSides) LcStyleProp('margin-$s', '${_sideLabels[s]}外边距', LcStyleGroup.margin, _len),
  for (final s in cssSides) LcStyleProp('padding-$s', '${_sideLabels[s]}内边距', LcStyleGroup.padding, _len),
  for (final s in cssSides) ...[
    LcStyleProp('border-$s-width', '${_sideLabels[s]}边框宽度', LcStyleGroup.border, _len),
    LcStyleProp('border-$s-style', '${_sideLabels[s]}边框样式', LcStyleGroup.border, _choice, _borderStyleOptions),
    LcStyleProp('border-$s-color', '${_sideLabels[s]}边框颜色', LcStyleGroup.border, LcStyleKind.color),
  ],
  for (final c in cssCorners) LcStyleProp('border-$c-radius', '${_cornerLabels[c]}圆角', LcStyleGroup.radius, _len),
  const LcStyleProp('background-color', '背景色', LcStyleGroup.background, LcStyleKind.color),
  const LcStyleProp('color', '文字颜色', LcStyleGroup.text, LcStyleKind.color),
  const LcStyleProp('font-size', '字号', LcStyleGroup.text, _len),
  const LcStyleProp('font-weight', '粗细', LcStyleGroup.text, _choice, ['normal', 'bold', '100', '200', '300', '400', '500', '600', '700', '800', '900']),
  const LcStyleProp('line-height', '行高', LcStyleGroup.text, LcStyleKind.text),
  const LcStyleProp('text-align', '对齐', LcStyleGroup.text, _choice, ['left', 'center', 'right', 'justify']),
  const LcStyleProp('letter-spacing', '字间距', LcStyleGroup.text, _len),
  const LcStyleProp('text-decoration-line', '装饰线', LcStyleGroup.text, _choice, ['none', 'underline', 'line-through', 'overline']),
  const LcStyleProp('font-style', '斜体', LcStyleGroup.text, _choice, ['normal', 'italic']),
  const LcStyleProp('box-shadow', '阴影', LcStyleGroup.shadow, LcStyleKind.shadow),
  const LcStyleProp('opacity', '不透明度', LcStyleGroup.opacity, LcStyleKind.number),
  const LcStyleProp('display', '显示方式', LcStyleGroup.layout, _choice, ['flex', 'block', 'inline-block', 'inline', 'grid', 'none']),
  const LcStyleProp('flex-direction', '排列方向', LcStyleGroup.layout, _choice, ['row', 'column', 'row-reverse', 'column-reverse']),
  const LcStyleProp('flex-wrap', '换行', LcStyleGroup.layout, _choice, ['nowrap', 'wrap', 'wrap-reverse']),
  const LcStyleProp('justify-content', '主轴对齐', LcStyleGroup.layout, _choice, ['flex-start', 'center', 'flex-end', 'space-between', 'space-around', 'space-evenly']),
  const LcStyleProp('align-items', '交叉轴对齐', LcStyleGroup.layout, _choice, ['flex-start', 'center', 'flex-end', 'stretch', 'baseline']),
  const LcStyleProp('align-self', '自身对齐', LcStyleGroup.layout, _choice, ['auto', 'flex-start', 'center', 'flex-end', 'stretch', 'baseline']),
  const LcStyleProp('row-gap', '行间距', LcStyleGroup.layout, _len),
  const LcStyleProp('column-gap', '列间距', LcStyleGroup.layout, _len),
  const LcStyleProp('flex-grow', '放大系数', LcStyleGroup.layout, LcStyleKind.number),
  const LcStyleProp('flex-shrink', '缩小系数', LcStyleGroup.layout, LcStyleKind.number),
  const LcStyleProp('flex-basis', '基准尺寸', LcStyleGroup.layout, _len),
  const LcStyleProp('position', '定位方式', LcStyleGroup.position, _choice, ['static', 'relative', 'absolute', 'fixed', 'sticky']),
  for (final s in cssSides) LcStyleProp(s, '距${_sideLabels[s]}', LcStyleGroup.position, _len),
  const LcStyleProp('z-index', '层级', LcStyleGroup.position, LcStyleKind.number),
  const LcStyleProp('overflow-x', '横向溢出', LcStyleGroup.overflow, _choice, ['visible', 'hidden', 'scroll', 'auto']),
  const LcStyleProp('overflow-y', '纵向溢出', LcStyleGroup.overflow, _choice, ['visible', 'hidden', 'scroll', 'auto']),
]);

final Map<String, LcStyleProp> _propsByName = {for (final p in lcStyleProps) p.name: p};

/// 查登记表；不认识的返回 null。
LcStyleProp? lcStyleProp(String name) => _propsByName[name];

/// 某个分组里的属性，按显示顺序。
List<LcStyleProp> lcStylePropsIn(LcStyleGroup group) => [
  for (final p in lcStyleProps)
    if (p.group == group) p,
];

/// 一张样式表上的带类型读写。直接改传进来的那张表（通常就是 `node.style`），所以改完由调用方负责记撤销、存盘。
///
/// 写入都经过 [set]：值不合页面文件的规矩（带 `{ } ; < >`、换行，超过 500 字，属性名不是小写连字符）时不写并返回 false；
/// 写的是简写（`margin`、`border`…）会自动拆成单项，所以表一直是规范写法。
/// 带 `!important` 的值：带类型的读法（长度、数字、枚举、颜色数值）读不出来，要用 [get] 读原文。
class LcStyle {
  LcStyle(this.map);

  final Map<String, String> map;

  /// 原文；没设返回 null。
  String? get(String name) => map[name];

  /// 写原文。null 或空白＝删掉这一条（写的是简写就删掉它管的所有单项）。返回有没有写成。
  bool set(String name, String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) {
      map.remove(name);
      cssLonghands(name).forEach(map.remove);
      return true;
    }
    if (LcNode.cleanStyle({name: v}).isEmpty) return false;
    applyDeclaration(map, name, v);
    return true;
  }

  LcLength? length(String name) => LcLength.parse(map[name]);
  bool setLength(String name, LcLength? value) => set(name, value?.toCss());

  /// 不带单位的数字（opacity、z-index、flex-grow）；没设或不是数字返回 null。
  double? number(String name) {
    final v = double.tryParse(map[name]?.trim() ?? '');
    return v == null || v.isNaN || v.isInfinite ? null : v;
  }

  bool setNumber(String name, num? value) => set(name, value == null ? null : _num(value.toDouble()));

  /// 枚举值（转成小写）；没设、或者值不在登记的可选值里返回 null（这时用 [get] 看原文）。
  String? choice(String name) {
    final v = map[name]?.trim().toLowerCase();
    return v != null && (lcStyleProp(name)?.options.contains(v) ?? false) ? v : null;
  }

  /// 只收登记过的可选值；别的返回 false、什么都不改。null＝删掉。
  bool setChoice(String name, String? value) {
    if (value != null && !(lcStyleProp(name)?.options.contains(value) ?? false)) return false;
    return set(name, value);
  }

  /// 颜色原文（`#ff0000`、`red`、`rgb(…)`、`var(--c)` 都原样返回）。
  String? color(String name) => map[name];

  /// 颜色的 0xAARRGGBB 数值；没设或转不了返回 null。
  int? colorArgb(String name) => cssColorToArgb(map[name]);
  bool setColor(String name, String? value) => set(name, value);
  bool setColorArgb(String name, int? argb) => set(name, argb == null ? null : argbToCss(argb));

  /// 单层阴影；没设、`none`、多层或认不出时返回 null（原文还在，用 [get] 读）。
  LcShadow? get shadow => LcShadow.parse(map['box-shadow']);
  bool setShadow(LcShadow? value) => set('box-shadow', value?.toCss());

  /// 四边 / 四角的属性名。[group] 是简写名：margin、padding、inset、border-width、border-style、border-color、border-radius。
  /// 不是这几个的抛 [ArgumentError]（这是写错代码，不是坏数据）。
  static List<String> sideNames(String group) {
    final names = cssLonghands(group);
    if (names.length != 4) throw ArgumentError.value(group, 'group', '不是四边 / 四角的简写');
    return names;
  }

  /// 四边的原文。
  LcSides<String> sides(String group) {
    final n = sideNames(group);
    return LcSides(map[n[0]], map[n[1]], map[n[2]], map[n[3]]);
  }

  /// 四边一起写原文；哪一边是 null 就删哪一边。四边都写成才返回 true（有一边不合规矩时其他边照写）。
  bool setSides(String group, LcSides<String> value) {
    final n = sideNames(group);
    final v = value.values;
    var ok = true;
    for (var i = 0; i < 4; i++) {
      ok = set(n[i], v[i]) && ok;
    }
    return ok;
  }

  /// 四边的长度。
  LcSides<LcLength> lengthSides(String group) {
    final n = sideNames(group);
    return LcSides(length(n[0]), length(n[1]), length(n[2]), length(n[3]));
  }

  bool setLengthSides(String group, LcSides<LcLength> value) => setSides(group, LcSides(value.top?.toCss(), value.right?.toCss(), value.bottom?.toCss(), value.left?.toCss()));

  /// 四边设成同一个长度（null＝四边都删）。
  bool setAllSides(String group, LcLength? value) => setLengthSides(group, LcSides.all(value));

  /// 登记表里有的条目（面板上有对应控件的）。
  Map<String, String> get known => {
    for (final e in map.entries)
      if (_propsByName.containsKey(e.key)) e.key: e.value,
  };

  /// 不在登记表里的条目＝“自定义 CSS”，保持表里的顺序。
  Map<String, String> get custom => {
    for (final e in map.entries)
      if (!_propsByName.containsKey(e.key)) e.key: e.value,
  };

  /// 某个分组里有没有设过东西（面板据此给分组标题打点）。
  bool hasAny(LcStyleGroup group) => map.keys.any((k) => _propsByName[k]?.group == group);

  /// 整张表的 CSS 文本（合并简写后的写法），给“看 / 改 CSS”的文本框用。
  String toCss() => declarationsToCss(map);

  /// 用一段 CSS 文本整个换掉这张表；返回没收下的条目（见 [parseCss]）。
  List<String> replaceWithCss(String css) {
    final result = parseCss(css);
    map
      ..clear()
      ..addAll(result.declarations);
    return result.dropped;
  }
}
