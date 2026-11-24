// 设计约束（取色面板；390×844，浅色 + 深色）
// - 从上到下：当前颜色（色块 + 十六进制输入）→ 常用色 → 最近用过 → 色相 / 饱和度 / 明度 / 不透明度四条滑块 → 底部一行操作。
// - 主操作只有一个：“用这个颜色”。“透明”“清除”是次要操作，放在它左边、不抢眼。
// - 点色块、拖滑块只是换“当前颜色”，不关面板；这样能先点个色块再调透明度。
// - 色块每个 40px；滑块的可拖区域 40px 高。
// - 不加依赖：滑块、棋盘格都是自己画的。
import 'package:flutter/services.dart';
import 'package:lopicode/lowcode/css_color.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:material_ui/material_ui.dart';

/// 取色的结果。[css] 为 null＝清除（删掉这一条样式）。面板被直接关掉时 [showStyleColorPicker] 返回 null（什么都不改）。
class StyleColorResult {
  const StyleColorResult(this.css);
  final String? css;
}

/// 常用色（给用户的页面用的颜色，不是本应用界面的配色）。
const List<int> kStyleSwatches = [
  0xFF000000, 0xFF50525B, 0xFF989EA4, 0xFFD8DCDF, 0xFFF3F4F6, 0xFFFFFFFF, 0xFFC6212F, 0xFFEE5986, //
  0xFFF08A24, 0xFFF7BC2E, 0xFF058654, 0xFF2BB673, 0xFF14A3B8, 0xFF2962CB, 0xFF5B4BD6, 0xFF8E44AD,
];

/// 最近用过的颜色：只在这次运行的内存里记，不存盘。最新的在前，最多 8 个。
final List<int> _recent = [];

void _remember(int argb) {
  _recent
    ..remove(argb)
    ..insert(0, argb);
  if (_recent.length > 8) _recent.removeLast();
}

/// 测试用：清掉“最近用过”。
@visibleForTesting
void debugClearRecentColors() => _recent.clear();

/// 十六进制颜色（#RGB / #RRGGBB / #RRGGBBAA，# 可省略）→ 0xAARRGGBB；别的写法返回 null。
int? parseHexColor(String text) {
  final t = text.trim();
  final h = t.startsWith('#') ? t.substring(1) : t;
  if (!RegExp(r'^([0-9a-fA-F]{3}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$').hasMatch(h)) return null;
  return cssColorToArgb('#$h');
}

/// 打开取色面板。[initial] 是当前的颜色原文（可以是 `red`、`var(--c)` 这种）。
Future<StyleColorResult?> showStyleColorPicker(BuildContext context, {String? initial, String title = '选择颜色'}) => showModalBottomSheet<StyleColorResult>(
  context: context,
  isScrollControlled: true,
  builder: (_) => _ColorSheet(initial: initial, title: title),
);

class _ColorSheet extends StatefulWidget {
  const _ColorSheet({required this.initial, required this.title});
  final String? initial;
  final String title;

  @override
  State<_ColorSheet> createState() => _ColorSheetState();
}

class _ColorSheetState extends State<_ColorSheet> {
  // 用色相 / 饱和度 / 明度记当前颜色（不用 RGB）：拖到灰色时色相不会丢。
  double _h = 215, _s = 0.66, _l = 0.48, _a = 1;
  final TextEditingController _hex = TextEditingController();
  bool _hexBad = false;

  @override
  void initState() {
    super.initState();
    final argb = cssColorToArgb(widget.initial);
    if (argb != null) _setArgb(argb);
    _hex.text = argbToCss(_argb);
  }

  @override
  void dispose() {
    _hex.dispose();
    super.dispose();
  }

  int get _argb {
    final rgb = HSLColor.fromAHSL(1, _h, _s, _l).toColor().toARGB32() & 0xFFFFFF;
    return ((_a * 255).round() << 24) | rgb;
  }

  void _setArgb(int argb) {
    final hsl = HSLColor.fromColor(Color(argb | 0xFF000000));
    // 灰色没有色相：保留之前的，免得滑块跳回红色。
    if (hsl.saturation > 0) _h = hsl.hue;
    _s = hsl.saturation;
    _l = hsl.lightness;
    _a = ((argb >> 24) & 0xFF) / 255;
  }

  /// 滑块、色块改了颜色：把十六进制框同步过去。
  void _pick(VoidCallback change) => setState(() {
    change();
    _hex.text = argbToCss(_argb);
    _hexBad = false;
  });

