// 设计约束（样式编辑面板；390×844，浅色 + 深色）
// - 可拖高的底部面板：默认约 60% 高、可拉到 92%，画布露在上面；每次提交都交给搭建页，画布跟着变。
// - 顶部固定两行：① 组件名 + 右边“CSS”“重置”两个次要操作；② 一行可横向滚动的分组标签（有改动的带小圆点）。
// - 下面一次只显示一个分组，每行只做一件事（标签在左、控件在右）；不常用的在分组里的“更多”。
// - 最后是“自定义 CSS”小节：面板不认识的条目，每条可删。有才显示。
// - 没有“保存”按钮：改了就生效，靠搭建页的撤销反悔。
// - 撤销记录的合并：打字、点加减、拖滑块算连续操作，停 400ms（或松手 / 关面板 / 做了别的操作）才提交一次；
//   按钮组、开关、换单位、清除、取色、应用 CSS、重置是一下一条。
import 'dart:async';

import 'package:lopicode/lowcode/edit_types.dart';
import 'package:lopicode/lowcode/model.dart';
import 'package:lopicode/lowcode/style_controls_widgets.dart';
import 'package:lopicode/lowcode/style_css_sheet.dart';
import 'package:lopicode/lowcode/style_groups_widgets.dart';
import 'package:lopicode/lowcode/style_model.dart';
import 'package:lopicode/lowcode/style_resolve.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/widgets.dart';
import 'package:material_ui/material_ui.dart';

/// 连续操作（打字、加减、拖动）停多久算“告一段落”、提交成一条撤销记录。
const Duration kStyleCommitDelay = Duration(milliseconds: 400);

/// 打开某个节点的样式编辑面板。改动都通过 [onEdit] 交回搭建页。
Future<void> showStyleEditor(BuildContext context, {required LcDocument doc, required String nodeId, required LcEdit onEdit}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  // 遮罩要淡：用户是看着上面的画布调样式的。
  barrierColor: const Color(0x14000000),
  builder: (_) => _StyleEditorSheet(doc: doc, nodeId: nodeId, onEdit: onEdit),
);

class _StyleEditorSheet extends StatefulWidget {
  const _StyleEditorSheet({required this.doc, required this.nodeId, required this.onEdit});
  final LcDocument doc;
  final String nodeId;
  final LcEdit onEdit;

  @override
  State<_StyleEditorSheet> createState() => _StyleEditorSheetState();
}

class _StyleEditorSheetState extends State<_StyleEditorSheet> {
  /// 最近一次见到的文档：打开时是传进来的那份，之后每次提交换成搭建页在回调里给的那份
  /// （撤销 / 重做之后搭建页手里的文档对象可能已经换了）。
  late LcDocument _doc = widget.doc;

  /// 面板显示用的 style：节点自己的 style 加上还没提交的改动。
  Map<String, String> _draft = {};

  /// 还没提交的改动。提交时在搭建页给的节点上按顺序重放一遍，而不是拿 [_draft] 整个盖过去——
  /// 这样即使节点的 style 在别处变过，也只动用户碰过的那几条。
  final List<void Function(LcStyle s)> _pending = [];
  Timer? _timer;
  final DraggableScrollableController _sheet = DraggableScrollableController();
  bool _keyboardUp = false;

  /// 面板给的滚动控制器（换分组时回到顶上用）。
  ScrollController? _scroll;
  StyleTab _tab = StyleTab.size;

  /// 上次“应用 CSS”时没收下的条目。
  List<String> _dropped = const [];

