// 第四轮 B5：状态样式分屏宽——按下 / 禁用 / 聚焦时的样子，在平板、桌面档可以另设（存在 responsive.<档>.states.<状态>）。
// 前半：读写规矩、网页类三种导出的 @media 规则、旧文件不变。
// 后半（390×844，逐步点击）：顶栏切到平板 → 选中按钮 → 样式页顶上选“按下” → 改一条 → 只记进平板档的按下；
// 手机上“按下”的样子没动；画布照这一档这个状态画；“清掉”只清这一档的。
// 没覆盖的：真浏览器里 @media + :active 的实际效果（这里只核对生成的规则文字）；Flutter 导出不带这一部分（说明里会写一句，这里没有核对那句话）。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/lowcode/canvas_view.dart';
import 'package:lopicode/lowcode/model.dart';
import 'package:lopicode/lowcode/responsive.dart';
import 'package:lopicode/lowcode/states.dart';
import 'package:lopicode/lowcode/states_bp.dart';

import 'support/bind_export_files.dart';
import 'support/comp_samples.dart';
import 'support/harness.dart';
import 'support/lowcode_builder.dart';

final String _shotDir = Platform.environment['LOPI_SHOT_DIR'] ?? '.tmp/editor-r4b5-shots';

LcDocument _doc([Map<String, Object?> more = const {}]) => LcDocument.fromJson(
  <String, Object?>{
    'version': 3,
    'title': 'Bp',
    'root': cn('root', 'page', {}, [
      cn('buy', 'button', {'text': '买'}, [], more),
      cn('hi', 'text', {'text': '你好'}),
    ]),
  }.cast<String, dynamic>(),
);

const _both = {
  'states': {
    'pressed': {'background-color': '#111111', 'color': '#ffffff'},
  },
  'responsive': {
    'tablet': {
      'style': {'padding': '20px'},
      'states': {
        'pressed': {'background-color': '#222222'},
        'disabled': {'opacity': '0.2'},
        'later': {'x': 'y'},
      },
    },
    'desktop': {
      'states': {
        'pressed': {'color': '#333333'},
      },
    },
  },
};

