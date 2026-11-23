import 'package:lopicode/app_services.dart';
import 'package:lopicode/theme/app_theme.dart';
import 'package:lopicode/ui/home_gate.dart';
import 'package:material_ui/material_ui.dart';

class LopiCodeApp extends StatelessWidget {
  const LopiCodeApp({super.key, required this.services, this.home, this.fontFamily, this.forceThemeMode});

  final AppServices services;

  /// 测试 / 截图用：直接打开某个页面。
  final Widget? home;
  final String? fontFamily;
  final ThemeMode? forceThemeMode;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      services: services,
      child: ListenableBuilder(
        listenable: services,
        builder: (context, _) => MaterialApp(
          title: 'LopiCode',
          debugShowCheckedModeBanner: false,
          theme: buildAppTheme(Brightness.light, fontFamily: fontFamily),
          darkTheme: buildAppTheme(Brightness.dark, fontFamily: fontFamily),
          themeMode: forceThemeMode ?? services.themeMode,
          home: home ?? const HomeGate(),
        ),
      ),
    );
  }
}
