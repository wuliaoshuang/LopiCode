// 设计约束（背景图片设置页下半部分的各组 · 390×844）
// - 规矩同 backdrop_settings_screen.dart 开头：一行只做一件事；数值用“名称 + 数值 / 减 · 滑杆 · 加”。
// - 遮罩颜色一行：第一个是“跟随主题”（主题底色的圆点，里面一个“自”字样的图标），后面是固定的几个颜色，
//   选中的那个外面套一圈强调色。圆点 32、点击区域 44。
// - “透出”四个开关默认都关：终端、代码、画布上的字本来就小，露出背景容易看不清——副标题里写明。
import 'package:lopicode/backdrop/backdrop_model.dart';
import 'package:lopicode/state/backdrop_state.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/backdrop_controls.dart';
import 'package:lopicode/ui/settings_widgets.dart';
import 'package:material_ui/material_ui.dart';

/// 自选遮罩颜色的候选（黑、白，加几种压得住图的深色和柔和的浅色）。
const List<int> kBackdropMaskSwatches = [0xFF000000, 0xFFFFFFFF, 0xFF1B2A4A, 0xFF2B1B3D, 0xFF12302A, 0xFF3A1420, 0xFFF6EAD8, 0xFFE6EEFB];

/// 显示：总开关、适配方式、平铺时一格多大。
class BackdropDisplayGroup extends StatelessWidget {
  const BackdropDisplayGroup({super.key, required this.settings, required this.look, required this.dark, required this.notifier});
  final BackdropSettings settings;
  final BackdropLook look;
  final bool dark;
  final BackdropNotifier notifier;

  @override
  Widget build(BuildContext context) => SettingsGroup(
    title: '显示',
    children: [
      SettingsSwitchRow(
        title: '显示背景图片',
        subtitle: '关掉只是先不显示，图和设置都留着',
        switchKey: const Key('bg-enabled'),
        value: settings.enabled,
        onChanged: (v) => notifier.update((s) => s.copyWith(enabled: v)),
      ),
      SettingsSegmentRow<BackdropFit>(
        title: '适配方式',
        subtitle: switch (look.fit) {
          BackdropFit.cover => '按裁剪的区域铺满屏幕',
          BackdropFit.contain => '整张图都露出来（不裁），四周空的地方是主题底色',
          BackdropFit.tile => '把裁剪的区域当一格，重复铺满',
        },
        segmentKey: const Key('bg-fit'),
        segments: const [(BackdropFit.cover, '铺满'), (BackdropFit.contain, '完整显示'), (BackdropFit.tile, '平铺')],
        selected: look.fit,
        onChanged: (v) => notifier.updateLook(
          dark: dark,
          change: (l) => l.copyWith(fit: v),
        ),
      ),
      if (look.fit == BackdropFit.tile)
        BackdropValueRow(
          id: 'bg-tile',
          title: '一格的宽度',
          value: look.tilePercent,
          min: kBackdropTileMin,
          max: 100,
          step: 5,
          format: (v) => '屏幕宽的 $v%',
          onChanged: (v, {required done}) => notifier.updateLook(
            dark: dark,
            change: (l) => l.copyWith(tilePercent: v),
            persist: done,
          ),
        ),
    ],
  );
}

/// 效果：遮罩、遮罩颜色、模糊、亮度、表面不透明度、恢复默认。
class BackdropEffectGroup extends StatelessWidget {
  const BackdropEffectGroup({super.key, required this.settings, required this.look, required this.dark, required this.notifier});
  final BackdropSettings settings;
  final BackdropLook look;
  final bool dark;
  final BackdropNotifier notifier;

