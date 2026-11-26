// 设计约束（“换成…”小卡片，390 宽，浅色 + 深色）— 2026-11-24
// - 贴着被点的那个槽弹出来的一张小卡片（宽 300 左右，最高 340），不是整页面板；点卡片外面就关。
// - 从上到下：一行分类小圆点标签（只列有“值”可选的分类，横着滑）；下面是这一类的值，每一样都画成真的积木外形，点哪个换哪个。
// - 槽要的是“是 / 否”时，一打开就停在第一个有是非类值的分类上。
// - 最底下是两个小动作（有才显示）：这是一串值里的一项＝“去掉这一项”；槽里已经有拼好的值＝“清空，改回直接填”。
// - 主操作＝点一块积木；没有确定按钮。
import 'dart:math' as math;

import 'package:lopicode/blocks/block_geometry.dart';
import 'package:lopicode/blocks/block_host.dart';
import 'package:lopicode/blocks/block_palette_model.dart';
import 'package:lopicode/blocks/block_script_view.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:material_ui/material_ui.dart';

enum BkReplaceAction { pick, remove, reset }

typedef BkReplaceChoice = ({BkReplaceAction action, String? kind});

/// 弹出“换成…”小卡片。`anchor`＝那个槽在屏幕上的位置。
Future<BkReplaceChoice?> showBlockReplace(
  BuildContext context, {
  required BlockHost host,
  required BkKit kit,
  required Rect anchor,
  bool wantBoolean = false,
  bool canRemove = false,
  bool canReset = false,
}) {
  return showGeneralDialog<BkReplaceChoice>(
    context: context,
    barrierDismissible: true,
    barrierLabel: '关闭',
    barrierColor: context.colors.scrimOf(0.18),
    transitionDuration: const Duration(milliseconds: 140),
    transitionBuilder: (context, anim, _, child) => FadeTransition(
      opacity: anim,
      child: ScaleTransition(
        scale: Tween(begin: 0.94, end: 1.0).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
        child: child,
      ),
    ),
    pageBuilder: (context, _, _) => BlockReplaceView(host: host, kit: kit, anchor: anchor, wantBoolean: wantBoolean, canRemove: canRemove, canReset: canReset),
  );
}

class BlockReplaceView extends StatefulWidget {
  const BlockReplaceView({super.key, required this.host, required this.kit, required this.anchor, this.wantBoolean = false, this.canRemove = false, this.canReset = false});

  final BlockHost host;
  final BkKit kit;
  final Rect anchor;
  final bool wantBoolean;
  final bool canRemove;
  final bool canReset;

  @override
  State<BlockReplaceView> createState() => _BlockReplaceViewState();
}

class _BlockReplaceViewState extends State<BlockReplaceView> {
  late final List<BlockCategory> _categories = [
    for (final c in bkAllCategories(widget.host))
      if (c.allExprs.isNotEmpty) c,
  ];
  late String? _category = _first();
  final Map<String, List<(String, BkScriptLayout)>> _samples = {};

  String? _first() {
    if (_categories.isEmpty) return null;
    if (widget.wantBoolean) {
      for (final c in _categories) {
        if (c.allExprs.any((e) => widget.host.isBooleanExpr(widget.host.newExpr(e)))) return c.id;
      }
    }
    return _categories.first.id;
  }

