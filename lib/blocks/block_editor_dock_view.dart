// 设计约束（积木编辑器底部那块可以上下拖的面板，390 宽，浅色 + 深色）— 2026-11-24
// - 面板＝积木盒。按住最上面的手柄条（或分类那一行）上下拖，面板上沿跟着手指走，画布露出来的部分跟着变。
// - 最矮：只剩手柄条（44 高，屏幕底部有系统手势条时再加上它）。最高：顶到状态栏下沿，盖住页面的悬浮顶栏——手柄条还在最上面，随时能拖回来。
// - 松手：甩得快（≥ 700 像素 / 秒）去甩的方向上的下一档（收起 / 默认 / 全展开）；慢慢放下时离某一档不到 28 就吸过去，否则就停在放手的地方。
//   去某一档是 260 毫秒、带一点点过冲的滑动（滑到一半手指按上手柄＝停在那里，可以接着拖）；系统开了“减弱动态效果”就直接到位。点一下手柄条：收起 ⇄ 默认（比默认高时点一下回默认）。
// - 手柄条右边一行三样：撤销、重做、缩放比例（点一下回 100%）。画布上不再有常驻的浮条。面板收到只剩手柄条时它们还在。
// - 手柄条左边（2026-11-24 真机反馈“这个位置太空了”）。层级：把手（正中，怎么拖）＞ 名字“积木盒”＋箭头（这是什么、点一下收起 / 展开）
//   ＞ 问题数量（有问题才出现，点了开问题列表）。左右两组都是次要的：名字用正文色 600 字重，箭头、缩放比例用次要色。
//   取值都来自 tokens：字号 bodyMedium / bodySmall，间距 4 / 8 / 12，颜色 text / textMuted / danger(Soft) / warning(Soft)。
//   箭头：收起时朝上（点了展开），其余朝下。问题数量不只靠颜色：有错误是 ⓘ 形图标 + 红，只有警告是三角图标 + 黄。
//   两样都至少 44×44；从它们身上竖着拖还是拖面板。
// - 要往画布上放东西的时候面板自己让开：开始拖积木（从积木盒拿、或拖画布上的）、点积木盒快捷添加时，面板比默认档高就滑回默认档。
// - 拖画布上的积木时底部换成垃圾桶条：和面板一样高，但不矮于 96（面板收起时也有地方可扔）。
import 'dart:async';
import 'dart:math' as math;

import 'package:lopicode/blocks/block_dock.dart';
import 'package:lopicode/blocks/block_editor_canvas_view.dart';
import 'package:lopicode/blocks/block_editor_drag_view.dart';
import 'package:lopicode/blocks/block_editor_edit_view.dart';
import 'package:lopicode/blocks/block_editor_view.dart';
import 'package:lopicode/blocks/block_palette_view.dart';
import 'package:lopicode/blocks/block_script_view.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:material_ui/material_ui.dart';