  LcNode? get _node => _doc.find(widget.nodeId);

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    // 正常关闭走 PopScope，那里已经提交过了；这里只收定时器（销毁过程中不能再去动搭建页）。
    _timer?.cancel();
    _sheet.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 键盘一弹出就把面板拉到最高：默认 60% 高时键盘会盖掉大半，剩下的地方连被编辑的那一行都放不下。
    final up = MediaQuery.viewInsetsOf(context).bottom > 0;
    if (up && !_keyboardUp) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _sheet.isAttached && _sheet.size < _maxSize) unawaited(_sheet.animateTo(_maxSize, duration: const Duration(milliseconds: 180), curve: Curves.easeOut));
      });
    }
    _keyboardUp = up;
  }

  static const double _maxSize = 0.92;

  void _reload() {
    final n = _node;
    _draft = n == null ? {} : Map.of(n.style);
  }

  void _apply(void Function(LcStyle s) change, {bool merge = false}) {
    if (_node == null) {
      // 组件已经不在了（被删 / 被撤销）：不改，重画成“不在了”。
      setState(() {});
      return;
    }
    setState(() {
      change(LcStyle(_draft));
      _pending.add(change);
    });
    _timer?.cancel();
    if (merge) {
      _timer = Timer(kStyleCommitDelay, _flush);
    } else {
      _flush();
    }
  }

  /// 把攒着的改动一次交给搭建页（一条撤销记录），然后按搭建页手里的文档重新读显示值。
  void _flush() {
    _timer?.cancel();
    _timer = null;
    if (_pending.isEmpty) return;
    final ops = List.of(_pending);
    _pending.clear();
    widget.onEdit((d) {
      _doc = d;
      final n = d.find(widget.nodeId);
      if (n == null) return;
      final s = LcStyle(n.style);
      for (final op in ops) {
        op(s);
      }
    });
    if (mounted) setState(_reload);
  }

  Future<void> _openCss(LcNode node) async {
    _flush();
    final css = await showStyleCssEditor(context, initialCss: LcStyle(_draft).toCss(), legacy: legacyStyle(node, _doc.parentOf(node.id)));
    if (css == null || !mounted) return;
    final parsed = parseStyleInput(css);
    _apply(
      (s) => s.map
        ..clear()
        ..addAll(parsed.declarations),
    );
    setState(() => _dropped = parsed.dropped);
  }

  Future<void> _reset() async {
    final ok = await confirmDialog(context, title: '重置样式？', message: '会清掉这个组件在样式面板里设的全部内容（包括自定义 CSS）。“属性”里设的不受影响。清掉之后可以撤销。', confirmLabel: '重置', danger: true);
    if (!ok || !mounted) return;
    _apply((s) => s.map.clear());
    setState(() => _dropped = const []);
  }

  @override
  Widget build(BuildContext context) {
    final node = _node;
    return PopScope(
      // 面板怎么关的都算（下滑、点外面、返回键）：关之前把没提交的交出去。
      onPopInvokedWithResult: (_, _) => _flush(),
      // 键盘的高度垫在面板外面：滚动区到键盘上沿为止，被编辑的那一行才会被滚到看得见的地方。
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: DraggableScrollableSheet(
          controller: _sheet,
          expand: false,
          initialChildSize: 0.6,
          minChildSize: 0.35,
          maxChildSize: _maxSize,
          builder: (context, scroll) => node == null ? _gone(context, scroll) : _body(context, scroll, node),
        ),
      ),
    );
  }

  Widget _gone(BuildContext context, ScrollController scroll) => SingleChildScrollView(
    controller: scroll,
    child: SizedBox(
      height: 280,
      child: EmptyState(
        icon: Icons.layers_clear_outlined,
        title: '这个组件已经不在了',
        message: '它被删掉或者被撤销掉了，没有可以改的样式。',
        action: FilledButton(key: const Key('lc-style-close'), onPressed: () => Navigator.pop(context), child: const Text('关闭')),
      ),
    ),
  );

  Widget _body(BuildContext context, ScrollController scroll, LcNode node) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    // 用“节点 + 预览中的 style”算最终样式：面板显示的和提交后画布上的是同一套规矩。
    final preview = LcNode(id: node.id, type: node.type, props: node.props, style: _draft);
    final ed = StyleEdit(node: node, own: _draft, resolved: resolvedStyle(preview, _doc.parentOf(node.id)), apply: _apply);
    _scroll = scroll;
    final custom = LcStyle(_draft).custom;
    final mono = t.bodySmall?.copyWith(fontFamily: kMonoFont, fontFamilyFallback: kMonoFallback, color: c.text);
    return CustomScrollView(
      controller: scroll,
      slivers: [
        PinnedHeaderSliver(child: _header(context, node)),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(Space.x4, Space.x2, Space.x4, Space.x6),
          // 不用懒加载的列表：内容就这么几行，一次排好，滚动位置和“滚到被编辑的那一行”都更稳。
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_dropped.isNotEmpty) ...[
                  Stack(
                    children: [
                      InfoBanner(key: const Key('lc-style-dropped'), droppedText(_dropped), tone: BannerTone.warning),
                      Positioned(
                        right: 0,
                        top: 0,
                        child: StyleIconButton(key: const Key('lc-style-dropped-close'), icon: Icons.close, semantic: '知道了', onTap: () => setState(() => _dropped = const [])),
                      ),
                    ],
                  ),
                  const SizedBox(height: Space.x2),
                ],
                KeyedSubtree(key: ValueKey(_tab), child: styleTabBody(_tab, ed)),
                if (custom.isNotEmpty) ...[
                  const SizedBox(height: Space.x4),
                  Divider(height: 1, color: c.border),
                  const SizedBox(height: Space.x4),
                  Text('自定义 CSS', style: t.labelMedium),
                  const SizedBox(height: Space.x1),
                  Text('面板不认识的条目，原样留着、照样导出。要改点右上角“CSS”。', style: t.bodySmall?.copyWith(color: c.textFaint)),
                  for (final e in custom.entries)
                    ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 44),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text('${e.key}: ${e.value}', key: Key('lc-custom-${e.key}'), style: mono, maxLines: 2, overflow: TextOverflow.ellipsis),
                          ),
                          StyleIconButton(key: Key('lc-custom-del-${e.key}'), icon: Icons.delete_outline, semantic: '删除', onTap: () => _apply((s) => s.set(e.key, null))),
                        ],
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// 换分组：内容从头看起（上一组滚到哪儿和这一组没关系）。
  void _selectTab(StyleTab tab) {
    final scroll = _scroll;
    if (scroll != null && scroll.hasClients && scroll.offset > 0) scroll.jumpTo(0);
    setState(() => _tab = tab);
  }

  Widget _header(BuildContext context, LcNode node) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final quiet = TextButton.styleFrom(
      foregroundColor: c.textMuted,
      minimumSize: const Size(48, 40),
      padding: const EdgeInsets.symmetric(horizontal: Space.x3),
    );
    return ColoredBox(
      color: c.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: Space.x4, right: Space.x2),
            child: Row(
              children: [
                Expanded(
                  child: Text('${node.spec.label} 样式', style: t.titleLarge, maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
                TextButton(
                  key: const Key('lc-style-css'),
                  onPressed: () => _openCss(node),
                  style: TextButton.styleFrom(
                    minimumSize: const Size(48, 40),
                    padding: const EdgeInsets.symmetric(horizontal: Space.x3),
                  ),
                  child: const Text('CSS'),
                ),
                TextButton(key: const Key('lc-style-reset'), onPressed: _draft.isEmpty ? null : _reset, style: quiet, child: const Text('重置')),
              ],
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: Space.x3, vertical: Space.x1),
            child: Row(children: [for (final tab in StyleTab.values) _tabChip(context, tab)]),
          ),
          Divider(height: 1, color: c.border),
        ],
      ),
    );
  }

  Widget _tabChip(BuildContext context, StyleTab tab) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final on = tab == _tab;
    return Padding(
      padding: const EdgeInsets.only(right: Space.x1),
      child: Material(
        color: on ? c.accentSoft : Colors.transparent,
        borderRadius: BorderRadius.circular(Radii.bubble),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: Key('lc-tab-${tab.name}'),
          onTap: () => _selectTab(tab),
          child: Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: Space.x3),
            alignment: Alignment.center,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  tab.label,
                  style: t.bodyMedium?.copyWith(color: on ? c.accent : c.textMuted, fontWeight: on ? FontWeight.w600 : FontWeight.w400, height: 1.2),
                ),
                if (tab.touched(_draft)) ...[
                  const SizedBox(width: Space.x1),
                  Container(
                    key: Key('lc-tab-dot-${tab.name}'),
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(color: c.accentFill, shape: BoxShape.circle),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
