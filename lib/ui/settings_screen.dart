// 设计约束（设置 · 390×844）— 2026-11-23 按霜霜的参考图（workspace/user/files/88185_1_u07b.jpg）改版
// - 浅灰底（canvas）。顶部：左上悬浮的白色圆形返回按钮，标题“设置”居中。
// - 内容是一张张白色大圆角卡片（28），卡片左右各留 16。
// - 第一张是概况卡，版式照参考图：左边大字 + 一行小字，右边一句状态，下面一根进度条；两段之后一条分隔线和一个蓝色文字入口。
//   我们放的是真实状态：①新对话用的模型——只有渠道是 DeepSeek 官方、且设了额度上限时才有进度条（已用 ÷ 上限）和“已使用 x%（剩余 ¥y）”；
//     DeepSeek 没设上限只写余额；其他渠道只写模型名和渠道名，没有进度条和百分比。②运行环境 Ubuntu（装好 = 满，下载中 = 真实进度）。
// - 其余卡片按 AI / 能力 / 通用 / 关于 分组，每行一件事：左线性图标 + 名称 + 右侧弱化的当前值 + 右箭头；行间缩进的细分隔线。
// - 这一页只是目录，不放输入框；外观是唯一就地切换的项（三段选择）。
import 'package:lopicode/agent/agent_tools.dart';
import 'package:lopicode/agent/model_config.dart';
import 'package:lopicode/agent/quota.dart';
import 'package:lopicode/agent/web_search.dart';
import 'package:lopicode/app_services.dart';
import 'package:lopicode/core/project_store.dart';
import 'package:lopicode/core/stores.dart';
import 'package:lopicode/project_session.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/automation_screen.dart';
import 'package:lopicode/runtime/linux_runtime.dart';
import 'package:lopicode/runtime/runtime_screen.dart';
import 'package:lopicode/ui/chat_panels.dart';
import 'package:lopicode/ui/chrome.dart';
import 'package:lopicode/ui/settings_agent.dart';
import 'package:lopicode/ui/settings_ai.dart';
import 'package:lopicode/ui/settings_quota.dart';
import 'package:lopicode/ui/third_party_screen.dart';
import 'package:material_ui/material_ui.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, this.workspace, this.session});

  /// 当前打开的工作区的会话（项目规则是按工作区存的，要靠它读写）。
  final ProjectSession? session;

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
    final deepseek = [for (final ch in channels) if (isDeepSeekOfficial(ch.baseUrl)) ch];
    Future<void> toggle(String key, bool value) async {
      await app.settings.set(key, value);
      app.touch();
    }
    return Scaffold(
      backgroundColor: c.canvas,
      appBar: PageBar(titleText: '设置', background: c.canvas),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Space.x4, Space.x4, Space.x4, Space.x8),
        children: [
          _OverviewCard(
            onModels: () => go(const ChannelsScreen()),
            onRuntime: workspace == null ? null : () => go(RuntimeScreen(projectDir: workspace!.dir)),
            onQuota: (ch) => go(QuotaScreen(channelId: ch.id)),
          ),
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
              for (final ch in deepseek)
                AnimatedBuilder(
                  animation: app.quota,
                  builder: (context, _) {
                    final q = app.quota.quotaOf(ch.id);
                    return GroupRow(
                      key: Key('settings-quota-${ch.id}'),
                      icon: Icons.speed_outlined,
                      title: '额度上限',
                      subtitle: deepseek.length > 1 ? ch.name : null,
                      value: q == null ? '未设置' : '${formatMoney(q.currency, q.limit)} · 已用 ${q.percent}%',
                      onTap: () => go(QuotaScreen(channelId: ch.id)),
                    );
                  },
                ),
              if (session == null)
                const GroupRow(key: Key('settings-rules'), icon: Icons.rule, title: '项目规则', subtitle: '打开一个工作区后，才能写它的规则')
              else
                AnimatedBuilder(
                  animation: session!,
                  builder: (context, _) => GroupRow(
                    key: const Key('settings-rules'),
                    icon: Icons.rule,
                    title: '项目规则',
                    subtitle: '只对工作区“${session!.project.name}”生效',
                    value: session!.projectRules.isEmpty ? '未设置' : '已设置',
                    onTap: () => go(ProjectRulesScreen(session: session!)),
                  ),
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
          const GroupLabel('对话'),
          GroupCard(
            children: [
              GroupRow(
                icon: Icons.lightbulb_outline,
                title: '在新对话里显示开场建议',
                trailing: Switch(
                  key: const Key('settings-suggestions'),
                  value: app.settings.getBool(SettingKeys.chatSuggestions),
                  onChanged: (v) => toggle(SettingKeys.chatSuggestions, v),
                ),
              ),
              GroupRow(
                icon: Icons.data_usage,
                title: '在回复下方显示用量',
                subtitle: '每轮用了多少 tokens、缓存命中率、用时',
                trailing: Switch(
                  key: const Key('settings-usage'),
                  value: app.settings.getBool(SettingKeys.chatUsage, true),
                  onChanged: (v) => toggle(SettingKeys.chatUsage, v),
                ),
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
class _OverviewCard extends StatefulWidget {
  const _OverviewCard({required this.onModels, required this.onRuntime, required this.onQuota});
  final VoidCallback onModels;
  final VoidCallback? onRuntime;
  final void Function(Channel channel) onQuota;

  @override
  State<_OverviewCard> createState() => _OverviewCardState();
}

class _OverviewCardState extends State<_OverviewCard> {
  bool _asked = false;

  ResolvedModel? _model(AppServices app) {
    final models = app.models;
    return models.resolve(models.newChatUsesFixed ? models.fixedSelection : models.lastSelection) ?? models.firstAvailable;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_asked) return;
    _asked = true;
    // 进设置页查一次余额（有节流；不是 DeepSeek 官方渠道什么都不做）。
    final app = AppScope.of(context);
    final model = _model(app);
    if (model != null) app.quota.refresh(model.channel);
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final model = _model(app);
    final link = TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 48), textStyle: t.bodyLarge?.copyWith(fontSize: FontSize.lg));

    /// [value] 为 null 时不画进度条（[bar] 为 true 且 value 为 null 是“进行中”的滚动条）。
    Widget block({required String title, required String sub, String? state, double? value, bool bar = true, Color? color, Key? stateKey}) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(child: Text(title, style: t.titleLarge?.copyWith(fontWeight: FontWeight.w400, fontSize: FontSize.xl), maxLines: 1, overflow: TextOverflow.ellipsis)),
            if (state != null) ...[
              const SizedBox(width: Space.x3),
              Text(state, key: stateKey, style: t.bodyMedium?.copyWith(color: color ?? c.textMuted)),
            ],
          ],
        ),
        const SizedBox(height: 2),
        Text(sub, style: t.bodyMedium?.copyWith(color: c.textFaint), maxLines: 1, overflow: TextOverflow.ellipsis),
        if (bar) ...[
          const SizedBox(height: Space.x3),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(key: const Key('overview-bar'), value: value, minHeight: 6, color: color ?? c.accentFill, backgroundColor: c.border),
          ),
        ],
      ],
    );

    Widget modelBlock() {
      if (model == null) return block(title: '还没有可用的模型', sub: '添加渠道和模型后才能和 Agent 对话', state: '未配置', bar: false);
      final sub = '新对话用的模型 · ${model.channel.name}';
      // 不是 DeepSeek 官方：只有模型名和渠道名。
      if (!isDeepSeekOfficial(model.channel.baseUrl)) return block(title: model.model.name, sub: sub, bar: false);
      return AnimatedBuilder(
        animation: app.quota,
        builder: (context, _) {
          final q = app.quota.quotaOf(model.channel.id);
          final state = app.quota.stateOf(model.channel.id);
          if (q != null) {
            final info = state.result?.of(q.currency);
            return block(
              title: model.model.name,
              sub: '${model.channel.name} · ${info != null ? '余额 ${formatMoney(info.currency, info.total)}' : (state.keyInvalid ? 'Key 无效，查不到余额' : (state.loading ? '正在查余额…' : '余额没查到'))}',
              state: '已使用 ${q.percent}%（剩余 ${formatMoney(q.currency, q.remaining)}）',
              stateKey: const Key('overview-quota'),
              value: q.fraction,
              color: q.reached ? c.danger : null,
            );
          }
          // 没设上限：只写余额，不画进度条。
          final infos = state.result?.infos ?? const <BalanceInfo>[];
          final text = infos.isNotEmpty
              ? '余额 ${[for (final i in infos) formatMoney(i.currency, i.total)].join(' / ')}'
              : (state.loading ? '正在查余额…' : (state.keyInvalid ? 'Key 无效，查不到余额' : (state.error != null ? '余额没查到' : null)));
          return block(title: model.model.name, sub: sub, state: text, stateKey: const Key('overview-balance'), bar: false);
        },
      );
    }

    final deepseek = model != null && isDeepSeekOfficial(model.channel.baseUrl);
    return GroupCard(
      key: const Key('settings-overview'),
      dividers: false,
      padding: const EdgeInsets.fromLTRB(Space.x4, Space.x4, Space.x4, Space.x2),
      children: [
        modelBlock(),
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
        // 入口一行放不下三个时自动换行，每个入口仍是一整块可点区域。
        Wrap(
          spacing: Space.x6,
          children: [
            TextButton(key: const Key('overview-models'), style: link, onPressed: widget.onModels, child: Text(model == null ? '添加模型' : '管理模型')),
            if (deepseek)
              AnimatedBuilder(
                animation: app.quota,
                builder: (context, _) => TextButton(
                  key: const Key('overview-set-quota'),
                  style: link,
                  onPressed: () => widget.onQuota(model.channel),
                  child: Text(app.quota.quotaOf(model.channel.id) == null ? '设置额度上限' : '额度上限'),
                ),
              ),
            if (widget.onRuntime != null) TextButton(key: const Key('overview-runtime'), style: link, onPressed: widget.onRuntime, child: const Text('运行环境')),
          ],
        ),
      ],
    );
  }
}
