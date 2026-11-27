// 严格规矩（规矩版本 2）的后端文档：类型检查接进后端校验（lib/backend/backend_validate_types.dart）。
// 版本 1 的文档一条 T 规则都不报（行为不变）；版本 2 的文档报出来的问题落在对的那块积木上。
import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/backend/backend_block_host.dart';
import 'package:lopicode/backend/backend_model.dart';
import 'package:lopicode/backend/backend_templates.dart';
import 'package:lopicode/backend/backend_type_bridge.dart';
import 'package:lopicode/backend/backend_validate.dart';
import 'package:lopicode/lang/rules.dart';

import 'support/backend_conformance.dart';
import 'support/backend_func_blocks.dart';
import 'support/backend_lang_blocks.dart';
import 'support/backend_lang_blocks_routes.dart';

BeDocument _doc(List<J> body, int rules) => parseLangBlocksDocument(langBlocksDocumentJson([route('r1', 'GET', '/x', body)]))..rules = rules;

List<String> _issues(BeDocument doc) => [for (final i in validateBackend(doc)) '${i.level.name} ${i.code} ${i.where}｜${i.problem}｜${i.arg}'];

List<LcLogicIssue> _typeIssues(BeDocument doc) => [
  for (final i in validateBackend(doc))
    if (RegExp(r'^T\d\d$').hasMatch(i.code)) i,
];

final J _ok = json(dc({'ok': yes()}));

const String _mixedPush = '往列表里加的东西要文字，放进来的是小数';

// 库 1 下半（A2）：类型检查认识了内置库，“网址参数”是“可空的文字”（以前当“任意”）。直接拿它“变成数字”在严格规矩下要先处理空。
const String _nullableQuery = '「变成数字」的第 1 个参数要文字，这个值可能是空，要先判断“不是空”';

