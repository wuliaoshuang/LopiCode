// 设计约束（编辑一个“值” · 390×844）— 2026-11-24
// - 一个底部面板从头改到尾：嵌套的值（运算的左边 / 右边、拼接的每一项）在面板里往里走，顶上的面包屑（值 › 左边 › …）说明走到哪了；
//   不一层层叠新面板。
// - 从上到下：面包屑 → “读作”（整个值现在读成什么）→ 种类（按分组一行一组，最合适的排前面）→ 这个种类要填的东西。
// - 每行只做一件事：一个输入框，或一个开关，或一行“名字 + 可点的值胶囊”。
// - 最外层的主操作是“完成”（提交，一条撤销记录），旁边“取消”（什么都不改）；走到里层时主操作换成“回到上一层”。
import 'package:lopicode/lowcode/edit_types.dart';
import 'package:lopicode/lowcode/logic_blocks.dart';
import 'package:lopicode/lowcode/logic_pick_sheet.dart';
import 'package:lopicode/lowcode/logic_text.dart';
import 'package:lopicode/lowcode/logic_vars_sheet.dart';
import 'package:lopicode/lowcode/model.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:material_ui/material_ui.dart';

/// 打开面板编辑一个值。点“完成”返回新的表达式（一份新的对象）；取消返回 null。
/// [event]＝所在处理的事件（只有 input 才给“输入的内容”这个种类）；[read] / [edit] 用来在面板里顺手新建变量。
Future<Map<String, dynamic>?> showLcExprSheet(
  BuildContext context, {
  required LcDocument Function() read,
  required LcEdit edit,
  required String title,
  required Object? initial,
  required String valueType,
  required String event,
}) => showLcSheet<Map<String, dynamic>>(context, (_) => LcExprSheet(read: read, edit: edit, title: title, initial: initial, valueType: valueType, event: event));

typedef _Step = ({String label, String key, int? item, String valueType});

const List<String> _opSigns = ['+', '−', '×', '÷', '余', '=', '≠', '<', '≤', '>', '≥', '并且', '或者'];

class LcExprSheet extends StatefulWidget {
  const LcExprSheet({super.key, required this.read, required this.edit, required this.title, required this.initial, required this.valueType, required this.event});
  final LcDocument Function() read;
  final LcEdit edit;
  final String title;
  final Object? initial;
  final String valueType;
  final String event;

  @override
  State<LcExprSheet> createState() => _LcExprSheetState();
}

class _LcExprSheetState extends State<LcExprSheet> {
  late final Map<String, dynamic> _root = copyExpr(widget.initial) ?? defaultExprFor(widget.valueType);
  final List<_Step> _trail = [];
  final TextEditingController _field = TextEditingController();
  String? _numError;

  LcDocument get _doc => widget.read();

  @override
  void initState() {
    super.initState();
    _enter();
  }

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  /// 顺着面包屑走到现在正在改的那个值。走不通（数据对不上）就退回到走得通的那一层。
  Map<String, dynamic> get _cur {
    var cur = _root;
    for (var i = 0; i < _trail.length; i++) {
      final step = _trail[i];
      final items = exprField(cur, 'items');
      final next = step.item == null ? exprChild(cur, step.key) : (items is List && step.item! < items.length ? asExpr(items[step.item!]) : null);
      if (next == null) {
        _trail.removeRange(i, _trail.length);
        break;
      }
      cur = next;
    }
    return cur;
  }

  String get _curType => _trail.isEmpty ? widget.valueType : _trail.last.valueType;

  /// 进到一个值（刚打开、往里走、退回来、换了种类）：把缺的字段补上，输入框换成它的内容。
  void _enter() {
    final cur = _cur;
    switch (exprKind(cur)) {
      case 'text':
        if (exprString(cur, 'v') == null) cur['v'] = '';
        _field.text = exprString(cur, 'v') ?? '';
      case 'num':
        if (exprNum(cur, 'v') == null) cur['v'] = 0;
        _field.text = describeExpr(cur, _doc);
      case 'bool':
        if (exprBool(cur, 'v') == null) cur['v'] = true;
      case 'bin':
        if (!kBinOps.contains(exprString(cur, 'op'))) cur['op'] = '+';
        if (exprChild(cur, 'l') == null) cur['l'] = exNum(1);
        if (exprChild(cur, 'r') == null) cur['r'] = exNum(1);
      case 'not':
        if (exprChild(cur, 'x') == null) cur['x'] = exBool(true);
      case 'join':
        cur['items'] = <dynamic>[...exprItems(cur)];
    }
    _numError = null;
  }

  void _push(String label, String key, String valueType, [int? item]) => setState(() {
    _trail.add((label: label, key: key, item: item, valueType: valueType));
    _enter();
  });

