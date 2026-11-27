// 设计约束（设置 › 能力 › 积木库的手写代码 · 390×844）— 2026-11-27 第四轮
// - 这一页只有一件事：一个开关“允许库里的手写代码”。全应用一个，默认关。
// - 开关上面先把话说清楚（它意味着什么、没隔开的是什么）；打开要过一道确认框，框里再说一遍、按钮用危险色。
// - 关掉不用确认，但是说明里写着“关掉会把所有已经确认过的库一起作废”。
// - 颜色全取主题值。
import 'dart:async';

import 'package:lopicode/backend/lib_native_trust.dart';
import 'package:lopicode/ui/lib_import_sheet.dart';
import 'package:lopicode/ui/settings_widgets.dart';
import 'package:lopicode/ui/widgets.dart';
import 'package:material_ui/material_ui.dart';

class LibNativeSettingsScreen extends StatefulWidget {
  const LibNativeSettingsScreen({super.key});

  @override
  State<LibNativeSettingsScreen> createState() => _LibNativeSettingsScreenState();
}

class _LibNativeSettingsScreenState extends State<LibNativeSettingsScreen> {
  Future<void> _set(bool on) async {
    if (on) {
      final yes = await confirmDialog(context, title: '允许库里的手写代码吗', message: '$kLibNativeRisk\n\n打开以后，带手写代码的库还要一个一个地看过代码、单独确认才能用；库里的手写代码变了，要重新确认。', confirmLabel: '我明白，打开', danger: true);
      if (!yes) return;
    }
    await LibNativeTrust.instance.setEnabled(on);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) => SettingsPage(
    title: '积木库的手写代码',
    children: [
      SettingsGroup(
        footer: '$kLibNativeRisk\n\n关着的时候：带手写代码的库不能导入，项目里已经有的也用不了。\n关掉会把所有已经确认过的库一起作废，再打开要重新一个一个确认。',
        children: [
          SettingsSwitchRow(
            switchKey: const Key('lib-native-switch'),
            title: '允许库里的手写代码',
            subtitle: LibNativeTrust.instance.enabled ? '开着：每个库还要单独看过、确认' : '关着（默认）',
            value: LibNativeTrust.instance.enabled,
            onChanged: (v) => unawaited(_set(v)),
          ),
        ],
      ),
    ],
  );
}
