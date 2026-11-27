/// 规矩版本 2 的生成器·Node.js。小库：`lc2.js`（rt2_node.dart）。JS 两个目标共用的写法在 gen2_js.dart。
library;

import 'package:lopicode/lang/gen2_js.dart';
import 'package:lopicode/lang/gen2_split.dart';
import 'package:lopicode/lang/rt2_node.dart';

class NodeGen2 extends JsGen2 {
  NodeGen2(super.module, super.r);

  @override
  String get mainFile => 'main.js';
  @override
  Map<String, String> get runtimeFiles => const {'lc2.js': kRt2NodeSource};

  // “等”：Node 里一件要等的事交回来的是 Promise，前面写 await；“稍后的结果”本身就是 Promise。
  @override
  String nativeCall(String ident, List<String> args) => 'require("./$ident.js")(${args.join(', ')})';
  @override
  String awaited(String code) => '(await $code)';

  @override
  String programText(List<String> top, List<String> mainBody, {List<String> head = const []}) {
    final out = StringBuffer()
      ..writeln('// 由 LopiCode 积木生成（Node.js，严格规矩）。')
      ..writeln('"use strict";')
      ..writeln('const lc = require("./lc2.js");');
    head.forEach(out.writeln);
    if (top.isNotEmpty) out.writeln();
    top.forEach(out.writeln);
    out
      ..writeln()
      ..writeln('lc.run(${mainWaits ? 'async ' : ''}() => {');
    for (final l in indent(mainBody)) {
      out.writeln(l);
    }
    out.writeln('});');
    return out.toString();
  }

  // —— 分文件：每个模块是一个 CommonJS 文件，最后把类型、函数、变量交出去（module.exports）。
  // 变量交出去的是“读 / 写”一对（get / set），所以别的文件里 `lcM_模块.g_变量` 读到、改到的就是这个文件里的那个变量。

  @override
  String get ext => 'js';
  @override
  String globalFrom(String part, String base) => '${modVar(part)}.$base';

  @override
  List<String> importLines(String part, List<String> names, {required bool vars, required bool inMain}) {
    final file = 'require("./${partBase(part)}.js")';
    if (part == Gen2Split.kinds) return [names.isEmpty ? '$file;' : 'const { ${names.join(', ')} } = $file;'];
    return ['const ${modVar(part)} = $file;', if (names.isNotEmpty) 'const { ${names.join(', ')} } = ${modVar(part)};'];
  }

  @override
  List<String> exportLines(List<String> names, List<String> globals) => [
    'module.exports = {',
    ...indent([
      for (final n in names) '$n,',
      for (final g in globals) ...['get $g() { return $g; },', 'set $g(lcV) { $g = lcV; },'],
    ]),
    '};',
  ];

  @override
  String moduleText(String what, List<String> head, List<String> top, List<String> tail) =>
      ['// 由 LopiCode 积木生成（Node.js，严格规矩）：$what。', '"use strict";', 'const lc = require("./lc2.js");', ...head, if (top.isNotEmpty) '', ...top, '', ...tail, ''].join('\n');
}
