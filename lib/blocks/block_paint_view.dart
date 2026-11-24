// 设计约束（积木怎么画）— 2026-11-24
// - 只管“把排好版的积木画出来”：位置全部来自 block_geometry.dart，轮廓来自 block_shapes.dart，颜色来自 block_colors.dart。
// - 一块积木从下到上画五层：（被拖着时）投影 → 底下的深色边 → 渐变主体 → 顶部高光 → 字和槽位。
// - 槽位三种：白底输入框（直接填）、深色胶囊带小三角（挑一个）、空槽（等一个表达式）；要“是 / 否”的是六边形。
// - 选中＝外面一圈亮黄描边；落点阴影＝只画一个半透明的剪影。
import 'package:lopicode/blocks/block_colors.dart';
import 'package:lopicode/blocks/block_geometry.dart';
import 'package:lopicode/blocks/block_host.dart';
import 'package:lopicode/blocks/block_shapes.dart';
import 'package:lopicode/lowcode/logic_model.dart';
import 'package:material_ui/material_ui.dart';

/// 量字和画字。同一种字（内容 + 样式）只排一次版。
class BkText {
  BkText({required this.fontFamily, this.metrics = const BkMetrics()});

  final String? fontFamily;
  final BkMetrics metrics;
  final Map<String, TextPainter> _cache = {};

  TextStyle _style(Color color, FontWeight weight, double size) =>
      TextStyle(fontFamily: fontFamily, fontSize: size, height: metrics.textH / metrics.fontSize, fontWeight: weight, color: color, leadingDistribution: TextLeadingDistribution.even);

  TextPainter _painter(String text, Color color, FontWeight weight, double size, double maxWidth) {
    final key = '$text\u0000${color.toARGB32()}\u0000${weight.value}\u0000$size\u0000${maxWidth.toStringAsFixed(1)}';
    final cached = _cache[key];
    if (cached != null) return cached;
    if (_cache.length > 600) {
      for (final p in _cache.values) {
        p.dispose();
      }
      _cache.clear();
    }
    final tp = TextPainter(
      text: TextSpan(text: text, style: _style(color, weight, size)),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: maxWidth);
    return _cache[key] = tp;
  }

  /// 积木上的字有多宽（排版引擎的 [BkMeasure] 用这个）。往上取整，免得画的时候差零点几像素被省略成“…”。
  double measure(String text) => text.isEmpty ? 0 : _painter(text, const Color(0xFFFFFFFF), FontWeight.w600, metrics.fontSize, double.infinity).width.ceilToDouble();

  /// 把字画进 `rect`：竖直居中，水平靠左（`center`＝居中），放不下就省略。
  void paint(Canvas canvas, String text, Rect rect, Color color, {FontWeight weight = FontWeight.w600, double? size, bool center = false}) {
    if (text.isEmpty) return;
    final tp = _painter(text, color, weight, size ?? metrics.fontSize, rect.width + 1);
    final dx = center ? rect.left + (rect.width - tp.width) / 2 : rect.left;
    tp.paint(canvas, Offset(dx, rect.top + (rect.height - tp.height) / 2));
  }

  void dispose() {
    for (final p in _cache.values) {
      p.dispose();
    }
    _cache.clear();
  }
}

/// 画的时候的附加状态。
class BkPaintState {
  const BkPaintState({this.selected, this.selectedHat = false, this.selectedSlot, this.lifted = false, this.ghost = false, this.errors = const [], this.warnings = const []});

  /// 选中的积木（路径）；`selectedHat`＝选中的是帽子。
  final LcBlockPath? selected;
  final bool selectedHat;

  /// 选中的槽位（积木路径 + 参数名 + 参数里的位置）。
  final ({LcBlockPath block, String arg, BkExprPath path})? selectedSlot;

  /// 被拖起来了：整串底下加投影（放大由外面的控件做）。
  final bool lifted;

  /// 画成落点阴影：只有半透明的剪影。
  final bool ghost;

  /// 有错误 / 警告的积木（空路径＝帽子）：右上角画小圆点。
  final List<LcBlockPath> errors;
  final List<LcBlockPath> warnings;

