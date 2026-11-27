// 新的页面逻辑（前端这一边的积木文档）：读、写回、空壳、翻成浏览器程序（不真跑；真编译真跑在 lowcode_front_run_test.dart）。
import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/backend/backend_validate.dart';
import 'package:lopicode/backend/front_code.dart';
import 'package:lopicode/backend/front_doc.dart';
import 'package:lopicode/lowcode/lib_page.dart';
import 'package:lopicode/lowcode/logic_libs.dart';
import 'package:lopicode/lowcode/model.dart';

import 'support/page_front_samples.dart';

void main() {
  test('样例一：读得出来、自带“页面”库排第一个、空壳对得上', () {
    final doc = frontSampleCore();
    final front = lcFrontOf(doc.logic)!;
    expect(front.isFront, isTrue);
    expect(front.uses.first.id, kLcPageLibId);
    expect(front.loaded.first.id, kLcPageLibId);
    expect(lcDocUsesCore(doc), isTrue);
    expect([for (final h in doc.logic.handlers) '${h.event} ${h.target ?? ''}'], ['load ', 'click b1', 'click b2', 'click b3', 'click b4']);
    expect(doc.logic.handlers.every((h) => h.body.isEmpty), isTrue);
    final touch = lcFrontTouch(front);
    expect(touch.states, {'n'});
    expect(touch.props, {('t1', 'text'), ('t2', 'text'), ('t3', 'text'), ('t4', 'text'), ('in1', 'value')});
  });

  test('样例一：检查没有错误，翻得出浏览器程序', () {
    final front = lcFrontOf(frontSampleCore().logic)!;
    final issues = validateBackend(front).where((i) => i.isError).toList();
    expect([for (final i in issues) '${i.where} ${i.problem}'], isEmpty);
    final out = lcFrontProgram(front);
    expect(out.problems, isEmpty);
    expect(out.code, contains('function lcProgram(lc, lcHost)'));
    expect(out.code, contains('lcHost.uiOn('));
  });

  test('存出来再读回来一样；旧页面（没有 front）存出来没有这个键', () {
    final doc = frontSampleCore();
    final again = LcDocument.parse(doc.encode());
    expect(again.encode(), doc.encode());
    expect(lcFrontOf(again.logic)!.encode(), lcFrontOf(doc.logic)!.encode());
    final old = LcDocument.parse('{"version":3,"title":"x","root":{"id":"root","type":"page"},"logic":{"variables":[],"handlers":[]}}');
    expect(old.logic.front, isNull);
    expect(old.encode().contains('"front"'), isFalse);
    expect(lcDocUsesCore(old), isFalse);
  });
}
