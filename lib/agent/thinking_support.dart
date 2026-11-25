// 各家接口“思考”到底怎么调：这个模型在这个渠道上真实能选哪些档位、每个档位发什么参数。
//
// 规矩（docs/api-notes.md「2026-11-25 思考档位」逐家记了来源）：
// - 只有官方文档核对过的服务商 / 模型才发它专属的参数；核对不了的一律走通用做法
//   （OpenAI Chat 协议：选了档位才发 `reasoning_effort`，没选什么都不发）。
// - 模型没标记“可思考”时，什么思考参数都不发（DeepSeek 官方地址例外：它默认开着思考，见 chat_client.dart）。
// - 档位只给真实有区别的：点了没用的档位不出现。
import 'package:lopicode/agent/model_config.dart';
import 'package:lopicode/agent/provider_presets.dart';

/// 请求里思考参数的写法。
enum ThinkingWire {
  /// 通用：`reasoning_effort: 档位`；选“默认”什么都不发。
  effort,

  /// Gemini 2.5（非 Pro）：同上，但“关”发 `reasoning_effort: "none"`。
  effortWithNone,

  /// 开关：`enable_thinking: true / false`（阿里云百炼的千问、硅基流动）。
  enableThinking,

  /// 开关：`thinking: {type: enabled / disabled}`（智谱）。
  thinkingType,

  /// 智谱 GLM-5.2：关＝`thinking: {type: disabled}`；开＝`thinking: {type: enabled}` 加 `reasoning_effort`。
  thinkingTypeWithEffort,

  /// 只能关：关＝`thinking: {type: disabled}`，开着什么都不发（Kimi K2.6）。
  disableOnly,

  /// 调不了：什么都不发。
  fixed,

  /// Anthropic 老写法：`thinking: {type: enabled, budget_tokens}`。
  anthropicBudget,

  /// Anthropic 新写法：`thinking: {type: adaptive}` 加 `output_config: {effort}`。
  anthropicAdaptive,
}

/// Anthropic 新写法下，选“关 / 默认”时发什么。
enum AnthropicOff {
  /// 什么都不发（模型默认就不思考，或者只能用它的默认）。
  omit,

  /// 明说 `thinking: {type: disabled}`（默认开着、又允许关的模型）。
  disabled,

  /// 模型一直在思考、关不掉：只要一份能看的思考摘要，不指定强度。
  alwaysOn,
}

/// 一个模型在一个渠道上的思考能力。
class ThinkingCaps {
  const ThinkingCaps({required this.options, required this.offIsDefault, required this.wire, required this.note, this.anthropicOff = AnthropicOff.omit, this.verified = true});

  /// 能选的档位，第一个永远是 `off`。只有 `off` 一个＝调不了。
  final List<String> options;

  /// `off` 这一档是不是只是“不发参数、让模型按自己的默认来”（界面写“默认”）；false＝真的不思考（界面写“关”）。
  final bool offIsDefault;
  final ThinkingWire wire;

  /// 给用户看的一句话：这家是怎么回事。
  final String note;
  final AnthropicOff anthropicOff;

  /// 是不是按官方文档核对过的专属规则（false＝通用做法）。
  final bool verified;

  bool get adjustable => options.length > 1;
}

const _graded = ['off', 'low', 'medium', 'high'];

const _generic = ThinkingCaps(options: _graded, offIsDefault: true, wire: ThinkingWire.effort, note: '“默认”＝不发思考参数，模型按自己的默认来。', verified: false);

/// Claude 的模型 ID → 产品线和版本号（`claude-opus-4-7` → opus 4.7；`claude-sonnet-4-20250514` → sonnet 4.0；
/// `claude-3-7-sonnet-…` → sonnet 3.7）。认不出来返回 null。
({String line, int major, int minor})? parseClaudeId(String id) {
  final s = id.toLowerCase();
  final a = RegExp(r'claude-(opus|sonnet|haiku|fable|mythos)-(\d{1,2})(?!\d)(?:[-.](\d{1,2})(?!\d))?').firstMatch(s);
  if (a != null) return (line: a.group(1)!, major: int.parse(a.group(2)!), minor: int.parse(a.group(3) ?? '0'));
  final b = RegExp(r'claude-(\d)(?:[-.](\d))?-(opus|sonnet|haiku)').firstMatch(s);
  if (b != null) return (line: b.group(3)!, major: int.parse(b.group(1)!), minor: int.parse(b.group(2) ?? '0'));
  if (RegExp(r'claude-(fable|mythos)').hasMatch(s)) return (line: s.contains('fable') ? 'fable' : 'mythos', major: 5, minor: 0);
  return null;
}

