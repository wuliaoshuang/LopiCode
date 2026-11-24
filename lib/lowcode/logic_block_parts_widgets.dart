// 设计约束（积木上的小零件 · 390×844）— 2026-11-24
// - 参数胶囊：视觉高 30、点按区高 40；“从几个里选”的带小三角；有问题的画红圈。
// - 问题标记：积木右上角一个带白边的圆点（红＝错误，黄＝提醒），点按区 40×40。
// - 虚线占位“点这里加积木”：高 40，也是拖动的落点（指到时变成强调色）。
// - 操作行：选中积木后出现在它正下方，一行五个图标按钮（上移 / 下移 / 复制 / 删除 / 在下面加一块），每个 44×40；
//   嵌得很深、宽度不够时整行等比缩小，不换行不溢出。
// - 颜色都从 logic_block_widgets.dart 的配色表来，这里不另外定义分类色。
import 'package:lopicode/lowcode/logic_block_widgets.dart';
import 'package:lopicode/lowcode/logic_model.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:material_ui/material_ui.dart';

/// 句子里的参数胶囊。视觉高 30，点按区高 40。
class LcArgChip extends StatelessWidget {
  const LcArgChip({super.key, required this.text, required this.tone, required this.onTap, this.dropdown = false, this.flagged = false});
  final String text;
  final LcTone tone;
  final VoidCallback? onTap;

  /// 是“从几个里选一个”的（变量 / 控件 / 枚举）：尾巴上带个小三角。
  final bool dropdown;

  /// 这个参数有校验问题：红圈。
  final bool flagged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 40, maxWidth: 300),
        child: Align(
          alignment: Alignment.centerLeft,
          widthFactor: 1,
          heightFactor: 1,
          child: Container(
            constraints: const BoxConstraints(minHeight: 30, minWidth: 30),
            padding: EdgeInsets.fromLTRB(10, 4, dropdown ? 4 : 10, 4),
            decoration: BoxDecoration(
              color: tone.chip,
              borderRadius: BorderRadius.circular(15),
              border: flagged ? Border.all(color: c.danger, width: 2) : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: tone.chipInk, fontSize: FontSize.sm, fontWeight: FontWeight.w600, height: 1.3),
                  ),
                ),
                if (dropdown) Icon(Icons.arrow_drop_down_rounded, size: 20, color: tone.chipInk),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 积木右上角的问题标记：错误是红的，警告是黄的。
class LcIssueDot extends StatelessWidget {
  const LcIssueDot({super.key, required this.error, required this.onTap});
  final bool error;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: onTap,
    child: SizedBox(
      width: 40,
      height: 40,
      child: Center(
        child: Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: error ? const Color(0xFFC6212F) : const Color(0xFFF7BC2E),
            shape: BoxShape.circle,
            border: Border.all(color: kLcBlockInk, width: 2),
          ),
          alignment: Alignment.center,
          child: Text(
            '!',
            style: TextStyle(color: error ? kLcBlockInk : const Color(0xFF27282F), fontSize: FontSize.xs, fontWeight: FontWeight.w600, height: 1),
          ),
        ),
      ),
    ),
  );
}

