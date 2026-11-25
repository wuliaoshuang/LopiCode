// 主题界面和“背景图”那部分之间的挂载点，以及取色面板“最近用过”的记录。
//
// 背景图是另一块功能。主题这边只在两处用得上它：导出时“附带背景图”，导入时“文件里带的图要不要用”。
// 两处都只认下面这个 [ThemeBackgroundBridge]：**[themeBackgroundBridgeProvider] 返回 null（现在这样）时，
// 导出面板里没有“附带背景图”这一项，导入预览里只说明“带了图、这个版本用不了”。**
// 接上的办法：把 [themeBackgroundBridgeProvider] 的那一行换成返回一个真的 ThemeBackgroundBridge。
import 'package:lopicode/state/app_providers.dart';
import 'package:riverpod/riverpod.dart';

/// 导出时向背景图那边要图的结果：[data] 是可以直接放进主题文件 `background` 一节的对象
/// （键见 docs/themes-design.md 第四节：mime、data（base64）、crop、dim、blur；多带别的键也行，读的时候会跳过）。
/// 带不了时 [data] 是 null，[error] 写原因。[notes] 是带上了但要告诉用户的话（比如“图太大，缩小了”）。
class ThemeBackgroundExport {
  const ThemeBackgroundExport({this.data, this.error, this.notes = const []});
  final Map<String, Object?>? data;
  final String? error;
  final List<String> notes;
}

class ThemeBackgroundBridge {
  const ThemeBackgroundBridge({required this.hasImage, required this.export, required this.import});

  /// 现在有没有设背景图（没有就不显示“附带背景图”）。
  final bool Function() hasImage;

  /// 导出：把现在的背景图交出来。
  final Future<ThemeBackgroundExport> Function() export;

  /// 导入：把主题文件里 `background` 一节（已经过了主题这边的检查：格式、大小、图片文件头）交给背景图那边启用。
  /// 返回 null＝用上了；否则是一句失败原因。
  final Future<String?> Function(Map<String, Object?> background) import;
}

/// 背景图那边的对接口。**合并背景图功能时只改这一行**（现在是“没接上”）。
final themeBackgroundBridgeProvider = Provider<ThemeBackgroundBridge?>((ref) => null);

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
