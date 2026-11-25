// 外观主题的状态（完整版：不可变快照 + Notifier）。
//
// - 外观模式（跟随系统 / 浅色 / 深色）还是 ui_prefs.dart 的 themeModeProvider，这里不管。
// - 这里管：主题库（内置 + 用户的），以及“浅色时用哪套、深色时用哪套”。两个槽各记一个标识，
//   所以跟随系统照常工作：系统切到深色就用深色槽里那套。
// - 用户主题存在应用数据目录的 themes/（lib/appearance/theme_store.dart）；选了哪套存在设置文件里。
// - 界面要当前主题：订阅 [lightThemeProvider] / [darkThemeProvider]（只有那一套真的变了才通知），
//   或者在控件里直接用 `context.themeSpec`（lib/theme/tokens.dart）。
import 'package:lopicode/appearance/theme_builtin.dart';
import 'package:lopicode/appearance/theme_json.dart';
import 'package:lopicode/appearance/theme_spec.dart';
import 'package:lopicode/appearance/theme_store.dart';
import 'package:lopicode/core/stores.dart';
import 'package:lopicode/state/app_providers.dart';
import 'package:lopicode/state/ui_prefs.dart';
import 'package:riverpod/riverpod.dart';

/// 主题库和当前选择的快照。
class ThemesView {
  ThemesView({required List<ThemeSpec> builtin, required List<ThemeSpec> user, required this.lightId, required this.darkId}) : builtin = List.unmodifiable(builtin), user = List.unmodifiable(user);

  /// 内置主题（只读）。
  final List<ThemeSpec> builtin;

  /// 用户主题。
  final List<ThemeSpec> user;

  /// 两个槽里记的标识（可能指向一套已经不在了的主题，这时 [light] / [dark] 退回默认）。
  final String lightId;
  final String darkId;

  List<ThemeSpec> get all => [...builtin, ...user];

  ThemeSpec? byId(String id) => all.where((t) => t.id == id).firstOrNull;

  /// 某一种明暗下能选的主题。
  List<ThemeSpec> choices({required bool dark}) => [...all.where((t) => t.dark == dark)];

  /// 浅色时生效的那套。标识找不到、或者那套其实是深色的，就退回默认浅色。
  ThemeSpec get light => _resolve(lightId, dark: false);

  /// 深色时生效的那套。
  ThemeSpec get dark => _resolve(darkId, dark: true);

  ThemeSpec _resolve(String id, {required bool dark}) {
    final t = byId(id);
    return t != null && t.dark == dark ? t : defaultThemeFor(dark: dark);
  }
}

/// 一次操作的结果：成功时 [theme] 有值，失败时 [error] 是一句人话。
class ThemeOpResult {
  const ThemeOpResult.ok(ThemeSpec this.theme, {this.background, this.notes = const []}) : error = null;
  const ThemeOpResult.fail(String this.error) : theme = null, background = null, notes = const [];

  final ThemeSpec? theme;
  final String? error;

  /// 导入的文件里附带的背景图（有的话）。这里不落盘，交给背景图那部分处理。
  final ThemeBackground? background;
  final List<String> notes;

  bool get ok => theme != null;
}

class ThemesNotifier extends Notifier<ThemesView> {
  ThemeStore get _store => ref.read(appServicesProvider).themes;
  SettingsStore get _settings => ref.read(settingsStoreProvider);
  int _seq = 0;

  @override
  ThemesView build() {
    ref
      ..watch(settingRevProvider(SettingKeys.themeLight))
      ..watch(settingRevProvider(SettingKeys.themeDark));
    return _snapshot();
  }

  ThemesView _snapshot() => ThemesView(
    builtin: kBuiltinThemes,
    user: _store.user,
    lightId: _settings.getString(SettingKeys.themeLight, kDefaultLightThemeId),
    darkId: _settings.getString(SettingKeys.themeDark, kDefaultDarkThemeId),
  );

  void _publish() {
    if (ref.mounted) state = _snapshot();
  }

  /// 列出某一种明暗下能选的主题（内置的在前）。
  List<ThemeSpec> list({required bool dark}) => state.choices(dark: dark);

  /// 选用一套主题：浅色的进浅色槽，深色的进深色槽。找不到返回一句原因。
  Future<String?> select(String id) async {
    final t = state.byId(id);
    if (t == null) return '找不到这套主题，可能已经被删掉了。';
    await _settings.set(t.dark ? SettingKeys.themeDark : SettingKeys.themeLight, id);
    return null;
  }

  /// 新建一套：从同明暗的默认主题复制一份。
  Future<ThemeOpResult> create({required bool dark, String? name}) => _add(defaultThemeFor(dark: dark), name ?? (dark ? '我的深色主题' : '我的浅色主题'), author: null);

  /// 复制一份来改（内置主题要改就走这个）。
  Future<ThemeOpResult> duplicate(String id, {String? name}) async {
    final src = state.byId(id);
    if (src == null) return const ThemeOpResult.fail('找不到这套主题，可能已经被删掉了。');
    return _add(src, name ?? '${src.name} 副本', author: src.author);
  }

