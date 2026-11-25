// 设计约束（重试 / 编辑 / 分支 · 390×844）
// 层级：这三个都是“改这段对话走向”的动作，后果要说在前面，但不吓人——旧内容都另存着，没有红色。
// - 操作栏（一排最多 4 个图标）：我的消息常驻“复制、编辑、更多”；Agent 的回复常驻“复制、重试、更多”（重试只在这一轮最后一段回复下面）。
//   “从这里分支”“重新发送”（我的消息上的重试）在“更多”里。这条消息上分出去过对话时多一个分叉图标（强调色，点开列表）；
//   这条同时还收藏着、一排要超过 4 个时，分叉图标让位，进“更多”。
// - “重试”确认面板：标题一行；下面一条一行说清后果（移走什么、存到哪、文件不撤销、用量照算）；最下面一排：取消（弱）、重试（实心，唯一主操作）。
//   这一轮没有任何 Agent 的内容、后面也没有别的轮时不弹面板，直接重发（没有东西会被移走）。
// - “分出去的对话”面板：一行一段对话——图标（分支 / 旧版本）+ 名称 + 小标签，下面一行灰字是时间；点一行就切过去。
// - 右上“···”菜单里的“回到原对话”：只在分支 / 旧版本里出现，一行，名称过长截断。
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lopicode/project_session.dart';
import 'package:lopicode/session/branch_ops.dart';
import 'package:lopicode/session/message_branches.dart';
import 'package:lopicode/state/message_edit.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/favorites_screen.dart' show favoriteTimeLabel;
import 'package:lopicode/ui/message_action_bar.dart';
import 'package:lopicode/ui/model_setup.dart';
import 'package:lopicode/ui/widgets.dart';
import 'package:material_ui/material_ui.dart';

/// 重发以后提示的那句话。
String rewindDoneText(RewindStart start, {required bool edited}) => start.error ?? '${edited ? '已发送修改后的消息' : '已重新发送'}${start.oldVersionId == null ? '。' : '。原来的内容另存成了“旧版本”，在侧边栏的对话列表里。'}';

// ── 登记用的小函数（MessageAction 的字段都是“给一条消息、答一个值”）────────────
bool onReply(MessageTarget t) => !t.mine;
bool onMine(MessageTarget t) => t.mine;
bool hasBranches(MessageTarget t) => t.branches.isNotEmpty;
bool branchesPinned(MessageTarget t) => !t.favorited;
String? rewindBlocked(MessageTarget t) => t.busy ? kRewindWhileBusy : null;
String? branchBlocked(MessageTarget t) => t.session.branches.branchBlocked(t.id);

String retryLabel(MessageTarget t) => t.mine ? '重新发送' : '重试';
IconData retryIcon(MessageTarget t) => Icons.refresh;
String? retryHint(MessageTarget t) => t.mine ? '用这条消息原样再问一遍，从这里重新来' : '用同一条消息让 Agent 重新回答这一轮';
String editLabel(MessageTarget t) => '编辑';
IconData editIcon(MessageTarget t) => Icons.edit_outlined;
String? editHint(MessageTarget t) => '改了再发，从这条消息重新来';
String branchLabel(MessageTarget t) => '从这里分支';
IconData branchIcon(MessageTarget t) => Icons.call_split;
String? branchHint(MessageTarget t) => t.mine ? '另开一段对话：到这条消息之前为止，这条放进输入框。原对话不动' : '另开一段对话：到这段回复为止。原对话不动';
String branchesLabel(MessageTarget t) => '这里分出去的对话（${t.branches.length}）';
IconData branchesIcon(MessageTarget t) => Icons.account_tree_outlined;

// ── 重试 ─────────────────────────────────────────────
Future<void> runRetry(BuildContext context, MessageTarget t) async {
  final s = t.session;
  final plan = s.branches.previewRewind(t.id);
  if (plan == null) return showSnack(context, kMessageGone);
  // 这一行重发以后就不在了（context 跟着失效），提示用的东西先拿好
  final messenger = ScaffoldMessenger.of(context);
  if (plan.worthKeeping) {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => RewindConfirmSheet(plan: plan, title: s.conversationTitle),
    );
    if (ok != true || !context.mounted) return;
  }
  // 没有可用模型就不动这段对话：弹窗说明并带她去配置
  if (!await ensureModelReady(context, current: s.currentModel)) return;
  final start = await s.branches.retry(t.id);
  unawaited(start.turn);
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(rewindDoneText(start, edited: false))));
}

/// 重试之前的确认：说清会移走什么、存到哪。点“重试”返回 true。
class RewindConfirmSheet extends StatelessWidget {
  const RewindConfirmSheet({super.key, required this.plan, required this.title});
  final RewindPlan plan;

