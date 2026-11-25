// /export 和“分享这条消息”：把对话（或其中一条、一轮）写成 Markdown。
// 出门前一律过一遍 [redactSecrets]：像密钥 / 令牌 / 密码的内容换成 ***（宁可多抹）。
import 'dart:io';

import 'package:lopicode/core/crash_log.dart';
import 'package:lopicode/core/path_guard.dart';
import 'package:lopicode/session/session_core.dart';

/// 把接口格式的消息记录排成 Markdown 文本。纯计算。像密钥的内容已经抹掉。
String conversationMarkdown(String title, List<Map<String, dynamic>> messages) {
  final out = StringBuffer('# $title\n\n');
  for (final m in messages) {
    switch (m['role']) {
      case 'user' when m['_notice'] is String:
        out.writeln('> 应用通知：${m['_notice']}\n'); // 应用自己告诉模型的事，不是用户说的话
      case 'user':
        out.writeln('## 我\n\n${m['content'] ?? ''}\n');
        final images = m['_images'];
        for (final i in images is List ? images : const []) {
          if (i is Map) out.writeln('（附件：${i['path']}）\n');
        }
      case 'assistant':
        final content = m['content'];
        if (content is String && content.isNotEmpty) out.writeln('## Agent\n\n$content\n');
        final calls = m['tool_calls'];
        for (final c in calls is List ? calls : const []) {
          final fn = c is Map ? c['function'] : null;
          if (fn is Map) out.writeln('> 调用工具 `${fn['name']}`：`${clipText('${fn['arguments']}', 300)}`\n');
        }
      case 'tool':
        out.writeln('> 工具结果：${clipText('${m['content'] ?? ''}'.replaceAll('\n', ' '), 300)}\n');
    }
  }
  return redactSecrets(out.toString());
}

/// 写进工作区的 exports/ 目录，返回相对路径。[prefix] 是文件名开头（整段对话叫“对话”，单条 / 一轮叫“消息”）。
/// 同一秒里已经有同名文件就在后面加序号，不盖掉上一份。
Future<String> writeConversationExport(PathGuard guard, String markdown, {DateTime? now, String prefix = '对话'}) async {
  final t = now ?? DateTime.now();
  String two(int v) => v.toString().padLeft(2, '0');
  final base = 'exports/$prefix-${t.year}${two(t.month)}${two(t.day)}-${two(t.hour)}${two(t.minute)}${two(t.second)}';
  var rel = '$base.md';
  for (var n = 2; n < 100 && await File(guard.resolve(rel)).exists(); n++) {
    rel = '$base-$n.md';
  }
  final file = File(guard.resolve(rel));
  await file.parent.create(recursive: true);
  await file.writeAsString(markdown);
  return rel;
}
