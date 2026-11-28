// 设计约束（没配好模型时的引导 + 选择服务商 · 390×844）
// - 没有可用模型时弹一个对话框：一句话说清缺什么，两个按钮“稍后”和“去配置”。“去配置”直接落到该填的那一页：
//   一个渠道都没有 → 选择服务商；有渠道但缺 Key / 没勾模型 → 那个渠道的编辑页。
// - 不反复打扰：每次运行进聊天页最多自动弹一次；之后只有点“发送”时才再提示。
// - 选择服务商：一行一个（图标 + 名字 + 接口地址主机名），点了就进编辑页并填好名称、协议、地址，只差 Key。
//   列表最下面是“自定义”，走原来的全手填。
import 'package:lopicode/agent/model_config.dart';
import 'package:lopicode/agent/provider_presets.dart';
import 'package:lopicode/theme/breakpoints.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/app_ref.dart';
import 'package:lopicode/ui/chrome.dart';
import 'package:lopicode/ui/provider_icon.dart';
import 'package:lopicode/ui/settings_ai.dart';
import 'package:material_ui/material_ui.dart';

/// 检查当前模型能不能用；不能用就弹引导。返回 true 表示可以发消息。
///
/// [auto] 为真表示“进聊天页时自动检查”：这次运行里已经弹过就不再弹。
Future<bool> ensureModelReady(BuildContext context, {ResolvedModel? current, bool auto = false}) async {
  final app = appOf(context);
  if (app.chatClientFactory != null) return true; // 测试里换掉了模型客户端
  if (auto && app.modelSetupPrompted) return true;
  final gap = await app.models.readiness(current);
  if (gap == null) return true;
  if (!context.mounted) return false;
  app.modelSetupPrompted = true;
  final go = await showDialog<bool>(
    context: context,
    builder: (context) {
      final c = context.colors;
      return AlertDialog(
        key: const Key('model-setup-dialog'),
        title: Text(gap.title),
        content: Text(gap.message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            style: TextButton.styleFrom(foregroundColor: c.textMuted),
            child: const Text('稍后'),
          ),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('去配置')),
        ],
      );
    },
  );
  if (go != true || !context.mounted) return false;
  final ch = gap.channel;
  await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ch == null ? const ProviderPickerScreen() : ChannelEditScreen(channel: ch)));
  return false; // 配完回来让她自己再点一次发送，不替她发
}

/// 添加渠道的第一步：选服务商。
class ProviderPickerScreen extends StatelessWidget {
  const ProviderPickerScreen({super.key});

  Future<void> _pick(BuildContext context, ProviderPreset? preset) async {
    final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => ChannelEditScreen(preset: preset)));
    // 保存了就一路回到渠道列表；没保存（点了返回）留在这里重新选。
    if (saved == true && context.mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: c.canvas,
      extendBodyBehindAppBar: true,
      appBar: PageBar(background: c.canvas, title: const Text('选择服务商')),
      body: ContentWidth(
        child: ListView(
          key: const Key('provider-list'),
          padding: EdgeInsets.fromLTRB(Space.x4, PageBar.insetOf(context) + Space.x2, Space.x4, Space.x8),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.x4, 0, Space.x4, Space.x3),
              child: Text('选一个就自动填好名称、协议和接口地址，你只需要填 API Key。', style: t.bodySmall?.copyWith(color: c.textFaint)),
            ),
            GroupCard(
              children: [
                for (final p in kProviderPresets)
                  _ProviderRow(
                    key: ValueKey('preset-${p.id}'),
                    icon: ProviderIcon(preset: p),
                    title: p.name,
                    subtitle: p.host,
                    onTap: () => _pick(context, p),
                  ),
              ],
            ),
            GroupCard(
              children: [
                _ProviderRow(key: const ValueKey('preset-custom'), icon: const ProviderIcon(preset: null), title: '自定义', subtitle: '中转站、自建服务或列表里没有的：自己填协议和接口地址', onTap: () => _pick(context, null)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ProviderRow extends StatelessWidget {
  const _ProviderRow({super.key, required this.icon, required this.title, required this.subtitle, required this.onTap});
  final Widget icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 64),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.x4, vertical: Space.x3),
          child: Row(
            children: [
              icon,
              const SizedBox(width: Space.x3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(title, style: t.bodyLarge?.copyWith(height: 1.3), maxLines: 1, overflow: TextOverflow.ellipsis),
                    Text(
                      subtitle,
                      style: t.bodySmall?.copyWith(color: c.textFaint),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: Space.x2),
              Icon(Icons.chevron_right, size: 24, color: c.textFaint.withValues(alpha: 0.7)),
            ],
          ),
        ),
      ),
    );
  }
}
