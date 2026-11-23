import 'dart:convert';

import 'package:lopicode/agent/provider_presets.dart';
import 'package:lopicode/core/stores.dart';

/// 渠道用哪种接口协议。
enum ChatProtocol {
  openaiChat('openai-chat', 'OpenAI Chat Completions', 'https://api.openai.com/v1'),
  anthropic('anthropic', 'Anthropic Messages', 'https://api.anthropic.com/v1'),
  openaiResponses('openai-responses', 'OpenAI Responses', 'https://api.openai.com/v1');

  const ChatProtocol(this.id, this.label, this.exampleBaseUrl);
  final String id;
  final String label;
  final String exampleBaseUrl;

  static ChatProtocol byId(Object? id) => values.firstWhere((p) => p.id == id, orElse: () => openaiChat);
}

/// 思考档位。`off` 表示不思考。
const List<String> kThinkingLevels = ['low', 'medium', 'high'];

String thinkingLabel(String level) => switch (level) {
  'low' => '低',
  'medium' => '中',
  'high' => '高',
  _ => '关闭',
};

double? _price(Object? v) => v is num && v >= 0 && v.isFinite ? v.toDouble() : null;

/// 渠道里的一个模型。不可变：要改就 [copyWith] 出一份新的，再交给 [ModelConfigStore.upsert] 存。
class ModelSpec {
  ModelSpec({
    required this.id,
    String? name,
    this.contextLength = defaultContext,
    this.maxOutput = defaultMaxOutput,
    this.vision = false,
    this.thinking = false,
    List<String>? levels,
    this.priceHit,
    this.priceMiss,
    this.priceOutput,
  }) : name = (name == null || name.trim().isEmpty) ? id : name.trim(),
       levels = List.unmodifiable(levels ?? kThinkingLevels);

  static const int defaultContext = 256000;
  static const int defaultMaxOutput = 32000;
  static const int minContext = 32000;
  static const int maxContext = 1000000;

  /// 可以直接点选的上下文长度。
  static const List<int> contextChoices = [32000, 64000, 128000, 200000, 256000, 400000, 1000000];

  /// 发给接口的模型 ID。
  final String id;

  /// 显示名。
  final String name;
  final int contextLength;
  final int maxOutput;

  /// 输入类型：false＝只有文本，true＝文本和图片。
  final bool vision;

  /// 这个模型能不能“思考”，以及可选的档位。
  final bool thinking;
  final List<String> levels;

  /// 单价（元每百万 token）：输入命中缓存 / 输入未命中 / 输出。用户自己填，三个都填了才估算费用。
  final double? priceHit;
  final double? priceMiss;
  final double? priceOutput;

  static int clampContext(int v) => v.clamp(minContext, maxContext);

  /// 换掉几项，出一份新的。三个单价是“整组换”：传了 [prices] 就三个一起换（里面的 null 表示清空）。
  ModelSpec copyWith({String? name, int? contextLength, int? maxOutput, bool? vision, bool? thinking, List<String>? levels, ({double? hit, double? miss, double? output})? prices}) => ModelSpec(
    id: id,
    name: name ?? this.name,
    contextLength: contextLength ?? this.contextLength,
    maxOutput: maxOutput ?? this.maxOutput,
    vision: vision ?? this.vision,
    thinking: thinking ?? this.thinking,
    levels: levels ?? this.levels,
    priceHit: prices == null ? priceHit : prices.hit,
    priceMiss: prices == null ? priceMiss : prices.miss,
    priceOutput: prices == null ? priceOutput : prices.output,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'context': contextLength,
    'maxOutput': maxOutput,
    'vision': vision,
    'thinking': thinking,
    'levels': levels,
    'priceHit': ?priceHit,
    'priceMiss': ?priceMiss,
    'priceOut': ?priceOutput,
  };

