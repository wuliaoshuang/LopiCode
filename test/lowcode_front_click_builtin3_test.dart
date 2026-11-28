// 页面逻辑页里一步步点出来的路（积木第 5 版·第四轮·A5a）：用一个“靠着自带库的库”时问一句、点一下一起用上。
// 项目里有一个自己写的前端库“账本”（靠着自带的“状态仓库”）› 搭建页“更多 › 积木逻辑”›“更多 › 积木库…”› 点开“账本”›
// “在这份文档里用它”› 弹出“它要靠「状态仓库」，一起用上吗”› 先点取消（什么都没用上、说得出为什么）› 再点、点“一起用上”›
// 两个库都用上了、积木盒多出两页 › 拖“账本”的积木 › 存盘 › 三种网页真编译真跑。两个安全开关都是默认的关着。
//   LOPI_SHOTS=1 flutter test --no-pub test/lowcode_front_click_builtin3_test.dart   # 截图写到 ../preview/front/a5a/
@Tags(['needs-webdev'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/backend/backend_lib_store.dart';
import 'package:lopicode/lang/lib_model.dart';
import 'package:lopicode/lang/rules.dart';
import 'package:lopicode/lowcode/logic_model.dart';
import 'package:material_ui/material_ui.dart';

import 'support/backend_core_samples.dart';
import 'support/backend_func_blocks.dart';
import 'support/backend_lang_blocks.dart';
import 'support/front_libs_samples.dart';
import 'support/front_ui.dart';
import 'support/harness.dart';
import 'support/lowcode_builder.dart';
import 'support/page_front_samples.dart';
import 'support/user_libs.dart';

Future<void> _shot(WidgetTester tester, String name) => lbShot(tester, '../preview/front/a5a', name);

const String _book = 'shuang/book';

/// 自己写的前端库“账本”：包一层自带的“状态仓库”。
J _bookLib() {
  final doc = libDoc(
    '账本',
    _book,
    uses: [use('lopi/store')],
    functions: [
      tfn(
        'f1',
        '记一笔',
        [tpar('名', tText)],
        [
          lb('lopi/store', 'set', {'store': tx('账本'), 'key': pm('名'), 'value': tx('有')}),
        ],
      ),
    ],
    blocks: [
      def(
        'add',
        'call',
        fn: 'f1',
        look: look('记一笔', '往账本记一笔 {名}', shape: 'statement'),
      ),
    ],
  );
  return {
    ...doc,
    'library': {...doc['library'] as Map, 'for': 'frontend'},
  };
}

void main() {
  setUpAll(() async => lbFontsLoaded = await loadRealFonts());

  testWidgets('积木库… › 账本 › 用它 › 问“它要靠「状态仓库」，一起用上吗”› 取消 › 再点 › 一起用上 › 拖它的积木 › 三种网页真编译真跑', (tester) async {
    expect((kLibNativeCodeEnabled, kUserLibHostEnabled), (false, false), reason: '这条路考的是默认状态');
    final session = await fuOpen(tester, frontPage([btn('b1', '记'), txt('t1')], [], frontDoc()));
    // 项目里先放好一个自己写的库（新建、写、存这条路 lowcode_front_click_lib_test 一步步点过，这里直接放）。
    await tester.runAsync(() async {
      final made = await beLibCreate(session.guard, id: _book, name: '账本', author: '霜霜', side: LibSide.frontend);
      expect(made.problem, isNull);
      final saved = await beLibSaveSource(session.guard, made.rel!, parseLangBlocksDocument(_bookLib()));
      expect(saved.problems, isEmpty);
      expect(saved.written, isTrue);
    });
    final page = fuHost(tester);

    // 1 积木库… › 账本
    await fuMore(tester, 'libs');
    await fuUntil(tester, () => fk('be-lib-$_book').evaluate().isNotEmpty, '积木库面板里有“账本”');
    await fuTap(tester, 'be-lib-$_book');
    expect(tester.widget<SwitchListTile>(fk('be-lib-use')).value, isFalse);

    // 2 用它 → 问一句；取消＝两个都没用上，面板上说得出为什么
    await fuTap(tester, 'be-lib-use');
    expect(find.text('它要靠「状态仓库」，一起用上吗'), findsOneWidget);
    await _shot(tester, 'together-1-ask');
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(page.doc.use(_book), isNull);
    expect(page.doc.use('lopi/store'), isNull);
    expect(find.text('没有用上：「账本」要靠「状态仓库」。'), findsOneWidget);
    expect(tester.widget<SwitchListTile>(fk('be-lib-use')).value, isFalse);

    // 3 再点 → 一起用上：点一下，两个都用上了
    await fuTap(tester, 'be-lib-use');
    await tester.tap(find.text('一起用上'));
    await tester.pumpAndSettle();
    await fuUntil(tester, () => page.doc.use(_book) != null && page.doc.use('lopi/store') != null, '两个库都用上');
    expect(tester.widget<SwitchListTile>(fk('be-lib-use')).value, isTrue);
    expect(find.text('没有用上：「账本」要靠「状态仓库」。'), findsNothing);
    await _shot(tester, 'together-2-on');
    await fuCloseSheets(tester, 'be-libs');
    expect(page.categories.map((c) => c.id), containsAll(['lib:$_book', 'lib:lopi/store']), reason: '积木盒多出两页');

    // 4 已经用上“状态仓库”的时候不再问：关掉“账本”再开，直接就开了
    await fuMore(tester, 'libs');
    await fuUntil(tester, () => fk('be-lib-$_book').evaluate().isNotEmpty, '积木库面板里有“账本”');
    await fuTap(tester, 'be-lib-$_book');
    await fuTap(tester, 'be-lib-use');
    await fuUntil(tester, () => page.doc.use(_book) == null, '关掉账本');
    await fuTap(tester, 'be-lib-use');
    expect(find.text('它要靠「状态仓库」，一起用上吗'), findsNothing);
    await fuUntil(tester, () => page.doc.use(_book) != null, '再用上账本');
    await fuCloseSheets(tester, 'be-libs');

    // 5 点“记”：往账本记一笔〔甲〕，再把 t1 的文字改成〔记了〕
    await fuDropHat(tester, 'lib:lopi/page:事件', 'hat-libhat:lib:lopi/page#onClick', const Offset(40, 40));
    final h1 = page.doc.hats.last.id;
    await fuShow(tester, h1);
    await fuPick(tester, fuHatSlot(tester, h1, 'node'), 'b1');
    await fuDropStmt(tester, 'lib:$_book', 'block-lib:$_book#add', h1, const [], 0);
    await fuInline(tester, fuArg(tester, h1, [lcStep(0)], '名'), '甲');
    await fuDropStmt(tester, 'lib:lopi/page:控件', 'block-lib:lopi/page#propSet', h1, const [], 1);
    await fuPick(tester, fuArg(tester, h1, [lcStep(1)], 'node'), 't1');
    await fuPick(tester, fuArg(tester, h1, [lcStep(1)], 'prop'), 'text');
    await fuInline(tester, fuArg(tester, h1, [lcStep(1)], 'value'), '记了');
    expect(fuErrors(tester), isEmpty);
    await _shot(tester, 'together-3-canvas');

    // 6 存盘 → 三种网页真编译真跑（没把“状态仓库”一起用上的话，这一页的逻辑是导不出来的）
    final saved = await fuSavedAndRun(tester, session, [click('b1'), textIs('t1', '记了')]);
    expect(saved.logic.uses.map((u) => u['id']), containsAll([_book, 'lopi/store']));
  });
}
