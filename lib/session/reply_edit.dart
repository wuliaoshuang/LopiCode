// “编辑 Agent 的回复”里纯计算的那部分：这条能不能改、改完消息记录长什么样。不读盘、不碰状态；
// 真正动手（存盘、换进状态、收藏跟着变）在 message_actions.dart 的 MessageOps.editReply。
//
// 规矩（2026-11-26 真机反馈第五轮自定，可改）：
// - 只改这条 assistant 消息的正文文字。工具调用、工具结果、思考内容、这一轮的用量和改动清单原样不动。
// - 不重新生成、不截断对话、不另存旧版本：就是把这段字换掉。之后发给模型的历史用的是改后的文字。
// - 改过的消息多两个键（都以 `_` 开头，不会发给模型；旧存档没有这两个键，照常读）：
//   `_edited: true`——界面上标“已编辑”；`_orig`——第一次改之前模型的原话，可以在编辑页“恢复原文”。
//   改回和原话一模一样时两个键都拿掉（等于没改过）。
// - 空内容（只有空白）不许保存：要去掉这段回复用“删除”。
// - Anthropic 的原始内容块（`_raw`，下一次请求会原样带回去）里的文字块一起换：新文字放进第一个文字块，其余文字块拿掉；
//   思考块、工具调用块不动（它们的签名只管自己那一块）。
// - 已经被压缩归档的消息也能改：这里显示新的，但顶替它的那份摘要不会跟着变（编辑页会说明）。
import 'package:lopicode/agent/auto_compact.dart';
import 'package:lopicode/agent/message_ids.dart';
import 'package:lopicode/session/message_ops.dart';

/// 这条回复被用户改过。
const String kEditedMark = '_edited';

/// 第一次改之前模型的原话。
const String kOriginalTextKey = '_orig';

/// 空内容不许保存时的说明。
const String kReplyEditEmpty = '内容是空的，不能保存。想去掉这段回复，请用“删除”。';

bool isEditedMessage(Map<String, dynamic> m) => m[kEditedMark] == true;

String? _originalOf(Map<String, dynamic> m) {
  final orig = m[kOriginalTextKey];
  return isEditedMessage(m) && orig is String && orig.isNotEmpty ? orig : null;
}

bool _editable(Map<String, dynamic> m) => m['role'] == 'assistant' && !isCompactPiece(m) && m['content'] is String && (m['content'] as String).isNotEmpty && messageIdOf(m) != null;

/// 打开编辑页要用的东西。
class ReplyEditInfo {
  const ReplyEditInfo({required this.text, required this.original, required this.archived});

  /// 现在的文字。
  final String text;

  /// 模型的原话；没改过是 null。
  final String? original;

  /// 这条已经被压缩进摘要了（改了以后摘要不会跟着变）。
  final bool archived;
}

/// [id] 这条回复现在的样子；找不到、或者它不是一段能改的回复（压缩的承接语、没有文字的）返回 null。
ReplyEditInfo? infoOfReply(List<Map<String, dynamic>> messages, String id) {
  final index = indexOfMessage(messages, id);
  if (index < 0 || !_editable(messages[index])) return null;
  final m = messages[index];
  return ReplyEditInfo(text: m['content'] as String, original: _originalOf(m), archived: isArchived(m));
}

/// 改完以后的样子。
class ReplyEditPlan {
  const ReplyEditPlan({this.error, this.messages = const [], this.changed = false, this.edited = false, this.text = ''});

  /// 不能这么改的原因（给用户看）；能改是 null。
  final String? error;

  /// 新的消息记录（新列表；只有这一条是新的 Map，别的还是原来那个对象）。
  final List<Map<String, dynamic>> messages;

  /// 文字到底变没变（没变就什么都不用存）。
  final bool changed;

  /// 改完以后这条还算不算“已编辑”（改回原话就不算了）。
  final bool edited;

  /// 存进去的文字。
  final String text;
}

Map<String, dynamic> _withText(Map<String, dynamic> m, String text) {
  final next = {...m, 'content': text};
  final raw = m['_raw'];
  if (raw is Map && raw['content'] is List) {
    final blocks = <Object?>[];
    var placed = false;
    for (final b in raw['content'] as List) {
      if (b is Map && b['type'] == 'text') {
        if (!placed) blocks.add(<String, dynamic>{...b.cast<String, dynamic>(), 'text': text});
        placed = true;
      } else {
        blocks.add(b);
      }
    }
    if (!placed) {
      // 原始内容块里没有文字块（不该出现）：放在第一个工具调用前面，没有工具调用就放最后
      final at = blocks.indexWhere((b) => b is Map && b['type'] == 'tool_use');
      blocks.insert(at < 0 ? blocks.length : at, <String, dynamic>{'type': 'text', 'text': text});
    }
    next['_raw'] = <String, dynamic>{...raw.cast<String, dynamic>(), 'content': blocks};
  }
  return next;
}

/// 把 [id] 这段回复的文字换成 [text]。找不到这条、它不是能改的回复返回 null。
ReplyEditPlan? planReplyEdit(List<Map<String, dynamic>> messages, String id, String text) {
  final index = indexOfMessage(messages, id);
  if (index < 0 || !_editable(messages[index])) return null;
  if (text.trim().isEmpty) return const ReplyEditPlan(error: kReplyEditEmpty);
  final m = messages[index];
  final current = m['content'] as String;
  if (text == current) return ReplyEditPlan(messages: messages, edited: isEditedMessage(m), text: text);
  final original = _originalOf(m) ?? current;
  final next = _withText(m, text);
  final edited = text != original;
  if (edited) {
    next[kEditedMark] = true;
    next[kOriginalTextKey] = original;
  } else {
    next
      ..remove(kEditedMark)
      ..remove(kOriginalTextKey);
  }
  return ReplyEditPlan(messages: [...messages]..[index] = next, changed: true, edited: edited, text: text);
}

/// 一轮里 Agent 说的一段话。
class ReplyPart {
  const ReplyPart({required this.id, required this.text, this.edited = false, this.note = false});
  final String id;
  final String text;
  final bool edited;

  /// true＝工具调用之间说的话（那条消息后面跟着工具调用）；false＝正式回复。
  final bool note;
}

/// 每一轮里 Agent 说的话，按先后排（正式回复和工具调用之间的说明都算——界面上它们是同一条内容流里的正文）；
/// 键是操作栏挂着的那一段的 id，和 [lastReplyIdsOf] 一致（动作针对这一整轮的正文）。
Map<String, List<ReplyPart>> turnRepliesOf(List<Map<String, dynamic>> messages) {
  final out = <String, List<ReplyPart>>{};
  var parts = <ReplyPart>[];
  void close() {
    final at = parts.where((p) => !p.note).lastOrNull ?? parts.lastOrNull;
    if (at != null) out[at.id] = parts;
    parts = <ReplyPart>[];
  }

  for (final m in messages) {
    if (isRealUserMessage(m)) {
      close();
      continue;
    }
    final calls = m['tool_calls'];
    final id = messageIdOf(m);
    if (id == null || !_editable(m)) continue;
    parts.add(ReplyPart(id: id, text: m['content'] as String, edited: isEditedMessage(m), note: calls is List && calls.isNotEmpty));
  }
  close();
  return out;
}

/// 复制一整轮的正文：各段之间空一行。
String joinReplyParts(List<ReplyPart> parts) => [for (final p in parts) p.text].join('\n\n');
