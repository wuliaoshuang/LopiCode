// 第四轮 B8（上）：一步步点出来看——
// 1. 步进器开箱即用：组件盒里点出一个步进器，什么线都不接；画布上的数就是它自己记的那个状态（补线的结果有缓存，
//    画布重画不会一遍遍拷文档）；项目里存下来的网页（应用里“预览”读的那几个文件）在 jsdom 里点加减，数字真的变。
// 2. 图标按钮面板“属性跟着状态变”一栏：属性名是中文（“禁用”“说明文字”），选状态的单子标题也是。
// 4. 就地改字：列表（一行一项）、图片（说明文字）。
// 5. 多选“样式”：几个的值不一样的那一行先写“多个值”，点开以后改了几个一起变；值一样的行照常。
@Tags(['external'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/lowcode/comp_lib_builtin.dart';
import 'package:lopicode/lowcode/comp_self_wire.dart';
import 'package:lopicode/lowcode/inline_text_widgets.dart';
import 'package:lopicode/lowcode/model.dart';
import 'package:lopicode/lowcode/multi_select.dart';
import 'package:material_ui/material_ui.dart';

import 'support/b8_ui.dart';
import 'support/dev_tools.dart';
import 'support/harness.dart';
import 'support/lowcode_builder.dart';

LcDocument _plain() => b8Page([
  b8Node('t1', 'text', {'text': '标题'}),
  b8Node('li', 'list', {
    'items': ['苹果', '香蕉'],
  }),
  b8Node('img', 'image', {'src': '', 'height': 120, 'width': 'fill'}),
  b8Node('a', 'button', {'text': '甲', 'padding': 8, 'radius': 6}),
  b8Node('b', 'button', {'text': '乙', 'padding': 16, 'radius': 6}),
]);

void main() {
  setUpAll(() async => lbFontsLoaded = await loadRealFonts());

  test('多选：值不一样的是哪几项（比的是最后生效的样子）', () {
    final d = _plain();
    final fields = lcMultiCommonFields(d, {'a', 'b'});
    expect(fields, containsAll(['padding', 'radius']));
    expect(lcMultiMixed(d, {'a', 'b'}, fields), {'text', 'padding'}, reason: '上面的字（甲 / 乙）和内边距（8 / 16）不一样');
    d.find('b')!.props['padding'] = 8;
    d.find('b')!.props['text'] = '甲';
    expect(lcMultiMixed(d, {'a', 'b'}, fields), isEmpty);
    // 写在样式页里的也算
    d.find('b')!.style['border-radius'] = '20px';
    expect(lcMultiMixed(d, {'a', 'b'}, fields), {'radius'});
    expect(lcMultiMixed(d, {'a'}, fields), isEmpty, reason: '只选了一个没有“不一样”');
  });

  test('就地改字：哪些能改、框里一开始是什么、写回去是什么', () {
    final d = _plain();
    final li = d.find('li')!, img = d.find('img')!;
    expect(inlineTextProp(li), 'items');
    expect(inlineTextInitial(li), '苹果\n香蕉');
    inlineTextWrite(li, '苹果\n\n  梨  \n');
    expect(li.props['items'], ['苹果', '梨'], reason: '一行一项，空行不算，两头的空格去掉');
    expect(inlineTextProp(img), 'alt');
    expect(inlineTextInitial(img), '');
    inlineTextWrite(img, '店门口');
    expect(img.props['alt'], '店门口');
    inlineTextWrite(img, '  ');
    expect(img.props.containsKey('alt'), isFalse, reason: '删空了就去掉');
    // 绑了状态的不在这里改
    li.more['data'] = {
      'items': {'from': 'var', 'name': 'xs'},
    };
    expect(inlineTextProp(li), isNull);
  });

  testWidgets('就地改字：点一下已经选中的列表，一行一项地改；图片改的是说明文字', (tester) async {
    final s = await lbOpen(tester, doc: _plain());
    await b8Tap(tester, lbNode('li'));
    expect(lbKey('lc-inline-edit'), findsNothing, reason: '第一下只是选中');
    await b8Tap(tester, lbNode('li'));
    await b8Until(tester, lbKey('lc-inline-edit'), '列表的就地改字框');
    expect(tester.widget<TextField>(lbKey('lc-inline-edit')).controller!.text, '苹果\n香蕉');
    await lbShot(tester, b8ShotDir, 'b8-inline-list');
    await tester.enterText(lbKey('lc-inline-edit'), '苹果\n香蕉\n橘子');
    await tester.pump();
    // 点别处＝改完
    await b8Tap(tester, lbNode('t1'));
    var doc = await lbSaved(tester, s);
    expect(doc.find('li')!.props['items'], ['苹果', '香蕉', '橘子']);
    expect(find.textContaining('橘子'), findsWidgets, reason: '画布上多了一项');
    // 一次改字一条撤销
    await b8Tap(tester, find.byTooltip('撤销'));
    doc = await lbSaved(tester, s);
    expect(doc.find('li')!.props['items'], ['苹果', '香蕉']);

    // 图片
    await b8Tap(tester, lbNode('img'));
    await b8Tap(tester, lbNode('img'));
    await b8Until(tester, lbKey('lc-inline-edit'), '图片说明的就地改字框');
    expect(find.text(kInlineAltHint), findsOneWidget, reason: '没写过说明：框里有一句灰字说这是什么');
    final box = tester.getRect(lbKey('lc-inline-edit')), image = tester.getRect(lbNode('img'));
    expect(box.bottom, lessThanOrEqualTo(image.bottom + 1), reason: '框贴在图片下沿、不出图片');
    expect(box.top, greaterThan(image.top + 20), reason: '不盖住整张图');
    await lbShot(tester, b8ShotDir, 'b8-inline-image-alt');
    await tester.enterText(lbKey('lc-inline-edit'), '店门口的照片');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settle(tester, rounds: 3);
    doc = await lbSaved(tester, s);
    expect(doc.find('img')!.props['alt'], '店门口的照片');
    expect((await b8PreviewFiles(tester, s))['index.html'], contains('aria-label="店门口的照片"'), reason: '导出的网页里带上了');
    expect(tester.takeException(), isNull);
  });

  testWidgets('多选“样式”：值不一样的那一行写“多个值”，点开再改，改了几个一起变', (tester) async {
    final s = await lbOpen(tester, doc: _plain());
    await b8LongPress(tester, lbNode('a'));
    await b8TapText(tester, '多选');
    await b8Tap(tester, lbNode('b'));
    expect(find.text('已选 2 个'), findsOneWidget);
    await b8Tap(tester, lbKey('lc-multi-style'));
    await b8Until(tester, lbKey('lc-multi-style-rows'), '一起改样式的面板');
    // 内边距不一样（8 和 16）：写着“多个值”；圆角一样（都是 6）：照常
    expect(lbKey('lc-multi-mixed-padding'), findsOneWidget);
    expect(lbKey('lc-multi-mixed-radius'), findsNothing);
    expect(find.textContaining('多个值'), findsWidgets);
    await lbShot(tester, b8ShotDir, 'b8-multi-mixed');
    // 没点开时里面的控件点不到：点“多个值”那一行只是点开，什么都没改
    await lbTapShown(tester, lbKey('lc-multi-mixed-padding'));
    await settle(tester, rounds: 2);
    expect(lbKey('lc-multi-mixed-padding'), findsNothing, reason: '点开了');
    var doc = await lbSaved(tester, s);
    expect(doc.find('a')!.props['padding'], 8);
    expect(doc.find('b')!.props['padding'], 16);
    await lbShot(tester, b8ShotDir, 'b8-multi-mixed-opened');
    // 点开以后选一档：两个一起变
    await lbTapShown(tester, lbKey('lc-preset-padding-24'));
    doc = await lbSaved(tester, s);
    expect(doc.find('a')!.props['padding'], 24);
    expect(doc.find('b')!.props['padding'], 24);
    expect(lbKey('lc-multi-mixed-padding'), findsNothing, reason: '现在一样了');
    expect(tester.takeException(), isNull);
  });

  testWidgets('图标按钮：“属性跟着状态变”一栏的属性名是中文', (tester) async {
    final s = await lbOpen(tester, doc: b8Page(const []));
    await b8Add(tester, 'basic', 'component:${lcBuiltinDefId('iconButton')}');
    final doc = await lbSaved(tester, s);
    final inst = doc.root.children.single;
    await b8Tap(tester, lbNode(inst.id));
    await lbOpenCommon(tester);
    await lbShow(tester, lbKey('comp-bind-disabled'));
    expect(find.descendant(of: lbKey('comp-bind-disabled'), matching: find.text('禁用')), findsOneWidget);
    expect(find.descendant(of: lbKey('comp-bind-label'), matching: find.text('说明文字')), findsOneWidget);
    expect(find.descendant(of: lbKey('comp-bind-disabled'), matching: find.text('disabled')), findsNothing);
    await lbShot(tester, b8ShotDir, 'b8-iconbutton-bind-names');
    await lbTapShown(tester, lbKey('comp-bind-disabled'));
    await b8Until(tester, find.text('禁用 跟着哪个状态变'), '选状态的单子');
    expect(tester.takeException(), isNull);
  });

  testWidgets('步进器开箱即用：组件盒点一个出来不接线——画布上的数是它自己记的状态；存下来给预览看的网页点加减真的变', (tester) async {
    final s = await lbOpen(tester, doc: b8Page(const []));
    await b8Add(tester, 'form', 'component:${lcBuiltinDefId('stepper')}');
    final doc = await lbSaved(tester, s);
    final inst = doc.root.children.single;
    await b8Until(tester, lbNode(inst.id), '画布上的步进器');
    expect(find.descendant(of: lbNode(inst.id), matching: find.text('1')), findsOneWidget);
    // 画布这边用的也是补过线的那一份：它记着的状态在；重画几遍不再多拷文档
    final wired = lcSelfWiredHere(doc);
    expect(identical(wired, doc), isFalse);
    expect(wired.logic.variables.map((v) => v.name), contains(lcHeldName(inst.id, 'value')));
    final copies = lcSelfWiredCopies;
    expect(identical(lcSelfWiredHere(doc), wired), isTrue, reason: '什么都没变：用记着的那一份');
    expect(lcSelfWiredCopies, copies);
    // 她的页面文件里没有多出状态、也没有多出接线
    expect(doc.logic.variables, isEmpty);
    await lbShot(tester, b8ShotDir, 'b8-stepper-canvas');

    // 应用里的“预览”读的是项目里这几个文件
    final files = await b8PreviewFiles(tester, s);
    expect(files.keys, containsAll(['index.html', 'style.css', 'logic.js']));
    if (skipWithoutDom != false) {
      // ignore: avoid_print 跳过的原因要在测试输出里看得见
      print('【跳过】预览文件的真跑：$skipWithoutDom');
      return;
    }
    final id = inst.id;
    late ({bool ok, List<String> errors, List<String> warnings, int done}) r;
    final steps = [
      {'op': 'text', 'sel': '.n-${id}__num', 'is': '1'},
      {'op': 'click', 'sel': '.n-${id}__plus'},
      {'op': 'text', 'sel': '.n-${id}__num', 'is': '2'},
      {'op': 'click', 'sel': '.n-${id}__plus'},
      {'op': 'text', 'sel': '.n-${id}__num', 'is': '3'},
      {'op': 'click', 'sel': '.n-${id}__minus'},
      {'op': 'text', 'sel': '.n-${id}__num', 'is': '2'},
    ];
    await tester.runAsync(() async => r = await runInDom('html', files, 'index.html', steps));
    expect(r.errors, isEmpty);
    expect(r.done, steps.length);
    expect(r.ok, isTrue);
  });
}
