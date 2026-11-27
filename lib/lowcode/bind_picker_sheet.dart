// 设计约束（低代码 · “绑定到状态”的底部面板 · 390×844，浅色 + 深色；第 5 期，设计见 docs/blocks-v5-parts/E-editor-components.md §10.8）
// - 从哪进：面板里每个能绑的设置行尾的链环按钮、“数据”一节里的各行。
// - 这一页只做一件事：给这一项挑一个“从哪儿来”。主角是值的列表；点一下就定、面板关掉（不用再点确定）。
// - 从上到下：
//     标题“让「文字」跟着状态变”。
//     三种办法排成一行药丸（只出现用得上的）：用一个值 ｜ 拼一段文字（要文字的地方）｜ 比较（要“是 / 否”的地方）。一次只看一种。
//     用一个值：一个值一行（高 52）——名字（主，等宽）／下面灰色小字“类型 · 初值 · 本页 / 项目”；用不了的调淡，小字说为什么。
//       记录、“这一项”下面带一排小药丸：它的每一格（点了＝取这一格）；列表多一个“项数”。
//     拼一段文字：一个输入框（例：你好，{user}）+ 一排名字药丸（点了插进去）+ 整宽实心按钮“用这段文字”。写错了按钮上方一句红字。
//     比较：左边的值（输入框 + 名字药丸）→ 比法（一排药丸）→ 右边（一个数 / 一段文字 / {名字}）→ 整宽实心按钮“用这个条件”。
//     最下面一行：左“＋ 新建状态”（文字按钮），右“解除绑定”（红字；本来没绑就没有）。
// - 一个状态都没有：空状态，唯一的实心按钮“新建状态”。
// - 取用的 tokens：Space.x1/x2/x3/x4/x6、Radii.sm/md、textMuted / textFaint、accent / accentSoft、danger。
import 'package:lopicode/lowcode/bind_eval.dart';
import 'package:lopicode/lowcode/bind_model.dart';
import 'package:lopicode/lowcode/bind_simple.dart';
import 'package:lopicode/lowcode/inspector_presets_widgets.dart';
import 'package:lopicode/lowcode/logic_expr.dart';
import 'package:lopicode/lowcode/logic_vars_sheet.dart';
import 'package:lopicode/lowcode/model.dart';
import 'package:lopicode/lowcode/state_model.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/widgets.dart';
import 'package:material_ui/material_ui.dart';

/// 挑完的结果：[source]＝新的来源；[clear]＝解除绑定。
class LcBindPick {
  const LcBindPick(this.source) : clear = false;
  const LcBindPick.cleared() : source = null, clear = true;
  final Map<String, dynamic>? source;
  final bool clear;
}

/// 打开“绑定到状态”。[want]：这一项要什么（text / bool / list / any）。[current]：现在的来源（没绑是 null）。
/// [doc] 取现在的文档；[locals]＝外面的“重复”带出来的名字；[onNewState]＝新建一个状态（不给就没有这个入口）。
Future<LcBindPick?> showLcBindPicker(
  BuildContext context, {
  required String title,
  required String want,
  required LcDocument Function() doc,
  List<LcLocal> locals = const [],
  Map<String, dynamic>? current,
  Future<void> Function()? onNewState,
}) => showModalBottomSheet<LcBindPick>(
  context: context,
  isScrollControlled: true,
  builder: (_) => _BindPicker(title: title, want: want, doc: doc, locals: locals, current: current, onNewState: onNewState),
);

/// 新建一个状态的对话框（页面级）。存进去由调用方做。
Future<LcVarDraft?> showLcNewStateDialog(BuildContext context, LcDocument doc) => showLcVariableDialog(context, taken: {for (final v in doc.logic.variables) v.name}, wide: true, noun: '状态');

