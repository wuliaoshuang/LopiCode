// 设计约束（添加积木面板 · 390×844）— 2026-11-24
// - 顶上一行分类标签（变量 / 控件 / 流程 / 交互 / 网络），可横向滑；下面是这一类的积木。
// - 一行一种积木：左边一个和积木同色的小色块，中文名，下面一行弱化的说明。点了就加进去并关掉面板。
// - 没有别的操作：加到哪（选中积木的下面 / 某个子栈 / 处理末尾）在打开面板之前就定了，写在标题下面。
import 'package:lopicode/lowcode/logic_block_widgets.dart';
import 'package:lopicode/lowcode/logic_blocks.dart';
import 'package:lopicode/lowcode/logic_pick_sheet.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:material_ui/material_ui.dart';

/// 选一种要加的积木；返回它的 op，取消返回 null。[where] 是一句“会加到哪”的说明。
Future<String?> showLcPalette(BuildContext context, {String? where}) => showLcSheet<String>(context, (_) => LcPaletteSheet(where: where));

class LcPaletteSheet extends StatefulWidget {
  const LcPaletteSheet({super.key, this.where});
  final String? where;

  @override
  State<LcPaletteSheet> createState() => _LcPaletteSheetState();
}

class _LcPaletteSheetState extends State<LcPaletteSheet> {
  String _category = lcBlockCategories.first;

  @override
  Widget build(BuildContext context) {
    final tone = lcToneOf(context, _category);
    return LcSheetFrame(
      title: '添加积木',
      note: widget.where,
      header: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(Space.x4, 0, Space.x4, Space.x1),
        child: Row(
          children: [
            for (final category in lcBlockCategories)
              Padding(
                padding: const EdgeInsets.only(right: Space.x2),
                child: LcChoiceChip(
                  key: ValueKey('lc-palette-cat-$category'),
                  avatar: _Swatch(tone: lcToneOf(context, category), size: 14),
                  label: category,
                  selected: category == _category,
                  onSelected: () => setState(() => _category = category),
                ),
              ),
          ],
        ),
      ),
      children: [
        for (final spec in blockSpecsIn(_category))
          LcOptionRow(
            key: ValueKey('lc-palette-${spec.op}'),
            leading: _Swatch(tone: tone, size: 32, c: spec.hasBody),
            label: spec.label,
            detail: spec.hint,
            onTap: () => Navigator.pop(context, spec.op),
          ),
      ],
    );
  }
}

/// 小色块：和积木一个颜色、左边一条粗边；能装积木的那种（[c]）右下缺一块，像个 C。
class _Swatch extends StatelessWidget {
  const _Swatch({required this.tone, required this.size, this.c = false});
  final LcTone tone;
  final double size;
  final bool c;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(size / 4),
    child: SizedBox(
      width: size,
      height: size,
      child: Stack(
        children: [
          Positioned.fill(child: ColoredBox(color: tone.fill)),
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: size / 6,
            child: ColoredBox(color: tone.edge),
          ),
          if (c)
            Positioned(
              right: 0,
              top: size * 0.4,
              bottom: size * 0.25,
              left: size * 0.4,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Theme.of(context).bottomSheetTheme.backgroundColor ?? context.colors.surface,
                  borderRadius: BorderRadius.horizontal(left: Radius.circular(size / 10)),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}
