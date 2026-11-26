// 界面用的生产实现（RealLocalPackBackend）走真流程，不用任何替身打包器：
//   一、后端本身：读应用自带的模板 → 现生成一把钥匙 → 导出备份再导入 → 坏模板报明确的错；
//   二、经过界面的状态层（LocalPackNotifier / SigningKeyNotifier，就是打包页按钮背后那一层）对三个样例项目真打包：
//       纯静态页（应用自己的“前端网页”模板）、低代码导出（应用自己的“低代码页面”模板）、带子目录和大图的；
//       中文应用名、很长的包名、换图标、增减权限、升级包沿用同一把钥匙；
//   三、坏输入：非法包名、超限的项目、不适用的项目，都有明确的说法。
// 每个产物交给官方 apksigner / aapt2 / zipalign 核对；找不到官方工具时这些核对 skip 并写明原因。不联网。
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/apkpack/apk_pack_contract.dart';
import 'package:lopicode/build/apk_output.dart';
import 'package:lopicode/build/local_pack_backend.dart';
import 'package:lopicode/build/local_pack_backend_real.dart';
import 'package:lopicode/core/project_store.dart';
import 'package:lopicode/core/safe_file.dart';
import 'package:lopicode/core/stores.dart';
import 'package:lopicode/core/templates.dart';
import 'package:lopicode/project_session.dart';
import 'package:lopicode/state/local_pack.dart';
import 'package:lopicode/state/signing_key.dart';
import 'package:path/path.dart' as p;

import 'support/apkpack_kit.dart';
import 'support/harness.dart';

