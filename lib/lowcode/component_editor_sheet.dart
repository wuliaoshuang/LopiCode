// 设计约束（低代码 · 编辑组件的内容 · 390×844）
// - 整页：和搭建页同一套排法，只是画布上放的不是页面，而是“这个组件的内容”（外面垫一张空白页当背景）。
//   顶栏：标题“编辑组件”+ 组件名；右边 撤销 / 重做 /“⋮”（图层、可配置的属性）/ 主操作“完成”。
//   中间画布；选中控件后底下出现一行操作（名字在左；属性 / 样式 在右；上移、下移、复制、删除收进“更多操作”）；最底下组件栏。
// - 这里没有积木逻辑的入口：组件里面的控件不支持逻辑。
// - 组件最外层只能有一个控件：最外层不能删、不能移走，旁边也放不了别的控件（要放就放进它里面）。
// - 每改一下立刻写回组件定义（搭建页那边记一条撤销），所以回到页面时所有实例已经是新样子；“完成”只是关掉这一页。
import 'dart:async';

import 'package:lopicode/lowcode/canvas_view.dart';
import 'package:lopicode/lowcode/component_model.dart';
import 'package:lopicode/lowcode/component_ops.dart';
import 'package:lopicode/lowcode/component_props_sheet.dart';
import 'package:lopicode/lowcode/component_values_widgets.dart';
import 'package:lopicode/lowcode/edit_types.dart';
import 'package:lopicode/lowcode/layers_sheet.dart';
import 'package:lopicode/lowcode/model.dart';
import 'package:lopicode/lowcode/palette_widgets.dart';
import 'package:lopicode/lowcode/props_sheet.dart';
import 'package:lopicode/lowcode/style_editor_sheet.dart';
import 'package:lopicode/lowcode/style_model.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/shell.dart';
import 'package:material_ui/material_ui.dart';

/// “编辑组件”用的临时页面的根 id。带下划线：定义里的节点 id 只有字母数字，不会和它撞。
const String kComponentEditRootId = 'page_';

void _walk(LcNode n, void Function(LcNode n) visit) {
  visit(n);
  for (final c in n.children) {
    _walk(c, visit);
  }
}

/// 造一份只在“编辑组件”时用的临时文档：一张空白页，里面只放这个组件的内容（拷贝）。
/// 搭建页现成的画布、属性、样式面板都能直接作用在它上面；改完用 [applyComponentEditing] 写回去。
/// 临时文档里带着别的组件定义（拷贝，供里面套的实例显示、供组件栏列出），会造成循环的那些不带。
LcDocument? componentEditingDocument(LcDocument doc, String componentId) {
  final def = doc.component(componentId);
  if (def == null) return null;
  return LcDocument(
    title: def.name,
    root: LcNode(id: kComponentEditRootId, type: 'page', props: Map.of(lcSpecs['page']!.defaults), children: [copyLcTree(def.root)]),
    components: [
      for (final c in doc.components)
        if (c.id != componentId && !wouldCycle(doc, componentId, c.id))
          LcComponentDef(
            id: c.id,
            name: c.name,
            props: [for (final p in c.props) LcComponentProp(name: p.name, type: p.type, defaultValue: p.defaultValue)],
            root: copyLcTree(c.root),
          ),
    ],
  );
}

/// 把“编辑组件”的临时文档写回定义：定义的 id、名字、props 都不动，所以实例不会断开。
/// 临时页面里必须正好有一个最外层控件；接到已经不存在的 prop 上的绑定顺手清掉。失败时什么都不改。
LcOpResult applyComponentEditing(LcDocument doc, String componentId, LcDocument editing) {
  final def = doc.component(componentId);
  if (def == null) return const LcOpResult.fail('这个组件已经不存在了');
  if (editing.root.children.length != 1) return const LcOpResult.fail('组件最外层只能有一个控件');
  final root = copyLcTree(editing.root.children.single);
  var cycle = false;
  final seen = <String>{};
  var next = 1;
  _walk(root, (n) {
    final ref = n.props['ref'];
    if (n.type == 'component' && ref is String && wouldCycle(doc, componentId, ref)) cycle = true;
    // 定义里的 id 只能是字母数字、互不重复（临时文档里新加的节点是 n数字，本来就合规矩；这里防万一）。
    if (!RegExp(r'^[A-Za-z0-9]+$').hasMatch(n.id) || !seen.add(n.id)) {
      while (!seen.add('e$next')) {
        next++;
      }
      n.id = 'e$next';
    }
    n.bind.removeWhere((attr, name) {
      final p = def.prop(name);
      return p == null || !bindablePropsFor(n.type).contains(attr) || !propTypeFitsAttr(p.type, attr);
    });
  });
  if (cycle) return const LcOpResult.fail('组件里不能放它自己（或者里面用到了它的组件）');
  def.root = root;
  return LcOpResult.ok(componentId: componentId);
}

