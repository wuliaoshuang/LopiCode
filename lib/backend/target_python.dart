/// Python 生成器：`server.py`（你的接口）＋ `lc_runtime.py`（小库）＋ README。只用标准库，不用装任何包。
library;

import 'package:lopicode/backend/backend_ir.dart';
import 'package:lopicode/backend/backend_lang.dart';
import 'package:lopicode/backend/backend_target.dart';
import 'package:lopicode/backend/runtime_python.dart';
import 'package:lopicode/backend/runtime_python_func.dart';
import 'package:lopicode/backend/runtime_python_lang.dart';
import 'package:lopicode/lang/gen.dart';
import 'package:lopicode/lang/gen_python.dart';

class PythonBackendTarget extends BeCodeTarget {
  const PythonBackendTarget();

  @override
  String get id => 'python';
  @override
  String get label => 'Python';
  @override
  String get summary => '只用标准库的 http.server，不用装任何包（需要 Python 3.8 或更新）';
  @override
  String get entryFile => 'server.py';
  @override
  List<String> get startCommand => const ['python3', 'server.py'];
  @override
  bool get verified => true;
  @override
  String get runtimeFile => 'lc_runtime.py';
  @override
  String get runtimeSource => '${kPythonRuntimeSource.trim()}\n';
  @override
  LangGen langGen(LangHost host) => PythonLangGen(host: host);
  @override
  String get langRuntimeSource => '${kPythonLangRuntimeSource.trim()}\n\n\n${kPythonLangFuncSource.trim()}\n';
  @override
  String get indentUnit => '    ';

  @override
  String literal(Object? value) => switch (value) {
    null => 'None',
    final bool b => b ? 'True' : 'False',
    final num n => beNumberLiteral(n),
    final String s => beQuoted(s),
    _ => 'None',
  };

  /// 变量加 `v_` 前缀：不会撞上 Python 的关键字（class、def…）。
  @override
  String variable(String name) => 'v_$name';
  @override
  String temp(int slot) => 'lc_t$slot';

  /// 小库里的函数按 Python 的习惯叫 `db_get`、`send_json`。
  static String snake(String fn) => fn.replaceAllMapped(RegExp('[A-Z]'), (m) => '_${m[0]!.toLowerCase()}');

  @override
  String call(String fn, List<String> args) => 'lc.${snake(fn)}(${args.join(', ')})';

  @override
  String comment(String text) => '# ${beComment(text)}';
  @override
  List<String> declare(String name, String valueCode) => assign(name, valueCode);
  @override
  List<String> assign(String name, String valueCode) => ['${variable(name)} = $valueCode'];
  @override
  List<String> let(int slot, String valueCode) => ['${temp(slot)} = $valueCode'];
  @override
  List<String> perform(String callCode) => [callCode];

  /// Python 的一段代码不能是空的（只有注释也算空）：补一个 `pass`。
  List<String> _suite(List<String> lines) => indented([...lines, if (lines.every((l) => l.trimLeft().startsWith('#'))) 'pass']);

  @override
  List<String> ifElse(String cond, List<String> then, List<String> orElse) => [
    'if $cond:',
    ..._suite(then),
    if (orElse.isNotEmpty) ...['else:', ..._suite(orElse)],
  ];
  @override
  List<String> repeat(int n, String timesCode, List<String> body) => ['for _ in range($timesCode):', ..._suite(body)];
  @override
  List<String> forEach(int n, String listCode, String item, List<String> body) => [
    'for lc_item$n in $listCode:',
    ..._suite([...assign(item, 'lc_item$n'), ...body]),
  ];
  @override
  List<String> respond(String responseCode) => ['return $responseCode'];

  @override
  String entrySource(BeProgram program) {
    final out = StringBuffer();
    out.writeln('# ${beComment(program.name, 60)} —— 由 LopiCode 后端积木生成（Python）。重新生成会覆盖本文件，要改请回到积木里改。');
    out.writeln('# 启动：python3 server.py    端口默认 ${program.port}，可以用环境变量 PORT 改。');
    // 用到新积木（积木第 4 版）时引入 lc_lang：它把 lc_runtime 的函数也一起带上。
    out.writeln('import ${beUsesLang(program) ? 'lc_lang' : 'lc_runtime'} as lc');
    out.writeln();
    if (program.collections.isNotEmpty) {
      out.writeln('# 数据集合（存在内存里，服务重启就没了）');
      for (final c in program.collections) {
        out.writeln('lc.collection(${literal(c)})');
      }
      out.writeln();
    }
    for (final s in program.skipped) {
      out.writeln('# 没有生成：${beComment(s)}');
    }
    if (program.skipped.isNotEmpty) out.writeln();
    for (final line in moduleFunctions(program)) {
      // 顶层的函数之间空两行（PEP 8）
      out.writeln(line);
      if (line.isEmpty) out.writeln();
    }
    for (final r in program.routes) {
      out.writeln();
      out.writeln('# 接口：${beComment(r.title)}');
      out.writeln('def ${r.fnName}(req):');
      for (final line in _suite(routeBody(r, program))) {
        out.writeln(line);
      }
      out.writeln();
      out.writeln();
      out.writeln('lc.route(${literal(r.method)}, ${literal(r.path)}, ${r.fnName})');
      out.writeln();
    }
    out.writeln();
    out.writeln('if __name__ == "__main__":');
    out.writeln('    lc.start(${program.port})');
    return out.toString();
  }
}
