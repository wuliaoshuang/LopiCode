// 库的界面（390×844）：从“更多 › 积木库”新建库 → 在库的画布上写函数 → “这个库”里公开成积木 → 回到另一份文档用上它 →
// 积木盒里多出这个库的一页；导出成文件；带手写代码的文件如实显示、不许导入；复制一份来改；拿掉。
//   flutter test --no-pub test/backend_lib_ui_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/backend/backend_lib_build.dart';
import 'package:lopicode/backend/backend_lib_pack.dart';
import 'package:lopicode/backend/backend_lib_table.dart';
import 'package:lopicode/ui/backend_screen.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;

import 'support/backend_core_samples.dart';
import 'support/backend_func_blocks.dart';
import 'support/backend_lang_blocks.dart';
import 'support/lib_ui.dart';
import 'support/user_libs.dart';

J emptyStrict() => {
  ...flowUserDoc(),
  'uses': <J>[],
  'hats': <J>[],
  'start': <J>[
    say([tx('你好')]),
  ],
};

void main() {
  testWidgets('从零：新建库 → 写函数 → 公开成积木 → 另一份文档用上它 → 积木盒多一页', (tester) async {
    final ui = await openLibUi(tester, emptyStrict());
    final dir = ui.project.dir;

    // 1. 更多 › 积木库 › 新建库
    await libTap(tester, 'be-more');
    expect(lk('be-menu-lib-info'), findsNothing, reason: '普通文档没有“这个库”');
    await libTap(tester, 'be-menu-libs');
    expect(lk('be-libs'), findsOneWidget);
    expect(find.textContaining('库＝别人'), findsOneWidget, reason: '一个库都没有时有一句说明');
    await libTap(tester, 'be-lib-new');
    await libType(tester, '问好');
    await libType(tester, 'shuang/hello');
    await libUntil(tester, () => find.textContaining('库 · 公开了').evaluate().isNotEmpty, what: '新建完进库的画布');
    expect(File(p.join(dir, 'blocks/shuang/hello/source/backend.lc.json')).existsSync(), isTrue);

    // 2. 新建完直接进了库的画布（盖在上面的一页）；副标题说它是库
    final libScreen = tester.state<BackendScreenState>(find.byType(BackendScreen).last);
    final libHost = libScreen.host!;
    expect(libHost.doc.library?.id, 'shuang/hello');
    expect(find.textContaining('库 · 公开了 0 块积木'), findsOneWidget);

    // 3. 在库里写一个函数（界面上是从积木盒“我的积木”新建；这里直接经宿主放进去，写函数的界面另有测试）
    final fn = parseLangBlocksDocument({
      ...emptyStrict(),
      'functions': [
        tfn(
          'f1',
          '问好',
          [tpar('谁', tText)],
          [
            ret(cat([tx('你好，'), pm('谁')])),
          ],
          returns: tText,
        ),
      ],
    }).functions.single;
    libHost.edit(() => libHost.doc.functions.add(fn));
    await libSettle(tester);

    // 4. 更多 › 这个库 › 问好 › 公开成积木
    await libTap(tester, 'be-more');
    await libTap(tester, 'be-menu-lib-info');
    expect(lk('be-lib-info'), findsOneWidget);
    await libTap(tester, 'be-lib-def-f1');
    await libTap(tester, 'be-lib-def-public');
    expect(libHost.doc.library!.blocks.single.fn, 'f1');
    await libTap(tester, 'be-lib-def-look');
    await libType(tester, '向 {谁} 问好');
    expect(libHost.doc.library!.blocks.single.look?.template, '向 {谁} 问好');
    expect(beLibFiles(libHost.doc).problems, isEmpty);
    // 同一个槽写两次：面板顶上说出来
    await libTap(tester, 'be-lib-def-look');
    await libType(tester, '向 {谁} 问好 {谁}');
    expect(lk('be-sheet-problem'), findsWidgets);
    await libTap(tester, 'be-lib-def-look');
    await libType(tester, '向 {谁} 问好');
    await tester.tap(lk('be-sheet-done').last);
    await libSettle(tester, rounds: 2);
    await tester.tap(lk('be-sheet-done').last);
    await libSettle(tester);
    await libUntil(tester, () => File(p.join(dir, 'blocks/shuang/hello/lib.json')).existsSync(), what: '库存盘就出库文件');

    // 5. 回到原来那份文档，在“积木库”里用上它
    await tester.binding.handlePopRoute();
    await libSettle(tester);
    final host = ui.screen.host!;
    await libTap(tester, 'be-more');
    await libTap(tester, 'be-menu-libs');
    expect(find.text('1 块积木'), findsOneWidget);
    await libTap(tester, 'be-lib-shuang/hello');
    await libTap(tester, 'be-lib-use');
    expect(host.doc.use('shuang/hello'), isNotNull);
    expect(host.categories.map((c) => c.id), contains('lib:shuang/hello'));
    expect(BeLibTable(host.doc).ofLib('shuang/hello').single.sentence, contains('问好'));

    // 6. 导出成一个文件
    await libTap(tester, 'be-lib-export');
    await libUntil(tester, () => lk('be-lib-note').evaluate().isNotEmpty, what: '导出');
    expect(lk('be-lib-note'), findsOneWidget);
    final packs = Directory(p.join(dir, 'exports')).listSync().whereType<File>().where((f) => f.path.endsWith(kBeLibFileSuffix)).toList();
    expect(packs, hasLength(1));

    // 7. 不用了：没有用到它的积木，直接能关
    await libTap(tester, 'be-lib-use');
    expect(host.doc.use('shuang/hello'), isNull);
  });

  testWidgets('设置项、还在用就关不掉、复制一份来改、拿掉', (tester) async {
    final ui = await openLibUi(tester, flowUserDoc(), libs: [flowLibDoc()]);
    final host = ui.screen.host!;
    expect(host.issues.where((i) => i.isError), isEmpty, reason: '项目里的库读进来了，库积木不标红');
    expect(host.categories.map((c) => c.id), contains('lib:$kLibFlow'));

    await libTap(tester, 'be-more');
    await libTap(tester, 'be-menu-libs');
    expect(find.textContaining('用上了'), findsOneWidget);
    await libTap(tester, 'be-lib-$kLibFlow');
    // 设置项：填错说原因，填对写进文档
    await libTap(tester, 'be-lib-setting-tries');
    await libType(tester, '99');
    expect(find.textContaining('要在 1 到 9 之间'), findsOneWidget);
    await libTap(tester, 'be-lib-setting-tries');
    await libType(tester, '3');
    expect(host.doc.use(kLibFlow)!.settings['tries'], 3);
    // 还在用它的积木：关不掉，说有几处
    await libTap(tester, 'be-lib-use');
    expect(host.doc.use(kLibFlow), isNotNull);
    expect(find.textContaining('处在用它的积木'), findsOneWidget);

    // 复制一份来改：换标识；问一次要不要把用法换过去
    await libTap(tester, 'be-lib-fork');
    await libType(tester, '流程二');
    await libType(tester, 'shuang/flow2');
    await libUntil(tester, () => find.textContaining('换过去吗').evaluate().isNotEmpty, what: '复制完问要不要换用法');
    expect(find.textContaining('换过去吗'), findsOneWidget);
    await tester.tap(find.text('换过去'));
    await libUntil(tester, () => find.textContaining('库 · 公开了').evaluate().isNotEmpty, what: '进复制出来的库的画布');
    expect(host.doc.use('shuang/flow2'), isNotNull);
    expect(host.doc.use(kLibFlow), isNull);
    final copy = tester.state<BackendScreenState>(find.byType(BackendScreen).last).host!;
    expect(copy.doc.library?.id, 'shuang/flow2');
    expect(copy.doc.library?.originId, kLibFlow);
    await tester.binding.handlePopRoute();
    await libSettle(tester);
    expect(host.issues.where((i) => i.isError), isEmpty, reason: '换过去以后照样不标红');

    // 拿掉原来那个
    await libTap(tester, 'be-more');
    await libTap(tester, 'be-menu-libs');
    await libTap(tester, 'be-lib-$kLibFlow');
    await libTap(tester, 'be-lib-remove');
    await tester.tap(find.text('拿掉'));
    await libUntil(tester, () => lk('be-lib-$kLibFlow').evaluate().isEmpty && lk('be-lib-shuang/flow2').evaluate().isNotEmpty, what: '拿掉');
    expect(Directory(p.join(ui.project.dir, 'blocks/shuang/flow')).existsSync(), isFalse);
    expect(lk('be-lib-$kLibFlow'), findsNothing);
    expect(lk('be-lib-shuang/flow2'), findsOneWidget);
  });

  testWidgets('从文件导入：先看预览；带手写代码的如实显示、能看代码、不许导入', (tester) async {
    final built = beLibFiles(parseLangBlocksDocument(checkLibDoc()));
    expect(built.problems, isEmpty);
    final ui = await openLibUi(
      tester,
      emptyStrict(),
      files: {
        '校验器.lopilib': beLibPack(built.files!),
        'exports/带手写.lopilib': beLibPack({...built.files!, 'native/hack.js': 'require("child_process")'}),
      },
    );
    await libTap(tester, 'be-more');
    await libTap(tester, 'be-menu-libs');
    await libTap(tester, 'be-lib-import');
    await tester.tap(lk('be-lib-file-exports/带手写.lopilib'));
    await libUntil(tester, () => lk('be-lib-import-sheet').evaluate().isNotEmpty, what: '预览');
    expect(lk('be-lib-import-sheet'), findsOneWidget);
    expect(find.textContaining('这一版的应用不会把手写代码放进生成的工程里'), findsOneWidget);
    expect(tester.widget<FilledButton>(lk('be-lib-import-go')).onPressed, isNull, reason: '带手写代码的不许导入');
    await libTap(tester, 'be-lib-native-native/hack.js');
    expect(find.textContaining('child_process'), findsOneWidget, reason: '代码给看');
    await tester.tap(lk('be-sheet-done').last);
    await libSettle(tester, rounds: 2);
    await tester.tap(lk('be-sheet-done').last);
    await libSettle(tester, rounds: 2);
    expect(Directory(p.join(ui.project.dir, 'blocks')).existsSync(), isFalse, reason: '什么都没放进项目');

    await libTap(tester, 'be-lib-import');
    await tester.tap(lk('be-lib-file-校验器.lopilib'));
    await libUntil(tester, () => lk('be-lib-import-sheet').evaluate().isNotEmpty, what: '预览');
    expect(find.text(kLibCheck), findsOneWidget);
    await tester.tap(lk('be-lib-import-go'));
    await libUntil(tester, () => lk('be-lib-$kLibCheck').evaluate().isNotEmpty, what: '导入');
    expect(lk('be-lib-$kLibCheck'), findsOneWidget);
    expect(File(p.join(ui.project.dir, 'blocks/$kLibCheck/lib.json')).existsSync(), isTrue);
  });
}