  /// 这段对话的名字。
  final String title;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final p = plan;
    final parts = [if (p.replies > 0) '${p.replies} 段话', if (p.steps > 0) '${p.steps} 个步骤'];
    final lines = [
      (Icons.refresh, '用同一条消息重新问一遍${p.images.isEmpty ? '' : '（${p.images.length} 张图片还在）'}，权限和确认照常。'),
      (Icons.drive_file_move_outline, '这一轮${parts.isEmpty ? '' : '里 Agent 的 ${parts.join('、')}'}${p.laterTurns > 0 ? '，连同后面的 ${p.laterTurns} 轮对话，' : ''}会从这段对话里移走。'),
      (Icons.history, '移走的内容不会丢：另存成“$title · 旧版本”，在侧边栏的对话列表里能打开。'),
      if (p.steps > 0 || p.changedFiles) (Icons.description_outlined, 'Agent 已经对文件做过的修改不会撤销。'),
      (Icons.data_usage, '已经花掉的用量不变，重试这一轮照常计入。'),
    ];
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.x6, 0, Space.x6, Space.x3),
            child: Text(p.laterTurns > 0 ? '从这一轮重新来？' : '重试这一轮？', style: t.titleMedium),
          ),
          for (final (icon, text) in lines)
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.x6, 0, Space.x6, Space.x3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Icon(icon, size: 16, color: c.textMuted),
                  ),
                  const SizedBox(width: Space.x3),
                  Expanded(
                    child: Text(text, style: t.bodyMedium?.copyWith(color: c.text, height: 1.45)),
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.x6, Space.x2, Space.x6, Space.x4),
            child: Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    style: TextButton.styleFrom(foregroundColor: c.textMuted, minimumSize: const Size.fromHeight(48)),
                    child: const Text('取消'),
                  ),
                ),
                const SizedBox(width: Space.x3),
                Expanded(
                  child: FilledButton(
                    key: const ValueKey('retry-confirm'),
                    onPressed: () => Navigator.pop(context, true),
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                    child: const Text('重试'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── 编辑 ─────────────────────────────────────────────
Future<void> runEdit(BuildContext context, MessageTarget t) async {
  final plan = t.session.branches.previewRewind(t.id);
  if (plan == null) return showSnack(context, kMessageGone);
  ProviderScope.containerOf(context, listen: false)
      .read(messageEditProvider(t.session).notifier)
      .start(EditingMessage(convId: t.session.activeConversationId, messageId: t.id, original: ComposerDraft(plan.text, plan.images), laterTurns: plan.laterTurns, keepsOld: plan.worthKeeping));
}

// ── 分支 ─────────────────────────────────────────────
Future<void> runBranch(BuildContext context, MessageTarget t) async {
  final messenger = ScaffoldMessenger.of(context);
  final r = await t.session.branches.branch(t.id);
  final String text;
  if (r.error != null) {
    text = r.error!;
  } else if (!r.opened) {
    text = '已另开分支。Agent 停下后，在侧边栏的对话列表里打开它。';
  } else if (r.draftHeld) {
    text = '已另开分支，原对话没有动。这条消息放进了输入框，可以改了再发。';
  } else {
    text = '已另开分支${r.wholeTurn ? '（这段回复在一轮中间，所以带上了这一整轮）' : ''}，原对话没有动。右上角“···”里能回到原对话。';
  }
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));
}

Future<void> runShowBranches(BuildContext context, MessageTarget t) async {
  final id = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (_) => BranchListSheet(branches: t.branches),
  );
  if (id == null || !context.mounted) return;
  final failed = await t.session.branches.openConversation(id);
  if (failed != null && context.mounted) showSnack(context, failed);
}

/// 这条消息上分出去的对话。点一行返回那段对话的 id。
class BranchListSheet extends StatelessWidget {
  const BranchListSheet({super.key, required this.branches});
  final List<Conversation> branches;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.x6, 0, Space.x6, Space.x2),
              child: Text('这里分出去的对话', style: t.titleMedium),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final b in branches)
                    ListTile(
                      key: ValueKey('branch-${b.id}'),
                      leading: Icon(b.origin?.old ?? false ? Icons.history : Icons.call_split, color: c.textMuted),
                      title: ConversationLabel(conv: b, style: t.bodyLarge),
                      subtitle: Text(favoriteTimeLabel(b.updatedAt), style: t.bodySmall),
                      onTap: () => Navigator.pop(context, b.id),
                    ),
                ],
              ),
            ),
            const SizedBox(height: Space.x2),
          ],
        ),
      ),
    );
  }
}

/// 对话的名字，分支 / 旧版本后面跟一个小标签。一行，名字过长截断，标签不被挤掉。
class ConversationLabel extends StatelessWidget {
  const ConversationLabel({super.key, required this.conv, this.style});
  final Conversation conv;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final tag = conv.origin?.tag;
    final name = Text(conv.title.isEmpty ? '新对话' : conv.title, style: style, maxLines: 1, overflow: TextOverflow.ellipsis);
    if (tag == null) return name;
    return Row(
      children: [
        Flexible(child: name),
        const SizedBox(width: Space.x2),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: Space.x2, vertical: 1),
          decoration: BoxDecoration(color: c.surfaceMuted, borderRadius: BorderRadius.circular(Radii.sm)),
          child: Text(tag, style: t.labelSmall?.copyWith(color: c.textMuted)),
        ),
      ],
    );
  }
}

// ── 回到原对话（聊天页右上“···”菜单）────────────────────
/// 当前对话是分支 / 旧版本时，菜单里多的那一项（不是就没有）。
List<PopupMenuEntry<String>> originMenuItems(ProjectSession s) {
  final origin = s.activeConversation.origin;
  if (origin == null) return const [];
  return [
    PopupMenuItem(
      value: 'origin',
      enabled: !s.agentBusy,
      child: Text('回到原对话：${origin.title}', maxLines: 1, overflow: TextOverflow.ellipsis),
    ),
  ];
}

Future<void> openBranchOrigin(BuildContext context, ProjectSession s) async {
  final failed = await s.branches.openOrigin();
  if (failed != null && context.mounted) showSnack(context, failed);
}
