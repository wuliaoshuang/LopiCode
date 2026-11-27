// 第四轮 B3：Vue 3 / React 导出里，各页共用的底部导航抽成一个公共部件文件，各页引用它、把“这一页亮第几项”传进去。
// 核对：文件清单和各页写法；没用共用的项目导出里没有这个文件；撞名时换名字；
// 官方编译器真编译 0 错误 0 警告；Node + jsdom 真跑——点导航换页以后亮着的那一项跟着变。
// 真编译 / 真跑的环境只在开发机上有，找不到就明确跳过。不联网。没覆盖的：真浏览器、真手机、样式表的效果（jsdom 不排版）。
@Tags(['external'])
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/lowcode/export_react.dart';
import 'package:lopicode/lowcode/export_vue.dart';
import 'package:lopicode/lowcode/model.dart';
import 'package:lopicode/lowcode/nav_shared.dart';

import 'support/bind_export_files.dart';
import 'support/dev_tools.dart';
import 'support/pages_sample.dart';

const _entry = {'vue': 'LcApp.vue', 'react': 'LcApp.jsx'};
const _ext = {'vue': 'vue', 'react': 'jsx'};
const _label = {'vue': 'Vue 3', 'react': 'React'};

LcDocument _shared([void Function(Map<String, dynamic> json)? change]) {
  final json = jsonDecode(jsonEncode(pagesSampleJson())) as Map<String, dynamic>;
  change?.call(json);
  final doc = LcDocument.fromJson(json);
  lcShareNav(doc, 'p1');
  // 存一遍再读：和她在手机上“改成共用 → 导出”走的是同一条路。
  return LcDocument.parse(doc.encode());
}

Map<String, String> _files(LcDocument doc, String kind) => {for (final f in (kind == 'vue' ? exportVue(doc) : exportReact(doc)).files) f.path: f.content};

void main() {
  if (skipWithoutDom != false) {
    // ignore: avoid_print 跳过的原因要在测试输出里看得见
    print('【跳过】共用导航公共部件的真编译 / 真跑：$skipWithoutDom');
  }

  for (final kind in ['vue', 'react']) {
    final ext = _ext[kind]!;
    group('${_label[kind]}：共用的底部导航', () {
      test('多出一个公共部件文件；三页都引用它、各传各的“亮第几项”，页面里不再各写一遍', () {
        final files = _files(_shared(), kind);
        final part = files['components/LcBottomNav.$ext'];
        expect(part, isNotNull, reason: '${files.keys}');
        expect('<nav'.allMatches(part!).length, 1);
        expect('lc-nav-item'.allMatches(part).length, greaterThanOrEqualTo(3));
        for (final (i, page) in ['Home', 'LcPage', 'Me'].indexed) {
          final src = files['$page.$ext']!;
          expect(src, contains('import LcBottomNav from "./components/LcBottomNav.$ext";'));
          expect(src, isNot(contains('<nav')), reason: '$page 里还写着一份导航');
          expect('<LcBottomNav '.allMatches(src).length, 1);
          expect(src, contains(kind == 'vue' ? ':current="$i"' : 'current={$i}'));
        }
      });

      test('没用共用的项目：没有这个文件，各页照旧自己写一份', () {
        final files = _files(pagesSample(), kind);
        expect(files.keys.where((k) => k.contains('LcBottomNav')), isEmpty);
        expect(files['Home.$ext'], contains('<nav'));
      });

      test('项目里已经有叫 LcBottomNav 的自定义组件：公共部件换个名字，两样都在', () {
        final files = _files(_shared((json) => ((json['components'] as List).first as Map)['name'] = 'LcBottomNav'), kind);
        expect(files.keys, contains('components/LcBottomNav.$ext'));
        expect(files.keys, contains('components/LcBottomNav2.$ext'));
        expect(files['components/LcBottomNav2.$ext'], contains('<nav'));
        expect(files['Me.$ext'], contains('<LcBottomNav2 '));
      });

      test('真编译：0 错误 0 警告，首页亮的是第一项', () async {
        final r = await compileExport('compile_$kind.mjs', _files(_shared(), kind), _entry[kind]!);
        expect(r.errors, isEmpty, reason: r.raw);
        expect(r.warnings, isEmpty, reason: r.raw);
        expect(r.ok, isTrue, reason: r.raw);
        expect('aria-current="page"'.allMatches(r.html).length, 1, reason: r.html);
      }, skip: skipWithoutDom);

      test('真跑：点导航换页，亮着的那一项跟着变；直接改地址也一样', () async {
        const on = '.lc-nav-item[aria-current="page"]';
        final r = await runInDom(kind, exportFilesOf(_shared(), kind), _entry[kind]!, [
          {'op': 'count', 'sel': on, 'is': 1},
          {'op': 'text', 'sel': on, 'is': '首页'},
          {'op': 'click', 'sel': '.lc-nav-item', 'at': 1},
          {'op': 'hash', 'is': '#/p2'},
          {'op': 'count', 'sel': on, 'is': 1},
          {'op': 'text', 'sel': on, 'is': '商品'},
          {'op': 'page', 'hash': '#/p3'},
          {'op': 'count', 'sel': on, 'is': 1},
          {'op': 'text', 'sel': on, 'is': '我的'},
          // 点当前页那一项：地址不变，亮的也不变。
          {'op': 'click', 'sel': '.lc-nav-item', 'at': 2},
          {'op': 'hash', 'is': '#/p3'},
          {'op': 'text', 'sel': on, 'is': '我的'},
          {'op': 'click', 'sel': '.lc-nav-item', 'at': 0},
          {'op': 'text', 'sel': on, 'is': '首页'},
        ]);
        expect(r.errors, isEmpty);
        expect(r.warnings, isEmpty);
        expect(r.ok, isTrue);
        expect(r.done, 14);
      }, skip: skipWithoutDom);
    });
  }
}
