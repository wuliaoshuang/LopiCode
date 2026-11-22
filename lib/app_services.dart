import 'dart:io';

import 'package:lopicode/agent/chat_client.dart';
import 'package:lopicode/core/keystore_secret_store.dart';
import 'package:lopicode/core/project_store.dart';
import 'package:lopicode/core/stores.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 全应用共用的服务：设置、密钥、项目仓库。测试里可以整体替换。
class AppServices extends ChangeNotifier {
  AppServices({
    required this.settings,
    required this.secrets,
    required this.projects,
    this.chatClientFactory,
  });

  final SettingsStore settings;
  final SecretStore secrets;
  final ProjectStore projects;

  /// 测试钩子：替换真实的模型客户端。
  final ChatClient Function()? chatClientFactory;

  static Future<AppServices> boot() async {
    final docs = await getApplicationDocumentsDirectory();
    final settings = SettingsStore(File(p.join(docs.path, 'settings.json')));
    await settings.load();
    final secrets = KeystoreSecretStore();
    await secrets.probe();
    return AppServices(
      settings: settings,
      secrets: secrets,
      projects: ProjectStore(p.join(docs.path, 'projects')),
    );
  }

  ThemeMode get themeMode => switch (settings.getString(SettingKeys.themeMode, 'system')) {
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    _ => ThemeMode.system,
  };

  Future<void> setThemeMode(ThemeMode mode) async {
    await settings.set(SettingKeys.themeMode, mode.name);
    notifyListeners();
  }

  bool get agentConfigured =>
      chatClientFactory != null ||
      (settings.getString(SettingKeys.agentBaseUrl).trim().isNotEmpty &&
          settings.getString(SettingKeys.agentModel).trim().isNotEmpty);

  Future<ChatClient> createChatClient() async {
    final factory = chatClientFactory;
    if (factory != null) return factory();
    return OpenAiChatClient(
      baseUrl: settings.getString(SettingKeys.agentBaseUrl),
      apiKey: await secrets.read(SecretKeys.agentApiKey) ?? '',
      model: settings.getString(SettingKeys.agentModel),
    );
  }

  /// 设置改动后通知界面刷新。
  void touch() => notifyListeners();
}

class AppScope extends InheritedNotifier<AppServices> {
  const AppScope({super.key, required AppServices services, required super.child}) : super(notifier: services);

  static AppServices of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;
}
