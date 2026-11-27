/// 严格规矩（规矩版本 2）的后端文档用的“生成器”：对外还是 [BackendTarget] 的样子（入口文件、启动命令、README），
/// 里面走的是“接口服务”库那条路（backend_to_service.dart 的 `beServiceGenerate`）。
///
/// 和宽松规矩的生成器不一样的地方：入口文件叫 main.*（宽松的叫 server.*，Go / Java 两边都叫 main.go / Main.java），
/// 小库叫 lc2.*（Go 在 lc/ 目录里，Java 是 Lc.java、LcHost.java、LcTask.java）。启动命令照旧一行。
library;

import 'package:lopicode/backend/backend_core_gen.dart';
import 'package:lopicode/backend/backend_model.dart';
import 'package:lopicode/backend/backend_target.dart';
import 'package:lopicode/backend/backend_to_service.dart';
import 'package:lopicode/backend/target_php.dart' show kPhpServerWorkers;

/// 严格规矩的工程里固定会有的文件（不算分出去的模块文件）。换语言、换规矩时拿它认“上一种留下的文件”。
const Map<String, List<String>> kBeStrictFiles = {
  'node': ['main.js', 'lc2.js'],
  'python': ['main.py', 'lc2.py'],
  'php': ['main.php', 'lc2.php'],
  'go': ['main.go', 'go.mod', 'lc/lc.go', 'lc/host.go', 'lc/more.go', 'lc/io.go', 'lc/task.go'],
  'java': ['Main.java', 'Lc.java', 'LcHost.java', 'LcTask.java'],
};

/// 运行时出了错（除以 0、类型不对这些）回给对方的内容。
const String kBeStrictFailedBody = '{"error":"服务器内部出错"}';

class StrictBackendTarget extends BackendTarget {
  const StrictBackendTarget(this.base);

  /// 同一种语言宽松规矩的生成器（名字、说明借它的）。
  final BackendTarget base;

  @override
  String get id => base.id;

  @override
  String get label => base.label;

  @override
  String get summary => base.summary;

  @override
  String get entryFile => kBeStrictFiles[id]?.first ?? base.entryFile;

  @override
  List<String> get startCommand => startCommandFor(8080);

  @override
  List<String> startCommandFor(int port) => switch (id) {
    'node' => const ['node', 'main.js'],
    'python' => const ['python3', 'main.py'],
    'php' => ['env', 'PHP_CLI_SERVER_WORKERS=$kPhpServerWorkers', 'php', '-S', '0.0.0.0:$port', 'main.php'],
    'go' => const ['./server'],
    'java' => const ['java', '-cp', 'out', 'Main'],
    _ => base.startCommandFor(port),
  };

  @override
  List<List<String>> get buildCommands => switch (id) {
    'go' => const [
      ['go', 'build', '-o', 'server', '.'],
    ],
    'java' => const [
      ['javac', '-encoding', 'UTF-8', '-d', 'out', '*.java'],
    ],
    _ => const [],
  };

  @override
  bool get portFromEnv => id != 'php';

  /// PHP 的数据存在临时目录的文件里，但文件跟着服务进程走：服务一重启也是空的，所以对用户说的话和别的语言一样。
  @override
  bool get dataInMemory => true;

  @override
  bool get verified => true;

  @override
  List<String> get notes => [
    '这份积木用的是**严格规矩**：除以 0、整数算出界、拿空值去算、类型对不上这些，运行时不再悄悄当成 0，而是这一次请求回 500 和 `$kBeStrictFailedBody`，原因写在终端的日志里。',
    if (id == 'php') ...[
      'PHP 每来一个请求都把 `main.php` 从头跑一遍，所以数据集合放在系统临时目录的一个文件里（文件名带服务进程的编号）；服务重启以后是新的文件，数据从空开始。',
      'PHP 自带的开发服务器默认一次只处理一个请求，所以启动命令前面带了 `env PHP_CLI_SERVER_WORKERS=$kPhpServerWorkers`。`php -S` 是开发用的服务器，不适合正式对外；启动后不会打印“后端已启动”，它自己会打印一行监听地址。',
    ],
    if (id == 'java') '编译出来的东西在 `out/` 目录里；改了积木重新生成以后要再编译一次。',
    if (id == 'go') '编译出来的程序叫 `server`；改了积木重新生成以后要再编译一次。',
    '手机上还没有验证过；在电脑上五种语言跑的是同一套 135 条测试，结果逐字节一样。',
  ];

  /// 出不来代码时的原因；出得来是 null。
  String? problem(BeDocument doc) => _gen(doc).problem;

  /// 整个小工程。出不来（积木有错、翻不成）时是空表——调用方先问 [problem]。
  @override
  Map<String, String> generate(BeDocument doc) {
    final files = _gen(doc).files;
    if (files == null) return const {};
    return {...files, 'README.md': beStrictReadme(doc, this)};
  }