/// 打开“编辑组件内容”页。关掉后组件定义已经是改好的（每一步都即时写回）。
Future<void> showComponentEditor(BuildContext context, {required LcDocument doc, required LcEdit onEdit, required String componentId}) async {
  if (doc.component(componentId) == null) {
    await tellComponentProblem(context, '这个组件的定义已经不存在了。');
    return;
  }
  await Navigator.push(
    context,
    MaterialPageRoute<void>(
      builder: (_) => _ComponentEditor(doc: doc, onEdit: onEdit, componentId: componentId),
    ),
  );
}

class _ComponentEditor extends StatefulWidget {
  const _ComponentEditor({required this.doc, required this.onEdit, required this.componentId});
  final LcDocument doc;
  final LcEdit onEdit;
  final String componentId;

  @override
  State<_ComponentEditor> createState() => _ComponentEditorState();
}

class _ComponentEditorState extends State<_ComponentEditor> {
  /// 搭建页手里的文档（每次写回时更新成它当时用的那个对象）。
  late LcDocument _real = widget.doc;
  late LcDocument _temp;
  late LcHistory _history;
  String? _selected;
  bool _dragging = false;

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

  /// 把临时文档写回定义（搭建页记一条撤销）。写不回去返回原因。
  String? _writeBack() {
    LcOpResult? result;
    widget.onEdit((d) {
      _real = d;
      result = applyComponentEditing(d, widget.componentId, _temp);
    });
    return result?.error;
  }

