// 页面逻辑新路（页面逻辑 → 语言核心 → 浏览器目标）的验收（积木第 5 版·前端 1·A2）：
// 三组不同形状的样例，在纯网页 / Vue 3 / React 三种产物里用官方编译器真编译 0 错 0 警告，再在 Node＋jsdom 里真跑同一串步骤。
// - 样例甲（旧积木全集）：老路、新路各跑一遍，同一串步骤都过＝新路在旧积木上和老路行为一致。
// - 样例乙（库积木：函数＋闭包、类、试着做；列表 / 记录状态）：只有新路能跑。
// - 样例丙（状态与绑定两页样例）：强制走新路，原来那串步骤照过＝“改状态→界面跟着变”“项目级状态怎么通知”在新路上没变。
// 环境只在开发机上有；找不到就明确跳过。不联网（网络是假的）。没覆盖的：真浏览器、真手机。
@Tags(['external'])
@Timeout(Duration(minutes: 20))
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/lowcode/logic_libs.dart';
import 'package:lopicode/lowcode/model.dart';

import 'support/bind_export_files.dart';
import 'support/bind_sample.dart';
import 'support/bind_steps.dart';
import 'support/dev_tools.dart';
import 'support/page_core_samples.dart';

const _label = {'html': '普通网页', 'vue': 'Vue 3', 'react': 'React'};

String _entry(String kind, Map<String, String> files) => switch (kind) {
  'html' => 'index.html',
  'vue' => files.containsKey('LcApp.vue') ? 'LcApp.vue' : files.keys.firstWhere((k) => k.endsWith('.vue') && !k.contains('/')),
  _ => files.containsKey('LcApp.jsx') ? 'LcApp.jsx' : files.keys.firstWhere((k) => k.endsWith('.jsx') && !k.contains('/')),
};

Future<void> _check(String kind, LcDocument Function() make, List<Map<String, Object?>> steps, {required bool core}) async {
  lcForceCorePath = core;
  final Map<String, String> files;
  try {
    files = exportFilesOf(make(), kind);
  } finally {
    lcForceCorePath = false;
  }
  final all = files.values.join('\n');
  expect(all.contains('function lcProgram(lc, lcHost)'), core, reason: core ? '应该走新路' : '应该走老路');
  expect(all, isNot(contains('这一页的逻辑没有导出')));
  final entry = _entry(kind, files);
  final c = await compileExport('compile_$kind.mjs', files, entry);
  expect(c.errors, isEmpty, reason: c.raw);
  expect(c.warnings, isEmpty, reason: c.raw);
  final r = await runInDom(kind, files, entry, steps);
  expect(r.errors, isEmpty);
  expect(r.warnings, isEmpty);
  expect(r.done, steps.length);
  expect(r.ok, isTrue);
}

void main() {
  if (skipWithoutDom != false) {
    // ignore: avoid_print 跳过的原因要在测试输出里看得见
    print('【跳过】页面逻辑新路的真编译 / 真跑：$skipWithoutDom');
  }
  tearDown(() => lcForceCorePath = false);

  for (final kind in ['html', 'vue', 'react']) {
    group('${_label[kind]}', () {
      test('样例甲（旧积木全集）走老路：这串步骤是对的', () => _check(kind, coreSampleOld, coreStepsOld(), core: false), skip: skipWithoutDom);
      test('样例甲（旧积木全集）强制走新路：同一串步骤照过', () => _check(kind, coreSampleOld, coreStepsOld(), core: true), skip: skipWithoutDom);
      test('样例乙（库积木：函数＋闭包、类、试着做；列表和记录状态）', () => _check(kind, coreSampleLib, coreStepsLib(), core: true), skip: skipWithoutDom);
      test('样例丙（状态与绑定两页样例）强制走新路：原来那串步骤照过', () => _check(kind, bindSample, bindSampleSteps(kind), core: true), skip: skipWithoutDom);
    });
  }
}
