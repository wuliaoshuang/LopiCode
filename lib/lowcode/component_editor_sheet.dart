// 设计约束（低代码 · 编辑组件的内容 · 390×844）
// - 整页：和搭建页同一套排法，只是画布上放的不是页面，而是“这个组件的内容”（外面垫一张空白页当背景）。
//   顶栏（沉浸式，悬浮在画布上面，没有底色）：标题“编辑组件”+ 组件名；右边“⋮”（可配置的属性、屏宽与缩放）和主操作“完成”。
//   顶栏以下是和搭建页共用的搭建台（editor_workbench_widgets.dart）：画布 → 选中条（“选上一层”和名字在左；常用 / 样式 在右，
//   打开同一张合一面板的两页；其余收进“更多操作”，和长按菜单同一份）→ 最底下的工具条（添加 / 图层 / 撤销 / 重做；这里没有预览）。
// - 这里没有积木逻辑的入口：组件里面的控件不支持逻辑。
// - 组件最外层只能有一个控件：最外层不能删、不能移走，旁边也放不了别的控件（要放就放进它里面）。
// - 插槽：选中一个容器 › 更多操作 ›“把内容设成插槽”（先起名）；选中插槽 › 更多操作 ›“改插槽名 / 取消插槽”。
//   画布上插槽是一个带“插槽 · 名字”角标的框，里面放的是没填时显示的默认内容。
// - 每改一下立刻写回组件定义（搭建页那边记一条撤销），所以回到页面时所有实例已经是新样子；“完成”只是关掉这一页。
import 'dart:async';

import 'package:lopicode/lowcode/builder_bars_widgets.dart';
import 'package:lopicode/lowcode/canvas_parts_widgets.dart';
import 'package:lopicode/lowcode/canvas_view_sheet.dart';
import 'package:lopicode/lowcode/component_editing.dart';
import 'package:lopicode/lowcode/component_ops.dart';
import 'package:lopicode/lowcode/component_props_sheet.dart';
import 'package:lopicode/lowcode/component_slot_sheet.dart';
import 'package:lopicode/lowcode/component_slots.dart';
import 'package:lopicode/lowcode/component_values_widgets.dart';
import 'package:lopicode/lowcode/edit_types.dart';
import 'package:lopicode/lowcode/editor_clipboard.dart';
import 'package:lopicode/lowcode/editor_workbench_widgets.dart';
import 'package:lopicode/lowcode/image_pick_sheet.dart';
import 'package:lopicode/lowcode/inspector_sheet.dart';
import 'package:lopicode/lowcode/layers_sheet.dart';
import 'package:lopicode/lowcode/model.dart';
import 'package:lopicode/lowcode/multi_select_widgets.dart';
import 'package:lopicode/lowcode/node_actions.dart';
import 'package:lopicode/lowcode/palette_catalog.dart';
import 'package:lopicode/lowcode/palette_widgets.dart';
import 'package:lopicode/lowcode/slots.dart';
import 'package:lopicode/lowcode/style_model.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/shell.dart';
import 'package:lopicode/ui/widgets.dart';
import 'package:material_ui/material_ui.dart';

export 'package:lopicode/lowcode/component_editing.dart';

/// 打开“编辑组件内容”页。关掉后组件定义已经是改好的（每一步都即时写回）。
Future<void> showComponentEditor(BuildContext context, {required LcDocument doc, required LcEdit onEdit, required String componentId, PaletteRecents? recents, LcImages? images}) async {
  if (doc.component(componentId) == null) {
    await tellComponentProblem(context, '这个组件的定义已经不存在了。');
    return;
  }
  await Navigator.push(
    context,
    MaterialPageRoute<void>(
      builder: (_) => _ComponentEditor(doc: doc, onEdit: onEdit, componentId: componentId, recents: recents ?? PaletteRecents(), images: images),
    ),
  );
}

class _ComponentEditor extends StatefulWidget {
  const _ComponentEditor({required this.doc, required this.onEdit, required this.componentId, required this.recents, this.images});

  /// 项目的图片（画布认相对地址、面板里选图）；没给就只能填网址。
  final LcImages? images;

  /// 组件盒的“常用”：和搭建页用同一份（没给就只在这一页里记）。
  final PaletteRecents recents;
  final LcDocument doc;
  final LcEdit onEdit;
  final String componentId;

  @override
  State<_ComponentEditor> createState() => _ComponentEditorState();
}

class _ComponentEditorState extends State<_ComponentEditor> with LcMultiSelectHost<_ComponentEditor> {
  @override
  LcDocument get multiDoc => _temp;
  @override
  LcEdit get multiEdit => _apply;
  @override
  void multiSelectSingle(String? id) => _select(id);
  // 垫在外面的那张页面、组件的最外层不能和别的一起选。
  @override
  bool multiCanPick(String id) => id != kComponentEditRootId && id != _top?.id && _temp.parentOf(id) != null;

