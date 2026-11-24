// 设计约束（聊天里的一行 · 390×844）
// - 一行只放一样东西：我的消息（靠右浅蓝块）、Agent 的正式回复（靠左浅灰块）、一组步骤（一行摘要，见 chat_steps.dart）、
//   这一轮的用量脚注、应用自己的提示。
// - 正式回复最重（16 号字、有底色）；步骤组和脚注是次要内容（小一号、灰色、无底）。
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lopicode/agent/quota.dart';
import 'package:lopicode/agent/usage.dart';
import 'package:lopicode/session/chat_models.dart';
import 'package:lopicode/session/chat_rows.dart';
import 'package:lopicode/state/ui_prefs.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/chat_panels.dart';
import 'package:lopicode/ui/chat_steps.dart';
import 'package:lopicode/ui/usage_ui.dart';
import 'package:lopicode/ui/widgets.dart';
import 'package:material_ui/material_ui.dart';

export 'package:lopicode/session/chat_rows.dart' show describeTool;

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
        return Align(
          alignment: Alignment.centerRight,
          child: Container(
            margin: const EdgeInsets.only(top: Space.x2, bottom: Space.x1, left: Space.x8),
            padding: const EdgeInsets.symmetric(horizontal: Space.x4, vertical: Space.x3),
            decoration: BoxDecoration(
              color: c.accentSoft,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(Radii.bubble),
                topRight: Radius.circular(Radii.sm),
                bottomLeft: Radius.circular(Radii.bubble),
                bottomRight: Radius.circular(Radii.bubble),
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
                SelectableText(text, style: t.bodyLarge),
              ],
            ),
          ),
        );
      case AssistantItem(:final text, :final streaming):
        return Align(
          alignment: Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.only(top: Space.x1, bottom: Space.x1, right: Space.x6),
            padding: const EdgeInsets.symmetric(horizontal: Space.x4, vertical: Space.x3),
            decoration: BoxDecoration(
              color: c.surfaceMuted,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(Radii.sm),
                topRight: Radius.circular(Radii.bubble),
                bottomLeft: Radius.circular(Radii.bubble),
                bottomRight: Radius.circular(Radii.bubble),
              ),
            ),
            child: SelectableText(streaming ? '$text▍' : text, style: t.bodyLarge),
          ),
        );
      case final ToolItem tool:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: Space.x1),
          child: StepRow(tool: tool, onOpenChild: onOpenChild),
        );
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
