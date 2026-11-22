// 设计约束（Refactoring UI · Workflow A）
// - 只有手机一个目标：390×844，浅色 + 深色。
// - 色板：品牌绿（primary）、冷灰（neutral）、危险红、警告橙，各 9 阶，
//   由 refactoring-ui 的 generate_palette.py 生成，界面里不出现表外的颜色。
// - 字号阶：12 / 14 / 16 / 18 / 20 / 24 / 30；字重只用 400 和 600。
// - 间距阶：4 / 8 / 12 / 16 / 24 / 32 / 48。
// - 圆角：6（小控件）/ 10（卡片、输入框）/ 16（底部面板）。
// - 层级靠字重和颜色深浅拉开，不靠加大字号；次要信息用 muted 色。
import 'package:material_ui/material_ui.dart';

abstract final class Palette {
  static const primary100 = Color(0xFFEBFFFF);
  static const primary200 = Color(0xFF9BFFF8);
  static const primary300 = Color(0xFF5DEEDB);
  static const primary400 = Color(0xFF29D2B2);
  static const primary500 = Color(0xFF0F9D7A);
  static const primary600 = Color(0xFF0A9267);
  static const primary700 = Color(0xFF058654);
  static const primary800 = Color(0xFF017B43);
  static const primary900 = Color(0xFF006B32);

  static const neutral50 = Color(0xFFFAFDFF);
  static const neutral100 = Color(0xFFF6FBFD);
  static const neutral200 = Color(0xFFD3DEE4);
  static const neutral300 = Color(0xFFB1C0C8);
  static const neutral400 = Color(0xFF919EAC);
  static const neutral500 = Color(0xFF707A8F);
  static const neutral600 = Color(0xFF5C6479);
  static const neutral700 = Color(0xFF494E62);
  static const neutral800 = Color(0xFF35394C);
  static const neutral900 = Color(0xFF222435);
  static const neutral950 = Color(0xFF11121F);

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

  final Color bg;
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
    bg: Palette.neutral100,
    surface: Color(0xFFFFFFFF),
    surfaceMuted: Color(0xFFEAF1F5),
    text: Palette.neutral900,
    textMuted: Palette.neutral600,
    textFaint: Palette.neutral600,
    border: Palette.neutral200,
    accent: Palette.primary800,
    accentSoft: Color(0xFFDDF5EC),
    accentFill: Palette.primary700,
    onAccent: Color(0xFFFFFFFF),
    danger: Palette.danger600,
    dangerSoft: Palette.danger100,
    warning: Palette.warning800,
    warningSoft: Palette.warning100,
    codeBg: Palette.neutral50,
  );

  static const dark = AppColors(
    bg: Palette.neutral950,
    surface: Palette.neutral900,
    surfaceMuted: Palette.neutral800,
    text: Palette.neutral100,
    textMuted: Palette.neutral300,
    textFaint: Palette.neutral400,
    border: Palette.neutral700,
    accent: Palette.primary300,
    accentSoft: Color(0xFF12382F),
    accentFill: Palette.primary400,
    onAccent: Palette.neutral950,
    danger: Palette.danger300,
    dangerSoft: Color(0xFF3A1420),
    warning: Palette.warning300,
    warningSoft: Color(0xFF3A2A0C),
    codeBg: Color(0xFF191A2A),
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