  Future<ThemeOpResult> _add(ThemeSpec src, String name, {required String? author, ThemeBackground? background, List<String> notes = const []}) async {
    final bad = _checkName(name);
    if (bad != null) return ThemeOpResult.fail(bad);
    if (_store.user.length >= kMaxUserThemes) return const ThemeOpResult.fail('自己的主题最多 $kMaxUserThemes 套，先删掉几套不用的。');
    final theme = src.copyWith(id: _newId(), name: _uniqueName(name.trim()), author: () => author, builtin: false);
    final failed = await _write(theme);
    if (failed != null) return ThemeOpResult.fail(failed);
    return ThemeOpResult.ok(theme, background: background, notes: notes);
  }

  /// 保存改过的主题（只能存用户主题；标识不变，明暗不许改）。
  Future<String?> save(ThemeSpec theme) async {
    final old = _store.byId(theme.id);
    if (old == null) return '这套主题不能直接改（内置主题先“复制一份”，再改副本）。';
    if (old.dark != theme.dark) return '浅色主题不能改成深色的（反过来也不行）。要另一种就新建一套。';
    final bad = _checkName(theme.name);
    if (bad != null) return bad;
    // 走一遍“写成文件再读回来”：范围、大小这些规矩和导入是同一套。
    final checked = decodeThemeJson(encodeTheme(theme));
    if (!checked.ok) return checked.error;
    return _write(checked.theme!.copyWith(id: theme.id, name: theme.name.trim()));
  }

  /// 改名。
  Future<String?> rename(String id, String name) async {
    final old = _store.byId(id);
    if (old == null) return '这套主题不能改名（内置主题先“复制一份”）。';
    final bad = _checkName(name);
    if (bad != null) return bad;
    final next = name.trim();
    if (state.all.any((t) => t.id != id && t.name == next)) return '已经有一套叫“$next”的主题了，换个名字。';
    return _write(old.copyWith(name: next));
  }

  /// 删除。正在用的被删了，那个槽退回默认主题。
  Future<String?> delete(String id) async {
    if (_store.byId(id) == null) return '这套主题不能删（内置主题删不了）。';
    try {
      await _store.delete(id);
    } on Exception catch (e) {
      _publish();
      return '没删掉：${e.runtimeType}。';
    }
    if (_settings.getString(SettingKeys.themeLight, kDefaultLightThemeId) == id) await _settings.set(SettingKeys.themeLight, kDefaultLightThemeId);
    if (_settings.getString(SettingKeys.themeDark, kDefaultDarkThemeId) == id) await _settings.set(SettingKeys.themeDark, kDefaultDarkThemeId);
    _publish();
    return null;
  }

  /// 导入别人给的主题文本：校验过了才落盘，永远当一套新的存（不会盖掉已有的）。不自动选用。
  Future<ThemeOpResult> importText(String text) async {
    final r = decodeThemeText(text);
    if (!r.ok) return ThemeOpResult.fail(r.error!);
    return _add(r.theme!, r.theme!.name, author: r.theme!.author, background: r.background, notes: r.notes);
  }

  /// 导出成文本。[background] 给了就一起带上（由背景图那部分决定带不带）。找不到返回 null。
  String? exportText(String id, {ThemeBackground? background}) {
    final t = state.byId(id);
    return t == null ? null : encodeThemeText(t.copyWith(builtin: false), background: background);
  }

  Future<String?> _write(ThemeSpec theme) async {
    try {
      await _store.save(theme);
    } on Exception catch (e) {
      return '没存上：${e.runtimeType}。检查一下手机的存储空间。';
    }
    _publish();
    return null;
  }

  String? _checkName(String name) {
    final n = name.trim();
    if (n.isEmpty) return '给主题起个名字。';
    if (n.runes.length > kThemeNameMax) return '名字太长了，最多 $kThemeNameMax 个字。';
    return null;
  }

  /// 名字和别的主题撞了就在后面加 2、3……
  String _uniqueName(String base) {
    final taken = {for (final t in state.all) t.name};
    if (!taken.contains(base)) return base;
    for (var i = 2; ; i++) {
      final suffix = ' $i';
      final head = base.runes.length + suffix.length > kThemeNameMax ? String.fromCharCodes(base.runes.take(kThemeNameMax - suffix.length)) : base;
      if (!taken.contains('$head$suffix')) return '$head$suffix';
    }
  }

  String _newId() {
    for (;;) {
      final id = 'u-${ref.read(clockProvider)().microsecondsSinceEpoch.toRadixString(36)}-${(_seq++).toRadixString(36)}';
      if (_store.byId(id) == null) return id;
    }
  }
}

final themesProvider = NotifierProvider<ThemesNotifier, ThemesView>(ThemesNotifier.new);

/// 浅色时生效的主题。只有这一套换了 / 改了才通知。
final lightThemeProvider = Provider<ThemeSpec>((ref) => ref.watch(themesProvider.select((v) => v.light)));

/// 深色时生效的主题。
final darkThemeProvider = Provider<ThemeSpec>((ref) => ref.watch(themesProvider.select((v) => v.dark)));

/// 现在生效的主题。参数是“系统现在是不是深色”（外观模式选了跟随系统时才用得上；状态层看不到系统的开关，所以由界面传进来）。
final activeThemeProvider = Provider.family<ThemeSpec, bool>((ref, systemDark) {
  final dark = switch (ref.watch(themeModeProvider)) {
    AppThemeMode.light => false,
    AppThemeMode.dark => true,
    AppThemeMode.system => systemDark,
  };
  return ref.watch(dark ? darkThemeProvider : lightThemeProvider);
});
