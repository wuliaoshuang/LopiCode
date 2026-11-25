// 把“一轮在跑”接到后台保活上（lib/agent/keep_alive.dart）：一轮开始领票，跑的过程中把“正在做什么”
// 和“是不是卡在确认卡上”告诉它，结束时交票。主对话、子代理、自动化任务都从 TurnRunner.execute 走这里。
//
// 这里只看状态，不改 Agent 怎么跑；通知上点“停止”时走的也是聊天页那个停止。
import 'dart:convert';

import 'package:lopicode/agent/keep_alive.dart';
import 'package:lopicode/session/chat_models.dart';
import 'package:lopicode/session/chat_rows.dart';
import 'package:lopicode/session/session_core.dart';
import 'package:lopicode/state/workspace_chat.dart';

/// 通知上那句“正在做什么”。只看这一轮（最后一条用户消息之后）的条目。
/// 命令、路径原样给，脱敏和截短在 [safeNoticeText]（AgentKeepAlive 发出去之前统一做）。
String turnStatusText(List<ChatItem> items) {
  var steps = 0;
  ToolItem? running;
  ChatItem? last;
  for (var i = items.length - 1; i >= 0; i--) {
    final item = items[i];
    if (item is UserItem) break;
    last ??= item;
    if (item is ToolItem) {
      steps++;
      if (item.running) running ??= item;
    }
  }
  final String doing;
  if (running != null) {
    doing = _doing(running);
  } else if (last is ThinkingItem && last.streaming) {
    doing = '正在思考';
  } else if (last is AssistantItem && last.streaming) {
    doing = '正在写回复';
  } else {
    doing = steps == 0 ? '正在等模型回应' : '正在想下一步';
  }
  return steps == 0 ? doing : '第 $steps 步 · $doing';
}

String _doing(ToolItem tool) {
  String arg(String key) {
    try {
      final decoded = jsonDecode(tool.arguments);
      final v = decoded is Map ? decoded[key] : null;
      return v is String ? v.trim() : '';
    } on FormatException {
      return ''; // 参数还没收全 / 不是合法 JSON：只说动作
    }
  }

  String withTarget(String verb, String target) => target.isEmpty ? verb : '$verb $target';
  switch (tool.name) {
    case 'write_file':
      return withTarget('正在改', arg('path'));
    case 'read_file':
      return withTarget('正在读', arg('path'));
    case 'delete_file':
      return withTarget('正在删', arg('path'));
    case 'list_files':
      return '正在看文件列表';
    case 'run_command':
      final command = arg('command');
      return command.isEmpty ? '正在跑命令' : '正在跑命令：$command';
    case 'web_search':
      return '正在联网搜索';
    case 'spawn_agent':
      return '正在派子代理';
    case 'ask_user':
      return '在等你回答';
  }
  final (verb, _) = stepLabel(tool.name, tool.arguments);
  // 没有中文名的工具（以后新加的）：说“正在调用 xxx”
  return verb == tool.name ? '正在调用 ${tool.name}' : '正在$verb';
}

class TurnKeepAlive {
  TurnKeepAlive._(this._core, this._run) : _startLen = _run.items.length {
    final app = _core.app;
    final conv = _run.conv;
    _ticket = app.keepAlive.begin(title: conv.title, root: conv.parentId == null, unattended: _run.unattended, cancel: _cancel);
    if (app.disposed) return;
    final runSub = app.container.listen<ChatRunState>(chatRunProvider((_core.session, _run.convId)), (_, next) => _ticket.status(turnStatusText(next.items)));
    final cardSub = app.container.listen<PendingCardsState>(pendingCardsProvider(_core.session), (_, next) => _ticket.waiting(_waitingOn(next)), fireImmediately: true);
    _closers.addAll([runSub.close, cardSub.close]);
  }

  /// 一轮开始（紧挨着 `try` 前面调：和收尾里的 [finish] 一定成对）。
  factory TurnKeepAlive.start(SessionCore core, ChatRunNotifier run) => TurnKeepAlive._(core, run);

  final SessionCore _core;
  final ChatRunNotifier _run;
  final int _startLen;
  late final KeepAliveTicket _ticket;
  final List<void Function()> _closers = [];

  bool _waitingOn(PendingCardsState cards) => cards.approvals.any((a) => a.conversationId == _run.convId) || cards.questions.any((q) => q.conversationId == _run.convId);

  /// 通知上点了“停止”。当前对话走聊天页那个停止（连它派的子代理、排队规矩一起）；别的对话只停它自己。
  void _cancel() {
    if (identical(_run, _core.active)) {
      _core.session.stopAgent();
    } else {
      _run.runner?.cancel();
      _core.cards.dropOf({_run.convId});
    }
  }

  /// 一轮结束（收尾里调）。[failed]＝没做成。用户点了停止的不算出错，也不提醒。
  void finish({required bool failed}) {
    for (final close in _closers) {
      close();
    }
    _closers.clear();
    final from = (_startLen - 1).clamp(0, _run.items.length);
    final stopped = _run.items.skip(from).any((i) => i is NoticeItem && i.text.startsWith('已停止'));
    _ticket.end(stopped ? TurnEnd.stopped : (failed ? TurnEnd.failed : TurnEnd.done));
  }
}
