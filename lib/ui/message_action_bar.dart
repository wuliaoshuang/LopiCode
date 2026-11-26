// 设计约束（聊天消息下面的操作栏 · 390×844）
// 层级：正文最重；操作栏是次要内容——图标 16、最淡的灰（textFaint），不带底色、不带文字，紧贴在气泡下面、和气泡同侧对齐。
// - 一条消息下面只有一排，常驻四个按钮，位置固定（2026-11-26 真机反馈第五轮，霜霜：“消息气泡底下有四个按钮”）：
//   我的消息：复制、编辑、重新发送、更多；Agent 的回复：复制、编辑、重试、更多。其余动作（分支、收藏、分享、删除）收进“更多”面板，一行一个。
//   Agent 的一轮只在最后一段正文下面出现一次（2026-11-26 11:52 协调者补充：之后 Agent 一整轮会画成一条连续的内容流，操作栏在末尾只有一排）。
//   所以这一排管的是“这一轮的正文”（[MessageTarget.parts]）：复制＝各段连起来；编辑＝只有一段直接改，有几段先选改哪一段；
//   重试＝重试这一轮；“更多”里的分支、收藏、分享、删除照旧针对最后一段。
// - 四个按钮之外只放“状态记号”，不放别的动作：收藏着是实心书签（点它＝取消收藏）、分出过对话是强调色分叉（点开列表）、
//   改过的回复是一个很淡的“已编辑”。记号排在四个按钮的外侧（Agent 的回复在右边，我的消息在左边），所以四个按钮的位置不跟着变。
//   最挤的时候是 4 个按钮 + 2 个记号 + “已编辑”，约 310 宽，390 的屏放得下。
// - 每个图标的可点区域 44×44。
// - 只挂在“我的消息”和“Agent 的正式回复”下面；步骤组、思考、脚注、提示下面没有。还在往外冒的回复没有操作栏。
//
// 怎么加一个新动作：在本文件末尾的 [kMessageActions] 里登记一条 [MessageAction]（见那里的说明），别的地方都不用动。
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lopicode/project_session.dart';
import 'package:lopicode/session/message_actions.dart';
import 'package:lopicode/session/reply_edit.dart';
import 'package:lopicode/state/workspace_chat.dart';
import 'package:lopicode/state/workspace_conversations.dart';
import 'package:lopicode/state/workspace_favorites.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/message_branch_actions.dart';
import 'package:lopicode/ui/message_reply_editor.dart';
import 'package:lopicode/ui/message_sheets.dart';
import 'package:lopicode/ui/widgets.dart';
import 'package:material_ui/material_ui.dart';

/// 动作在“更多”面板里的先后（也是常驻图标从左到右的先后）。
enum MessageActionSlot { copy, edit, retry, branch, branches, favorite, share, delete }

/// 常驻的四个按钮里除“更多”以外的三个位置。别的动作就算常驻，也只算状态记号，排在外侧。
const Set<MessageActionSlot> kCoreSlots = {MessageActionSlot.copy, MessageActionSlot.edit, MessageActionSlot.retry};

/// 操作栏点的是哪条消息。
class MessageTarget {
  const MessageTarget({
    required this.session,
    required this.item,
    required this.id,
    required this.mine,
    required this.text,
    required this.busy,
    required this.turnLast,
    required this.favorited,
    this.branches = const [],
    this.edited = false,
    this.parts = const [],
  });

  final ProjectSession session;

  /// [UserItem] 或 [AssistantItem]。
  final ChatItem item;

  /// 消息的稳定标识（消息记录里的 `_id`）。底层方法都认它：`session.messageOps.xxx(target.id)`。
  final String id;

  /// true＝我的消息；false＝Agent 的回复。
  final bool mine;

  /// 这一条的文字（Markdown 原文）。
  final String text;

  /// 这段对话是不是正在生成。
  final bool busy;

  /// 是不是这一轮最后一段回复（整轮级别的动作只挂在它下面）。
  final bool turnLast;
  final bool favorited;

