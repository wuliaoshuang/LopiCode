// 设计约束（收藏的消息 · 390×844）
// 层级：每条收藏最重的是消息文字本身（最多 4 行）；上面一行小字是出处——谁说的 · 哪段对话；下面一行最淡的是收藏时间。
// - 一条收藏一张卡，整张卡可点：原消息还在就跳回那段对话并滚到它；原消息（或整段对话）已经删了，点开看收藏时留下的全文。
// - 卡片右上角一个实心书签（44×44）：取消收藏。它是这张卡上唯一的按钮。
// - “原消息已删除”用一个小标签写在出处那一行，不用红色（不是出错，只是说明）。
// - 新收藏的排最前。一条都没有时是空状态：一句话说明去哪收藏。
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lopicode/project_session.dart';
import 'package:lopicode/session/favorites.dart';
import 'package:lopicode/state/workspace_favorites.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/top_bar.dart';
import 'package:lopicode/ui/widgets.dart';
import 'package:material_ui/material_ui.dart';

/// 打开“收藏的消息”。点了一条还在的：切到那段对话，[goChat]（切到聊天页），再让聊天页滚到那条消息。
Future<void> openFavorites(BuildContext context, ProjectSession session, {VoidCallback? goChat}) async {
  final picked = await Navigator.of(context).push<FavoriteMessage>(MaterialPageRoute(builder: (_) => FavoritesScreen(session: session)));
  if (picked == null || !context.mounted) return;
  if (picked.convId != session.activeConversationId) {
    if (session.agentBusy) return showSnack(context, 'Agent 正在回复，停下后才能切到别的对话。');
    await session.selectConversation(picked.convId);
    if (!context.mounted) return;
    if (session.activeConversationId != picked.convId) return showSnack(context, '没能打开那段对话。');
  }
  goChat?.call();
  ProviderScope.containerOf(context, listen: false).read(chatJumpProvider(session).notifier).request(picked.messageId);
}

String _two(int v) => v.toString().padLeft(2, '0');

/// 收藏时间的写法：今年的不写年份。
String favoriteTimeLabel(DateTime at, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final day = at.year == n.year ? '${at.month}月${at.day}日' : '${at.year}年${at.month}月${at.day}日';
  return '$day ${_two(at.hour)}:${_two(at.minute)}';
}

class FavoritesScreen extends ConsumerStatefulWidget {
  const FavoritesScreen({super.key, required this.session});
  final ProjectSession session;

  @override
  ConsumerState<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends ConsumerState<FavoritesScreen> {
  ProjectSession get s => widget.session;

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (mounted) unawaited(ref.read(favoritesProvider(s).notifier).load());
    });
  }

  void _open(FavoriteMessage f) {
    if (s.messageOps.favoriteMissing(f)) {
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (_) => _SnapshotSheet(item: f),
      );
    } else {
      Navigator.pop(context, f);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(favoritesProvider(s));
    final items = state.items;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: const PageBar(titleText: '收藏的消息'),
      body: !state.loaded
          ? const SizedBox.shrink()
          : items.isEmpty
          ? const BelowBar(
              child: EmptyState(icon: Icons.bookmark_border, title: '还没有收藏', message: '在聊天里点一条消息下面的“⋯”，选“收藏”，\n它就会出现在这里。'),
            )
          : ListView.separated(
              padding: EdgeInsets.fromLTRB(Space.x4, PageBar.insetOf(context) + Space.x2, Space.x4, Space.x8),
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(height: Space.x3),
              itemBuilder: (context, i) {
                final f = items[i];
                return _FavoriteCard(
                  key: ValueKey('favorite-${f.key}'),
                  item: f,
                  missing: s.messageOps.favoriteMissing(f),
                  onTap: () => _open(f),
                  onRemove: () => ref.read(favoritesProvider(s).notifier).remove(f.key),
                );
              },
            ),
    );
  }
}

class _FavoriteCard extends StatelessWidget {
  const _FavoriteCard({super.key, required this.item, required this.missing, required this.onTap, required this.onRemove});
  final FavoriteMessage item;
  final bool missing;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final title = item.convTitle.isEmpty ? '未命名的对话' : item.convTitle;
    return Material(
      color: c.surfaceMuted,
      borderRadius: BorderRadius.circular(Radii.lg),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.only(left: Space.x4, bottom: Space.x3),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${item.mine ? '我' : 'Agent'} · $title',
                      style: t.bodySmall?.copyWith(color: c.textMuted),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (missing)
                    Container(
                      key: const ValueKey('favorite-gone'),
                      margin: const EdgeInsets.only(left: Space.x2),
                      padding: const EdgeInsets.symmetric(horizontal: Space.x2, vertical: 2),
                      decoration: BoxDecoration(color: c.bg, borderRadius: BorderRadius.circular(Radii.sm)),
                      child: Text('原消息已删除', style: t.bodySmall?.copyWith(color: c.textMuted)),
                    ),
                  Semantics(
                    button: true,
                    label: '取消收藏',
                    child: Tooltip(
                      message: '取消收藏',
                      child: InkResponse(
                        key: const ValueKey('favorite-remove'),
                        onTap: onRemove,
                        radius: 20,
                        child: SizedBox(width: 44, height: 44, child: Icon(Icons.bookmark, size: 18, color: c.accent)),
                      ),
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(right: Space.x4),
                child: Text(item.text.trim(), style: t.bodyMedium?.copyWith(height: 1.5), maxLines: 4, overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(height: Space.x2),
              Text(favoriteTimeLabel(item.savedAt), style: t.bodySmall?.copyWith(color: c.textFaint)),
            ],
          ),
        ),
      ),
    );
  }
}

/// 原消息已经删了：看收藏时留下的全文，可以复制。
class _SnapshotSheet extends StatelessWidget {
  const _SnapshotSheet({required this.item});
  final FavoriteMessage item;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.7),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.x6, 0, Space.x6, Space.x2),
              child: Text('原消息已删除，这是收藏时留下的文字', style: t.bodySmall),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: Space.x6),
                child: SelectableText(item.text, style: t.bodyLarge),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.x6, Space.x3, Space.x6, Space.x4),
              child: OutlinedButton.icon(
                key: const ValueKey('favorite-copy'),
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: item.text));
                  if (context.mounted) {
                    Navigator.pop(context);
                    showSnack(context, '已复制');
                  }
                },
                icon: const Icon(Icons.content_copy_outlined, size: 18),
                label: const Text('复制'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