  /// 没有接口、只有“程序开始时”、又只用了语言核心的文档是一个跑完就结束的程序（backend_core_gen.dart）；别的都是服务。
  /// 记着上一次的结果：重新生成一次会先问 [problem] 再要 [generate]，不用翻两遍。
  BeServiceGen _gen(BeDocument doc) {
    final key = '$id\n${doc.encode()}';
    final last = _last;
    if (last != null && last.$1 == key) return last.$2;
    BeServiceGen out = (files: null, problem: null);
    if (beIsCoreProgram(doc)) {
      final core = beCoreGenerate(doc, id);
      if (core.files != null) out = (files: core.files, problem: null);
    }
    if (out.files == null) out = beServiceGenerate(doc, id);
    _last = (key, out);
    return out;
  }

  static (String, BeServiceGen)? _last;
}

/// 这份严格文档生成出来是不是“跑完就结束的程序”（不开服务）。
bool beStrictIsPlainProgram(BeDocument doc, String language) => beIsCoreProgram(doc) && beCoreGenerate(doc, language).files != null;

String _cmd(List<String> command) => command.join(' ');

/// 严格规矩工程的 README：怎么启动、端口、接口清单、要知道的几件事（和宽松规矩那份同一个章法）。
String beStrictReadme(BeDocument doc, BackendTarget target) {
  final out = StringBuffer();
  final title = beComment(doc.name, 60);
  out.writeln('# ${title.isEmpty ? '我的后端' : title}');
  out.writeln();
  out.writeln('由 LopiCode 后端积木生成（${target.label}，严格规矩：${target.summary}）。重新生成会覆盖这些文件，要改请回到积木里改。');
  out.writeln();
  final plain = beStrictIsPlainProgram(doc, target.id);
  if (plain) {
    out.writeln('这份积木没有接口，只有“程序开始时”，也没用到数据集合、请求这些：它是一个**跑完就结束的程序**，不开服务。下面讲端口、接口的几条对它不适用。');
    out.writeln();
  }
  out.writeln('## 怎么启动');
  out.writeln();
  out.writeln('```');
  final start = _cmd(target.startCommandFor(doc.port));
  for (final c in target.buildCommands) {
    out.writeln(_cmd(c));
  }
  out.writeln(start);
  out.writeln('```');
  out.writeln();
  if (target.portFromEnv) {
    out.writeln('- 端口默认 ${doc.port}；想换就先设环境变量 `PORT`，例如 `PORT=3000 $start`。');
    out.writeln('- 默认所有网卡都能访问（`0.0.0.0`）；只想本机访问就设 `HOST=127.0.0.1`。');
  } else {
    out.writeln('- 端口是 ${doc.port}，写在启动命令里；想换就改命令里的数字。');
    out.writeln('- 默认所有网卡都能访问（`0.0.0.0`）；只想本机访问就把命令里的 `0.0.0.0` 换成 `127.0.0.1`。');
  }
  out.writeln('- 启动后在浏览器或别的程序里访问 `http://localhost:${doc.port}` 加下面的路径。');
  out.writeln();
  out.writeln('## 接口');
  out.writeln();
  final skipped = beServiceProgram(doc).skipped;
  if (doc.routes.isEmpty) {
    out.writeln('（还没有接口）');
  } else {
    out.writeln('| 方式 | 路径 |');
    out.writeln('| --- | --- |');
    for (final r in doc.routes) {
      out.writeln('| ${beComment(r.method, 12).replaceAll('|', '/')} | `${beComment(r.path).replaceAll('|', '/').replaceAll('`', "'")}` |');
    }
  }
  if (skipped.isNotEmpty) {
    out.writeln();
    out.writeln('下面这些接口有问题，没有生成：');
    out.writeln();
    for (final s in skipped) {
      out.writeln('- ${beComment(s).replaceAll('|', '/').replaceAll('`', "'")}');
    }
  }
  out.writeln();
  out.writeln('## 要知道的几件事');
  out.writeln();
  if (doc.collections.isNotEmpty) {
    out.writeln('- 数据集合（${doc.collections.map((c) => beComment(c.name, 40)).join('、')}）不存盘：**服务一重启数据就没了**。每条记录自动带数字 `id`，从 1 开始。');
  }
  for (final n in target.notes) {
    out.writeln('- $n');
  }
  out.writeln('- 路径里的 `:名字` 是路径参数：`/todos/:id` 能匹配 `/todos/5`。接口按上面的顺序从上到下匹配，先对上的先用。');
  out.writeln('- 没有对上的地址回 404，地址对了但方式不对回 405；接口里没有碰到“返回”积木时回 204（空响应）。');
  out.writeln('- 返回的 JSON 里，对象的字段按名字排序；整数不带小数点。');
  out.writeln('- 所有响应都带 `Access-Control-Allow-Origin: *`，网页可以直接跨域调用。');
  out.writeln('- `${target.entryFile}` 是你的积木翻出来的代码；一个模块一个文件：“接口服务”库和你分出去的模块各有一个名字带模块名的文件，内置的错误种类也单独一个。其余代码文件是每份工程都一样的小工具，不用改。');
  return out.toString();
}
