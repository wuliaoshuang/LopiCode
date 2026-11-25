// 设计约束（主题编辑器的取色面板 · 底部面板 · 390×844）— 2026-11-26
// - 只占屏幕下面六成左右、后面不压暗：上面那块实时预览要一直看得见，边拖边看效果。面板里的内容超出就自己滚。
// - 从上到下，一行只做一件事：
//   这一项是什么（改之前 → 现在两个色块 + 名字 + 说明）→ 和它的底的对比度（达标 / 偏低）
//   → 取色器的芯（方块、色相条、透明度条、十六进制输入，见 theme_color_picker.dart）
//   → 主题里已有的颜色 → 常用色 → 最近用过 → 底部一行：恢复默认值、不单独上色（次要，左）· 完成（主操作，右）。
// - 拖、点、输入都是立刻生效（预览跟着变），不用再点“确定”；整个面板开着的这一段在撤销里只算一步（由编辑器记）。
// - “恢复默认值”＝同明暗默认主题里这一项的值；高亮分类默认没单独上色的，就是恢复成“不单独上色”。
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lopicode/appearance/theme_color_math.dart';
import 'package:lopicode/appearance/theme_edit_model.dart';
import 'package:lopicode/state/theme_hooks.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/theme_color_picker.dart';
import 'package:material_ui/material_ui.dart';

/// 常用色（两排各八个：一排灰阶，一排彩色）。
const List<int> kThemeCommonColors = [
  0xFF000000, 0xFF27282F, 0xFF50525B, 0xFF989EA4, 0xFFD8DCDF, 0xFFF3F4F6, 0xFFFCFCFC, 0xFFFFFFFF, //
  0xFFC6212F, 0xFFE0457B, 0xFFF08A24, 0xFFF7BC2E, 0xFF058654, 0xFF14A3B8, 0xFF2962CB, 0xFF7C4DFF,
];

/// 主题里已有的颜色最多列几个。
const int kThemeOwnColorsMax = 16;

/// [spec] 里用到的颜色（不看透明度），用得多的在前，最多 [kThemeOwnColorsMax] 个。
List<int> themeOwnColors(ThemeSpec spec) {
  final count = <int, int>{};
  for (final item in kThemeItems) {
    final c = itemColor(spec, item);
    if (c == null) continue;
    final rgb = withAlpha(c, 255);
    count[rgb] = (count[rgb] ?? 0) + 1;
  }
  final sorted = count.keys.toList()..sort((a, b) => count[b]!.compareTo(count[a]!));
  return sorted.take(kThemeOwnColorsMax).toList();
}

/// 打开取色面板。[spec] 每次调用都要给出“现在这份草稿”；[onChanged] 在每次变化时调用（null＝高亮分类不单独上色）。
Future<void> showThemeColorSheet(BuildContext context, {required ThemeItem item, required ThemeSpec Function() spec, required ValueChanged<int?> onChanged}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  barrierColor: Colors.transparent,
  builder: (_) => ThemeColorSheet(item: item, spec: spec, onChanged: onChanged),
);

class ThemeColorSheet extends ConsumerStatefulWidget {
  const ThemeColorSheet({super.key, required this.item, required this.spec, required this.onChanged});
  final ThemeItem item;
  final ThemeSpec Function() spec;
  final ValueChanged<int?> onChanged;

  @override
  ConsumerState<ThemeColorSheet> createState() => _ThemeColorSheetState();
}

class _ThemeColorSheetState extends ConsumerState<ThemeColorSheet> {
  late final int? _before = itemColor(widget.spec(), widget.item);
  late final bool _alphaOk = itemAllowsAlpha(widget.item);
  late final List<int> _own = themeOwnColors(widget.spec());

  /// 现在的颜色；null＝不单独上色（只有高亮分类会）。
  late int? _now = _before;

  /// 没单独上色时取色器从哪个颜色开始调：代码文字的颜色。
  late final int _seed = widget.spec().code[CodeKey.fg] ?? 0xFF808080;

  void _set(int? argb) {
    final next = argb == null ? null : (_alphaOk ? argb : withAlpha(argb, 255));
    setState(() => _now = next);
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final item = widget.item;
    final spec = widget.spec();
    final contrast = worstContrastOf(spec, item.id);
    final recent = ref.watch(recentColorsProvider);
    final fallback = itemDefaultColor(item, dark: spec.dark);
    final atDefault = _now == fallback;
    final mq = MediaQuery.of(context);
    return Padding(
      // 键盘升起来时整块往上让（输十六进制的时候）。
      padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
      child: SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: mq.size.height * 0.6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Flexible(
                child: SingleChildScrollView(
                  key: const Key('color-sheet-scroll'),
                  padding: const EdgeInsets.fromLTRB(Space.x4, 0, Space.x4, Space.x2),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          ThemeSwatch(_before, key: const Key('color-before')),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: Space.x1),
                            child: Icon(Icons.arrow_forward, size: 14, color: c.textFaint),
                          ),
                          ThemeSwatch(_now, key: const Key('color-now')),
                          const SizedBox(width: Space.x3),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(item.label, style: t.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                                Text(
                                  item.note.isEmpty ? item.sectionLabel : '${item.sectionLabel} · ${item.note}',
                                  style: t.bodySmall?.copyWith(color: c.textFaint),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      if (contrast != null)
                        Padding(
                          padding: const EdgeInsets.only(top: Space.x2),
                          child: Row(
                            key: const Key('color-contrast'),
                            children: [
                              Icon(contrast.ok ? Icons.check_circle_outline : Icons.warning_amber_rounded, size: 16, color: contrast.ok ? c.textMuted : c.warning),
                              const SizedBox(width: Space.x1),
                              Expanded(
                                child: Text(
                                  contrastSentence(contrast),
                                  key: const Key('color-contrast-text'),
                                  style: t.bodySmall?.copyWith(color: contrast.ok ? c.textMuted : c.warning),
                                ),
                              ),
                            ],
                          ),
                        ),
                      const SizedBox(height: Space.x3),
                      ThemeColorPicker(value: _now ?? _seed, empty: _now == null, allowAlpha: _alphaOk, onChanged: _set),
                      ThemeSwatchRow(title: '主题里已有的', colors: _own, keyPrefix: 'color-own', onPick: _set),
                      ThemeSwatchRow(title: '常用色', colors: kThemeCommonColors, keyPrefix: 'color-common', onPick: _set),
                      if (recent.isNotEmpty) ThemeSwatchRow(title: '最近用过', colors: recent, keyPrefix: 'color-recent', onPick: _set),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(Space.x2, 0, Space.x4, Space.x2),
                child: Row(
                  children: [
                    TextButton(key: const Key('color-reset-default'), onPressed: atDefault ? null : () => _set(fallback), child: const Text('恢复默认值')),
                    if (item.isToken && fallback != null) TextButton(key: const Key('color-clear'), onPressed: _now == null ? null : () => _set(null), child: const Text('不单独上色')),
                    const Spacer(),
                    FilledButton(key: const Key('color-done'), onPressed: () => Navigator.pop(context), child: const Text('完成')),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 对比度的一句话：“放在“代码 › 代码底色”上：对比度 2.34:1 · 偏低（至少 4.5:1）”。
String contrastSentence(ItemContrast c) => '${c.asFg ? '放在' : '上面放'}“${c.other}”${c.asFg ? '上' : ''}：对比度 ${c.ratio.toStringAsFixed(2)}:1 · ${c.ok ? '达标' : '偏低'}（至少 ${formatMetric(c.min)}:1）';
