// 设计约束（积木编辑器整页，390 宽，浅色 + 深色）— 2026-11-24
// - 这一页就是一张桌子：整屏是点阵画布，积木摆在上面；底部是积木盒（可收起）。主操作＝用手把积木拖来拖去拼起来。
// - 顶栏是全应用统一的悬浮顶栏（lib/ui/top_bar.dart）：没有底色，画布从屏幕最顶铺起，顶栏的三样悬浮在画布上面——
//   返回、标题（只有文字：标题 + 一行状态小字）、少数入口（宿主给的，例如“变量”）＋“问题”（有问题才带数字）＋“看代码”。
//   三样之间的空白是画布：可以在那里拖画布、点积木。画布的起始位置、定位都把顶栏那一段当成被盖住的。
// - 画布上没有常驻的浮条：撤销、重做、缩放比例（点一下回到 100%）在积木盒手柄条的右边，
//   左边是“积木盒”名字（点一下收起 / 展开）和问题数量（block_editor_dock_view.dart）。
// - 积木盒面板可以上下拖：最矮只剩手柄条，最高顶到状态栏下沿（盖住顶栏）。所以它和“手上的积木”不在画布那一层里，
//   而是盖在整页（顶栏 + 画布）上面的一层；顶栏不放进 Scaffold 的 appBar，自己叠在画布上面、面板下面。
// - 选中一块积木：顶栏下面出现一条小工具条（这块的问题、复制、删除）；没选中就没有。
// - 拖动时：积木盒换成“拖到这里删除”，别的浮动控件都收起来，眼里只有积木。
// - 提示用一句话小条（两秒多自己消失），贴在积木盒上沿之上：不盖画布顶上那串的帽子；需要时带一个“撤销”。不弹对话框打断。
//   面板高到画布放不下提示条时，提示条改放在面板里分类那一行的下面（不被面板盖住，也不挡手柄）。
// - 一块积木都没有时，画布中间一句话 + 一个往上走的箭头教第一步：从下面拿一块“事件”拖上来（画布露出来不够高时不显示）。
import 'dart:async';

import 'package:lopicode/backdrop/backdrop_model.dart';
import 'package:lopicode/blocks/block_canvas_layout.dart';
import 'package:lopicode/blocks/block_canvas_view.dart';
import 'package:lopicode/blocks/block_editor_arms_view.dart';
import 'package:lopicode/blocks/block_editor_canvas_view.dart';
import 'package:lopicode/blocks/block_editor_dock_view.dart';
import 'package:lopicode/blocks/block_editor_drag_view.dart';
import 'package:lopicode/blocks/block_editor_edit_view.dart';
import 'package:lopicode/blocks/block_editor_fn_view.dart';
import 'package:lopicode/blocks/block_editor_fx_view.dart';
import 'package:lopicode/blocks/block_host.dart';
import 'package:lopicode/blocks/block_palette_model.dart';
import 'package:lopicode/blocks/block_palette_parts_view.dart';
import 'package:lopicode/blocks/block_palette_view.dart';
import 'package:lopicode/blocks/block_panels_sheet.dart';
import 'package:lopicode/blocks/block_script_view.dart';
import 'package:lopicode/lowcode/logic_blocks.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/app_backdrop.dart';
import 'package:lopicode/ui/shell.dart';
import 'package:lopicode/ui/top_bar.dart';
import 'package:material_ui/material_ui.dart';

/// 下拉小菜单最底下额外的一项（例如“新建变量…”）。`run` 里宿主自己问用户要什么；
/// 返回要填进槽里的值，和一段“先做这个”（例如把变量建出来）——编辑器把两件事放进同一次改动里。取消返回 null。
typedef BlockMenuExtra = ({String label, Future<({String value, void Function() apply})?> Function(BuildContext context) run});

/// 积木编辑器整页。前端、后端各给一个 [BlockHost] 就能用：
///
/// ```dart
/// BlockEditorView(host: myHost, title: '逻辑', extraActions: [IconButton(...)])
/// ```
///
/// 这一页自己带 Scaffold 和顶栏；会占用 `host.onChanged`（离开时还回 null）。
class BlockEditorView extends StatefulWidget {
  const BlockEditorView({
    super.key,
    required this.host,
    this.title = '积木',
    this.subtitle,
    this.extraActions = const [],
    this.focusScriptId,
    this.menuExtra,
    this.onHostChanged,
    this.paletteHeight = 248,
    this.dockMemoryKey,
    this.stars,
  });