/// 虚线占位：“点这里加积木”。也是拖动的落点。
class LcAddSlot extends StatelessWidget {
  const LcAddSlot({super.key, required this.host, required this.spot, required this.label});
  final LcStackHost host;
  final LcDropSpot spot;
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final hint = host.dropHint;
    final active = hint != null && lcSamePath(hint.parent, spot.parent) && (spot.parent.isEmpty || hint.inElse == spot.inElse) && hint.index == spot.index;
    return LcDropZone(
      host: host,
      spotFor: (_) => spot,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => host.addAt(spot),
        child: CustomPaint(
          painter: _DashPainter(active ? c.accent : c.textFaint, active ? 2 : 1),
          child: SizedBox(
            height: 40,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.add_rounded, size: 18, color: active ? c.accent : c.textMuted),
                const SizedBox(width: Space.x1),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: active ? c.accent : c.textMuted, fontSize: FontSize.sm),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DashPainter extends CustomPainter {
  const _DashPainter(this.color, this.width);
  final Color color;
  final double width;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = width;
    final box = RRect.fromRectAndRadius((Offset.zero & size).deflate(width / 2), const Radius.circular(kLcBlockRadius));
    for (final metric in (Path()..addRRect(box)).computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += 9) {
        canvas.drawPath(metric.extractPath(d, d + 5), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashPainter old) => old.color != color || old.width != width;
}

/// 选中积木后出现在它下面的一行操作。
class LcActionRow extends StatelessWidget {
  const LcActionRow({super.key, required this.host, required this.path, required this.editable});
  final LcStackHost host;
  final LcBlockPath path;
  final bool editable;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final list = host.handler.listAt(path.sublist(0, path.length - 1), inElse: path.last.inElse);
    final index = path.last.index;
    Widget button(IconData icon, String tip, LcBlockAction action, {bool enabled = true, Color? color}) => IconButton(
      tooltip: tip,
      onPressed: enabled ? () => host.act(path, action) : null,
      icon: Icon(icon, size: 20),
      color: color ?? c.text,
      disabledColor: c.textFaint.withValues(alpha: 0.45),
      constraints: const BoxConstraints.tightFor(width: 44, height: 40),
      padding: EdgeInsets.zero,
    );
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 4),
      child: Align(
        alignment: Alignment.centerLeft,
        child: DecoratedBox(
          decoration: BoxDecoration(color: c.surfaceMuted, borderRadius: BorderRadius.circular(Radii.md)),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                button(Icons.arrow_upward_rounded, '上移', LcBlockAction.up, enabled: index > 0),
                button(Icons.arrow_downward_rounded, '下移', LcBlockAction.down, enabled: list != null && index < list.length - 1),
                button(Icons.copy_rounded, '复制', LcBlockAction.copy),
                button(Icons.delete_outline_rounded, '删除', LcBlockAction.delete, color: c.danger),
                button(Icons.add_rounded, '在下面加一块', LcBlockAction.addBelow),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 拖动时指示“会插到这里”的横条。
class LcDropBar extends StatelessWidget {
  const LcDropBar({super.key, required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: Container(
      height: 4,
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
    ),
  );
}

/// 拖动时跟着手指的小标签。
class LcDragGhost extends StatelessWidget {
  const LcDragGhost({super.key, required this.text, required this.tone});
  final String text;
  final LcTone tone;

  @override
  Widget build(BuildContext context) => FractionalTranslation(
    translation: const Offset(-0.5, -1.4),
    child: Material(
      color: Colors.transparent,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 260),
        padding: const EdgeInsets.symmetric(horizontal: Space.x3, vertical: Space.x2),
        decoration: BoxDecoration(
          color: tone.fill.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(kLcBlockRadius),
          boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 12, offset: Offset(0, 4))],
        ),
        child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: kLcBlockWords),
      ),
    ),
  );
}

/// 一块可以“拖到这里”的区域。手指在上半还是下半决定插在前面还是后面（[spotFor] 说了算）。
class LcDropZone extends StatefulWidget {
  const LcDropZone({super.key, required this.host, required this.spotFor, required this.child});
  final LcStackHost host;
  final LcDropSpot Function(bool upperHalf) spotFor;
  final Widget child;

  @override
  State<LcDropZone> createState() => _LcDropZoneState();
}

class _LcDropZoneState extends State<LcDropZone> {
  /// 手指在这块区域里指的是哪个插入位；不能放（别的处理的积木、放进自己里面、原位）返回 null。
  LcDropSpot? _spotAt(LcDragData data, Offset global) {
    if (data.handlerId != widget.host.handler.id) return null;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return null;
    final spot = widget.spotFor(box.globalToLocal(global).dy < box.size.height / 2);
    return lcCanDrop(data.path, spot) ? spot : null;
  }

  @override
  Widget build(BuildContext context) => DragTarget<LcDragData>(
    onWillAcceptWithDetails: (d) => d.data.handlerId == widget.host.handler.id,
    onMove: (d) => widget.host.hover(_spotAt(d.data, d.offset)),
    onLeave: (_) => widget.host.hover(null),
    onAcceptWithDetails: (d) {
      final spot = _spotAt(d.data, d.offset);
      widget.host.hover(null);
      if (spot != null) widget.host.drop(d.data, spot);
    },
    builder: (context, _, _) => widget.child,
  );
}
