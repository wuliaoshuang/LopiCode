// 打包页（重做后）在 390×844 上的界面测试：三种方式、本地打包的表单 / 图标 / 权限 / 钥匙 / 进度 / 失败 / 成功。
// 用假的打包后端（test/support/fake_local_pack.dart）。
// LOPI_SHOTS=1 时顺手出截图：默认写到 docs/screenshots/，设了 LOPI_SHOT_DIR 就写到那里。
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/apkpack/apk_pack_contract.dart';
import 'package:lopicode/build/apk_icon.dart';
import 'package:lopicode/build/apk_icon_sheet.dart';
import 'package:lopicode/build/apk_output.dart';
import 'package:lopicode/build/build_screen.dart';
import 'package:lopicode/build/local_pack_backend.dart';
import 'package:lopicode/build/local_pack_form.dart';
import 'package:lopicode/build/signing_key_screen.dart';
import 'package:lopicode/core/project_store.dart';
import 'package:lopicode/core/stores.dart';
import 'package:lopicode/core/templates.dart';
import 'package:lopicode/project_session.dart';
import 'package:lopicode/ssh/ssh_config.dart';
import 'package:lopicode/state/local_pack.dart';
import 'package:lopicode/state/signing_key.dart';
import 'package:lopicode/ui/shell.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;

import 'support/fake_local_pack.dart';
import 'support/harness.dart';

final bool writeShots = Platform.environment['LOPI_SHOTS'] == '1';
final String shotDir = Platform.environment['LOPI_SHOT_DIR'] ?? 'docs/screenshots';
bool fontsLoaded = false;

Future<void> shot(WidgetTester tester, String name) async {
  expect(tester.takeException(), isNull, reason: '$name 渲染时出了异常');
  if (!writeShots || !fontsLoaded) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(shotKey));
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('$shotDir/$name.png');
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(data!.buffer.asUint8List());
  });
}

/// 造一张真的 PNG（引擎画的），给“选图标”用。
Future<Uint8List> makePng(int width, int height) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()), ui.Paint()..color = const ui.Color(0xFFE85D75));
  canvas.drawCircle(ui.Offset(width / 2, height / 2), (width < height ? width : height) * 0.32, ui.Paint()..color = const ui.Color(0xFFFFFFFF));
  final image = await recorder.endRecording().toImage(width, height);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

