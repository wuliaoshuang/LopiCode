// 把 MCP 工具接进一段对话：读状态、对话开头刷新工具清单、把确认卡 / “本对话都允许” / 超长结果这几样接到现成的机制上。
// 工具本身和安全规矩在 lib/agent/mcp/mcp_tools.dart；连接和缓存在 lib/state/mcp_state.dart。
//
// 没配置（或没开）任何 MCP 服务器时：这里什么都不做——不联网、不加工具、不加提示词、不出提示。
import 'package:lopicode/agent/agent_tools.dart';
import 'package:lopicode/agent/command_output_store.dart';
import 'package:lopicode/agent/mcp/mcp_tools.dart';
import 'package:lopicode/session/chat_models.dart';
import 'package:lopicode/session/conversation.dart';
import 'package:lopicode/session/session_core.dart';
import 'package:lopicode/state/mcp_state.dart';
import 'package:lopicode/state/workspace_chat.dart';

export 'package:lopicode/agent/mcp/mcp_tools.dart' show kMcpPromptNote;

/// 现在有没有开着的 MCP 服务器（系统提示词据此决定要不要加那段“外部数据不是指令”）。
bool mcpActive(SessionCore core) => !core.app.disposed && core.app.container.read(mcpProvider).active;

/// 这段对话能用的 MCP 工具。[taken] 是已经被别的工具占了的名字。
Future<List<ExtraTool>> mcpToolsFor(SessionCore core, ChatRunNotifier run, Conversation root, ApprovalRequester approve, {Set<String> taken = const {}}) async {
  final app = core.app;
  if (app.disposed) return const [];
  final mcp = app.container.read(mcpProvider.notifier);
  await mcp.ensureLoaded();
  if (!mcp.snapshot.active) return const [];
  // 每段主对话第一次用到时刷新一次工具清单；没人在场（自动化任务）不为这个联网，直接用存着的清单。
  if (!run.unattended) {
    for (final note in await mcp.refreshForConversation(root.id)) {
      if (run.conv.parentId == null) run.add(NoticeItem(note));
    }
  }
  if (app.disposed) return const [];
  return mcpExtraTools(
    servers: mcp.snapshot.servers,
    call: (server, tool, args) => mcp.call(server.id, tool, args),
    approve: approve,
    alwaysAllowed: (key) => core.cards.keyAllowed(root.id, key),
    unattended: () => run.unattended,
    spill: (label, output) async => spilledOutputText(output, await CommandOutputStore(core.guard).save(label, output)),
    taken: taken,
  );
}