  static ModelSpec? fromJson(Object? j) {
    if (j is! Map) return null;
    final id = j['id'];
    if (id is! String || id.trim().isEmpty) return null;
    final rawLevels = j['levels'];
    final name = j['name'];
    final context = j['context'];
    final maxOutput = j['maxOutput'];
    return ModelSpec(
      id: id.trim(),
      name: name is String ? name : null,
      contextLength: clampContext(context is int ? context : defaultContext),
      maxOutput: maxOutput is int && maxOutput > 0 ? maxOutput : defaultMaxOutput,
      vision: j['vision'] == true,
      thinking: j['thinking'] == true,
      levels: rawLevels is List
          ? [
              for (final l in rawLevels)
                if (l is String && kThinkingLevels.contains(l)) l,
            ]
          : null,
      priceHit: _price(j['priceHit']),
      priceMiss: _price(j['priceMiss']),
      priceOutput: _price(j['priceOut']),
    );
  }
}

/// 一个渠道（一家服务的接口地址 + 它下面勾选的模型）。不可变：要改走 [ModelConfigStore.upsert]。
class Channel {
  Channel({required this.id, required this.name, required this.protocol, required this.baseUrl, List<ModelSpec>? models}) : models = List.unmodifiable(models ?? const []);
  final String id;
  final String name;
  final ChatProtocol protocol;
  final String baseUrl;
  final List<ModelSpec> models;

  ModelSpec? model(String? id) => models.where((m) => m.id == id).firstOrNull;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'protocol': protocol.id,
    'baseUrl': baseUrl,
    'models': [for (final m in models) m.toJson()],
  };

  static Channel? fromJson(Object? j) {
    if (j is! Map) return null;
    final id = j['id'];
    if (id is! String || !RegExp(r'^[a-z0-9]{1,24}$').hasMatch(id)) return null;
    final models = j['models'];
    return Channel(
      id: id,
      name: '${j['name'] ?? '渠道'}',
      protocol: ChatProtocol.byId(j['protocol']),
      baseUrl: '${j['baseUrl'] ?? ''}',
      models: [for (final m in models is List ? models : const []) ?ModelSpec.fromJson(m)],
    );
  }
}

/// 对话当前用的“渠道 + 模型 + 思考深度”。
class ModelSelection {
  const ModelSelection(this.channelId, this.modelId, [this.level = 'off']);
  final String channelId;
  final String modelId;
  final String level;

  Map<String, dynamic> toJson() => {'channel': channelId, 'model': modelId, 'level': level};

  static ModelSelection? fromJson(Object? j) {
    if (j is! Map || j['channel'] is! String || j['model'] is! String) return null;
    return ModelSelection(j['channel'] as String, j['model'] as String, j['level'] is String ? j['level'] as String : 'off');
  }

  @override
  bool operator ==(Object other) => other is ModelSelection && other.channelId == channelId && other.modelId == modelId && other.level == level;
  @override
  int get hashCode => Object.hash(channelId, modelId, level);
}

/// 选择解析后的结果：真的存在的渠道和模型。
class ResolvedModel {
  ResolvedModel(this.channel, this.model, this.level);
  final Channel channel;
  final ModelSpec model;

  /// 已经按模型能力收过口的档位：模型不支持思考或没开这个档位时是 `off`。
  final String level;
  ModelSelection get selection => ModelSelection(channel.id, model.id, level);
}

/// 把一个选择落到 [channels] 里真实存在的渠道和模型上；指向的东西被删了就返回 null。
ResolvedModel? resolveSelection(List<Channel> channels, ModelSelection? s) {
  if (s == null) return null;
  final ch = channels.where((c) => c.id == s.channelId).firstOrNull;
  final m = ch?.model(s.modelId);
  if (ch == null || m == null) return null;
  final level = m.thinking && m.levels.contains(s.level) ? s.level : 'off';
  return ResolvedModel(ch, m, level);
}

/// [channels] 里第一个能用的模型（兜底）。
ResolvedModel? firstAvailableModel(List<Channel> channels) {
  for (final c in channels) {
    if (c.models.isNotEmpty) return ResolvedModel(c, c.models.first, 'off');
  }
  return null;
}

