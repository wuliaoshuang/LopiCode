// Agent 预设与个人偏好的状态（照额度那个完整版样板：不可变状态 + Notifier）。
//
// 数据落在设置文件里（lib/agent/presets.dart 的 PresetStore 负责读写和校验）。
// 这里把它读成一份不可变的快照给界面订阅；要改就调 Notifier 的方法——写完设置文件，快照自动换成新的一份。
// 不管是谁改的设置文件（界面、Agent、导入），快照都会跟着换。
import 'package:lopicode/agent/presets.dart';
import 'package:lopicode/state/app_providers.dart';
import 'package:riverpod/riverpod.dart';

class PresetsState {
  PresetsState({required List<AgentPreset> custom, required this.defaultId, required this.preferences}) : custom = List.unmodifiable(custom);

  /// 自己建的预设（不含内置的“标准模式”）。
  final List<AgentPreset> custom;

  /// 新对话默认用哪个（指向的预设被删了就回到标准模式）。
  final String defaultId;

  /// 个人偏好（进系统提示词；空串＝没写）。
  final String preferences;

  late final List<AgentPreset> all = List.unmodifiable([PresetStore.standard, ...custom]);

  /// 找不到就给标准模式。
  AgentPreset byId(String? id) => all.firstWhere((p) => p.id == id, orElse: () => all.first);

  AgentPreset get defaultPreset => byId(defaultId);
}

class PresetsNotifier extends Notifier<PresetsState> {
  PresetStore get _store => ref.read(appServicesProvider).presets;

  @override
  PresetsState build() {
    final store = ref.watch(appServicesProvider).presets;
    // 这三个键任何一个被写了，就重新读一份
    for (final key in const [PresetStore.kPresets, PresetStore.kDefault, PresetStore.kPreferences]) {
      ref.watch(settingRevProvider(key));
    }
    return PresetsState(custom: store.custom, defaultId: store.defaultId, preferences: store.preferences);
  }

  /// 新建（不传 id）或修改一个预设。
  Future<AgentPreset> upsert({String? id, required String name, required String prompt, Set<String>? tools}) => _store.upsert(id: id, name: name, prompt: prompt, tools: tools);

  Future<AgentPreset> copy(AgentPreset source) => _store.copy(source);

  Future<void> delete(String id) => _store.delete(id);

  Future<void> setDefault(String id) => _store.setDefault(id);

  Future<void> setPreferences(String text) => _store.setPreferences(text);
}

final presetsProvider = NotifierProvider<PresetsNotifier, PresetsState>(PresetsNotifier.new);
