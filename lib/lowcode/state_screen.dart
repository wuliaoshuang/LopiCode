// 设计约束（低代码 · “状态”页 · 390×844，浅色 + 深色；第 5 期，设计见 docs/blocks-v5-parts/E-editor-components.md §10.8）
// - 从哪进：搭建页顶栏“⋮”→“状态”。整页（PageBar），返回就回搭建页。
// - 用途：看这个项目记着哪些值、建新的、改名、删、看哪里在用。主角是“状态的名字”。
// - 从上到下：
//     一句灰色小字：状态是页面记着的值；控件绑上它，它变了界面跟着变。
//     检查出问题时（绑到了不存在的状态、派生值绕圈、重复没给标识…）：一条提示，最多列 5 条。没问题不出现。
//     两节，节标题是小号灰字：
//       “这一页（页名）”——只有这一页用得到，积木编辑器里看到的也是这一份。
//       “整个项目”——所有页面共用；换页不丢。这一页有同名的时候用这一页的（那一行小字会说“被这一页的同名状态盖住了”）。
//     一个状态一行（行高 56）：名字（主，粗一点）／下面灰色小字“类型 · 初值 · 用了 3 处”；行尾“⋮”。
//       点整行＝改它（名字、类型、初值；派生值改的是它的算法）。“⋮”里：看哪里在用、挪到项目 / 挪到这一页（没有重名时）、删除（红字）。
//     每节最下面一行文字按钮“＋ 新建状态”“＋ 新建派生值”（派生值＝由别的状态算出来的，不能直接改）。
//   两节都空：空状态 + 唯一的实心按钮“新建状态”（建在这一页）。
// - 删除一定先问：说清楚有几处在用；删了以后那些地方会被检查标出来，不会自动改。
// - 每个操作一条撤销（回到搭建页点撤销）。
// - 取用的 tokens：Space.x1/x2/x3/x4/x6、textMuted / textFaint、accent、danger。
import 'package:lopicode/lowcode/bind_check.dart';
import 'package:lopicode/lowcode/bind_eval.dart';
import 'package:lopicode/lowcode/bind_model.dart';
import 'package:lopicode/lowcode/bind_picker_sheet.dart';
import 'package:lopicode/lowcode/bind_refs.dart';
import 'package:lopicode/lowcode/edit_types.dart';
import 'package:lopicode/lowcode/logic_model.dart';
import 'package:lopicode/lowcode/logic_vars_sheet.dart';
import 'package:lopicode/lowcode/model.dart';
import 'package:lopicode/lowcode/state_model.dart';
import 'package:lopicode/theme/breakpoints.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/top_bar.dart';
import 'package:lopicode/ui/widgets.dart';
import 'package:material_ui/material_ui.dart';

/// 打开“状态”页。[doc] 取现在的文档（这一页开着的时候文档会被改）。
Future<void> showStateScreen(BuildContext context, {required LcDocument Function() doc, required LcEdit onEdit}) => Navigator.push(
  context,
  MaterialPageRoute<void>(
    builder: (_) => StateScreen(doc: doc, onEdit: onEdit),
  ),
);

/// 一个项目最多多少个项目级状态、一页最多多少个页面级状态。
const int kLcMaxStates = 64;

/// “状态”页顶上最多列几条检查出来的问题（多的只说还有几处）。
const int kLcIssuesShown = 5;

class StateScreen extends StatefulWidget {
  const StateScreen({super.key, required this.doc, required this.onEdit});
  final LcDocument Function() doc;
  final LcEdit onEdit;

  @override
  State<StateScreen> createState() => _StateScreenState();
}

class _StateScreenState extends State<StateScreen> {
  void _edit(void Function(LcDocument d) change) {
    widget.onEdit(change);
    if (mounted) setState(() {});
  }

  List<LcVariable> _list(LcDocument d, bool project) => project ? lcProjectStates(d) : d.logic.variables;

  void _put(LcDocument d, bool project, void Function(List<LcVariable> list) change) => project ? lcEditProjectStates(d, change) : change(d.logic.variables);

  Future<void> _create(bool project) async {
    final doc = widget.doc();
    final draft = await showLcVariableDialog(context, taken: {for (final v in _list(doc, project)) v.name}, wide: true, noun: '状态');
    if (draft == null || draft.delete) return;
    _edit((d) => _put(d, project, (list) => list.add(LcVariable(name: draft.name, type: draft.type, initial: draft.initial))));
  }

