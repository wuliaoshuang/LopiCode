// 待办清单：Agent 做多步任务时先列出要做的几件事，做一件勾一件。聊天页输入框上方显示进度。
// 不另存盘：清单就是最近一次 update_todos 调用的参数，跟着对话记录走。
import 'dart:convert';

import 'package:lopicode/agent/agent_tools.dart';

enum TodoStatus { pending, inProgress, done }

class TodoEntry {
  const TodoEntry(this.text, this.status);
  final String text;
  final TodoStatus status;
}

/// 一份清单最多几条（再多手机上看不过来，模型也容易乱）。
const int kMaxTodos = 20;

TodoStatus? _statusOf(Object? raw) => switch (raw) {
  'pending' => TodoStatus.pending,
  'in_progress' => TodoStatus.inProgress,
  'done' || 'completed' => TodoStatus.done,
  _ => null,
};

/// 解析 update_todos 的参数。不合规矩抛 [ToolArgError]，说明哪里不对。
List<TodoEntry> parseTodos(Map<String, dynamic> args) {
  final raw = args['items'];
  if (raw is! List) throw ToolArgError('items 必须是数组，每项形如 {"text": "要做的事", "status": "pending"}');
  if (raw.length > kMaxTodos) throw ToolArgError('待办最多 $kMaxTodos 条，现在有 ${raw.length} 条，请合并一下');
  final out = <TodoEntry>[];
  for (final (i, item) in raw.indexed) {
    final text = item is Map && item['text'] is String ? (item['text'] as String).trim() : '';
    if (text.isEmpty) throw ToolArgError('第 ${i + 1} 项缺少 text（要做的事）');
    final status = _statusOf(item is Map ? item['status'] ?? 'pending' : null);
    if (status == null) throw ToolArgError('第 ${i + 1} 项的 status 只能是 pending、in_progress、done');
    out.add(TodoEntry(text.length > 200 ? '${text.substring(0, 200)}…' : text, status));
  }
  if (out.where((t) => t.status == TodoStatus.inProgress).length > 1) throw ToolArgError('同一时间只能有一项是 in_progress');
  return out;
}

/// 从存着的参数原文解析；坏了返回 null（显示的地方用，不抛错）。
List<TodoEntry>? tryParseTodos(String rawArgs) {
  try {
    final decoded = jsonDecode(rawArgs);
    return decoded is Map<String, dynamic> ? parseTodos(decoded) : null;
  } on FormatException {
    return null;
  } on ToolArgError {
    return null;
  }
}

/// update_todos 工具。只是记一笔，不碰文件，任何权限、计划模式下都能用。
ExtraTool todoTool() => ExtraTool(
  spec: toolSpec(
    'update_todos',
    '任务要分 3 步以上时，先用它列出待办清单；之后每开始或做完一项就再调用一次，把**完整清单**连同最新状态一起传进来（它会整体替换上一份）。'
        '用户能在界面上看到进度。简单的一两步任务不需要用。',
    {
      'items': {
        'type': 'array',
        'description': '完整的待办清单，按顺序',
        'items': {
          'type': 'object',
          'properties': {
            'text': {'type': 'string', 'description': '要做的事，一句话'},
            'status': {
              'type': 'string',
              'enum': ['pending', 'in_progress', 'done'],
              'description': 'pending 还没做；in_progress 正在做（同时只能有一项）；done 做完了',
            },
          },
          'required': ['text', 'status'],
        },
      },
    },
    ['items'],
  ),
  kind: ToolKind.read,
  run: (args) async {
    final todos = parseTodos(args);
    final done = todos.where((t) => t.status == TodoStatus.done).length;
    final current = todos.where((t) => t.status == TodoStatus.inProgress).firstOrNull;
    return ToolOutcome('待办清单已更新：${todos.length} 项，已完成 $done 项${current == null ? '' : '，正在做：${current.text}'}。');
  },
);
