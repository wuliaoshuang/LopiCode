// 打包页接上真打包器以后的界面测试（390×844）：不用假后端，点“开始打包”背后跑的就是生产实现
// （真模板、现生成的真钥匙、真打包、真签名）。看的是界面上的结果对不对：进度、产物卡、失败原因、不适用的说明。
// 只在“进行中”那一步用一层很薄的包装把真打包的结果按住不放，好让界面停在进行中（打包本身还是真的）。
// LOPI_SHOTS=1 时顺手出截图：默认写到 docs/screenshots/，设了 LOPI_SHOT_DIR 就写到那里。
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/apkpack/apk_pack_contract.dart';
import 'package:lopicode/build/apk_output.dart';
import 'package:lopicode/build/build_screen.dart';
import 'package:lopicode/build/local_pack_backend.dart';
import 'package:lopicode/build/local_pack_backend_real.dart';
import 'package:lopicode/core/project_store.dart';
import 'package:lopicode/core/templates.dart';
import 'package:lopicode/project_session.dart';
import 'package:lopicode/state/local_pack.dart';
import 'package:lopicode/ui/shell.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;

import 'support/apkpack_kit.dart';
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

/// 真打包，只是打完以后先按住结果不交出去（界面就停在“进行中”）。
class _HeldRealBackend extends RealLocalPackBackend {
  _HeldRealBackend();
  final Completer<void> gate = Completer<void>();
  bool packed = false;

  @override
  Future<ApkPackResult> pack({required Uint8List template, required ApkSigningKey key, required ApkPackRequest request, void Function(ApkPackProgress progress)? onProgress}) async {
    final r = await super.pack(template: template, key: key, request: request, onProgress: onProgress);
    packed = true;
    await gate.future;
    return r;
  }
}

void main() {
  late TestEnv env;
  late Project project;
  late ProjectSession session;

  setUpAll(() async => fontsLoaded = await loadRealFonts());

  Future<void> boot(WidgetTester tester, {ProjectTemplate template = ProjectTemplate.web, LocalPackBackend? backend}) async {
    usePhoneViewport(tester);
    localPackBackendOverride = backend; // null ＝ 生产实现
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
    });
  }

  Future<void> show(WidgetTester tester, {ThemeMode mode = ThemeMode.light}) async {
    await tester.pumpWidget(
      appFor(
        env,
        ShellScope(
          openDrawer: () {},
          go: (_) {},
          projectName: '我的小站',
          child: BuildScreen(key: UniqueKey(), session: session),
        ),
        mode: mode,
        font: kTestFont,
      ),
    );
    await settle(tester);
  }

  LocalPackState state() => env.services.container.read(localPackProvider(session));

  /// 真的活在别的 isolate 里跑：让真实时间走一走再刷新界面，直到条件成立（最多 2 分钟）。
  Future<void> waitFor(WidgetTester tester, bool Function() ok) async {
    for (var i = 0; i < 1200 && !ok(); i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump(const Duration(milliseconds: 50));
    }
    await settle(tester, rounds: 4);
    expect(ok(), isTrue, reason: '等了 2 分钟还没等到');
  }

  Future<void> reveal(WidgetTester tester, Finder f) async {
    await tester.scrollUntilVisible(f, 160, scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(f);
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<void> tapStart(WidgetTester tester) async {
    await reveal(tester, find.byKey(const Key('pack-start')));
    await tester.tap(find.byKey(const Key('pack-start')));
    await tester.pump();
  }

  testWidgets('真打包：填好的表单 → 进行中 → 产物卡上的大小 / 包名 / 版本 / 位置都是真的', (tester) async {
    final held = _HeldRealBackend();
    await boot(tester, backend: held);
    await show(tester);
    await waitFor(tester, () => state().project != null);
    expect(find.text('这个项目可以本地打包'), findsOneWidget);
    await shot(tester, 'real-01-form-light');

    await tapStart(tester);
    await waitFor(tester, () => held.packed);
    expect(state().phase, LocalPackPhase.packing);
    await reveal(tester, find.text('正在打包'));
    expect(find.byKey(const Key('pack-step-detail')), findsOneWidget);
    await shot(tester, 'real-02-packing-light');

    held.gate.complete();
    await waitFor(tester, () => state().phase == LocalPackPhase.done);
    final r = state().result!;
    await reveal(tester, find.text('打包完成'));
    expect(tester.widget<Text>(find.byKey(const Key('pack-result-name'))).data, '我的小站');
    expect(tester.widget<Text>(find.byKey(const Key('pack-result-version'))).data, '1.0.0（版本号 1）');
    expect(find.text(r.packageName), findsWidgets);
    expect(find.text(r.path), findsOneWidget);
    expect(find.text(state().publicPath!), findsOneWidget);
    expect(File(r.path).lengthSync(), r.sizeBytes);
    expect(r.sizeBytes, greaterThan(20 * 1024), reason: '至少有模板那么大');
    expect(find.widgetWithText(FilledButton, '安装'), findsOneWidget);
    await shot(tester, 'real-03-done-light');
    await tester.drag(find.byType(ListView).first, const Offset(0, -400));
    await settle(tester, rounds: 2);
    await shot(tester, 'real-03b-done-bottom-light');

    // 界面上打出来的这个文件，官方工具认
    final tools = AndroidTools.find();
    if (tools.missing == null) {
      final copy = p.join(env.tmp.path, 'check.apk');
      File(copy).writeAsBytesSync(File(r.path).readAsBytesSync());
      final v = '${tools.run('apksigner', ['verify', '--verbose', '--print-certs', '--min-sdk-version', '21', copy]).stdout}';
      expect(v, contains('Verified using v1 scheme (JAR signing): true'));
      expect(v, contains('Verified using v2 scheme (APK Signature Scheme v2): true'));
      expect(v, contains('certificate SHA-256 digest: ${r.certSha256Hex}'));
      expect(tools.badging(copy), contains("package: name='${r.packageName}' versionCode='1' versionName='1.0.0'"));
    }
  }, timeout: const Timeout(Duration(minutes: 15)));

  testWidgets('真打包失败：项目里有个超大的文件 → 停在“收集网页文件”，原因写的是哪个文件、为什么', (tester) async {
    await boot(tester);
    await tester.runAsync(() async {
      final big = File(p.join(project.dir, 'video.mp4')).openSync(mode: FileMode.write);
      big.truncateSync(51 * 1024 * 1024); // 稀疏文件，不真占盘
      big.closeSync();
    });
    await show(tester);
    await waitFor(tester, () => state().project != null);
    await tapStart(tester);
    await waitFor(tester, () => state().phase == LocalPackPhase.failed);
    await reveal(tester, find.text('打包没成功'));
    final why = tester.widget<Text>(find.byKey(const Key('pack-failure'))).data!;
    expect(why, allOf(contains('video.mp4'), contains('太大了')));
    expect(find.textContaining('停在：'), findsOneWidget);
    await shot(tester, 'real-04-failed-light');
  }, timeout: const Timeout(Duration(minutes: 15)));

  testWidgets('不适用的项目（没有网页的空项目）：真识别给出的说明，指向远程打包', (tester) async {
    await boot(tester, template: ProjectTemplate.empty);
    await show(tester);
    await waitFor(tester, () => state().project != null);
    expect(find.text('这个项目不能本地打包'), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const Key('pack-not-applicable'))).data, allOf(contains('index.html'), contains('远程打包')));
    expect(find.byKey(const Key('pack-start')), findsNothing);
    expect(find.byKey(const Key('pack-switch-remote')), findsOneWidget);
    await shot(tester, 'real-05-not-applicable-light');
  });
}
