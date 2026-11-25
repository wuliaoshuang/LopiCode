// 拼系统提示词：默认提示词 + 执行环境 + 预设 + 个人偏好 + 项目规则 + 项目里的 AGENTS.md + 技能 + 权限说明 + 计划模式 + 子代理 / 团队的身份说明。
import 'package:lopicode/agent/agent_runner.dart';
import 'package:lopicode/agent/agent_tools.dart';
import 'package:lopicode/agent/memory_tools.dart';
import 'package:lopicode/agent/skills.dart';
import 'package:lopicode/agent/team.dart';
import 'package:lopicode/session/conversation.dart';
import 'package:lopicode/session/mcp_wiring.dart';
import 'package:lopicode/session/prompt_context.dart';
import 'package:lopicode/session/session_core.dart';

/// [conv] 是正在跑的这段对话，[root] 是它最上面那段主对话（权限、计划模式、预设都跟着主对话走）。
String systemPromptFor(SessionCore core, Conversation conv, Conversation root, List<Skill> skills, {String? taskNote}) {
  root = core.live(root);
  final parts = <String>[AgentRunner.defaultSystemPrompt, environmentSection(core.app.runtime, guestCwd: core.project.linuxPath, customRunner: core.session.commandRunnerFactory?.call())];
  final presetPrompt = core.presetOf(root).prompt.trim();
  if (presetPrompt.isNotEmpty) parts.add('当前 Agent 预设的要求：\n$presetPrompt');
  final prefs = core.app.presets.preferences;
  if (prefs.isNotEmpty) parts.add('用户的个人偏好（尽量照做）：\n$prefs');
  final rules = core.dir.projectRules;
  if (rules.isNotEmpty) parts.add('用户给这个项目定的规则（必须遵守）：\n$rules');
  final agentsMd = agentsMdSection(readAgentsMd(core.guard));
  if (agentsMd != null) parts.add(agentsMd);
  final skillText = SkillStore.promptSection(skills);
  if (skillText.isNotEmpty) parts.add(skillText);
  // 记忆的清单 / 摘要（用的是这一轮开始前读好的那份）。能不能写只影响这里怎么说，真正的拦截在工具那边。
  if (core.app.memory.enabled) {
    parts.add(memoryPromptSection(core.app.memory.global.entries, core.projectMemory?.entries, canWrite: conv.parentId == null && !root.planMode && core.permissionOf(root) != PermissionLevel.view));
  }
  parts.add(switch (core.permissionOf(root)) {
    PermissionLevel.view => '当前权限：仅可查看。你只能看，不能改文件、删文件、执行命令（这些工具已经被关掉）。',
    PermissionLevel.workspace => '当前权限：工作区内修改。可以改工作区里的文件；删除文件、执行命令每次要用户确认。',
    PermissionLevel.full => '当前权限：完全权限。删除文件、执行命令不再逐次确认，动手前自己多想一步。',
  });
  if (root.planMode) parts.add('现在是计划模式：只调查、只出计划，不要改任何东西（写文件、删文件、执行命令的工具已经被关掉）。把打算怎么做分步骤写清楚，等用户确认。');
  if (conv.parentId != null) {
    parts.add('你是被上级智能体派出来的子代理“${conv.agentName}”，只负责交给你的这一件事。做完后用一段话汇报结果（做了什么、改了哪些文件、有什么没做成），这段话会原样交回上级。${taskNote ?? ''}');
  } else if (core.teamEnabled) {
    parts.add('这段对话开了智能体团队：你是“${TeamBoard.lead}”。复杂的事先用 team_task 在任务板上拆成任务（写清负责人、依赖、写入范围），再用 spawn_agent 把任务派给子代理（带上 task_id），最后汇总。');
  }
  if (mcpActive(core)) parts.add(kMcpPromptNote);
  return parts.join('\n\n');
}
