// 设计约束（设置 · 一级页 · 390×844）— 2026-11-24 霜霜：“设置页太乱，分门别类做好，参考 dsh-Go”
// 内容分级：
// - 最重要：现在用的是哪个模型、花了多少、运行环境装没装 → 顶部一张概况卡（只读状态，点一下进对应的页）。
// - 其次：分类入口。这一页只放入口，不放开关、不放输入框、不放说明段落；具体设置都在二级页。
// - 最弱：版本说明 → “关于”组的脚注。
// 分类（一类东西只在一处）：
//   模型　　　　模型与渠道 · 额度与余额（只有 DeepSeek 官方渠道才有）
//   Agent 　　　权限与执行 · 个性化 · 子代理与团队
//   能力　　　　联网搜索 · 技能 · 自动化任务
//   界面　　　　对话显示 · 外观
//   运行与打包　运行环境 · SSH 构建机
//   当前工作区　项目规则（只对这个工作区生效；组标题写明是哪个工作区。没打开工作区时这一行灰掉并说明）
//   关于　　　　第三方声明 · 错误日志
// 每个入口同一个样子：图标 + 名称 + 右边一句很短的当前状态 + 箭头，行高 56。尺寸见 settings_widgets.dart。
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lopicode/agent/agent_tools.dart';
import 'package:lopicode/agent/quota.dart';
import 'package:lopicode/agent/web_search.dart';
import 'package:lopicode/core/project_store.dart';
import 'package:lopicode/core/stores.dart';
import 'package:lopicode/project_session.dart';
import 'package:lopicode/runtime/runtime_screen.dart';
import 'package:lopicode/ssh/ssh_config.dart';
import 'package:lopicode/ssh/ssh_connect_screen.dart';
import 'package:lopicode/state/app_providers.dart';
import 'package:lopicode/state/automations_state.dart';
import 'package:lopicode/state/config_providers.dart';
import 'package:lopicode/state/models_state.dart';
import 'package:lopicode/state/presets_state.dart';
import 'package:lopicode/state/runtime_state.dart';
import 'package:lopicode/state/ui_prefs.dart';
import 'package:lopicode/state/workspace_conversations.dart';
import 'package:lopicode/ui/app_ref.dart';
import 'package:lopicode/ui/automation_screen.dart';
import 'package:lopicode/ui/error_guard.dart';
import 'package:lopicode/ui/settings_agent.dart';
import 'package:lopicode/ui/settings_ai.dart';
import 'package:lopicode/ui/settings_overview.dart';
import 'package:lopicode/ui/settings_pages.dart';
import 'package:lopicode/ui/settings_quota.dart';
import 'package:lopicode/ui/settings_widgets.dart';
import 'package:lopicode/ui/third_party_screen.dart';
import 'package:material_ui/material_ui.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key, this.workspace, this.session});

  /// 当前打开的工作区的会话（项目规则是按工作区存的，要靠它读写）。
  final ProjectSession? session;

  /// 从哪个工作区进来的（技能页据此列出这个工作区自己的技能）。
  final Project? workspace;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref
      ..watch(settingsAnyRevProvider)
      ..watch(modelsProvider)
      ..watch(skillFilesRevProvider)
      ..watch(sshConfigRevProvider)
      ..watch(webSearchRevProvider);
    final automationCount = ref.watch(automationsProvider.select((s) => s.items.length));
    final app = appOf(context);
    void go(Widget page) => pushSettingsPage<void>(context, page);
    final channels = app.models.channels;
    final modelCount = channels.fold<int>(0, (n, ch) => n + ch.models.length);
    final level = PermissionLevel.byId(app.settings.getString(SettingKeys.defaultPermission, 'workspace'));
    final subOn = app.settings.getBool(SettingKeys.subagentEnabled, true);
    final teamOn = app.settings.getBool(SettingKeys.teamEnabled);
    final ssh = SshConfig.load(app.settings);
    final deepseek = [
      for (final ch in channels)
        if (isDeepSeekOfficial(ch.baseUrl)) ch,
    ];
    final wsName = session?.project.name ?? workspace?.name;

    return SettingsPage(
      title: '设置',
      listKey: const Key('settings-list'),
      children: [
        SettingsOverviewCard(
          onModels: () => go(const ChannelsScreen()),
          onRuntime: () => go(RuntimeScreen(projectDir: workspace?.dir)),
        ),
        SettingsGroup(
          title: '模型',
          iconRows: true,
          children: [
            SettingsRow(
              key: const Key('settings-channels'),
              icon: Icons.hub_outlined,
              title: '模型与渠道',
              value: channels.isEmpty ? '还没添加' : '${channels.length} 渠道 · $modelCount 模型',
              onTap: () => go(const ChannelsScreen()),
            ),
            if (deepseek.isNotEmpty)
              QuotaBuilder(
                builder: (context, _) {
                  final q = deepseek.length == 1 ? app.quota.quotaOf(deepseek.single.id) : null;
                  return SettingsRow(
                    key: const Key('settings-quota'),
                    icon: Icons.speed_outlined,
                    title: '额度与余额',
                    value: deepseek.length > 1 ? '${deepseek.length} 个渠道' : (q == null ? '未设上限' : '已用 ${q.percent}%'),
                    onTap: () => go(deepseek.length == 1 ? QuotaScreen(channelId: deepseek.single.id) : const QuotaChannelsScreen()),
                  );
                },
              ),
          ],
        ),
        SettingsGroup(
          title: 'Agent',
          children: [
            SettingsRow(key: const Key('settings-agent'), icon: Icons.verified_user_outlined, title: '权限与执行', value: level.label, onTap: () => go(const AgentBehaviorScreen())),
            SettingsRow(
              key: const Key('settings-personalize'),
              icon: Icons.face_outlined,
              title: '个性化',
              value: ref.watch(presetsProvider).defaultPreset.name,
              onTap: () => go(const PersonalizeScreen()),
            ),
            SettingsRow(
              key: const Key('settings-subagents'),
              icon: Icons.account_tree_outlined,
              title: '子代理与团队',
              value: '子代理${subOn ? '开' : '关'} · 团队${teamOn ? '开' : '关'}',
              onTap: () => go(const SubagentSettingsScreen()),
            ),
          ],
        ),
        SettingsGroup(
          title: '能力',
          iconRows: true,
          children: [
            FutureBuilder<WebSearchConfig?>(
              future: WebSearchConfig.load(app.settings, app.secrets),
              builder: (context, snap) =>
                  SettingsRow(key: const Key('settings-search'), icon: Icons.travel_explore, title: '联网搜索', value: snap.data == null ? '未配置' : '已配置', onTap: () => go(const WebSearchSettingsScreen())),
            ),
            SettingsRow(
              key: const Key('settings-skills'),
              icon: Icons.menu_book_outlined,
              title: '技能',
              onTap: () => go(SkillsScreen(workspace: workspace)),
            ),
            SettingsRow(
              key: const Key('settings-automations'),
              icon: Icons.event_repeat,
              title: '自动化任务',
              value: automationCount == 0 ? '还没有' : '$automationCount 个任务',
              onTap: () => go(AutomationListScreen(workspace: workspace)),
            ),
          ],
        ),
        SettingsGroup(
          title: '界面',
          children: [
            SettingsRow(key: const Key('settings-chat'), icon: Icons.chat_bubble_outline, title: '对话显示', onTap: () => go(const ChatDisplayScreen())),
            SettingsRow(key: const Key('settings-appearance'), icon: Icons.contrast, title: '外观', value: themeModeLabel(ref.watch(themeModeProvider)), onTap: () => go(const AppearanceScreen())),
          ],
        ),
        SettingsGroup(
          title: '运行与打包',
          iconRows: true,
          children: [
            Consumer(
              builder: (context, ref, _) => SettingsRow(
                key: const Key('settings-runtime'),
                icon: Icons.memory,
                title: '运行环境',
                value: runtimeStateLabel(ref.watch(runtimeProvider)),
                onTap: () => go(RuntimeScreen(projectDir: workspace?.dir)),
              ),
            ),
            SettingsRow(
              key: const Key('settings-ssh'),
              icon: Icons.dns_outlined,
              title: 'SSH 构建机',
              value: ssh.isComplete ? ssh.display : '未设置',
              onTap: () => go(const SshConnectScreen(submitLabel: '保存')),
            ),
          ],
        ),
        SettingsGroup(
          title: wsName == null ? '当前工作区' : '当前工作区 · $wsName',
          iconRows: true,
          footer: session == null ? '项目规则是按工作区存的：打开一个工作区后，才能写它的规则。' : '这一组只管这个工作区，换一个工作区要另外设。',
          children: [
            if (session == null)
              const SettingsRow(key: Key('settings-rules'), icon: Icons.rule, title: '项目规则', enabled: false)
            else
              Consumer(
                builder: (context, ref, _) => SettingsRow(
                  key: const Key('settings-rules'),
                  icon: Icons.rule,
                  title: '项目规则',
                  value: ref.watch(conversationsProvider(session!).select((v) => v.projectRules)).isEmpty ? '未设置' : '已设置',
                  onTap: () => go(ProjectRulesScreen(session: session!)),
                ),
              ),
          ],
        ),
        SettingsGroup(
          title: '关于',
          footer: 'LopiCode 1.0.0 · 在手机上通过 Agent 完成代码项目：写代码、终端、网页预览、低代码搭建、远程打包 APK。',
          children: [
            SettingsRow(key: const Key('settings-third-party'), icon: Icons.gavel_outlined, title: '第三方声明', onTap: () => go(const ThirdPartyScreen())),
            SettingsRow(key: const Key('settings-error-log'), icon: Icons.bug_report_outlined, title: '错误日志', onTap: () => go(const ErrorLogScreen())),
          ],
        ),
      ],
    );
  }
}
