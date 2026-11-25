// 收藏的消息：一个工作区存一个文件（.lopicode/favorites.json）。
//
// 每条记“哪段对话 + 消息的稳定标识（`_id`）+ 文字快照”。原消息或整段对话后来被删了，快照还在，照样能看。
// 这里只有数据的样子和读写；状态在 lib/state/workspace_favorites.dart。
import 'dart:io';

import 'package:lopicode/core/safe_file.dart';

/// 文字快照最多留这么多字（再长的只留开头；原消息还在时可以跳回去看全文）。
const int kFavoriteSnapshotChars = 4000;

class FavoriteMessage {
  const FavoriteMessage({required this.convId, required this.messageId, required this.role, required this.text, required this.convTitle, required this.savedAt, this.gone = false});

  final String convId;
  final String messageId;

  /// `user`（我的消息）/ `assistant`（Agent 的回复）。
  final String role;

  /// 收藏那一刻的文字。
  final String text;

  /// 收藏那一刻所属对话的名字（对话后来被删了还能显示）。
  final String convTitle;
  final DateTime savedAt;

  /// 原消息已经被删掉了。
  final bool gone;

  String get key => '$convId/$messageId';
  bool get mine => role == 'user';

  FavoriteMessage copyWith({bool? gone}) => FavoriteMessage(convId: convId, messageId: messageId, role: role, text: text, convTitle: convTitle, savedAt: savedAt, gone: gone ?? this.gone);

  Map<String, dynamic> toJson() => {'conv': convId, 'msg': messageId, 'role': role, 'text': text, 'title': convTitle, 'at': savedAt.toIso8601String(), if (gone) 'gone': true};

  /// 形状不对（缺对话 id、消息 id）返回 null。
  static FavoriteMessage? fromJson(Object? j) {
    if (j is! Map) return null;
    final conv = j['conv'], msg = j['msg'], text = j['text'], title = j['title'], at = j['at'];
    if (conv is! String || conv.isEmpty || msg is! String || msg.isEmpty) return null;
    return FavoriteMessage(
      convId: conv,
      messageId: msg,
      role: j['role'] == 'user' ? 'user' : 'assistant',
      text: text is String ? text : '',
      convTitle: title is String ? title : '',
      savedAt: (at is String ? DateTime.tryParse(at) : null) ?? DateTime.fromMillisecondsSinceEpoch(0),
      gone: j['gone'] == true,
    );
  }
}

/// 读收藏文件。文件不在、读不懂（会先另存一份 .bad-时间）都当没有收藏。同一条消息只留第一份；新收藏的排前面。
Future<List<FavoriteMessage>> readFavorites(File file) async {
  final decoded = await readJsonFile(file, accept: (j) => j is Map && j['items'] is List, label: '收藏的消息');
  if (decoded is! Map) return const [];
  final seen = <String>{};
  final out = <FavoriteMessage>[];
  final items = decoded['items'];
  for (final j in items is List ? items : const []) {
    final f = FavoriteMessage.fromJson(j);
    if (f != null && seen.add(f.key)) out.add(f);
  }
  out.sort((a, b) => b.savedAt.compareTo(a.savedAt));
  return out;
}

Future<void> writeFavorites(File file, List<FavoriteMessage> items) => writeJsonAtomic(file, {
  'version': 1,
  'items': [for (final f in items) f.toJson()],
});
