// 渠道与模型的状态（完整版：不可变快照 + Notifier，照额度那个样板）。
//
// 数据落在设置文件里（Key 在安全存储里），lib/agent/model_config.dart 的 ModelConfigStore 负责读写和校验。
// 这里把它读成一份不可变的快照给界面订阅；界面要改就调 [ModelsNotifier] 的方法——存好以后快照自动换成新的一份。
// 不管是谁改的（界面、发消息时记“上次用的模型”、老设置搬家），快照都会跟着换。
// `Channel`、`ModelSpec` 本身也是不可变的：界面拿到手改不了字段。
import 'package:lopicode/agent/model_config.dart';
import 'package:lopicode/state/app_providers.dart';
import 'package:riverpod/riverpod.dart';

class ModelsState {
  ModelsState({
    required List<Channel> channels,
    required this.lastSelection,
    required this.fixedSelection,
    required this.newChatUsesFixed,
    this.keyRev = 0,
    Map<String, String> thinkingLevels = const {},
  }) : channels = List.unmodifiable(channels),
       thinkingLevels = Map.unmodifiable(thinkingLevels);

  final List<Channel> channels;

  /// 上次用的模型、固定默认的模型（可能指向已经删掉的渠道，用 [resolve] 落到真实存在的上面）。
  final ModelSelection? lastSelection;
  final ModelSelection? fixedSelection;

  /// 新对话用“固定默认”（true）还是“上次用的”（false）。
  final bool newChatUsesFixed;

  /// 某个渠道的 Key 存了、换了、清了的次数（Key 本身不进状态；“有没有 Key”要问 [ModelConfigStore.hasKey]）。
  final int keyRev;

  /// 每个模型上次设的思考档位（键是 `渠道 id/模型 id`）。
  final Map<String, String> thinkingLevels;

  /// 这个模型上次设的档位；没设过是 null。
  String? thinkingLevelOf(String channelId, String modelId) => thinkingLevels[thinkingLevelKey(channelId, modelId)];

  Channel? channel(String? id) => channels.where((c) => c.id == id).firstOrNull;

  /// 把一个选择落到真实存在的渠道和模型上；指向的东西被删了就是 null。
  ResolvedModel? resolve(ModelSelection? s) => resolveSelection(channels, s, remembered: thinkingLevels);

  /// 第一个能用的模型（兜底）。
  ResolvedModel? get firstAvailable => firstAvailableModel(channels, remembered: thinkingLevels);

  /// 新对话用哪个模型：固定默认 → 上次用的 → 第一个能用的。
  ResolvedModel? get defaultForNewChat => (newChatUsesFixed ? resolve(fixedSelection) : null) ?? resolve(lastSelection) ?? resolve(fixedSelection) ?? firstAvailable;

  bool get configured => firstAvailable != null;
}

class ModelsNotifier extends Notifier<ModelsState> {
  ModelConfigStore get _store => ref.read(appServicesProvider).models;

  @override
  ModelsState build() {
    final store = ref.watch(appServicesProvider).models;
    // 这五个键任何一个被写了，就重新读一份
    for (final key in const [ModelConfigStore.kChannels, ModelConfigStore.kLast, ModelConfigStore.kFixed, ModelConfigStore.kDefaultMode, ModelConfigStore.kLevels]) {
      ref.watch(settingRevProvider(key));
    }
    // 渠道清单在内存里换了（启动时从盘上读出来那一次不写设置文件，所以单独听）
    void onChannels() {
      if (ref.mounted) ref.invalidateSelf();
    }

    // Key 不在设置文件里，所以单独记
    void onKey(String _) => onChannels();

    store.channelListeners.add(onChannels);
    store.keyListeners.add(onKey);
    ref.onDispose(() {
      store.channelListeners.remove(onChannels);
      store.keyListeners.remove(onKey);
    });
    return ModelsState(
      channels: store.channels,
      lastSelection: store.lastSelection,
      fixedSelection: store.fixedSelection,
      newChatUsesFixed: store.newChatUsesFixed,
      keyRev: store.keyRev,
      thinkingLevels: store.thinkingLevels,
    );
  }

  /// 新建（不传 id）或修改一个渠道，返回存好的那一份。[apiKey] 留空表示不动已保存的 Key；[models] 不传表示不动模型。
  Future<Channel> upsert({String? id, required String name, required ChatProtocol protocol, required String baseUrl, String? apiKey, List<ModelSpec>? models}) =>
      _store.upsert(id: id, name: name, protocol: protocol, baseUrl: baseUrl, apiKey: apiKey, models: models);

  /// 删掉渠道和它的 Key。
  Future<void> remove(String id) => _store.remove(id);

  Future<void> clearKey(String id) => _store.clearKey(id);

  Future<void> setNewChatUsesFixed(bool fixed) => _store.setNewChatUsesFixed(fixed);

  Future<void> setFixedSelection(ModelSelection? s) => _store.setFixedSelection(s);

  /// 记住某个模型的思考档位。
  Future<void> setThinkingLevel(String channelId, String modelId, String level) => _store.setThinkingLevel(channelId, modelId, level);

  /// 把一个模型标成“可思考”（或取消）。返回存好的那份渠道；渠道或模型不在了返回 null。
  Future<Channel?> setModelThinking(String channelId, String modelId, bool thinking) async {
    final ch = _store.channel(channelId);
    if (ch == null || ch.model(modelId) == null) return null;
    return _store.upsert(
      id: ch.id,
      name: ch.name,
      protocol: ch.protocol,
      baseUrl: ch.baseUrl,
      models: [
        for (final m in ch.models)
          if (m.id == modelId) m.copyWith(thinking: thinking, levels: m.levels.isEmpty ? kThinkingLevels : null) else m,
      ],
    );
  }
}

final modelsProvider = NotifierProvider<ModelsNotifier, ModelsState>(ModelsNotifier.new);
