// 设计约束（设置 · 390×844）— 2026-11-23 按霜霜的参考图（workspace/user/files/88185_1_u07b.jpg）改版
// - 浅灰底（canvas）。顶部：左上悬浮的白色圆形返回按钮，标题“设置”居中。
// - 内容是一张张白色大圆角卡片（28），卡片左右各留 16。
// - 第一张是概况卡，版式照参考图：左边大字 + 一行小字，右边一句状态，下面一根进度条；两段之后一条分隔线和一个蓝色文字入口。
//   我们放的是真实状态：①新对话用的模型（配好 = 蓝条满，没配 = 灰条）；②运行环境 Ubuntu（装好 = 满，下载中 = 真实进度）。
// - 其余卡片按 AI / 能力 / 通用 / 关于 分组，每行一件事：左线性图标 + 名称 + 右侧弱化的当前值 + 右箭头；行间缩进的细分隔线。
// - 这一页只是目录，不放输入框；外观是唯一就地切换的项（三段选择）。
import 'package:lopicode/agent/agent_tools.dart';
import 'package:lopicode/agent/web_search.dart';
import 'package:lopicode/app_services.dart';
import 'package:lopicode/core/project_store.dart';
import 'package:lopicode/core/stores.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/automation_screen.dart';
import 'package:lopicode/runtime/linux_runtime.dart';
import 'package:lopicode/runtime/runtime_screen.dart';
import 'package:lopicode/ui/chat_panels.dart';
import 'package:lopicode/ui/chrome.dart';
import 'package:lopicode/ui/settings_agent.dart';
import 'package:lopicode/ui/settings_ai.dart';
import 'package:lopicode/ui/third_party_screen.dart';
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
      backgroundColor: c.canvas,
      appBar: PageBar(titleText: '设置', background: c.canvas),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Space.x4, Space.x4, Space.x4, Space.x8),
        children: [
          _OverviewCard(onModels: () => go(const ChannelsScreen()), onRuntime: workspace == null ? null : () => go(RuntimeScreen(projectDir: workspace!.dir))),
          const GroupLabel('AI'),
          GroupCard(
            children: [
              GroupRow(
                key: const Key('settings-channels'),
                icon: Icons.hub_outlined,
                title: '模型与渠道',
                value: channels.isEmpty ? '还没添加' : '${channels.length} 个渠道 · $modelCount 个模型',
                onTap: () => go(const ChannelsScreen()),
              ),
              GroupRow(
                key: const Key('settings-personalize'),
                icon: Icons.face_outlined,
                title: '个性化',
                subtitle: '个人偏好 · Agent 预设（默认：${app.presets.byId(app.presets.defaultId).name}）',
                onTap: () => go(const PersonalizeScreen()),
              ),
            ],
          ),
          const GroupLabel('能力'),
          GroupCard(
            children: [
              GroupRow(
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
              GroupRow(
                key: const Key('settings-subagents'),
                icon: Icons.account_tree_outlined,
                title: '子代理与团队',
                value: '子代理${subOn ? '开' : '关'} · 团队${teamOn ? '开' : '关'}',
                onTap: () => go(const SubagentSettingsScreen()),
              ),
              GroupRow(
                key: const Key('settings-automations'),
                icon: Icons.event_repeat,
                title: '自动化任务',
                value: app.automations.items.isEmpty ? '还没有任务' : '${app.automations.items.length} 个任务',
                onTap: () => go(AutomationListScreen(workspace: workspace)),
              ),
              FutureBuilder<WebSearchConfig?>(
                future: WebSearchConfig.load(app.settings, app.secrets),
                builder: (context, snap) => GroupRow(
                  key: const Key('settings-search'),
                  icon: Icons.travel_explore,
                  title: '联网搜索',
                  value: snap.data == null ? '未配置' : '已配置',
                  subtitle: snap.data == null ? 'Agent 现在没有搜索工具' : null,
                  onTap: () => go(const WebSearchSettingsScreen()),
                ),
              ),
              GroupRow(
                key: const Key('settings-skills'),
                icon: Icons.menu_book_outlined,
                title: '技能',
                subtitle: '写给 Agent 的做事说明书',
                onTap: () => go(SkillsScreen(workspace: workspace)),
              ),
            ],
          ),
          const GroupLabel('通用'),
          GroupCard(
            padding: const EdgeInsets.all(Space.x4),
            dividers: false,
            children: [
              Row(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: Space.x1),
                    child: Icon(Icons.contrast, size: 26, color: c.text),
                  ),
                  const SizedBox(width: Space.x4),
                  Text('外观', style: t.bodyLarge?.copyWith(fontSize: FontSize.lg, height: 1.3)),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(top: Space.x3),
                child: SegmentedButton<ThemeMode>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: ThemeMode.system, label: Text('跟随系统')),
                    ButtonSegment(value: ThemeMode.light, label: Text('浅色')),
                    ButtonSegment(value: ThemeMode.dark, label: Text('深色')),
                  ],
                  selected: {app.themeMode},
                  onSelectionChanged: (s) => app.setThemeMode(s.first),
                ),
              ),
            ],
          ),
          const GroupLabel('关于'),
          GroupCard(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(Space.x4, Space.x4, Space.x4, Space.x4),
                child: Text(
                  'LopiCode 1.0.0\n在手机上通过 Agent 完成代码项目：写代码、终端、网页预览、低代码搭建、远程打包 APK。',
                  style: t.bodySmall?.copyWith(color: c.textMuted, height: 1.6),
                ),
              ),
              GroupRow(
                key: const Key('settings-third-party'),
                icon: Icons.gavel_outlined,
                title: '第三方声明',
                subtitle: '随安装包带的开源组件和许可证',
                onTap: () => go(const ThirdPartyScreen()),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 概况卡：新对话用的模型 + 运行环境。版式照参考图的“套餐 / 用量”卡，内容是真实状态。
class _OverviewCard extends StatelessWidget {
  const _OverviewCard({required this.onModels, required this.onRuntime});
  final VoidCallback onModels;
  final VoidCallback? onRuntime;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final models = app.models;
    final model = models.resolve(models.newChatUsesFixed ? models.fixedSelection : models.lastSelection) ?? models.firstAvailable;
    Widget block({required String title, required String sub, required String state, required double? value}) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(child: Text(title, style: t.titleLarge?.copyWith(fontWeight: FontWeight.w400, fontSize: FontSize.xl), maxLines: 1, overflow: TextOverflow.ellipsis)),
            const SizedBox(width: Space.x3),
            Text(state, style: t.bodyMedium?.copyWith(color: c.textMuted)),
          ],
        ),
        const SizedBox(height: 2),
        Text(sub, style: t.bodyMedium?.copyWith(color: c.textFaint), maxLines: 1, overflow: TextOverflow.ellipsis),
        const SizedBox(height: Space.x3),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(value: value, minHeight: 6, color: c.accentFill, backgroundColor: c.border),
        ),
      ],
    );
    return GroupCard(
      key: const Key('settings-overview'),
      dividers: false,
      padding: const EdgeInsets.fromLTRB(Space.x4, Space.x4, Space.x4, Space.x2),
      children: [
        block(
          title: model == null ? '还没有可用的模型' : model.model.name,
          sub: model == null ? '添加渠道和模型后才能和 Agent 对话' : '新对话用的模型 · ${model.channel.name}',
          state: model == null ? '未配置' : '已配置',
          value: model == null ? 0 : 1,
        ),
        const SizedBox(height: Space.x4),
        AnimatedBuilder(
          animation: app.runtime,
          builder: (context, _) {
            final r = app.runtime;
            final (String state, double? value) = switch (r.phase) {
              RuntimePhase.installed when !r.usable => ('已下载，进不去', 1.0),
              RuntimePhase.installed => ('已安装', 1.0),
              RuntimePhase.downloading => ('正在下载', null),
              RuntimePhase.verifying => ('正在校验', null),
              RuntimePhase.extracting => ('正在解压', null),
              RuntimePhase.notInstalled => ('未安装', 0.0),
            };
            return block(title: '运行环境', sub: 'Ubuntu 24.04 · 终端和 Agent 的命令在里面跑', state: state, value: value);
          },
        ),
        const SizedBox(height: Space.x4),
        Divider(height: 1, color: c.border),
        Row(
          children: [
            TextButton(
              key: const Key('overview-models'),
              style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 48), textStyle: t.bodyLarge?.copyWith(fontSize: FontSize.lg)),
              onPressed: onModels,
              child: Text(model == null ? '添加模型' : '管理模型'),
            ),
            if (onRuntime != null) ...[
              const SizedBox(width: Space.x6),
              TextButton(
                key: const Key('overview-runtime'),
                style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 48), textStyle: t.bodyLarge?.copyWith(fontSize: FontSize.lg)),
                onPressed: onRuntime,
                child: const Text('运行环境'),
              ),
            ],
          ],
        ),
      ],
    );
  }
}
