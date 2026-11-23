// 聊天里要显示、要排队的那些东西。全都不可变：要改就换一个新的，交给对应的 Notifier 换进状态里。
import 'dart:async';

import 'package:lopicode/agent/agent_tools.dart';
import 'package:lopicode/agent/usage.dart';

/// 对话里显示的一项。
sealed class ChatItem {
  const ChatItem();
}

class UserItem extends ChatItem {
  const UserItem(this.text, {this.images = const []});
  final String text;

  /// 图片附件在手机上的完整路径。
  final List<String> images;
}

class AssistantItem extends ChatItem {
  const AssistantItem(this.text, {this.streaming = false});
  final String text;
  final bool streaming;

  AssistantItem copyWith({String? text, bool? streaming}) => AssistantItem(text ?? this.text, streaming: streaming ?? this.streaming);
}

class ToolItem extends ChatItem {
  const ToolItem(this.callId, this.name, this.arguments, {this.result, this.ok = true, this.denied = false, this.childConversationId});
  final String callId;
  final String name;
  final String arguments;
  final String? result;
  final bool ok;
  final bool denied;
  bool get running => result == null;

  /// 派子代理的调用：对应的子对话。
  final String? childConversationId;

  ToolItem copyWith({String? result, bool? ok, bool? denied, String? childConversationId}) =>
      ToolItem(callId, name, arguments, result: result ?? this.result, ok: ok ?? this.ok, denied: denied ?? this.denied, childConversationId: childConversationId ?? this.childConversationId);
}

/// 上下文占用。
class ContextUsage {
  const ContextUsage(this.used, this.limit, {required this.estimated});
  final int used;
  final int limit;

  /// true＝按字数估的“预计下次请求”；false＝接口返回的“上次请求”。
  final bool estimated;
  double get fraction => (used / limit).clamp(0.0, 1.0);
}

/// 一轮结束后，回复下方那行用量。
class UsageItem extends ChatItem {
  const UsageItem(this.turn);
  final TurnUsage turn;
}

class NoticeItem extends ChatItem {
  const NoticeItem(this.text, {this.isError = false});
  final String text;
  final bool isError;
}

/// 等用户点“允许 / 拒绝”的确认卡。
class PendingApproval {
  PendingApproval(this.request, {this.conversationId = '', this.agentName = ''});
  final ApprovalRequest request;
  final String conversationId;

  /// 是哪个子代理要的；主智能体为空。
  final String agentName;
  final Completer<bool> completer = Completer<bool>();
}

/// AI 向用户提的问题（选择卡）。
class PendingQuestion {
  PendingQuestion(this.question, this.options, {this.conversationId = '', this.agentName = ''});
  final String question;
  final List<String> options;
  final String conversationId;
  final String agentName;
  final Completer<String> completer = Completer<String>();
}

/// AI 生成过程中用户又发的消息：排队的，或者插话（还没交给模型的）。
class QueuedMessage {
  const QueuedMessage(this.text, {this.images = const [], this.steer = false});
  final String text;
  final List<Map<String, dynamic>> images;

  /// true＝插话（下一步交给模型）；false＝排队（这一轮结束后再发）。
  final bool steer;

  QueuedMessage asSteer(bool value) => QueuedMessage(text, images: images, steer: value);
}

/// 发送方式（AI 正在生成时）。
enum SendMode { queue, steer, interrupt }
