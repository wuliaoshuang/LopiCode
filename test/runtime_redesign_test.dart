// “运行环境”页重排（2026-11-25 真机反馈第三轮第 2 条）在 390×844 上的检查，浅色 + 深色。
//   LOPI_SHOTS=1 flutter test --no-pub test/runtime_redesign_test.dart   # 同时把截图写到 docs/screenshots/rt3-*.png
// 全部用假的启动器和临时目录：不下载、不联网。
//
// 功能对照清单（改版前页面上的每个可操作项和每种状态 → 现在在哪儿；“旧”= test/runtime_screens_test.dart 里原有的用例守着）
//  操作
//   1 安装运行环境 / 继续下载（已有 x）      → 状态卡主按钮 runtime-install（旧）；上次失败且没有残留时文字是“重新安装”（本文件）
//   2 取消安装                               → 状态卡 runtime-cancel（旧）
//   3 重新尝试进入 Ubuntu                    → 状态卡 runtime-retry-launch（旧）
//   4 选系统包下载源 / 选 apt 下载源         → “下载源”两行 rootfs-source / apt-mirror，点开底部面板单选（本文件）；安装中不能改（本文件）
//   5 安装某个语言 / 工具                    → 行尾小按钮 pack-<id>-install，整行也能点（本文件）
//   6 停止正在装的语言                       → 行尾小按钮 pack-<id>-stop（本文件；改版前这个按钮没有 key）
//   7 开始诊断 / 重新诊断                    → “诊断”一行 runtime-diagnose（旧 + 本文件）
//   8 复制诊断结果                           → 报告下面 diag-copy（旧）
//   9 复制日志                               → 日志下面 runtime-log-copy（本文件）
//  10 卸载运行环境 / 删除没下完的文件 + 确认 → 最后一行危险行 runtime-uninstall（旧）；安装中、装语言中不能点（本文件）
//  状态
//   a 未安装（空间说明、剩余空间）           → 旧
//   b 下载中 / 校验中 / 解压中（进度条、文字）→ 旧；多了百分比 runtime-percent（本文件）
//   c 安装失败（真正原因）                   → 旧
//   d 已安装                                 → 旧；多了占用空间 runtime-usage（现数的，数不出来不显示；本文件）
//   e 已下载但进不去（安装包缺启动器）       → 旧（未安装时）；已安装时“语言与工具”里是一条说明（本文件）
//   f 连续启动失败（原因、重试、诊断在第一屏）→ 旧 + 诊断提到状态卡下面（本文件）
//   g 语言：未装 / 已装（+ 版本）/ 安装中（最新输出 + 进度条）/ 失败（原因 + 重试）/ 用户停止 → 本文件
//   h 语言安装输出 pack-output               → 本文件
//   i 诊断：没跑过 / 进行中（第几项）/ 有结论和报告 → 旧 + 本文件
//   j 日志：空 / 有内容                      → 旧 + 本文件
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/app.dart';
import 'package:lopicode/app_services.dart';
import 'package:lopicode/core/project_store.dart';
import 'package:lopicode/core/stores.dart';
import 'package:lopicode/runtime/linux_runtime.dart';
import 'package:lopicode/runtime/runtime_diagnostics.dart';
import 'package:lopicode/runtime/runtime_pack_info.dart';
import 'package:lopicode/runtime/runtime_screen.dart';
import 'package:lopicode/runtime/runtime_screen_widgets.dart';
import 'package:lopicode/runtime/runtime_sources.dart';
import 'package:lopicode/state/runtime_extras.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/settings_widgets.dart';
import 'package:lopicode/ui/shell.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;

import 'support/harness.dart';
import 'support/runtime_fakes.dart';

final bool writeShots = Platform.environment['LOPI_SHOTS'] == '1';
bool fontsLoaded = false;

