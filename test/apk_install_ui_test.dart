// 应用内安装 APK 的界面测试（390×844）：
// - “安装”按钮：没允许 → 去设置 → 回来自动继续；回来还没允许；设置页打不开；成功拉起；各种失败的大白话。
// - 文件页：点安装包出信息面板（应用名、包名、版本、指纹、路径可复制、安装）；坏包讲人话且仍有基本信息；
//   二进制 / 大文件也出面板；面板里的重命名、删除就是原来那两项。
// - 打包结果卡：有“安装”，装的是外部目录那一份；打完自动滚动后“重新打包”不被顶栏盖住。
// 用假的安装器（test/support/fake_apk_installer.dart）和假的打包后端。LOPI_SHOTS=1 时出截图。
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/apkpack/apk_inspect.dart';
import 'package:lopicode/apkpack/apk_packer.dart';
import 'package:lopicode/apkpack/sign/apk_signer.dart';
import 'package:lopicode/build/apk_install_view.dart';
import 'package:lopicode/build/apk_installer.dart';
import 'package:lopicode/build/apk_output.dart';
import 'package:lopicode/build/build_controller.dart';
import 'package:lopicode/build/build_job_view.dart';
import 'package:lopicode/build/build_screen.dart';
import 'package:lopicode/build/local_pack_backend.dart';
import 'package:lopicode/core/project_store.dart';
import 'package:lopicode/core/templates.dart';
import 'package:lopicode/project_session.dart';
import 'package:lopicode/state/local_pack.dart';
import 'package:lopicode/ui/file_info_sheet.dart';
import 'package:lopicode/ui/files_tab.dart';
import 'package:lopicode/ui/shell.dart';
import 'package:lopicode/ui/top_bar.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;

import 'support/apkpack_kit.dart';
import 'support/apkpack_sign_support.dart';
import 'support/fake_apk_installer.dart';
import 'support/fake_local_pack.dart';
import 'support/harness.dart';

final bool writeShots = Platform.environment['LOPI_SHOTS'] == '1';
final String shotDir = Platform.environment['LOPI_SHOT_DIR'] ?? 'docs/screenshots';
bool fontsLoaded = false;

Future<void> shot(WidgetTester tester, String name) async {
  if (!writeShots || !fontsLoaded) return;
  final boundary = shotKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('$shotDir/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes!.buffer.asUint8List());
  });
}

