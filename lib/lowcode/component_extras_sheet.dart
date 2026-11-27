// 设计约束（低代码 · 编辑组件 ›“事件”和“变体”两张底部面板 · 390×844）
// - 两张面板一个排法：标题 + 一句灰字说明 → 一行一条（名字在上，下面一行弱化的说明）→ 最后是唯一的主操作“添加…”。
// - 事件：一行一个事件，副标题写“由谁发出”（“按钮 被点击时”/“还没有控件发出它”）。点一行出一张单子：
//   让现在选中的控件“被点击时 / 输入时”发出它、发出时带上一项数据（第四轮 B4；有控件发出它才有这一行，
//   点开是一张单选的单子：组件的属性、组件的状态、重复带出的那一项；已经带了的多一行“不带数据”）、
//   不再发出、改叫法、删除（删除要确认）。副标题末尾写“带：名字”。
//   进面板前没选中控件时，单子里“让选中的控件发出”那一行换成一句灰字提示。
// - 变体：一行一个变体，“组 · 名字”在上，下面写“改了 N 个控件的样子”。点一行＝去画布上改它的样子（面板关掉，
//   顶栏写着正在改哪个变体）；改名 / 删除收进行尾的“⋮”。
// - 每次操作一条撤销记录。取用的 tokens：Space.x1/x2/x4/x6、textMuted、danger。
import 'package:lopicode/lowcode/bind_model.dart';
import 'package:lopicode/lowcode/component_extras.dart';
import 'package:lopicode/lowcode/component_instance_widgets.dart';
import 'package:lopicode/lowcode/component_model.dart';
import 'package:lopicode/lowcode/component_values_widgets.dart';
import 'package:lopicode/lowcode/edit_types.dart';
import 'package:lopicode/lowcode/model.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/widgets.dart';
import 'package:material_ui/material_ui.dart';

void _walk(LcNode n, void Function(LcNode n) visit) {
  visit(n);
  for (final c in n.children) {
    _walk(c, visit);
  }
}

LcNode? _find(LcNode root, String id) {
  LcNode? hit;
  _walk(root, (n) => hit ??= n.id == id ? n : null);
  return hit;
}

String _free(String prefix, Set<String> taken) {
  var i = 1;
  while (taken.contains('$prefix$i')) {
    i++;
  }
  return '$prefix$i';
}

Widget _sheet(BuildContext context, {required String title, required String note, required List<Widget> rows, required Widget add}) => DraggableScrollableSheet(
  expand: false,
  initialChildSize: 0.6,
  minChildSize: 0.35,
  maxChildSize: 0.92,
  builder: (context, scroll) => ListView(
    controller: scroll,
    padding: const EdgeInsets.only(bottom: Space.x6),
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(Space.x4, 0, Space.x4, Space.x1),
        child: Text(title, style: Theme.of(context).textTheme.titleLarge, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(Space.x4, 0, Space.x4, Space.x2),
        child: Text(note, style: Theme.of(context).textTheme.bodySmall),
      ),
      ...rows,
      Padding(padding: const EdgeInsets.fromLTRB(Space.x4, Space.x2, Space.x4, 0), child: add),
    ],
  ),
);

const Map<String, String> _onLabels = {'click': '被点击时', 'input': '输入时'};

/// “事件”面板。[selectedId]：进来前在画布上选中的控件（定义里的节点 id）；没选给 null。
Future<void> showComponentEventsSheet(BuildContext context, {required LcDocument doc, required LcEdit onEdit, required String componentId, String? selectedId}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  builder: (_) => _EventsSheet(doc: doc, onEdit: onEdit, componentId: componentId, selectedId: selectedId),
);

class _EventsSheet extends StatefulWidget {
  const _EventsSheet({required this.doc, required this.onEdit, required this.componentId, this.selectedId});
  final LcDocument doc;
  final LcEdit onEdit;
  final String componentId;
  final String? selectedId;

  @override
  State<_EventsSheet> createState() => _EventsSheetState();
}

class _EventsSheetState extends State<_EventsSheet> {
  late LcDocument _doc = widget.doc;
  LcComponentDef? get _def => _doc.component(widget.componentId);

  void _run(void Function(LcComponentDef def) change) {
    widget.onEdit((d) {
      _doc = d;
      final def = d.component(widget.componentId);
      if (def != null) change(def);
    });
    if (mounted) setState(() {});
  }

  /// 定义里发出这个事件的地方：（节点, 控件的哪个事件）。
  List<(LcNode, String)> _emitters(LcComponentDef def, String event) {
    final out = <(LcNode, String)>[];
    _walk(def.root, (n) {
      for (final e in lcEmitsOf(n).entries) {
        if (e.value.event == event) out.add((n, e.key));
      }
    });
    return out;
  }

