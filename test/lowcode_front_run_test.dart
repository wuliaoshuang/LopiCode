// 新的页面逻辑（前端这一边的积木文档）的验收（积木第 5 版·前端 1·下半）：
// 样例在纯网页 / Vue 3 / React 三种产物里用官方编译器真编译 0 错 0 警告，再在 Node＋jsdom 里真跑同一串步骤。
// 环境只在开发机上有；找不到就明确跳过。不联网。没覆盖的：真浏览器、真手机。
@Tags(['external'])
@Timeout(Duration(minutes: 20))
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:lopicode/backend/front_doc.dart';
import 'package:lopicode/backend/front_upgrade.dart';
import 'package:lopicode/lowcode/model.dart';

import 'support/dev_tools.dart';
import 'support/page_core_samples.dart';
import 'support/page_front_check.dart';
import 'support/page_front_samples.dart';

/// 旧积木全集的样例，升级成新的页面逻辑。
LcDocument _upgraded() {
  final doc = coreSampleOld();
  lcFrontStore(doc.logic, lcUpgradeToFront(doc.logic).doc);
  return doc;
}

void main() {
  if (skipWithoutDom != false) {
    // ignore: avoid_print 跳过的原因要在测试输出里看得见
    print('【跳过】新的页面逻辑的真编译 / 真跑：$skipWithoutDom');
  }
  for (final kind in kFrontKinds.keys) {
    group('${kFrontKinds[kind]}', () {
      test('样例一（函数＋闭包＋类＋错误）', () => frontCheck(kind, frontSampleCore(), frontStepsCore()), skip: skipWithoutDom);
      test('旧积木全集升级成新的页面逻辑：原来那串步骤照过（升级不改行为）', () => frontCheck(kind, _upgraded(), coreStepsOld()), skip: skipWithoutDom);
      test('样例二（列表和记录状态＋重复里的事件＋去页面带参数）', () => frontCheck(kind, frontSampleList(), frontStepsList(kind)), skip: skipWithoutDom);
    });
  }
}
