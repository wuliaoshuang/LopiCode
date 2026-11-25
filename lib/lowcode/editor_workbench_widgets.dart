// 设计约束（低代码 · 搭建台 · 390×844）——页面搭建和“编辑自定义组件”共用的那一整块（顶栏以下）
// - 从上到下：画布（主角，铺满）→ 选中条（48 高，选中了组件才有）→ 工具条（56 高，固定在最底下，拇指够得着）。
//     工具条：[＋添加]（实心，主操作）在左；右边一排图标 [图层][撤销][重做][预览]（预览可以没有）。一行只做这一件事。
//     选中条：左边图标＋名字，右边是这个组件能做的事（由页面传进来，见 [EditorSelectionBar]）。
// - 组件盒（palette_widgets.dart）贴着工具条上沿盖在画布上：点“添加”打开 / 关上；它开着时画布底下留出手柄那一条。
// - 拖组件（画布上长按、组件盒里长按，手感一样：280 毫秒、拿起来震一下）都归这里管：
//     画布只负责算落点、画蓝线；手指下面的半透明缩略图画在最上面一层；
//     拖动时工具条换成“拖到这里删除”（从组件盒拖出来的新组件是“拖到这里取消”），手指进去变红；
//     经过一个新的可放位置轻震一下，放下轻震，丢进删除区重震。
//   拖动时别的都不动：选中条不收（只是变淡、点不了）、画布不变高——页面一个像素都不跳。
// - 第 2 期往这里加东西的口子：选中条的按钮是传进来的一串控件；工具条右边那排图标可以加 [toolbarExtra]。
import 'package:lopicode/lowcode/canvas_drag_widgets.dart';
import 'package:lopicode/lowcode/canvas_view.dart';
import 'package:lopicode/lowcode/lift_gesture_widgets.dart';
import 'package:lopicode/lowcode/model.dart';
import 'package:lopicode/lowcode/palette_catalog.dart';
import 'package:lopicode/lowcode/palette_widgets.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/top_bar.dart';
import 'package:material_ui/material_ui.dart';

/// 工具条多高。
const double kEditorToolbarHeight = 56;

/// 选中条多高。
const double kEditorSelectionBarHeight = 48;

class EditorWorkbench extends StatefulWidget {
  const EditorWorkbench({
    super.key,
    required this.doc,
    required this.selected,
    required this.onSelect,
    required this.onAdd,
    required this.onDrop,
    required this.canDrop,
    required this.onDelete,
    required this.onResize,
    required this.recents,
    required this.onLayers,
    required this.onUndo,
    required this.onRedo,
    this.canDelete,
    this.onPreview,
    this.selectionBar,
    this.toolbarExtra = const [],
    this.presetWidth = 0,
    this.showBoxModel = true,
  });

  final LcDocument doc;
  final String? selected;
  final void Function(String? id) onSelect;

  /// 点了组件盒里的一个组件：加进页面，返回新组件的 id（没加成返回 null）。
  final String? Function(String type, String? ref) onAdd;

  /// 拖着的东西放下了：新组件插进去 / 已有的挪过去。
  final void Function(LcDrag drag, String parentId, int index) onDrop;
  final bool Function(LcDrag drag, String parentId) canDrop;

  /// 把画布上的组件拖进了删除区。
  final void Function(String nodeId) onDelete;

  /// 这个组件能不能拖进删除区（不给＝都能）。
  final bool Function(String nodeId)? canDelete;
  final void Function(String id, int? width, int? height) onResize;

  /// “常用”：最近用过的组件。
  final PaletteRecents recents;

  final VoidCallback onLayers;

  /// 撤销 / 重做；null＝现在不能点。
  final VoidCallback? onUndo;
  final VoidCallback? onRedo;

  /// 预览；null＝工具条上没有这个按钮。
  final VoidCallback? onPreview;

  /// 选中条（选中了组件时由页面给出来；一般就是一个 [EditorSelectionBar]）。
  final Widget? selectionBar;

