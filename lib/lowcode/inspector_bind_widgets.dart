// 设计约束（低代码 · 面板里的“数据绑定” · 390×844，浅色 + 深色；第 5 期，设计见 docs/blocks-v5-parts/E-editor-components.md §10.8）
// - 绑定是控件的设置，不是积木。两处入口：
//   (1) “常用”页里每个能绑的设置，行尾一个链环小按钮（36 宽，不抢行里原来的东西）。点它＝挑一个状态。
//       绑上以后这一行换个样子：名字照旧在左，右边是一块强调色的小牌子（写着从哪儿来）+ 一个“×”（解除）。
//       原来的输入框收起来——写死的值这时不起作用，留着只会让人以为还能改。
//   (2) “常用”页最下面的“数据”一节：跟状态同步（输入类）、重复、显示条件；不常用的三样（存在条件、类名开关、样式）收在“更多绑定”里。
//       每行一件事：没设＝一个灰色药丸（“选一个状态”“设一个条件”…）；设了＝强调色小牌子 + “×”。
// - 没有主操作：挑完就生效，一次一条撤销。
// - 自定义组件里面的控件这一期不绑（留给组件库那一期）：那里没有行尾按钮，也没有“数据”一节。
// - 取用的 tokens：Space.x1/x2/x3、Radii.sm、accent / accentSoft（小牌子）、textMuted / textFaint。
import 'package:lopicode/lowcode/bind_eval.dart';
import 'package:lopicode/lowcode/bind_model.dart';
import 'package:lopicode/lowcode/bind_picker_sheet.dart';
import 'package:lopicode/lowcode/bind_repeat_sheet.dart';
import 'package:lopicode/lowcode/bind_simple.dart';
import 'package:lopicode/lowcode/inspector_common_widgets.dart';
import 'package:lopicode/lowcode/inspector_presets_widgets.dart';
import 'package:lopicode/lowcode/logic_model.dart';
import 'package:lopicode/lowcode/model.dart';
import 'package:lopicode/lowcode/style_controls_widgets.dart';
import 'package:lopicode/lowcode/theme_scope_widgets.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/widgets.dart';
import 'package:material_ui/material_ui.dart';

/// 这个组件外面（含它自己，[self]）的“重复”带出来的名字；“这一项”带上列表初值的第一项（面板列它有哪些格子）。
List<LcLocal> lcLocalsOf(InspectorEdit ed, {bool self = true}) {
  final env = LcBindEnv.of(ed.doc);
  return lcLocalsAt(
    ed.doc.root,
    ed.node.id,
    self: self,
    firstOf: (list) {
      final v = lcEval(list, env);
      return v is List && v.isNotEmpty ? v.first : null;
    },
  );
}

/// 打开“绑定到状态”，返回挑的结果。新建的状态是页面级的（项目级的去“状态”页建）。
Future<LcBindPick?> lcPickBinding(BuildContext context, InspectorEdit ed, {required String title, required String want, Map<String, dynamic>? current, bool self = true, List<LcLocal>? locals}) {
  var doc = ed.doc;
  final editDoc = ed.editDoc;
  return showLcBindPicker(
    context,
    title: title,
    want: want,
    doc: () => doc,
    locals: locals ?? lcLocalsOf(ed, self: self),
    current: current,
    onNewState: editDoc == null
        ? null
        : () async {
            final draft = await showLcNewStateDialog(context, doc);
            if (draft == null) return;
            editDoc((d) {
              doc = d;
              if (d.logic.variable(draft.name) == null) d.logic.variables.add(LcVariable(name: draft.name, type: draft.type, initial: draft.initial));
            });
          },
  );
}

/// “绑着”的小牌子 + 解除按钮。
class LcBoundPill extends StatelessWidget {
  const LcBoundPill({super.key, required this.id, required this.text, required this.onTap, required this.onClear});
  final String id;
  final String text;
  final VoidCallback onTap;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Flexible(
        child: LcVarBadge(key: Key('lc-bound-$id'), label: text, onTap: onTap),
      ),
      IconButton(key: Key('lc-unbind-$id'), onPressed: onClear, icon: const Icon(Icons.close, size: 18), tooltip: '解除绑定', visualDensity: VisualDensity.compact, color: context.colors.textMuted),
    ],
  );
}

