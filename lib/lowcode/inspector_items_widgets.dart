// 设计约束（低代码 · 合一面板“常用”页里的“选项 / 页签 / 导航项”那一块 · 390×844）
// - 谁用：单选组、下拉选择（选项）；标签页（页签）；底部导航栏（导航项）。规矩都在 items_edit.dart。
// - 一块从上到下：小标题一行（“选项 3/50”在左，右边一个“＋ 添加”文字按钮——这块唯一的“加”，满了变灰）；
//   下面一项一行；一行只做“改这一项”这一件事：
//     [选中圈] [图标（只有导航项有）] [名字输入框（最宽）] [值输入框（只有选项有，窄）] [上移] [下移] [删除]
//   选中圈＝“默认选中 / 当前页签 / 当前项”，点一下就换；选项再点一次＝不要默认选中。
//   上移 / 下移 / 删除是三个小图标按钮（32 宽），到头的、只剩一项的变灰。没有拖动排序：面板本身要上下滑，拖动会抢手势。
// - 值填得不对（空、和别的重复）：不写进页面，这一行下面出一句红字原因；改对了红字消失。
// - 删页签会连里面的组件一起删：里面有东西时先问一句（说清楚有几个）。别的删除不问（能撤销）。
// - 主次：名字是主角（正常字号、最宽）；值是次要的（窄、等宽感的小字）；三个小按钮用次要色。
// - 第 4 期·多页面（只有导航项有）：项目里有别的页面时，每一项下面多一行“点了去：〔页面名 ▾〕”——一行只管“去哪页”这一件事，
//   点开是一张单选的小单子（不跳转 / 各个页面）。指着的页面已经删掉的显示红字“已经删掉的页面”。
//   整块最下面是“共用”那一块（inspector_nav_shared_widgets.dart）：改成各页共用 / 这一页不显示 / 取消共用。
//   共用的导航栏上，选中圈只是给看（亮哪一项按“指着哪一页”自动算）。
//   只有一页的项目里这两样都不出现，只在最下面说一句“加了别的页面以后可以选去哪页”。
// - 取用的 tokens：Space.x1/x2/x3、accent（选中圈）、textMuted / textFaint（小按钮、小标题）、danger（红字）。
import 'package:lopicode/lowcode/editor_workbench_widgets.dart';
import 'package:lopicode/lowcode/icon_set_widgets.dart';
import 'package:lopicode/lowcode/inspector_common_widgets.dart';
import 'package:lopicode/lowcode/inspector_nav_shared_widgets.dart';
import 'package:lopicode/lowcode/inspector_v3_rows_widgets.dart';
import 'package:lopicode/lowcode/items_edit.dart';
import 'package:lopicode/lowcode/model.dart';
import 'package:lopicode/lowcode/model_v3_components.dart';
import 'package:lopicode/lowcode/nav_shared.dart';
import 'package:lopicode/lowcode/nav_sync.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:material_ui/material_ui.dart';

class LcItemsEditor extends StatefulWidget {
  const LcItemsEditor({super.key, required this.ed, required this.kind});
  final InspectorEdit ed;
  final LcItemsKind kind;

  @override
  State<LcItemsEditor> createState() => _LcItemsEditorState();
}

class _LcItemsEditorState extends State<LcItemsEditor> {
  /// 哪一行的值填得不对、为什么。
  final Map<int, String> _errors = {};

  InspectorEdit get ed => widget.ed;
  LcItemsKind get kind => widget.kind;

  void _change(void Function() clearAnd, void Function(LcNode n) f) {
    setState(clearAnd);
    ed.apply((n, _) => f(n));
  }

