// 设计约束（积木盒 · 底部抽屉，390 宽，浅色 + 深色）— 2026-11-24
// - 从上到下三行东西：手柄条（44 高：正中一条小把手，严格水平居中；左边、右边各可以放外面给的东西——
//   编辑器左边放“积木盒”名字（点一下收起 / 展开）和问题数量，右边放撤销、重做、缩放比例。左边那块最宽到把手左边 8 处，不压把手）；
//   一行分类（彩色圆点 + 名字，横着滑，选中的那个整颗填成它的颜色）；下面是这一类的积木。
// - 积木不是文字列表：每一样都用和画布上同一套画法画成真的积木外形（帽子 / 语句 / C 形 / 表达式），小块的并排，放不下换行。
// - 主操作就是“拿一块积木”：按住一块（约 0.18 秒）或直接横着拖，就把它拿出来了（回调交给外面的编辑器接着拖）；
//   上下滑还是翻这一页（这一页没满、翻不动时竖着滑也不会把积木拿出来）。点一下＝快捷添加（回调告诉外面点了哪一样）。
// - 手指一按上去，那块样品就微微缩一下（96%）、暗一点：告诉人“按到了，可以拿”。松手 / 拿走就弹回来。
// - 面板多高由外面说了算（[BlockPaletteView.height]，可以矮到只剩手柄条：里面的东西不挤扁，只是被裁掉）。
//   按住手柄条、或者分类那一行，上下拖＝改高度（只把手势报给外面）；分类那一行横着滑还是翻分类，积木那一片上下滑还是翻积木，互不抢。
//   点一下手柄条（按钮以外的地方）＝外面决定收起还是展开。收到只剩手柄条时，下面两行淡出、点不到。
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:lopicode/blocks/block_geometry.dart';
import 'package:lopicode/blocks/block_host.dart';
import 'package:lopicode/blocks/block_script_view.dart';
import 'package:material_ui/material_ui.dart';

export 'package:lopicode/blocks/block_host.dart' show BlockPaletteKind;

/// 积木盒里的一样东西。
class BlockPaletteItem {
  const BlockPaletteItem(this.kind, this.id, this.layout, {this.preset = const {}});
  final BlockPaletteKind kind;

  /// 帽子模板的 id / 积木的 op / 表达式的 e。
  final String id;

  /// 拿出来时顺手设好的“固定选项”参数（搜到“一块顶多块”里的某一种时有，见 [BlockItemRef.preset]）。
  final Map<String, String> preset;

  /// 样品的排版（拖出来时可以直接拿它画拖着的样子）。
  final BkScriptLayout layout;
}

class BlockPaletteView extends StatefulWidget {
  const BlockPaletteView({
    super.key,
    required this.host,
    this.onPick,
    this.initialCategory,
    this.height = 300,
    this.handleLeading,
    this.handleTrailing,
    this.onHandleTap,
    this.onResizeDown,
    this.onResizeStart,
    this.onResizeUpdate,
    this.onResizeEnd,
    this.onDragStart,
    this.onDragUpdate,
    this.onDragEnd,
    this.onDragCancel,
  });

  /// 手柄条的高度（也是面板收到最矮时露在外面的那一条）。
  static const double handleHeight = 44;

  /// 手柄条 + 分类那一行 + 分隔线：里面的东西至少按这么高排（面板比这矮时下面的被裁掉）。
  static const double headHeight = handleHeight + 48 + 1;

  final BlockHost host;

  /// 点了某一样。
  final void Function(BlockPaletteItem item)? onPick;

  /// 一开始停在哪一类（[BlockCategory.id]）；不给就是第一类。
  final String? initialCategory;

  /// 面板现在多高（外面每一帧给；比 [headHeight] 矮时里面的东西被裁掉，不挤扁）。
  final double height;

  /// 把手多宽；左边那块离把手至少留多少。
  static const double gripWidth = 36;
  static const double gripGap = 8;

  /// 手柄条左边放的东西（编辑器放“积木盒”名字和问题数量）。最宽到把手左边 [gripGap] 处；里面没人接的点按算“点手柄”。
  final Widget? handleLeading;

  /// 手柄条右边放的东西（编辑器放撤销 / 重做 / 缩放）。
  final Widget? handleTrailing;