  void _onHex(String text) {
    final argb = parseHexColor(text);
    setState(() {
      _hexBad = argb == null && text.trim().isNotEmpty;
      if (argb != null) _setArgb(argb);
    });
  }

  void _done() {
    final argb = _argb;
    _remember(argb);
    Navigator.pop(context, StyleColorResult(argbToCss(argb)));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final initial = widget.initial;
    final unreadable = initial != null && initial.trim().isNotEmpty && cssColorToArgb(initial) == null;
    Color hsl(double h, double s, double l) => HSLColor.fromAHSL(1, h, s, l).toColor();
    final solid = hsl(_h, _s, _l);
    OutlineInputBorder border(Color color, double w) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(Radii.md),
      borderSide: BorderSide(color: color, width: w),
    );

    Widget swatches(String id, List<int> colors) => Wrap(
      spacing: 5,
      runSpacing: Space.x1,
      children: [
        for (final argb in colors)
          InkWell(
            key: Key('lc-color-$id-${argbToCss(argb)}'),
            onTap: () => _pick(() => _setArgb(argb)),
            borderRadius: BorderRadius.circular(Radii.md),
            child: Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(Radii.md),
                border: Border.all(color: argb == _argb ? c.accentFill : Colors.transparent, width: 2),
              ),
              child: ColorDot(argb: argb, size: 28),
            ),
          ),
      ],
    );

    Widget slider(String id, String label, String value, double v, List<Color> colors, ValueChanged<double> onChanged, {bool checker = false}) => SizedBox(
      height: 44,
      child: Row(
        children: [
          SizedBox(width: 64, child: Text(label, style: t.bodyMedium)),
          Expanded(
            child: GradientSlider(key: Key('lc-color-slider-$id'), value: v, colors: colors, checker: checker, onChanged: onChanged),
          ),
          SizedBox(
            width: 48,
            child: Text(value, style: t.bodySmall, textAlign: TextAlign.right),
          ),
        ],
      ),
    );

    // 键盘的高度垫在滚动区外面：滚动区到键盘上沿为止，输入框才会被滚到看得见的地方。
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(Space.x4, 0, Space.x4, Space.x4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(widget.title, style: t.titleLarge),
              const SizedBox(height: Space.x3),
              Row(
                children: [
                  ColorDot(key: const Key('lc-color-preview'), argb: _argb, size: 44),
                  const SizedBox(width: Space.x3),
                  Expanded(
                    child: TextField(
                      key: const Key('lc-color-hex'),
                      controller: _hex,
                      autocorrect: false,
                      enableSuggestions: false,
                      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[#0-9a-fA-F]')), LengthLimitingTextInputFormatter(9)],
                      style: t.bodyLarge?.copyWith(fontFamily: kMonoFont, fontFamilyFallback: kMonoFallback, color: _hexBad ? c.danger : c.text),
                      decoration: InputDecoration(
                        hintText: '#RRGGBB',
                        helperText: _hexBad ? '写成 #RGB、#RRGGBB 或 #RRGGBBAA' : null,
                        helperStyle: t.bodySmall?.copyWith(color: c.danger),
                        enabledBorder: border(_hexBad ? c.danger : c.border, _hexBad ? 2 : 1),
                        focusedBorder: border(_hexBad ? c.danger : c.accentFill, 2),
                      ),
                      onChanged: _onHex,
                    ),
                  ),
                ],
              ),
              if (unreadable) ...[const SizedBox(height: Space.x2), Text('现在的值是 ${initial.trim()}，这里显示不了它；选一个新颜色会把它换掉。', style: t.bodySmall?.copyWith(color: c.textFaint))],
              const SizedBox(height: Space.x4),
              Text('常用', style: t.labelMedium),
              const SizedBox(height: Space.x1),
              swatches('swatch', kStyleSwatches),
              if (_recent.isNotEmpty) ...[const SizedBox(height: Space.x3), Text('最近用过', style: t.labelMedium), const SizedBox(height: Space.x1), swatches('recent', _recent)],
              const SizedBox(height: Space.x3),
              slider('h', '色相', '${_h.round()}°', _h / 360, [for (var i = 0; i <= 6; i++) hsl(i * 60.0 % 360, 1, 0.5)], (v) => _pick(() => _h = v * 360)),
              slider('s', '饱和度', '${(_s * 100).round()}%', _s, [hsl(_h, 0, _l), hsl(_h, 1, _l)], (v) => _pick(() => _s = v)),
              slider('l', '明度', '${(_l * 100).round()}%', _l, [const Color(0xFF000000), hsl(_h, _s, 0.5), const Color(0xFFFFFFFF)], (v) => _pick(() => _l = v)),
              slider('a', '不透明度', '${(_a * 100).round()}%', _a, [solid.withValues(alpha: 0), solid], (v) => _pick(() => _a = v), checker: true),
              const SizedBox(height: Space.x3),
              Row(
                children: [
                  TextButton(
                    key: const Key('lc-color-clear'),
                    onPressed: () => Navigator.pop(context, const StyleColorResult(null)),
                    style: TextButton.styleFrom(foregroundColor: c.textMuted),
                    child: const Text('清除'),
                  ),
                  TextButton(
                    key: const Key('lc-color-transparent'),
                    onPressed: () => Navigator.pop(context, const StyleColorResult('transparent')),
                    style: TextButton.styleFrom(foregroundColor: c.textMuted),
                    child: const Text('透明'),
                  ),
                  const Spacer(),
                  FilledButton(key: const Key('lc-color-ok'), onPressed: _hexBad ? null : _done, child: const Text('用这个颜色')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 一条带渐变底的滑块（0～1）。自己画：系统滑块的轨道画不了渐变，色相条没法看。
class GradientSlider extends StatelessWidget {
  const GradientSlider({super.key, required this.value, required this.colors, required this.onChanged, this.checker = false});
  final double value;
  final List<Color> colors;
  final ValueChanged<double> onChanged;

  /// 垫棋盘格（不透明度那一条）。
  final bool checker;

  static const double _thumb = 22;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return LayoutBuilder(
      builder: (context, box) {
        final span = box.maxWidth - _thumb;
        void at(double dx) => onChanged(((dx - _thumb / 2) / span).clamp(0.0, 1.0));
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => at(d.localPosition.dx),
          onHorizontalDragStart: (d) => at(d.localPosition.dx),
          onHorizontalDragUpdate: (d) => at(d.localPosition.dx),
          child: SizedBox(
            height: 40,
            child: Stack(
              alignment: Alignment.centerLeft,
              children: [
                Container(
                  height: 14,
                  margin: const EdgeInsets.symmetric(horizontal: _thumb / 2 - 7),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(7),
                    border: Border.all(color: c.border),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: CustomPaint(
                    painter: checker ? const CheckerPainter(Color(0xFFFFFFFF), Color(0xFFCFD2D6), 4) : null,
                    child: DecoratedBox(
                      decoration: BoxDecoration(gradient: LinearGradient(colors: colors)),
                      child: const SizedBox.expand(),
                    ),
                  ),
                ),
                Positioned(
                  left: value.clamp(0.0, 1.0) * span,
                  child: Container(
                    width: _thumb,
                    height: _thumb,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFFFFF),
                      shape: BoxShape.circle,
                      border: Border.all(color: c.textMuted, width: 2),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// 透明底的棋盘格：色块带透明度时垫在下面，才看得出“透”。
class CheckerPainter extends CustomPainter {
  const CheckerPainter(this.light, this.dark, [this.cell = 5]);
  final Color light;
  final Color dark;
  final double cell;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = light);
    final p = Paint()..color = dark;
    for (var y = 0; y * cell < size.height; y++) {
      for (var x = y.isEven ? 0 : 1; x * cell < size.width; x += 2) {
        canvas.drawRect(Rect.fromLTWH(x * cell, y * cell, cell, cell).intersect(Offset.zero & size), p);
      }
    }
  }

  @override
  bool shouldRepaint(CheckerPainter old) => old.light != light || old.dark != dark || old.cell != cell;
}

/// 一个色块：有透明度的垫棋盘格；[argb] 为 null（没设 / 认不出）画一道斜线。
class ColorDot extends StatelessWidget {
  const ColorDot({super.key, required this.argb, this.size = 22});
  final int? argb;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final v = argb;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Radii.sm),
        border: Border.all(color: c.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: v == null
          ? Icon(Icons.block, size: size * 0.6, color: c.textFaint)
          : CustomPaint(
              painter: (v >> 24) & 0xFF == 0xFF ? null : const CheckerPainter(Color(0xFFFFFFFF), Color(0xFFCFD2D6)),
              child: ColoredBox(color: Color(v)),
            ),
    );
  }
}
