// 重试 / 编辑 / 分支里“纯计算”的那部分：从哪条消息重新来、会移走什么、另开的那段对话抄哪些消息。
// 不读盘、不碰状态；真正动手（另存、截断、重发、切对话）在 message_branches.dart。
//
// 规矩（2026-11-25 自定，可改）：
// - 重试＝用这一轮“我的那条消息”再发一遍；编辑＝把那条消息换成新的再发。两者是同一个动作“从这条消息重新来”：
//   这条消息和它后面的全部内容从这段对话里移走（[planRewind]），然后照常发送。
//   被移走的只要有 Agent 的内容（回复、步骤）或后面还有别的轮，就先整段另存成一段“旧版本”对话，不直接丢。
// - 分支＝另开一段对话，原对话一个字不动（[planBranch]）：
//   从 Agent 的一段回复分支：抄到这段回复为止（含它）；要是这样抄出来的记录发给模型会被拒绝，就抄到这一轮结束。
//   从我的一条消息分支：抄到这条消息之前，这条的文字和图片放进输入框（可以改了再发）。
// - 截在压缩过的地方（[restoreLiveTail]）：截断后留下的最后一份摘要和它后面的内容重新变回“发给模型的”，
//   摘要之前的仍然是归档；一份摘要都没留下，就全部变回来。也就是回到“那时候”模型看到的样子。
// - 抄出去的消息保留原来的 id（id 只要求一段对话里不重复），所以收藏、跳转在两边认的是同一条。
import 'dart:convert';

import 'package:lopicode/agent/auto_compact.dart';
import 'package:lopicode/agent/message_ids.dart';
import 'package:lopicode/session/chat_items.dart' show kChildLinksKey;
import 'package:lopicode/session/message_ops.dart';

/// 深拷贝一份消息记录（两段对话不能共用同一批 Map）。
List<Map<String, dynamic>> cloneMessages(Iterable<Map<String, dynamic>> messages) => [for (final m in messages) (jsonDecode(jsonEncode(m)) as Map).cast<String, dynamic>()];

/// 截断之后：最后一份摘要和它后面的内容不再算归档（见文件开头）。返回新列表，改过的消息是新的 Map。
List<Map<String, dynamic>> restoreLiveTail(List<Map<String, dynamic>> kept) {
  final from = kept.lastIndexWhere((m) => m[kCompactMark] == true);
  return [
    for (var i = 0; i < kept.length; i++)
      if (i >= from && isArchived(kept[i])) ({...kept[i]}..remove(kArchivedMark)) else kept[i],
  ];
}

List<Map<String, dynamic>> _imagesOf(Map<String, dynamic> m) {
  final images = m['_images'];
  return [
    for (final i in images is List ? images : const [])
      if (i is Map) i.cast<String, dynamic>(),
  ];
}

List<Object?> _calls(Map<String, dynamic> m) {
  final calls = m['tool_calls'];
  return m['role'] == 'assistant' && calls is List ? calls : const [];
}

bool _operable(Map<String, dynamic> m) => !isCompactPiece(m) && (isRealUserMessage(m) || m['role'] == 'assistant');

/// 最后一条“我的消息”的位置（正在跑的那一轮从它开始）；没有是 -1。
int lastTurnStart(List<Map<String, dynamic>> messages) => messages.lastIndexWhere(isRealUserMessage);

/// “从这条消息重新来”之前先算好的东西。
class RewindPlan {
  const RewindPlan({
    required this.userId,
    required this.text,
    required this.images,
    required this.kept,
    required this.anchorId,
    required this.laterTurns,
    required this.replies,
    required this.steps,
    required this.changedFiles,
    required this.goneIds,
    required this.goneCallIds,
  });

  /// 这一轮“我的那条消息”：id、原文、图片附件（`{path, mime}`）。
  final String? userId;
  final String text;
  final List<Map<String, dynamic>> images;

  /// 截断以后留下的记录（新列表）。
  final List<Map<String, dynamic>> kept;

  /// 留下的记录里最后一条看得见的消息的 id（旧版本“回到原对话”时滚到它）；没有是 null。
  final String? anchorId;

  /// 这一轮后面还有几轮会一起移走。
  final int laterTurns;

  /// 被移走的内容里：Agent 的几段话、几个步骤、有没有改过文件。
  final int replies;
  final int steps;
  final bool changedFiles;

  /// 被移走的消息 id、工具调用 id（派子代理的那几次，子对话跟着旧版本走）。
  final Set<String> goneIds;
  final Set<String> goneCallIds;

  /// 被移走的东西值不值得另存：有 Agent 的内容，或者后面还有别的轮。
  bool get worthKeeping => replies > 0 || steps > 0 || laterTurns > 0;
}

