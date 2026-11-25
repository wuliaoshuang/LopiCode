import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lopicode/app_services.dart';
import 'package:lopicode/state/themes_state.dart';
import 'package:lopicode/state/ui_prefs.dart';
import 'package:lopicode/theme/app_theme.dart';
import 'package:lopicode/theme/text_scale.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/error_guard.dart';
import 'package:lopicode/ui/home_gate.dart';
import 'package:lopicode/ui/keyboard_tap_dismiss.dart';
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
      // 应用外壳只订阅“外观模式”和“浅色 / 深色各用哪套主题”：别的设置变了不会让整个应用重建。
      // 主题那两项只有那一套真的换了 / 改了才通知；ThemeData 按主题对象记着，不会每次重算。
      child: Consumer(
        builder: (context, ref, _) => MaterialApp(
          title: 'LopiCode',
          navigatorKey: _navigatorKey,
          // 有没被接住的错误时，在所有页面上面出一条可点开的提示（见 ui/error_guard.dart）。
          builder: (context, child) => ErrorNotice(
            navigatorKey: _navigatorKey,
            // 点输入框外面的空白收键盘：全应用只在这里接一次（见 ui/keyboard_tap_dismiss.dart）。
            child: KeyboardTapDismiss(
              // 主题的“界面字号”倍率在这里统一生效（默认主题是 1，什么都不包）。
              child: ThemeTextScale(
                child: ColoredBox(
                  color: context.colors.canvas,
                  child: Center(
                    child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 720), child: child ?? const SizedBox.shrink()),
                  ),
                ),
              ),
            ),
          ),
          debugShowCheckedModeBanner: false,
          theme: buildThemeData(ref.watch(lightThemeProvider), fontFamily: widget.fontFamily),
          darkTheme: buildThemeData(ref.watch(darkThemeProvider), fontFamily: widget.fontFamily),
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