void main() {
  late TestEnv env;
  late FakeApkInstaller installer;
  late Project project;
  late ProjectSession session;
  final copied = <String>[];

  setUpAll(() async => fontsLoaded = await loadRealFonts());

  Future<void> boot(WidgetTester tester) async {
    usePhoneViewport(tester);
    installer = FakeApkInstaller();
    apkInstallerOverride = installer;
    apkInspectOverride = (path) async => inspectApkSync(path); // 界面测试里不起后台 isolate
    copied.clear();
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied.add((call.arguments as Map)['text'] as String);
      return null;
    });
    await tester.runAsync(() async {
      env = await TestEnv.create();
      externalFilesDirOverride = () async => p.join(env.tmp.path, 'external');
      project = await env.services.projects.create('我的小站', ProjectTemplate.web);
      session = ProjectSession(env.services, project);
      await session.loadChat();
      await Future<void>.delayed(const Duration(milliseconds: 150));
    });
    addTearDown(() async {
      session.dispose();
      await env.dispose();
      apkInstallerOverride = null;
      apkInspectOverride = null;
      localPackBackendOverride = null;
      externalFilesDirOverride = null;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null);
    });
  }

  String message(WidgetTester tester) => tester.widget<Text>(find.byKey(const Key('apk-install-message'))).data!;
  Finder button(String label) => find.widgetWithText(FilledButton, label);

  Future<void> showButton(WidgetTester tester, {String path = '/x/app.apk'}) async {
    await tester.pumpWidget(
      appFor(
        env,
        Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: ApkInstallButton(path: path),
          ),
        ),
        font: kTestFont,
      ),
    );
    await settle(tester, rounds: 2);
  }

  Future<void> resume(WidgetTester tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await settle(tester, rounds: 2);
  }

  testWidgets('安装按钮：系统还没允许 → 去设置里允许 → 回到应用自动接着装', (tester) async {
    await boot(tester);
    installer.allowed = false;
    await showButton(tester);
    await tester.tap(button('安装'));
    await settle(tester, rounds: 2);
    expect(installer.installed, isEmpty);
    expect(message(tester), contains('系统还没允许'));
    expect(button('去设置里允许'), findsOneWidget);
    await shot(tester, 'install-01-need-permission-light');

    await tester.tap(button('去设置里允许'));
    await settle(tester, rounds: 2);
    expect(installer.settingsOpened, 1);
    expect(button('继续安装'), findsOneWidget);
    expect(message(tester), contains('回到这里，会自动接着装'));

    // 她在设置里打开了开关，回到应用
    installer.allowed = true;
    await resume(tester);
    expect(installer.installed, ['/x/app.apk'], reason: '回来以后不用再点，自己接着装');
    expect(message(tester), contains('已经交给系统安装器'));
    expect(message(tester), contains('看不到结果'), reason: '装没装成我们不知道，如实说');
    expect(button('再装一次'), findsOneWidget);

    // 之后再切出去再回来，不会又装一遍
    await resume(tester);
    expect(installer.installed.length, 1);
  });

  testWidgets('安装按钮：从设置回来开关还没打开——说清楚，能再去；也能手动点“继续安装”', (tester) async {
    await boot(tester);
    installer.allowed = false;
    await showButton(tester);
    await tester.tap(button('安装'));
    await settle(tester, rounds: 2);
    await tester.tap(button('去设置里允许'));
    await settle(tester, rounds: 2);
    await resume(tester);
    expect(installer.installed, isEmpty);
    expect(message(tester), contains('开关还没打开'));
    expect(button('去设置里允许'), findsOneWidget);

    // 再去一次；这次回来时系统没发“回到前台”的通知（有的系统是悬浮设置页）：手动点“继续安装”
    await tester.tap(button('去设置里允许'));
    await settle(tester, rounds: 2);
    installer.allowed = true;
    await tester.tap(button('继续安装'));
    await settle(tester, rounds: 2);
    expect(installer.installed, ['/x/app.apk']);
  });

  testWidgets('安装按钮：设置页打不开时告诉她自己去哪里开', (tester) async {
    await boot(tester);
    installer
      ..allowed = false
      ..settingsOpen = false;
    await showButton(tester);
    await tester.tap(button('安装'));
    await settle(tester, rounds: 2);
    await tester.tap(button('去设置里允许'));
    await settle(tester, rounds: 2);
    expect(message(tester), contains('没能替你打开'));
    expect(message(tester), contains('安装未知应用'));
    expect(button('继续安装'), findsOneWidget);
  });

  testWidgets('安装按钮：各种失败各有各的大白话，能再试', (tester) async {
    await boot(tester);
    await showButton(tester);
    final cases = {
      ApkInstallStatus.missing: '已经不在了',
      ApkInstallStatus.unreadable: '读不了',
      ApkInstallStatus.noInstaller: '没有找到系统安装器',
      ApkInstallStatus.copyFailed: '存储空间不够',
      ApkInstallStatus.notShareable: '挪到工作区里',
      ApkInstallStatus.blocked: '系统拒绝了',
      ApkInstallStatus.unsupported: '安卓手机',
      ApkInstallStatus.timeout: '没回应',
    };
    var first = true;
    for (final MapEntry(key: status, value: words) in cases.entries) {
      installer.outcome = status;
      await tester.tap(button(first ? '安装' : '再试一次'));
      await settle(tester, rounds: 2);
      expect(message(tester), contains(words), reason: '$status');
      expect(button('再试一次'), findsOneWidget);
      first = false;
    }
    expect(installer.installed, isEmpty);
    await shot(tester, 'install-02-failed-light');
    // 每种状态都有话说（包括以后新加的）
    for (final s in ApkInstallStatus.values) {
      expect(installStatusText(s), isNotEmpty);
    }
    expect(installStatusOf('launched'), ApkInstallStatus.launched);
    expect(installStatusOf('need_permission'), ApkInstallStatus.needPermission);
    expect(installStatusOf('没见过的字'), ApkInstallStatus.blocked);
    expect(installStatusOf(null), ApkInstallStatus.blocked);
  });

  group('文件页', () {
    late String apkFull;

    Future<void> showFiles(WidgetTester tester, {ThemeMode mode = ThemeMode.light}) async {
      await tester.pumpWidget(
        appFor(
          env,
          Scaffold(
            body: SafeArea(child: FilesTab(session: session)),
          ),
          mode: mode,
          font: kTestFont,
        ),
      );
      await settle(tester);
    }

    Future<void> seed(WidgetTester tester) async {
      await tester.runAsync(() async {
        final build = Directory(p.join(project.dir, 'build'))..createSync(recursive: true);
        final web = p.join(env.tmp.path, 'web');
        sampleStatic(web);
        apkFull = p.join(build.path, '我的小站-1.2.3-45.apk');
        await LocalApkPacker(
          template: realShell(),
          signer: KeyApkSigner(fixtureKey()),
        ).pack(requestFor(web, apkFull, appName: '我的小站', packageName: 'com.example.site', versionName: '1.2.3', versionCode: 45));
        File(p.join(build.path, '坏的.apk')).writeAsStringSync('这不是安装包' * 50);
        File(p.join(project.dir, 'logo.png')).writeAsBytesSync(Uint8List.fromList([0x89, 0x50, 0x4e, 0x47, 0, 0, 0, 13, 1, 2, 3]));
        File(p.join(project.dir, 'big.log')).writeAsStringSync('一行日志\n' * 120000); // 超过 1MB 的文字
      });
    }

    Future<void> open(WidgetTester tester, String name) async {
      await tester.scrollUntilVisible(find.text(name), 120, scrollable: find.byType(Scrollable).first);
      await tester.ensureVisible(find.text(name));
      await tester.tap(find.text(name));
      await settle(tester, rounds: 4);
    }

    String textOf(WidgetTester tester, String key) => tester.widget<Text>(find.byKey(Key(key))).data!;

    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      final suffix = mode == ThemeMode.light ? 'light' : 'dark';
      testWidgets('点安装包：出信息面板（应用名、包名、版本、指纹、路径），能直接装 ($suffix)', (tester) async {
        await boot(tester);
        await seed(tester);
        await showFiles(tester, mode: mode);
        await open(tester, '我的小站-1.2.3-45.apk');
        expect(find.textContaining('不能在编辑器里打开'), findsNothing, reason: '不再只弹一句话');
        expect(find.byKey(const Key('file-info')), findsOneWidget);
        expect(textOf(tester, 'file-info-title'), '我的小站');
        expect(textOf(tester, 'file-info-subtitle'), 'com.example.site');
        expect(textOf(tester, 'file-info-version'), '1.2.3（版本号 45）');
        expect(find.text(ApkBuildController.formatBytes(File(apkFull).lengthSync())), findsOneWidget);
        expect(find.text(fixtureKey().certSha256Hex), findsOneWidget);
        expect(find.textContaining('没有检查签名本身有没有效'), findsOneWidget);
        expect(find.text('build/我的小站-1.2.3-45.apk'), findsOneWidget);
        expect(find.text(apkFull), findsOneWidget);
        await shot(tester, 'install-03-apk-info-$suffix');

        // 路径可复制
        await tester.ensureVisible(find.byKey(const Key('file-info-full-path')));
        await tester.tap(find.descendant(of: find.byKey(const Key('file-info-full-path')), matching: find.byTooltip('复制')));
        await settle(tester, rounds: 2);
        expect(copied.last, apkFull);

        // 安装：交出去的是这个文件的完整路径
        await tester.ensureVisible(button('安装'));
        await tester.tap(button('安装'));
        await settle(tester, rounds: 2);
        expect(installer.installed, [apkFull]);
        expect(message(tester), contains('已经交给系统安装器'));
        await tester.pump(const Duration(seconds: 5)); // 等“已复制”的提示条收起来
      });
    }

    testWidgets('坏的安装包：讲人话，仍有大小和位置；“安装”降成“仍然试着安装”', (tester) async {
      await boot(tester);
      await seed(tester);
      await showFiles(tester);
      await open(tester, '坏的.apk');
      expect(textOf(tester, 'file-info-title'), '坏的.apk');
      expect(textOf(tester, 'file-info-subtitle'), startsWith('安卓安装包 · '));
      expect(textOf(tester, 'file-info-apk-error'), contains('不是安装包'));
      expect(find.text('build/坏的.apk'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, '仍然试着安装'), findsOneWidget);
      expect(button('安装'), findsNothing);
      await shot(tester, 'install-04-bad-apk-light');
    });

    testWidgets('二进制文件、超过 1MB 的文件：也出面板（类型、大小、位置），不再只弹一句话；没有“安装”', (tester) async {
      await boot(tester);
      await seed(tester);
      await showFiles(tester);
      await open(tester, 'logo.png');
      expect(textOf(tester, 'file-info-subtitle'), startsWith('图片 · '));
      expect(textOf(tester, 'file-info-why'), contains('二进制文件'));
      expect(find.byKey(const Key('apk-install')), findsNothing);
      expect(find.text('logo.png'), findsWidgets);
      await shot(tester, 'install-05-binary-light');
      Navigator.of(tester.element(find.byKey(const Key('file-info')))).pop();
      await settle(tester, rounds: 3);

      await open(tester, 'big.log');
      expect(textOf(tester, 'file-info-subtitle'), startsWith('文本文件 · '));
      expect(textOf(tester, 'file-info-why'), contains('超过 1MB'));
      Navigator.of(tester.element(find.byKey(const Key('file-info')))).pop();
      await settle(tester, rounds: 3);

      // 普通文字文件照旧进编辑器
      await open(tester, 'index.html');
      expect(find.byKey(const Key('file-info')), findsNothing);
      expect(find.text('已保存'), findsOneWidget);
    });

    testWidgets('面板里的删除、重命名就是原来那两项', (tester) async {
      await boot(tester);
      await seed(tester);
      await showFiles(tester);
      await open(tester, 'logo.png');
      await tester.ensureVisible(find.byKey(const Key('file-info-rename')));
      await tester.tap(find.byKey(const Key('file-info-rename')));
      await settle(tester, rounds: 3);
      expect(find.byKey(const Key('file-info')), findsNothing, reason: '面板先收起');
      await tester.enterText(find.byType(TextField).last, 'img/logo2.png');
      await tester.tap(find.text('保存'));
      await settle(tester, rounds: 4);
      expect(File(p.join(project.dir, 'img', 'logo2.png')).existsSync(), isTrue);
      expect(File(p.join(project.dir, 'logo.png')).existsSync(), isFalse);

      await open(tester, 'logo2.png');
      await tester.ensureVisible(find.byKey(const Key('file-info-delete')));
      await tester.tap(find.byKey(const Key('file-info-delete')));
      await settle(tester, rounds: 3);
      await tester.tap(find.widgetWithText(TextButton, '删除').last);
      await settle(tester, rounds: 4);
      expect(File(p.join(project.dir, 'img', 'logo2.png')).existsSync(), isFalse);
    });
  });

  group('打包结果卡', () {
    Future<void> packOnce(WidgetTester tester) async {
      localPackBackendOverride = FakeLocalPackBackend();
      await tester.pumpWidget(
        appFor(
          env,
          ShellScope(
            openDrawer: () {},
            go: (_) {},
            projectName: '我的小站',
            child: BuildScreen(session: session),
          ),
          font: kTestFont,
        ),
      );
      await settle(tester);
      final start = find.byKey(const Key('pack-start'));
      await tester.scrollUntilVisible(start, 160, scrollable: find.byType(Scrollable).first);
      await tester.ensureVisible(start);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(start);
      await settle(tester, rounds: 8);
      expect(env.services.container.read(localPackProvider(session)).phase, LocalPackPhase.done);
    }

    testWidgets('打完自动滚动后，“重新打包”整个在顶栏下面，不被顶栏的渐隐盖住；结果卡紧跟在它下面', (tester) async {
      await boot(tester);
      await packOnce(tester);
      // 不再手动滚：就看自动滚完停在哪
      final again = tester.getRect(find.widgetWithText(FilledButton, '重新打包'));
      final inset = PageBar.insetOf(tester.element(find.byType(ListView).first));
      expect(again.top, greaterThanOrEqualTo(inset), reason: '按钮上沿要在“状态栏 + 顶栏”以下（原来是 inset-40 左右，下半截透在顶栏的渐隐里）');
      expect(again.top, lessThan(inset + BarScrim.kTail + 40), reason: '也没有滚过头');
      final done = tester.getRect(find.text('打包完成'));
      expect(done.top, greaterThan(again.bottom));
      expect(done.bottom, lessThan(844), reason: '结果卡的开头在屏幕里');
      await shot(tester, 'install-06-pack-done-light');
    });

    testWidgets('结果卡上的“安装”：装的是外部目录里的那一份', (tester) async {
      await boot(tester);
      await packOnce(tester);
      final state = env.services.container.read(localPackProvider(session));
      expect(state.publicPath, isNotNull);
      final install = button('安装');
      await tester.scrollUntilVisible(install, 120, scrollable: find.byType(Scrollable).first);
      await tester.ensureVisible(install);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(install);
      await settle(tester, rounds: 2);
      expect(installer.installed, [state.publicPath]);
      expect(message(tester), contains('已经交给系统安装器'));
    });

    testWidgets('远程打包（GitHub / SSH）完成的卡上也有“安装”：装的是下载回来的那一份', (tester) async {
      await boot(tester);
      const apk = '/storage/emulated/0/Android/data/com.lopicode.app/files/apk/demo/app-release.apk';
      final job = _DoneJob()
        ..phase = BuildPhase.done
        ..log.add('APK 已保存（21.3 MB）')
        ..apkPath = apk;
      await tester.pumpWidget(
        appFor(
          env,
          Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: BuildJobCard(job: job),
            ),
          ),
          font: kTestFont,
        ),
      );
      await settle(tester, rounds: 2);
      expect(find.text('打包完成'), findsOneWidget);
      await tester.tap(button('安装'));
      await settle(tester, rounds: 2);
      expect(installer.installed, [apk]);
      expect(message(tester), contains('已经交给系统安装器'));
      // 没打完 / 没成的卡上没有“安装”
      final failed = _DoneJob()
        ..phase = BuildPhase.failed
        ..log.add('构建命令失败');
      await tester.pumpWidget(
        appFor(
          env,
          Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: BuildJobCard(key: UniqueKey(), job: failed),
            ),
          ),
          font: kTestFont,
        ),
      );
      await settle(tester, rounds: 2);
      expect(find.byKey(const Key('apk-install')), findsNothing);
    });

    testWidgets('这台设备没有外部目录：装工作区里的那一份', (tester) async {
      await boot(tester);
      externalFilesDirOverride = () async => null;
      await packOnce(tester);
      final state = env.services.container.read(localPackProvider(session));
      expect(state.publicPath, isNull);
      final install = button('安装');
      await tester.scrollUntilVisible(install, 120, scrollable: find.byType(Scrollable).first);
      await tester.ensureVisible(install);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(install);
      await settle(tester, rounds: 2);
      expect(installer.installed, [state.result!.path]);
    });
  });
}

class _DoneJob extends BuildJob {
  @override
  void cancel() {}
}
