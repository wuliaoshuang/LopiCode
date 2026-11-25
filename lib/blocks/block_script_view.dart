// 设计约束（一串积木的静态显示）— 2026-11-24
// - 这个控件只做一件事：把一串积木（帽子 + 下面的积木）按排版结果画出来，大小正好是这一串占的大小。
// - 点一下：回调告诉外面点到了哪块积木、哪个槽位（外面决定选中还是就地编辑）。这里不做拖拽。
// - 被拖着的样子（`lifted`）：整串略放大并带投影；落点阴影（`ghost`）：只有半透明剪影。
import 'package:lopicode/blocks/block_colors.dart';
import 'package:lopicode/blocks/block_geometry.dart';
import 'package:lopicode/blocks/block_host.dart';
import 'package:lopicode/blocks/block_layout.dart';
import 'package:lopicode/blocks/block_paint_view.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:material_ui/material_ui.dart';

/// 画积木要用的一套东西：字（按主题字体）、色表（按明暗）、画笔。几个积木控件各拿一套。
class BkKit {
  BkKit({required String? fontFamily, required bool dark, BkPalette? palette, this.metrics = const BkMetrics()})
    : text = BkText(fontFamily: fontFamily, metrics: metrics),
      palette = palette ?? BkPalette.of(dark: dark) {
    painter = BkScriptPainter(palette: this.palette, text: text, metrics: metrics);
  }

  /// 照当前主题造一套。
  factory BkKit.of(BuildContext context) {
    final theme = Theme.of(context);
    return BkKit(fontFamily: theme.textTheme.bodyMedium?.fontFamily, dark: theme.brightness == Brightness.dark, palette: BkPalette.fromTheme(context.themeSpec));
  }

  final BkMetrics metrics;
  final BkText text;
  final BkPalette palette;
  late final BkScriptPainter painter;

  /// 主题没变（字体、积木色表都一样）就可以接着用。
  bool fits(BuildContext context) {
    final theme = Theme.of(context);
    return text.fontFamily == theme.textTheme.bodyMedium?.fontFamily && identical(palette, BkPalette.fromTheme(context.themeSpec));
  }

  BlockLayoutEngine engine(BlockHost host) => BlockLayoutEngine(host, text.measure, metrics: metrics);

  void dispose() => text.dispose();
}

/// 持有一套 [BkKit] 的 State 混入：主题变了自动换一套。
mixin BkKitHolder<T extends StatefulWidget> on State<T> {
  BkKit? _kit;

  BkKit get kit => _kit!;

  /// 主题变了（换了一套 kit）时调，子类用来丢掉旧的排版缓存。
  void kitChanged() {}

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_kit == null || !_kit!.fits(context)) {
      _kit?.dispose();
      _kit = BkKit.of(context);
      kitChanged();
    }
  }

  @override
  void dispose() {
    _kit?.dispose();
    super.dispose();
  }
}

/// 把排好版的一串积木画出来。排版由外面给（[BlockScriptView.of] 可以代劳）。
class BkLayoutView extends StatelessWidget {
  const BkLayoutView({super.key, required this.layout, required this.kit, this.state = BkPaintState.none, this.revision = 0, this.onTap});

  final BkScriptLayout layout;
  final BkKit kit;
  final BkPaintState state;
  final int revision;

  /// 点到了积木（没点到积木不回调）。
  final void Function(BkHit hit)? onTap;

  @override
  Widget build(BuildContext context) {
    Widget child = CustomPaint(
      size: layout.size,
      painter: BkScriptCustomPainter(layout: layout, painter: kit.painter, state: state, revision: revision),
    );
    if (state.lifted) child = Transform.scale(scale: 1.04, alignment: Alignment.topLeft, child: child);
    final tap = onTap;
    if (tap == null) return child;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTapUp: (d) {
        final hit = layout.hitTest(d.localPosition);
        if (hit != null) tap(hit);
      },
      child: child,
    );
  }
}

/// 给定宿主和一串脚本的 id，把它画出来。
class BlockScriptView extends StatefulWidget {
  const BlockScriptView({super.key, required this.host, required this.scriptId, this.state = BkPaintState.none, this.onTap});

  final BlockHost host;
  final String scriptId;
  final BkPaintState state;
  final void Function(BkHit hit)? onTap;

  @override
  State<BlockScriptView> createState() => _BlockScriptViewState();
}

class _BlockScriptViewState extends State<BlockScriptView> with BkKitHolder {
  BkScriptLayout? _layout;
  int _rev = -1;

  @override
  void kitChanged() => _layout = null;

  @override
  void didUpdateWidget(BlockScriptView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.host, widget.host) || oldWidget.scriptId != widget.scriptId) _layout = null;
  }

  @override
  Widget build(BuildContext context) {
    final tree = widget.host.script(widget.scriptId);
    if (tree == null) return const SizedBox.shrink();
    if (_layout == null || _rev != widget.host.revision) {
      _layout = kit.engine(widget.host).layoutScript(tree);
      _rev = widget.host.revision;
    }
    return BkLayoutView(layout: _layout!, kit: kit, state: widget.state, revision: _rev, onTap: widget.onTap);
  }
}
