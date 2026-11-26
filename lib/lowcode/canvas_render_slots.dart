part of 'canvas_render_widgets.dart';

/// 拖柄拖动中的临时尺寸：只影响画布怎么画，不动页面数据（松手才真的写进去）。
class CanvasResizePreview {
  const CanvasResizePreview(this.nodeId, this.width, this.height);
  final String nodeId;
  final int? width;
  final int? height;
}

/// 画一个子组件时，从父容器那里知道的事。
class _Ctx {
  const _Ctx({
    required this.parent,
    required this.flow,
    required this.boundedW,
    required this.boundedH,
    required this.availW,
    required this.availH,
    required this.scale,
    required this.growCount,
    required this.textColor,
    required this.buttonText,
    required this.styles,
    required this.env,
  });
  final LcNode parent;
  final CssFlow flow;

  /// 父容器给的宽 / 高是不是有上限。没有上限时不能“撑满”，不然排版会报错。
  final bool boundedW;
  final bool boundedH;

  /// 父容器内容区的宽高（估的），百分比尺寸参照它；高度不知道是 null。
  final double availW;
  final double? availH;
  final CssScale scale;

  /// 父容器里有几个子项要“放大占满”，用来估每个能分到多宽。
  final int growCount;

  /// 继承下来的文字颜色（边框、阴影没写颜色时用它，CSS 的 currentcolor）。
  final Color textColor;

  /// 设了字号的按钮，文字的基础样式沿用应用主题里的（第 1 版就是这样，换掉的话旧页面的按钮会变样）。
  final TextStyle? buttonText;

  /// 这一次重搭里已经算过的最终样式（按组件对象记）：同一个组件不算第二遍。
  final Map<LcNode, Map<String, String>> styles;

  /// 按什么条件看（主题变量的值、现在是哪一档屏宽）。
  final LcViewEnv env;

  Map<String, String> styleOf(LcNode n, LcNode? parent) => styles[n] ??= resolvedStyle(lcViewNode(n, env), parent);
}

bool _has(Map<String, String> s, String prefix) => s.keys.any((k) => k.startsWith(prefix));

bool _hasRadius(Map<String, String> s) => s.keys.any((k) => k.startsWith('border-') && k.endsWith('-radius'));

/// 画布上的插槽（自定义组件的），两种情形：
/// - 组件编辑页里（或者页面里误放的）占位节点：一个能选中、能拖、能往里放默认内容的框，顶上一行角标“插槽 · 名字”（自己占一行，不盖内容）。
///   它里面的东西照它外面那个容器的排法排（横排 / 竖排、间距、对齐都跟容器走）。
/// - 页面上一个实例展开以后留下的记号（`props.host` 是实例的 id）：填了内容的，内容交给活页面画（能选中、能改、能拖走）；
///   没填的画定义里的默认内容（只是样子）；连默认内容也没有，画一个空位提示。落点 id 是 `实例id#插槽名`。
extension _CanvasSlots on CanvasPage {
  Widget _item(BuildContext context, LcNode container, Map<String, String> s, _Ctx inner, LcNode c) => c.type == 'slot' ? _slotBox(context, container, s, inner, c) : _node(context, c, inner);

  Widget _slotBox(BuildContext context, LcNode container, Map<String, String> s, _Ctx inner, LcNode slot) {
    final hostId = slot.strProp('host');
    final name = lcSlotNameOf(slot);
    final row = inner.flow.row;
    final label = slot.name.isNotEmpty ? slot.name : lcDefaultSlotLabel(name);
    Widget body;
    if (hostId == null) {
      // 占位节点本身
      body = _flex(context, container, s, inner, tightW: !row, tightH: false, only: slot.children);
      if (!inert) {
        final ui = context.themeSpec;
        // 角标自己占一行（不叠在内容上：叠着会盖住默认内容的字，两个插槽挨着时角标还会互相压）。
        // 所以编辑页里插槽框比真正用的时候高出一行角标——页面上用这个组件时没有这一行。
        body = DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: BoxDecoration(
            border: Border.all(color: ui.lowcodeColor(LowcodeKey.dropIdleBorder)),
            borderRadius: BorderRadius.circular(Radii.sm),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: inner.boundedW ? CrossAxisAlignment.stretch : CrossAxisAlignment.start,
            children: [
              Align(alignment: Alignment.centerLeft, widthFactor: 1, heightFactor: 1, child: CanvasBadge(doc.root.id == kComponentEditRootId ? '插槽 · $label' : '插槽（只在组件里有用）')),
              body,
            ],
          ),
        );
        body = KeyedSubtree(key: boxKey(slot.id), child: body);
        body = GestureDetector(key: ValueKey('lowcode-node-${slot.id}'), behavior: HitTestBehavior.opaque, onTap: () => onSelect(slot.id), child: body);
        body = _liftable(slot, slot.id == movingId ? Opacity(opacity: 0.35, child: body) : body);
      }
    } else {
      final page = inert ? live : this;
      final active = page != null && !page.inert && page.doc.find(hostId) != null;
      if (active && slot.props['filled'] == true) {
        body = page._flex(context, container, s, inner, tightW: !row, tightH: false, only: slot.children);
      } else if (slot.children.isEmpty) {
        body = active ? CanvasSlotHint(key: ValueKey('lc-slot-hint-$hostId-$name'), label: label, row: row, quiet: page.selected != hostId) : const SizedBox.shrink();
      } else {
        body = _flex(context, container, s, inner, tightW: !row, tightH: false, only: slot.children);
      }
      if (active) body = KeyedSubtree(key: page.boxKey(lcSlotBoxId(hostId, name)), child: body);
    }
    // 占满它外面那个容器：竖排占满宽，横排占掉剩下的宽。
    final key = ValueKey('lc-item-${hostId == null ? slot.id : '$hostId#$name'}');
    if (inner.flow.wrap) return KeyedSubtree(key: key, child: body);
    if (row) return inner.boundedW ? Expanded(key: key, child: body) : KeyedSubtree(key: key, child: body);
    return inner.boundedW ? SizedBox(key: key, width: double.infinity, child: body) : KeyedSubtree(key: key, child: body);
  }
}
