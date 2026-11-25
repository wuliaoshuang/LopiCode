// 设计约束（积木上的问题标记 + 问题小卡，390 宽，浅色 + 深色）— 2026-11-24
// - 标记要克制：积木还是积木，标记只是“贴在上面的小记号”，不改积木的颜色和形状。
// - 有错误的积木：沿轮廓一圈细红线 + 右上角红色圆形角标；只有警告的积木：不描边，只在右上角放黄色三角角标。
//   角标里都有“!”，而且错误是圆、警告是三角——不只靠颜色分。选中是亮黄的柔光描边、吸附是白色，都和红色细线分得开。
// - 出问题的那一格（槽）：外面一圈同色虚线（空着的必填格就是红色虚线框）。
// - 点角标弹出小卡，贴着角标：一条问题两行——原因（正文色）、“建议：…”（次要色），右上角是规则编号；多条依次列出。
//   小卡外面点一下就关，不挡画布别的操作。主操作＝看完去改那一格。
import 'dart:math' as math;

import 'package:lopicode/blocks/block_canvas_layout.dart';
import 'package:lopicode/blocks/block_colors.dart';
import 'package:lopicode/blocks/block_geometry.dart';
import 'package:lopicode/blocks/block_host.dart';
import 'package:lopicode/blocks/block_shapes.dart';
import 'package:lopicode/lowcode/logic_model.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:material_ui/material_ui.dart';

/// 一串积木上的问题，按“哪一块 / 哪一格”查。
class BkIssueMarks {
  BkIssueMarks(this.issues);

  /// 把全部问题按串分开。
  static Map<String, BkIssueMarks> byScript(List<BlockIssue> issues) {
    final out = <String, List<BlockIssue>>{};
    for (final i in issues) {
      final id = i.scriptId;
      if (id != null) (out[id] ??= []).add(i);
    }
    return {for (final e in out.entries) e.key: BkIssueMarks(e.value)};
  }

  final List<BlockIssue> issues;

  /// 这一块上的问题（帽子＝路径为空的那些），错误在前。
  List<BlockIssue> of(BkBlock b) {
    final mine = [
      for (final i in issues)
        if (i.path.isEmpty == b.isHat && (b.isHat || bkSameBlockPath(i.path, b.path))) i,
    ];
    return [...mine.where((i) => i.isError), ...mine.where((i) => !i.isError)];
  }

  /// true＝有错误，false＝只有警告，null＝没问题。
  bool? levelOf(BkBlock b) {
    bool? level;
    for (final i in issues) {
      if (i.path.isEmpty != b.isHat || !(b.isHat || bkSameBlockPath(i.path, b.path))) continue;
      if (i.isError) return true;
      level = false;
    }
    return level;
  }

  /// 这一格有没有问题（`block`＝它所在积木的路径，帽子为空）。
  bool? slotLevel(LcBlockPath block, BkSlot s) {
    if (s.look == BkSlotLook.add) return null;
    final hat = s.hatSlotId;
    bool? level;
    for (final i in issues) {
      final xp = i.exprPath;
      if (xp == null) continue;
      final hit = hat != null ? (i.path.isEmpty && i.arg == hat) : (i.path.isNotEmpty && i.arg == s.arg && bkSameBlockPath(i.path, block) && bkSameExprPath(xp, s.exprPath));
      if (!hit) continue;
      if (i.isError) return true;
      level = false;
    }
    return level;
  }
}

/// 角标的圆心（这一串自己的坐标）：压在积木右上角上，帽子的在圆顶下面那条边上。
Offset bkIssueBadgeCenter(BkBlock b, BkMetrics m) => Offset(b.rect.right - 5, (b.isHat ? b.rect.top + m.hatDome : b.rect.top) + 4);

