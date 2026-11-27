// 内置“页面”库（积木第 5 版·前端 1）：库本身读得进来、没有问题；旧积木都有对着的库积木；
// 一页旧积木的逻辑能翻成语言核心的程序、过类型检查、交给浏览器目标生成。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/lang/gen2_browser.dart';
import 'package:lopicode/lang/lib_model.dart';
import 'package:lopicode/lowcode/lib_page.dart';
import 'package:lopicode/lowcode/logic_to_core.dart';

import 'support/lowcode_samples.dart';
import 'support/page_core_samples.dart';

void main() {
  test('“页面”库读得进来，没有问题，只给前端用', () {
    final lib = lcPageLibrary();
    expect(lib.problems, isEmpty);
    expect(lib.id, kLcPageLibId);
    expect(lib.side, LibSide.frontend);
    expect(lib.builtin, isTrue);
  });

  test('旧积木个个有对着的库积木', () {
    final lib = lcPageLibrary();
    for (final fn in ['setVar', 'var', 'setProp', 'prop', 'event', 'wait', 'alert', 'navigate', 'log', 'fetch', 'lcNum', 'lcText', 'lcBool', 'lcEq', 'bin']) {
      expect(lib.legacy(fn), isNotNull, reason: fn);
    }
  });

  test('样本页的逻辑翻成语言核心的程序，能生成浏览器里的页面程序', () {
    final doc = frameworkSample();
    final built = lcLogicToCore(doc, pageUrl: (p) => '${p.id}.html');
    expect(built.problems, isEmpty);
    expect(built.skipped, isEmpty);
    final js = gen2BrowserProgram(built.program!);
    if (Platform.environment['LOPI_DUMP'] == '1') File('.tmp/page-core.js').writeAsStringSync(js);
    expect(js, contains('function lcProgram(lc, lcHost)'));
    expect(built.states, isNotEmpty);
    expect(built.props, isNotEmpty);
  });

  test('用了库积木的页面（函数＋闭包、类、试着做；列表和记录状态）：库没有问题，翻得出来，生成得了', () {
    expect(pageKit().problems, isEmpty);
    final doc = coreSampleLib();
    final built = lcLogicToCore(doc, pageUrl: (p) => '${p.id}.html');
    expect(built.problems, isEmpty);
    expect(built.skipped, isEmpty);
    expect(built.libs.map((l) => l.id), [kLcPageLibId, 'test/page-kit']);
    expect(gen2BrowserProgram(built.program!), contains('function lcProgram(lc, lcHost)'));
    expect(built.states, {'n', 'items', 'who'});
  });
}
