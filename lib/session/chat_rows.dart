// 把一段对话的条目排成聊天页要画的“行”。纯计算：不读盘、不碰状态、不带界面。
//
// 规则（2026-11-24，霜霜嫌工具调用一条条刷屏）：
// - 用户消息把对话切成一段一段；一段里从第一次工具调用到最后一次工具调用之间的东西
//   （工具调用 + 模型在工具之间说的话）合成一个“步骤组”，只占一行；
// - 最后一次工具调用之后模型说的话是正式回复，留在外面；用量脚注、提示也留在外面；
// - 存盘格式不变：历史对话重新打开时，同样的条目经过这里得到同样的行。
import 'dart:convert';

import 'package:lopicode/agent/todos.dart';
import 'package:lopicode/session/chat_models.dart';

/// 聊天页的一行。
sealed class ChatRow {
  const ChatRow();
}

/// 原样显示的一项（用户消息、正式回复、用量脚注、提示）。
class ItemRow extends ChatRow {
  const ItemRow(this.item);
  final ChatItem item;
}

/// 一组步骤：[steps] 里是 [ToolItem]（一次工具调用）、[AssistantItem]（工具之间模型说的话）、
/// [ThinkingItem]（某一步之前的思考），按发生顺序。
class StepGroupRow extends ChatRow {
  const StepGroupRow(this.steps, {required this.live});
  final List<ChatItem> steps;

  /// 这一组还在进行（这段对话正忙，而且它后面还没有正式回复）。
  final bool live;

  List<ToolItem> get tools => [...steps.whereType<ToolItem>()];

  /// 用来认出“还是同一组”（展开状态跟着它走）：第一次工具调用的 id。
  String get id => tools.first.callId;
}

/// [busy]：这段对话是不是正在跑。[showThinking]＝false 时思考过程一律不出现（设置里关了）。
List<ChatRow> deriveChatRows(List<ChatItem> all, {required bool busy, bool showThinking = true}) {
  final items = showThinking ? all : [...all.where((i) => i is! ThinkingItem)];
  final rows = <ChatRow>[];
  var start = 0;
  for (var i = 0; i <= items.length; i++) {
    if (i < items.length && items[i] is! UserItem) continue;
    _segment(items, start, i, rows, live: busy && i == items.length);
    if (i < items.length) rows.add(ItemRow(items[i]));
    start = i + 1;
  }
  return rows;
}

void _segment(List<ChatItem> items, int from, int to, List<ChatRow> rows, {required bool live}) {
  var lastTool = -1;
  for (var i = from; i < to; i++) {
    if (items[i] is ToolItem) lastTool = i;
  }
  final hasAfter = lastTool < to - 1;
  var group = <ChatItem>[];
  void flush({required bool isLast}) {
    if (group.isEmpty) return;
    // 组里最后几句话后面没有工具调用了（被提示隔开）：它们不是步骤，放回外面。
    final tail = <ChatItem>[];
    while (group.isNotEmpty && group.last is! ToolItem) {
      tail.insert(0, group.removeLast());
    }
    // 还在进行：组里有工具在跑，或者组后面还什么都没有（模型正在想下一步）。
    final going = group.whereType<ToolItem>().any((t) => t.running) || (isLast && tail.isEmpty && !hasAfter);
    if (group.isNotEmpty) rows.add(StepGroupRow(group, live: live && going));
    rows.addAll(tail.map(ItemRow.new));
    group = <ChatItem>[];
  }

  for (var i = from; i < to; i++) {
    final item = items[i];
    if (i > lastTool) {
      flush(isLast: true);
      rows.add(ItemRow(item));
    } else if (item is ToolItem || item is AssistantItem || item is ThinkingItem) {
      group.add(item);
    } else {
      // 提示、用量脚注夹在中间：前面的先收成一组，顺序不动。
      flush(isLast: false);
      rows.add(ItemRow(item));
    }
  }
  flush(isLast: true);
}

/// 工具的种类（只管怎么显示、怎么计数；权限按 `ToolKind` 走，和这里无关）。
enum StepKind { read, look, edit, delete, command, search, agent, ask, plan, other }

StepKind stepKindOf(String name) => switch (name) {
  'read_file' || 'lowcode_get_page' || 'backend_get_blocks' => StepKind.read,
  'memory_read' || 'memory_search' || 'conversation_search' => StepKind.look,
  'list_files' || 'read_skill' || 'team_board' || 'list_scheduled_tasks' => StepKind.look,
  'write_file' || 'edit_file' || 'lowcode_update_page' || 'backend_update_blocks' => StepKind.edit,
  'delete_file' => StepKind.delete,
  'run_command' => StepKind.command,
  'web_search' => StepKind.search,
  'spawn_agent' => StepKind.agent,
  'ask_user' => StepKind.ask,
  'update_todos' => StepKind.plan,
  _ => StepKind.other,
};

Map<String, dynamic> _argsOf(String rawArgs) {
  try {
    final decoded = jsonDecode(rawArgs);
    if (decoded is Map<String, dynamic>) return decoded;
  } on FormatException {
    // 参数不是合法 JSON：只显示动作名
  }
  return const {};
}

