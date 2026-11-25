// 语言核心一致性（三·补充）：函数里容易出岔子的写法。Node / Python / Go / Java 四种语言真的跑起来，
// 输出逐字节相同、且等于写死的预期。PHP 本机跑不了（未实测），这里只查它能生成出来。

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/lang/lang.dart';

import 'support/lang_cases_func_more.dart';
import 'support/lang_conformance.dart';

void main() {
  langConformanceGroup('函数（补充）', kLangFuncMoreCases);

  test('这些用例检查器都没有报错；五种语言（含未实测的 PHP）都能生成', () {
    for (final m in casesProgram(kLangFuncMoreCases)) {
      final a = analyzeModule(m);
      expect([for (final i in a.issues.where((i) => i.isError)) '${i.code} ${i.message}'], isEmpty, reason: m.name);
    }
    for (final l in kLangTargets) {
      expect(() => langGenFor(l)!.script(casesProgram(kLangFuncMoreCases)), returnsNormally, reason: l);
    }
  });
}
