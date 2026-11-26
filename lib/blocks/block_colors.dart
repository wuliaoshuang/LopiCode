/// 积木的色表。宿主只说“哪一类”（[BlockColorKey]），具体颜色在这里，浅色深色各一套。
///
/// 自己定的颜色（没有照搬任何现成积木工具的配色）。每一类只定一个主色，其余几档（顶部亮一点、底边深一点、
/// 槽位更深一点）由主色算出来，保证同一块积木上的深浅关系一致。积木上的字是白色：主色都压在白字对比度 4.5:1 上下。
/// 深色主题用压暗、降一点饱和的主色——整屏是深底，原色会刺眼。
library;

import 'dart:ui';

import 'package:lopicode/blocks/block_host.dart';

const Color _white = Color(0xFFFFFFFF);
const Color _black = Color(0xFF000000);

/// 浅色主题的主色。
const Map<String, Color> _lightBase = {
  BlockColorKey.event: Color(0xFFB4500B), // 橙：事件（帽子）
  BlockColorKey.variable: Color(0xFFD03A6F), // 玫红：变量
  BlockColorKey.widget: Color(0xFF1B72C4), // 蓝：控件
  BlockColorKey.control: Color(0xFF6B4BD8), // 紫：流程
  BlockColorKey.action: Color(0xFF0B7C8E), // 青：交互
  BlockColorKey.network: Color(0xFF756C0E), // 橄榄：网络
  BlockColorKey.value: Color(0xFF5B677A), // 灰蓝：直接填的值
  BlockColorKey.operator: Color(0xFF287838), // 绿：运算
  BlockColorKey.data: Color(0xFFA63DBF), // 洋红：数据集合
  BlockColorKey.request: Color(0xFF0A7F5C), // 墨绿：请求
  BlockColorKey.response: Color(0xFFC53030), // 红：返回
  BlockColorKey.unknown: Color(0xFF636B73), // 灰：不认识的
  // 第 4 版语言核心（设计稿 9.1）。积木盒里挨着的两页色相至少差 40°：
  // 变量(玫红) → 运算(绿) → 流程(紫) → 函数 → 文字 → 列表 → 字典 → 类 → 出错 → 等待 → 我的积木。
  BlockColorKey.function: Color(0xFF0F7B6C), // 松石绿：函数
  BlockColorKey.text: Color(0xFF8A6A00), // 姜黄：文字
  BlockColorKey.list: Color(0xFF2468C8), // 钴蓝：列表
  BlockColorKey.dict: Color(0xFFA23BB8), // 紫红：字典
  BlockColorKey.classes: Color(0xFF5E7A12), // 草绿：类
  BlockColorKey.error: Color(0xFFC2362F), // 朱红：出错
  BlockColorKey.async: Color(0xFF0B7A94), // 湖蓝：等待
  BlockColorKey.custom: Color(0xFF4C56C8), // 靛蓝：我的积木
};

/// 一类积木在一种主题下的几档颜色。
class BkTone {
  const BkTone({required this.fill, required this.fillTop, required this.edge, required this.deep, required this.text, required this.fieldBg, required this.fieldText, required this.fieldHint});

  /// 主色（渐变的下端）和顶部稍亮的那一端。
  final Color fill;
  final Color fillTop;

  /// 底下那道深色边、描边。
  final Color edge;

  /// 槽位（下拉、空槽、开关）的底色：比主色深。
  final Color deep;

  /// 积木上的字。
  final Color text;

  /// 输入框：底色、字、提示字。
  final Color fieldBg;
  final Color fieldText;
  final Color fieldHint;

  /// 嵌在同色积木里时用的一套：整体提亮一点，不然两层糊在一起分不出来。
  BkTone get nested =>
      BkTone(fill: Color.lerp(fill, _white, 0.16)!, fillTop: Color.lerp(fillTop, _white, 0.16)!, edge: edge, deep: deep, text: text, fieldBg: fieldBg, fieldText: fieldText, fieldHint: fieldHint);
}

/// 一种主题下的整张色表。
class BkPalette {
  const BkPalette._(
    this.dark,
    this._tones, {
    required this.selection,
    required this.ghost,
    required this.shadow,
    required this.canvas,
    required this.canvasDot,
    required this.error,
    required this.warning,
    required this.hint,
  });

  final bool dark;
  final Map<String, BkTone> _tones;

  /// 选中积木的描边。
  final Color selection;

  /// 落点阴影（拖着积木靠近可拼位置时，那里出现的影子）。
  final Color ghost;

  /// 被拖起来的积木底下的阴影。
  final Color shadow;

  /// 画布底色和上面的点阵。
  final Color canvas;
  final Color canvasDot;

  /// 有问题的积木右上角的小圆点。
  final Color error;
  final Color warning;

  /// “提醒”级的标记（不是错也不是警告）：一种不抢眼的蓝灰。
  final Color hint;

  BkTone tone(String key) => _tones[key] ?? _tones[BlockColorKey.unknown]!;

  static final BkPalette light = BkPalette._(
    false,
    {for (final e in _lightBase.entries) e.key: _tone(e.value, dark: false)},
    selection: const Color(0xFFFFC53D),
    ghost: const Color(0x33000000),
    shadow: const Color(0x52000000),
    canvas: const Color(0xFFF3F4F6),
    canvasDot: const Color(0xFFD5D8DD),
    error: const Color(0xFFE03131),
    warning: const Color(0xFFF59F00),
    hint: const Color(0xFF4C6EF5),
  );

  static final BkPalette darkTheme = BkPalette._(
    true,
    {for (final e in _lightBase.entries) e.key: _tone(_dim(e.value), dark: true)},
    selection: const Color(0xFFFFD866),
    ghost: const Color(0x38FFFFFF),
    shadow: const Color(0x8A000000),
    canvas: const Color(0xFF15151B),
    canvasDot: const Color(0xFF2B2C34),
    error: const Color(0xFFFF6B6B),
    warning: const Color(0xFFFFC53D),
    hint: const Color(0xFF91A7FF),
  );

  static BkPalette of({required bool dark}) => dark ? darkTheme : light;
}

/// 深色主题：往黑里压一点，再往自己的灰度靠一点（降饱和）。
Color _dim(Color c) {
  final grey = c.computeLuminance();
  final g = (grey * 255).round().clamp(0, 255);
  final desat = Color.lerp(c, Color.fromARGB(255, g, g, g), 0.10)!;
  return Color.lerp(desat, _black, 0.10)!;
}

BkTone _tone(Color base, {required bool dark}) => BkTone(
  fill: base,
  fillTop: Color.lerp(base, _white, dark ? 0.07 : 0.10)!,
  edge: Color.lerp(base, _black, dark ? 0.38 : 0.30)!,
  deep: Color.lerp(base, _black, dark ? 0.26 : 0.20)!,
  text: dark ? const Color(0xFFF4F5F7) : _white,
  fieldBg: dark ? const Color(0xFFE4E6EB) : _white,
  fieldText: const Color(0xFF1F2128),
  fieldHint: const Color(0xFF7A808C),
);
