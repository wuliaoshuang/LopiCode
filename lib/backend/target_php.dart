/// PHP 生成器：`server.php`（你的接口，PHP 自带开发服务器的路由脚本）＋ `lc_*.php`（小库）＋ README。只用 PHP 自带的函数。
///
/// **没有在真机器上实际运行过**（本机没有 php），只做结构检查，所以 `verified` 是 false。
/// 和别的语言不一样的地方：PHP 每个请求都是从头跑一遍，集合留不在内存里，改成存在工程目录的 `lc_data.json`（加文件锁）；
/// 端口写在启动命令里（`php -S 0.0.0.0:端口 server.php`），不读环境变量。
library;

import 'package:lopicode/backend/backend_ir.dart';
import 'package:lopicode/backend/backend_target.dart';
import 'package:lopicode/backend/runtime_php.dart';
import 'package:lopicode/backend/runtime_php_data.dart';
import 'package:lopicode/backend/runtime_php_json.dart';
import 'package:lopicode/backend/runtime_php_server.dart';

/// PHP 的注释：`// …` 碰到 `?>` 就结束了（后面的会被当成网页内容原样输出），所以拆开；`<?` 也顺手拆开。
String phpComment(String text) => beComment(text).replaceAll('?>', '? >').replaceAll('<?', '< ?');

class PhpBackendTarget extends BeCodeTarget {
  const PhpBackendTarget();

  @override
  String get id => 'php';
  @override
  String get label => 'PHP（未实际运行）';
  @override
  String get summary => '只用 PHP 自带的函数和自带的开发服务器（php -S），不用装任何包、不用 Composer（估计需要 PHP 7.4 或更新）；本机没有 php，生成结果未实际运行、只检查过结构';
  @override
  String get entryFile => 'server.php';
  @override
  List<String> get startCommand => startCommandFor(8080);
  @override
  List<String> startCommandFor(int port) => ['php', '-S', '0.0.0.0:$port', 'server.php'];
  @override
  bool get portFromEnv => false;
  @override
  bool get dataInMemory => false;
  @override
  bool get verified => false;
  @override
  String get runtimeFile => 'lc_runtime.php';
  @override
  String get runtimeSource => '${kPhpRuntimeSource.trim()}\n';
  @override
  String get indentUnit => '    ';
  @override
  List<String> get notes => const [
    '**和别的语言不一样**：PHP 每来一个请求都把 `server.php` 从头跑一遍，内存里留不住东西，所以数据集合存在工程目录下的 `lc_data.json` 文件里（一次请求里第一次用到集合时加独占锁，请求结束才放开）。服务重启数据还在；想清空就删掉这个文件。文件内容坏了会被当成没有数据。',
    '同一时间只有一个请求能用集合（别的排队等锁）。用到集合的接口里“请求别的网址”如果请求的是这个服务自己，会互相等到超时——PHP 自带的开发服务器默认一次只处理一个请求。',
    '`php -S` 是 PHP 自带的**开发**服务器，不适合正式对外提供服务；启动后不会打印“后端已启动”，它自己会打印一行监听地址。',
    '“写到日志”写到 `php -S` 所在终端的标准输出；“请求别的网址”要求 php.ini 里 `allow_url_fopen` 是开着的（默认开），请求 https 还要有 openssl 扩展。',
    '这份 PHP 代码**还没有实际运行过**，可能有写错的地方；碰到报错请把终端里的错误信息发给 Agent。',
  ];

  /// 数字都写成带小数点的（PHP 里 `1` 是整数、`1.0` 才是浮点数，`===` 比较时两者不相等）。
  @override
  String literal(Object? value) => switch (value) {
    null => 'null',
    final bool b => '$b',
    final num n => _number(n),
    // 双引号里 `$` 会被当成变量，要加反斜杠；控制字符写成 \u{…}（PHP 7 起支持）。
    final String s => beQuotedWith(s, escape: r'$', unicode: beUnicodeBraced),
    _ => 'null',
  };

  static String _number(num n) {
    final text = beNumberLiteral(n);
    return text.contains(RegExp('[.eE]')) ? text : '$text.0';
  }

  /// 变量加 `v_` 前缀（PHP 的变量本来就带 `$`，不会撞关键字；加前缀是为了不撞 `$req`、`$this` 这些）。
  @override
  String variable(String name) => '\$v_$name';
  @override
  String temp(int slot) => '\$lcT$slot';
  @override
  String get request => r'$req';

  /// 小库的函数都是 `lc_` 开头的全局函数。
  @override
  String call(String fn, List<String> args) => 'lc_$fn(${args.join(', ')})';

  @override
  String comment(String text) => '// ${phpComment(text)}';
  @override
  List<String> declare(String name, String valueCode) => assign(name, valueCode);
  @override
  List<String> assign(String name, String valueCode) => ['${variable(name)} = $valueCode;'];
  @override
  List<String> let(int slot, String valueCode) => ['${temp(slot)} = $valueCode;'];
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
  List<String> repeat(int n, String timesCode, List<String> body) => ['for (\$lcI$n = 0, \$lcN$n = $timesCode; \$lcI$n < \$lcN$n; \$lcI$n++) {', ...indented(body), '}'];
  @override
  List<String> forEach(int n, String listCode, String item, List<String> body) => ['foreach ($listCode as \$lcItem$n) {', ...indented(assign(item, '\$lcItem$n')), ...indented(body), '}'];
  @override
  List<String> respond(String responseCode) => ['return $responseCode;'];

  @override
  String entrySource(BeProgram program) {
    final out = StringBuffer();
    out.writeln('<?php');
    out.writeln('// ${phpComment(beComment(program.name, 60))} —— 由 LopiCode 后端积木生成（PHP）。重新生成会覆盖本文件，要改请回到积木里改。');
    out.writeln('// 启动：${startCommandFor(program.port).join(' ')}    端口写在命令里。注意：PHP 版还没有实际运行过。');
    for (final f in ['lc_runtime.php', 'lc_json.php', 'lc_data.php', 'lc_server.php']) {
      out.writeln("require_once __DIR__ . '/$f';");
    }
    out.writeln();
    if (program.collections.isNotEmpty) {
      out.writeln('// 数据集合（存在 lc_data.json 文件里，服务重启数据还在）');
      for (final c in program.collections) {
        out.writeln('lc_collection(${literal(c)});');
      }
      out.writeln();
    }
    for (final s in program.skipped) {
      out.writeln('// 没有生成：${phpComment(s)}');
    }
    if (program.skipped.isNotEmpty) out.writeln();
    for (final r in program.routes) {
      out.writeln('// 接口：${phpComment(r.title)}');
      out.writeln('function ${r.fnName}(\$req)');
      out.writeln('{');
      for (final line in indented([...routeBody(r), if (!beAlwaysReturns(r.body)) 'return null;'])) {
        out.writeln(line);
      }
      out.writeln('}');
      out.writeln();
      out.writeln("lc_route(${literal(r.method)}, ${literal(r.path)}, '${r.fnName}');");
      out.writeln();
    }
    out.writeln('lc_start();');
    return out.toString();
  }

  @override
  Map<String, String> extraFiles(BeProgram program) => {
    'lc_json.php': '${kPhpRuntimeJsonSource.trim()}\n',
    'lc_data.php': '${kPhpRuntimeDataSource.trim()}\n',
    'lc_server.php': '${kPhpRuntimeServerSource.trim()}\n',
  };
}