  /// 从这条消息分出去的对话（分支和旧版本）。
  final List<Conversation> branches;

  /// 这一轮的正文里有用户改过的段。
  final bool edited;

  /// Agent 的回复：这一轮的正式回复段，按先后排，最后一段就是 [id]。我的消息是空的。
  /// 复制、编辑针对的是这个列表——以后改成“针对整轮”只要换这里装的东西。
  final List<ReplyPart> parts;

  /// 复制用的文字：Agent 的回复是这一轮各段正文连起来。
  String get copyText => parts.length > 1 ? joinReplyParts(parts) : text;
}

/// 一个消息动作。全部字段都是“给一条消息、答一个值”，所以同一个动作可以按消息变样子（收藏 / 取消收藏）。
class MessageAction {
  const MessageAction({
    required this.slot,
    required this.label,
    required this.icon,
    required this.run,
    this.hint,
    this.appliesTo,
    this.pinned,
    this.disabledReason,
    this.turnLevel = false,
    this.danger = false,
  });

  final MessageActionSlot slot;
  final String Function(MessageTarget t) label;
  final IconData Function(MessageTarget t) icon;

  /// “更多”面板里名称下面那句灰色说明；不需要就不给。
  final String? Function(MessageTarget t)? hint;

  /// 这条消息有没有这个动作（不给＝都有）。
  final bool Function(MessageTarget t)? appliesTo;

  /// 要不要常驻在操作栏上（不给＝收进“更多”）。
  final bool Function(MessageTarget t)? pinned;

  /// 现在不能用的原因（能用返回 null）。不能用时“更多”里那一行变灰并写出原因；常驻图标变灰，点了提示原因。
  final String? Function(MessageTarget t)? disabledReason;

  /// 整轮级别的动作：只在这一轮最后一段回复下面出现。（Agent 的操作栏本来就只挂在那里，现在登记的动作都不用它。）
  final bool turnLevel;

  /// 危险动作（删除）：“更多”里用红色。
  final bool danger;

  /// 点了以后做什么。[context] 是聊天页的（“更多”面板已经关掉）。
  final Future<void> Function(BuildContext context, MessageTarget t) run;

  bool _on(MessageTarget t) => (appliesTo?.call(t) ?? true) && (!turnLevel || t.turnLast);
}

/// 聊天页把“消息操作需要的东西”放在这里，行里的操作栏从这里取。没有它（子代理对话页、测试台）就不显示操作栏。
class MessageOpsScope extends InheritedWidget {
  const MessageOpsScope({
    super.key,
    required super.child,
    required this.session,
    required this.busy,
    required this.lastReplyIds,
    required this.favoriteIds,
    this.turnReplies = const {},
    this.branches = const {},
    this.flash,
    this.actions = kMessageActions,
  });

  final ProjectSession session;
  final bool busy;
  final Set<String> lastReplyIds;

  /// 每一轮的正式回复段（键＝这一轮最后一段的 id）。没给＝每一轮只当它有最后那一段。
  final Map<String, List<ReplyPart>> turnReplies;

  String get _replySig => [
    for (final e in turnReplies.entries) '${e.key}:${[for (final p in e.value) '${p.id}/${p.edited}/${p.text.hashCode}'].join(',')}',
  ].join(';');

  /// 当前对话里收藏着的消息 id。
  final Set<String> favoriteIds;

  /// 消息 id → 从它分出去的对话（分支和旧版本）。
  final Map<String, List<Conversation>> branches;

  String get _branchSig => [
    for (final e in branches.entries) '${e.key}:${[for (final c in e.value) '${c.id}/${c.title}'].join(',')}',
  ].join(';');

  /// 刚从收藏页跳回来的那条消息的 id（短暂高亮）。
  final ValueListenable<String?>? flash;
  final List<MessageAction> actions;

  static MessageOpsScope? maybeOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<MessageOpsScope>();

  @override
  bool updateShouldNotify(MessageOpsScope old) =>
      old.session != session ||
      old.busy != busy ||
      old.flash != flash ||
      old.actions != actions ||
      old._branchSig != _branchSig ||
      old._replySig != _replySig ||
      !setEquals(old.lastReplyIds, lastReplyIds) ||
      !setEquals(old.favoriteIds, favoriteIds);
}

