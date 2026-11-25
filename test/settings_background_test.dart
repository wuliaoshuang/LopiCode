// 设置 › Agent › 后台与通知（390×844）：两个开关默认开、能关、关了真的存下来；通知权限的三种状态；
// 点权限行 / 系统设置行走到假宿主；打不开时说人话。
//   flutter test test/settings_background_test.dart
//   LOPI_SHOTS=1 flutter test test/settings_background_test.dart   # 截图到 docs/screenshots/（ka-…）
import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/agent/keep_alive.dart';
import 'package:lopicode/core/stores.dart';
import 'package:lopicode/ui/settings_background.dart';
import 'package:lopicode/ui/settings_screen.dart';
import 'package:material_ui/material_ui.dart';

import 'screens_test.dart' show fontsLoaded, shot;
import 'support/harness.dart';
import 'support/keep_alive_fakes.dart';

void main() {
  setUpAll(() async => fontsLoaded = await loadRealFonts());

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    final suffix = mode == ThemeMode.light ? 'light' : 'dark';
    late TestEnv env;
    late FakeKeepAliveHost host;

    Future<void> boot(WidgetTester tester, Widget home, {bool? allowed = true}) async {
      usePhoneViewport(tester);
      await tester.runAsync(() async => env = await TestEnv.create());
      host = FakeKeepAliveHost()..allowed = allowed;
      env.services.keepAlive.attach(host);
      addTearDown(() => tester.runAsync(env.dispose));
      await tester.pumpWidget(appFor(env, home, mode: mode, font: kTestFont));
      await settle(tester, rounds: 3);
    }

    bool sw(WidgetTester tester, String key) => tester.widget<Switch>(find.byKey(Key(key))).value;
    String permission(WidgetTester tester) => tester.widget<Text>(find.byKey(const Key('settings-notification-permission-value'))).data!;

    testWidgets('两个开关默认开；关掉会存下来，协调器马上认 ($suffix)', (tester) async {
      await boot(tester, const BackgroundSettingsScreen());
      expect(find.text('后台与通知'), findsOneWidget);
      expect(sw(tester, 'settings-keep-alive'), isTrue);
      expect(sw(tester, 'settings-notify-done'), isTrue);
      expect(permission(tester), '已允许');
      expect(tester.takeException(), isNull);
      await shot(tester, 'ka-01-background-$suffix');

      await tester.tap(find.text('Agent 干活时保持后台运行'));
      await settle(tester, rounds: 3);
      await tester.tap(find.text('做完时通知我'));
      await settle(tester, rounds: 3);
      expect(sw(tester, 'settings-keep-alive'), isFalse);
      expect(sw(tester, 'settings-notify-done'), isFalse);
      final s = env.services.settings;
      expect(s.getBool(SettingKeys.agentKeepAlive, true), isFalse);
      expect(s.getBool(SettingKeys.agentNotifyDone, true), isFalse);
      expect(env.services.keepAlive.keepEnabled(), isFalse);
      expect(env.services.keepAlive.notifyEnabled(), isFalse);
      // 关着保活时开一轮：不调原生
      final t = env.services.keepAlive.begin(title: 'x', root: true, cancel: () {});
      await tester.pump();
      expect(host.calls, isEmpty);
      t.end(TurnEnd.stopped);
      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets('通知没允许：写明“没允许”，点了先请系统询问、再打开系统的通知设置 ($suffix)', (tester) async {
      await boot(tester, const BackgroundSettingsScreen(), allowed: false);
      expect(permission(tester), '没允许');
      expect(find.textContaining('没允许通知也照样保持后台运行'), findsOneWidget);
      await shot(tester, 'ka-02-background-denied-$suffix');
      host.allowed = true; // 她在系统设置里打开了
      await tester.tap(find.byKey(const Key('settings-notification-permission')));
      await settle(tester, rounds: 3);
      expect(host.permissionRequests, 1);
      expect(host.openedNotificationSettings, 1);
      expect(permission(tester), '已允许', reason: '回来以后重新问了一次');
    });

    testWidgets('问不到权限（不是安卓）：如实写查不到，这一行点不了；系统设置打不开时说人话 ($suffix)', (tester) async {
      await boot(tester, const BackgroundSettingsScreen(), allowed: null);
      expect(permission(tester), '这台设备上查不到');
      await tester.tap(find.byKey(const Key('settings-notification-permission')));
      await settle(tester, rounds: 2);
      expect(host.openedNotificationSettings, 0);
      host.canOpenSettings = false;
      final row = find.byKey(const Key('settings-open-app-settings'));
      await tester.ensureVisible(row);
      await tester.tap(row);
      await settle(tester, rounds: 3);
      expect(host.openedAppSettings, 1);
      expect(find.textContaining('打不开系统的应用设置'), findsOneWidget);
    });

    testWidgets('通道抛错：页面照常显示，权限按查不到算 ($suffix)', (tester) async {
      await boot(tester, const BackgroundSettingsScreen());
      host.broken = true;
      await tester.pumpWidget(
        appFor(
          env,
          const BackgroundSettingsScreen(key: Key('again')),
          mode: mode,
          font: kTestFont,
        ),
      );
      await settle(tester, rounds: 3);
      expect(tester.takeException(), isNull);
      expect(sw(tester, 'settings-keep-alive'), isTrue);
    });

    testWidgets('一级页有“后台与通知”入口，右边写当前状态，点开是这一页 ($suffix)', (tester) async {
      await boot(tester, const SettingsScreen());
      final row = find.byKey(const Key('settings-background'));
      await tester.scrollUntilVisible(
        row,
        120,
        scrollable: find.descendant(of: find.byKey(const Key('settings-list')), matching: find.byType(Scrollable)).first,
      );
      await tester.ensureVisible(row);
      await settle(tester, rounds: 1);
      expect(find.descendant(of: row, matching: find.text('保活开 · 通知开')), findsOneWidget);
      await tester.runAsync(() => env.services.settings.set(SettingKeys.agentKeepAlive, false));
      await settle(tester, rounds: 2);
      expect(find.descendant(of: row, matching: find.text('保活关 · 通知开')), findsOneWidget);
      await tester.tap(row);
      await settle(tester, rounds: 4);
      expect(find.byType(BackgroundSettingsScreen), findsOneWidget);
    });
  }
}
