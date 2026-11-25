// 思考档位：每家接口在每个档位下真实发出去的请求体（规则见 docs/api-notes.md「2026-11-25 思考档位」）。
// 不联网：请求被假的 http 客户端截下来，只看请求体。
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lopicode/agent/model_config.dart';
import 'package:lopicode/agent/protocols.dart';
import 'package:lopicode/agent/provider_presets.dart';
import 'package:lopicode/agent/thinking_support.dart';
import 'package:lopicode/core/safe_file.dart';
import 'package:lopicode/core/stores.dart';
import 'package:path/path.dart' as p;

final _urls = {
  'deepseek': 'https://api.deepseek.com',
  'openai': 'https://api.openai.com/v1',
  'gemini': 'https://generativelanguage.googleapis.com/v1beta/openai',
  'zhipu': 'https://open.bigmodel.cn/api/paas/v4',
  'bailian': 'https://dashscope.aliyuncs.com/compatible-mode/v1',
  'moonshot': 'https://api.moonshot.cn/v1',
  'siliconflow': 'https://api.siliconflow.cn/v1',
  'openrouter': 'https://openrouter.ai/api/v1',
  'relay': 'https://api.example.com/v1',
  'anthropic': 'https://api.anthropic.com/v1',
  'local': 'http://192.168.1.20:1234/v1',
  // 没核对过思考参数的服务商：地址直接取预设里的
  for (final id in _unverifiedPresets) id: _presetUrl(id),
};

/// 思考参数没对着官方文档核对过的服务商（预设 id）。
const _unverifiedPresets = ['volcengine', 'minimax', 'xai', 'groq', 'hunyuan', 'qianfan', 'stepfun', 'cerebras', 'ollama'];
String _presetUrl(String id) => presetById(id)!.baseUrl;

/// 按“渠道 + 模型 + 档位”造客户端、发一次请求，返回发出去的请求体。
Future<Map<String, dynamic>> sent(
  String provider,
  String modelId,
  String level, {
  ChatProtocol protocol = ChatProtocol.openaiChat,
  bool marked = true,
  int? maxOutput,
  List<Map<String, dynamic>>? messages,
}) async {
  Map<String, dynamic>? body;
  final client = MockClient.streaming((req, bodyStream) async {
    body = jsonDecode(await utf8.decoder.bind(bodyStream).join()) as Map<String, dynamic>;
    return http.StreamedResponse(Stream.value(utf8.encode('data: [DONE]\n\n')), 200, headers: {'content-type': 'text/event-stream'});
  });
  final ch = Channel(
    id: 'c1',
    name: provider,
    protocol: protocol,
    baseUrl: _urls[provider]!,
    models: [ModelSpec(id: modelId, thinking: marked, maxOutput: maxOutput ?? ModelSpec.defaultMaxOutput)],
  );
  // 和应用里一样：档位先按这个模型真实支持的收口
  final r = resolveSelection([ch], ModelSelection('c1', modelId, level))!;
  try {
    await buildChatClient(r, 'sk-test', httpClient: client)
        .streamChat(
          messages:
              messages ??
              [
                {'role': 'user', 'content': '你好'},
              ],
          tools: const [],
        )
        .toList();
  } on Object {
    // 假回复很简陋，解析报不报错都无所谓，这里只看发出去的请求
  }
  expect(body, isNotNull, reason: '请求没有发出去');
  return body!;
}

/// 请求体里跟思考有关的字段。
Map<String, dynamic> thinkingOf(Map<String, dynamic> body) => {
  for (final k in const ['reasoning_effort', 'thinking', 'enable_thinking', 'output_config', 'reasoning'])
    if (body.containsKey(k)) k: body[k],
};