/// 聊天页用它包住消息列表：订阅“忙不忙”和收藏，把 [MessageOpsScope] 备好。
class MessageOpsHost extends ConsumerStatefulWidget {
  const MessageOpsHost({super.key, required this.session, required this.child, this.flash, this.actions = kMessageActions});
  final ProjectSession session;
  final Widget child;
  final ValueListenable<String?>? flash;
  final List<MessageAction> actions;

  @override
  ConsumerState<MessageOpsHost> createState() => _MessageOpsHostState();
}

class _MessageOpsHostState extends ConsumerState<MessageOpsHost> {
  @override
  void initState() {
    super.initState();
    // 搭界面的过程中不能改状态：推后一拍再读收藏
    Future.microtask(() {
      if (mounted) ref.read(favoritesProvider(widget.session).notifier).load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.session;
    final chat = ref.watch(activeChatProvider(s));
    final favorites = ref.watch(favoritesProvider(s));
    ref.watch(conversationsProvider(s)); // 分出去的对话多了 / 少了 / 改名了
    final conv = s.activeConversationId;
    return MessageOpsScope(
      session: s,
      busy: chat.busy,
      lastReplyIds: s.messageOps.lastReplyIds,
      turnReplies: s.messageOps.turnReplies,
      favoriteIds: {
        for (final f in favorites.items)
          if (f.convId == conv) f.messageId,
      },
      branches: s.branches.branchesByMessage,
      flash: widget.flash,
      actions: widget.actions,
      child: widget.child,
    );
  }
}

/// 把一条消息的气泡和它下面的操作栏叠成一块。[child] 是气泡。
class MessageFrame extends StatelessWidget {
  const MessageFrame({super.key, required this.item, required this.child});
  final ChatItem item;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scope = MessageOpsScope.maybeOf(context);
    final (id, mine, text, streaming) = switch (item) {
      UserItem(:final id, :final text) => (id, true, text, false),
      AssistantItem(:final id, :final text, :final streaming) => (id, false, text, streaming),
      _ => (null, false, '', false),
    };
    if (scope == null || id == null || streaming) return child;
    final turnLast = scope.lastReplyIds.contains(id);
    final parts = mine ? const <ReplyPart>[] : (scope.turnReplies[id] ?? const <ReplyPart>[]);
    final ownEdited = switch (item) {
      AssistantItem(:final edited) => edited,
      _ => false,
    };
    // Agent 的一轮只在最后一段正文下面有操作栏；中间的段没有（从收藏页跳回来的高亮照常有）
    final target = !mine && !turnLast
        ? null
        : MessageTarget(
            session: scope.session,
            item: item,
            id: id,
            mine: mine,
            text: text,
            busy: scope.busy,
            turnLast: turnLast,
            favorited: scope.favoriteIds.contains(id),
            branches: scope.branches[id] ?? const [],
            edited: ownEdited || parts.any((p) => p.edited),
            parts: parts,
          );
    final block = target == null
        ? child
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              child,
              MessageActionBar(target: target, actions: scope.actions),
            ],
          );
    final flash = scope.flash;
    if (flash == null) return block;
    final c = context.colors;
    return ValueListenableBuilder<String?>(
      valueListenable: flash,
      child: block,
      builder: (context, flashing, child) => AnimatedContainer(
        key: ValueKey('message-frame-$id'),
        duration: const Duration(milliseconds: 250),
        // 描一圈边（不铺底色：我的消息气泡本身就是这个浅色，铺了会糊成一片）
        foregroundDecoration: BoxDecoration(
          border: Border.all(color: flashing == id ? c.accent : c.accent.withValues(alpha: 0), width: 1.5),
          borderRadius: BorderRadius.circular(Radii.lg),
        ),
        child: child,
      ),
    );
  }
}

