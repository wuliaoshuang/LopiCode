// 第四轮·A1 的界面（390×844）：
// - 手写代码的四种状态：开关关着拒绝／打开要二次确认／每个库再确认一次／代码变了要重新确认；
// - “给谁用”对不上的库：开关灰着、写着原因；
// - 自带的“接口服务”复制一份来改：复制 → 用它顶替 → 改库的文字（改坏了不存）。
//   flutter test --no-pub test/lib_more_ui_test.dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/backend/backend_lib_pack.dart';
import 'package:lopicode/backend/lib_native_trust.dart';
import 'package:lopicode/ui/settings_lib_native.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;

import 'support/backend_core_samples.dart';
import 'support/backend_func_blocks.dart';
import 'support/backend_lang_blocks.dart';
import 'support/harness.dart' hide say;
import 'support/lib_ui.dart';
import 'support/native_lib.dart';
import 'support/user_libs.dart';

J emptyStrict() => {
  ...flowUserDoc(),
  'uses': <J>[],
  'hats': <J>[],
  'start': <J>[
    say([tx('你好')]),
  ],
};

Map<String, List<int>> asProjectLib(String id, Map<String, String> files) => {for (final e in files.entries) 'blocks/$id/${e.key}': utf8.encode(e.value)};

Future<void> openLibs(WidgetTester tester) async {
  await libTap(tester, 'be-more');
  await libTap(tester, 'be-menu-libs');
}

Future<void> closeSheet(WidgetTester tester) async {
  await tester.tap(lk('be-sheet-done').last);
  await libSettle(tester, rounds: 3);
}

