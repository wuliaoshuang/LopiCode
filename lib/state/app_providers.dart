import 'package:lopicode/app_services.dart';
import 'package:lopicode/core/project_store.dart';
import 'package:lopicode/core/stores.dart';
import 'package:riverpod/riverpod.dart';

/// 应用服务（设置文件、密钥、项目仓库这些“干活的对象”）。
///
/// 启动时由 [AppServices] 自己建好容器并把自己填进来（见 `AppServices.container`），
/// 所以这里没有默认值：没填就读说明接线漏了。
final appServicesProvider = Provider<AppServices>((ref) => throw StateError('appServicesProvider 没有接线：要通过 AppServices.container 读'));

/// 设置文件（键值）。只是取用入口；界面要“跟着变”的值请订阅对应的状态 provider，不要直接读它。
final settingsStoreProvider = Provider<SettingsStore>((ref) => ref.watch(appServicesProvider).settings);

/// 密钥存储。
final secretStoreProvider = Provider<SecretStore>((ref) => ref.watch(appServicesProvider).secrets);

/// 项目（工作区）仓库。
final projectStoreProvider = Provider<ProjectStore>((ref) => ref.watch(appServicesProvider).projects);

/// “现在几点”。测试里替换成假时钟。
final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// 某一个设置键“变过几次”。订阅它＝这个键一变就重算 / 重画；值本身仍从 [settingsStoreProvider] 读。
///
/// 这样任何地方（界面或逻辑层）写设置，关心这个键的界面都会跟着变，而且只有它们变。
class SettingRev extends Notifier<int> {
  SettingRev(this.key);
  final String key;

  @override
  int build() {
    final store = ref.watch(settingsStoreProvider);
    void onKey(String k) {
      if (k == key) state = state + 1;
    }

    store.addKeyListener(onKey);
    ref.onDispose(() => store.removeKeyListener(onKey));
    return 0;
  }
}

final settingRevProvider = NotifierProvider.family<SettingRev, int, String>(SettingRev.new);

/// 任意设置键变了都加一。只给“设置总览”这种本来就汇总所有设置的页面用，别的地方订阅具体的键。
class SettingsAnyRev extends Notifier<int> {
  @override
  int build() {
    final store = ref.watch(settingsStoreProvider);
    void onKey(String _) => state = state + 1;
    store.addKeyListener(onKey);
    ref.onDispose(() => store.removeKeyListener(onKey));
    return 0;
  }
}

final settingsAnyRevProvider = NotifierProvider<SettingsAnyRev, int>(SettingsAnyRev.new);
