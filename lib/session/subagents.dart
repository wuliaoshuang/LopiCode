// 派子代理：spawn_agent 工具和它背后的事——起名、选模型、认领任务板上的任务、排队等名额、
// 跑完把汇报交回上级、把用量记在上级那一轮名下。
//
// 限制都在代码里再查一遍（就算工具被硬调用也绕不过）：功能开关、委派层数、每段主对话最多 24 个、
// 只能换成设置里允许的模型、同时进行的个数。
import 'dart:async';

import 'package:lopicode/agent/agent_tools.dart';
import 'package:lopicode/agent/model_config.dart';
import 'package:lopicode/agent/skills.dart';
import 'package:lopicode/agent/team.dart';
import 'package:lopicode/agent/usage.dart';
import 'package:lopicode/session/chat_models.dart';
import 'package:lopicode/session/conversation.dart';
import 'package:lopicode/session/session_core.dart';
import 'package:lopicode/session/turn_runner.dart';
import 'package:lopicode/state/workspace_chat.dart';

/// 一段主对话里最多派出多少个子代理。
const int kMaxSubagentsPerConversation = 24;

/// 限制同时进行的个数：名额满了就排队，先来先得。
class RunSlots {
  RunSlots(this.max);
  int max;
  int _held = 0;
  final List<Completer<void>> _waiters = [];

  Future<void> acquire() async {
    if (_held < max) {
      _held++;
      return;
    }
    final c = Completer<void>();
    _waiters.add(c);
    await c.future;
  }

  void release() {
    if (_waiters.isNotEmpty) {
      _waiters.removeAt(0).complete(); // 名额直接转给下一个
    } else {
      _held--;
    }
  }
}

class Subagents {
  Subagents(this.core, {required this.execute});

  final SessionCore core;

  /// 跑一段对话（turn_runner.dart 的 TurnRunner.execute）。
  final ExecuteTurn execute;

  late final RunSlots _slots = RunSlots(2);

  ExtraTool tool(ChatRunNotifier parent, Conversation root, List<Skill> skills) {
    final allowed = core.subagentAllowedModels;
    return ExtraTool(
      spec: toolSpec(
        'spawn_agent',
        '派出一个子代理去独立完成一件事。它有自己的上下文（看不到这段对话），所以 task 里要把背景、要求、要交回什么写全。'
            '同一轮里连着派出的几个会同时进行（最多 ${core.subagentMaxConcurrent} 个）。它做完后把结果汇报给你。',
        {
          'name': {'type': 'string', 'description': '给它起个短名字，如“前端”“查资料”'},
          'task': {'type': 'string', 'description': '交给它的完整任务说明'},
          if (core.teamEnabled) 'task_id': {'type': 'string', 'description': '对应任务板上的任务编号（可选）：它会成为负责人，并且只能改这个任务写入范围内的文件'},
          if (allowed.isNotEmpty) 'model': {'type': 'string', 'enum': allowed, 'description': '可选：让它用别的模型（渠道ID/模型ID）；省略则和你用同一个'},
        },
        ['task'],
      ),
      kind: ToolKind.other,
      run: (args) => _spawn(parent, root, skills, args),
    );
  }

