// 第 5 期（状态与数据绑定）的三种网页导出：真编译 0 错误 0 警告，再在 Node 里用 jsdom 当浏览器真跑一遍——
// 点按钮改状态→界面跟着变、输入框 / 勾选框双向、重复、显示 / 存在条件、类名开关、样式、跨页的项目级状态。
// 环境只在开发机上有（docs/api-notes.md “开发机验证环境”）；找不到就明确跳过。不联网。
// 没覆盖的：真浏览器、真手机；样式表的效果（jsdom 不排版，这里只看元素、文字、属性和行内样式）。
@Tags(['external'])
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/lowcode/model.dart';

import 'support/bind_export_files.dart';
import 'support/bind_sample.dart';
import 'support/bind_steps.dart';
import 'support/dev_tools.dart';

const _entry = {'html': 'index.html', 'vue': 'LcApp.vue', 'react': 'LcApp.jsx'};
const _label = {'html': '普通网页', 'vue': 'Vue 3', 'react': 'React'};

/// 样例里把几处文字换成刁钻的：要原样显示出来，不能变成标签、不能把脚本截断。
const _nasty = '</script><img src=x onerror="pwn()"> {{ 7*7 }} \${x} `反引号` \\ \' " &amp;';

LcDocument _nastySample() {
  final json = bindSampleJson();
  final state = (json['state']! as List).cast<Map<String, Object?>>();
  state.firstWhere((s) => s['name'] == 'user')['initial'] = _nasty;
  final encoded = jsonEncode(json).replaceAll(jsonEncode('你好，').replaceAll('"', ''), jsonEncode('$_nasty，').replaceAll(RegExp(r'^"|"$'), ''));
  return LcDocument.parse(encoded);
}

void main() {
  if (skipWithoutDom != false) {
    // ignore: avoid_print 跳过的原因要在测试输出里看得见
    print('【跳过】状态与绑定的真编译 / 真跑：$skipWithoutDom');
  }

  for (final kind in ['html', 'vue', 'react']) {
    group('${_label[kind]}：带状态和 8 种绑定的两页样例', () {
      test('真编译：0 错误 0 警告', () async {
        final files = exportFilesOf(bindSample(), kind);
        final r = await compileExport('compile_$kind.mjs', files, _entry[kind]!);
        expect(r.errors, isEmpty, reason: r.raw);
        expect(r.warnings, isEmpty, reason: r.raw);
        expect(r.ok, isTrue);
        expect(r.html, contains('你好，小塔塔'), reason: '第一屏应该已经是初值算出来的字');
      }, skip: skipWithoutDom);

      test('真跑：改状态界面跟着变、双向、重复、条件、类名、样式、跨页的项目级状态', () async {
        final steps = bindSampleSteps(kind);
        final r = await runInDom(kind, exportFilesOf(bindSample(), kind), _entry[kind]!, steps);
        expect(r.errors, isEmpty);
        expect(r.warnings, isEmpty);
        expect(r.done, steps.length);
        expect(r.ok, isTrue);
      }, skip: skipWithoutDom);

      test('验证脚本真的在把关：期望写错一步就报出来', () async {
        final steps = [
          {'op': 'text', 'sel': '.n-tipText', 'is': '已点 0 次'},
          {'op': 'click', 'sel': '.n-add'},
          {'op': 'text', 'sel': '.n-tipText', 'is': '已点 0 次'},
          {'op': 'click', 'sel': '.n-nothing'},
        ];
        final r = await runInDom(kind, exportFilesOf(bindSample(), kind), _entry[kind]!, steps);
        expect(r.ok, isFalse);
        expect(r.errors.length, 2, reason: '${r.errors}');
        expect(r.errors.first, contains('已点 1 次'));
        expect(r.errors.last, contains('找不到'));
      }, skip: skipWithoutDom);

      test('状态初值、绑定里的文字全是刁钻字符：编译得过，页面上原样显示', () async {
        final files = exportFilesOf(_nastySample(), kind);
        final c = await compileExport('compile_$kind.mjs', files, _entry[kind]!);
        expect(c.errors, isEmpty, reason: c.raw);
        final r = await runInDom(kind, files, _entry[kind]!, [
          {'op': 'text', 'sel': '.n-hello', 'is': '$_nasty，$_nasty'.replaceAll(RegExp(r'\s+'), ' ').trim()},
          {'op': 'count', 'sel': 'img', 'is': 0},
          {'op': 'count', 'sel': '.n-rowItem', 'is': 2},
        ]);
        expect(r.errors, isEmpty);
        expect(r.ok, isTrue);
      }, skip: skipWithoutDom);
    });
  }
}
