/// Java 生成器。小库：`Lc.java`（值的规矩）＋ `LcLang.java`（第 4 版新加的）。只用 JDK 自带的东西，`javac` 直接编译。
///
/// 值一律是 `Object`（**按建议先做，可改**：设计稿“问题 2”）：`null / Boolean / Double / String / List / Map`。
library;

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

  @override
  String scriptSource(List<List<String>> bodies) {
    final out = StringBuffer()
      ..writeln('// 由 LopiCode 积木生成（Java）。')
      ..writeln('public final class $className {')
      ..writeln('    private $className() {}');
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
