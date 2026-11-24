// 真机反馈第三轮第 3 条：后端“运行”——所选语言的工具没装就自动装好再启动（lib/state/backend_run.dart）。
//
// 都按安卓的规矩跑（不许用本机 shell）。Ubuntu 里的进程是假的（test/support/run_fakes.dart 的 FakeGuest）：
// 不进 PRoot、不联网、不下载任何东西；装 Ubuntu 环境那几条用本机回环上的小文件服务器和一个几百 KB 的样品包。
import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/backend/backend_launch.dart';
import 'package:lopicode/core/templates.dart';
import 'package:lopicode/project_session.dart';
import 'package:lopicode/runtime/linux_runtime.dart';
import 'package:lopicode/runtime/pack_install.dart';
import 'package:lopicode/runtime/runtime_sources.dart';
import 'package:lopicode/state/backend_run.dart';
import 'package:lopicode/state/runtime_state.dart';
import 'package:lopicode/terminal/terminal_session.dart';

import 'support/run_fakes.dart';
import 'support/runtime_fakes.dart';

const goCmd = 'go build -o server . && ./server';

void main() {
  late RunEnv env;
  ProjectSession? opened;
  late ProjectSession session;

  Future<void> open({bool android = true, bool installed = true, bool proot = true, int? free = 23 * 1024 * 1024 * 1024, FileServer? server, RootfsImage? image}) async {
    env = await RunEnv.create(
      android: android,
      installed: installed,
      proot: proot,
      free: free,
      httpClient: server == null ? null : () => RedirectingClient(server.uri('/rootfs.tar.gz')),
      image: image ?? RootfsImage.ubuntu2404Arm64,
    );
    final project = await env.services.projects.create('小后端', ProjectTemplate.web);
    session = opened = ProjectSession(env.services, project);
    env.wire(session);
  }

  tearDown(() async {
    final s = opened;
    opened = null;
    if (s == null) return;
    s.dispose();
    await env.dispose();
  });

  BackendRunState run() => env.run(session);
  BackendRunNotifier ctl() => env.ctl(session);
  TerminalSession backendTerm() => session.terminals.firstWhere((t) => t.title == kBackendTerminalTitle);
  String screen() => backendTerm().text.replaceAll('\n', '');
  List<String> launched() => env.typed.where((t) => t.contains('server')).toList();

  group('清单', () {
    test('语言和工具是同一份清单：Node / Python / Git 还在，多了 Go / Java / PHP；每项都有检测文件、命令和能重复跑的脚本', () {
      final packs = runtimePacks('tuna');
      expect([for (final x in packs) x.id], ['node', 'python', 'git', 'go', 'java', 'php']);
      for (final x in packs) {
        expect(x.marker, isNotEmpty);
        expect(x.commands, isNotEmpty, reason: x.id);
        expect(x.script, startsWith('set -e'), reason: x.id);
        expect(x.script, contains('dpkg --configure -a'), reason: '${x.id}：先把上次被打断的安装收尾');
      }
      expect(runtimePackById(packs, 'java')!.commands, ['java', 'javac'], reason: '生成的 Java 工程要 javac 编译');
      expect(runtimePackById(packs, 'java')!.script, contains('openjdk-21-jdk-headless'));
      expect(runtimePackById(packs, 'php')!.script, contains('php-cli'));
      expect(runtimePackById(packs, 'cobol'), isNull);
    });

    test('Go：官方包，版本和校验值写死；国内源走 golang.google.cn，官方源走 go.dev；校验不过删文件；链接进 PATH', () {
      final cn = runtimePackById(runtimePacks('tuna'), 'go')!.script;
      final official = runtimePackById(runtimePacks('official'), 'go')!.script;
      expect(cn, contains('https://golang.google.cn/dl/\$FILE'));
      expect(official, contains('https://go.dev/dl/\$FILE'));
      expect(cn, contains('FILE=go1.26.11.linux-arm64.tar.gz'));
      expect(cn, contains('6c2f29b458b5add0835f18b776f69c8881a6d88428f1484a6da55755e620757e  \$FILE" | sha256sum -c -'));
      expect(cn, contains('rm -f "\$FILE"; echo "校验没通过'));
      expect(cn, contains('ln -sf /usr/local/go/bin/go /usr/local/bin/go'));
      expect(goArchiveSha256.length, 64);
    });

    test('要先问一次的门槛是 100 MB：只有 JDK 过线；没核对过体积的不显示数字、也不问', () {
      final packs = runtimePacks('tuna');
      expect(kPackConfirmBytes, 100 * 1024 * 1024);
      expect(
        [
          for (final x in packs)
            if (x.needsConfirm) x.id,
        ],
        ['java'],
      );
      expect(runtimePackById(packs, 'go')!.sizeNote, '下载约 61 MB，装好后占约 240 MB');
      expect(runtimePackById(packs, 'java')!.sizeNote, '下载约 130 MB，装好后占约 300 MB');
      expect(runtimePackById(packs, 'php')!.sizeNote, isNull);
      expect(runtimePackById(packs, 'node')!.sizeNote, isNull);
    });

    test('失败原因的分类：认 apt / curl / tar 的原话；认不出来归“别的”', () {
      expect(classifyPackFailure(['E: Failed to fetch http://x/y.deb  Temporary failure resolving \'mirrors.tuna.tsinghua.edu.cn\'']), PackFailure.network);
      expect(classifyPackFailure(['curl: (6) Could not resolve host: golang.google.cn']), PackFailure.network);
      expect(classifyPackFailure(['curl: (28) Operation timed out after 300 seconds']), PackFailure.network);
      expect(classifyPackFailure(['tar: go/bin/go: Cannot write: No space left on device']), PackFailure.noSpace);
      expect(classifyPackFailure(['E: You don\'t have enough free space in /var/cache/apt/archives/.']), PackFailure.noSpace);
      expect(classifyPackFailure(['E: Unable to locate package openjdk-21-jdk-headless']), PackFailure.notFound);
      expect(classifyPackFailure(['curl: (22) The requested URL returned error: 404']), PackFailure.notFound);
      expect(classifyPackFailure(['go1.26.11.linux-arm64.tar.gz: FAILED', '校验没通过，已删掉下到的文件']), PackFailure.checksum);
      expect(classifyPackFailure(['dpkg: error processing package foo (--configure)']), PackFailure.other);
      expect(classifyPackFailure(const []), PackFailure.other);
    });
  });

  group('已经装好', () {
    test('环境里有那个文件：直接启动，不进 Ubuntu 核对、不多一步、终端里不多一行字', () async {
      await open();
      env.markPack('go');
      expect(ctl().start(language: 'go', command: goCmd), isTrue);
      expect(run().phase, BackendRunPhase.idle);
      await waitFor(() => launched().isNotEmpty, '命令打进终端');
      expect(launched(), ['$goCmd\r']);
      expect(env.guest.scripts, isEmpty, reason: '没有起任何进程');
      expect(screen(), isNot(contains('[运行]')));
      expect(session.terminals.last.title, kBackendTerminalTitle);
      expect(session.activeTerminal, session.terminals.length - 1);
    });

    test('文件不在但命令能用（她自己用别的办法装的）：核对一次，不装，直接启动', () async {
      await open();
      env.guest.present.add('go');
      ctl().start(language: 'go', command: goCmd);
      expect(run().phase, BackendRunPhase.checking);
      await waitFor(() => launched().isNotEmpty, '命令打进终端');
      expect(launched(), ['$goCmd\r'], reason: '这次新开的终端：不用先 Ctrl+C');
      expect((env.guest.probes, env.guest.installs.length), (1, 0));
      expect(env.guest.scripts.single, 'command -v go >/dev/null 2>&1');
      expect(run().phase, BackendRunPhase.idle);
    });

    test('Java 要 java 和 javac 都在：只有 java 不算装好', () async {
      await open();
      env.guest.present.add('java');
      ctl().start(language: 'java', command: 'javac Main.java && java Main # server');
      await waitFor(() => run().phase == BackendRunPhase.confirming, '发现缺 javac，要装');
      expect(env.guest.scripts.single, 'command -v java >/dev/null 2>&1 && command -v javac >/dev/null 2>&1');
      ctl().cancel();
    });

    test('核对不了（Ubuntu 进不去）：不拦着，照常把命令打进终端，进不去的原因由终端自己显示', () async {
      await open();
      env.guest.failProbeStart = true;
      ctl().start(language: 'go', command: goCmd);
      await waitFor(() => launched().isNotEmpty, '命令打进终端');
      expect(env.guest.installs, isEmpty);
      expect(run().phase, BackendRunPhase.idle);
    });

    test('清单里没有的语言：没什么可装的，直接启动', () async {
      await open();
      ctl().start(language: 'cobol', command: './server');
      await waitFor(() => launched().isNotEmpty, '命令打进终端');
      expect(env.guest.scripts, isEmpty);
    });

    test('第二次运行复用“后端”终端：先 Ctrl+C 再启动', () async {
      await open();
      env.markPack('go');
      ctl().start(language: 'go', command: goCmd);
      await waitFor(() => launched().isNotEmpty, '第一次');
      ctl().start(language: 'go', command: goCmd);
      await waitFor(() => launched().single == '$goCmd\r\x03$goCmd\r', '第二次先 Ctrl+C');
      expect(session.terminals.where((t) => t.title == kBackendTerminalTitle).length, 1);
    });
  });

  group('没装：自动装好再启动', () {
    test('Go（不到门槛，不问）：核对 → 安装 → 启动；过程一行行出现在“后端”终端里；装的时候还没启动', () async {
      await open();
      final seen = <BackendRunPhase>[];
      env.services.container.listen(backendRunProvider(session), (_, next) => seen.add(next.phase));
      ctl().start(language: 'go', command: goCmd);
      await waitFor(() => env.guest.installs.isNotEmpty, '开始装');
      expect(run().phase, BackendRunPhase.installing);
      expect((run().packId, run().packTitle, run().sizeNote), ('go', 'Go 1.26.11', '下载约 61 MB，装好后占约 240 MB'));
      expect(env.runtime.runningPack, 'go', reason: '和“运行环境”页是同一个安装：那边也显示正在装');
      expect(env.guest.scripts.last, contains('go1.26.11.linux-arm64.tar.gz'));
      expect(env.host.keepAlive, isTrue, reason: '装的时候保持后台运行');
      final proc = env.guest.installs.single
        ..say('Get:1 http://mirrors.tuna.tsinghua.edu.cn/ubuntu-ports noble InRelease\n')
        ..say('下载 go1.26.11.linux-arm64.tar.gz（约 61 MB）\n')
        ..complain('  % Total    % Received\n');
      await waitFor(() => screen().contains('% Received'), '输出进终端');
      expect(screen(), allOf(contains('检查 Go 1.26.11 装没装'), contains('没找到 Go 1.26.11，现在自动安装'), contains('Get:1'), contains('约 61 MB')));
      expect(launched(), isEmpty);
      proc
        ..say('go version go1.26.11 linux/arm64\n')
        ..finish(0);
      await waitFor(() => launched().isNotEmpty, '装好后自动启动');
      expect(launched(), ['$goCmd\r']);
      expect(screen(), allOf(contains('go version go1.26.11'), contains('Go 1.26.11 装好了，现在启动')));
      expect(run().phase, BackendRunPhase.idle);
      expect(seen, [BackendRunPhase.checking, BackendRunPhase.installing, BackendRunPhase.idle]);
      expect(env.guest.installs.length, 1);
      expect(env.runtime.view.packErrorId, isNull);
    });

    test('JDK（过了门槛）：先问一次，点头才装；装好自动启动', () async {
      await open();
      ctl().start(language: 'java', command: 'javac Main.java && java Main # server');
      await waitFor(() => run().phase == BackendRunPhase.confirming, '等她点头');
      expect((run().packTitle, run().sizeNote), ('Java（JDK 21）', '下载约 130 MB，装好后占约 300 MB'));
      await tick(60);
      expect(env.guest.installs, isEmpty, reason: '没点头不装');
      ctl().confirmInstall();
      await waitFor(() => env.guest.installs.isNotEmpty, '开始装');
      expect(env.guest.scripts.last, contains('openjdk-21-jdk-headless'));
      env.guest.installs.single.finish(0);
      await waitFor(() => launched().isNotEmpty, '启动');
      expect(run().phase, BackendRunPhase.idle);
    });

    test('JDK：她说先不装——不装、不启动、不留状态；再点运行还会再问', () async {
      await open();
      ctl().start(language: 'java', command: 'java Main # server');
      await waitFor(() => run().phase == BackendRunPhase.confirming, '等她点头');
      ctl().cancel();
      await tick(40);
      expect(run().phase, BackendRunPhase.idle);
      expect(env.guest.installs, isEmpty);
      expect(launched(), isEmpty);
      expect(screen(), contains('没有安装 Java（JDK 21），也没有启动'));
      expect(ctl().start(language: 'java', command: 'java Main # server'), isTrue);
      await waitFor(() => run().phase == BackendRunPhase.confirming, '再问一次');
      ctl().cancel();
    });

    test('“运行环境”页正在装别的：等它装完再装自己的，同一时间只有一个安装进程', () async {
      await open();
      final node = runtimePackById(env.runtime.packs, 'node')!;
      final other = env.runtime.installPack(node);
      await waitFor(() => env.guest.installs.length == 1, 'Node 开始装');
      ctl().start(language: 'go', command: goCmd);
      await tick(60);
      expect(run().phase, BackendRunPhase.checking);
      expect(env.guest.installs.length, 1, reason: 'Go 还没开始');
      expect(screen(), contains('正在装别的东西'));
      env.guest.installs.first.finish(0);
      expect(await other, isTrue);
      await waitFor(() => env.guest.installs.length == 2, 'Go 接着装');
      expect(env.runtime.runningPack, 'go');
      env.guest.installs.last.finish(0);
      await waitFor(() => launched().isNotEmpty, '启动');
    });
  });

  group('装失败：说清真正的原因，可以重试', () {
    Future<PackFailure?> failWith(String output, int code) async {
      ctl().start(language: 'go', command: goCmd);
      await waitFor(() => env.guest.installs.isNotEmpty, '开始装');
      env.guest.installs.last
        ..complain('$output\n')
        ..finish(code);
      await waitFor(() => run().phase == BackendRunPhase.failed, '失败');
      expect(launched(), isEmpty, reason: '没装成就不启动');
      expect(screen(), contains('没有启动'));
      expect(env.runtime.view.packErrorId, 'go', reason: '“运行环境”页也拿得到原因');
      expect(env.runtime.view.packError, run().error);
      return run().failure;
    }

    test('网络不通：点名现在用的下载源，指路换源', () async {
      await open();
      expect(await failWith('curl: (6) Could not resolve host: golang.google.cn', 6), PackFailure.network);
      expect(run().error, allOf(contains('连不上下载源'), contains('清华大学镜像'), contains('换一个下载源')));
    });

    test('空间写满', () async {
      await open();
      expect(await failWith('tar: go/pkg/tool: Cannot write: No space left on device', 2), PackFailure.noSpace);
      expect(run().error, contains('空间写满'));
    });

    test('源里找不到包', () async {
      await open();
      expect(await failWith('E: Unable to locate package curl', 100), PackFailure.notFound);
      expect(run().error, contains('找不到要装的包'));
    });

    test('校验不过', () async {
      await open();
      expect(await failWith('go1.26.11.linux-arm64.tar.gz: FAILED\n校验没通过，已删掉下到的文件', 1), PackFailure.checksum);
      expect(run().error, contains('校验没通过'));
    });

    test('认不出来的：给退出码和最后几行原话', () async {
      await open();
      expect(await failWith('第一行\n第二行\ndpkg: error processing package libfoo (--configure)\nE: Sub-process /usr/bin/dpkg returned an error code (1)', 100), PackFailure.other);
      expect(run().error, allOf(contains('退出码 100'), contains('Sub-process /usr/bin/dpkg'), contains('第二行'), isNot(contains('第一行'))));
    });

    test('装之前就查出空间不够：不起安装进程，说清差多少', () async {
      await open(free: 100 * 1024 * 1024);
      ctl().start(language: 'go', command: goCmd);
      await waitFor(() => run().phase == BackendRunPhase.failed, '失败');
      expect(run().failure, PackFailure.noSpace);
      expect(run().error, allOf(contains('剩余空间不够'), contains('Go 1.26.11'), contains('301.0 MB'), contains('100.0 MB')));
      expect(env.guest.installs, isEmpty);
      expect(launched(), isEmpty);
    });

    test('安装进程起不来（Ubuntu 进不去）', () async {
      await open();
      env.guest.failInstallStart = true;
      ctl().start(language: 'go', command: goCmd);
      await waitFor(() => run().phase == BackendRunPhase.failed, '失败');
      expect(run().failure, PackFailure.launch);
      expect(run().error, contains('进不去 Ubuntu 环境'));
    });

    test('重试：同一条命令再来一遍，这次装成了就启动；失败原因清掉', () async {
      await open();
      await failWith('curl: (7) Failed to connect', 7);
      expect(ctl().retry(), isTrue);
      await waitFor(() => env.guest.installs.length == 2, '重新装');
      expect(env.runtime.view.packErrorId, isNull, reason: '重新开始装就清掉上次的原因');
      env.guest.installs.last.finish(0);
      await waitFor(() => launched().isNotEmpty, '启动');
      expect(launched(), ['$goCmd\r']);
      expect(run().phase, BackendRunPhase.idle);
    });

    test('“知道了”：收起提示，不重试', () async {
      await open();
      await failWith('curl: (7) Failed to connect', 7);
      ctl().dismiss();
      expect(run().phase, BackendRunPhase.idle);
      expect(ctl().retry(), isFalse);
      expect(env.guest.installs.length, 1);
    });
  });

  group('取消', () {
    test('装到一半取消：安装进程被停掉，不启动，不算失败（不留原因）；再点运行接着装', () async {
      await open();
      ctl().start(language: 'go', command: goCmd);
      await waitFor(() => env.guest.installs.isNotEmpty, '开始装');
      env.guest.installs.single.say('Get:1 …\n');
      await tick();
      ctl().cancel();
      await waitFor(() => run().phase == BackendRunPhase.idle, '停下');
      expect(env.guest.installs.single.killed, isTrue);
      expect(env.runtime.runningPack, isNull);
      expect(env.runtime.view.packErrorId, isNull);
      expect(launched(), isEmpty);
      expect(screen(), allOf(contains('已取消安装 Go 1.26.11'), contains('已取消安装，没有启动')));
      expect(ctl().start(language: 'go', command: goCmd), isTrue);
      await waitFor(() => env.guest.installs.length == 2, '再装');
      env.guest.installs.last.finish(0);
      await waitFor(() => launched().isNotEmpty, '启动');
    });

    test('在“运行环境”页点了停止（同一个安装）：这边也按取消处理', () async {
      await open();
      ctl().start(language: 'go', command: goCmd);
      await waitFor(() => env.guest.installs.isNotEmpty, '开始装');
      env.services.container.read(runtimeProvider.notifier).cancelPack();
      await waitFor(() => run().phase == BackendRunPhase.idle, '停下');
      expect(launched(), isEmpty);
    });

    test('核对的时候取消：核对回来以后什么都不做', () async {
      await open();
      final hold = env.guest.holdProbe = Completer<void>();
      ctl().start(language: 'go', command: goCmd);
      await tick();
      expect(run().phase, BackendRunPhase.checking);
      ctl().cancel();
      expect(run().phase, BackendRunPhase.idle);
      hold.complete();
      await tick(60);
      expect(env.guest.installs, isEmpty);
      expect(launched(), isEmpty);
      expect(run().phase, BackendRunPhase.idle);
    });
  });

  group('连点和销毁', () {
    test('连点运行：进行中的那一次没完之前不再受理，只起一个安装进程', () async {
      await open();
      expect(ctl().start(language: 'go', command: goCmd), isTrue);
      expect(ctl().start(language: 'go', command: goCmd), isFalse);
      expect(ctl().start(language: 'go', command: goCmd), isFalse);
      await waitFor(() => env.guest.installs.isNotEmpty, '开始装');
      expect(ctl().start(language: 'go', command: goCmd), isFalse);
      await tick(60);
      expect((env.guest.probes, env.guest.installs.length), (1, 1));
      env.guest.installs.single.finish(0);
      await waitFor(() => launched().isNotEmpty, '启动');
      expect(launched(), ['$goCmd\r'], reason: '只启动一次');
    });

    test('装到一半工作区关了：装完不启动、不往终端里写、不写状态、不抛错', () async {
      await open();
      ctl().start(language: 'go', command: goCmd);
      await waitFor(() => env.guest.installs.isNotEmpty, '开始装');
      final term = backendTerm();
      session.dispose();
      final before = term.text;
      env.guest.installs.single
        ..say('还在装\n')
        ..finish(0);
      await tick(80);
      expect(launched(), isEmpty);
      expect(term.text, before);
      expect(env.runtime.runningPack, isNull, reason: '安装本身照常收尾');
    });

    test('装到一半整个应用状态销毁：同样什么都不写', () async {
      await open();
      ctl().start(language: 'go', command: goCmd);
      await waitFor(() => env.guest.installs.isNotEmpty, '开始装');
      env.services.dispose();
      env.guest.installs.single.finish(0);
      await tick(80);
      expect(launched(), isEmpty);
    });

    test('核对到一半工作区关了：回来以后不装也不启动', () async {
      await open();
      final hold = env.guest.holdProbe = Completer<void>();
      ctl().start(language: 'go', command: goCmd);
      await tick();
      session.dispose();
      hold.complete();
      await tick(60);
      expect(env.guest.installs, isEmpty);
      expect(launched(), isEmpty);
    });
  });

  group('Ubuntu 运行环境还没装', () {
    late FileServer server;
    late RootfsImage image;
    late Directory scratch;

    setUp(() async {
      scratch = Directory.systemTemp.createTempSync('lopi_run_img_');
      final bytes = (await makeSampleRootfs(scratch)).readAsBytesSync();
      image = RootfsImage(version: 'test', fileName: 'rootfs.tar.gz', size: bytes.length, sha256: sha256.convert(bytes).toString());
      server = await FileServer.start({'/rootfs.tar.gz': bytes});
    });
    tearDown(() async {
      await server.close();
      scratch.deleteSync(recursive: true);
    });

    test('自动开始装环境 → 装好接着核对 → 装 Go → 启动，全程不用再点一次', () async {
      await open(installed: false, server: server, image: image);
      expect(session.terminals, isEmpty);
      ctl().start(language: 'go', command: goCmd);
      expect(run().phase, BackendRunPhase.waitingRuntime);
      await waitFor(() => env.runtime.installed, '环境装好');
      await waitFor(() => env.guest.installs.isNotEmpty, '接着装 Go');
      expect(server.requests, greaterThan(0));
      expect(run().phase, BackendRunPhase.installing);
      env.guest.installs.single.finish(0);
      await waitFor(() => launched().isNotEmpty, '启动');
      expect(launched(), ['$goCmd\r']);
      expect([for (final t in session.terminals) t.title], ['Ubuntu 1', kBackendTerminalTitle]);
      expect(session.terminals[session.activeTerminal].title, kBackendTerminalTitle, reason: '停在“后端”终端上');
      expect(run().phase, BackendRunPhase.idle);
    });

    test('装环境的时候她取消了：整个停下，不留半截；以后环境装好也不会自己冒出来启动', () async {
      await open(installed: false, server: server, image: image);
      server.chunkDelay = const Duration(milliseconds: 30);
      ctl().start(language: 'go', command: goCmd);
      await waitFor(() => env.runtime.phase == RuntimePhase.downloading && env.runtime.progressDone > 0, '下载中');
      env.runtime.cancelInstall(); // 安装引导里的“取消”
      await waitFor(() => !env.runtime.busy, '停下');
      await tick(40);
      expect(run().phase, BackendRunPhase.idle);
      expect(env.runtime.installError, isNull);
      server.chunkDelay = null;
      await env.runtime.install();
      expect(env.runtime.installed, isTrue);
      await tick(80);
      expect(env.guest.scripts, isEmpty);
      expect(launched(), isEmpty);
      expect([for (final t in session.terminals) t.title], ['Ubuntu 1']);
    });

    test('在准备条上点取消（环境正在装）：环境的安装也停下', () async {
      await open(installed: false, server: server, image: image);
      server.chunkDelay = const Duration(milliseconds: 30);
      ctl().start(language: 'go', command: goCmd);
      await waitFor(() => env.runtime.phase == RuntimePhase.downloading && env.runtime.progressDone > 0, '下载中');
      ctl().cancel();
      expect(run().phase, BackendRunPhase.idle);
      await waitFor(() => !env.runtime.busy, '停下');
      expect(env.runtime.installed, isFalse);
      await tick(60);
      expect(launched(), isEmpty);
    });

    test('装环境失败（空间不够）：原因在安装引导里；她清出空间再点一次安装，装好还是接着启动', () async {
      await open(installed: false, server: server, image: image, free: 20 * 1024 * 1024);
      ctl().start(language: 'go', command: goCmd);
      await waitFor(() => env.runtime.installError != null, '失败');
      expect(env.runtime.installError, contains('剩余空间不够'));
      expect(server.requests, 0);
      await tick(40);
      expect(run().phase, BackendRunPhase.waitingRuntime, reason: '还等着：引导里再点一次就接着来');
      env.host.freeNow = 23 * 1024 * 1024 * 1024;
      await env.runtime.install(); // 安装引导里的“安装运行环境”
      await waitFor(() => env.guest.installs.isNotEmpty, '接着装 Go');
      env.guest.installs.single.finish(0);
      await waitFor(() => launched().isNotEmpty, '启动');
    });

    test('装环境失败以后她回去又点了一次“运行”：算再试一次（重新装环境），不会卡成“点了没反应”；也只启动一次', () async {
      await open(installed: false, server: server, image: image, free: 20 * 1024 * 1024);
      ctl().start(language: 'go', command: goCmd);
      await waitFor(() => env.runtime.installError != null, '失败');
      await tick(40);
      env.host.freeNow = 23 * 1024 * 1024 * 1024;
      expect(ctl().start(language: 'go', command: goCmd), isTrue);
      await waitFor(() => env.guest.installs.isNotEmpty, '环境装好，接着装 Go');
      expect(
        ctl().start(language: 'go', command: goCmd),
        isFalse,
        reason: '这回是真的在进行中',
      );
      env.guest.installs.single.finish(0);
      await waitFor(() => launched().isNotEmpty, '启动');
      await tick(60);
      expect(launched(), ['$goCmd\r']);
      expect(env.guest.installs.length, 1);
    });

    test('安装包里缺 PRoot：装了也进不去，不自动装、不留状态（终端页的引导已写明原因）', () async {
      await open(installed: false, proot: false, server: server, image: image);
      ctl().start(language: 'go', command: goCmd);
      await tick(60);
      expect(run().phase, BackendRunPhase.idle);
      expect(server.requests, 0);
      expect(env.runtime.installed, isFalse);
    });
  });

  group('不是安卓', () {
    test('桌面调试 / 宿主机上没装环境：和以前一样直接把命令打进本机 shell，不核对也不装', () async {
      await open(android: false, installed: false);
      ctl().start(language: 'go', command: goCmd);
      await waitFor(() => launched().isNotEmpty, '命令打进终端');
      expect(launched(), ['$goCmd\r']);
      expect(env.guest.scripts, isEmpty);
      expect(run().phase, BackendRunPhase.idle);
    });
  });

  group('“运行环境”页那边', () {
    test('installPack 还是返回装没装成；正在装的时候再装别的返回 false；带原因的结果从 installPackDetailed 拿', () async {
      await open();
      final ctl = env.services.container.read(runtimeProvider.notifier);
      final php = runtimePackById(env.runtime.packs, 'php')!;
      final git = runtimePackById(env.runtime.packs, 'git')!;
      final first = ctl.installPack(php);
      await waitFor(() => env.guest.installs.isNotEmpty, '开始装');
      expect(env.services.container.read(runtimeProvider).runningPack, 'php');
      expect(await ctl.installPack(git), isFalse);
      final busy = await ctl.installPackDetailed(git);
      expect(busy.failure, PackFailure.busy);
      expect(env.services.container.read(runtimeProvider).packOutput.first, '开始安装 PHP 8.3…', reason: '被拒的那次不动正在装的输出');
      env.guest.installs.single
        ..say('PHP 8.3.6 (cli)\n')
        ..finish(0);
      expect(await first, isTrue);
      final view = env.services.container.read(runtimeProvider);
      expect(view.runningPack, isNull);
      expect(view.packOutput, containsAllInOrder(['开始安装 PHP 8.3…', 'PHP 8.3.6 (cli)', 'PHP 8.3 安装完成。']));
      expect(env.runtime.logLines.join('\n'), contains('安装 PHP 8.3：成功'));
      expect(File('${env.runtime.rootfsDir}/usr/bin/php').existsSync(), isFalse, reason: '假进程什么都没装');
    });

    test('环境没装：装不了，说清原因，不起进程', () async {
      await open(installed: false);
      final result = await env.runtime.installPackDetailed(runtimePackById(env.runtime.packs, 'php')!);
      expect(result.failure, PackFailure.notUsable);
      expect(env.guest.scripts, isEmpty);
    });
  });
}
