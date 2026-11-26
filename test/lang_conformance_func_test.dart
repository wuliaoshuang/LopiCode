// 语言核心一致性（三）：函数（第 2 阶段）。Node / Python / Go / Java 四种语言真的跑起来，
// 输出逐字节相同、且等于写死的预期。PHP 也真跑（2026-11-26 起；本机没有 php 时跳过），文本检查在 lang_gen_func_test.dart。

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/lang/lang.dart';

import 'support/lang_cases_func.dart';
import 'support/lang_cases_hof.dart';
import 'support/lang_conformance.dart';

void main() {
  langConformanceGroup('函数', kLangFuncCases);
  langConformanceGroup('拿函数当参数的列表操作', kLangHofCases);

  group('语言核心一致性·函数出错时', () {
    for (final language in kLangRunnable) {
      test('$language：${kLangFailCases.length} 个会出错的程序都在该停的地方停下、带着该有的话', () async {
        final wrong = <String>[];
        for (final c in kLangFailCases) {
          final run = await runLang(language, [LModule(name: c.name, decls: c.decls, body: c.body)]);
          if (run == null) {
            // ignore: avoid_print 跳过的原因要让跑测试的人看见
            print('跳过：本机没有 $language 的工具');
            markTestSkipped('本机没有 $language 的工具');
            return;
          }
          final lines = run.out.trim().split('\n');
          if (run.exitCode <= 0) wrong.add('【${c.name}】应该出错退出，退出码却是 ${run.exitCode}：${run.err}');
          if (!run.err.contains(c.message)) wrong.add('【${c.name}】错误信息里没有“${c.message}”：${run.err}');
          if (lines.first != '前' || lines.contains('不该出现')) wrong.add('【${c.name}】出错前后的输出不对：$lines');
        }
        expect(wrong, isEmpty, reason: wrong.join('\n'));
      }, timeout: const Timeout(Duration(minutes: 15)));
    }
  });
}
