// 第四轮 A4 补的九样（八块新积木＋匿名函数参数能标类型）：
// 用积木文档的数据模型搭一份程序 → 语法树 → 版本 2 的生成器 → 五种后端语言和浏览器目标真跑，六份输出逐字节一样。
// 另外钉住：每块翻成的语法树是什么形状；标了类型的参数真的被检查（放错类型的被拦）；从文字写法翻回来能认出这九样。
@Tags(['external'])
@Timeout(Duration(minutes: 30))
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/backend/backend_blocks_strict.dart';
import 'package:lopicode/backend/backend_core_gen.dart';
import 'package:lopicode/backend/backend_from_text.dart';
import 'package:lopicode/backend/backend_text.dart';
import 'package:lopicode/backend/backend_type_bridge.dart';
import 'package:lopicode/backend/lib_service_module.dart';
import 'package:lopicode/blocks/block_look.dart';
import 'package:lopicode/lang/ast.dart';
import 'package:lopicode/lang/ast_util.dart';
import 'package:lopicode/lang/gen2_all.dart';
import 'package:lopicode/lang/gen2_browser.dart';
import 'package:lopicode/lang/lib_model.dart';
import 'package:lopicode/lowcode/lib_page_module.dart';

import 'support/backend_core_samples.dart';
import 'support/backend_func_blocks.dart';
import 'support/backend_lang_blocks.dart';
import 'support/browser_run.dart';
import 'support/gen2_run.dart';

J _size(J x) => ex(kBeSizeOf, {'x': x});
J _join(List<J> items) => ex(kBeJoinText, {'items': items});
J _idiv(J l, J r) => ex(kBeIntDiv, {'l': l, 'r': r});
J _isNamed(J x, J name) => ex(kBeIsTypeNamed, {'x': x, 'name': name});
J _line(List<J> items) => blk('log', {'value': _join(items)});
J _at(J of, J key) => ex('index', {'of': of, 'key': key});

/// 短函数，参数标了类型。
J _arrowTyped(List<String> params, List<String> types, J body) => ex('lambdaExpr', {'params': params, kExprParamTypes: types, 'body': body});

/// 带口的匿名函数，参数标了类型。
J _lamTyped(List<String> params, List<String> types, List<J> body) => ex('lambda', {'params': params, kExprParamTypes: types, '@body': body});

J _doc({J? twice}) => coreDoc(
  'A4 的九样',
  main: [
    _line([
      tx('个数：'),
      _size(ls([nm(1), nm(2), nm(3)])),
      tx('、'),
      _size(tx('你好吗a')),
      tx('、'),
      _size(dc({'a': nm(1), 'b': nm(2)})),
    ]),
    _line([tx('整除：'), _idiv(nm(17), nm(5)), tx('、'), _idiv(nm(20), nm(4)), tx('、'), _idiv(nm(7), nm(2))]),
    _line([
      tx('取整：'),
      ex('toInt', {'x': nm(3.7)}),
      tx('、'),
      ex('toInt', {'x': nm(12)}),
    ]),
    _line([
      tx('是数字：'),
      ex('isNumeric', {'x': tx('12.5')}),
      tx('、'),
      ex('isNumeric', {'x': tx('abc')}),
      tx('、'),
      ex('isNumeric', {'x': nm(8)}),
    ]),
    _line([
      tx('解码：'),
      ex('urlDecode', {'s': tx('%E4%BD%A0%20a%2Bb')}),
    ]),
    let('cps', ex('codePoints', {'s': tx('你a')})),
    _line([tx('码点：'), _size(vr('cps')), tx(' 个，'), _at(vr('cps'), nm(0)), tx('、'), _at(vr('cps'), nm(1))]),
    let('kind', tx('text')),
    _line([
      tx('看类型：'),
      _isNamed(tx('x'), vr('kind')),
      tx('、'),
      _isNamed(nm(1), vr('kind')),
      tx('、'),
      _isNamed(ls([nm(1)]), tx('list')),
    ]),
    let('twice', twice ?? _arrowTyped(['x'], ['整数'], op2('*', pm('x'), nm(2)))),
    _line([
      tx('短函数：'),
      callV(vr('twice'), [nm(21)]),
    ]),
    let('count', _lamTyped(['s', 'n'], ['文字', '整数'], [ret(op2('+', _size(pm('s')), pm('n')))])),
    _line([
      tx('匿名函数：'),
      callV(vr('count'), [tx('四个字啊'), nm(10)]),
    ]),
  ],
);

