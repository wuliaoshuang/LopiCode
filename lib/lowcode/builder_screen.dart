// 设计约束（低代码搭建 · 390×844）
// - 画布是主角：可缩放 / 平移，按组件的最终样式渲染（画布本身在 canvas_view.dart）。
// - 底部固定一条组件栏：长按拖到画布，或者点一下直接加进当前选中的容器。
// - 选中组件后，组件栏上方出现一行操作：名字在左；属性 / 样式 / 事件 在右；上移、下移、复制、删除收进“更多操作”。
// - 属性、样式、图层、自定义组件都放进底部面板，积木逻辑是单独一页，不和画布抢地方。撤销 / 重做在顶栏。
// - 拖动时才显示插入位置（色条），平时不干扰画面。
import 'dart:async';
import 'dart:io';

import 'package:lopicode/agent/agent_tools.dart';
import 'package:lopicode/core/templates.dart';
import 'package:lopicode/lowcode/canvas_view.dart';
import 'package:lopicode/lowcode/code_sheet.dart';
import 'package:lopicode/lowcode/component_sheet.dart';
import 'package:lopicode/lowcode/export_dart.dart';
import 'package:lopicode/lowcode/export_sheet.dart';
import 'package:lopicode/lowcode/layers_sheet.dart';
import 'package:lopicode/lowcode/logic_edit.dart';
import 'package:lopicode/lowcode/logic_screen.dart';
import 'package:lopicode/lowcode/model.dart';
import 'package:lopicode/lowcode/palette_widgets.dart';
import 'package:lopicode/lowcode/props_sheet.dart';
import 'package:lopicode/lowcode/style_editor_sheet.dart';
import 'package:lopicode/lowcode/style_model.dart';
import 'package:lopicode/project_session.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/shell.dart';
import 'package:lopicode/ui/widgets.dart';
import 'package:material_ui/material_ui.dart';

// 这两样原来就定义在这个文件里，别处（打包页等）还从这里引用。
export 'package:lopicode/lowcode/code_sheet.dart' show CodeSheetBody;
export 'package:lopicode/lowcode/palette_widgets.dart' show lcIcon;

class BuilderScreen extends StatefulWidget {
  const BuilderScreen({super.key, required this.session, this.initialSelection});
  final ProjectSession session;

  /// 测试 / 截图用。
  final String? initialSelection;

  @override
  State<BuilderScreen> createState() => _BuilderScreenState();
}

class _BuilderScreenState extends State<BuilderScreen> {
  LcDocument? _doc;
  LcHistory? _history;
  String? _loadError;
  bool _missing = false;
  String? _selected;
  bool _dragging = false;
  Future<void> _saving = Future.value();

  File get _file => File(widget.session.guard.resolve(kLowcodePageFile));

  @override
  void initState() {
    super.initState();
    _selected = widget.initialSelection;
    _load();
  }

  Future<void> _load() async {
    try {
      if (!await _file.exists()) {
        if (mounted) setState(() => _missing = true);
        return;
      }
      final doc = LcDocument.parse(await _file.readAsString());
      if (!mounted) return;
      setState(() {
        _doc = doc;
        _history = LcHistory(doc);
        _missing = false;
        _loadError = null;
      });
    } on FormatException catch (e) {
      if (mounted) setState(() => _loadError = e.message);
    } on FileSystemException {
      if (mounted) setState(() => _loadError = '读不了 $kLowcodePageFile');
    }
  }

  Future<void> _createFresh() async {
    final doc = LcDocument.starter(widget.session.project.name);
    await saveLowcodePage(widget.session.guard, doc);
    widget.session.filesChanged();
    await _load();
  }

  /// 所有修改都走这里：改模型 → 记历史 → 存盘并重新导出网页。
  void _apply(void Function(LcDocument doc) change) {
    final doc = _doc!;
    setState(() => change(doc));
    _history!.record(doc);
    _save();
  }

  void _save() {
    final snapshot = LcDocument.parse(_doc!.encode());
    _saving = _saving.then((_) async {
      try {
        await saveLowcodePage(widget.session.guard, snapshot);
        widget.session.filesChanged();
      } on FileSystemException {
        if (mounted) showSnack(context, '保存失败');
      }
    });
  }

  void _restore(LcDocument? doc) {
    if (doc == null) return;
    setState(() {
      _doc = doc;
      if (_selected != null && doc.find(_selected!) == null) _selected = null;
    });
    _save();
  }

