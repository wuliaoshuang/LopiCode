// 核心 2 的样例文档（用积木文档的数据模型搭的）：积木 → 语法树 → 版本 2 的生成器 → 五种语言真编译真跑，输出和预期逐字节一样。
// 标了 fixture 的样例，预期就是 test/fixtures/core2/ 里那个手写样例的 .expect——“积木搭出来的”和“样例写出来的”跑出来一个样。
@Tags(['external'])
@Timeout(Duration(minutes: 30))
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/backend/backend_core_gen.dart';
import 'package:lopicode/lang/gen2_all.dart';

import 'support/backend_core_samples.dart';
import 'support/backend_lang_blocks.dart';
import 'support/gen2_run.dart';

void main() {
  for (final s in coreSamples) {
    final fixture = s.fixture;
    final want = fixture == null ? s.expect! : File('test/fixtures/core2/$fixture.expect').readAsStringSync();
    for (final language in kGen2Languages) {
      test('${s.name} · $language', () async {
        final out = beCoreGenerate(parseLangBlocksDocument(s.doc), language);
        expect(out.problem, isNull);
        final skip = gen2SkipReason(language);
        if (skip != null) {
          // ignore: avoid_print — 跳过的原因要让跑测试的人看见
          print('跳过：$skip');
          markTestSkipped(skip);
          return;
        }
        final run = await gen2RunFiles(language, out.files!);
        expect(run.problem, isNull, reason: language);
        expect(utf8.decode(run.stdout), want, reason: language);
      });
    }
  }
}
