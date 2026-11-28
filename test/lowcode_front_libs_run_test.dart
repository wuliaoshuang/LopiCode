// 自带前端库（定时、本地保存、状态仓库、事件总线）的样例：每个库三组，纯网页、Vue 3、React 三种导出真编译 0 错 0 警告，
// 逻辑在 Node＋jsdom 里真跑同一串步骤（三种都得一步不差地过＝三种一致）。“请求”库的在 lowcode_front_libs_http_test.dart。
@Tags(['external'])
library;

import 'package:flutter_test/flutter_test.dart';

import 'support/dev_tools.dart';
import 'support/front_libs_samples.dart';
import 'support/page_front_check.dart';

void main() {
  final skip = skipWithoutDom;
  final groups = {'定时': timerSamples, '事件总线': busSamples, '本地保存': storageSamples, '状态仓库': storeSamples};
  for (final g in groups.entries) {
    group('“${g.key}”库', () {
      test('有三组样例', () => expect(g.value().length, greaterThanOrEqualTo(3)));
      for (final kind in kFrontKinds.entries) {
        test(
          '${kind.value}：三组样例真编译、真跑',
          () async {
            for (final s in g.value()) {
              await frontCheckAll(kind.key, s.doc, [s.steps]);
            }
          },
          skip: skip,
          timeout: const Timeout(Duration(minutes: 6)),
        );
      }
    });
  }
}
