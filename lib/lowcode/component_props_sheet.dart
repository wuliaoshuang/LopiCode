// 设计约束（低代码 · 编辑组件属性 · 390×844）
// - 底部面板，从上到下两段：
//   ①“可配置的属性”：一行一个属性——名字在上，下面一行弱化的“类型 · 默认值”；点一行＝改默认值；
//     改名 / 改类型 / 删除收进行尾的“⋮”。这一段最后是唯一的主操作“添加属性”。
//   ②“内容接到属性上”：定义里每个能接的地方一行——“控件 · 哪一项”在上，下面一行弱化的当前内容；
//     行尾显示接到了哪个属性（没接显示“不接”），点一行在弹出的清单里选。
// - 每次操作一条撤销记录；改完画布上的实例立刻跟着变（画布按展开后的内容画）。
// - 删除属性要确认（接着它的地方会解开，实例填的值会清掉）。
import 'package:lopicode/lowcode/component_model.dart';
import 'package:lopicode/lowcode/component_ops.dart';
import 'package:lopicode/lowcode/component_values_widgets.dart';
import 'package:lopicode/lowcode/edit_types.dart';
import 'package:lopicode/lowcode/model.dart';
import 'package:lopicode/lowcode/palette_widgets.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/widgets.dart';
import 'package:material_ui/material_ui.dart';

/// 打开“编辑组件属性”面板。
Future<void> showComponentPropsSheet(BuildContext context, {required LcDocument doc, required LcEdit onEdit, required String componentId}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  builder: (_) => _PropsSheet(doc: doc, onEdit: onEdit, componentId: componentId),
);

class _PropsSheet extends StatefulWidget {
  const _PropsSheet({required this.doc, required this.onEdit, required this.componentId});
  final LcDocument doc;
  final LcEdit onEdit;
  final String componentId;

  @override
  State<_PropsSheet> createState() => _PropsSheetState();
}

class _PropsSheetState extends State<_PropsSheet> {
  late LcDocument _doc = widget.doc;

  LcComponentDef? get _def => _doc.component(widget.componentId);

  /// 做一次修改（一条撤销记录）；没做成就弹一句原因。
  Future<void> _run(LcOpResult Function(LcDocument d) op) async {
    LcOpResult? result;
    widget.onEdit((d) {
      _doc = d;
      result = op(d);
    });
    if (!mounted) return;
    setState(() {});
    final error = result?.error;
    if (error != null) await tellComponentProblem(context, error);
  }

  String? _checkPropName(LcComponentDef def, String text, {String? except}) {
    final name = text.trim();
    if (!LcComponentProp.namePattern.hasMatch(name)) return '只能用英文字母、数字和下划线，不能用数字开头（比如 title、price2）';
    if (name != except && def.prop(name) != null) return '已经有一个叫 $name 的属性了';
    return null;
  }

