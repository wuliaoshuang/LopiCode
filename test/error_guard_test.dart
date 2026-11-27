// 全局兜底：没被接住的异常 → 进日志 + 顶上出提示 → 点“查看”能看到并复制；某一块画不出来只换掉那一块；启动失败有整页说明。
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/core/crash_log.dart';
import 'package:lopicode/ui/error_guard.dart';
import 'package:lopicode/ui/settings_screen.dart';
import 'package:material_ui/material_ui.dart';

import 'support/harness.dart';

final bool writeShots = Platform.environment['LOPI_SHOTS'] == '1';
bool fontsLoaded = false;

Future<void> shot(WidgetTester tester, String name) async {
  if (!writeShots || !fontsLoaded) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(shotKey));
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    File('docs/screenshots/$name.png')
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync(data!.buffer.asUint8List());
  });
}

class _Bomb extends StatelessWidget {
  const _Bomb();
  @override
  Widget build(BuildContext context) => throw StateError('这一块画不出来 token=ghp_abcdefghijklmnopqrstuvwxyz0123456789');
}

void main() {
  setUpAll(() async => fontsLoaded = await loadRealFonts());
  setUp(CrashLog.instance.resetForTest);
  tearDown(CrashLog.instance.resetForTest);

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    final suffix = mode == ThemeMode.light ? 'light' : 'dark';

    testWidgets('后台任务抛的异常：记进日志，顶上出提示；“查看”打开错误日志页，可复制、可清空 ($suffix)', (tester) async {
      usePhoneViewport(tester);
      late TestEnv env;
      await tester.runAsync(() async => env = await TestEnv.create());
      addTearDown(env.dispose);
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String?;
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));

      await tester.pumpWidget(appFor(env, const SettingsScreen(), mode: mode, font: kTestFont));
      await settle(tester);
      expect(find.byKey(const Key('error-notice')), findsNothing);

      // 模拟一个没人接的异步异常（真机上由 PlatformDispatcher.onError / runZonedGuarded 送到这里）
      recordZoneError(StateError('保存失败：Authorization: Bearer sk-leak1234567890abcd'), StackTrace.current);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byKey(const Key('error-notice')), findsOneWidget);
      expect(find.text('出了点问题，刚才的操作可能没完成'), findsOneWidget);
      await shot(tester, '97-error-notice-$suffix');

      await tester.tap(find.byKey(const Key('error-notice-open')));
      await waitUntil(tester, () => find.byKey(const Key('error-log-text')).evaluate().isNotEmpty && find.text('错误日志').evaluate().length == 1, '错误日志页打开、转场走完');
      await settle(tester, rounds: 3);
      expect(find.text('错误日志'), findsOneWidget);
      expect(find.byKey(const Key('error-notice')), findsNothing, reason: '点了查看，提示收起');
      final shown = tester.widget<SelectableText>(find.byKey(const Key('error-log-text'))).data!;
      expect(shown, contains('保存失败'));
      expect(shown, contains('后台任务'));
      expect(shown, isNot(contains('sk-leak1234567890abcd')), reason: '日志里不许出现 Key');
      await shot(tester, '98-error-log-$suffix');

      await tester.tap(find.byKey(const Key('error-log-copy')));
      await settle(tester, rounds: 3);
      expect(copied, contains('保存失败'));
      expect(copied, isNot(contains('sk-leak1234567890abcd')));

      await tester.ensureVisible(find.byKey(const Key('error-log-clear')));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byKey(const Key('error-log-clear')));
      await settle(tester, rounds: 3);
      await tester.tap(find.text('清空').last);
      await waitUntil(tester, () => find.text('没有记录到错误').evaluate().isNotEmpty, '错误日志清空（日志文件删掉、页面刷新）');
      await settle(tester, rounds: 3);
      expect(find.text('没有记录到错误'), findsOneWidget);
      expect(CrashLog.instance.entries, isEmpty);
    });

    testWidgets('提示可以关掉；只是“记一笔”的事（存盘文件坏了已回退）不弹提示 ($suffix)', (tester) async {
      usePhoneViewport(tester);
      late TestEnv env;
      await tester.runAsync(() async => env = await TestEnv.create());
      addTearDown(env.dispose);
      await tester.pumpWidget(appFor(env, const SettingsScreen(), mode: mode, font: kTestFont));
      await settle(tester);

      CrashLog.instance.note('设置文件读不懂，已备份并改用默认值');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byKey(const Key('error-notice')), findsNothing);

      recordZoneError(Exception('x'), StackTrace.current);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byKey(const Key('error-notice')), findsOneWidget);
      await tester.tap(find.byKey(const Key('error-notice-close')));
      await tester.pump();
      expect(find.byKey(const Key('error-notice')), findsNothing);
      // 设置页里也有入口
      final list = find.byType(Scrollable).first;
      await tester.scrollUntilVisible(find.byKey(const Key('settings-error-log')), 300, scrollable: list);
      expect(find.byKey(const Key('settings-error-log')), findsOneWidget);
    });

    testWidgets('某一块界面画不出来：只换掉那一块，别的照常显示；错误进日志且不带 Key ($suffix)', (tester) async {
      usePhoneViewport(tester);
      late TestEnv env;
      await tester.runAsync(() async => env = await TestEnv.create());
      addTearDown(env.dispose);
      final restore = installErrorHandlers(forward: false);
      // 测试框架自己也挂了 onError（会把异常记成测试失败）；这里要验证的正是我们的处理器，所以放在它之后装、用完恢复。
      addTearDown(restore);

      await tester.pumpWidget(
        appFor(
          env,
          const Scaffold(body: Column(children: [Text('上面这块好好的'), _Bomb(), Text('下面这块也好好的')])),
          mode: mode,
          font: kTestFont,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 50));
      restore();

      expect(find.text('上面这块好好的'), findsOneWidget);
      expect(find.text('下面这块也好好的'), findsOneWidget);
      expect(find.byKey(const Key('broken-block')), findsOneWidget);
      expect(find.textContaining('这一块显示不出来'), findsOneWidget);
      expect(find.textContaining('ghp_abcdefghijklmnopqrstuvwxyz0123456789'), findsNothing);
      final entry = CrashLog.instance.entries.where((e) => e.message.contains('画不出来')).single;
      expect(entry.source, startsWith('界面'));
      expect(entry.message, isNot(contains('ghp_abcdefghijklmnopqrstuvwxyz0123456789')));
      expect(find.byKey(const Key('error-notice')), findsOneWidget);
      await shot(tester, '99-broken-block-$suffix');
    });

    testWidgets('连着报很多错：提示不会反复弹个不停（都在日志里） ($suffix)', (tester) async {
      usePhoneViewport(tester);
      late TestEnv env;
      await tester.runAsync(() async => env = await TestEnv.create());
      addTearDown(env.dispose);
      await tester.pumpWidget(appFor(env, const SettingsScreen(), mode: mode, font: kTestFont));
      await settle(tester);
      for (var i = 0; i < 5; i++) {
        recordZoneError(Exception('第 $i 个'), StackTrace.current);
      }
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.byKey(const Key('error-notice-close')));
      await tester.pump();
      for (var i = 5; i < 30; i++) {
        recordZoneError(Exception('第 $i 个'), StackTrace.current);
      }
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byKey(const Key('error-notice')), findsNothing, reason: '短时间里报得太多，不再打扰');
      expect(CrashLog.instance.entries.length, 30, reason: '但都记下来了');
    });

    testWidgets('启动失败：整页说明 + 可复制的错误 + 重试 ($suffix)', (tester) async {
      usePhoneViewport(tester);
      tester.platformDispatcher.platformBrightnessTestValue = mode == ThemeMode.dark ? Brightness.dark : Brightness.light;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      var retried = 0;
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String?;
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));

      await tester.pumpWidget(
        RepaintBoundary(
          key: shotKey,
          child: BootFailureApp(error: '[2026-11-23T20:00:00] 启动\nFileSystemException: 读不了设置目录', onRetry: () => retried++, fontFamily: kTestFont),
        ),
      );
      await settle(tester);
      expect(find.text('LopiCode 没能启动'), findsOneWidget);
      expect(find.textContaining('读不了设置目录'), findsOneWidget);
      await shot(tester, '100-boot-failure-$suffix');
      await tester.tap(find.byKey(const Key('boot-copy')));
      await settle(tester, rounds: 2);
      expect(copied, contains('读不了设置目录'));
      await tester.tap(find.byKey(const Key('boot-retry')));
      await tester.pump();
      expect(retried, 1);
    });
  }

  test('三道兜底装上后：界面框架的错误和平台层的错误都进日志；能恢复原样', () {
    final oldFlutter = FlutterError.onError;
    final oldPlatform = PlatformDispatcher.instance.onError;
    final restore = installErrorHandlers();
    try {
      expect(FlutterError.onError, isNot(same(oldFlutter)));
      final handled = PlatformDispatcher.instance.onError!(StateError('平台层的错'), StackTrace.current);
      expect(handled, isTrue, reason: '返回 true 表示已处理，应用不会因此退出');
      expect(CrashLog.instance.entries.last.message, contains('平台层的错'));
      expect(CrashLog.instance.entries.last.source, '后台任务');
    } finally {
      restore();
    }
    expect(FlutterError.onError, same(oldFlutter));
    expect(PlatformDispatcher.instance.onError, same(oldPlatform));
  });
}