  Future<void> _remove(int index) async {
    // 数页签里有几个组件要看页面里真正的那个节点（面板手里的这份只是它自己，不带子节点）。
    final real = ed.doc.find(ed.node.id);
    final inside = kind == LcItemsKind.tabs && real != null ? lcTabChildCount(real, index) : 0;
    if (inside > 0) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('删掉这个页签？'),
          content: Text('里面的 $inside 个组件会一起删掉。删错了可以撤销。'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('不删')),
            FilledButton(key: const Key('lc-items-remove-ok'), onPressed: () => Navigator.pop(context, true), child: const Text('一起删掉')),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }
    _change(_errors.clear, (n) => lcItemRemove(n, kind, index));
  }

  void _setText(int index, String key, String text) {
    String? problem;
    ed.apply((n, _) => problem = lcItemSet(n, kind, index, key, text), merge: true);
    setState(() {
      if (problem == null) {
        _errors.remove(index);
      } else {
        _errors[index] = problem!;
      }
    });
  }

  Future<void> _pickIcon(int index, String? now) async {
    final picked = await showLcIconPicker(context, selected: now);
    if (picked == null || picked.isEmpty || !mounted) return; // 导航项必须有图标：选“不要”＝不改
    ed.apply((n, _) => lcItemSet(n, kind, index, 'icon', picked));
  }

  /// 选这一项点了去哪页。
  Future<void> _pickPage(int index, String? now) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      builder: (context) {
        final c = context.colors;
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.symmetric(vertical: Space.x3),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(Space.x4, Space.x2, Space.x4, Space.x2),
                child: Text('点了去哪页', style: Theme.of(context).textTheme.titleMedium),
              ),
              for (final p in ed.doc.pages)
                ListTile(
                  key: Key('lc-items-page-pick-${p.id}'),
                  leading: Icon(Icons.description_outlined, color: c.textMuted),
                  title: Text(p.id == ed.doc.page.id ? '${p.title}（就是这一页）' : p.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                  trailing: p.id == now ? Icon(Icons.check, color: c.accent) : null,
                  onTap: () => Navigator.pop(context, p.id),
                ),
              if (now != null)
                ListTile(
                  key: const Key('lc-items-page-pick-none'),
                  title: Text('不跳转', style: TextStyle(color: c.danger)),
                  onTap: () => Navigator.pop(context, ''),
                ),
            ],
          ),
        );
      },
    );
    if (picked == null || picked == (now ?? '') || !mounted) return;
    final edit = ed.editDoc;
    if (edit == null || !lcIsSharedNav(ed.node) || picked.isEmpty) {
      ed.apply((n, _) => lcItemSet(n, kind, index, 'page', picked));
      return;
    }
    // 共用的那一条：指着的页还没显示它就顺手加上（同一次修改里，撤销一次都回去）。
    var added = false;
    edit((d) {
      final n = d.find(ed.node.id);
      if (n == null) return;
      lcItemSet(n, kind, index, 'page', picked);
      added = lcSetPageShowsSharedNav(d, picked, true);
    });
    if (added && mounted) showEditorHint(context, '「${ed.doc.pageTitle(picked) ?? ''}」也显示这条导航了。');
  }

  /// “点了去”后面那几个字：没设是强调色的“选一页”，设了是页名，页面已经删掉是红字。
  Widget _pageLabel(String? pageId, TextStyle? style, AppColors c) {
    final title = pageId == null ? null : ed.doc.pageTitle(pageId);
    final (text, color) = pageId == null
        ? ('选一页', c.accent)
        : title == null
        ? ('已经删掉的页面', c.danger)
        : (title, c.text);
    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: style?.copyWith(color: color),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final node = ed.node;
    final pages = kind == LcItemsKind.nav && ed.doc.isMultiPage;
    final all = lcObjects(node, kind.prop);
    final shared = lcIsSharedNav(node);
    final canRemove = lcItemsCanRemove(node, kind);
    Widget small(String key, IconData icon, String label, VoidCallback? onTap) => SizedBox(
      width: 32,
      height: 40,
      child: IconButton(
        key: Key(key),
        padding: EdgeInsets.zero,
        iconSize: 18,
        color: c.textMuted,
        onPressed: onTap,
        icon: Icon(icon, semanticLabel: label),
      ),
    );
    return Padding(
      key: Key('lc-items-${kind.prop}'),
      padding: const EdgeInsets.symmetric(vertical: Space.x1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(kind.label, style: t.labelLarge?.copyWith(color: c.textMuted)),
              const SizedBox(width: Space.x2),
              Text('${all.length}/${kind.max}', style: t.labelSmall?.copyWith(color: c.textFaint)),
              const Spacer(),
              TextButton.icon(
                key: const Key('lc-items-add'),
                onPressed: lcItemsCanAdd(node, kind) ? () => _change(() {}, (n) => lcItemAdd(n, kind)) : null,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('添加'),
              ),
            ],
          ),
          for (var i = 0; i < all.length; i++) ...[
            if (i > 0) const SizedBox(height: Space.x2),
            Row(
              children: [
                SizedBox(
                  width: 32,
                  height: 40,
                  child: IconButton(
                    key: Key('lc-items-current-$i'),
                    padding: EdgeInsets.zero,
                    iconSize: 20,
                    // 共用的导航栏：亮哪一项是按“指着哪一页”自动算的，这里只是给看。
                    onPressed: shared ? null : () => ed.apply((n, _) => lcItemSetCurrent(n, kind, i)),
                    icon: lcItemIsCurrent(node, kind, i)
                        ? Icon(Icons.radio_button_checked, color: c.accent, semanticLabel: '现在选中的是这一项')
                        : Icon(Icons.radio_button_unchecked, color: c.textFaint, semanticLabel: '选中这一项'),
                  ),
                ),
                if (kind == LcItemsKind.nav) small('lc-items-icon-$i', lcIconData[all[i]['icon']] ?? Icons.help_outline, '换图标', () => _pickIcon(i, all[i]['icon'] as String?)),
                const SizedBox(width: Space.x1),
                Expanded(
                  child: _ItemField(
                    key: ValueKey('lc-items-field-label-$i'),
                    fieldKey: Key('lc-items-label-$i'),
                    text: (all[i]['label'] as String?) ?? '',
                    hint: '名字',
                    onChanged: (v) => _setText(i, 'label', v),
                  ),
                ),
                if (kind == LcItemsKind.options) ...[
                  const SizedBox(width: Space.x2),
                  SizedBox(
                    width: 72,
                    child: _ItemField(
                      key: ValueKey('lc-items-field-value-$i'),
                      fieldKey: Key('lc-items-value-$i'),
                      text: all[i]['value'] as String,
                      hint: '值',
                      small: true,
                      keepWhileWrong: _errors.containsKey(i),
                      onChanged: (v) => _setText(i, 'value', v),
                    ),
                  ),
                ],
                small('lc-items-up-$i', Icons.arrow_upward, '上移', i == 0 ? null : () => _change(_errors.clear, (n) => lcItemMove(n, kind, i, -1))),
                small('lc-items-down-$i', Icons.arrow_downward, '下移', i == all.length - 1 ? null : () => _change(_errors.clear, (n) => lcItemMove(n, kind, i, 1))),
                small('lc-items-remove-$i', Icons.delete_outline, '删除', canRemove ? () => _remove(i) : null),
              ],
            ),
            if (pages || (kind == LcItemsKind.nav && lcNavItemPage(all[i]) != null))
              Padding(
                padding: const EdgeInsets.only(left: 36),
                child: Row(
                  children: [
                    Text('点了去：', style: t.bodySmall?.copyWith(color: c.textMuted)),
                    Flexible(
                      child: TextButton(
                        key: Key('lc-items-page-$i'),
                        onPressed: () => _pickPage(i, lcNavItemPage(all[i])),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: Space.x2),
                          minimumSize: const Size(0, 36),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(child: _pageLabel(lcNavItemPage(all[i]), t.bodyMedium, c)),
                            Icon(Icons.arrow_drop_down, size: 18, color: c.textMuted),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            if (_errors[i] != null)
              Padding(
                padding: const EdgeInsets.only(left: 36, bottom: Space.x1),
                child: Text(
                  _errors[i]!,
                  key: Key('lc-items-error-$i'),
                  style: t.bodySmall?.copyWith(color: c.danger),
                ),
              ),
          ],
          if (pages) LcNavShareBlock(ed: ed),
          if (kind == LcItemsKind.nav && !ed.doc.isMultiPage)
            Padding(
              padding: const EdgeInsets.only(top: Space.x1),
              child: Text(
                '加了别的页面以后（右上角“页面”），这里可以给每一项选“点了去哪页”。',
                key: const Key('lc-items-page-hint'),
                style: t.bodySmall?.copyWith(color: c.textFaint),
              ),
            ),
          if (kind == LcItemsKind.options)
            Padding(
              padding: const EdgeInsets.only(top: Space.x1),
              child: Text('左边是给人看的名字，右边是程序里用的值（不能重复）。', style: t.bodySmall?.copyWith(color: c.textFaint)),
            ),
        ],
      ),
    );
  }
}

/// 一格输入框：外面的字变了（撤销、排序）跟着变；自己正在打的不被顶掉。
class _ItemField extends StatefulWidget {
  const _ItemField({super.key, required this.fieldKey, required this.text, required this.hint, required this.onChanged, this.small = false, this.keepWhileWrong = false});
  final Key fieldKey;
  final String text;
  final String hint;
  final bool small;

  /// 这一格现在填得不对（没写进页面）：别用页面里的旧值把她正在改的字顶掉。
  final bool keepWhileWrong;
  final ValueChanged<String> onChanged;

  @override
  State<_ItemField> createState() => _ItemFieldState();
}

class _ItemFieldState extends State<_ItemField> {
  late final TextEditingController _text = TextEditingController(text: widget.text);

  @override
  void didUpdateWidget(_ItemField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.keepWhileWrong && widget.text != _text.text) _text.text = widget.text;
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
    key: widget.fieldKey,
    controller: _text,
    style: widget.small ? Theme.of(context).textTheme.bodySmall : null,
    decoration: InputDecoration(isDense: true, hintText: widget.hint),
    onChanged: widget.onChanged,
  );
}
