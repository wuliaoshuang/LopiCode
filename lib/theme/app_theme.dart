import 'package:lopicode/appearance/theme_builtin.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:material_ui/material_ui.dart';

/// 默认浅色 / 默认深色主题的 ThemeData。没有主题库可用的地方（启动失败页、不带应用外壳的测试台）用它；
/// 应用里一律用 [buildThemeData]，吃当前选中的主题。
ThemeData buildAppTheme(Brightness brightness, {String? fontFamily}) => buildThemeData(defaultThemeFor(dark: brightness == Brightness.dark), fontFamily: fontFamily);

final Expando<Map<String?, ThemeData>> _built = Expando();

/// 把一份主题翻译成 ThemeData。[fontFamily] 只在截图测试里传（加载真实字体）。
///
/// 同一份主题对象只翻译一次（结果记在主题对象上），所以在 build 里反复调用不贵。
ThemeData buildThemeData(ThemeSpec spec, {String? fontFamily}) => (_built[spec] ??= {})[fontFamily] ??= _build(spec, fontFamily);

ThemeData _build(ThemeSpec spec, String? fontFamily) {
  final brightness = spec.dark ? Brightness.dark : Brightness.light;
  final c = AppColors.fromSpec(spec);
  // 形状与密度：默认主题这三个都是 1，下面的式子算出来和原来的常量一模一样。
  final line = c.hairline;
  double r(double base) => c.radius(base);
  double sp(double base) => c.space(base);
  final scheme = ColorScheme(
    brightness: brightness,
    primary: c.accentFill,
    onPrimary: c.onAccent,
    secondary: c.accent,
    onSecondary: c.onAccent,
    error: c.danger,
    onError: c.onDanger,
    surface: c.surface,
    onSurface: c.text,
    onSurfaceVariant: c.textMuted,
    outline: c.border,
    outlineVariant: c.border,
    surfaceContainerHighest: c.surfaceMuted,
    surfaceContainerHigh: c.surfaceMuted,
    surfaceContainer: c.surface,
    surfaceContainerLow: c.surface,
    surfaceTint: Colors.transparent,
  );

  TextStyle t(double size, FontWeight weight, Color color, [double height = 1.4]) => TextStyle(fontSize: size, fontWeight: weight, color: color, height: height, letterSpacing: 0);
  const regular = FontWeight.w400;
  const strong = FontWeight.w600;

  final textTheme = TextTheme(
    headlineMedium: t(FontSize.xxl, strong, c.text, 1.25),
    headlineSmall: t(FontSize.xl, strong, c.text, 1.3),
    titleLarge: t(FontSize.lg, strong, c.text, 1.3),
    titleMedium: t(FontSize.base, strong, c.text),
    titleSmall: t(FontSize.sm, strong, c.text),
    bodyLarge: t(FontSize.base, regular, c.text, 1.5),
    bodyMedium: t(FontSize.sm, regular, c.text, 1.5),
    bodySmall: t(FontSize.xs, regular, c.textMuted),
    labelLarge: t(FontSize.sm, strong, c.text, 1.2),
    labelMedium: t(FontSize.xs, strong, c.textMuted, 1.2),
    labelSmall: t(FontSize.xs, regular, c.textMuted, 1.2),
  );

  final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(r(Radii.lg)));
  final inputBorder = OutlineInputBorder(
    borderRadius: BorderRadius.circular(r(Radii.lg)),
    borderSide: BorderSide(color: c.border, width: line),
  );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    fontFamily: fontFamily,
    scaffoldBackgroundColor: c.bg,
    textTheme: textTheme,
    extensions: [c],
    splashFactory: InkSparkle.splashFactory,
    dividerTheme: DividerThemeData(color: c.border, thickness: line, space: 1),
    appBarTheme: AppBarTheme(
      backgroundColor: c.bg,
      foregroundColor: c.text,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
      titleSpacing: sp(Space.x4),
      titleTextStyle: textTheme.titleLarge?.copyWith(fontFamily: fontFamily),
    ),
    cardTheme: CardThemeData(
      color: c.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(r(Radii.bubble)),
        side: BorderSide(color: c.border, width: line),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 44),
        padding: EdgeInsets.symmetric(horizontal: sp(Space.x4)),
        shape: shape,
        textStyle: textTheme.labelLarge?.copyWith(fontFamily: fontFamily),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 44),
        padding: EdgeInsets.symmetric(horizontal: sp(Space.x4)),
        foregroundColor: c.text,
        side: BorderSide(color: c.border, width: line),
        shape: shape,
        textStyle: textTheme.labelLarge?.copyWith(fontFamily: fontFamily),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(0, 40),
        foregroundColor: c.accent,
        shape: shape,
        textStyle: textTheme.labelLarge?.copyWith(fontFamily: fontFamily),
      ),
    ),
    iconTheme: IconThemeData(color: c.textMuted, size: 22),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: c.inputBg,
      isDense: true,
      contentPadding: EdgeInsets.symmetric(horizontal: sp(Space.x4), vertical: sp(Space.x3)),
      hintStyle: textTheme.bodyMedium?.copyWith(color: c.textFaint),
      labelStyle: textTheme.bodyMedium?.copyWith(color: c.textMuted),
      helperStyle: textTheme.bodySmall,
      helperMaxLines: 3,
      border: inputBorder,
      enabledBorder: inputBorder,
      focusedBorder: inputBorder.copyWith(borderSide: BorderSide(color: c.accentFill, width: 2)),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: c.surface,
      elevation: 0,
      height: 64,
      indicatorColor: c.accentSoft,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (s) => t(FontSize.xs, s.contains(WidgetState.selected) ? strong : regular, s.contains(WidgetState.selected) ? c.accent : c.textMuted, 1.2).copyWith(fontFamily: fontFamily),
      ),
      iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(size: 22, color: s.contains(WidgetState.selected) ? c.accent : c.textMuted)),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: c.surface,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      dragHandleColor: c.border,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(r(Radii.card)))),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: c.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(r(Radii.card))),
      titleTextStyle: textTheme.titleLarge?.copyWith(fontFamily: fontFamily),
      contentTextStyle: textTheme.bodyMedium?.copyWith(color: c.textMuted, fontFamily: fontFamily),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: c.snackBg,
      contentTextStyle: t(FontSize.sm, regular, c.snackText).copyWith(fontFamily: fontFamily),
      shape: shape,
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: c.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(r(Radii.bubble)),
        side: BorderSide(color: c.border, width: line),
      ),
      textStyle: textTheme.bodyMedium?.copyWith(fontFamily: fontFamily),
    ),
    listTileTheme: ListTileThemeData(
      iconColor: c.textMuted,
      titleTextStyle: textTheme.bodyLarge?.copyWith(fontFamily: fontFamily),
      subtitleTextStyle: textTheme.bodySmall?.copyWith(fontFamily: fontFamily),
      contentPadding: EdgeInsets.symmetric(horizontal: sp(Space.x4)),
    ),
    switchTheme: SwitchThemeData(
      trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? c.onAccent : c.surface),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? c.accentFill : c.border),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        visualDensity: VisualDensity.compact,
        side: WidgetStateProperty.all(BorderSide(color: c.border, width: line)),
        backgroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? c.accentSoft : c.surface),
        foregroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? c.accent : c.textMuted),
        textStyle: WidgetStateProperty.all(t(FontSize.sm, strong, c.text, 1.2).copyWith(fontFamily: fontFamily)),
        shape: WidgetStateProperty.all(shape),
      ),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: c.accentFill, linearTrackColor: c.surfaceMuted),
  );
}
