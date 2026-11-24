// 设计约束（移动工作台 · 390×844）
// - 顶部标题左对齐，主操作靠右；用细分隔线和留白分组，不靠悬浮圆按钮和居中胶囊制造层级。
// - 底色两种：bg（主页面近白）和 canvas（设置类页面浅灰）；卡片只承载一组相关内容，圆角保持在 16–20。
// - 字号阶：12 / 14 / 16 / 18 / 20 / 24 / 30；字重只用 400 和 600。
// - 间距阶：4 / 8 / 12 / 16 / 24 / 32 / 48；一屏只突出一个主操作。
// - 正文 / 次要文字 / 强调色在各自底色上都保持足够对比度；次要信息用 muted 色。
import 'package:material_ui/material_ui.dart';

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
  static const double bubble = 16;
  static const double xl = 24;

  /// 分组卡片（设置页那种）。
  static const double card = 20;
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
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.bg,
    required this.canvas,
    required this.surface,
    required this.surfaceMuted,
    required this.text,
    required this.textMuted,
    required this.textFaint,
    required this.border,
    required this.accent,
    required this.accentSoft,
    required this.onAccent,
    required this.accentFill,
    required this.danger,
    required this.dangerSoft,
    required this.warning,
    required this.warningSoft,
    required this.codeBg,
  });

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

  /// 代码、终端、日志的底色。
  final Color codeBg;

  static const light = AppColors(
    bg: Color(0xFFFCFCFC),
    canvas: Color(0xFFF3F4F6),
    surface: Color(0xFFFFFFFF),
    surfaceMuted: Color(0xFFE9EAEC),
    text: Palette.neutral950,
    textMuted: Palette.neutral700,
    textFaint: Palette.neutral600,
    border: Color(0xFFE4E5E7),
    accent: Palette.primary500,
    accentSoft: Color(0xFFE6EEFB),
    accentFill: Palette.primary500,
    onAccent: Color(0xFFFFFFFF),
    danger: Palette.danger600,
    dangerSoft: Palette.danger100,
    warning: Palette.warning800,
    warningSoft: Palette.warning100,
    codeBg: Color(0xFFF3F4F6),
  );

  static const dark = AppColors(
    bg: Palette.neutral950,
    canvas: Color(0xFF0F0F14),
    surface: Color(0xFF1E1F25),
    surfaceMuted: Color(0xFF2C2D35),
    text: Palette.neutral100,
    textMuted: Palette.neutral300,
    textFaint: Palette.neutral400,
    border: Palette.neutral800,
    accent: Color(0xFF8FB4F5),
    accentSoft: Color(0xFF1B2A4A),
    accentFill: Color(0xFF3A72DC),
    onAccent: Color(0xFFFFFFFF),
    danger: Palette.danger300,
    dangerSoft: Color(0xFF3A1420),
    warning: Palette.warning300,
    warningSoft: Color(0xFF3A2A0C),
    codeBg: Color(0xFF1A1A21),
  );

  @override
  AppColors copyWith() => this;

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) => t < 0.5 || other is! AppColors ? this : other;
}

extension AppColorsX on BuildContext {
  AppColors get colors => Theme.of(this).extension<AppColors>()!;
}

/// 等宽字体族（代码、终端）。Android 自带 monospace；CJK 走系统回退。
const String kMonoFont = 'monospace';

/// 等宽字体里没有的字（中文）退到这个字体族。真机上系统会自动回退，
/// 这个名字只在截图测试里对应一个真实加载的字体。
const List<String> kMonoFallback = ['LopiCJK'];
