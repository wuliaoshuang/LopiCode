// 设计约束（低代码 · 合一面板“常用”页 · 选中一个自定义组件时多出来的三组 · 390×844）
// - 都是“一行一件事”，名字在左、现在的值在右、整行可点；没设的值用强调色写“选一个 / 设置”，设了的用弱化色。
// - ①“样子”（组件有变体才有）：一组变体一行，点了出单子选一个，最下面一行“不选（平时的样子）”。
// - ②“属性跟着状态变”（组件有属性才有）：一个属性一行，点了出单子选页面里的一个状态；选了以后上面填的固定值不再起作用，
//   所以这一行下面有一句灰字说明。只能选状态本身（要拼、要比，先在“状态”页做一个派生值再选它）。
// - ③“组件的事件”（组件有事件才有）：一个事件一行，右边写现在接的动作；点了出单子选做哪件事
//   （去页面 / 打开网址 / 弹出提示 / 打开弹窗 / 关闭弹窗 / 让一个数字加 1；带数据的事件多一样“把一个状态设成事件带来的值”），再填 / 选它要的那一样东西；最下面一行“不要这个动作”。
// - 没有主操作。取用的 tokens：Space.x2/x3/x4、accent、textMuted、textFaint、danger、border。
import 'package:lopicode/lowcode/bind_model.dart';
import 'package:lopicode/lowcode/component_extras.dart';
import 'package:lopicode/lowcode/component_model.dart';
import 'package:lopicode/lowcode/logic_model.dart';
import 'package:lopicode/lowcode/model.dart';
import 'package:lopicode/lowcode/quick_actions.dart';
import 'package:lopicode/lowcode/state_model.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/widgets.dart';
import 'package:material_ui/material_ui.dart';

/// 组件事件上能挂的快捷动作。
const List<LcQuickAction> kLcEventQuickActions = [...kLcQuickActions, kLcBumpQuick, kLcTakeQuick];

String _actionName(LcQuickAction a) => a.label.startsWith('点击时') ? a.label.substring(3) : a.label;

/// 一串积木如果正好是一个快捷动作：返回（动作, 填的值）。
(LcQuickAction, String)? lcEventQuickOf(List<LcBlock> body) {
  if (body.length != 1) return null;
  for (final a in kLcEventQuickActions) {
    final v = lcQuickBlockValue(body.single, a);
    if (v != null) return (a, v);
  }
  return null;
}

/// 选一样：[choices] 是（值, 给人看的名字）；[none] 不是 null 时最下面多一行（选它返回空字）。没选返回 null。
Future<String?> lcPickFromList(BuildContext context, {required String title, required List<(String, String)> choices, String? current, String? none, String keyPrefix = 'lc-pick'}) =>
    showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        final c = context.colors;
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.7),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(vertical: Space.x3),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(Space.x4, Space.x2, Space.x4, Space.x2),
                  child: Text(title, style: Theme.of(context).textTheme.titleMedium),
                ),
                for (final (id, name) in choices)
                  ListTile(
                    key: Key('$keyPrefix-$id'),
                    title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
                    trailing: id == current ? Icon(Icons.check, color: c.accent) : null,
                    onTap: () => Navigator.pop(context, id),
                  ),
                if (none != null)
                  ListTile(
                    key: Key('$keyPrefix-none'),
                    title: Text(none, style: TextStyle(color: c.danger)),
                    onTap: () => Navigator.pop(context, ''),
                  ),
              ],
            ),
          ),
        );
      },
    );

class ComponentInstanceExtras extends StatelessWidget {
  const ComponentInstanceExtras({super.key, required this.doc, required this.node, required this.apply});
  final LcDocument doc;
  final LcNode node;
  final void Function(void Function(LcNode n) change) apply;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final ref = node.props['ref'];
    final def = ref is String ? doc.component(ref) : null;
    if (def == null) return const SizedBox.shrink();
    final groups = lcVariantGroups(def);
    final variants = lcVariants(def);
    final picked = lcInstanceVariants(def, node);
    final events = lcCompEvents(def);
    final on = lcOnOf(node);

    Widget row(String id, String label, String? value, String unset, VoidCallback onTap) => InkWell(
      key: Key(id),
      onTap: onTap,
      child: SizedBox(
        height: 48,
        child: Row(
          children: [
            Text(label, style: t.bodyLarge),
            const SizedBox(width: Space.x3),
            Expanded(
              child: Text(
                value ?? unset,
                textAlign: TextAlign.right,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: t.bodyMedium?.copyWith(color: value == null ? c.accent : c.textMuted),
              ),
            ),
            Icon(Icons.chevron_right, size: 20, color: c.textMuted),
          ],
        ),
      ),
    );
    Widget head(String text) => Padding(
      padding: const EdgeInsets.only(top: Space.x3),
      child: Text(text, style: t.labelLarge?.copyWith(color: c.textMuted)),
    );

    Future<void> pickVariant(String group) async {
      final v = await lcPickFromList(
        context,
        title: groups[group] ?? group,
        choices: [
          for (final x in variants)
            if (x.group == group) (x.name, x.label),
        ],
        current: picked[group],
        none: '不选（平时的样子）',
        keyPrefix: 'comp-variant-pick',
      );
      if (v != null) apply((n) => lcSetInstanceVariant(n, group, v.isEmpty ? null : v));
    }

