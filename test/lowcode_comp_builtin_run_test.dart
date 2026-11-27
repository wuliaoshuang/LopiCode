// 第四轮 B5：内置组件库里六个 P1 组件（图标按钮、链接、网格、滚动区、步进器、表单项）的四种导出。
// 前半（不依赖外部环境）：四种都导得出、Vue 3 / React 各出组件文件、纯网页 / Flutter 摊开。
// 后半（开发机才有环境，找不到明确跳过）：三种网页导出用官方编译器真编译 0 错 0 警告；Node + jsdom 真跑——
// 步进器点加减数字变、到边上禁用；图标按钮点了页面状态变；链接点了换页（Vue 3 / React）。
// 没覆盖的：真浏览器、真手机、样式表的效果（jsdom 不排版，网格的列数、滚动区能不能滚只看了样式表里有那几句）。
@Tags(['external'])
library;

import 'package:flutter_test/flutter_test.dart';

import 'support/bind_export_files.dart';
import 'support/builtin_p1_sample.dart';
import 'support/comp_steps.dart';
import 'support/dev_tools.dart';

const _entry = {'html': 'index.html', 'vue': 'LcApp.vue', 'react': 'LcApp.jsx'};
const _label = {'html': '普通网页', 'vue': 'Vue 3', 'react': 'React'};

void main() {
  if (skipWithoutDom != false) {
    // ignore: avoid_print 跳过的原因要在测试输出里看得见
    print('【跳过】内置 P1 组件的真编译 / 真跑：$skipWithoutDom');
  }

  group('内置 P1 组件的导出', () {
    test('Vue 3 / React：六个各出一个组件文件；纯网页 / Flutter 摊开进页面', () {
      final all = allExportFiles(builtinP1Doc());
      expect(all.keys.where((k) => k.startsWith('vue/components/') && k.endsWith('.vue')), hasLength(6), reason: '${all.keys}');
      expect(all.keys.where((k) => k.startsWith('react/components/') && k.endsWith('.jsx')), hasLength(6));
      expect(all.keys.where((k) => (k.startsWith('html/') || k.startsWith('flutter/')) && k.contains('components/')), isEmpty);
      final html = all['html/index.html']!;
      for (final cls in ['n-st__plus', 'n-st__minus', 'n-lk', 'n-ib', 'n-gr', 'n-sc', 'n-fi__label']) {
        expect(html, contains(cls), reason: cls);
      }
      final css = all['html/style.css']!;
      expect(css, contains('grid-template-columns: repeat(3, 1fr)'), reason: '网格选了“3 列”');
      expect(css, contains('overflow-y: auto'), reason: '滚动区');
      expect(css, contains('text-decoration-line: underline'), reason: '链接的下划线');
      final dart = all['flutter/page.dart']!;
      expect(dart, contains('class '));
      expect(dart, contains('去更多'));
      expect(dart, contains('姓名'));
    });

    for (final kind in ['html', 'vue', 'react']) {
      final plain = builtinP1Steps(jump: kind != 'html');
      final steps = kind == 'html' ? plain : compFileSteps(plain, kBuiltinP1Defs);
      test('${_label[kind]}：真编译 0 错误 0 警告', () async {
        final r = await compileExport('compile_$kind.mjs', exportFilesOf(builtinP1Doc(), kind), _entry[kind]!);
        expect(r.errors, isEmpty, reason: r.raw);
        expect(r.warnings, isEmpty, reason: r.raw);
        expect(r.ok, isTrue);
      }, skip: skipWithoutDom);

      test('${_label[kind]}：真跑——步进器加减、图标按钮、表单项${kind == 'html' ? '' : '、链接换页'}', () async {
        final r = await runInDom(kind, exportFilesOf(builtinP1Doc(), kind), _entry[kind]!, steps);
        expect(r.errors, isEmpty);
        expect(r.warnings, isEmpty);
        expect(r.done, steps.length);
        expect(r.ok, isTrue);
      }, skip: skipWithoutDom);
    }
  });
}
