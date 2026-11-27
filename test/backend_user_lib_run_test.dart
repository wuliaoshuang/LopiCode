// 用户自己写的库（积木第 5 版·库 2）的验收：用积木从零写库，在另一份文档里用它，五种语言真编译真跑，输出逐字节一样。
// 每个库都走整条产品路径：库文档 → 写出器 → 库文件 → 读入器 → 放进用它的文档 → 五种语言生成（见 support/user_libs.dart）。
// 缺哪种语言的编译器就跳过那种并打印原因。
@Tags(['external'])
@Timeout(Duration(minutes: 30))
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/backend/backend_to_service.dart';
import 'package:lopicode/lang/gen2_all.dart';

import 'support/backend_lang_blocks.dart';
import 'support/gen2_run.dart';
import 'support/user_libs.dart';

void main() {
  final cases = <(String, J Function(), List<J Function()>, String)>[
    ('校验器（类与接口）', checkUserDoc, [checkLibDoc], kCheckWant),
    ('流程（帽子、隐含的东西、带口）', flowUserDoc, [flowLibDoc], kFlowWant.substring(1)),
  ];
  for (final (name, user, libs, want) in cases) {
    for (final language in kGen2Languages) {
      test('$name · $language', () async {
        final doc = userDocument(user(), [for (final l in libs) buildUserLib(l()).lib]);
        final gen = beServiceGenerate(doc, language);
        expect(gen.problem, isNull);
        final skip = gen2SkipReason(language);
        if (skip != null) {
          // ignore: avoid_print — 跳过的原因要让跑测试的人看见
          print('跳过：$skip');
          markTestSkipped(skip);
          return;
        }
        final run = await gen2RunFiles(language, gen.files!);
        expect(run.problem, isNull, reason: language);
        expect(utf8.decode(run.stdout), want, reason: language);
      });
    }
  }
}
