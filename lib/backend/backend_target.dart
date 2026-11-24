/// 后端代码生成的公共部分：[BackendTarget]（一种语言对外的样子）和 [BeCodeTarget]（照中间形式一句句写代码的公共骨架）。
///
/// **加一种语言要写什么**（照 target_node.dart / target_python.dart 抄一份改）：
/// 1. 运行时小库（一个字符串常量）：实现 backend_ir.dart 里 `kBeRuntimeFns` 的每个函数，外加 `collection`、`route`、`start`
///    （路由匹配、读请求、写响应、CORS、出错兜底）。值的规矩全在这里，必须和别的语言逐字节一致。
/// 2. 一个 `BeCodeTarget` 子类：字面量怎么写、变量 / 临时值叫什么、调小库函数怎么写、七种语句怎么写、整份路由文件怎么拼。
/// 3. 在 backend_targets.dart 的 `backendTargets` 里加一行；在 test/backend_conformance_test.dart 里加一行启动命令，
///    同一套请求脚本就会对着它跑。跑不了的环境（本机没有这种语言）把 `verified` 写成 false。
library;

import 'dart:convert';

import 'package:lopicode/backend/backend_ir.dart';
import 'package:lopicode/backend/backend_model.dart';

/// 一种目标语言。
abstract class BackendTarget {
  const BackendTarget();

  /// 语言 id（存在 `backend.lc.json` 的 `language` 里）：node / python / go / java / php…
  String get id;

  /// 给人看的名字：“Node.js”。
  String get label;

  /// 用什么写的，一句话：“只用 Node 自带的 node:http，不用装任何包”。
  String get summary;

  /// 生成的工程里的入口文件（相对路径）。
  String get entryFile;

  /// 在工程目录里启动服务的命令：`['node', 'server.js']`。
  List<String> get startCommand;

  /// 启动前要先跑的命令（编译等）；不需要就是空表。
  List<List<String>> get buildCommands => const [];

  /// 有没有在本机真的启动过、并通过一致性测试（`test/backend_conformance_test.dart`）。没有的要在界面和 README 里说明。
  bool get verified;

  /// 生成整个小工程：相对路径 → 文件内容。任何输入都不抛异常。
  Map<String, String> generate(BeDocument doc);
}

/// 把不成对的代理项（半个表情符号那种）换成 U+FFFD：写进 UTF-8 文件时它们本来也存不下来，先换掉免得各处表现不一。
String beWellFormed(String s) {
  final out = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    final c = s.codeUnitAt(i);
    if (c >= 0xD800 && c <= 0xDBFF && i + 1 < s.length && s.codeUnitAt(i + 1) >= 0xDC00 && s.codeUnitAt(i + 1) <= 0xDFFF) {
      out.writeCharCode(c);
      out.writeCharCode(s.codeUnitAt(++i));
    } else if (c >= 0xD800 && c <= 0xDFFF) {
      out.writeCharCode(0xFFFD);
    } else {
      out.writeCharCode(c);
    }
  }
  return out.toString();
}

/// 双引号字符串字面量的通用写法（JavaScript、Python、Go、Java 都认）：JSON 的转义（`\"`、`\\`、`\n`、`\u00xx`…），
/// 再把 DEL、U+0085、U+2028、U+2029 也写成 `\uXXXX`（有的编辑器 / 老解析器把它们当换行）。中文等其余字符原样保留，方便人看。
/// 注意：PHP、Kotlin、Ruby 这类双引号里会展开 `$` / `#{}` 的语言不能直接用它。
String beQuoted(String s) => jsonEncode(beWellFormed(s)).replaceAll('\x7f', r'\u007f').replaceAll('\u0085', r'\u0085').replaceAll('\u2028', r'\u2028').replaceAll('\u2029', r'\u2029');

/// 把任意字符串收拾成可以放进一行注释的内容（`// …`、`# …`、`/* … */` 都安全）：
/// 去掉所有换行类 / 控制字符（否则后半截会变成代码）、拆开 `*/`、过长截断。
String beComment(String s, [int limit = 160]) {
  var out = beWellFormed(s).replaceAll(RegExp('[\\x00-\\x1f\\x7f\u0085\u2028\u2029]+'), ' ').replaceAll('*/', '* /').replaceAll('</', '< /').trim();
  final runes = out.runes.toList();
  if (runes.length > limit) out = '${String.fromCharCodes(runes.take(limit))}…';
  // 截断可能正好拼出新的 “*/”；再保险一次。
  return out.replaceAll('*/', '* /');
}

