// 上下文快满时怎么办：先看“只省略较早的工具结果”够不够，不够再把较早的对话压成摘要。AgentRunner 每次调用模型之前来问一次。
//
// 顺序是有讲究的（2026-11-25 改）：
// - 省略旧工具结果会改动前面的消息，前缀一变，服务商的前缀缓存就从那里断掉。所以先在一份副本上试着省略：
//   省略完够用（回到 85% 线以下）就真的省略，不压缩——和以前一样；
//   不够用、要压缩时，压缩请求用的是**没省略过**的原样历史（和上一次正常请求同前缀，缓存能命中）。
// - 原样历史加上指令和摘要放不进上下文（见 [compactReserveOf]）时，退一步用省略过的历史（前缀只对到第一处被省略的地方）；
//   还放不下就用纯文字记录的老办法（它自己会截短）。三种都只发**一次**请求。
// - 压缩失败（含模型反而去调工具）：记录不动，照旧省略旧工具结果继续；这一轮不再试（由调用方记着）。
import 'dart:convert';
import 'dart:math' as math;

import 'package:lopicode/agent/agent_runner.dart';
import 'package:lopicode/agent/auto_compact.dart';
import 'package:lopicode/agent/loop_guard.dart';
import 'package:lopicode/agent/usage.dart';

/// 同前缀的压缩请求要给“压缩指令 + 模型写的摘要”留出的余量：上下文的 5%，至少 2000 token（按估算）。
const double kCompactReserveShare = 0.05;
const int kCompactReserveMin = 2000;

int compactReserveOf(int limit) => math.max(kCompactReserveMin, (limit * kCompactReserveShare).floor());

class ContextRelief {
  const ContextRelief({this.pruned = 0, this.compact});

  /// 省略了几条较早的工具结果。
  final int pruned;

  /// 压缩那一次的结果；这次没去压缩是 null。
  final CompactOutcome? compact;
}

/// 系统提示词 + 工具定义大约占多少 token（消息之外的固定开销）。
int _overhead(AgentRunner r) => estimateTextTokens(r.systemPrompt) + estimateTextTokens(jsonEncode(r.toolbox.specs));

/// 选压缩请求用哪份历史当前缀：原样的 → 省略过的 → null（纯文字记录）。上下文长度未知时直接用原样的。
Future<List<Map<String, dynamic>>?> _pickPrefix(AgentRunner r, List<List<Map<String, dynamic>>> candidates) async {
  final limit = r.contextLimit;
  for (final history in candidates) {
    if (limit == null || AgentRunner.estimateTokens(history) + _overhead(r) + compactReserveOf(limit) <= limit) return r.buildRequest(history);
  }
  return null;
}

/// 每次调用模型之前：快满了就省略 / 压缩。[compact]＝允不允许压缩（开关开着、这一轮还没失败过）。
Future<ContextRelief> relieveContext(AgentRunner r, {required bool compact}) async {
  final limit = r.contextLimit;
  final messages = r.messages;
  if (limit == null || AgentRunner.estimateTokens(messages) <= limit * AgentRunner.pruneAt) return const ContextRelief();
  // 在副本上试着省略（pruneOldToolResults 换的是列表里的项，不改原来的消息对象）。
  final trial = [...messages];
  final pruned = pruneOldToolResults(trial);
  void applyPrune() {
    if (pruned == 0) return;
    messages
      ..clear()
      ..addAll(trial);
  }

  if (!compact || AgentRunner.estimateTokens(trial) <= limit * AgentRunner.pruneAt) {
    applyPrune();
    return ContextRelief(pruned: pruned);
  }
  final outcome = await compactOlder(
    r.client,
    messages,
    keepRecent: kCompactKeepRecent,
    archive: true,
    keepLastRequest: true,
    contextLimit: limit,
    prefix: await _pickPrefix(r, [messages, if (pruned > 0) trial]),
    tools: r.toolbox.specs,
  );
  if (outcome.ok) return ContextRelief(compact: outcome);
  applyPrune();
  return ContextRelief(pruned: pruned, compact: outcome);
}

/// /compact：把整段对话压成摘要（和自动压缩同一套实现，只是不留最近几条、不归档）。
Future<CompactOutcome> compactWholeConversation(AgentRunner r) async {
  if (r.messages.where((m) => !isArchived(m)).length < 2) return const CompactOutcome(skipped: true);
  return compactOlder(r.client, r.messages, contextLimit: r.contextLimit, prefix: await _pickPrefix(r, [r.messages]), tools: r.toolbox.specs);
}
