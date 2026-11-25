// 消息的稳定标识：消息记录里每条非工具消息都带一个 `_id`（以 `_` 开头的键不会发给模型接口）。
//
// - 新消息：生成时就带上（AgentRunner 加消息的地方）。
// - 旧对话文件（没有 `_id`）：读进来时 [ensureMessageIds] 给没有的补上，调用方随即写回盘上——
//   这样收藏、删除、以后的重试 / 编辑 / 分支认的都是同一个 id，重开应用也不变。
// - 工具结果（role: tool）不带 `_id`：它靠 `tool_call_id` 跟着所属的那条 assistant 消息走。
// - 只保证“一段对话里不重复”；不同对话里可以相同（分支复制消息时可以原样带过去）。
import 'dart:math';

/// 消息记录里放稳定标识的键。
const String kMessageIdKey = '_id';

final Random _random = Random();
int _lastMicros = 0;

/// 一个新的消息 id：`m` + 当前微秒数（36 进制）+ 三位随机数。同一微秒里连着要也不会重。
String newMessageId() {
  var now = DateTime.now().microsecondsSinceEpoch;
  if (now <= _lastMicros) now = _lastMicros + 1;
  _lastMicros = now;
  return 'm${now.toRadixString(36)}${_random.nextInt(46656).toRadixString(36).padLeft(3, '0')}';
}

/// 这条消息的 id；没有（工具结果、还没补过的旧消息）或形状不对是 null。
String? messageIdOf(Map<String, dynamic> message) {
  final id = message[kMessageIdKey];
  return id is String && id.isNotEmpty ? id : null;
}

/// 给没有 id 的非工具消息补上，重复的 id 只留第一条、后面的换新的。返回改了几条（0＝不用写回）。
int ensureMessageIds(List<Map<String, dynamic>> messages) {
  final seen = <String>{};
  var changed = 0;
  for (final m in messages) {
    if (m['role'] == 'tool') continue;
    final id = messageIdOf(m);
    if (id != null && seen.add(id)) continue;
    var fresh = newMessageId();
    while (!seen.add(fresh)) {
      fresh = newMessageId();
    }
    m[kMessageIdKey] = fresh;
    changed++;
  }
  return changed;
}

/// 按 id 找消息的位置；没有是 -1。
int indexOfMessage(List<Map<String, dynamic>> messages, String id) => messages.indexWhere((m) => m[kMessageIdKey] == id);
