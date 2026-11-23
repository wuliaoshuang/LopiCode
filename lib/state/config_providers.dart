// 配置类状态的订阅入口：技能、自动化任务、Agent 相关设置、SSH 主机、联网搜索。
// （渠道与模型在 models_state.dart，预设在 presets_state.dart，都是完整版。）
//
// 这些数据的主人是各自的存储对象（都落在设置文件或自己的文件里，见 lib/agent/）。
// 这里的 provider 负责“谁变了只通知关心它的界面”：界面在 build 里 `ref.watch(某个 Rev)`，
// 然后照常从存储对象读值；要改就调存储对象的方法——它写完会让对应的 Rev 加一。
// 不要再写“改完手动通知全应用”的代码。
import 'package:lopicode/agent/skills.dart';
import 'package:lopicode/core/stores.dart';
import 'package:lopicode/state/app_providers.dart';
import 'package:riverpod/riverpod.dart';

int _sum(Ref ref, List<String> keys) => keys.fold(0, (n, k) => n + ref.watch(settingRevProvider(k)));

/// 新对话默认权限、子代理、智能体团队这几项设置变了。
final agentSettingsRevProvider = Provider<int>(
  (ref) => _sum(ref, const [
    SettingKeys.defaultPermission,
    SettingKeys.subagentEnabled,
    SettingKeys.subagentMaxDepth,
    SettingKeys.subagentMaxConcurrent,
    SettingKeys.subagentAllowedModels,
    SettingKeys.teamEnabled,
  ]),
);

/// SSH 主机（终端和打包共用的那一台）的地址、端口、用户名、登录方式变了。
final sshConfigRevProvider = Provider<int>((ref) => _sum(ref, const [SettingKeys.sshHost, SettingKeys.sshPort, SettingKeys.sshUser, SettingKeys.sshAuth]));

/// 技能文件增删了（开关在设置文件里，见 [skillsRevProvider]）。
class SkillFilesRev extends Notifier<int> {
  @override
  int build() {
    final skills = ref.watch(appServicesProvider).skills;
    void onChange() => state = state + 1;
    skills.changeListeners.add(onChange);
    ref.onDispose(() => skills.changeListeners.remove(onChange));
    return 0;
  }
}

final skillFilesRevProvider = NotifierProvider<SkillFilesRev, int>(SkillFilesRev.new);

/// 技能（有哪些、哪些开着）变了。
final skillsRevProvider = Provider<int>((ref) => ref.watch(settingRevProvider(SkillStore.kDisabled)) + ref.watch(skillFilesRevProvider));

/// 联网搜索的配置变了（Key 存在安全存储里，不走设置文件，所以保存 / 清除后来这里说一声）。
class WebSearchRev extends Notifier<int> {
  @override
  int build() => 0;

  void bump() {
    if (ref.mounted) state = state + 1;
  }
}

final webSearchRevProvider = NotifierProvider<WebSearchRev, int>(WebSearchRev.new);
