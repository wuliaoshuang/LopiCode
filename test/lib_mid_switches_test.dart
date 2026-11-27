// 2026-11-27 中途包：两条路默认关着，这里把“默认关”和关着时各处的样子钉住。
// - 带手写代码的库的启用（rules.dart 的 kLibNativeCodeEnabled / libNativeCodeEntry）；
// - 自己的库（含前端库）直接用宿主接口（kUserLibHostEnabled / userLibHostEntry）。
// 这个文件**不**打开开关；开着时的样子由 lib_side_native_test、lib_more_ui_test、lib_fork_native_run_test 等先打开再测。
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/backend/backend_lib_pack.dart';
import 'package:lopicode/backend/backend_lib_store.dart';
import 'package:lopicode/backend/lib_native_trust.dart';
import 'package:lopicode/backend/lib_service.dart';
import 'package:lopicode/backend/lib_service_fork.dart';
import 'package:lopicode/core/path_guard.dart';
import 'package:lopicode/lang/lib_model.dart';
import 'package:lopicode/lang/rules.dart';
import 'package:lopicode/lowcode/lib_page.dart';
import 'package:lopicode/ui/settings_screen.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;

import 'support/backend_core_samples.dart';
import 'support/backend_lang_blocks.dart';
import 'support/harness.dart' hide say;
import 'support/lib_ui.dart';
import 'support/native_lib.dart';
import 'support/page_front_samples2.dart';
import 'support/user_libs.dart';

/// 给后端用的库，清单里老老实实写明了它直接用宿主接口 time.now（开着时这样写就能用）。
const Map<String, String> _backHostFiles = {
  'lib.json': '''
{"kind": "lopicode-lib", "format": 1, "id": "test/back-host", "name": "看钟", "version": "1.0.0", "summary": "测试用", "rules": 2,
 "for": "backend", "hosts": ["time.now"], "modules": [{"file": "modules/kit.lc", "name": "看钟"}], "blocks": ["blocks.json"]}''',
  'modules/kit.lc': '''
(模块 看钟
  (宿主 time.now () -> 整数)
  (公开 (函数 现在 () -> 整数 (返回 (宿 time.now)))))
''',
  'blocks.json': '''
{"blocks": [
  {"id": "now", "how": "call", "of": "现在", "args": [], "look": {"name": "现在几点", "shape": "value", "template": "现在几点"}}
]}''',
};

J _emptyStrict() => {
  ...flowUserDoc(),
  'uses': <J>[],
  'hats': <J>[],
  'start': <J>[
    say([tx('你好')]),
  ],
};

Future<void> _openLibs(WidgetTester tester) async {
  await libTap(tester, 'be-more');
  await libTap(tester, 'be-menu-libs');
}

Future<void> _closeSheet(WidgetTester tester) async {
  await tester.tap(lk('be-sheet-done').last);
  await libSettle(tester, rounds: 3);
}

/// 关着时不许再出现的说法：指向一个不存在的入口。
void _noDeadEntry(Iterable<String> texts) {
  for (final t in texts) {
    expect(t, isNot(contains('设置 › 能力')), reason: t);
    expect(t, isNot(contains('允许库里的手写代码')), reason: t);
  }
}