class _BindPicker extends StatefulWidget {
  const _BindPicker({required this.title, required this.want, required this.doc, required this.locals, this.current, this.onNewState});
  final String title;
  final String want;
  final LcDocument Function() doc;
  final List<LcLocal> locals;
  final Map<String, dynamic>? current;
  final Future<void> Function()? onNewState;

  @override
  State<_BindPicker> createState() => _BindPickerState();
}

class _BindPickerState extends State<_BindPicker> {
  late String _mode;
  final _template = TextEditingController();
  final _left = TextEditingController();
  final _right = TextEditingController();
  String _op = '==';
  String? _error;

  bool get _wantText => widget.want == 'text' || widget.want == 'any';
  bool get _wantBool => widget.want == 'bool' || widget.want == 'any';

  @override
  void initState() {
    super.initState();
    _mode = 'value';
    final expr = lcSrcExprOf(widget.current);
    if (expr == null) return;
    final simple = exprKind(expr) == 'var';
    final cmp = _wantBool ? LcCompare.of(expr) : null;
    final tpl = _wantText ? lcTemplateText(expr) : null;
    if (!simple && cmp != null) {
      _mode = 'compare';
      _left.text = cmp.left;
      _op = cmp.op;
      _right.text = cmp.right;
    } else if (!simple && tpl != null) {
      _mode = 'template';
      _template.text = tpl;
    }
  }

  @override
  void dispose() {
    _template.dispose();
    _left.dispose();
    _right.dispose();
    super.dispose();
  }

  void _pick(String name, [List<String> path = const [], bool len = false]) => Navigator.pop(context, LcBindPick(len ? lcSrcExpr(exLen(exRead(name, path))) : lcSrcVar(name, path)));

  /// 这个类型的值能不能直接用在这儿；不能返回原因。
  String? _unfit(String type) => switch (widget.want) {
    'list' => type == 'list' ? null : '这里要一个列表',
    'bool' => type == 'bool' ? null : '不是“是 / 否”：去“比较”里用它',
    'text' => type == 'list' || type == 'record' ? '是${lcStateTypeLabel(type)}：点下面取其中一样' : null,
    _ => null,
  };

  void _insert(TextEditingController c, String text) {
    final sel = c.selection;
    final at = sel.isValid ? sel.start : c.text.length;
    final end = sel.isValid ? sel.end : c.text.length;
    c.value = TextEditingValue(
      text: c.text.replaceRange(at, end, text),
      selection: TextSelection.collapsed(offset: at + text.length),
    );
    setState(() => _error = null);
  }

  void _useTemplate() {
    String? bad;
    final src = lcTemplateSource(_template.text, onBad: (b) => bad = b);
    if (src == null) {
      setState(() => _error = bad != null ? '$bad 写得不对：花括号里写状态的名字，例如 {user}' : '里面还没有用到状态：点下面的名字插进去');
      return;
    }
    if (_unknown(src)) return;
    Navigator.pop(context, LcBindPick(src));
  }

  /// 式子里用到了不存在的名字：说出来，不收。
  bool _unknown(Map<String, dynamic> src) {
    final known = {for (final l in widget.locals) l.name, for (final s in lcStatesInScope(widget.doc())) s.name};
    final missing = [
      for (final n in lcExprNames(lcSrcExprOf(src) ?? const {}))
        if (!known.contains(n)) n,
    ];
    if (missing.isEmpty) return false;
    setState(() => _error = '没有叫 ${missing.join('、')} 的状态：点下面的名字插进去，或者先新建一个');
    return true;
  }

  void _useCompare() {
    final src = LcCompare(_left.text, _op, _right.text).toSource();
    if (src == null) {
      setState(() => _error = '左边写状态的名字（点下面的名字填进去）；右边写一个数、一段文字，或者 {名字}');
      return;
    }
    if (_unknown(src)) return;
    Navigator.pop(context, LcBindPick(src));
  }

