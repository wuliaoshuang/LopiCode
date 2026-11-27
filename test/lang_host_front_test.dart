// 假宿主测试（积木第 5 版·前端 1·A2，D 分册 §9.2）：前端的宿主接口逐个有用例——
// 乙类 20 个原生绑定换一个假的浏览器窗口（假定时器、假网络、假存储、假地址和历史、假对话框、假窗口事件），
// 甲类 9 个页面宿主接口换一张假的读写表。再加事件记录（§2.4）。在 Node 里跑；没有 node 就跳过并打印原因。
@Tags(['external'])
@Timeout(Duration(minutes: 10))
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/lang/host_front.dart';
import 'package:lopicode/lang/rt2_browser.dart';
import 'package:lopicode/lowcode/page_host_js.dart';

import 'support/fake_host_js.dart';
import 'support/gen2_run.dart';

Future<List<String>> _run(String cases) async {
  final got = await gen2RunFiles('node', {'main.js': '$kFakeHostHarness\n$cases\n$kFakeHostRun', 'lc2.js': kRt2BrowserSource, 'host.js': kLcPageHostJs});
  expect(got.problem, isNull);
  return const LineSplitter().convert(utf8.decode(got.stdout));
}

void main() {
  final skip = gen2SkipReason('node');

  test('乙类：20 个原生绑定逐个过（假浏览器窗口），外加事件记录', () async {
    if (skip != null) {
      markTestSkipped(skip);
      return;
    }
    final lines = await _run(kFakeBrowserCases);
    expect(lines.where((l) => l.startsWith('FAIL')), isEmpty);
    expect(kHostFrontBrowser.length, 20);
    for (final name in kHostFrontBrowser) {
      expect(lines, contains('ok $name'), reason: '原生绑定 $name 没有用例');
    }
    expect(lines, contains('ok 事件记录'));
    expect(lines.length, 21);
  });

  test('甲类：9 个页面宿主接口逐个过（假读写表）', () async {
    if (skip != null) {
      markTestSkipped(skip);
      return;
    }
    final lines = await _run(kFakePageCases);
    expect(lines.where((l) => l.startsWith('FAIL')), isEmpty);
    expect(kHostFrontPage.length, 9);
    for (final name in kHostFrontPage) {
      expect(lines, contains('ok $name'), reason: '宿主接口 $name 没有用例');
    }
    expect(lines.length, 9);
  });
}