ThinkingCaps _claudeCaps(String modelId) {
  final v = parseClaudeId(modelId);
  if (v == null) {
    return const ThinkingCaps(options: _graded, offIsDefault: true, wire: ThinkingWire.anthropicBudget, note: '认不出是哪一代 Claude，按老写法发思考预算；“默认”＝不发思考参数。', verified: false);
  }
  final n = v.major * 10 + v.minor;
  const alwaysOn = ThinkingCaps(options: _graded, offIsDefault: true, wire: ThinkingWire.anthropicAdaptive, anthropicOff: AnthropicOff.alwaysOn, note: '这个模型一直在思考，关不掉；“默认”＝用它自己的强度。');
  if (v.line == 'fable' || v.line == 'mythos') return alwaysOn;
  if (n < 46) return const ThinkingCaps(options: _graded, offIsDefault: false, wire: ThinkingWire.anthropicBudget, note: '档位换成思考预算发给接口（低 4K / 中 16K / 高 32K）。');
  // 默认开着、文档写明可以用 disabled 关掉的三个
  final canDisable = (v.line == 'opus' && n == 50) || (v.line == 'sonnet' && n == 50) || (v.line == 'haiku' && n == 55);
  if (canDisable) return const ThinkingCaps(options: _graded, offIsDefault: false, wire: ThinkingWire.anthropicAdaptive, anthropicOff: AnthropicOff.disabled, note: '这个模型默认会思考，选“关”会明确关掉。');
  // 默认不思考的：4.6 两个、Opus 4.7 / 4.8
  final offByDefault = n == 46 || (v.line == 'opus' && (n == 47 || n == 48));
  if (offByDefault) return const ThinkingCaps(options: _graded, offIsDefault: false, wire: ThinkingWire.anthropicAdaptive, note: '由模型自己决定想多久，档位是给它的强度。');
  return alwaysOn;
}

ThinkingCaps _zhipuCaps(String id) {
  if (id.startsWith('glm-5.3')) {
    return const ThinkingCaps(options: ['off', 'low', 'high', 'max'], offIsDefault: true, wire: ThinkingWire.effort, note: '这个模型一直在思考，关不掉；“默认”＝最高。');
  }
  if (id.startsWith('glm-5.2')) {
    return const ThinkingCaps(options: ['off', 'high', 'max'], offIsDefault: false, wire: ThinkingWire.thinkingTypeWithEffort, note: '这个模型只分“高”和“最高”两档。');
  }
  return const ThinkingCaps(options: ['off', 'on'], offIsDefault: false, wire: ThinkingWire.thinkingType, note: '这个模型的思考只能开或关，不分档位。');
}

ThinkingCaps _kimiCaps(String id) {
  if (id.startsWith('kimi-k3')) {
    return const ThinkingCaps(options: ['off', 'low', 'high', 'max'], offIsDefault: true, wire: ThinkingWire.effort, note: '这个模型一直在思考，关不掉；“默认”＝最高。');
  }
  if (id.startsWith('kimi-k2.7-code')) {
    return const ThinkingCaps(options: ['off'], offIsDefault: true, wire: ThinkingWire.fixed, note: '这个模型一直在思考，接口不让调强度，也关不掉。');
  }
  if (id.startsWith('kimi-k2.6')) {
    return const ThinkingCaps(options: ['off', 'on'], offIsDefault: false, wire: ThinkingWire.disableOnly, note: '这个模型的思考只能开或关，不分档位。');
  }
  return _generic;
}

