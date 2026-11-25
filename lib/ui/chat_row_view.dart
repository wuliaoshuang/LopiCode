// 设计约束（聊天里的一行 · 390×844）
// - 一行只放一样东西：我的消息（靠右浅蓝块）、Agent 的正式回复（靠左浅灰块）、一组步骤（一行摘要，见 chat_steps.dart）、
//   这一轮的用量脚注、应用自己的提示、一段思考（一行）、“已压缩较早的对话”（一行）、“上一轮没正常结束”（一张卡）。
// - 正式回复最重（16 号字、有底色）；步骤组和脚注是次要内容（小一号、灰色、无底）。
// - 我的消息和正式回复下面各有一排很淡的小图标（复制、更多……），见 message_action_bar.dart；这里只负责把气泡交给它。
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lopicode/agent/quota.dart';
import 'package:lopicode/agent/usage.dart';
import 'package:lopicode/session/chat_models.dart';
import 'package:lopicode/session/chat_rows.dart';
import 'package:lopicode/state/ui_prefs.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/changed_files.dart';
import 'package:lopicode/ui/chat_extras.dart';
import 'package:lopicode/ui/chat_panels.dart';
import 'package:lopicode/ui/chat_steps.dart';
import 'package:lopicode/ui/message_action_bar.dart';
import 'package:lopicode/ui/usage_ui.dart';
import 'package:lopicode/ui/widgets.dart';
import 'package:material_ui/material_ui.dart';

export 'package:lopicode/session/chat_rows.dart' show describeTool;

/// 把聊天项排成行；设置里关了“显示思考过程”就不带思考。
List<ChatRow> chatRowsOf(WidgetRef ref, List<ChatItem> items, {required bool busy}) => deriveChatRows(items, busy: busy, showThinking: ref.watch(chatPrefsProvider).thinking);

/// 聊天页的一行：一组步骤，或者原样的一项。
class ChatRowView extends StatelessWidget {
  const ChatRowView({super.key, required this.row, this.onOpenChild, this.onOpenQuota, this.onOpenTurn});
  final ChatRow row;
  final void Function(String conversationId)? onOpenChild;
  final VoidCallback? onOpenQuota;
  final void Function(TurnUsage turn)? onOpenTurn;

  @override
  Widget build(BuildContext context) => switch (row) {
    final StepGroupRow group => StepGroupView(key: ValueKey('steps-${group.id}'), row: group, onOpenChild: onOpenChild),
    ItemRow(:final item) => ChatItemView(item: item, onOpenChild: onOpenChild, onOpenQuota: onOpenQuota, onOpenTurn: onOpenTurn),
  };
}

class ChatItemView extends ConsumerWidget {
  const ChatItemView({super.key, required this.item, this.onOpenChild, this.onOpenQuota, this.onOpenTurn});

  /// 点回合脚注时打开本轮轨迹。
  final void Function(TurnUsage turn)? onOpenTurn;

  /// 被额度上限拦住的提示下面“去调额度上限”的去处。
  final VoidCallback? onOpenQuota;
  final ChatItem item;

  /// 点“派子代理”那张卡时进子对话。
  final void Function(String conversationId)? onOpenChild;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final showUsage = ref.watch(chatPrefsProvider).usage;
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    switch (item) {
      case UserItem(:final text, :final images):
        return MessageFrame(
          item: item,
          child: Align(
            alignment: Alignment.centerRight,
            child: Container(
              margin: const EdgeInsets.only(top: Space.x2, bottom: Space.x1, left: Space.x8),
              padding: const EdgeInsets.symmetric(horizontal: Space.x4, vertical: Space.x3),
              decoration: BoxDecoration(
                color: c.bubbleMineBg,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(c.radius(Radii.bubble)),
                  topRight: Radius.circular(c.radius(Radii.sm)),
                  bottomLeft: Radius.circular(c.radius(Radii.bubble)),
                  bottomRight: Radius.circular(c.radius(Radii.bubble)),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (images.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: Space.x2),
                      child: Wrap(
                        spacing: Space.x1,
                        runSpacing: Space.x1,
                        alignment: WrapAlignment.end,
                        children: [for (final path in images) ImageThumb(path: path, size: 64)],
                      ),
                    ),
                  SelectableText(text, style: t.bodyLarge?.copyWith(color: c.bubbleMineText)),
                ],
              ),
            ),
          ),
        );
      case AssistantItem(:final text, :final streaming):
        return MessageFrame(
          item: item,
          child: Align(
            alignment: Alignment.centerLeft,
            child: Container(
              margin: const EdgeInsets.only(top: Space.x1, bottom: Space.x1, right: Space.x6),
              padding: const EdgeInsets.symmetric(horizontal: Space.x4, vertical: Space.x3),
              decoration: BoxDecoration(
                color: c.bubbleAgentBg,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(c.radius(Radii.sm)),
                  topRight: Radius.circular(c.radius(Radii.bubble)),
                  bottomLeft: Radius.circular(c.radius(Radii.bubble)),
                  bottomRight: Radius.circular(c.radius(Radii.bubble)),
                ),
              ),
              child: SelectableText(streaming ? '$text▍' : text, style: t.bodyLarge?.copyWith(color: c.bubbleAgentText)),
            ),
          ),
        );
      case final ToolItem tool:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: Space.x1),
          child: StepRow(tool: tool, onOpenChild: onOpenChild),
        );
      case final ThinkingItem thinking:
        return ThinkingRow(item: thinking);
      case final CompactionItem compaction:
        return CompactionRow(item: compaction);
      case final InterruptedItem cut:
        return InterruptedCard(item: cut);
      case ChangedFilesItem(:final files):
        return ChangedFilesRow(files: files);
      case UsageItem(:final turn):
        if (!showUsage) return const SizedBox.shrink();
        return TurnFootnote(turn: turn, onTap: onOpenTurn == null ? null : () => onOpenTurn!(turn));
      case NoticeItem(:final text, :final isError):
        final banner = InfoBanner(
          text,
          tone: isError ? BannerTone.danger : BannerTone.info,
          margin: const EdgeInsets.symmetric(vertical: Space.x2),
        );
        // 被额度上限拦住：紧跟一个去调上限的入口。
        if (!isError || !text.startsWith(kQuotaBlockedPrefix) || onOpenQuota == null) return banner;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            banner,
            TextButton.icon(onPressed: onOpenQuota, icon: const Icon(Icons.speed_outlined, size: 18), label: const Text('去调额度上限')),
          ],
        );
    }
  }
}
