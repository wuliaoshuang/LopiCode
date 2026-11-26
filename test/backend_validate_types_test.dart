// 严格规矩（规矩版本 2）的后端文档：类型检查接进后端校验（lib/backend/backend_validate_types.dart）。
// 版本 1 的文档一条 T 规则都不报（行为不变）；版本 2 的文档报出来的问题落在对的那块积木上。
import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/backend/backend_model.dart';
import 'package:lopicode/backend/backend_templates.dart';
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

void main() {
  test('开关现在的值：新文档还是规矩版本 1（后端的严格生成还没接上，见 B-gen-notes.md 第 5 节）', () {
    expect(kLangRulesForNewDocs, kLangRulesLoose);
    expect(backendStarterDocument('样本').rules, kLangRulesLoose);
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

  test('现有样本文档换成版本 2：入门样本、一致性样本、“我的积木”样本一条不多；第 4 版新积木样本多出 10 条（故意混着放类型的那些）', () {
    BeDocument starter() => backendStarterDocument('样本', rules: kLangRulesLoose);
    BeDocument lang() => parseLangBlocksDocument(langBlocksDocumentJson(langBlocksRoutes()));
    for (final make in [starter, conformanceDocument, funcBlocksDocument]) {
      final v1 = _issues(make()..rules = kLangRulesLoose);
      final v2 = _issues(make()..rules = kLangRulesStrict);
      expect(v2, v1);
    }
    expect(_typeIssues(lang()..rules = kLangRulesLoose), isEmpty);
    final extra = _typeIssues(lang()..rules = kLangRulesStrict);
    final byCode = <String, int>{};
    for (final i in extra) {
      byCode[i.code] = (byCode[i.code] ?? 0) + 1;
    }
    expect(byCode, {'T01': 8, 'T06': 1, 'T07': 1});
    // 其中一条是老积木“数列”带步长（3 个参数）对不上版本 2 的签名（2 个）：翻开关前要先解决。
    expect(extra.where((i) => i.code == 'T07').single.problem, '「数列」要 2 个参数，给了 3 个');
  });
}