  /// 能直接写进式子里的名字（拼文字、比较用）。
  List<String> _names(LcDocument doc) => [
    for (final l in widget.locals) ...[
      l.name,
      if (l.sample is Map)
        for (final k in (l.sample! as Map).keys) '${l.name}.$k',
    ],
    for (final s in lcStatesInScope(doc)) ...[
      if (s.variable.type == 'list') '${s.name}.$kLcLenWord' else if (s.variable.type != 'record') s.name,
      if (s.variable.type == 'record')
        for (final k in (s.variable.initial as Map).keys) '${s.name}.$k',
    ],
  ];

  Widget _chips(List<(String, VoidCallback)> items, {String keyPrefix = 'lc-bind-chip'}) => Wrap(
    spacing: Space.x2,
    runSpacing: Space.x1,
    children: [for (final (label, tap) in items) InspectorChip(key: Key('$keyPrefix-$label'), label: label, selected: false, onTap: tap)],
  );

  Widget _valueRow(BuildContext context, {required String name, required String sub, required String type, Object? sample, required bool local}) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final unfit = _unfit(type);
    final fields = sample is Map ? [for (final k in sample.keys) '$k'] : const <String>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          key: Key('lc-bind-value-$name'),
          onTap: unfit == null ? () => _pick(name) : null,
          borderRadius: BorderRadius.circular(Radii.md),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 52),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: Space.x1),
              child: Row(
                children: [
                  Icon(local ? Icons.repeat : Icons.data_object, size: 18, color: unfit == null ? c.accent : c.textFaint),
                  const SizedBox(width: Space.x3),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          name,
                          style: t.titleSmall?.copyWith(color: unfit == null ? c.text : c.textMuted),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          unfit ?? sub,
                          style: t.bodySmall?.copyWith(color: c.textMuted),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (widget.want != 'list' && (fields.isNotEmpty || type == 'list'))
          Padding(
            padding: const EdgeInsets.only(left: Space.x6 + Space.x1, bottom: Space.x2),
            child: _chips([
              for (final f in fields) ('$name.$f', () => _pick(name, [f])),
              if (type == 'list' && widget.want != 'bool') ('$name.$kLcLenWord', () => _pick(name, const [], true)),
            ], keyPrefix: 'lc-bind-field'),
          ),
      ],
    );
  }

  List<Widget> _valueMode(BuildContext context, LcDocument doc) {
    final states = lcStatesInScope(doc);
    return [
      for (final l in widget.locals)
        _valueRow(
          context,
          name: l.name,
          sub: '${l.label} · 来自外面的“重复”',
          type: l.isIndex ? 'number' : (l.sample is Map ? 'record' : (l.sample is List ? 'list' : (l.sample is num ? 'number' : (l.sample is bool ? 'bool' : 'text')))),
          sample: l.sample,
          local: true,
        ),
      for (final s in states)
        _valueRow(
          context,
          name: s.name,
          sub: '${lcStateTypeLabel(s.variable.type)} · ${s.variable.isDerived ? '派生值（算出来的）' : '初值 ${lcInitialText(s.variable.initial)}'} · ${s.project ? '项目' : '本页'}',
          type: s.variable.type,
          sample: s.variable.type == 'record' ? s.variable.initial : null,
          local: false,
        ),
    ];
  }

  List<Widget> _templateMode(BuildContext context, LcDocument doc) => [
    TextField(
      key: const Key('lc-bind-template'),
      controller: _template,
      minLines: 2,
      maxLines: 4,
      decoration: const InputDecoration(isDense: true, hintText: '例：你好，{user}', helperText: '花括号里是状态的名字，显示的时候换成它现在的值'),
      onChanged: (_) => setState(() => _error = null),
    ),
    const SizedBox(height: Space.x3),
    _chips([for (final n in _names(doc)) (n, () => _insert(_template, '{$n}'))]),
  ];

  List<Widget> _compareMode(BuildContext context, LcDocument doc) {
    final needRight = _op != 'is' && _op != 'not';
    return [
      TextField(
        key: const Key('lc-bind-left'),
        controller: _left,
        decoration: const InputDecoration(isDense: true, labelText: '哪个值', hintText: '点下面的名字填进来'),
        onChanged: (_) => setState(() => _error = null),
      ),
      const SizedBox(height: Space.x2),
      _chips([
        for (final n in _names(doc))
          (
            n,
            () => setState(() {
              _left.text = n;
              _error = null;
            }),
          ),
      ]),
      const SizedBox(height: Space.x3),
      Wrap(
        spacing: Space.x2,
        runSpacing: Space.x1,
        children: [for (final e in kLcCompareOps.entries) InspectorChip(key: Key('lc-bind-op-${e.key}'), label: e.value, selected: _op == e.key, onTap: () => setState(() => _op = e.key))],
      ),
      if (needRight) ...[
        const SizedBox(height: Space.x3),
        TextField(
          key: const Key('lc-bind-right'),
          controller: _right,
          decoration: const InputDecoration(isDense: true, labelText: '和什么比', hintText: '一个数、一段文字，或者 {名字}'),
          onChanged: (_) => setState(() => _error = null),
        ),
      ],
    ];
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final doc = widget.doc();
    final empty = lcStatesInScope(doc).isEmpty && widget.locals.isEmpty;
    final modes = {'value': '用一个值', if (_wantText) 'template': '拼一段文字', if (_wantBool) 'compare': '比较'};
    final newState = widget.onNewState;
    Future<void> create() async {
      await newState!();
      if (mounted) setState(() {});
    }

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(Space.x4, Space.x4, Space.x4, Space.x3 + MediaQuery.viewInsetsOf(context).bottom),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('让“${widget.title}”跟着状态变', key: const Key('lc-bind-title'), style: t.titleMedium),
              const SizedBox(height: Space.x3),
              if (empty)
                EmptyState(
                  icon: Icons.data_object,
                  title: '还没有状态',
                  message: '状态是页面记着的一个值（次数、输入的字、一张列表…）。\n先建一个，再让这一项跟着它变。',
                  action: newState == null ? null : FilledButton(key: const Key('lc-bind-new-first'), onPressed: create, child: const Text('新建状态')),
                )
              else ...[
                if (modes.length > 1) ...[
                  Wrap(
                    spacing: Space.x2,
                    children: [
                      for (final m in modes.entries)
                        InspectorChip(
                          key: Key('lc-bind-mode-${m.key}'),
                          label: m.value,
                          selected: _mode == m.key,
                          onTap: () => setState(() {
                            _mode = m.key;
                            _error = null;
                          }),
                        ),
                    ],
                  ),
                  const SizedBox(height: Space.x3),
                ],
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: switch (_mode) {
                        'template' => _templateMode(context, doc),
                        'compare' => _compareMode(context, doc),
                        _ => _valueMode(context, doc),
                      },
                    ),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: Space.x2),
                  Text(
                    _error!,
                    key: const Key('lc-bind-error'),
                    style: t.bodySmall?.copyWith(color: c.danger),
                  ),
                ],
                if (_mode != 'value') ...[
                  const SizedBox(height: Space.x3),
                  FilledButton(key: const Key('lc-bind-use'), onPressed: _mode == 'template' ? _useTemplate : _useCompare, child: Text(_mode == 'template' ? '用这段文字' : '用这个条件')),
                ],
                const SizedBox(height: Space.x2),
                Row(
                  children: [
                    if (newState != null) TextButton.icon(key: const Key('lc-bind-new'), onPressed: create, icon: const Icon(Icons.add, size: 18), label: const Text('新建状态')),
                    const Spacer(),
                    if (widget.current != null)
                      TextButton(
                        key: const Key('lc-bind-clear'),
                        onPressed: () => Navigator.pop(context, const LcBindPick.cleared()),
                        style: TextButton.styleFrom(foregroundColor: c.danger),
                        child: const Text('解除绑定'),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
