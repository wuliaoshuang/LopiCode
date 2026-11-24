/// Node.js 生成器：`server.js`（你的接口）＋ `lc_runtime.js`（小库）＋ README。只用 node:http，不用装任何包。
library;

import 'package:lopicode/backend/backend_ir.dart';
import 'package:lopicode/backend/backend_target.dart';
import 'package:lopicode/backend/runtime_node.dart';

class NodeBackendTarget extends BeCodeTarget {
  const NodeBackendTarget();

  @override
  String get id => 'node';
  @override
  String get label => 'Node.js';
  @override
  String get summary => '只用 Node 自带的 node:http，不用装任何包（需要 Node 20 或更新）';
  @override
  String get entryFile => 'server.js';
  @override
  List<String> get startCommand => const ['node', 'server.js'];
  @override
  bool get verified => true;
  @override
  String get runtimeFile => 'lc_runtime.js';
  @override
  String get runtimeSource => '${kNodeRuntimeSource.trim()}\n';

  /// 在通用写法上多拆开 `</` 和 `<!--`：万一有人把这段脚本贴进网页的 `<script>` 里，不会被提前截断。
  @override
  String literal(Object? value) => switch (value) {
    null => 'null',
    final bool b => '$b',
    final num n => beNumberLiteral(n),
    final String s => beQuoted(s).replaceAll('</', r'<\/').replaceAll('<!--', r'<\!--'),
    _ => 'null',
  };

  /// 变量加 `v_` 前缀：不会撞上 JavaScript 的关键字，也不会撞上小库的名字。
  @override
  String variable(String name) => 'v_$name';
  @override
  String temp(int slot) => 'lcT$slot';

  /// “请求别的网址”是异步的，要等它。
  @override
  String call(String fn, List<String> args) => '${fn == 'fetch' ? 'await ' : ''}lc.$fn(${args.join(', ')})';

  @override
  String comment(String text) => '// ${beComment(text)}';
  @override
  List<String> declare(String name, String valueCode) => ['let ${variable(name)} = $valueCode;'];
  @override
  List<String> assign(String name, String valueCode) => ['${variable(name)} = $valueCode;'];
  @override
  List<String> let(int slot, String valueCode) => ['const ${temp(slot)} = $valueCode;'];
  @override
  List<String> perform(String callCode) => ['$callCode;'];
  @override
  List<String> ifElse(String cond, List<String> then, List<String> orElse) => [
    'if ($cond) {',
    ...indented(then),
    if (orElse.isNotEmpty) ...['} else {', ...indented(orElse)],
    '}',
  ];
  @override
  List<String> repeat(int n, String timesCode, List<String> body) => ['for (let lcI$n = 0, lcN$n = $timesCode; lcI$n < lcN$n; lcI$n++) {', ...indented(body), '}'];
  @override
  List<String> forEach(int n, String listCode, String item, List<String> body) => ['for (const lcItem$n of $listCode) {', ...indented(assign(item, 'lcItem$n')), ...indented(body), '}'];
  @override
  List<String> respond(String responseCode) => ['return $responseCode;'];

  @override
  String entrySource(BeProgram program) {
    final out = StringBuffer();
    out.writeln('// ${beComment(program.name, 60)} —— 由 LopiCode 后端积木生成（Node.js）。重新生成会覆盖本文件，要改请回到积木里改。');
    out.writeln('// 启动：node server.js    端口默认 ${program.port}，可以用环境变量 PORT 改。');
    out.writeln('"use strict";');
    out.writeln('const lc = require("./lc_runtime.js");');
    out.writeln();
    if (program.collections.isNotEmpty) {
      out.writeln('// 数据集合（存在内存里，服务重启就没了）');
      for (final c in program.collections) {
        out.writeln('lc.collection(${literal(c)});');
      }
      out.writeln();
    }
    for (final s in program.skipped) {
      out.writeln('// 没有生成：${beComment(s)}');
    }
    if (program.skipped.isNotEmpty) out.writeln();
    for (final r in program.routes) {
      out.writeln('// 接口：${beComment(r.title)}');
      out.writeln('lc.route(${literal(r.method)}, ${literal(r.path)}, async function ${r.fnName}(req) {');
      for (final line in indented(routeBody(r))) {
        out.writeln(line);
      }
      out.writeln('});');
      out.writeln();
    }
    out.writeln('lc.start(${program.port});');
    return out.toString();
  }
}
