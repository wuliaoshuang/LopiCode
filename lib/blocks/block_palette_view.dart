// 设计约束（积木盒 · 底部抽屉，390 宽，浅色 + 深色）— 2026-11-24
// - 从上到下三行东西：一条小把手；一行分类（彩色圆点 + 名字，横着滑，选中的那个整颗填成它的颜色）；下面是这一类的积木。
// - 积木不是文字列表：每一样都用和画布上同一套画法画成真的积木外形（帽子 / 语句 / C 形 / 表达式），小块的并排，放不下换行。
// - 这一版只做展示和点选（回调告诉外面点了哪一样）；“拖出来”由画布那边接。
// - 主操作就是“拿一块积木”，没有别的按钮。
import 'package:lopicode/blocks/block_geometry.dart';
import 'package:lopicode/blocks/block_host.dart';
import 'package:lopicode/blocks/block_script_view.dart';
import 'package:material_ui/material_ui.dart';

enum BlockPaletteKind { hat, block, expr }

/// 积木盒里的一样东西。
class BlockPaletteItem {
  const BlockPaletteItem(this.kind, this.id, this.layout);
  final BlockPaletteKind kind;

  /// 帽子模板的 id / 积木的 op / 表达式的 e。
  final String id;

  /// 样品的排版（拖出来时可以直接拿它画拖着的样子）。
  final BkScriptLayout layout;
}

class BlockPaletteView extends StatefulWidget {
  const BlockPaletteView({super.key, required this.host, this.onPick, this.initialCategory, this.height = 300});

  final BlockHost host;

  /// 点了某一样。
  final void Function(BlockPaletteItem item)? onPick;

  /// 一开始停在哪一类（[BlockCategory.id]）；不给就是第一类。
  final String? initialCategory;
  final double height;

  @override
  State<BlockPaletteView> createState() => _BlockPaletteViewState();
}

class _BlockPaletteViewState extends State<BlockPaletteView> with BkKitHolder {
  late String? _category = widget.initialCategory;
  final Map<String, List<BlockPaletteItem>> _items = {};
  int _rev = -1;

  @override
  void kitChanged() => _items.clear();

  @override
  void didUpdateWidget(BlockPaletteView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.host, widget.host)) _items.clear();
  }

  /// 这一类的样品。宿主内容变了要重排（默认参数会跟着变：第一个变量、第一个控件…）。
  List<BlockPaletteItem> _itemsOf(BlockCategory c) {
    if (_rev != widget.host.revision) {
      _items.clear();
      _rev = widget.host.revision;
    }
    return _items[c.id] ??= () {
      final host = widget.host;
      final engine = kit.engine(host);
      return [
        for (final h in c.hats) BlockPaletteItem(BlockPaletteKind.hat, h.id, engine.layoutHat(h.hat)),
        for (final op in c.blocks) BlockPaletteItem(BlockPaletteKind.block, op, engine.layoutStack([host.newBlock(op)])),
        for (final e in c.exprs) BlockPaletteItem(BlockPaletteKind.expr, e, engine.layoutExpr(host.newExpr(e))),
      ];
    }();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final categories = [
      for (final c in widget.host.categories)
        if (!c.isEmpty) c,
    ];
    final current = categories.isEmpty ? null : categories.firstWhere((c) => c.id == _category, orElse: () => categories.first);
    return Container(
      height: widget.height,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: kit.palette.dark ? 0.5 : 0.12),
            blurRadius: 16,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 8, bottom: 4),
              width: 36,
              height: 4,
              decoration: BoxDecoration(color: theme.dividerColor, borderRadius: BorderRadius.circular(2)),
            ),
          ),
          SizedBox(
            height: 48,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              itemCount: categories.length,
              separatorBuilder: (_, _) => const SizedBox(width: 6),
              itemBuilder: (_, i) => _tab(categories[i], identical(categories[i], current)),
            ),
          ),
          Divider(height: 1, color: theme.dividerColor),
          Expanded(
            child: current == null
                ? const SizedBox.shrink()
                : SingleChildScrollView(
                    key: ValueKey('bk-palette-page-${current.id}'),
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: Wrap(spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.start, children: [for (final item in _itemsOf(current)) _sample(item)]),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _tab(BlockCategory c, bool selected) {
    final tone = kit.palette.tone(c.colorKey);
    final theme = Theme.of(context);
    return GestureDetector(
      key: ValueKey('bk-palette-tab-${c.id}'),
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _category = c.id),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(color: selected ? tone.fill : Colors.transparent, borderRadius: BorderRadius.circular(20)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: selected ? tone.text : tone.fill, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Text(
              c.label,
              style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600, color: selected ? tone.text : theme.textTheme.bodyMedium?.color),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sample(BlockPaletteItem item) {
    final view = BkLayoutView(layout: item.layout, kit: kit);
    return GestureDetector(
      key: ValueKey('bk-palette-item-${item.kind.name}-${item.id}'),
      behavior: HitTestBehavior.opaque,
      onTap: widget.onPick == null ? null : () => widget.onPick!(item),
      // 小的表达式块也要有 40 高的触控范围。
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 40),
        child: Align(alignment: Alignment.centerLeft, widthFactor: 1, heightFactor: 1, child: view),
      ),
    );
  }
}