  /// 点组件栏：加进选中的容器；选中的不是容器就加在它后面；没选中加到页面末尾。
  void _addByTap(String type) {
    final doc = _doc!;
    final sel = _selected == null ? null : doc.find(_selected!);
    final node = doc.newNode(type);
    _apply((d) {
      if (sel != null && sel.isContainer) {
        d.insert(sel.id, node);
      } else if (sel != null) {
        final parent = d.parentOf(sel.id)!;
        d.insert(parent.id, node, parent.children.indexOf(sel) + 1);
      } else {
        d.insert(d.root.id, node);
      }
    });
    setState(() => _selected = node.id);
  }

  void _drop(LcDrag drag, String parentId, int index) {
    if (drag.type != null) {
      final node = _doc!.newNode(drag.type!);
      _apply((d) => d.insert(parentId, node, index));
      setState(() => _selected = node.id);
    } else {
      _apply((d) => d.move(drag.nodeId!, parentId, index));
    }
  }

  bool _canDrop(LcDrag drag, String parentId) {
    if (drag.nodeId == null) return true;
    final node = _doc!.find(drag.nodeId!);
    if (node == null) return false;
    // 不能拖进自己或自己的后代里
    bool contains(LcNode n) => n.id == parentId || n.children.any(contains);
    return !contains(node);
  }

  void _setDragging(bool v) {
    if (mounted && _dragging != v) setState(() => _dragging = v);
  }

  void _openProps() {
    final node = _doc!.find(_selected!);
    if (node == null) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      barrierColor: Colors.black26,
      builder: (_) => PropertySheet(
        node: node,
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

  void _openLayers() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => LayerSheet(
        doc: _doc!,
        selected: _selected,
        onSelect: (id) {
          Navigator.pop(sheetContext);
          setState(() => _selected = id);
        },
      ),
    );
  }

