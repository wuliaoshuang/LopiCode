// 设计约束（设置的四个小二级页：权限与执行 / 对话显示 / 外观 / 额度与余额（多渠道时）· 390×844）— 2026-11-24
// - 都用 settings_widgets.dart 的组和行：组有小标题，说明只在行的副标题或组的脚注里，一行只做一件事。
// - 权限与执行：〔权限〕新对话的权限（跳转行，点开底部弹层选档；选“完全权限”要先确认）
//               〔执行〕连续执行多少步后问我（跳转行，底部弹层选档）· 上下文快满时自动压缩（开关，副标题写明代价）
// - 对话显示：〔新对话〕开场建议（开关）〔回复里〕用量（开关）· 思考过程（开关）
// - 外观：三行单选（跟随系统 / 浅色 / 深色），点了立刻生效。
// - 额度与余额：只有不止一个 DeepSeek 官方渠道时才有这一页，一行一个渠道，点进各自的额度页。
// - 这些页面可能被留在后面（上面又盖了一页），所以各自订阅自己那几个设置键，回来时数是新的。
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lopicode/agent/agent_tools.dart';
import 'package:lopicode/agent/quota.dart';
import 'package:lopicode/core/stores.dart';
import 'package:lopicode/state/app_providers.dart';
import 'package:lopicode/state/models_state.dart';
import 'package:lopicode/state/ui_prefs.dart';
import 'package:lopicode/ui/app_ref.dart';
import 'package:lopicode/ui/chat_panels.dart';
import 'package:lopicode/ui/provider_icon.dart';
import 'package:lopicode/ui/settings_chat.dart';
import 'package:lopicode/ui/settings_code_font.dart';
import 'package:lopicode/ui/settings_quota.dart';
import 'package:lopicode/ui/settings_widgets.dart';
import 'package:material_ui/material_ui.dart';

String themeModeLabel(AppThemeMode mode) => switch (mode) {
  AppThemeMode.system => '跟随系统',
  AppThemeMode.light => '浅色',
  AppThemeMode.dark => '深色',
};

/// 设置 › Agent › 权限与执行。
class AgentBehaviorScreen extends ConsumerWidget {
  const AgentBehaviorScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    for (final k in const [SettingKeys.defaultPermission, SettingKeys.agentMaxSteps, SettingKeys.agentAutoCompact]) {
      ref.watch(settingRevProvider(k));
    }
    final s = appOf(context).settings;
    final level = PermissionLevel.byId(s.getString(SettingKeys.defaultPermission, 'workspace'));
    final limit = stepLimitOf(s);
    return SettingsPage(
      title: '权限与执行',
      children: [
        SettingsGroup(
          title: '权限',
          footer: '只决定新对话一开始用哪一档；每段对话里还可以单独换。',
          children: [
            SettingsRow(
              key: const Key('settings-permission'),
              icon: Icons.verified_user_outlined,
              title: '新对话的权限',
              value: level.label,
              onTap: () async {
                final picked = await showModalBottomSheet<PermissionLevel>(
                  context: context,
                  builder: (_) => PermissionSheet(current: level, title: '新对话默认用哪档权限'),
                );
                if (picked == null || picked == level || !context.mounted) return;
                if (picked == PermissionLevel.full && !await confirmFullPermission(context)) return;
                await s.set(SettingKeys.defaultPermission, picked.id);
              },
            ),
          ],
        ),
        SettingsGroup(
          title: '执行',
          children: [
            SettingsRow(
              key: const Key('settings-step-limit'),
              icon: Icons.format_list_numbered,
              title: '连续执行多少步后问我',
              subtitle: '到了会停下来问要不要继续；自动化任务到了直接停',
              value: '$limit 步',
              onTap: () async {
                final picked = await showModalBottomSheet<int>(
                  context: context,
                  builder: (_) => StepLimitSheet(current: limit),
                );
                if (picked != null && picked != limit) await s.set(SettingKeys.agentMaxSteps, picked);
              },
            ),
            SettingsSwitchRow(
              icon: Icons.compress,
              title: '上下文快满时自动压缩',
              subtitle: '把较早的对话压成摘要再继续。会多调用一次模型、多花一点额度',
              switchKey: const Key('settings-auto-compact'),
              value: s.getBool(SettingKeys.agentAutoCompact, true),
              onChanged: (v) => s.set(SettingKeys.agentAutoCompact, v),
            ),
          ],
        ),
      ],
    );
  }
}