    Future<void> pickState(LcComponentProp p) async {
      final want = switch (p.type) {
        'number' => 'number',
        'bool' => 'bool',
        'list' => 'list',
        _ => 'text',
      };
      final cur = lcDataExpr(node, p.name);
      final v = await lcPickFromList(
        context,
        title: '${p.name} 跟着哪个状态变',
        choices: [
          for (final s in lcStatesInScope(doc))
            if (s.variable.type == want || want == 'text') (s.name, '${s.name} · ${lcStateTypeLabel(s.variable.type)}${s.project ? ' · 项目级' : ''}'),
        ],
        current: cur != null && cur['e'] == 'var' ? cur['name'] as String? : null,
        none: cur == null ? null : '不跟状态（用上面填的值）',
        keyPrefix: 'comp-bind-pick',
      );
      if (v != null) apply((n) => lcSetData(n, p.name, v.isEmpty ? null : {'from': 'var', 'name': v}));
    }

    Future<void> pickAction(LcCompEvent e) async {
      final now = on[e.name] == null ? null : lcEventQuickOf(on[e.name]!);
      final which = await lcPickFromList(
        context,
        title: '${e.label}：做什么',
        // “把一个状态设成事件带来的值”只有带数据的事件才有。
        choices: [
          for (final a in kLcEventQuickActions)
            if (!identical(a, kLcTakeQuick) || e.params.isNotEmpty) (a.id, _actionName(a)),
        ],
        current: now?.$1.id,
        none: on[e.name] == null ? null : '不要这个动作',
        keyPrefix: 'comp-event-act',
      );
      if (which == null || !context.mounted) return;
      if (which.isEmpty) return apply((n) => lcSetOn(n, e.name, null));
      final a = kLcEventQuickActions.firstWhere((x) => x.id == which);
      final take = identical(a, kLcTakeQuick);
      final picksState = take || identical(a, kLcBumpQuick);
      final choices = picksState
          ? [
              for (final s in lcStatesInScope(doc))
                if (!s.variable.isDerived && (take ? LcVariable.types.contains(s.variable.type) : s.variable.type == 'number')) (s.name, s.name),
            ]
          : a.picksPage
          ? [
              for (final p in doc.pages)
                if (!identical(p, doc.page)) (p.id, p.title),
            ]
          : [for (final d in a.picksDialog ? lcDialogsOf(doc) : const <LcNode>[]) (d.id, lcDialogName(d))];
      final old = now != null && identical(now.$1, a) ? now.$2 : null;
      final String? v;
      if (picksState || a.picksId) {
        if (choices.isEmpty) {
          await showDialog<void>(
            context: context,
            builder: (context) => AlertDialog(
              content: Text(
                take
                    ? '页面里还没有能放这个值的状态（文字、数字、是 / 否）。先到“状态”页加一个。'
                    : identical(a, kLcBumpQuick)
                    ? '页面里还没有“数字”类型的状态。先到“状态”页加一个。'
                    : (a.picksPage ? '项目里还没有别的页面。先加一个页面。' : '页面里还没有弹窗。先加一个弹窗。'),
              ),
              actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('知道了'))],
            ),
          );
          return;
        }
        v = await lcPickFromList(context, title: _actionName(a), choices: choices, current: old, keyPrefix: 'comp-event-val');
      } else {
        v = await promptDialog(context, title: _actionName(a), initial: old ?? '', hint: a.hint, confirmLabel: '保存');
      }
      if (v == null || v.trim().isEmpty) return;
      final value = v.trim();
      apply((n) => lcSetOn(n, e.name, [lcQuickBlock(a, value)]));
    }

    String? actionText(LcCompEvent e) {
      final body = on[e.name];
      if (body == null) return null;
      final q = lcEventQuickOf(body);
      if (q == null) return '${body.length} 块积木';
      final (a, v) = q;
      final shown = a.picksPage ? (doc.pageTitle(v) ?? '页面已经删了') : (a.picksDialog ? (doc.find(v)?.type == 'dialog' ? lcDialogName(doc.find(v)!) : '弹窗已经删了') : v);
      return '${_actionName(a)}：$shown';
    }

    return Column(
      key: const Key('comp-instance-extras'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (groups.isNotEmpty) ...[
          head('样子'),
          for (final g in groups.entries)
            row(
              'comp-variant-${g.key}',
              g.value,
              () {
                for (final x in variants) {
                  if (x.group == g.key && x.name == picked[g.key]) return x.label;
                }
                return null;
              }(),
              '选一个',
              () => pickVariant(g.key),
            ),
        ],
        if (def.props.isNotEmpty) ...[
          head('属性跟着状态变'),
          for (final p in def.props)
            row(
              'comp-bind-${p.name}',
              p.name,
              () {
                final e = lcDataExpr(node, p.name);
                return e == null ? null : (e['e'] == 'var' ? '跟着 ${e['name']}' : '跟着一个式子');
              }(),
              '选一个状态',
              () => pickState(p),
            ),
          Text('选了状态以后，这个属性跟着状态走，上面填的固定值不再起作用。', style: t.bodySmall?.copyWith(color: c.textFaint)),
        ],
        if (events.isNotEmpty) ...[
          head('组件的事件'),
          for (final e in events) row('comp-event-${e.name}', e.label, actionText(e), '设置', () => pickAction(e)),
          Text('这里先能接最常见的几件事；更复杂的逻辑等积木那边接上“当组件发出事件”以后在积木里写。', style: t.bodySmall?.copyWith(color: c.textFaint)),
        ],
        const SizedBox(height: Space.x2),
        Divider(height: 1, color: c.border),
      ],
    );
  }
}
