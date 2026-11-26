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
// - 第 2 期加的三样也归这里管（两个页面共用）：
//     合一面板（inspector_sheet.dart）：贴在工具条上面、盖住选中条、**不挡画布**——上面露着的画布照样能点，
//       点另一个组件面板跟着换；点“×”/ 往下拖到底 / 返回键＝收起。取消选中时它只是先让开，再选中一个组件它自己回来
//       （所以“选中 → 点档”两步就能改一个值）；她亲手收起、或者去开组件盒以后，就不再自己出来。
//       它开着时画布把选中的组件滚到面板上方。
//     就地改字（inline_text_widgets.dart）：点一下已经选中的文字 / 按钮 / 输入框，原地变输入框。
//     长按菜单：长按一个组件、没挪（不到 8 像素）就松手＝出菜单（由页面决定菜单里有什么）；挪了才是拖动。
import 'package:lopicode/lowcode/canvas_banner_widgets.dart';
import 'package:lopicode/lowcode/canvas_drag_widgets.dart';
import 'package:lopicode/lowcode/canvas_view.dart';
import 'package:lopicode/lowcode/edit_types.dart';
import 'package:lopicode/lowcode/editor_selection_bar_widgets.dart';
import 'package:lopicode/lowcode/editor_toolbar_widgets.dart';
import 'package:lopicode/lowcode/inline_text_widgets.dart';
import 'package:lopicode/lowcode/inspector_sheet.dart';
import 'package:lopicode/lowcode/lift_gesture_widgets.dart';
import 'package:lopicode/lowcode/model.dart';
import 'package:lopicode/lowcode/multi_select_widgets.dart';
import 'package:lopicode/lowcode/overlay_focus.dart';
import 'package:lopicode/lowcode/palette_catalog.dart';
import 'package:lopicode/lowcode/palette_widgets.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/top_bar.dart';
import 'package:material_ui/material_ui.dart';

// 选中条的外壳原来就定义在这个文件里，别处还从这里引用。
export 'package:lopicode/lowcode/editor_selection_bar_widgets.dart' show EditorSelectionBar, kEditorSelectionBarHeight;
export 'package:lopicode/lowcode/editor_toolbar_widgets.dart' show kEditorToolbarHeight;

