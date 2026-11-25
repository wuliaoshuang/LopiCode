// 设计约束（“正在编辑之前的消息”提示条 · 390×844）
// - 输入区上方的一条窄条（和“计划模式”“自动允许中”同一种样子）：左边铅笔图标 + 一句话（在编辑、发送以后会怎样），右边唯一的按钮“取消”。
//   最多两行；它在 KeyboardDock 线以下，点“取消”不收键盘。
// - 进入编辑：这条消息的文字和图片放进输入框，她原来打了一半的草稿（文字 + 图片）先收好；
//   点“取消”、换了对话：草稿原样放回去。改完点发送＝从这条消息重新来（规矩见 lib/session/message_branches.dart）。
// - 聊天页只接三处：建一个 [ComposerEditBinding]、发送前问它一句、输入区上方放 [MessageEditBar]。
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lopicode/project_session.dart';
import 'package:lopicode/state/message_edit.dart';
import 'package:lopicode/ui/chat_panels.dart';
import 'package:lopicode/ui/message_branch_actions.dart';
import 'package:lopicode/ui/model_setup.dart';
import 'package:lopicode/ui/widgets.dart';
import 'package:material_ui/material_ui.dart';

/// 把“正在编辑哪条”和聊天页的输入框接起来：放进去、收好草稿、取消时放回、发送时改走“从这条重新来”。
class ComposerEditBinding {
  ComposerEditBinding({required this.session, required this.input, required this.attachments, required this.focus, required this.changed});

  final ProjectSession session;
  final TextEditingController input;

  /// 聊天页那份“还没发出去的图片附件”（就地改）。
  final List<Map<String, dynamic>> attachments;
  final FocusNode focus;

  /// 附件变了：让聊天页重画。
  final VoidCallback changed;

  late WidgetRef _ref;
  ComposerDraft? _saved;
  bool _disposed = false;

  /// 在聊天页的 initState 里接上（页面销毁时订阅自动取消）。
  void attach(WidgetRef ref) {
    _ref = ref;
    ref.listenManual(messageEditProvider(session), _onChange, fireImmediately: true);
  }

  void dispose() => _disposed = true;

  void _load(ComposerDraft draft) {
    input.value = TextEditingValue(
      text: draft.text,
      selection: TextSelection.collapsed(offset: draft.text.length),
    );
    attachments
      ..clear()
      ..addAll([for (final i in draft.images) Map<String, dynamic>.of(i)]);
    changed();
  }

  void _onChange(MessageEditState? prev, MessageEditState next) {
    if (_disposed) return;
    final was = prev?.editing, now = next.editing;
    if (now != null && (was == null || was.messageId != now.messageId || was.convId != now.convId)) {
      // 连着点两条“编辑”：收好的仍然是最开始那份草稿
      _saved ??= ComposerDraft(input.text, attachments);
      _load(now.original);
      focus.requestFocus();
    } else if (now == null && was != null) {
      final saved = _saved;
      _saved = null;
      if (saved != null) _load(saved);
    }
    if (next.handoff != null) {
      // 通知里不能再改状态：等这一拍过去再拿走
      scheduleMicrotask(() {
        if (_disposed) return;
        final draft = _ref.read(messageEditProvider(session).notifier).takeHandoff();
        // 输入框里已经有她自己的草稿：不盖
        if (draft != null && input.text.isEmpty && attachments.isEmpty) _load(draft);
      });
    }
  }

  /// 发送前问一句：正在编辑就按“改了再发”处理并返回 true（聊天页不用再发）；没在编辑返回 false。
  Future<bool> sendIfEditing(BuildContext context, String text) async {
    final editing = _ref.read(messageEditProvider(session)).editing;
    if (editing == null) return false;
    final messenger = ScaffoldMessenger.of(context);
    // 没有可用模型就不动这段对话：弹窗说明并带她去配置，编辑状态留着
    if (!await ensureModelReady(context, current: session.currentModel) || _disposed) return true;
    final start = await session.branches.resendEdited(editing.messageId, text, [for (final i in attachments) Map<String, dynamic>.of(i)]);
    if (_disposed) return true;
    if (start.error == null) {
      unawaited(start.turn);
      // 发出去了：收着的旧草稿不用放回（她刚才改的就是输入框里这份）
      _saved = null;
      _ref.read(messageEditProvider(session).notifier).finish();
      input.clear();
      attachments.clear();
      changed();
    }
    if (start.error != null || start.oldVersionId != null) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(rewindDoneText(start, edited: true))));
    }
    return true;
  }
}

/// 输入区上方的“正在编辑之前的消息”。没在编辑时不占地方。
class MessageEditBar extends ConsumerWidget {
  const MessageEditBar({super.key, required this.session});
  final ProjectSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final editing = ref.watch(messageEditProvider(session).select((v) => v.editing));
    if (editing == null) return const SizedBox.shrink();
    final after = editing.laterTurns > 0 ? '这一轮和后面 ${editing.laterTurns} 轮' : '它后面的内容';
    return StatusChipRow(
      key: const ValueKey('edit-chip'),
      icon: Icons.edit_outlined,
      text: '正在编辑之前的消息。发送后从这条重新来${editing.keepsOld ? '，$after另存为旧版本' : ''}',
      action: '取消',
      tone: BannerTone.info,
      onTap: () => ref.read(messageEditProvider(session).notifier).cancel(),
    );
  }
}