  bool get _isDefault => look.maskFollowsTheme && look.maskOpacity == kBackdropMaskDefault && look.blur == 0 && look.brightness == 0 && settings.surfaceOpacity == kBackdropSurfaceDefault;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    void look_(BackdropLook Function(BackdropLook) change, bool done) => notifier.updateLook(dark: dark, change: change, persist: done);
    Widget swatch({required Key key, required Color color, required bool selected, required String tip, required VoidCallback onTap, IconData? icon}) => Tooltip(
      message: tip,
      child: InkResponse(
        key: key,
        radius: 22,
        onTap: onTap,
        child: SizedBox(
          width: 40,
          height: 44,
          child: Center(
            child: Container(
              width: 32,
              height: 32,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: selected ? c.accent : Colors.transparent, width: 2),
              ),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: Border.all(color: c.border),
                ),
                child: icon == null ? null : Icon(icon, size: 14, color: c.textMuted),
              ),
            ),
          ),
        ),
      ),
    );
    return SettingsGroup(
      title: '效果',
      footer: '遮罩越深字越清楚、图越淡。表面指气泡、卡片和输入框：越低越透。',
      children: [
        BackdropValueRow(
          id: 'bg-mask',
          title: '遮罩',
          value: look.maskOpacity,
          min: 0,
          max: 100,
          step: 5,
          format: (v) => '$v%',
          onChanged: (v, {required done}) => look_((l) => l.copyWith(maskOpacity: v), done),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.x4, Space.x3, Space.x4, Space.x2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(child: Text('遮罩颜色', style: t.bodyLarge)),
                  Text(
                    look.maskFollowsTheme ? '跟随主题' : '自选',
                    key: const Key('bg-mask-color-value'),
                    style: t.bodyMedium?.copyWith(color: c.textMuted),
                  ),
                ],
              ),
              const SizedBox(height: Space.x1),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    swatch(
                      key: const Key('bg-mask-theme'),
                      color: c.bg,
                      selected: look.maskFollowsTheme,
                      tip: '跟随主题底色',
                      icon: Icons.auto_awesome_outlined,
                      onTap: () => look_((l) => l.copyWith(maskFollowsTheme: true), true),
                    ),
                    for (final v in kBackdropMaskSwatches)
                      swatch(
                        key: Key('bg-mask-${v.toRadixString(16)}'),
                        color: Color(v),
                        selected: !look.maskFollowsTheme && look.maskColor == v,
                        tip: '用这个颜色',
                        onTap: () => look_((l) => l.copyWith(maskFollowsTheme: false, maskColor: v), true),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        BackdropValueRow(
          id: 'bg-blur',
          title: '模糊',
          value: look.blur,
          min: 0,
          max: kBackdropBlurMax,
          step: 2,
          format: (v) => v == 0 ? '不模糊' : '$v',
          onChanged: (v, {required done}) => look_((l) => l.copyWith(blur: v), done),
        ),
        BackdropValueRow(
          id: 'bg-brightness',
          title: '亮度',
          value: look.brightness,
          min: -kBackdropBrightnessRange,
          max: kBackdropBrightnessRange,
          step: 5,
          format: (v) => v == 0 ? '原样' : (v > 0 ? '提亮 $v%' : '变暗 ${-v}%'),
          onChanged: (v, {required done}) => look_((l) => l.copyWith(brightness: v), done),
        ),
        BackdropValueRow(
          id: 'bg-surface',
          title: '表面不透明度',
          value: settings.surfaceOpacity,
          min: kBackdropSurfaceMin,
          max: 100,
          step: 5,
          format: (v) => '$v%',
          onChanged: (v, {required done}) => notifier.update((s) => s.copyWith(surfaceOpacity: v), persist: done),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.x1),
          child: Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              key: const Key('bg-effect-reset'),
              onPressed: _isDefault
                  ? null
                  : () {
                      notifier.updateLook(
                        dark: dark,
                        change: (l) => l.copyWith(maskFollowsTheme: true, maskOpacity: kBackdropMaskDefault, blur: 0, brightness: 0),
                        persist: false,
                      );
                      notifier.update((s) => s.copyWith(surfaceOpacity: kBackdropSurfaceDefault));
                    },
              child: const Text('恢复默认效果'),
            ),
          ),
        ),
      ],
    );
  }
}

/// 范围 + 透出。
class BackdropScopeGroups extends StatelessWidget {
  const BackdropScopeGroups({super.key, required this.settings, required this.notifier});
  final BackdropSettings settings;
  final BackdropNotifier notifier;

  @override
  Widget build(BuildContext context) {
    Widget row(BackdropArea a, String title, String subtitle) =>
        SettingsSwitchRow(title: title, subtitle: subtitle, switchKey: Key('bg-area-${a.name}'), value: settings.area(a), onChanged: (v) => notifier.update((s) => s.withArea(a, v)));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SettingsGroup(title: '范围', footer: '两个都关＝哪里都不显示。', children: [row(BackdropArea.chat, '聊天页', '对话内容后面'), row(BackdropArea.pages, '其它页面', '项目列表、文件、设置等主要页面')]),
        SettingsGroup(
          title: '透出背景',
          footer: '这几处的字小而密，默认用实底色保证看得清。打开后它们的底色会按“表面不透明度”变透。',
          children: [
            row(BackdropArea.terminal, '终端', '终端的底色变透'),
            row(BackdropArea.code, '代码区', '编辑器、看代码、代码块的底色变透'),
            row(BackdropArea.blocks, '积木画布', '积木编辑器的画布变透'),
            row(BackdropArea.lowcode, '低代码画布', '页面搭建的画布四周变透（页面本身不变）'),
          ],
        ),
      ],
    );
  }
}
