// 设计约束（设置 › Agent › 后台与通知 · 390×844）— 2026-11-25 后台保活
// 层级：
// - 最重要：两个开关——〔后台〕Agent 干活时保持后台运行；〔通知〕做完时通知我。各占一行，代价 / 效果写在副标题。
// - 其次：通知权限现在给没给（只读状态 + 点了去处理）。没给时保活照常，只是看不到进度和提醒——写在脚注。
// - 最弱：系统自己的省电规则应用管不了，只给一个跳到系统设置的入口，并如实说明。
// 一行只做一件事；说明只在副标题和组脚注里。从系统设置回来（应用重新到前台）时重新问一次权限。
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lopicode/core/stores.dart';
import 'package:lopicode/state/app_providers.dart';
import 'package:lopicode/state/keep_alive_state.dart';
import 'package:lopicode/ui/app_ref.dart';
import 'package:lopicode/ui/settings_widgets.dart';
import 'package:material_ui/material_ui.dart';

/// 一级页那一行右边的一句当前状态。
String backgroundSettingsLabel(SettingsStore s) {
  final keep = s.getBool(SettingKeys.agentKeepAlive, true);
  final notify = s.getBool(SettingKeys.agentNotifyDone, true);
  return '保活${keep ? '开' : '关'} · 通知${notify ? '开' : '关'}';
}

class BackgroundSettingsScreen extends ConsumerStatefulWidget {
  const BackgroundSettingsScreen({super.key});

  @override
  ConsumerState<BackgroundSettingsScreen> createState() => _BackgroundSettingsScreenState();
}

class _BackgroundSettingsScreenState extends ConsumerState<BackgroundSettingsScreen> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    // 去系统设置改完权限再回来：重新问一次
    _lifecycle = AppLifecycleListener(onResume: () => ref.invalidate(notificationsAllowedProvider));
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  void _say(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _fixPermission(bool? allowed) async {
    final host = appOf(context).keepAlive.host;
    if (allowed == false) {
      // 先请系统弹询问；被拒绝过的话系统不会再弹，所以同时给出去系统设置的路
      await host.requestNotifications();
    }
    final opened = await host.openNotificationSettings();
    if (!opened) _say('打不开系统的通知设置。请到 系统设置 › 应用 › LopiCode › 通知 里手动打开。');
    if (mounted) ref.invalidate(notificationsAllowedProvider);
  }

  Future<void> _openAppSettings() async {
    final opened = await appOf(context).keepAlive.host.openAppSettings();
    if (!opened) _say('打不开系统的应用设置。请到 系统设置 › 应用 › LopiCode 里手动找。');
  }

  @override
  Widget build(BuildContext context) {
    for (final k in const [SettingKeys.agentKeepAlive, SettingKeys.agentNotifyDone]) {
      ref.watch(settingRevProvider(k));
    }
    final s = appOf(context).settings;
    final allowed = ref.watch(notificationsAllowedProvider).value;
    return SettingsPage(
      title: '后台与通知',
      children: [
        SettingsGroup(
          title: '后台',
          footer: 'Agent 一停，这条通知就自己消失。通知上有“停止”，点了和在聊天页里点停止一样。',
          children: [
            SettingsSwitchRow(
              icon: Icons.all_inclusive,
              title: 'Agent 干活时保持后台运行',
              subtitle: '切到别的应用或锁屏时，通知栏挂一条进度，系统不容易把它停掉',
              switchKey: const Key('settings-keep-alive'),
              value: s.getBool(SettingKeys.agentKeepAlive, true),
              onChanged: (v) => s.set(SettingKeys.agentKeepAlive, v),
            ),
          ],
        ),
        SettingsGroup(
          title: '通知',
          footer: '没允许通知也照样保持后台运行，只是看不到进度和提醒。\n手机锁屏设了“隐藏敏感内容”时，锁屏上只显示“Agent 正在干活”，不显示文件名和命令。',
          children: [
            SettingsSwitchRow(
              icon: Icons.notifications_active_outlined,
              title: '做完时通知我',
              subtitle: '做完了、出错了、或者在等你确认时提醒一声；你正看着应用时不提醒',
              switchKey: const Key('settings-notify-done'),
              value: s.getBool(SettingKeys.agentNotifyDone, true),
              onChanged: (v) => s.set(SettingKeys.agentNotifyDone, v),
            ),
            SettingsRow(
              key: const Key('settings-notification-permission'),
              icon: Icons.verified_outlined,
              title: '通知权限',
              value: switch (allowed) {
                true => '已允许',
                false => '没允许',
                null => '这台设备上查不到',
              },
              valueKey: const Key('settings-notification-permission-value'),
              onTap: allowed == null ? null : () => _fixPermission(allowed),
            ),
          ],
        ),
        SettingsGroup(
          title: '系统的省电规则',
          footer:
              '有些手机（比如小米）会按自己的省电规则停掉后台应用，应用自己拦不住。'
              '要更稳，可以在系统的应用设置里把 LopiCode 的“省电策略”改成“无限制”，并打开“自启动”。',
          children: [SettingsRow(key: const Key('settings-open-app-settings'), icon: Icons.battery_saver_outlined, title: '打开系统的应用设置', onTap: _openAppSettings)],
        ),
      ],
    );
  }
}
