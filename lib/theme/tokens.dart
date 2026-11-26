// 设计约束（Refactoring UI · Workflow A）— 2026-11-23 按霜霜给的两张参考图改版
// - 只有手机一个目标：390×844，浅色 + 深色。
// - 色板：品牌蓝（primary，基色取自参考图二进度条的 #2962CB）、中性灰（neutral）、危险红、警告橙，
//   由 refactoring-ui 的 generate_palette.py 生成，界面里不出现表外的颜色；
//   正文 / 次要文字 / 强调色在各自底色上都用 check_contrast.py 验过 ≥ 4.5:1。
// - 底色两种：bg（对话等主页面，近白 #FCFCFC，参考图一）和 canvas（设置这类“卡片分组”页面，浅灰 #F3F4F6，参考图二）。
//   白卡片（surface）只放在 canvas 上；浅灰块（surfaceMuted，#E9EAEC）用于气泡和胶囊输入框。
// - 字号阶：12 / 14 / 16 / 18 / 20 / 24 / 30；字重只用 400 和 600。
// - 间距阶：4 / 8 / 12 / 16 / 24 / 32 / 48。
// - 圆角：6（小控件）/ 10（按钮、输入框）/ 16（底部面板）/ 20（气泡）/ 24（旧卡片）/ 28（分组大卡片）；胶囊和圆按钮是全圆。
// - 层级靠字重和颜色深浅拉开，不靠加大字号；次要信息用 muted 色。
import 'package:lopicode/appearance/theme_builtin.dart';
import 'package:lopicode/appearance/theme_fields.dart';
import 'package:lopicode/appearance/theme_spec.dart';
import 'package:material_ui/material_ui.dart';

export 'package:lopicode/appearance/theme_fields.dart' show BlockKey, CodeKey, LowcodeKey, MetricKey, UiKey;
export 'package:lopicode/appearance/theme_spec.dart' show ThemeSpec;

abstract final class Palette {
  static const primary100 = Color(0xFFEBF9FF);
  static const primary200 = Color(0xFFADE5FF);
  static const primary300 = Color(0xFF78CBF7);
  static const primary400 = Color(0xFF4E99E4);
  static const primary500 = Color(0xFF2962CB);
  static const primary600 = Color(0xFF1D4BB5);
  static const primary700 = Color(0xFF12359E);
  static const primary800 = Color(0xFF072186);
  static const primary900 = Color(0xFF00116B);

  static const neutral50 = Color(0xFFFCFDFE);
  static const neutral100 = Color(0xFFF8FAFB);
  static const neutral200 = Color(0xFFD8DCDF);
  static const neutral300 = Color(0xFFB8BEC1);
  static const neutral400 = Color(0xFF989EA4);
  static const neutral500 = Color(0xFF797D86);
  static const neutral600 = Color(0xFF656870);
  static const neutral700 = Color(0xFF50525B);
  static const neutral800 = Color(0xFF3C3D45);
  static const neutral900 = Color(0xFF27282F);
  static const neutral950 = Color(0xFF15151B);

  static const danger100 = Color(0xFFFFEBF3);
  static const danger300 = Color(0xFFFE7FB6);
  static const danger400 = Color(0xFFEE5986);
  static const danger600 = Color(0xFFC6212F);
  static const danger700 = Color(0xFFAB131E);
  static const danger900 = Color(0xFF6B0004);

  static const warning100 = Color(0xFFFFFEEB);
  static const warning300 = Color(0xFFFFE068);
  static const warning400 = Color(0xFFF7BC2E);
  static const warning700 = Color(0xFFA84C00);
  static const warning800 = Color(0xFF893300);
  static const warning900 = Color(0xFF6B1F00);
}

abstract final class Space {
  static const double x1 = 4;
  static const double x2 = 8;
  static const double x3 = 12;
  static const double x4 = 16;
  static const double x6 = 24;
  static const double x8 = 32;
  static const double x12 = 48;
}

abstract final class Radii {
  static const double sm = 6;
  static const double md = 10;
  static const double lg = 16;
  static const double bubble = 20;
  static const double xl = 24;

  /// 分组大卡片（设置页那种）。
  static const double card = 28;
}

