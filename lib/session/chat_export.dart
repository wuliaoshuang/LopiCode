// /export：把一段对话写成 Markdown。
import 'dart:io';

import 'package:lopicode/core/path_guard.dart';
import 'package:lopicode/session/session_core.dart';

/// 把接口格式的消息记录排成 Markdown 文本。纯计算。
String conversationMarkdown(String title, List<Map<String, dynamic>> messages) {
  final out = StringBuffer('# $title\n\n');
  for (final m in messages) {
    switch (m['role']) {
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
  return out.toString();
}

/// 写进工作区的 exports/ 目录，返回相对路径。
Future<String> writeConversationExport(PathGuard guard, String markdown, {DateTime? now}) async {
  final t = now ?? DateTime.now();
  String two(int v) => v.toString().padLeft(2, '0');
  final rel = 'exports/对话-${t.year}${two(t.month)}${two(t.day)}-${two(t.hour)}${two(t.minute)}${two(t.second)}.md';
  final file = File(guard.resolve(rel));
  await file.parent.create(recursive: true);
  await file.writeAsString(markdown);
  return rel;
}