/// 假设模型已经标记“可思考”，它在这个渠道上能怎么调。
ThinkingCaps thinkingCaps(ChatProtocol protocol, String baseUrl, String modelId) {
  final id = modelId.trim().toLowerCase();
  switch (protocol) {
    case ChatProtocol.anthropic:
      return _claudeCaps(id);
    case ChatProtocol.openaiResponses:
      return const ThinkingCaps(options: _graded, offIsDefault: true, wire: ThinkingWire.effort, note: '“默认”＝不发思考参数，模型按自己的默认来。');
    case ChatProtocol.openaiChat:
      break;
  }
  switch (presetForBaseUrl(baseUrl)?.id) {
    case 'deepseek':
      return const ThinkingCaps(options: ['off', 'low', 'high', 'max'], offIsDefault: false, wire: ThinkingWire.effort, note: 'DeepSeek 只分低、高、最高三档（它把“中”当“高”）。');
    case 'openai':
      return const ThinkingCaps(options: _graded, offIsDefault: true, wire: ThinkingWire.effort, note: '“默认”＝不发思考参数，模型按自己的默认来（有的模型不让关）。');
    case 'openrouter':
      return const ThinkingCaps(options: _graded, offIsDefault: true, wire: ThinkingWire.effort, note: '“默认”＝不发思考参数，模型按自己的默认来。');
    case 'gemini':
      if (id.contains('gemini-2.5') && !id.contains('pro')) {
        return const ThinkingCaps(options: _graded, offIsDefault: false, wire: ThinkingWire.effortWithNone, note: '选“关”会明确关掉思考。');
      }
      return const ThinkingCaps(options: _graded, offIsDefault: true, wire: ThinkingWire.effort, note: '这个模型关不掉思考；“默认”＝用它自己的强度。');
    case 'bailian':
      if (id.startsWith('qwen')) {
        return const ThinkingCaps(options: ['off', 'on'], offIsDefault: false, wire: ThinkingWire.enableThinking, note: '千问的思考只能开或关，不分档位。');
      }
      return _generic;
    case 'siliconflow':
      return const ThinkingCaps(options: ['off', 'on'], offIsDefault: false, wire: ThinkingWire.enableThinking, note: '硅基流动的思考只能开或关，不分档位。');
    case 'zhipu':
      return _zhipuCaps(id);
    case 'moonshot':
      return _kimiCaps(id);
  }
  return _generic;
}

/// 这个模型现在真实能选的档位（没标记“可思考”就只有 `off`）。模型设置里去掉的档位不出现。
List<String> thinkingOptions(Channel channel, ModelSpec model) {
  if (!model.thinking) return const ['off'];
  final caps = thinkingCaps(channel.protocol, channel.baseUrl, model.id);
  return [
    for (final o in caps.options)
      if (!kThinkingLevels.contains(o) || model.levels.contains(o)) o,
  ];
}

/// 把一个档位落到 [options] 里：没有这一档就挑最接近的（先往高找，再往低找），实在没有就是 `off`。
String normalizeThinkingLevel(List<String> options, String level) {
  if (options.contains(level)) return level;
  const order = ['low', 'medium', 'high', 'max'];
  if (level == 'on') {
    for (final l in const ['medium', 'high', 'low', 'max']) {
      if (options.contains(l)) return l;
    }
    return 'off';
  }
  final i = order.indexOf(level);
  if (i < 0) return 'off';
  if (options.contains('on')) return 'on';
  for (var j = i + 1; j < order.length; j++) {
    if (options.contains(order[j])) return order[j];
  }
  for (var j = i - 1; j >= 0; j--) {
    if (options.contains(order[j])) return order[j];
  }
  return 'off';
}

/// 档位在界面上叫什么。`off` 要看这家是“真的关”还是“不发参数”。
String thinkingOptionLabel(ThinkingCaps caps, String level) => level == 'off' ? (caps.offIsDefault ? '默认' : '关') : thinkingLabel(level);