abstract final class FontSize {
  static const double xs = 12;
  static const double sm = 14;
  static const double base = 16;
  static const double lg = 18;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xxxl = 30;
}

/// 语义色：界面代码只用这一层，不直接碰 [Palette]。
///
/// 颜色都从当前主题（[ThemeSpec]）来：`context.colors.xxx`。前 17 个是原来就有的名字，没改；
/// 后面是加主题系统时补的。别的几节（代码、终端、积木、低代码编辑器）用 `context.themeSpec` 取，见下面的 [ThemeSpecColors]。
@immutable
class AppColors extends ThemeExtension<AppColors> {
  AppColors.fromSpec(this.spec)
    : bg = spec.uiColor(UiKey.bg),
      canvas = spec.uiColor(UiKey.canvas),
      surface = spec.uiColor(UiKey.surface),
      surfaceMuted = spec.uiColor(UiKey.surfaceMuted),
      text = spec.uiColor(UiKey.text),
      textMuted = spec.uiColor(UiKey.textMuted),
      textFaint = spec.uiColor(UiKey.textFaint),
      border = spec.uiColor(UiKey.border),
      accent = spec.uiColor(UiKey.accent),
      accentSoft = spec.uiColor(UiKey.accentSoft),
      accentFill = spec.uiColor(UiKey.accentFill),
      onAccent = spec.uiColor(UiKey.onAccent),
      danger = spec.uiColor(UiKey.danger),
      dangerSoft = spec.uiColor(UiKey.dangerSoft),
      warning = spec.uiColor(UiKey.warning),
      warningSoft = spec.uiColor(UiKey.warningSoft),
      codeBg = spec.uiColor(UiKey.codeBg),
      onDanger = spec.uiColor(UiKey.onDanger),
      success = spec.uiColor(UiKey.success),
      successSoft = spec.uiColor(UiKey.successSoft),
      info = spec.uiColor(UiKey.info),
      infoSoft = spec.uiColor(UiKey.infoSoft),
      link = spec.uiColor(UiKey.link),
      selectedBg = spec.uiColor(UiKey.selectedBg),
      navBg = spec.uiColor(UiKey.navBg),
      navActive = spec.uiColor(UiKey.navActive),
      navInactive = spec.uiColor(UiKey.navInactive),
      barButtonBg = spec.uiColor(UiKey.barButtonBg),
      bubbleMineBg = spec.uiColor(UiKey.bubbleMineBg),
      bubbleMineText = spec.uiColor(UiKey.bubbleMineText),
      bubbleAgentBg = spec.uiColor(UiKey.bubbleAgentBg),
      bubbleAgentText = spec.uiColor(UiKey.bubbleAgentText),
      cardBg = spec.uiColor(UiKey.cardBg),
      inputBg = spec.uiColor(UiKey.inputBg),
      snackBg = spec.uiColor(UiKey.snackBg),
      snackText = spec.uiColor(UiKey.snackText),
      noticeBg = spec.uiColor(UiKey.noticeBg),
      noticeText = spec.uiColor(UiKey.noticeText),
      scrim = spec.uiColor(UiKey.scrim),
      shadow = spec.uiColor(UiKey.shadow),
      backdropScrim = spec.uiColor(UiKey.backdropScrim),
      chart1 = spec.uiColor(UiKey.chart1),
      chart2 = spec.uiColor(UiKey.chart2),
      chart3 = spec.uiColor(UiKey.chart3),
      chart4 = spec.uiColor(UiKey.chart4);

  /// 这些颜色出自哪份主题。
  final ThemeSpec spec;

  /// 主页面底色（对话、文件、终端……）。
  final Color bg;

  /// “卡片分组”页面（设置和它的子页）的底色，上面放白卡片。
  final Color canvas;
  final Color surface;
  final Color surfaceMuted;
  final Color text;
  final Color textMuted;
  final Color textFaint;
  final Color border;

  /// 强调色文字 / 图标。
  final Color accent;

  /// 强调色的浅底（选中态、标签）。
  final Color accentSoft;

