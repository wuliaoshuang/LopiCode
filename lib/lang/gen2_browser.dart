/// 规矩版本 2 的生成器·浏览器目标。和 Node 目标是同一棵语法树、同一套类型检查、同一套 JS 写法（gen2_js.dart），不一样的只有：
/// - 产物是一个函数 `lcProgram(lc, lcHost)`：`lc`＝浏览器小库（rt2_browser.dart），`lcHost`＝页面宿主（9 个接口，纯网页 / Vue 3 / React 各一份）。
///   导出器决定怎么放（纯网页直接放进 logic.js；Vue / React 前面加 `export` 成模块）。库的模块先合进同一个程序再生成，不分文件。
/// - “等”：浏览器里没有 Node 的 AsyncLocalStorage，每个等写成 `lc.back(lc.lineNow(), await lc.safe(…))`——等之前记下“这条线”，
///   等回来先放回去再交值（或者把错抛出来）。
/// - 宿主接口只认前端那张表（host_front.dart）加两边都有的四个；后端的（文件、环境变量、开服务……）一律不认。
/// - 不接手写代码。
library;

import 'package:lopicode/lang/ast.dart';
import 'package:lopicode/lang/gen2_js.dart';
import 'package:lopicode/lang/gen_support.dart';
import 'package:lopicode/lang/host_front.dart';
import 'package:lopicode/lang/host_v2.dart';
import 'package:lopicode/lang/link.dart';
import 'package:lopicode/lang/rt2_browser.dart';
import 'package:lopicode/lang/rt_v2.dart';
import 'package:lopicode/lang/typecheck.dart';

/// 浏览器产物里页面程序那个函数的名字。
const String kBrowserProgramFn = 'lcProgram';

class BrowserGen2 extends JsGen2 {
  BrowserGen2(super.module, super.r);

  @override
  String get mainFile => 'program.js';
  @override
  Map<String, String> get runtimeFiles => const {kRt2BrowserFile: kRt2BrowserSource};

  @override
  LRtSig? hostSig(String name) => langHostOnFrontend(name) ? langHostSig(name) : null;
  @override
  Iterable<String> get hostNames => [...kHostFront.keys.where((k) => !kHostFrontBuiltinOnly.contains(k)), ...kHostBothSides];
  @override
  String hostCode(String name) => langHostFrontCode(name)!;
  @override
  String hostCall(String fn, List<String> args) => fn.startsWith('@') ? 'lcHost.${fn.substring(1)}(${args.join(', ')})' : super.hostCall(fn, args);

  @override
  String nativeCall(String ident, List<String> args) => unsupported('浏览器里不接手写代码（带手写代码的库只能给后端用）');
  @override
  String awaited(String code) => 'lc.back(lc.lineNow(), await lc.safe($code))';

  @override
  String programText(List<String> top, List<String> mainBody, {List<String> head = const []}) {
    final out = StringBuffer()
      ..writeln('// 由 LopiCode 积木生成（浏览器，严格规矩）。')
      ..writeln('function $kBrowserProgramFn(lc, lcHost) {')
      ..writeln('  "use strict";');
    for (final l in indent([...head, ...top])) {
      out.writeln(l);
    }
    out.writeln('  return lc.run(${mainWaits ? 'async ' : ''}() => {');
    for (final l in indent(indent(mainBody))) {
      out.writeln(l);
    }
    out
      ..writeln('  });')
      ..writeln('}');
    return out.toString();
  }

  // —— 不分文件：库的模块都合进这一个函数里 ——
  @override
  String get ext => 'js';
  @override
  String globalFrom(String part, String base) => unsupported('浏览器目标不分文件');
  @override
  List<String> importLines(String part, List<String> names, {required bool vars, required bool inMain}) => unsupported('浏览器目标不分文件');
  @override
  List<String> exportLines(List<String> names, List<String> globals) => unsupported('浏览器目标不分文件');
  @override
  String moduleText(String what, List<String> head, List<String> top, List<String> tail) => unsupported('浏览器目标不分文件');
}

/// 一个程序（几个模块）→ 浏览器里的页面程序（那个 `lcProgram` 函数的全文）。模块之间有错、类型检查没过都抛 [LangUnsupported]。
String gen2BrowserProgram(LProgram program) {
  final linked = linkProgram(program);
  final module = linked.module;
  if (module == null) throw LangUnsupported('模块检查没过：${linked.issues.first.message}');
  return gen2BrowserModule(module);
}

/// 一个模块（合好了的）→ 页面程序。[checked]＝已经查过类型的结果（没给就现查）。
String gen2BrowserModule(LModule module, [LTypeResult? checked]) {
  final result = checked ?? checkModuleTypes(module);
  if (result.hasErrors) {
    final first = result.issues.where((i) => i.isError).firstOrNull;
    throw LangUnsupported('类型检查没过：${first?.message ?? ''}');
  }
  return BrowserGen2(module, result).program();
}