/// 设置 › 界面 › 对话显示。
class ChatDisplayScreen extends ConsumerWidget {
  const ChatDisplayScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    for (final k in const [SettingKeys.chatSuggestions, SettingKeys.chatUsage, SettingKeys.chatThinking, SettingKeys.chatAutoImages]) {
      ref.watch(settingRevProvider(k));
    }
    final s = appOf(context).settings;
    return SettingsPage(
      title: '对话显示',
      children: [
        SettingsGroup(
          title: '新对话',
          children: [
            SettingsSwitchRow(
              icon: Icons.lightbulb_outline,
              title: '在新对话里显示开场建议',
              subtitle: '空白对话中间给几条可以直接点的开头',
              switchKey: const Key('settings-suggestions'),
              value: s.getBool(SettingKeys.chatSuggestions, true),
              onChanged: (v) => s.set(SettingKeys.chatSuggestions, v),
            ),
          ],
        ),
        SettingsGroup(
          title: '回复里',
          footer: '只影响显示，不影响 Agent 怎么干活，也不影响费用。',
          children: [
            SettingsSwitchRow(
              icon: Icons.data_usage,
              title: '在回复下方显示用量',
              subtitle: '每轮的 tokens、缓存命中率和用时',
              switchKey: const Key('settings-usage'),
              value: s.getBool(SettingKeys.chatUsage, true),
              onChanged: (v) => s.set(SettingKeys.chatUsage, v),
            ),
            SettingsSwitchRow(
              icon: Icons.psychology_alt_outlined,
              title: '显示思考过程',
              subtitle: '模型给了思考内容时，在聊天里折成一行，点开看',
              switchKey: const Key('settings-thinking'),
              value: s.getBool(SettingKeys.chatThinking, true),
              onChanged: (v) => s.set(SettingKeys.chatThinking, v),
            ),
          ],
        ),
        SettingsGroup(
          title: '消息里的图片',
          footer: '关着时，消息里的网络图片先显示成一小块，点一下才去下载——这样模型写出来的图片地址不会悄悄联网。工作区里的图片不受影响，一直直接显示。',
          children: [
            SettingsSwitchRow(
              icon: Icons.image_outlined,
              title: '自动加载网络图片',
              subtitle: '只加载 https 图片，单张不超过 5MB',
              switchKey: const Key('settings-auto-images'),
              value: s.getBool(SettingKeys.chatAutoImages, false),
              onChanged: (v) => s.set(SettingKeys.chatAutoImages, v),
            ),
          ],
        ),
      ],
    );
  }
}

/// 设置 › 界面 › 外观。
class AppearanceScreen extends ConsumerWidget {
  const AppearanceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    return SettingsPage(
      title: '外观',
      children: [
        SettingsGroup(
          title: '颜色模式',
          footer: '“跟随系统”会跟着手机的深色模式开关自动切换。',
          children: [
            for (final m in AppThemeMode.values)
              SettingsChoiceRow(key: Key('appearance-${m.name}'), title: themeModeLabel(m), selected: m == mode, onTap: () => ref.read(themeModeProvider.notifier).set(m)),
          ],
        ),
        const CodeFontGroup(),
      ],
    );
  }
}

/// 设置 › 模型 › 额度与余额（有不止一个 DeepSeek 官方渠道时）：先选渠道。
class QuotaChannelsScreen extends ConsumerWidget {
  const QuotaChannelsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(modelsProvider);
    final app = appOf(context);
    final channels = [
      for (final ch in app.models.channels)
        if (isDeepSeekOfficial(ch.baseUrl)) ch,
    ];
    return SettingsPage(
      title: '额度与余额',
      children: [
        SettingsGroup(
          title: 'DeepSeek 官方渠道',
          iconRows: true,
          footer: '余额和额度上限按渠道分开算。别的服务商查不了余额，所以不在这里。',
          children: [
            for (final ch in channels)
              QuotaBuilder(
                builder: (context, _) {
                  final q = app.quota.quotaOf(ch.id);
                  return SettingsRow(
                    key: Key('settings-quota-${ch.id}'),
                    leading: ProviderIcon.forBaseUrl(ch.baseUrl, size: 32),
                    title: ch.name,
                    value: q == null ? '未设上限' : '${formatMoney(q.currency, q.limit)} · 已用 ${q.percent}%',
                    onTap: () => pushSettingsPage<void>(context, QuotaScreen(channelId: ch.id)),
                  );
                },
              ),
          ],
        ),
      ],
    );
  }
}
