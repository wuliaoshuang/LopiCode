// 设计约束（积木盒 · 底部抽屉，390 宽，浅色 + 深色）— 2026-11-24
// - 从上到下三行东西：手柄条（44 高：正中一条小把手，严格水平居中；左边、右边各可以放外面给的东西——
//   编辑器左边放“积木盒”名字（点一下收起 / 展开）和问题数量，右边放撤销、重做、缩放比例。左边那块最宽到把手左边 8 处，不压把手）；
//   一行分类（彩色圆点 + 名字，横着滑，选中的那个整颗填成它的颜色）；下面是这一类的积木。
// - 积木不是文字列表：每一样都用和画布上同一套画法画成真的积木外形（帽子 / 语句 / C 形 / 表达式），小块的并排，放不下换行。
// - 主操作就是“拿一块积木”：按住一块（约 0.18 秒）或直接横着拖，就把它拿出来了（回调交给外面的编辑器接着拖）；
//   上下滑还是翻这一页（这一页没满、翻不动时竖着滑也不会把积木拿出来）。点一下＝快捷添加（回调告诉外面点了哪一样）。
// - 手指一按上去，那块样品就微微缩一下（96%）、暗一点：告诉人“按到了，可以拿”。松手 / 拿走就弹回来。
// - 面板多高由外面说了算（[BlockPaletteView.height]，可以矮到只剩手柄条：里面的东西不挤扁，只是被裁掉）。
//   按住手柄条、或者分类那一行，上下拖＝改高度（只把手势报给外面）；分类那一行横着滑还是翻分类，积木那一片上下滑还是翻积木，互不抢。
//   点一下手柄条（按钮以外的地方）＝外面决定收起还是展开。收到只剩手柄条时，下面两行淡出、点不到。
//
// 第 4 版加的（2026-11-25；先定层级，再排版，最后上色）：
// - 层级：积木样品 ＞ 分类页签 ＞ 搜索入口 / 小标题。小标题、搜索框只用中性色，不用彩色，不抢积木的戏。
// - 分类那一行最左边固定一个放大镜（44 宽）；右边是横着滑的页签，第一个永远是“常用”（星形，中性色），后面是宿主的各页。
// - 点放大镜：这一行整行换成搜索框（一行只做一件事），下面换成搜到的积木；右边的 × 退出搜索。搜到的积木一样能点、能拖；
//   一拖出去键盘就收起（画布让出来），搜索的词和结果留着。
// - 一页里可以分小标题（12 号、次要色）。组和组之间隔 20，标题和它的积木隔 8，积木之间隔 12：组间距 ＞ 组内间距。
// - “常用”页：加了星的 + 这份文档里用得最多的 12 块；文档还空着时是入门积木。
// - 加星：按住一块样品不挪、直接松手（没有拖走）→ 样品旁边弹出一项“加到常用 / 从常用拿掉”。挪了就是拖，不弹。
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:lopicode/blocks/block_drag.dart';
import 'package:lopicode/blocks/block_geometry.dart';
import 'package:lopicode/blocks/block_host.dart';
import 'package:lopicode/blocks/block_palette_model.dart';
import 'package:lopicode/blocks/block_palette_parts_view.dart';
import 'package:lopicode/blocks/block_script_view.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:material_ui/material_ui.dart';

export 'package:lopicode/blocks/block_host.dart' show BlockPaletteKind;

/// 积木盒里的一样东西。
class BlockPaletteItem {
  const BlockPaletteItem(this.kind, this.id, this.layout, {this.preset = const {}});
  final BlockPaletteKind kind;

  /// 帽子模板的 id / 积木的 op / 表达式的 e。
  final String id;

  /// 拿出来时顺手设好的“固定选项”参数（搜到“一块顶多块”里的某一种时有，见 [BlockItemRef.preset]）。
  final Map<String, String> preset;

  /// 样品的排版（拖出来时可以直接拿它画拖着的样子）。
  final BkScriptLayout layout;

  BlockItemRef get ref => BlockItemRef(kind, id, preset: preset);
}

