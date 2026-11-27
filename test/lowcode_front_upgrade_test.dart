// “升级到新的页面逻辑”：旧处理一块一块改写成新的页面逻辑，改写完检查没有错误，翻得出浏览器程序。
// （升级前后在浏览器里行为一样，在 lowcode_front_run_test.dart 里真跑。）
import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/backend/backend_validate.dart';
import 'package:lopicode/backend/front_code.dart';
import 'package:lopicode/backend/front_doc.dart';
import 'package:lopicode/backend/front_upgrade.dart';
import 'package:lopicode/lowcode/model.dart';

import 'support/page_core_samples.dart';

void main() {
  test('旧积木全集的样例：升级后没有错误、没有丢东西、翻得出程序', () {
    final doc = coreSampleOld();
    final up = lcUpgradeToFront(doc.logic);
    expect(up.notes, isEmpty);
    expect(up.doc.hats.length, doc.logic.handlers.length);
    final issues = validateBackend(up.doc).where((i) => i.isError).toList();
    expect([for (final i in issues) '${i.where} ${i.problem}'], isEmpty);
    final out = lcFrontProgram(up.doc);
    expect(out.problems, isEmpty);
    expect(out.skipped, isEmpty);
    expect(lcUpgradePreview(doc.logic).errors, 0);
  });

  test('升级写回页面：旧处理只剩空壳，状态原样留着；再读回来一样', () {
    final doc = coreSampleOld();
    final vars = [for (final v in doc.logic.variables) v.name];
    final events = {for (final h in doc.logic.handlers) '${h.event} ${h.target ?? ''}'};
    lcFrontStore(doc.logic, lcUpgradeToFront(doc.logic).doc);
    expect(doc.logic.front, isNotNull);
    expect([for (final v in doc.logic.variables) v.name], vars);
    expect(doc.logic.handlers.every((h) => h.body.isEmpty), isTrue);
    expect({for (final h in doc.logic.handlers) '${h.event} ${h.target ?? ''}'}, {...events, 'load '});
    final again = LcDocument.parse(doc.encode());
    expect(again.encode(), doc.encode());
  });
}
