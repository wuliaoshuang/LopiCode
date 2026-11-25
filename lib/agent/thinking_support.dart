// 各家接口“思考”到底怎么调：这个模型在这个渠道上真实能选哪些档位、每个档位发什么参数。
//
// 规矩（docs/api-notes.md「2026-11-25 思考档位」逐家记了来源）：
// - 只有官方文档核对过的服务商 / 模型才有档位、才发思考参数。核对不了的（[ThinkingCaps.verified] 为 false）：
//   界面上不给档位也不给“可思考”开关，只写一句说明；请求里一个思考参数都不发，连通用的 `reasoning_effort` 也不发。
//   （2026-11-25 霜霜定的。旧存盘里已经标了“可思考”、记了档位的，读进来照样按“不发”处理。）
// - 怎么算“核对过”：官方地址按地址认；自己填的地址（中转站）按模型名认，认得出是核对过的那几家的模型才算；
//   本机 / 局域网地址、没核对过的服务商的官方地址，一律不算。见 [thinkingCaps]。
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

  /// 是不是按官方文档核对过的规则。false＝没核对过：没有档位、不发任何思考参数，[note] 写的是为什么。
  final bool verified;

  /// 没核对过的服务商 / 模型：只有 `off`，什么都不发。
  const ThinkingCaps.unverified(this.note) : options = const ['off'], offIsDefault = true, wire = ThinkingWire.fixed, anthropicOff = AnthropicOff.omit, verified = false;

  bool get adjustable => options.length > 1;
}

const _graded = ['off', 'low', 'medium', 'high'];

const _noParams = '请求里不带任何思考参数，模型按自己的默认来。';

/// 没核对过时写给用户的那句话。
ThinkingCaps _unverifiedProvider(String name) => ThinkingCaps.unverified('$name的思考参数还没对着官方文档核对过，暂时不能在这里调。$_noParams');
const _unverifiedModel = ThinkingCaps.unverified('这个模型的思考参数还没对着官方文档核对过，暂时不能在这里调。$_noParams');
const _unverifiedRelay = ThinkingCaps.unverified('这是自己填的接口地址，从模型名认不出是哪家的模型，思考参数没法核对，暂时不能在这里调。$_noParams');
const _unverifiedLocal = ThinkingCaps.unverified('本机 / 局域网服务的思考参数还没对着官方文档核对过，暂时不能在这里调。$_noParams');

const _openAiEffort = ThinkingCaps(options: _graded, offIsDefault: true, wire: ThinkingWire.effort, note: '“默认”＝不发思考参数，模型按自己的默认来（有的模型不让关）。');

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
    // 新旧两种写法发错了都会 400，认不出是哪一代就不发
    return const ThinkingCaps.unverified('认不出这是哪一代 Claude，新旧两种思考写法不知道该用哪种，暂时不能在这里调。$_noParams');
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
  return _unverifiedModel;
}

ThinkingCaps _geminiCaps(String id) {
  if (id.contains('gemini-2.5') && !id.contains('pro')) {
    return const ThinkingCaps(options: _graded, offIsDefault: false, wire: ThinkingWire.effortWithNone, note: '选“关”会明确关掉思考。');
  }
  return const ThinkingCaps(options: _graded, offIsDefault: true, wire: ThinkingWire.effort, note: '这个模型关不掉思考；“默认”＝用它自己的强度。');
}

const _qwenCaps = ThinkingCaps(options: ['off', 'on'], offIsDefault: false, wire: ThinkingWire.enableThinking, note: '千问的思考只能开或关，不分档位。');

/// 模型名看着是不是 OpenAI 自家的（`gpt-…`、`o3…`、`chatgpt-…`）。只用来在自己填的地址上认模型。
bool _looksOpenAi(String id) => RegExp(r'^(gpt-|chatgpt-|o\d)').hasMatch(id);