class BlockPaletteView extends StatefulWidget {
  const BlockPaletteView({
    super.key,
    required this.host,
    this.onPick,
    this.initialCategory,
    this.height = 300,
    this.stars,
    this.onNotice,
    this.onCustom,
    this.handleLeading,
    this.handleTrailing,
    this.onHandleTap,
    this.onResizeDown,
    this.onResizeStart,
    this.onResizeUpdate,
    this.onResizeEnd,
    this.onDragStart,
    this.onDragUpdate,
    this.onDragEnd,
    this.onDragCancel,
  });

  /// 手柄条的高度（也是面板收到最矮时露在外面的那一条）。
  static const double handleHeight = 44;

  /// 手柄条 + 分类那一行 + 分隔线：里面的东西至少按这么高排（面板比这矮时下面的被裁掉）。
  static const double headHeight = handleHeight + 48 + 1;

  final BlockHost host;

  /// 点了某一样。
  final void Function(BlockPaletteItem item)? onPick;

  /// 一开始停在哪一类（[BlockCategory.id]，“常用”是 [bkCommonCategoryId]）；不给就是第一类（“常用”）。
  final String? initialCategory;

  /// 加的星存在哪。不给＝只记在这个控件里（控件没了就没了）。
  final BlockStars? stars;

  /// 有话要告诉用户（“已加到常用”这种）：外面拿去显示成提示条。
  final void Function(String text)? onNotice;

  /// “我的积木”的操作：[BkCustomAction.create]（`id` 是空的）/ edit / define / remove。不给＝那一页没有“新建积木”，长按只有加星。
  final void Function(BkCustomAction action, String id)? onCustom;

  /// 面板现在多高（外面每一帧给；比 [headHeight] 矮时里面的东西被裁掉，不挤扁）。
  final double height;

  /// 把手多宽；左边那块离把手至少留多少。
  static const double gripWidth = 36;
  static const double gripGap = 8;

  /// 手柄条左边放的东西（编辑器放“积木盒”名字和问题数量）。最宽到把手左边 [gripGap] 处；里面没人接的点按算“点手柄”。
  final Widget? handleLeading;

  /// 手柄条右边放的东西（编辑器放撤销 / 重做 / 缩放）。
  final Widget? handleTrailing;

  /// 点了一下手柄条（按钮以外的地方）。
  final void Function()? onHandleTap;

  /// 手指刚按到手柄条或分类那一行上（还不知道是点还是拖）：面板正滑着的话先停住。
  final void Function()? onResizeDown;

  /// 按住手柄条或分类那一行上下拖：开始；手指又竖着动了多少（往下为正）；松手时的速度（每秒像素，往下为正）。
  final void Function()? onResizeStart;
  final void Function(double dy)? onResizeUpdate;
  final void Function(double velocity)? onResizeEnd;

  /// 把一样东西拿出来了：`global`＝手指在屏幕的哪里；`grab`＝手指离样品左上角多远。之后手指每动一下调 [onDragUpdate]，
  /// 松手调 [onDragEnd]，被系统打断调 [onDragCancel]。
  final void Function(BlockPaletteItem item, Offset global, Offset grab)? onDragStart;
  final void Function(Offset global)? onDragUpdate;
  final void Function()? onDragEnd;
  final void Function()? onDragCancel;

  @override
  State<BlockPaletteView> createState() => _BlockPaletteViewState();
}

class _BlockPaletteViewState extends State<BlockPaletteView> with BkKitHolder {
  late String? _category = widget.initialCategory;
  final Map<String, BlockPaletteItem> _items = {};
  int _rev = -1;
  late BlockStars _store = widget.stars ?? MemoryBlockStars();
  late List<String> _stars = bkCleanStars(_store.load());
  bool _searching = false;

  /// 页签条左边 / 右边还有没有滑出去的页签（有才画那一头的渐隐）。
  bool _tabsBefore = false, _tabsAfter = false;