void main() {
  setUpAll(() async => lbFontsLoaded = await loadRealFonts());

  group('读写', () {
    test('各档自己的、叠起来看到的；不认识的状态名原样留着', () {
      final n = _doc(_both).find('buy')!;
      expect(lcHasBpStates(n), isTrue);
      expect(lcBpStateStyle(n, 'tablet', 'pressed'), {'background-color': '#222222'});
      expect(lcBpStateStyle(n, 'desktop', 'pressed'), {'color': '#333333'});
      expect(lcBpStateStyle(n, 'desktop', 'disabled'), isEmpty);
      expect(lcStateStyleAt(n, 'pressed', null), {'background-color': '#111111', 'color': '#ffffff'});
      expect(lcStateStyleAt(n, 'pressed', 'tablet'), {'background-color': '#222222', 'color': '#ffffff'});
      expect(lcStateStyleAt(n, 'pressed', 'desktop'), {'background-color': '#222222', 'color': '#333333'});
      expect(lcStateStyleAt(n, 'disabled', 'desktop'), {'opacity': '0.2'});
      expect(lcStateStyleAt(n, 'focused', 'desktop'), isEmpty);
      // 存出去读回来一个字不变（连看不懂的 later 也在）
      final doc = _doc(_both);
      expect(LcDocument.parse(doc.encode()).encode(), doc.encode());
      expect(doc.encode(), contains('"later"'));
    });

    test('在平板档改：只记和下面不一样的；改回和手机一样＝这一档不再管；清空了字段不留；这一档的普通样式不受影响', () {
      final n = _doc().find('buy')!;
      lcReplaceState(n, 'pressed', {'background-color': '#111111'});
      lcEditStateAtBp(n, 'tablet', 'pressed', (m) => m['background-color'] = '#222222');
      expect(lcBpStateStyle(n, 'tablet', 'pressed'), {'background-color': '#222222'});
      expect(lcStateStyle(n, 'pressed'), {'background-color': '#111111'}, reason: '手机上的没动');
      expect(n.style, isEmpty);
      lcReplaceBp(n, 'tablet', {'padding': '20px'});
      expect(lcBpStateStyle(n, 'tablet', 'pressed'), {'background-color': '#222222'}, reason: '改这一档的普通样式不碰状态的');
      lcEditStateAtBp(n, 'tablet', 'pressed', (m) => m['background-color'] = '#111111');
      expect(lcBpStateStyle(n, 'tablet', 'pressed'), isEmpty);
      expect((n.more['responsive'] as Map)['tablet'], {
        'style': {'padding': '20px'},
      });
      lcReplaceBp(n, 'tablet', const {});
      expect(n.more.containsKey('responsive'), isFalse);
      // 类名成立那种“状态”不分屏宽
      expect(lcStateSplitsByBp('class:on'), isFalse);
      expect(lcStateSplitsByBp('pressed'), isTrue);
      expect(lcStateSplitsByBp(null), isFalse);
    });
  });

  group('导出', () {
    test('网页类三种：各档的 @media 里多出带伪类的规则，排在这一档普通规则后面', () {
      final all = allExportFiles(_doc(_both));
      for (final path in ['html/style.css', 'vue/Bp.vue', 'react/Bp.css']) {
        // Vue 的样式是一条声明一行，这里把空白压成一个空格再比（规则本身一个字不差）
        final css = all[path]!.replaceAll(RegExp(r'\s+'), ' ');
        final sel = path.startsWith('html') ? RegExp(r'[#.][\w-]*buy') : RegExp(r'\.n-buy');
        expect(css, contains(':active { background: #111111; color: #ffffff; }'), reason: path);
        final tablet = css.substring(css.indexOf('@media (min-width: 768px)'), css.indexOf('@media (min-width: 1024px)'));
        final desktop = css.substring(css.indexOf('@media (min-width: 1024px)'));
        expect(tablet, contains(':active { background: #222222; }'), reason: path);
        expect(tablet, contains(':disabled { opacity: 0.2; }'), reason: path);
        expect(tablet.indexOf('padding'), lessThan(tablet.indexOf(':active')), reason: '状态的规则在普通规则后面');
        expect(desktop, contains(':active { color: #333333; }'), reason: path);
        expect(desktop, isNot(contains('#222222')));
        expect(sel.hasMatch(tablet), isTrue);
        expect(css, isNot(contains('later')));
      }
    });

    test('只有状态分了屏宽、普通样式没分：也出 @media', () {
      final css = allExportFiles(
        _doc({
          'responsive': {
            'desktop': {
              'states': {
                'focused': {'outline-color': '#ff0000'},
              },
            },
          },
        }),
      )['html/style.css']!;
      expect(css, contains('@media (min-width: 1024px)'));
      expect(css, contains(':focus { outline-color: #ff0000; }'));
      expect(css, isNot(contains('@media (min-width: 768px)')));
    });

    test('没用这个功能的：导出里没有多出来的东西', () {
      final css = allExportFiles(_doc())['html/style.css']!;
      expect(css, isNot(contains('@media')));
    });
  });

  testWidgets('逐步点击：切到平板 → 选中按钮 → 样式页选“按下” → 改一条，只记进平板档的按下；清掉只清这一档的', (tester) async {
    final doc = _doc({
      'states': {
        'pressed': {'opacity': '0.8'},
      },
    });
    final session = await lbOpen(tester, doc: doc);
    await lbTap(tester, lbKey('lc-bp-open'));
    await lbTap(tester, lbKey('lc-bp-tablet'));
    await lbTap(tester, lbNode('buy'));
    await lbOpenCommon(tester);
    await lbTap(tester, find.text('样式').last);
    await lbTap(tester, lbKey('lc-state-pressed'));
    expect(find.textContaining('现在改的是“按下”时的样子，只在平板及更宽的屏上生效'), findsOneWidget);
    expect(tester.widget<CanvasView>(find.byType(CanvasView)).statePreview, (nodeId: 'buy', state: 'pressed'));
    await lbTapShown(tester, lbKey('lc-tab-layout'));
    await lbTapShown(tester, lbKey('lc-num-flex-grow-plus'));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    var buy = (await lbSaved(tester, session)).find('buy')!;
    expect(lcBpStateStyle(buy, 'tablet', 'pressed'), {'flex-grow': '1'});
    expect(lcStateStyle(buy, 'pressed'), {'opacity': '0.8'}, reason: '手机上“按下”的样子没动');
    expect(lcBpStyle(buy, 'tablet'), isEmpty, reason: '平板平时的样子没动');
    expect(buy.style.containsKey('flex-grow'), isFalse);
    await lbShow(tester, lbKey('lc-bp-note'));
    await lbShot(tester, _shotDir, 'b5-state-at-tablet');
    await lbShow(tester, lbKey('lc-state-bar'));
    await lbTapShown(tester, lbKey('lc-state-clear'));
    buy = (await lbSaved(tester, session)).find('buy')!;
    expect(buy.more.containsKey('responsive'), isFalse, reason: '这一档的清掉了');
    expect(lcStateStyle(buy, 'pressed'), {'opacity': '0.8'}, reason: '手机上的还在');
    expect(tester.takeException(), isNull);
  });
}
