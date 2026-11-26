// 本地打包的状态层：表单默认值和文件名规则、钥匙（SigningKeyNotifier）、一次打包（LocalPackNotifier）。
// 用的是假的打包后端（test/support/fake_local_pack.dart）；生产实现走真打包器的测试在 test/local_pack_real_backend_test.dart 和 test/local_pack_real_screen_test.dart。
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/apkpack/apk_pack_contract.dart';
import 'package:lopicode/build/apk_output.dart';
import 'package:lopicode/build/build_controller.dart';
import 'package:lopicode/build/build_widgets.dart';
import 'package:lopicode/build/local_pack_backend.dart';
import 'package:lopicode/build/local_pack_backend_real.dart';
import 'package:lopicode/build/local_pack_form.dart';
import 'package:lopicode/core/path_guard.dart';
import 'package:lopicode/core/project_store.dart';
import 'package:lopicode/core/safe_file.dart';
import 'package:lopicode/core/stores.dart';
import 'package:lopicode/core/templates.dart';
import 'package:lopicode/project_session.dart';
import 'package:lopicode/state/app_providers.dart';
import 'package:lopicode/state/local_pack.dart';
import 'package:lopicode/state/signing_key.dart';
import 'package:path/path.dart' as p;
import 'package:riverpod/riverpod.dart';

import 'support/fake_local_pack.dart';
import 'support/harness.dart';

