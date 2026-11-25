/// Java 生成器。小库：`Lc.java`（值的规矩）＋ `LcLang.java`（第 4 版新加的）。只用 JDK 自带的东西，`javac` 直接编译。
///
/// 值一律是 `Object`（**按建议先做，可改**：设计稿“问题 2”）：`null / Boolean / Double / String / List / Map`。
library;

import 'package:lopicode/lang/ast.dart';
import 'package:lopicode/lang/ast_util.dart';
import 'package:lopicode/lang/gen.dart';
import 'package:lopicode/lang/rt.dart';

/// Java 的字符串常量写进 class 文件时最多 65535 字节；超过这么多个字符的文字拆成几段在运行时拼起来。
const int kLangJavaLiteralChunk = 8000;

class JavaLangGen extends LangGen {
  const JavaLangGen({super.host, this.className = 'Main'});

  /// [script] 生成的类名（文件要叫 `类名.java`）。
  final String className;

  @override
  String get id => 'java';
  @override
  String get runtimeFile => 'LcLang.java';
  @override
  String get indentUnit => '    ';

  /// 数字都带小数点（否则会被当成 Integer）。太长的文字拆开用 `String.join` 拼（不能用 `+`：编译器会把常量再拼回去）。
  @override
  String literal(Object? value) => switch (value) {
    null => 'null',
    final bool b => '$b',
    final num n => langNumber(n, dotZero: true),
    final String s => _string(s),
    _ => 'null',
  };

  static String _string(String s) {
    final runes = s.runes.toList();
    if (runes.length <= kLangJavaLiteralChunk) return langQuoted(s);
    final parts = [for (var i = 0; i < runes.length; i += kLangJavaLiteralChunk) langQuoted(String.fromCharCodes(runes.skip(i).take(kLangJavaLiteralChunk)))];
    return 'String.join("", ${parts.join(', ')})';
  }

  /// 个数不定的参数只有一项时，Java 可能把它当成“整个数组”（比如只有一个 null）：写明它是一个值。
  static String _args(String fn, List<String> args) {
    final variadic = (kLangRtFns[fn] ?? kLangCoreFns[fn])?.variadic ?? false;
    return variadic && args.length == 1 ? '(Object) ${args.single}' : args.join(', ');
  }

  @override
  String coreCall(String fn, List<String> args) => 'Lc.$fn(${_args(fn, args)})';
  @override
  String langCall(String fn, List<String> args) => 'LcLang.$fn(${_args(fn, args)})';

  /// 编译器在分词之前就会把 `\uXXXX` 换成字符（`\u000a` 会变成真的换行），所以注释里拆开反斜杠和 u。
  @override
  String comment(String text) => '// ${langComment(text).replaceAll(r'\u', r'\ u')}';
  @override
  List<String> declare(String name) => ['Object ${variable(name)} = null;'];

  @override
  String local(LRet type, String name, String value) {
    final t = switch (type) {
      LRet.number => 'double',
      LRet.nativeInt => 'int',
      LRet.nativeList => 'java.util.List<Object>',
      LRet.bool => 'boolean',
      LRet.text => 'String',
      _ => 'Object',
    };
    return 'final $t $name = $value;';
  }

  /// “一直重复”不能写 `while (true)`：后面要是还有语句，Java 会说执行不到、编译不过。
  @override
  String whileHead(String? cond) => 'while (${cond ?? 'Lc.truthy(true)'})';
  @override
  String countedHead(String k, String n) => 'for (int $k = 0; $k < $n; $k++)';
  @override
  String ternary(String cond, String then, String orElse) => '($cond ? (Object) $then : (Object) $orElse)';
  @override
  String nativeLen(String list) => '$list.size()';
  @override
  String nativeAt(String list, String k) => '$list.get($k)';
  @override
  String intToNumber(String k) => '(double) $k';

  // —— 函数 ——

  @override
  Map<String, LCap> get caps => {...kLangBaseCaps, 'closures': LCap.lowered};
  @override
  bool get nativeDefaults => false;
  @override
  bool get argsByList => true;
  @override
  bool get boxesCaptured => true;
  @override
  bool get renamesShadows => true;