/// 数字字面量的通用写法（JavaScript、Python、Go、Java、PHP 都认）：整数不带小数点，其余用 Dart 的最短写法（`0.5`、`1e-7`、`1.5e+21`）。
/// 负数原样带负号——中间形式里数字只会出现在“函数参数”和“赋值的右边”，不会被别的运算符吃掉。
String beNumberLiteral(num v) {
  if (!v.isFinite) return '0';
  if (v is int || (v == v.roundToDouble() && v.abs() < 1e15)) return '${v.round()}';
  return '$v';
}

/// 照中间形式（backend_ir.dart）一句句写代码的公共骨架。子类只回答“这种语言里这个东西怎么写”。
///
/// 约定：语句函数返回一行行代码，**不带这一层的缩进**（嵌在里面的那几行由子类用 [indented] 缩好）；
/// 模型里来的字符串只通过 [literal] 进代码、只通过 [comment]（内部用 [beComment]）进注释。
abstract class BeCodeTarget extends BackendTarget {
  const BeCodeTarget();

  /// 缩进一层用的空白。
  String get indentUnit => '  ';

  List<String> indented(List<String> lines) => [for (final l in lines) l.isEmpty ? l : '$indentUnit$l'];

  // —— 表达式 ——

  /// 字面量：null / bool / num / String。字符串必须转义到不可能跳出引号。
  String literal(Object? value);

  /// 读变量 `name`（名字一定合乎 `[A-Za-z_][A-Za-z0-9_]*`；要避开关键字就加前缀）。
  String variable(String name);

  /// 读第 `slot` 个临时值。
  String temp(int slot);

  /// “这次请求”在处理函数里叫什么。
  String get request => 'req';

  /// 调运行时小库的函数 `fn`（名字见 `kBeRuntimeFns`），参数已经写好。
  String call(String fn, List<String> args);

  // —— 语句 ——

  /// 一行注释。
  String comment(String text);

  /// 接口开头声明变量并给初始值。
  List<String> declare(String name, String valueCode);

  /// 给变量赋值。
  List<String> assign(String name, String valueCode);

  /// 存临时值（声明 + 赋值）。
  List<String> let(int slot, String valueCode);

  /// 只为了效果调一次函数。
  List<String> perform(String callCode);

  /// 如果…否则…（`orElse` 可能是空的；`then` 也可能是空的）。`cond` 已经是这种语言的布尔。
  List<String> ifElse(String cond, List<String> then, List<String> orElse);

  /// 重复 `timesCode` 次（它已经是整数）。`n` 给循环变量起名用。
  List<String> repeat(int n, String timesCode, List<String> body);

  /// 对 `listCode`（已经是列表）里的每一项：赋给变量 `item` 再做 `body`。
  List<String> forEach(int n, String listCode, String item, List<String> body);

  /// 返回响应，结束这个接口。
  List<String> respond(String responseCode);

  // —— 骨架 ——

  String expression(BeX x) => switch (x) {
    BeXLit(:final value) => literal(value is String ? beWellFormed(value) : value),
    BeXVar(:final name) => variable(name),
    BeXTmp(:final slot) => temp(slot),
    BeXReq() => request,
    BeXCall(:final fn, :final args) => call(fn, [for (final a in args) expression(a)]),
  };

  List<String> statements(List<BeS> list) => [for (final s in list) ..._statement(s)];

  List<String> _statement(BeS s) => switch (s) {
    BeSNote(:final text) => [comment(text)],
    BeSSet(:final name, :final value) => assign(name, expression(value)),
    BeSLet(:final slot, :final value) => let(slot, expression(value)),
    BeSDo(call: final c) => perform(expression(c)),
    BeSIf(:final cond, :final then, :final orElse) => ifElse(expression(cond), statements(then), statements(orElse)),
    BeSRepeat(:final n, :final times, :final body) => repeat(n, expression(times), statements(body)),
    BeSForEach(:final n, :final list, :final item, :final body) => forEach(n, expression(list), item, statements(body)),
    BeSReturn(:final response) => respond(expression(response)),
  };

