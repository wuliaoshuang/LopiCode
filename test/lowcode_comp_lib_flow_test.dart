// 第四轮 B2 的验收：三种形状的组件各走一遍“项目甲做 → 存进库 → 导出文件 → 项目乙导入（先看预览）→ 用在页面上”，
// 然后三种网页导出真编译 0 错误 0 警告，在 Node＋jsdom 里真跑（事件传到页面、状态变了界面跟着变）。
// 环境只在开发机上有；找不到就明确跳过。不联网。没覆盖的：真浏览器、真手机。
@Tags(['external'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/lowcode/comp_lib.dart';
import 'package:lopicode/lowcode/comp_lib_sheet.dart';

import 'support/bind_export_files.dart';
import 'support/comp_lib_flow.dart';
import 'support/comp_samples.dart';
import 'support/comp_steps.dart';
import 'support/dev_tools.dart';

const _entry = {'html': 'index.html', 'vue': 'Shop.vue', 'react': 'Shop.jsx'};
const _label = {'html': '普通网页', 'vue': 'Vue 3', 'react': 'React'};

void main() {
  if (skipWithoutDom != false) {
    // ignore: avoid_print 跳过的原因要在测试输出里看得见
    print('【跳过】组件库全流程的真编译 / 真跑：$skipWithoutDom');
  }
  late Directory tmp;
  setUp(() async => tmp = await Directory.systemTemp.createTemp('complibflow'));
  tearDown(() => tmp.delete(recursive: true));

  final shapes = <String, (Map<String, Object?> Function(), CompSteps Function(), String)>{
    '商品卡片': (productCardDef, productCardSteps, '加入购物车'),
    '登录表单': (loginFormDef, loginFormSteps, '请登录'),
    '标签筛选条': (tagBarDef, tagBarSteps, '清空'),
  };
  for (final shape in shapes.entries) {
    final (def, steps, word) = shape.value;
    test('${shape.key}：甲 → 库 → 文件 → 乙，预览说得清，装进去以后是库里的组件', () async {
      final flow = await compLibFullFlow(tmp, [def()]);
      final view = compLibImportView(flow.previewed);
      expect(view.canImport, isTrue);
      expect(view.name, '商城组件');
      expect(view.id, 'shuang/shop');
      expect(view.version, '1.0.0');
      expect(view.author, '霜霜');
      expect(view.items.single, startsWith(shape.key));
      expect(flow.packRel, endsWith('.lopilib'));
      expect(flow.notes, isEmpty);
      expect(flow.doc.components.every((c) => compLibOf(c)?.id == 'shuang/shop'), isTrue);
    });
    for (final kind in ['html', 'vue', 'react']) {
      test('${shape.key}·${_label[kind]}：从库里导入以后，真编译 0 错误 0 警告，真跑一步不差', () async {
        final flow = await compLibFullFlow(tmp, [def()]);
        final files = exportFilesOf(flow.doc, kind);
        final r = await compileExport('compile_$kind.mjs', files, _entry[kind]!);
        expect(r.errors, isEmpty, reason: r.raw);
        expect(r.warnings, isEmpty, reason: r.raw);
        expect(r.ok, isTrue);
        expect(r.html, contains(word));
        final list = steps();
        final run = await runInDom(kind, files, _entry[kind]!, list);
        expect(run.errors, isEmpty);
        expect(run.warnings, isEmpty);
        expect(run.done, list.length);
        expect(run.ok, isTrue);
      }, skip: skipWithoutDom);
    }
  }
}
