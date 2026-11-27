// 设计约束（低代码 · “主题变量”页 · 390×844，浅色 + 深色；第 4 期，设计见 docs/blocks-v5-parts/E-editor-components.md §10.7）
// - 从哪进：搭建页顶栏“⋮”→“主题变量”。整页（PageBar），返回就回搭建页。
// - 这一页的用途：看项目里有哪些变量、改它们的值。主角是“变量的值”——颜色是一个大色块，数值是一段粗一点的字，都在行的最前面。
// - 从上到下：
//     一句灰色小字：变量整个项目共用，改了值用到的地方一起变。
//     按种类分节（颜色 / 字号 / 间距 / 圆角 / 其它；没有变量的种类不出现）。节标题是小号灰字。
//     一个变量一行（行高 56）：[值：色块或数值] [给人看的名字（主）／下面灰色小字“--代码名 · 用了 3 处”] [›]。整行可点＝改它。
//     最下面一个整宽的描边按钮“＋ 加一个变量”（次要操作）。
//   一个变量都没有：空状态 + 唯一的实心按钮“加一套起步的变量”（16 个：6 个颜色、4 个字号、3 个间距、3 个圆角）。
// - 改一个变量（底部面板，一行一件事）：名字 → 值（颜色点开取色面板；数值直接填，例如 16px）→ 代码里的名字（不常改，放最后，等宽字）。
//   底部：左“删除”（红字，新加的没有）、右“取消”“保存”（唯一实心）。值或名字写得不对时“保存”变灰，下面一句红字说哪儿不对。
// - 删除一定先问：说清楚有几处在用、删了以后那些地方换成它现在的值（样子不变，只是不再跟着变）。
// - 每个操作一条撤销（回到搭建页点撤销）。
// - 取用的 tokens：Space.x1/x2/x3/x4/x6、Radii.md、textMuted / textFaint（小字）、border（数值小牌子的边）、danger（删除、出错）。
import 'package:lopicode/lowcode/css_color.dart';
import 'package:lopicode/lowcode/edit_types.dart';
import 'package:lopicode/lowcode/model.dart';
import 'package:lopicode/lowcode/style_color_sheet.dart';
import 'package:lopicode/lowcode/style_model.dart';
import 'package:lopicode/lowcode/theme_vars.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/top_bar.dart';
import 'package:lopicode/ui/widgets.dart';
import 'package:material_ui/material_ui.dart';

/// 打开“主题变量”页。[doc] 取现在的文档（这一页开着的时候文档会被改）。
Future<void> showThemeVarsScreen(BuildContext context, {required LcDocument Function() doc, required LcEdit onEdit}) => Navigator.push(
  context,
  MaterialPageRoute<void>(
    builder: (_) => ThemeVarsScreen(doc: doc, onEdit: onEdit),
  ),
);

/// 这一类变量的值写得对不对；不对返回一句说明。
String? lcVarValueProblem(LcVarKind kind, String value) {
  final v = value.trim();
  if (v.isEmpty) return '还没填值';
  if (!lcVarValueOk(v)) return '值里不能有 { } ; < > 和换行';
  switch (kind) {
    case LcVarKind.color:
      return cssColorToArgb(v) == null ? '这不是一个颜色（例如 #058654）' : null;
    case LcVarKind.font || LcVarKind.space || LcVarKind.radius:
      final l = LcLength.parse(v);
      return l == null || !l.isNumeric ? '写成“数字 + 单位”，例如 16px' : null;
    case LcVarKind.other:
      return null;
  }
}

class ThemeVarsScreen extends StatefulWidget {
  const ThemeVarsScreen({super.key, required this.doc, required this.onEdit});
  final LcDocument Function() doc;
  final LcEdit onEdit;

  @override
  State<ThemeVarsScreen> createState() => _ThemeVarsScreenState();
}

class _ThemeVarsScreenState extends State<ThemeVarsScreen> {
  void _edit(void Function(LcDocument d) change) {
    widget.onEdit(change);
    if (mounted) setState(() {});
  }