/// 从 [id] 这条消息所在那一轮“我的消息”处重新来。找不到这条、它前面没有我的消息（压缩摘要后面的承接语之类）返回 null。
RewindPlan? planRewind(List<Map<String, dynamic>> messages, String id) {
  final index = indexOfMessage(messages, id);
  if (index < 0 || !_operable(messages[index])) return null;
  var start = index;
  while (start >= 0 && !isRealUserMessage(messages[start])) {
    start--;
  }
  if (start < 0) return null;
  final mine = messages[start];
  var later = 0, replies = 0, steps = 0, changed = false;
  final goneIds = <String>{};
  final goneCalls = <String>{};
  for (var i = start; i < messages.length; i++) {
    final m = messages[i];
    final mid = messageIdOf(m);
    if (mid != null) goneIds.add(mid);
    if (i > start && isRealUserMessage(m)) later++;
    if (m['role'] == 'assistant' && !isCompactPiece(m)) {
      if (m['content'] is String && (m['content'] as String).isNotEmpty) replies++;
      for (final c in _calls(m)) {
        steps++;
        if (c is Map) goneCalls.add('${c['id']}');
      }
    }
    if (m['_files'] is List || m['_diff'] != null) changed = true;
  }
  final kept = tidyForWire(restoreLiveTail(messages.sublist(0, start)));
  String? anchor;
  for (final m in kept.reversed) {
    if (_operable(m) && m['content'] is String && (m['content'] as String).isNotEmpty && _calls(m).isEmpty) {
      anchor = messageIdOf(m);
      break;
    }
  }
  return RewindPlan(
    userId: messageIdOf(mine),
    text: '${mine['content'] ?? ''}',
    images: _imagesOf(mine),
    kept: kept,
    anchorId: anchor,
    laterTurns: later,
    replies: replies,
    steps: steps,
    changedFiles: changed,
    goneIds: goneIds,
    goneCallIds: goneCalls,
  );
}

/// “从这里分支”抄出来的东西。
class BranchPlan {
  const BranchPlan({required this.messages, required this.draftText, required this.draftImages, required this.wholeTurn, required this.turns});

  /// 新对话的消息记录（深拷贝，和原对话不共用任何对象）。
  final List<Map<String, dynamic>> messages;

  /// 从我的消息分支时：这条消息的文字和图片，交给输入框。从回复分支时是 null / 空。
  final String? draftText;
  final List<Map<String, dynamic>> draftImages;

  /// 只抄到那段回复会让记录不合法，所以抄到了这一轮结束。
  final bool wholeTurn;

  /// 抄过去几轮（我的消息条数）。
  final int turns;
}

/// 从 [id] 这条消息分支。找不到这条（或它是压缩摘要、应用通知、工具结果）返回 null。
BranchPlan? planBranch(List<Map<String, dynamic>> messages, String id) {
  final index = indexOfMessage(messages, id);
  if (index < 0 || !_operable(messages[index])) return null;
  final m = messages[index];
  final mine = isRealUserMessage(m);
  List<Map<String, dynamic>> upTo(int end) => restoreLiveTail(cloneMessages(messages.sublist(0, end)));
  var copy = upTo(mine ? index : index + 1);
  var whole = false;
  // 截在一轮中间时，抄出来的记录必须能发给模型：不行就抄到这一轮结束（这一轮本来就是完整的）
  if (!mine && wireProblems(copy).isNotEmpty) {
    final wider = upTo(turnRangeAt(messages, index).end);
    if (wireProblems(wider).length < wireProblems(copy).length) {
      copy = wider;
      whole = true;
    }
  }
  copy = tidyForWire(copy);
  return BranchPlan(
    messages: copy,
    draftText: mine ? '${m['content'] ?? ''}' : null,
    draftImages: mine ? cloneMessages(_imagesOf(m)) : const [],
    wholeTurn: whole,
    turns: copy.where(isRealUserMessage).length,
  );
}

/// 给抄出去的记录里每次 spawn_agent 调用记上“原来对应哪段子对话”（[links]：调用 id → 子对话 id）。就地改。
void stampChildLinks(List<Map<String, dynamic>> copy, Map<String, String> links) {
  if (links.isEmpty) return;
  for (final m in copy) {
    final mine = <String, String>{
      for (final c in _calls(m))
        if (c is Map && links.containsKey('${c['id']}')) '${c['id']}': links['${c['id']}']!,
    };
    if (mine.isEmpty) continue;
    final had = m[kChildLinksKey];
    m[kChildLinksKey] = {if (had is Map) ...had, ...mine};
  }
}
