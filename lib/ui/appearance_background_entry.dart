// 设计约束（设置 › 界面 › 外观 里“背景图片”那一行）— 2026-11-26
// - 外观页在〔主题〕和〔代码字号〕之间放这一组，只有一行：名称“背景图片”，右侧一句当前状态
//   （未设置 / 已启用 / 已关闭），点了进背景图片设置页。具体怎么设都在那一页里，这里不放开关。
// - 状态文字订阅 backdropStatusProvider：在设置页里改完退回来，这一行跟着变。
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lopicode/state/backdrop_state.dart';
import 'package:lopicode/ui/backdrop_settings_screen.dart';
import 'package:lopicode/ui/settings_widgets.dart';
import 'package:material_ui/material_ui.dart';

/// 外观页里“背景图片”那一组。
Widget? buildAppearanceBackgroundEntry(BuildContext context) => SettingsGroup(
  title: '背景',
  children: [
    Consumer(
      builder: (context, ref, _) =>
          SettingsRow(key: const Key('appearance-background'), title: '背景图片', value: ref.watch(backdropStatusProvider), onTap: () => pushSettingsPage<void>(context, const BackdropSettingsScreen())),
    ),
  ],
);