  Future<void> _open(LcVarKind kind, [String? name]) async {
    final doc = widget.doc();
    final theme = lcThemeOf(doc);
    final r = await showModalBottomSheet<_VarResult>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _VarSheet(theme: theme, kind: kind, name: name, uses: name == null ? 0 : lcVarUseCount(doc, name)),
    );
    if (r == null || !mounted) return;
    if (r.delete) {
      final uses = lcVarUseCount(widget.doc(), name!);
      final ok = await confirmDialog(
        context,
        title: '删除“${theme.labelOf(name)}”？',
        message: uses == 0 ? '现在没有地方用它。删了可以撤销。' : '有 $uses 处在用它：删了以后那些地方换成它现在的值（${theme.resolved(name)}），样子不变，只是不再跟着变。删了可以撤销。',
        confirmLabel: '删除',
        danger: true,
      );
      if (ok) _edit((d) => lcRemoveVar(d, name));
      return;
    }
    _edit((d) {
      var code = name ?? r.code;
      if (name != null && r.code != name && lcRenameVar(d, name, r.code)) code = r.code;
      lcSetVar(d, code, r.value, label: r.label);
    });
  }

  Future<void> _add() async {
    final box = context.findRenderObject()! as RenderBox;
    final kind = await showMenu<LcVarKind>(
      context: context,
      position: RelativeRect.fromLTRB(Space.x4, box.size.height - 320, Space.x4, 0),
      items: [for (final k in LcVarKind.values) PopupMenuItem(key: Key('lc-var-kind-${k.name}'), value: k, child: Text(k.label))],
    );
    if (kind != null && mounted) await _open(kind);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final doc = widget.doc();
    final theme = lcThemeOf(doc);
    final full = theme.values.length >= kLcMaxVars;
    Widget row(String name) {
      final kind = LcVarKind.of(name);
      final value = theme.resolved(name);
      final uses = lcVarUseCount(doc, name);
      return InkWell(
        key: Key('lc-var-row-$name'),
        onTap: () => _open(kind, name),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.x4, vertical: Space.x1),
            child: Row(
              children: [
                SizedBox(
                  width: 72,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: kind == LcVarKind.color
                        ? ColorDot(argb: cssColorToArgb(value), size: 36)
                        : Container(
                            padding: const EdgeInsets.symmetric(horizontal: Space.x2, vertical: Space.x1),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(Radii.md),
                              border: Border.all(color: c.border),
                            ),
                            child: Text(value, style: t.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                          ),
                  ),
                ),
                const SizedBox(width: Space.x3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(theme.labelOf(name), style: t.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                      Text(
                        '--$name · ${uses == 0 ? '还没用' : '用了 $uses 处'}',
                        style: t.bodySmall?.copyWith(color: c.textMuted),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, size: 20, color: c.textFaint),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: const PageBar(titleText: '主题变量'),
      body: theme.isEmpty
          ? BelowBar(
              child: EmptyState(
                icon: Icons.palette_outlined,
                title: '还没有主题变量',
                message: '把常用的颜色、字号、间距、圆角起个名字存成变量，\n各个页面都用它；以后改一处，用到的地方一起变。',
                action: FilledButton(key: const Key('lc-var-starter'), onPressed: () => _edit(lcAddStarterVars), child: const Text('加一套起步的变量')),
              ),
            )
          : ListView(
              key: const Key('lc-var-list'),
              padding: EdgeInsets.only(top: PageBar.insetOf(context) + Space.x2, bottom: Space.x6 + MediaQuery.paddingOf(context).bottom),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(Space.x4, 0, Space.x4, Space.x2),
                  child: Text('整个项目共用：每个页面、每个自定义组件都能用。改了值，用到的地方一起变。', style: t.bodySmall?.copyWith(color: c.textMuted)),
                ),
                for (final kind in LcVarKind.values)
                  if (theme.namesOf(kind).isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(Space.x4, Space.x4, Space.x4, Space.x1),
                      child: Text(kind.label, style: t.labelLarge?.copyWith(color: c.textMuted)),
                    ),
                    for (final name in theme.namesOf(kind)) row(name),
                  ],
                Padding(
                  padding: const EdgeInsets.fromLTRB(Space.x4, Space.x6, Space.x4, 0),
                  child: OutlinedButton.icon(key: const Key('lc-var-add'), onPressed: full ? null : _add, icon: const Icon(Icons.add, size: 18), label: Text(full ? '最多 $kLcMaxVars 个变量' : '加一个变量')),
                ),
              ],
            ),
    );
  }
}

class _VarResult {
  const _VarResult({this.code = '', this.label = '', this.value = '', this.delete = false});
  final String code;
  final String label;
  final String value;
  final bool delete;
}

class _VarSheet extends StatefulWidget {
  const _VarSheet({required this.theme, required this.kind, required this.name, required this.uses});
  final LcTheme theme;
  final LcVarKind kind;

  /// 改的是哪个变量；null＝新加一个。
  final String? name;
  final int uses;

  @override
  State<_VarSheet> createState() => _VarSheetState();
}

class _VarSheetState extends State<_VarSheet> {
  late final String _initialCode = widget.name ?? lcFreshVarName(widget.theme, widget.kind);
  late final TextEditingController _label = TextEditingController(text: widget.name == null ? '' : widget.theme.labelOf(widget.name!));
  late final TextEditingController _value = TextEditingController(text: widget.name == null ? _defaultValue : widget.theme.values[widget.name!]);
  late final TextEditingController _code = TextEditingController(text: _initialCode);

