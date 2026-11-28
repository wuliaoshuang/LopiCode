// 设计约束（低代码 · 多选 · 390×844）
// - 怎么进：长按菜单 / 选中条“⋯”里的“多选”，或者图层面板标题行的“多选”。进去以后选中条换成这一条（高 48，位置不变）：
//     左边“已选 N 个”，右边 [样式]（描边）[复制]（只有字）[⋯]（包成容器 / 上移 / 下移 / 删除——删除红字放最后）[完成]（实心，唯一主操作）。
//   一排三个带字的按钮加一个“⋯”，和单选时那一条的规矩一样；所以“包成容器”“删除”收进了“⋯”。
// - 多选时：点一个组件＝加进来 / 移出去（只能选同一层的，跨层说一句“只能一起选同一层的”）；点空白不取消；
//   长按没挪松手也是加进来 / 移出去；长按拖其中一个＝几个一起挪；拖进删除区＝一起删。合一面板、就地改字这时都不出来。
// - 画布上每个选中的组件描一圈选中色、里面罩一层很淡的选中色；没有拖柄（一起改大小没有意义）。
// - “样式”打开一张底部面板：只放这几个组件**都有**的那几项（内边距、背景…），显示的是第一个的值，改了几个一起变。
// - 取用的 tokens：LowcodeKey.selection（描边和罩色）、Space.x4、textFaint。
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:lopicode/lowcode/canvas_view.dart';
import 'package:lopicode/lowcode/edit_types.dart';
import 'package:lopicode/lowcode/editor_workbench_widgets.dart';
import 'package:lopicode/lowcode/inspector_common_widgets.dart';
import 'package:lopicode/lowcode/model.dart';
import 'package:lopicode/lowcode/multi_select.dart';
import 'package:lopicode/lowcode/palette_widgets.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/widgets.dart';
import 'package:material_ui/material_ui.dart';