/// 一条消息下面的那排小图标。
class MessageActionBar extends StatelessWidget {
  const MessageActionBar({super.key, required this.target, required this.actions});
  final MessageTarget target;
  final List<MessageAction> actions;

  @override
  Widget build(BuildContext context) {
    final t = target;
    final all = [...actions.where((a) => a._on(t))]..sort((a, b) => a.slot.index.compareTo(b.slot.index));
    final pinned = [...all.where((a) => a.pinned?.call(t) ?? false)];
    final rest = [...all.where((a) => !pinned.contains(a))];
    if (all.isEmpty) return const SizedBox.shrink();
    Widget button(MessageAction a) => _BarIcon(
      key: ValueKey('message-${a.slot.name}-${t.id}'),
      icon: a.icon(t),
      label: a.label(t),
      active: (a.slot == MessageActionSlot.favorite && t.favorited) || a.slot == MessageActionSlot.branches,
      disabled: a.disabledReason?.call(t) != null,
      onTap: () => runMessageAction(context, a, t),
    );
    // 四个按钮：位置固定
    final core = [
      for (final a in pinned)
        if (kCoreSlots.contains(a.slot)) button(a),
      if (rest.isNotEmpty) _BarIcon(key: ValueKey('message-more-${t.id}'), icon: Icons.more_horiz, label: '更多操作', onTap: () => _openMore(context, rest)),
    ];
    // 状态记号：排在四个按钮的外侧
    final marks = [
      for (final a in pinned)
        if (!kCoreSlots.contains(a.slot)) button(a),
      if (t.edited)
        Flexible(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.x1),
            child: Text(
              '已编辑',
              key: ValueKey('message-edited-${t.id}'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(color: context.colors.textFaint),
            ),
          ),
        ),
    ];
    return Align(
      alignment: t.mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Row(key: ValueKey('message-actions-${t.id}'), mainAxisSize: MainAxisSize.min, children: t.mine ? [...marks.reversed, ...core] : [...core, ...marks]),
    );
  }

  Future<void> _openMore(BuildContext context, List<MessageAction> rest) async {
    final picked = await showModalBottomSheet<MessageAction>(
      context: context,
      isScrollControlled: true,
      builder: (_) => MessageMoreSheet(target: target, actions: rest),
    );
    if (picked != null && context.mounted) await runMessageAction(context, picked, target);
  }
}

/// 执行一个动作；现在不能用就说明原因。
Future<void> runMessageAction(BuildContext context, MessageAction action, MessageTarget target) async {
  final why = action.disabledReason?.call(target);
  if (why != null) return showSnack(context, why);
  await action.run(context, target);
}

class _BarIcon extends StatelessWidget {
  const _BarIcon({super.key, required this.icon, required this.label, required this.onTap, this.active = false, this.disabled = false});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;
  final bool disabled;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      label: label,
      child: Tooltip(
        message: label,
        child: InkResponse(
          onTap: onTap,
          radius: 20,
          child: SizedBox(width: 44, height: 44, child: Icon(icon, size: 16, color: active ? c.accent : (disabled ? c.border : c.textFaint))),
        ),
      ),
    );
  }
}

// ── 登记在册的动作 ─────────────────────────────────────
//
// 加一个动作＝在 [kMessageActions] 里加一条（字段说明见 [MessageAction]）。
// 重试、编辑、分支已经登记：它们的文案和动作在 message_branch_actions.dart；改 Agent 的回复在 message_reply_editor.dart。
// 没登记的位置不显示任何东西（不放点了没反应的按钮）。

Future<void> _copy(BuildContext context, MessageTarget t) async {
  await Clipboard.setData(ClipboardData(text: t.copyText));
  if (context.mounted) showSnack(context, '已复制');
}

Future<void> _favorite(BuildContext context, MessageTarget t) async {
  final now = await t.session.messageOps.toggleFavorite(t.item);
  if (!context.mounted || now == null) return;
  showSnack(context, now ? '已收藏。在侧边栏的“收藏的消息”里能找到' : '已取消收藏');
}

Future<void> _share(BuildContext context, MessageTarget t) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  builder: (_) => MessageShareSheet(target: t),
);