  String get _defaultValue => switch (widget.kind) {
    LcVarKind.color => '#2962cb',
    LcVarKind.font => '16px',
    LcVarKind.space => '16px',
    LcVarKind.radius => '10px',
    LcVarKind.other => '',
  };

  @override
  void dispose() {
    _label.dispose();
    _value.dispose();
    _code.dispose();
    super.dispose();
  }

  String? get _problem {
    final value = lcVarValueProblem(widget.kind, lcSubstVars(_value.text, widget.theme.values));
    if (value != null) return value;
    final code = _code.text.trim();
    if (!kLcVarName.hasMatch(code)) return '代码里的名字：小写字母开头，只用小写字母、数字、连字符';
    if (code != widget.name && widget.theme.values.containsKey(code)) return '已经有一个叫 --$code 的变量了';
    if (LcVarKind.of(code) != widget.kind) return widget.kind == LcVarKind.other ? '“其它”类的名字不能以 color- / font- / space- / radius- 开头' : '代码里的名字要以 ${widget.kind.prefix} 开头（它是${widget.kind.label}）';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final problem = _problem;
    final isColor = widget.kind == LcVarKind.color;
    final shown = lcSubstVars(_value.text, widget.theme.values);
    Widget field(String label, Widget child) => Padding(
      padding: const EdgeInsets.only(bottom: Space.x3),
      child: Row(
        children: [
          SizedBox(
            width: 72,
            child: Text(label, style: t.bodyMedium?.copyWith(color: c.textMuted)),
          ),
          Expanded(child: child),
        ],
      ),
    );
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(Space.x4, 0, Space.x4, Space.x3),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(widget.name == null ? '加一个${widget.kind.label}变量' : '改变量', style: t.titleLarge),
              const SizedBox(height: Space.x4),
              field(
                '名字',
                TextField(
                  key: const Key('lc-var-label'),
                  controller: _label,
                  maxLength: kLcVarLabelMax,
                  decoration: InputDecoration(isDense: true, counterText: '', hintText: isColor ? '例如 主色' : '例如 正文'),
                ),
              ),
              field(
                '值',
                Row(
                  children: [
                    if (isColor) ...[
                      InkWell(
                        key: const Key('lc-var-pick-color'),
                        borderRadius: BorderRadius.circular(Radii.md),
                        onTap: () async {
                          final r = await showStyleColorPicker(context, initial: shown, title: '变量的颜色');
                          if (r?.css != null && mounted) setState(() => _value.text = r!.css!);
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(Space.x1),
                          child: ColorDot(argb: cssColorToArgb(shown), size: 36),
                        ),
                      ),
                      const SizedBox(width: Space.x2),
                    ],
                    Expanded(
                      child: TextField(
                        key: const Key('lc-var-value'),
                        controller: _value,
                        autocorrect: false,
                        enableSuggestions: false,
                        style: t.bodyLarge?.copyWith(fontFamily: kMonoFont, fontFamilyFallback: kMonoFallback),
                        decoration: InputDecoration(isDense: true, hintText: isColor ? '#RRGGBB' : '例如 16px'),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                  ],
                ),
              ),
              field(
                '代码名',
                TextField(
                  key: const Key('lc-var-code'),
                  controller: _code,
                  autocorrect: false,
                  enableSuggestions: false,
                  maxLength: 40,
                  style: t.bodyMedium?.copyWith(fontFamily: kMonoFont, fontFamilyFallback: kMonoFallback),
                  decoration: const InputDecoration(isDense: true, counterText: '', prefixText: '--'),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              Text(
                problem ?? (widget.name != null && widget.uses > 0 ? '有 ${widget.uses} 处在用它：改了值它们一起变；改代码里的名字，那些地方也一起改。' : '导出的网页里它叫 var(--${_code.text.trim()})。'),
                key: const Key('lc-var-note'),
                style: t.bodySmall?.copyWith(color: problem != null ? c.danger : c.textMuted),
              ),
              const SizedBox(height: Space.x3),
              Row(
                children: [
                  if (widget.name != null)
                    TextButton(
                      key: const Key('lc-var-delete'),
                      onPressed: () => Navigator.pop(context, const _VarResult(delete: true)),
                      style: TextButton.styleFrom(foregroundColor: c.danger),
                      child: const Text('删除'),
                    ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    style: TextButton.styleFrom(foregroundColor: c.textMuted),
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: Space.x2),
                  FilledButton(
                    key: const Key('lc-var-save'),
                    onPressed: problem != null ? null : () => Navigator.pop(context, _VarResult(code: _code.text.trim(), label: _label.text.trim(), value: _value.text.trim())),
                    child: const Text('保存'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