  /// 实心强调按钮的底色和上面的文字色。
  final Color accentFill;
  final Color onAccent;
  final Color danger;
  final Color dangerSoft;
  final Color warning;
  final Color warningSoft;

  /// 代码块、日志的底色。
  final Color codeBg;

  // —— 下面是加主题系统时补的（各是什么见 lib/appearance/theme_fields.dart 的 kUiFields）——
  final Color onDanger;
  final Color success;
  final Color successSoft;
  final Color info;
  final Color infoSoft;
  final Color link;
  final Color selectedBg;
  final Color navBg;
  final Color navActive;
  final Color navInactive;
  final Color barButtonBg;
  final Color bubbleMineBg;
  final Color bubbleMineText;
  final Color bubbleAgentBg;
  final Color bubbleAgentText;
  final Color cardBg;
  final Color inputBg;
  final Color snackBg;
  final Color snackText;
  final Color noticeBg;
  final Color noticeText;

  /// 遮罩、阴影只定色相；深浅用 [scrimOf] / [shadowOf] 给。
  final Color scrim;
  final Color shadow;
  final Color backdropScrim;
  final Color chart1;
  final Color chart2;
  final Color chart3;
  final Color chart4;

  /// 阴影色：[alpha] 是这一处原本想要的深浅（0–1），再乘上主题的“阴影强弱”。
  Color shadowOf(double alpha) => shadow.withValues(alpha: (alpha * spec.metric(MetricKey.shadowStrength)).clamp(0.0, 1.0));

  /// 遮罩色：[alpha] 是这一处想要的深浅（0–1）。
  Color scrimOf(double alpha) => scrim.withValues(alpha: alpha);

  /// 圆角：把 [Radii] 里的档位按主题的圆角倍率算（默认主题倍率是 1，原样返回）。
  double radius(double base) => base * spec.metric(MetricKey.radiusScale);

  /// 间距：把 [Space] 里的档位按主题的密度倍率算。
  double space(double base) => base * spec.metric(MetricKey.spaceScale);

  /// 分隔线 / 细边的粗细。
  double get hairline => spec.metric(MetricKey.dividerWidth);

  /// 默认浅色 / 默认深色主题的颜色（不在主题里的地方、测试里用）。
  static final AppColors light = AppColors.fromSpec(kDefaultLightTheme);
  static final AppColors dark = AppColors.fromSpec(kDefaultDarkTheme);

  /// 外面可能没有应用主题的地方用（比如很靠外的出错提示）：有就用，没有就按明暗退回默认主题。
  static AppColors resolve(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<AppColors>() ?? (theme.brightness == Brightness.dark ? dark : light);
  }

  @override
  AppColors copyWith() => this;

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) => t < 0.5 || other is! AppColors ? this : other;
}

extension AppColorsX on BuildContext {
  AppColors get colors => Theme.of(this).extension<AppColors>()!;

  /// 当前生效的整份主题（代码、终端、积木、低代码编辑器的颜色从这里取）。
  ThemeSpec get themeSpec => AppColors.resolve(this).spec;
}

/// 从主题里按键取颜色。键在 lib/appearance/theme_fields.dart（[UiKey]、[CodeKey]、[BlockKey]、[LowcodeKey]…）。
/// 主题里万一缺了某个键（不该发生：读文件时都补齐了），退回同明暗默认主题的值。
extension ThemeSpecColors on ThemeSpec {
  Color _pick(String section, String key) => Color(this.section(section)[key] ?? defaultThemeFor(dark: dark).section(section)[key] ?? 0xFFFF00FF);

  Color uiColor(String key) => _pick('ui', key);
  Color codeColor(String key) => _pick('code', key);
  Color terminalColor(String key) => _pick('terminal', key);
  Color blockColor(String key) => _pick('blocks', key);
  Color lowcodeColor(String key) => _pick('lowcode', key);
}

/// 等宽字体族（代码、终端）。Android 自带 monospace；CJK 走系统回退。
const String kMonoFont = 'monospace';

/// 等宽字体里没有的字（中文）退到这个字体族。真机上系统会自动回退，
/// 这个名字只在截图测试里对应一个真实加载的字体。
const List<String> kMonoFallback = ['LopiCJK'];
