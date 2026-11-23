// 本机 Linux 运行环境里能在主机上验证的部分：断点续传、校验、解压、PRoot 参数、
// 启动失败回退、Agent 命令走向。PRoot 本身在手机上能不能跑，这里验证不了。
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:lopicode/core/stores.dart';
import 'package:lopicode/runtime/linux_command_runner.dart';
import 'package:lopicode/runtime/linux_runtime.dart';
import 'package:lopicode/runtime/linux_shell_backend.dart';
import 'package:lopicode/runtime/proot_command.dart';
import 'package:lopicode/runtime/resumable_download.dart';
import 'package:lopicode/runtime/runtime_sources.dart';
import 'package:lopicode/runtime/tar_extract.dart';
import 'package:lopicode/terminal/terminal_session.dart';
import 'package:path/path.dart' as p;

import 'support/runtime_fakes.dart';

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('lopi_rt_'));
  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  group('断点续传下载', () {
    late Uint8List payload;
    late String digest;
    late FileServer server;
    late http.Client client;

    setUp(() async {
      payload = Uint8List.fromList(List.generate(300000, (i) => (i * 31 + 7) & 0xff));
      digest = sha256.convert(payload).toString();
      server = await FileServer.start({'/file.bin': payload});
      client = http.Client();
    });
    tearDown(() async {
      client.close();
      await server.close();
    });

    Future<void> fetch(File target, {CancelToken? cancel, String? sha, void Function(int, int)? onProgress}) =>
        ResumableDownload(client).fetch(server.uri('/file.bin'), target, expectedSize: payload.length, expectedSha256: sha ?? digest, cancel: cancel, onProgress: onProgress);

    test('一次下完：内容一致，没有残留的 .part', () async {
      final target = File(p.join(tmp.path, 'a.bin'));
      var last = 0;
      await fetch(target, onProgress: (r, t) => last = r);
      expect(target.readAsBytesSync(), payload);
      expect(ResumableDownload.partFile(target).existsSync(), isFalse);
      expect(last, payload.length);
    });

    test('连接中途断开：报真实原因并保留已下载部分，重试只请求剩下的', () async {
      final target = File(p.join(tmp.path, 'a.bin'));
      server.dropAfter = 100000;
      await expectLater(fetch(target), throwsA(isA<DownloadException>().having((e) => e.message, 'message', contains('下载中断'))));
      final part = ResumableDownload.partFile(target);
      expect(part.existsSync(), isTrue);
      final have = part.lengthSync();
      expect(have, greaterThan(0));
      expect(have, lessThan(payload.length));

      server.dropAfter = null;
      await fetch(target);
      expect(target.readAsBytesSync(), payload);
      expect(server.ranges.last, 'bytes=$have-');
    });

    test('服务器不支持续传（回 200）：从头重下，结果仍然正确', () async {
      final target = File(p.join(tmp.path, 'a.bin'));
      ResumableDownload.partFile(target).writeAsBytesSync(payload.sublist(0, 5000));
      server.ignoreRange = true;
      await fetch(target);
      expect(target.readAsBytesSync(), payload);
    });

    test('已有的半截文件是坏的：校验不过，删掉并报错，不会当成好文件', () async {
      final target = File(p.join(tmp.path, 'a.bin'));
      ResumableDownload.partFile(target).writeAsBytesSync(Uint8List(5000)); // 全是 0，和真内容不一样
      await expectLater(fetch(target), throwsA(isA<DownloadException>().having((e) => e.message, 'message', contains('校验不一致'))));
      expect(target.existsSync(), isFalse);
      expect(ResumableDownload.partFile(target).existsSync(), isFalse);
      await fetch(target); // 再来一次从头下，成功
      expect(target.readAsBytesSync(), payload);
    });

    test('半截文件比整个文件还大（服务器回 416 的情形）：丢掉重下', () async {
      final target = File(p.join(tmp.path, 'a.bin'));
      ResumableDownload.partFile(target).writeAsBytesSync(Uint8List(payload.length + 10));
      await fetch(target);
      expect(target.readAsBytesSync(), payload);
    });

    test('连接卡死（一直不来数据）：到时限就停下报错，不会无限等；重试接着下', () async {
      final target = File(p.join(tmp.path, 'a.bin'));
      server.stallAfter = 40000;
      await expectLater(
        ResumableDownload(client, stallTimeout: const Duration(milliseconds: 400)).fetch(server.uri('/file.bin'), target, expectedSize: payload.length, expectedSha256: digest),
        throwsA(isA<DownloadException>().having((e) => e.message, 'message', contains('没有收到数据'))),
      );
      expect(ResumableDownload.partFile(target).lengthSync(), greaterThan(0));
      server.stallAfter = null;
      await fetch(target);
      expect(target.readAsBytesSync(), payload);
    });

    test('服务器报错：提示里带状态码', () async {
      final target = File(p.join(tmp.path, 'a.bin'));
      await expectLater(
        ResumableDownload(client).fetch(server.uri('/nope'), target, expectedSize: 10, expectedSha256: digest),
        throwsA(isA<DownloadException>().having((e) => e.message, 'message', contains('HTTP 404'))),
      );
    });

    test('连不上：提示里带主机名', () async {
      final target = File(p.join(tmp.path, 'a.bin'));
      final port = server.port;
      await server.close();
      await expectLater(
        ResumableDownload(client).fetch(Uri.parse('http://127.0.0.1:$port/file.bin'), target, expectedSize: 10, expectedSha256: digest),
        throwsA(isA<DownloadException>().having((e) => e.message, 'message', contains('连不上下载源 127.0.0.1'))),
      );
    });

    test('取消：保留半截文件，下次接着下', () async {
      final target = File(p.join(tmp.path, 'a.bin'));
      final cancel = CancelToken();
      server.chunkDelay = const Duration(milliseconds: 5);
      await expectLater(
        fetch(
          target,
          cancel: cancel,
          onProgress: (r, t) {
            if (r > 50000) cancel.cancel();
          },
        ),
        throwsA(isA<DownloadException>().having((e) => e.cancelled, 'cancelled', isTrue)),
      );
      expect(ResumableDownload.partFile(target).lengthSync(), greaterThan(0));
      server.chunkDelay = null;
      await fetch(target);
      expect(target.readAsBytesSync(), payload);
      expect(server.ranges.last, startsWith('bytes='));
    });
  });

  group('解压 tar.gz', () {
    test('文件、目录、可执行位、符号链接、硬链接、超长文件名', () async {
      final archive = await makeSampleRootfs(tmp);
      final out = Directory(p.join(tmp.path, 'out'));
      final result = await extractTarGz(archive, out);
      expect(File(p.join(out.path, 'etc/os-release')).readAsStringSync(), contains('Ubuntu'));
      expect(File(p.join(out.path, 'usr/bin/hello')).statSync().mode & 0x49, isNot(0), reason: '可执行位要保留');
      expect(File(p.join(out.path, 'etc/os-release')).statSync().mode & 0x49, 0);
      expect(Link(p.join(out.path, 'bin')).targetSync(), 'usr/bin');
      expect(Link(p.join(out.path, 'etc/resolv.conf')).targetSync(), '../run/resolv.conf');
      // 硬链接按复制处理：内容一样，也带可执行位
      final copy = File(p.join(out.path, 'usr/bin/hello2'));
      expect(copy.readAsStringSync(), File(p.join(out.path, 'usr/bin/hello')).readAsStringSync());
      expect(copy.statSync().mode & 0x49, isNot(0));
      expect(FileSystemEntity.isLinkSync(copy.path), isFalse);
      final long = Directory(p.join(out.path, 'usr/share')).listSync(recursive: true).whereType<File>().singleWhere((f) => f.path.endsWith('.txt'));
      expect(p.basename(long.path).length, greaterThan(100));
      expect(result.hardlinks, 1);
      expect(result.symlinks, 2);
      expect(result.files, greaterThanOrEqualTo(3));
    });

    test('压缩包被截断：报“不完整”，不会悄悄当成功', () async {
      final archive = await makeSampleRootfs(tmp);
      final bytes = archive.readAsBytesSync();
      final cut = File(p.join(tmp.path, 'cut.tar.gz'))..writeAsBytesSync(bytes.sublist(0, bytes.length ~/ 2));
      await expectLater(extractTarGz(cut, Directory(p.join(tmp.path, 'o2'))), throwsA(isA<TarException>()));
    });

    test('想写到目标目录外面的条目被拒绝', () async {
      final evil = File(p.join(tmp.path, 'evil.tar.gz'))..writeAsBytesSync(gzip.encode([...tarHeader('../escape.txt', 5), ...utf8.encode('hello'), ...Uint8List(507), ...Uint8List(1024)]));
      await expectLater(extractTarGz(evil, Directory(p.join(tmp.path, 'o3'))), throwsA(isA<TarException>().having((e) => e.message, 'message', contains('越界'))));
      expect(File(p.join(tmp.path, 'escape.txt')).existsSync(), isFalse);
    });

    test('真实的 Ubuntu 24.04 arm64 基础包：能完整解开（本机有这个文件时才跑）', () async {
      final real = File('${Platform.environment['HOME']}/workspace/tools/dl/rootfs/${RootfsImage.ubuntu2404Arm64.fileName}');
      if (!real.existsSync()) {
        markTestSkipped('本机没有下载过基础包');
        return;
      }
      expect(real.lengthSync(), RootfsImage.ubuntu2404Arm64.size);
      expect(await sha256Of(real), RootfsImage.ubuntu2404Arm64.sha256);
      final out = Directory(p.join(tmp.path, 'ubuntu'));
      final result = await extractTarGz(real, out);
      expect(File(p.join(out.path, 'usr/bin/bash')).statSync().mode & 0x49, isNot(0));
      expect(Link(p.join(out.path, 'bin')).targetSync(), 'usr/bin');
      expect(File(p.join(out.path, 'usr/bin/env')).existsSync(), isTrue, reason: '启动命令要用 /usr/bin/env');
      expect(File(p.join(out.path, 'usr/bin/uncompress')).existsSync(), isTrue, reason: '包里的硬链接');
      expect(File(p.join(out.path, 'usr/share/keyrings/ubuntu-archive-keyring.gpg')).existsSync(), isTrue);
      // ignore: avoid_print
      print(
        '真实基础包：${result.files} 个文件，${result.directories} 个目录，${result.symlinks} 个符号链接，'
        '${result.hardlinks} 个硬链接，跳过 ${result.skipped}，文件内容共 ${result.bytes} 字节',
      );
    }, timeout: const Timeout(Duration(minutes: 5)));
  });

  group('PRoot 启动命令', () {
    final command = buildProotCommand(
      nativeLibDir: '/data/app/x/lib/arm64',
      libDir: '/data/user/0/com.lopicode.app/files/runtime/hostlib',
      rootfs: '/data/user/0/com.lopicode.app/files/runtime/rootfs',
      tmpDir: '/data/user/0/com.lopicode.app/files/runtime/tmp',
      guestCommand: guestLoginShell,
      projectDir: '/data/user/0/com.lopicode.app/app_flutter/projects/demo',
    );

    test('可执行文件和加载器都指向安装包的原生库目录', () {
      expect(command.executable, '/data/app/x/lib/arm64/libproot.so');
      expect(command.environment['PROOT_LOADER'], '/data/app/x/lib/arm64/libproot-loader.so');
      expect(command.environment['PROOT_TMP_DIR'], endsWith('/runtime/tmp'));
      // PRoot 依赖的两个库：先找放了 libtalloc.so.2 链接的目录，再找安装包的原生库目录
      expect(command.environment['LD_LIBRARY_PATH'], '/data/user/0/com.lopicode.app/files/runtime/hostlib:/data/app/x/lib/arm64');
      expect(command.environment['LD_PRELOAD'], '');
      expect(command.environment.containsKey('PROOT_NO_SECCOMP'), isFalse);
    });

    test('根目录、绑定、工作目录、假 root、硬链接替换', () {
      final a = command.arguments;
      expect(a.sublist(0, 3), ['--kill-on-exit', '--link2symlink', '-0']);
      expect(a[a.indexOf('-r') + 1], endsWith('/runtime/rootfs'));
      final binds = [
        for (var i = 0; i < a.length; i++)
          if (a[i] == '-b') a[i + 1],
      ];
      expect(binds, containsAll(['/dev', '/proc', '/sys']));
      expect(binds, contains('/data/user/0/com.lopicode.app/app_flutter/projects/demo:/workspace'));
      expect(binds, contains(endsWith('/runtime/rootfs/tmp:/dev/shm')));
      expect(a[a.indexOf('-w') + 1], '/workspace');
    });

    test('环境里的命令用 env -i 清空变量，只留指定的几个', () {
      final a = command.arguments;
      final env = a.indexOf('/usr/bin/env');
      expect(a[env + 1], '-i');
      final vars = a.sublist(env + 2, a.length - 2);
      expect(vars, containsAll(['HOME=/root', 'TMPDIR=/tmp', 'LANG=C.UTF-8', 'TERM=xterm-256color', 'PATH=$guestPath']));
      expect(vars.every((v) => v.contains('=')), isTrue);
      expect(vars.any((v) => v.startsWith('LD_')), isFalse);
      expect(a.sublist(a.length - 2), ['/bin/bash', '-l']);
    });

    test('兼容模式加 PROOT_NO_SECCOMP；没有项目时工作目录是 /root', () {
      final c = buildProotCommand(nativeLibDir: '/n', libDir: '/l', rootfs: '/r', tmpDir: '/t', guestCommand: guestRun('echo hi'), noSeccomp: true);
      expect(c.environment['PROOT_NO_SECCOMP'], '1');
      expect(c.arguments[c.arguments.indexOf('-w') + 1], '/root');
      expect(c.arguments.sublist(c.arguments.length - 3), ['/bin/bash', '-lc', 'echo hi']);
      expect(c.arguments.any((x) => x.endsWith(':/workspace')), isFalse);
    });
  });

  group('下载源', () {
    test('默认是国内镜像，可以换成官方；未知的值退回默认', () {
      expect(mirrorById(rootfsSources, '').id, 'tuna');
      expect(mirrorById(rootfsSources, 'official').base, startsWith('https://cdimage.ubuntu.com/'));
      expect(mirrorById(aptMirrors, 'whatever').id, 'tuna');
    });

    test('apt 源文件是 arm64 的 ubuntu-ports，带安全更新和签名钥匙', () {
      final text = aptSourcesFor(mirrorById(aptMirrors, 'aliyun'));
      expect(text, contains('URIs: http://mirrors.aliyun.com/ubuntu-ports'));
      expect(text, contains('noble-security'));
      expect(text, contains('Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg'));
    });

    test('Node 安装脚本：国内源走 npmmirror，官方源走 nodejs.org，都先核对 sha256', () {
      final cn = runtimePacks('tuna').firstWhere((x) => x.id == 'node').script;
      final official = runtimePacks('official').firstWhere((x) => x.id == 'node').script;
      expect(cn, contains('https://npmmirror.com/mirrors/node/latest-v24.x'));
      expect(official, contains('https://nodejs.org/dist/latest-v24.x'));
      expect(cn, contains('sha256sum -c'));
      expect(cn, contains('linux-arm64'));
    });
  });

  group('安装流程', () {
    late FileServer server;
    late File archive;
    late RootfsImage image;
    late SettingsStore settings;

    setUp(() async {
      archive = await makeSampleRootfs(tmp);
      final bytes = archive.readAsBytesSync();
      image = RootfsImage(version: 'test', fileName: 'rootfs.tar.gz', size: bytes.length, sha256: sha256.convert(bytes).toString());
      server = await FileServer.start({'/rootfs.tar.gz': bytes});
      settings = SettingsStore(File(p.join(tmp.path, 'settings.json')));
    });
    tearDown(() => server.close());

    LinuxRuntime make({FakeRuntimeHost? host}) =>
        LinuxRuntime(settings: settings, baseDir: p.join(tmp.path, 'runtime'), host: host ?? FakeRuntimeHost(), image: image, httpClient: () => RedirectingClient(server.uri('/rootfs.tar.gz')));

    test('下载、校验、解压、配置，最后是“已安装”', () async {
      final runtime = make();
      await runtime.init();
      expect(runtime.phase, RuntimePhase.notInstalled);
      final phases = <RuntimePhase>{};
      runtime.changeListeners.add(() => phases.add(runtime.phase));
      await runtime.install();
      expect(runtime.installError, isNull);
      expect(runtime.phase, RuntimePhase.installed);
      expect(phases, containsAll([RuntimePhase.downloading, RuntimePhase.extracting, RuntimePhase.installed]));
      final root = runtime.rootfsDir;
      expect(File(p.join(root, 'etc/resolv.conf')).readAsStringSync(), contains('nameserver 223.5.5.5'));
      expect(FileSystemEntity.isLinkSync(p.join(root, 'etc/resolv.conf')), isFalse, reason: '原来的符号链接要换成真文件');
      expect(File(p.join(root, 'etc/apt/sources.list.d/ubuntu.sources')).readAsStringSync(), contains('mirrors.tuna.tsinghua.edu.cn/ubuntu-ports'));
      expect(File(p.join(root, 'etc/apt/apt.conf.d/99lopicode')).readAsStringSync(), contains('Sandbox'));
      expect(Directory(p.join(root, 'tmp')).existsSync(), isTrue);
      expect(Directory(runtime.tmpDir).existsSync(), isTrue);
      expect(File(p.join(tmp.path, 'runtime/download/rootfs.tar.gz')).existsSync(), isFalse, reason: '装完删掉压缩包省空间');
      expect(runtime.logLines.join('\n'), contains('解压完成'));

      // 重新打开应用：还是已安装
      final again = make();
      await again.init();
      expect(again.installed, isTrue);

      // 换软件源：文件跟着改
      await again.setAptMirror('official');
      expect(File(p.join(root, 'etc/apt/sources.list.d/ubuntu.sources')).readAsStringSync(), contains('ports.ubuntu.com'));

      // 运行时是否已装：看环境里有没有那个文件
      final python = again.packs.firstWhere((x) => x.id == 'python');
      expect(again.packInstalled(python), isFalse);
      File(p.join(root, 'usr/bin/python3')).writeAsStringSync('x');
      expect(again.packInstalled(python), isTrue);

      // 卸载：整个目录没了
      await again.uninstall();
      expect(again.phase, RuntimePhase.notInstalled);
      expect(Directory(p.join(tmp.path, 'runtime')).existsSync(), isFalse);
    });

    test('空间不够：不下载，直接说差多少', () async {
      final runtime = make(host: FakeRuntimeHost(free: 20 * 1024 * 1024));
      await runtime.init();
      await runtime.install();
      expect(runtime.phase, RuntimePhase.notInstalled);
      expect(runtime.installError, contains('剩余空间不够'));
      expect(runtime.installError, contains('20.0 MB'));
      expect(server.requests, 0);
    });

    test('下载中断：状态回到未安装，原因如实显示，再点一次接着下', () async {
      final runtime = make();
      await runtime.init();
      server.dropAfter = image.size ~/ 2;
      await runtime.install();
      expect(runtime.phase, RuntimePhase.notInstalled);
      expect(runtime.installError, contains('下载中断'));
      expect(runtime.partialBytes, greaterThan(0));
      server.dropAfter = null;
      await runtime.install();
      expect(runtime.installed, isTrue);
      expect(server.ranges.last, startsWith('bytes='));
    });

    test('下载源给的文件不对：校验不过，不解压', () async {
      final runtime = LinuxRuntime(
        settings: settings,
        baseDir: p.join(tmp.path, 'runtime'),
        host: FakeRuntimeHost(),
        image: RootfsImage(version: 't', fileName: 'rootfs.tar.gz', size: image.size, sha256: 'f' * 64),
        httpClient: () => RedirectingClient(server.uri('/rootfs.tar.gz')),
      );
      await runtime.init();
      await runtime.install();
      expect(runtime.installError, contains('校验不一致'));
      expect(Directory(runtime.rootfsDir).existsSync(), isFalse);
    });

    test('安装包里没有 PRoot：能装，但不会自动进 Ubuntu', () async {
      final runtime = make(host: FakeRuntimeHost(nativeDir: tmp.path));
      await runtime.init();
      await runtime.install();
      expect(runtime.installed, isTrue);
      expect(runtime.prootBundled, isFalse);
      expect(runtime.shouldUseLinux, isFalse);
    });
  });

  group('PRoot 随包文件和依赖库', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('lopi_launcher'));
    tearDown(() => tmp.deleteSync(recursive: true));

    LinuxRuntime make(String? nativeDir) => LinuxRuntime(
      settings: SettingsStore(File(p.join(tmp.path, 's.json'))),
      baseDir: p.join(tmp.path, 'runtime'),
      host: FakeRuntimeHost(nativeDir: nativeDir),
    );

    test('四个文件齐全才算带了 PRoot；缺哪个说哪个', () async {
      final native = makeFakeNativeDir(tmp);
      final runtime = make(native);
      await runtime.init();
      expect(runtime.prootBundled, isTrue);
      expect(runtime.missingLauncherFiles, isEmpty);

      File(p.join(native, 'libtalloc.so')).deleteSync();
      await runtime.init();
      expect(runtime.prootBundled, isFalse);
      expect(runtime.missingLauncherFiles, ['libtalloc.so']);

      final none = make(null);
      await none.init();
      expect(none.missingLauncherFiles, ['libproot.so', 'libproot-loader.so', 'libtalloc.so', 'libandroid-shmem.so']);
    });

    test('libtalloc.so.2 链接：第一次建好，重复调用不动它', () async {
      final native = makeFakeNativeDir(tmp);
      final runtime = make(native);
      await runtime.init();
      expect(runtime.prepareLauncherLibs(), isNull);
      final link = Link(p.join(runtime.hostLibDir, 'libtalloc.so.2'));
      expect(link.targetSync(), p.join(native, 'libtalloc.so'));
      expect(runtime.prepareLauncherLibs(), isNull);
      expect(link.targetSync(), p.join(native, 'libtalloc.so'));
    });

    test('应用更新后原生库目录换了地方：链接跟着改过去', () async {
      final native = makeFakeNativeDir(tmp);
      final runtime = make(native);
      await runtime.init();
      runtime.prepareLauncherLibs();
      final moved = Directory(p.join(tmp.path, 'nativelib-v2'))..createSync();
      for (final f in Directory(native).listSync().whereType<File>()) {
        f.copySync(p.join(moved.path, p.basename(f.path)));
      }
      File(p.join(moved.path, 'libtalloc.so')).writeAsStringSync('talloc-v2');
      runtime.nativeLibDir = moved.path;
      expect(runtime.prepareLauncherLibs(), isNull);
      expect(Link(p.join(runtime.hostLibDir, 'libtalloc.so.2')).targetSync(), p.join(moved.path, 'libtalloc.so'));
      expect(File(p.join(runtime.hostLibDir, 'libtalloc.so.2')).readAsStringSync(), 'talloc-v2');
    });

    test('卸载环境后链接目录没了：下次拼命令时自动重建', () async {
      final native = makeFakeNativeDir(tmp);
      final runtime = make(native);
      markInstalled(runtime);
      await runtime.init();
      runtime.prootCommand(guestCommand: guestLoginShell);
      expect(Directory(runtime.hostLibDir).existsSync(), isTrue);
      await runtime.uninstall();
      expect(Directory(runtime.hostLibDir).existsSync(), isFalse);
      final command = runtime.prootCommand(guestCommand: guestLoginShell);
      expect(command.environment['LD_LIBRARY_PATH'], '${runtime.hostLibDir}:$native');
      expect(File(p.join(runtime.hostLibDir, 'libtalloc.so.2')).existsSync(), isTrue);
    });

    test('上次是复制的旧文件（不是链接）：大小不同就换成新的', () async {
      final native = makeFakeNativeDir(tmp);
      final runtime = make(native);
      await runtime.init();
      Directory(runtime.hostLibDir).createSync(recursive: true);
      File(p.join(runtime.hostLibDir, 'libtalloc.so.2')).writeAsStringSync('old-copy-of-different-size');
      expect(runtime.prepareLauncherLibs(), isNull);
      expect(File(p.join(runtime.hostLibDir, 'libtalloc.so.2')).readAsStringSync(), 'talloc');
    });

    test('拿不到原生库目录：返回原因，不抛异常', () async {
      final runtime = make(null);
      await runtime.init();
      expect(runtime.prepareLauncherLibs(), isNotNull);
    });
  });

  group('启动失败回退', () {
    late LinuxRuntime runtime;
    late FakeRuntimeHost host;

    setUp(() async {
      host = FakeRuntimeHost(nativeDir: makeFakeNativeDir(tmp));
      runtime = LinuxRuntime(settings: SettingsStore(File(p.join(tmp.path, 's.json'))), baseDir: p.join(tmp.path, 'runtime'), host: host);
      markInstalled(runtime);
      await runtime.init();
      expect(runtime.shouldUseLinux, isTrue);
    });

    test('正常启动：进 Ubuntu，稳定后记成功，开着的时候挂保活，关掉就撤', () async {
      final spawned = <FakePty>[];
      final backend = LinuxShellBackend(
        runtime: runtime,
        projectDir: tmp.path,
        quickExit: const Duration(milliseconds: 50),
        spawner: (exe, args, {required workingDirectory, required environment, required rows, required columns}) {
          expect(exe, endsWith('libproot.so'));
          expect(args, containsAllInOrder(['-r', runtime.rootfsDir]));
          expect(args.sublist(args.length - 2), ['/bin/bash', '-l']);
          expect(environment['PROOT_LOADER'], endsWith('libproot-loader.so'));
          final pty = FakePty();
          spawned.add(pty);
          return pty;
        },
      );
      final seen = StringBuffer();
      backend.output.listen(seen.write);
      await backend.start(columns: 80, rows: 24);
      expect(backend.label, 'Ubuntu');
      expect(host.keepAlive, isTrue);
      spawned.single.emit('root@localhost:/workspace# ');
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(runtime.launchFailures, 0);
      backend.write('ls\r');
      expect(utf8.decode(spawned.single.written), 'ls\r');
      expect(seen.toString(), contains('root@localhost'));
      await backend.close();
      await Future<void>.delayed(Duration.zero);
      expect(host.keepAlive, isFalse);
      expect(spawned.single.killed, isTrue);
    });

    test('第一次失败提示重试并改用兼容模式；第二次失败退回本机 shell 并说明原因', () async {
      final envs = <Map<String, String>>[];
      final local = <FakePty>[];
      final backend = LinuxShellBackend(
        runtime: runtime,
        projectDir: tmp.path,
        spawner: (exe, args, {required workingDirectory, required environment, required rows, required columns}) {
          envs.add(environment);
          return FakePty()
            ..emit('proot error: execve("/usr/bin/env"): Permission denied\r\n')
            ..exit(255);
        },
        fallbackSpawner: (exe, {required workingDirectory, required environment, required rows, required columns}) {
          final pty = FakePty();
          local.add(pty);
          return pty;
        },
      );
      final seen = StringBuffer();
      backend.output.listen(seen.write);
      await backend.start(columns: 80, rows: 24);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(runtime.launchFailures, 1);
      expect(seen.toString(), contains('按回车再试一次'));
      expect(backend.usingFallback, isFalse);
      expect(envs.single.containsKey('PROOT_NO_SECCOMP'), isFalse);

      backend.write('\r'); // 回车重试
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(envs.length, 2);
      expect(envs.last['PROOT_NO_SECCOMP'], '1', reason: '第二次要用兼容模式');
      expect(runtime.launchFailures, 2);
      expect(runtime.shouldUseLinux, isFalse);
      expect(backend.usingFallback, isTrue);
      expect(backend.label, '本机');
      expect(seen.toString(), contains('已退回手机自带的 sh'));
      expect(seen.toString(), contains('退出码 255'));
      expect(local.single, isNotNull);
      backend.write('pwd\r');
      expect(utf8.decode(local.single.written), 'pwd\r', reason: '退回后键盘输入要进本机 shell，不能卡死');
      expect(runtime.logLines.join('\n'), contains('Permission denied'), reason: 'PRoot 的输出要进日志');
      expect(host.keepAlive, isFalse);

      // 用户在“运行环境”页点重新尝试：计数清零，下次新会话又会进 Ubuntu
      runtime.resetLaunchFailures();
      expect(runtime.shouldUseLinux, isTrue);
      await backend.close();
    });

    test('伪终端里根本起不来（抛异常）也算失败，不会抛到界面上', () async {
      final backend = LinuxShellBackend(
        runtime: runtime,
        projectDir: tmp.path,
        spawner: (exe, args, {required workingDirectory, required environment, required rows, required columns}) => throw StateError('libflutter_pty.so not found'),
        fallbackSpawner: (exe, {required workingDirectory, required environment, required rows, required columns}) => FakePty(),
      );
      await backend.start(columns: 80, rows: 24);
      expect(runtime.launchFailures, 1);
      expect(runtime.lastLaunchError, contains('libflutter_pty.so'));
      await backend.close();
    });

    test('兼容模式救回来之后记住，以后直接用兼容模式', () async {
      runtime.recordLaunchFailure('x');
      expect(runtime.compatMode, isTrue);
      runtime.recordLaunchSuccess();
      // 设置是“不等结果”写盘的：等它真的落盘，否则机器忙时收尾删临时目录会抢在写盘前面。
      for (var i = 0; i < 100 && !(runtime.settings.file.existsSync() && runtime.settings.file.readAsStringSync().contains('true')); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(runtime.launchFailures, 0);
      expect(runtime.settings.getBool(SettingKeys.runtimeCompat), isTrue);
      expect(runtime.prootCommand(guestCommand: guestLoginShell).environment['PROOT_NO_SECCOMP'], '1');
    });

    test('正常退出（exit）不算失败', () async {
      late FakePty pty;
      final backend = LinuxShellBackend(
        runtime: runtime,
        projectDir: tmp.path,
        spawner: (exe, args, {required workingDirectory, required environment, required rows, required columns}) => pty = FakePty(),
      );
      final seen = StringBuffer();
      backend.output.listen(seen.write);
      await backend.start(columns: 80, rows: 24);
      pty.exit(0);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(runtime.launchFailures, 0);
      expect(seen.toString(), contains('按回车重新进入'));
      await backend.close();
    });
  });

  group('Agent 的 run_command', () {
    test('环境没装：走手机自带的 sh，时限 60 秒', () async {
      final runtime = LinuxRuntime(settings: SettingsStore(File(p.join(tmp.path, 's.json'))), baseDir: p.join(tmp.path, 'runtime'));
      await runtime.init();
      final echoed = StringBuffer();
      final runner = LinuxCommandRunner(runtime, onOutput: echoed.write);
      expect(runner.commandTimeout, const Duration(seconds: 60));
      final result = await runner.run('echo local-\$((1+1))', workingDirectory: tmp.path);
      expect(result.output.trim(), 'local-2');
      expect(echoed.toString(), contains('[Agent] \$'));
    });

    test('环境可用：命令交给 PRoot，在 /workspace（项目目录）里用 bash 执行，时限 5 分钟', () async {
      final host = FakeRuntimeHost(nativeDir: makeFakeNativeDir(tmp));
      final runtime = LinuxRuntime(settings: SettingsStore(File(p.join(tmp.path, 's.json'))), baseDir: p.join(tmp.path, 'runtime'), host: host);
      markInstalled(runtime);
      await runtime.init();
      final echoed = StringBuffer();
      final runner = LinuxCommandRunner(runtime, onOutput: echoed.write);
      expect(runner.commandTimeout, const Duration(minutes: 5));
      final project = Directory(p.join(tmp.path, 'proj'))..createSync();
      // 假的 libproot.so 是个脚本：把收到的参数和环境变量打印出来
      final result = await runner.run('node -v', workingDirectory: project.path);
      expect(result.exitCode, 0);
      expect(result.output, contains('-b ${project.path}:/workspace'));
      expect(result.output, contains('-w /workspace'));
      expect(result.output, contains('/bin/bash -lc node -v'));
      expect(result.output, contains('LOADER=${p.join(host.nativeDir!, 'libproot-loader.so')}'));
      expect(result.output, contains('LIBPATH=${runtime.hostLibDir}:${host.nativeDir!}'));
      // PRoot 本体要找的 libtalloc.so.2 已经指向安装包里的 libtalloc.so
      expect(File(p.join(runtime.hostLibDir, 'libtalloc.so.2')).readAsStringSync(), 'talloc');
      expect(result.output, contains('HOSTPATH=unset'), reason: '不能把应用自己的环境变量带进去');
      expect(echoed.toString(), contains('[Agent · Ubuntu] \$ node -v'));
      expect(host.keepAliveStarts, 1);
      expect(host.keepAlive, isFalse);
    });

    test('连续启动失败后：Agent 的命令也退回本机 sh', () async {
      final host = FakeRuntimeHost(nativeDir: makeFakeNativeDir(tmp));
      final runtime = LinuxRuntime(settings: SettingsStore(File(p.join(tmp.path, 's.json'))), baseDir: p.join(tmp.path, 'runtime'), host: host);
      markInstalled(runtime);
      await runtime.init();
      runtime
        ..recordLaunchFailure('a')
        ..recordLaunchFailure('b');
      final result = await LinuxCommandRunner(runtime).run('echo fallback', workingDirectory: tmp.path);
      expect(result.output.trim(), 'fallback');
    });
  });

  test('终端会话标题跟着后端走', () {
    final runtime = LinuxRuntime(settings: SettingsStore(File(p.join(tmp.path, 's.json'))), baseDir: p.join(tmp.path, 'runtime'));
    final session = TerminalSession(
      title: 'Ubuntu 1',
      backend: LinuxShellBackend(runtime: runtime, projectDir: tmp.path),
    );
    expect(session.backend.label, 'Ubuntu');
    session.dispose();
  });
}
