// 设计约束（低代码 · 自定义组件面板 · 390×844）
// - 底部面板，从上到下：标题 → 一句说明 →（选中了能存的控件时）唯一的主操作“把选中的控件存成组件”→ 组件清单。
// - 清单一行一个组件：名字在上，下面一行弱化的“用了几次 · 几个可配置属性”；行尾一个“插入”按钮；
//   改名 / 编辑属性 / 编辑内容 / 删除收进行尾的“⋮”。
// - 没有组件时显示怎么创建（在画布上选中一个控件 → 更多操作 → 存成组件）。
// - 删除要确认；还有地方在用时让人选：把用到的地方拆成普通控件再删，还是连用到的地方一起删。
// - 每次操作一条撤销记录。“插入”和“存成组件”做完就关面板，搭建页选中那个实例。
import 'package:lopicode/lowcode/component_editor_sheet.dart';
import 'package:lopicode/lowcode/component_model.dart';
import 'package:lopicode/lowcode/component_ops.dart';
import 'package:lopicode/lowcode/component_props_sheet.dart';
import 'package:lopicode/lowcode/component_values_widgets.dart';
import 'package:lopicode/lowcode/edit_types.dart';
import 'package:lopicode/lowcode/image_pick_sheet.dart';
import 'package:lopicode/lowcode/model.dart';
import 'package:lopicode/lowcode/palette_catalog.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/widgets.dart';
import 'package:material_ui/material_ui.dart';

export 'package:lopicode/lowcode/component_editor_sheet.dart' show showComponentEditor;
export 'package:lopicode/lowcode/component_ops.dart' show componentLabel;

/// 自定义组件：列出已有组件（可插入、改名、改 props、删除），并可把 [selectedNodeId] 那棵子树存成新组件。
/// 返回新插入 / 新变成实例的节点 id（没有就是 null），搭建页拿去选中。
Future<String?> showComponentSheet(BuildContext context, {required LcDocument doc, required LcEdit onEdit, String? selectedNodeId, PaletteRecents? recents, LcImages? images}) =>
    showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ComponentSheet(doc: doc, onEdit: onEdit, selectedNodeId: selectedNodeId, recents: recents, images: images),
    );

/// “存成组件”：问一个名字，把 [nodeId] 那棵子树存成新组件、原位置换成实例（一条撤销记录）。
/// 返回实例的 id；取消或存不了返回 null（存不了时会弹一句原因）。
Future<String?> saveAsComponentFlow(BuildContext context, {required LcDocument doc, required LcEdit onEdit, required String nodeId}) async {
  final blocked = canSaveAsComponent(doc, nodeId);
  if (blocked != null) {
    await tellComponentProblem(context, blocked);
    return null;
  }
  final name = await askComponentText(
    context,
    title: '存成组件',
    initial: uniqueComponentName(doc, '组件 ${doc.components.length + 1}'),
    hint: '给组件起个名字',
    confirmLabel: '完成',
    validate: validateComponentName,
  );
  if (name == null) return null;
  LcOpResult? result;
  onEdit((d) => result = saveAsComponent(d, nodeId, name));
  final error = result?.error;
  if (error != null && context.mounted) await tellComponentProblem(context, error);
  return result?.nodeId;
}

/// “拆开成普通控件”：确认后把实例换成组件内容的拷贝（一条撤销记录）。返回有没有拆。
Future<bool> detachInstanceFlow(BuildContext context, {required LcDocument doc, required LcEdit onEdit, required String instanceId}) async {
  final node = doc.find(instanceId);
  if (node == null) return false;
  final ok = await confirmDialog(context, title: '拆开成普通控件', message: '拆开以后它就是一组普通控件，不再跟着组件「${componentLabel(doc, node)}」一起变。', confirmLabel: '拆开');
  if (!ok) return false;
  LcOpResult? result;
  onEdit((d) => result = detachInstance(d, instanceId));
  final error = result?.error;
  if (error != null && context.mounted) await tellComponentProblem(context, error);
  return error == null;
}

class _ComponentSheet extends StatefulWidget {
  const _ComponentSheet({required this.doc, required this.onEdit, required this.selectedNodeId, this.recents, this.images});
  final LcImages? images;

  /// 组件盒的“常用”（传给“编辑组件”页，和搭建页用同一份）。
  final PaletteRecents? recents;
  final LcDocument doc;
  final LcEdit onEdit;
  final String? selectedNodeId;

  @override
  State<_ComponentSheet> createState() => _ComponentSheetState();
}

class _ComponentSheetState extends State<_ComponentSheet> {
  late LcDocument _doc = widget.doc;

  void _edit(void Function(LcDocument d) change) => widget.onEdit((d) => change(_doc = d));

  Future<void> _run(LcOpResult Function(LcDocument d) op) async {
    LcOpResult? result;
    _edit((d) => result = op(d));
    if (!mounted) return;
    setState(() {});
    final error = result?.error;
    if (error != null) await tellComponentProblem(context, error);
  }

  Future<void> _saveSelected(String nodeId) async {
    final id = await saveAsComponentFlow(context, doc: _doc, onEdit: _edit, nodeId: nodeId);
    if (!mounted) return;
    if (id != null) {
      Navigator.pop(context, id);
    } else {
      setState(() {});
    }
  }

  void _insert(LcComponentDef def) {
    LcOpResult? result;
    _edit((d) => result = insertInstance(d, def.id, nearId: widget.selectedNodeId));
    final id = result?.nodeId;
    if (id != null) {
      Navigator.pop(context, id);
    } else {
      setState(() {});
    }
  }

