// 设计约束（积木怎么画）— 2026-11-24
// - 只管“把排好版的积木画出来”：位置全部来自 block_geometry.dart，轮廓来自 block_shapes.dart，颜色来自 block_colors.dart。
// - 一块积木从下到上画五层：（被拖着时）投影 → 底下的深色边 → 渐变主体 → 顶部高光 → 字和槽位。
// - 槽位三种：白底输入框（直接填）、深色胶囊带小三角（挑一个）、空槽（等一个表达式）；要“是 / 否”的是六边形。
// - 选中＝外面一圈柔和的亮黄描边（细线 + 淡淡的光晕）；落点阴影＝和手上那块同形的剪影：淡淡的本色 + 一圈本色描边，一眼看出“会插到这里”。
// - 有问题的积木：错误＝沿轮廓一圈细红线 + 右上角红色圆角标，警告＝只有黄色三角角标；出问题的那一格外面一圈同色虚线（画法在 block_issue_view.dart）。
// - 让位时积木是滑过去的：位置由外面给（`BkPaintState.pose`），这里只管照着画；刚落下的积木轻弹一下（`pulse`）。
import 'package:lopicode/blocks/block_colors.dart';
import 'package:lopicode/blocks/block_geometry.dart';
import 'package:lopicode/blocks/block_host.dart';
import 'package:lopicode/blocks/block_issue_view.dart';
import 'package:lopicode/blocks/block_motion.dart';
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
  double measure(String text) => text.isEmpty ? 0 : _painter(text, kBkMeasureInk, FontWeight.w600, metrics.fontSize, double.infinity).width.ceilToDouble();

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
  const BkPaintState({
    this.selected,
    this.selectedHat = false,
    this.selectedSlot,
    this.slotColor,
    this.lifted = false,
    this.ghost = false,
    this.ghostRange,
    this.ghostAlpha = 1,
    this.clip,
    this.pose,
    this.pulse,
    this.pulseRange,
    this.pulseSlot,
    this.flash = 0,
    this.errors = const [],
    this.warnings = const [],
    this.marks,
  });

  /// 选中的积木（路径）；`selectedHat`＝选中的是帽子。
  final LcBlockPath? selected;
  final bool selectedHat;

  /// 选中的槽位（积木路径 + 参数名 + 参数里的位置）。
  final ({LcBlockPath block, String arg, BkExprPath path})? selectedSlot;

  /// [selectedSlot] 的描边换一种颜色（拖表达式时：类型对不上的槽用提醒色）；null＝和选中积木一样的亮黄。
  final Color? slotColor;

  /// 这一段积木画成落点阴影（拖动时“让出来的位置”）：`parent / inElse` 下面从 `start` 起的 `count` 块，连同它们里面的。
  final BkRange? ghostRange;

  /// 落点阴影的浓淡（0–1；让位动画里淡入）。
  final double ghostAlpha;

  /// 只画碰到这块区域的积木（这一串自己的坐标；画布上露出来的那一块）。null＝全画。
  final Rect? clip;

  /// 让位动画：这块积木此刻该画在哪（这一串自己的坐标）；返回 null＝就在排版算出来的位置。
  final BkFrame? Function(BkBlock block)? pose;

  /// 刚落下的积木轻弹一下的进度（0–1）；null＝没有。弹的是 [pulseRange] 那一段（null＝整串），
  /// 或者 [pulseSlot] 那个槽（表达式落进槽里：槽的描边闪一下）。
  final double? pulse;
  final BkRange? pulseRange;
  final ({LcBlockPath block, String arg, BkExprPath path})? pulseSlot;

  /// 选中的那块闪一下的强度（0–1；跳到某块积木时用）。
  final double flash;

  /// 被拖起来了：整串底下加投影（放大由外面的控件做）。
  final bool lifted;

  /// 画成落点阴影：只有半透明的剪影。
  final bool ghost;

  /// 有错误 / 警告的积木（空路径＝帽子）：只知道“哪一块”时用这两个（只读画布）；编辑器给 [marks]，连哪一格都标。
  final List<LcBlockPath> errors;
  final List<LcBlockPath> warnings;

  /// 这一串上的问题（给了就不看 [errors] / [warnings]）。
  final BkIssueMarks? marks;

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
    final range = state.ghostRange;
    final pulse = state.pulseSlot == null ? state.pulse : null;
    final pulseRange = state.pulseRange;
    bool pulsed(BkBlock b) => pulse != null && (pulseRange == null || _inRange(b, pulseRange));
    Rect? pulseBox;
    if (pulse != null) {
      for (final b in layout.blocks) {
        if (pulsed(b)) pulseBox = pulseBox?.expandToInclude(b.rect) ?? b.rect;
      }
    }
    // 轻弹：整段绕自己的中心缩放。
    void bounce(void Function() draw) {
      final c = pulseBox!.center;
      final k = bkLandScale(pulse!);
      canvas.save();
      canvas.translate(c.dx, c.dy);
      canvas.scale(k);
      canvas.translate(-c.dx, -c.dy);
      draw();
      canvas.restore();
    }

    final clip = state.clip;
    // 单独摆着的值先画：它要是“带口的值”，口里的积木（在 blocks 里）得画在它上面。
    if (loose != null) _expr(canvas, loose, palette.tone(loose.colorKey), const [], state);
    for (final b in layout.blocks) {
      final posed = state.pose?.call(b);
      // 很长的一串只画露出来的那几块（正在滑的按滑到的位置算）。
      if (clip != null && !(posed?.rect ?? b.rect).inflate(12).overlaps(clip)) continue;
      if (range != null && _inRange(b, range)) {
        _ghostBlock(canvas, b, state.ghostAlpha);
      } else if (pulsed(b)) {
        bounce(() {
          _block(canvas, b, state);
          // 落下的一瞬间亮一圈，马上淡掉。
          canvas.drawPath(
            bkBlockPath(b, metrics),
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2 + 5 * pulse!
              ..strokeJoin = StrokeJoin.round
              ..color = palette.gloss.withValues(alpha: 0.75 * (1 - pulse)),
          );
        });
      } else {
        _block(canvas, b, state, posed);
      }
    }
    // 选中描边最后画，压在所有积木上面（不会被下一块盖住半边）。
    final sel = state.selected;
    for (final b in layout.blocks) {
      final hit = b.isHat ? state.selectedHat : (sel != null && bkSameBlockPath(sel, b.path));
      if (!hit) continue;
      final path = bkBlockPath(b, metrics);
      void outline() {
        if (state.flash > 0) {
          canvas.drawPath(
            path,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 5 + 12 * state.flash
              ..strokeJoin = StrokeJoin.round
              ..color = palette.selection.withValues(alpha: 0.45 * state.flash),
          );
        }
        _outline(canvas, path, soft: true);
      }

      pulsed(b) ? bounce(outline) : outline();
    }
  }

  /// 落点阴影里的一块：和真积木同一个轮廓（凹口、凸起、C 形的口都在），淡淡的本色 + 一圈本色描边。
  void _ghostBlock(Canvas canvas, BkBlock b, double alpha) {
    final a = alpha.clamp(0.0, 1.0);
    final tone = palette.tone(b.colorKey);
    final path = bkBlockPath(b, metrics);
    canvas.drawPath(path, Paint()..color = palette.ghost.withValues(alpha: palette.ghost.a * a));
    canvas.drawPath(path, Paint()..color = tone.fill.withValues(alpha: (palette.dark ? 0.34 : 0.24) * a));
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeJoin = StrokeJoin.round
        ..color = (palette.dark ? tone.fillTop : tone.fill).withValues(alpha: 0.8 * a),
    );
  }

  static bool _inRange(BkBlock b, BkRange r) {
    final n = r.parent.length;
    if (b.isHat || b.path.length <= n || !bkSameBlockPath(r.parent, b.path.sublist(0, n))) return false;
    final step = b.path[n];
    return (n == 0 || lcSameMouth(step, lcStep(0, inElse: r.inElse, arm: r.arm))) && step.index >= r.start && step.index < r.start + r.count;
  }

  /// 描边。`soft`＝选中积木用的柔和版（细线 + 淡光晕）；拖表达式时目标槽的描边要醒目，用默认的。
  void _outline(Canvas canvas, Path path, {Color? color, bool soft = false, double alpha = 1}) {
    final c = color ?? palette.selection;
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = soft ? 6 : 5
        ..strokeJoin = StrokeJoin.round
        ..color = c.withValues(alpha: (soft ? 0.22 : 0.35) * alpha),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = soft ? 1.8 : 2.2
        ..strokeJoin = StrokeJoin.round
        ..color = c.withValues(alpha: alpha),
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
        ..color = palette.gloss.withValues(alpha: palette.dark ? 0.16 : 0.30),
    );
    canvas.restore();
  }

  /// `pose`＝让位动画里这块此刻的位置和外形（见 [BkFrame]）：头上的字和槽跟着左上角走，口和横栏照 pose 的大小画。
  void _block(Canvas canvas, BkBlock b, BkPaintState state, [BkFrame? pose]) {
    final tone = palette.tone(b.colorKey);
    if (pose != null && pose.mouths.length != b.mouths.length) pose = null;
    final d = pose == null ? Offset.zero : pose.rect.topLeft - b.rect.topLeft;
    var shape = b;
    if (pose != null) {
      shape = BkBlock(path: b.path, block: b.block, shape: b.shape, colorKey: b.colorKey, rect: pose.rect, head: b.head.shift(d));
      for (var i = 0; i < b.mouths.length; i++) {
        shape.mouths.add(BkMouth(inElse: b.mouths[i].inElse, arm: b.mouths[i].arm, rect: pose.mouths[i], bar: pose.bars[i]));
      }
    }
    final path = bkBlockPath(shape, metrics);
    _solid(canvas, path, shape.rect, tone, metrics.edgeH);
    // 头上的字和槽跟着左上角走；每段横栏上的跟着那条横栏走；底条上的“＋”跟着下沿走。
    void shifted(Offset by, void Function() draw) {
      if (by == Offset.zero) return draw();
      canvas.save();
      canvas.translate(by.dx, by.dy);
      draw();
      canvas.restore();
    }

    Offset barShift(int mouth) {
      if (pose == null) return Offset.zero;
      if (mouth < 0) return pose.rect.bottomLeft - b.rect.bottomLeft;
      final from = b.mouths[mouth].bar, to = pose.bars[mouth];
      return from != null && to != null ? to.topLeft - from.topLeft : d;
    }

    shifted(d, () {
      for (var i = 0; i < b.headLabels && i < b.labels.length; i++) {
        text.paint(canvas, b.labels[i].text, b.labels[i].rect, tone.text);
      }
      for (var i = 0; i < b.headSlots && i < b.slots.length; i++) {
        _slot(canvas, b.slots[i], tone, b.path, state);
      }
    });
    for (var i = 0; i < b.mouths.length; i++) {
      final mouth = b.mouths[i];
      final l = mouth.label;
      if (l == null && mouth.labels.isEmpty && mouth.slots.isEmpty) continue;
      shifted(barShift(i), () {
        if (l != null) text.paint(canvas, l.text, l.rect, tone.text.withValues(alpha: 0.92), size: 13);
        for (final x in mouth.labels) {
          text.paint(canvas, x.text, x.rect, tone.text);
        }
        for (final x in mouth.slots) {
          _slot(canvas, x, tone, b.path, state);
        }
      });
    }
    for (final c in b.controls) {
      shifted(barShift(c.mouth), () => _control(canvas, c, tone));
    }
    final marks = state.marks;
    bool same(LcBlockPath p) => bkSameBlockPath(p, b.path) && (p.isEmpty == b.isHat);
    final level = marks != null ? marks.levelOf(b) : (state.errors.any(same) ? true : (state.warnings.any(same) ? false : null));
    if (level != null) bkPaintBlockMark(canvas, palette, metrics, shape, path, error: level);
  }

  /// 多口积木上的小按钮：一个压进去的深色小圆，里面白色的“＋”或“−”（和“一串值”末尾的小“＋”同一个样子）。
  void _control(Canvas canvas, BkControl c, BkTone tone) {
    final o = c.rect.center;
    final add = c.kind == BkControlKind.add;
    canvas.drawCircle(o, c.rect.width / 2, Paint()..color = tone.deep.withValues(alpha: add ? 1 : 0.78));
    final pen = Paint()
      ..color = tone.text.withValues(alpha: add ? 0.92 : 0.8)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(o - const Offset(4.5, 0), o + const Offset(4.5, 0), pen);
    if (add) canvas.drawLine(o - const Offset(0, 4.5), o + const Offset(0, 4.5), pen);
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
        ..color = palette.shade.withValues(alpha: alpha),
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
      case BkSlotLook.param:
        // 参数小块：就是它拖出来以后那个值的样子（同色的小胶囊），比槽略矮一点，看得出是“放在上面的一小块”。
        final chip = palette.tone(s.colorKey ?? BlockColorKey.variable);
        final r = s.rect.deflate(1);
        _solid(canvas, bkPillPath(r), r, identical(chip.fill, tone.fill) || chip.fill == tone.fill ? chip.nested : chip, 1.5);
        text.paint(canvas, s.text, Rect.fromLTRB(r.left + m.fieldPadH, r.top, r.right - m.fieldPadH, r.bottom), chip.text, center: true);
        return;
      case BkSlotLook.add:
        final c = s.rect.center;
        canvas.drawCircle(c, 10, Paint()..color = tone.deep);
        final plus = Paint()
          ..color = tone.text.withValues(alpha: 0.9)
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round;
        canvas.drawLine(c - const Offset(4.5, 0), c + const Offset(4.5, 0), plus);
        canvas.drawLine(c - const Offset(0, 4.5), c + const Offset(0, 4.5), plus);
      case BkSlotLook.expr:
        final e = s.expr!;
        final own = palette.tone(e.colorKey);
        _expr(canvas, e, e.bare ? tone : (identical(own.fill, tone.fill) || own.fill == tone.fill ? own.nested : own), block, state, parent: tone);
    }
    final bad = state.marks?.slotLevel(block, s);
    if (bad != null) bkPaintSlotMark(canvas, palette, metrics, s, error: bad);
    final sel = state.selectedSlot;
    if (sel != null && sel.arg == s.arg && bkSameBlockPath(sel.block, block) && bkSameExprPath(sel.path, s.exprPath) && s.hatSlotId == null && s.look != BkSlotLook.add && s.param == null) {
      _outline(canvas, path, color: state.slotColor);
    }
    final ps = state.pulseSlot, pp = state.pulse;
    if (ps != null && pp != null && ps.arg == s.arg && bkSameBlockPath(ps.block, block) && bkSameExprPath(ps.path, s.exprPath) && s.hatSlotId == null && s.look != BkSlotLook.add && s.param == null) {
      _outline(canvas, path, color: palette.gloss, alpha: 1 - pp);
    }
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
    final mouth = e.mouth;
    if (mouth != null) {
      // 带口的值：口是凹进去的一块（露出画布的底色，上沿一道暗线），里面的语句积木另外画在上面。
      final hole = Path()..addRRect(RRect.fromRectAndRadius(mouth, const Radius.circular(9)));
      canvas.drawPath(hole, Paint()..color = palette.canvas);
      canvas.drawPath(hole, Paint()..color = t.deep.withValues(alpha: palette.dark ? 0.30 : 0.14));
      _inset(canvas, hole, 0.24);
    }
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