void main() {
  setUp(() => LibNativeTrust.instance = LibNativeTrust());
  tearDown(() => LibNativeTrust.instance = LibNativeTrust());

  testWidgets('设置里的开关：默认关；打开要过一道确认，取消就还是关；关掉不用确认', (tester) async {
    usePhoneViewport(tester);
    late TestEnv env;
    await tester.runAsync(() async => env = await TestEnv.create());
    addTearDown(() => tester.runAsync(env.dispose));
    await tester.pumpWidget(appFor(env, const LibNativeSettingsScreen()));
    await settle(tester);
    Switch sw() => tester.widget<Switch>(find.byKey(const Key('lib-native-switch')));
    expect(sw().value, isFalse, reason: '默认关');
    expect(find.textContaining('同一个进程里'), findsWidgets, reason: '风险说明直接写在页面上');
    await tester.tap(find.byKey(const Key('lib-native-switch')));
    await settle(tester);
    expect(find.text('允许库里的手写代码吗'), findsOneWidget, reason: '打开要二次确认');
    expect(LibNativeTrust.instance.enabled, isFalse, reason: '没确认之前不算开');
    await tester.tap(find.text('取消'));
    await settle(tester);
    expect(sw().value, isFalse);
    await tester.tap(find.byKey(const Key('lib-native-switch')));
    await settle(tester);
    await tester.tap(find.text('我明白，打开'));
    await settle(tester);
    expect(sw().value, isTrue);
    expect(LibNativeTrust.instance.enabled, isTrue);
    await tester.tap(find.byKey(const Key('lib-native-switch')));
    await settle(tester);
    expect(sw().value, isFalse);
    expect(find.text('允许库里的手写代码吗'), findsNothing);
  });

  testWidgets('带手写代码的库：关着拒绝 → 开着要勾“我看过了”才能导入 → 代码变了要重新确认', (tester) async {
    final ui = await openLibUi(tester, emptyStrict(), files: {'手写示例.lopilib': beLibPack(handLibFiles())});
    final libDir = p.join(ui.project.dir, 'blocks', kLibHand);

    // 1. 开关关着：能看代码，不能导入。
    await openLibs(tester);
    await libTap(tester, 'be-lib-import');
    await libUntil(tester, () => lk('be-lib-import-sheet').evaluate().isNotEmpty, what: '预览');
    expect(tester.widget<FilledButton>(lk('be-lib-import-go')).onPressed, isNull);
    await libSee(tester, 'be-lib-native-off');
    expect(lk('be-lib-native-off'), findsOneWidget);
    await libSee(tester, 'be-lib-native-native/join.go');
    expect(find.textContaining('手写函数「twice」：要等'), findsOneWidget);
    expect(lk('be-lib-native-seen'), findsNothing);
    await libTap(tester, 'be-lib-native-native/join.go');
    expect(find.textContaining('strings.Join'), findsOneWidget, reason: '代码给看全文');
    await closeSheet(tester);
    await closeSheet(tester);
    expect(Directory(libDir).existsSync(), isFalse);

    // 2. 开关开着：先是灰的；勾了“我看过这些代码了”才点得动。
    await tester.runAsync(() => LibNativeTrust.instance.setEnabled(true));
    await libTap(tester, 'be-lib-import');
    await libUntil(tester, () => lk('be-lib-import-sheet').evaluate().isNotEmpty, what: '预览');
    expect(tester.widget<FilledButton>(lk('be-lib-import-go')).onPressed, isNull, reason: '没勾之前不许导入');
    await libSee(tester, 'be-lib-native-risk');
    expect(lk('be-lib-native-risk'), findsOneWidget);
    expect(lk('be-lib-native-off'), findsNothing);
    await libTap(tester, 'be-lib-native-seen');
    expect(tester.widget<FilledButton>(lk('be-lib-import-go')).onPressed, isNotNull);
    await tester.tap(lk('be-lib-import-go'));
    await libUntil(tester, () => lk('be-lib-$kLibHand').evaluate().isNotEmpty, what: '导入完回到库的清单');
    expect(File(p.join(libDir, 'native/join.go')).existsSync(), isTrue);
    expect(
      find.descendant(of: lk('be-lib-$kLibHand'), matching: find.textContaining('2 块积木')),
      findsOneWidget,
      reason: '确认过，能用',
    );
    await closeSheet(tester);

    // 3. 项目里的手写代码被改了（比如 Agent 改的）：这个库立刻“有问题”，要重新看、重新确认。
    await tester.runAsync(() async => File(p.join(libDir, 'native/join.js')).writeAsString('module.exports = function (s, n) { return "改过了"; };\n'));
    await openLibs(tester);
    await libUntil(tester, () => lk('be-lib-$kLibHand').evaluate().isNotEmpty, what: '库的清单');
    expect(find.descendant(of: lk('be-lib-$kLibHand'), matching: find.text('有问题')), findsOneWidget);
    await libTap(tester, 'be-lib-$kLibHand');
    expect(lk('be-lib-use'), findsNothing, reason: '没重新确认之前用不了');
    await libTap(tester, 'be-lib-native-confirm');
    await libUntil(tester, () => lk('be-lib-import-sheet').evaluate().isNotEmpty, what: '确认页');
    expect(find.text('确认手写代码'), findsOneWidget);
    await libTap(tester, 'be-lib-native-native/join.js');
    expect(find.textContaining('改过了'), findsOneWidget, reason: '看到的是改过以后的代码');
    await closeSheet(tester);
    expect(tester.widget<FilledButton>(lk('be-lib-import-go')).onPressed, isNull);
    await libTap(tester, 'be-lib-native-seen');
    await tester.tap(lk('be-lib-import-go'));
    await libUntil(tester, () => lk('be-lib-import-sheet').evaluate().isEmpty && lk('be-lib-$kLibHand').evaluate().isNotEmpty, what: '确认完回到库的清单');
    await libUntil(
      tester,
      () => find.descendant(of: lk('be-lib-$kLibHand'), matching: find.textContaining('2 块积木')).evaluate().isNotEmpty,
      what: '重新确认以后又能用',
    );
    await libTap(tester, 'be-lib-$kLibHand');
    await libTap(tester, 'be-lib-use');
    expect(ui.screen.host!.doc.use(kLibHand), isNotNull);
  });

  testWidgets('给谁用对不上：开关灰着、写着原因', (tester) async {
    final front = buildUserLib(
      {
          ...libDoc(
            '只给前端',
            'tata/front',
            functions: [
              tfn('f1', '甲', [tpar('话', tText)], [ret(pm('话'))], returns: tText),
            ],
            blocks: [
              def(
                'a',
                'call',
                fn: 'f1',
                look: look('甲', '甲 {话}', shape: 'value'),
              ),
            ],
          ),
        }
        ..['library'] = {
          'id': 'tata/front',
          'version': '1.0.0',
          'for': 'frontend',
          'blocks': [
            def(
              'a',
              'call',
              fn: 'f1',
              look: look('甲', '甲 {话}', shape: 'value'),
            ),
          ],
        },
    );
    expect(front.lib.side.name, 'frontend');
    final ui = await openLibUi(tester, emptyStrict(), files: asProjectLib('tata/front', front.files));
    await openLibs(tester);
    await libUntil(tester, () => lk('be-lib-tata/front').evaluate().isNotEmpty, what: '库的清单');
    await libTap(tester, 'be-lib-tata/front');
    expect(find.textContaining('给前端用'), findsWidgets);
    expect(find.textContaining('只给前端用的库'), findsOneWidget, reason: '写着为什么不能用');
    expect(tester.widget<SwitchListTile>(lk('be-lib-use')).onChanged, isNull, reason: '灰着');
    expect(ui.screen.host!.doc.use('tata/front'), isNull);
  });

  testWidgets('“接口服务”复制一份来改：复制 → 用它顶替 → 改库的文字（改坏了不存，改对了存）', (tester) async {
    final ui = await openLibUi(tester, emptyStrict());
    final libDir = p.join(ui.project.dir, 'blocks', 'shuang', 'svc');
    final errorsBefore = [for (final i in ui.screen.host!.issues.where((i) => i.isError)) i.message];
    await openLibs(tester);
    await libTap(tester, 'be-lib-builtin');
    expect(lk('be-lib-builtin-sheet'), findsOneWidget);
    await libTap(tester, 'be-lib-builtin-fork');
    await libType(tester, '我的接口服务');
    await libType(tester, 'shuang/svc');
    await libUntil(tester, () => lk('be-lib-sheet-shuang/svc').evaluate().isNotEmpty, what: '复制完打开新库的面板');
    expect(File(p.join(libDir, 'modules/service.lc')).existsSync(), isTrue);
    expect(find.text('它直接用的宿主能力'), findsOneWidget);
    expect(lk('be-lib-use'), findsNothing, reason: '顶替用的库不当普通库用上');

    // 用它顶替
    await libTap(tester, 'be-lib-replace');
    expect(ui.screen.host!.doc.serviceLib, 'shuang/svc');
    expect([for (final i in ui.screen.host!.issues.where((i) => i.isError)) i.message], errorsBefore, reason: '换成用复制件以后没有多出问题');

    // 改库的文字：先改坏
    await libTap(tester, 'be-lib-text-open');
    expect(lk('be-lib-text'), findsOneWidget);
    await libTap(tester, 'be-lib-text-modules/service.lc');
    expect(lk('be-lib-text-page'), findsOneWidget);
    final before = File(p.join(libDir, 'modules/service.lc')).readAsStringSync();
    await tester.enterText(lk('be-lib-text-field'), '(模块 shuang/svc (函数 坏了');
    await tester.tap(lk('be-lib-text-save'));
    await libUntil(tester, () => lk('be-lib-text-problem').evaluate().isNotEmpty, what: '存不了的原因');
    expect(File(p.join(libDir, 'modules/service.lc')).readAsStringSync(), before, reason: '改坏的没有存');
    expect(find.textContaining('第 1 行'), findsOneWidget, reason: '说得出是哪一行');
    // “检查”只查不存：写对的说没有问题，文件没动
    await tester.enterText(lk('be-lib-text-field'), '$before\n; 只是查查\n');
    await tester.tap(lk('be-lib-text-check'));
    await libUntil(tester, () => lk('be-lib-text-fine').evaluate().isNotEmpty, what: '检查过了没有问题');
    expect(lk('be-lib-text-problem'), findsNothing);
    expect(File(p.join(libDir, 'modules/service.lc')).readAsStringSync(), before, reason: '检查不存');
    // 再改对
    await tester.enterText(lk('be-lib-text-field'), '$before\n; 霜霜改过\n');
    await tester.tap(lk('be-lib-text-save'));
    await libUntil(tester, () => lk('be-lib-text-page').evaluate().isEmpty, what: '存好了回去');
    expect(File(p.join(libDir, 'modules/service.lc')).readAsStringSync(), contains('霜霜改过'));
  });
}