void main() {
  setUp(() => LibNativeTrust.instance = LibNativeTrust());
  tearDown(() => LibNativeTrust.instance = LibNativeTrust());

  test('两个开关默认都是关', () {
    expect(kLibNativeCodeEnabled, isFalse);
    expect(kUserLibHostEnabled, isFalse);
    expect(libNativeCodeEntry, isFalse, reason: '别的测试改过要改回来');
    expect(userLibHostEntry, isFalse, reason: '别的测试改过要改回来');
  });

  group('带手写代码的库（关着）', () {
    test('私有目录里存过“开着”和确认记录也不算数：没开、不许用、确认记不上、打不开', () async {
      final dir = await Directory.systemTemp.createTemp('lopi_mid_trust');
      addTearDown(() => dir.delete(recursive: true));
      final file = File(p.join(dir.path, 'lib_native_trust.json'));
      final sum = libNativeSum(handLibFiles());
      await file.writeAsString(
        jsonEncode({
          'enabled': true,
          'confirmed': {'/proj\u0000$kLibHand': sum},
        }),
      );
      final trust = LibNativeTrust();
      await trust.attach(file);
      expect(trust.enabled, isFalse);
      expect(trust.allows('/proj', kLibHand, sum), isFalse);
      expect(await trust.confirm('/proj', kLibHand, sum), isFalse);
      await trust.setEnabled(true);
      expect(trust.enabled, isFalse, reason: '总开关关着时打不开');
      // 同一份记录，总开关开着时是算数的——证明上面几条是总开关拦下的，不是记录没读进来。
      libNativeCodeEntry = true;
      addTearDown(() => libNativeCodeEntry = kLibNativeCodeEnabled);
      expect(trust.enabled, isTrue);
      expect(trust.allows('/proj', kLibHand, sum), isTrue);
    });

    test('读出来有问题、预览如实列出文件但不能导入、硬放也放不进项目；说法不指向不存在的入口', () async {
      final files = handLibFiles();
      final lib = libRead(files, builtin: false);
      expect(lib.ok, isFalse);
      expect(lib.problems.join(), contains(kLibNativeOffNote));
      _noDeadEntry(lib.problems);

      final preview = beLibPreview(files);
      expect(preview.hasNative, isTrue);
      expect(preview.nativeFiles, isNotEmpty, reason: '文件照样列出来给看');
      expect(preview.nativeBlocked, isTrue);
      expect(preview.canImport, isFalse);
      expect(preview.problems.join(), contains(kLibNativeOffNote));
      _noDeadEntry(preview.problems);

      final dir = await Directory.systemTemp.createTemp('lopi_mid_install');
      addTearDown(() => dir.delete(recursive: true));
      final saved = await beLibInstall(PathGuard(dir.path), preview, nativeConfirmed: true);
      expect(saved.written, isFalse);
      _noDeadEntry(saved.problems);
      expect(Directory(p.join(dir.path, 'blocks')).existsSync(), isFalse, reason: '什么都没放进项目');
    });
  });

  group('自己的库直接用宿主接口（关着）', () {
    test('给后端的一份、只给前端的一份：清单里写明了也一样——读出来有问题、点名是哪些接口、不能导入', () {
      for (final (files, host) in [(_backHostFiles, 'time.now'), (kFrontKitFiles, 'page.alert')]) {
        final lib = libRead(files, builtin: false);
        expect(lib.ok, isFalse, reason: host);
        final said = lib.problems.join('\n');
        expect(said, contains('这一版自己的库还不能直接碰宿主接口，只有应用自带的库可以'), reason: host);
        expect(said, contains(host));
        final preview = beLibPreview(files);
        expect(preview.canImport, isFalse, reason: host);
        expect(preview.problems.join('\n'), contains(host));
      }
    });

    test('同样两份，开着时没有问题（证明是这个开关拦下的）', () {
      userLibHostEntry = true;
      addTearDown(() => userLibHostEntry = kUserLibHostEnabled);
      expect(libRead(_backHostFiles, builtin: false).problems, isEmpty);
      expect(libRead(kFrontKitFiles, builtin: false).problems, isEmpty);
    });

    test('应用自带的“接口服务”“页面”库照常：0 问题，宿主接口都在', () {
      final service = libRead(kBeServiceLibFiles, builtin: true);
      expect(service.problems, isEmpty);
      expect(service.hosts, isNotEmpty);
      expect(beServiceLibrary().ok, isTrue);
      final page = libRead(kLcPageLibFiles, builtin: true);
      expect(page.problems, isEmpty);
      expect(page.hosts, isNotEmpty);
      expect(lcPageLibrary().ok, isTrue);
    });

    test('不碰宿主接口的自己的库照常读得进来', () {
      final plain = Map.of(_backHostFiles)
        ..['lib.json'] = _backHostFiles['lib.json']!.replaceFirst('"hosts": ["time.now"], ', '')
        ..['modules/kit.lc'] = '(模块 看钟\n  (公开 (函数 现在 () -> 整数 (返回 7))))\n';
      expect(libRead(plain, builtin: false).problems, isEmpty);
    });

    test('“接口服务”复制不出来，说的是这一版还不能', () {
      final made = beServiceForkFiles(id: 'shuang/svc', name: '我的接口服务');
      expect(made.files, isNull);
      expect(made.problem, kServiceForkOffNote);
    });
  });

  group('界面（关着）', () {
    testWidgets('设置 › 能力：没有“积木库的手写代码”那一行（前后两行都在）', (tester) async {
      usePhoneViewport(tester);
      late TestEnv env;
      await tester.runAsync(() async => env = await TestEnv.create());
      addTearDown(() => tester.runAsync(env.dispose));
      await tester.pumpWidget(appFor(env, const SettingsScreen()));
      await settle(tester);
      await tester.scrollUntilVisible(find.byKey(const Key('settings-automations')), 200, scrollable: find.byType(Scrollable).first);
      await settle(tester);
      expect(find.byKey(const Key('settings-memory')), findsOneWidget, reason: '上一行在');
      expect(find.byKey(const Key('settings-automations')), findsOneWidget, reason: '下一行在');
      expect(find.byKey(const Key('settings-lib-native')), findsNothing);
      expect(find.text('积木库的手写代码'), findsNothing);
    });

    testWidgets('从文件导入带手写代码的库：看得到文件、点得开全文、不能导入；已在项目里的“有问题”，面板里只给“看手写代码”', (tester) async {
      final ui = await openLibUi(tester, _emptyStrict(), files: {'手写示例.lopilib': beLibPack(handLibFiles())});
      final libDir = p.join(ui.project.dir, 'blocks', kLibHand);
      await _openLibs(tester);
      await libTap(tester, 'be-lib-import');
      await libUntil(tester, () => lk('be-lib-import-sheet').evaluate().isNotEmpty, what: '预览');
      expect(tester.widget<FilledButton>(lk('be-lib-import-go')).onPressed, isNull, reason: '不能导入');
      await libSee(tester, 'be-lib-native-off');
      expect(find.descendant(of: lk('be-lib-native-off'), matching: find.textContaining(kLibNativeOffNote)), findsOneWidget);
      expect(find.textContaining('设置 › 能力'), findsNothing);
      expect(find.textContaining('允许库里的手写代码'), findsNothing);
      expect(lk('be-lib-native-seen'), findsNothing, reason: '没有可勾的确认');
      await libSee(tester, 'be-lib-native-native/join.go');
      await libTap(tester, 'be-lib-native-native/join.go');
      expect(find.textContaining('strings.Join'), findsOneWidget, reason: '代码给看全文');
      await _closeSheet(tester);
      await _closeSheet(tester);
      expect(Directory(libDir).existsSync(), isFalse);
      await _closeSheet(tester);

      // 项目里已经有一个带手写代码的库（比如旧版本放进来的）：照旧“有问题、用不了”。
      await tester.runAsync(() async {
        for (final e in handLibFiles().entries) {
          final f = File(p.join(libDir, e.key));
          await f.parent.create(recursive: true);
          await f.writeAsString(e.value);
        }
      });
      await _openLibs(tester);
      await libUntil(tester, () => lk('be-lib-$kLibHand').evaluate().isNotEmpty, what: '库的清单');
      expect(find.descendant(of: lk('be-lib-$kLibHand'), matching: find.text('有问题')), findsOneWidget);
      await libTap(tester, 'be-lib-$kLibHand');
      expect(lk('be-lib-use'), findsNothing, reason: '用不了');
      expect(find.textContaining('设置 › 能力'), findsNothing);
      expect(find.textContaining('允许库里的手写代码'), findsNothing);
      await libSee(tester, 'be-lib-native-confirm');
      expect(find.descendant(of: lk('be-lib-native-confirm'), matching: find.text('看手写代码')), findsOneWidget);
      await libTap(tester, 'be-lib-native-confirm');
      await libUntil(tester, () => lk('be-lib-import-sheet').evaluate().isNotEmpty, what: '看代码那一页');
      expect(find.text('看手写代码'), findsWidgets);
      expect(find.text('确认手写代码'), findsNothing);
      expect(tester.widget<FilledButton>(lk('be-lib-import-go')).onPressed, isNull, reason: '只能看，确认不了');
      expect(lk('be-lib-native-seen'), findsNothing);
    });

    testWidgets('自带“接口服务”面板：没有可点的“复制一份来改”，换成一行灰字说明', (tester) async {
      await openLibUi(tester, _emptyStrict());
      await _openLibs(tester);
      await libTap(tester, 'be-lib-builtin');
      expect(lk('be-lib-builtin-sheet'), findsOneWidget);
      expect(lk('be-lib-builtin-fork'), findsNothing);
      expect(find.text('复制一份来改'), findsNothing);
      expect(lk('be-lib-builtin-no-fork'), findsOneWidget);
      expect(find.text(kServiceForkOffNote), findsOneWidget);
    });
  });
}
