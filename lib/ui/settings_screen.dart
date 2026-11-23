// 设计约束（设置 · 390×844）
// - 设置首页只是一张目录：三组（AI / 能力 / 通用），每行一个入口，下面一句小字说现在的状态。
// - 具体的表单都在下一级页面里，这一页不放输入框。
// - “通用”里有外观、关于，和一行进“第三方声明”（随包带的开源组件、许可证全文、来源和校验值）。
import 'package:lopicode/agent/agent_tools.dart';
import 'package:lopicode/agent/web_search.dart';
import 'package:lopicode/app_services.dart';
import 'package:lopicode/core/project_store.dart';
import 'package:lopicode/core/stores.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/automation_screen.dart';
import 'package:lopicode/ui/chat_panels.dart';
import 'package:lopicode/ui/settings_agent.dart';
import 'package:lopicode/ui/settings_ai.dart';
import 'package:lopicode/ui/shell.dart';
import 'package:lopicode/ui/third_party_screen.dart';
import 'package:lopicode/ui/widgets.dart';
import 'package:material_ui/material_ui.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, this.workspace});

  /// 从哪个工作区进来的（技能页据此列出这个工作区自己的技能）。
  final Project? workspace;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    void go(Widget page) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
    final channels = app.models.channels;
    final modelCount = channels.fold<int>(0, (n, ch) => n + ch.models.length);
    final level = PermissionLevel.byId(app.settings.getString(SettingKeys.defaultPermission, 'workspace'));
    final subOn = app.settings.getBool(SettingKeys.subagentEnabled, true);
    final teamOn = app.settings.getBool(SettingKeys.teamEnabled);
    return Scaffold(
      appBar: const ShellAppBar(title: '设置', subtitle: 'LopiCode'),
      body: ListView(
        padding: const EdgeInsets.only(bottom: Space.x8),
        children: [
          const SectionLabel('AI'),
          SettingsRow(
            key: const Key('settings-channels'),
            icon: Icons.hub_outlined,
            title: '模型与渠道',
            value: channels.isEmpty ? '还没添加' : '${channels.length} 个渠道 · $modelCount 个模型',
            onTap: () => go(const ChannelsScreen()),
          ),
          SettingsRow(
            key: const Key('settings-personalize'),
            icon: Icons.face_outlined,
            title: '个性化',
            value: '个人偏好 · Agent 预设（默认：${app.presets.byId(app.presets.defaultId).name}）',
            onTap: () => go(const PersonalizeScreen()),
          ),
          const SectionLabel('能力'),
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
              await app.settings.set(SettingKeys.defaultPermission, picked.id);
              app.touch();
            },
          ),
          SettingsRow(
            key: const Key('settings-subagents'),
            icon: Icons.account_tree_outlined,
            title: '子代理与团队',
            value: '子代理${subOn ? '开' : '关'} · 团队${teamOn ? '开' : '关'}',
            onTap: () => go(const SubagentSettingsScreen()),
          ),
          SettingsRow(
            key: const Key('settings-automations'),
            icon: Icons.event_repeat,
            title: '自动化任务',
            value: app.automations.items.isEmpty ? '还没有任务' : '${app.automations.items.length} 个任务',
            onTap: () => go(AutomationListScreen(workspace: workspace)),
          ),
          FutureBuilder<WebSearchConfig?>(
            future: WebSearchConfig.load(app.settings, app.secrets),
            builder: (context, snap) => SettingsRow(
              key: const Key('settings-search'),
              icon: Icons.travel_explore,
              title: '联网搜索',
              value: snap.data == null ? '未配置（Agent 没有搜索工具）' : '已配置',
              onTap: () => go(const WebSearchSettingsScreen()),
            ),
          ),
          SettingsRow(
            key: const Key('settings-skills'),
            icon: Icons.menu_book_outlined,
            title: '技能',
            value: '写给 Agent 的做事说明书',
            onTap: () => go(SkillsScreen(workspace: workspace)),
          ),
          const SectionLabel('通用'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.x4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('外观', style: t.bodyMedium),
                const SizedBox(height: Space.x2),
                SegmentedButton<ThemeMode>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: ThemeMode.system, label: Text('跟随系统')),
                    ButtonSegment(value: ThemeMode.light, label: Text('浅色')),
                    ButtonSegment(value: ThemeMode.dark, label: Text('深色')),
                  ],
                  selected: {app.themeMode},
                  onSelectionChanged: (s) => app.setThemeMode(s.first),
                ),
                const SizedBox(height: Space.x4),
                Text(
                  'LopiCode 1.0.0\n在手机上通过 Agent 完成代码项目：写代码、终端、网页预览、低代码搭建、远程打包 APK。',
                  style: t.bodySmall?.copyWith(color: c.textMuted, height: 1.6),
                ),
              ],
            ),
          ),
          SettingsRow(
            key: const Key('settings-third-party'),
            icon: Icons.gavel_outlined,
            title: '第三方声明',
            value: '随安装包带的开源组件和许可证',
            onTap: () => go(const ThirdPartyScreen()),
          ),
        ],
      ),
    );
  }
}

/// 设置目录里的一行：图标 + 标题 + 一句状态 + 箭头。
class SettingsRow extends StatelessWidget {
  const SettingsRow({super.key, required this.icon, required this.title, required this.value, required this.onTap});
  final IconData icon;
  final String title;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    leading: Icon(icon),
    title: Text(title),
    subtitle: Text(value, maxLines: 1, overflow: TextOverflow.ellipsis),
    trailing: const Icon(Icons.chevron_right),
    onTap: onTap,
  );
}