/// 画布上这一点是不是点在某个角标上（`reach`＝离圆心多远算点中，画布尺寸）。
({BkPlaced script, BkBlock block, List<BlockIssue> issues})? bkIssueBadgeAt(BkCanvasLayout layout, Map<String, BkIssueMarks> marks, Offset canvas, BkMetrics m, double reach) {
  for (var k = layout.scripts.length - 1; k >= 0; k--) {
    final s = layout.scripts[k];
    final mk = marks[s.id];
    if (mk == null || !s.bounds.inflate(reach).contains(canvas)) continue;
    final local = canvas - s.origin;
    for (final b in s.layout.blocks) {
      if ((bkIssueBadgeCenter(b, m) - local).distance > reach) continue;
      final mine = mk.of(b);
      if (mine.isNotEmpty) return (script: s, block: b, issues: mine);
    }
  }
  return null;
}

/// 积木上的标记：有错误＝沿轮廓一圈细红线；再加右上角的角标。
void bkPaintBlockMark(Canvas canvas, BkPalette palette, BkMetrics m, BkBlock b, Path outline, {required bool error}) {
  if (error) {
    canvas.drawPath(
      outline,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round
        ..color = palette.error,
    );
  }
  bkPaintIssueBadge(canvas, bkIssueBadgeCenter(b, m), error: error, color: error ? palette.error : palette.warning, mark: error ? palette.onError : palette.onWarning, ring: palette.canvas);
}

/// 角标：错误是圆，警告是圆角三角，里面都是“!”。`ring`＝外面一圈底色（把角标和积木隔开）。
void bkPaintIssueBadge(Canvas canvas, Offset c, {required bool error, required Color color, required Color mark, required Color ring, double size = 8}) {
  final markPaint = Paint()
    ..color = mark
    ..strokeWidth = size * 0.26
    ..strokeCap = StrokeCap.round;
  if (error) {
    canvas.drawCircle(c, size + 1.6, Paint()..color = ring);
    canvas.drawCircle(c, size, Paint()..color = color);
    canvas.drawLine(c + Offset(0, -size * 0.5), c + Offset(0, size * 0.1), markPaint);
    canvas.drawCircle(c + Offset(0, size * 0.5), size * 0.15, markPaint..style = PaintingStyle.fill);
    return;
  }
  final r = size * 1.12;
  final tri = Path()
    ..moveTo(c.dx, c.dy - r)
    ..lineTo(c.dx + r * 1.02, c.dy + r * 0.78)
    ..lineTo(c.dx - r * 1.02, c.dy + r * 0.78)
    ..close();
  Paint round(Color color, double w) => Paint()
    ..color = color
    ..style = PaintingStyle.stroke
    ..strokeWidth = w
    ..strokeJoin = StrokeJoin.round;
  canvas.drawPath(tri, round(ring, size * 0.9));
  canvas.drawPath(tri, Paint()..color = ring);
  canvas.drawPath(tri, round(color, size * 0.5));
  canvas.drawPath(tri, Paint()..color = color);
  canvas.drawLine(c + Offset(0, -size * 0.36), c + Offset(0, size * 0.16), markPaint);
  canvas.drawCircle(c + Offset(0, size * 0.52), size * 0.15, markPaint..style = PaintingStyle.fill);
}

/// 出问题的那一格：外面一圈同色虚线。
void bkPaintSlotMark(Canvas canvas, BkPalette palette, BkMetrics m, BkSlot s, {required bool error}) {
  final color = error ? palette.error : palette.warning;
  final path = bkSlotPath(s.rect.inflate(2), m, hex: s.hex);
  // 底下先垫一圈积木画布的底色，虚线在什么颜色的积木上都看得清。
  canvas.drawPath(
    path,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.2
      ..color = palette.canvas.withValues(alpha: 0.85),
  );
  final dash = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.8
    ..strokeCap = StrokeCap.round
    ..color = color;
  for (final metric in path.computeMetrics()) {
    const on = 4.5, off = 3.5;
    final n = math.max(1, (metric.length / (on + off)).round());
    final step = metric.length / n;
    for (var i = 0; i < n; i++) {
      canvas.drawPath(metric.extractPath(i * step, i * step + step * on / (on + off)), dash);
    }
  }
}