  void _popTo(int length) => setState(() {
    _trail.removeRange(length, _trail.length);
    _enter();
  });

  /// 这个种类合不合适现在要的类型：0 最合适，1 都行，2 不太对。
  int _fit(String kind) {
    final want = _curType;
    if (want == LcType.any) return 1;
    return switch (kind) {
      'text' || 'join' || 'event' => want == LcType.text ? 0 : 2,
      'num' => want == LcType.number ? 0 : 2,
      'bool' || 'not' => want == LcType.boolean ? 0 : 2,
      'bin' => want == LcType.text ? 2 : 0,
      _ => 1,
    };
  }

  void _setKind(String kind) {
    final cur = _cur;
    final oldKind = exprKind(cur);
    if (kind == oldKind) return;
    final old = copyExpr(cur) ?? exText('');
    // 原来是变量 / 控件属性 / 运算这类“有内容”的值，换成运算时把它留在左边，不让人重填。
    final keep = const ['var', 'prop', 'event', 'bin', 'not', 'join'].contains(oldKind);
    var next = newExpr(kind, _doc);
    switch (kind) {
      case 'bin':
        final want = _curType;
        next = exBin(want == LcType.boolean ? '==' : '+', keep ? old : exNum(1), exNum(1));
      case 'not':
        if (keep) next = exNot(old);
      case 'join':
        final hasWords = oldKind == 'text' && (exprString(old, 'v') ?? '').isNotEmpty;
        next = exJoin([keep || hasWords ? old : exText(''), exText('')]);
      case 'num':
        final n = oldKind == 'text' ? lcParseNumber(exprString(old, 'v') ?? '') : null;
        if (n != null) next = exNum(n);
      case 'text':
        if (oldKind == 'num') next = exText(describeExpr(old, _doc));
    }
    setState(() {
      cur
        ..clear()
        ..addAll(next);
      _enter();
    });
  }

  void _done() {
    if (_numError != null) return;
    Navigator.pop(context, copyExpr(_root));
  }

  Future<void> _newVariable(Map<String, dynamic> cur) async {
    final draft = await showLcVariableDialog(context, taken: {for (final v in _doc.logic.variables) v.name}, suggestType: _curType == LcType.any ? null : _curType);
    if (draft == null || !mounted) return;
    widget.edit((d) => lcApplyVarDraft(d.logic, draft));
    setState(() => cur['name'] = draft.name);
  }