  Future<String?> _pickType(String current) => showDialog<String>(
    context: context,
    builder: (context) => SimpleDialog(
      title: const Text('属性类型'),
      children: [
        for (final type in LcComponentProp.types)
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, type),
            child: Row(
              children: [
                Icon(type == current ? Icons.radio_button_checked : Icons.radio_button_off, size: 20, color: type == current ? context.colors.accent : context.colors.textFaint),
                const SizedBox(width: Space.x3),
                Text(componentPropTypeLabel(type)),
              ],
            ),
          ),
      ],
    ),
  );

  Future<void> _add() async {
    final def = _def;
    if (def == null) return;
    final name = await askComponentText(context, title: '新属性叫什么', hint: '英文名，比如 title', confirmLabel: '下一步', validate: (s) => _checkPropName(def, s));
    if (name == null || !mounted) return;
    final type = await _pickType('text');
    if (type == null || !mounted) return;
    await _run((d) => addComponentProp(d, widget.componentId, name, type));
  }

  Future<void> _rename(LcComponentProp p) async {
    final def = _def;
    if (def == null) return;
    final name = await askComponentText(
      context,
      title: '属性改名',
      initial: p.name,
      confirmLabel: '保存',
      validate: (s) => _checkPropName(def, s, except: p.name),
    );
    if (name == null || name == p.name || !mounted) return;
    final old = p.name;
    await _run((d) => renameComponentProp(d, widget.componentId, old, name));
  }

  Future<void> _retype(LcComponentProp p) async {
    final type = await _pickType(p.type);
    if (type == null || type == p.type || !mounted) return;
    final name = p.name;
    await _run((d) => setComponentPropType(d, widget.componentId, name, type));
  }

  Future<void> _editDefault(LcComponentProp p) async {
    final name = p.name;
    final value = await askComponentValue(context, title: '$name 的默认值', type: p.type, initial: p.defaultValue);
    if (value == null || !mounted) return;
    await _run((d) => setComponentPropDefault(d, widget.componentId, name, value));
  }

  Future<void> _remove(LcComponentProp p) async {
    final name = p.name;
    final ok = await confirmDialog(context, title: '删除属性 $name', message: '接在它上面的内容会解开（回到控件自己原来的内容），各处给它填的值也会清掉。', confirmLabel: '删除', danger: true);
    if (!ok || !mounted) return;
    await _run((d) => removeComponentProp(d, widget.componentId, name));
  }

  Future<void> _pickBinding(LcComponentDef def, LcNode node, String attr) async {
    final fits = [
      for (final p in def.props)
        if (propTypeFitsAttr(p.type, attr)) p,
    ];
    final current = node.bind[attr];
    // 用空字符串表示“不接”（属性名不可能是空的），null 留给“关掉对话框什么都不改”。
    final picked = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text('${node.spec.label}的${bindablePropLabel(attr)}接到'),
        children: [
          SimpleDialogOption(onPressed: () => Navigator.pop(context, ''), child: Text(current == null ? '不接（现在这样）' : '不接')),
          for (final p in fits) SimpleDialogOption(onPressed: () => Navigator.pop(context, p.name), child: Text('${p.name} · ${componentPropTypeLabel(p.type)}${p.name == current ? '（现在这样）' : ''}')),
          if (fits.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.x6, Space.x2, Space.x6, 0),
              child: Text(attr == 'bg' || attr == 'color' ? '还没有“颜色”类型的属性。先在上面添加一个。' : '还没有属性。先在上面添加一个。', style: Theme.of(context).textTheme.bodySmall),
            ),
        ],
      ),
    );
    if (picked == null || !mounted || picked == (current ?? '')) return;
    final nodeId = node.id;
    await _run((d) => bindComponentProp(d, widget.componentId, nodeId, attr, picked.isEmpty ? null : picked));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final def = _def;
    final targets = <(LcNode, String)>[];
    void collect(LcNode n) {
      for (final attr in bindablePropsFor(n.type)) {
        targets.add((n, attr));
      }
      n.children.forEach(collect);
    }

    if (def != null) collect(def.root);
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      builder: (context, scroll) => ListView(
        controller: scroll,
        padding: const EdgeInsets.only(bottom: Space.x6),
        children: def == null
            ? [
                Padding(
                  padding: const EdgeInsets.all(Space.x4),
                  child: Text('这个组件已经不存在了。', style: t.bodyMedium),
                ),
              ]
            : [
                Padding(
                  padding: const EdgeInsets.fromLTRB(Space.x4, 0, Space.x4, Space.x1),
                  child: Text('「${def.name}」的属性', style: t.titleLarge, maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(Space.x4, 0, Space.x4, Space.x2),
                  child: Text('属性是组件对外留的“空”：每次用这个组件时可以填不同的内容。', style: t.bodySmall),
                ),
                const SectionLabel('可配置的属性'),
                for (final p in def.props)
                  ListTile(
                    key: ValueKey('comp-prop-${p.name}'),
                    title: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text('${componentPropTypeLabel(p.type)} · 默认 ${componentValueSummary(p.defaultValue)}', maxLines: 1, overflow: TextOverflow.ellipsis),
                    onTap: () => _editDefault(p),
                    trailing: PopupMenuButton<String>(
                      tooltip: '${p.name} 的更多操作',
                      onSelected: (v) => switch (v) {
                        'rename' => _rename(p),
                        'type' => _retype(p),
                        'default' => _editDefault(p),
                        _ => _remove(p),
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'default', child: Text('改默认值')),
                        PopupMenuItem(value: 'rename', child: Text('改名')),
                        PopupMenuItem(value: 'type', child: Text('改类型')),
                        PopupMenuItem(value: 'delete', child: Text('删除')),
                      ],
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(Space.x4, Space.x2, Space.x4, Space.x2),
                  child: FilledButton.icon(key: const ValueKey('comp-prop-add'), onPressed: _add, icon: const Icon(Icons.add, size: 18), label: const Text('添加属性')),
                ),
                const SectionLabel('内容接到属性上'),
                if (targets.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: Space.x4),
                    child: Text('这个组件里没有能接属性的内容（文字、图片地址、提示文字、颜色）。', style: t.bodySmall),
                  ),
                for (final (node, attr) in targets)
                  ListTile(
                    key: ValueKey('comp-bind-${node.id}-$attr'),
                    leading: Icon(lcIcon(node.type), size: 20, color: c.textMuted),
                    title: Text('${node.spec.label} · ${bindablePropLabel(attr)}', maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(componentValueSummary(node.strProp(attr) ?? ''), maxLines: 1, overflow: TextOverflow.ellipsis),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 120),
                          child: Text(
                            node.bind[attr] ?? '不接',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: t.bodyMedium?.copyWith(color: node.bind[attr] == null ? c.textFaint : c.accent),
                          ),
                        ),
                        Icon(Icons.chevron_right, size: 20, color: c.textFaint),
                      ],
                    ),
                    onTap: () => _pickBinding(def, node, attr),
                  ),
              ],
      ),
    );
  }
}
