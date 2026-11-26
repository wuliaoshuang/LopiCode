// 严格规矩的三块新值积木（“把 … 变成整数”“… 是空就用 …”“一定不是空 …”）翻成的语法树形状——
// 小库调用 `parseInt(s)`、`orElse(x, d)`、`must(x)`——版本 2 的生成器五种语言都生成得出来，真跑结果一样。
// 这里只搭语法树（不依赖积木和界面的文件）。
@Tags(['external'])
@Timeout(Duration(minutes: 30))
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/lang/ast.dart';
import 'package:lopicode/lang/gen2_all.dart';
import 'package:lopicode/lang/gen2_dyn.dart';
import 'package:lopicode/lang/typecheck.dart';

import 'support/gen2_run.dart';
import 'support/proto_lc.dart';

const String _program = '''
(主
  (打印 (连 "a：" (或空 (解析整数 "12") 0)))
  (打印 (连 "b：" (或空 (解析整数 "abc") 7)))
  (打印 (连 "c：" (必有 (解析整数 "-5"))))
  (设 n (解析整数 "x"))
  (打印 (连 "d：" (或空 n 1)))
  (设 t (或空 (取 (典 ("k" "有")) "没有") "缺"))
  (打印 (连 "e：" t))
  (打印 (连 "f：" (必有 n))))
''';

const String _want = 'a：12\nb：7\nc：-5\nd：1\ne：缺\n出错：这里的值是空，不能直接用\n';

void main() {
  test('三种形状在语法树里就是小库调用 parseInt / orElse / must，类型检查没有错', () {
    final module = lcModule(_program);
    final names = <String>{};
    lWalkAll(module.body, (e) {
      if (e is LRt) names.add(e.fn);
    });
    expect(names, containsAll(['parseInt', 'orElse', 'must']));
    expect(checkModuleTypes(module).hasErrors, isFalse);
  });

  for (final language in kGen2Languages) {
    test('$language：生成、真跑，输出一样（最后一句“一定不是空”碰到空，报错）', () async {
      final files = gen2Files(language, lcModule(_program));
      final skip = gen2SkipReason(language);
      if (skip != null) {
        // ignore: avoid_print — 跳过的原因要让跑测试的人看见
        print('跳过：$skip');
        markTestSkipped(skip);
        return;
      }
      final run = await gen2RunFiles(language, files);
      expect(run.problem, isNull, reason: language);
      expect(utf8.decode(run.stdout), _want, reason: language);
    });
  }
}