  Future<void> _pickNode(Map<String, dynamic> cur) async {
    final id = await showLcNodePicker(context, _doc, title: '读哪个控件？', selected: exprString(cur, 'node'));
    if (id == null || !mounted) return;
    final type = _doc.find(id)?.type ?? '';
    setState(() {
      cur['node'] = id;
      final props = readablePropsFor(type);
      if (!props.contains(exprString(cur, 'prop'))) cur['prop'] = type == 'input' ? 'value' : props.first;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final cur = _cur;
    final kind = exprKind(cur);
    final nested = _trail.isNotEmpty;
    return LcSheetFrame(
      title: widget.title,
      header: nested ? _crumbs(c, t) : null,
      footer: nested
          ? FilledButton(key: const ValueKey('lc-expr-up'), onPressed: () => _popTo(_trail.length - 1), child: const Text('好了，回到上一层'))
          : Row(
              children: [
                Expanded(
                  child: OutlinedButton(key: const ValueKey('lc-expr-cancel'), onPressed: () => Navigator.pop(context), child: const Text('取消')),
                ),
                const SizedBox(width: Space.x2),
                Expanded(
                  child: FilledButton(key: const ValueKey('lc-expr-done'), onPressed: _numError == null ? _done : null, child: const Text('完成')),
                ),
              ],
            ),
      children: [
        Container(
          margin: const EdgeInsets.fromLTRB(Space.x4, 0, Space.x4, Space.x3),
          padding: const EdgeInsets.all(Space.x3),
          decoration: BoxDecoration(color: c.surfaceMuted, borderRadius: BorderRadius.circular(Radii.md)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('读作', style: t.labelMedium),
              const SizedBox(height: 2),
              Text(
                describeExpr(_root, _doc),
                key: const ValueKey('lc-expr-reading'),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: t.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
        ..._kindRows(t, kind),
        const SizedBox(height: Space.x2),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.x4),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: _fields(c, t, cur, kind)),
        ),
      ],
    );
  }

  Widget _crumbs(AppColors c, TextTheme t) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    padding: const EdgeInsets.symmetric(horizontal: Space.x2),
    child: Row(
      children: [
        for (var i = 0; i <= _trail.length; i++) ...[
          if (i > 0) Icon(Icons.chevron_right_rounded, size: 18, color: c.textFaint),
          TextButton(
            key: ValueKey('lc-expr-crumb-$i'),
            onPressed: i == _trail.length ? null : () => _popTo(i),
            style: TextButton.styleFrom(
              foregroundColor: c.accent,
              disabledForegroundColor: c.text,
              minimumSize: const Size(40, 40),
              padding: const EdgeInsets.symmetric(horizontal: Space.x2),
            ),
            child: Text(i == 0 ? widget.title : _trail[i - 1].label),
          ),
        ],
      ],
    ),
  );

  /// 种类：一组一行，最合适的组和种类排前面。
  List<Widget> _kindRows(TextTheme t, String? kind) {
    final groups = <(int, String, List<LcExprSpec>)>[];
    for (final category in lcExprCategories) {
      final specs = [
        for (final s in exprSpecsIn(category))
          if (s.kind != 'event' || widget.event == 'input' || kind == 'event') s,
      ];
      if (specs.isEmpty) continue;
      // Dart 的排序不保证稳定，所以把原来的次序也放进比较里。
      final order = {for (var i = 0; i < specs.length; i++) specs[i].kind: i};
      specs.sort((a, b) => _fit(a.kind) != _fit(b.kind) ? _fit(a.kind).compareTo(_fit(b.kind)) : order[a.kind]!.compareTo(order[b.kind]!));
      groups.add((_fit(specs.first.kind), category, specs));
    }
    final rank = {for (var i = 0; i < groups.length; i++) groups[i].$2: i};
    groups.sort((a, b) => a.$1 != b.$1 ? a.$1.compareTo(b.$1) : rank[a.$2]!.compareTo(rank[b.$2]!));
    return [
      for (final (_, category, specs) in groups)
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.x4, 0, Space.x4, 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 56,
                height: 48,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(category, style: t.labelMedium),
                ),
              ),
              Expanded(
                child: Wrap(
                  spacing: Space.x2,
                  children: [for (final s in specs) LcChoiceChip(key: ValueKey('lc-expr-kind-${s.kind}'), label: s.label, selected: s.kind == kind, onSelected: () => _setKind(s.kind))],
                ),
              ),
            ],
          ),
        ),
    ];
  }

  /// 子值的类型：算术和比大小要数字，并且 / 或者要“是否”，等于 / 不等于随便。
  String _sideType(String? op) => kLogicOps.contains(op) ? LcType.boolean : (op == '==' || op == '!=' ? LcType.any : LcType.number);

  Widget _valueRow(String label, Object? value, VoidCallback onTap, {Key? key, Widget? trailing}) => Padding(
    padding: const EdgeInsets.only(bottom: Space.x2),
    child: Row(
      children: [
        SizedBox(width: 56, child: Text(label, style: Theme.of(context).textTheme.labelMedium)),
        Expanded(
          child: _ValuePill(key: key, text: value is String ? value : describeExpr(value, _doc), onTap: onTap),
        ),
        ?trailing,
      ],
    ),
  );

  List<Widget> _fields(AppColors c, TextTheme t, Map<String, dynamic> cur, String? kind) {
    final spec = lcExprSpecs[kind];
    final hint = spec == null || spec.hint.isEmpty
        ? null
        : Padding(
            padding: const EdgeInsets.only(bottom: Space.x2),
            child: Text(spec.hint, style: t.bodySmall),
          );
    switch (kind) {
      case 'text':
        return [
          TextField(
            key: const ValueKey('lc-expr-text'),
            controller: _field,
            minLines: 1,
            maxLines: 3,
            decoration: const InputDecoration(labelText: '文字', hintText: '可以留空'),
            onChanged: (v) => setState(() => cur['v'] = v),
          ),
        ];
      case 'num':
        return [
          TextField(
            key: const ValueKey('lc-expr-num'),
            controller: _field,
            keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
            decoration: InputDecoration(labelText: '数字', errorText: _numError),
            onChanged: (v) => setState(() {
              final n = lcParseNumber(v);
              _numError = n == null ? '这里要填一个数字' : null;
              if (n != null) cur['v'] = n;
            }),
          ),
        ];
      case 'bool':
        final v = exprBool(cur, 'v') ?? true;
        return [SwitchListTile(key: const ValueKey('lc-expr-bool'), contentPadding: EdgeInsets.zero, title: Text(v ? '是' : '否'), value: v, onChanged: (b) => setState(() => cur['v'] = b))];
      case 'var':
        final vars = _doc.logic.variables;
        return [
          if (vars.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: Space.x2),
              child: Text('这个页面还没有变量，先新建一个。', style: t.bodySmall),
            ),
          Wrap(
            spacing: Space.x2,
            children: [
              for (final v in vars)
                LcChoiceChip(
                  key: ValueKey('lc-expr-var-${v.name}'),
                  label: '${v.name} · ${describeVarType(v.type)}',
                  selected: exprString(cur, 'name') == v.name,
                  onSelected: () => setState(() => cur['name'] = v.name),
                ),
              ActionChip(key: const ValueKey('lc-expr-var-new'), avatar: const Icon(Icons.add_rounded, size: 18), label: const Text('新建变量'), onPressed: () => _newVariable(cur)),
            ],
          ),
        ];
      case 'prop':
        final node = _doc.find(exprString(cur, 'node') ?? '');
        final propSpec = spec?.arg('prop');
        return [
          ?hint,
          _valueRow('控件', describeNode(_doc, exprString(cur, 'node')), () => _pickNode(cur), key: const ValueKey('lc-expr-node')),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 56,
                height: 48,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('读什么', style: t.labelMedium),
                ),
              ),
              Expanded(
                child: Wrap(
                  spacing: Space.x2,
                  children: [
                    for (final p in node == null ? kReadableProps : readablePropsFor(node.type))
                      LcChoiceChip(key: ValueKey('lc-expr-prop-$p'), label: propSpec?.choiceLabel(p) ?? p, selected: exprString(cur, 'prop') == p, onSelected: () => setState(() => cur['prop'] = p)),
                  ],
                ),
              ),
            ],
          ),
        ];
      case 'event':
        return [Text(widget.event == 'input' ? '就是输入框里现在的内容，不用再填别的。' : '“输入的内容”只能用在“输入内容变化时”的处理里，这里用不了，请换一种。', style: t.bodyMedium?.copyWith(color: widget.event == 'input' ? c.textMuted : c.danger))];
      case 'bin':
        final op = exprString(cur, 'op');
        final side = _sideType(op);
        return [
          _valueRow('左边', exprChild(cur, 'l'), () => _push('左边', 'l', side), key: const ValueKey('lc-expr-l')),
          Wrap(
            spacing: Space.x1,
            children: [
              for (var i = 0; i < kBinOps.length; i++)
                LcChoiceChip(
                  key: ValueKey('lc-expr-op-${kBinOps[i]}'),
                  label: _opSigns[i],
                  tooltip: spec?.arg('op')?.choiceLabel(kBinOps[i]),
                  selected: op == kBinOps[i],
                  onSelected: () => setState(() => cur['op'] = kBinOps[i]),
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: Space.x1),
            child: Text('现在选的是：${spec?.arg('op')?.choiceLabel(op ?? '') ?? ''}', style: t.bodySmall),
          ),
          _valueRow('右边', exprChild(cur, 'r'), () => _push('右边', 'r', side), key: const ValueKey('lc-expr-r')),
        ];
      case 'not':
        return [?hint, _valueRow('条件', exprChild(cur, 'x'), () => _push('条件', 'x', LcType.boolean), key: const ValueKey('lc-expr-x'))];
      case 'join':
        final raw = exprField(cur, 'items');
        final items = raw is List ? raw : <dynamic>[];
        return [
          ?hint,
          for (var i = 0; i < items.length; i++)
            _valueRow(
              '第 ${i + 1} 项',
              items[i],
              () => _push('第 ${i + 1} 项', 'items', LcType.any, i),
              key: ValueKey('lc-expr-item-$i'),
              trailing: IconButton(
                key: ValueKey('lc-expr-item-del-$i'),
                tooltip: '去掉这一项',
                onPressed: items.length > 1 ? () => setState(() => items.removeAt(i)) : null,
                icon: const Icon(Icons.remove_circle_outline_rounded, size: 20),
              ),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const ValueKey('lc-expr-item-add'),
              onPressed: () => setState(() => items.add(exText(''))),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('加一项'),
            ),
          ),
        ];
      default:
        return [Text('不认识的值（${kind ?? '空'}）。可以在上面换一个种类；不换就原样留着。', style: t.bodyMedium?.copyWith(color: c.textMuted))];
    }
  }
}

/// 面板里“可点进去改”的一个值：整行宽的浅灰胶囊。
class _ValuePill extends StatelessWidget {
  const _ValuePill({super.key, required this.text, required this.onTap});
  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: c.surfaceMuted,
      borderRadius: BorderRadius.circular(22),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(Space.x4, Space.x1, Space.x2, Space.x1),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    text,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: c.text, fontSize: FontSize.sm, fontWeight: FontWeight.w600),
                  ),
                ),
                Icon(Icons.chevron_right_rounded, size: 20, color: c.textMuted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