/// 搭建页 / 组件编辑页接上多选要用的那一套（状态只属于这一页，所以放在 State 上）。
mixin LcMultiSelectHost<T extends StatefulWidget> on State<T> {
  Set<String>? _ids;

  /// 现在的文档，和“改一下文档”的统一入口（一次一条撤销）。
  LcDocument get multiDoc;
  LcEdit get multiEdit;

  /// 这个组件能不能被多选（页面本身、组件编辑页垫在外面的那两层不能）。
  bool multiCanPick(String id) => multiDoc.parentOf(id) != null;

  /// 退出多选以后该单选谁（包成容器以后选那个新容器）；null＝什么都不选。
  void multiSelectSingle(String? id);

  bool get multiOn => _ids != null;
  Set<String> get multiIds => _ids ?? const {};

  /// 进入多选；[first] 是一上来就选中的那个。
  void multiEnter([String? first]) {
    final ids = <String>{};
    if (first != null && multiCanPick(first)) lcMultiToggle(multiDoc, ids, first);
    multiSelectSingle(null);
    setState(() => _ids = ids);
  }

  void multiExit([String? select]) {
    if (_ids == null) return;
    setState(() => _ids = null);
    multiSelectSingle(select);
  }

  /// 点了（或长按了）一个组件：加进来 / 移出去。返回没办成的原因（已经提示过了）。
  String? multiTap(String? id) {
    final ids = _ids;
    if (ids == null || id == null) return null;
    final why = multiCanPick(id) ? lcMultiToggle(multiDoc, ids, id) : '这个不能和别的一起选';
    if (why != null) {
      showEditorHint(context, why);
    } else {
      setState(() {});
    }
    return why;
  }

  /// 文档被换过 / 改过（撤销、重做、面板里改了）以后调：已经不在的从选中里去掉。
  void multiSync() {
    final ids = _ids;
    if (ids != null) lcMultiPrune(multiDoc, ids);
  }

  bool _dragsSelection(LcDrag drag) => _ids != null && drag.nodeId != null && _ids!.contains(drag.nodeId) && _ids!.length > 1;

  /// 拖的是选中的几个之一：能不能放进 [parentId]。不是这种情况返回 null（照原来的规矩判断）。
  bool? multiCanDrop(LcDrag drag, String parentId) => _dragsSelection(drag) ? lcMultiCanDropInto(multiDoc, _ids!, parentId) : null;

  /// 拖的是选中的几个之一：一起挪过去。不是这种情况返回 false（照原来的办）。
  bool multiDrop(LcDrag drag, String parentId, int index) {
    if (!_dragsSelection(drag)) return false;
    final ids = _ids!;
    multiEdit((d) => lcMultiMoveTo(d, ids, parentId, index));
    setState(() {});
    return true;
  }

  /// 把选中的几个之一拖进了删除区：一起删。不是这种情况返回 false。
  bool multiDeleteDragged(String id) {
    if (_ids == null || !_ids!.contains(id) || _ids!.length < 2) return false;
    unawaited(multiAction('delete'));
    return true;
  }

  /// 那一条上的按钮：style 样式 / copy 复制 / wrap 包成容器 / up 上移 / down 下移 / delete 删除 / done 完成。
  Future<void> multiAction(String v) async {
    final ids = _ids;
    if (ids == null) return;
    if (v == 'done') return multiExit();
    if (ids.isEmpty) return;
    final n = ids.length;
    switch (v) {
      case 'copy':
        if (lcMultiCopy(multiDoc, ids)) showEditorHint(context, '已复制 $n 个，长按别的组件可以“粘贴到它后面”');
      case 'wrap':
        String? box;
        multiEdit((d) => box = lcMultiWrap(d, ids));
        if (box != null) multiExit(box);
      case 'up' || 'down':
        var moved = false;
        multiEdit((d) => moved = lcMultiShift(d, ids, v == 'up' ? -1 : 1));
        if (!moved) showEditorHint(context, v == 'up' ? '已经在最前面了' : '已经在最后面了');
        setState(() {});
      case 'delete':
        final refs = lcMultiLogicRefs(multiDoc, ids);
        if (refs > 0) {
          final ok = await confirmDialog(context, title: '删除 $n 个组件', message: '有 $refs 处积木逻辑在用它们，删除会一并清掉。', confirmLabel: '删除', danger: true);
          if (!ok || !mounted) return;
        }
        multiEdit((d) => lcMultiDelete(d, ids));
        multiExit();
      case 'style':
        await showMultiStyleSheet(context, doc: () => multiDoc, ids: () => _ids ?? const {}, onEdit: multiEdit);
        if (mounted) setState(multiSync);
    }
  }

  /// 多选时画布下面的那一条。
  Widget multiBar() {
    final n = multiIds.length;
    void Function()? act(String v) => n == 0 ? null : () => unawaited(multiAction(v));
    return EditorSelectionBar(
      icon: Icons.checklist,
      label: n == 0 ? '点组件来选' : '已选 $n 个',
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: Space.x1),
          child: OutlinedButton(
            key: const ValueKey('lc-multi-style'),
            onPressed: act('style'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 36),
              padding: const EdgeInsets.symmetric(horizontal: Space.x3),
            ),
            child: const Text('样式'),
          ),
        ),
        KeyedSubtree(key: const ValueKey('lc-multi-copy'), child: EditorSelectionBar.plain('复制', act('copy'))),
        PopupMenuButton<String>(
          key: const ValueKey('lc-multi-more'),
          tooltip: '更多操作',
          enabled: n > 0,
          icon: const Icon(Icons.more_horiz, size: 20),
          onSelected: (v) => unawaited(multiAction(v)),
          itemBuilder: (context) => [
            const PopupMenuItem(value: 'wrap', child: Text('包成容器')),
            const PopupMenuDivider(),
            const PopupMenuItem(value: 'up', child: Text('上移')),
            const PopupMenuItem(value: 'down', child: Text('下移')),
            const PopupMenuDivider(),
            PopupMenuItem(
              value: 'delete',
              child: Text('删除', style: TextStyle(color: context.colors.danger)),
            ),
          ],
        ),
        KeyedSubtree(key: const ValueKey('lc-multi-done'), child: EditorSelectionBar.primary('完成', () => unawaited(multiAction('done')))),
        const SizedBox(width: Space.x2),
      ],
    );
  }
}

/// 画布上给多选的每个组件描的那一圈。盖在画布上面、不接手势；跟着画布的平移缩放走。
class MultiMarksOverlay extends StatefulWidget {
  const MultiMarksOverlay({super.key, required this.canvas, required this.ids});

  /// 取画布（刚搭出来的第一帧可能还没有）。
  final CanvasViewState? Function() canvas;
  final Set<String> ids;

  @override
  State<MultiMarksOverlay> createState() => _MultiMarksOverlayState();
}

class _MultiMarksOverlayState extends State<MultiMarksOverlay> {
  Map<String, Rect> _rects = const {};
  ValueListenable<CanvasViewport>? _view;

  // 组件在哪儿要等排完版才量得到：每次重搭以后量一遍，变了才重画。
  void _measure() {
    if (!mounted) return;
    final canvas = widget.canvas();
    final box = context.findRenderObject();
    if (canvas == null || box is! RenderBox || !box.hasSize) return;
    if (!identical(_view, canvas.view)) {
      _view?.removeListener(_measure);
      _view = canvas.view..addListener(_measure);
    }
    final origin = box.localToGlobal(Offset.zero);
    final next = <String, Rect>{
      for (final id in widget.ids)
        if (canvas.nodeScreenRect(id) case final r?) id: r.shift(-origin),
    };
    if (next.length == _rects.length && next.entries.every((e) => _rects[e.key] == e.value)) return;
    setState(() => _rects = next);
  }