void main() {
  late TestEnv env;
  late ProviderContainer box;
  late FakeLocalPackBackend fake;
  late Project project;
  late ProjectSession session;

  setUp(() async {
    env = await TestEnv.create();
    box = env.services.container;
    fake = FakeLocalPackBackend();
    localPackBackendOverride = fake;
    externalFilesDirOverride = () async => p.join(env.tmp.path, 'external');
    project = await env.services.projects.create('我的小站', ProjectTemplate.web);
    session = ProjectSession(env.services, project, headless: true);
  });
  tearDown(() async {
    session.dispose();
    await pendingWrites();
    await env.dispose();
    localPackBackendOverride = null;
    externalFilesDirOverride = null;
  });

  /// 等到条件成立（最多 5 秒）。不用固定的“等 30 毫秒”：机器忙的时候 30 毫秒不够，测试会时灵时不灵。
  Future<void> until(bool Function() ok) async {
    for (var i = 0; i < 500 && !ok(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  LocalPackNotifier pack() => box.read(localPackProvider(session).notifier);
  LocalPackState state() => box.read(localPackProvider(session));
  SigningKeyNotifier keys() => box.read(signingKeyProvider.notifier);

  group('默认值和文件名规则', () {
    test('默认包名：com.lopicode.app. + 目录名变来的一段', () {
      expect(defaultPackageName('my-site'), 'com.lopicode.app.mysite');
      expect(defaultPackageName('Shop_2'), 'com.lopicode.app.shop_2');
      expect(defaultPackageName('2048'), 'com.lopicode.app.p2048', reason: '数字开头的前面补 p');
      expect(defaultPackageName('_x'), 'com.lopicode.app.p_x');
      final zh = defaultPackageName('我的小站');
      expect(zh, matches(RegExp(r'^com\.lopicode\.app\.p[0-9a-f]{6}$')), reason: '全中文：用校验码');
      expect(defaultPackageName('我的小站'), zh, reason: '同一个目录名每次一样');
      expect(defaultPackageName('另一个'), isNot(zh));
      expect(defaultPackageName('a' * 80).length, kPackagePrefix.length + kPackageTailMax);
      // 默认包名要过得了校验
      for (final id in ['my-site', '2048', '我的小站', 'a' * 80]) {
        expect(fake.validatePackageName(defaultPackageName(id)), isNull, reason: id);
      }
    });

    test('默认应用名：工作区名字，空的有兜底，太长截断', () {
      expect(defaultAppName('  我的小站 '), '我的小站');
      expect(defaultAppName(''), '我的应用');
      expect(defaultAppName('字' * 40).runes.length, kAppNameDefaultMax);
    });

    test('产物文件名：应用名-版本名-版本号.apk；不能当文件名的字符换掉', () {
      expect(apkFileName(appName: '我的小站', versionName: '1.0.0', versionCode: 3), '我的小站-1.0.0-3.apk');
      expect(apkFileName(appName: 'a/b:c d', versionName: '1.0 beta', versionCode: 1), 'a_b_c_d-1.0_beta-1.apk');
      expect(apkFileName(appName: '  ', versionName: '', versionCode: 2), 'app-0-2.apk');
    });

    test('远程打包推送文件时跳过本地打包留在 build/ 下的安装包和钥匙备份', () async {
      expect(isLocalPackOutput('build/我的小站-1.0.0-1.apk'), isTrue);
      expect(isLocalPackOutput('build/${kKeyBackupPrefix}20261126-0230.txt'), isTrue);
      expect(isLocalPackOutput('build/app.js'), isFalse);
      expect(isLocalPackOutput('build/app/outputs/x.apk'), isFalse, reason: '只管 build/ 这一层');
      expect(isLocalPackOutput('assets/x.apk'), isFalse);
      Directory(p.join(project.dir, 'build')).createSync();
      File(p.join(project.dir, 'build', 'x-1.0.0-1.apk')).writeAsStringSync('apk');
      File(p.join(project.dir, 'build', '${kKeyBackupPrefix}1.txt')).writeAsStringSync('key');
      File(p.join(project.dir, 'build', 'keep.js')).writeAsStringSync('js');
      final files = await ApkBuildController.collectFiles(PathGuard(project.dir));
      expect(files.keys.where((k) => k.startsWith('build/')), ['build/keep.js']);
    });

    test('打包方式：没存过＝本地；原来存了 github / ssh 的照旧；认不出来的当本地', () {
      expect(BuildMode.fromSetting(''), BuildMode.local);
      expect(BuildMode.fromSetting('github'), BuildMode.github);
      expect(BuildMode.fromSetting('ssh'), BuildMode.ssh);
      expect(BuildMode.fromSetting('local'), BuildMode.local);
      expect(BuildMode.fromSetting('???'), BuildMode.local);
    });

    test('生产实现已接好：权限表是打包器那七项，校验走打包器的规则', () {
      const real = RealLocalPackBackend();
      expect(real.permissionOptions.length, 7);
      expect(real.permissionOptions.where((o) => o.defaultOn).map((o) => o.id), ['android.permission.INTERNET']);
      expect(real.validatePackageName('com.shuang.demo'), isNull);
      expect(real.validatePackageName('com.new.app'), isNotNull);
      expect(real.validateVersionCode(' 12 '), isNull);
      expect(real.validateVersionCode('1.5'), isNotNull);
      expect(real.validateVersionCode('0'), isNotNull);
    });
  });

  group('签名钥匙', () {
    test('一开始没有；ensure 生成一把并存进安全存储；再 ensure 还是同一把', () async {
      await keys().load();
      expect(box.read(signingKeyProvider).loaded, isTrue);
      expect(box.read(signingKeyProvider).hasKey, isFalse);
      final a = await keys().ensure();
      expect(box.read(signingKeyProvider).fingerprint, a.certSha256Hex);
      expect(box.read(signingKeyProvider).shortFingerprint, '3556a3b1');
      expect(await env.services.secrets.read(SecretKeys.apkSigningKey), a.serialize());
      final b = await keys().ensure();
      expect(identical(a, b), isTrue);
      expect(fake.generated, 1);
      expect(env.services.settings.file.existsSync() ? env.services.settings.file.readAsStringSync() : '', isNot(contains('3556a3b1')), reason: '钥匙不进普通设置文件');
    });

    test('同时要两次：只生成一把；生成中状态是“正在生成”', () async {
      fake.keyGate = Completer<void>();
      final f1 = keys().ensure();
      final f2 = keys().ensure();
      await until(() => box.read(signingKeyProvider).busy == SigningKeyBusy.generating);
      expect(box.read(signingKeyProvider).busy, SigningKeyBusy.generating);
      fake.keyGate!.complete();
      expect(identical(await f1, await f2), isTrue);
      expect(fake.generated, 1);
      expect(box.read(signingKeyProvider).busy, SigningKeyBusy.none);
    });

    test('应用重开（新容器）：从安全存储读回同一把', () async {
      final a = await keys().ensure();
      final again = ProviderContainer(overrides: [appServicesProvider.overrideWithValue(env.services)]);
      addTearDown(again.dispose);
      await again.read(signingKeyProvider.notifier).load();
      expect(again.read(signingKeyProvider).fingerprint, a.certSha256Hex);
    });

    test('存着的内容读不出来：不崩、不删，说明原因；ensure 不会悄悄换一把', () async {
      await env.services.secrets.write(SecretKeys.apkSigningKey, '不是钥匙');
      await keys().load();
      final s = box.read(signingKeyProvider);
      expect(s.hasKey, isFalse);
      expect(s.error, contains('读不出来'));
      expect(s.error, isNot(contains('不是钥匙')), reason: '报错里不带存着的内容');
      await expectLater(keys().ensure(), throwsA(isA<SigningKeyException>()));
      expect(fake.generated, 0);
      expect(await env.services.secrets.read(SecretKeys.apkSigningKey), '不是钥匙');
    });

    test('导出 → 重新生成 → 导入：拿回原来那把；口令不对 / 内容不对有原因，钥匙不动', () async {
      final a = await keys().ensure();
      await expectLater(keys().exportBackup('short'), throwsA(isA<SigningKeyException>()), reason: '口令太短');
      final text = await keys().exportBackup('correct horse');
      await keys().regenerate();
      final b = box.read(signingKeyProvider).fingerprint;
      expect(b, isNot(a.certSha256Hex));
      await expectLater(keys().importBackup(text, 'wrong pass'), throwsA(isA<SigningKeyException>().having((e) => e.message, 'message', '口令不对。')));
      expect(box.read(signingKeyProvider).fingerprint, b, reason: '没导入成，现在的钥匙不动');
      await expectLater(keys().importBackup('随便一段字', 'correct horse'), throwsA(isA<SigningKeyException>().having((e) => e.message, 'message', contains('不是 LopiCode 导出的钥匙备份'))));
      await keys().importBackup('  $text\n', 'correct horse');
      expect(box.read(signingKeyProvider).fingerprint, a.certSha256Hex);
      expect(await env.services.secrets.read(SecretKeys.apkSigningKey), a.serialize());
    });

    test('没有钥匙时导出：说没东西可备份', () async {
      await expectLater(keys().exportBackup('correct horse'), throwsA(isA<SigningKeyException>()));
    });

    test('容器销毁后生成才回来：不写状态、不抛到没人接的地方', () async {
      final other = ProviderContainer(overrides: [appServicesProvider.overrideWithValue(env.services)]);
      fake.keyGate = Completer<void>();
      final f = other.read(signingKeyProvider.notifier).ensure();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      other.dispose();
      fake.keyGate!.complete();
      await f; // 钥匙本身还是生成并存好了的
      expect(await env.services.secrets.read(SecretKeys.apkSigningKey), isNotNull);
    });
  });

  group('一次打包', () {
    test('读好以后：表单是默认值，项目适用', () async {
      await pack().load();
      final s = state();
      expect(s.loaded, isTrue);
      expect(s.project!.applicable, isTrue);
      expect(s.form.appName, '我的小站');
      expect(s.form.packageName, defaultPackageName(project.id));
      expect(s.form.versionName, '1.0.0');
      expect(s.form.versionCode, '1');
      expect(s.form.permissions, {'android.permission.INTERNET'});
      expect(s.phase, LocalPackPhase.idle);
    });

    test('完整流程：第一次自动生成钥匙 → 七步 → 产物在 build/ 下并抄一份到外部目录 → 版本号加 1', () async {
      await pack().load();
      final phases = <String>[];
      box.listen(localPackProvider(session), (_, s) {
        final tag = '${s.phase.name}${s.phase == LocalPackPhase.packing ? ':${s.step?.name}' : ''}';
        if (phases.isEmpty || phases.last != tag) phases.add(tag);
      });
      expect(await pack().start(), isTrue);
      expect(phases, ['preparingKey', 'packing:check', 'packing:collect', 'packing:manifest', 'packing:icon', 'packing:zip', 'packing:sign', 'packing:write', 'done']);
      final s = state();
      final r = s.result!;
      expect(r.path, p.join(project.dir, 'build', '我的小站-1.0.0-1.apk'));
      expect(File(r.path).existsSync(), isTrue);
      expect(s.publicPath, p.join(env.tmp.path, 'external', 'apk', project.id, '我的小站-1.0.0-1.apk'));
      expect(File(s.publicPath!).readAsStringSync(), File(r.path).readAsStringSync());
      expect(fake.lastRequest!.permissions, {'android.permission.INTERNET'});
      expect(fake.lastRequest!.iconPngs, isEmpty, reason: '没选图标＝用模板自带的');
      expect(fake.lastRequest!.webRoot, project.dir);
      expect(fake.lastRequest!.entry, 'index.html');
      expect(r.certSha256Hex, box.read(signingKeyProvider).fingerprint);
      expect(s.form.versionCode, '2', reason: '成功一次，下次默认加 1');
      // 存盘了：换一个容器（相当于重开）读回来还是 2
      await pendingWrites();
      final again = ProviderContainer(overrides: [appServicesProvider.overrideWithValue(env.services)]);
      addTearDown(again.dispose);
      await again.read(localPackProvider(session).notifier).load();
      expect(again.read(localPackProvider(session)).form.versionCode, '2');
      // 第二次：钥匙已经有了，不再有“生成钥匙”这一步；同一把
      phases.clear();
      expect(await pack().start(), isTrue);
      expect(phases.first, 'packing:check');
      expect(fake.generated, 1);
      expect(state().result!.versionCode, 2);
      expect(File(p.join(project.dir, 'build', '我的小站-1.0.0-2.apk')).existsSync(), isTrue);
    });

    test('输入没过校验：不受理，错写在对应的项下面；改了那一项错就收起来', () async {
      await pack().load();
      pack().edit(packageName: 'Bad Name', versionCode: '0', appName: ' ');
      expect(await pack().start(), isFalse);
      expect(state().fieldErrors.keys, containsAll(['appName', 'packageName', 'versionCode']));
      expect(state().fieldErrors.containsKey('versionName'), isFalse);
      expect(state().phase, LocalPackPhase.idle);
      expect(fake.packs, 0);
      pack().edit(packageName: 'com.example.shop');
      expect(state().fieldErrors.containsKey('packageName'), isFalse);
      expect(state().fieldErrors.containsKey('versionCode'), isTrue);
    });

    test('打包器报错（带 field）：失败状态里有哪一步、原因、哪个输入；版本号不加', () async {
      await pack().load();
      fake.packError = const ApkPackException('包名 com.lopicode.app.x 里的 x 段太短。', field: 'packageName');
      fake.packErrorAt = ApkPackStep.manifest;
      expect(await pack().start(), isTrue);
      final s = state();
      expect(s.phase, LocalPackPhase.failed);
      expect(s.failure!.step, ApkPackStep.manifest);
      expect(s.failure!.field, 'packageName');
      expect(s.failure!.message, contains('太短'));
      expect(s.fieldErrors['packageName'], contains('太短'));
      expect(s.form.versionCode, '1');
      // 改好再打：成功，失败信息清掉
      fake.packError = null;
      expect(await pack().start(), isTrue);
      expect(state().phase, LocalPackPhase.done);
      expect(state().failure, isNull);
      expect(state().fieldErrors, isEmpty);
    });

    test('打包器报错指向权限（field 是 permissions）：错记在权限那一项上；改了权限就收起来', () async {
      await pack().load();
      fake.packError = const ApkPackException('权限表里没有 android.permission.FOO。', field: 'permissions');
      fake.packErrorAt = ApkPackStep.check;
      expect(await pack().start(), isTrue);
      expect(state().phase, LocalPackPhase.failed);
      expect(state().failure!.field, 'permissions');
      expect(state().fieldErrors['permissions'], contains('权限表里没有'));
      pack().setPermission('android.permission.CAMERA', true);
      expect(state().fieldErrors.containsKey('permissions'), isFalse);
    });

    test('钥匙读不出来：打包失败，原因指向钥匙，不会悄悄换一把', () async {
      await env.services.secrets.write(SecretKeys.apkSigningKey, '坏的');
      await pack().load();
      expect(await pack().start(), isTrue);
      expect(state().phase, LocalPackPhase.failed);
      expect(state().failure!.field, 'key');
      expect(fake.packs, 0);
      expect(fake.generated, 0);
    });

    test('同一时间只受理一次；打包中表单改不动', () async {
      await pack().load();
      fake
        ..holdAt = ApkPackStep.zip
        ..packGate = Completer<void>();
      final first = pack().start();
      await until(() => state().step == ApkPackStep.zip);
      expect(state().busy, isTrue);
      expect(state().step, ApkPackStep.zip);
      expect(state().detail, '23 / 23');
      expect(await pack().start(), isFalse, reason: '进行中再点不受理');
      pack().edit(appName: '改了');
      pack().setPermission('android.permission.CAMERA', true);
      expect(state().form.appName, '我的小站');
      expect(state().form.permissions, {'android.permission.INTERNET'});
      fake.packGate!.complete();
      await first;
      expect(fake.packs, 1);
      expect(state().phase, LocalPackPhase.done);
    });

    test('打包中工作区关掉：回来的结果丢掉，不写状态、不报错', () async {
      await pack().load();
      fake
        ..holdAt = ApkPackStep.collect
        ..packGate = Completer<void>();
      final notifier = pack();
      final running = notifier.start();
      await until(() => notifier.current.step == ApkPackStep.collect);
      session.dispose();
      fake.packGate!.complete();
      await running;
      expect(notifier.current.phase, LocalPackPhase.packing, reason: '最后一份快照停在关掉那一刻，没被后来的结果改写');
    });

    test('项目不适用：不受理', () async {
      fake.project = const WebProjectInfo(applicable: false, reason: '这是 Flutter 项目。');
      await pack().load();
      expect(state().project!.applicable, isFalse);
      expect(await pack().start(), isFalse);
      expect(fake.packs, 0);
    });

    test('项目文件变了：适不适用重新看一遍', () async {
      File(p.join(project.dir, 'index.html')).deleteSync();
      await pack().load();
      expect(state().project!.applicable, isFalse);
      expect(state().project!.reason, contains('没找到网页入口'));
      File(p.join(project.dir, 'index.html')).writeAsStringSync('<h1>hi</h1>');
      session.filesChanged();
      await until(() => state().project!.applicable);
      expect(state().project!.applicable, isTrue);
    });

    test('权限勾选会存下来；表里没有的权限读回来时丢掉', () async {
      await pack().load();
      pack().setPermission('android.permission.CAMERA', true);
      pack().setPermission('android.permission.INTERNET', false);
      await pendingWrites();
      final store = LocalPackFormStore(session.guard);
      final back = await store.read(fallback: state().form, options: kFakePermissions);
      expect(back.permissions, {'android.permission.CAMERA'});
      await writeJsonAtomic(store.file, {
        'permissions': ['android.permission.CAMERA', 'android.permission.SEND_SMS', 7],
      });
      final odd = await store.read(fallback: state().form, options: kFakePermissions);
      expect(odd.permissions, {'android.permission.CAMERA'});
    });

    test('抄到外部目录没成：打包照样算成功，如实说明', () async {
      // 外部目录指到一个“文件”上，建不出目录
      final blocker = File(p.join(env.tmp.path, 'blocker'))..writeAsStringSync('x');
      externalFilesDirOverride = () async => blocker.path;
      await pack().load();
      expect(await pack().start(), isTrue);
      expect(state().phase, LocalPackPhase.done);
      expect(state().publicPath, isNull);
      expect(state().publicNote, contains('没能抄一份到手机存储'));
    });
  });
}
