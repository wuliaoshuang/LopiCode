// 第四轮 B2：三种形状的组件（商品卡片、登录表单、标签筛选条）用在页面里以后，三种网页导出
// 真编译 0 错误 0 警告，再在 Node 里用 jsdom 当浏览器真跑：点组件里的按钮事件传到页面、状态变了界面跟着变。
// 环境只在开发机上有；找不到就明确跳过。不联网。没覆盖的：真浏览器、真手机、样式表的效果。
@Tags(['external'])
library;

import 'package:flutter_test/flutter_test.dart';

import 'support/bind_export_files.dart';
import 'support/comp_samples.dart';
import 'support/comp_steps.dart';
import 'support/dev_tools.dart';

const _entry = {'html': 'index.html', 'vue': 'Shop.vue', 'react': 'Shop.jsx'};
const _label = {'html': '普通网页', 'vue': 'Vue 3', 'react': 'React'};

void main() {
  if (skipWithoutDom != false) {
    // ignore: avoid_print 跳过的原因要在测试输出里看得见
    print('【跳过】组件的真编译 / 真跑：$skipWithoutDom');
  }
  final shapes = <String, (Map<String, Object?> Function(), CompSteps Function(), String)>{
    '商品卡片': (productCardDef, productCardSteps, '加入购物车'),
    '登录表单': (loginFormDef, loginFormSteps, '请登录'),
    '标签筛选条': (tagBarDef, tagBarSteps, '清空'),
  };
  for (final kind in ['html', 'vue', 'react']) {
    for (final shape in shapes.entries) {
      final (def, steps, word) = shape.value;
      test('${_label[kind]}·${shape.key}：真编译 0 错误 0 警告', () async {
        final files = exportFilesOf(compUserDoc([def()]), kind);
        final r = await compileExport('compile_$kind.mjs', files, _entry[kind]!);
        expect(r.errors, isEmpty, reason: r.raw);
        expect(r.warnings, isEmpty, reason: r.raw);
        expect(r.ok, isTrue);
        expect(r.html, contains(word));
      }, skip: skipWithoutDom);

      test('${_label[kind]}·${shape.key}：真跑，一步不差', () async {
        final list = steps();
        final r = await runInDom(kind, exportFilesOf(compUserDoc([def()]), kind), _entry[kind]!, list);
        expect(r.errors, isEmpty);
        expect(r.warnings, isEmpty);
        expect(r.done, list.length);
        expect(r.ok, isTrue);
      }, skip: skipWithoutDom);
    }

    test('${_label[kind]}·三个组件放在同一页：真编译、三串步骤接着跑', () async {
      final files = exportFilesOf(compUserDoc([productCardDef(), loginFormDef(), tagBarDef()]), kind);
      final c = await compileExport('compile_$kind.mjs', files, _entry[kind]!);
      expect(c.errors, isEmpty, reason: c.raw);
      expect(c.warnings, isEmpty, reason: c.raw);
      final list = [...productCardSteps(), ...loginFormSteps(), ...tagBarSteps()];
      final r = await runInDom(kind, files, _entry[kind]!, list);
      expect(r.errors, isEmpty);
      expect(r.done, list.length);
    }, skip: skipWithoutDom);
  }
}