  static const BkPaintState none = BkPaintState();
}

/// 把一串排好版的积木画到画布上（原点＝这串的左上角）。
class BkScriptPainter {
  BkScriptPainter({required this.palette, required this.text, this.metrics = const BkMetrics()});

  final BkPalette palette;
  final BkText text;
  final BkMetrics metrics;

  void paint(Canvas canvas, BkScriptLayout layout, [BkPaintState state = BkPaintState.none]) {
    final loose = layout.loose;
    if (state.ghost) {
      final fill = Paint()..color = palette.ghost;
      for (final b in layout.blocks) {
        canvas.drawPath(bkBlockPath(b, metrics), fill);
      }
      if (loose != null) canvas.drawPath(bkSlotPath(loose.rect, metrics, hex: loose.hex), fill);
      return;
    }
    if (state.lifted) {
      final shadow = Paint()
        ..color = palette.shadow
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
      for (final b in layout.blocks) {
        canvas.drawPath(bkBlockPath(b, metrics).shift(const Offset(0, 7)), shadow);
      }
      if (loose != null) canvas.drawPath(bkSlotPath(loose.rect, metrics, hex: loose.hex).shift(const Offset(0, 6)), shadow);
    }
    for (final b in layout.blocks) {
      _block(canvas, b, state);
    }
    if (loose != null) _expr(canvas, loose, palette.tone(loose.colorKey), const [], state);
    // 选中描边最后画，压在所有积木上面（不会被下一块盖住半边）。
    final sel = state.selected;
    for (final b in layout.blocks) {
      final hit = b.isHat ? state.selectedHat : (sel != null && bkSameBlockPath(sel, b.path));
      if (hit) _outline(canvas, bkBlockPath(b, metrics));
    }
  }

