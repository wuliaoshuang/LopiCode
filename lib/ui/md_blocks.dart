// 设计约束（正文里的各种块 · 390×844）— 2026-11-26
// - 一块占一行（整宽），块和块之间留一档间距；一行只放一样东西。
// - 列表：记号（圆点 / 序号 / 勾选框）在左边窄窄一列，内容在右边；嵌套就往右缩进。勾选框只是显示，不能点。
// - 引用：左边一条细竖线 + 灰字，不加底色。
// - 表格：比屏幕宽就左右滑，不撑破屏幕；表头加粗、有底色；单元格最宽 240，再长就在格子里换行。
// - details：一行标题（带展开箭头），点了才显示里面的内容。
import 'package:lopicode/markdown/md_nodes.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/md_code_block.dart';
import 'package:lopicode/ui/md_inline.dart';
import 'package:lopicode/ui/md_style.dart';
import 'package:material_ui/material_ui.dart';

/// 表格一格最宽这么多（自己定的）。
const double kMdTableCellMaxWidth = 240;

/// 一串块从上往下排。[cursor]＝最后一块末尾带光标块。
class MdBlocks extends StatelessWidget {
  const MdBlocks(this.blocks, {super.key, this.cursor = false, this.style});
  final List<MdBlock> blocks;
  final bool cursor;

  /// 这一串里文字的样式（引用里是灰字）；不传用正文样式。
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final s = MdScope.of(context).styles;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < blocks.length; i++)
          Padding(
            padding: EdgeInsets.only(top: i == 0 ? 0 : s.gap),
            child: MdBlockView(blocks[i], cursor: cursor && i == blocks.length - 1, style: style),
          ),
      ],
    );
  }
}

class MdBlockView extends StatelessWidget {
  const MdBlockView(this.block, {super.key, this.cursor = false, this.style});
  final MdBlock block;
  final bool cursor;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final s = MdScope.of(context).styles;
    final c = s.colors;
    final b = block;
    switch (b) {
      case MdParagraph(:final inlines):
        return MdRichText(inlines, style: style, cursor: cursor);
      case MdHeading(:final level, :final inlines):
        return Padding(
          padding: EdgeInsets.only(top: level <= 2 && s.tone != MdTone.muted ? Space.x1 : 0),
          child: MdRichText(inlines, style: s.heading(level).copyWith(color: style?.color), cursor: cursor),
        );
      case final MdCode code:
        return MdCodeBlock(code, cursor: cursor);
      case MdRule():
        return _withCursor(Divider(height: Space.x2, thickness: 1, color: c.border), s);
      case MdQuote(:final children):
        return Container(
          padding: const EdgeInsets.only(left: Space.x3),
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: c.border, width: 3)),
          ),
          child: MdBlocks(children, cursor: cursor, style: (style ?? s.base).copyWith(color: s.subtle)),
        );
      case final MdList list:
        return _withCursor(_MdListView(list, style: style), s, inside: true);
      case final MdTable table:
        return _withCursor(_MdTableView(table), s);
      case final MdDetails details:
        return _withCursor(_MdDetailsView(details), s);
    }
  }

  /// 最后一块不是文字时，光标块单独占一小行。
  Widget _withCursor(Widget child, MdStyles s, {bool inside = false}) {
    if (!cursor) return child;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        child,
        Text('▍', style: s.base),
      ],
    );
  }
}

class _MdListView extends StatelessWidget {
  const _MdListView(this.list, {this.style});
  final MdList list;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final s = MdScope.of(context).styles;
    final c = s.colors;
    final base = style ?? s.base;
    // 序号那一列的宽度按最大的序号有几位数定，免得两位数把内容挤歪
    final digits = '${list.start + list.items.length - 1}'.length;
    final markerWidth = list.ordered ? 14.0 + digits * 9 : 20.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < list.items.length; i++)
          Padding(
            padding: EdgeInsets.only(top: i == 0 ? 0 : Space.x1),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: markerWidth,
                  child: switch (list.items[i].checked) {
                    null => Text(list.ordered ? '${list.start + i}.' : '•', style: base.copyWith(color: s.subtle)),
                    final on => Padding(
                      // 和第一行文字的中线对齐
                      padding: EdgeInsets.only(top: ((base.fontSize ?? 16) * (base.height ?? 1.5) - 16) / 2),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Icon(
                          on ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
                          size: 16,
                          color: on ? c.accent : c.textFaint,
                          semanticLabel: on ? '已完成' : '未完成',
                        ),
                      ),
                    ),
                  },
                ),
                Expanded(child: MdBlocks(list.items[i].children, style: style)),
              ],
            ),
          ),
      ],
    );
  }
}