  /// 搭建页手里的文档（每次写回时更新成它当时用的那个对象）。
  late LcDocument _real = widget.doc;
  late LcDocument _temp;
  late LcHistory _history;
  String? _selected;
  int _presetWidth = 0;
  bool _showBoxModel = true;
  final GlobalKey<EditorWorkbenchState> _bench = GlobalKey();

  @override
  void initState() {
    super.initState();
    _reload();
  }

  /// 按现在的定义重新造临时文档（进来时、在“可配置的属性”里改过以后）。
  void _reload() {
    _temp =
        componentEditingDocument(_real, widget.componentId) ??
        LcDocument(
          title: '',
          root: LcNode(id: kComponentEditRootId, type: 'page'),
        );
    _history = LcHistory(_temp);
    if (_selected != null && _temp.find(_selected!) == null) _selected = null;
  }

  LcNode? get _top => _temp.root.children.length == 1 ? _temp.root.children.single : null;

  /// 把临时文档写回定义（搭建页记一条撤销）。写不回去返回原因。[before]：写回之前先在搭建页的文档上做的事（同一条撤销）。
  String? _writeBack([void Function(LcDocument real)? before]) {
    LcOpResult? result;
    widget.onEdit((d) {
      _real = d;
      before?.call(d);
      result = applyComponentEditing(d, widget.componentId, _temp);
    });
    return result?.error;
  }

  /// 这一页所有的修改都走这里：改临时文档 → 写回定义；写不回去（比如最外层被弄没了）就退回改之前的样子并说明原因。
  void _apply(void Function(LcDocument doc) change, {void Function(LcDocument real)? onReal}) {
    final before = _temp.encode();
    setState(() {
      change(_temp);
      lcLinkInstances(_temp);
    });
    if (_temp.encode() == before) return;
    final error = _writeBack(onReal);
    if (error == null) {
      _history.record(_temp);
      return;
    }
    setState(() => _temp = LcDocument.parse(before));
    unawaited(tellComponentProblem(context, error));
  }

  void _restore(LcDocument? doc) {
    if (doc == null) return;
    setState(() {
      _temp = doc;
      if (_selected != null && doc.find(_selected!) == null) _selected = null;
      multiSync();
    });
    final error = _writeBack();
    if (error != null) unawaited(tellComponentProblem(context, error));
  }

  // 点画布空白处选中的是垫在下面的那张页面：它不是组件的一部分，当作“什么都没选”。
  void _select(String? id) => setState(() => _selected = id == kComponentEditRootId ? null : id);

  LcNode _fresh(String type, String? ref) {
    final node = _temp.newNode(type);
    if (ref != null) node.props['ref'] = ref;
    return node;
  }

  static const _noDialog = '弹窗是整页的东西，不能放进组件里。请回到页面上加弹窗。';

  String? _addByTap(String type, [String? ref]) {
    final top = _top;
    final sel = _selected == null ? null : _temp.find(_selected!);
    final target = sel ?? top;
    if (target == null) return null;
    if (type == 'dialog') {
      unawaited(tellComponentProblem(context, _noDialog));
      return null;
    }
    final node = _fresh(type, ref);
    if (target.isContainer) {
      _apply((d) => d.insert(target.id, node));
    } else if (identical(target, top)) {
      unawaited(tellComponentProblem(context, '组件最外层只能有一个控件。想放多个控件，就让最外层是一个容器（容器、行、列、卡片），再把别的放进去。'));
      return null;
    } else {
      final parent = _temp.parentOf(target.id)!;
      _apply((d) => d.insert(parent.id, node, parent.children.indexOf(target) + 1));
    }
    if (_temp.find(node.id) == null) return null;
    setState(() => _selected = node.id);
    return node.id;
  }

  void _drop(LcDrag drag, String parentId, int index) {
    if (multiDrop(drag, parentId, index)) return;
    if (drag.type == 'dialog') {
      unawaited(tellComponentProblem(context, _noDialog));
      return;
    }
    if (drag.type != null) {
      final node = _fresh(drag.type!, drag.ref);
      _apply((d) => lcInsertAt(d, parentId, node, index));
      if (_temp.find(node.id) != null) setState(() => _selected = node.id);
    } else {
      _apply((d) => lcMoveTo(d, drag.nodeId!, parentId, index));
      if (_temp.find(drag.nodeId!) != null) setState(() => _selected = drag.nodeId);
    }
  }

  bool _canDrop(LcDrag drag, String parentId) {
    // 垫在下面的页面里只能有组件最外层那一个控件。
    if (parentId == kComponentEditRootId) return false;
    final many = multiCanDrop(drag, parentId);
    if (many != null) return many;
    if (drag.nodeId == null) return true;
    final node = _temp.find(drag.nodeId!);
    if (node == null) return false;
    bool contains(LcNode n) => n.id == lcSplitSlotId(parentId).$1 || n.children.any(contains);
    return !contains(node);
  }

