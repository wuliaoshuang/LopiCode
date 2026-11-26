// 设计约束（低代码 · “屏宽与缩放”面板 · 390×844）
// - 从顶栏“⋮”进来的底部面板，不常点的画布显示设置都在这里（原来浮在画布上的两个小条挪到这儿，画布上不再有东西挡着）。
// - 从上到下三行，一行只做一件事：
//     屏宽：自适应 / 360 / 390 / 768（选中的那一档会显示在顶栏的小字里）；
//     缩放：缩小、当前比例、放大、“适应屏幕”；
//     间距示意：开关（选中组件时画出外边距橙色、内边距绿色）。
// - 改了马上生效，面板不关（可以连着调）；点面板外面关掉。
import 'package:lopicode/lowcode/canvas_view.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:material_ui/material_ui.dart';

/// 打开“屏宽与缩放”。现在的值用函数取（面板开着时外面的值会变）。
Future<void> showCanvasViewSheet(
  BuildContext context, {
  required CanvasViewState canvas,
  required int Function() presetWidth,
  required void Function(int preset) onPresetWidth,
  required bool Function() showBoxModel,
  required void Function(bool show) onShowBoxModel,
}) => showModalBottomSheet<void>(
  context: context,
  barrierColor: context.colors.scrimOf(0x1F / 255),
  builder: (context) => StatefulBuilder(
    builder: (context, setSheet) {
      final c = context.colors;
      final t = Theme.of(context).textTheme;
      final preset = presetWidth();
      Widget row(String label, Widget child) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.x4, vertical: Space.x2),
        child: Row(
          children: [
            SizedBox(
              width: 72,
              child: Text(label, style: t.bodyMedium?.copyWith(color: c.textMuted)),
            ),
            Expanded(child: child),
          ],
        ),
      );
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.x4, 0, Space.x4, Space.x2),
              child: Text('屏宽与缩放', style: t.titleLarge),
            ),
            row(
              '屏宽',
              SegmentedButton<int>(
                showSelectedIcon: false,
                style: const ButtonStyle(visualDensity: VisualDensity.compact),
                segments: [
                  for (final w in kCanvasWidthPresets)
                    ButtonSegment(
                      value: w,
                      label: Text(w == 0 ? '自适应' : '$w', key: ValueKey('lc-width-$w')),
                    ),
                ],
                selected: {preset},
                onSelectionChanged: (v) {
                  onPresetWidth(v.first);
                  setSheet(() {});
                },
              ),
            ),
            row(
              '缩放',
              Row(
                children: [
                  IconButton(tooltip: '缩小', icon: const Icon(Icons.remove), onPressed: () => canvas.zoomStep(-1)),
                  ValueListenableBuilder<CanvasViewport>(
                    valueListenable: canvas.view,
                    builder: (context, v, _) => SizedBox(
                      width: 52,
                      child: Text('${(v.scale * 100).round()}%', key: const ValueKey('lowcode-zoom-label'), textAlign: TextAlign.center, style: t.titleSmall),
                    ),
                  ),
                  IconButton(tooltip: '放大', icon: const Icon(Icons.add), onPressed: () => canvas.zoomStep(1)),
                  const Spacer(),
                  OutlinedButton(key: const ValueKey('lc-fit'), onPressed: canvas.fitToScreen, child: const Text('适应屏幕')),
                ],
              ),
            ),
            SwitchListTile(
              key: const ValueKey('lc-box-model'),
              contentPadding: const EdgeInsets.symmetric(horizontal: Space.x4),
              title: const Text('间距示意'),
              subtitle: const Text('选中组件时画出外边距（橙）和内边距（绿）'),
              value: showBoxModel(),
              onChanged: (v) {
                onShowBoxModel(v);
                setSheet(() {});
              },
            ),
            const SizedBox(height: Space.x2),
          ],
        ),
      );
    },
  ),
);
