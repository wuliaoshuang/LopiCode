// 设计约束（设置 › 界面 › 外观 里“背景图”那一行的挂载点）— 2026-11-26
// - 背景图是另一块功能。外观页在〔主题〕和〔代码字号〕之间给它留了一个位置，放什么由下面这个函数决定。
// - **现在返回 null＝没接上，外观页里不出现这一行**（不放点了没反应的东西）。
// - 接上的办法（合并背景图功能时只改这一行）：让它返回背景图那边的设置入口，比如
//     Widget? buildAppearanceBackgroundEntry(BuildContext context) => SettingsGroup(title: '背景图', children: [
//       SettingsRow(key: const Key('appearance-background'), title: '背景图', onTap: () => pushSettingsPage<void>(context, const BackdropSettingsScreen())),
//     ]);
//   或者直接返回背景图那边自己做好的一组控件。排在外观页的位置不用再动。
import 'package:material_ui/material_ui.dart';

/// 外观页里“背景图”那一组；null＝不显示。
Widget? buildAppearanceBackgroundEntry(BuildContext context) => null;
