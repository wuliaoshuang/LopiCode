// 语言核心一致性（一）：语法树的每一种节点，Node / Python / Go / Java 四种语言真的跑起来，
// 输出逐字节相同、且等于写死的预期。不经过积木，直接用语法树搭程序。PHP 本机跑不了，文本检查在 lang_gen_test.dart。

import 'support/lang_cases_flow.dart';
import 'support/lang_conformance.dart';

void main() {
  langConformanceGroup('语法树节点', kLangFlowCases);
}
