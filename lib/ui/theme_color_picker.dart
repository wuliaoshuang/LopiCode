// 设计约束（取色器的“芯”：饱和 × 明度方块 + 色相条 + 透明度条 + 十六进制输入 · 宽约 358）— 2026-11-26
// - 给取色面板（theme_color_sheet.dart）和快捷生成面板（theme_generate_sheet.dart）共用，一行只做一件事：
//   方块（高 132）→ 色相条 → 透明度条（允许透明时才有）→ 十六进制输入。
// - 手机上好拖：两根条的可拖区域高 36，按下就跟手（不用先拖出一段距离）；把手是双圈，深浅底上都看得见。
// - 颜色由外面拿着（[value]）；这里只记“色相”这一个外面给不出来的东西——颜色拖成灰 / 黑以后色相算不出来，
//   把手不能因此乱跳。外面把 [value] 换成别的颜色（点了色块、撤销）时这里跟着走。
// - 十六进制输入容错（parseLooseColor）；看不懂时在框下面用一句话说，不清空她打的字。
// - 不加依赖：都是自己画的；颜色都是算出来的或取自当前主题。
import 'dart:math' as math;

import 'package:lopicode/appearance/theme_color_math.dart';
import 'package:lopicode/appearance/theme_json.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:material_ui/material_ui.dart';

class ThemeColorPicker extends StatefulWidget {
  const ThemeColorPicker({super.key, required this.value, required this.onChanged, this.allowAlpha = false, this.empty = false, this.keyPrefix = 'color'});

  /// 现在的颜色（ARGB）。
  final int value;
  final ValueChanged<int> onChanged;
  final bool allowAlpha;

  /// 现在其实是“没有单独上色”（输入框空着、显示提示字）；一动就按 [value] 开始调。
  final bool empty;

  /// 里面几个控件的 key 的开头：`<prefix>-sv`、`-hue`、`-alpha`、`-hex`。
  final String keyPrefix;

  @override
  State<ThemeColorPicker> createState() => _ThemeColorPickerState();
}

class _ThemeColorPickerState extends State<ThemeColorPicker> {
  final TextEditingController _hex = TextEditingController();
  double _h = 0, _s = 0, _v = 0;
  int _alpha = 255;
  String? _hexError;

  int get _color => hsvToArgb(_h, _s, _v, alpha: _alpha);

  @override
  void initState() {
    super.initState();
    _load(widget.value);
    _hex.text = widget.empty ? '' : formatThemeColor(_color);
  }

  @override
  void didUpdateWidget(ThemeColorPicker old) {
    super.didUpdateWidget(old);
    final outside = widget.allowAlpha ? widget.value : withAlpha(widget.value, 255);
    if (outside != _color) {
      // 外面换了颜色（点色块、恢复默认、撤销）：跟过去，输入框也跟着写。
      _load(widget.value);
      _hex.text = widget.empty ? '' : formatThemeColor(_color);
      _hexError = null;
    } else if (widget.empty != old.empty && widget.empty) {
      _hex.text = '';
      _hexError = null;
    }
  }

  @override
  void dispose() {
    _hex.dispose();
    super.dispose();
  }

  void _load(int argb) {
    final hsv = argbToHsv(argb);
    // 灰的 / 纯黑的颜色算不出色相：留着原来的，免得色相条上的把手乱跳。
    if (hsv.s > 0 && hsv.v > 0) _h = hsv.h;
    _s = hsv.s;
    _v = hsv.v;
    _alpha = widget.allowAlpha ? alphaOf(argb) : 255;
  }

  void _emit({bool syncHex = true}) {
    setState(() {
      if (syncHex) {
        _hex.text = formatThemeColor(_color);
        _hexError = null;
      }
    });
    widget.onChanged(_color);
  }