  Future<ToolOutcome> _spawn(ChatRunNotifier parent, Conversation root, List<Skill> skills, Map<String, dynamic> args) async {
    final app = core.app;
    final dir = core.dir;
    final task = AgentToolbox.argString(args, 'task');
    // 层数限制在代码里再查一遍：就算工具被硬调用也派不出去。
    if (!core.subagentsEnabled) return ToolOutcome('错误：子代理功能已在设置里关闭', ok: false);
    if (parent.conv.depth >= core.subagentMaxDepth) return ToolOutcome('错误：已经到了委派层数上限（${core.subagentMaxDepth} 层），不能再往下派', ok: false);
    var name = '${args['name'] ?? ''}'.trim();
    if (name.isEmpty) name = '子代理';
    if (name.length > 12) name = name.substring(0, 12);
    final siblings = dir.all.where((c) => dir.rootOf(c).id == root.id && c.parentId != null).length;
    if (siblings >= kMaxSubagentsPerConversation) return ToolOutcome('错误：这段对话已经派出 $kMaxSubagentsPerConversation 个子代理，达到上限', ok: false);
    if (dir.all.any((c) => c.parentId != null && dir.rootOf(c).id == root.id && c.agentName == name)) name = '$name${siblings + 1}';

    // 模型：默认跟随上级；要换只能换成设置里允许的。
    var selection = core.modelOf(parent.conv)?.selection;
    final wanted = args['model'];
    if (wanted is String && wanted.trim().isNotEmpty) {
      final parts = wanted.trim().split('/');
      final ok = core.subagentAllowedModels.contains(wanted.trim()) && parts.length >= 2;
      final sel = ok ? ModelSelection(parts.first, parts.sublist(1).join('/')) : null;
      if (sel == null || app.models.resolve(sel) == null) {
        return ToolOutcome('错误：模型 $wanted 不在允许子代理使用的模型里。省略 model 参数就会和你用同一个模型', ok: false);
      }
      selection = sel;
    }

    // 任务板：认领任务，拿到写入范围。
    List<String>? scope;
    TeamBoard? board;
    String? taskId;
    final rawTaskId = args['task_id'];
    if (core.teamEnabled && rawTaskId is String && rawTaskId.trim().isNotEmpty) {
      board = await core.boardOf(root);
      taskId = rawTaskId.trim();
      try {
        final t = await board.update(taskId, status: TaskStatus.doing, owner: name);
        scope = t.scope.isEmpty ? null : [...t.scope];
      } on TeamException catch (e) {
        return ToolOutcome('错误：${e.message}', ok: false);
      }
    } else if (core.teamEnabled) {
      await (await core.boardOf(root)).addMember(name, '子代理');
    }

    final child = Conversation(core.newConvId(), titleFromText(task), DateTime.now(), parentId: parent.conv.id, depth: parent.conv.depth + 1, agentName: name, selection: selection);
    core.convs?.add(child);
    final run = core.runOf(child)
      ..markLoaded()
      ..unattended = parent.unattended;
    // 让界面上那张工具卡能点进这段子对话。
    final card = parent.items.whereType<ToolItem>().where((t) => t.name == 'spawn_agent' && t.running && t.childConversationId == null).firstOrNull;
    if (card != null) parent.replace(card, card.copyWith(childConversationId: child.id));
    await core.saveIndex();

    _slots.max = core.subagentMaxConcurrent;
    await _slots.acquire();
    String result;
    var failed = false;
    try {
      if (parent.runner?.isCancelled ?? false) {
        result = '用户已停止，子代理没有开始。';
        failed = true;
      } else {
        final outcome = await execute(run, task, root: root, skills: skills, writeScope: scope, taskNote: scope == null ? null : '你只能改这些位置的文件：${scope.join('、')}。');
        result = outcome.text;
        failed = outcome.failed;
        // 子代理花的用量记在上级这一轮名下（可以分开看）。
        final spent = run.turn;
        if (spent != null && spent.totals.requests > 0) parent.turn?.children.add(ChildUsage(name, spent));
      }
    } finally {
      _slots.release();
    }
    if (board != null && taskId != null) {
      final t = board.task(taskId);
      if (t != null && t.status == TaskStatus.doing) {
        // 子代理没自己更新任务状态：正常结束算完成，出错退回待办。
        await board.update(taskId, status: failed ? TaskStatus.todo : TaskStatus.done, note: failed ? '子代理没做完：${clipText(result, 80)}' : (t.note.isEmpty ? '子代理结束时自动标记完成' : t.note));
      }
    }
    final text = result.trim().isEmpty ? '（子代理没有给出汇报）' : clipText(result.trim(), 8000);
    return ToolOutcome('子代理“$name”的汇报：\n$text', ok: !failed, changedFiles: true);
  }
}
