// 从接口格式的消息记录重建聊天页显示的条目。纯计算：不读盘、不碰状态。
import 'package:lopicode/agent/agent_runner.dart' show kAppNoticeMark;
import 'package:lopicode/agent/auto_compact.dart';
import 'package:lopicode/agent/line_diff.dart';
import 'package:lopicode/agent/message_ids.dart';
import 'package:lopicode/agent/usage.dart';
import 'package:lopicode/session/chat_models.dart';

/// [childConversationIds]：这段对话派出的子代理对话，按派出顺序；第几次 spawn_agent 调用就对上第几个。
/// [hostPathOf]：把附件的相对路径换成手机上的真实路径。
List<ChatItem> chatItemsFromMessages(List<Map<String, dynamic>> messages, {required List<String> childConversationIds, required String Function(String rel) hostPathOf}) {
  final items = <ChatItem>[];
  final toolAt = <String, int>{};
  var kid = 0;
  for (final m in messages) {
    switch (m['role']) {
      case 'user' when m[kCompactMark] == true:
        // 自动 / 手动压缩留下的摘要：显示成一行“已压缩较早的对话”，点开看摘要。
        items.add(CompactionItem(compactSummaryOf(m)));
      case 'user' when m[kAppNoticeMark] is String:
        // 应用自己告诉模型的事（后台命令结束了……）：显示成一行提示，不是用户说的话。
        items.add(NoticeItem(m[kAppNoticeMark] as String));
      case 'user':
        final images = m['_images'];
        items.add(
          UserItem(
            '${m['content'] ?? ''}',
            id: messageIdOf(m),
            images: [
              for (final i in images is List ? images : const [])
                if (i is Map) hostPathOf('${i['path']}'),
            ],
          ),
        );
      case 'assistant' when m[kCompactAckMark] == true:
        break; // 摘要后面那句承接的话：不显示
      case 'assistant':
        // 存着思考内容的（旧对话没有就不显示）：排在这一步的回复 / 工具调用前面。
        final thought = m['_reasoning'];
        final thoughtMs = m['_reasoningMs'];
        if (thought is String && thought.trim().isNotEmpty) items.add(ThinkingItem(thought, ms: thoughtMs is int ? thoughtMs : null));
        final text = m['content'];
        if (text is String && text.isNotEmpty) items.add(AssistantItem(text, id: messageIdOf(m)));
        final calls = m['tool_calls'];
        for (final c in calls is List ? calls : const []) {
          if (c is! Map) continue;
          final fn = c['function'];
          final name = fn is Map ? '${fn['name']}' : '';
          final item = ToolItem(
            '${c['id']}',
            name,
            fn is Map ? '${fn['arguments']}' : '',
            result: '（没有记录到结果）',
            childConversationId: name == 'spawn_agent' && kid < childConversationIds.length ? childConversationIds[kid++] : null,
          );
          toolAt[item.callId] = items.length;
          items.add(item);
        }
      case 'tool':
        final at = toolAt['${m['tool_call_id']}'];
        if (at != null) {
          final result = '${m['content'] ?? ''}';
          // `_diff`：这一步的改动对比；`_ms`：这一步用了多久（旧记录都没有；类型不对就当没有）。
          final ms = m['_ms'];
          items[at] = (items[at] as ToolItem).copyWith(
            result: result,
            ok: !result.startsWith('错误') && !result.startsWith('用户拒绝'),
            denied: result.startsWith('用户拒绝'),
            change: FileChange.tryParse(m['_diff']),
            ms: ms is int && ms >= 0 ? ms : null,
          );
        }
    }
    // `_files`：这一轮改过的文件（旧记录没有）。排在用量脚注前面。
    final files = parseFileChanges(m['_files']);
    if (files.isNotEmpty) items.add(ChangedFilesItem(files));
    final turn = TurnUsage.fromJson(m['_usage']);
    if (turn != null) items.add(UsageItem(turn));
  }
  return items;
}
