// 页面逻辑新路上“故意写错的”要在检查阶段被拦下（积木第 5 版·前端 1·A2）：
// 类型对不上、在不能等的地方等、绑定了的属性再用积木写、前端文档启用后端库（和带手写代码的库）、派生里改状态。
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/lang/ast.dart';
import 'package:lopicode/lang/gen2_browser.dart';
import 'package:lopicode/lang/gen_support.dart';
import 'package:lopicode/lang/lib_apply.dart';
import 'package:lopicode/lang/lib_model.dart';
import 'package:lopicode/lowcode/bind_check.dart';
import 'package:lopicode/lowcode/export_bind_plan.dart';
import 'package:lopicode/lowcode/lib_page.dart';
import 'package:lopicode/lowcode/logic_core_js.dart';
import 'package:lopicode/lowcode/logic_js.dart';
import 'package:lopicode/lowcode/logic_libs.dart';
import 'package:lopicode/lowcode/logic_to_core.dart';
import 'package:lopicode/lowcode/model.dart';

import 'support/bind_sample.dart';
import 'support/lib_files.dart';
import 'support/lowcode_samples.dart';
import 'support/page_core_samples.dart';
import 'support/proto_lc.dart';

LcDocument _kitDoc(List<Object?> body) {
  final doc = docOf({
    'version': 3,
    'title': 'T',
    'root': {
      'id': 'root',
      'type': 'page',
      'children': [
        {
          'id': 'b1',
          'type': 'button',
          'props': {'text': 'x'},
        },
      ],
    },
    'logic': {
      'uses': [
        {'id': 'test/page-kit'},
      ],
      'variables': [
        {'name': 'n', 'type': 'number', 'initial': 1},
      ],
      'handlers': [
        {'id': 'h1', 'event': 'click', 'target': 'b1', 'body': body},
      ],
    },
  });
  doc.logic.loaded = [pageKit()];
  return doc;
}

String _program(String main) {
  final m = lcModule(main);
  return gen2BrowserProgram(libProgram([lcPageLibrary()], LModule(name: 'main', decls: m.decls, body: m.body)));
}

void main() {
  test('类型对不上：往要数字的库积木里递文字，这一页的逻辑不导出，说得出原因', () {
    final doc = _kitDoc([
      blk('setVar', {
        'name': 'n',
        'value': {
          'e': 'lib:test/page-kit#addTwice',
          'x': exJoin([exText('a'), exVar('n')]),
          'step': exNum(1),
        },
      }),
    ]);
    final notes = <String>[];
    final core = lcCoreJsFor(doc, const DomJsTarget(), notes, hash: false)!;
    expect(core.problems.single, contains('类型检查没过'));
    expect(core.top, isEmpty);
    expect(notes.single, contains('这一页的逻辑没有导出'));
    // 写对的照常
    final good = _kitDoc([
      blk('setVar', {
        'name': 'n',
        'value': {'e': 'lib:test/page-kit#addTwice', 'x': exVar('n'), 'step': exNum(1)},
      }),
    ]);
    expect(lcCoreJsFor(good, const DomJsTarget(), null, hash: false)!.problems, isEmpty);
  });

  test('在不能等的地方等：派生值的算法里歇一会儿，类型检查拦下', () {
    const host = '(宿主 time.sleep ((毫秒 整数)) -> 空)\n';
    expect(() => _program('$host(主 (设 d (调 派生格子 (λ块 () (做 (宿 time.sleep 5)) (返回 1)))))'), throwsA(isA<LangUnsupported>().having((e) => e.message, '话', allOf(contains('类型检查没过'), contains('等')))));
    // 能等的地方（事件的处理里）等，照常
    expect(_program('$host(主 (做 (调 当页面放上以后 (λ块 () (做 (宿 time.sleep 5))))))'), contains('lcProgram'));
  });

  test('绑定了的属性再用“改控件”积木写：检查报出来', () {
    final json = bindSampleJson();
    final handlers = ((json['logic']! as Map)['handlers']! as List).cast<Map<String, Object?>>();
    handlers.first['body'] = [
      ...handlers.first['body']! as List,
      blk('setProp', {'node': 'tipText', 'prop': 'text', 'value': exText('硬改')}),
    ];
    final issues = lcCheckBindings(LcDocument.parse(jsonEncode(json)));
    expect(issues.map((i) => i.message), contains(contains('已经绑定了，又被“改控件”积木直接改')));
    expect(lcCheckBindings(bindSample()).where((i) => i.message.contains('又被“改控件”积木直接改')), isEmpty);
  });

  test('前端文档启用只给后端的库、带手写代码的库、不在项目里的库：都拦下', () {
    final backend = libRead(libFilesFromDir('test/fixtures/libs/demo-kit'), builtin: false);
    expect(backend.ok, isTrue);
    expect(backend.side, LibSide.backend);
    final doc = _kitDoc(const []);
    doc.logic.uses.add({'id': 'demo/kit'});
    doc.logic.uses.add({'id': 'no/such'});
    doc.logic.loaded = [pageKit(), backend];
    final problems = <String>[];
    expect(lcUsedLibs(doc.logic, problems).map((l) => l.id), ['test/page-kit']);
    expect(problems, hasLength(2));
    expect(problems.first, contains('只给后端用的库'));
    expect(problems.last, contains('项目里找不到'));
    final built = lcLogicToCore(doc, pageUrl: (p) => p.id);
    expect(built.problems, hasLength(2));
    expect(lcCoreJsFor(doc, const DomJsTarget(), null, hash: false)!.top, isEmpty);
    // 反过来：后端文档里启用只给前端的库（“页面”库）也不行
    expect(lcPageLibrary().sideProblem(LibSide.backend), contains('只给前端用的库'));
  });

  test('派生里改状态：往派生值里写的积木翻译时跳过并记一句', () {
    final json = bindSampleJson();
    final handlers = ((json['logic']! as Map)['handlers']! as List).cast<Map<String, Object?>>();
    handlers.first['body'] = [
      ...handlers.first['body']! as List,
      blk('setVar', {'name': 'cartCount', 'value': exNum(9)}),
    ];
    final doc = LcDocument.parse(jsonEncode(json));
    final plan = LcBindPlan.of(doc, doc.root)!;
    final built = lcLogicToCore(doc, lookup: plan.lookup, pageUrl: (p) => p.id);
    expect(built.skipped, contains(contains('cartCount 是派生值，算出来的，不能改')));
    expect(built.problems, isEmpty);
  });
}