void main() {
  test('开关现在的值：新文档是规矩版本 2（后端的严格生成接上了，见 B-gen-notes.md 15.2.2）', () {
    expect(kLangRulesForNewDocs, kLangRulesStrict);
    expect(backendStarterDocument('样本').rules, kLangRulesStrict);
  });

  test('版本 1 的文档：一条类型规则都不报', () {
    final body = [
      let('xs', ls([nm(1)])),
      push('xs', tx('a')),
      _ok,
    ];
    expect(_typeIssues(_doc(body, kLangRulesLoose)), isEmpty);
  });

  test('版本 2 的文档：往整数列表里加文字，报 T01，落在第 2 块上，是错', () {
    final body = [
      let('xs', ls([nm(1)])),
      push('xs', tx('a')),
      _ok,
    ];
    final found = _typeIssues(_doc(body, kLangRulesStrict));
    expect(found, hasLength(1));
    final i = found.single;
    expect(i.code, 'T01');
    expect(i.level, LcIssueLevel.error);
    expect(i.path.single.index, 1);
    expect(i.problem, '往列表里加的东西要整数，放进来的是文字');
    expect(i.advice.trim(), isNotEmpty);
    // 有类型错误的版本 2 文档拦在生成之前（重新生成、运行、导出都先看 backendErrors）。
    expect(backendErrors(_doc(body, kLangRulesStrict)).where((e) => e.code == 'T01'), hasLength(1));
    expect(backendErrors(_doc(body, kLangRulesLoose)), isEmpty);
  });

  test('版本 2 的文档：类型对的那些积木不报', () {
    final body = [
      let('xs', ls([nm(1)])),
      push('xs', nm(2)),
      let('n', op2('+', nm(1), nm(2))),
      _ok,
    ];
    expect(_typeIssues(_doc(body, kLangRulesStrict)), isEmpty);
  });

  test('现有样本文档换成版本 2：入门样本、“我的积木”样本一条不多；一致性样本多 10 条错、少 5 条老警告；第 4 版新积木样本多出 15 条（故意混着放类型的那些）', () {
    BeDocument starter() => backendStarterDocument('样本', rules: kLangRulesLoose);
    BeDocument lang() => parseLangBlocksDocument(langBlocksDocumentJson(langBlocksRoutes()));
    Map<String, int> byCode(Iterable<LcLogicIssue> issues) {
      final out = <String, int>{};
      for (final i in issues) {
        out[i.code] = (out[i.code] ?? 0) + 1;
      }
      return out;
    }

    for (final make in [starter, funcBlocksDocument]) {
      final v1 = _issues(make()..rules = kLangRulesLoose);
      final v2 = _issues(make()..rules = kLangRulesStrict);
      // “我的积木”样本的 /wrap 两个接口往同一个列表里先放文字、再放“变成数字”的结果乘 2：“变成数字”有了版本 2 的签名（结果是小数）以后，
      // 这是一处真的类型不一致，严格规矩下各报一条（接口里一条、包成积木以后积木里一条）。别的一条不多。
      // 另外（A2 起）：样本里 6 处“把 网址参数 变成数字”没先处理空，各报一条 T02（/call 4 处，/wrap 两个接口各 1 处）。
      expect(v2.where((x) => !x.contains(_mixedPush) && !x.contains(_nullableQuery)), v1);
      expect(v2.where((x) => x.contains(_mixedPush)), hasLength(make == starter ? 0 : 2));
      expect(v2.where((x) => x.contains(_nullableQuery)), hasLength(make == starter ? 0 : 6));
      expect(v2.where((x) => x.contains(_nullableQuery)).every((x) => x.startsWith('error T02 ')), isTrue);
    }

    // 一致性样本全是旧积木。合并以后旧积木的接口也查（老的“运算 / 比较”“不是”翻成语言核心的式子），所以它故意放的那些
    // “宽松规矩下能跑”的东西在严格规矩下报出来：5.5 取余、超过整数范围的 123456789012345678、六处“不是（不是（不是是否的东西））”、
    // 对文字“每个”、空 + 空。同一格上原来那 5 条“填的是固定的数字 / 文字”（老规则 G10）被说得更准的 T09 换掉。
    expect(_typeIssues(conformanceDocument()..rules = kLangRulesLoose), isEmpty);
    final conf = _typeIssues(conformanceDocument()..rules = kLangRulesStrict);
    // A2 起类型检查认识内置库：“网址参数”是可空的文字、“集合里全部”是列表（以前都当“任意”），所以又多报出 15 条：
    // /calc 拿网址参数直接算、直接比（T02 9 条）、直接当条件（T09 2 条）；/branch 同样（T02 1 条、T09 1 条）；
    // /truthy 里“不是（不是（集合里全部））”（T09 1 条）；/loop 的次数是网址参数（T01 1 条）。
    expect(byCode(conf), {'T06': 2, 'T16': 1, 'T09': 10, 'T01': 2, 'T02': 10});
    expect(conf.every((i) => i.level == LcIssueLevel.error), isTrue);
    final rest1 = _issues(conformanceDocument()..rules = kLangRulesLoose);
    final rest2 = [
      for (final i in validateBackend(conformanceDocument()..rules = kLangRulesStrict))
        if (!RegExp(r'^T\d\d$').hasMatch(i.code)) '${i.level.name} ${i.code} ${i.where}｜${i.problem}｜${i.arg}',
    ];
    final gone = [...rest1];
    for (final x in rest2) {
      expect(gone.remove(x), isTrue, reason: '版本 2 多出来一条不是类型规则的：$x');
    }
    expect(gone, hasLength(5));
    expect(gone.every((x) => x.startsWith('warning badType 接口「GET /truthy」') && x.contains('这里要一个条件，填的是固定的')), isTrue, reason: '$gone');

    expect(_typeIssues(lang()..rules = kLangRulesLoose), isEmpty);
    final extra = _typeIssues(lang()..rules = kLangRulesStrict);
    // 问题带着“参数里的哪个位置”，同一块同一个参数里的几处各算各的（合并前同一个参数里的只留一条，是 T01 8 条、T07 1 条）。
    // “数列”的版本 2 签名改成三个参数（从、到、步长）以后，原来那三条 T07（“「数列」要 2 个参数，给了 3 个”）没有了。
    expect(extra.where((i) => i.code == 'T07'), isEmpty);
    expect(byCode(extra)['T06'], 1);
  });

  test('“我的积木”没标类型的参数被别处用得很宽（任意）时，把它当函数值交给“映射”不该报“要任意的列表”', () {
    // 合并时查到的误报：样本里「加倍」的参数没标类型，从各处的调用推出来是“任意”；“映射(整数的列表, 加倍)”就被说成第 1 个参数要列表〈任意〉。
    final doc = funcBlocksDocument()..rules = kLangRulesStrict;
    final all = [for (final i in _typeIssues(doc)) '${i.where}｜${i.problem}'];
    expect(all.where((x) => x.contains('要任意的列表')), isEmpty);
    // 剩下的只有 /wrap 那一处真的类型不一致（见上一条测试的说明）。
    expect(all.where((x) => !x.contains(_mixedPush) && !x.contains(_nullableQuery)), isEmpty);
  });

  test('校验和编辑器拿的是同一批类型问题：校验里每条“错 / 警告”在检查结果里都有，提醒（T12）不进校验', () {
    final doc = parseLangBlocksDocument(langBlocksDocumentJson(langBlocksRoutes()))..rules = kLangRulesStrict;
    final check = beTypeCheck(doc)!;
    final want = {
      for (final f in check.findings)
        if (f.issue.level.name != 'hint') '${f.issue.code}|${f.at.treeId}|${f.at.path.map((s) => s.index).join('.')}|${f.problem}',
    };
    final got = {for (final i in _typeIssues(doc)) '${i.code}|${i.handlerId}|${i.path.map((s) => s.index).join('.')}|${i.problem}'};
    expect(got, isNotEmpty);
    expect(want.containsAll(got), isTrue, reason: '校验里多出来的：${got.difference(want)}');
    // 校验里同一块同一格同一条规则只留一条，所以可以比检查结果少，但不会多、不会是另一种说法。
    expect(want.difference(got).length, lessThan(want.length));
    expect(_typeIssues(doc).where((i) => i.code == 'T12'), isEmpty);
  });

  test('编辑器里同一个类型问题只出现一次（校验带出来的那份被带一键修的那份换掉）', () {
    for (final make in <BeDocument Function()>[
      () => _doc([
        let('xs', ls([nm(1)])),
        push('xs', tx('a')),
        let('n', op2('*', tx('12'), nm(2))),
        _ok,
      ], kLangRulesStrict),
      () => parseLangBlocksDocument(langBlocksDocumentJson(langBlocksRoutes()))..rules = kLangRulesStrict,
    ]) {
      final doc = make();
      final inValidate = _typeIssues(doc).length;
      expect(inValidate, greaterThan(0), reason: '前提：校验自己已经带出了类型问题');
      final host = BeBlockHost(doc: doc);
      final typed = [
        for (final i in host.issues)
          if (RegExp(r'^T\d\d$').hasMatch(i.rule)) i,
      ];
      // 条数＝检查结果的条数（不是“校验的＋检查的”），每一条的位置都不重样。
      expect(typed.length, beTypeCheck(doc)!.findings.length);
      final spots = [for (final i in typed) '${i.rule}|${i.scriptId}|${i.path.map((s) => '${s.index}${s.inElse}${s.arm}').join('.')}|${i.arg}|${i.exprPath}|${i.problem}'];
      expect(spots.toSet().length, spots.length, reason: '有重复：$spots');
      // 错误数没有被算两遍：编辑器的错误数＝校验的非类型错误＋检查结果里的类型错误。
      final plainErrors = backendErrors(doc).where((e) => !RegExp(r'^T\d\d$').hasMatch(e.code)).length;
      final typeErrors = beTypeCheck(doc)!.findings.where((f) => f.issue.isError).length;
      expect(host.errorCount, plainErrors + typeErrors);
      host.stopIssueTimer();
    }
  });
}
