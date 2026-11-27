/// “看代码”的另一条路（积木第 5 版·核心 2·A3）：只用语言核心积木的严格文档，走版本 2 的生成器出五种语言的代码。
///
/// **不含接口、有“程序开始时”、从头到尾没用旧的“干活”积木**的文档走这条路：生成出来是一个跑完就结束的程序。
/// 严格生成开着（`kLangStrictBackendGen`，2026-11-27 起）的时候，写文件、看代码都用它（backend_strict_target.dart）；
/// 关着的时候只用来“看代码”。带接口的严格文档走“接口服务”库那条路（backend_to_service.dart）。
library;

import 'package:lopicode/backend/backend_model.dart';
import 'package:lopicode/backend/backend_type_bridge.dart';
import 'package:lopicode/lang/ast.dart';
import 'package:lopicode/lang/ast_util.dart';
import 'package:lopicode/lang/gen.dart' show LangUnsupported;
import 'package:lopicode/lang/gen2_all.dart';
import 'package:lopicode/lang/rules.dart';

/// 这份文档是不是“只用语言核心”的样子（值不值得去试着出代码）：严格规矩、没有接口、有“程序开始时”。
bool beIsCoreProgram(BeDocument doc) => langRulesStrict(doc.rules) && doc.routes.isEmpty && doc.core.main != null;

/// 语法树里有没有版本 2 的生成器不认的东西（旧的“干活”积木、小库以外的调用、“这次请求”）。有就返回一句说明。
String? bePureProblem(LModule module) {
  String? bad;
  void stmts(List<LStmt> list) {
    lWalk(list, (s) {
      if (s is LHost) bad ??= '用到了接口服务才有的积木（返回、数据集合、请求别的网址这些）';
    });
    lWalkExprs(list, (e) {
      if (e is LNative) bad ??= '用到了接口服务才有的值（数据集合、请求这些）';
      if (e is LName && e.kind == LNameKind.host) bad ??= '用到了“这次请求”';
    });
  }

  stmts(module.body);
  for (final d in module.decls) {
    switch (d) {
      case LFuncDecl():
        stmts(d.body);
      case LClassDecl():
        stmts(d.ctor?.body ?? const []);
        for (final m in d.methods) {
          stmts(m.fn.body);
        }
      default:
        break;
    }
  }
  return bad;
}

/// 出代码的结果：成了是文件表（第一个是主文件），不成是一句原因。
typedef BeCoreGen = ({Map<String, String>? files, String? problem});

/// 只用语言核心的严格文档 → 那种语言的整套文件。任何输入都不抛异常。
BeCoreGen beCoreGenerate(BeDocument doc, String language) {
  if (!beIsCoreProgram(doc)) return (files: null, problem: '这份文档不是只用语言核心的（要没有接口、有“程序开始时”）');
  if (!kGen2Languages.contains(language)) return (files: null, problem: '这种语言还没有生成器');
  final checked = beTypeCheck(doc, pure: true);
  if (checked == null) return (files: null, problem: '积木翻不成语法树');
  final bad = bePureProblem(checked.module);
  if (bad != null) return (files: null, problem: bad);
  try {
    final program = checked.program;
    return (files: program != null ? gen2ProgramFiles(language, program) : gen2Files(language, checked.module), problem: null);
  } on LangUnsupported catch (e) {
    return (files: null, problem: e.what);
  } on Object catch (e) {
    return (files: null, problem: '$e');
  }
}

/// “看代码”里显示的字：主文件的内容；出不来就是一句为什么。
String beCoreCodeText(BeDocument doc, String language) {
  final out = beCoreGenerate(doc, language);
  final files = out.files;
  if (files == null || files.isEmpty) return '代码现在出不来：${out.problem ?? ''}。\n\n把标红的地方改好，或者把接口服务才有的积木拿掉，再来看。';
  return files.values.first;
}

/// 主文件叫什么（“看代码”的标题用）；出不来是空的。
String beCoreCodeFileName(BeDocument doc, String language) => beCoreGenerate(doc, language).files?.keys.firstOrNull ?? '';