  void _onHex(String text) {
    final c = parseLooseColor(text);
    if (c == null) {
      setState(() => _hexError = text.trim().isEmpty ? null : '看不懂这个颜色。写成 #RRGGBB${widget.allowAlpha ? ' 或 #AARRGGBB' : ''}，比如 #2962CB。');
      return;
    }
    _hexError = !widget.allowAlpha && alphaOf(c) != 255 ? '这一项不能带透明度，已经按不透明的用了。' : null;
    _load(c);
    _emit(syncHex: false);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final p = widget.keyPrefix;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _DragArea(
          key: Key('$p-sv'),
          height: 132,
          onDrag: (dx, dy) {
            _s = dx;
            _v = 1 - dy;
            _emit();
          },
          painter: _SvPainter(Color(hsvToArgb(_h, 1, 1)), Offset(_s, 1 - _v), c.surface, c.text),
        ),
        const SizedBox(height: Space.x2),
        _DragArea(
          key: Key('$p-hue'),
          height: 36,
          onDrag: (dx, _) {
            _h = dx * 360;
            // 灰色上拖色相看不出变化：给一点饱和和明度，让它真的变色。
            if (_s == 0) _s = 0.5;
            if (_v == 0) _v = 0.5;
            _emit();
          },
          painter: _BarPainter([for (var i = 0; i <= 6; i++) Color(hsvToArgb(i * 60.0, 1, 1))], _h / 360, c.surface, c.text),
        ),
        if (widget.allowAlpha) ...[
          const SizedBox(height: Space.x2),
          _DragArea(
            key: Key('$p-alpha'),
            height: 36,
            onDrag: (dx, _) {
              _alpha = (dx * 255).round();
              _emit();
            },
            painter: _BarPainter([Color(hsvToArgb(_h, _s, _v, alpha: 0)), Color(hsvToArgb(_h, _s, _v))], _alpha / 255, c.surface, c.text, checker: c.surfaceMuted),
          ),
        ],
        const SizedBox(height: Space.x3),
        TextField(
          key: Key('$p-hex'),
          controller: _hex,
          autocorrect: false,
          enableSuggestions: false,
          textCapitalization: TextCapitalization.characters,
          style: t.bodyMedium?.copyWith(fontFamily: kMonoFont, fontFamilyFallback: kMonoFallback),
          decoration: InputDecoration(
            isDense: true,
            labelText: widget.allowAlpha ? '十六进制（#RRGGBB 或 #AARRGGBB）' : '十六进制（#RRGGBB）',
            hintText: widget.empty ? '没有单独上色' : null,
            errorText: _hexError,
            errorMaxLines: 2,
          ),
          onChanged: _onHex,
          onSubmitted: (_) {
            if (!widget.empty) setState(() => _hex.text = formatThemeColor(_color));
          },
        ),
      ],
    );
  }
}

/// 小色块：半透明的颜色下面垫棋盘格；[argb] 是 null 画一个“没有颜色”的记号。
class ThemeSwatch extends StatelessWidget {
  const ThemeSwatch(this.argb, {super.key, this.size = 28});
  final int? argb;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Radii.sm),
        border: Border.all(color: c.border),
      ),
      child: argb == null ? Icon(Icons.format_color_reset_outlined, size: size * 0.6, color: c.textFaint) : CustomPaint(painter: _SwatchPainter(Color(argb!), c.surface, c.surfaceMuted)),
    );
  }
}

/// 一组可以点的色块（带小标题）。
class ThemeSwatchRow extends StatelessWidget {
  const ThemeSwatchRow({super.key, required this.title, required this.colors, required this.keyPrefix, required this.onPick});
  final String title;
  final List<int> colors;
  final String keyPrefix;
  final ValueChanged<int> onPick;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: Space.x3, bottom: Space.x2),
          child: Text(title, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: c.textFaint)),
        ),
        Wrap(
          spacing: Space.x2,
          runSpacing: Space.x2,
          children: [
            for (final (i, argb) in colors.indexed)
              Semantics(
                button: true,
                label: formatThemeColor(argb),
                child: InkWell(key: Key('$keyPrefix-$i'), onTap: () => onPick(argb), borderRadius: BorderRadius.circular(Radii.sm), child: ThemeSwatch(argb, size: 36)),
              ),
          ],
        ),
      ],
    );
  }
}

