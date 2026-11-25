import 'package:http/http.dart' as http;
import 'package:lopicode/agent/chat_client.dart';
import 'package:lopicode/agent/model_config.dart';
import 'package:lopicode/agent/protocols.dart';
import 'package:lopicode/agent/thinking_support.dart';

/// 按“渠道 + 模型 + 思考档位”造客户端。每家发什么思考参数由 lib/agent/thinking_support.dart 定。
ChatClient buildChatClient(ResolvedModel r, String apiKey, {http.Client? httpClient}) {
  final m = r.model;
  final caps = thinkingCaps(r.channel.protocol, r.channel.baseUrl, m.id);
  // 没标记“可思考”的模型、思考参数没核对过的服务商：一律当没选档位，一个思考参数都不发
  final marked = m.thinking && caps.verified;
  final level = !marked || r.level == 'off' ? null : r.level;
  switch (r.channel.protocol) {
    case ChatProtocol.openaiChat:
      final plan = openAiChatThinking(caps, marked: marked, level: level ?? 'off');
      return OpenAiChatClient(
        baseUrl: r.channel.baseUrl,
        apiKey: apiKey,
        model: m.id,
        reasoningEffort: plan.effort,
        extraBody: plan.extra,
        maxTokens: m.maxOutput == ModelSpec.defaultMaxOutput ? null : m.maxOutput,
        httpClient: httpClient,
      );
    case ChatProtocol.anthropic:
      return AnthropicChatClient(
        baseUrl: r.channel.baseUrl,
        apiKey: apiKey,
        model: m.id,
        maxTokens: m.maxOutput,
        thinkingLevel: level,
        adaptive: caps.wire == ThinkingWire.anthropicAdaptive,
        whenOff: marked ? caps.anthropicOff : AnthropicOff.omit,
        httpClient: httpClient,
      );
    case ChatProtocol.openaiResponses:
      return OpenAiResponsesClient(baseUrl: r.channel.baseUrl, apiKey: apiKey, model: m.id, maxOutputTokens: m.maxOutput, reasoningEffort: level, httpClient: httpClient);
  }
}
