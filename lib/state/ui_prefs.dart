import 'package:lopicode/core/stores.dart';
import 'package:lopicode/state/app_providers.dart';
import 'package:riverpod/riverpod.dart';

/// 外观：跟随系统 / 浅色 / 深色。（逻辑层不引用界面库，所以不用 Flutter 的 ThemeMode。）
enum AppThemeMode { system, light, dark }

/// 外观模式。只有它变了，应用外壳才重建。
class ThemeModeNotifier extends Notifier<AppThemeMode> {
  @override
  AppThemeMode build() {
    ref.watch(settingRevProvider(SettingKeys.themeMode));
    return switch (ref.watch(settingsStoreProvider).getString(SettingKeys.themeMode, 'system')) {
      'light' => AppThemeMode.light,
      'dark' => AppThemeMode.dark,
      _ => AppThemeMode.system,
    };
  }

  /// 写进设置文件；设置键一变，这里自己会重算。
  Future<void> set(AppThemeMode mode) => ref.read(settingsStoreProvider).set(SettingKeys.themeMode, mode.name);
}

final themeModeProvider = NotifierProvider<ThemeModeNotifier, AppThemeMode>(ThemeModeNotifier.new);

/// 聊天页的几个开关。
class ChatPrefs {
  const ChatPrefs({required this.suggestions, required this.usage, this.thinking = true});

  /// 在聊天里显示思考过程（默认开）。
  final bool thinking;

  /// 新对话里显示开场建议（默认开）。
  final bool suggestions;

  /// 在回复下方显示用量（默认开）。
  final bool usage;

  @override
  bool operator ==(Object other) => other is ChatPrefs && other.suggestions == suggestions && other.usage == usage && other.thinking == thinking;

  @override
  int get hashCode => Object.hash(suggestions, usage, thinking);
}

class ChatPrefsNotifier extends Notifier<ChatPrefs> {
  @override
  ChatPrefs build() {
    ref
      ..watch(settingRevProvider(SettingKeys.chatSuggestions))
      ..watch(settingRevProvider(SettingKeys.chatUsage))
      ..watch(settingRevProvider(SettingKeys.chatThinking));
    final s = ref.watch(settingsStoreProvider);
    return ChatPrefs(suggestions: s.getBool(SettingKeys.chatSuggestions, true), usage: s.getBool(SettingKeys.chatUsage, true), thinking: s.getBool(SettingKeys.chatThinking, true));
  }

  Future<void> setSuggestions(bool on) => ref.read(settingsStoreProvider).set(SettingKeys.chatSuggestions, on);

  Future<void> setUsage(bool on) => ref.read(settingsStoreProvider).set(SettingKeys.chatUsage, on);
}

final chatPrefsProvider = NotifierProvider<ChatPrefsNotifier, ChatPrefs>(ChatPrefsNotifier.new);