  bool _tabsMoved(ScrollMetrics m) {
    if (m.axis != Axis.horizontal) return false;
    final before = m.pixels > 1, after = m.pixels < m.maxScrollExtent - 1;
    if (before != _tabsBefore || after != _tabsAfter) {
      // 可能正在排版当中（页签刚铺好就来报尺寸）：推后一帧再改。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() {
          _tabsBefore = before;
          _tabsAfter = after;
        });
      });
    }
    return false;
  }

  /// 按住样品以后手指挪过没有（样品每次重画都会换一批回调，所以记在这里，不记在回调里）。
  bool _moved = false;
  final TextEditingController _query = TextEditingController();
  final FocusNode _queryFocus = FocusNode();

  @override
  void kitChanged() => _items.clear();

  @override
  void didUpdateWidget(BlockPaletteView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.host, widget.host)) _items.clear();
    if (!identical(oldWidget.stars, widget.stars)) {
      _store = widget.stars ?? MemoryBlockStars(_stars);
      _stars = bkCleanStars(_store.load());
    }
  }

  @override
  void dispose() {
    _query.dispose();
    _queryFocus.dispose();
    super.dispose();
  }

  /// 一样东西的样品。宿主内容变了要重排（默认参数会跟着变：第一个变量、第一个控件…）。排不出来的（宿主已经没有这样东西）返回 null。
  BlockPaletteItem? _itemOf(BlockItemRef ref) {
    if (_rev != widget.host.revision) {
      _items.clear();
      _rev = widget.host.revision;
    }
    final key = bkItemKey(ref);
    final had = _items[key];
    if (had != null) return had;
    final host = widget.host;
    final engine = kit.engine(host);
    final BkScriptLayout layout;
    switch (ref.kind) {
      case BlockPaletteKind.hat:
        final t = bkHatTemplate(host, ref.id);
        if (t == null) return null;
        layout = engine.layoutHat(t.hat);
      case BlockPaletteKind.block:
        layout = engine.layoutStack([BkPaletteSource(BkDragKind.statement, ref.id, preset: ref.preset).newBlock(host)], controls: false);
      case BlockPaletteKind.expr:
        layout = engine.layoutExpr(BkPaletteSource(BkDragKind.expr, ref.id, preset: ref.preset).newExpr(host), controls: false);
    }
    return _items[key] = BlockPaletteItem(ref.kind, ref.id, layout, preset: ref.preset);
  }

  void _openSearch() {
    setState(() => _searching = true);
    _queryFocus.requestFocus();
  }

  void _closeSearch() {
    _queryFocus.unfocus();
    setState(() {
      _searching = false;
      _query.clear();
    });
  }

  void _toggleStar(BlockPaletteItem item) {
    final token = BlockItemRef(item.kind, item.id).token;
    final had = _stars.contains(token);
    final next = bkToggleStar(_stars, token);
    if (next == null) {
      widget.onNotice?.call('最多加 $bkStarMax 颗星，先拿掉几颗再加。');
      return;
    }
    setState(() => _stars = next);
    _store.save(next);
    widget.onNotice?.call(had ? '从“常用”里拿掉了。' : '加到“常用”了。');
  }

  bool _inPanel(Offset global) {
    final box = context.findRenderObject();
    return box is RenderBox && box.attached && (box.localToGlobal(Offset.zero) & box.size).contains(global);
  }

  /// 按住没挪就松手：在样品旁边问要不要加星。
  Future<void> _askStar(BuildContext box, BlockPaletteItem item) async {
    final starred = _stars.contains(BlockItemRef(item.kind, item.id).token);
    final mine = widget.onCustom != null && item.kind != BlockPaletteKind.hat && (widget.host.custom?.customs.any((c) => c.id == item.id) ?? false);
    final picked = await showBkStarMenu(box, starred: starred, custom: mine);
    if (!mounted || picked == null) return;
    if (picked == BkCustomAction.star) return _toggleStar(item);
    widget.onCustom?.call(picked, item.id);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = context.colors;
    final categories = [
      for (final c in bkAllCategories(widget.host))
        if (!c.isEmpty || c.id == bkCustomCategoryId) c,
    ];
    final ids = [if (categories.isNotEmpty) bkCommonCategoryId, for (final c in categories) c.id];
    final currentId = ids.isEmpty ? null : (ids.contains(_category) ? _category! : ids.first);
    final BlockCategory? current = currentId == null || currentId == bkCommonCategoryId ? null : categories.firstWhere((c) => c.id == currentId);
    final List<BkPaletteSection> sections;
    final String? pageId;
    if (_searching) {
      pageId = '@search';
      final found = bkSearchPalette(widget.host, _query.text);
      sections = [if (found.isNotEmpty) BkPaletteSection(null, found)];
    } else {
      pageId = currentId;
      sections = current != null ? bkCategorySections(current) : (currentId == null ? const [] : bkCommonSections(widget.host, _stars));
    }
    final mine = pageId == bkCustomCategoryId && widget.onCustom != null;
    final handleColor = theme.dividerColor;
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    // 收到只剩手柄条时，下面那两行淡出去（屏幕底部有系统手势条时不露半截分类）。
    final shown = ((widget.height - BlockPaletteView.handleHeight - safeBottom) / 40).clamp(0.0, 1.0);
    return Container(
      height: widget.height,
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        boxShadow: [BoxShadow(color: context.colors.shadowOf(kit.palette.dark ? 0.5 : 0.12), blurRadius: 16, offset: const Offset(0, -2))],
      ),
      child: Material(
        color: theme.colorScheme.surface,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
        clipBehavior: Clip.antiAlias,
        // 面板被拖矮时里面照原样排、下面的裁掉：不挤扁，也不报溢出。
        child: OverflowBox(
          alignment: Alignment.topCenter,
          minHeight: 0,
          maxHeight: widget.height < BlockPaletteView.headHeight ? BlockPaletteView.headHeight : widget.height,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _resizable(
                key: const ValueKey('bk-palette-handle'),
                onTap: widget.onHandleTap,
                child: SizedBox(
                  height: BlockPaletteView.handleHeight,
                  child: LayoutBuilder(
                    builder: (context, row) => Stack(
                      children: [
                        Center(
                          child: Container(
                            key: const ValueKey('bk-palette-grip'),
                            width: BlockPaletteView.gripWidth,
                            height: 4,
                            decoration: BoxDecoration(color: handleColor, borderRadius: BorderRadius.circular(2)),
                          ),
                        ),
                        if (widget.handleLeading != null)
                          Align(
                            alignment: Alignment.centerLeft,
                            child: ConstrainedBox(
                              constraints: BoxConstraints(maxWidth: math.max(0, row.maxWidth / 2 - BlockPaletteView.gripWidth / 2 - BlockPaletteView.gripGap)),
                              child: widget.handleLeading,
                            ),
                          ),
                        if (widget.handleTrailing != null)
                          // 按钮之间的缝、按不动的按钮：点到了不算“点手柄”。
                          Align(
                            alignment: Alignment.centerRight,
                            child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: () {}, child: widget.handleTrailing),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              Expanded(
                child: IgnorePointer(
                  ignoring: shown <= 0,
                  child: Opacity(
                    opacity: shown,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _resizable(
                          key: const ValueKey('bk-palette-tabs-grip'),
                          child: SizedBox(
                            height: 48,
                            child: _searching
                                ? BkPaletteSearchBar(controller: _query, focusNode: _queryFocus, onChanged: (_) => setState(() {}), onClose: _closeSearch)
                                : Row(
                                    children: [
                                      BkPaletteSearchButton(onTap: ids.isEmpty ? null : _openSearch),
                                      // 页签滑到放大镜底下时有一条细线接着，不像被一刀切掉。
                                      Container(width: 1, height: 20, color: context.colors.border),
                                      Expanded(
                                        child: Stack(
                                          children: [
                                            NotificationListener<ScrollMetricsNotification>(
                                              onNotification: (n) => _tabsMoved(n.metrics),
                                              child: NotificationListener<ScrollUpdateNotification>(
                                                onNotification: (n) => _tabsMoved(n.metrics),
                                                child: ListView.separated(
                                                  key: const ValueKey('bk-palette-tabs'),
                                                  scrollDirection: Axis.horizontal,
                                                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
                                                  itemCount: ids.length,
                                                  separatorBuilder: (_, _) => const SizedBox(width: 6),
                                                  itemBuilder: (_, i) => Builder(
                                                    builder: (at) => i == 0 ? _commonTab(currentId == bkCommonCategoryId, at) : _tab(categories[i - 1], categories[i - 1].id == currentId, at),
                                                  ),
                                                ),
                                              ),
                                            ),
                                            // 滑出去的页签在两头渐渐淡掉，不是被一刀切掉；没滑动时不盖住第一个 / 最后一个页签。
                                            BkPaletteTabsFade(left: true, shown: _tabsBefore, color: theme.colorScheme.surface),
                                            BkPaletteTabsFade(left: false, shown: _tabsAfter, color: theme.colorScheme.surface),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                          ),
                        ),
                        Divider(height: 1, color: theme.dividerColor),
                        Expanded(
                          child: pageId == null
                              ? const SizedBox.shrink()
                              : SingleChildScrollView(
                                  key: ValueKey('bk-palette-page-$pageId'),
                                  // 这一页没满也照样接竖着的滑动：不然竖着滑没人接，会落到样品的“横着拖”手里，把积木误拿出来。
                                  physics: const AlwaysScrollableScrollPhysics(),
                                  padding: EdgeInsets.fromLTRB(16, 14, 16, 20 + safeBottom),
                                  child: Align(
                                    alignment: Alignment.topLeft,
                                    child: sections.isEmpty && !mine
                                        ? (_searching ? BkPaletteSearchHint(query: _query.text) : const SizedBox.shrink())
                                        : Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              if (mine) BkPaletteCustomHead(empty: sections.isEmpty, onNew: () => widget.onCustom?.call(BkCustomAction.create, '')),
                                              for (final (i, s) in sections.indexed) ...[
                                                if (s.label != null) BkPaletteHeading(s.label!, first: i == 0 && !mine, color: c.textMuted) else if (i > 0 || mine) const SizedBox(height: 12),
                                                Wrap(
                                                  spacing: 12,
                                                  runSpacing: 12,
                                                  crossAxisAlignment: WrapCrossAlignment.start,
                                                  children: [
                                                    for (final ref in s.items)
                                                      if (_itemOf(ref) case final item?) _sample(item),
                                                  ],
                                                ),
                                              ],
                                            ],
                                          ),
                                  ),
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 按住上下拖＝改面板高度的那两行。只认竖着的拖：横着滑（翻分类）、点（选分类、点按钮）都不拦。
  Widget _resizable({required Key key, required Widget child, VoidCallback? onTap}) {
    if (widget.onResizeUpdate == null && onTap == null) return KeyedSubtree(key: key, child: child);
    return GestureDetector(
      key: key,
      behavior: HitTestBehavior.opaque,
      // 一认出是竖着拖，就把认出来之前走的那一小段也补上：面板上沿贴着手指，不落后一截。
      dragStartBehavior: DragStartBehavior.down,
      onTap: onTap,
      onVerticalDragDown: (_) => widget.onResizeDown?.call(),
      onVerticalDragStart: (_) => widget.onResizeStart?.call(),
      onVerticalDragUpdate: (d) => widget.onResizeUpdate?.call(d.primaryDelta ?? 0),
      onVerticalDragEnd: (d) => widget.onResizeEnd?.call(d.primaryVelocity ?? 0),
      onVerticalDragCancel: () => widget.onResizeEnd?.call(0),
      child: child,
    );
  }

  /// 点一个页签：切过去，并把它整个滑进来（点的是露了一半的页签时，不让它继续被边上的渐隐盖着）。
  void _pickTab(String id, BuildContext at) {
    setState(() => _category = id);
    // 只在它有一部分在外面、或者被两头的渐隐盖着时才动，而且只动到刚好露全：看得全的页签点了不滑（不打乱她手上的位置）。
    final box = at.findRenderObject(), pos = Scrollable.maybeOf(at)?.position;
    final port = Scrollable.maybeOf(at)?.context.findRenderObject();
    if (box is! RenderBox || port is! RenderBox || pos == null || !box.hasSize) return;
    final left = box.localToGlobal(Offset.zero, ancestor: port).dx, right = left + box.size.width;
    final lo = BkPaletteTabsFade.widthOf(left: true);
    final hi = port.size.width - BkPaletteTabsFade.widthOf(left: false);
    final by = left < lo ? left - lo : (right > hi ? right - hi : 0.0);
    final to = (pos.pixels + by).clamp(pos.minScrollExtent, pos.maxScrollExtent).toDouble();
    if (to != pos.pixels) unawaited(pos.animateTo(to, duration: const Duration(milliseconds: 160), curve: Curves.easeOut));
  }

  /// “常用”页签：星形 + 中性色（不占任何一种积木的颜色）。
  Widget _commonTab(bool selected, BuildContext at) {
    final c = context.colors;
    final fg = selected ? c.surface : c.text;
    return GestureDetector(
      key: const ValueKey('bk-palette-tab-$bkCommonCategoryId'),
      behavior: HitTestBehavior.opaque,
      onTap: () => _pickTab(bkCommonCategoryId, at),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.only(left: 10, right: 12),
        decoration: BoxDecoration(color: selected ? c.text : Colors.transparent, borderRadius: BorderRadius.circular(20)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.star_rounded, size: 16, color: selected ? c.surface : c.textMuted),
            const SizedBox(width: 4),
            Text(
              '常用',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600, color: fg),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tab(BlockCategory c, bool selected, BuildContext at) {
    final tone = kit.palette.tone(c.colorKey);
    final theme = Theme.of(context);
    return GestureDetector(
      key: ValueKey('bk-palette-tab-${c.id}'),
      behavior: HitTestBehavior.opaque,
      onTap: () => _pickTab(c.id, at),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(color: selected ? tone.fill : Colors.transparent, borderRadius: BorderRadius.circular(20)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: selected ? tone.text : tone.fill, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Text(
              c.label,
              style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600, color: selected ? tone.text : theme.textTheme.bodyMedium?.color),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sample(BlockPaletteItem item) {
    final view = BkLayoutView(layout: item.layout, kit: kit);
    void start(Offset global, Offset local, double boxHeight) {
      _moved = false;
      // 从搜索结果里往外拖：键盘收起来，画布让出来；搜的词和结果留着。
      _queryFocus.unfocus();
      // 样品在 40 高的触控范围里是竖着居中的。
      final dy = (boxHeight - item.layout.size.height) / 2;
      widget.onDragStart?.call(item, global, local - Offset(0, dy > 0 ? dy : 0));
    }

    return Builder(
      builder: (box) => RawGestureDetector(
        key: ValueKey('bk-palette-item-${bkItemKey(item.ref)}'),
        behavior: HitTestBehavior.opaque,
        gestures: {
          TapGestureRecognizer: GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(TapGestureRecognizer.new, (r) => r.onTap = widget.onPick == null ? null : () => widget.onPick!(item)),
          if (widget.onDragStart != null) ...{
            LongPressGestureRecognizer: GestureRecognizerFactoryWithHandlers<LongPressGestureRecognizer>(() => LongPressGestureRecognizer(duration: const Duration(milliseconds: 180)), (r) {
              r.onLongPressStart = (d) => start(d.globalPosition, d.localPosition, box.size?.height ?? 0);
              r.onLongPressMoveUpdate = (d) {
                if (d.offsetFromOrigin.distance > 8) _moved = true;
                widget.onDragUpdate?.call(d.globalPosition);
              };
              r.onLongPressEnd = (d) {
                // 按住了却一点没挪、松手时手指还在积木盒上：不是要拖，是要加星。
                // （面板比默认档高时一拿起积木面板就自己让开，手指底下可能已经是画布了：那是在放积木。）
                if (_moved || !_inPanel(d.globalPosition)) return widget.onDragEnd?.call();
                widget.onDragCancel?.call();
                unawaited(_askStar(box, item));
              };
              r.onLongPressCancel = () => widget.onDragCancel?.call();
            }),
            HorizontalDragGestureRecognizer: GestureRecognizerFactoryWithHandlers<HorizontalDragGestureRecognizer>(HorizontalDragGestureRecognizer.new, (r) {
              r.onStart = (d) => start(d.globalPosition, d.localPosition, box.size?.height ?? 0);
              r.onUpdate = (d) => widget.onDragUpdate?.call(d.globalPosition);
              r.onEnd = (_) => widget.onDragEnd?.call();
              r.onCancel = () => widget.onDragCancel?.call();
            }),
          },
        },
        // 小的表达式块也要有 40 高的触控范围。
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 40),
          child: Align(
            alignment: Alignment.centerLeft,
            widthFactor: 1,
            heightFactor: 1,
            child: BkPressFeel(child: view),
          ),
        ),
      ),
    );
  }
}