  /// 这个事件发出时能带上什么：(名字, 类型, 给人看的说法)。属性、组件自己的状态（文字 / 数字 / 是否），
  /// 再加上发出它的控件都够得着的“重复带出的那一项 / 第几个”。面板上一个事件只配一项（模型里最多 [kLcMaxEventParams] 项）。
  List<(String, String, String)> _dataSources(LcComponentDef def, String event) {
    const simple = {'text': '文字', 'number': '数字', 'bool': '是 / 否'};
    final out = <(String, String, String)>[
      for (final p in def.props)
        if (simple[p.type == 'color' ? 'text' : p.type] != null) (p.name, p.type == 'color' ? 'text' : p.type, '属性'),
      for (final v in lcCompStates(def))
        if (simple[v.type] != null && def.prop(v.name) == null) (v.name, v.type, '组件的状态'),
    ];
    // “重复”带出的名字：每个发出它的控件各自够得着哪些，取大家都有的。
    Set<(String, String)>? common;
    void walk(LcNode n, Set<(String, String)> scope) {
      final r = lcRepeatOf(n);
      final here = r == null ? scope : {...scope, (r.item, 'text'), (r.index, 'number')};
      if (lcEmitsOf(n).values.any((x) => x.event == event)) common = common == null ? here : common!.intersection(here);
      for (final c in n.children) {
        walk(c, here);
      }
    }

    walk(def.root, const {});
    for (final (name, type) in common ?? const <(String, String)>{}) {
      if (out.every((x) => x.$1 != name)) out.add((name, type, type == 'number' ? '重复里的第几个' : '重复带出的那一项'));
    }
    return out;
  }

  Future<void> _add() async {
    final def = _def;
    if (def == null) return;
    final events = lcCompEvents(def);
    if (events.length >= kLcMaxCompEvents) return tellComponentProblem(context, '一个组件最多 $kLcMaxCompEvents 个事件。');
    final label = await askComponentText(context, title: '新事件叫什么', hint: '比如 点了加入购物车', confirmLabel: '下一步', validate: (s) => s.trim().isEmpty || s.trim().length > 20 ? '写一个 20 个字以内的名字' : null);
    if (label == null || !mounted) return;
    final name = await askComponentText(
      context,
      title: '它的英文名',
      hint: '代码里用的名字，比如 addCart',
      initial: _free('event', {for (final e in events) e.name}),
      validate: (s) => !kLcEventName.hasMatch(s.trim()) ? '字母开头，只用英文字母、数字和下划线，最多 24 个' : (events.any((e) => e.name == s.trim()) ? '已经有一个叫 ${s.trim()} 的事件了' : null),
    );
    if (name == null || !mounted) return;
    _run((def) => lcSetCompEvents(def, [...lcCompEvents(def), LcCompEvent(name: name.trim(), label: label.trim())]));
  }