  /// 点了一下手柄条（按钮以外的地方）。
  final void Function()? onHandleTap;

  /// 手指刚按到手柄条或分类那一行上（还不知道是点还是拖）：面板正滑着的话先停住。
  final void Function()? onResizeDown;

  /// 按住手柄条或分类那一行上下拖：开始；手指又竖着动了多少（往下为正）；松手时的速度（每秒像素，往下为正）。
  final void Function()? onResizeStart;
  final void Function(double dy)? onResizeUpdate;
  final void Function(double velocity)? onResizeEnd;

  /// 把一样东西拿出来了：`global`＝手指在屏幕的哪里；`grab`＝手指离样品左上角多远。之后手指每动一下调 [onDragUpdate]，
  /// 松手调 [onDragEnd]，被系统打断调 [onDragCancel]。
  final void Function(BlockPaletteItem item, Offset global, Offset grab)? onDragStart;
  final void Function(Offset global)? onDragUpdate;
  final void Function()? onDragEnd;
  final void Function()? onDragCancel;

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
    final handleColor = theme.dividerColor;
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    // 收到只剩手柄条时，下面那两行淡出去（屏幕底部有系统手势条时不露半截分类）。
    final shown = ((widget.height - BlockPaletteView.handleHeight - safeBottom) / 40).clamp(0.0, 1.0);
    return Container(
      height: widget.height,
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: kit.palette.dark ? 0.5 : 0.12),
            blurRadius: 16,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Material(
        color: theme.colorScheme.surface,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
        clipBehavior: Clip.antiAlias,
        // 面板被拖矮时里面照原样排、下面的裁掉：不挤扁，也不报溢出。
        child: OverflowBox(
          alignment: Alignment.topCenter,
          minHeight: 0,
          maxHeight: widget.height < BlockPaletteView.headHeight ? BlockPaletteView.headHeight : widget.height,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _resizable(
                key: const ValueKey('bk-palette-handle'),
                onTap: widget.onHandleTap,
                child: SizedBox(
                  height: BlockPaletteView.handleHeight,
                  child: LayoutBuilder(
                    builder: (context, row) => Stack(
                      children: [
                        Center(
                          child: Container(
                            key: const ValueKey('bk-palette-grip'),
                            width: BlockPaletteView.gripWidth,
                            height: 4,
                            decoration: BoxDecoration(color: handleColor, borderRadius: BorderRadius.circular(2)),
                          ),
                        ),
                        if (widget.handleLeading != null)
                          Align(
                            alignment: Alignment.centerLeft,
                            child: ConstrainedBox(
                              constraints: BoxConstraints(maxWidth: math.max(0, row.maxWidth / 2 - BlockPaletteView.gripWidth / 2 - BlockPaletteView.gripGap)),
                              child: widget.handleLeading,
                            ),
                          ),
                        if (widget.handleTrailing != null)
                          // 按钮之间的缝、按不动的按钮：点到了不算“点手柄”。
                          Align(
                            alignment: Alignment.centerRight,
                            child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: () {}, child: widget.handleTrailing),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              Expanded(
                child: IgnorePointer(
                  ignoring: shown <= 0,
                  child: Opacity(
                    opacity: shown,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _resizable(
                          key: const ValueKey('bk-palette-tabs-grip'),
                          child: SizedBox(
                            height: 48,
                            child: ListView.separated(
                              key: const ValueKey('bk-palette-tabs'),
                              scrollDirection: Axis.horizontal,
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                              itemCount: categories.length,
                              separatorBuilder: (_, _) => const SizedBox(width: 6),
                              itemBuilder: (_, i) => _tab(categories[i], identical(categories[i], current)),
                            ),
                          ),
                        ),
                        Divider(height: 1, color: theme.dividerColor),
                        Expanded(
                          child: current == null
                              ? const SizedBox.shrink()
                              : SingleChildScrollView(
                                  key: ValueKey('bk-palette-page-${current.id}'),
                                  // 这一页没满也照样接竖着的滑动：不然竖着滑没人接，会落到样品的“横着拖”手里，把积木误拿出来。
                                  physics: const AlwaysScrollableScrollPhysics(),
                                  padding: EdgeInsets.fromLTRB(16, 14, 16, 20 + safeBottom),
                                  child: Align(
                                    alignment: Alignment.topLeft,
                                    child: Wrap(spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.start, children: [for (final item in _itemsOf(current)) _sample(item)]),
                                  ),
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 按住上下拖＝改面板高度的那两行。只认竖着的拖：横着滑（翻分类）、点（选分类、点按钮）都不拦。
  Widget _resizable({required Key key, required Widget child, VoidCallback? onTap}) {
    if (widget.onResizeUpdate == null && onTap == null) return KeyedSubtree(key: key, child: child);
    return GestureDetector(
      key: key,
      behavior: HitTestBehavior.opaque,
      // 一认出是竖着拖，就把认出来之前走的那一小段也补上：面板上沿贴着手指，不落后一截。
      dragStartBehavior: DragStartBehavior.down,
      onTap: onTap,
      onVerticalDragDown: (_) => widget.onResizeDown?.call(),
      onVerticalDragStart: (_) => widget.onResizeStart?.call(),
      onVerticalDragUpdate: (d) => widget.onResizeUpdate?.call(d.primaryDelta ?? 0),
      onVerticalDragEnd: (d) => widget.onResizeEnd?.call(d.primaryVelocity ?? 0),
      onVerticalDragCancel: () => widget.onResizeEnd?.call(0),
      child: child,
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
    void start(Offset global, Offset local, double boxHeight) {
      // 样品在 40 高的触控范围里是竖着居中的。
      final dy = (boxHeight - item.layout.size.height) / 2;
      widget.onDragStart?.call(item, global, local - Offset(0, dy > 0 ? dy : 0));
    }

    return Builder(
      builder: (box) => RawGestureDetector(
        key: ValueKey('bk-palette-item-${item.kind.name}-${item.id}'),
        behavior: HitTestBehavior.opaque,
        gestures: {
          TapGestureRecognizer: GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(TapGestureRecognizer.new, (r) => r.onTap = widget.onPick == null ? null : () => widget.onPick!(item)),
          if (widget.onDragStart != null) ...{
            LongPressGestureRecognizer: GestureRecognizerFactoryWithHandlers<LongPressGestureRecognizer>(() => LongPressGestureRecognizer(duration: const Duration(milliseconds: 180)), (r) {
              r.onLongPressStart = (d) => start(d.globalPosition, d.localPosition, box.size?.height ?? 0);
              r.onLongPressMoveUpdate = (d) => widget.onDragUpdate?.call(d.globalPosition);
              r.onLongPressEnd = (_) => widget.onDragEnd?.call();
              r.onLongPressCancel = () => widget.onDragCancel?.call();
            }),
            HorizontalDragGestureRecognizer: GestureRecognizerFactoryWithHandlers<HorizontalDragGestureRecognizer>(HorizontalDragGestureRecognizer.new, (r) {
              r.onStart = (d) => start(d.globalPosition, d.localPosition, box.size?.height ?? 0);
              r.onUpdate = (d) => widget.onDragUpdate?.call(d.globalPosition);
              r.onEnd = (_) => widget.onDragEnd?.call();
              r.onCancel = () => widget.onDragCancel?.call();
            }),
          },
        },
        // 小的表达式块也要有 40 高的触控范围。
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 40),
          child: Align(
            alignment: Alignment.centerLeft,
            widthFactor: 1,
            heightFactor: 1,
            child: _PressFeel(child: view),
          ),
        ),
      ),
    );
  }
}

/// 按下态：手指按着的时候缩到 96%、略暗。只是看的，不拦手势。
class _PressFeel extends StatefulWidget {
  const _PressFeel({required this.child});
  final Widget child;

  @override
  State<_PressFeel> createState() => _PressFeelState();
}

class _PressFeelState extends State<_PressFeel> {
  bool _down = false;

  void _set(bool v) {
    if (_down != v && mounted) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    final time = MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 90);
    return Listener(
      onPointerDown: (_) => _set(true),
      onPointerUp: (_) => _set(false),
      onPointerCancel: (_) => _set(false),
      child: AnimatedScale(
        scale: _down ? 0.96 : 1,
        duration: time,
        curve: Curves.easeOut,
        child: AnimatedOpacity(opacity: _down ? 0.82 : 1, duration: time, child: widget.child),
      ),
    );
  }
}
