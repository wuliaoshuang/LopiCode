// 语言核心一致性（二）：第 4 版新加的小库函数，Node / Python / Go / Java 四种语言真的跑起来，
// 输出逐字节相同、且等于写死的预期；会抛错的操作四种语言都抛同一句话。PHP 也真跑（2026-11-26 起；本机没有 php 时跳过），文本检查在 lang_gen_test.dart。
import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/lang/lang.dart';

import 'support/lang_cases_rt.dart';
import 'support/lang_conformance.dart';

void main() {
  langConformanceGroup('小库函数', kLangRtCases);

  test('用例盖住了每一个第 1 阶段的小库函数', () {
    final used = <String>{};
    void expr(LExpr e) {
      if (e is LRt) used.add(e.fn);
      lExprChildren(e).forEach(expr);
    }

    for (final c in [...kLangRtCases, for (final e in kLangErrorCases) LangCase(e.$1, e.$2, const [])]) {
      lWalkExprs(c.body, expr);
    }
    final want = {
      for (final e in kLangRtFns.entries)
        if (e.value.stage == 1 && !e.value.internal) e.key,
    };
    expect(want.difference(used), isEmpty, reason: '这些小库函数没有一致性用例');
  });

  group('语言核心一致性·抛错', () {
    for (final language in kLangRunnable) {
      test('$language：写到不存在的位置 / 改不是列表字典的值会抛错，消息一样，前面的输出还在', () async {
        for (final (name, body, message) in kLangErrorCases) {
          final run = await runLang(language, [LModule(name: name, body: body)]);
          if (run == null) {
            // ignore: avoid_print 跳过的原因要让跑测试的人看见
            print('跳过：本机没有 $language 的工具');
            markTestSkipped('本机没有 $language 的工具');
            return;
          }
          expect(run.exitCode, isNot(0), reason: '$name：应该以出错收场\n${run.out}\n${run.err}');
          expect(run.exitCode, isNot(-1), reason: '$name：${run.err}');
          expect(run.out, '前\n', reason: name);
          expect(run.err, contains(message), reason: name);
        }
      }, timeout: const Timeout(Duration(minutes: 15)));
    }
  });
}
