// 设计约束（低代码 · 顶部导航栏“常用”页最下面的“共用”那一块 · 390×844；第四轮 B3，规矩见 top_shared.dart）
// - 只有多页面的项目里才出现。入口和底部导航那一块（inspector_nav_shared_widgets.dart）同一套，从上到下一行一件事。
// - 还没共用：一个整宽的描边按钮“改成各页共用…”。点了先说清楚会动哪几页：
//     各页顶栏的样子都一样（或只有这一页有）→ 一个确认框；不一样 → 一张单子“以哪一页的为准”。
//     每一页的标题、返回箭头、左右按钮和作准的不一样的，留成那一页自己的（确认框里写明）。
// - 已经共用：
//     一条浅强调色的说明：“各页共用 · N 个页面在显示。样子在这里改，那些页面一起变。”
//     三行开关，一行一样：“这一页用自己的标题 / 返回箭头 / 左右按钮”。关上＝换回共用的那一份（左右按钮关上前先问，因为会丢掉这一页放的）。
//     文字按钮“这一页不显示”（要再显示：右上角“页面”› 那一页的 ⋮）
//     文字按钮“取消共用…”（先问；各页留着当时的样子）
// - 取用的 tokens：Space.x2/x3、accentSoft（说明条）、textMuted（小字）。
import 'package:lopicode/lowcode/editor_workbench_widgets.dart';
import 'package:lopicode/lowcode/inspector_common_widgets.dart';
import 'package:lopicode/lowcode/model.dart';
import 'package:lopicode/lowcode/top_shared.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/widgets.dart';
import 'package:material_ui/material_ui.dart';

String _names(List<LcPage> pages) => [for (final p in pages) '「${p.title}」'].join('、');

class LcTopShareBlock extends StatelessWidget {
  const LcTopShareBlock({super.key, required this.ed});
  final InspectorEdit ed;

  Future<void> _share(BuildContext context) async {
    final doc = ed.doc;
    var base = doc.page.id;
    if (!lcTopsAllSame(doc)) {
      final picked = await showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        builder: (_) => _PickBaseSheet(doc: doc),
      );
      if (picked == null || !context.mounted) return;
      base = picked;
    } else {
      final plan = lcShareTopPlan(doc, base);
      if (plan == null) return;
      final keepers = [
        for (final p in plan.replaced)
          if (plan.keeps[p.id]?.isNotEmpty ?? false)
            '「${p.title}」留着自己的${[for (final k in kLcTopOwnKeys)
              if (plan.keeps[p.id]!.contains(k)) kLcTopOwnLabels[k]].join('、')}',
      ];
      final lines = [
        '以后在任何一页改这条顶栏的样子（居左居中、背景、文字颜色、固定顶部），用它的页面都一起变。',
        if (plan.replaced.isNotEmpty) '${_names(plan.replaced)}的顶栏会换成共用的。',
        if (keepers.isNotEmpty) '${keepers.join('；')}。',
        '每一页的标题、返回箭头、左右按钮可以用自己的。没有顶栏的页不会自动加上。做错了可以撤销。',
      ];
      final ok = await confirmDialog(context, title: '改成各页共用', message: lines.join('\n'), confirmLabel: '改成共用');
      if (!ok || !context.mounted) return;
    }
    var n = 0;
    ed.editDoc!((d) => n = lcShareTop(d, base));
    if (context.mounted) showEditorHint(context, n == 0 ? '没改成：那一页已经没有顶栏了。' : '已改成共用：$n 个页面在显示这一条。');
  }

  Future<void> _unshare(BuildContext context) async {
    final ok = await confirmDialog(context, title: '取消共用', message: '每一页留着现在的样子，变回各页自己的一条：以后在一页上改，别的页不会跟着变。做错了可以撤销。', confirmLabel: '取消共用');
    if (!ok || !context.mounted) return;
    ed.editDoc!(lcUnshareTop);
    if (context.mounted) showEditorHint(context, '已取消共用。');
  }

  void _hideHere(BuildContext context) {
    final title = ed.doc.page.title;
    ed.editDoc!((d) => lcSetPageShowsSharedTop(d, d.page.id, false));
    showEditorHint(context, '「$title」不显示顶部导航了。要再显示：右上角“页面”› 这一页的 ⋮。');
  }

  Future<void> _own(BuildContext context, String key, bool mine) async {
    final id = ed.node.id;
    if (!mine && key == 'slots' && ed.node.children.isNotEmpty) {
      final ok = await confirmDialog(context, title: '左右按钮换回共用的', message: '这一页顶栏左右两边放的控件会换成共用的那一份，这一页给它们接的逻辑也会去掉。做错了可以撤销。', confirmLabel: '换回共用的');
      if (!ok || !context.mounted) return;
    }
    ed.editDoc!((d) {
      final n = d.find(id);
      if (n != null) lcSetTopOwn(d, n, key, mine);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (ed.editDoc == null || !ed.doc.isMultiPage) return const SizedBox.shrink();
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    if (!lcIsSharedTop(ed.node)) {
      return Padding(
        padding: const EdgeInsets.only(top: Space.x2),
        child: OutlinedButton(key: const Key('lc-top-share'), onPressed: () => _share(context), child: const Text('改成各页共用…')),
      );
    }
    final count = lcSharedTopPageCount(ed.doc), own = lcTopOwn(ed.node);
    return Padding(
      padding: const EdgeInsets.only(top: Space.x2),
      child: Column(
        key: const Key('lc-top-shared'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: Space.x3, vertical: Space.x2),
            decoration: BoxDecoration(color: c.accentSoft, borderRadius: BorderRadius.circular(Radii.sm)),
            child: Text('各页共用 · $count 个页面在显示。样子在这里改，那些页面一起变；下面三样每页可以用自己的。', style: t.bodySmall?.copyWith(color: c.text)),
          ),
          for (final k in kLcTopOwnKeys)
            Row(
              children: [
                Expanded(child: Text('这一页用自己的${kLcTopOwnLabels[k]}', style: t.bodyMedium)),
                Switch(key: Key('lc-top-own-$k'), value: own.contains(k), onChanged: (v) => _own(context, k, v)),
              ],
            ),
          TextButton(key: const Key('lc-top-hide-here'), onPressed: () => _hideHere(context), child: const Text('这一页不显示')),
          TextButton(key: const Key('lc-top-unshare'), onPressed: () => _unshare(context), child: const Text('取消共用…')),
        ],
      ),
    );
  }
}

/// “以哪一页的为准”：各页顶栏的样子不一样时挑一页。
class _PickBaseSheet extends StatelessWidget {
  const _PickBaseSheet({required this.doc});
  final LcDocument doc;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    return SafeArea(
      child: ListView(
        key: const Key('lc-top-share-pick'),
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: Space.x3),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.x4, Space.x2, Space.x4, Space.x1),
            child: Text('以哪一页的为准', style: t.titleMedium),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.x4, 0, Space.x4, Space.x2),
            child: Text('各页顶栏的样子不一样。挑一页：别的页的样子会换成它的；各页的标题、返回箭头、左右按钮留着自己的（做错了可以撤销）。', style: t.bodySmall?.copyWith(color: c.textMuted)),
          ),
          for (final (p, n) in lcTopCandidates(doc))
            ListTile(
              key: Key('lc-top-share-base-${p.id}'),
              leading: Icon(Icons.description_outlined, color: c.textMuted),
              title: Text(p.id == doc.page.id ? '${p.title}（就是这一页）' : p.title, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text('标题：${n.strProp('title') ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis),
              onTap: () => Navigator.pop(context, p.id),
            ),
        ],
      ),
    );
  }
}