const String _want =
    '个数：3、4、2\n'
    '整除：3、5、3\n'
    '取整：3、12\n'
    '是数字：true、false、true\n'
    '解码：你 a+b\n'
    '码点：2 个，20320、97\n'
    '看类型：true、false、true\n'
    '短函数：42\n'
    '匿名函数：14\n';

void main() {
  test('每一样翻成的语法树：小库调用 size / join / toInt / isNumeric / urlDecode / codePoints / isType、整除、带类型的参数', () {
    final checked = beTypeCheck(parseLangBlocksDocument(_doc()), pure: true)!;
    expect([for (final i in checked.result.issues.where((i) => i.isError)) i.message], isEmpty);
    final rts = <String>{};
    final ops = <String>{};
    final typed = <String>[];
    void look(LExpr e) {
      if (e is LRt) rts.add(e.fn);
      if (e is LBinary) ops.add(e.op);
      if (e is LLambda) {
        typed.addAll([for (final p in e.params) '${p.name}:${p.type?.show()}']);
        lWalkExprs(e.body, look);
      }
      lExprChildren(e).forEach(look);
    }

    lWalkExprs(checked.module.body, look);
    expect(rts, containsAll(['size', 'join', 'toInt', 'isNumeric', 'urlDecode', 'codePoints', 'isType']));
    expect(ops, contains('//'));
    expect(typed, ['x:整数', 's:文字', 'n:整数']);
  });

  test('标了类型的参数真的被检查：给“整数”的参数里做文字才有的事，查得出来', () {
    // 参数 x 标的是整数，却拿它去“网址解码”（要文字）。
    final bad = _arrowTyped(['x'], ['整数'], ex('urlDecode', {'s': pm('x')}));
    final checked = beTypeCheck(parseLangBlocksDocument(_doc(twice: bad)), pure: true)!;
    expect(checked.result.issues.where((i) => i.isError), isNotEmpty);
    // 不标类型的同一句：参数是“任意”，这一处不报。
    final loose = arrow(['x'], ex('urlDecode', {'s': pm('x')}));
    final ok = beTypeCheck(parseLangBlocksDocument(_doc(twice: loose)), pure: true)!;
    final errs = [for (final i in ok.result.issues.where((i) => i.isError)) i.message];
    final strictErrs = [for (final i in checked.result.issues.where((i) => i.isError)) i.message];
    expect(strictErrs.length, greaterThan(errs.length));
  });

  test('念出来的话带着参数的类型', () {
    final text = describeBeExpr(_arrowTyped(['x'], ['整数'], nm(1)));
    expect(text, contains('x：整数'));
  });

  test('两个自带库从文字写法翻成积木：这九样都认得出来，“照文字原样放着”的不剩几处', () {
    final page = beFromText(kLcPageModuleLc, id: 'shuang/page-view', name: '页面', side: LibSide.frontend);
    final service = beFromText(kBeServiceModuleLc, id: 'shuang/service-view', name: '接口服务', side: LibSide.backend);
    expect(page.problems, isEmpty);
    expect(service.problems, isEmpty);
    // 第三轮末是 4 处／34 处（reports/A3b.md）；补了这九样以后：
    expect(page.rawSpots, 0, reason: [for (final f in page.fns) ...f.raws].join('\n'));
    expect(service.rawSpots, 0, reason: [for (final f in service.fns) ...f.raws].join('\n'));
    expect(page.rawStmts + service.rawStmts, 0);
  });

  for (final language in kGen2Languages) {
    test('$language：生成、真跑，输出和预期逐字节一样', () async {
      final out = beCoreGenerate(parseLangBlocksDocument(_doc()), language);
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
      expect(utf8.decode(run.stdout), _want, reason: language);
    });
  }

  test('浏览器目标：同一份积木生成页面程序，在 Node 里真跑，输出一样', () async {
    final checked = beTypeCheck(parseLangBlocksDocument(_doc()), pure: true)!;
    final program = checked.program;
    final js = program != null ? gen2BrowserProgram(program) : gen2BrowserModule(checked.module);
    final skip = gen2SkipReason('node');
    if (skip != null) {
      // ignore: avoid_print — 跳过的原因要让跑测试的人看见
      print('跳过：$skip');
      markTestSkipped(skip);
      return;
    }
    final run = await browserRunProgram(js);
    expect(run.problem, isNull);
    expect(utf8.decode(run.stdout), _want);
  });
}
