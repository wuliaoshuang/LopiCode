// 设计约束（页面变量面板 · 390×844）— 2026-11-24
// - 面板里一行一个变量：名字（等宽）在上，下面一行弱化的“类型 · 初始值 · 几处在用”。点一行＝编辑它。
// - 主操作只有一个：底下的“新建变量”。
// - 编辑 / 新建是同一个对话框，从上到下：名字 → 类型（三选一）→ 初始值（按类型换成文字框 / 数字框 / 开关）；
//   删除放在对话框左下角（弱化的危险色），不和“保存”抢。保存一次＝一条撤销记录。
// - 名字不合规矩、重名、数字填错：就地在输入框下面说清楚原因，不关对话框。
import 'dart:convert';

import 'package:lopicode/lowcode/edit_types.dart';
import 'package:lopicode/lowcode/logic_edit.dart';
import 'package:lopicode/lowcode/logic_model.dart';
import 'package:lopicode/lowcode/logic_text.dart';
import 'package:lopicode/lowcode/model.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/widgets.dart';
import 'package:material_ui/material_ui.dart';

/// 对话框里填好的一个变量。[delete] 为真＝用户点了“删除”。
class LcVarDraft {
  const LcVarDraft({required this.name, required this.type, required this.initial, this.delete = false});
  final String name;
  final String type;
  final Object initial;
  final bool delete;
}

/// 把输入框里的字读成数字；读不出来返回 null。整数就给 int（存盘里是 `3` 不是 `3.0`）。
num? lcParseNumber(String text) {
  final s = text.trim();
  final v = int.tryParse(s) ?? double.tryParse(s);
  return v != null && v.isFinite ? v : null;
}

String _initialText(Object v) => switch (v) {
  final bool b => b ? '是' : '否',
  final num n => n is int || n == n.roundToDouble() && n.abs() < 1e15 ? '${n.round()}' : '$n',
  final String s => s.isEmpty ? '（空）' : '“$s”',
  final List<Object?> l => l.isEmpty ? '（空）' : '${l.length} 项',
  final Map<Object?, Object?> m => m.isEmpty ? '（空）' : '${m.length} 格',
  _ => '',
};

/// 初始值给人看的短写法（变量面板、状态页共用）。
String lcInitialText(Object v) => _initialText(v);

/// 把输入框里的字读成列表 / 记录（JSON）；空着＝空的；读不出来或者种类不对返回 null。
Object? lcParseJsonInitial(String type, String text) {
  final s = text.trim();
  if (s.isEmpty) return type == 'list' ? <Object?>[] : <String, Object?>{};
  try {
    final v = jsonDecode(s);
    return (type == 'list' ? v is List : v is Map) ? v : null;
  } on FormatException {
    return null;
  }
}

/// 新建 / 编辑一个变量。[taken]＝别的变量已经占用的名字。取消返回 null。
/// [wide]：类型里多“列表”“记录”两种（搭建页的状态用；初值填 JSON）。正在改的本来就是这两种时也自动带上。
/// [noun]：对话框里怎么叫它（“变量”/“状态”）。
Future<LcVarDraft?> showLcVariableDialog(BuildContext context, {required Set<String> taken, LcVariable? editing, String? suggestType, int refCount = 0, bool wide = false, String noun = '状态'}) =>
    showDialog<LcVarDraft>(
      context: context,
      builder: (_) =>
          _VariableDialog(taken: taken, editing: editing, suggestType: suggestType, refCount: refCount, wide: wide || (editing != null && !LcVariable.types.contains(editing.type)), noun: noun),
    );

class _VariableDialog extends StatefulWidget {
  const _VariableDialog({required this.taken, this.editing, this.suggestType, required this.refCount, required this.wide, required this.noun});
  final bool wide;
  final String noun;
  final Set<String> taken;
  final LcVariable? editing;
  final String? suggestType;
  final int refCount;

  @override
  State<_VariableDialog> createState() => _VariableDialogState();
}

class _VariableDialogState extends State<_VariableDialog> {
  late final TextEditingController _name = TextEditingController(text: widget.editing?.name ?? '');
  late final TextEditingController _value = TextEditingController();
  List<String> get _types => widget.wide ? LcVariable.stateTypes : LcVariable.types;
  bool get _json => _type == 'list' || _type == 'record';
  late String _type = widget.editing?.type ?? (_types.contains(widget.suggestType) ? widget.suggestType! : 'text');
  bool _flag = false;
  String? _nameError;
  String? _valueError;

  @override
  void initState() {
    super.initState();
    final v = widget.editing?.initial;
    if (v is bool) _flag = v;
    if (v is num) _value.text = _initialText(v);
    if (v is String) _value.text = v;
    if (v is List || v is Map) _value.text = (v is List ? v.isEmpty : (v as Map).isEmpty) ? '' : jsonEncode(v);
  }

  @override
  void dispose() {
    _name.dispose();
    _value.dispose();
    super.dispose();
  }