  Future<void> _rename(LcComponentDef def) async {
    final id = def.id;
    final name = await askComponentText(
      context,
      title: '组件改名',
      initial: def.name,
      confirmLabel: '保存',
      validate: (s) => validateComponentName(s) ?? (_doc.components.any((c) => c.id != id && c.name == s.trim()) ? '已经有一个叫这个名字的组件了' : null),
    );
    if (name == null || !mounted) return;
    await _run((d) => renameComponent(d, id, name));
  }

  Future<void> _editProps(LcComponentDef def) async {
    await showComponentPropsSheet(context, doc: _doc, onEdit: _edit, componentId: def.id);
    if (mounted) setState(() {});
  }

  Future<void> _editContent(LcComponentDef def) async {
    await showComponentEditor(context, doc: _doc, onEdit: _edit, componentId: def.id, recents: widget.recents, images: widget.images);
    if (mounted) setState(() {});
  }

  Future<void> _delete(LcComponentDef def) async {
    final id = def.id;
    final uses = componentUseCount(_doc, id);
    if (uses == 0) {
      final ok = await confirmDialog(context, title: '删除组件「${def.name}」', message: '现在没有地方在用它。删除后可以用撤销找回。', confirmLabel: '删除', danger: true);
      if (!ok || !mounted) return;
      await _run((d) => deleteComponent(d, id));
      return;
    }
    final c = context.colors;
    final mode = await showDialog<LcDeleteInstances>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('删除组件「${def.name}」'),
        content: Text('还有 $uses 处在用它。用到的地方怎么办？'),
        actionsOverflowDirection: VerticalDirection.down,
        actions: [
          TextButton(key: const ValueKey('comp-delete-detach'), onPressed: () => Navigator.pop(context, LcDeleteInstances.detach), child: const Text('拆成普通控件留着')),
          TextButton(
            key: const ValueKey('comp-delete-remove'),
            onPressed: () => Navigator.pop(context, LcDeleteInstances.remove),
            style: TextButton.styleFrom(foregroundColor: c.danger),
            child: const Text('连用到的地方一起删'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            style: TextButton.styleFrom(foregroundColor: c.textMuted),
            child: const Text('取消'),
          ),
        ],
      ),
    );
    if (mode == null || !mounted) return;
    await _run((d) => deleteComponent(d, id, instances: mode));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final selectedId = widget.selectedNodeId;
    final selected = selectedId == null ? null : _doc.find(selectedId);
    // 选中的是页面本身或已经是组件：不提“存成组件”这回事；别的存不了的原因（比如有积木逻辑在用）说出来。
    final savable = selected != null && selected.type != 'page' && selected.type != 'component';
    final blocked = savable ? canSaveAsComponent(_doc, selected.id) : null;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      builder: (context, scroll) => ListView(
        controller: scroll,
        padding: const EdgeInsets.only(bottom: Space.x6),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.x4, 0, Space.x4, Space.x1),
            child: Text('自定义组件', style: t.titleLarge),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.x4, 0, Space.x4, Space.x3),
            child: Text('把一组控件存成组件，就能反复用；改组件，用到的地方一起变。', style: t.bodySmall),
          ),
          if (savable)
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.x4, 0, Space.x4, Space.x2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FilledButton.icon(
                    key: const ValueKey('comp-save-selected'),
                    onPressed: blocked == null ? () => _saveSelected(selected.id) : null,
                    icon: const Icon(Icons.add_box_outlined, size: 18),
                    label: Text('把选中的${selected.spec.label}存成组件'),
                  ),
                  if (blocked != null)
                    Padding(
                      padding: const EdgeInsets.only(top: Space.x1),
                      child: Text(blocked, style: t.bodySmall?.copyWith(color: c.warning)),
                    ),
                ],
              ),
            ),
          if (_doc.components.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.x4, Space.x6, Space.x4, Space.x4),
              child: Column(
                children: [
                  Icon(Icons.widgets_outlined, size: 36, color: c.textFaint),
                  const SizedBox(height: Space.x2),
                  Text('还没有自定义组件', style: t.titleSmall),
                  const SizedBox(height: Space.x1),
                  Text('在画布上选中一个控件 → 更多操作 → 存成组件', style: t.bodySmall, textAlign: TextAlign.center),
                ],
              ),
            ),
          for (final def in _doc.components)
            ListTile(
              key: ValueKey('comp-item-${def.id}'),
              contentPadding: const EdgeInsets.only(left: Space.x4, right: Space.x1),
              leading: Icon(Icons.widgets_outlined, color: c.accent),
              title: Text(def.name, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text('用了 ${componentUseCount(_doc, def.id)} 次 · ${def.props.isEmpty ? '没有可配置属性' : '${def.props.length} 个可配置属性'}', maxLines: 1, overflow: TextOverflow.ellipsis),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  OutlinedButton(
                    key: ValueKey('comp-insert-${def.id}'),
                    onPressed: () => _insert(def),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 36),
                      padding: const EdgeInsets.symmetric(horizontal: Space.x3),
                    ),
                    child: const Text('插入'),
                  ),
                  PopupMenuButton<String>(
                    tooltip: '${def.name} 的更多操作',
                    onSelected: (v) => switch (v) {
                      'rename' => _rename(def),
                      'props' => _editProps(def),
                      'content' => _editContent(def),
                      _ => _delete(def),
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'props', child: Text('编辑属性')),
                      PopupMenuItem(value: 'content', child: Text('编辑内容')),
                      PopupMenuItem(value: 'rename', child: Text('改名')),
                      PopupMenuItem(value: 'delete', child: Text('删除')),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