class _MdTableView extends StatelessWidget {
  const _MdTableView(this.table);
  final MdTable table;

  @override
  Widget build(BuildContext context) {
    final s = MdScope.of(context).styles;
    final c = s.colors;
    final cols = [table.header.length, for (final r in table.rows) r.length].fold(0, (a, b) => a > b ? a : b);
    if (cols == 0) return const SizedBox.shrink();
    final small = s.base.copyWith(fontSize: (s.base.fontSize ?? 16) - 2, height: 1.45);
    TextAlign alignOf(int i) => switch (i < table.aligns.length ? table.aligns[i] : MdAlign.left) {
      MdAlign.left => TextAlign.left,
      MdAlign.center => TextAlign.center,
      MdAlign.right => TextAlign.right,
    };
    Widget cell(List<MdInline>? inlines, int i, {bool head = false}) => ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: kMdTableCellMaxWidth),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.x3, vertical: Space.x2),
        child: MdRichText(inlines ?? const [], style: head ? small.copyWith(fontWeight: FontWeight.w600) : small, textAlign: alignOf(i)),
      ),
    );
    TableRow row(List<List<MdInline>> cells, {bool head = false}) => TableRow(
      decoration: head ? BoxDecoration(color: s.blockBg) : null,
      children: [for (var i = 0; i < cols; i++) cell(i < cells.length ? cells[i] : null, i, head: head)],
    );
    return Align(
      alignment: Alignment.centerLeft,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(Radii.sm),
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: c.border),
            borderRadius: BorderRadius.circular(Radii.sm),
          ),
          child: SingleChildScrollView(
            key: const Key('md-table-scroll'),
            scrollDirection: Axis.horizontal,
            child: Table(
              defaultColumnWidth: const IntrinsicColumnWidth(),
              defaultVerticalAlignment: TableCellVerticalAlignment.middle,
              border: TableBorder(
                horizontalInside: BorderSide(color: c.border),
                verticalInside: BorderSide(color: c.border),
              ),
              children: [if (table.header.isNotEmpty) row(table.header, head: true), for (final r in table.rows) row(r)],
            ),
          ),
        ),
      ),
    );
  }
}

class _MdDetailsView extends StatefulWidget {
  const _MdDetailsView(this.details);
  final MdDetails details;

  @override
  State<_MdDetailsView> createState() => _MdDetailsViewState();
}

class _MdDetailsViewState extends State<_MdDetailsView> {
  late bool _open = widget.details.open;

  @override
  Widget build(BuildContext context) {
    final s = MdScope.of(context).styles;
    final c = s.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          button: true,
          label: _open ? '收起' : '展开',
          child: InkWell(
            key: const Key('md-details-toggle'),
            borderRadius: BorderRadius.circular(Radii.sm),
            onTap: () => setState(() => _open = !_open),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 36),
              child: Row(
                children: [
                  Icon(_open ? Icons.expand_more : Icons.chevron_right, size: 20, color: c.textMuted),
                  const SizedBox(width: Space.x1),
                  Expanded(child: MdRichText(widget.details.summary, style: s.base.copyWith(fontWeight: FontWeight.w600))),
                ],
              ),
            ),
          ),
        ),
        if (_open)
          Padding(
            padding: const EdgeInsets.only(left: Space.x6, top: Space.x1),
            child: MdBlocks(widget.details.children),
          ),
      ],
    );
  }
}