Future<void> shot(WidgetTester tester, String name) async {
  expect(tester.takeException(), isNull, reason: '$name 渲染时出了异常');
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

class Env {
  Env(this.tmp, this.services);
  final Directory tmp;
  final AppServices services;
  LinuxRuntime get runtime => services.runtime;

  static Future<Env> create({bool proot = true, bool installed = false}) async {
    final tmp = Directory.systemTemp.createTempSync('lopi_rt3_');
    final settings = SettingsStore(File(p.join(tmp.path, 'settings.json')));
    final host = FakeRuntimeHost(nativeDir: proot ? makeFakeNativeDir(tmp) : tmp.path, free: 23 * 1024 * 1024 * 1024);
    final runtime = LinuxRuntime(settings: settings, baseDir: p.join(tmp.path, 'runtime'), host: host);
    if (installed) markInstalled(runtime);
    await runtime.init();
    return Env(tmp, AppServices(settings: settings, secrets: MemorySecretStore(), projects: ProjectStore(p.join(tmp.path, 'projects')), runtime: runtime));
  }

  Widget app(ThemeMode mode, {String? projectDir}) => RepaintBoundary(
    key: shotKey,
    child: LopiCodeApp(
      services: services,
      home: ShellScope(
        openDrawer: () {},
        go: (_) {},
        projectName: '我的后端服务（积木）',
        child: RuntimeScreen(projectDir: projectDir),
      ),
      fontFamily: kTestFont,
      forceThemeMode: mode,
    ),
  );

  /// 摆出“Node.js 和 Python 已装好”的样子（标记文件 + 版本信息所在的文件）。
  void fakeNodeAndPython() {
    File(p.join(runtime.rootfsDir, 'usr/local/bin/node'))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('x' * 4096);
    File(p.join(runtime.rootfsDir, 'usr/local/include/node/node_version.h'))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('#define NODE_MAJOR_VERSION 24\n#define NODE_MINOR_VERSION 9\n#define NODE_PATCH_VERSION 0\n');
    File(p.join(runtime.rootfsDir, 'usr/bin/python3')).writeAsStringSync('x' * 2048);
    File(p.join(runtime.rootfsDir, 'var/lib/dpkg/status'))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(
        'Package: python3\nStatus: install ok installed\nVersion: 3.12.3-0ubuntu2.1\n\n'
        'Package: git\nStatus: deinstall ok config-files\nVersion: 1:2.43.0-1ubuntu7.3\n',
      );
  }
}

Future<Env> boot(WidgetTester tester, {bool proot = true, bool installed = false}) async {
  usePhoneViewport(tester);
  final env = (await tester.runAsync(() => Env.create(proot: proot, installed: installed)))!;
  addTearDown(() {
    if (env.tmp.existsSync()) env.tmp.deleteSync(recursive: true);
  });
  return env;
}

/// 占用空间、版本号是真读文件现算的：真实的文件读写要“真等一下 + 让测试时钟走一下”才往下走（见 harness 的 settle）。
Future<void> loadExtras(WidgetTester tester, Env env) async {
  for (var i = 0; i < 20; i++) {
    await settle(tester, rounds: 1);
    final c = env.services.container;
    if (!c.read(runtimeDiskUsageProvider).isLoading && !c.read(runtimePackVersionsProvider).isLoading) break;
  }
  await tester.pump();
}

void main() {
  setUpAll(() async => fontsLoaded = await loadRealFonts());

  group('只读信息（不起进程、不联网）', () {
    test('目录占用：把普通文件的大小加起来；目录不在是 null', () async {
      final tmp = Directory.systemTemp.createTempSync('lopi_du_');
      addTearDown(() => tmp.deleteSync(recursive: true));
      File(p.join(tmp.path, 'a/b/one'))
        ..parent.createSync(recursive: true)
        ..writeAsBytesSync(List.filled(1000, 0));
      File(p.join(tmp.path, 'two')).writeAsBytesSync(List.filled(24, 0));
      Link(p.join(tmp.path, 'link')).createSync(p.join(tmp.path, 'two'));
      expect(await directorySize(tmp.path), 1024, reason: '符号链接不重复算');
      expect(await directorySize(p.join(tmp.path, 'nope')), isNull);
    });

    test('版本号：Node 读头文件，Go 读 VERSION，apt 装的读 dpkg 清单；读不到就没有这一项', () async {
      final tmp = Directory.systemTemp.createTempSync('lopi_ver_');
      addTearDown(() => tmp.deleteSync(recursive: true));
      expect(await readPackVersions(tmp.path, ['node', 'python', 'git', 'go']), isEmpty);
      File(p.join(tmp.path, 'usr/local/include/node/node_version.h'))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('#define NODE_MAJOR_VERSION 24\n#define NODE_MINOR_VERSION 11\n#define NODE_PATCH_VERSION 1\n');
      File(p.join(tmp.path, 'var/lib/dpkg/status'))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(
          'Package: python3-pip\nStatus: install ok installed\nVersion: 24.0+dfsg-1ubuntu1\n\n'
          'Package: python3\nStatus: install ok installed\nVersion: 3.12.3-0ubuntu2.1\n\n'
          'Package: git\nStatus: install ok installed\nVersion: 1:2.43.0-1ubuntu7.3\n\n'
          'Package: openjdk-21-jdk-headless\nStatus: install ok installed\nVersion: 21.0.9+10-1~24.04\n\n'
          'Package: php-cli\nStatus: install ok installed\nVersion: 2:8.3+93ubuntu2\n',
        );
      expect(await readPackVersions(tmp.path, ['node', 'python', 'git', 'go']), {'node': '24.11.1', 'python': '3.12.3', 'git': '2.43.0'});
      File(p.join(tmp.path, 'usr/local/go/VERSION'))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('go1.26.11\ntime 2026-01-01T00:00:00Z\n');
      expect(await readPackVersions(tmp.path, ['go', 'java', 'php']), {'go': '1.26.11', 'java': '21.0.9', 'php': '8.3'});
      File(p.join(tmp.path, 'usr/local/go/VERSION')).writeAsBytesSync([0xff, 0xfe, 0x00]);
      expect(await readPackVersions(tmp.path, ['go']), isEmpty, reason: 'VERSION 文件坏了不崩');
      // 坏内容不崩
      File(p.join(tmp.path, 'usr/local/include/node/node_version.h')).writeAsBytesSync([0xff, 0xfe, 0x00]);
      File(p.join(tmp.path, 'var/lib/dpkg/status')).writeAsStringSync('Package: git\n');
      expect(await readPackVersions(tmp.path, ['node', 'git']), isEmpty);
    });

    test('上一次没装成的是哪一项、为什么：用安装器记下的那一项和原因的第一行；用户停止不算出错；装好了 / 正在装不算', () {
      final packs = runtimePacks('tuna');
      final git = packs.firstWhere((x) => x.id == 'git');
      PackAttempt? of(List<String> output, {Set<String> installed = const {}, String? running, String? errorId, String? error}) =>
          lastFailedPack(packs: packs, installed: installed, runningPack: running, output: output, errorId: errorId, errorMessage: error);
      final failed = of(['开始安装 ${git.title}…', 'E: Unable to locate package git', '${git.title} 没装成：软件源里找不到这个包。'], errorId: 'git', error: '软件源里找不到这个包。\nE: Unable to locate package git');
      expect(failed?.packId, 'git');
      expect(failed?.stopped, isFalse);
      expect(failed?.reason, '软件源里找不到这个包。', reason: '只取原因的第一行，完整输出在下面的框里');
      final stopped = of(['开始安装 ${git.title}…', 'Get:1 http://x', '已取消安装 ${git.title}。']);
      expect(stopped?.packId, 'git');
      expect(stopped?.stopped, isTrue);
      expect(stopped?.reason, '已停止，没有装完');
      expect(of(const ['x'], errorId: 'git')?.reason, '安装没有成功', reason: '没有原因也不编');
      expect(of(['开始安装 ${git.title}…', 'ok', '${git.title} 安装完成。']), isNull);
      expect(
        of(const ['x'], installed: {'git'}, errorId: 'git', error: 'x'),
        isNull,
        reason: '后来装好了就不再挂着',
      );
      expect(of(const ['x'], running: 'git', errorId: 'git', error: 'x'), isNull);
      expect(
        of(const ['x'], errorId: 'ruby', error: 'x'),
        isNull,
        reason: '清单里没有的不显示',
      );
      expect(of(const []), isNull);
      expect(of(['别的格式', 'x']), isNull, reason: '认不出来就不显示，不乱猜');
    });

    test('语言图标：六样内置的都有对应图标名，没登记的用自己的 id', () {
      expect([for (final pack in runtimePacks('tuna')) packIconId(pack.id)], ['nodejs', 'python', 'git', 'go', 'java', 'php']);
      expect(packIconId('go'), 'go');
    });
  });

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    final suffix = mode == ThemeMode.light ? 'light' : 'dark';

    testWidgets('未安装：一张状态卡 + 一个主按钮，下面是下载源和日志；全页只有一个实心按钮 ($suffix)', (tester) async {
      final env = await boot(tester);
      await tester.pumpWidget(env.app(mode));
      await tester.pump();
      expect(find.text('未安装'), findsOneWidget);
      expect(find.byType(FilledButton), findsOneWidget, reason: '主操作只有一个');
      expect(find.widgetWithText(FilledButton, '安装运行环境'), findsOneWidget);
      expect(find.text('语言与工具'), findsNothing);
      expect(find.text('诊断'), findsNothing);
      expect(find.byKey(const Key('runtime-usage')), findsNothing);
      expect(tester.widget<Scaffold>(find.byType(Scaffold).last).backgroundColor, isNotNull, reason: '和设置页一样的浅灰底');
      await shot(tester, 'rt3-not-installed-$suffix');
    });

    testWidgets('上次安装失败、没有残留文件：原因照实显示，主按钮是“重新安装” ($suffix)', (tester) async {
      final env = await boot(tester);
      env.runtime.installError = '校验没通过：下载的文件和官方的校验值对不上，已经删掉，请换个下载源再试';
      await tester.pumpWidget(env.app(mode));
      await tester.pump();
      expect(find.text('上次安装没有成功'), findsOneWidget);
      expect(find.textContaining('校验值对不上'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, '重新安装'), findsOneWidget);
      expect(find.byType(FilledButton), findsOneWidget);
      await shot(tester, 'rt3-install-failed-$suffix');
    });

    testWidgets('下载中：进度条 + 已下载多少 + 百分比，只有“取消”一个按钮；下载源和卸载这时不能动 ($suffix)', (tester) async {
      final env = await boot(tester);
      Directory(p.join(env.runtime.baseDir, 'download')).createSync(recursive: true);
      File(p.join(env.runtime.baseDir, 'download', '${env.runtime.image.fileName}.part')).writeAsBytesSync(List.filled(4096, 0));
      env.runtime
        ..phase = RuntimePhase.downloading
        ..progressDone = 12 * 1024 * 1024
        ..progressTotal = env.runtime.image.size;
      await tester.pumpWidget(env.app(mode));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('正在下载…'), findsOneWidget);
      expect(find.text('42%'), findsOneWidget);
      expect(find.byType(FilledButton), findsNothing);
      expect(find.byKey(const Key('runtime-cancel')), findsOneWidget);
      await shot(tester, 'rt3-downloading-$suffix');
      await tester.tap(find.byKey(const Key('rootfs-source')));
      await tester.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 2));
      expect(find.byType(SettingsChoiceRow), findsNothing, reason: '安装中不能换下载源');
      await tester.ensureVisible(find.byKey(const Key('runtime-uninstall')));
      await tester.tap(find.byKey(const Key('runtime-uninstall')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('卸载运行环境？'), findsNothing, reason: '安装中不能卸载');
      env.runtime.phase = RuntimePhase.notInstalled;
    });

    testWidgets('已安装：占用空间是现数的；语言一行一样——已装的带版本和对勾、正在装的有进度和最新输出、没装的是同一尺寸的小按钮 ($suffix)', (tester) async {
      final env = await boot(tester, installed: true);
      env.fakeNodeAndPython();
      env.runtime.packInstaller.running = 'git';
      env.runtime.packOutput.addAll(['开始安装 Git…', 'Get:1 http://mirrors.tuna.tsinghua.edu.cn/ubuntu-ports noble/main arm64 git arm64 [3,412 kB]']);
      await tester.pumpWidget(env.app(mode));
      await tester.pump();
      expect(find.byKey(const Key('runtime-usage')), findsNothing, reason: '没数完之前不显示，不编数字');
      await loadExtras(tester, env);
      expect(tester.widget<Text>(find.byKey(const Key('runtime-usage'))).data, startsWith('约 '));
      expect(find.byType(FilledButton), findsNothing, reason: '一切正常时没有主按钮');
      // 已装：版本 + 对勾
      expect(tester.widget<Text>(find.byKey(const Key('pack-node-note'))).data, '已安装 · 24.9.0');
      expect(tester.widget<Text>(find.byKey(const Key('pack-python-note'))).data, '已安装 · 3.12.3');
      expect(find.descendant(of: find.byKey(const Key('pack-node-installed')), matching: find.byIcon(Icons.check_circle)), findsOneWidget);
      // 正在装：进度条、最新一行输出、能停；别的安装按钮没有（都装了）
      expect(find.byKey(const Key('pack-git-progress')), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const Key('pack-git-note'))).data, startsWith('Get:1 http://mirrors'));
      expect(find.byKey(const Key('pack-git-stop')), findsOneWidget);
      expect(find.byKey(const Key('pack-output')), findsOneWidget);
      // 每行都有语言图标
      for (final icon in ['nodejs', 'python', 'git']) {
        expect(find.byKey(ValueKey('file-icon-assets/file_icons/$icon.svg')), findsOneWidget);
      }
      // 装语言的时候不能卸载
      await shot(tester, 'rt3-installed-$suffix');
      await tester.ensureVisible(find.byKey(const Key('runtime-uninstall')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('runtime-uninstall')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('卸载运行环境？'), findsNothing);
      await shot(tester, 'rt3-installed-bottom-$suffix');
      env.runtime.packInstaller.running = null;
    });

    testWidgets('语言没装成：原因写在那一行（红字）+ “重试”，完整输出在下面；小按钮全是一个尺寸；点了真的去装 ($suffix)', (tester) async {
      final env = await boot(tester, installed: true);
      env.runtime.packOutput.addAll([
        '开始安装 Python 3.12…',
        'Err:1 http://mirrors.tuna.tsinghua.edu.cn/ubuntu-ports noble InRelease',
        'E: Unable to locate package python3-venv',
        'Python 3.12 没装成：软件源里找不到要装的包。',
      ]);
      env.runtime.packInstaller
        ..errorPack = 'python'
        ..error = '软件源里找不到要装的包。\nE: Unable to locate package python3-venv';
      await tester.pumpWidget(env.app(mode));
      await tester.pump();
      expect(tester.widget<Text>(find.byKey(const Key('pack-python-note'))).data, '软件源里找不到要装的包。');
      expect(tester.widget<Text>(find.byKey(const Key('pack-python-note'))).style?.color, tester.element(find.byType(RuntimeScreen)).colors.danger);
      expect(find.descendant(of: find.byKey(const Key('pack-python-install')), matching: find.text('重试')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('pack-node-install')), matching: find.text('安装')), findsOneWidget);
      final sizes = {
        for (final id in ['node', 'python', 'git']) tester.getSize(find.byKey(Key('pack-$id-install'))),
      };
      expect(sizes, {RuntimeSmallButton.size}, reason: '三个小按钮同一个尺寸');
      final rights = {
        for (final id in ['node', 'python', 'git']) tester.getTopRight(find.byKey(Key('pack-$id-install'))).dx,
      };
      expect(rights.length, 1, reason: '右边缘对齐');
      await shot(tester, 'rt3-pack-failed-$suffix');

      // 点“安装”：走的是真的 installPack（这里的启动器是个只会回显的假脚本，不下载）
      await tester.tap(find.byKey(const Key('pack-git-install')));
      for (var i = 0; i < 40 && !env.runtime.packOutput.last.contains('安装完成'); i++) {
        await settle(tester, rounds: 1);
      }
      await settle(tester, rounds: 1);
      expect(env.runtime.packOutput.first, '开始安装 Git…');
      expect(env.runtime.packOutput.last, 'Git 安装完成。');
      expect(find.text('重试'), findsNothing, reason: '换了一次安装，上一次的失败不再挂着');
    });

    testWidgets('下载源：两行，值在右；点开底部面板单选，选了就生效 ($suffix)', (tester) async {
      final env = await boot(tester);
      await tester.pumpWidget(env.app(mode));
      await tester.pump();
      expect(tester.widget<Text>(find.byKey(const Key('rootfs-source-value'))).data, '清华大学镜像');
      expect(find.byType(DropdownButton<String>), findsNothing);
      await tester.tap(find.byKey(const Key('rootfs-source')));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsChoiceRow), findsNWidgets(3));
      expect(tester.widget<SettingsChoiceRow>(find.byKey(const Key('mirror-option-tuna'))).selected, isTrue);
      expect(find.text('mirrors.aliyun.com'), findsOneWidget);
      await shot(tester, 'rt3-source-sheet-$suffix');
      await tester.tap(find.byKey(const Key('mirror-option-aliyun')));
      await settle(tester);
      await tester.pumpAndSettle();
      // 选项先写进设置，界面上的字要等真实写盘做完才跟着换；机器忙的时候固定等一次不够，这里等到换过来为止（有上限）。
      for (var i = 0; i < 40 && tester.widget<Text>(find.byKey(const Key('rootfs-source-value'))).data != '阿里云镜像'; i++) {
        await settle(tester, rounds: 1);
      }
      expect(env.runtime.rootfsSource.id, 'aliyun');
      expect(tester.widget<Text>(find.byKey(const Key('rootfs-source-value'))).data, '阿里云镜像');
      expect(tester.widget<Text>(find.byKey(const Key('apt-mirror-value'))).data, '清华大学镜像', reason: '两个源各管各的');

      await tester.tap(find.byKey(const Key('apt-mirror')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('mirror-option-official')));
      await settle(tester);
      await tester.pumpAndSettle();
      expect(env.runtime.aptMirror.id, 'official');
      expect(tester.widget<Text>(find.byKey(const Key('apt-mirror-value'))).data, 'Ubuntu 官方');
    });

    testWidgets('诊断是一行入口，不是大按钮；进行中显示查到第几项；日志能复制 ($suffix)', (tester) async {
      final env = await boot(tester, installed: true);
      env.runtime.recordLaunchFailure('PRoot 刚启动就退出了（退出码 255）', output: 'proot error: execve("/usr/bin/env"): Permission denied');
      await tester.pumpWidget(env.app(mode));
      await tester.pump();
      expect(tester.widget(find.byKey(const Key('runtime-diagnose'))), isA<SettingsRow>());
      expect(find.byType(FilledButton), findsNothing);
      expect(find.text('开始诊断'), findsOneWidget);
      // 正常时的顺序：语言与工具 → 下载源 → 诊断 → 日志 → 卸载
      double y(Finder f) => tester.getTopLeft(f).dy;
      expect(y(find.text('语言与工具')), lessThan(y(find.text('下载源'))));
      expect(y(find.text('下载源')), lessThan(y(find.text('诊断'))));
      expect(y(find.text('诊断')), lessThan(y(find.text('日志'))));
      expect(y(find.text('日志')), lessThan(y(find.byKey(const Key('runtime-uninstall')))));

      env.runtime.diagnostics
        ..running = true
        ..progress = '用兼容模式进 Ubuntu'
        ..steps.addAll([DiagStep('手机和系统'), DiagStep('启动器文件'), DiagStep('默认模式进 Ubuntu')]);
      for (final listener in List.of(env.runtime.diagnostics.changeListeners)) {
        listener();
      }
      await tester.pump();
      expect(find.text('正在检查…'), findsOneWidget);
      expect(find.text('第 3 项：用兼容模式进 Ubuntu'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('diag-progress')));
      await tester.pump();
      await shot(tester, 'rt3-diagnosing-$suffix');
      await tester.tap(find.byKey(const Key('runtime-diagnose')), warnIfMissed: false);
      await tester.pump();
      expect(env.runtime.diagnostics.running, isTrue, reason: '进行中再点不会重跑');

      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String;
        return null;
      });
      await tester.ensureVisible(find.byKey(const Key('runtime-log-copy')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('runtime-log-copy')));
      await tester.pump();
      expect(copied, contains('Permission denied'));
      expect(find.text('日志已复制'), findsOneWidget);
      env.runtime.diagnostics.running = false;
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('连续启动失败：诊断提到状态卡正下面、在第一屏里；主按钮只有“重新尝试进入 Ubuntu” ($suffix)', (tester) async {
      final env = await boot(tester, installed: true);
      env.runtime
        ..recordLaunchFailure('PRoot 刚启动就退出了（退出码 255）', output: 'proot error: Permission denied')
        ..recordLaunchFailure('PRoot 刚启动就退出了（退出码 255）', output: 'proot error: Permission denied');
      await tester.pumpWidget(env.app(mode));
      await tester.pump();
      expect(find.byType(FilledButton), findsOneWidget);
      expect(find.widgetWithText(FilledButton, '重新尝试进入 Ubuntu'), findsOneWidget);
      expect(tester.getBottomLeft(find.byKey(const Key('runtime-diagnose'))).dy, lessThan(kPhone.height), reason: '诊断那一行整个在第一屏里');
      expect(tester.getTopLeft(find.byKey(const Key('runtime-diagnose'))).dy, lessThan(tester.getTopLeft(find.text('语言与工具')).dy));
      expect(find.byKey(const Key('pack-node-install')), findsOneWidget);
      expect(tester.widget<RuntimeSmallButton>(find.byKey(const Key('pack-node-install'))).onPressed, isNull, reason: '进不去的时候装不了');
      await shot(tester, 'rt3-launch-failed-$suffix');
    });

    testWidgets('已下载但安装包缺启动器：语言与工具里如实说装不了，不给安装按钮 ($suffix)', (tester) async {
      final env = await boot(tester, proot: false, installed: true);
      await tester.pumpWidget(env.app(mode));
      await tester.pump();
      expect(find.text('已下载，但进不去'), findsOneWidget);
      expect(find.text('环境进不去的时候装不了运行时。'), findsOneWidget);
      expect(find.byKey(const Key('pack-node-install')), findsNothing);
      expect(find.byKey(const Key('runtime-no-proot')), findsOneWidget);
      await shot(tester, 'rt3-no-proot-installed-$suffix');
    });
  }
}