/// 把“常用”页的一行包一下：这个属性能绑的话，没绑时行尾多一个链环按钮，绑了整行换成小牌子。不能绑的原样返回。
class LcBindableRow extends StatelessWidget {
  const LcBindableRow({super.key, required this.ed, required this.prop, required this.label, required this.child});
  final InspectorEdit ed;
  final String prop;
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final spec = ed.canBind ? lcBindable(ed.node.type, prop) : null;
    if (spec == null) return child;
    final expr = lcDataExpr(ed.node, prop);
    Future<void> open() async {
      final r = await lcPickBinding(context, ed, title: spec.label, want: spec.type, current: expr == null ? null : lcSrcExpr(expr));
      if (r == null) return;
      ed.apply((n, _) => lcSetData(n, prop, r.clear ? null : r.source));
    }

    if (expr != null) {
      return InspectorRow(
        label: label,
        scroll: false,
        child: LcBoundPill(id: prop, text: lcDescribeExpr(expr), onTap: open, onClear: () => ed.apply((n, _) => lcSetData(n, prop, null))),
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: child),
        SizedBox(
          width: 36,
          height: 52,
          child: IconButton(
            key: Key('lc-bind-$prop'),
            onPressed: open,
            icon: const Icon(Icons.link, size: 18),
            tooltip: '让“${spec.label}”跟着状态变',
            padding: EdgeInsets.zero,
            color: context.colors.textMuted,
          ),
        ),
      ],
    );
  }
}

/// “常用”页最下面的“数据”一节。这个组件什么都不能设时不出现（返回空的）。
class InspectorDataSection extends StatelessWidget {
  const InspectorDataSection({super.key, required this.ed});
  final InspectorEdit ed;

  LcNode get n => ed.node;

  Widget _unset(String id, String label, VoidCallback onTap) => Align(
    alignment: Alignment.centerLeft,
    child: InspectorChip(key: Key('lc-data-$id'), label: label, selected: false, onTap: onTap),
  );

  Widget _cond(BuildContext context, String id, String label, String field, String ask) {
    final expr = lcSrcExprOf(n.more[field]);
    Future<void> open() async {
      final r = await lcPickBinding(context, ed, title: label, want: 'bool', current: expr == null ? null : lcSrcExpr(expr));
      if (r != null) ed.apply((n, _) => lcSetCond(n, field, r.clear ? null : r.source));
    }

    return InspectorRow(
      label: label,
      scroll: false,
      child: expr == null ? _unset(id, ask, open) : LcBoundPill(id: id, text: lcDescribeExpr(expr), onTap: open, onClear: () => ed.apply((n, _) => lcSetCond(n, field, null))),
    );
  }

  Future<void> _repeat(BuildContext context) async {
    final rep = lcRepeatOf(n);
    final r = await showLcRepeatSheet(context, ed: ed, current: rep);
    if (r == null) return;
    ed.apply((n, _) => r.remove ? lcSetRepeat(n, listSrc: null) : lcSetRepeat(n, listSrc: r.list, item: r.item, index: r.index, keySrc: r.key, empty: r.empty, preview: r.preview));
  }

