/// 一份主题的数据。纯 Dart：颜色是 ARGB 整数（0xAARRGGBB），不依赖界面库。
///
/// 每份主题只声明一种明暗（[dark]）。数据按节分开，每节是一张“键 → 值”的表，键的目录在
/// `theme_fields.dart`。对象不可变：要改就 [copyWith] 造一份新的。
library;

import 'package:lopicode/appearance/theme_fields.dart';

/// 现在的主题文件格式版本。
const int kThemeFormatVersion = 1;

/// 一个高亮分类的样子：颜色（null＝跟代码文字一个色）、粗体、斜体。
class TokenStyle {
  const TokenStyle({this.color, this.bold = false, this.italic = false});
  final int? color;
  final bool bold;
  final bool italic;

  /// 什么都没设：这一类就按普通代码文字画。
  bool get isPlain => color == null && !bold && !italic;

  TokenStyle copyWith({int? Function()? color, bool? bold, bool? italic}) => TokenStyle(color: color == null ? this.color : color(), bold: bold ?? this.bold, italic: italic ?? this.italic);

  @override
  bool operator ==(Object other) => other is TokenStyle && other.color == color && other.bold == bold && other.italic == italic;

  @override
  int get hashCode => Object.hash(color, bold, italic);
}

class ThemeSpec {
  ThemeSpec({
    required this.id,
    required this.name,
    this.author,
    required this.dark,
    this.version = kThemeFormatVersion,
    this.builtin = false,
    required Map<String, int> ui,
    required Map<String, int> code,
    required Map<String, TokenStyle> tokens,
    required Map<String, int> terminal,
    required Map<String, int> blocks,
    required Map<String, int> lowcode,
    required Map<String, double> metrics,
  }) : ui = Map.unmodifiable(ui),
       code = Map.unmodifiable(code),
       tokens = Map.unmodifiable(tokens),
       terminal = Map.unmodifiable(terminal),
       blocks = Map.unmodifiable(blocks),
       lowcode = Map.unmodifiable(lowcode),
       metrics = Map.unmodifiable(metrics);

  /// 标识：只有小写字母、数字、连字符。内置的以 `default-` / `builtin-` 开头，用户的以 `u-` 开头。
  final String id;
  final String name;
  final String? author;

  /// 这份主题是深色的（否则是浅色的）。
  final bool dark;
  final int version;

  /// 内置主题：只读，不能改名、不能删，要改先“复制一份”。
  final bool builtin;

  /// 界面色（键见 [UiKey]）。
  final Map<String, int> ui;

  /// 代码区域的颜色（键见 [CodeKey]）。
  final Map<String, int> code;

  /// 代码高亮（键见 [kTokenFields]）。
  final Map<String, TokenStyle> tokens;

  /// 终端（键见 [kTerminalFields]）。
  final Map<String, int> terminal;

  /// 积木（分类主色 + [BlockKey]）。
  final Map<String, int> blocks;

  /// 低代码编辑器的界面色（键见 [LowcodeKey]）。
  final Map<String, int> lowcode;

  /// 形状与密度（键见 [MetricKey]）。
  final Map<String, double> metrics;

  /// 按节名取那一节的颜色表（'ui' / 'code' / 'terminal' / 'blocks' / 'lowcode'）。
  Map<String, int> section(String name) => switch (name) {
    'ui' => ui,
    'code' => code,
    'terminal' => terminal,
    'blocks' => blocks,
    'lowcode' => lowcode,
    _ => const {},
  };

  double metric(String key) => metrics[key] ?? kMetricFields.firstWhere((f) => f.key == key).fallback;

  ThemeSpec copyWith({
    String? id,
    String? name,
    String? Function()? author,
    bool? dark,
    bool? builtin,
    Map<String, int>? ui,
    Map<String, int>? code,
    Map<String, TokenStyle>? tokens,
    Map<String, int>? terminal,
    Map<String, int>? blocks,
    Map<String, int>? lowcode,
    Map<String, double>? metrics,
  }) => ThemeSpec(
    id: id ?? this.id,
    name: name ?? this.name,
    author: author == null ? this.author : author(),
    dark: dark ?? this.dark,
    version: version,
    builtin: builtin ?? this.builtin,
    ui: ui ?? this.ui,
    code: code ?? this.code,
    tokens: tokens ?? this.tokens,
    terminal: terminal ?? this.terminal,
    blocks: blocks ?? this.blocks,
    lowcode: lowcode ?? this.lowcode,
    metrics: metrics ?? this.metrics,
  );

  /// 只换某一节里的几个颜色，别的不动。节名不认识就原样返回。
  ThemeSpec withColors(String sectionName, Map<String, int> changes) {
    final next = {...section(sectionName), ...changes};
    return switch (sectionName) {
      'ui' => copyWith(ui: next),
      'code' => copyWith(code: next),
      'terminal' => copyWith(terminal: next),
      'blocks' => copyWith(blocks: next),
      'lowcode' => copyWith(lowcode: next),
      _ => this,
    };
  }

  ThemeSpec withToken(String key, TokenStyle style) => copyWith(tokens: {...tokens, key: style});

  ThemeSpec withMetric(String key, double value) => copyWith(metrics: {...metrics, key: value});

  /// 内容是不是一样（标识、名字、每一个值）。
  @override
  bool operator ==(Object other) =>
      other is ThemeSpec &&
      other.id == id &&
      other.name == name &&
      other.author == author &&
      other.dark == dark &&
      other.builtin == builtin &&
      _same(other.ui, ui) &&
      _same(other.code, code) &&
      _same(other.tokens, tokens) &&
      _same(other.terminal, terminal) &&
      _same(other.blocks, blocks) &&
      _same(other.lowcode, lowcode) &&
      _same(other.metrics, metrics);

  @override
  int get hashCode => Object.hash(id, name, dark, ui.length, Object.hashAll(ui.values));
}

bool _same<V>(Map<String, V> a, Map<String, V> b) {
  if (a.length != b.length) return false;
  for (final e in a.entries) {
    if (!b.containsKey(e.key) || b[e.key] != e.value) return false;
  }
  return true;
}
