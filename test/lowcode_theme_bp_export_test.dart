// 第 4 期·主题变量＋断点的导出：带变量和断点的两页样例（support/theme_bp_sample.dart）四种导出各是什么样，
// 纯网页 / Vue 3 / React 用官方编译器真的编译一遍（环境只在开发机上有，找不到就明确跳过），Flutter 那份检入并且真的能装进界面
// （第四轮 B1 起 Flutter 那份是“会动的”：变量集中、断点按屏宽，细的在 lowcode_dart_live_test.dart）。
import 'dart:io';

// 导出的页面用的是 Flutter 自带的那套 Material（别人的工程里没有我们的 material_ui）：这里也得用它来装。
// ignore: deprecated_member_use
import 'package:flutter/material.dart' as m;
import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/lowcode/export_dart.dart';
import 'package:lopicode/lowcode/export_html.dart';
import 'package:lopicode/lowcode/export_pages.dart';
import 'package:lopicode/lowcode/export_react.dart';
import 'package:lopicode/lowcode/export_vue.dart';

import 'generated/theme_bp_page.dart';
import 'support/dev_tools.dart';
import 'support/theme_bp_sample.dart';

void main() {
  group('纯网页', () {
    test('每页的 css：:root 里是变量，规则里写 var(--名)，断点是放在最后的媒体查询', () {
      final pages = exportHtmlPages(themeBpSample());
      expect(pages.length, 2);
      for (final p in pages) {
        expect(p.files.css, contains(':root {'), reason: '${p.htmlName}：每个页面的 css 都带变量');
        expect(p.files.css, contains('--color-primary: #058654;'));
      }
      final css = pages[0].files.css;
      expect(css, contains('var(--color-primary)'));
      expect(css, contains('var(--font-lg)'));
      final tablet = css.indexOf('@media (min-width: 768px)'), desktop = css.indexOf('@media (min-width: 1024px)');
      expect(tablet, greaterThan(css.indexOf('var(--font-lg)')));
      expect(desktop, greaterThan(tablet), reason: '桌面的在平板后面：后写的盖前面的');
      expect(css.substring(tablet), contains('font-size: var(--font-xl);'));
      expect(css.substring(tablet, desktop), contains('flex-direction: row;'));
      expect(css.substring(desktop), contains('gap: 24px;'));
      expect(pages[1].files.css, isNot(contains('@media')), reason: '第二页没用断点');
    });

    test('真编译：两页的 css / js 语法 0 错 0 警告，网页里引用的文件都在', () async {
      final files = <String, String>{};
      for (final p in exportHtmlPages(themeBpSample())) {
        files[p.htmlName] = p.files.html;
        files[p.cssName] = p.files.css;
        files[p.jsName] = p.files.js;
      }
      final r = await compileExport('compile_html.mjs', files, 'index.html');
      expect(r.errors, isEmpty, reason: r.raw);
      expect(r.warnings, isEmpty, reason: r.raw);
      expect(r.html, contains('欢迎来到小站'));
    }, skip: skipWithoutWebdev);

    test('编译器真的在把关：写坏的 css 会报', () async {
      final r = await compileExport('compile_html.mjs', {
        'index.html': '<!doctype html><link rel="stylesheet" href="style.css">',
        'style.css': '@media (min-width: 768px) { .a { color: red; }',
      }, 'index.html');
      expect([...r.errors, ...r.warnings], isNotEmpty);
    }, skip: skipWithoutWebdev);
  });

  for (final kind in ['vue', 'react']) {
    group(kind == 'vue' ? 'Vue 3' : 'React', () {
      test('变量只写一份（${kind == 'vue' ? '外壳里不带 scoped 的那段样式' : 'lc-base.css'}），断点是媒体查询', () {
        final e = kind == 'vue' ? exportVue(themeBpSample()) : exportReact(themeBpSample());
        expect(e.files.every((f) => f.formatProblem == null), isTrue, reason: [for (final f in e.files) '${f.path}: ${f.formatProblem}'].join('\n'));
        final withRoot = [
          for (final f in e.files)
            if (f.content.contains('--color-primary: #058654;')) f.path,
        ];
        expect(withRoot, [kind == 'vue' ? 'LcApp.vue' : 'lc-base.css']);
        final home = e.files.where((f) => f.path == (kind == 'vue' ? 'Home.vue' : 'Home.css')).single.content;
        expect(home, contains('@media (min-width: 768px)'));
        expect(home, contains('@media (min-width: 1024px)'));
        expect(home, contains('var(--color-primary)'));
        if (kind == 'vue') {
          final shell = e.file('LcApp.vue')!.content;
          expect(RegExp(r'<style>\s*/\* 主题变量').hasMatch(shell), isTrue, reason: ':root 不能放在 scoped 的样式里（放了不生效）');
        }
      });

      test('真编译：0 错误 0 警告，服务端渲染得出首页', () async {
        final e = kind == 'vue' ? exportVue(themeBpSample()) : exportReact(themeBpSample());
        final entry = kind == 'vue' ? 'LcApp.vue' : 'LcApp.jsx';
        final r = await compileExport(kind == 'vue' ? 'compile_vue.mjs' : 'compile_react.mjs', {for (final f in e.files) f.path: f.content}, entry);
        expect(r.errors, isEmpty, reason: r.raw);
        expect(r.warnings, isEmpty, reason: r.raw);
        expect(r.html, contains('欢迎来到小站'));
        expect(r.html, contains('新品'), reason: '自定义组件“标签”也渲染了');
        expect(r.html, isNot(contains('关于我们')));
      }, skip: skipWithoutWebdev);
    });
  }

  group('Flutter', () {
    test('检入的样本和导出器当前的输出一致；变量集中在 LcVars 里，文件头说明了变量和断点怎么用', () {
      final code = exportDart(themeBpSample(), className: 'ThemeBpHomePage');
      expect(File('test/generated/theme_bp_page.dart').readAsStringSync(), code, reason: '导出器改了：运行 dart run tool/gen_sample_export.dart 重新生成');
      expect(code, isNot(contains('var(--')));
      expect(code, contains('主题变量'));
      expect(code, contains('断点'));
      expect(code, contains('static const Color colorPrimary = Color(0xFF058654);'), reason: '变量 color-primary 在变量表里');
      expect(code, contains('backgroundColor: LcVars.colorPrimary'), reason: '按钮底色指到变量上，不再写死');
    });

    testWidgets('真的装得进界面（手机宽度）：没有异常、没有溢出', (tester) async {
      tester.view.physicalSize = const m.Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const m.MaterialApp(home: ThemeBpHomePage()));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('欢迎来到小站'), findsOneWidget);
      expect(find.text('新品'), findsOneWidget);
      final title = tester.widget<m.Text>(find.text('欢迎来到小站'));
      expect(title.style?.fontSize, 20, reason: '字号变量 font-lg 的值；平板的 30 在 lowcode_dart_live_test.dart 里按 800 宽验');
    });
  });

  test('没用变量、没用断点的文档：css 里没有 :root、没有 @media', () {
    final d = themeBpSample();
    d.more.remove('theme');
    final css = exportHtml(d).css;
    expect(css, isNot(contains(':root')), reason: '变量表空了：var() 留在规则里，但不写 :root');
  });
}
