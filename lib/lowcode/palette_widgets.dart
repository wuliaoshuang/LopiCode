// 设计约束（低代码 · 组件盒 · 390×844）
// - 一块贴着底部工具条上沿的面板，点工具条的“添加”打开。三档高矮：收起（只剩 28 高的手柄条）/ 默认（304）/ 顶到悬浮顶栏下沿；
//   按住手柄上下拖能改高矮，点一下手柄在收起和默认之间切。（三档怎么停借用积木盒的规矩 BkDockStops。）
// - 从上到下一行只做一件事：手柄 → 搜索框 → 分类（横着滑：常用 / 布局 / 基础 / 表单 / 展示 / 我的）→ 组件格子（一行 4 个，图标＋名字，72 高）。
//   搜索时分类那一行换成“找到 N 个”，格子里是搜到的；搜不到写明没有。
// - 点一个格子＝加进页面（加完面板收到最矮，画布滚到它那里）；长按 280 毫秒＝拿起来拖（面板同样收到最矮，把画布让出来）。
// - 自定义组件在“我的”里，图标统一用“组件”图标、名字用强调色。
// - 面板收起时里面的格子不销毁（只是被裁掉）：手指从格子上拿起东西以后面板才收，格子没了手势就断了。
import 'package:lopicode/blocks/block_dock.dart';
import 'package:lopicode/lowcode/lift_gesture_widgets.dart';
import 'package:lopicode/lowcode/palette_catalog.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:material_ui/material_ui.dart';

/// 拖动中携带的东西：新组件的类型，或画布上已有组件的 id。
class LcDrag {
  const LcDrag.fresh(String this.type) : nodeId = null, ref = null;
  const LcDrag.move(String this.nodeId) : type = null, ref = null;

  /// 一个自定义组件的新实例。
  const LcDrag.component(String this.ref) : type = 'component', nodeId = null;
  final String? type;
  final String? nodeId;

  /// 自定义组件的 id（只有新实例有）。
  final String? ref;
}

IconData lcIcon(String type) => switch (type) {
  'page' => Icons.phone_android,
  'container' => Icons.crop_square,
  'row' => Icons.view_column_outlined,
  'column' => Icons.table_rows_outlined,
  'card' => Icons.featured_play_list_outlined,
  'text' => Icons.title,
  'button' => Icons.smart_button_outlined,
  'image' => Icons.image_outlined,
  'input' => Icons.text_fields,
  'list' => Icons.format_list_bulleted,
  'divider' => Icons.horizontal_rule,
  'spacer' => Icons.expand,
  'icon' => Icons.star_outline,
  'textarea' => Icons.notes,
  'switch' => Icons.toggle_on_outlined,
  'checkbox' => Icons.check_box_outlined,
  'radio' => Icons.radio_button_checked,
  'select' => Icons.arrow_drop_down_circle_outlined,
  'listItem' => Icons.view_list_outlined,
  'appBar' => Icons.web_asset,
  'bottomNav' => Icons.video_label,
  'tabs' => Icons.tab,
  'dialog' => Icons.chat_bubble_outline,
  // 内置组件库里进组件盒的那几个（comp_lib_builtin.dart）和滑块。
  'iconButton' => Icons.add_circle_outline,
  'link' => Icons.link,
  'grid' => Icons.grid_view,
  'scroll' => Icons.swap_vert,
  'stepper' => Icons.exposure,
  'formItem' => Icons.short_text,
  'slider' => Icons.linear_scale,
  _ => Icons.widgets_outlined,
};

/// 组件盒手柄条多高（面板收到最矮时只剩它）。
const double kPaletteHandleHeight = 28;

/// 组件盒默认多高。
const double kPaletteNormalHeight = 304;

/// 一类里有 [count] 个条目时，默认那一档多高：两行以内就是 [kPaletteNormalHeight]（两行半，露半行表示下面还有）；
/// 三行、四行的把这几行整个露出来（第四轮 B6：“表单”有 9 个，第 9 个原来只露一条边）；再多的露四行，其余往下滑。
double paletteNormalHeight(int count) {
  final rows = (count / 4).ceil();
  if (rows <= 2) return kPaletteNormalHeight;
  final shownRows = rows > 4 ? 4 : rows;
  // 手柄 28 ＋ 搜索 48 ＋ 分类 36 ＋ 格子上边距 4 ＋ 行（72 一行、行间 8）＋ 下边距 12
  return kPaletteHandleHeight + 48 + 36 + Space.x1 + shownRows * 72 + (shownRows - 1) * Space.x2 + Space.x3;
}

