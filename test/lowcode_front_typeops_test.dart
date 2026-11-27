// 三块类型积木在浏览器目标上：页面逻辑里用一遍，纯网页 / Vue 3 / React 三种产物真编译 0 错 0 警告，jsdom 里真跑，
// 得到的那一行字和五种后端语言的一个字不差（backend_typeops_blocks_test.dart 用的是同一份积木）。
// 环境只在开发机上有；找不到就明确跳过。不联网。
@Tags(['external'])
@Timeout(Duration(minutes: 30))
library;

import 'package:flutter_test/flutter_test.dart';

import 'support/backend_lang_blocks.dart';
import 'support/dev_tools.dart';
import 'support/page_front_check.dart';
import 'support/page_front_samples.dart';
import 'support/typeops_sample.dart';

void main() {
  for (final kind in kFrontKinds.keys) {
    test('${kFrontKinds[kind]}：点一下，文字变成那一行', () async {
      final doc = frontPage(
        [btn('b1', '试'), txt('t1')],
        const [],
        frontDoc(
          types: [typeOpsCard()],
          hats: [
            onClick('h1', 'b1', [...typeOpsBody(), show('t1', vr('out'))]),
          ],
        ),
      );
      await frontCheck(kind, doc, [
        {'op': 'click', 'sel': '.n-b1'},
        {'op': 'text', 'sel': '.n-t1', 'is': kTypeOpsWant},
      ]);
    }, skip: skipWithoutDom);
  }
}
