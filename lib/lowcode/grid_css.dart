/// 网格（`display: grid`）的读写：第一版只做“等宽 N 列”。画布、样式面板、落点计算共用。
///
/// 写进样式的是 `display: grid` + `grid-template-columns: repeat(N, 1fr)`（N＝1–12）；间距用 `column-gap` / `row-gap`；
/// 子组件跨列写 `grid-column: span N`。这几个写法的核对情况见 docs/api-notes.md。
library;

/// 列数最多多少（面板上能选到的）。
const int kLcGridMaxColumns = 12;

final RegExp _repeat = RegExp(r'^repeat\(\s*(\d+)\s*,');
final RegExp _span = RegExp(r'^span\s+(\d+)$');

bool lcIsGrid(Map<String, String> style) {
  final d = style['display']?.trim().toLowerCase();
  return d == 'grid' || d == 'inline-grid';
}

/// 几列：`repeat(N, …)` 是 N；空格隔开写了几段就是几列（括号里的空格不算）；没写、认不出来是 1。
int lcGridColumns(Map<String, String> style) {
  final v = style['grid-template-columns']?.trim().toLowerCase() ?? '';
  if (v.isEmpty || v == 'none') return 1;
  final m = _repeat.firstMatch(v);
  if (m != null) return int.parse(m.group(1)!).clamp(1, 1000);
  var depth = 0, count = 0, inToken = false;
  for (final ch in v.split('')) {
    if (ch == '(') depth++;
    if (ch == ')') depth--;
    final space = depth == 0 && ch.trim().isEmpty;
    if (!space && !inToken) count++;
    inToken = !space;
  }
  return count.clamp(1, 1000);
}

/// 等宽 N 列的写法。
String lcGridTemplate(int columns) => 'repeat(${columns.clamp(1, kLcGridMaxColumns)}, 1fr)';

/// 子组件跨几列：`grid-column: span N`（或拆开后的 `grid-column-start` / `grid-column-end` 里有 `span N`）；没写是 1。
int lcGridSpan(Map<String, String> childStyle) {
  for (final key in const ['grid-column', 'grid-column-end', 'grid-column-start']) {
    final first = childStyle[key]?.trim().toLowerCase().split('/').first.trim() ?? '';
    final m = _span.firstMatch(first);
    if (m != null) return int.parse(m.group(1)!).clamp(1, 1000);
  }
  return 1;
}