/// 一块按下就跟手的拖动区：把手指位置换成 0–1 的横纵比例。
class _DragArea extends StatelessWidget {
  const _DragArea({super.key, required this.height, required this.onDrag, required this.painter});
  final double height;
  final void Function(double dx, double dy) onDrag;
  final CustomPainter painter;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      void at(Offset p) => onDrag((p.dx / box.maxWidth).clamp(0.0, 1.0), (p.dy / height).clamp(0.0, 1.0));
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanDown: (d) => at(d.localPosition),
        onPanUpdate: (d) => at(d.localPosition),
        child: CustomPaint(size: Size(box.maxWidth, height), painter: painter),
      );
    },
  );
}

void _thumb(Canvas canvas, Offset at, Color ring, Color outline) {
  canvas
    ..drawCircle(at, 9, Paint()..color = outline)
    ..drawCircle(at, 8, Paint()..color = ring)
    ..drawCircle(at, 5, Paint()..color = outline);
}

void _checker(Canvas canvas, Rect rect, Color a, Color b) {
  const cell = 6.0;
  canvas.drawRect(rect, Paint()..color = a);
  final paint = Paint()..color = b;
  for (var y = 0; rect.top + y * cell < rect.bottom; y++) {
    for (var x = y.isEven ? 0 : 1; rect.left + x * cell < rect.right; x += 2) {
      canvas.drawRect(Rect.fromLTWH(rect.left + x * cell, rect.top + y * cell, cell, cell).intersect(rect), paint);
    }
  }
}

/// 饱和（横）× 明度（纵）的方块。
class _SvPainter extends CustomPainter {
  _SvPainter(this.hue, this.at, this.ring, this.outline);
  final Color hue;
  final Offset at;
  final Color ring;
  final Color outline;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final r = RRect.fromRectAndRadius(rect, const Radius.circular(Radii.md));
    final white = Color(hsvToArgb(0, 0, 1)), black = Color(hsvToArgb(0, 0, 0));
    canvas
      ..save()
      ..clipRRect(r)
      ..drawRect(rect, Paint()..shader = LinearGradient(colors: [white, hue]).createShader(rect))
      ..drawRect(rect, Paint()..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [black.withValues(alpha: 0), black]).createShader(rect))
      ..restore();
    _thumb(canvas, Offset(at.dx * size.width, at.dy * size.height), ring, outline);
  }

  @override
  bool shouldRepaint(_SvPainter old) => old.hue != hue || old.at != at || old.ring != ring;
}

/// 一根横条（色相 / 透明度）：渐变 + 把手。条本身 16 高，画在可拖区域的正中。
class _BarPainter extends CustomPainter {
  _BarPainter(this.colors, this.at, this.ring, this.outline, {this.checker});
  final List<Color> colors;
  final double at;
  final Color ring;
  final Color outline;

  /// 给了就先垫一层棋盘格（透明度条用）。
  final Color? checker;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, (size.height - 16) / 2, size.width, 16);
    canvas
      ..save()
      ..clipRRect(RRect.fromRectAndRadius(rect, const Radius.circular(8)));
    if (checker != null) _checker(canvas, rect, ring, checker!);
    canvas
      ..drawRect(rect, Paint()..shader = LinearGradient(colors: colors).createShader(rect))
      ..restore();
    _thumb(canvas, Offset(math.min(math.max(at * size.width, 9), size.width - 9), size.height / 2), ring, outline);
  }

  @override
  bool shouldRepaint(_BarPainter old) => old.at != at || old.colors.first != colors.first || old.colors.last != colors.last || old.ring != ring;
}

/// 小色块：半透明的颜色下面垫棋盘格。
class _SwatchPainter extends CustomPainter {
  _SwatchPainter(this.color, this.a, this.b);
  final Color color;
  final Color a;
  final Color b;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    if (color.a < 1) _checker(canvas, rect, a, b);
    canvas.drawRect(rect, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_SwatchPainter old) => old.color != color || old.a != a || old.b != b;
}
