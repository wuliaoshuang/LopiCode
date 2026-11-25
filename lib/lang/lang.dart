/// 语言核心的入口（积木第 4 版）。设计稿 docs/blocks-v4-language-design.md，对照表和取舍见其中“实施记录·阶段 1”。
///
/// - 语法树：ast.dart；类型：types.dart；检查（名字、类型、规则）：analyze.dart；
/// - 小库函数表：rt.dart；生成器：gen.dart ＋ gen_node / gen_python / gen_go / gen_java / gen_php。
library;

import 'package:lopicode/lang/ast.dart';
import 'package:lopicode/lang/gen.dart';
import 'package:lopicode/lang/gen_go.dart';
import 'package:lopicode/lang/gen_java.dart';
import 'package:lopicode/lang/gen_node.dart';
import 'package:lopicode/lang/gen_php.dart';
import 'package:lopicode/lang/gen_python.dart';

export 'package:lopicode/lang/analyze.dart';
export 'package:lopicode/lang/ast.dart';
export 'package:lopicode/lang/ast_util.dart';
export 'package:lopicode/lang/custom_block.dart';
export 'package:lopicode/lang/custom_block_edit.dart';
export 'package:lopicode/lang/gen.dart';
export 'package:lopicode/lang/rt.dart';
export 'package:lopicode/lang/types.dart';

/// 语言核心支持的目标语言。
const List<String> kLangTargets = ['node', 'python', 'go', 'java', 'php'];

/// 按语言 id 拿生成器；不认识的 id 返回 null。
LangGen? langGenFor(String language, {LangHost host = const LangHost()}) => switch (language) {
  'node' => NodeLangGen(host: host),
  'python' => PythonLangGen(host: host),
  'go' => GoLangGen(host: host),
  'java' => JavaLangGen(host: host),
  'php' => PhpLangGen(host: host),
  _ => null,
};

/// **给第三步的入口**：一段语法树语句 ＋ 目标语言 → 代码片段（要在函数开头声明的名字 ＋ 一行行代码）。
///
/// 同一个函数体里的几段要传同一个 [ctx]。不认识的语言、这一阶段不支持的节点抛 [LangUnsupported]（消息是给人看的整句话）；
/// 生成前先用 `analyzeBody` 检查，有错误就不要生成。
LangFragment langFragment(String language, List<LStmt> body, {LangHost host = const LangHost(), LangCtx? ctx}) {
  final gen = langGenFor(language, host: host);
  if (gen == null) throw LangUnsupported('不认识的目标语言 $language');
  return gen.fragment(body, ctx: ctx);
}
