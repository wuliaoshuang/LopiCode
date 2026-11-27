part of 'canvas_v3_widgets.dart';

/// 画布上的标签页。现在看哪一页记在这里（不写进页面文件）。
class CanvasTabs extends StatefulWidget {
  const CanvasTabs({super.key, required this.args});
  final CanvasV3 args;

  @override
  State<CanvasTabs> createState() => _CanvasTabsState();
}

class _CanvasTabsState extends State<CanvasTabs> {
  /// 手点过的页签，以及点的时候“一开始显示哪一页”是什么：面板里改了一开始显示哪一页，这里就作废、跟着面板走。
  ({String tab, String base})? _picked;

  String get _shown {
    final n = widget.args.node;
    final base = lcCurrentTab(n) ?? '';
    final p = _picked;
    if (p != null && p.base == base && lcSlotsOf(n).any((s) => s.name == p.tab)) return p.tab;
    return base;
  }

  @override
  void initState() {
    super.initState();
    _follow();
  }

  @override
  void didUpdateWidget(CanvasTabs old) {
    super.didUpdateWidget(old);
    if (old.args.selected != widget.args.selected) _follow();
  }

  /// 选中的组件在别的页签里：切过去，不然选中了却看不见。
  void _follow() {
    final id = widget.args.selected, n = widget.args.node;
    if (id == null || id == n.id) return;
    bool holds(LcNode x) => x.id == id || x.children.any(holds);
    for (final c in n.children) {
      if (!holds(c)) continue;
      final tab = lcSlotOfChild(n, c);
      if (tab != null) _picked = (tab: tab, base: lcCurrentTab(n) ?? '');
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.args, n = a.node;
    final pill = lcVariantOf(n) == 'pill';
    final shown = _shown;
    Widget header(LcSlot tab) {
      final on = tab.name == shown;
      final label = Text(
        tab.label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: a.textColor.withValues(alpha: on ? 1 : 0.6),
          fontWeight: on ? FontWeight.w600 : null,
        ),
      );
      final box = pill
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(color: on ? kLcPagePill : null, borderRadius: BorderRadius.circular(999)),
              child: label,
            )
          : Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(width: 2, color: on ? a.textColor : Colors.transparent)),
              ),
              child: label,
            );
      if (a.inert) return box;
      return GestureDetector(
        key: ValueKey('lc-tab-${n.id}-${tab.name}'),
        behavior: HitTestBehavior.opaque,
        onTap: () {
          setState(() => _picked = (tab: tab.name, base: lcCurrentTab(n) ?? ''));
          a.onSelect(n.id);
        },
        child: box,
      );
    }

    final tabs = lcSlotsOf(n);
    final bounded = a.tightW || a.boundedW;
    final bar = QuietFlex(
      direction: Axis.horizontal,
      mainAxisSize: pill ? MainAxisSize.min : MainAxisSize.max,
      spacing: pill ? 8 : 0,
      children: [
        for (final t in tabs)
          if (pill) header(t) else Expanded(child: header(t)),
      ],
    );
    final body = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (pill)
          bar
        else
          DecoratedBox(
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: kLcPageSoftLine)),
            ),
            child: bar,
          ),
        const SizedBox(height: 12),
        if (shown.isNotEmpty) a.slot(shown, row: false, availW: bounded ? a.contentW : math.max(a.contentW, 240)),
      ],
    );
    // 标签页要一个有上限的宽度（里面的内容要撑满）；放在没有上限的地方给一个手机宽。
    return bounded ? body : SizedBox(width: math.max(a.contentW, 240), child: body);
  }
}

/// 弹窗在页面里留的小标签（它平时不显示，不占页面的位置；点它进“只看这个弹层”）。
class _DialogChip extends StatelessWidget {
  const _DialogChip({required this.title});
  final String? title;

  @override
  Widget build(BuildContext context) {
    final ui = context.themeSpec;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: ui.lowcodeColor(LowcodeKey.dropIdleBg),
        borderRadius: BorderRadius.circular(Radii.sm),
        border: Border.all(color: ui.lowcodeColor(LowcodeKey.dropIdleBorder)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.web_asset_outlined, size: 16, color: ui.lowcodeColor(LowcodeKey.dropText)),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              '弹窗 · ${title ?? '没有标题'} · 点一下编辑',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, height: 1.4, fontWeight: FontWeight.w400, color: ui.lowcodeColor(LowcodeKey.dropText)),
            ),
          ),
        ],
      ),
    );
  }
}

/// 空插槽的落点。横排的插槽里是 28 见方的小框，竖排的是一条写着字的。
class CanvasSlotHint extends StatelessWidget {
  const CanvasSlotHint({super.key, required this.label, required this.row, this.quiet = false});
  final String label;
  final bool row;

  /// 宿主没被选中时画淡一点：一页里十来个小“＋”框太抢眼，选中那一行时才画实。
  final bool quiet;

  @override
  Widget build(BuildContext context) {
    final ui = context.themeSpec;
    final box = BoxDecoration(
      color: ui.lowcodeColor(LowcodeKey.dropIdleBg),
      borderRadius: BorderRadius.circular(Radii.sm),
      border: Border.all(color: ui.lowcodeColor(LowcodeKey.dropIdleBorder)),
    );
    final color = ui.lowcodeColor(LowcodeKey.dropText);
    if (row) {
      return Opacity(
        opacity: quiet ? 0.4 : 1,
        child: Container(
          width: 28,
          height: 28,
          decoration: box,
          child: Icon(Icons.add, size: 14, color: color),
        ),
      );
    }
    return Container(
      height: 40,
      alignment: Alignment.center,
      decoration: box,
      child: Text(
        '$label是空的 · 拖组件到这里',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 12, height: 1.4, fontWeight: FontWeight.w400, color: color),
      ),
    );
  }
}
