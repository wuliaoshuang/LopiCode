import 'package:lopicode/core/stores.dart';

/// 设置页里能勾选的全部工具（名字 → 给人看的说明）。
const Map<String, String> kToolLabels = {
  'list_files': '查看文件列表',
  'read_file': '读取文件',
  'view_image': '查看图片',
  'write_file': '写入文件',
  'delete_file': '删除文件',
  'run_command': '执行命令',
  'lowcode_get_page': '读取低代码页面',
  'lowcode_update_page': '更新低代码页面',
  'backend_get_blocks': '读取后端积木',
  'backend_update_blocks': '更新后端积木',
  'ask_user': '向你提问',
  'update_todos': '列待办清单',
  'web_search': '联网搜索',
  'read_skill': '读取技能',
  'spawn_agent': '派出子代理',
  'team_board': '查看任务板',
  'team_task': '新建 / 更新任务',
  'team_message': '给团队留言',
  'list_scheduled_tasks': '查看自动化任务',
  'schedule_task': '新建 / 修改自动化任务',
};

/// Agent 预设：一套系统提示词 + 可用工具。
class AgentPreset {
  AgentPreset({required this.id, required this.name, this.prompt = '', Set<String>? tools, this.builtIn = false}) : tools = tools == null ? null : Set.unmodifiable(tools);
  final String id;
  final String name;

  /// 附加的系统提示词（接在内置的基础规则后面）。
  final String prompt;

  /// 勾选的工具；null 表示全部。改不了：要改就 [upsert] 一份新的。
  final Set<String>? tools;
  final bool builtIn;

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'prompt': prompt, 'tools': tools?.toList()};

  static AgentPreset? fromJson(Object? j) {
    if (j is! Map || j['id'] is! String || !RegExp(r'^[a-z0-9]{1,24}$').hasMatch(j['id'] as String)) return null;
    if (j['id'] == PresetStore.standardId) return null;
    return AgentPreset(
      id: j['id'] as String,
      name: '${j['name'] ?? '预设'}',
      prompt: '${j['prompt'] ?? ''}',
      tools: j['tools'] is List
          ? {
              for (final t in j['tools'] as List)
                if (kToolLabels.containsKey(t)) t as String,
            }
          : null,
    );
  }
}

/// 个性化：个人偏好 + Agent 预设。
class PresetStore {
  PresetStore(this.settings);
  final SettingsStore settings;

  static const standardId = 'standard';
  static const kPresets = 'agent.presets';
  static const kDefault = 'agent.defaultPreset';
  static const kPreferences = 'agent.preferences';

  static AgentPreset get standard => AgentPreset(id: standardId, name: '标准模式', builtIn: true);

  List<AgentPreset> get custom => [for (final p in settings.get<List<dynamic>>(kPresets) ?? const []) ?AgentPreset.fromJson(p)];

  List<AgentPreset> get all => [standard, ...custom];

  AgentPreset byId(String? id) => all.firstWhere((p) => p.id == id, orElse: () => standard);

  String get defaultId => byId(settings.getString(kDefault, standardId)).id;
  Future<void> setDefault(String id) => settings.set(kDefault, id);

  Future<void> _save(List<AgentPreset> list) => settings.set(kPresets, [for (final p in list) p.toJson()]);

  Future<AgentPreset> upsert({String? id, required String name, required String prompt, Set<String>? tools}) async {
    final list = custom;
    final clean = name.trim().isEmpty ? '未命名预设' : name.trim();
    final at = list.indexWhere((p) => p.id == id);
    var newId = at >= 0 ? list[at].id : DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    while (at < 0 && list.any((p) => p.id == newId)) {
      newId = '${newId}x';
    }
    final preset = AgentPreset(id: newId, name: clean, prompt: prompt.trim(), tools: tools);
    if (at >= 0) {
      list[at] = preset;
    } else {
      list.add(preset);
    }
    await _save(list);
    return preset;
  }

  Future<AgentPreset> copy(AgentPreset source) => upsert(name: '${source.name} 副本', prompt: source.prompt, tools: source.tools == null ? null : {...source.tools!});

  Future<void> delete(String id) async {
    await _save(custom.where((p) => p.id != id).toList());
    if (settings.getString(kDefault) == id) await settings.set(kDefault, null);
  }

  /// 个人偏好：进系统提示词；清空就是删掉。
  String get preferences => settings.getString(kPreferences).trim();
  Future<void> setPreferences(String text) => settings.set(kPreferences, text.trim().isEmpty ? null : text.trim());
}
