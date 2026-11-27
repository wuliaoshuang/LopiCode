/// 前端这一边的积木文档（新的页面逻辑、前端库）→ 浏览器里跑的那段程序（积木第 5 版·前端 1·下半）。
///
/// 和后端文档出工程是同一套翻法（`beServiceBuild`：积木 → 语言核心的程序，垫底的自带库是“页面”），
/// 过同一个类型检查，再交给浏览器目标（lib/lang/gen2_browser.dart）。浏览器里不接手写代码：用上的库带了手写函数就不生成。
library;

import 'package:lopicode/backend/backend_lib_table.dart';
import 'package:lopicode/backend/backend_model.dart';
import 'package:lopicode/backend/backend_to_service.dart';
import 'package:lopicode/blocks/block_host.dart';
import 'package:lopicode/lang/gen2_browser.dart';
import 'package:lopicode/lang/gen_support.dart';
import 'package:lopicode/lang/lib_model.dart';
import 'package:lopicode/lang/typecheck.dart';
import 'package:lopicode/lowcode/lib_blocks.dart' show libOp;
import 'package:lopicode/lowcode/lib_page.dart';

/// 生成的结果：成了是 `lcProgram(lc, lcHost)` 那一段；不成是原因。[skipped]＝跳过没翻的地方各一句。
typedef LcFrontProgram = ({String? code, List<String> problems, List<String> skipped, List<LibLibrary> libs});

/// 任何输入都不抛异常。
LcFrontProgram lcFrontProgram(BeDocument doc) {
  final built = beServiceBuild(doc);
  final problems = [...built.problems];
  final program = built.program;
  if (program == null && problems.isEmpty) problems.add('积木翻不成语法树');
  for (final l in built.libs) {
    if (l.natives.isNotEmpty) problems.add('库「${l.name}」带了手写代码，浏览器里不接手写代码');
  }
  if (program == null || problems.isNotEmpty) return (code: null, problems: problems, skipped: built.skipped, libs: built.libs);
  try {
    final (linked, checked) = checkProgramTypes(program);
    if (linked.issues.isNotEmpty) return (code: null, problems: [linked.issues.first.message], skipped: built.skipped, libs: built.libs);
    final errors = checked?.errors ?? const [];
    if (errors.isNotEmpty) return (code: null, problems: ['${errors.first.where}：${errors.first.message}'], skipped: built.skipped, libs: built.libs);
    return (code: gen2BrowserProgram(program), problems: const [], skipped: built.skipped, libs: built.libs);
  } on LangUnsupported catch (e) {
    return (code: null, problems: [e.what], skipped: built.skipped, libs: built.libs);
  } on Object catch (e) {
    return (code: null, problems: ['$e'], skipped: built.skipped, libs: built.libs);
  }
}

/// “看代码”里给人看的字。
String lcFrontCodeText(BeDocument doc) {
  final out = lcFrontProgram(doc);
  final code = out.code;
  if (code != null) return code;
  return '代码现在出不来：${out.problems.join('；')}。\n\n把标红的地方改好再来看。';
}

/// 新的页面逻辑（一块积木都还没有）时“常用”页放的一套入门积木。
List<BlockItemRef> beFrontStarterItems(BeLibTable table) {
  String op(String id) => libOp(kLcPageLibId, id);
  bool has(String id) => table.of(op(id)) != null;
  return [
    for (final id in const ['stateSet', 'propSet', 'alert'])
      if (has(id)) BlockItemRef.block(op(id)),
    const BlockItemRef.block('if'),
    const BlockItemRef.block('let'),
    const BlockItemRef.block('forEach'),
    const BlockItemRef.block('repeat'),
    for (final id in const ['stateGet', 'propGet', 'eventValue'])
      if (has(id)) BlockItemRef.expr(op(id)),
    const BlockItemRef.expr('bin'),
    const BlockItemRef.expr('join'),
    const BlockItemRef.expr('listLit'),
    const BlockItemRef.expr('obj'),
  ];
}