  void _resize(String id, int? width, int? height) => _apply((d) {
    final n = d.find(id);
    if (n == null) return;
    final style = LcStyle(n.style);
    if (width != null) style.setLength('width', LcLength.px(width.toDouble()));
    if (height != null) style.setLength('height', LcLength.px(height.toDouble()));
  });

  void _refresh() {
    if (!mounted) return;
    setState(() {
      if (_selected != null && _temp.find(_selected!) == null) _selected = null;
      multiSync();
    });
  }

  /// 图层面板从组件的最外层列起（外面垫的那张空白页不算）。
  Future<void> _openLayers() async {
    _bench.currentState?.closeInspector();
    await showLayerSheet(
      context,
      doc: () => _temp,
      root: () => _top ?? _temp.root,
      selected: _selected,
      onEdit: _apply,
      multi: LayerMulti(ids: () => multiOn ? multiIds : null, setOn: (on) => on ? multiEnter() : multiExit(), tap: multiTap),
      showLogic: false,
      onSelect: (id) {
        _select(id);
        WidgetsBinding.instance.addPostFrameCallback((_) => _bench.currentState?.canvas?.revealNode(id));
      },
      onMove: (id, parentId, index) {
        _apply((d) => d.move(id, parentId, index));
        _select(id);
      },
    );
    _refresh();
  }

  Future<void> _nodeMenu(String id, Offset at) async {
    final node = _temp.find(id);
    if (node == null || id == kComponentEditRootId) return;
    if (multiOn) {
      multiTap(id); // 多选时长按没挪＝加进来 / 移出去
      return;
    }
    _select(id);
    final v = await showLcNodeMenu(context, at, node, componentActions: false, slotActions: true, fixed: identical(node, _top), avoid: _bench.currentState?.canvas?.nodeScreenRect(id));
    if (v != null && mounted) _nodeAction(v, id);
  }

  /// 设成插槽 / 改插槽名：先问名字（不合适的原因就写在对话框里），再改。
  Future<void> _nameSlot(String id, {required bool rename}) async {
    final node = _temp.find(id);
    if (node == null) return;
    if (!rename) {
      final blocked = canMakeSlot(_temp, id);
      if (blocked != null) return tellComponentProblem(context, blocked);
    }
    final isDefault = rename && lcSlotNameOf(node) == kLcDefaultSlot;
    final hasDefault = slotNamesIn(_temp.root).contains(kLcDefaultSlot);
    final r = await showSlotNameDialog(
      context,
      title: rename ? '改插槽名' : '把内容设成插槽',
      initial: rename ? slotNodeLabel(node) : (hasDefault ? '' : '内容'),
      initialDefault: rename ? isDefault : !hasDefault,
      canDefault: !hasDefault,
      check: (label, asDefault) => slotLabelProblem(_temp, label, asDefault: asDefault, slotNodeId: rename ? id : null),
    );
    if (r == null || !mounted) return;
    LcOpResult? result;
    _apply((d) => result = rename ? renameSlot(d, id, label: r.label, asDefault: r.asDefault) : makeSlot(d, id, label: r.label, asDefault: r.asDefault));
    if (result?.error != null) return tellComponentProblem(context, result!.error!);
    final select = result?.nodeId;
    if (select != null && _temp.find(select) != null) setState(() => _selected = select);
  }

  /// 取消插槽：已有实例在里面填了东西的，先说清楚有几处、内容会挪到哪儿，确认了再做（内容挪到实例后面，不删）。
  Future<void> _unwrapSlot(String id) async {
    final node = _temp.find(id);
    if (node == null || node.type != 'slot') return;
    final name = lcSlotNameOf(node);
    final fill = slotFillCount(_real, widget.componentId, name);
    if (fill.nodes > 0) {
      final ok = await confirmDialog(
        context,
        title: '取消插槽「${slotNodeLabel(node)}」',
        message: '有 ${fill.instances} 个用到这个组件的地方在这个插槽里填了东西（共 ${fill.nodes} 个组件）。取消以后，这些内容会挪到各自那个组件的后面，不会删掉。',
        confirmLabel: '取消插槽',
      );
      if (!ok || !mounted) return;
    }
    String? select;
    _apply((d) => select = unwrapSlot(d, id).nodeId, onReal: (real) => evictSlotContent(real, widget.componentId, name));
    if (_temp.find(id) == null) setState(() => _selected = select);
  }