const _internet = 'android.permission.INTERNET';
const _camera = 'android.permission.CAMERA';
const _fine = 'android.permission.ACCESS_FINE_LOCATION';
const _coarse = 'android.permission.ACCESS_COARSE_LOCATION';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final tools = AndroidTools.find();
  const real = RealLocalPackBackend();

  /// 整个文件共用一把真钥匙（生成一把要几秒）；“第一次打包自动生成”那条用例自己另生成。
  String? sharedKey;
  Future<String> keyText() async => sharedKey ??= (await real.generateKey(commonName: 'LopiCode App Key')).serialize();

  /// 官方工具核对一个产物。JDK 在这台机器的默认语言环境下打不开中文文件名，所以先抄成英文名再验（内容逐字节相同）。
  void checkOfficial(ApkPackResult r, {required Set<String> permissions, required String cert, Map<int, Uint8List> icons = const {}}) {
    if (tools.missing != null) {
      markTestSkipped(tools.missing!);
      return;
    }
    final bytes = File(r.path).readAsBytesSync();
    expect(sha256.convert(bytes).toString(), r.sha256Hex);
    final copy = p.join(Directory.systemTemp.createTempSync('apkpack_chk_').path, 'check.apk');
    addTearDown(() => File(copy).parent.deleteSync(recursive: true));
    File(copy).writeAsBytesSync(bytes);
    String run(String tool, List<String> args) {
      final x = tools.run(tool, args);
      return '${x.stdout}${x.stderr}';
    }

    expect(run('zipalign', ['-c', '-v', '4', copy]), contains('Verification succes'));
    final v = run('apksigner', ['verify', '--verbose', '--print-certs', '--min-sdk-version', '21', copy]);
    expect(v, contains('Verifies'));
    expect(v, contains('Verified using v1 scheme (JAR signing): true'));
    expect(v, contains('Verified using v2 scheme (APK Signature Scheme v2): true'));
    expect(v, contains('certificate SHA-256 digest: $cert'));
    expect(run('apksigner', ['verify', '--min-sdk-version', '24', copy]), isNot(contains('DOES NOT VERIFY')));
    final b = run('aapt2', ['dump', 'badging', copy]);
    expect(b, contains("package: name='${r.packageName}' versionCode='${r.versionCode}' versionName='${r.versionName}'"));
    expect(b.replaceAll(r'\"', '"'), contains("application-label:'${r.appName}'"));
    expect({for (final m in RegExp(r"^uses-permission: name='([^']*)'", multiLine: true).allMatches(b)) m.group(1)!}, permissions);
    expect(b, contains("application-icon-640:'res/mipmap-xxxhdpi/ic_launcher.png'"));
    expect(b, contains("launchable-activity: name='lopi.shell.MainActivity'"));
    for (final e in icons.entries) {
      final dpi = const {48: 'mdpi', 72: 'hdpi', 96: 'xhdpi', 144: 'xxhdpi', 192: 'xxxhdpi'}[e.key]!;
      final unzip = Process.runSync('unzip', ['-p', copy, 'res/mipmap-$dpi/ic_launcher.png'], stdoutEncoding: null);
      expect(sha256.convert(unzip.stdout as List<int>).toString(), sha256.convert(e.value).toString(), reason: '$dpi 的图标就是界面缩好的那张');
    }
  }

  /// 包里放了哪些网页文件。
  List<String> webFilesIn(String apk) {
    final r = Process.runSync('unzip', ['-Z1', apk]);
    return [
      for (final l in (r.stdout as String).split('\n'))
        if (l.startsWith('assets/www/')) l.substring('assets/www/'.length),
    ]..sort();
  }

  group('后端本身', () {
    test('模板就是随应用发的那份；钥匙生成、存取、备份往返；口令不对进不来', () async {
      final template = await real.loadTemplate();
      expect(sha256.convert(template).toString(), sha256.convert(File(kApkShellAsset).readAsBytesSync()).toString());

      final key = real.parseKey(await keyText());
      expect(key.certSha256Hex, hasLength(64));
      final backup = await real.exportKey(key, '口令 passphrase 1');
      expect(backup, isNot(contains(key.serialize().split('\n')[1])), reason: '备份里不是明文私钥');
      final back = await real.importKey(backup, '口令 passphrase 1');
      expect(back.certSha256Hex, key.certSha256Hex);
      await expectLater(real.importKey(backup, '不对的口令 123'), throwsA(isA<ApkPackException>()));
      await expectLater(real.importKey('随便一段不是备份的文字', '口令 passphrase 1'), throwsA(anyOf(isA<ApkPackException>(), isA<FormatException>())));
    }, timeout: const Timeout(Duration(minutes: 15)));

    test('模板坏了：报“模板损坏或不匹配”，指向 template，不留半截文件', () async {
      final tmp = Directory.systemTemp.createTempSync('apkpack_real_');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final root = p.join(tmp.path, 'proj');
      sampleStatic(root);
      final key = real.parseKey(await keyText());
      final good = await real.loadTemplate();
      final out = p.join(root, 'build', 'x.apk');
      for (final bad in [Uint8List.fromList(List.filled(300, 7)), Uint8List.sublistView(good, 0, good.length ~/ 2)]) {
        await expectLater(
          real.pack(template: bad, key: key, request: requestFor(root, out)),
          throwsA(isA<ApkPackException>().having((e) => e.field, 'field', 'template').having((e) => e.message, 'message', contains('模板'))),
        );
      }
      expect(Directory(p.join(root, 'build')).existsSync() ? Directory(p.join(root, 'build')).listSync() : const [], isEmpty);
    }, timeout: const Timeout(Duration(minutes: 15)));
  });

  group('经过状态层（打包页按钮背后那一层）', () {
    late TestEnv env;
    final sessions = <ProjectSession>[];

    setUp(() async {
      env = await TestEnv.create();
      localPackBackendOverride = null; // 就用生产实现
      externalFilesDirOverride = () async => p.join(env.tmp.path, 'external');
    });
    tearDown(() async {
      for (final s in sessions) {
        s.dispose();
      }
      sessions.clear();
      await pendingWrites();
      await env.dispose();
      externalFilesDirOverride = null;
    });

    Future<(ProjectSession, LocalPackNotifier)> open(String name, ProjectTemplate template, {bool withKey = true}) async {
      if (withKey) await env.services.secrets.write(SecretKeys.apkSigningKey, await keyText());
      final Project project = await env.services.projects.create(name, template);
      final session = ProjectSession(env.services, project, headless: true);
      sessions.add(session);
      final n = env.services.container.read(localPackProvider(session).notifier);
      await n.load();
      return (session, n);
    }

    LocalPackState stateOf(ProjectSession s) => env.services.container.read(localPackProvider(s));

    test('样例一 纯静态页（“前端网页”模板）：第一次打包自动生成钥匙，中文应用名、默认包名、只联网', () async {
      final (session, n) = await open('我的小站', ProjectTemplate.web, withKey: false);
      expect(stateOf(session).project!.applicable, isTrue, reason: stateOf(session).project!.reason);
      expect(stateOf(session).project!.kind, 'static');
      expect(await env.services.secrets.read(SecretKeys.apkSigningKey), isNull);

      final phases = <LocalPackPhase>{};
      final steps = <ApkPackStep>{};
      env.services.container.listen(localPackProvider(session), (_, s) {
        phases.add(s.phase);
        if (s.step != null) steps.add(s.step!);
      });
      expect(await n.start(), isTrue);
      final s = stateOf(session);
      expect(s.phase, LocalPackPhase.done, reason: s.failure?.message);
      expect(phases, containsAll([LocalPackPhase.preparingKey, LocalPackPhase.packing, LocalPackPhase.done]));
      expect(steps, containsAll([ApkPackStep.check, ApkPackStep.collect, ApkPackStep.manifest, ApkPackStep.zip, ApkPackStep.sign, ApkPackStep.write]));

      final r = s.result!;
      expect(p.basename(r.path), '我的小站-1.0.0-1.apk');
      expect(p.dirname(r.path), p.join(session.project.dir, 'build'));
      expect(File(r.path).lengthSync(), r.sizeBytes);
      expect((r.appName, r.versionName, r.versionCode), ('我的小站', '1.0.0', 1));
      expect(File(s.publicPath!).readAsBytesSync(), File(r.path).readAsBytesSync(), reason: '抄到外部目录的那份一模一样');
      expect(s.form.versionCode, '2', reason: '成功后下次的版本号默认加 1');

      // 钥匙：这次生成的那把已经存进安全存储，指纹和产物上的一致
      final saved = await env.services.secrets.read(SecretKeys.apkSigningKey);
      expect(real.parseKey(saved!).certSha256Hex, r.certSha256Hex);
      expect(env.services.container.read(signingKeyProvider).fingerprint, r.certSha256Hex);
      checkOfficial(r, permissions: {_internet}, cert: r.certSha256Hex);
    }, timeout: const Timeout(Duration(minutes: 15)));

    test('样例二 低代码导出（“低代码页面”模板）：很长的包名、一个权限都不要；页面源文件不进包', () async {
      final (session, n) = await open('落地页', ProjectTemplate.lowcode);
      expect(stateOf(session).project!.kind, 'lowcode', reason: stateOf(session).project!.reason);
      final longPkg = 'com.${List.filled(13, 'verylongsegment').join('.')}.app';
      n.edit(packageName: longPkg, appName: 'LC 页面', versionName: '0.9-beta', versionCode: '2100000000');
      n.setPermission(_internet, false);
      expect(await n.start(), isTrue);
      final s = stateOf(session);
      expect(s.phase, LocalPackPhase.done, reason: s.failure?.message);
      final r = s.result!;
      expect(r.packageName, longPkg);
      final files = webFilesIn(r.path);
      expect(files, containsAll(['index.html', 'style.css']));
      expect(files, isNot(contains(kLowcodePageFile)));
      checkOfficial(r, permissions: {}, cert: real.parseKey(await keyText()).certSha256Hex);
    }, timeout: const Timeout(Duration(minutes: 15)));

    test('样例三 带子目录和大图：换图标、加摄像头和定位 → 再去掉打升级包（同一把钥匙、版本号加 1）', () async {
      final (session, n) = await open('相册', ProjectTemplate.web);
      sampleWithAssets(session.project.dir);
      session.filesChanged();
      await n.detect();
      await n.setIcon(solidPng(512, r: 30, g: 120, b: 220));
      final icons = stateOf(session).icons;
      expect(icons.keys.toSet(), {48, 72, 96, 144, 192});
      n.edit(appName: '霜霜的相册 😀', packageName: 'com.shuang.album');
      n.setPermission(_camera, true);
      n.setPermission(_fine, true);
      expect(await n.start(), isTrue);
      var s = stateOf(session);
      expect(s.phase, LocalPackPhase.done, reason: s.failure?.message);
      final first = s.result!;
      final cert = real.parseKey(await keyText()).certSha256Hex;
      expect(first.certSha256Hex, cert);
      final files = webFilesIn(first.path);
      expect(files, containsAll(['index.html', 'img/big.png', 'js/app/main.js', 'css/a/b/c/deep.css', 'fonts/x.woff2']));
      expect(files.where((f) => f.startsWith('node_modules') || f.startsWith('.') || f.startsWith('build/')), isEmpty);
      checkOfficial(first, permissions: {_internet, _camera, _fine, _coarse}, cert: cert, icons: icons);

      // 升级包：去掉两个权限、恢复默认图标，版本号是自动加好的 2，钥匙还是那一把
      n.setPermission(_camera, false);
      n.setPermission(_fine, false);
      await n.clearIcon();
      expect(await n.start(), isTrue);
      s = stateOf(session);
      expect(s.phase, LocalPackPhase.done, reason: s.failure?.message);
      final second = s.result!;
      expect((second.versionCode, second.packageName, second.certSha256Hex), (2, first.packageName, cert));
      expect(p.basename(second.path), isNot(p.basename(first.path)));
      expect(webFilesIn(second.path), files, reason: '上一次打出来的安装包不会被装进这一次的包里');
      checkOfficial(second, permissions: {_internet}, cert: cert);
    }, timeout: const Timeout(Duration(minutes: 15)));

    test('网页目录就是 build/ 的项目：钥匙备份和以前的安装包都不进包', () async {
      final (session, n) = await open('构建过的', ProjectTemplate.empty);
      writeFiles(session.project.dir, {
        'package.json': '{"scripts":{"build":"vite build"}}',
        'build/index.html': '<!doctype html><p>built</p>',
        'build/app.js': 'x()',
        'build/${kKeyBackupPrefix}20261126-0230.txt': 'LOPIKEY…',
        'build/旧的-1.0.0-1.apk': 'old',
      });
      session.filesChanged();
      await n.detect();
      expect(stateOf(session).project!.webRoot, p.join(session.project.dir, 'build'), reason: stateOf(session).project!.reason);
      expect(await n.start(), isTrue);
      final s = stateOf(session);
      expect(s.phase, LocalPackPhase.done, reason: s.failure?.message);
      expect(webFilesIn(s.result!.path), ['app.js', 'index.html']);
    }, timeout: const Timeout(Duration(minutes: 15)));

    test('坏输入：非法包名不受理并标在包名上；超限的项目打包失败、原因说清、不留半截文件', () async {
      final (session, n) = await open('坏输入', ProjectTemplate.web);
      n.edit(packageName: 'com.new.1app');
      expect(await n.start(), isFalse);
      expect(stateOf(session).fieldErrors.keys, ['packageName']);
      expect(stateOf(session).phase, LocalPackPhase.idle);
      n.edit(packageName: 'com.shuang.bad', versionCode: '0');
      expect(await n.start(), isFalse);
      expect(stateOf(session).fieldErrors.keys, ['versionCode']);
      n.edit(versionCode: '1');

      // 单个文件 51MB（稀疏文件，不真占盘）
      final big = File(p.join(session.project.dir, 'video.mp4')).openSync(mode: FileMode.write);
      big.truncateSync(51 * 1024 * 1024);
      big.closeSync();
      expect(await n.start(), isTrue);
      final s = stateOf(session);
      expect(s.phase, LocalPackPhase.failed);
      expect(s.failure!.field, 'project');
      expect(s.failure!.message, allOf(contains('video.mp4'), contains('太大了')));
      expect(s.failure!.step, ApkPackStep.collect);
      final build = Directory(p.join(session.project.dir, 'build'));
      expect(build.existsSync() ? build.listSync() : const [], isEmpty);
    }, timeout: const Timeout(Duration(minutes: 15)));

    test('不适用的项目：说明原因并指向远程打包，开始打包不受理', () async {
      final (session, n) = await open('空的', ProjectTemplate.empty);
      var info = stateOf(session).project!;
      expect(info.applicable, isFalse);
      expect(info.reason, allOf(contains('index.html'), contains('远程打包')));
      expect(await n.start(), isFalse);

      writeFiles(session.project.dir, {'pubspec.yaml': 'name: x', 'index.html': 'x'});
      session.filesChanged();
      await n.detect();
      info = stateOf(session).project!;
      expect(info.applicable, isFalse);
      expect(info.reason, allOf(contains('Flutter'), contains('远程打包')));
      expect(await n.start(), isFalse);
    });
  });
}