  Future<void> _menu(LcCompEvent e) async {
    final def = _def;
    if (def == null) return;
    final sel = widget.selectedId == null ? null : _find(def.root, widget.selectedId!);
    final canEmit = sel != null && sel.type != 'slot' && sel.type != 'component';
    final has = _emitters(def, e.name).isNotEmpty;
    final t = Theme.of(context).textTheme;
    final pick = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(e.label),
        children: [
          if (canEmit)
            for (final on in sel.type == 'input' ? const ['input', 'click'] : const ['click'])
              SimpleDialogOption(key: Key('comp-event-emit-$on'), onPressed: () => Navigator.pop(context, 'emit:$on'), child: Text('选中的「${sel.spec.label}」${_onLabels[on]}发出它'))
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.x6, 0, Space.x6, Space.x2),
              child: Text('要让某个控件发出它：先关掉这张面板，在画布上选中那个控件（比如按钮），再回来点这一行。', style: t.bodySmall),
            ),
          if (has)
            SimpleDialogOption(
              key: const Key('comp-event-data'),
              onPressed: () => Navigator.pop(context, 'data'),
              child: Text(e.params.isEmpty ? '发出时带上一项数据' : '换一项带出去的数据（现在带：${e.params.first.name}）'),
            ),
          if (has) SimpleDialogOption(key: const Key('comp-event-unemit'), onPressed: () => Navigator.pop(context, 'unemit'), child: const Text('不再让任何控件发出它')),
          SimpleDialogOption(key: const Key('comp-event-rename'), onPressed: () => Navigator.pop(context, 'rename'), child: const Text('改叫法')),
          SimpleDialogOption(
            key: const Key('comp-event-delete'),
            onPressed: () => Navigator.pop(context, 'delete'),
            child: Text('删除这个事件', style: TextStyle(color: context.colors.danger)),
          ),
        ],
      ),
    );
    if (pick == null || !mounted) return;
    final name = e.name;
    void clear(LcComponentDef def) => _walk(def.root, (n) {
      for (final x in lcEmitsOf(n).entries.toList()) {
        if (x.value.event == name) lcSetEmit(n, x.key, null);
      }
    });
    if (pick.startsWith('emit:')) {
      final on = pick.substring(5), id = sel!.id;
      _run((def) {
        final n = _find(def.root, id);
        if (n == null) return;
        lcSetEmit(n, on, name);
        // 这个事件已经定了要带数据：新接上的控件照样带（来源它够得着才带）。
        final first = lcCompEvent(def, name)?.params.firstOrNull;
        if (first != null && _dataSources(def, name).any((x) => x.$1 == first.name)) lcSetEmitArg(n, on, first.name, lcSrcVar(first.name));
      });
    } else if (pick == 'data') {
      final sources = _dataSources(def, name);
      if (sources.isEmpty && e.params.isEmpty) {
        return tellComponentProblem(context, '这个组件里还没有能带出去的东西。先给组件加一个属性或者状态（文字、数字、是 / 否）；发出它的控件在“重复”里的话，重复带出的那一项也能带。');
      }
      final which = await lcPickFromList(
        context,
        title: '「${e.label}」发出时带上',
        choices: [for (final (n, _, what) in sources) (n, '$n · $what')],
        current: e.params.firstOrNull?.name,
        none: e.params.isEmpty ? null : '不带数据',
        keyPrefix: 'comp-event-data',
      );
      if (which == null || !mounted) return;
      _run((def) {
        final type = which.isEmpty ? null : sources.firstWhere((x) => x.$1 == which).$2;
        _walk(def.root, (n) {
          for (final x in lcEmitsOf(n).entries.toList()) {
            if (x.value.event != name) continue;
            for (final old in x.value.args.keys.toList()) {
              lcSetEmitArg(n, x.key, old, null);
            }
            if (type != null) lcSetEmitArg(n, x.key, which, lcSrcVar(which));
          }
        });
        lcSetCompEvents(def, [
          for (final x in lcCompEvents(def))
            if (x.name == name) LcCompEvent(name: x.name, label: x.label, params: [if (type != null) LcCompEventParam(which, type)]) else x,
        ]);
      });
    } else if (pick == 'unemit') {
      _run(clear);
    } else if (pick == 'rename') {
      final label = await askComponentText(context, title: '改叫法', initial: e.label, confirmLabel: '保存', validate: (s) => s.trim().isEmpty || s.trim().length > 20 ? '写一个 20 个字以内的名字' : null);
      if (label == null || !mounted) return;
      _run(
        (def) => lcSetCompEvents(def, [
          for (final x in lcCompEvents(def))
            if (x.name == name) LcCompEvent(name: x.name, label: label.trim(), params: x.params) else x,
        ]),
      );
    } else if (pick == 'delete') {
      final ok = await confirmDialog(context, title: '删除事件「${e.label}」', message: '组件里发出它的控件会解开；各处接在它上面的动作不会再触发。', confirmLabel: '删除', danger: true);
      if (!ok || !mounted) return;
      _run((def) {
        clear(def);
        lcSetCompEvents(def, [
          for (final x in lcCompEvents(def))
            if (x.name != name) x,
        ]);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final def = _def;
    final events = def == null ? const <LcCompEvent>[] : lcCompEvents(def);
    return _sheet(
      context,
      title: '「${def?.name ?? ''}」的事件',
      note: '事件是组件对外说的“发生了一件事”（比如“点了加入购物车”）。用这个组件的页面可以给它接上动作。',
      rows: [
        for (final e in events)
          ListTile(
            key: ValueKey('comp-event-row-${e.name}'),
            title: Text(e.label, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(
              () {
                final from = _emitters(def!, e.name);
                final data = e.params.isEmpty ? '' : ' · 带：${e.params.first.name}';
                return from.isEmpty ? '${e.name} · 还没有控件发出它' : '${e.name} · ${[for (final (n, on) in from) '${n.spec.label}${_onLabels[on] ?? on}'].join('、')}发出$data';
              }(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _menu(e),
          ),
      ],
      add: FilledButton.icon(key: const Key('comp-event-add'), onPressed: _add, icon: const Icon(Icons.add), label: const Text('添加事件')),
    );
  }
}

/// “变体”面板。返回要去画布上改样子的那个变体（`组/名字`）；只是关掉返回 null。
Future<String?> showComponentVariantsSheet(BuildContext context, {required LcDocument doc, required LcEdit onEdit, required String componentId}) => showModalBottomSheet<String>(
  context: context,
  isScrollControlled: true,
  builder: (_) => _VariantsSheet(doc: doc, onEdit: onEdit, componentId: componentId),
);

class _VariantsSheet extends StatefulWidget {
  const _VariantsSheet({required this.doc, required this.onEdit, required this.componentId});
  final LcDocument doc;
  final LcEdit onEdit;
  final String componentId;

  @override
  State<_VariantsSheet> createState() => _VariantsSheetState();
}

class _VariantsSheetState extends State<_VariantsSheet> {
  late LcDocument _doc = widget.doc;
  LcComponentDef? get _def => _doc.component(widget.componentId);

  void _run(void Function(LcComponentDef def) change) {
    widget.onEdit((d) {
      _doc = d;
      final def = d.component(widget.componentId);
      if (def != null) change(def);
    });
    if (mounted) setState(() {});
  }

  String? _checkLabel(String s) => s.trim().isEmpty || s.trim().length > 12 ? '写一个 12 个字以内的名字' : null;

  Future<void> _add() async {
    final def = _def;
    if (def == null) return;
    final list = lcVariants(def);
    final groups = lcVariantGroups(def);
    // 先选放进哪一组（空字＝新开一组）；一组都没有时直接进默认组“样子”。
    var group = kLcDefaultVariantGroup;
    String? groupLabel;
    if (groups.isNotEmpty) {
      final g = await showDialog<String>(
        context: context,
        builder: (context) => SimpleDialog(
          title: const Text('放进哪一组'),
          children: [
            for (final e in groups.entries) SimpleDialogOption(key: Key('comp-variant-group-${e.key}'), onPressed: () => Navigator.pop(context, e.key), child: Text('${e.value}（一组里每次只能选一个）')),
            if (groups.length < kLcMaxVariantGroups) SimpleDialogOption(key: const Key('comp-variant-group-new'), onPressed: () => Navigator.pop(context, ''), child: const Text('新开一组…')),
          ],
        ),
      );
      if (g == null || !mounted) return;
      group = g;
      if (g.isEmpty) {
        groupLabel = await askComponentText(context, title: '新的一组叫什么', hint: '比如 大小', confirmLabel: '下一步', validate: _checkLabel);
        if (groupLabel == null || !mounted) return;
        group = _free('g', groups.keys.toSet());
      }
    }
    if (list.where((v) => v.group == group).length >= kLcMaxVariantsPerGroup) return tellComponentProblem(context, '一组最多 $kLcMaxVariantsPerGroup 个变体。');
    final label = await askComponentText(context, title: '新变体叫什么', hint: '比如 热卖、大号', validate: _checkLabel);
    if (label == null || !mounted) return;
    final name = _free('v', {
      for (final v in list)
        if (v.group == group) v.name,
    });
    final g = group, gl = groupLabel?.trim() ?? groups[group];
    _run((def) => lcSetVariants(def, [...lcVariants(def), LcVariant(group: g, name: name, label: label.trim(), groupLabel: gl)]));
  }

  Future<void> _rename(LcVariant v) async {
    final label = await askComponentText(context, title: '变体改名', initial: v.label, confirmLabel: '保存', validate: _checkLabel);
    if (label == null || !mounted) return;
    final key = v.key;
    _run((def) {
      final list = lcVariants(def);
      for (final x in list) {
        if (x.key == key) x.label = label.trim();
      }
      lcSetVariants(def, list);
    });
  }

  Future<void> _remove(LcVariant v) async {
    final ok = await confirmDialog(context, title: '删除变体「${v.label}」', message: '选了它的地方会回到平时的样子。', confirmLabel: '删除', danger: true);
    if (!ok || !mounted) return;
    final key = v.key;
    _run(
      (def) => lcSetVariants(def, [
        for (final x in lcVariants(def))
          if (x.key != key) x,
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final def = _def;
    final list = def == null ? const <LcVariant>[] : lcVariants(def);
    return _sheet(
      context,
      title: '「${def?.name ?? ''}」的变体',
      note: '变体是这个组件的另外几套样子（比如 热卖、大号）。点一个变体去画布上改它的样子；用组件的地方在“常用”页里选。',
      rows: [
        for (final v in list)
          ListTile(
            key: ValueKey('comp-variant-row-${v.group}-${v.name}'),
            title: Text('${v.groupLabel} · ${v.label}', maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(v.styles.isEmpty ? '还没改样子 · 点这里去改' : '改了 ${v.styles.length} 个控件的样子', maxLines: 1, overflow: TextOverflow.ellipsis),
            onTap: () => Navigator.pop(context, v.key),
            trailing: PopupMenuButton<String>(
              tooltip: '${v.label} 的更多操作',
              onSelected: (x) => x == 'rename' ? _rename(v) : _remove(v),
              itemBuilder: (_) => const [PopupMenuItem(value: 'rename', child: Text('改名')), PopupMenuItem(value: 'delete', child: Text('删除'))],
            ),
          ),
      ],
      add: FilledButton.icon(key: const Key('comp-variant-add'), onPressed: _add, icon: const Icon(Icons.add), label: const Text('添加变体')),
    );
  }
}