Future<void> _delete(BuildContext context, MessageTarget t) async {
  final preview = t.session.messageOps.previewDelete(t.id);
  if (preview == null) return showSnack(context, '这条消息已经不在记录里了。');
  final scope = await showModalBottomSheet<DeleteScope>(
    context: context,
    isScrollControlled: true,
    builder: (_) => MessageDeleteSheet(target: t, preview: preview),
  );
  if (scope == null || !context.mounted) return;
  // 删完以后这一行就不在了（context 跟着失效），所以提示用的东西先拿好
  final messenger = ScaffoldMessenger.of(context);
  final failed = await t.session.messageOps.delete(t.id, scope);
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(failed ?? (scope == DeleteScope.turn ? '已删除这一轮' : '已删除'))));
}

/// 全部消息动作。顺序无所谓（按 [MessageActionSlot] 排）。
const List<MessageAction> kMessageActions = [
  MessageAction(slot: MessageActionSlot.copy, label: _copyLabel, icon: _copyIcon, pinned: _always, run: _copy),
  // 编辑：我的消息＝放回输入框改了再发（message_branch_actions.dart）；Agent 的回复＝直接改这段文字（message_reply_editor.dart）
  MessageAction(slot: MessageActionSlot.edit, label: editLabel, icon: editIcon, hint: editHint, appliesTo: onMine, pinned: _always, disabledReason: rewindBlocked, run: runEdit),
  MessageAction(slot: MessageActionSlot.edit, label: editLabel, icon: editIcon, hint: editReplyHint, appliesTo: onReply, pinned: _always, disabledReason: editReplyBlocked, run: runEditReply),
  // 重试 / 重新发送：我的每条消息、Agent 每一轮的末尾都有
  MessageAction(slot: MessageActionSlot.retry, label: retryLabel, icon: retryIcon, hint: retryHint, pinned: _always, disabledReason: rewindBlocked, run: runRetry),
  MessageAction(slot: MessageActionSlot.branch, label: branchLabel, icon: branchIcon, hint: branchHint, disabledReason: branchBlocked, run: runBranch),
  MessageAction(slot: MessageActionSlot.branches, label: branchesLabel, icon: branchesIcon, appliesTo: hasBranches, pinned: branchesPinned, run: runShowBranches),
  MessageAction(slot: MessageActionSlot.favorite, label: _favoriteLabel, icon: _favoriteIcon, hint: _favoriteHint, pinned: _whenFavorited, run: _favorite),
  MessageAction(slot: MessageActionSlot.share, label: _shareLabel, icon: _shareIcon, hint: _shareHint, run: _share),
  MessageAction(slot: MessageActionSlot.delete, label: _deleteLabel, icon: _deleteIcon, hint: _deleteHint, disabledReason: _deleteBlocked, danger: true, run: _delete),
];

bool _always(MessageTarget t) => true;
bool _whenFavorited(MessageTarget t) => t.favorited;
String _copyLabel(MessageTarget t) => '复制';
IconData _copyIcon(MessageTarget t) => Icons.content_copy_outlined;
String _favoriteLabel(MessageTarget t) => t.favorited ? '取消收藏' : '收藏';
IconData _favoriteIcon(MessageTarget t) => t.favorited ? Icons.bookmark : Icons.bookmark_border;
String? _favoriteHint(MessageTarget t) => t.favorited ? null : '以后在侧边栏的“收藏的消息”里找';
String _shareLabel(MessageTarget t) => '分享';
IconData _shareIcon(MessageTarget t) => Icons.ios_share;
String? _shareHint(MessageTarget t) => '复制成 Markdown，或存成工作区里的文件';
String _deleteLabel(MessageTarget t) => '删除';
IconData _deleteIcon(MessageTarget t) => Icons.delete_outline;
String? _deleteHint(MessageTarget t) => t.busy ? kDeleteWhileBusy : '可以只删这一条，也可以删掉这一整轮';
String? _deleteBlocked(MessageTarget t) => t.busy ? kDeleteWhileBusy : null;