/// OpenAI Chat 协议下这一次请求的思考参数：`reasoning_effort` 的值（null 不发）和要并进请求体的其它字段。
({String? effort, Map<String, dynamic> extra}) openAiChatThinking(ThinkingCaps caps, {required bool marked, required String level}) {
  const none = (effort: null, extra: <String, dynamic>{});
  if (!marked) return none;
  final off = level == 'off';
  switch (caps.wire) {
    case ThinkingWire.effort:
      return off ? none : (effort: level, extra: const {});
    case ThinkingWire.effortWithNone:
      return (effort: off ? 'none' : level, extra: const {});
    case ThinkingWire.enableThinking:
      return (effort: null, extra: {'enable_thinking': !off});
    case ThinkingWire.thinkingType:
      return (
        effort: null,
        extra: {
          'thinking': {'type': off ? 'disabled' : 'enabled'},
        },
      );
    case ThinkingWire.thinkingTypeWithEffort:
      return (
        effort: off ? null : level,
        extra: {
          'thinking': {'type': off ? 'disabled' : 'enabled'},
        },
      );
    case ThinkingWire.disableOnly:
      return off
          ? (
              effort: null,
              extra: {
                'thinking': {'type': 'disabled'},
              },
            )
          : none;
    case ThinkingWire.fixed:
    case ThinkingWire.anthropicBudget:
    case ThinkingWire.anthropicAdaptive:
      return none;
  }
}

/// 官方文档能核对到“确实支持思考”的模型（添加模型时据此默认标成可思考）。拿不准的一律 false。
/// [listed]：模型列表接口自己说了它能思考（目前只有 OpenRouter 的 `reasoning` 字段）。
bool knownThinkingModel(ChatProtocol protocol, String baseUrl, String modelId, {bool listed = false}) {
  final id = modelId.trim().toLowerCase();
  if (protocol == ChatProtocol.anthropic) {
    final v = parseClaudeId(id);
    if (v == null) return false;
    final n = v.major * 10 + v.minor;
    if (v.line == 'fable' || v.line == 'mythos' || n >= 46) return true;
    return switch (v.line) {
      'opus' => n == 40 || n == 41 || n == 45,
      'sonnet' => n == 40 || n == 45,
      'haiku' => n == 45,
      _ => false,
    };
  }
  if (protocol != ChatProtocol.openaiChat) return false;
  return switch (presetForBaseUrl(baseUrl)?.id) {
    'deepseek' => id.startsWith('deepseek-'),
    'gemini' => RegExp(r'gemini-(2\.5|3|4)').hasMatch(id),
    'zhipu' => RegExp(r'^glm-(4\.[5-7]|5)').hasMatch(id),
    'moonshot' => id.startsWith('kimi-k3') || id.startsWith('kimi-k2.7-code') || id.startsWith('kimi-k2.6'),
    'openrouter' => listed,
    _ => false,
  };
}

/// 新加进渠道的模型：能核对到支持思考的默认就标上。
ModelSpec newModelSpec(ChatProtocol protocol, String baseUrl, String id, {String? name, bool listedThinking = false}) => ModelSpec(
  id: id,
  name: name,
  thinking: knownThinkingModel(protocol, baseUrl, id, listed: listedThinking),
);

/// 思考档位 → `budget_tokens`（自己定的换算，见 api-notes）。
int anthropicBudget(String level) => switch (level) {
  'low' => 4096,
  'medium' => 16384,
  _ => 32768,
};

/// Anthropic Messages 请求体里的思考参数（没有就是空表）。[level] 为空＝没选档位。
Map<String, dynamic> anthropicThinkingBody({required String? level, required bool adaptive, required AnthropicOff whenOff, required int maxTokens}) {
  if (!adaptive) {
    if (level == null || maxTokens <= 2048) return const {};
    // 思考预算最少 1024，而且必须小于 max_tokens。
    return {
      'thinking': {'type': 'enabled', 'budget_tokens': anthropicBudget(level).clamp(1024, maxTokens - 1024)},
    };
  }
  // display: summarized＝要一份能看的思考摘要（新模型默认不给文字）。
  const visible = {'type': 'adaptive', 'display': 'summarized'};
  if (level != null) {
    return {
      'thinking': visible,
      'output_config': {'effort': level},
    };
  }
  return switch (whenOff) {
    AnthropicOff.omit => const {},
    AnthropicOff.disabled => const {
      'thinking': {'type': 'disabled'},
    },
    AnthropicOff.alwaysOn => const {'thinking': visible},
  };
}
