// 规矩版本 1 的行为“一个字不变”的钉子（积木第 5 版·核心 1）。
//
// 一批现有样本（入门样本、后端一致性样本、第 4 版新积木样本、函数和“我的积木”样本，外加语言核心一致性测试的全部用例程序）：
// 五种语言生成出来的每个文件（长度 ＋ 指纹）和校验结果（逐条原文），都必须等于 test/golden/rules_v1_frozen.txt 里记下的。
// 那份记录是 **改造类型系统之前**（master da5ae2c）生成的。以后谁动了版本 1 的生成或校验，这里会失败。
//
// 真的要改版本 1 的行为（要霜霜点头）才重出记录：`LOPI_GOLDEN_WRITE=1 flutter test test/rules_v1_frozen_test.dart`。
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/backend/backend_model.dart';
import 'package:lopicode/backend/backend_targets.dart';
import 'package:lopicode/backend/backend_templates.dart';
import 'package:lopicode/backend/backend_validate.dart';
import 'package:lopicode/lang/lang.dart';

import 'support/backend_conformance.dart';
import 'support/backend_func_blocks.dart';
import 'support/backend_lang_blocks.dart';
import 'support/backend_lang_blocks_routes.dart';
import 'support/lang_cases_flow.dart';
import 'support/lang_cases_func.dart';
import 'support/lang_cases_func_more.dart';
import 'support/lang_cases_hof.dart';
import 'support/lang_cases_rt.dart';
import 'support/lang_cases_rt_basic.dart';
import 'support/lang_cases_rt_data.dart';
import 'support/lang_conformance.dart';

const String _goldenPath = 'test/golden/rules_v1_frozen.txt';

/// FNV-1a 64 位（不引新依赖；只为发现“变了”，不是为了安全）。
String _fingerprint(String s) {
  var h = 0xcbf29ce484222325;
  for (final b in utf8.encode(s)) {
    h ^= b;
    h = (h * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF;
  }
  return h.toUnsigned(64).toRadixString(16).padLeft(16, '0');
}

Map<String, BeDocument> _docs() => {
  '入门样本': backendStarterDocument('样本'),
  '一致性样本': conformanceDocument(),
  '第4版新积木': parseLangBlocksDocument(langBlocksDocumentJson(langBlocksRoutes())),
  '函数和我的积木': funcBlocksDocument(),
};

Map<String, List<LangCase>> _cases() => {
  'flow': kLangFlowCases,
  'func': kLangFuncCases,
  'funcMore': kLangFuncMoreCases,
  'hof': kLangHofCases,
  'rt': kLangRtCases,
  'rtBasic': kLangRtBasicCases,
  'rtData': kLangRtDataCases,
};

List<String> snapshot() {
  final out = <String>[];
  for (final MapEntry(key: name, value: doc) in _docs().entries) {
    out.add('文档 $name 存盘 ${doc.encode().length} ${_fingerprint(doc.encode())}');
    for (final issue in validateBackend(doc, languages: kLangTargets)) {
      out.add('文档 $name 校验 ${issue.level.name} ${issue.code} ${issue.where}｜${issue.problem}｜${issue.arg}｜${issue.exprPath}｜${issue.fix}');
    }
    for (final lang in kLangTargets) {
      final files = generateBackend(doc, language: lang)!.files;
      for (final file in files.keys.toList()..sort()) {
        out.add('文档 $name $lang $file ${files[file]!.length} ${_fingerprint(files[file]!)}');
      }
    }
  }
  for (final MapEntry(key: name, value: cases) in _cases().entries) {
    final modules = casesProgram(cases);
    for (final m in modules) {
      final a = analyzeModule(m);
      for (final i in a.issues) {
        out.add('程序 $name 检查 $i');
      }
    }
    for (final lang in kLangTargets) {
      final text = langGenFor(lang)!.script(modules);
      out.add('程序 $name $lang ${text.length} ${_fingerprint(text)}');
    }
  }
  return out;
}

void main() {
  test('规矩版本 1：现有样本的五种语言生成结果和校验结果逐字不变', () {
    final now = snapshot();
    final file = File(_goldenPath);
    if (Platform.environment['LOPI_GOLDEN_WRITE'] == '1') {
      file.writeAsStringSync('${now.join('\n')}\n');
    }
    expect(file.existsSync(), isTrue, reason: '缺 $_goldenPath');
    final want = const LineSplitter().convert(file.readAsStringSync());
    expect(now.length, want.length, reason: '条数变了');
    for (var i = 0; i < want.length; i++) {
      expect(now[i], want[i], reason: '第 ${i + 1} 条变了');
    }
    expect(now.length, greaterThan(100));
  });
}