mixin BkEditorDock on State<BlockEditorView>, BkKitHolder<BlockEditorView>, TickerProvider, BkEditorCanvas, BkEditorDrag, BkEditorEdit {
  /// 滑到某一档多久、怎么滑（末尾过冲约 5%，像被弹了一下）。
  static const Duration dockSnapTime = Duration(milliseconds: 260);
  static const Curve dockSnapCurve = Cubic(0.34, 1.26, 0.64, 1);

  /// 垃圾桶条最矮多高（不算屏幕底部的系统手势条）。
  static const double trashMinHeight = 96;

  /// 提示条、空画布引导至少要这么高的画布才放得下。
  static const double toastRoom = 64;
  static const double guideRoom = 170;

  BkDockStops dockStops = const BkDockStops(collapsed: BlockPaletteView.handleHeight, normal: 248, full: 248);
  double _safeBottom = 0;

  /// 面板现在多高；null＝还没定（第一次排的时候取记住的，或默认档）。
  double? _dockH;

  /// 停在全展开：屏幕高度变了也跟着顶到头。
  bool _dockFull = false;

  /// 手指按下以后一共竖着走了多少算出来的高度（可以出界；面板显示的是夹到界内的）。
  double _dockRaw = 0;

  /// 手指正按着手柄拖。
  bool dockResizing = false;

  late final AnimationController _dockAnim = AnimationController.unbounded(vsync: this)..addListener(_dockTick);

  /// 面板（积木盒）现在多高。
  double get panelHeight => dockStops.clamp(_dockFull && !_dockAnim.isAnimating ? dockStops.full : (_dockH ?? dockStops.normal));

  /// 面板收到只剩手柄条了。
  bool get paletteCollapsed => dockStops.isCollapsed(panelHeight);

  /// 拖画布上的积木时，底部垃圾桶条多高。
  double get trashHeight => math.min(math.max(panelHeight, trashMinHeight + _safeBottom), math.max(dockStops.full, dockStops.collapsed));

  @override
  double get dockHeight {
    if (editing != null) return 0;
    final d = drag;
    return d != null && !d.isNew ? trashHeight : panelHeight;
  }

  /// 每次搭界面时算一遍三档。`area`＝状态栏下沿到编辑器下沿一共多高；`safeBottom`＝屏幕底部系统手势条多高。
  void layoutDock({required double area, required double safeBottom}) {
    _safeBottom = safeBottom;
    // 就地改字时面板不在：手柄上没松开的拖动作废。
    if (editing != null) dockResizing = false;
    dockStops = BkDockStops.of(handle: BlockPaletteView.handleHeight, normal: widget.paletteHeight, area: area, bottomInset: safeBottom);
    if (_dockH != null) return;
    final seen = BkDockMemory.of(widget.dockMemoryKey);
    _dockH = dockStops.clamp(seen?.height ?? dockStops.normal);
    _dockFull = seen?.full ?? false;
  }

  /// 手指按到手柄上了：面板正滑着就停在这里（手柄不从手指底下溜走）。
  void dockHold() {
    if (!_dockAnim.isAnimating) return;
    final h = dockStops.clamp(_dockAnim.value);
    _dockAnim.stop();
    BkDockMemory.remember(widget.dockMemoryKey, h, full: dockStops.isFull(h));
    setState(() {
      _dockH = h;
      _dockFull = dockStops.isFull(h);
    });
  }

  void dockResizeStart() {
    final h = panelHeight;
    _dockAnim.stop();
    setState(() {
      dockResizing = true;
      _dockFull = false;
      _dockH = _dockRaw = h;
    });
  }

  /// `dy`＝手指又竖着走了多少（往下为正）。
  void dockResizeUpdate(double dy) {
    if (!dockResizing) return;
    _dockRaw -= dy;
    setState(() => _dockH = dockStops.clamp(_dockRaw));
  }

  /// `velocity`＝松手时的速度（每秒像素，往下为正）。
  void dockResizeEnd(double velocity) {
    if (!dockResizing) return;
    dockResizing = false;
    _dockTo(dockStops.rest(panelHeight, velocity));
  }

  /// 点了一下手柄条。
  void dockToggle() => _dockTo(dockStops.toggled(panelHeight));

  @override
  void dockYield() {
    // 另一根手指正拖着手柄：那次拖动到此为止（接下来底部可能换成垃圾桶条，手柄的手势收不到“结束”）。
    dockResizing = false;
    final to = _dockAnim.isAnimating ? _dockGoal : panelHeight;
    if (to > dockStops.normal + 1) _dockTo(dockStops.normal);
  }

  double _dockGoal = 0;

  void _dockTo(double target) {
    final from = panelHeight;
    final to = dockStops.clamp(target);
    _dockAnim.stop();
    _dockGoal = to;
    final full = dockStops.isFull(to);
    BkDockMemory.remember(widget.dockMemoryKey, to, full: full);
    if (reduceMotion || (to - from).abs() < 0.5) {
      setState(() {
        _dockH = to;
        _dockFull = full;
      });
      return;
    }
    setState(() {
      _dockH = from;
      _dockFull = full;
    });
    _dockAnim.value = from;
    unawaited(_dockAnim.animateTo(to, duration: dockSnapTime, curve: dockSnapCurve));
  }

  void _dockTick() {
    if (!mounted || dockResizing) return;
    setState(() => _dockH = dockStops.clamp(_dockAnim.value));
  }

  void disposeDock() => _dockAnim.dispose();

  /// 画布露出来的那一段的正中（编辑区坐标）：缩放绕着它。
  Offset get canvasCenter => Offset(viewSize.width / 2, coveredTop + math.max(0, viewSize.height - coveredTop - dockHeight) / 2);

  /// 手柄条右边的三样：撤销、重做、缩放比例。
  Widget buildDockTools(BuildContext context, {required VoidCallback? onUndo, required VoidCallback? onRedo}) {
    final c = context.colors;
    Widget button(String key, IconData icon, String tip, VoidCallback? onTap) => IconButton(
      key: ValueKey(key),
      tooltip: tip,
      onPressed: onTap,
      icon: Icon(icon, size: 20),
      color: c.text,
      disabledColor: c.textMuted.withValues(alpha: 0.4),
      constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
    );
    return Row(
      key: const ValueKey('bk-tools'),
      mainAxisSize: MainAxisSize.min,
      children: [
        button('bk-undo', Icons.undo_rounded, '撤销', onUndo),
        button('bk-redo', Icons.redo_rounded, '重做', onRedo),
        Tooltip(
          message: '回到 100%',
          child: InkWell(
            key: const ValueKey('bk-zoom'),
            customBorder: const StadiumBorder(),
            onTap: () => setState(() => setZoom(1, canvasCenter)),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 52, minHeight: BlockPaletteView.handleHeight),
              child: Center(
                widthFactor: 1,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(6, 0, 12, 0),
                  child: Text(
                    '${(zoom * 100).round()}%',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: c.textMuted, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// 手柄条左边的两样：名字（点一下收起 / 展开）、问题数量（有问题才有，点了开问题列表）。
  Widget buildDockLead(BuildContext context, {required VoidCallback onIssues}) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    final collapsed = paletteCollapsed;
    final errors = issues.where((i) => i.isError).length;
    final tone = errors > 0 ? c.danger : c.warning;
    return Row(
      key: const ValueKey('bk-dock-lead'),
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Semantics(
            button: true,
            label: collapsed ? '展开积木盒' : '收起积木盒',
            excludeSemantics: true,
            child: InkWell(
              key: const ValueKey('bk-dock-title'),
              customBorder: const StadiumBorder(),
              onTap: dockToggle,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 44, minHeight: BlockPaletteView.handleHeight),
                child: Padding(
                  padding: const EdgeInsets.only(left: 12, right: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AnimatedRotation(
                        turns: collapsed ? 0 : 0.5,
                        duration: reduceMotion ? Duration.zero : const Duration(milliseconds: 160),
                        child: Icon(Icons.keyboard_arrow_up_rounded, key: ValueKey(collapsed ? 'bk-dock-arrow-up' : 'bk-dock-arrow-down'), size: 20, color: c.textMuted),
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          '积木盒',
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.fade,
                          style: text.bodyMedium?.copyWith(color: c.text, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        if (issues.isNotEmpty)
          Tooltip(
            message: '${issues.length} 个问题',
            child: InkWell(
              key: const ValueKey('bk-dock-issues'),
              customBorder: const StadiumBorder(),
              onTap: onIssues,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 44, minHeight: BlockPaletteView.handleHeight),
                child: Center(
                  widthFactor: 1,
                  child: Container(
                    height: 24,
                    padding: const EdgeInsets.only(left: 6, right: 8),
                    decoration: ShapeDecoration(color: errors > 0 ? c.dangerSoft : c.warningSoft, shape: const StadiumBorder()),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(errors > 0 ? Icons.error_outline_rounded : Icons.warning_amber_rounded, size: 14, color: tone),
                        const SizedBox(width: 4),
                        Text(
                          issues.length > 99 ? '99+' : '${issues.length}',
                          style: text.bodySmall?.copyWith(color: tone, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