  List<(String, BkScriptLayout)> _of(BlockCategory c) => _samples[c.id] ??= () {
    final engine = widget.kit.engine(widget.host);
    final kinds = [...c.allExprs];
    // 要“是 / 否”的槽：是非类的排前面。
    if (widget.wantBoolean) {
      final yes = [
        for (final k in kinds)
          if (widget.host.isBooleanExpr(widget.host.newExpr(k))) k,
      ];
      kinds
        ..removeWhere(yes.contains)
        ..insertAll(0, yes);
    }
    return [for (final k in kinds) (k, engine.layoutExpr(widget.host.newExpr(k), controls: false))];
  }();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final media = MediaQuery.of(context);
    final screen = media.size;
    final width = math.min(304.0, screen.width - 24);
    const maxH = 340.0;
    final a = widget.anchor;
    final safeTop = media.padding.top + 8, safeBottom = screen.height - media.viewInsets.bottom - media.padding.bottom - 8;
    final below = safeBottom - a.bottom - 6, above = a.top - 6 - safeTop;
    final under = below >= 220 || below >= above;
    final height = math.max(160.0, math.min(maxH, under ? below : above));
    final left = (a.left - 8).clamp(12.0, math.max(12.0, screen.width - width - 12)).toDouble();
    final top = under ? a.bottom + 6 : math.max(safeTop, a.top - 6 - height);
    final current = _categories.isEmpty ? null : _categories.firstWhere((x) => x.id == _category, orElse: () => _categories.first);
    return Stack(
      children: [
        Positioned(
          left: left,
          top: top,
          width: width,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: height),
            child: Material(
              key: const ValueKey('bk-replace'),
              color: c.surface,
              elevation: 12,
              borderRadius: BorderRadius.circular(16),
              clipBehavior: Clip.antiAlias,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 10, 14, 2),
                    child: Text(
                      '换成…',
                      style: t.labelMedium?.copyWith(color: c.textMuted, fontWeight: FontWeight.w600),
                    ),
                  ),
                  SizedBox(
                    height: 40,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      itemCount: _categories.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 4),
                      itemBuilder: (_, i) => _tab(_categories[i], identical(_categories[i], current)),
                    ),
                  ),
                  Divider(height: 1, color: c.border),
                  if (current != null)
                    Flexible(
                      child: SingleChildScrollView(
                        key: ValueKey('bk-replace-page-${current.id}'),
                        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                        child: Align(
                          alignment: Alignment.topLeft,
                          child: Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: [
                              for (final (kind, layout) in _of(current))
                                GestureDetector(
                                  key: ValueKey('bk-replace-$kind'),
                                  behavior: HitTestBehavior.opaque,
                                  onTap: () => Navigator.pop<BkReplaceChoice>(context, (action: BkReplaceAction.pick, kind: kind)),
                                  child: ConstrainedBox(
                                    constraints: const BoxConstraints(minHeight: 36),
                                    child: Align(
                                      alignment: Alignment.centerLeft,
                                      widthFactor: 1,
                                      heightFactor: 1,
                                      child: FittedBox(
                                        fit: BoxFit.scaleDown,
                                        alignment: Alignment.centerLeft,
                                        child: BkLayoutView(layout: layout, kit: widget.kit),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  if (widget.canRemove || widget.canReset) ...[
                    Divider(height: 1, color: c.border),
                    InkWell(
                      key: ValueKey(widget.canRemove ? 'bk-replace-remove' : 'bk-replace-reset'),
                      onTap: () => Navigator.pop<BkReplaceChoice>(context, (action: widget.canRemove ? BkReplaceAction.remove : BkReplaceAction.reset, kind: null)),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        child: Row(
                          children: [
                            Icon(widget.canRemove ? Icons.remove_circle_outline_rounded : Icons.backspace_outlined, size: 18, color: c.danger),
                            const SizedBox(width: 8),
                            Text(widget.canRemove ? '去掉这一项' : '清空，改回直接填', style: t.bodyMedium?.copyWith(color: c.danger)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _tab(BlockCategory cat, bool selected) {
    final tone = widget.kit.palette.tone(cat.colorKey);
    final t = Theme.of(context).textTheme;
    return GestureDetector(
      key: ValueKey('bk-replace-tab-${cat.id}'),
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _category = cat.id),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(color: selected ? tone.fill : Colors.transparent, borderRadius: BorderRadius.circular(16)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: selected ? tone.text : tone.fill, shape: BoxShape.circle),
            ),
            const SizedBox(width: 5),
            Text(
              cat.label,
              style: t.bodySmall?.copyWith(fontWeight: FontWeight.w600, color: selected ? tone.text : t.bodyMedium?.color),
            ),
          ],
        ),
      ),
    );
  }
}