  Future<void> _exportDart() async {
    final code = exportDart(_doc!);
    const path = 'export/page.dart';
    try {
      final file = File(widget.session.guard.resolve(path));
      await file.parent.create(recursive: true);
      await file.writeAsString(code);
      widget.session.filesChanged();
    } on FileSystemException {
      if (mounted) showSnack(context, '写入 $path 失败');
      return;
    }
    if (!mounted) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => CodeSheetBody(title: 'Flutter 代码', note: '已保存到项目的 $path', code: code),
    );
  }

  Future<void> _renamePage() async {
    final name = await promptDialog(context, title: '页面标题', initial: _doc!.title, confirmLabel: '保存');
    if (name == null || name.trim().isEmpty) return;
    _apply((d) => d.title = name.trim());
  }

  /// 拖柄松手：把宽 / 高写进组件自己的样式。整次拖动只走这一次统一入口，所以只记一条撤销。
  void _resize(String id, int? width, int? height) => _apply((d) {
    final n = d.find(id);
    if (n == null) return;
    final style = LcStyle(n.style);
    if (width != null) style.setLength('width', LcLength.px(width.toDouble()));
    if (height != null) style.setLength('height', LcLength.px(height.toDouble()));
  });

  /// 删除组件。积木逻辑里还有地方在用它（或它里面的组件）时先问一句；
  /// 清逻辑和删组件放在同一次修改里，撤销一次就能全部恢复。
  Future<void> _delete(LcNode node) async {
    final ids = <String>[];
    void walk(LcNode n) {
      ids.add(n.id);
      n.children.forEach(walk);
    }

    walk(node);
    final refs = ids.fold<int>(0, (sum, id) => sum + _doc!.logic.nodeRefCount(id));
    if (refs > 0) {
      final ok = await confirmDialog(context, title: '删除${node.spec.label}', message: '有 $refs 处积木逻辑在用这个组件，删除会一并清掉。', confirmLabel: '删除', danger: true);
      if (!ok || !mounted) return;
    }
    _apply((d) {
      if (d.find(node.id) == null) return;
      for (final id in ids) {
        d.logic.removeNodeRefs(id);
      }
      d.remove(node.id);
    });
    setState(() => _selected = null);
  }

  // 面板 / 页面开着的时候文档可能被改过（甚至被撤销换成另一个对象）：关掉以后重画一遍，选中的组件没了就取消选中。
  void _refresh() {
    if (!mounted) return;
    setState(() {
      if (_selected != null && _doc?.find(_selected!) == null) _selected = null;
    });
  }

  Future<void> _openStyle(String id) async {
    await showStyleEditor(context, doc: _doc!, nodeId: id, onEdit: _apply);
    _refresh();
  }

  Future<void> _openLogic([String? nodeId]) async {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => LogicScreen(doc: _doc!, onEdit: _apply, initialNodeId: nodeId),
      ),
    );
    _refresh();
  }

  Future<void> _openComponents() async {
    final id = await showComponentSheet(context, doc: _doc!, onEdit: _apply, selectedNodeId: _selected);
    if (!mounted) return;
    if (id != null && _doc?.find(id) != null) _selected = id;
    _refresh();
  }

  Future<void> _openFrameworkExport() async {
    await showFrameworkExport(context, doc: _doc!, session: widget.session);
    _refresh();
  }

  void _onMenu(String v) {
    switch (v) {
      case 'preview':
        final shell = ShellScope.maybeOf(context);
        if (shell != null) {
          shell.go(ShellDest.preview);
        } else {
          Navigator.pop(context, 'preview');
        }
      case 'dart':
        unawaited(_exportDart());
      case 'framework':
        unawaited(_openFrameworkExport());
      case 'logic':
        unawaited(_openLogic());
      case 'components':
        unawaited(_openComponents());
      case 'title':
        unawaited(_renamePage());
    }
  }

  @override
  Widget build(BuildContext context) {
    final doc = _doc;
    final history = _history;
    final node = doc == null || _selected == null ? null : doc.find(_selected!);
    return Scaffold(
      appBar: ShellAppBar(
        title: '低代码搭建',
        subtitle: doc?.title,
        actions: doc == null
            ? null
            : [
                IconButton(tooltip: '撤销', icon: const Icon(Icons.undo), onPressed: history!.canUndo ? () => _restore(history.undo()) : null),
                IconButton(tooltip: '重做', icon: const Icon(Icons.redo), onPressed: history.canRedo ? () => _restore(history.redo()) : null),
                IconButton(tooltip: '图层', icon: const Icon(Icons.layers_outlined), onPressed: _openLayers),
                PopupMenuButton<String>(
                  tooltip: '更多',
                  onSelected: _onMenu,
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'preview', child: Text('在预览里打开网页')),
                    PopupMenuItem(value: 'logic', child: Text('积木逻辑')),
                    PopupMenuItem(value: 'components', child: Text('自定义组件')),
                    PopupMenuItem(value: 'dart', child: Text('导出 Flutter 代码')),
                    PopupMenuItem(value: 'framework', child: Text('导出 Vue / React')),
                    PopupMenuItem(value: 'title', child: Text('修改页面标题')),
                  ],
                ),
              ],
      ),
      body: _loadError != null
          ? EmptyState(
              icon: Icons.error_outline,
              title: '页面文件打不开',
              message: '$kLowcodePageFile 的内容有问题：$_loadError',
              action: OutlinedButton(onPressed: _createFresh, child: const Text('用一个新页面覆盖')),
            )
          : _missing
          ? EmptyState(
              icon: Icons.dashboard_customize_outlined,
              title: '这个项目还没有低代码页面',
              message: '新建后会在项目里生成 $kLowcodePageFile，\n并自动导出 index.html 和 style.css。',
              action: FilledButton(onPressed: _createFresh, child: const Text('新建页面')),
            )
          : doc == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: CanvasView(
                    doc: doc,
                    selected: _selected,
                    dragging: _dragging,
                    onSelect: (id) => setState(() => _selected = id),
                    onDrop: _drop,
                    canDrop: _canDrop,
                    onDragging: _setDragging,
                    onResize: _resize,
                  ),
                ),
                if (node != null) _selectionBar(context, node),
                PaletteBar(onTap: _addByTap, onDragging: _setDragging),
              ],
            ),
    );
  }

  Widget _selectionBar(BuildContext context, LcNode node) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final compact = FilledButton.styleFrom(
      minimumSize: const Size(0, 36),
      padding: const EdgeInsets.symmetric(horizontal: Space.x3),
    );
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
            child: Text(node.spec.label, style: t.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          FilledButton(onPressed: _openProps, style: compact, child: const Text('属性')),
          const SizedBox(width: Space.x2),
          OutlinedButton(onPressed: () => _openStyle(node.id), style: compact, child: const Text('样式')),
          IconButton(tooltip: '事件', visualDensity: VisualDensity.compact, icon: const Icon(Icons.bolt_outlined, size: 20), onPressed: () => _openLogic(node.id)),
          // 页面本身不能移动、复制、删除。
          if (node.type != 'page')
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
                    unawaited(_delete(node));
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
