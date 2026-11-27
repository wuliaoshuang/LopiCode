// 设计约束（低代码 · 底部导航栏“常用”页里“导航项”下面的“共用”那一块 · 390×844；第四轮 B1，规矩见 nav_shared.dart）
// - 只有多页面的项目里才出现（只有一页谈不上共用）。
// - 还没共用：一个整宽的描边按钮“改成各页共用…”（这块唯一的操作）。点了先说清楚会动哪几页：
//     各页的导航栏都一样（或只有这一页有）→ 一个确认框，列出“会换成共用的页 / 会加上导航的页”。
//     各页不一样 → 一张单子“以哪一页的为准”，一页一行（页名／下面小字是它的导航项），单子顶上说明“别的页的导航栏会被换成它”。
// - 已经共用：从上到下三行，一行一件事——
//     一条浅强调色的说明：“各页共用 · N 个页面在显示。在这里改，那些页面一起变。”
//     文字按钮“这一页不显示”（要再显示：右上角“页面”› 那一页的 ⋮）
//     文字按钮“取消共用…”（先问；各页留着当时的样子，以后各改各的）
// - 取用的 tokens：Space.x1/x2/x3、accentSoft（说明条）、textMuted（小字）。
import 'package:lopicode/lowcode/editor_workbench_widgets.dart';
import 'package:lopicode/lowcode/inspector_common_widgets.dart';
import 'package:lopicode/lowcode/model.dart';
import 'package:lopicode/lowcode/model_v3_components.dart';
import 'package:lopicode/lowcode/nav_shared.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/widgets.dart';
import 'package:material_ui/material_ui.dart';

String _names(List<LcPage> pages) => [for (final p in pages) '「${p.title}」'].join('、');

class LcNavShareBlock extends StatelessWidget {
  const LcNavShareBlock({super.key, required this.ed});
  final InspectorEdit ed;

  Future<void> _share(BuildContext context) async {
    final doc = ed.doc;
    var base = doc.page.id;
    if (!lcNavsAllSame(doc)) {
      final picked = await showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        builder: (_) => _PickBaseSheet(doc: doc),
      );
      if (picked == null || !context.mounted) return;
      base = picked;
    } else {
      final plan = lcShareNavPlan(doc, base);
      if (plan == null) return;
      final lines = [
        '以后在任何一页改这条导航栏（导航项、图标、去哪页、样子），用它的页面都一起变，不用再同步。',
        if (plan.replaced.isNotEmpty) '${_names(plan.replaced)}的导航栏和这条一样，会换成共用的。',
        if (plan.added.isNotEmpty) '${_names(plan.added)}还没有导航栏（导航项指着它），会在页面最后加上。',
        '哪一项亮着是自动的：指着哪一页，在那一页上就亮。做错了可以撤销。',
      ];
      final ok = await confirmDialog(context, title: '改成各页共用', message: lines.join('\n'), confirmLabel: '改成共用');
      if (!ok || !context.mounted) return;
    }
    var n = 0;
    ed.editDoc!((d) => n = lcShareNav(d, base));
    if (context.mounted) showEditorHint(context, n == 0 ? '没改成：那一页已经没有导航栏了。' : '已改成共用：$n 个页面在显示这一条。');
  }

  Future<void> _unshare(BuildContext context) async {
    final ok = await confirmDialog(context, title: '取消共用', message: '每一页留着现在的样子，变回各页自己的一条：以后在一页上改，别的页不会跟着变。做错了可以撤销。', confirmLabel: '取消共用');
    if (!ok || !context.mounted) return;
    ed.editDoc!(lcUnshareNav);
    if (context.mounted) showEditorHint(context, '已取消共用。');
  }

  void _hideHere(BuildContext context) {
    final title = ed.doc.page.title;
    ed.editDoc!((d) => lcSetPageShowsSharedNav(d, d.page.id, false));
    showEditorHint(context, '「$title」不显示底部导航了。要再显示：右上角“页面”› 这一页的 ⋮。');
  }

  @override
  Widget build(BuildContext context) {
    if (ed.editDoc == null || !ed.doc.isMultiPage) return const SizedBox.shrink();
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    if (!lcIsSharedNav(ed.node)) {
      return Padding(
        padding: const EdgeInsets.only(top: Space.x2),
        child: OutlinedButton(key: const Key('lc-nav-share'), onPressed: () => _share(context), child: const Text('改成各页共用…')),
      );
    }
    final count = lcSharedNavPageCount(ed.doc);
    return Padding(
      padding: const EdgeInsets.only(top: Space.x2),
      child: Column(
        key: const Key('lc-nav-shared'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: Space.x3, vertical: Space.x2),
            decoration: BoxDecoration(color: c.accentSoft, borderRadius: BorderRadius.circular(Radii.sm)),
            child: Text('各页共用 · $count 个页面在显示。在这里改，那些页面一起变；哪一项亮着是自动的。', style: t.bodySmall?.copyWith(color: c.text)),
          ),
          TextButton(key: const Key('lc-nav-hide-here'), onPressed: () => _hideHere(context), child: const Text('这一页不显示')),
          TextButton(key: const Key('lc-nav-unshare'), onPressed: () => _unshare(context), child: const Text('取消共用…')),
        ],
      ),
    );
  }
}

/// “以哪一页的为准”：各页的导航栏不一样时挑一页。
class _PickBaseSheet extends StatelessWidget {
  const _PickBaseSheet({required this.doc});
  final LcDocument doc;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    return SafeArea(
      child: ListView(
        key: const Key('lc-nav-share-pick'),
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: Space.x3),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.x4, Space.x2, Space.x4, Space.x1),
            child: Text('以哪一页的为准', style: t.titleMedium),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.x4, 0, Space.x4, Space.x2),
            child: Text('各页的导航栏不一样。挑一页：别的页的导航栏会被换成它（做错了可以撤销）。', style: t.bodySmall?.copyWith(color: c.textMuted)),
          ),
          for (final (p, n) in lcNavCandidates(doc))
            ListTile(
              key: Key('lc-nav-share-base-${p.id}'),
              leading: Icon(Icons.description_outlined, color: c.textMuted),
              title: Text(p.id == doc.page.id ? '${p.title}（就是这一页）' : p.title, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text([for (final m in lcObjects(n, 'items')) lcItemLabel(m, 'icon')].join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis),
              onTap: () => Navigator.pop(context, p.id),
            ),
        ],
      ),
    );
  }
}
