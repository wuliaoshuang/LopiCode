// 服务商预设：添加渠道时点一下就填好名称、协议、接口地址，只需要再填 Key。
//
// 规矩（test/provider_presets_test.dart 守着）：
// - 这里的每一个接口地址都在 2026-11-23 对着该服务商官方文档页核对过，来源网址记在 [ProviderPreset.source]，
//   详细过程在 docs/provider-presets-research.md。没核对过官方文档的服务商不放进来，让用户走“自定义”。
// - 接口地址 = 官方完整地址里 `/chat/completions`（或 `/messages`）之前的全部，代码不会再自动补 `/v1`。
// - “核对过地址”不等于“实际连通过”：没有任何一家用真 Key 试过。
import 'package:lopicode/agent/model_config.dart';

class ProviderPreset {
  const ProviderPreset({
    required this.id,
    required this.name,
    required this.protocol,
    required this.baseUrl,
    required this.icon,
    required this.source,
    this.monoIcon = false,
    this.keyOptional = false,
    this.note,
    this.keyHint,
    this.extraHosts = const [],
  });

  /// 稳定的标识（存进渠道里，用来配图标）。
  final String id;

  /// 显示名，也是新渠道的默认名称。
  final String name;
  final ChatProtocol protocol;
  final String baseUrl;

  /// 图标文件名（assets/provider_icons/ 下，不含 .svg）。
  final String icon;

  /// 单色图标：要跟着深浅色换颜色。
  final bool monoIcon;

  /// 不填 Key 也能用（本机服务）。
  final bool keyOptional;

  /// 选了以后给用户看的一句提醒。
  final String? note;

  /// 去哪里拿 Key（一句话）。
  final String? keyHint;

  /// 核对接口地址时打开的官方文档页。
  final String source;

  /// 除了 [baseUrl] 的主机名以外，也算这家的主机名（按地址认图标用）。
  final List<String> extraHosts;

  String get host => Uri.parse(baseUrl).host.toLowerCase();
  String get iconAsset => 'assets/provider_icons/$icon.svg';
}

/// 核对日期（所有预设同一天）。
const String kPresetsVerifiedOn = '2026-11-23';