  /// 工具条右边那排图标前面再加的东西。
  final List<Widget> toolbarExtra;

  final int presetWidth;
  final bool showBoxModel;

  @override
  State<EditorWorkbench> createState() => EditorWorkbenchState();
}

class EditorWorkbenchState extends State<EditorWorkbench> {
  final GlobalKey<CanvasViewState> _canvasKey = GlobalKey();
  final GlobalKey<PalettePanelState> _paletteKey = GlobalKey();
  final GlobalKey _zoneKey = GlobalKey();
  bool _paletteOpen = false;

  // 正在拖的东西；手指位置和“在不在删除区上”单独通知，不让整块跟着重搭。
  LcDrag? _drag;
  Widget? _ghost;
  final ValueNotifier<Offset?> _finger = ValueNotifier(null);
  final ValueNotifier<bool> _overZone = ValueNotifier(false);

  /// 画布（缩放、适应屏幕、量位置都找它）。
  CanvasViewState? get canvas => _canvasKey.currentState;

  /// 组件盒（没打开是 null）。
  PalettePanelState? get palette => _paletteKey.currentState;

  bool get paletteOpen => _paletteOpen;
  bool get dragging => _drag != null;

  void togglePalette() => setState(() {
    final p = palette;
    if (_paletteOpen && p != null && p.collapsed) {
      p.expand(); // 只剩手柄时再点“添加”＝拉回默认高度
    } else {
      _paletteOpen = !_paletteOpen;
    }
  });

  @override
  void dispose() {
    _finger.dispose();
    _overZone.dispose();
    super.dispose();
  }

  // ───────────── 点一下添加 ─────────────