  /// 派生值：先起名，再挑它怎么算。项目级的派生值只能读项目级的状态。
  Future<void> _createDerived(bool project) async {
    final doc = widget.doc();
    final name = await promptDialog(context, title: '派生值叫什么', hint: '字母开头，只用字母、数字和 _');
    if (name == null || !mounted) return;
    final key = name.trim();
    if (!LcVariable.namePattern.hasMatch(key) || _list(doc, project).any((v) => v.name == key)) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(LcVariable.namePattern.hasMatch(key) ? '已经有一个叫 $key 的了' : '“$key”不能用：字母开头，只用字母、数字和 _')));
      return;
    }
    await _pickDerived(project, key, null);
  }

  Future<void> _pickDerived(bool project, String name, LcVariable? editing) async {
    final r = await showLcBindPicker(
      context,
      title: name,
      want: 'any',
      doc: project ? _projectOnly : widget.doc,
      current: editing?.derived == null ? null : lcSrcExpr(Map<String, dynamic>.from(editing!.derived! as Map)),
    );
    final expr = lcSrcExprOf(r?.source);
    if (r == null || r.clear || expr == null) return;
    final type = lcExprType(expr, (n) => lcStateOf(widget.doc(), n)?.variable.type);
    _edit(
      (d) => _put(d, project, (list) {
        final at = list.indexWhere((v) => v.name == name);
        final v = LcVariable(name: name, type: LcVariable.stateTypes.contains(type) ? type : 'text', derived: expr);
        if (at < 0) {
          list.add(v);
        } else {
          list[at] = v;
        }
      }),
    );
  }

  /// 只看得到项目级状态的一份文档（给项目级派生值挑算法用：它读不到某一页的状态）。
  LcDocument _projectOnly() {
    final d = LcDocument.starter('');
    final raw = widget.doc().more[kLcProjectStateKey];
    if (raw != null) d.more[kLcProjectStateKey] = raw;
    return d;
  }

  Future<void> _open(LcVariable v, bool project) async {
    if (v.isDerived) return _pickDerived(project, v.name, v);
    final doc = widget.doc();
    final uses = lcStateUses(doc, v.name, project: project).length;
    final draft = await showLcVariableDialog(
      context,
      taken: {
        for (final o in _list(doc, project))
          if (o.name != v.name) o.name,
      },
      editing: v,
      refCount: uses,
      wide: true,
      noun: '状态',
    );
    if (draft == null || !mounted) return;
    if (draft.delete) return _delete(v, project);
    _edit((d) {
      if (draft.name != v.name) lcRenameState(d, v.name, draft.name, project: project);
      _put(d, project, (list) {
        for (final o in list) {
          if (o.name == draft.name) {
            o
              ..type = draft.type
              ..initial = draft.initial;
          }
        }
      });
    });
  }

  Future<void> _delete(LcVariable v, bool project) async {
    final uses = lcStateUses(widget.doc(), v.name, project: project);
    final ok = await confirmDialog(
      context,
      title: '删除“${v.name}”？',
      message: uses.isEmpty ? '现在没有地方用它。删了可以撤销。' : '有 ${uses.length} 处在用它。删了以后那些地方不会自动改，检查会把它们一处处标出来。删了可以撤销。',
      confirmLabel: '删除',
      danger: true,
    );
    if (ok) _edit((d) => lcRemoveState(d, v.name, project: project));
  }

  Future<void> _showUses(LcVariable v, bool project) async {
    final uses = lcStateUses(widget.doc(), v.name, project: project);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        final c = context.colors;
        final t = Theme.of(context).textTheme;
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.7),
            child: ListView(
              key: const Key('lc-state-uses'),
              shrinkWrap: true,
              padding: const EdgeInsets.all(Space.x4),
              children: [
                Text('哪里在用 ${v.name}', style: t.titleMedium),
                const SizedBox(height: Space.x2),
                if (uses.isEmpty) Text('现在没有地方用它。', style: t.bodyMedium?.copyWith(color: c.textMuted)),
                for (final u in uses)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: Space.x2),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(u.what, style: t.bodyMedium),
                        Text(u.where, style: t.bodySmall?.copyWith(color: c.textMuted)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 在页面和项目之间挪。那一层已经有同名的就不能挪。
  void _move(LcVariable v, bool project) => _edit((d) {
    if (_list(d, !project).any((o) => o.name == v.name)) return;
    final copy = v.clone();
    _put(d, project, (list) => list.removeWhere((o) => o.name == v.name));
    _put(d, !project, (list) => list.add(copy));
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final doc = widget.doc();
    final own = doc.logic.variables, shared = lcProjectStates(doc);
    final env = LcBindEnv.of(doc);
    final issues = lcCheckBindings(doc);

    Widget row(LcVariable v, bool project) {
      final uses = lcStateUses(doc, v.name, project: project).length;
      final hidden = project && own.any((o) => o.name == v.name);
      final clash = _list(doc, !project).any((o) => o.name == v.name);
      final value = v.isDerived ? '派生值，现在是 ${lcInitialText(lcEval(v.derived, env) ?? '')}' : '初值 ${lcInitialText(v.initial)}';
      return InkWell(
        key: Key('lc-state-row-${project ? 'p' : 'l'}-${v.name}'),
        onTap: () => _open(v, project),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.only(left: Space.x4, top: Space.x1, bottom: Space.x1),
            child: Row(
              children: [
                Icon(v.isDerived ? Icons.functions : Icons.data_object, size: 20, color: c.accent),
                const SizedBox(width: Space.x3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(v.name, style: t.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                      Text(
                        hidden ? '被这一页的同名状态盖住了' : '${lcStateTypeLabel(v.type)} · $value · ${uses == 0 ? '还没用' : '用了 $uses 处'}',
                        style: t.bodySmall?.copyWith(color: c.textMuted),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  key: Key('lc-state-menu-${project ? 'p' : 'l'}-${v.name}'),
                  tooltip: '更多',
                  icon: Icon(Icons.more_vert, size: 20, color: c.textMuted),
                  onSelected: (a) => switch (a) {
                    'uses' => _showUses(v, project),
                    'move' => _move(v, project),
                    _ => _delete(v, project),
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'uses', child: Text('看哪里在用')),
                    // 派生值挪了层以后读的东西可能不在了，不提供挪。
                    if (!v.isDerived && !clash) PopupMenuItem(value: 'move', child: Text(project ? '挪到这一页' : '挪到整个项目')),
                    PopupMenuItem(
                      value: 'delete',
                      child: Text('删除', style: TextStyle(color: c.danger)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    }

    List<Widget> section(String title, String note, List<LcVariable> list, bool project) {
      final full = list.length >= kLcMaxStates;
      final id = project ? 'p' : 'l';
      return [
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.x4, Space.x4, Space.x4, 0),
          child: Text(title, style: t.labelLarge?.copyWith(color: c.textMuted)),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.x4, 0, Space.x4, Space.x1),
          child: Text(note, style: t.bodySmall?.copyWith(color: c.textFaint)),
        ),
        for (final v in list) row(v, project),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.x2),
          child: Wrap(
            children: [
              TextButton.icon(key: Key('lc-state-add-$id'), onPressed: full ? null : () => _create(project), icon: const Icon(Icons.add, size: 18), label: Text(full ? '最多 $kLcMaxStates 个' : '新建状态')),
              if (!full)
                TextButton.icon(
                  key: Key('lc-state-derive-$id'),
                  onPressed: list.isEmpty && (project || shared.isEmpty) ? null : () => _createDerived(project),
                  icon: const Icon(Icons.functions, size: 18),
                  label: const Text('新建派生值'),
                ),
            ],
          ),
        ),
      ];
    }

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: const PageBar(titleText: '状态'),
      body: ContentWidth(
        child: own.isEmpty && shared.isEmpty
            ? BelowBar(
                child: EmptyState(
                  icon: Icons.data_object,
                  title: '还没有状态',
                  message: '状态是页面记着的一个值：点了几次、输入的字、一张列表…\n控件绑上它以后，它一变，界面跟着变。',
                  action: FilledButton(key: const Key('lc-state-first'), onPressed: () => _create(false), child: const Text('新建状态')),
                ),
              )
            : ListView(
                key: const Key('lc-state-list'),
                padding: EdgeInsets.only(top: PageBar.insetOf(context) + Space.x2, bottom: Space.x6 + MediaQuery.paddingOf(context).bottom),
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: Space.x4),
                    child: Text('状态是页面记着的值。控件绑上它（面板里每一项行尾的链环），它一变界面跟着变；积木也能读它、改它。', style: t.bodySmall?.copyWith(color: c.textMuted)),
                  ),
                  if (issues.isNotEmpty)
                    InfoBanner(
                      key: const Key('lc-state-issues'),
                      '这一页有 ${issues.length} 处要处理：\n${issues.take(kLcIssuesShown).map((i) => '· ${i.message}').join('\n')}${issues.length > kLcIssuesShown ? '\n· …还有 ${issues.length - kLcIssuesShown} 处' : ''}',
                      tone: issues.any((i) => !i.warning) ? BannerTone.warning : BannerTone.info,
                      margin: const EdgeInsets.fromLTRB(Space.x4, Space.x3, Space.x4, 0),
                    ),
                  ...section('这一页（${doc.title.isEmpty ? '没起名' : doc.title}）', '只有这一页用得到。积木编辑器里看到的也是这一份。', own, false),
                  ...section('整个项目', '所有页面共用，换页不丢。这一页有同名的时候，用这一页的。', shared, true),
                ],
              ),
      ),
    );
  }
}
