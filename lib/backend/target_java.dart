/// Java 生成器：`Main.java`（你的接口）＋ `Lc.java`、`LcJson.java`、`LcServer.java`（小库）＋ README。只用 JDK 自带的东西，
/// 不用 Maven / Gradle，`javac` 直接编译。值在 Java 里一律是 `Object`：`null / Boolean / Double / String / List / Map`。
library;

import 'package:lopicode/backend/backend_ir.dart';
import 'package:lopicode/backend/backend_target.dart';
import 'package:lopicode/backend/runtime_java.dart';
import 'package:lopicode/backend/runtime_java_json.dart';
import 'package:lopicode/backend/runtime_java_lang.dart';
import 'package:lopicode/backend/runtime_java_server.dart';
import 'package:lopicode/lang/gen.dart';
import 'package:lopicode/lang/gen_java.dart';

/// Java 的字符串常量写进 class 文件时最多 65535 字节；超过这么多个字符的文字拆成几段在运行时拼起来。
const int kJavaLiteralChunk = 8000;

/// Java 的双引号字符串字面量：引号、反斜杠加反斜杠，换行类 / 控制字符 / BOM 写成转义（源码里不留原样的）；
/// 太长的拆开用 `String.join` 拼（不能用 `+`：编译器会把常量再拼回去）。
String javaStringLiteral(String s) {
  String quote(String part) => beQuotedWith(part, unicode: beUnicode4);
  final runes = beWellFormed(s).runes.toList();
  if (runes.length <= kJavaLiteralChunk) return quote(s);
  final parts = [for (var i = 0; i < runes.length; i += kJavaLiteralChunk) quote(String.fromCharCodes(runes.skip(i).take(kJavaLiteralChunk)))];
  return 'String.join("", ${parts.join(', ')})';
}

/// Java 的注释：编译器在分词之前就会把 `\uXXXX` 换成字符（`\u000a` 会变成真的换行，把注释后半截变成代码），所以拆开反斜杠和 u。
String javaComment(String text) => beComment(text).replaceAll(r'\u', r'\ u');

class JavaBackendTarget extends BeCodeTarget {
  const JavaBackendTarget();

  static const List<String> _sources = ['Main.java', 'Lc.java', 'LcJson.java', 'LcServer.java'];

  @override
  String get id => 'java';
  @override
  String get label => 'Java';
  @override
  String get summary => '只用 JDK 自带的东西（java.net 的 ServerSocket，JSON 自己带一个小实现），不用 Maven / Gradle、不用装任何包（需要 JDK 11 或更新）；已在本机用 JDK 21 真跑验证';
  @override
  String get entryFile => 'Main.java';
  @override
  List<List<String>> get buildCommands => const [
    ['javac', '-encoding', 'UTF-8', '-d', 'out', ..._sources],
  ];
  @override
  List<String> get startCommand => const ['java', '-cp', 'out', 'Main'];
  @override
  bool get verified => true;
  @override
  String get runtimeFile => 'Lc.java';
  @override
  String get runtimeSource => '${kJavaRuntimeSource.trim()}\n';

  /// `LcLang.java` 不用写进编译命令：`Main.java` 用到它时 javac 会自己在当前目录找到并一起编译。
  @override
  LangGen langGen(LangHost host) => JavaLangGen(host: host);
  @override
  String get langRuntimeSource => '${kJavaLangRuntimeSource.trim()}\n';
  @override
  String get indentUnit => '    ';
  @override
  List<String> get notes => const [
    '不用 Maven / Gradle：上面第一行用 `javac` 把四个 `.java` 文件编译到 `out/` 目录，第二行直接运行。改了积木重新生成后要再编译一次。',
    '没有用 JDK 自带的 `com.sun.net.httpserver`（它会拒掉地址里写法不对的百分号），小库自己读 HTTP 请求：一个连接只处理一个请求，不认分块传输的请求内容。',
    '一个接口翻出来是一个 Java 方法；积木特别多（上千块）时可能超过 Java 单个方法的大小上限而编译不过，那就把接口拆小。',
  ];