  void _nodeAction(String v, String id) {
    if (v == 'multi') return multiEnter(id);
    if (v == 'slot' || v == 'slotRename') return unawaited(_nameSlot(id, rename: v == 'slotRename'));
    if (v == 'slotUnwrap') return unawaited(_unwrapSlot(id));
    final (done, select) = runLcNodeAction(v, _temp, id, _apply);
    if (done) {
      setState(() => _selected = select);
      if (v == 'clip') showEditorHint(context, '已复制，长按别的组件可以“粘贴到它后面”');
    } else if (v == 'delete') {
      _apply((d) => d.remove(id));
      setState(() => _selected = null);
    }
  }

  Future<void> _openComponentProps() async {
    await showComponentPropsSheet(context, doc: _real, onEdit: (change) => widget.onEdit((d) => change(_real = d)), componentId: widget.componentId);
    // 那边改的是定义本身（绑定、属性）：按新的定义重来，这一页自己的撤销记录也从这里重新开始。
    if (mounted) setState(_reload);
  }

  void _openView() {
    final canvas = _bench.currentState?.canvas;
    if (canvas == null) return;
    unawaited(
      showCanvasViewSheet(
        context,
        canvas: canvas,
        presetWidth: () => _presetWidth,
        onPresetWidth: (v) => setState(() => _presetWidth = v),
        showBoxModel: () => _showBoxModel,
        onShowBoxModel: (v) => setState(() => _showBoxModel = v),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final node = _selected == null ? null : _temp.find(_selected!);
    final name = _real.component(widget.componentId)?.name ?? _temp.title;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: ShellAppBar(
        background: context.colors.surfaceMuted,
        title: '编辑组件',
        subtitle: name,
        actions: [
          PopupMenuButton<String>(
            tooltip: '更多',
            onSelected: (v) => v == 'view' ? _openView() : unawaited(_openComponentProps()),
            itemBuilder: (_) => const [PopupMenuItem(value: 'props', child: Text('可配置的属性')), PopupMenuItem(value: 'view', child: Text('屏宽与缩放'))],
          ),
          TextButton(key: const ValueKey('comp-editor-done'), onPressed: () => Navigator.pop(context), child: const Text('完成')),
        ],
      ),
      body: LcImageScope(
        resolve: (src) => widget.images?.resolve(src),
        child: EditorWorkbench(
          key: _bench,
          onEdit: _apply,
          pickImage: widget.images == null ? null : (from) => widget.images!.pick(context, from),
          onNodeMenu: (id, at) => unawaited(_nodeMenu(id, at)),
          doc: _temp,
          selected: multiOn ? null : _selected,
          marked: multiIds,
          onSelect: (id) => multiOn ? multiTap(id) : _select(id),
          onAdd: _addByTap,
          onDrop: _drop,
          canDrop: _canDrop,
          // 最外层不能删（组件只能有一个最外层）。
          canDelete: (id) => id != _top?.id,
          onDelete: (id) {
            if (multiDeleteDragged(id)) return;
            _apply((d) => d.remove(id));
            setState(() => _selected = null);
          },
          onResize: _resize,
          recents: widget.recents,
          onLayers: () => unawaited(_openLayers()),
          onUndo: _history.canUndo ? () => _restore(_history.undo()) : null,
          onRedo: _history.canRedo ? () => _restore(_history.redo()) : null,
          presetWidth: _presetWidth,
          showBoxModel: _showBoxModel,
          selectionBar: multiOn ? multiBar() : (node == null ? null : _selectionBar(context, node)),
        ),
      ),
    );
  }

  Widget _selectionBar(BuildContext context, LcNode node) {
    final isTop = identical(node, _top);
    return EditorSelectionBar(
      icon: lcIcon(node.type),
      label: '${node.type == 'component' ? componentLabel(_temp, node) : (node.type == 'slot' ? '插槽 · ${slotNodeLabel(node)}' : node.spec.label)}${isTop ? '（最外层）' : ''}',
      onParent: isTop
          ? null
          : () {
              final parent = _temp.parentOf(node.id);
              if (parent != null && parent.id != kComponentEditRootId) _select(parent.id);
            },
      actions: [
        EditorSelectionBar.primary('常用', () => _bench.currentState?.openInspector(InspectorPage.common)),
        EditorSelectionBar.outlined('样式', () => _bench.currentState?.openInspector(InspectorPage.style)),
        // 最外层不能移动、复制、删除（组件只能有一个最外层）：剪贴板里有东西时只有“粘贴到里面”。
        if (!isTop)
          LcNodeMoreButton(node: node, componentActions: false, slotActions: true, onAction: (v) => _nodeAction(v, node.id))
        else if ((lcClipboardHasContent && node.isContainer) || (kSlotHostTypes.contains(node.type) && slotInside(node) == null))
          LcNodeMoreButton(node: node, componentActions: false, slotActions: true, fixed: true, onAction: (v) => _nodeAction(v, node.id))
        else
          const SizedBox(width: Space.x3),
      ],
    );
  }
}
