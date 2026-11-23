import 'dart:convert';

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

/// 渠道里的一个模型。
class ModelSpec {
  ModelSpec({
    required this.id,
    String? name,
    this.contextLength = defaultContext,
    this.maxOutput = defaultMaxOutput,
    this.vision = false,
    this.thinking = false,
    List<String>? levels,
  }) : name = (name == null || name.trim().isEmpty) ? id : name.trim(),
       levels = levels ?? List.of(kThinkingLevels);

  static const int defaultContext = 256000;
  static const int defaultMaxOutput = 32000;
  static const int minContext = 32000;
  static const int maxContext = 1000000;

  /// 可以直接点选的上下文长度。
  static const List<int> contextChoices = [32000, 64000, 128000, 200000, 256000, 400000, 1000000];

  /// 发给接口的模型 ID。
  final String id;

  /// 显示名。
  String name;
  int contextLength;
  int maxOutput;

  /// 输入类型：false＝只有文本，true＝文本和图片。
  bool vision;

  /// 这个模型能不能“思考”，以及可选的档位。
  bool thinking;
  List<String> levels;

  static int clampContext(int v) => v.clamp(minContext, maxContext);

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'context': contextLength,
    'maxOutput': maxOutput,
    'vision': vision,
    'thinking': thinking,
    'levels': levels,
  };

  static ModelSpec? fromJson(Object? j) {
    if (j is! Map || j['id'] is! String || (j['id'] as String).trim().isEmpty) return null;
    final levels = [
      for (final l in (j['levels'] as List?) ?? const [])
        if (kThinkingLevels.contains(l)) l as String,
    ];
    return ModelSpec(
      id: (j['id'] as String).trim(),
      name: j['name'] is String ? j['name'] as String : null,
      contextLength: clampContext(j['context'] is int ? j['context'] as int : defaultContext),
      maxOutput: j['maxOutput'] is int && (j['maxOutput'] as int) > 0 ? j['maxOutput'] as int : defaultMaxOutput,
      vision: j['vision'] == true,
      thinking: j['thinking'] == true,
      levels: j['levels'] is List ? levels : null,
    );
  }
}

class Channel {
  Channel({required this.id, required this.name, required this.protocol, required this.baseUrl, List<ModelSpec>? models})
    : models = models ?? [];
  final String id;
  String name;
  ChatProtocol protocol;
  String baseUrl;
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
    if (j is! Map || j['id'] is! String) return null;
    final id = j['id'] as String;
    if (!RegExp(r'^[a-z0-9]{1,24}$').hasMatch(id)) return null;
    return Channel(
      id: id,
      name: '${j['name'] ?? '渠道'}',
      protocol: ChatProtocol.byId(j['protocol']),
      baseUrl: '${j['baseUrl'] ?? ''}',
      models: [
        for (final m in (j['models'] as List?) ?? const [])
          ?ModelSpec.fromJson(m),
      ],
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
  bool operator ==(Object other) =>
      other is ModelSelection && other.channelId == channelId && other.modelId == modelId && other.level == level;
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

  List<Channel> channels = [];

  /// 读配置；第一次运行新版时把老的“单一接口”设置搬成一个渠道。
  Future<void> load() async {
    final raw = settings.get<List<dynamic>>(kChannels);
    channels = [
      for (final c in raw ?? const [])
        ?Channel.fromJson(c),
    ];
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
    channels = [ch];
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

  /// 新建或更新渠道。[apiKey] 留空（null 或空串）表示不动已保存的 Key。
  Future<Channel> upsert({
    String? id,
    required String name,
    required ChatProtocol protocol,
    required String baseUrl,
    String? apiKey,
    List<ModelSpec>? models,
  }) async {
    var ch = channel(id);
    if (ch == null) {
      ch = Channel(id: id ?? _freeId(), name: name, protocol: protocol, baseUrl: baseUrl.trim(), models: models);
      channels.add(ch);
    } else {
      ch
        ..name = name
        ..protocol = protocol
        ..baseUrl = baseUrl.trim();
      if (models != null) {
        ch.models
          ..clear()
          ..addAll(models);
      }
    }
    if (ch.name.trim().isEmpty) ch.name = protocol.label;
    if (apiKey != null && apiKey.trim().isNotEmpty) await secrets.write(keyName(ch.id), apiKey.trim());
    await save();
    return ch;
  }

  Future<void> remove(String id) async {
    channels.removeWhere((c) => c.id == id);
    await secrets.delete(keyName(id));
    await save();
  }

  Future<bool> hasKey(String id) async => ((await secrets.read(keyName(id))) ?? '').isNotEmpty;
  Future<String> apiKey(String id) async => (await secrets.read(keyName(id))) ?? '';
  Future<void> clearKey(String id) => secrets.delete(keyName(id));

  // ── 选择 ─────────────────────────────────────────────
  bool get newChatUsesFixed => settings.getString(kDefaultMode, 'last') == 'fixed';
  Future<void> setNewChatUsesFixed(bool fixed) => settings.set(kDefaultMode, fixed ? 'fixed' : 'last');

  ModelSelection? get lastSelection => ModelSelection.fromJson(settings.get<Map<String, dynamic>>(kLast));
  ModelSelection? get fixedSelection => ModelSelection.fromJson(settings.get<Map<String, dynamic>>(kFixed));
  Future<void> setLastSelection(ModelSelection s) => settings.set(kLast, s.toJson());
  Future<void> setFixedSelection(ModelSelection? s) => settings.set(kFixed, s?.toJson());

  /// 把一个选择落到真实存在的渠道和模型上；指向的东西被删了就返回 null。
  ResolvedModel? resolve(ModelSelection? s) {
    if (s == null) return null;
    final ch = channel(s.channelId);
    final m = ch?.model(s.modelId);
    if (ch == null || m == null) return null;
    final level = m.thinking && m.levels.contains(s.level) ? s.level : 'off';
    return ResolvedModel(ch, m, level);
  }

  /// 第一个能用的模型（兜底）。
  ResolvedModel? get firstAvailable {
    for (final c in channels) {
      if (c.models.isNotEmpty) return ResolvedModel(c, c.models.first, 'off');
    }
    return null;
  }

  /// 新对话用哪个模型：固定默认 → 上次用的 → 第一个能用的。
  ResolvedModel? defaultForNewChat() =>
      (newChatUsesFixed ? resolve(fixedSelection) : null) ?? resolve(lastSelection) ?? resolve(fixedSelection) ?? firstAvailable;

  bool get configured => firstAvailable != null;

  /// 调试 / 测试用：配置的 JSON（不含任何 Key）。
  String dump() => jsonEncode([for (final c in channels) c.toJson()]);
}
