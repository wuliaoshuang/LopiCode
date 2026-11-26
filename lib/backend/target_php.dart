/// PHP 生成器：`server.php`（你的接口，PHP 自带开发服务器的路由脚本）＋ `lc_*.php`（小库）＋ README。只用 PHP 自带的函数。
///
/// 2026-11-26 起在开发机上用 PHP 8.3 真跑：一致性测试（test/backend_conformance_test.dart）和别的语言跑同一份样本，所以 `verified` 是 true。
/// 手机上（Ubuntu 软件源里的 PHP 8.3）还没有验证过。
/// 和别的语言不一样的地方：PHP 每个请求都是从头跑一遍，集合留不在内存里，改成存在工程目录的 `lc_data.json`（加文件锁）；
/// 端口写在启动命令里（`php -S 0.0.0.0:端口 server.php`），不读环境变量。
/// 启动命令前面带 `env PHP_CLI_SERVER_WORKERS=4`：自带的开发服务器默认一次只处理一个请求，
/// “请求别的网址”请求到这个服务自己时会一直等到超时（真跑时撞到的）；开 4 个工作进程就不会。
library;

import 'package:lopicode/backend/backend_ir.dart';
import 'package:lopicode/backend/backend_lang.dart';
import 'package:lopicode/backend/backend_target.dart';
import 'package:lopicode/backend/runtime_php.dart';
import 'package:lopicode/backend/runtime_php_data.dart';
import 'package:lopicode/backend/runtime_php_func.dart';
import 'package:lopicode/backend/runtime_php_json.dart';
import 'package:lopicode/backend/runtime_php_lang.dart';
import 'package:lopicode/backend/runtime_php_server.dart';
import 'package:lopicode/lang/gen.dart';
import 'package:lopicode/lang/gen_php.dart';

/// PHP 的注释：`// …` 碰到 `?>` 就结束了（后面的会被当成网页内容原样输出），所以拆开；`<?` 也顺手拆开。
String phpComment(String text) => beComment(text).replaceAll('?>', '? >').replaceAll('<?', '< ?');

/// `php -S` 开几个工作进程（环境变量 `PHP_CLI_SERVER_WORKERS`，官方手册“Built-in web server”一页；见 docs/api-notes.md）。
const int kPhpServerWorkers = 4;

class PhpBackendTarget extends BeCodeTarget {
  const PhpBackendTarget();

  @override
  String get id => 'php';
  @override
  String get label => 'PHP';
  @override
  String get summary => '只用 PHP 自带的函数和自带的开发服务器（php -S），不用装任何包、不用 Composer（只在 PHP 8.3 上试过；多个工作进程要 PHP 7.4 或更新）；已在本机用 PHP 8.3 真跑验证';
  @override
  String get entryFile => 'server.php';
  @override
  List<String> get startCommand => startCommandFor(8080);
  @override
  List<String> startCommandFor(int port) => ['env', 'PHP_CLI_SERVER_WORKERS=$kPhpServerWorkers', 'php', '-S', '0.0.0.0:$port', 'server.php'];
  @override
  bool get portFromEnv => false;
  @override
  bool get dataInMemory => false;
  @override
  bool get verified => true;
  @override
  String get runtimeFile => 'lc_runtime.php';
  @override
  String get runtimeSource => '${kPhpRuntimeSource.trim()}\n';
  @override
  LangGen langGen(LangHost host) => PhpLangGen(host: host);
  @override
  String get langRuntimeSource => '${kPhpLangRuntimeSource.trim()}\n\n${kPhpLangFuncSource.trim()}\n';
  @override
  String get indentUnit => '    ';
  @override
  List<String> get notes => const [
    '**和别的语言不一样**：PHP 每来一个请求都把 `server.php` 从头跑一遍，内存里留不住东西，所以数据集合存在工程目录下的 `lc_data.json` 文件里（一次请求里第一次用到集合时加独占锁，请求结束才放开）。服务重启数据还在；想清空就删掉这个文件。文件内容坏了会被当成没有数据。',
    '同一时间只有一个请求能用集合（别的排队等锁）。用到集合的接口里“请求别的网址”如果请求的是这个服务自己、而对方那个接口也要用集合，会互相等到超时。',
    'PHP 自带的开发服务器默认一次只处理一个请求，所以启动命令前面带了 `env PHP_CLI_SERVER_WORKERS=$kPhpServerWorkers`（开 $kPhpServerWorkers 个工作进程，PHP 7.4 起支持，Windows 上不支持）。去掉它的话，“请求别的网址”请求到这个服务自己时会一直等到超时。',
    '`php -S` 是 PHP 自带的**开发**服务器，不适合正式对外提供服务；启动后不会打印“后端已启动”，它自己会打印一行监听地址。',
    '“写到日志”写到 `php -S` 所在终端的标准输出；“请求别的网址”要求 php.ini 里 `allow_url_fopen` 是开着的（默认开），请求 https 还要有 openssl 扩展。',
    '这份 PHP 代码在电脑上用 PHP 8.3 跑通过和别的语言同一套测试；手机上的 PHP 还没有验证过，碰到报错请把终端里的错误信息发给 Agent。',
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
    out.writeln('// 启动：${startCommandFor(program.port).join(' ')}    端口写在命令里。');
    // 用到新积木（积木第 4 版）时多引入 lc_lang.php。
    for (final f in ['lc_runtime.php', 'lc_json.php', 'lc_data.php', 'lc_server.php', if (beUsesLang(program)) 'lc_lang.php']) {
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
    moduleFunctions(program).forEach(out.writeln);
    for (final r in program.routes) {
      out.writeln('// 接口：${phpComment(r.title)}');
      out.writeln('function ${r.fnName}(\$req)');
      out.writeln('{');
      for (final line in indented([...routeBody(r, program), if (!beAlwaysReturns(r.body)) 'return null;'])) {
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
