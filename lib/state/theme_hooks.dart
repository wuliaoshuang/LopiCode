// 主题界面和“背景图”那部分之间的对接，以及取色面板“最近用过”的记录。
//
// 背景图是另一块功能（lib/backdrop/、lib/state/backdrop_state.dart）。主题这边只在两处用得上它：
// 导出时“附带背景图”，导入时“文件里带的图要不要用”。两处都只认下面这个 [ThemeBackgroundBridge]。
// 两边的数据在主题这边的 [ThemeBackground] 上对齐：
//   导出：BackdropNotifier.exportForTheme 给的 Map → [themeBackgroundFromBackdrop] → encodeThemeBackground → 文件里的 `background` 一节
//   导入：文件里的 `background` 一节 → decodeThemeBackground（严格检查）→ [backdropDataFromTheme] → BackdropNotifier.applyThemeBackground
// 主题文件只带一张图：带“当前外观（浅色 / 深色）正在用的那一张”，所以三个函数都要说明是哪一边（dark）。
import 'dart:typed_data';

import 'package:lopicode/appearance/theme_json.dart';
import 'package:lopicode/state/app_providers.dart';
import 'package:lopicode/state/backdrop_state.dart';
import 'package:riverpod/riverpod.dart';

/// 导出时向背景图那边要图的结果：[data] 是可以直接放进主题文件 `background` 一节的对象
/// （键见 docs/themes-design.md 第四节）。带不了时 [data] 是 null，[error] 写原因。
/// [notes] 是带上了但要告诉用户的话（比如“图太大，缩小了”）。
class ThemeBackgroundExport {
  const ThemeBackgroundExport({this.data, this.error, this.notes = const []});
  final Map<String, Object?>? data;
  final String? error;
  final List<String> notes;
}

class ThemeBackgroundBridge {
  const ThemeBackgroundBridge({required this.hasImage, required this.export, required this.import});

  /// 浅色 / 深色外观现在有没有背景图（没有就不显示“附带背景图”）。
  final bool Function({required bool dark}) hasImage;

  /// 导出：把浅色 / 深色外观正在用的那张背景图交出来。
  final Future<ThemeBackgroundExport> Function({required bool dark}) export;

  /// 导入：把主题文件里 `background` 一节交给背景图那边启用（[dark]＝放到深色外观那一份）。
  /// 返回 null＝用上了；否则是一句失败原因。
  final Future<String?> Function(Map<String, Object?> background, {required bool dark}) import;
}

/// 背景图那边交出来的 Map（键见 lib/backdrop/backdrop_theme_bridge.dart）→ 主题这边的 [ThemeBackground]。
ThemeBackground themeBackgroundFromBackdrop(Map<String, Object?> d) {
  double n(String k, double fallback) => d[k] is num ? (d[k]! as num).toDouble() : fallback;
  int? i(String k) => d[k] is num ? (d[k]! as num).round() : null;
  final bytes = d['bytes'];
  final fit = d['fit'];
  return ThemeBackground(
    mime: d['mime'] is String ? d['mime']! as String : '',
    bytes: bytes is Uint8List ? bytes : Uint8List.fromList(bytes is List<int> ? bytes : const []),
    cropX: n('cropX', 0),
    cropY: n('cropY', 0),
    cropW: n('cropW', 1),
    cropH: n('cropH', 1),
    dim: n('dim', 0).clamp(0.0, 1.0),
    blur: n('blur', 0).clamp(0.0, 40.0),
    fit: fit is String && kThemeBackgroundFits.contains(fit) ? fit : null,
    tile: i('tile')?.clamp(10, 100),
    // 那边的约定：带了 maskColor 这个键、值是 null＝跟随主题；是数＝自选色；没带这个键＝没说
    maskFollowsTheme: d.containsKey('maskColor') ? d['maskColor'] == null : null,
    maskColor: i('maskColor'),
    brightness: i('brightness')?.clamp(-100, 100),
  );
}

/// 主题这边的 [ThemeBackground] → 背景图那边收的 Map。后加的四项没写（null）就不放进去，那边保持原样。
Map<Object?, Object?> backdropDataFromTheme(ThemeBackground b) => {
  'mime': b.mime,
  'bytes': b.bytes,
  'cropX': b.cropX,
  'cropY': b.cropY,
  'cropW': b.cropW,
  'cropH': b.cropH,
  'dim': b.dim,
  'blur': b.blur,
  if (b.fit != null) 'fit': b.fit,
  if (b.tile != null) 'tile': b.tile,
  if (b.maskFollowsTheme == true) 'maskColor': null else if (b.maskColor != null) 'maskColor': b.maskColor,
  if (b.brightness != null) 'brightness': b.brightness,
};

/// 背景图那边的对接口。背景设置一变它就换一份新的（界面跟着重画“附带背景图”那一项）。
/// 类型留着可空：测试里可以换成 null 看“没接背景图”时的样子。
final themeBackgroundBridgeProvider = Provider<ThemeBackgroundBridge?>((ref) {
  final settings = ref.watch(backdropProvider);
  final notifier = ref.watch(backdropProvider.notifier);
  return ThemeBackgroundBridge(
    hasImage: ({required dark}) => settings.loaded && settings.lookFor(dark: dark).hasImage,
    export: ({required dark}) async {
      final r = await notifier.exportForTheme(dark: dark);
      final d = r.data;
      if (d == null) return ThemeBackgroundExport(error: r.error ?? '背景图带不上。');
      return ThemeBackgroundExport(data: encodeThemeBackground(themeBackgroundFromBackdrop(d)), notes: r.notes);
    },
    import: (background, {required dark}) async {
      final (bg, why) = decodeThemeBackground(background);
      if (bg == null) return why ?? '背景图用不了。';
      return notifier.applyThemeBackground(backdropDataFromTheme(bg), dark: dark);
    },
  );
});

/// 取色面板“最近用过”最多记几个。
const int kRecentColorsMax = 12;

/// 存在设置文件里的键（一串用逗号隔开的 #AARRGGBB）。
const String kRecentColorsKey = 'ui.themeRecentColors';

/// 取色面板里“最近用过”的颜色（ARGB 整数，新的在前）。跨主题、跨次打开都记着。
class RecentColorsNotifier extends Notifier<List<int>> {
  @override
  List<int> build() {
    ref.watch(settingRevProvider(kRecentColorsKey));
    final raw = ref.watch(settingsStoreProvider).getString(kRecentColorsKey, '');
    final out = <int>[];
    for (final part in raw.split(',')) {
      final m = RegExp(r'^#([0-9A-Fa-f]{8})$').firstMatch(part.trim());
      if (m == null) continue;
      final c = int.parse(m[1]!, radix: 16);
      if (!out.contains(c)) out.add(c);
      if (out.length >= kRecentColorsMax) break;
    }
    return List.unmodifiable(out);
  }

  /// 记一个刚用过的颜色：挪到最前面，超出的丢掉。
  void remember(int argb) {
    final c = argb & 0xFFFFFFFF;
    final next = [c, ...state.where((x) => x != c)].take(kRecentColorsMax).toList();
    state = List.unmodifiable(next);
    ref.read(settingsStoreProvider).setLater(kRecentColorsKey, next.map((x) => '#${x.toRadixString(16).padLeft(8, '0').toUpperCase()}').join(','));
  }
}

final recentColorsProvider = NotifierProvider<RecentColorsNotifier, List<int>>(RecentColorsNotifier.new);