  /// 一个接口的函数体：先声明用到的变量，再是翻好的积木。不带缩进。
  List<String> routeBody(BeRouteProgram r) => [for (final v in r.variables) ...declare(v.name, literal(beInitialValue(v))), ...statements(r.body)];

  /// 运行时小库的文件名和内容。
  String get runtimeFile;
  String get runtimeSource;

  /// 路由文件（＝[entryFile]）的内容：引入小库、声明集合、每个接口一个函数、最后启动。
  String entrySource(BeProgram program);

  /// 除了入口、小库、README 之外还要带的文件（比如 Go 的 go.mod）。
  Map<String, String> extraFiles(BeProgram program) => const {};

  @override
  Map<String, String> generate(BeDocument doc) {
    final program = lowerBackend(doc);
    return {entryFile: entrySource(program), runtimeFile: runtimeSource, ...extraFiles(program), 'README.md': beReadme(program, this)};
  }
}

String _cmd(List<String> command) => command.join(' ');

/// 生成的工程里的 README：怎么启动、端口、接口清单、要知道的几件事。
String beReadme(BeProgram program, BackendTarget target) {
  final out = StringBuffer();
  final title = beComment(program.name, 60);
  out.writeln('# ${title.isEmpty ? '我的后端' : title}');
  out.writeln();
  out.writeln('由 LopiCode 后端积木生成（${target.label}：${target.summary}）。重新生成会覆盖这些文件，要改请回到积木里改。');
  if (!target.verified) {
    out.writeln();
    out.writeln('> 注意：这种语言的生成结果**还没有在真机器上实际运行过**，只检查过结构。');
  }
  out.writeln();
  out.writeln('## 怎么启动');
  out.writeln();
  out.writeln('```');
  for (final c in target.buildCommands) {
    out.writeln(_cmd(c));
  }
  out.writeln(_cmd(target.startCommand));
  out.writeln('```');
  out.writeln();
  out.writeln('- 端口默认 ${program.port}；想换就先设环境变量 `PORT`，例如 `PORT=3000 ${_cmd(target.startCommand)}`。');
  out.writeln('- 默认所有网卡都能访问（`0.0.0.0`）；只想本机访问就设 `HOST=127.0.0.1`。');
  out.writeln('- 启动后在浏览器或别的程序里访问 `http://localhost:${program.port}` 加下面的路径。');
  out.writeln();
  out.writeln('## 接口');
  out.writeln();
  if (program.routes.isEmpty) {
    out.writeln('（还没有接口）');
  } else {
    out.writeln('| 方式 | 路径 |');
    out.writeln('| --- | --- |');
    for (final r in program.routes) {
      out.writeln('| ${r.method} | `${r.path}` |');
    }
  }
  if (program.skipped.isNotEmpty) {
    out.writeln();
    out.writeln('下面这些接口有问题，没有生成：');
    out.writeln();
    for (final s in program.skipped) {
      out.writeln('- ${beComment(s).replaceAll('|', '/').replaceAll('`', "'")}');
    }
  }
  out.writeln();
  out.writeln('## 要知道的几件事');
  out.writeln();
  if (program.collections.isNotEmpty) {
    out.writeln('- 数据集合（${program.collections.join('、')}）存在内存里：**服务一重启数据就没了**。每条记录自动带数字 `id`，从 1 开始。');
  }
  out.writeln('- 路径里的 `:名字` 是路径参数：`/todos/:id` 能匹配 `/todos/5`。接口按上面的顺序从上到下匹配，先对上的先用。');
  out.writeln('- 没有对上的地址回 404，地址对了但方式不对回 405；接口里没有碰到“返回”积木时回 204（空响应）。');
  out.writeln('- 返回的 JSON 里，对象的字段按名字排序；整数不带小数点。');
  out.writeln('- 所有响应都带 `Access-Control-Allow-Origin: *`，网页可以直接跨域调用。');
  out.writeln('- `${target.entryFile}` 是你的接口（积木翻出来的），其余代码文件是每份工程都一样的小工具，不用改。');
  return out.toString();
}
