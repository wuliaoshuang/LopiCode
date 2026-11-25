/// Go 生成器。小库在包 `lc` 里：`lc/values.go`（值的规矩）＋ `lc/lang.go`（第 4 版新加的）。生成的代码是 gofmt 的规范格式。
///
/// 值一律是 `any`（**按建议先做，可改**：设计稿“问题 2”）：`nil / bool / float64 / string / *lc.List / map[string]any`。
/// 列表是 `*lc.List`（一个指针），这样“在末尾加一项”改的是同一个列表，和别的语言一样。
library;

import 'package:lopicode/lang/gen.dart';
import 'package:lopicode/lang/rt.dart';

class GoLangGen extends LangGen {
  const GoLangGen({super.host, this.module = 'lcbackend'});

  /// 生成的工程的模块名（`go.mod` 里的）；小库在 `模块名/lc`。
  final String module;

  @override
  String get id => 'go';
  @override
  String get runtimeFile => 'lc/lang.go';
  @override
  String get indentUnit => '\t';
  @override
  Map<String, LCap> get caps => {...kLangBaseCaps, 'cond': LCap.runtime};

  /// 数字都带小数点（否则常量会被当成整数）。
  @override
  String literal(Object? value) => switch (value) {
    null => 'nil',
    final bool b => '$b',
    final num n => langNumber(n, dotZero: true),
    final String s => langQuoted(s),
    _ => 'nil',
  };

  static String _up(String fn) => '${fn[0].toUpperCase()}${fn.substring(1)}';

  @override
  String coreCall(String fn, List<String> args) => 'lc.${_up(fn)}(${args.join(', ')})';
  @override
  String langCall(String fn, List<String> args) => 'lc.${_up(fn)}(${args.join(', ')})';
  @override
  String comment(String text) => '// ${langComment(text)}';

  /// 只赋值不读的变量 Go 不让编译，所以声明后跟一句 `_ = 变量`。
  @override
  List<String> declare(String name) => ['var ${variable(name)} any', '_ = ${variable(name)}'];
  @override
  String get end => '';
  @override
  String local(LRet type, String name, String value) => '$name := $value';
  @override
  String ifHead(String cond) => 'if ${_bare(cond)}';
  @override
  String elseIfHead(String cond) => 'else if ${_bare(cond)}';
  @override
  String whileHead(String? cond) => cond == null ? 'for' : 'for ${_bare(cond)}';

  /// 条件最外面那对括号去掉（`(a && b)` → `a && b`）：gofmt 的规范格式里 if / for 的条件不带多余的括号。
  /// 只有开头的 `(` 配的正好是结尾的 `)` 才去；文字字面量里的括号不算。
  static String _bare(String cond) {
    if (!cond.startsWith('(') || !cond.endsWith(')')) return cond;
    var depth = 0;
    var inText = false;
    for (var i = 0; i < cond.length; i++) {
      final c = cond[i];
      if (inText) {
        if (c == r'\') {
          i++;
        } else if (c == '"') {
          inText = false;
        }
      } else if (c == '"') {
        inText = true;
      } else if (c == '(') {
        depth++;
      } else if (c == ')') {
        depth--;
        if (depth == 0 && i != cond.length - 1) return cond;
      }
    }
    return cond.substring(1, cond.length - 1);
  }

  @override
  String countedHead(String k, String n) => 'for $k := 0; $k < $n; $k++';

  /// Go 没有 `?:`：交给小库的 `Pick`，两边包成函数，只算选中的那一边。
  @override
  String ternary(String cond, String then, String orElse) => 'lc.Pick($cond, func() any { return $then }, func() any { return $orElse })';
  @override
  String nativeLen(String list) => 'len($list)';
  @override
  String nativeAt(String list, String k) => '$list[$k]';
  @override
  String intToNumber(String k) => 'float64($k)';

  /// gofmt 的写法：乘法两边不留空格。
  @override
  String stepValue(String a, String k, String s) => '$a + float64($k)*$s';

  @override
  String scriptSource(List<List<String>> bodies) {
    final out = StringBuffer()
      ..writeln('// 由 LopiCode 积木生成（Go）。')
      ..writeln('package main')
      ..writeln()
      ..writeln('import "$module/lc"')
      ..writeln()
      ..writeln('// 没有一块积木时也要用到小库一次，否则 Go 不让编译。')
      ..writeln('var _ = lc.Truthy');
    for (var i = 0; i < bodies.length; i++) {
      out
        ..writeln()
        ..writeln('func lcModule${i + 1}() {');
      indented(bodies[i]).forEach(out.writeln);
      out.writeln('}');
    }
    out
      ..writeln()
      ..writeln('func main() {');
    for (var i = 0; i < bodies.length; i++) {
      out.writeln('\tlcModule${i + 1}()');
    }
    out.writeln('}');
    return out.toString();
  }
}