/// 自己填的地址（中转站）：只能靠模型名认。认得出是核对过的那几家的模型，就按那家官方文档的写法；认不出就是没核对。
/// 中转站常见的 `厂商/模型` 写法只看最后一段。
ThinkingCaps _relayChatCaps(String modelId) {
  final id = modelId.split('/').last;
  if (id.startsWith('deepseek-')) {
    // 不是官方地址，客户端不会替我们发 disabled：这里照官方文档把开关和强度都明说
    return const ThinkingCaps(options: ['off', 'low', 'high', 'max'], offIsDefault: false, wire: ThinkingWire.thinkingTypeWithEffort, note: 'DeepSeek 只分低、高、最高三档（它把“中”当“高”）。');
  }
  if (id.startsWith('glm-')) return _zhipuCaps(id);
  if (id.startsWith('kimi-')) return _kimiCaps(id);
  if (id.startsWith('qwen')) return _qwenCaps;
  if (id.startsWith('gemini-')) return _geminiCaps(id);
  if (_looksOpenAi(id)) return _openAiEffort;
  return _unverifiedRelay;
}

/// 假设模型已经标记“可思考”，它在这个渠道上能怎么调。没核对过的返回 [ThinkingCaps.unverified]。
///
/// 怎么认：
/// - Anthropic 协议：看模型名认得出是哪一代 Claude（官方地址和中转站一样）。
/// - OpenAI Responses 协议：OpenAI 官方地址；或者自己填的地址上、模型名看着是 OpenAI 的。
/// - OpenAI Chat 协议：先按地址认是哪家。是核对过的那几家就按它的规则；是没核对过的服务商、或者本机 / 局域网地址，
///   就是没核对；哪家都不是（自己填的中转站）再按模型名认。
ThinkingCaps thinkingCaps(ChatProtocol protocol, String baseUrl, String modelId) {
  final id = modelId.trim().toLowerCase();
  final preset = presetForBaseUrl(baseUrl);
  switch (protocol) {
    case ChatProtocol.anthropic:
      return _claudeCaps(id);
    case ChatProtocol.openaiResponses:
      const caps = ThinkingCaps(options: _graded, offIsDefault: true, wire: ThinkingWire.effort, note: '“默认”＝不发思考参数，模型按自己的默认来。');
      if (preset?.id == 'openai') return caps;
      if (preset != null) return _unverifiedProvider(preset.name);
      if (isLocalBaseUrl(baseUrl)) return _unverifiedLocal;
      return _looksOpenAi(id.split('/').last) ? caps : _unverifiedRelay;
    case ChatProtocol.openaiChat:
      break;
  }
  switch (preset?.id) {
    case 'deepseek':
      return const ThinkingCaps(options: ['off', 'low', 'high', 'max'], offIsDefault: false, wire: ThinkingWire.effort, note: 'DeepSeek 只分低、高、最高三档（它把“中”当“高”）。');
    case 'openai':
      return _openAiEffort;
    case 'openrouter':
      return const ThinkingCaps(options: _graded, offIsDefault: true, wire: ThinkingWire.effort, note: '“默认”＝不发思考参数，模型按自己的默认来。');
    case 'gemini':
      return _geminiCaps(id);
    case 'bailian':
      // 百炼上不是千问的模型：官方只说“控制参数因模型而异”，没逐个核对
      return id.startsWith('qwen') ? _qwenCaps : _unverifiedModel;
    case 'siliconflow':
      return const ThinkingCaps(options: ['off', 'on'], offIsDefault: false, wire: ThinkingWire.enableThinking, note: '硅基流动的思考只能开或关，不分档位。');
    case 'zhipu':
      return _zhipuCaps(id);
    case 'moonshot':
      return _kimiCaps(id);
  }
  if (preset != null) return _unverifiedProvider(preset.name);
  if (isLocalBaseUrl(baseUrl)) return _unverifiedLocal;
  return _relayChatCaps(id);
}

/// 这个模型在这个渠道上的思考参数核对过没有。没核对过：界面不给档位和开关，请求不带思考参数。
bool thinkingVerified(Channel channel, ModelSpec model) => thinkingCaps(channel.protocol, channel.baseUrl, model.id).verified;

/// 界面上该不该写“可思考”：标了，而且核对过（旧存盘里没核对过的服务商也可能标着）。
bool showsThinking(ChatProtocol protocol, String baseUrl, ModelSpec model) => model.thinking && thinkingCaps(protocol, baseUrl, model.id).verified;

/// 这个模型现在真实能选的档位（没标记“可思考”就只有 `off`）。模型设置里去掉的档位不出现。
List<String> thinkingOptions(Channel channel, ModelSpec model) {
  if (!model.thinking) return const ['off'];
  final caps = thinkingCaps(channel.protocol, channel.baseUrl, model.id);
  if (!caps.verified) return const ['off'];
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
  if (!marked || !caps.verified) return none;
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
