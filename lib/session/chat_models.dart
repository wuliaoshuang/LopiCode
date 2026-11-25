// 聊天里要显示、要排队的那些东西。全都不可变：要改就换一个新的，交给对应的 Notifier 换进状态里。
import 'dart:async';

import 'package:lopicode/agent/agent_tools.dart';
import 'package:lopicode/agent/line_diff.dart';
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
  const ToolItem(this.callId, this.name, this.arguments, {this.result, this.ok = true, this.denied = false, this.childConversationId, this.change, this.startedAt, this.ms});

  /// 这一步从什么时候开始的（只在这次运行里有，界面拿它算“已经跑了几秒”；重新打开的旧记录是 null）。
  final DateTime? startedAt;

  /// 这一步一共用了多久（毫秒，含等用户点确认的时间）；旧记录里没存就是 null。
  final int? ms;

  /// 这一步把文件改成了什么样（精简的对比，不带全文）；没改文件、旧记录里没存就是 null。
  final FileChange? change;
  final String callId;
  final String name;
  final String arguments;
  final String? result;
  final bool ok;
  final bool denied;
  bool get running => result == null;

  /// 派子代理的调用：对应的子对话。
  final String? childConversationId;

  ToolItem copyWith({String? result, bool? ok, bool? denied, String? childConversationId, FileChange? change, int? ms}) => ToolItem(
    callId,
    name,
    arguments,
    result: result ?? this.result,
    ok: ok ?? this.ok,
    denied: denied ?? this.denied,
    childConversationId: childConversationId ?? this.childConversationId,
    change: change ?? this.change,
    startedAt: startedAt,
    ms: ms ?? this.ms,
  );
}

/// 模型的一段思考。[streaming]＝还在想；想完后 [ms] 是想了多久（旧记录里没存就是 null）。
class ThinkingItem extends ChatItem {
  const ThinkingItem(this.text, {this.streaming = false, this.ms, this.startedAt});
  final String text;
  final bool streaming;
  final int? ms;

  /// 从什么时候开始想的（只在还在想的时候有，界面拿它算“已经想了几秒”）。
  final DateTime? startedAt;

  ThinkingItem copyWith({String? text, bool? streaming, int? ms}) => ThinkingItem(text ?? this.text, streaming: streaming ?? this.streaming, ms: ms ?? this.ms, startedAt: startedAt);
}

/// “已压缩较早的对话”：[summary] 是顶替它们的那份摘要。
class CompactionItem extends ChatItem {
  const CompactionItem(this.summary);
  final String summary;
}

/// 上一轮没正常结束（App 被关掉 / 被系统回收）：下次打开这段对话时的提示。
class InterruptedItem extends ChatItem {
  const InterruptedItem({required this.headline, required this.lines, required this.risky});

  /// 一句话：上次停在哪。
  final String headline;

  /// 细节：哪些步骤已经执行、哪一步可能只做了一半……一行一条。
  final List<String> lines;

  /// 有没有“可能只执行了一半”的步骤（有的话提示要醒目一点）。
  final bool risky;
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

/// 一轮结束后，回复下方那行“改了 N 个文件”。[files] 是这一轮合并后的改动（子代理改的也在里面）。
class ChangedFilesItem extends ChatItem {
  const ChangedFilesItem(this.files);
  final List<FileChange> files;
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
  PendingQuestion(this.question, this.options, {this.conversationId = '', this.agentName = '', this.title, this.choiceOnly = false});

  /// 卡片标题；null 用默认的“Agent 想问你”。
  final String? title;

  /// 只能从选项里选（应用自己问的“要不要继续”）：不给“其他回答”。
  final bool choiceOnly;
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
