// 上下文占用的分段估算：系统提示词 / 工具定义 / 对话消息 / 工具结果 / 剩余。纯计算。
//
// 全是按字数估的（约 3 个字符算 1 个 token，和 AgentRunner.estimateTokens 同一个口径），和接口实际计的数会有出入；
// 界面上要写明“估算”。已归档（被摘要顶替）的消息不算——它们不再发给模型。
import 'package:lopicode/agent/auto_compact.dart';

class ContextSegments {
  const ContextSegments({required this.system, required this.tools, required this.messages, required this.toolResults, required this.limit});

  /// 系统提示词。
  final int system;

  /// 工具定义。
  final int tools;

  /// 对话消息（用户和助手说的话、助手发起的工具调用、图片附件）。
  final int messages;

  /// 工具结果。
  final int toolResults;

  /// 模型的上下文长度。
  final int limit;

  int get used => system + tools + messages + toolResults;

  /// 还剩多少；估出来已经超了就是 0。
  int get remaining => used >= limit ? 0 : limit - used;

  /// 横条的总长：正常是上下文长度；估出来超了就按已用的算（各段照比例挤满）。
  int get total => used > limit ? used : limit;

  /// 某一段占横条的比例（0–1）。
  double shareOf(int tokens) => total <= 0 ? 0 : tokens / total;

  /// 把消息记录分成“对话消息”和“工具结果”两段来估。
  factory ContextSegments.of({required int system, required int tools, required List<Map<String, dynamic>> messages, required int limit}) {
    var talk = 0, results = 0;
    for (final m in messages) {
      if (isArchived(m)) continue;
      var chars = '${m['content'] ?? ''}'.length;
      final calls = m['tool_calls'];
      for (final c in calls is List ? calls : const []) {
        chars += '$c'.length;
      }
      final images = m['_images'];
      chars += (images is List ? images.length : 0) * 3000;
      if (m['role'] == 'tool') {
        results += chars;
      } else {
        talk += chars;
      }
    }
    return ContextSegments(system: system, tools: tools, messages: talk ~/ 3, toolResults: results ~/ 3, limit: limit);
  }
}