  @override
  void dispose() {
    _view?.removeListener(_measure);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
    final color = context.themeSpec.lowcodeColor(LowcodeKey.selection);
    return IgnorePointer(
      child: ClipRect(
        child: Stack(
          children: [
            for (final e in _rects.entries)
              if (widget.ids.contains(e.key))
                Positioned.fromRect(
                  rect: e.value,
                  child: DecoratedBox(
                    key: ValueKey('lc-multi-mark-${e.key}'),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      border: Border.all(color: color, width: 2),
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

/// “样式”：一起改这几个组件都有的那几项。
Future<void> showMultiStyleSheet(BuildContext context, {required LcDocument Function() doc, required Set<String> Function() ids, required LcEdit onEdit}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  barrierColor: context.colors.scrimOf(0x14 / 255), // 遮罩要淡：改的时候她要看得见上面的画布跟着变
  builder: (_) => _MultiStyleSheet(doc: doc, ids: ids, onEdit: onEdit),
);

class _MultiStyleSheet extends StatefulWidget {
  const _MultiStyleSheet({required this.doc, required this.ids, required this.onEdit});
  final LcDocument Function() doc;
  final Set<String> Function() ids;
  final LcEdit onEdit;

  @override
  State<_MultiStyleSheet> createState() => _MultiStyleSheetState();
}

class _MultiStyleSheetState extends State<_MultiStyleSheet> {
  /// 值不一样、但她已经点开要改的那几项（点开以后显示第一个的值，改了几个一起变）。
  final Set<String> _opened = {};

  void _apply(void Function(LcNode n, LcNode? parent) change, {bool merge = false}) {
    final ids = widget.ids();
    widget.onEdit((d) {
      for (final n in lcMultiOrdered(d, ids)) {
        change(n, d.parentOf(n.id));
      }
    });
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final doc = widget.doc(), ids = widget.ids();
    final nodes = lcMultiOrdered(doc, ids);
    final fields = lcMultiCommonFields(doc, ids);
    final mixed = lcMultiMixed(doc, ids, fields);
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(Space.x4, 0, Space.x4, Space.x4 + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('一起改样式 · ${nodes.length} 个', style: t.titleLarge),
            const SizedBox(height: Space.x1),
            Text(
              fields.isEmpty ? '这几个组件没有都能改的样式项，分开选中再改。' : (mixed.isEmpty ? '只列这几个都有的项；改了以后几个一起变。' : '只列这几个都有的项；改了以后几个一起变。几个的值不一样的那一行写着“多个值”，点它再改。'),
              style: t.bodySmall?.copyWith(color: c.textFaint),
            ),
            const SizedBox(height: Space.x2),
            if (nodes.isNotEmpty && fields.isNotEmpty)
              InspectorCommonPage(
                key: const ValueKey('lc-multi-style-rows'),
                ed: InspectorEdit(doc: doc, node: nodes.first, parent: doc.parentOf(nodes.first.id), apply: _apply),
                only: fields,
                wrap: (f, row) => mixed.contains(f) && !_opened.contains(f) ? MultiMixedRow(field: f, row: row, onOpen: () => setState(() => _opened.add(f))) : row,
              ),
          ],
        ),
      ),
    );
  }
}

/// 多选“一起改样式”里，几个组件的值不一样的那一行：原来的控件压淡、点不到，右边一颗“多个值”。
/// 点一下这一行＝“我要把它们改成一样的”：控件恢复（显示的是第一个的值），之后改了几个一起变。
class MultiMixedRow extends StatelessWidget {
  const MultiMixedRow({super.key, required this.field, required this.row, required this.onOpen});
  final String field;
  final Widget row;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    return InkWell(
      key: ValueKey('lc-multi-mixed-$field'),
      onTap: onOpen,
      child: Stack(
        alignment: Alignment.centerRight,
        children: [
          // 原来的控件还在原位（这一行多高、叫什么一眼看得出），只是压淡、点不到、读屏不念它的值。
          ExcludeSemantics(
            child: IgnorePointer(child: Opacity(opacity: 0.28, child: row)),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: Space.x3, vertical: Space.x1),
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(Radii.xl),
              border: Border.all(color: c.border),
            ),
            child: Text('多个值 · 点这里改', style: t.labelMedium?.copyWith(color: c.textMuted)),
          ),
        ],
      ),
    );
  }
}
