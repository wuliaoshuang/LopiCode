// 从接口格式的消息记录重建聊天页显示的条目。纯计算：不读盘、不碰状态。
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
      case 'user':
        final images = m['_images'];
        items.add(
          UserItem(
            '${m['content'] ?? ''}',
            images: [
              for (final i in images is List ? images : const [])
                if (i is Map) hostPathOf('${i['path']}'),
            ],
          ),
        );
      case 'assistant':
        final text = m['content'];
        if (text is String && text.isNotEmpty) items.add(AssistantItem(text));
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
          items[at] = (items[at] as ToolItem).copyWith(result: result, ok: !result.startsWith('错误') && !result.startsWith('用户拒绝'), denied: result.startsWith('用户拒绝'));
        }
    }
    final turn = TurnUsage.fromJson(m['_usage']);
    if (turn != null) items.add(UsageItem(turn));
  }
  return items;
}
