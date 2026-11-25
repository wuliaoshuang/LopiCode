/// Go 生成器：`main.go`（你的接口）＋ `lc/values.go`、`lc/server.go`、`lc/fetch.go`（小库）＋ `go.mod` ＋ README。只用标准库，不用装任何包。
///
/// 生成的 `main.go` 已经是 gofmt 的规范格式（缩进用制表符）。值在 Go 里一律是 `any`：
/// `nil / bool / float64 / string / []any / map[string]any`，所以数字字面量都带小数点（`200.0`）。
library;

import 'package:lopicode/backend/backend_ir.dart';
import 'package:lopicode/backend/backend_target.dart';
import 'package:lopicode/backend/runtime_go.dart';
import 'package:lopicode/backend/runtime_go_fetch.dart';
import 'package:lopicode/backend/runtime_go_func.dart';
import 'package:lopicode/backend/runtime_go_lang.dart';
import 'package:lopicode/backend/runtime_go_server.dart';
import 'package:lopicode/lang/gen.dart';
import 'package:lopicode/lang/gen_go.dart';

/// 生成的工程的模块名（写死的，不用用户的名字：模块名里能出现的字符很有限）。
const String kGoModuleName = 'lcbackend';

class GoBackendTarget extends BeCodeTarget {
  const GoBackendTarget();

  @override
  String get id => 'go';
  @override
  String get label => 'Go';
  @override
  String get summary => '只用标准库的 net/http，不用装任何包（需要 Go 1.18 或更新）；已在本机用 Go 1.25 真跑验证';
  @override
  String get entryFile => 'main.go';
  @override
  List<List<String>> get buildCommands => const [
    ['go', 'build', '-o', 'server', '.'],
  ];
  @override
  List<String> get startCommand => const ['./server'];
  @override
  bool get verified => true;
  @override
  String get runtimeFile => 'lc/values.go';
  @override
  String get runtimeSource => '${kGoRuntimeValuesSource.trim()}\n';
  @override
  LangGen langGen(LangHost host) => GoLangGen(host: host, module: kGoModuleName);
  @override
  String get langRuntimeSource => '${kGoLangRuntimeSource.trim()}\n\n${kGoLangFuncSource.trim()}\n';
  @override
  String get indentUnit => '\t';
  @override
  List<String> get notes => const ['想不编译直接跑可以用 `go run .`。Windows 上编译出来的文件要叫 `server.exe`（`go build -o server.exe .`）。'];

  /// Go 的常量默认可能是整数，值的规矩里数字都是 float64：没有小数点 / 指数的补上 `.0`。
  /// U+FEFF 在 Go 源码里不许原样出现（会被当成放错位置的 BOM），写成转义。
  @override
  String literal(Object? value) => switch (value) {
    null => 'nil',
    final bool b => '$b',
    final num n => _number(n),
    final String s => beQuoted(s).replaceAll('\ufeff', r'\ufeff'),
    _ => 'nil',
  };

  static String _number(num n) {
    final text = beNumberLiteral(n);
    return text.contains(RegExp('[.eE]')) ? text : '$text.0';
  }

  /// 变量加 `v_` 前缀：不会撞上 Go 的关键字（func、type…）和小库的包名。
  @override
  String variable(String name) => 'v_$name';
  @override
  String temp(int slot) => 'lcT$slot';

  /// 小库的函数在 Go 里要大写开头才能跨包用：`lc.DbGet`。
  @override
  String call(String fn, List<String> args) => 'lc.${fn[0].toUpperCase()}${fn.substring(1)}(${args.join(', ')})';

  @override
  String comment(String text) => '// ${beComment(text)}';

  /// 只赋值不读的变量 Go 不让编译（declared and not used），所以声明后跟一句 `_ = 变量`。
  @override
  List<String> declare(String name, String valueCode) => ['var ${variable(name)} any = $valueCode', '_ = ${variable(name)}'];
  @override
  List<String> assign(String name, String valueCode) => ['${variable(name)} = $valueCode'];
  @override
  List<String> let(int slot, String valueCode) => ['${temp(slot)} := $valueCode'];
  @override
  List<String> perform(String callCode) => [callCode];
  @override
  List<String> ifElse(String cond, List<String> then, List<String> orElse) => [
    'if $cond {',
    ...indented(then),
    if (orElse.isNotEmpty) ...['} else {', ...indented(orElse)],
    '}',
  ];
  @override
  List<String> repeat(int n, String timesCode, List<String> body) => ['for lcI$n, lcN$n := 0, $timesCode; lcI$n < lcN$n; lcI$n++ {', ...indented(body), '}'];
  @override
  List<String> forEach(int n, String listCode, String item, List<String> body) => ['for _, lcItem$n := range $listCode {', ...indented(assign(item, 'lcItem$n')), ...indented(body), '}'];
  @override
  List<String> respond(String responseCode) => ['return $responseCode'];

  @override
  String entrySource(BeProgram program) {
    final out = StringBuffer();
    out.writeln('// ${beComment(program.name, 60)} —— 由 LopiCode 后端积木生成（Go）。重新生成会覆盖本文件，要改请回到积木里改。');
    out.writeln('// 启动：go build -o server . && ./server    端口默认 ${program.port}，可以用环境变量 PORT 改。');
    out.writeln('package main');
    out.writeln();
    out.writeln('import "$kGoModuleName/lc"');
    out.writeln();
    for (final s in program.skipped) {
      out.writeln('// 没有生成：${beComment(s)}');
    }
    if (program.skipped.isNotEmpty) out.writeln();
    moduleFunctions(program).forEach(out.writeln);
    for (final r in program.routes) {
      out.writeln('// 接口：${beComment(r.title)}');
      out.writeln('func ${r.fnName}(req *lc.Request) *lc.Response {');
      // 没有“怎么走都会返回”的接口，末尾补一句“什么都不返回”（204）。
      for (final line in indented([...routeBody(r, program), if (!beAlwaysReturns(r.body)) 'return nil'])) {
        out.writeln(line);
      }
      out.writeln('}');
      out.writeln();
    }
    out.writeln('func main() {');
    if (program.collections.isNotEmpty) {
      out.writeln('\t// 数据集合（存在内存里，服务重启就没了）');
      for (final c in program.collections) {
        out.writeln('\tlc.Collection(${literal(c)})');
      }
      out.writeln();
    }
    for (final r in program.routes) {
      out.writeln('\tlc.Route(${literal(r.method)}, ${literal(r.path)}, ${r.fnName})');
    }
    out.writeln('\tlc.Start(${program.port})');
    out.writeln('}');
    return out.toString();
  }

  /// `go` 那一行写保守的版本：小库用到的最新的东西是 Go 1.18 的 `any` 和 `strings.Cut`。
  @override
  Map<String, String> extraFiles(BeProgram program) => {
    'lc/server.go': '${kGoRuntimeServerSource.trim()}\n',
    'lc/fetch.go': '${kGoRuntimeFetchSource.trim()}\n',
    'go.mod': 'module $kGoModuleName\n\ngo 1.18\n',
  };
}