  final BlockHost host;
  final String title;
  final String? subtitle;

  /// 顶栏上多放的入口（排在“问题”“看代码”前面）。
  final List<Widget> extraActions;

  /// 一进来就挪到这一串并选中它的帽子。
  final String? focusScriptId;

  /// 某种参数的下拉菜单要不要多一项；不要返回 null。
  final BlockMenuExtra? Function(LcArgSpec arg)? menuExtra;

  /// 宿主的内容变了（改动、撤销）以后顺带通知外壳一声（比如顶栏上的数量要跟着变）。
  final VoidCallback? onHostChanged;

  /// 积木盒面板默认档多高（不算屏幕底部的系统手势条）。
  final double paletteHeight;

  /// 给了就在这次运行里记住面板停在多高（同一个名字的编辑器离开再回来还在那里）；不给就每次从默认档开始。
  final String? dockMemoryKey;

  /// 积木盒里加的星存在哪（见 `SettingsBlockStars`）。不给＝只在这个编辑器开着的时候记着。
  final BlockStars? stars;

  @override
  State<BlockEditorView> createState() => BlockEditorViewState();
}

class BlockEditorViewState extends State<BlockEditorView> with TickerProviderStateMixin, BkKitHolder, BkEditorCanvas, BkEditorDrag, BkEditorEdit, BkEditorArms, BkEditorDock, BkEditorFn {
  String? _toast;
  String? _toastAction;
  VoidCallback? _onToastAction;
  Timer? _toastTimer;
  int _nudge = 0;
  bool _focused = false;
  late final BlockStars _stars = widget.stars ?? MemoryBlockStars();

  @override
  void initState() {
    super.initState();
    widget.host.onChanged = _hostChanged;
  }