/// 现在为什么还不能和模型对话。
enum ModelGapKind { noChannel, noModel, noKey }

class ModelGap {
  const ModelGap(this.kind, [this.channel]);
  final ModelGapKind kind;

  /// 缺东西的那个渠道；一个渠道都没有时是 null。
  final Channel? channel;

  String get title => switch (kind) {
    ModelGapKind.noChannel => '还没有配置模型',
    ModelGapKind.noModel => '还没有选模型',
    ModelGapKind.noKey => '还没有填 API Key',
  };

  String get message => switch (kind) {
    ModelGapKind.noChannel => 'Agent 要连上一个模型服务才能干活。选一个服务商，填上 API Key 就行。',
    ModelGapKind.noModel => '渠道“${channel?.name ?? ''}”里还没有勾选模型。进去点“获取模型”勾上要用的，或者手动添加模型 ID。',
    ModelGapKind.noKey => '渠道“${channel?.name ?? ''}”还没有保存 API Key，发出去的消息会被拒绝。',
  };
}

/// 渠道与模型的配置。普通信息在设置文件里，Key 只进安全存储（每个渠道一个）。
class ModelConfigStore {
  ModelConfigStore(this.settings, this.secrets);
  final SettingsStore settings;
  final SecretStore secrets;

  static const kChannels = 'ai.channels';
  static const kLast = 'ai.lastSelection';
  static const kFixed = 'ai.fixedSelection';
  static const kDefaultMode = 'ai.newChatDefault'; // last / fixed

  static String keyName(String channelId) => 'channel_key_$channelId';

  /// 现有的渠道（列表不可改；每次增删改都换一份新的）。
  List<Channel> get channels => _channels;
  List<Channel> _channels = const [];
  void _setChannels(Iterable<Channel> next) {
    _channels = List.unmodifiable(next);
    for (final listener in List.of(channelListeners)) {
      listener();
    }
  }

  /// 渠道清单换了一份（状态层据此换快照）。
  final List<void Function()> channelListeners = [];

  /// 某个渠道的 Key 换了、清了，或者渠道被删了（额度那边据此作废旧的余额请求）。
  final List<void Function(String channelId)> keyListeners = [];

  /// Key 存了、换了、清了的次数。
  int keyRev = 0;

  void _keyChanged(String channelId) {
    keyRev++;
    for (final listener in List.of(keyListeners)) {
      listener(channelId);
    }
  }

  /// 读配置；第一次运行新版时把老的“单一接口”设置搬成一个渠道。
  Future<void> load() async {
    final raw = settings.get<List<dynamic>>(kChannels);
    _setChannels([for (final c in raw ?? const []) ?Channel.fromJson(c)]);
    if (raw == null) await _migrateLegacy();
  }

  Future<void> _migrateLegacy() async {
    final base = settings.getString(SettingKeys.agentBaseUrl).trim();
    final model = settings.getString(SettingKeys.agentModel).trim();
    final key = await secrets.read(SecretKeys.agentApiKey);
    if (base.isEmpty && model.isEmpty && (key == null || key.isEmpty)) {
      await save();
      return;
    }
    final ch = Channel(
      id: 'default',
      name: '默认渠道',
      protocol: ChatProtocol.openaiChat,
      baseUrl: base,
      models: [if (model.isNotEmpty) ModelSpec(id: model)],
    );
    _setChannels([ch]);
    if (key != null && key.isNotEmpty) {
      // 先写新位置，写成功了再删旧的，中途失败不会丢 Key。
      await secrets.write(keyName(ch.id), key);
      await secrets.delete(SecretKeys.agentApiKey);
    }
    await save();
    if (model.isNotEmpty) await settings.set(kLast, ModelSelection(ch.id, model).toJson());
    await settings.set(SettingKeys.agentBaseUrl, null);
    await settings.set(SettingKeys.agentModel, null);
  }

  Future<void> save() => settings.set(kChannels, [for (final c in channels) c.toJson()]);

