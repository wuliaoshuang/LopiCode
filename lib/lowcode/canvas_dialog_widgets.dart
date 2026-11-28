// 设计约束（低代码 · 画布“只看这个弹层” · 390×844）
// - 弹窗平时不显示，所以单独给它一个编辑状态：整块页面换成“遮罩 + 居中的弹窗面板”，页面里别的组件这时不画（不会误点、误拖进去）。
// - 面板照导出网页的样子：最宽 320、四周留 24、内边距 20、圆角 12、白底；从上到下：标题 → 正文 → 内容插槽 → 底部。
// - 底部：自己往“底部”插槽里放了东西就只画它们；没放就画自带的按钮（提示＝确定；确认＝取消 + 确定），旁边留一个小落点。
// - 轻提示（样子＝toast，第四轮 B8）：没有遮罩和面板，页面底色上靠下画一颗深色小胶囊，只有一句话。
// - 退出的按钮不在这里（它是编辑器的东西，不属于页面）：在画布顶上那条“正在编辑弹窗”的横条里（overlay_bar_widgets.dart）。
import 'dart:math' as math;

import 'package:lopicode/lowcode/canvas_v3_widgets.dart';
import 'package:lopicode/lowcode/model.dart';
import 'package:lopicode/lowcode/model_v3_components.dart';
import 'package:lopicode/lowcode/slots.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:material_ui/material_ui.dart';

/// 弹窗面板里面能放内容的宽度。
double canvasDialogContentWidth(double pageWidth) => math.max(0, math.min(320, pageWidth - 48) - 40);

/// “只看这个弹层”时的整块页面。[pageKey] 是页面的定位 key，[panelKey] 是弹窗自己的。
Widget canvasDialogStage(
  BuildContext context, {
  required LcNode node,
  required double pageWidth,
  required double minHeight,
  required Color pageColor,
  required Key pageKey,
  required Key panelKey,
  required bool inert,
  required VoidCallback onSelect,
  required CanvasSlotBuilder slot,
}) {
  final c = context.colors;
  if (lcIsToast(node)) {
    // 轻提示：没有遮罩，页面底色上靠下一颗深色小胶囊（照导出网页的样子）。
    final pill = Container(
      key: panelKey,
      constraints: BoxConstraints(maxWidth: math.max(0, pageWidth - 48)),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(color: kLcToastBg, borderRadius: BorderRadius.circular(8)),
      child: Text(node.strProp('text') ?? '', style: const TextStyle(color: kLcPageWhite, fontSize: 14, height: 1.4)),
    );
    return Container(
      key: pageKey,
      width: pageWidth,
      constraints: BoxConstraints(minHeight: minHeight),
      color: pageColor,
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 72),
      alignment: Alignment.bottomCenter,
      child: inert ? pill : GestureDetector(key: ValueKey('lowcode-node-${node.id}'), behavior: HitTestBehavior.opaque, onTap: onSelect, child: pill),
    );
  }
  final inner = canvasDialogContentWidth(pageWidth);
  final title = node.strProp('title'), text = node.strProp('text');
  final ownFooter = lcSlotChildren(node, 'footer').isNotEmpty;
  final confirm = lcVariantOf(node) == 'confirm';
  Widget action(String label) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    child: Text(
      label,
      style: const TextStyle(fontWeight: FontWeight.w600, color: kLcPageAccent),
    ),
  );
  final panel = Container(
    key: panelKey,
    width: inner + 40,
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: kLcPageWhite,
      borderRadius: BorderRadius.circular(12),
      boxShadow: [BoxShadow(color: c.shadowOf(0.25), blurRadius: 32, offset: const Offset(0, 8))],
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 12,
      children: [
        if (title != null) Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, height: 1.4)),
        if (text != null) Text(text, style: const TextStyle(height: 1.5, color: kLcPageMuted)),
        if (!inert || lcSlotChildren(node, 'content').isNotEmpty) slot('content', row: false, availW: inner),
        if (ownFooter)
          slot('footer', row: true, availW: inner, end: true)
        else
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            spacing: 8,
            children: [
              if (!inert) slot('footer', row: true, availW: inner, end: true),
              if (confirm) action(node.strProp('cancelText') ?? '取消'),
              action(node.strProp('okText') ?? '确定'),
            ],
          ),
      ],
    ),
  );
  return Container(
    key: pageKey,
    width: pageWidth,
    constraints: BoxConstraints(minHeight: minHeight),
    color: pageColor,
    child: Container(
      constraints: BoxConstraints(minHeight: minHeight),
      color: c.scrimOf(0.45),
      padding: const EdgeInsets.all(24),
      alignment: Alignment.center,
      child: inert ? panel : GestureDetector(key: ValueKey('lowcode-node-${node.id}'), behavior: HitTestBehavior.opaque, onTap: onSelect, child: panel),
    ),
  );
}
