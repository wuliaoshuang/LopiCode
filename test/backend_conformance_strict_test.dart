// 一致性样本 135 条的严格规矩版（积木第 5 版·库 1 下半）：产品路径（beServiceGenerate）出工程，五种语言真跑，逐字节比。
// 文档怎么改写、哪几条的期望和版本 1 不一样、为什么：test/support/conformance_strict.dart。
@Tags(['external'])
@Timeout(Duration(minutes: 40))
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/backend/backend_to_service.dart';
import 'package:lopicode/backend/backend_validate.dart';
import 'package:lopicode/lang/gen2_all.dart';

import 'support/backend_conformance.dart';
import 'support/conformance_strict.dart';
import 'support/gen2_run.dart';
import 'support/gen2_serve.dart';
import 'support/service_run.dart';

void main() {
  test('严格版样本：135 条一条不少，另加严格规矩才有的几条', () {
    expect(conformanceCases, hasLength(135));
    expect(strictCases(), hasLength(135 + strictExtraCases.length));
  });

  test('严格版样本文档：类型检查一条错都没有，翻得出来', () {
    final doc = strictConformanceDocument();
    expect([
      for (final i in validateBackend(doc))
        if (RegExp(r'^[TM]\d\d$').hasMatch(i.code)) '${i.code} ${i.where.split('（').first}｜${i.problem}',
    ], isEmpty);
    final out = beServiceProgram(doc);
    expect(out.problems, isEmpty);
  });

  for (final language in kGen2Languages) {
    test('$language：严格版 135 条真跑，状态码、Content-Type、内容逐字节一样', () async {
      final skip = gen2SkipReason(language);
      if (skip != null) {
        markTestSkipped(skip);
        return;
      }
      final gen = beServiceGenerate(strictConformanceDocument(), language);
      expect(gen.problem, isNull);
      final server = await gen2Serve(language, gen.files!);
      final cases = strictCases();
      late final List<String> wrong;
      try {
        wrong = await serviceRun(server, cases);
      } finally {
        await server.stop();
      }
      final first135 = wrong.where((w) => int.parse(RegExp(r'第 (\d+) 条').firstMatch(w)!.group(1)!) <= 135).length;
      // ignore: avoid_print — 逐语言的通过数要让跑测试的人看见
      print('$language：严格版 135 条里通过 ${135 - first135} 条；另加的 ${strictExtraCases.length} 条里通过 ${strictExtraCases.length - (wrong.length - first135)} 条');
      expect(wrong, isEmpty, reason: '$language 的标准错误：\n${server.stderrText}');
    });
  }
}
