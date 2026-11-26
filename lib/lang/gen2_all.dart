/// 规矩版本 2 的生成器·入口：一个模块（先过类型检查）→ 一种语言的整套文件。
library;

import 'package:lopicode/lang/ast.dart';
import 'package:lopicode/lang/gen2_expr.dart';
import 'package:lopicode/lang/gen2_node.dart';
import 'package:lopicode/lang/gen2_python.dart';
import 'package:lopicode/lang/gen_support.dart';
import 'package:lopicode/lang/typecheck.dart';

/// 版本 2 的独立程序能生成成哪些语言。
const List<String> kGen2Languages = ['node', 'python'];

Gen2 gen2For(String language, LModule module, LTypeResult result) => switch (language) {
  'node' => NodeGen2(module, result),
  'python' => PythonGen2(module, result),
  _ => throw LangUnsupported('「$language」还没有带类型的生成器'),
};

/// 生成整套文件（相对路径 → 内容）：主文件＋小库。类型检查没过就抛 [LangUnsupported]（第一条错误的说法）。
Map<String, String> gen2Files(String language, LModule module, [LTypeResult? checked]) {
  final result = checked ?? checkModuleTypes(module);
  if (result.hasErrors) {
    final first = result.issues.where((i) => i.isError).firstOrNull;
    throw LangUnsupported('类型检查没过：${first?.message ?? ''}');
  }
  final gen = gen2For(language, module, result);
  return {gen.mainFile: gen.program(), ...gen.runtimeFiles};
}
