/// Python 生成器。小库：`lc_runtime.py`（值的规矩）＋ `lc_lang.py`（第 4 版新加的；它把前者的函数也带上，所以代码里都写 `lc.xxx`）。
library;

import 'package:lopicode/lang/gen.dart';
import 'package:lopicode/lang/rt.dart';

class PythonLangGen extends LangGen {
  const PythonLangGen({super.host});

  @override
  String get id => 'python';
  @override
  String get runtimeFile => 'lc_lang.py';
  @override
  String get indentUnit => '    ';

  @override
  String literal(Object? value) => switch (value) {
    null => 'None',
    final bool b => b ? 'True' : 'False',
    final num n => langNumber(n),
    final String s => langQuoted(s),
    _ => 'None',
  };

  /// 小库的函数在 Python 里是下划线写法：`listGet` → `list_get`。
  static String snake(String fn) => fn.replaceAllMapped(RegExp('[A-Z]'), (m) => '_${m[0]!.toLowerCase()}');

  @override
  String coreCall(String fn, List<String> args) => 'lc.${snake(fn)}(${args.join(', ')})';
  @override
  String langCall(String fn, List<String> args) => 'lc.${snake(fn)}(${args.join(', ')})';
  @override
  String comment(String text) => '# ${langComment(text)}';
  @override
  List<String> declare(String name) => ['${variable(name)} = None'];
  @override
  String get end => '';
  @override
  String local(LRet type, String name, String value) => '$name = $value';
  @override
  bool get braces => false;
  @override
  String ifHead(String cond) => 'if $cond';
  @override
  String elseIfHead(String cond) => 'elif $cond';
  @override
  String whileHead(String? cond) => 'while ${cond ?? 'True'}';
  @override
  String countedHead(String k, String n) => 'for $k in range($n)';
  @override
  String get andOp => 'and';
  @override
  String get orOp => 'or';
  @override
  String ternary(String cond, String then, String orElse) => '($then if $cond else $orElse)';
  @override
  String nativeLen(String list) => 'len($list)';
  @override
  String nativeAt(String list, String k) => '$list[$k]';
  @override
  String intToNumber(String k) => 'float($k)';

  @override
  String scriptSource(List<List<String>> bodies) {
    final out = StringBuffer()
      ..writeln('# 由 LopiCode 积木生成（Python）。')
      ..writeln('import lc_lang as lc');
    for (var i = 0; i < bodies.length; i++) {
      out
        ..writeln()
        ..writeln()
        ..writeln('def lc_module${i + 1}():');
      suite(bodies[i]).forEach(out.writeln);
    }
    out
      ..writeln()
      ..writeln();
    for (var i = 0; i < bodies.length; i++) {
      out.writeln('lc_module${i + 1}()');
    }
    return out.toString();
  }
}
