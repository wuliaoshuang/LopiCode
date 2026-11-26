// 低代码导出的 Vue 3 / React 工程用官方编译器真的编译一遍，再在 Node 里服务端渲染入口页面（2026-11-26 第一次真跑）。
// 另有 TypeScript：产品里还没有 TS 生成器，这里只守住“tsc 在、能编译能跑、类型错了会拦”，给以后的 TS 生成器当现成的工具。
// 环境只在开发机上有（docs/api-notes.md “开发机验证环境”）；找不到就明确跳过。不联网。
// 没覆盖的：真浏览器、点击之后的变化（服务端渲染只出第一屏）。
@Tags(['external'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/lowcode/export_react.dart';
import 'package:lopicode/lowcode/export_vue.dart';
import 'package:lopicode/lowcode/model.dart';

import 'lowcode_export_vue_test.dart' show nastyJson;
import 'support/dev_tools.dart';
import 'support/lowcode_samples.dart';
import 'support/pages_sample.dart';
import 'support/sample_doc.dart';
import 'support/slot_sample.dart';
import 'support/v3_components_sample.dart';
import 'support/v3_sample.dart';

Map<String, String> _files(LcFrameworkExport e) => {for (final f in e.files) f.path: f.content};

String _entry(LcFrameworkExport e, String ext) => e.files.firstWhere((f) => f.path.endsWith(ext)).path;

void main() {
  if (skipWithoutWebdev != false) {
    // ignore: avoid_print 跳过的原因要在测试输出里看得见
    print('【跳过】Vue / React / TypeScript 真编译：$skipWithoutWebdev');
  }

  final samples = <String, LcDocument Function()>{
    '带逻辑和自定义组件的样本': frameworkSample,
    '文字里全是刁钻字符的样本': () => docOf(nastyJson()),
    '各种组件都有的样本': sample,
    '第 3 版新属性都用上的样本': v3Sample,
    '新建页面的默认内容': () => LcDocument.starter('我的页面'),
    // 第 3 期第 2 段：11 个新组件的四个样例页
    ...v3ComponentSamples(),
    // 第 3 期第 3 段：带插槽的自定义组件
    '带插槽的商品卡片': slotCardPage,
    // 第 4 期：多页面（入口是外壳 LcApp，它把三页和共用的组件都引进来）
    '三页的多页面样例': pagesSample,
  };

  for (final kind in ['vue', 'react']) {
    group(kind == 'vue' ? 'Vue 3 导出真编译' : 'React 导出真编译', () {
      for (final s in samples.entries) {
        test('${s.key}：编译 0 错误 0 警告，服务端渲染得出网页', () async {
          final e = kind == 'vue' ? exportVue(s.value()) : exportReact(s.value());
          final r = await compileExport(kind == 'vue' ? 'compile_vue.mjs' : 'compile_react.mjs', _files(e), _entry(e, kind == 'vue' ? '.vue' : '.jsx'));
          expect(r.errors, isEmpty, reason: r.raw);
          expect(r.warnings, isEmpty, reason: r.raw);
          expect(r.ok, isTrue);
          expect(r.html, contains('<'), reason: '渲染出来是空的');
          expect(r.html, isNot(contains('<script')), reason: '样本里的文字不该变成真的标签');
          expect(r.html, isNot(contains('<img src=x')), reason: '样本里的文字不该变成真的标签');
          expect(r.html, isNot(contains('" onclick="pwn()')), reason: '样本里的文字不该变成真的属性');
        }, skip: skipWithoutWebdev);
      }

      test('带逻辑的样本：页面上的字、自定义组件里的字都渲染出来了', () async {
        final e = kind == 'vue' ? exportVue(frameworkSample()) : exportReact(frameworkSample());
        final r = await compileExport(kind == 'vue' ? 'compile_vue.mjs' : 'compile_react.mjs', _files(e), _entry(e, kind == 'vue' ? '.vue' : '.jsx'));
        expect(r.ok, isTrue, reason: r.raw);
        expect(e.files.length, greaterThan(1), reason: '样本带自定义组件，应该不止一个文件');
        expect(RegExp(r'>[^<>]*[\u4e00-\u9fff][^<>]*<').hasMatch(r.html), isTrue, reason: '网页里应该有中文文字：${r.html}');
      }, skip: skipWithoutWebdev);

      test('带插槽的商品卡片：填进去的内容和默认内容各在该在的位置', () async {
        final e = kind == 'vue' ? exportVue(slotCardPage()) : exportReact(slotCardPage());
        final r = await compileExport(kind == 'vue' ? 'compile_vue.mjs' : 'compile_react.mjs', _files(e), _entry(e, kind == 'vue' ? '.vue' : '.jsx'));
        expect(r.ok, isTrue, reason: r.raw);
        final order = ['今日推荐', '草莓蛋糕', '新鲜草莓，当天现做', '¥ 68', '立即购买', '收藏', '商品名', '暂无介绍', '加入购物车'];
        var at = -1;
        for (final t in order) {
          final i = r.html.indexOf(t, at + 1);
          expect(i, greaterThan(at), reason: '“$t”不在该在的位置：${r.html}');
          at = i;
        }
        expect('暂无介绍'.allMatches(r.html).length, 1, reason: '填了内容的那个实例里不该再有默认内容：${r.html}');
        expect('加入购物车'.allMatches(r.html).length, 1, reason: r.html);
        expect('草莓蛋糕'.allMatches(r.html).length, 1, reason: r.html);
      }, skip: skipWithoutWebdev);

      test('三页的多页面样例：入口是外壳；服务端渲染出来的是首页，别的页的字不在', () async {
        final e = kind == 'vue' ? exportVue(pagesSample()) : exportReact(pagesSample());
        expect(_entry(e, kind == 'vue' ? '.vue' : '.jsx'), kind == 'vue' ? 'LcApp.vue' : 'LcApp.jsx');
        final r = await compileExport(kind == 'vue' ? 'compile_vue.mjs' : 'compile_react.mjs', _files(e), _entry(e, kind == 'vue' ? '.vue' : '.jsx'));
        expect(r.ok, isTrue, reason: r.raw);
        for (final t in ['欢迎', '今日推荐', '草莓蛋糕', '去看商品', '我的资料']) {
          expect(r.html, contains(t), reason: '首页的“$t”没渲染出来：${r.html}');
        }
        expect(r.html, isNot(contains('回首页')), reason: '第二页不该出现：${r.html}');
        expect(r.html, isNot(contains('昵称：小橘')), reason: '第三页不该出现：${r.html}');
      }, skip: skipWithoutWebdev);

      test('编译器真的在把关：故意写坏的文件会报错', () async {
        final bad = kind == 'vue'
            ? {'Bad.vue': '<template><div><span></div></template>\n<script setup>\nconst a = ;\n</script>\n'}
            : {'Bad.jsx': 'export default function Bad() { return <div><span></div>; }\n'};
        final r = await compileExport(kind == 'vue' ? 'compile_vue.mjs' : 'compile_react.mjs', bad, bad.keys.first);
        expect(r.ok, isFalse);
        expect(r.errors, isNotEmpty);
      }, skip: skipWithoutWebdev);
    });
  }

  group('TypeScript（只是工具在不在；产品里还没有 TS 生成器）', () {
    final Object skip = skipWithoutWebdev != false
        ? skipWithoutWebdev
        : webdevHas('typescript')
        ? false
        : '开发机验证环境里没有 typescript，跳过';

    test('最小样本：严格模式编译通过，跑出来的结果对', () async {
      final r = await compileAndRunTs(File('tool/verify/ts/sample.ts').readAsStringSync());
      expect(r.code, 0, reason: r.messages);
      expect(r.messages.trim(), isEmpty);
      expect(r.stdout, '[{"id":1,"title":"买菜","done":false},{"id":2,"title":"写作业","done":false}] 2\n');
    }, skip: skip);

    test('类型写错的样本：编译器拦下来，说得出是哪一行', () async {
      final r = await compileAndRunTs(File('tool/verify/ts/bad.ts').readAsStringSync());
      expect(r.code, isNot(0));
      expect(r.messages, allOf(contains('TS2322'), contains('main.ts(1,')));
      expect(r.stdout, isEmpty, reason: '编译不过就不该跑');
    }, skip: skip);
  });
}
