// 对当前对话里的一条消息动手：删一条 / 删一轮、导出成 Markdown、收藏。
// 算法（删完长什么样、合不合法）在 message_ops.dart；这里负责换进状态、存盘、通知收藏。
// 界面通过 ProjectSession.messageOps 用它。重试 / 编辑 / 分支以后也加在这里（它们要用的 [deleteTurn] 这类底层方法已经在了）。
import 'package:lopicode/agent/message_ids.dart';
import 'package:lopicode/session/chat_export.dart';
import 'package:lopicode/session/chat_models.dart';
import 'package:lopicode/session/favorites.dart';
import 'package:lopicode/session/message_ops.dart';
import 'package:lopicode/session/message_ops.dart' as ops show previewDelete;
import 'package:lopicode/session/session_core.dart';
import 'package:lopicode/state/workspace_chat.dart';
import 'package:lopicode/state/workspace_favorites.dart';

/// Agent 正在回复时不能删：说明原因的那句话。
const String kDeleteWhileBusy = 'Agent 正在回复，等它停下再删。';

class MessageOps {
  MessageOps(this.core, {required this.dropConversations});

  final SessionCore core;

  /// 把这些对话（子代理的）连同它们的文件删掉（ProjectSession 里那套）。
  final Future<void> Function(List<String> ids) dropConversations;

  ChatRunNotifier get _run => core.active;

  FavoritesNotifier? get _favorites => core.app.disposed ? null : core.app.container.read(favoritesProvider(core.session).notifier);

  /// 当前对话的消息记录里 [id] 这条（没有是 null）。只读，别改它。
  Map<String, dynamic>? messageById(String id) {
    final i = indexOfMessage(_run.messages, id);
    return i < 0 ? null : _run.messages[i];
  }

  /// 当前对话里每一轮最后一段回复的 id（整轮级别的操作挂在它下面）。
  Set<String> get lastReplyIds => lastReplyIdsOf(_run.messages);

  // ── 删除 ─────────────────────────────────────────────
  /// 删之前先算：两种删法各自行不行、会带走什么。这条不在记录里返回 null。
  DeletePreview? previewDelete(String id) => ops.previewDelete(_run.messages, id);

  /// 这一轮里派出去的子代理对话（整轮删时会一起删）。
  List<String> childConversationsOf(DeleteResult result) => [
    for (final item in _run.items)
      // 只算这段对话自己派出去的：分支 / 旧版本里抄来的调用连着的是原对话的子代理，不归这里删
      if (item is ToolItem && item.childConversationId != null && result.goneCallIds.contains(item.callId) && core.dir.byId(item.childConversationId)?.parentId == _run.convId)
        item.childConversationId!,
  ];

  /// 删一条 / 删一整轮。成功返回 null；没删成返回原因（给用户看）。
  ///
  /// - Agent 正在回复时一律不删（它手里正拿着这份记录在跑，中途改会对不上）。
  /// - 不回滚文件改动，不改对话累计用量。
  /// - 删完马上存盘（原子写）；界面条目从记录重建，所以和重开对话看到的一样。
  Future<String?> delete(String id, DeleteScope scope) async {
    final run = _run;
    if (run.busy) return kDeleteWhileBusy;
    final preview = ops.previewDelete(run.messages, id);
    if (preview == null) return '这条消息已经不在记录里了。';
    final result = preview.of(scope);
    if (result == null) return preview.singleBlocked;
    final kids = childConversationsOf(result);
    // “上一轮没正常结束”的提示不在消息记录里，重建条目后要放回去
    final interrupted = [...run.items.whereType<InterruptedItem>()];
    run.messages = result.messages;
    core.rebuildItems(run);
    for (final card in interrupted) {
      run.add(card);
    }
    // 上次请求的 token 数对不上现在的记录了：上下文占用改回估算
    core.convs?.update(run.convId, (c) => c.copyWith(clearLastInput: true));
    if (kids.isNotEmpty) await dropConversations(kids);
    await core.saveRun(run);
    await _favorites?.markGone(run.convId, result.goneIds);
    return null;
  }

  // ── 分享 ─────────────────────────────────────────────
  /// 这一条（[wholeTurn]＝这一整轮：我的提问 + 步骤 + 回复）的 Markdown。像密钥的内容已经抹掉。不在记录里返回 null。
  String? markdownOf(String id, {required bool wholeTurn}) {
    final part = messagesForShare(_run.messages, id, wholeTurn: wholeTurn);
    if (part == null) return null;
    final title = _run.conv.title.isEmpty ? '新对话' : _run.conv.title;
    return conversationMarkdown(title, part);
  }

  /// 存成工作区里的文件（exports/消息-日期-时间.md），返回相对路径。不在记录里返回 null。
  Future<String?> saveMarkdown(String id, {required bool wholeTurn, DateTime? now}) async {
    final markdown = markdownOf(id, wholeTurn: wholeTurn);
    if (markdown == null) return null;
    final rel = await writeConversationExport(core.guard, markdown, now: now, prefix: '消息');
    core.filesChanged();
    return rel;
  }

  // ── 收藏 ─────────────────────────────────────────────
  /// 收藏 / 取消收藏当前对话里的一条。返回现在是不是收藏着；这条没有稳定标识（还在往外冒）返回 null。
  Future<bool?> toggleFavorite(ChatItem item) async {
    final (id, role, text) = switch (item) {
      UserItem(:final id, :final text) => (id, 'user', text),
      AssistantItem(:final id, :final text) => (id, 'assistant', text),
      _ => (null, '', ''),
    };
    final favorites = _favorites;
    if (id == null || favorites == null) return null;
    return favorites.toggle(convId: _run.convId, messageId: id, role: role, text: text, convTitle: _run.conv.title);
  }

  /// 收藏页里的一条现在还找不找得到原消息（对话没了、消息被删了都算找不到）。
  bool favoriteMissing(FavoriteMessage f) => f.gone || core.dir.byId(f.convId) == null;
}