/// 一次工具调用拆成“动作 + 对象”，例如（读取，lib/main.dart）。对象可能为空。
(String verb, String target) stepLabel(String name, String rawArgs) {
  final args = _argsOf(rawArgs);
  String a(String key) => '${args[key] ?? ''}'.trim();
  return switch (name) {
    'list_files' => ('查看文件列表', a('path')),
    'read_file' => ('读取', a('path')),
    'write_file' => ('写入', a('path')),
    'edit_file' => ('修改', a('path')),
    'delete_file' => ('删除', a('path')),
    'run_command' => ('执行', a('command')),
    'lowcode_get_page' => ('读取低代码页面', ''),
    'lowcode_update_page' => ('更新低代码页面', ''),
    'backend_get_blocks' => ('读取后端积木', ''),
    'backend_update_blocks' => ('更新后端积木', ''),
    'ask_user' => ('向你提问', a('question')),
    'web_search' => ('联网搜索', a('query')),
    'read_skill' => ('读技能', a('name')),
    'spawn_agent' => (a('name').isEmpty ? '派子代理' : '派子代理“${a('name')}”', a('task')),
    'team_board' => ('查看任务板', ''),
    'team_task' => ('更新任务板', a('title')),
    'team_message' => (a('to').isEmpty ? '团队留言' : '团队留言给 ${a('to')}', ''),
    'list_scheduled_tasks' => ('查看自动化任务', ''),
    'schedule_task' => ('安排自动化任务', a('title')),
    'update_todos' => ('更新待办清单', ''),
    'memory_read' => (a('title').isEmpty ? '查看记忆清单' : '读记忆', a('title')),
    'memory_search' => ('查记忆', a('query')),
    'memory_write' => ('记住了', a('title')),
    'memory_delete' => ('从记忆里删掉', a('title')),
    'conversation_search' => ('查历史对话', a('query')),
    _ => (name, ''),
  };
}

/// 工具名 → 一句人话。
String describeTool(String name, String rawArgs) {
  final (verb, target) = stepLabel(name, rawArgs);
  return target.isEmpty ? verb : '$verb $target';
}

/// 一组步骤的统计。文件按路径去重；失败、被拒绝的不算“读了 / 改了”。
class StepSummary {
  const StepSummary({
    required this.total,
    required this.read,
    required this.edited,
    required this.commands,
    required this.searches,
    required this.agents,
    required this.other,
    required this.failed,
    required this.denied,
    required this.running,
    this.remembered = 0,
  });

  final int total;
  final int read;
  final int edited;
  final int commands;
  final int searches;
  final int agents;
  final int other;
  final int failed;
  final int denied;
  final int running;

  /// 记进记忆的条数（成功的 memory_write）。
  final int remembered;

  /// “读 3 个文件 · 改 1 个文件 · 1 条命令”这样的几段；一段都没有时为空。
  List<String> get parts => [
    if (read > 0) '读 $read 个文件',
    if (edited > 0) '改 $edited 个文件',
    if (commands > 0) '$commands 条命令',
    if (searches > 0) '搜索 $searches 次',
    if (agents > 0) '$agents 个子代理',
    if (remembered > 0) '记住 $remembered 条',
  ];

  /// 折叠时那一行：`执行了 5 步 · 读 3 个文件 · 改 1 个文件 · 1 条命令`。
  String get line => ['执行了 $total 步', ...parts].join(' · ');
}

StepSummary summarizeSteps(List<ToolItem> tools) {
  final read = <String>{};
  final edited = <String>{};
  var commands = 0, searches = 0, agents = 0, other = 0, failed = 0, denied = 0, running = 0, remembered = 0;
  for (final t in tools) {
    if (t.running) running++;
    if (t.denied) {
      denied++;
    } else if (!t.running && !t.ok) {
      failed++;
    }
    final good = t.running || (t.ok && !t.denied);
    if (t.name == 'memory_write' && !t.running && t.ok && !t.denied) remembered++;
    final args = _argsOf(t.arguments);
    // 没写路径的（低代码页面、文件列表）按“工具名”算一个，免得同一个东西数好几次。
    final path = '${args['path'] ?? ''}'.trim().isEmpty ? '\u0000${t.name}' : '${args['path']}'.trim();
    switch (stepKindOf(t.name)) {
      case StepKind.read:
        if (good) read.add(path);
      case StepKind.edit || StepKind.delete:
        if (good) edited.add(path);
      case StepKind.command:
        commands++;
      case StepKind.search:
        searches++;
      case StepKind.agent:
        agents++;
      case StepKind.look || StepKind.ask || StepKind.plan || StepKind.other:
        other++;
    }
  }
  return StepSummary(
    total: tools.length,
    read: read.length,
    edited: edited.length,
    commands: commands,
    searches: searches,
    agents: agents,
    other: other,
    failed: failed,
    denied: denied,
    running: running,
    remembered: remembered,
  );
}

/// 现在该显示的待办清单：最后一条用户消息之后、最近一次成功的 update_todos。没有就是 null。
/// （只看当前这一轮：上一轮没做完的清单不会一直挂着。）
List<TodoEntry>? latestTodos(List<ChatItem> items) {
  for (var i = items.length - 1; i >= 0; i--) {
    final item = items[i];
    if (item is UserItem) return null;
    if (item is ToolItem && item.name == 'update_todos' && !item.running && item.ok) return tryParseTodos(item.arguments);
  }
  return null;
}