  /// 这一页所有的修改都走这里：改临时文档 → 写回定义；写不回去（比如最外层被弄没了）就退回改之前的样子并说明原因。
  void _apply(void Function(LcDocument doc) change) {
    final before = _temp.encode();
    setState(() => change(_temp));
    if (_temp.encode() == before) return;
    final error = _writeBack();
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

  void _addByTap(String type, [String? ref]) {
    final top = _top;
    final sel = _selected == null ? null : _temp.find(_selected!);
    final target = sel ?? top;
    if (target == null) return;
    final node = _fresh(type, ref);
    if (target.isContainer) {
      _apply((d) => d.insert(target.id, node));
    } else if (identical(target, top)) {
      unawaited(tellComponentProblem(context, '组件最外层只能有一个控件。想放多个控件，就让最外层是一个容器（容器、行、列、卡片），再把别的放进去。'));
      return;
    } else {
      final parent = _temp.parentOf(target.id)!;
      _apply((d) => d.insert(parent.id, node, parent.children.indexOf(target) + 1));
    }
    if (_temp.find(node.id) != null) setState(() => _selected = node.id);
  }

  void _drop(LcDrag drag, String parentId, int index) {
    if (drag.type != null) {
      final node = _fresh(drag.type!, drag.ref);
      _apply((d) => d.insert(parentId, node, index));
      if (_temp.find(node.id) != null) setState(() => _selected = node.id);
    } else {
      _apply((d) => d.move(drag.nodeId!, parentId, index));
    }
  }

  bool _canDrop(LcDrag drag, String parentId) {
    // 垫在下面的页面里只能有组件最外层那一个控件。
    if (parentId == kComponentEditRootId) return false;
    if (drag.nodeId == null) return true;
    final node = _temp.find(drag.nodeId!);
    if (node == null) return false;
    bool contains(LcNode n) => n.id == parentId || n.children.any(contains);
    return !contains(node);
  }

  void _setDragging(bool v) {
    if (mounted && _dragging != v) setState(() => _dragging = v);
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
    });
  }

  void _openProps(LcNode node) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      barrierColor: Colors.black26,
      builder: (_) => PropertySheet(
        node: node,
        doc: _temp,
        onChanged: (key, value) => _apply((d) {
          final n = d.find(node.id);
          if (n == null) return;
          if (value == null) {
            n.props.remove(key);
          } else {
            n.props[key] = value;
          }
        }),
      ),
    );
  }

  Future<void> _openStyle(String id) async {
    await showStyleEditor(context, doc: _temp, nodeId: id, onEdit: _apply);
    _refresh();
  }

  void _openLayers() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => LayerSheet(
        doc: _temp,
        selected: _selected,
        onSelect: (id) {
          Navigator.pop(sheetContext);
          _select(id);
        },
      ),
    );
  }

  Future<void> _openComponentProps() async {
    await showComponentPropsSheet(context, doc: _real, onEdit: (change) => widget.onEdit((d) => change(_real = d)), componentId: widget.componentId);
    // 那边改的是定义本身（绑定、属性）：按新的定义重来，这一页自己的撤销记录也从这里重新开始。
    if (mounted) setState(_reload);
  }

  @override
  Widget build(BuildContext context) {
    final node = _selected == null ? null : _temp.find(_selected!);
    final name = _real.component(widget.componentId)?.name ?? _temp.title;
    return Scaffold(
      appBar: ShellAppBar(
        title: '编辑组件',
        subtitle: name,
        actions: [
          IconButton(tooltip: '撤销', icon: const Icon(Icons.undo), onPressed: _history.canUndo ? () => _restore(_history.undo()) : null),
          IconButton(tooltip: '重做', icon: const Icon(Icons.redo), onPressed: _history.canRedo ? () => _restore(_history.redo()) : null),
          PopupMenuButton<String>(
            tooltip: '更多',
            onSelected: (v) => v == 'layers' ? _openLayers() : unawaited(_openComponentProps()),
            itemBuilder: (_) => const [PopupMenuItem(value: 'layers', child: Text('图层')), PopupMenuItem(value: 'props', child: Text('可配置的属性'))],
          ),
          TextButton(key: const ValueKey('comp-editor-done'), onPressed: () => Navigator.pop(context), child: const Text('完成')),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: CanvasView(doc: _temp, selected: _selected, dragging: _dragging, onSelect: _select, onDrop: _drop, canDrop: _canDrop, onDragging: _setDragging, onResize: _resize),
          ),
          if (node != null) _selectionBar(context, node),
          PaletteBar(onTap: _addByTap, onDragging: _setDragging, components: _temp.components),
        ],
      ),
    );
  }

  Widget _selectionBar(BuildContext context, LcNode node) {
    final c = context.colors;
    final compact = FilledButton.styleFrom(
      minimumSize: const Size(0, 36),
      padding: const EdgeInsets.symmetric(horizontal: Space.x3),
    );
    final isTop = identical(node, _top);
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(top: BorderSide(color: c.border)),
      ),
      padding: const EdgeInsets.only(left: Space.x4, right: Space.x1),
      height: 48,
      child: Row(
        children: [
          Icon(lcIcon(node.type), size: 18, color: c.accent),
          const SizedBox(width: Space.x2),
          Expanded(
            child: Text(
              '${node.type == 'component' ? componentLabel(_temp, node) : node.spec.label}${isTop ? '（最外层）' : ''}',
              style: Theme.of(context).textTheme.titleSmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          FilledButton(onPressed: () => _openProps(node), style: compact, child: const Text('属性')),
          const SizedBox(width: Space.x2),
          OutlinedButton(onPressed: () => _openStyle(node.id), style: compact, child: const Text('样式')),
          // 最外层不能移动、复制、删除（组件只能有一个最外层）。
          if (isTop)
            const SizedBox(width: Space.x3)
          else
            PopupMenuButton<String>(
              tooltip: '更多操作',
              icon: const Icon(Icons.more_horiz, size: 20),
              onSelected: (v) {
                switch (v) {
                  case 'up':
                    _apply((d) => d.shift(node.id, -1));
                  case 'down':
                    _apply((d) => d.shift(node.id, 1));
                  case 'copy':
                    String? copy;
                    _apply((d) => copy = d.duplicate(node.id));
                    if (copy != null) setState(() => _selected = copy);
                  case 'delete':
                    _apply((d) => d.remove(node.id));
                    setState(() => _selected = null);
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'up', child: Text('上移')),
                PopupMenuItem(value: 'down', child: Text('下移')),
                PopupMenuItem(value: 'copy', child: Text('复制')),
                PopupMenuItem(value: 'delete', child: Text('删除')),
              ],
            ),
        ],
      ),
    );
  }
}