class PalettePanel extends StatefulWidget {
  const PalettePanel({
    super.key,
    required this.entries,
    required this.recent,
    required this.maxHeight,
    required this.onTap,
    required this.onLift,
    required this.onLiftMove,
    required this.onLiftDrop,
    required this.onLiftCancel,
    required this.onClose,
  });

  /// 全部能加的组件（内置＋自定义）。
  final List<PaletteEntry> entries;

  /// 最近用过的（条目的 key，新的在前）。
  final List<String> recent;

  /// 最高能到多高（画布底边到悬浮顶栏下沿）。
  final double maxHeight;

  /// 点了一个格子。
  final void Function(PaletteEntry entry) onTap;

  /// 长按一个格子拿起来了 / 手指在动 / 松手 / 被打断（位置是屏幕坐标）。
  final void Function(PaletteEntry entry, Offset global) onLift;
  final void Function(Offset global) onLiftMove;
  final VoidCallback onLiftDrop;
  final VoidCallback onLiftCancel;

  /// 点了右上角的“收起”（整块面板关掉）。
  final VoidCallback onClose;

  @override
  State<PalettePanel> createState() => PalettePanelState();
}

class PalettePanelState extends State<PalettePanel> {
  final TextEditingController _query = TextEditingController();
  final FocusNode _focus = FocusNode();
  PaletteGroup _group = PaletteGroup.recent;
  double _height = kPaletteNormalHeight;
  bool _dragging = false;

  BkDockStops get _stops => BkDockStops.of(handle: kPaletteHandleHeight, normal: paletteNormalHeight(_shownGroup.$2.length), area: widget.maxHeight);

  /// 现在看的是哪一类、这一类里有哪些（不算搜索）。
  (PaletteGroup, List<PaletteEntry>) get _shownGroup {
    final group = paletteGroups(widget.entries).contains(_group) ? _group : PaletteGroup.recent;
    return (group, paletteInGroup(widget.entries, group, widget.recent));
  }

  /// 换一类看。面板正停在默认那一档时跟着新的一类调高矮（这一类有三四行就高一点，一眼看全）；她自己拖过的不动。
  void _pick(PaletteGroup g) => setState(() {
    final atNormal = (height - _stops.normal).abs() < 0.5;
    _group = g;
    if (atNormal) _height = _stops.normal;
  });

  /// 现在多高（测试用）。
  double get height => _stops.clamp(_height);
  bool get collapsed => _stops.isCollapsed(height);

  /// 收到最矮（只剩手柄），键盘也收起。
  void collapse() {
    _focus.unfocus();
    if (!collapsed) setState(() => _height = _stops.collapsed);
  }

  /// 回到默认高度。
  void expand() {
    if (collapsed) setState(() => _height = _stops.normal);
  }

