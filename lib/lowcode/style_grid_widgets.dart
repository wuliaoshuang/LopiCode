// 设计约束（样式面板 › 布局组里的“网格”几行；390×844）
// - 一行只做一件事：排法（弹性 / 网格）、列数、列间距、行间距各占一行；子组件多一行“跨几列”。
// - 第一版网格只有“等宽 N 列”（1–12）。文件里写的是别的网格写法（列宽不一样、带名字的线…）时不硬改：
//   列数那一行显示数出来的列数，下面一句小字说清楚“改了会变成等宽”。
// - 唯一主操作：没有（都是改值的控件）。
// - 取用的 tokens：Space.x2、textFaint。
import 'package:lopicode/lowcode/grid_css.dart';
import 'package:lopicode/lowcode/style_controls_widgets.dart';
import 'package:lopicode/lowcode/style_rows_widgets.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:material_ui/material_ui.dart';

/// 容器的“排法”：弹性（默认）还是网格。选网格时没写过列数就先给两列；换回弹性把网格的列写法去掉（间距留着，两种排法通用）。
class GridModeRow extends StatelessWidget {
  const GridModeRow(this.ed, {super.key});
  final StyleEdit ed;

  @override
  Widget build(BuildContext context) => StyleRow(
    label: '排法',
    child: ChoiceButtons(
      id: 'layout-mode',
      options: const [ChoiceOption('flex', '弹性'), ChoiceOption('grid', '网格')],
      selected: lcIsGrid(ed.resolved) ? 'grid' : 'flex',
      // 再点一下已经选中的那个：不变（两个里总得有一个）。
      onChanged: (v) => v == null
          ? null
          : ed.apply((s) {
              if (v == 'grid') {
                s.set('display', 'grid');
                if (!s.map.containsKey('grid-template-columns')) s.set('grid-template-columns', lcGridTemplate(2));
              } else {
                s.set('display', null);
                s.set('grid-template-columns', null);
              }
            }),
    ),
  );
}

/// 网格容器的三行：列数、列间距、行间距。
class GridRows extends StatelessWidget {
  const GridRows(this.ed, {super.key});
  final StyleEdit ed;

  @override
  Widget build(BuildContext context) {
    final raw = ed.resolved['grid-template-columns']?.trim() ?? '';
    final columns = lcGridColumns(ed.resolved);
    final even = raw.isEmpty || raw == lcGridTemplate(columns);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StyleRow(
          label: '列数',
          hint: '每列一样宽',
          child: NumberField(
            id: 'grid-columns',
            value: columns.toDouble(),
            min: 1,
            integer: true,
            start: 1,
            // 清除＝回到一列。
            onChanged: (v, {required merge}) => ed.apply((s) => s.set('grid-template-columns', v == null ? null : lcGridTemplate(v.round())), merge: merge),
          ),
        ),
        if (!even)
          Padding(
            key: const Key('lc-grid-uneven'),
            padding: const EdgeInsets.only(bottom: Space.x2),
            child: Text('现在各列不一样宽（$raw）。在这里改列数会变成每列一样宽。', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: context.colors.textFaint, height: 1.5)),
          ),
        StyleLengthRow(ed, 'column-gap', '列间距', stepper: true),
        StyleLengthRow(ed, 'row-gap', '行间距', stepper: true),
      ],
    );
  }
}

/// 放在网格里的组件：跨几列（1＝不跨，不写）。最多跨到父容器的列数。
class GridSpanRow extends StatelessWidget {
  const GridSpanRow(this.ed, {super.key, required this.columns});
  final StyleEdit ed;
  final int columns;

  @override
  Widget build(BuildContext context) => StyleRow(
    label: '跨几列',
    hint: '所在的网格一共 $columns 列',
    child: NumberField(
      id: 'grid-span',
      value: lcGridSpan(ed.resolved).clamp(1, columns).toDouble(),
      min: 1,
      integer: true,
      start: 1,
      onChanged: (v, {required merge}) => ed.apply((s) {
        final n = (v ?? 1).round().clamp(1, columns);
        s.set('grid-column', n <= 1 ? null : 'span $n');
      }, merge: merge),
    ),
  );
}
