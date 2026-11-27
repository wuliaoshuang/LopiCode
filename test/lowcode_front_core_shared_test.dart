// 导出体积（积木第 5 版·第四轮 A3b 第 6 件）：多页面的 Vue / React 导出里，走新路的页面有两页以上时，
// 语言核心的浏览器小库和页面宿主抽成一个共用文件 lcCore.js，各页从它引；只有一页走新路、或者只有一页的项目，和以前一样每页自带。
// 纯网页这一版没有抽（每页的 logic.js 仍各带一份），这里把现状钉住。
// 抽完以后真编译、真跑由 lowcode_front_run_test 的“两页”样例管（Vue / React 各三组步骤，React 另加 StrictMode）。
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/backend/front_doc.dart';
import 'package:lopicode/lowcode/export_pages.dart';
import 'package:lopicode/lowcode/export_react.dart';
import 'package:lopicode/lowcode/export_vue.dart';
import 'package:lopicode/lowcode/logic_core_js.dart';
import 'package:lopicode/lowcode/model.dart';

import 'support/lib_switches.dart';
import 'support/page_front_samples.dart';

const String _rt = 'function lcRuntime(win)';
const String _host = 'function lcPageHost(lc, t)';

Map<String, String> _files(String kind, LcDocument doc) => {for (final f in (kind == 'vue' ? exportVue(doc) : exportReact(doc)).files) f.path: f.content};

/// 两页的样例，把第二页的逻辑拿掉：只剩一页走新路。
LcDocument _onlyOne() {
  final j = jsonDecode(jsonEncode(frontSampleList().toJson())) as Map<String, dynamic>;
  ((j['pages'] as List)[0] as Map<String, dynamic>).remove('logic'); // 第一页写在最外层，'pages' 里是其余的页
  final doc = LcDocument.parse(jsonEncode(j));
  expect(doc.pages.length, 2);
  expect(lcFrontOf(doc.pages[0].logic), isNotNull);
  expect(lcFrontOf(doc.pages[1].logic), isNull);
  return doc;
}

void main() {
  libSwitchesOn();

  for (final kind in ['vue', 'react']) {
    final ext = kind == 'vue' ? '.vue' : '.jsx';
    test('$kind：两页都走新路 → 多一个 lcCore.js，各页从它引，自己不再带小库和页面宿主', () {
      final files = _files(kind, frontSampleList());
      expect(files.keys, contains(kLcCoreSharedFile));
      final core = files[kLcCoreSharedFile]!;
      expect(_rt.allMatches(core).length, 1);
      expect(_host.allMatches(core).length, 1);
      expect(core, contains('export { lcRuntime, lcPageHost };'));
      final pages = [
        for (final e in files.entries)
          if (e.key.endsWith(ext) && !e.key.contains('/') && e.value.contains('function lcProgram(lc, lcHost)')) e,
      ];
      expect(pages.length, 2, reason: '两页都有自己的程序');
      for (final p in pages) {
        expect(p.value, isNot(contains(_rt)), reason: p.key);
        expect(p.value, isNot(contains(_host)), reason: p.key);
        expect(RegExp('import \\{ lcRuntime, lcPageHost \\} from [\'"]\\./lcCore\\.js[\'"];').allMatches(p.value).length, 1, reason: p.key);
      }
      // 省了多少：以前每页一份，现在一共一份。
      final block = core.length;
      final total = files.values.fold<int>(0, (a, b) => a + b.length);
      // ignore: avoid_print 体积数字要在测试输出里看得见，汇报里用
      print('【体积】$kind 两页：共用文件 $block 个字；现在一共 $total 个字，以前约 ${total + block} 个字');
      expect(block, greaterThan(4000));
    });

    test('$kind：两页里只有一页走新路 → 不抽，没有 lcCore.js，那一页自带', () {
      final files = _files(kind, _onlyOne());
      expect(files.keys, isNot(contains(kLcCoreSharedFile)));
      final all = files.values.join('\n');
      expect(_rt.allMatches(all).length, 1);
      expect(all, isNot(contains('lcCore.js')));
    });

    test('$kind：只有一页的项目 → 不抽', () {
      final files = _files(kind, frontSampleCore());
      expect(files.keys, isNot(contains(kLcCoreSharedFile)));
      expect(_rt.allMatches(files.values.join('\n')).length, 1);
    });
  }

  test('纯网页：两页都走新路，每页的脚本仍各带一份（这一版没有抽）', () {
    final pages = exportHtmlPages(frontSampleList());
    expect(pages.length, 2);
    for (final p in pages) {
      expect(_rt.allMatches(p.files.js).length, 1, reason: p.jsName);
      expect(p.files.html, isNot(contains('lcCore.js')));
    }
  });
}
