import 'package:lopicode/core/stores.dart';
import 'package:lopicode/state/app_providers.dart';
import 'package:riverpod/riverpod.dart';

/// 代码区域字号的范围、默认值和步进（2026-11-25 自定：10–24，默认 14，一步 1）。
const double kCodeFontMin = 10;
const double kCodeFontMax = 24;
const double kCodeFontDefault = 14;
const double kCodeFontStep = 1;

/// “小一号”的代码字：改动对比、步骤详情、完整输出、后台日志这些“想看再点”的次要内容比正式代码小这么多
/// （默认 14 − 2 = 12，和原来写死的 12 号一样），但不小于最小字号。
const double kCodeFontCompactGap = 2;
double compactCodeFont(double size) => (size - kCodeFontCompactGap).clamp(kCodeFontMin, kCodeFontMax).toDouble();

/// 把任意数夹回范围并取整到步进。
double clampCodeFont(num v) => ((v / kCodeFontStep).round() * kCodeFontStep).clamp(kCodeFontMin, kCodeFontMax).toDouble();

/// 代码区域的字号：文件编辑器、“看代码”、导出预览、原始 CSS 编辑共用一个值。
///
/// 捏合过程中用 [preview] 只改内存（界面立刻跟着变），松手时 [commit] 才写进设置文件，免得一次捏合写几十次盘。
class CodeFontNotifier extends Notifier<double> {
  @override
  double build() {
    ref.watch(settingRevProvider(SettingKeys.codeFontSize));
    // 旧版本 / 坏数据：不是数字就回默认，范围外的夹回来。
    final v = ref.watch(settingsStoreProvider).get<num>(SettingKeys.codeFontSize);
    return v == null ? kCodeFontDefault : clampCodeFont(v);
  }

  /// 只改内存里的值（捏合过程中）。
  void preview(double size) {
    final next = clampCodeFont(size);
    if (next != state) state = next;
  }

  /// 把现在的值写进设置文件（不等写完）。
  void commit() => ref.read(settingsStoreProvider).setLater(SettingKeys.codeFontSize, state);

  /// 改成某个值并存下来（设置页的加减号）。
  void set(double size) {
    preview(size);
    commit();
  }

  /// 在现在的值上加减（按现在的值算，连点两下不会只算一下）。
  void bump(double delta) => set(state + delta);

  /// 恢复默认（把键删掉）。
  void reset() => ref.read(settingsStoreProvider).setLater(SettingKeys.codeFontSize, null);
}

final codeFontProvider = NotifierProvider<CodeFontNotifier, double>(CodeFontNotifier.new);

/// 次要代码内容（对比、步骤详情、完整输出、后台日志）的字号：跟着“代码字号”走，小一号。
final compactCodeFontProvider = Provider<double>((ref) => compactCodeFont(ref.watch(codeFontProvider)));
