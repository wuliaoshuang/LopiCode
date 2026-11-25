// 设计约束（MCP 服务器列表 · 390×844）— 2026-11-25 新增，照设置的统一样式（settings_widgets.dart）
// - 页 › 组 › 行。最上面一条提示条说清这是什么、有什么限制（只连远程、只支持请求头鉴权、每次调用都要确认）。
// - 〔服务器〕组：一个服务器一行——名称在上，状态和工具数在下面的副标题里；右边一个开关。点整行进编辑页，点开关只开 / 关。
//   这一行有两个可点的地方（行 + 开关）：开关是任务书点名要的，所以保留；别的操作（改名、请求头、选工具、删除）都收进编辑页。
// - 组的最后一行是强调色的“添加 MCP 服务器”。一个都没有时，组里只有这一行，脚注写明“没有服务器时对话里不会出现任何 MCP 的东西”。
// - 颜色：状态文字用弱色；只有“上次没连上”那一行的副标题带原因，不上红色（红色只给删除）。
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lopicode/agent/mcp/mcp_config.dart';
import 'package:lopicode/state/mcp_state.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/mcp_edit_screen.dart';
import 'package:lopicode/ui/settings_widgets.dart';
import 'package:lopicode/ui/widgets.dart';
import 'package:material_ui/material_ui.dart';

/// 设置一级页“MCP 服务器”那一行右边写什么。
String mcpSummary(McpState s) {
  if (s.servers.isEmpty) return '未配置';
  final on = s.enabled.length;
  return on == 0 ? '${s.servers.length} 个，都关着' : '$on 个开着';
}

/// 列表里一个服务器的状态说明。
String mcpServerStatusText(McpServerConfig s, McpStatus st) {
  final total = s.tools.length;
  final active = s.activeTools.length;
  final count = total == 0 ? '' : (active == total ? '$total 个工具' : '$active / $total 个工具开着');
  if (!s.enabled) return ['已关闭', count].where((x) => x.isNotEmpty).join(' · ');
  return switch (st.phase) {
    McpPhase.checking => '正在连接…',
    McpPhase.failed => total == 0 ? '上次没连上：${st.message}' : '上次没连上，先用旧清单（$count）：${st.message}',
    _ => s.toolsAt == null ? '还没读过工具清单，点进去连一次' : (total == 0 ? '连得上，但没有工具' : count),
  };
}

class McpServersScreen extends ConsumerWidget {
  const McpServersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(mcpProvider);
    final mcp = ref.read(mcpProvider.notifier);
    return SettingsPage(
      title: 'MCP 服务器',
      children: [
        const InfoBanner(
          'MCP 服务器给 Agent 提供外部工具（查资料、操作别的系统等）。只能接远程服务器（网址），鉴权只支持自定义请求头。'
          'Agent 每次调用这些工具都会先问你；只接入你信得过的服务器。',
          margin: EdgeInsets.only(bottom: Space.x6),
        ),
        SettingsGroup(
          title: '服务器',
          footer: state.servers.isEmpty ? '一个服务器都没有（或都关着）时，对话里不会出现任何 MCP 的东西。' : '关掉的服务器不联网，Agent 也看不到它的工具。仅可查看、计划模式、限定了工具的 Agent 预设下，也没有这些工具。',
          children: [
            for (final s in state.servers)
              SettingsRow(
                key: Key('mcp-server-${s.id}'),
                icon: Icons.extension_outlined,
                title: s.name,
                subtitle: mcpServerStatusText(s, state.statusOf(s.id)),
                onTap: () => pushSettingsPage<void>(context, McpServerEditScreen(serverId: s.id)),
                trailing: Switch(key: Key('mcp-switch-${s.id}'), value: s.enabled, onChanged: (on) => mcp.setEnabled(s.id, on)),
              ),
            SettingsRow(key: const Key('mcp-add'), icon: Icons.add, title: '添加 MCP 服务器', accent: true, onTap: () => pushSettingsPage<void>(context, const McpServerEditScreen())),
          ],
        ),
      ],
    );
  }
}