  void _save() {
    final name = _name.text.trim();
    String? nameError;
    if (!LcVariable.namePattern.hasMatch(name)) {
      nameError = '只能用英文字母、数字和下划线，不能用数字开头，最多 32 个字符';
    } else if (name != widget.editing?.name && widget.taken.contains(name)) {
      nameError = '已经有一个${widget.noun}叫 $name 了';
    }
    final number = lcParseNumber(_value.text);
    final json = _json ? lcParseJsonInitial(_type, _value.text) : null;
    final valueError = _type == 'number' && _value.text.trim().isNotEmpty && number == null
        ? '这里要填一个数字'
        : (_json && json == null ? (_type == 'list' ? '要写成一个列表，比如 ["苹果", "香蕉"]' : '要写成一条记录，比如 {"name": "小明", "age": 18}') : null);
    if (nameError != null || valueError != null) {
      setState(() {
        _nameError = nameError;
        _valueError = valueError;
      });
      return;
    }
    final Object initial = switch (_type) {
      'number' => number ?? 0,
      'bool' => _flag,
      'list' || 'record' => json ?? _value.text,
      _ => _value.text,
    };
    Navigator.pop(context, LcVarDraft(name: name, type: _type, initial: initial));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final editing = widget.editing;
    return AlertDialog(
      scrollable: true,
      title: Text(editing == null ? '新建${widget.noun}' : '编辑${widget.noun}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            key: const ValueKey('lc-var-name'),
            controller: _name,
            autofocus: editing == null,
            autocorrect: false,
            style: const TextStyle(fontFamily: kMonoFont, fontFamilyFallback: kMonoFallback),
            decoration: InputDecoration(labelText: '名字', hintText: '比如 count', errorText: _nameError, errorMaxLines: 3),
            onSubmitted: (_) => _save(),
          ),
          const SizedBox(height: Space.x4),
          Text('类型', style: t.labelMedium),
          const SizedBox(height: Space.x1),
          Wrap(
            spacing: Space.x2,
            children: [
              for (final type in _types)
                LcChoiceChip(
                  key: ValueKey('lc-var-type-$type'),
                  label: describeVarType(type),
                  selected: _type == type,
                  onSelected: () => setState(() {
                    // 换类型时原来填的值多半对不上，清掉（数字换文字这种能留的留着）。
                    if (type == 'number' && lcParseNumber(_value.text) == null) _value.clear();
                    if ((type == 'list' || type == 'record') != _json || (_json && type != _type)) _value.clear();
                    _type = type;
                    _valueError = null;
                  }),
                ),
            ],
          ),
          const SizedBox(height: Space.x3),
          if (_type == 'bool')
            SwitchListTile(key: const ValueKey('lc-var-flag'), contentPadding: EdgeInsets.zero, title: Text('初始值：${_flag ? '是' : '否'}'), value: _flag, onChanged: (v) => setState(() => _flag = v))
          else
            TextField(
              key: const ValueKey('lc-var-initial'),
              controller: _value,
              keyboardType: _type == 'number' ? const TextInputType.numberWithOptions(decimal: true, signed: true) : (_json ? TextInputType.multiline : TextInputType.text),
              minLines: _json ? 3 : 1,
              maxLines: _json ? 8 : 1,
              autocorrect: !_json,
              style: _json ? const TextStyle(fontFamily: kMonoFont, fontFamilyFallback: kMonoFallback) : null,
              decoration: InputDecoration(
                labelText: '初始值',
                hintText: switch (_type) {
                  'number' => '不填就是 0',
                  'list' => '比如 ["苹果", "香蕉"]；不填就是空的',
                  'record' => '比如 {"name": "小明"}；不填就是空的',
                  _ => '可以不填',
                },
                errorText: _valueError,
                errorMaxLines: 3,
              ),
              onSubmitted: _json ? null : (_) => _save(),
            ),
          if (editing != null && widget.refCount > 0) ...[const SizedBox(height: Space.x3), Text('有 ${widget.refCount} 处在用它；改名会一起改过去。', style: t.bodySmall)],
        ],
      ),
      actionsAlignment: MainAxisAlignment.spaceBetween,
      actions: [
        if (editing != null)
          TextButton(
            onPressed: () => Navigator.pop(context, LcVarDraft(name: editing.name, type: editing.type, initial: editing.initial, delete: true)),
            style: TextButton.styleFrom(foregroundColor: c.danger),
            child: const Text('删除'),
          )
        else
          const SizedBox.shrink(),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              style: TextButton.styleFrom(foregroundColor: c.textMuted),
              child: const Text('取消'),
            ),
            TextButton(onPressed: _save, child: Text(editing == null ? '新建' : '保存')),
          ],
        ),
      ],
    );
  }
}

/// 页面变量面板。[read] 每次都给最新的文档（搭建页撤销重做后会换对象）；[edit] 提交一次改动。
class LcVarsSheet extends StatefulWidget {
  const LcVarsSheet({super.key, required this.read, required this.edit});
  final LcDocument Function() read;
  final LcEdit edit;