const List<ProviderPreset> kProviderPresets = [
  ProviderPreset(
    id: 'deepseek',
    name: 'DeepSeek',
    protocol: ChatProtocol.openaiChat,
    baseUrl: 'https://api.deepseek.com',
    icon: 'deepseek-color',
    keyHint: '在 DeepSeek 开放平台（platform.deepseek.com）创建',
    source: 'https://api-docs.deepseek.com/',
  ),
  ProviderPreset(
    id: 'openai',
    name: 'OpenAI',
    protocol: ChatProtocol.openaiChat,
    baseUrl: 'https://api.openai.com/v1',
    icon: 'openai',
    monoIcon: true,
    source: 'https://developers.openai.com/api/reference/resources/models/methods/list',
  ),
  ProviderPreset(
    id: 'anthropic',
    name: 'Anthropic',
    protocol: ChatProtocol.anthropic,
    baseUrl: 'https://api.anthropic.com/v1',
    icon: 'anthropic',
    monoIcon: true,
    source: 'https://platform.claude.com/docs/en/api/http/models/retrieve',
  ),
  ProviderPreset(
    id: 'gemini',
    name: 'Google Gemini',
    protocol: ChatProtocol.openaiChat,
    baseUrl: 'https://generativelanguage.googleapis.com/v1beta/openai',
    icon: 'gemini-color',
    keyHint: '在 Google AI Studio（aistudio.google.com/apikey）创建',
    source: 'https://aistudio.google.com/docs/openai?hl=pt',
  ),
  ProviderPreset(
    id: 'zhipu',
    name: '智谱 BigModel',
    protocol: ChatProtocol.openaiChat,
    baseUrl: 'https://open.bigmodel.cn/api/paas/v4',
    icon: 'zhipu-color',
    keyHint: '在 bigmodel.cn 的“API Keys”页面创建',
    source: 'https://docs.bigmodel.cn/cn/guide/develop/openai/introduction',
  ),
  ProviderPreset(
    id: 'bailian',
    name: '阿里云百炼',
    protocol: ChatProtocol.openaiChat,
    baseUrl: 'https://dashscope.aliyuncs.com/compatible-mode/v1',
    icon: 'bailian-color',
    note: '这是北京地域的地址。别的地域地址不同，Key 也不通用，要用就改接口地址。',
    source: 'https://help.aliyun.com/zh/model-studio/model-calling-in-sub-workspace',
  ),
  ProviderPreset(
    id: 'moonshot',
    name: '月之暗面 Kimi',
    protocol: ChatProtocol.openaiChat,
    baseUrl: 'https://api.moonshot.cn/v1',
    icon: 'moonshot',
    monoIcon: true,
    note: '这是国内站的地址。国际站的账号和 Key 不通用。',
    keyHint: '在 Kimi 开放平台控制台创建',
    source: 'https://platform.kimi.com/docs/api/overview',
    extraHosts: ['api.moonshot.ai'],
  ),
  ProviderPreset(
    id: 'volcengine',
    name: '火山方舟（豆包）',
    protocol: ChatProtocol.openaiChat,
    baseUrl: 'https://ark.cn-beijing.volces.com/api/v3',
    icon: 'volcengine-color',
    note: '模型一栏填 Model ID 或你在方舟里建的接入点 ID。',
    source: 'https://ark.volcengine.com/region:cn-beijing/docs/compatible-with-openai-sdk',
  ),
  ProviderPreset(
    id: 'siliconflow',
    name: '硅基流动',
    protocol: ChatProtocol.openaiChat,
    baseUrl: 'https://api.siliconflow.cn/v1',
    icon: 'siliconcloud-color',
    keyHint: '在 cloud.siliconflow.cn 的“API 密钥”页面创建',
    source: 'https://docs.siliconflow.cn/docs/usercases/use-siliconcloud-in-yan',
  ),
  ProviderPreset(
    id: 'openrouter',
    name: 'OpenRouter',
    protocol: ChatProtocol.openaiChat,
    baseUrl: 'https://openrouter.ai/api/v1',
    icon: 'openrouter-color',
    source: 'https://openrouter.ai/docs/api/api-reference/models/list-all-models-and-their-properties',
  ),
  ProviderPreset(
    id: 'minimax',
    name: 'MiniMax',
    protocol: ChatProtocol.openaiChat,
    baseUrl: 'https://api.minimax.cn/v1',
    icon: 'minimax-color',
    note: '官方文档今天写的是这个地址；网上也有文章写 api.minimaxi.com（国内）和 api.minimax.io（国际）。连不上时改接口地址试试。',
    source: 'https://platform.minimax.cn/docs/guides/quickstart-preparation',
    extraHosts: ['api.minimaxi.com', 'api.minimax.io'],
  ),
  ProviderPreset(
    id: 'xai',
    name: 'xAI',
    protocol: ChatProtocol.openaiChat,
    baseUrl: 'https://api.x.ai/v1',
    icon: 'xai',
    monoIcon: true,
    keyHint: '在 console.x.ai 创建',
    source: 'https://docs.x.ai/developers/model-capabilities/legacy/chat-completions.md',
  ),
  ProviderPreset(
    id: 'groq',
    name: 'Groq',
    protocol: ChatProtocol.openaiChat,
    baseUrl: 'https://api.groq.com/openai/v1',
    icon: 'groq',
    monoIcon: true,
    keyHint: '在 console.groq.com 创建',
    source: 'https://console.groq.com/docs/openai',
  ),
  ProviderPreset(
    id: 'hunyuan',
    name: '腾讯混元',
    protocol: ChatProtocol.openaiChat,
    baseUrl: 'https://tokenhub.tencentmaas.com/v1',
    icon: 'hunyuan-color',
    note: '这是腾讯云 TokenHub 的新地址，要用 TokenHub 控制台创建的 Key；老的混元 API Key 不通用。',
    source: 'https://cloud.tencent.com/document/product/1823/132252',
    extraHosts: ['api.hunyuan.cloud.tencent.com'],
  ),
  ProviderPreset(
    id: 'qianfan',
    name: '百度千帆',
    protocol: ChatProtocol.openaiChat,
    baseUrl: 'https://qianfan.baidubce.com/v2',
    icon: 'baiducloud-color',
    keyHint: '在百度千帆“系统管理”里创建 API Key',
    source: 'https://cloud.baidu.com/doc/qianfan/s/Hmh4suq26',
  ),
  ProviderPreset(
    id: 'stepfun',
    name: '阶跃星辰',
    protocol: ChatProtocol.openaiChat,
    baseUrl: 'https://api.stepfun.com/v1',
    icon: 'stepfun-color',
    source: 'https://platform.stepfun.com/docs/zh/guides/developer/openai',
  ),
  ProviderPreset(
    id: 'cerebras',
    name: 'Cerebras',
    protocol: ChatProtocol.openaiChat,
    baseUrl: 'https://api.cerebras.ai/v1',
    icon: 'cerebras-color',
    source: 'https://inference-docs.cerebras.ai/resources/openai',
  ),
  ProviderPreset(
    id: 'ollama',
    name: 'Ollama（本机）',
    protocol: ChatProtocol.openaiChat,
    baseUrl: 'http://localhost:11434/v1',
    icon: 'ollama',
    monoIcon: true,
    keyOptional: true,
    note: 'localhost 指的是这台手机自己。Ollama 装在电脑上的话，把地址里的 localhost 换成电脑的局域网 IP。不用填 Key。',
    source: 'https://docs.ollama.com/api/openai-compatibility',
  ),
];

ProviderPreset? presetById(String? id) {
  if (id == null || id.isEmpty) return null;
  for (final p in kProviderPresets) {
    if (p.id == id) return p;
  }
  return null;
}

String _hostOf(String baseUrl) {
  var text = baseUrl.trim();
  if (text.isEmpty) return '';
  if (!text.contains('://')) text = 'https://$text';
  return (Uri.tryParse(text)?.host ?? '').toLowerCase();
}

/// 按接口地址的主机名认出是哪家（认图标用）。本机地址只在端口是 11434 时才算 Ollama。
ProviderPreset? presetForBaseUrl(String baseUrl) {
  final host = _hostOf(baseUrl);
  if (host.isEmpty) return null;
  for (final p in kProviderPresets) {
    if (p.keyOptional) continue;
    if (p.host == host || p.extraHosts.contains(host)) return p;
  }
  var text = baseUrl.trim();
  if (!text.contains('://')) text = 'http://$text';
  if (Uri.tryParse(text)?.port == 11434) return presetById('ollama');
  return null;
}

/// 接口地址是不是本机 / 局域网（这种服务通常不需要 Key）。
bool isLocalBaseUrl(String baseUrl) {
  final host = _hostOf(baseUrl);
  if (host.isEmpty) return false;
  if (host == 'localhost' || host.endsWith('.local') || host == '::1') return true;
  final parts = host.split('.');
  if (parts.length != 4) return false;
  final n = [for (final s in parts) int.tryParse(s)];
  if (n.any((v) => v == null || v < 0 || v > 255)) return false;
  final a = n[0]!, b = n[1]!;
  return a == 127 || a == 10 || (a == 192 && b == 168) || (a == 172 && b >= 16 && b <= 31);
}
