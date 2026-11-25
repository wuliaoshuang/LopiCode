// Agent 循环往外发的事件（聊天页、用量统计、通知都靠它们知道进行到哪了）。从 agent_runner.dart 拆出来，免得那个文件超长。
import 'package:lopicode/agent/agent_tools.dart';
import 'package:lopicode/agent/usage.dart';

sealed class AgentEvent {}

/// 模型正在输出的文字（增量）。
class AssistantDelta extends AgentEvent {
  AssistantDelta(this.text);
  final String text;
}

/// 模型正在思考（增量）。只用来显示，不算回复。
class ReasoningDelta extends AgentEvent {
  ReasoningDelta(this.text);
  final String text;
}

/// 这一段思考结束了（开始说话 / 调工具，或者这次回复结束）。[ms] 是想了多久。
class ReasoningDone extends AgentEvent {
  ReasoningDone(this.ms);
  final int ms;
}

/// 上下文快满，较早的对话已经压成摘要（这一轮接着跑）。
class ContextCompacted extends AgentEvent {
  ContextCompacted(this.summary, this.replaced);
  final String summary;

  /// 被摘要顶替的消息条数。
  final int replaced;
}

/// 一轮模型回复结束（[text] 是这一轮的完整文字，可能为空）。
class AssistantMessage extends AgentEvent {
  AssistantMessage(this.text, {this.id});
  final String text;

  /// 这段回复存进消息记录时的稳定标识（`_id`）；没存（被打断而且一个字没说）是 null。
  final String? id;
}

class ToolStarted extends AgentEvent {
  ToolStarted(this.callId, this.name, this.arguments);
  final String callId;
  final String name;
  final String arguments;
}

class ToolFinished extends AgentEvent {
  ToolFinished(this.callId, this.name, this.outcome, {this.ms});
  final String callId;
  final String name;
  final ToolOutcome outcome;

  /// 这一步用了多久（毫秒，含等用户点确认的时间）；没真正执行的是 null。
  final int? ms;
}

/// 生成过程中用户插的话，已经交给模型（从这一步起它能看到）。
class UserInjected extends AgentEvent {
  UserInjected(this.text, {this.id});
  final String text;

  /// 这句插话在消息记录里的稳定标识（`_id`）。
  final String? id;
}

/// 应用自己告诉模型的一件事（不是用户说的话）。[text] 给模型看；[label] 是聊天页上那一行短提示。
class AppNotice {
  const AppNotice(this.text, this.label);
  final String text;
  final String label;
}

/// 一条应用通知已经交给模型。
class NoticeInjected extends AgentEvent {
  NoticeInjected(this.notice);
  final AppNotice notice;
}

/// 消息记录里“应用通知”的标记（值是聊天页上显示的那行短提示）：聊天页据此显示成一行提示而不是用户消息。
const String kAppNoticeMark = '_notice';

/// 应用自己的提示（例如达到轮次上限）。
class AgentNotice extends AgentEvent {
  AgentNotice(this.text);
  final String text;
}

/// 一次模型请求结束（成功、被打断、或者中途断了）。[usage] 是接口给的用量，没给是 null。
class RequestFinished extends AgentEvent {
  RequestFinished(this.usage, this.ms, {this.firstMs, this.startedAt, this.compaction = false});
  final TokenUsage? usage;

  /// 这次请求是“自动压缩对话”那一次（照样算进这一轮的用量）。
  final bool compaction;
  final int ms;

  /// 从发出到收到第一块内容（文字或工具调用）的用时；一块都没收到是 null。
  final int? firstMs;
  final DateTime? startedAt;
}

class AgentError extends AgentEvent {
  AgentError(this.text, {this.partialId});
  final String text;

  /// 出错前模型已经说了半截、这半截存进了消息记录：它的稳定标识（`_id`）。没有半截是 null。
  final String? partialId;
}