  void _tapAdd(PaletteEntry e) {
    final id = widget.onAdd(e.type, e.ref);
    if (id == null) return;
    widget.recents.touch(e.key);
    palette?.collapse();
    // 等新组件排出来再滚过去。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) canvas?.revealNode(id);
    });
  }

  // ───────────── 拖 ─────────────

  void _lift(LcDrag drag, Offset global) {
    final cv = canvas;
    if (cv == null || _drag != null || !cv.beginDrag(drag)) return;
    LcHaptics.lift();
    palette?.collapse();
    final moving = drag.nodeId;
    final rect = moving == null ? null : cv.nodeScreenRect(moving);
    _overZone.value = false;
    _finger.value = global;
    setState(() {
      _drag = drag;
      _ghost = buildDragGhost(widget.doc, drag, layoutWidth: rect == null ? cv.pageWidth : rect.width / cv.scale);
    });
    _move(global, quiet: true); // 刚拿起：只算落点，不再多震一下
  }

  bool _inZone(Offset global) {
    final box = _zoneKey.currentContext?.findRenderObject();
    return box is RenderBox && box.hasSize && global.dy >= box.localToGlobal(Offset.zero).dy;
  }

  void _move(Offset global, {bool quiet = false}) {
    final cv = canvas;
    if (_drag == null || cv == null) return;
    _finger.value = global;
    final before = cv.dropTarget;
    if (_inZone(global)) {
      cv.dragAway();
      if (!_overZone.value) LcHaptics.overTarget();
      _overZone.value = true;
      return;
    }
    _overZone.value = false;
    final now = cv.dragMove(global);
    if (!quiet && now != null && !now.noop && !now.sameSpot(before)) LcHaptics.overTarget();
  }

  void _end({required bool cancelled}) {
    final drag = _drag;
    if (drag == null) return;
    final target = canvas?.finishDrag();
    final over = _overZone.value;
    _finger.value = null;
    _overZone.value = false;
    setState(() {
      _drag = null;
      _ghost = null;
    });
    if (cancelled) return;
    final moving = drag.nodeId;
    if (over) {
      if (moving != null && (widget.canDelete?.call(moving) ?? true)) {
        LcHaptics.delete();
        widget.onDelete(moving);
      }
      return;
    }
    if (target == null || target.noop) return;
    LcHaptics.drop();
    widget.onDrop(drag, target.parentId, target.index);
    final ref = drag.ref, type = drag.type;
    if (type != null) widget.recents.touch(ref == null ? type : 'component:$ref');
  }

  // ───────────── 界面 ─────────────

  @override
  Widget build(BuildContext context) {
    final topInset = PageBar.insetOf(context);
    final drag = _drag;
    return Stack(
      children: [
        Column(
          children: [
            Expanded(
              child: LayoutBuilder(
                builder: (context, box) => Stack(
                  children: [
                    Positioned.fill(
                      child: CanvasView(
                        key: _canvasKey,
                        doc: widget.doc,
                        selected: widget.selected,
                        onSelect: widget.onSelect,
                        canDrop: widget.canDrop,
                        onResize: widget.onResize,
                        onLift: _lift,
                        onLiftMove: _move,
                        onLiftDrop: () => _end(cancelled: false),
                        onLiftCancel: () => _end(cancelled: true),
                        presetWidth: widget.presetWidth,
                        showBoxModel: widget.showBoxModel,
                        topInset: topInset,
                        bottomInset: _paletteOpen ? kPaletteHandleHeight : 0,
                      ),
                    ),
                    if (_paletteOpen)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: PalettePanel(
                          key: _paletteKey,
                          entries: paletteEntries(widget.doc.components),
                          recent: widget.recents.keys,
                          maxHeight: (box.maxHeight - topInset).clamp(kPaletteHandleHeight, double.infinity).toDouble(),
                          onTap: _tapAdd,
                          onLift: (e, at) => _lift(e.ref == null ? LcDrag.fresh(e.type) : LcDrag.component(e.ref!), at),
                          onLiftMove: _move,
                          onLiftDrop: () => _end(cancelled: false),
                          onLiftCancel: () => _end(cancelled: true),
                          onClose: () => setState(() => _paletteOpen = false),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            // 拖动时选中条留在原地（页面不跳），但变淡、点不了：手里拿着东西时它那几个按钮用不上
            if (widget.selectionBar != null)
              IgnorePointer(
                ignoring: drag != null,
                child: Opacity(key: const ValueKey('lc-selection-bar-wrap'), opacity: drag == null ? 1 : 0.4, child: widget.selectionBar),
              ),
            KeyedSubtree(key: _zoneKey, child: drag == null ? _toolbar(context) : _dropZone(context, drag)),
          ],
        ),
        // 手指下面的缩略图：在手指的正上方一点，不被手指挡住
        if (_ghost != null)
          Positioned.fill(
            child: IgnorePointer(
              child: ValueListenableBuilder<Offset?>(
                valueListenable: _finger,
                child: _ghost,
                builder: (context, at, child) {
                  final box = context.findRenderObject();
                  if (at == null || box is! RenderBox || !box.hasSize) return const SizedBox.shrink();
                  final local = box.globalToLocal(at);
                  return Stack(
                    children: [
                      Positioned(
                        left: local.dx,
                        top: local.dy - 20,
                        child: FractionalTranslation(translation: const Offset(-0.5, -1), child: child),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
      ],
    );
  }

  Widget _toolbar(BuildContext context) {
    final c = context.colors;
    Widget icon(String tip, IconData data, VoidCallback? onPressed) =>
        IconButton(tooltip: tip, icon: Icon(data), onPressed: onPressed, constraints: const BoxConstraints.tightFor(width: 48, height: 48));
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(top: BorderSide(color: c.border)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          key: const ValueKey('lc-toolbar'),
          height: kEditorToolbarHeight,
          child: Padding(
            padding: const EdgeInsets.only(left: Space.x3, right: Space.x1),
            child: Row(
              children: [
                FilledButton.icon(
                  key: const ValueKey('lc-tool-add'),
                  onPressed: togglePalette,
                  icon: Icon(_paletteOpen && !(palette?.collapsed ?? false) ? Icons.keyboard_arrow_down : Icons.add, size: 20),
                  label: const Text('添加'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 40),
                    padding: const EdgeInsets.symmetric(horizontal: Space.x4),
                  ),
                ),
                const Spacer(),
                ...widget.toolbarExtra,
                icon('图层', Icons.layers_outlined, widget.onLayers),
                icon('撤销', Icons.undo, widget.onUndo),
                icon('重做', Icons.redo, widget.onRedo),
                if (widget.onPreview != null) icon('预览', Icons.play_arrow_outlined, widget.onPreview),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _dropZone(BuildContext context, LcDrag drag) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final moving = drag.nodeId;
    final deletable = moving != null && (widget.canDelete?.call(moving) ?? true);
    final label = moving == null ? '拖到这里取消' : (deletable ? '拖到这里删除' : '这个不能删 · 拖到这里放回去');
    return ValueListenableBuilder<bool>(
      valueListenable: _overZone,
      builder: (context, over, _) {
        final hot = over && deletable;
        final fg = hot ? c.danger : c.textMuted;
        return DecoratedBox(
          decoration: BoxDecoration(
            color: hot ? c.dangerSoft : (over ? c.surfaceMuted : c.surface),
            border: Border(
              top: BorderSide(color: hot ? c.danger : c.border, width: hot ? 2 : 1),
            ),
          ),
          child: SafeArea(
            top: false,
            child: SizedBox(
              key: const ValueKey('lc-drop-zone'),
              height: kEditorToolbarHeight,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(deletable ? Icons.delete_outline : Icons.close, size: 20, color: fg),
                  const SizedBox(width: Space.x2),
                  Text(label, style: t.labelLarge?.copyWith(color: fg)),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// 选中条：左边图标＋名字，右边是这个组件能做的事。
///
/// [actions] 从左到右排；按钮用下面三个造：[primary]（实心，最常点的那个）、[outlined]、[plain]（只有字，可带小圆点）。
/// “⋯”之类的菜单直接放一个 PopupMenuButton 进来。
class EditorSelectionBar extends StatelessWidget {
  const EditorSelectionBar({super.key, required this.icon, required this.label, required this.actions});
  final IconData icon;
  final String label;
  final List<Widget> actions;

  static ButtonStyle _compact() => FilledButton.styleFrom(
    minimumSize: const Size(0, 36),
    padding: const EdgeInsets.symmetric(horizontal: Space.x3),
  );

  static Widget primary(String label, VoidCallback? onPressed) => FilledButton(onPressed: onPressed, style: _compact(), child: Text(label));

  static Widget outlined(String label, VoidCallback? onPressed) => Padding(
    padding: const EdgeInsets.only(left: Space.x2),
    child: OutlinedButton(onPressed: onPressed, style: _compact(), child: Text(label)),
  );

  /// [dot]：右上角带一个小圆点（“这里已经有东西了”）。
  static Widget plain(String label, VoidCallback? onPressed, {bool dot = false}) => Builder(
    builder: (context) => TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        minimumSize: const Size(0, 36),
        padding: const EdgeInsets.symmetric(horizontal: Space.x3),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label),
          if (dot)
            Container(
              key: const ValueKey('lc-action-dot'),
              margin: const EdgeInsets.only(left: 4, bottom: 8),
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: context.colors.accent, shape: BoxShape.circle),
            ),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      key: const ValueKey('lc-selection-bar'),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(top: BorderSide(color: c.border)),
      ),
      padding: const EdgeInsets.only(left: Space.x4, right: Space.x1),
      height: kEditorSelectionBarHeight,
      child: Row(
        children: [
          Icon(icon, size: 18, color: c.accent),
          const SizedBox(width: Space.x2),
          Expanded(
            child: Text(label, style: Theme.of(context).textTheme.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          ...actions,
        ],
      ),
    );
  }
}
