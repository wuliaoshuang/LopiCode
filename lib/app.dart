import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lopicode/app_services.dart';
import 'package:lopicode/state/ui_prefs.dart';
import 'package:lopicode/theme/app_theme.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/error_guard.dart';
import 'package:lopicode/ui/home_gate.dart';
import 'package:material_ui/material_ui.dart';

class LopiCodeApp extends StatefulWidget {
  const LopiCodeApp({super.key, required this.services, this.home, this.fontFamily, this.forceThemeMode});

  final AppServices services;

  /// 测试 / 截图用：直接打开某个页面。
  final Widget? home;
  final String? fontFamily;
  final ThemeMode? forceThemeMode;

  @override
  State<LopiCodeApp> createState() => _LopiCodeAppState();
}

class _LopiCodeAppState extends State<LopiCodeApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    final services = widget.services;
    return UncontrolledProviderScope(
      container: services.container,
      // 应用外壳只订阅“外观模式”这一项：别的设置变了不会让整个应用重建。
      child: Consumer(
        builder: (context, ref, _) => MaterialApp(
          title: 'LopiCode',
          navigatorKey: _navigatorKey,
          // 有没被接住的错误时，在所有页面上面出一条可点开的提示（见 ui/error_guard.dart）。
          builder: (context, child) => ErrorNotice(
            navigatorKey: _navigatorKey,
            child: ColoredBox(
              color: context.colors.canvas,
              child: Center(
                child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 720), child: child ?? const SizedBox.shrink()),
              ),
            ),
          ),
          debugShowCheckedModeBanner: false,
          theme: buildAppTheme(Brightness.light, fontFamily: widget.fontFamily),
          darkTheme: buildAppTheme(Brightness.dark, fontFamily: widget.fontFamily),
          themeMode:
              widget.forceThemeMode ??
              switch (ref.watch(themeModeProvider)) {
                AppThemeMode.light => ThemeMode.light,
                AppThemeMode.dark => ThemeMode.dark,
                AppThemeMode.system => ThemeMode.system,
              },
          home: widget.home ?? const HomeGate(),
        ),
      ),
    );
  }
}