  @override
  void didUpdateWidget(BlockEditorView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.host, widget.host)) return;
    if (oldWidget.host.onChanged == _hostChanged) oldWidget.host.onChanged = null;
    widget.host.onChanged = _hostChanged;
    dragCancel();
    dropLayout();
  }

  void _hostChanged() {
    if (!mounted) return;
    // 正拖着的时候内容被换了（外面撤销了）：手上的东西作废。
    if (drag != null && drag!.revision != host.revision && !busy) dragCancel();
    setState(() {});
    widget.onHostChanged?.call();
  }

  @override
  void dispose() {
    if (widget.host.onChanged == _hostChanged) widget.host.onChanged = null;
    _toastTimer?.cancel();
    disposeCanvas();
    disposeDrag();
    disposeEdit();
    disposeDock();
    super.dispose();
  }

  @override
  void toast(String text, {String? actionLabel, VoidCallback? onAction}) {
    if (text.isEmpty) return;
    _toastTimer?.cancel();
    setState(() {
      _toast = text;
      _toastAction = onAction == null ? null : actionLabel;
      _onToastAction = onAction;
      // 画布还空着的时候被提醒“先拿一块事件”：引导的箭头再动两下。
      if (host.scripts.isEmpty) _nudge++;
    });
    // 带动作的多留一会儿，来得及点。
    _toastTimer = Timer(Duration(milliseconds: onAction == null ? 2400 : 4000), _hideToast);
  }

  void _hideToast() {
    _toastTimer?.cancel();
    if (!mounted || _toast == null) return;
    setState(() {
      _toast = null;
      _toastAction = null;
      _onToastAction = null;
    });
  }

  void _undo() {
    commitEdit();
    if (host.canUndo) host.undo();
  }

  void _redo() {
    commitEdit();
    if (host.canRedo) host.redo();
  }

  void _onCustom(BkCustomAction action, String id) {
    switch (action) {
      case BkCustomAction.create:
        unawaited(customNew());
      case BkCustomAction.edit:
        unawaited(customEdit(id));
      case BkCustomAction.define:
        showDefinition(id);
      case BkCustomAction.remove:
        unawaited(customRemove(id));
      case BkCustomAction.star:
        break;
    }
  }

  Future<void> _showIssues() async {
    commitEdit();
    final picked = await showBlockIssues(context, host.issues);
    if (!mounted || picked == null) return;
    final id = picked.scriptId;
    if (id != null) jumpTo(id, picked.path);
  }

  void _showCode() {
    commitEdit();
    unawaited(showBlockCode(context, host));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    reduceMotion = MediaQuery.disableAnimationsOf(context);
    final all = layout; // 先排版：issues、选中都跟着刷新
    final errors = issues.where((i) => i.isError).length;
    final bar = ShellAppBar(
      key: const ValueKey('bk-bar'),
      background: kit.palette.canvas,
      title: widget.title,
      subtitle: widget.subtitle,
      actions: [
        ...widget.extraActions,
        IconButton(
          key: const ValueKey('bk-issues'),
          tooltip: issues.isEmpty ? '没有问题' : '${issues.length} 个问题',
          onPressed: _showIssues,
          icon: Badge(
            isLabelVisible: issues.isNotEmpty,
            backgroundColor: errors > 0 ? c.danger : c.warning,
            label: Text('${issues.length}'),
            child: Icon(issues.isEmpty ? Icons.check_circle_outline_rounded : Icons.error_outline_rounded),
          ),
        ),
        IconButton(key: const ValueKey('bk-code'), tooltip: '看代码', onPressed: _showCode, icon: const Icon(Icons.code_rounded)),
      ],
    );
    return Scaffold(
      backgroundColor: BackdropScope.clear(context, kit.palette.canvas, seeThrough: BackdropArea.blocks), // “透出背景 › 积木画布”开着时让开，画布自己铺半透明的底
      body: LayoutBuilder(
        builder: (context, page) {
          final safe = MediaQuery.paddingOf(context);
          // 悬浮顶栏连同状态栏一共多高：画布铺满整页，这一段算被盖住的。
          final barHeight = PageBar.insetOf(context);
          coveredTop = barHeight;
          layoutDock(area: page.maxHeight - safe.top, safeBottom: safe.bottom);
          final dragging = drag != null;
          final trashing = dragging && !drag!.isNew;
          final dock = dockHeight;
          final room = page.maxHeight - barHeight - dock;
          // 画布放不下提示条了（面板拖得很高）：提示条放到面板里、分类那一行下面。
          final toastInPanel = _toast != null && editing == null && room < BkEditorDock.toastRoom + 16;
          return Stack(
            fit: StackFit.expand,
            children: [
              MediaQuery.removePadding(
                context: context,
                removeTop: true,
                child: _area(context, all, showToast: !toastInPanel),
              ),
              // 悬浮顶栏：在画布上面、积木盒面板下面（面板全展开时盖住它）。空白处不接手指，落到画布上。
              Positioned(left: 0, right: 0, top: 0, child: bar),
              // 带 key：别的浮动控件出现 / 消失时，积木盒不能被当成新的重建（手指正按在它上面拖）。
              // 积木盒一直留在树里（就地改字、拖画布上的积木时只是不显示）：停在哪一页、搜了什么都不丢。
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Stack(
                  alignment: Alignment.bottomCenter,
                  children: [
                    Offstage(
                      offstage: editing != null || trashing,
                      child: TickerMode(
                        enabled: editing == null && !trashing,
                        child: BlockPaletteView(
                          host: host,
                          height: panelHeight,
                          handleLeading: buildDockLead(context, onIssues: _showIssues),
                          handleTrailing: buildDockTools(context, onUndo: host.canUndo ? _undo : null, onRedo: host.canRedo ? _redo : null),
                          onHandleTap: dockToggle,
                          onCustom: host.custom == null ? null : _onCustom,
                          onResizeDown: dockHold,
                          onResizeStart: dockResizeStart,
                          onResizeUpdate: dockResizeUpdate,
                          onResizeEnd: dockResizeEnd,
                          onPick: (item) {
                            final rev = host.revision;
                            quickAdd(item);
                            // 真加上去了：面板比默认档高就让开，看得见加在了哪。
                            if (host.revision != rev) dockYield();
                          },
                          onDragStart: (item, global, grab) {
                            commitEdit();
                            dragStartFromPalette(item, global, grab);
                          },
                          onDragUpdate: dragMoveGlobal,
                          onDragEnd: dragEnd,
                          onDragCancel: dragCancel,
                          stars: _stars,
                          onNotice: toast,
                        ),
                      ),
                    ),
                    if (editing == null && trashing) buildTrash(context),
                    // 看得见的那一个（积木盒或垃圾桶）占的地方；就地改字时两个都不在。
                    if (editing == null)
                      const Positioned.fill(
                        child: IgnorePointer(child: SizedBox(key: ValueKey('bk-dock'))),
                      ),
                  ],
                ),
              ),
              if (toastInPanel) Positioned(key: const ValueKey('bk-toast-layer'), left: 24, right: 24, top: page.maxHeight - dock + BlockPaletteView.headHeight + 8, child: _toastBar()),
              // 手上的积木：最上面一层（拖到顶上时从悬浮按钮上面过）。
              if (dragging)
                Positioned.fill(
                  child: Stack(clipBehavior: Clip.hardEdge, children: [buildDragPiece(context)]),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _toastBar() => BkToastBar(
    text: _toast!,
    actionLabel: _toastAction,
    onAction: () {
      final f = _onToastAction;
      _hideToast();
      f?.call();
    },
  );

  /// 编辑区：画布和画布上的浮层（积木盒、手上的积木在它外面那一层）。
  Widget _area(BuildContext context, BkCanvasLayout all, {required bool showToast}) {
    return LayoutBuilder(
      builder: (context, box) {
        viewSize = Size(box.maxWidth, box.maxHeight);
        if (!_focused) {
          _focused = true;
          final id = widget.focusScriptId;
          final placed = id == null ? null : all.placed(id);
          if (placed != null) {
            selection = BlockSelection(placed.id, const []);
            setPan(Offset(16 - placed.origin.dx, 72 - placed.origin.dy));
          }
        }
        final dragging = drag != null;
        final dock = dockHeight;
        return Stack(
          key: viewKey,
          fit: StackFit.expand,
          clipBehavior: Clip.hardEdge,
          children: [
            Positioned.fill(
              key: const ValueKey('bk-canvas-layer'),
              child: ColoredBox(
                color: BackdropScope.surface(context, kit.palette.canvas, seeThrough: BackdropArea.blocks),
                child: buildCanvas(context),
              ),
            ),
            if (all.scripts.isEmpty && !dragging && box.maxHeight - coveredTop - dock >= BkEditorDock.guideRoom)
              Positioned(
                key: const ValueKey('bk-empty-layer'),
                left: 32,
                right: 32,
                top: coveredTop,
                bottom: dock,
                child: IgnorePointer(
                  child: Center(child: BkEmptyGuide(nudge: _nudge)),
                ),
              ),
            if (selection != null && !dragging && editing == null) Positioned(key: const ValueKey('bk-selection-bar'), left: 12, right: 12, top: coveredTop + 8, child: _selectionBar(context)),
            ...buildInlineEdit(context),
            // 提示条贴在积木盒上沿之上：不盖顶上那串的帽子；键盘弹出时页面整体上移，它还在键盘上面。
            if (_toast != null && showToast) Positioned(key: const ValueKey('bk-toast-layer'), left: 24, right: 24, bottom: dock + 16, child: _toastBar()),
          ],
        );
      },
    );
  }

  Widget _pill(BuildContext context, {required List<Widget> children}) {
    final c = context.colors;
    return Material(
      color: c.surface,
      elevation: 2,
      shadowColor: c.shadowOf(0.25),
      shape: const StadiumBorder(),
      clipBehavior: Clip.antiAlias,
      child: Row(mainAxisSize: MainAxisSize.min, children: children),
    );
  }

  Widget _selectionBar(BuildContext context) {
    final c = context.colors;
    final sel = selection!;
    final mine = [
      for (final i in issues)
        if (i.scriptId == sel.scriptId && i.path.length == sel.path.length && [for (var k = 0; k < i.path.length; k++) i.path[k] == sel.path[k]].every((x) => x)) i,
    ];
    final issue = mine.isEmpty ? null : mine.firstWhere((i) => i.isError, orElse: () => mine.first);
    return Align(
      alignment: Alignment.topRight,
      child: _pill(
        context,
        children: [
          if (issue != null)
            Flexible(
              child: Padding(
                padding: const EdgeInsets.only(left: 14, right: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.error_rounded, size: 16, color: issue.isError ? c.danger : c.warning),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        issue.message,
                        key: const ValueKey('bk-selection-issue'),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: c.text),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (sel.path.isNotEmpty)
            IconButton(
              key: const ValueKey('bk-action-duplicate'),
              tooltip: '复制一块',
              onPressed: duplicateSelection,
              icon: const Icon(Icons.copy_rounded, size: 20),
              color: c.text,
              constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            ),
          IconButton(
            key: const ValueKey('bk-action-delete'),
            tooltip: sel.path.isEmpty ? '删掉这一串' : '删除',
            onPressed: deleteSelection,
            icon: const Icon(Icons.delete_outline_rounded, size: 20),
            color: c.danger,
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
          ),
        ],
      ),
    );
  }
}