  Future<void> _addNamed(
    BuildContext context, {
    required String title,
    required String hint,
    required RegExp ok,
    required String want,
    required void Function(LcNode n, String name, Map<String, dynamic>? src) set,
  }) async {
    final name = await promptDialog(context, title: title, hint: hint);
    if (name == null || !context.mounted) return;
    final key = name.trim();
    if (!ok.hasMatch(key)) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text('“$key”不能用：$hint')));
      return;
    }
    final r = await lcPickBinding(context, ed, title: key, want: want);
    if (r == null || r.clear) return;
    ed.apply((n, _) => set(n, key, r.source));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final modelProp = lcModelProp(n.type);
    final wrap = lcCanWrapBind(n);
    if (!ed.canBind || (modelProp == null && !wrap)) return const SizedBox.shrink();
    final model = lcModelOf(n);
    final rep = lcRepeatOf(n);
    final classes = lcClassIfOf(n);
    final styles = lcStyleBinds(n);

    Future<void> pickModel() async {
      // 双向只能绑到一个能写的状态：派生值、“重复”带出来的名字不行（面板里只列状态，派生的由检查拦）。
      final r = await lcPickBinding(
        context,
        ed,
        title: modelProp == 'checked' ? '开没开' : '里面填的内容',
        want: modelProp == 'checked' ? 'bool' : 'any',
        current: model == null ? null : lcSrcVar(model),
        locals: const [],
      );
      if (r == null) return;
      final src = r.source;
      final name = src != null && src['from'] == 'var' && lcPathOf(src['path']).isEmpty ? src['name'] : null;
      if (!r.clear && name is! String) {
        if (context.mounted) ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(content: Text('跟状态同步要选一个状态本身（不能是拼出来的、比出来的，也不能是记录里的一格）')));
        return;
      }
      ed.apply((n, _) => lcSetModel(n, r.clear ? null : name as String));
    }

    return Column(
      key: const Key('lc-data-section'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: Space.x3),
        Text('数据', style: t.labelLarge?.copyWith(color: c.textMuted)),
        if (modelProp != null)
          InspectorRow(
            label: '跟状态同步',
            scroll: false,
            below: Text(modelProp == 'checked' ? '状态变了它跟着变；点了它，状态也跟着变。' : '状态变了它跟着变；在里面打字，状态也跟着变。', style: t.bodySmall?.copyWith(color: c.textFaint)),
            child: model == null ? _unset('model', '选一个状态', pickModel) : LcBoundPill(id: 'model', text: model, onTap: pickModel, onClear: () => ed.apply((n, _) => lcSetModel(n, null))),
          ),
        if (wrap) ...[
          InspectorRow(
            label: '重复',
            scroll: false,
            child: rep == null
                ? _unset('repeat', '按一张列表重复', () => _repeat(context))
                : LcBoundPill(id: 'repeat', text: '${lcDescribeExpr(rep.list)} 的每一项（${rep.item}）', onTap: () => _repeat(context), onClear: () => ed.apply((n, _) => lcSetRepeat(n, listSrc: null))),
          ),
          _cond(context, 'showIf', '显示条件', kLcShowIf, '设一个条件'),
          MoreSection(
            id: 'bind',
            label: '更多绑定',
            initiallyOpen: lcRenderIfExpr(n) != null || classes.isNotEmpty || styles.isNotEmpty,
            children: [
              _cond(context, 'renderIf', '存在条件', kLcRenderIf, '设一个条件'),
              Text('“显示条件”不成立时只是看不见，东西还在；“存在条件”不成立时网页里真的没有它。', style: t.bodySmall?.copyWith(color: c.textFaint)),
              for (final k in classes)
                InspectorRow(
                  label: '类名 ${k.name}',
                  scroll: false,
                  child: LcBoundPill(
                    id: 'class-${k.name}',
                    text: lcDescribeExpr(k.when),
                    onTap: () async {
                      final r = await lcPickBinding(context, ed, title: '类名 ${k.name}', want: 'bool', current: lcSrcExpr(k.when));
                      if (r != null) ed.apply((n, _) => lcSetClassIf(n, k.name, r.clear ? null : r.source));
                    },
                    onClear: () => ed.apply((n, _) => lcSetClassIf(n, k.name, null)),
                  ),
                ),
              for (final s in styles.entries)
                InspectorRow(
                  label: s.key,
                  scroll: false,
                  child: LcBoundPill(
                    id: 'style-${s.key}',
                    text: lcDescribeExpr(s.value),
                    onTap: () async {
                      final r = await lcPickBinding(context, ed, title: s.key, want: 'text', current: lcSrcExpr(s.value));
                      if (r != null) ed.apply((n, _) => lcSetStyleBind(n, s.key, r.clear ? null : r.source));
                    },
                    onClear: () => ed.apply((n, _) => lcSetStyleBind(n, s.key, null)),
                  ),
                ),
              Wrap(
                spacing: Space.x2,
                children: [
                  InspectorChip(
                    key: const Key('lc-data-add-class'),
                    label: '加一个类名开关',
                    selected: false,
                    onTap: () => _addNamed(context, title: '类名', hint: '字母开头，只用字母、数字、- 和 _', ok: kLcClassName, want: 'bool', set: lcSetClassIf),
                  ),
                  InspectorChip(
                    key: const Key('lc-data-add-style'),
                    label: '加一条样式',
                    selected: false,
                    onTap: () => _addNamed(context, title: 'CSS 属性名', hint: '小写字母和 -，例如 width、background-color', ok: kLcCssProp, want: 'text', set: lcSetStyleBind),
                  ),
                ],
              ),
              Text('类名开关：条件成立时给这个组件加上这个类名（类名的样子要在导出以后自己的样式表里写）。样式：某一条 CSS 的值跟着状态变。', style: t.bodySmall?.copyWith(color: c.textFaint)),
            ],
          ),
        ],
      ],
    );
  }
}
