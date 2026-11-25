// 设计约束（主题编辑器的“快捷生成”面板 · 底部面板 · 390×844）— 2026-11-26
// - 两种用法共用这一个面板：
//   · 换强调色：只挑一个颜色，相关的一组（实心按钮、强调文字、浅底、选中、开关、光标…）一起重算。
//   · 从主色生成整套：挑两个颜色——强调色、底色倾向（底色和文字往哪个色相偏一点）。上面一行两段切换现在在挑哪一个。
// - 和取色面板一样：后面不压暗、只占下面六成，上面那块预览边挑边变。
// - 从上到下一行一件事：标题 + 一句说明 → （整套时）在挑哪一个的切换 → 取色器的芯 → 常用色 → 底部：取消（左）· 用这个（右，主操作）。
// - 没动过任何东西时“用这个”是灰的；点取消、点外面、按返回都算取消，编辑器把草稿退回打开之前的样子。
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/theme_color_picker.dart';
import 'package:lopicode/ui/theme_color_sheet.dart';
import 'package:material_ui/material_ui.dart';

/// 打开快捷生成面板。[full]＝从主色生成整套（否则只换强调色）。每次变化调 [onChanged]（强调色、底色倾向）。
/// 返回 true＝用这个；别的都算取消。
Future<bool?> showThemeGenerateSheet(BuildContext context, {required bool full, required int accent, required int tint, required void Function(int accent, int tint) onChanged}) =>
    showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      barrierColor: Colors.transparent,
      builder: (_) => ThemeGenerateSheet(full: full, accent: accent, tint: tint, onChanged: onChanged),
    );

class ThemeGenerateSheet extends StatefulWidget {
  const ThemeGenerateSheet({super.key, required this.full, required this.accent, required this.tint, required this.onChanged});
  final bool full;
  final int accent;
  final int tint;
  final void Function(int accent, int tint) onChanged;

  @override
  State<ThemeGenerateSheet> createState() => _ThemeGenerateSheetState();
}

class _ThemeGenerateSheetState extends State<ThemeGenerateSheet> {
  late int _accent = widget.accent;
  late int _tint = widget.tint;

  /// 现在在挑底色倾向（false＝强调色）。
  bool _onTint = false;
  bool _touched = false;

  void _set(int argb) {
    setState(() {
      _touched = true;
      if (_onTint) {
        _tint = argb;
      } else {
        _accent = argb;
      }
    });
    widget.onChanged(_accent, _tint);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final mq = MediaQuery.of(context);
    return Padding(
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
                  padding: const EdgeInsets.fromLTRB(Space.x4, 0, Space.x4, Space.x2),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(widget.full ? '从主色生成整套' : '换强调色', style: t.titleMedium),
                      const SizedBox(height: Space.x1),
                      Text(widget.full ? '挑一个强调色和一个底色倾向，算出一套协调的初稿（深浅不变，只换色相），之后可以逐项细调。' : '按钮、链接、选中、开关、光标这一组颜色跟着一起换，文字的深浅会自动调到看得清。', style: t.bodySmall?.copyWith(color: c.textMuted)),
                      if (widget.full) ...[
                        const SizedBox(height: Space.x3),
                        SegmentedButton<bool>(
                          key: const Key('gen-which'),
                          showSelectedIcon: false,
                          segments: const [
                            ButtonSegment(value: false, label: Text('强调色')),
                            ButtonSegment(value: true, label: Text('底色倾向')),
                          ],
                          selected: {_onTint},
                          onSelectionChanged: (s) => setState(() => _onTint = s.first),
                        ),
                      ],
                      const SizedBox(height: Space.x3),
                      ThemeColorPicker(key: ValueKey(_onTint), value: _onTint ? _tint : _accent, keyPrefix: 'gen', onChanged: _set),
                      ThemeSwatchRow(title: '常用色', colors: kThemeCommonColors, keyPrefix: 'gen-common', onPick: _set),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(Space.x2, 0, Space.x4, Space.x2),
                child: Row(
                  children: [
                    TextButton(key: const Key('gen-cancel'), onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
                    const Spacer(),
                    FilledButton(key: const Key('gen-apply'), onPressed: _touched ? () => Navigator.pop(context, true) : null, child: const Text('用这个')),
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