  Channel? channel(String? id) => channels.where((c) => c.id == id).firstOrNull;

  String _freeId() {
    var id = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    while (channel(id) != null) {
      id = '${id}x';
    }
    return id.length > 24 ? id.substring(id.length - 24) : id;
  }

  /// 新建或更新渠道，返回存好的那一份。[apiKey] 留空（null 或空串）表示不动已保存的 Key；[models] 不传表示不动模型。
  Future<Channel> upsert({String? id, required String name, required ChatProtocol protocol, required String baseUrl, String? apiKey, List<ModelSpec>? models}) async {
    final old = channel(id);
    final ch = Channel(id: old?.id ?? id ?? _freeId(), name: name.trim().isEmpty ? protocol.label : name, protocol: protocol, baseUrl: baseUrl.trim(), models: models ?? old?.models);
    _setChannels(old == null ? [...channels, ch] : [for (final c in channels) c.id == ch.id ? ch : c]);
    if (apiKey != null && apiKey.trim().isNotEmpty) {
      final changed = (await secrets.read(keyName(ch.id))) != apiKey.trim();
      await secrets.write(keyName(ch.id), apiKey.trim());
      if (changed) _keyChanged(ch.id);
    }
    await save();
    return ch;
  }

  Future<void> remove(String id) async {
    _setChannels(channels.where((c) => c.id != id));
    await secrets.delete(keyName(id));
    _keyChanged(id);
    await save();
  }

  Future<bool> hasKey(String id) async => ((await secrets.read(keyName(id))) ?? '').isNotEmpty;
  Future<String> apiKey(String id) async => (await secrets.read(keyName(id))) ?? '';
  Future<void> clearKey(String id) async {
    await secrets.delete(keyName(id));
    _keyChanged(id);
  }

  // ── 选择 ─────────────────────────────────────────────
  bool get newChatUsesFixed => settings.getString(kDefaultMode, 'last') == 'fixed';
  Future<void> setNewChatUsesFixed(bool fixed) => settings.set(kDefaultMode, fixed ? 'fixed' : 'last');

  ModelSelection? get lastSelection => ModelSelection.fromJson(settings.get<Map<String, dynamic>>(kLast));
  ModelSelection? get fixedSelection => ModelSelection.fromJson(settings.get<Map<String, dynamic>>(kFixed));
  Future<void> setLastSelection(ModelSelection s) => settings.set(kLast, s.toJson());
  Future<void> setFixedSelection(ModelSelection? s) => settings.set(kFixed, s?.toJson());

  /// 把一个选择落到真实存在的渠道和模型上；指向的东西被删了就返回 null。
  ResolvedModel? resolve(ModelSelection? s) => resolveSelection(channels, s);

  /// 第一个能用的模型（兜底）。
  ResolvedModel? get firstAvailable => firstAvailableModel(channels);

  /// 新对话用哪个模型：固定默认 → 上次用的 → 第一个能用的。
  ResolvedModel? defaultForNewChat() => (newChatUsesFixed ? resolve(fixedSelection) : null) ?? resolve(lastSelection) ?? resolve(fixedSelection) ?? firstAvailable;

  bool get configured => firstAvailable != null;

  /// 现在能不能发消息；能就返回 null。[current] 是这段对话选的模型，不传就看新对话默认用的那个。
  /// 本机 / 局域网的服务（Ollama 之类）不要求 Key。
  Future<ModelGap?> readiness([ResolvedModel? current]) async {
    if (channels.isEmpty) return const ModelGap(ModelGapKind.noChannel);
    final r = current ?? defaultForNewChat();
    if (r == null) return ModelGap(ModelGapKind.noModel, channels.first);
    if (!isLocalBaseUrl(r.channel.baseUrl) && !await hasKey(r.channel.id)) return ModelGap(ModelGapKind.noKey, r.channel);
    return null;
  }

  /// 调试 / 测试用：配置的 JSON（不含任何 Key）。
  String dump() => jsonEncode([for (final c in channels) c.toJson()]);
}