/// 搭建台里的一句提示（“已复制…”）：浮在工具条和选中条**上面**。
/// 用全应用那种贴底的提示会把撤销 / 重做盖住好几秒（测试里点撤销点到了提示上才发现）。
void showEditorHint(BuildContext context, String text) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(text),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
        margin: const EdgeInsets.fromLTRB(Space.x4, 0, Space.x4, kEditorToolbarHeight + kEditorSelectionBarHeight + Space.x2),
      ),
    );
}

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
    this.onEdit,
    this.pickImage,
    this.onOpenLogic,
    this.onAddLogic,
    this.onNodeMenu,
    this.marked = const {},
  });

  /// 多选时选中的那几个（画布上各描一圈，见 multi_select_widgets.dart）；空的＝没在多选。
  final Set<String> marked;

  /// 合一面板和就地改字靠它改文档；不给＝这两样都没有。
  final LcEdit? onEdit;

  /// 合一面板里选图片（见 [InspectorPanel.pickImage]）。
  final Future<String?> Function(String from)? pickImage;

  /// 合一面板“事件”页用（见 [InspectorPanel]）；不给＝没有“事件”页。
  final void Function(String nodeId)? onOpenLogic;
  final void Function(String nodeId, String event)? onAddLogic;

  /// 长按一个组件没挪就松手：页面在 [at]（屏幕坐标）弹菜单。不给＝长按只有拖动。
  final void Function(String nodeId, Offset at)? onNodeMenu;

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
  final GlobalKey<InspectorPanelState> _inspectorKey = GlobalKey();
  bool _paletteOpen = false;

  /// 合一面板开在哪一页；null＝没开。
  InspectorPage? _inspector;

  /// 正在就地改字的组件。
  String? _editing;

  /// “只看这个弹层”（overlay_focus.dart）；画布顶上的横条一共多高（画布把页面顶边让出这么多）。
  final LcOverlayFocus _overlay = LcOverlayFocus();
  double _bannerHeight = 0;

  /// 合一面板“样式”页正在看哪个状态（按下 / 禁用 / 聚焦）；null＝平时。
  String? _stateShown;

  // 这次长按是从哪儿拿起来的、拿起来以后挪没挪过。
  Offset _liftAt = Offset.zero;
  bool _moved = false;

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
  bool get inspectorOpen => _inspector != null && widget.selected != null;

  /// 合一面板（没开是 null）。
  InspectorPanelState? get inspector => _inspectorKey.currentState;

  /// 打开合一面板的某一页（已经开着就换页）。
  void openInspector(InspectorPage page) {
    if (widget.onEdit == null) return;
    final open = inspector;
    if (open != null) {
      open.showPage(page);
      return;
    }
    setState(() {
      _inspector = page;
      _paletteOpen = false;
    });
    _revealSelected();
  }

  /// 收起合一面板（没提交的改动先交出去）。
  void closeInspector() {
    if (_inspector == null) return;
    inspector?.flush();
    setState(() => _inspector = _stateShown = null);
  }

  void _revealSelected() => WidgetsBinding.instance.addPostFrameCallback((_) {
    final id = widget.selected;
    if (mounted && id != null && _inspector != null) canvas?.revealNode(id);
  });

  @override
  void didUpdateWidget(EditorWorkbench oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selected != oldWidget.selected) {
      _editing = null;
      if (_inspector != null) _revealSelected(); // 面板开着换了组件：滚到面板上方
    }
  }

  /// 画布上点了一个组件（或空白）。点的是已经选中的文字 / 按钮 / 输入框＝就地改字。
  void _tapNode(String? id) {
    // 正在编辑弹窗时点到了弹窗外面（遮罩）：算点空白，不选中页面（选中页面＝退出这个状态）。
    if (id == widget.doc.root.id && _overlay.sync(widget.doc, widget.selected) != null) id = null;
    final node = id == null ? null : widget.doc.find(id);
    if (_editing != null) {
      // 正在就地改字时点了别处：先把字交出去（输入框失焦就会提交），这一下只算“改完了”。
      FocusManager.instance.primaryFocus?.unfocus();
      if (id != widget.selected) widget.onSelect(id);
      return;
    }
    if (node != null && id == widget.selected && widget.onEdit != null && _drag == null && inlineTextProp(node) != null) {
      setState(() => _editing = id);
      return;
    }
    widget.onSelect(id);
  }

  void _inlineDone(String id, String? text) {
    if (!mounted) return;
    setState(() => _editing = null);
    if (text == null) return;
    widget.onEdit?.call((d) {
      final n = d.find(id);
      final prop = n == null ? null : inlineTextProp(n);
      if (prop != null) n!.props[prop] = text;
    });
  }

  bool get dragging => _drag != null;

  void togglePalette() => setState(() {
    final p = palette;
    if (_paletteOpen && p != null && p.collapsed) {
      p.expand(); // 只剩手柄时再点“添加”＝拉回默认高度
    } else {
      _paletteOpen = !_paletteOpen;
      if (_paletteOpen) _inspector = null; // 去加组件了：合一面板不再自己跟出来
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
    // 正在编辑弹窗、又什么都没选中：加进这个弹窗里（不然会加到看不见的页面上）。
    final dialog = _overlay.sync(widget.doc, widget.selected);
    if (dialog != null && widget.selected == null) widget.onSelect(dialog.id);
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
    inspector?.flush(); // 面板里没提交的先交出去（拖动时面板先收着）
    palette?.collapse();
    final moving = drag.nodeId;
    final rect = moving == null ? null : cv.nodeScreenRect(moving);
    _overZone.value = false;
    _finger.value = global;
    _liftAt = global;
    _moved = false;
    setState(() {
      _editing = null;
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
    if ((global - _liftAt).distance > kLcLiftSlop) _moved = true;
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
    // 拿起来没挪就松手：不是拖动，是要菜单。
    if (!_moved && moving != null && widget.onNodeMenu != null) {
      widget.onNodeMenu!(moving, _liftAt);
      return;
    }
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
    final barInset = PageBar.insetOf(context);
    final topInset = barInset + (_bannerHeight > 0 ? _bannerHeight + Space.x1 * 2 : 0);
    final dialog = _overlay.sync(widget.doc, widget.selected);
    final drag = _drag;
    final selected = widget.selected, editing = _editing == null ? null : widget.doc.find(_editing!);
    return Stack(
      children: [
        Column(
          children: [
            Expanded(
              child: Stack(
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
                                  onSelect: _tapNode,
                                  canDrop: widget.canDrop,
                                  onResize: widget.onResize,
                                  onLift: _lift,
                                  onLiftMove: _move,
                                  onLiftDrop: () => _end(cancelled: false),
                                  onLiftCancel: () => _end(cancelled: true),
                                  presetWidth: widget.presetWidth,
                                  showBoxModel: widget.showBoxModel,
                                  overlayId: dialog?.id,
                                  statePreview: _inspector != null && selected != null && _stateShown != null ? (nodeId: selected, state: _stateShown!) : null,
                                  topInset: topInset,
                                  // 合一面板开着：它盖住的那一段不算画布的可见范围（选中的组件滚到它上方）。
                                  bottomInset: _inspector != null && selected != null
                                      ? ((box.maxHeight + kEditorSelectionBarHeight) * kInspectorInitialSize - kEditorSelectionBarHeight).clamp(0.0, box.maxHeight * 0.75).toDouble()
                                      : (_paletteOpen ? kPaletteHandleHeight : 0),
                                ),
                              ),
                              Positioned(
                                left: 0,
                                right: 0,
                                top: barInset + Space.x1,
                                child: CanvasBanners(
                                  doc: widget.doc,
                                  dialog: dialog,
                                  onExitDialog: () {
                                    setState(_overlay.exit);
                                    widget.onSelect(null);
                                  },
                                  onHeight: (h) => setState(() => _bannerHeight = h),
                                ),
                              ),
                              if (widget.marked.isNotEmpty && drag == null)
                                Positioned.fill(
                                  child: MultiMarksOverlay(canvas: () => canvas, ids: widget.marked),
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
                    ],
                  ),
                  // 合一面板：盖住选中条和画布的下半截，最底下的工具条（撤销 / 重做 / 预览）一直露着。
                  if (_inspector != null && selected != null && widget.onEdit != null && drag == null)
                    Positioned.fill(
                      child: InspectorPanel(
                        key: _inspectorKey,
                        doc: widget.doc,
                        nodeId: selected,
                        onEdit: widget.onEdit!,
                        initialPage: _inspector!,
                        onClose: closeInspector,
                        pickImage: widget.pickImage,
                        onOpenLogic: widget.onOpenLogic,
                        onAddLogic: widget.onAddLogic,
                        onState: (s) => setState(() => _stateShown = s),
                      ),
                    ),
                ],
              ),
            ),
            KeyedSubtree(
              key: _zoneKey,
              child: drag == null
                  ? EditorToolbar(
                      adding: _paletteOpen && !(palette?.collapsed ?? false),
                      onAdd: togglePalette,
                      extra: widget.toolbarExtra,
                      onLayers: widget.onLayers,
                      onUndo: widget.onUndo,
                      onRedo: widget.onRedo,
                      onPreview: widget.onPreview,
                    )
                  : EditorDropZone(over: _overZone, moving: drag.nodeId != null, deletable: drag.nodeId != null && (widget.canDelete?.call(drag.nodeId!) ?? true)),
            ),
          ],
        ),
        if (editing != null && canvas != null && inlineTextProp(editing) != null)
          Positioned.fill(
            child: InlineTextEditor(
              key: ValueKey('inline-${editing.id}'),
              canvas: canvas!,
              node: editing,
              parent: widget.doc.parentOf(editing.id),
              origin: () {
                final box = context.findRenderObject();
                return box is RenderBox && box.hasSize ? box.localToGlobal(Offset.zero) : Offset.zero;
              },
              onDone: (text) => _inlineDone(editing.id, text),
            ),
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
}
