// 设计约束（积木编辑器整页，390 宽，浅色 + 深色）— 2026-11-24
// - 这一页就是一张桌子：整屏是点阵画布，积木摆在上面；底部是积木盒（可收起）。主操作＝用手把积木拖来拖去拼起来。
// - 顶栏只放三样：返回、标题、少数入口（宿主给的，例如“变量”）＋“问题”（有问题才带数字）＋“看代码”。
// - 画布右下角（积木盒上方）浮着一小条：撤销、重做、缩放比例（点一下回到 100%）。不占画布的地方。
// - 选中一块积木：画布上方出现一条小工具条（这块的问题、复制、删除）；没选中就没有。
// - 拖动时：积木盒换成“拖到这里删除”，别的浮动控件都收起来，眼里只有积木。
// - 提示用画布上方的一句话小条（两秒多自己消失），不弹对话框打断。
// - 一块积木都没有时，画布中间一句话教第一步：从下面拿一块“事件”。
import 'dart:async';

import 'package:lopicode/blocks/block_canvas_view.dart';
import 'package:lopicode/blocks/block_editor_canvas_view.dart';
import 'package:lopicode/blocks/block_editor_drag_view.dart';
import 'package:lopicode/blocks/block_editor_edit_view.dart';
import 'package:lopicode/blocks/block_host.dart';
import 'package:lopicode/blocks/block_palette_view.dart';
import 'package:lopicode/blocks/block_panels_sheet.dart';
import 'package:lopicode/blocks/block_script_view.dart';
import 'package:lopicode/lowcode/logic_blocks.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/shell.dart';
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
  const BlockEditorView({super.key, required this.host, this.title = '积木', this.subtitle, this.extraActions = const [], this.focusScriptId, this.menuExtra, this.paletteHeight = 248});

  final BlockHost host;
  final String title;
  final String? subtitle;

  /// 顶栏上多放的入口（排在“问题”“看代码”前面）。
  final List<Widget> extraActions;

  /// 一进来就挪到这一串并选中它的帽子。
  final String? focusScriptId;

  /// 某种参数的下拉菜单要不要多一项；不要返回 null。
  final BlockMenuExtra? Function(LcArgSpec arg)? menuExtra;
  final double paletteHeight;

  @override
  State<BlockEditorView> createState() => BlockEditorViewState();
}

class BlockEditorViewState extends State<BlockEditorView> with TickerProviderStateMixin, BkKitHolder, BkEditorCanvas, BkEditorDrag, BkEditorEdit {
  bool paletteCollapsed = false;
  String? _toast;
  Timer? _toastTimer;
  bool _focused = false;

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
  }

  @override
  void dispose() {
    if (widget.host.onChanged == _hostChanged) widget.host.onChanged = null;
    _toastTimer?.cancel();
    disposeCanvas();
    disposeDrag();
    disposeEdit();
    super.dispose();
  }

  @override
  double get dockHeight => editing != null ? 0 : (paletteCollapsed ? (drag != null ? 96 : BlockPaletteView.collapsedHeight) : widget.paletteHeight);

  @override
  void toast(String text) {
    if (text.isEmpty) return;
    _toastTimer?.cancel();
    setState(() => _toast = text);
    _toastTimer = Timer(const Duration(milliseconds: 2400), () {
      if (mounted) setState(() => _toast = null);
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
    final all = layout; // 先排版：issues、选中都跟着刷新
    final errors = issues.where((i) => i.isError).length;
    return Scaffold(
      backgroundColor: kit.palette.canvas,
      appBar: ShellAppBar(
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
      ),
      body: LayoutBuilder(
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
              Positioned.fill(key: const ValueKey('bk-canvas-layer'), child: buildCanvas(context)),
              if (all.scripts.isEmpty && !dragging)
                Positioned(
                  key: const ValueKey('bk-empty-layer'),
                  left: 32,
                  right: 32,
                  top: 0,
                  bottom: dock,
                  child: IgnorePointer(
                    child: Center(
                      child: Text(
                        '还没有积木。\n从下面的积木盒里拖一块“事件”出来，\n再往它下面拼积木。',
                        key: const ValueKey('bk-empty'),
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: c.textMuted, height: 1.6),
                      ),
                    ),
                  ),
                ),
              if (selection != null && !dragging && editing == null) Positioned(key: const ValueKey('bk-selection-bar'), left: 12, right: 12, top: 8, child: _selectionBar(context)),
              if (!dragging && editing == null) Positioned(key: const ValueKey('bk-tools'), right: 12, bottom: dock + 12, child: _tools(context)),
              // 带 key：别的浮动控件出现 / 消失时，积木盒不能被当成新的重建（手指正按在它上面拖）。
              if (editing == null)
                Positioned(
                  key: const ValueKey('bk-dock'),
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: dragging && !drag!.isNew
                      ? buildTrash(context)
                      : BlockPaletteView(
                          host: host,
                          height: widget.paletteHeight,
                          collapsed: paletteCollapsed,
                          onToggle: () => setState(() => paletteCollapsed = !paletteCollapsed),
                          onPick: quickAdd,
                          onDragStart: (item, global, grab) {
                            commitEdit();
                            dragStartFromPalette(item, global, grab);
                          },
                          onDragUpdate: dragMoveGlobal,
                          onDragEnd: dragEnd,
                          onDragCancel: dragCancel,
                        ),
                ),
              ...buildInlineEdit(context),
              if (dragging) buildDragPiece(context),
              if (_toast != null)
                Positioned(
                  left: 24,
                  right: 24,
                  top: 12,
                  child: IgnorePointer(
                    child: Center(
                      child: Material(
                        color: c.text,
                        elevation: 4,
                        borderRadius: BorderRadius.circular(20),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                          child: Text(
                            _toast!,
                            key: const ValueKey('bk-toast'),
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: c.surface, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _pill(BuildContext context, {required List<Widget> children}) {
    final c = context.colors;
    return Material(
      color: c.surface,
      elevation: 2,
      shadowColor: Colors.black.withValues(alpha: 0.25),
      shape: const StadiumBorder(),
      clipBehavior: Clip.antiAlias,
      child: Row(mainAxisSize: MainAxisSize.min, children: children),
    );
  }

  Widget _tools(BuildContext context) {
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
    return _pill(
      context,
      children: [
        button('bk-undo', Icons.undo_rounded, '撤销', host.canUndo ? _undo : null),
        button('bk-redo', Icons.redo_rounded, '重做', host.canRedo ? _redo : null),
        InkWell(
          key: const ValueKey('bk-zoom'),
          onTap: () => setState(() => setZoom(1, Offset(viewSize.width / 2, (viewSize.height - dockHeight) / 2))),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(6, 13, 14, 13),
            child: Text(
              '${(zoom * 100).round()}%',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: c.textMuted, fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ],
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