  /// 值的规矩里数字都是 Double：没有小数点 / 指数的补上 `.0`（否则会被当成 Integer）。
  @override
  String literal(Object? value) => switch (value) {
    null => 'null',
    final bool b => '$b',
    final num n => _number(n),
    final String s => javaStringLiteral(s),
    _ => 'null',
  };

  static String _number(num n) {
    final text = beNumberLiteral(n);
    return text.contains(RegExp('[.eE]')) ? text : '$text.0';
  }

  /// 变量加 `v_` 前缀：不会撞上 Java 的关键字（class、int、new…）。
  @override
  String variable(String name) => 'v_$name';
  @override
  String temp(int slot) => 'lcT$slot';

  /// “把这些连起来”是不定个数的参数：只有一项而且是 null 时，Java 会把它当成“没有数组”，要写明它是一个值。
  @override
  String call(String fn, List<String> args) => 'Lc.$fn(${fn == 'join' && args.length == 1 && args.single == 'null' ? '(Object) null' : args.join(', ')})';

  @override
  String comment(String text) => '// ${javaComment(text)}';
  @override
  List<String> declare(String name, String valueCode) => ['Object ${variable(name)} = $valueCode;'];
  @override
  List<String> assign(String name, String valueCode) => ['${variable(name)} = $valueCode;'];
  @override
  List<String> let(int slot, String valueCode) => ['final Object ${temp(slot)} = $valueCode;'];
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
  List<String> repeat(int n, String timesCode, List<String> body) => ['for (int lcI$n = 0, lcN$n = $timesCode; lcI$n < lcN$n; lcI$n++) {', ...indented(body), '}'];
  @override
  List<String> forEach(int n, String listCode, String item, List<String> body) => ['for (Object lcItem$n : $listCode) {', ...indented(assign(item, 'lcItem$n')), ...indented(body), '}'];
  @override
  List<String> respond(String responseCode) => ['return $responseCode;'];

  @override
  String entrySource(BeProgram program) {
    final out = StringBuffer();
    out.writeln('// ${javaComment(beComment(program.name, 60))} —— 由 LopiCode 后端积木生成（Java）。重新生成会覆盖本文件，要改请回到积木里改。');
    out.writeln('// 启动：${buildCommands.single.join(' ')} && ${startCommand.join(' ')}');
    out.writeln('// 端口默认 ${program.port}，可以用环境变量 PORT 改。');
    out.writeln('public final class Main {');
    out.writeln('    private Main() {}');
    out.writeln();
    for (final s in program.skipped) {
      out.writeln('    // 没有生成：${javaComment(s)}');
    }
    if (program.skipped.isNotEmpty) out.writeln();
    for (final r in program.routes) {
      out.writeln('    // 接口：${javaComment(r.title)}');
      out.writeln('    static Lc.Response ${r.fnName}(Lc.Request req) {');
      // “怎么走都会返回”的接口后面不能再有代码（Java 不让写执行不到的语句）；其余的末尾补一句“什么都不返回”（204）。
      for (final line in indented(indented([...routeBody(r), if (!beAlwaysReturns(r.body)) 'return null;']))) {
        out.writeln(line);
      }
      out.writeln('    }');
      out.writeln();
    }
    out.writeln('    public static void main(String[] args) {');
    if (program.collections.isNotEmpty) {
      out.writeln('        // 数据集合（存在内存里，服务重启就没了）');
      for (final c in program.collections) {
        out.writeln('        Lc.collection(${literal(c)});');
      }
      out.writeln();
    }
    for (final r in program.routes) {
      out.writeln('        Lc.route(${literal(r.method)}, ${literal(r.path)}, Main::${r.fnName});');
    }
    out.writeln('        Lc.start(${program.port});');
    out.writeln('    }');
    out.writeln('}');
    return out.toString();
  }

  @override
  Map<String, String> extraFiles(BeProgram program) => {'LcJson.java': '${kJavaRuntimeJsonSource.trim()}\n', 'LcServer.java': '${kJavaRuntimeServerSource.trim()}\n'};
}
