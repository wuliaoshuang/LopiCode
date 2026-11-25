// /compact 背后的那一次请求：和正常对话用同一份系统提示词、同一套工具定义、同样的历史（同前缀，服务商的缓存能命中），
// 所以这里照“跑一轮”的样子把执行器搭出来，但不跑循环，只交给 compactWholeConversation 发一次压缩请求。
// 自动压缩走的也是 lib/agent/context_relief.dart + auto_compact.dart 那同一套实现。
import 'dart:io';

import 'package:lopicode/agent/agent_runner.dart';
import 'package:lopicode/agent/context_relief.dart';
import 'package:lopicode/session/session_core.dart';
import 'package:lopicode/session/system_prompt.dart';
import 'package:lopicode/session/toolbox_builder.dart';
import 'package:lopicode/state/workspace_chat.dart';

/// 把 [run] 这段对话整段压成摘要，就地改写它的消息记录。成功返回 null；失败 / 太短返回给用户看的原因，记录不动。
Future<String?> compactRun(SessionCore core, ToolboxBuilder toolbox, ChatRunNotifier run) async {
  final app = core.app;
  final root = core.dir.rootOf(run.conv);
  final skills = await app.skills.enabled(workspaceDir: core.project.dir);
  final resolved = core.modelOf(run.conv);
  // 额度到顶的拦截在 createChatClient 里（和正常对话同一个口子）。
  final runner = AgentRunner(
    client: await app.createChatClient(resolved),
    history: run.messages,
    systemPrompt: systemPromptFor(core, run.conv, root, skills),
    toolbox: await toolbox.build(run, root, skills),
    vision: resolved?.model.vision ?? false,
    loadImage: (path) async {
      try {
        return await File(core.guard.resolve(path)).readAsBytes();
      } on Exception {
        return null;
      }
    },
    contextLimit: resolved?.model.contextLength,
  );
  final r = await compactWholeConversation(runner);
  return r.skipped ? '对话还很短，不需要压缩' : r.error;
}