  /// lambda 里的变量不许和外面的重名：里层的改叫 `v2_名字`（数字是套了几层）。
  @override
  String shadowName(String name, int depth) => 'v${depth}_$name';

  /// lambda 只能用“不再改的”外层变量：被里层函数用到的变量装进一格的盒子（`Object[]`），读写都是 `名字[0]`。
  @override
  String boxed(String code) => '$code[0]';
  @override
  List<String> declareIn(LangScope scope, String name) => [scope.boxed.contains(name) ? 'final Object[] ${localCode(scope, name)} = {null};' : 'Object ${localCode(scope, name)} = null;'];
  @override
  List<String> globalDecl(String code) => ['static Object $code = null;'];
  @override
  String fnWrap(String name, int min, int max, String impl) => 'LcLang.fn(${literal(name)}, $min, $max, $impl)';

  /// 参数是不定个数的：只有一个时写明它是一个值（见 [_args]）。
  @override
  String fnCall(String f, List<String> args) => 'LcLang.call(${[f, if (args.length == 1) '(Object) ${args.single}' else ...args].join(', ')})';
  @override
  String argAt(String args, int i, LParam p) => p.rest
      ? 'LcLang.rest($args, $i)'
      : p.defaultValue == null
      ? 'LcLang.arg($args, $i)'
      : 'LcLang.argOr($args, $i, ${literal(p.defaultValue!.value)})';

  /// 有名字的函数是静态方法。要装盒子的参数：参数本身改叫 `lcP_名字`，开头装进盒子。
  @override
  List<String> funcDecl(String fname, List<LParam> params, LangScope scope, List<String> body) => [
    'static Object $fname(${[for (final p in params) 'Object ${scope.boxed.contains(p.name) ? 'lcP_${p.name}' : localCode(scope, p.name)}'].join(', ')}) {',
    ...indented(body),
    '}',
  ];
  @override
  List<String> lambdaDef(String tmp, List<LParam> params, LangScope scope, List<String> body, List<String> uses, String args) => [
    'final Lc.Fn $tmp = LcLang.fn("", ${lMinArgs(params)}, ${lMaxArgs(params)}, ($args) -> {',
    ...indented(body),
    '});',
  ];
  @override
  String lambdaShort(List<LParam> params, LangScope scope, String code, List<String> uses, String args) => '($args) -> $code';
  @override
  String namedImpl(LFuncDecl f, String fname) => '(lcA) -> $fname(${[for (var i = 0; i < f.params.length; i++) argAt('lcA', i, f.params[i])].join(', ')})';

  @override
  List<String> paramPreamble(List<LParam> params, LangScope scope, String? args) => [
    for (var i = 0; i < params.length; i++)
      if (args != null)
        scope.boxed.contains(params[i].name)
            ? 'final Object[] ${localCode(scope, params[i].name)} = {${argAt(args, i, params[i])}};'
            : 'Object ${localCode(scope, params[i].name)} = ${argAt(args, i, params[i])};'
      else if (scope.boxed.contains(params[i].name))
        'final Object[] ${localCode(scope, params[i].name)} = {lcP_${params[i].name}};',
  ];

  @override
  String scriptSource(List<List<String>> bodies, {List<String> top = const []}) {
    final out = StringBuffer()
      ..writeln('// 由 LopiCode 积木生成（Java）。')
      ..writeln('public final class $className {')
      ..writeln('    private $className() {}');
    if (top.isNotEmpty) out.writeln();
    indented(top).forEach(out.writeln);
    for (var i = 0; i < bodies.length; i++) {
      out
        ..writeln()
        ..writeln('    static void lcModule${i + 1}() {');
      indented(indented(bodies[i])).forEach(out.writeln);
      out.writeln('    }');
    }
    out
      ..writeln()
      ..writeln('    public static void main(String[] args) {');
    for (var i = 0; i < bodies.length; i++) {
      out.writeln('        lcModule${i + 1}();');
    }
    out
      ..writeln('    }')
      ..writeln('}');
    return out.toString();
  }
}