void main() {
  group('OpenAI Chat 协议：各家各档位发什么', () {
    test('没核对过的服务商：标了“可思考”、存着哪一档都一样，一个思考参数都不发（通用的 reasoning_effort 也不发）', () async {
      for (final provider in [..._unverifiedPresets, 'local', 'relay']) {
        for (final l in ['off', 'on', 'low', 'medium', 'high', 'max']) {
          expect(thinkingOf(await sent(provider, 'some-model', l)), isEmpty, reason: '$provider $l');
        }
        expect(thinkingCaps(ChatProtocol.openaiChat, _urls[provider]!, 'some-model').verified, isFalse, reason: provider);
      }
      // 不经过档位收口、直接拿着“高”去造客户端（比如旧代码路径）：照样不发
      for (final provider in ['volcengine', 'relay']) {
        Map<String, dynamic>? body;
        final ch = Channel(
          id: 'c',
          name: provider,
          protocol: ChatProtocol.openaiChat,
          baseUrl: _urls[provider]!,
          models: [ModelSpec(id: 'some-model', thinking: true)],
        );
        final client = MockClient.streaming((req, bodyStream) async {
          body = jsonDecode(await utf8.decoder.bind(bodyStream).join()) as Map<String, dynamic>;
          return http.StreamedResponse(Stream.value(utf8.encode('data: [DONE]\n\n')), 200, headers: {'content-type': 'text/event-stream'});
        });
        try {
          await buildChatClient(ResolvedModel(ch, ch.models.first, 'high'), 'sk-test', httpClient: client)
              .streamChat(
                messages: [
                  {'role': 'user', 'content': '你好'},
                ],
                tools: const [],
              )
              .toList();
        } on Object {
          // 假回复很简陋，只看发出去的请求
        }
        expect(thinkingOf(body!), isEmpty, reason: provider);
      }
    });

    test('没核对过的服务商上的知名模型也不发：地址是那家的，参数就得按那家的文档，不能按模型名猜', () async {
      expect(thinkingOf(await sent('volcengine', 'deepseek-v4-pro', 'high')), isEmpty);
      expect(thinkingOf(await sent('groq', 'gpt-oss', 'high')), isEmpty);
      expect(thinkingOf(await sent('local', 'deepseek-v4-pro', 'high')), isEmpty, reason: '本机 / 局域网服务不是中转站');
      expect(thinkingOf(await sent('ollama', 'qwen3', 'on')), isEmpty);
    });

    test('自己填的中转站：模型名认得出是核对过的那几家，就按那家官方文档的写法发', () async {
      // DeepSeek：不是官方地址，开关和强度都明说
      expect(thinkingOf(await sent('relay', 'deepseek-v4-pro', 'off')), {
        'thinking': {'type': 'disabled'},
      });
      expect(thinkingOf(await sent('relay', 'deepseek-v4-pro', 'medium')), {
        'thinking': {'type': 'enabled'},
        'reasoning_effort': 'high',
      });
      expect(thinkingOf(await sent('relay', 'deepseek/deepseek-v4-pro', 'max')), {
        'thinking': {'type': 'enabled'},
        'reasoning_effort': 'max',
      }, reason: '“厂商/模型”的写法看最后一段');
      expect(thinkingOf(await sent('relay', 'deepseek-v4-pro', 'high', marked: false)), isEmpty, reason: '中转站上没标记就什么都不发（只有官方地址才替她关）');
      // OpenAI
      expect(thinkingOf(await sent('relay', 'gpt-6', 'off')), isEmpty);
      expect(thinkingOf(await sent('relay', 'openai/o5-mini', 'low')), {'reasoning_effort': 'low'});
      // 智谱 / Kimi / 千问 / Gemini
      expect(thinkingOf(await sent('relay', 'glm-4.6', 'on')), {
        'thinking': {'type': 'enabled'},
      });
      expect(thinkingOf(await sent('relay', 'kimi-k3', 'max')), {'reasoning_effort': 'max'});
      expect(thinkingOf(await sent('relay', 'kimi-k2.7-code', 'high')), isEmpty);
      expect(thinkingOf(await sent('relay', 'qwen-plus', 'on')), {'enable_thinking': true});
      expect(thinkingOf(await sent('relay', 'gemini-2.5-flash', 'off')), {'reasoning_effort': 'none'});
      // 认不出的：不发
      for (final id in ['claude-opus-4-8', 'moonshot-v1-8k', 'kimi-latest', 'my-model', 'doubao-pro', 'grok-5', 'ogpt-1']) {
        expect(thinkingOf(await sent('relay', id, 'high')), isEmpty, reason: id);
      }
    });

    test('没标记“可思考”的模型：不管存着什么档位，一个思考参数都不发', () async {
      for (final e in {
        'relay': 'x',
        'zhipu': 'glm-5.2',
        'bailian': 'qwen-max',
        'siliconflow': 'a/b',
        'moonshot': 'kimi-k2.6',
        'gemini': 'gemini-2.5-flash',
        'openai': 'gpt-x',
        'openrouter': 'a/b',
      }.entries) {
        expect(thinkingOf(await sent(e.key, e.value, 'high', marked: false)), isEmpty, reason: e.key);
      }
      // DeepSeek 官方地址是原有的例外：它默认开着思考，没选档位就明说关掉（否则白花钱）
      expect(thinkingOf(await sent('deepseek', 'deepseek-v4-pro', 'high', marked: false)), {
        'thinking': {'type': 'disabled'},
      });
    });

    test('OpenAI 官方 / OpenRouter：reasoning_effort 低中高，“默认”不发', () async {
      for (final provider in ['openai', 'openrouter']) {
        expect(thinkingOf(await sent(provider, 'm', 'off')), isEmpty);
        expect(thinkingOf(await sent(provider, 'm', 'medium')), {'reasoning_effort': 'medium'});
      }
    });

    test('DeepSeek 官方：低 / 高 / 最高；“中”当“高”；关＝thinking disabled', () async {
      expect(thinkingOf(await sent('deepseek', 'deepseek-v4-pro', 'off')), {
        'thinking': {'type': 'disabled'},
      });
      expect(thinkingOf(await sent('deepseek', 'deepseek-v4-pro', 'low')), {'reasoning_effort': 'low'});
      expect(thinkingOf(await sent('deepseek', 'deepseek-v4-pro', 'medium')), {'reasoning_effort': 'high'}, reason: '旧存盘里的“中”：官方把它当“高”，我们直接发“高”');
      expect(thinkingOf(await sent('deepseek', 'deepseek-v4-pro', 'high')), {'reasoning_effort': 'high'});
      expect(thinkingOf(await sent('deepseek', 'deepseek-v4-pro', 'max')), {'reasoning_effort': 'max'});
    });

    test('Gemini：2.5（非 Pro）关＝"none"；2.5 Pro / 3 / 4 关不掉，“默认”不发', () async {
      expect(thinkingOf(await sent('gemini', 'gemini-2.5-flash', 'off')), {'reasoning_effort': 'none'});
      expect(thinkingOf(await sent('gemini', 'gemini-2.5-flash', 'low')), {'reasoning_effort': 'low'});
      expect(thinkingOf(await sent('gemini', 'gemini-2.5-pro', 'off')), isEmpty);
      expect(thinkingOf(await sent('gemini', 'gemini-3-pro', 'off')), isEmpty);
      expect(thinkingOf(await sent('gemini', 'gemini-3-pro', 'high')), {'reasoning_effort': 'high'});
      expect(thinkingOf(await sent('gemini', 'gemini-4-neon', 'max')), {'reasoning_effort': 'high'}, reason: '没给“最高”这一档');
    });

    test('智谱：5.3 只收低 / 高 / 最高且不发 disabled；5.2 高 / 最高；其余只有开关', () async {
      expect(thinkingOf(await sent('zhipu', 'glm-5.3', 'off')), isEmpty, reason: '5.3 传 disabled 会报错');
      expect(thinkingOf(await sent('zhipu', 'glm-5.3-flash', 'low')), {'reasoning_effort': 'low'});
      expect(thinkingOf(await sent('zhipu', 'glm-5.3', 'medium')), {'reasoning_effort': 'high'}, reason: '5.3 传 medium 会报错');
      expect(thinkingOf(await sent('zhipu', 'glm-5.3', 'max')), {'reasoning_effort': 'max'});

      expect(thinkingOf(await sent('zhipu', 'glm-5.2', 'off')), {
        'thinking': {'type': 'disabled'},
      });
      expect(thinkingOf(await sent('zhipu', 'glm-5.2', 'low')), {
        'thinking': {'type': 'enabled'},
        'reasoning_effort': 'high',
      });
      expect(thinkingOf(await sent('zhipu', 'glm-5.2', 'max')), {
        'thinking': {'type': 'enabled'},
        'reasoning_effort': 'max',
      });

      expect(thinkingOf(await sent('zhipu', 'glm-4.6', 'off')), {
        'thinking': {'type': 'disabled'},
      });
      for (final l in ['on', 'low', 'high']) {
        expect(thinkingOf(await sent('zhipu', 'glm-4.6', l)), {
          'thinking': {'type': 'enabled'},
        }, reason: '只有开关，不发 reasoning_effort（$l）');
      }
    });

    test('Kimi：K3 低 / 高 / 最高、不发 thinking；K2.7 Code 什么都不发；K2.6 只有关要发', () async {
      expect(thinkingOf(await sent('moonshot', 'kimi-k3', 'off')), isEmpty);
      expect(thinkingOf(await sent('moonshot', 'kimi-k3.1-pro', 'low')), {'reasoning_effort': 'low'});
      expect(thinkingOf(await sent('moonshot', 'kimi-k3', 'medium')), {'reasoning_effort': 'high'});
      expect(thinkingOf(await sent('moonshot', 'kimi-k3', 'max')), {'reasoning_effort': 'max'});
      for (final l in ['off', 'low', 'high', 'on']) {
        expect(thinkingOf(await sent('moonshot', 'kimi-k2.7-code', l)), isEmpty, reason: l);
      }
      expect(thinkingOf(await sent('moonshot', 'kimi-k2.6', 'off')), {
        'thinking': {'type': 'disabled'},
      });
      expect(thinkingOf(await sent('moonshot', 'kimi-k2.6', 'on')), isEmpty, reason: '默认就开着');
      expect(thinkingOf(await sent('moonshot', 'kimi-k2.6', 'high')), isEmpty);
      // 没核对到的 Kimi 模型：不发
      expect(thinkingOf(await sent('moonshot', 'moonshot-v1-8k', 'low')), isEmpty);
    });

    test('Kimi：思考内容要原样带回（官方地址）；别家不带', () async {
      final history = [
        {'role': 'user', 'content': '看看'},
        {
          'role': 'assistant',
          'content': '',
          '_reasoning': '先列文件。',
          'tool_calls': [
            {
              'id': 'c1',
              'type': 'function',
              'function': {'name': 'list_files', 'arguments': '{}'},
            },
          ],
        },
        {'role': 'tool', 'tool_call_id': 'c1', 'content': 'a.txt'},
      ];
      Map<String, dynamic> assistantOf(Map<String, dynamic> body) => (body['messages'] as List).cast<Map<String, dynamic>>().firstWhere((m) => m['role'] == 'assistant');
      final kimi = assistantOf(await sent('moonshot', 'kimi-k3', 'high', messages: history));
      expect(kimi['reasoning_content'], '先列文件。');
      expect(kimi.keys.where((k) => k.startsWith('_')), isEmpty, reason: '内部字段不外发');
      final other = assistantOf(await sent('relay', 'some-model', 'high', messages: history));
      expect(other.containsKey('reasoning_content'), isFalse);
      expect(other.keys.where((k) => k.startsWith('_')), isEmpty);
    });

    test('百炼千问 / 硅基流动：enable_thinking 开关，不发 reasoning_effort', () async {
      for (final e in {'bailian': 'qwen-plus', 'siliconflow': 'Qwen/QwQ-32B'}.entries) {
        expect(thinkingOf(await sent(e.key, e.value, 'off')), {'enable_thinking': false}, reason: e.key);
        for (final l in ['on', 'low', 'medium', 'high', 'max']) {
          expect(thinkingOf(await sent(e.key, e.value, l)), {'enable_thinking': true}, reason: '${e.key} $l');
        }
      }
      // 百炼上不是千问的模型：参数因模型而异、没逐个核对 → 不发
      expect(thinkingOf(await sent('bailian', 'deepseek-v4-pro', 'off')), isEmpty);
      expect(thinkingOf(await sent('bailian', 'deepseek-v4-pro', 'high')), isEmpty);
      // Kimi 地址上没核对到的模型：同样不发
      expect(thinkingOf(await sent('moonshot', 'moonshot-v1-8k', 'high')), isEmpty);
    });
  });

  group('OpenAI Responses 协议', () {
    test('reasoning.effort 低中高；“默认”不发；没标记不发', () async {
      Future<Map<String, dynamic>> r(String l, {bool marked = true}) => sent('openai', 'gpt-x', l, protocol: ChatProtocol.openaiResponses, marked: marked);
      expect(thinkingOf(await r('off')), isEmpty);
      for (final l in ['low', 'medium', 'high']) {
        expect(thinkingOf(await r(l)), {
          'reasoning': {'effort': l, 'summary': 'auto'},
        });
      }
      expect(thinkingOf(await r('high', marked: false)), isEmpty);
    });

    test('只有 OpenAI 官方地址、或者中转站上看着是 OpenAI 的模型才发；别的不发', () async {
      Future<Map<String, dynamic>> r(String provider, String id) => sent(provider, id, 'high', protocol: ChatProtocol.openaiResponses);
      expect(thinkingOf(await r('relay', 'gpt-6')), {
        'reasoning': {'effort': 'high', 'summary': 'auto'},
      });
      expect(thinkingOf(await r('relay', 'my-model')), isEmpty);
      expect(thinkingOf(await r('xai', 'gpt-6')), isEmpty);
      expect(thinkingOf(await r('local', 'gpt-6')), isEmpty);
    });
  });

  group('Anthropic Messages 协议：按模型 ID 分新旧两种写法', () {
    Future<Map<String, dynamic>> a(String model, String l, {bool marked = true, int? maxOutput}) => sent('anthropic', model, l, protocol: ChatProtocol.anthropic, marked: marked, maxOutput: maxOutput);
    const adaptive = {'type': 'adaptive', 'display': 'summarized'};

    test('认版本号', () {
      expect(parseClaudeId('claude-opus-4-7'), (line: 'opus', major: 4, minor: 7));
      expect(parseClaudeId('claude-sonnet-4-5-20250929'), (line: 'sonnet', major: 4, minor: 5));
      expect(parseClaudeId('claude-sonnet-4-20250514'), (line: 'sonnet', major: 4, minor: 0), reason: '日期不是小版本号');
      expect(parseClaudeId('claude-opus-4-1-20250805'), (line: 'opus', major: 4, minor: 1));
      expect(parseClaudeId('claude-3-7-sonnet-20250219'), (line: 'sonnet', major: 3, minor: 7));
      expect(parseClaudeId('claude-fable-5-2'), (line: 'fable', major: 5, minor: 2));
      expect(parseClaudeId('anthropic/claude-haiku-5.5'), (line: 'haiku', major: 5, minor: 5));
      expect(parseClaudeId('claude-x'), isNull);
      expect(parseClaudeId('gpt-5'), isNull);
    });

    test('4.5 及更早：老写法 budget_tokens（最少 1024、比 max_tokens 小）；关＝不发', () async {
      expect(thinkingOf(await a('claude-sonnet-4-5-20250929', 'off')), isEmpty);
      expect(thinkingOf(await a('claude-sonnet-4-5-20250929', 'low')), {
        'thinking': {'type': 'enabled', 'budget_tokens': 4096},
      });
      expect(thinkingOf(await a('claude-opus-4-1', 'high')), {
        'thinking': {'type': 'enabled', 'budget_tokens': 30976},
      }, reason: '默认最大输出 32000：预算压到 max_tokens - 1024');
      expect(thinkingOf(await a('claude-haiku-4-5', 'high', maxOutput: 4096)), {
        'thinking': {'type': 'enabled', 'budget_tokens': 3072},
      });
      expect(thinkingOf(await a('claude-haiku-4-5', 'high', maxOutput: 2048)), isEmpty, reason: '输出上限太小，放不下最少 1024 的预算');
    });

    test('认不出是哪一代的：新旧写法不知道该用哪种，什么都不发', () async {
      for (final l in ['off', 'low', 'medium', 'high']) {
        expect(thinkingOf(await a('claude-x', l)), isEmpty, reason: l);
        expect(thinkingOf(await a('my-proxy-model', l)), isEmpty, reason: l);
      }
      expect(thinkingCaps(ChatProtocol.anthropic, _urls['anthropic']!, 'claude-x').verified, isFalse);
    });

    test('中转站上的 Claude（Anthropic 协议）：认得出版本就和官方地址一样发', () async {
      expect(thinkingOf(await sent('relay', 'claude-sonnet-4-5-20250929', 'low', protocol: ChatProtocol.anthropic)), {
        'thinking': {'type': 'enabled', 'budget_tokens': 4096},
      });
      expect(thinkingOf(await sent('relay', 'claude-opus-4-8', 'high', protocol: ChatProtocol.anthropic)), {
        'thinking': {'type': 'adaptive', 'display': 'summarized'},
        'output_config': {'effort': 'high'},
      });
    });

    test('4.6 / Opus 4.7 / 4.8：新写法 adaptive + output_config.effort；关＝不发（默认就不思考）', () async {
      for (final m in ['claude-opus-4-6', 'claude-sonnet-4-6', 'claude-opus-4-7', 'claude-opus-4-8']) {
        expect(thinkingOf(await a(m, 'off')), isEmpty, reason: m);
        for (final l in ['low', 'medium', 'high']) {
          final t = thinkingOf(await a(m, l));
          expect(t, {
            'thinking': adaptive,
            'output_config': {'effort': l},
          }, reason: '$m $l');
          expect(jsonEncode(t), isNot(contains('budget_tokens')), reason: '4.7 起发 budget_tokens 会 400');
        }
      }
    });

    test('Opus 5 / Sonnet 5 / Haiku 5.5：默认开着，关＝明说 disabled', () async {
      for (final m in ['claude-opus-5', 'claude-sonnet-5', 'claude-haiku-5-5']) {
        expect(thinkingOf(await a(m, 'off')), {
          'thinking': {'type': 'disabled'},
        }, reason: m);
        expect(thinkingOf(await a(m, 'medium')), {
          'thinking': adaptive,
          'output_config': {'effort': 'medium'},
        }, reason: m);
      }
    });

    test('Fable / Mythos / Opus 5.5 / Sonnet 5.5 / 没见过的新版本：关不掉，“默认”不发 disabled，只要思考摘要', () async {
      for (final m in ['claude-fable-5-2', 'claude-mythos-5', 'claude-opus-5-5', 'claude-sonnet-5-5', 'claude-opus-6']) {
        expect(thinkingOf(await a(m, 'off')), {'thinking': adaptive}, reason: m);
        expect(thinkingOf(await a(m, 'high')), {
          'thinking': adaptive,
          'output_config': {'effort': 'high'},
        }, reason: m);
      }
    });

    test('没标记“可思考”：不管哪一代都不发思考参数', () async {
      for (final m in ['claude-opus-5-5', 'claude-sonnet-5', 'claude-sonnet-4-5', 'claude-x']) {
        expect(thinkingOf(await a(m, 'high', marked: false)), isEmpty, reason: m);
      }
    });

    test('一直在思考的模型：历史里的思考块原样带回（哪怕选的是“默认”）；真关了就不带', () async {
      final history = [
        {'role': 'user', 'content': '看看'},
        {
          'role': 'assistant',
          'content': '好',
          '_raw': {
            'protocol': 'anthropic',
            'content': [
              {'type': 'thinking', 'thinking': '先列文件。', 'signature': 'sig-1'},
              {'type': 'text', 'text': '好'},
            ],
          },
        },
        {'role': 'user', 'content': '继续'},
      ];
      final kept = await sent('anthropic', 'claude-opus-5-5', 'off', protocol: ChatProtocol.anthropic, messages: history);
      expect(jsonEncode(kept['messages']), contains('sig-1'));
      final dropped = await sent('anthropic', 'claude-sonnet-5', 'off', protocol: ChatProtocol.anthropic, messages: history);
      expect(jsonEncode(dropped['messages']), isNot(contains('sig-1')));
    });
  });

  group('档位收口与显示', () {
    Channel ch(String provider, ModelSpec m, {ChatProtocol protocol = ChatProtocol.openaiChat}) => Channel(id: 'c', name: provider, protocol: protocol, baseUrl: _urls[provider]!, models: [m]);

    test('每家真实能选的档位', () {
      List<String> opts(String provider, String id, {ChatProtocol protocol = ChatProtocol.openaiChat}) =>
          thinkingOptions(ch(provider, ModelSpec(id: id, thinking: true), protocol: protocol), ModelSpec(id: id, thinking: true));
      expect(opts('relay', 'x'), ['off'], reason: '没核对过：一个能点的档位都不给');
      expect(opts('volcengine', 'doubao-pro'), ['off']);
      expect(opts('bailian', 'deepseek-v4-pro'), ['off']);
      expect(opts('relay', 'gpt-6'), ['off', 'low', 'medium', 'high']);
      expect(opts('relay', 'deepseek-v4-pro'), ['off', 'low', 'high', 'max']);
      expect(opts('openrouter', 'a/b'), ['off', 'low', 'medium', 'high']);
      expect(opts('deepseek', 'deepseek-flash'), ['off', 'low', 'high', 'max']);
      expect(opts('zhipu', 'glm-5.3'), ['off', 'low', 'high', 'max']);
      expect(opts('zhipu', 'glm-5.2'), ['off', 'high', 'max']);
      expect(opts('zhipu', 'glm-4.5'), ['off', 'on']);
      expect(opts('moonshot', 'kimi-k2.7-code'), ['off'], reason: '调不了：一个能点的档位都不给');
      expect(opts('moonshot', 'kimi-k2.6'), ['off', 'on']);
      expect(opts('bailian', 'qwen-max'), ['off', 'on']);
      expect(opts('siliconflow', 'x/y'), ['off', 'on']);
      expect(opts('anthropic', 'claude-opus-5-5', protocol: ChatProtocol.anthropic), ['off', 'low', 'medium', 'high']);
    });

    test('没标记＝只有 off；模型设置里去掉的档位不出现', () {
      final plain = ModelSpec(id: 'x');
      expect(thinkingOptions(ch('relay', plain), plain), ['off']);
      final some = ModelSpec(id: 'x', thinking: true, levels: const ['high']);
      expect(thinkingOptions(ch('openrouter', some), some), ['off', 'high']);
      final ds = ModelSpec(id: 'deepseek-v4-pro', thinking: true, levels: const ['low']);
      expect(thinkingOptions(ch('deepseek', ds), ds), ['off', 'low', 'max'], reason: '“最高”不在可勾掉的三档里，一直在');
    });

    test('“关”还是“默认”：真能关的写“关”，只是不发参数的写“默认”', () {
      String off(String provider, String id, {ChatProtocol protocol = ChatProtocol.openaiChat}) => thinkingOptionLabel(thinkingCaps(protocol, _urls[provider]!, id), 'off');
      expect(off('deepseek', 'deepseek-v4-pro'), '关');
      expect(off('gemini', 'gemini-2.5-flash'), '关');
      expect(off('gemini', 'gemini-3-pro'), '默认');
      expect(off('relay', 'x'), '默认');
      expect(off('zhipu', 'glm-5.3'), '默认');
      expect(off('zhipu', 'glm-4.6'), '关');
      expect(off('anthropic', 'claude-opus-5-5', protocol: ChatProtocol.anthropic), '默认');
      expect(off('anthropic', 'claude-sonnet-5', protocol: ChatProtocol.anthropic), '关');
      expect(off('relay', 'deepseek-v4-pro'), '关');
      expect(thinkingLabel('max'), '最高');
      expect(thinkingLabel('on'), '开');
    });

    test('收口：没有这一档就挑最近的，先往高找', () {
      expect(normalizeThinkingLevel(['off', 'low', 'high', 'max'], 'medium'), 'high');
      expect(normalizeThinkingLevel(['off', 'low', 'medium', 'high'], 'max'), 'high');
      expect(normalizeThinkingLevel(['off', 'on'], 'low'), 'on');
      expect(normalizeThinkingLevel(['off', 'low', 'medium', 'high'], 'on'), 'medium');
      expect(normalizeThinkingLevel(['off', 'high', 'max'], 'on'), 'high');
      expect(normalizeThinkingLevel(['off'], 'high'), 'off');
      expect(normalizeThinkingLevel(['off', 'low'], '乱写的'), 'off');
    });
  });

  group('添加模型时自动标“可思考”：只标官方文档核对到的', () {
    bool known(String provider, String id, {ChatProtocol protocol = ChatProtocol.openaiChat, bool listed = false}) => knownThinkingModel(protocol, _urls[provider]!, id, listed: listed);

    test('标的', () {
      expect(known('deepseek', 'deepseek-v4-pro'), isTrue);
      expect(known('deepseek', 'deepseek-flash'), isTrue);
      expect(known('gemini', 'gemini-2.5-flash'), isTrue);
      expect(known('gemini', 'models/gemini-3-pro-preview'), isTrue);
      expect(known('zhipu', 'glm-5.3-flash'), isTrue);
      expect(known('zhipu', 'glm-4.6'), isTrue);
      expect(known('moonshot', 'kimi-k3.1-pro'), isTrue);
      expect(known('moonshot', 'kimi-k2.6'), isTrue);
      expect(known('openrouter', 'a/b', listed: true), isTrue);
      for (final m in ['claude-fable-5-2', 'claude-opus-5-5', 'claude-haiku-5-5', 'claude-opus-4-8', 'claude-sonnet-4-5-20250929', 'claude-opus-4-1', 'claude-sonnet-4-20250514', 'claude-haiku-4-5']) {
        expect(known('anthropic', m, protocol: ChatProtocol.anthropic), isTrue, reason: m);
      }
    });

    test('拿不准的不标', () {
      expect(known('openai', 'gpt-6'), isFalse, reason: '哪些 ID 是推理模型没核对到');
      expect(known('bailian', 'qwen-max'), isFalse);
      expect(known('siliconflow', 'deepseek-ai/DeepSeek-V4'), isFalse);
      expect(known('relay', 'deepseek-v4-pro'), isFalse, reason: '中转站：不知道它后面是什么');
      expect(known('zhipu', 'glm-4-flash'), isFalse);
      expect(known('gemini', 'gemini-2.0-flash'), isFalse);
      expect(known('moonshot', 'moonshot-v1-8k'), isFalse);
      expect(known('openrouter', 'a/b'), isFalse);
      expect(known('anthropic', 'claude-3-5-haiku-20241022', protocol: ChatProtocol.anthropic), isFalse);
      expect(known('anthropic', 'claude-x', protocol: ChatProtocol.anthropic), isFalse);
      expect(known('openai', 'gpt-6', protocol: ChatProtocol.openaiResponses), isFalse);
    });

    test('自动标上的，一定是核对过、有档位可调或有说明的（不会出现“自动标了却说没核对”）', () {
      for (final e in {
        'deepseek': ['deepseek-v4-pro'],
        'gemini': ['gemini-2.5-flash', 'gemini-3-pro-preview'],
        'zhipu': ['glm-5.3-flash', 'glm-4.6'],
        'moonshot': ['kimi-k3.1-pro', 'kimi-k2.7-code', 'kimi-k2.6'],
        'openrouter': ['a/b'],
      }.entries) {
        for (final id in e.value) {
          expect(known(e.key, id, listed: true), isTrue, reason: id);
          expect(thinkingCaps(ChatProtocol.openaiChat, _urls[e.key]!, id).verified, isTrue, reason: id);
        }
      }
      for (final provider in [..._unverifiedPresets, 'local', 'relay']) {
        expect(known(provider, 'deepseek-v4-pro', listed: true), isFalse, reason: provider);
      }
    });

    test('newModelSpec 照这个规则给 thinking', () {
      expect(newModelSpec(ChatProtocol.openaiChat, _urls['deepseek']!, 'deepseek-v4-pro').thinking, isTrue);
      expect(newModelSpec(ChatProtocol.openaiChat, _urls['relay']!, 'whatever', name: '名字').thinking, isFalse);
      expect(newModelSpec(ChatProtocol.openaiChat, _urls['openrouter']!, 'a/b', listedThinking: true).thinking, isTrue);
    });

    test('模型列表：只有 OpenRouter 的 reasoning 字段算数', () async {
      Future<List<RemoteModel>> list(String provider) => listRemoteModels(
        protocol: ChatProtocol.openaiChat,
        baseUrl: _urls[provider]!,
        apiKey: 'k',
        httpClient: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'data': [
                {
                  'id': 'a/think',
                  'reasoning': {
                    'supported_efforts': ['low', 'high'],
                  },
                },
                {'id': 'a/plain'},
                {'id': 'a/odd', 'reasoning': 'yes'},
              ],
            }),
            200,
            headers: {'content-type': 'application/json'},
          ),
        ),
      );
      expect({for (final m in await list('openrouter')) m.id: m.thinking}, {'a/think': true, 'a/plain': false, 'a/odd': false});
      expect((await list('relay')).every((m) => !m.thinking), isTrue, reason: '别家的同名字段不认');
    });
  });

  group('按模型记住档位', () {
    late Directory tmp;
    late SettingsStore settings;
    late ModelConfigStore models;
    late Channel relay;

    setUp(() async {
      tmp = Directory.systemTemp.createTempSync('lopi_think_');
      settings = SettingsStore(File(p.join(tmp.path, 'settings.json')));
      await settings.load();
      models = ModelConfigStore(settings, MemorySecretStore());
      await models.load();
      // 用一家核对过、低中高都有的（OpenRouter）；没核对过的服务商另有一条测试
      relay = await models.upsert(
        name: '渠道',
        protocol: ChatProtocol.openaiChat,
        baseUrl: _urls['openrouter']!,
        models: [
          ModelSpec(id: 'a', thinking: true),
          ModelSpec(id: 'b', thinking: true),
          ModelSpec(id: 'plain'),
        ],
      );
    });
    tearDown(() async {
      await pendingWrites();
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    test('切到别的模型再切回来，还是上次给它设的档位；重开应用也在', () async {
      await models.setThinkingLevel(relay.id, 'a', 'high');
      await models.setThinkingLevel(relay.id, 'b', 'low');
      expect(models.thinkingLevelOf(relay.id, 'a'), 'high');
      expect(models.thinkingLevelOf(relay.id, 'b'), 'low');
      expect(models.thinkingLevelOf(relay.id, 'plain'), isNull);
      // 选择里带的档位是旧的：以按模型记住的为准
      expect(models.resolve(ModelSelection(relay.id, 'a', 'low'))!.level, 'high');
      expect(models.resolve(ModelSelection(relay.id, 'b'))!.level, 'low');

      await pendingWrites();
      final again = SettingsStore(File(p.join(tmp.path, 'settings.json')));
      await again.load();
      final reopened = ModelConfigStore(again, MemorySecretStore());
      await reopened.load();
      expect(reopened.thinkingLevels, {'${relay.id}/a': 'high', '${relay.id}/b': 'low'});
      expect(reopened.resolve(ModelSelection(relay.id, 'a'))!.level, 'high');
    });

    test('旧存盘（没有这张表）：照常读，档位用选择里带的那个', () async {
      expect(settings.get<Object>(ModelConfigStore.kLevels), isNull);
      expect(models.thinkingLevels, isEmpty);
      expect(models.resolve(ModelSelection(relay.id, 'a', 'medium'))!.level, 'medium');
      expect(models.resolve(ModelSelection(relay.id, 'plain', 'medium'))!.level, 'off', reason: '没标记可思考');
      expect(models.firstAvailable!.level, 'off');
    });

    test('记住的档位这个模型已经不支持了（取消了“可思考”）：落回 off，不发参数', () async {
      await models.setThinkingLevel(relay.id, 'a', 'high');
      await models.upsert(
        id: relay.id,
        name: relay.name,
        protocol: relay.protocol,
        baseUrl: relay.baseUrl,
        models: [ModelSpec(id: 'a')],
      );
      expect(models.resolve(ModelSelection(relay.id, 'a', 'high'))!.level, 'off');
    });

    test('旧存盘：没核对过的服务商上已经标了“可思考”、记了档位——读进来不崩，档位落回 off，记的东西不丢', () async {
      final old = await models.upsert(
        name: '火山方舟',
        protocol: ChatProtocol.openaiChat,
        baseUrl: _urls['volcengine']!,
        models: [ModelSpec(id: 'doubao-pro', thinking: true)],
      );
      await models.setThinkingLevel(old.id, 'doubao-pro', 'high');
      await pendingWrites();
      final again = SettingsStore(File(p.join(tmp.path, 'settings.json')));
      await again.load();
      final reopened = ModelConfigStore(again, MemorySecretStore());
      await reopened.load();
      final m = reopened.channel(old.id)!.model('doubao-pro')!;
      expect(m.thinking, isTrue, reason: '存着的标记原样读回来');
      expect(reopened.thinkingLevelOf(old.id, 'doubao-pro'), 'high');
      final r = reopened.resolve(ModelSelection(old.id, 'doubao-pro', 'high'))!;
      expect(r.level, 'off');
      expect(thinkingOptions(r.channel, r.model), ['off']);
      expect(showsThinking(r.channel.protocol, r.channel.baseUrl, r.model), isFalse);
      expect(thinkingVerified(r.channel, r.model), isFalse);
    });

    test('删渠道时把它名下记住的档位一起清掉', () async {
      await models.setThinkingLevel(relay.id, 'a', 'high');
      await models.remove(relay.id);
      expect(models.thinkingLevels, isEmpty);
    });
  });
}
