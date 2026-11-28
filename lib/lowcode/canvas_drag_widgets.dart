// 设计约束（低代码 · 拖组件时叠在画面上的东西）
// - 页面排版不动，落点只靠叠上去的三样说明（都不挡手指）：
//     蓝线：屏幕上 3 像素粗（不随缩放变），竖排的容器里是横线、横排的容器里是竖线；
//     容器描边：停够了才“放进去”的容器描一圈蓝边；空容器没有线，整块淡蓝高亮；
//     小标签：贴在蓝线上方（空容器贴在它左上角里面），写“放到 卡片 里 · 第 2 个”。
//       横线上的标签躲着手指：手指在线的左半边就贴线的右头，不然贴左头——手指上方的缩略图盖不到它。
//   放下去等于没动（原地）时三样都不画。
// - 手指下面的缩略图：就是这个组件自己的样子，垫一张带阴影的小白卡片，略透明，最宽 160、最高 120（放不下就按比例缩小），不挡手指。
//   它跟着手指走，由搭建台放在最上面一层（见 editor_workbench_widgets.dart）。
import 'package:lopicode/lowcode/canvas_render_widgets.dart';
import 'package:lopicode/lowcode/comp_lib_builtin.dart';
import 'package:lopicode/lowcode/component_model.dart';
import 'package:lopicode/lowcode/component_ops.dart';
import 'package:lopicode/lowcode/editor_drag.dart';
import 'package:lopicode/lowcode/model.dart';
import 'package:lopicode/lowcode/palette_widgets.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:material_ui/material_ui.dart';

/// 画在页面上面的落点说明（页面坐标；放在画布的变换里面）。
class CanvasDropOverlay extends StatelessWidget {
  const CanvasDropOverlay({super.key, required this.target, required this.scale, this.fingerX});
  final DropTarget target;

  /// 手指横着在哪（页面坐标）。标签放在离它远的那一头。
  final double? fingerX;

  /// 画布的缩放：线宽、标签按它反着缩，屏幕上看起来一样大。
  final double scale;

  @override
  Widget build(BuildContext context) {
    if (target.noop) return const SizedBox.shrink();
    final k = 1 / scale;
    final line = target.line, box = target.parentRect;
    final thick = kDropLineWidth * k;
    final ui = context.themeSpec;
    final mark = ui.lowcodeColor(LowcodeKey.insertBar);
    // 标签：有线贴线的上方（太靠页面顶就放线下面）；空容器放在它里面的左上角。
    final Offset labelAt;
    var atRight = false;
    if (line != null) {
      final above = line.top - 26 * k;
      atRight = line.width > line.height && fingerX != null && fingerX! < line.center.dx;
      labelAt = Offset(atRight ? line.right : line.left, above < 0 ? line.bottom + 6 * k : above);
    } else {
      labelAt = Offset(box.left + 6 * k, box.top + 6 * k);
    }
    return IgnorePointer(
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          if (target.inside)
            Positioned.fromRect(
              rect: box,
              child: DecoratedBox(
                key: const ValueKey('lc-drop-box'),
                decoration: BoxDecoration(
                  color: line == null ? mark.withValues(alpha: 0.12) : null,
                  border: Border.all(color: mark, width: 2 * k),
                ),
              ),
            ),
          if (line != null)
            Positioned.fromRect(
              // 量出来的线是按 1 倍算的粗细；这里换成屏幕上固定 3 像素
              rect: line.width > line.height ? Rect.fromLTWH(line.left, line.center.dy - thick / 2, line.width, thick) : Rect.fromLTWH(line.center.dx - thick / 2, line.top, thick, line.height),
              child: DecoratedBox(
                key: const ValueKey('lc-drop-line'),
                decoration: BoxDecoration(color: mark, borderRadius: BorderRadius.circular(thick / 2)),
              ),
            ),
          Positioned(
            left: labelAt.dx,
            top: labelAt.dy,
            child: FractionalTranslation(
              translation: Offset(atRight ? -1 : 0, 0),
              child: Transform.scale(
                scale: k,
                alignment: atRight ? Alignment.topRight : Alignment.topLeft,
                child: Container(
                  key: const ValueKey('lc-drop-label'),
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: ui.lowcodeColor(LowcodeKey.selection), borderRadius: BorderRadius.circular(4)),
                  child: Text(
                    target.label,
                    style: TextStyle(fontSize: 11, height: 1.3, color: ui.lowcodeColor(LowcodeKey.selectionText), fontWeight: FontWeight.w500, decoration: TextDecoration.none),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 缩略图最宽 / 最高多少（屏幕像素）。
const double kDragGhostMaxWidth = 160;
const double kDragGhostMaxHeight = 120;

/// 拖动时手指下面的缩略图：把要拖的那个组件单独画一份。
///
/// [layoutWidth]：按多宽来排它（挪已有的组件＝它现在的宽度；从组件盒拖新的＝页面宽度）。
/// 画不出来（组件不在了）返回 null。
Widget? buildDragGhost(LcDocument doc, LcDrag drag, {required double layoutWidth}) {
  final LcNode node;
  if (drag.nodeId != null) {
    final found = doc.find(drag.nodeId!);
    if (found == null || found.type == 'page') return null;
    node = copyLcTree(found);
  } else {
    node = LcNode(id: 'ghost', type: drag.type!, props: Map<String, dynamic>.of(lcSpecs[drag.type!]!.defaults));
    if (drag.ref != null) node.props['ref'] = drag.ref;
  }
  // 垫一张没有边距、透明的页面，只放这一个组件；自定义组件的定义带上，实例才画得出来。
  final temp = LcDocument(
    title: '',
    root: LcNode(id: 'ghost-page', type: 'page', props: {'padding': 0, 'gap': 0}, style: {'background-color': 'transparent'}, children: [node]),
    components: [for (final c in doc.components) LcComponentDef(id: c.id, name: c.name, props: c.props.toList(), root: copyLcTree(c.root))],
  );
  // 主题变量也带上（缩略图里用到变量的颜色才对）。
  if (doc.more['theme'] != null) temp.more['theme'] = doc.more['theme'];
  // 从组件盒拖出来的是内置组件库里的组件、文档里还没装：缩略图这份里先装上。
  lcEnsureBuiltin(temp, drag.ref);
  final width = layoutWidth.clamp(48.0, 1200.0).toDouble();
  return IgnorePointer(
    child: Opacity(
      opacity: 0.85,
      // 垫一张带阴影的小卡片：一看就是“拎起来的那个”，不会和页面上的字混在一起
      child: Builder(
        builder: (context) => Container(
          key: const ValueKey('lc-drag-ghost'),
          constraints: const BoxConstraints(maxWidth: kDragGhostMaxWidth, maxHeight: kDragGhostMaxHeight),
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            // 用户页面内容的底：页面默认是白的，拎起来的这份也垫白底（和画布上看到的一样），不跟应用主题走。
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: context.themeSpec.lowcodeColor(LowcodeKey.selection)),
            boxShadow: [BoxShadow(color: context.colors.shadowOf(0.2), blurRadius: 12, offset: const Offset(0, 4))],
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: width,
              child: CanvasPage.still(doc: temp, pageWidth: width),
            ),
          ),
        ),
      ),
    ),
  );
}