  void _outline(Canvas canvas, Path path) {
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..strokeJoin = StrokeJoin.round
        ..color = palette.selection.withValues(alpha: 0.35),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeJoin = StrokeJoin.round
        ..color = palette.selection,
    );
  }

  /// 立体的一块：底边、渐变主体、顶部高光。`depth`＝底边多厚。
  void _solid(Canvas canvas, Path path, Rect bounds, BkTone tone, double depth) {
    canvas.drawPath(path.shift(Offset(0, depth)), Paint()..color = tone.edge);
    canvas.drawPath(path, Paint()..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [tone.fillTop, tone.fill]).createShader(bounds));
    canvas.save();
    canvas.clipPath(path);
    canvas.drawPath(
      path.shift(const Offset(0, 1.4)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = const Color(0xFFFFFFFF).withValues(alpha: palette.dark ? 0.16 : 0.30),
    );
    canvas.restore();
  }

  void _block(Canvas canvas, BkBlock b, BkPaintState state) {
    final tone = palette.tone(b.colorKey);
    final path = bkBlockPath(b, metrics);
    _solid(canvas, path, b.rect, tone, metrics.edgeH);
    for (final l in b.labels) {
      text.paint(canvas, l.text, l.rect, tone.text);
    }
    for (final m in b.mouths) {
      final l = m.label;
      if (l != null) text.paint(canvas, l.text, l.rect, tone.text.withValues(alpha: 0.92), size: 13);
    }
    for (final s in b.slots) {
      _slot(canvas, s, tone, b.path, state);
    }
    final bad = state.errors.any((p) => bkSameBlockPath(p, b.path) && (p.isEmpty == b.isHat));
    final warn = !bad && state.warnings.any((p) => bkSameBlockPath(p, b.path) && (p.isEmpty == b.isHat));
    if (bad || warn) {
      final top = b.isHat ? b.rect.top + metrics.hatDome : b.rect.top;
      final c = Offset(b.rect.right - 3, top + 3);
      canvas.drawCircle(c, 6.5, Paint()..color = palette.canvas);
      canvas.drawCircle(c, 5, Paint()..color = bad ? palette.error : palette.warning);
    }
  }

  /// 槽位凹进去的感觉：上沿一道暗线。
  void _inset(Canvas canvas, Path path, double alpha) {
    canvas.save();
    canvas.clipPath(path);
    canvas.drawPath(
      path.shift(const Offset(0, 1.2)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = const Color(0xFF000000).withValues(alpha: alpha),
    );
    canvas.restore();
  }

  void _slot(Canvas canvas, BkSlot s, BkTone tone, LcBlockPath block, BkPaintState state) {
    final m = metrics;
    final path = bkSlotPath(s.rect, m, hex: s.hex);
    switch (s.look) {
      case BkSlotLook.field:
        canvas.drawPath(path, Paint()..color = tone.fieldBg);
        _inset(canvas, path, 0.16);
        final r = Rect.fromLTRB(s.rect.left + m.fieldPadH, s.rect.top, s.rect.right - m.fieldPadH, s.rect.bottom);
        text.paint(canvas, s.text, r, s.placeholder ? tone.fieldHint : tone.fieldText, weight: FontWeight.w400, center: true);
      case BkSlotLook.dropdown:
        canvas.drawPath(path, Paint()..color = tone.deep);
        _inset(canvas, path, 0.22);
        final r = Rect.fromLTRB(s.rect.left + m.fieldPadH, s.rect.top, s.rect.right - m.fieldPadH - m.caretW, s.rect.bottom);
        text.paint(canvas, s.text, r, tone.text.withValues(alpha: s.placeholder ? 0.72 : 1));
        final cx = s.rect.right - m.fieldPadH - 3, cy = s.rect.center.dy + 1;
        canvas.drawPath(
          Path()
            ..moveTo(cx - 4.5, cy - 2.5)
            ..lineTo(cx + 4.5, cy - 2.5)
            ..lineTo(cx, cy + 3)
            ..close(),
          Paint()..color = tone.text.withValues(alpha: 0.85),
        );
      case BkSlotLook.toggle:
        canvas.drawPath(path, Paint()..color = tone.deep);
        _inset(canvas, path, 0.22);
        text.paint(canvas, s.text, s.rect, tone.text, center: true);
      case BkSlotLook.empty:
        canvas.drawPath(path, Paint()..color = tone.deep);
        _inset(canvas, path, 0.30);
      case BkSlotLook.expr:
        final e = s.expr!;
        final own = palette.tone(e.colorKey);
        _expr(canvas, e, e.bare ? tone : (identical(own.fill, tone.fill) || own.fill == tone.fill ? own.nested : own), block, state, parent: tone);
    }
    final sel = state.selectedSlot;
    if (sel != null && sel.arg == s.arg && bkSameBlockPath(sel.block, block) && bkSameExprPath(sel.path, s.exprPath) && s.hatSlotId == null) _outline(canvas, path);
  }

  void _expr(Canvas canvas, BkExpr e, BkTone tone, LcBlockPath block, BkPaintState state, {BkTone? parent}) {
    if (e.bare) {
      // 直接填的值：只画里面那个输入框 / 开关，颜色跟着外面那块积木。
      for (final s in e.slots) {
        _slot(canvas, s, parent ?? palette.tone(BlockColorKey.value), block, state);
      }
      return;
    }
    final t = e.unknown ? palette.tone(BlockColorKey.unknown) : tone;
    _solid(canvas, bkSlotPath(e.rect, metrics, hex: e.hex), e.rect, t, 1.5);
    for (final l in e.labels) {
      text.paint(canvas, l.text, l.rect, t.text);
    }
    for (final s in e.slots) {
      _slot(canvas, s, t, block, state);
    }
  }
}

/// 把一串积木画出来的 CustomPainter。排版在外面算好传进来。
class BkScriptCustomPainter extends CustomPainter {
  BkScriptCustomPainter({required this.layout, required this.painter, this.state = BkPaintState.none, this.revision = 0});

  final BkScriptLayout layout;
  final BkScriptPainter painter;
  final BkPaintState state;

  /// 宿主的版本号：内容变了要重画。
  final int revision;

  @override
  void paint(Canvas canvas, Size size) => painter.paint(canvas, layout, state);

  @override
  bool shouldRepaint(BkScriptCustomPainter old) => !identical(old.layout, layout) || !identical(old.state, state) || old.revision != revision || !identical(old.painter, painter);
}