  @override
  void dispose() {
    _query.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final stops = _stops;
    final height = stops.clamp(_height);
    final query = _query.text.trim();
    final groups = paletteGroups(widget.entries);
    final (group, inGroup) = _shownGroup;
    final shown = query.isEmpty ? inGroup : paletteSearch(widget.entries, query);
    // 里面的内容按“至少默认那么高”排好，外面只是裁掉露不出来的部分：收起时格子还在（见文件开头）。
    final contentHeight = height < stops.normal ? stops.normal : height;
    return AnimatedContainer(
      key: const ValueKey('palette-panel'),
      duration: _dragging ? Duration.zero : const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      height: height,
      clipBehavior: Clip.hardEdge,
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(Radii.md)),
        border: Border(top: BorderSide(color: c.border)),
        boxShadow: [BoxShadow(color: c.shadowOf(0x1F / 255), blurRadius: 12, offset: const Offset(0, -2))],
      ),
      child: OverflowBox(
        alignment: Alignment.topCenter,
        minHeight: contentHeight,
        maxHeight: contentHeight,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 手柄：上下拖改高矮，点一下收起 / 展开
            Semantics(
              button: true,
              label: collapsed ? '展开组件盒' : '收起组件盒',
              child: GestureDetector(
                key: const ValueKey('palette-handle'),
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() {
                  _focus.unfocus();
                  _height = stops.toggled(height);
                }),
                onVerticalDragStart: (_) => setState(() => _dragging = true),
                onVerticalDragUpdate: (d) => setState(() => _height = stops.clamp(height - d.delta.dy)),
                onVerticalDragEnd: (d) => setState(() {
                  _dragging = false;
                  _height = stops.rest(height, d.primaryVelocity ?? 0);
                }),
                onVerticalDragCancel: () => setState(() => _dragging = false),
                child: SizedBox(
                  height: kPaletteHandleHeight,
                  child: Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(color: c.border, borderRadius: BorderRadius.circular(2)),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.x3, 0, Space.x1, Space.x2),
              child: Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 40,
                      child: TextField(
                        key: const ValueKey('palette-search'),
                        controller: _query,
                        focusNode: _focus,
                        onChanged: (_) => setState(() {}),
                        textInputAction: TextInputAction.search,
                        style: t.bodyMedium,
                        decoration: InputDecoration(
                          hintText: '搜索组件（名字、别名都行）',
                          prefixIcon: const Icon(Icons.search, size: 20),
                          suffixIcon: query.isEmpty ? null : IconButton(tooltip: '清空', icon: const Icon(Icons.close, size: 18), onPressed: () => setState(_query.clear)),
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ),
                  ),
                  IconButton(tooltip: '关闭组件盒', icon: const Icon(Icons.keyboard_arrow_down), onPressed: widget.onClose),
                ],
              ),
            ),
            SizedBox(
              height: 36,
              child: query.isNotEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(horizontal: Space.x4),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(shown.isEmpty ? '没有名字或别名里带“$query”的组件' : '找到 ${shown.length} 个', style: t.bodySmall?.copyWith(color: c.textMuted)),
                      ),
                    )
                  : ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: Space.x3),
                      itemCount: groups.length,
                      separatorBuilder: (_, _) => const SizedBox(width: Space.x1),
                      itemBuilder: (context, i) {
                        final g = groups[i], on = g == group;
                        return Center(
                          child: Material(
                            color: on ? c.accentSoft : Colors.transparent,
                            borderRadius: BorderRadius.circular(16),
                            child: InkWell(
                              key: ValueKey('palette-group-${g.name}'),
                              borderRadius: BorderRadius.circular(16),
                              onTap: () => _pick(g),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                child: Text(
                                  g.label,
                                  style: t.labelLarge?.copyWith(color: on ? c.accent : c.textMuted, fontWeight: on ? FontWeight.w600 : FontWeight.w400),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
            Expanded(
              child: shown.isEmpty && query.isEmpty
                  ? Center(
                      child: Text(group == PaletteGroup.mine ? '还没有自定义组件' : '这一类还没有组件', style: t.bodySmall?.copyWith(color: c.textFaint)),
                    )
                  : query.isEmpty && shown.any((e) => e.lib != null)
                  ? _byLib(context, shown)
                  : GridView.builder(
                      key: const ValueKey('palette-grid'),
                      padding: const EdgeInsets.fromLTRB(Space.x3, Space.x1, Space.x3, Space.x3),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 4, mainAxisExtent: 72, crossAxisSpacing: Space.x2, mainAxisSpacing: Space.x2),
                      itemCount: shown.length,
                      itemBuilder: (context, i) => _cell(context, shown[i]),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  /// “我的”里有组件库的时候：项目自己的一组，然后一个库一组（组名＝库的名字）。
  Widget _byLib(BuildContext context, List<PaletteEntry> shown) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final groups = <String?, List<PaletteEntry>>{};
    for (final e in shown) {
      groups.putIfAbsent(e.lib, () => []).add(e);
    }
    const grid = SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 4, mainAxisExtent: 72, crossAxisSpacing: Space.x2, mainAxisSpacing: Space.x2);
    return CustomScrollView(
      key: const ValueKey('palette-grid'),
      slivers: [
        for (final g in groups.entries) ...[
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(Space.x3, Space.x2, Space.x3, Space.x1),
            sliver: SliverToBoxAdapter(
              child: Text(
                g.key == null ? '项目里的' : '库 · ${g.key}',
                key: ValueKey('palette-lib-${g.key ?? ''}'),
                style: t.labelMedium?.copyWith(color: c.textMuted),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(Space.x3, 0, Space.x3, Space.x2),
            sliver: SliverGrid(
              gridDelegate: grid,
              delegate: SliverChildBuilderDelegate((context, i) => _cell(context, g.value[i]), childCount: g.value.length),
            ),
          ),
        ],
      ],
    );
  }

  Widget _cell(BuildContext context, PaletteEntry e) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final mine = e.ref != null && e.builtin == null;
    return LcLiftDetector(
      key: ValueKey('palette-item-${e.key}'),
      onLift: (at) => widget.onLift(e, at),
      onMove: widget.onLiftMove,
      onDrop: widget.onLiftDrop,
      onCancel: widget.onLiftCancel,
      child: Material(
        color: c.surfaceMuted,
        borderRadius: BorderRadius.circular(Radii.md),
        child: InkWell(
          borderRadius: BorderRadius.circular(Radii.md),
          onTap: () => widget.onTap(e),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.x1),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(lcIcon(e.icon), size: 22, color: mine ? c.accent : c.text),
                const SizedBox(height: 6),
                Text(
                  e.label,
                  style: t.labelMedium?.copyWith(color: mine ? c.accent : c.text),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
