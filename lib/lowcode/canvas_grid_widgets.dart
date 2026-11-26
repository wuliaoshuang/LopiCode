// 设计约束（低代码 · 画布上的网格）
// - 第一版只画“等宽的几列”：`display: grid` + `grid-template-columns: repeat(N, 1fr)`（或者写了 N 段的列表，一律当成 N 列等宽）。
//   写法认不出来的当 1 列。列间距 / 行间距读 `column-gap` / `row-gap`。
// - 子组件可以“跨几列”（`grid-column: span N`），一行放不下就换到下一行；跨的列数超过总列数按总列数算。
// - 同一行的格子一样高（和网页里网格默认的拉伸一致）。画不了的写法（命名的线、自动填充、行模板…）一律忽略，绝不报错。
import 'dart:math' as math;

import 'package:lopicode/lowcode/canvas_css.dart';
import 'package:lopicode/lowcode/grid_css.dart';
import 'package:material_ui/material_ui.dart';

/// 量好的网格：几列、每列多宽、两种间距。
class CanvasGridSpec {
  const CanvasGridSpec(this.columns, this.columnWidth, this.columnGap, this.rowGap);
  final int columns;
  final double columnWidth;
  final double columnGap;
  final double rowGap;
}

/// 这个容器是不是网格；不是返回 null。
CanvasGridSpec? canvasGridOf(Map<String, String> s, CssScale scale, double availW) {
  if (!lcIsGrid(s)) return null;
  final columns = lcGridColumns(s);
  final columnGap = cssSizePx(s['column-gap'], scale, percentOf: availW) ?? 0;
  final rowGap = cssSizePx(s['row-gap'], scale, percentOf: availW) ?? 0;
  return CanvasGridSpec(columns, math.max(0, (availW - columnGap * (columns - 1)) / columns), columnGap, rowGap);
}

/// 子组件跨几列（没写是 1）。
int canvasGridSpan(Map<String, String> childStyle) => lcGridSpan(childStyle);

/// 把格子一行行排出来。
Widget canvasGrid(CanvasGridSpec g, List<({int span, Widget child})> cells) {
  final rows = <List<Widget>>[[]];
  var used = 0;
  for (final cell in cells) {
    final span = cell.span.clamp(1, g.columns);
    if (used + span > g.columns) {
      rows.add([]);
      used = 0;
    }
    rows.last.add(SizedBox(width: g.columnWidth * span + g.columnGap * (span - 1), child: cell.child));
    used += span;
  }
  return Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    spacing: g.rowGap,
    children: [
      for (final row in rows)
        IntrinsicHeight(
          child: Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, spacing: g.columnGap, children: row),
        ),
    ],
  );
}