  @override
  State<LcVarsSheet> createState() => _LcVarsSheetState();
}

class _LcVarsSheetState extends State<LcVarsSheet> {
  Set<String> _names() => {for (final v in widget.read().logic.variables) v.name};

  Future<void> _create() async {
    final draft = await showLcVariableDialog(context, taken: _names());
    if (draft == null || !mounted) return;
    widget.edit((d) => lcApplyVarDraft(d.logic, draft));
    setState(() {});
  }

  Future<void> _edit(LcVariable v) async {
    final old = v.name;
    final refs = widget.read().logic.variableRefCount(old);
    final draft = await showLcVariableDialog(context, taken: _names(), editing: v, refCount: refs);
    if (draft == null || !mounted) return;
    if (draft.delete) {
      if (refs > 0) {
        final ok = await confirmDialog(context, title: '删除状态 $old？', message: '有 $refs 处在用它。删掉以后那些积木会被标出问题，要你一个个改。', confirmLabel: '删除', danger: true);
        if (!ok || !mounted) return;
      }
      widget.edit((d) => d.logic.removeVariable(old));
    } else {
      final same = draft.name == old && draft.type == v.type && draft.initial == v.initial;
      if (same) return;
      widget.edit((d) {
        final logic = d.logic;
        if (!logic.renameVariable(old, draft.name)) return;
        logic.retypeVariable(draft.name, draft.type);
        logic.variable(draft.name)?.initial = draft.initial;
      });
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final logic = widget.read().logic;
    return LcSheetFrame(
      title: '页面状态',
      note: '状态用来记住东西（次数、输入的字、开关…），积木可以读它、改它。',
      footer: FilledButton.icon(key: const ValueKey('lc-vars-add'), onPressed: _create, icon: const Icon(Icons.add_rounded, size: 18), label: const Text('新建状态')),
      children: [
        if (logic.variables.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.x4, vertical: Space.x6),
            child: Text(
              '还没有状态。',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: c.textMuted),
            ),
          ),
        for (final v in logic.variables)
          InkWell(
            key: ValueKey('lc-vars-row-${v.name}'),
            onTap: () => _edit(v),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.x4, vertical: Space.x2),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          v.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontFamily: kMonoFont, fontFamilyFallback: kMonoFallback, fontSize: FontSize.base, fontWeight: FontWeight.w600, color: c.text),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          () {
                            final refs = logic.variableRefCount(v.name);
                            return '${describeVarType(v.type)} · 初始值 ${_initialText(v.initial)} · ${refs == 0 ? '还没用到' : '$refs 处在用'}';
                          }(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded, size: 20, color: c.textFaint),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// 底部面板的统一骨架：标题（可带一行说明）+ 可滚动的内容 + 固定在底下的按钮区。
class LcSheetFrame extends StatelessWidget {
  const LcSheetFrame({super.key, required this.title, this.note, this.header, required this.children, this.footer});
  final String title;
  final String? note;

  /// 标题下面、不跟着滚动的一块（面包屑、分类标签）。
  final Widget? header;
  final List<Widget> children;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final media = MediaQuery.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: (media.size.height - media.viewInsets.bottom) * 0.85),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(Space.x4, 0, Space.x4, Space.x2),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: t.titleLarge),
                    if (note != null) ...[const SizedBox(height: 2), Text(note!, style: t.bodySmall)],
                  ],
                ),
              ),
              ?header,
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.only(bottom: Space.x2),
                  children: children,
                ),
              ),
              if (footer != null) Padding(padding: const EdgeInsets.fromLTRB(Space.x4, Space.x2, Space.x4, Space.x3), child: footer),
            ],
          ),
        ),
      ),
    );
  }
}

/// 把刚填的新变量建出来（已经有同名的就不动）。
void lcApplyVarDraft(LcLogic logic, LcVarDraft? draft) {
  if (draft == null || logic.variable(draft.name) != null) return;
  logic.addVariable(draft.name, type: draft.type, initial: draft.initial);
}

/// 面板里“几个里选一个”的小标签。选中＝实心强调色 + 白字（不用主题默认的选中色：深色主题下那个颜色配白字看不清）。
class LcChoiceChip extends StatelessWidget {
  const LcChoiceChip({super.key, required this.label, required this.selected, required this.onSelected, this.avatar, this.tooltip});
  final String label;
  final bool selected;
  final VoidCallback onSelected;
  final Widget? avatar;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ChoiceChip(
      avatar: avatar,
      tooltip: tooltip,
      label: Text(label),
      labelStyle: TextStyle(color: selected ? c.onAccent : c.text, fontSize: FontSize.sm, fontWeight: selected ? FontWeight.w600 : FontWeight.w400),
      selected: selected,
      showCheckmark: false,
      selectedColor: c.accentFill,
      backgroundColor: c.surface,
      side: BorderSide(color: selected ? c.accentFill : c.border),
      onSelected: (_) => onSelected(),
    );
  }
}