void main() {
  late TestEnv env;
  late FakeLocalPackBackend fake;
  late Project project;
  late ProjectSession session;
  final went = <ShellDest>[];
  final copied = <String>[];

  setUpAll(() async => fontsLoaded = await loadRealFonts());

  Future<void> boot(WidgetTester tester, {ProjectTemplate template = ProjectTemplate.web}) async {
    usePhoneViewport(tester);
    fake = FakeLocalPackBackend();
    localPackBackendOverride = fake;
    went.clear();
    copied.clear();
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied.add((call.arguments as Map)['text'] as String);
      return null;
    });
    await tester.runAsync(() async {
      env = await TestEnv.create();
      externalFilesDirOverride = () async => p.join(env.tmp.path, 'external');
      project = await env.services.projects.create('我的小站', template);
      session = ProjectSession(env.services, project);
      await session.loadChat();
      await Future<void>.delayed(const Duration(milliseconds: 150));
    });
    addTearDown(() async {
      session.dispose();
      await env.dispose();
      localPackBackendOverride = null;
      externalFilesDirOverride = null;
      pickIconImageOverride = null;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null);
    });
  }

  Future<void> show(WidgetTester tester, {ThemeMode mode = ThemeMode.light, bool fresh = true}) async {
    await tester.pumpWidget(
      appFor(
        env,
        ShellScope(
          openDrawer: () {},
          go: went.add,
          projectName: '我的小站',
          child: BuildScreen(key: fresh ? UniqueKey() : const Key('build'), session: session),
        ),
        mode: mode,
        font: kTestFont,
      ),
    );
    await settle(tester);
  }

  Future<void> reveal(WidgetTester tester, Finder f) async {
    await tester.scrollUntilVisible(f, 160, scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(f);
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<void> tapOn(WidgetTester tester, Finder f, {int rounds = 3}) async {
    await reveal(tester, f);
    await tester.tap(f);
    await settle(tester, rounds: rounds);
  }

  Future<void> toTop(WidgetTester tester) async {
    await tester.drag(find.byType(ListView).first, const Offset(0, 3000));
    await settle(tester, rounds: 2);
  }

  LocalPackState state() => env.services.container.read(localPackProvider(session));
  TextField field(WidgetTester tester, String key) => tester.widget<TextField>(find.byKey(Key(key)));

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    final suffix = mode == ThemeMode.light ? 'light' : 'dark';

    testWidgets('三种方式：默认是本地打包；切换后各自的表单都在；选择会记住 ($suffix)', (tester) async {
      await boot(tester);
      await show(tester, mode: mode);
      // 默认：本地打包
      expect(env.services.settings.getString(SettingKeys.apkBuildMode), '', reason: '没存过');
      expect(find.text('这个项目可以本地打包'), findsOneWidget);
      expect(find.textContaining('入口是 index.html'), findsOneWidget);
      expect(field(tester, 'pack-app-name').controller!.text, '我的小站');
      expect(field(tester, 'pack-package').controller!.text, defaultPackageName(project.id));
      expect(field(tester, 'pack-version-name').controller!.text, '1.0.0');
      expect(field(tester, 'pack-version-code').controller!.text, '1');
      expect(find.text('① 仓库'), findsNothing);
      expect(find.text('① 构建机'), findsNothing);
      expect(find.byTooltip('打开侧边栏'), findsOneWidget);
      await shot(tester, 'pack-01-local-$suffix');
      await reveal(tester, find.byKey(const Key('pack-start')));
      expect(find.text('已开：联网'), findsOneWidget);
      expect(find.text('还没有，第一次打包时自动生成'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, '开始打包'), findsOneWidget);
      await tester.drag(find.byType(ListView).first, const Offset(0, -3000)); // 滚到底再截：图标 / 权限 / 钥匙三行和主按钮
      await settle(tester, rounds: 2);
      await shot(tester, 'pack-02-local-bottom-$suffix');
      await toTop(tester);

      // GitHub Actions：原来的东西都在
      await tapOn(tester, find.byKey(const Key('pack-mode-github')));
      expect(env.services.settings.getString(SettingKeys.apkBuildMode), 'github');
      expect(find.textContaining('手机上跑不了 Android SDK 和 Gradle'), findsOneWidget);
      for (final text in ['① 仓库', '仓库', '分支', 'GitHub Token', '② 工作流', '工作流文件名', '③ 打包', '先把项目文件推送到仓库']) {
        await reveal(tester, find.text(text));
        expect(find.text(text), findsOneWidget, reason: text);
      }
      expect(find.textContaining('查看现成模板'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, '开始打包'), findsOneWidget);
      expect(find.text('这个项目可以本地打包'), findsNothing);
      await toTop(tester);
      await shot(tester, 'pack-10-github-$suffix');

      // SSH 构建机
      await tapOn(tester, find.byKey(const Key('pack-mode-ssh')));
      expect(env.services.settings.getString(SettingKeys.apkBuildMode), 'ssh');
      for (final text in ['① 构建机', '还没设置', '② 构建命令', '远程目录', '构建命令', 'APK 路径', '③ 打包', '先把项目文件传到构建机']) {
        await reveal(tester, find.text(text));
        expect(find.text(text), findsOneWidget, reason: text);
      }
      expect(find.byKey(const Key('ssh-build-start')), findsOneWidget);
      expect(find.text('① 仓库'), findsNothing);
      await toTop(tester);
      await shot(tester, 'pack-11-ssh-$suffix');

      // 切回本地：表单还在
      await tapOn(tester, find.byKey(const Key('pack-mode-local')));
      expect(env.services.settings.getString(SettingKeys.apkBuildMode), 'local');
      expect(field(tester, 'pack-app-name').controller!.text, '我的小站');

      // 重新打开页面：记得上次选的
      await tester.runAsync(() => env.services.settings.set(SettingKeys.apkBuildMode, 'ssh'));
      await show(tester, mode: mode);
      expect(find.text('① 构建机'), findsOneWidget, reason: '原来选了 SSH 的还是 SSH');
      expect(find.text('这个项目可以本地打包'), findsNothing);
    });

    testWidgets('本地打包：进度 → 成功的产物卡；失败（带是哪个输入）；截图 ($suffix)', (tester) async {
      await boot(tester);
      await show(tester, mode: mode);
      // 卡在“压缩”这一步看进度
      fake
        ..holdAt = ApkPackStep.zip
        ..packGate = Completer<void>();
      await tapOn(tester, find.byKey(const Key('pack-start')), rounds: 5);
      expect(state().phase, LocalPackPhase.packing);
      expect(find.text('正在打包'), findsOneWidget);
      expect(find.text('压缩'), findsOneWidget);
      expect(find.byKey(const Key('pack-step-detail')), findsOneWidget);
      expect(find.text('23 / 23'), findsOneWidget);
      expect(find.text('写出安装包'), findsOneWidget);
      await shot(tester, 'pack-05-packing-$suffix');
      // 打包中：主按钮灰着、表单锁住、三选一锁住
      expect(tester.widget<FilledButton>(find.byKey(const Key('pack-start'))).onPressed, isNull);
      expect(find.text('正在打包…'), findsOneWidget);
      await toTop(tester);
      expect(field(tester, 'pack-app-name').enabled, isFalse);
      await tester.tap(find.byKey(const Key('pack-mode-github')));
      await settle(tester, rounds: 2);
      expect(find.text('① 仓库'), findsNothing, reason: '打包中切不走');

      // 离开打包页再回来：进度还在
      await tester.pumpWidget(
        appFor(
          env,
          const Scaffold(body: Center(child: Text('别的页面'))),
          mode: mode,
          font: kTestFont,
        ),
      );
      await settle(tester, rounds: 2);
      expect(find.text('正在打包'), findsNothing);
      await show(tester, mode: mode);
      await reveal(tester, find.text('正在打包'));
      expect(find.text('23 / 23'), findsOneWidget);

      // 放行 → 成功
      fake.packGate!.complete();
      await settle(tester, rounds: 6);
      expect(state().phase, LocalPackPhase.done);
      await reveal(tester, find.text('打包完成'));
      expect(tester.widget<Text>(find.byKey(const Key('pack-result-name'))).data, '我的小站');
      expect(tester.widget<Text>(find.byKey(const Key('pack-result-version'))).data, '1.0.0（版本号 1）');
      expect(find.text('1.2 MB'), findsOneWidget);
      expect(find.text('23 个'), findsOneWidget);
      final workspacePath = p.join(project.dir, 'build', '我的小站-1.0.0-1.apk');
      final publicPath = p.join(env.tmp.path, 'external', 'apk', project.id, '我的小站-1.0.0-1.apk');
      expect(find.text(workspacePath), findsOneWidget);
      expect(find.text(publicPath), findsOneWidget);
      expect(File(workspacePath).existsSync() && File(publicPath).existsSync(), isTrue);
      expect(find.text('怎么装到手机上'), findsOneWidget);
      expect(find.textContaining('直接安装'), findsNothing, reason: '没有“直接安装”按钮（要新权限）');
      await tester.drag(find.byType(ListView).first, const Offset(0, -80));
      await settle(tester, rounds: 2);
      await shot(tester, 'pack-07-done-$suffix');
      // 复制路径、去文件页
      await reveal(tester, find.byKey(const Key('pack-result-public')));
      await tester.tap(find.descendant(of: find.byKey(const Key('pack-result-public')), matching: find.byTooltip('复制')));
      await settle(tester, rounds: 2);
      expect(copied.last, publicPath);
      await tapOn(tester, find.byKey(const Key('pack-open-files')));
      expect(went, [ShellDest.files]);
      await reveal(tester, find.textContaining('怎么装到手机上'));
      await tester.drag(find.byType(ListView).first, const Offset(0, -400));
      await tester.pump(const Duration(seconds: 5)); // 等“已复制”的提示条收起来
      await settle(tester, rounds: 2);
      await shot(tester, 'pack-08-done-bottom-$suffix');
      // 版本号自动加 1
      await reveal(tester, find.byKey(const Key('pack-version-code')));
      expect(field(tester, 'pack-version-code').controller!.text, '2');
      expect(find.widgetWithText(FilledButton, '重新打包'), findsOneWidget);

      // 再打一次：这次打包器说包名有问题
      fake
        ..holdAt = null
        ..packError = const ApkPackException('包名里的“app”这一段是系统保留的，换一个。', field: 'packageName')
        ..packErrorAt = ApkPackStep.manifest;
      await tapOn(tester, find.byKey(const Key('pack-start')), rounds: 6);
      expect(state().phase, LocalPackPhase.failed);
      await reveal(tester, find.text('打包没成功'));
      expect(find.text('停在：写入应用名、包名、版本、权限'), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const Key('pack-failure'))).data, contains('系统保留'));
      expect(find.text('去改包名'), findsOneWidget);
      await shot(tester, 'pack-06-failed-$suffix');
      await tapOn(tester, find.byKey(const Key('pack-fix')), rounds: 4);
      expect(field(tester, 'pack-package').focusNode!.hasFocus, isTrue, reason: '光标放进出问题的那一项');
      expect(
        find.descendant(of: find.byType(ListView).first, matching: find.textContaining('系统保留')),
        findsNWidgets(2),
        reason: '输入框下面也写着原因',
      );
      await shot(tester, 'pack-06b-failed-field-$suffix');
    });

    testWidgets('不适用的项目：说明原因，“改用远程打包”切过去 ($suffix)', (tester) async {
      await boot(tester);
      await tester.runAsync(() => File(p.join(project.dir, 'pubspec.yaml')).writeAsString('name: demo\n'));
      await show(tester, mode: mode);
      expect(find.text('这个项目不能本地打包'), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const Key('pack-not-applicable'))).data, contains('Flutter 项目'));
      expect(find.byKey(const Key('pack-app-name')), findsNothing, reason: '填了也没用的表单不出现');
      expect(find.byKey(const Key('pack-start')), findsNothing);
      await shot(tester, 'pack-03-not-applicable-$suffix');
      await tapOn(tester, find.byKey(const Key('pack-switch-remote')));
      expect(find.text('① 仓库'), findsOneWidget, reason: '没配过构建机：去 GitHub Actions');
      expect(env.services.settings.getString(SettingKeys.apkBuildMode), 'github');
      // 配过构建机的：去 SSH
      await tester.runAsync(() => const SshConfig(host: 'build.example.com', user: 'dev').save(env.services.settings));
      await toTop(tester); // 三选一在最上面：先滚回顶再点，不然它会被滚到悬浮顶栏的标题下面，点不到
      await tester.tap(find.byKey(const Key('pack-mode-local')));
      await settle(tester, rounds: 3);
      await tapOn(tester, find.byKey(const Key('pack-switch-remote')));
      expect(find.text('① 构建机'), findsOneWidget);
      expect(find.text('dev@build.example.com'), findsOneWidget);
    });

    testWidgets('权限面板、钥匙页：截图 ($suffix)', (tester) async {
      await boot(tester);
      await show(tester, mode: mode);
      await tapOn(tester, find.byKey(const Key('pack-perm-row')), rounds: 4);
      expect(find.text('相机'), findsOneWidget);
      expect(find.text('保持亮屏'), findsOneWidget);
      await shot(tester, 'pack-04-permissions-$suffix');
      await tester.tap(find.byKey(const Key('pack-perm-CAMERA')));
      await settle(tester, rounds: 2);
      expect(state().form.permissions, {'android.permission.INTERNET', 'android.permission.CAMERA'});
      await tester.binding.handlePopRoute();
      await settle(tester, rounds: 3);
      expect(find.text('已开：联网、相机'), findsOneWidget);

      await tapOn(tester, find.text('签名钥匙'), rounds: 4);
      expect(find.byType(SigningKeyScreen), findsOneWidget);
      expect(find.text('还没有钥匙'), findsOneWidget);
      expect(find.textContaining('换了钥匙，手机上已经装的应用就装不了升级包，要先卸载'), findsOneWidget);
      await shot(tester, 'pack-09a-key-none-$suffix');
      await tester.tap(find.byKey(const Key('key-generate')));
      await settle(tester, rounds: 4);
      expect(find.text('指纹 3556a3b1…'), findsOneWidget);
      expect(find.text('重新生成钥匙'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5)); // 等提示条收起来再截图
      await shot(tester, 'pack-09b-key-$suffix');
    });
  }

  testWidgets('每个输入的校验：错写在那一项下面，光标放到第一项有错的', (tester) async {
    await boot(tester);
    await show(tester);
    Future<void> type(String key, String text) async {
      await reveal(tester, find.byKey(Key(key)));
      await tester.enterText(find.byKey(Key(key)), text);
      await tester.pump();
    }

    await type('pack-app-name', ' ');
    await type('pack-package', 'Bad Name');
    await type('pack-version-name', '');
    await type('pack-version-code', '0');
    await tapOn(tester, find.byKey(const Key('pack-start')), rounds: 4);
    expect(fake.packs, 0);
    expect(state().phase, LocalPackPhase.idle);
    for (final text in ['应用名不能空着', '包名要像 com.example.app 这样：小写字母开头，用点分成至少两段', '版本名不能空着', '版本号要是大于 0 的整数']) {
      await reveal(tester, find.text(text));
      expect(find.text(text), findsOneWidget);
    }
    expect(field(tester, 'pack-app-name').focusNode!.hasFocus, isTrue);
    // 版本号只收数字
    await type('pack-version-code', '1a2');
    expect(field(tester, 'pack-version-code').controller!.text, '12');
    // 改对一项，那一项的错收起来，别的还在
    await type('pack-package', 'com.example.shop');
    expect(find.textContaining('包名要像'), findsNothing);
    expect(state().fieldErrors.keys, containsAll(['appName', 'versionName']));
    // 全改对：能打
    await type('pack-app-name', '小店');
    await type('pack-version-name', '2.1');
    await tapOn(tester, find.byKey(const Key('pack-start')), rounds: 6);
    expect(state().phase, LocalPackPhase.done);
    expect(fake.lastRequest!.packageName, 'com.example.shop');
    expect(fake.lastRequest!.appName, '小店');
    expect(fake.lastRequest!.versionCode, 12);
    expect(File(p.join(project.dir, 'build', '小店-2.1-12.apk')).existsSync(), isTrue);
  });

  testWidgets('表单每个工作区各记各的：重开页面、换工作区', (tester) async {
    await boot(tester);
    await show(tester);
    await tester.enterText(find.byKey(const Key('pack-app-name')), '小店');
    await settle(tester, rounds: 3);
    late Project other;
    late ProjectSession otherSession;
    await tester.runAsync(() async {
      other = await env.services.projects.create('另一个', ProjectTemplate.web);
      otherSession = ProjectSession(env.services, other);
      await otherSession.loadChat();
    });
    addTearDown(() => otherSession.dispose());
    await tester.pumpWidget(
      appFor(
        env,
        BuildScreen(key: UniqueKey(), session: otherSession),
        font: kTestFont,
      ),
    );
    await settle(tester);
    expect(field(tester, 'pack-app-name').controller!.text, '另一个');
    await show(tester);
    expect(field(tester, 'pack-app-name').controller!.text, '小店');
    final saved = await tester.runAsync(() => LocalPackFormStore(session.guard).file.readAsString());
    expect(saved, contains('小店'));
  });

  testWidgets('图标：选一张图 → 缩成五张；太小 / 打不开有大白话；恢复默认', (tester) async {
    await boot(tester);
    late Uint8List good;
    late Uint8List small;
    await tester.runAsync(() async {
      good = await makePng(400, 256);
      small = await makePng(120, 300);
    });
    await show(tester);
    await tapOn(tester, find.text('图标'), rounds: 4);
    expect(find.textContaining('默认图标'), findsWidgets);
    expect(find.byKey(const Key('pack-icon-reset')), findsNothing);

    Future<void> pick(Uint8List? bytes) async {
      pickIconImageOverride = () async => bytes;
      await tester.tap(find.byKey(const Key('pack-icon-pick')));
      await settle(tester, rounds: 8);
    }

    String status() => tester.widget<Text>(find.byKey(const Key('pack-icon-status'))).data!;

    await pick(small);
    expect(status(), '这张图太小了（120×300）。图标至少要 192×192，换一张大一点的。');
    expect(state().form.customIcon, isFalse);
    await pick(Uint8List.fromList(List.filled(64, 7)));
    expect(status(), contains('这张图打不开'));
    await pick(null); // 没选：什么都不变
    expect(state().form.customIcon, isFalse);

    await pick(good);
    expect(state().form.customIcon, isTrue);
    expect(state().icons.keys.toList()..sort(), kApkIconSizes);
    expect(status(), '用的是你选的图');
    await shot(tester, 'pack-04b-icon-light');
    // 每一张都是对应边长的正方形 PNG
    await tester.runAsync(() async {
      for (final size in kApkIconSizes) {
        final codec = await ui.instantiateImageCodec(state().icons[size]!);
        final frame = await codec.getNextFrame();
        expect((frame.image.width, frame.image.height), (size, size));
      }
      // 也存到了工作区的内部目录里（下次打开还在）
      expect(File(p.join(project.dir, '.lopicode', kLocalPackIconDir, '192.png')).existsSync(), isTrue);
    });
    // 重开页面：还是自己选的图；打包时交给打包器的是这五张
    await tester.binding.handlePopRoute();
    await settle(tester, rounds: 3);
    expect(find.text('用的是你选的图'), findsOneWidget);
    env.services.container.invalidate(localPackProvider(session));
    await show(tester);
    // 重新读要读表单 + 五张图，真实文件读写的步数多：等到读好为止，不靠固定的轮数（机器忙时不够）。
    for (var i = 0; i < 20 && !state().loaded; i++) {
      await settle(tester, rounds: 1);
    }
    expect(state().form.customIcon, isTrue);
    expect(state().icons.length, 5);
    await tapOn(tester, find.byKey(const Key('pack-start')), rounds: 6);
    expect(fake.lastRequest!.iconPngs.keys.toList()..sort(), kApkIconSizes);

    // 恢复默认
    await tapOn(tester, find.text('图标'), rounds: 4);
    await tester.tap(find.byKey(const Key('pack-icon-reset')));
    await settle(tester, rounds: 4);
    expect(state().form.customIcon, isFalse);
    expect(state().icons, isEmpty);
    expect(find.byKey(const Key('pack-icon-reset')), findsNothing);
  });

  testWidgets('图标处理本身：居中裁成正方形；空文件有说明', (tester) async {
    await tester.runAsync(() async {
      final icons = await makeApkIcons(await makePng(300, 200));
      expect(icons.keys.toList()..sort(), kApkIconSizes);
      await expectLater(makeApkIcons(Uint8List(0)), throwsA(isA<ApkIconException>()));
      await expectLater(makeApkIcons(await makePng(191, 500)), throwsA(isA<ApkIconException>().having((e) => e.message, 'message', contains('191×500'))));
      // 刚好 192：可以
      expect((await makeApkIcons(await makePng(192, 192))).length, 5);
    });
  });

  testWidgets('钥匙页：生成时有等待状态；导出备份（口令校验、存成文件）；重新生成和导入都要二次确认', (tester) async {
    await boot(tester);
    await show(tester);
    await tapOn(tester, find.text('签名钥匙'), rounds: 4);
    expect(
      tester.widget<InkWell>(find.descendant(of: find.byKey(const Key('key-export')), matching: find.byType(InkWell))).onTap,
      isNull,
      reason: '没有钥匙时不能导出',
    );

    // 生成：卡住看等待状态
    fake.keyGate = Completer<void>();
    await tester.tap(find.byKey(const Key('key-generate')));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
    expect(find.text('正在生成钥匙…'), findsOneWidget);
    expect(find.textContaining('可能要十几秒'), findsOneWidget);
    await shot(tester, 'pack-09c-key-generating-light');
    fake.keyGate!.complete();
    await settle(tester, rounds: 4);
    expect(find.text('指纹 3556a3b1…'), findsOneWidget);
    expect(find.textContaining('2026-11-26 生成'), findsOneWidget);

    // 导出：口令太短、两次不一样 → 报错；对了 → 存成文件
    await tester.tap(find.byKey(const Key('key-export')));
    await settle(tester, rounds: 3);
    await tester.enterText(find.byKey(const Key('key-pass')), 'short');
    await tester.enterText(find.byKey(const Key('key-pass-again')), 'short');
    await tester.tap(find.byKey(const Key('key-export-go')));
    await settle(tester, rounds: 2);
    expect(find.text('口令至少 $kKeyPassphraseMin 位'), findsNWidgets(1));
    await tester.enterText(find.byKey(const Key('key-pass')), 'correct horse');
    await tester.enterText(find.byKey(const Key('key-pass-again')), 'correct house');
    await tester.tap(find.byKey(const Key('key-export-go')));
    await settle(tester, rounds: 2);
    expect(find.text('两次输的不一样'), findsOneWidget);
    await shot(tester, 'pack-09d-key-export-light');
    await tester.enterText(find.byKey(const Key('key-pass-again')), 'correct horse');
    await tester.tap(find.byKey(const Key('key-export-go')));
    await settle(tester, rounds: 6);
    expect(find.text('备份好了'), findsOneWidget);
    final backups = Directory(p.join(project.dir, 'build')).listSync().whereType<File>().where((f) => p.basename(f.path).startsWith(kKeyBackupPrefix)).toList();
    expect(backups, hasLength(1));
    final backupText = backups.single.readAsStringSync();
    expect(backupText, startsWith('LOPIKEY1:'));
    expect(find.text(backups.single.path), findsOneWidget);
    expect(File(p.join(env.tmp.path, 'external', 'apk', project.id, p.basename(backups.single.path))).existsSync(), isTrue, reason: '也抄了一份到手机存储');
    await tester.tap(find.byKey(const Key('key-backup-copy')));
    await settle(tester, rounds: 2);
    expect(copied.last, backupText);
    await shot(tester, 'pack-09e-key-exported-light');
    // 口令没有进普通设置文件
    final settingsText = env.services.settings.file.existsSync() ? env.services.settings.file.readAsStringSync() : '';
    expect(settingsText, isNot(contains('correct horse')));
    await tester.binding.handlePopRoute();
    await settle(tester, rounds: 3);

    // 重新生成：先确认；取消就不动
    await tester.tap(find.byKey(const Key('key-regenerate')));
    await settle(tester, rounds: 2);
    expect(find.text('重新生成钥匙？'), findsOneWidget);
    expect(find.textContaining('要先卸载再装'), findsOneWidget);
    await shot(tester, 'pack-09f-key-regenerate-confirm-light');
    await tester.tap(find.text('取消'));
    await settle(tester, rounds: 2);
    expect(fake.generated, 1);
    await tester.tap(find.byKey(const Key('key-regenerate')));
    await settle(tester, rounds: 2);
    await tester.tap(find.text('换掉，重新生成'));
    await settle(tester, rounds: 4);
    expect(fake.generated, 2);
    expect(find.text('指纹 aa11bb22…'), findsOneWidget);

    // 导入刚才的备份：空着不行；口令不对有原因；对了先确认（会换掉现在这把）
    await tester.tap(find.byKey(const Key('key-import')));
    await settle(tester, rounds: 3);
    await tester.tap(find.byKey(const Key('key-import-go')));
    await settle(tester, rounds: 2);
    expect(find.textContaining('先把备份内容贴进来'), findsOneWidget);
    expect(find.text('输导出时设的口令'), findsOneWidget);
    // 从工作区选文件
    await tester.tap(find.byKey(const Key('key-import-file')));
    await settle(tester, rounds: 4);
    expect(find.text('选一份备份'), findsOneWidget);
    await tester.tap(find.text('build/${p.basename(backups.single.path)}'));
    await settle(tester, rounds: 4);
    expect(field(tester, 'key-import-text').controller!.text, backupText);
    await tester.enterText(find.byKey(const Key('key-import-pass')), 'wrong pass!');
    await tester.tap(find.byKey(const Key('key-import-go')));
    await settle(tester, rounds: 2);
    expect(find.text('换掉现在的钥匙？'), findsOneWidget);
    await tester.tap(find.text('换掉，导入'));
    await settle(tester, rounds: 4);
    expect(find.text('口令不对。'), findsOneWidget);
    await shot(tester, 'pack-09g-key-import-light');
    expect(env.services.container.read(signingKeyProvider).shortFingerprint, 'aa11bb22', reason: '没导入成，钥匙不动');
    await tester.enterText(find.byKey(const Key('key-import-pass')), 'correct horse');
    await tester.tap(find.byKey(const Key('key-import-go')));
    await settle(tester, rounds: 2);
    await tester.tap(find.text('取消'));
    await settle(tester, rounds: 2);
    expect(env.services.container.read(signingKeyProvider).shortFingerprint, 'aa11bb22', reason: '取消确认：不动');
    await tester.tap(find.byKey(const Key('key-import-go')));
    await settle(tester, rounds: 2);
    await tester.tap(find.text('换掉，导入'));
    await settle(tester, rounds: 4);
    expect(find.text('指纹 3556a3b1…'), findsOneWidget, reason: '导入后回到钥匙页，是原来那把');
    // 回到打包页：那一行跟着变
    await tester.binding.handlePopRoute();
    await settle(tester, rounds: 3);
    expect(find.textContaining('已有（指纹 3556a3b1…'), findsOneWidget);
  });

  testWidgets('第一次打包：进度里先有“生成签名钥匙”这一步和一句解释', (tester) async {
    await boot(tester);
    await show(tester);
    fake.keyGate = Completer<void>();
    await tapOn(tester, find.byKey(const Key('pack-start')), rounds: 4);
    expect(state().phase, LocalPackPhase.preparingKey);
    expect(find.text('生成签名钥匙'), findsOneWidget);
    expect(find.textContaining('只有第一次要做'), findsOneWidget);
    await shot(tester, 'pack-05a-preparing-key-light');
    fake.keyGate!.complete();
    await settle(tester, rounds: 6);
    expect(state().phase, LocalPackPhase.done);
    expect(find.text('生成签名钥匙'), findsNothing);
  });

  testWidgets('打包器说权限有问题：权限那一行写着原因，失败卡上有“去改权限”，点了开权限面板', (tester) async {
    await boot(tester);
    await show(tester);
    fake
      ..packError = const ApkPackException('权限表里没有 android.permission.FOO。', field: 'permissions')
      ..packErrorAt = ApkPackStep.check;
    await tapOn(tester, find.byKey(const Key('pack-start')), rounds: 6);
    expect(state().phase, LocalPackPhase.failed);
    expect(state().fieldErrors['permissions'], contains('权限表里没有'));
    expect(find.descendant(of: find.byKey(const Key('pack-perm-row')), matching: find.textContaining('权限表里没有')), findsOneWidget);
    await reveal(tester, find.byKey(const Key('pack-fix')));
    expect(find.text('去改权限'), findsOneWidget);
    await tapOn(tester, find.byKey(const Key('pack-fix')), rounds: 4);
    expect(find.byKey(const Key('pack-perm-CAMERA')), findsOneWidget);
    await tester.tap(find.byKey(const Key('pack-perm-CAMERA')));
    await settle(tester, rounds: 3);
    expect(state().fieldErrors.containsKey('permissions'), isFalse);
  });

  testWidgets('钥匙读不出来：打包失败卡上有“去看签名钥匙”，点了进钥匙页', (tester) async {
    await boot(tester);
    await tester.runAsync(() => env.services.secrets.write(SecretKeys.apkSigningKey, '坏的'));
    await show(tester);
    await reveal(tester, find.text('读不出来，点进去处理'));
    await tapOn(tester, find.byKey(const Key('pack-start')), rounds: 5);
    expect(state().phase, LocalPackPhase.failed);
    await reveal(tester, find.text('还没开始打就停了'));
    await tapOn(tester, find.byKey(const Key('pack-fix')), rounds: 4);
    expect(find.byType(SigningKeyScreen), findsOneWidget);
    expect(find.textContaining('有备份就导入备份'), findsOneWidget);
  });
}
