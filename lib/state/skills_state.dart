// 技能清单的状态（完整版：不可变状态 + Notifier）。
//
// 技能是磁盘上的一个个文件夹（全局的 + 某个工作区自己的），开关记在设置文件里；读写和校验在 lib/agent/skills.dart。
// 这里按“哪个工作区”分身，把扫描结果做成不可变的快照；增删、开关之后自动重新扫描。
// 扫描是异步的：用代次丢掉过期的结果（连点两下开关，先回来的旧结果不能盖掉新的），销毁后不再写。
import 'dart:async';

import 'package:lopicode/agent/skills.dart';
import 'package:lopicode/state/app_providers.dart';
import 'package:lopicode/state/config_providers.dart';
import 'package:riverpod/riverpod.dart';

class SkillsState {
  SkillsState({List<Skill>? skills}) : skills = skills == null ? null : List.unmodifiable(skills);

  /// 还没扫描完是 null。
  final List<Skill>? skills;

  bool get loaded => skills != null;
  List<Skill> get ofWorkspace => [...?skills?.where((s) => !s.global)];
  List<Skill> get global => [...?skills?.where((s) => s.global)];
}

/// 键：工作区目录；只看全局技能就传 null。没人看了就释放，下次进页面重新扫描（技能文件可能被 Agent 或文件页改过）。
class SkillsNotifier extends Notifier<SkillsState> {
  SkillsNotifier(this.workspaceDir);
  final String? workspaceDir;

  int _generation = 0;
  SkillsState? _last;

  SkillStore get _store => ref.read(appServicesProvider).skills;

  @override
  SkillsState build() {
    final store = ref.watch(appServicesProvider).skills;
    ref.watch(skillsRevProvider); // 技能文件增删、开关变了：重新扫描
    unawaited(_scan(store, ++_generation));
    // 重新扫描期间先留着上一份，免得界面闪一下“加载中”
    return _last ?? SkillsState();
  }

  Future<void> _scan(SkillStore store, int generation) async {
    final List<Skill> list;
    try {
      list = await store.list(workspaceDir: workspaceDir);
    } on Exception {
      if (generation == _generation && ref.mounted) state = _last = SkillsState(skills: const []);
      return;
    }
    if (generation != _generation || !ref.mounted) return;
    state = _last = SkillsState(skills: list);
  }

  Future<void> setEnabled(Skill skill, bool on) => _store.setEnabled(skill, on);

  /// 名字不合规、重名会抛 [SkillException]。
  Future<Skill> create({required String name, required String description, required String body, required bool global}) =>
      _store.create(name: name, description: description, body: body, workspaceDir: global ? null : workspaceDir);

  Future<void> delete(Skill skill) => _store.delete(skill);
}

final skillsProvider = NotifierProvider.autoDispose.family<SkillsNotifier, SkillsState, String?>(SkillsNotifier.new);
