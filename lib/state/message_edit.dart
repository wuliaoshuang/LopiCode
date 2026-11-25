// “正在编辑之前的消息”和“交给输入框的草稿”（按工作区分身）。
//
// - 编辑：点了我的一条消息的“编辑”以后，这里记着正在改哪条（[MessageEditState.editing]）。输入框那头（lib/ui/message_edit_bar.dart）
//   看到它就把原文和图片放进输入框、把她原来打了一半的草稿收好；点取消（[MessageEditNotifier.cancel]）就把草稿放回去。
//   这里只记“在改哪条”，真正重发在 lib/session/message_branches.dart。
// - 换了对话、那段对话被删掉：自动取消编辑（草稿照样放回去）。
// - 交接草稿（[MessageEditState.handoff]）：从我的一条消息分支时，把那条的文字和图片交给新分支的输入框；输入框拿走就清掉。
import 'package:lopicode/project_session.dart';
import 'package:lopicode/state/workspace_conversations.dart';
import 'package:riverpod/riverpod.dart';

/// 要放进输入框的一份内容：文字 + 图片附件（`{path, mime}`，path 相对工作区）。
class ComposerDraft {
  ComposerDraft(this.text, List<Map<String, dynamic>> images) : images = List.unmodifiable([for (final i in images) Map<String, dynamic>.unmodifiable(i)]);
  final String text;
  final List<Map<String, dynamic>> images;
}

/// 正在编辑的那条消息。
class EditingMessage {
  const EditingMessage({required this.convId, required this.messageId, required this.original, required this.laterTurns, required this.keepsOld});
  final String convId;
  final String messageId;

  /// 这条消息原来的文字和图片。
  final ComposerDraft original;

  /// 它所在这一轮后面还有几轮（发送后会一起移走）。
  final int laterTurns;

  /// 发送后会不会另存一份旧版本（这条后面有 Agent 的内容或别的轮）。
  final bool keepsOld;
}

class MessageEditState {
  const MessageEditState({this.editing, this.handoff});
  final EditingMessage? editing;
  final ComposerDraft? handoff;
}

class MessageEditNotifier extends Notifier<MessageEditState> {
  MessageEditNotifier(this.session);
  final ProjectSession session;

  @override
  MessageEditState build() {
    // 换了对话：正在编辑的那条不在眼前了，取消
    ref.listen(conversationsProvider(session).select((v) => v.activeId), (_, active) {
      if (state.editing != null && state.editing!.convId != active) cancel();
    });
    return const MessageEditState();
  }

  void _set(MessageEditState next) {
    if (ref.mounted && !session.released) state = next;
  }

  /// 开始编辑（已经在编辑别的一条就换成这条）。
  void start(EditingMessage message) => _set(MessageEditState(editing: message, handoff: state.handoff));

  /// 取消编辑。
  void cancel() {
    if (state.editing != null) _set(MessageEditState(handoff: state.handoff));
  }

  /// 编辑后的消息已经发出去了。
  void finish() => cancel();

  /// 交一份草稿给输入框。
  void handOff(ComposerDraft draft) => _set(MessageEditState(editing: state.editing, handoff: draft));

  /// 输入框把交接的草稿拿走（拿走就清掉）。
  ComposerDraft? takeHandoff() {
    final draft = state.handoff;
    if (draft != null) _set(MessageEditState(editing: state.editing));
    return draft;
  }
}

final messageEditProvider = NotifierProvider.family<MessageEditNotifier, MessageEditState, ProjectSession>(MessageEditNotifier.new);