/// 角标 / 列表里用的小图标（和画在积木上的是同一个画法）。
class BkIssueIcon extends StatelessWidget {
  const BkIssueIcon({super.key, required this.error, this.size = 18});
  final bool error;
  final double size;

  @override
  Widget build(BuildContext context) {
    // 和画布上的角标用同一套颜色：列表里看到的图标和积木上的是同一个东西。
    final p = BkPalette.fromTheme(context.themeSpec);
    return Semantics(
      label: error ? '错误' : '警告',
      child: CustomPaint(
        size: Size.square(size),
        painter: _IconPainter(error: error, color: error ? p.error : p.warning, mark: error ? p.onError : p.onWarning),
      ),
    );
  }
}

class _IconPainter extends CustomPainter {
  _IconPainter({required this.error, required this.color, required this.mark});
  final bool error;
  final Color color;
  final Color mark;

  @override
  void paint(Canvas canvas, Size size) => bkPaintIssueBadge(canvas, size.center(Offset.zero), error: error, color: color, mark: mark, ring: Colors.transparent, size: size.shortestSide * 0.42);

  @override
  bool shouldRepaint(_IconPainter old) => old.error != error || old.color != color;
}

/// 一条问题的两行：原因 + 建议（小卡和问题列表共用）。
class BkIssueLines extends StatelessWidget {
  const BkIssueLines({super.key, required this.issue, this.head = ''});
  final BlockIssue issue;

  /// 原因前面再加一句“在哪”（问题列表里用；小卡贴着积木，不用说）。
  final String head;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: BkIssueIcon(error: issue.isError),
        ),
        const SizedBox(width: Space.x2),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (head.isNotEmpty)
                Text(
                  head,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: t.bodySmall?.copyWith(color: c.textMuted),
                ),
              Text(issue.reason, style: t.bodyMedium),
              if (issue.fix.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text('建议：${issue.fix}', style: t.bodySmall?.copyWith(color: c.textMuted)),
                ),
            ],
          ),
        ),
        if (issue.rule.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: Space.x2, top: 2),
            child: Text(issue.rule, style: t.labelSmall?.copyWith(color: c.textMuted)),
          ),
      ],
    );
  }
}

/// 贴着角标弹出问题小卡（`anchor`＝角标在屏幕上的位置）。点外面关掉。
Future<void> showBlockIssueCard(BuildContext context, {required Rect anchor, required List<BlockIssue> issues}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: '关闭问题说明',
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 120),
    pageBuilder: (dialog, _, _) {
      final c = dialog.colors;
      final screen = MediaQuery.sizeOf(dialog);
      final pad = MediaQuery.paddingOf(dialog);
      final width = math.min(312.0, screen.width - 24);
      final left = (anchor.right - width + 8).clamp(12.0, screen.width - width - 12);
      // 下面放得下就放下面，否则放上面。
      final below = screen.height - pad.bottom - anchor.bottom - 16;
      final above = anchor.top - pad.top - 16;
      final down = below >= 160 || below >= above;
      return Stack(
        children: [
          Positioned(
            left: left.toDouble(),
            width: width,
            top: down ? anchor.bottom + 6 : null,
            bottom: down ? null : screen.height - anchor.top + 6,
            child: Material(
              key: const ValueKey('bk-issue-card'),
              color: c.surface,
              elevation: 6,
              shadowColor: c.shadowOf(0x55 / 255),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(color: c.border),
              ),
              clipBehavior: Clip.antiAlias,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: math.max(120, down ? below : above)),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: Space.x3, vertical: Space.x3),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < issues.length; i++) ...[
                        if (i > 0)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: Space.x2),
                            child: Divider(height: 1, color: c.border),
                          ),
                        BkIssueLines(key: ValueKey('bk-issue-card-$i'), issue: issues[i]),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    },
    transitionBuilder: (_, anim, _, child) => FadeTransition(opacity: anim, child: child),
  );
}
