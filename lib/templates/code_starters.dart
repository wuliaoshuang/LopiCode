/// 纯代码起步模板（“后端 · 代码”）：每种主流语言一个最小可用的 HTTP 服务工程——入口文件 + README + .gitignore。
///
/// 不带积木。`verified`＝有没有在本机实际启动并请求过（test/code_starters_test.dart）；没有的在说明和 README 里如实写明。
library;

import 'package:lopicode/templates/code_starter_sources.dart';
import 'package:lopicode/templates/code_starter_sources_more.dart';

class CodeStarter {
  const CodeStarter({
    required this.id,
    required this.label,
    required this.summary,
    required this.needs,
    required this.entryFile,
    required this.startCommand,
    required this.verified,
    required this.sources,
    required this.gitignore,
    this.portNote,
    this.readyHint = '“后端已启动”那一行',
  });

  /// 语言 id，也是图标的 id（`FileIcon.language`）。
  final String id;

  /// 给人看的名字：“Node.js”。
  final String label;

  /// 用什么写的，一句话。
  final String summary;

  /// 机器上要先有什么。
  final String needs;

  /// 入口文件（相对路径）。
  final String entryFile;

  /// 在工程目录里启动的命令（一整行）。
  final String startCommand;

  /// 有没有在本机实际启动并请求过。
  final bool verified;

  /// 源码文件：相对路径 → 内容。
  final Map<String, String> sources;
  final String gitignore;

  /// 端口不是读环境变量 `PORT` 的语言（PHP 的内置服务器），这里写怎么换端口。
  final String? portNote;

  /// 启动成功时终端里会看到什么（写进 README）。
  final String readyHint;

  /// 这份工程的全部文件：相对路径 → 内容。`name`＝项目名（只进 README）。
  Map<String, String> files(String name) => {for (final e in sources.entries) e.key: '${e.value.trim()}\n', 'README.md': codeStarterReadme(this, name), '.gitignore': '${gitignore.trim()}\n'};
}

/// 全部起步模板，按界面上的顺序。
const List<CodeStarter> codeStarters = [
  CodeStarter(
    id: 'node',
    label: 'Node.js',
    summary: '只用 Node 自带的 node:http，不用装任何包',
    needs: 'Node.js 18 或更新',
    entryFile: 'server.js',
    startCommand: 'node server.js',
    verified: true,
    sources: {'server.js': kStarterNode},
    gitignore: 'node_modules/\n.env\n*.log',
  ),
  CodeStarter(
    id: 'python',
    label: 'Python',
    summary: '只用 Python 标准库的 http.server，不用装任何包',
    needs: 'Python 3.8 或更新',
    entryFile: 'server.py',
    startCommand: 'python3 server.py',
    verified: true,
    sources: {'server.py': kStarterPython},
    gitignore: '__pycache__/\n*.pyc\n.venv/\n.env',
  ),
  CodeStarter(
    id: 'go',
    label: 'Go',
    summary: '只用 Go 标准库的 net/http，不用装任何包',
    needs: 'Go 1.21 或更新',
    entryFile: 'main.go',
    startCommand: 'go run .',
    verified: true,
    sources: {'main.go': kStarterGo, 'go.mod': kStarterGoMod},
    gitignore: '/app\n*.exe\n.env',
  ),
  CodeStarter(
    id: 'java',
    label: 'Java',
    summary: '只用 JDK 自带的 com.sun.net.httpserver，不用装任何包，也不用先编译',
    needs: 'JDK 17 或更新（源码是 UTF-8；JDK 17 上中文乱码的话，启动命令改成 java -Dfile.encoding=UTF-8 Main.java）',
    entryFile: 'Main.java',
    startCommand: 'java Main.java',
    verified: true,
    sources: {'Main.java': kStarterJava},
    gitignore: '*.class\n*.jar\nout/\n.env',
  ),
  CodeStarter(
    id: 'php',
    label: 'PHP',
    summary: '只用 PHP 自带的内置服务器（php -S），不用装任何包',
    needs: 'PHP 8.0 或更新',
    entryFile: 'index.php',
    startCommand: 'php -S 0.0.0.0:8080 index.php',
    verified: false,
    sources: {'index.php': kStarterPhp},
    gitignore: 'vendor/\n.env',
    portNote: '端口写在启动命令里：想换就把命令里的 `8080` 改掉。',
    readyHint: '带 “Development Server” 和 “started” 的那一行',
  ),
  CodeStarter(
    id: 'csharp',
    label: 'C#',
    summary: 'ASP.NET Core 的 Minimal API（.NET SDK 自带）',
    needs: '.NET SDK 8',
    entryFile: 'Program.cs',
    startCommand: 'dotnet run',
    verified: false,
    sources: {'Program.cs': kStarterCsharp, 'app.csproj': kStarterCsproj},
    gitignore: 'bin/\nobj/\n.env',
  ),
  CodeStarter(
    id: 'rust',
    label: 'Rust',
    summary: '只用 Rust 标准库（std::net）手写的最简 HTTP 处理，不用装任何包',
    needs: 'Rust 1.70 或更新（带 cargo）',
    entryFile: 'src/main.rs',
    startCommand: 'cargo run',
    verified: false,
    sources: {'src/main.rs': kStarterRust, 'Cargo.toml': kStarterCargo},
    gitignore: 'target/\n.env',
  ),
  CodeStarter(
    id: 'ruby',
    label: 'Ruby',
    summary: '只用 Ruby 标准库（socket、json）手写的最简 HTTP 处理，不用装任何 gem',
    needs: 'Ruby 3.0 或更新',
    entryFile: 'server.rb',
    startCommand: 'ruby server.rb',
    verified: false,
    sources: {'server.rb': kStarterRuby},
    gitignore: '.bundle/\nvendor/bundle/\n.env',
  ),
  CodeStarter(
    id: 'kotlin',
    label: 'Kotlin',
    summary: '只用 JDK 自带的 com.sun.net.httpserver，不用装任何包',
    needs: 'Kotlin 编译器（kotlinc）和 JDK 17 或更新',
    entryFile: 'Main.kt',
    startCommand: 'kotlinc Main.kt -include-runtime -d app.jar && java -jar app.jar',
    verified: false,
    sources: {'Main.kt': kStarterKotlin},
    gitignore: '*.class\n*.jar\nout/\n.env',
  ),
  CodeStarter(
    id: 'dart',
    label: 'Dart',
    summary: '只用 Dart 自带的 dart:io，不用装任何包',
    needs: 'Dart SDK 3.0 或更新',
    entryFile: 'server.dart',
    startCommand: 'dart run server.dart',
    verified: true,
    sources: {'server.dart': kStarterDart},
    gitignore: '.dart_tool/\n.env',
  ),
];

/// 按 id 找；没有返回 null。
CodeStarter? codeStarterFor(String id) {
  for (final s in codeStarters) {
    if (s.id == id) return s;
  }
  return null;
}

/// 放进 Markdown 标题里的项目名：去掉换行和会搅乱排版的字符。
String starterTitle(String name) {
  final clean = name.replaceAll(RegExp(r'[\x00-\x1f\x7f]+'), ' ').replaceAll(RegExp(r'[`<>|]'), ' ').trim();
  return clean.isEmpty ? '我的后端' : clean;
}

String codeStarterReadme(CodeStarter s, String name) {
  final out = StringBuffer();
  out.writeln('# ${starterTitle(name)}');
  out.writeln();
  out.writeln('${s.label} 的最小 HTTP 服务：${s.summary}。从 `${s.entryFile}` 写起。');
  if (!s.verified) {
    out.writeln();
    out.writeln('> 注意：这份 ${s.label} 起步代码**还没有在真机器上实际运行过**（做模板的机器上没有 ${s.label} 的工具），只检查过结构。跑不起来请照报错改，或者告诉 Agent 帮你看。');
  }
  out.writeln();
  out.writeln('## 需要什么');
  out.writeln();
  out.writeln('- ${s.needs}。');
  out.writeln();
  out.writeln('## 怎么启动');
  out.writeln();
  out.writeln('```');
  out.writeln(s.startCommand);
  out.writeln('```');
  out.writeln();
  out.writeln('在 LopiCode 里：点底部导航的“终端”（第一次用要先在侧边栏“运行环境”里装好 Ubuntu 环境和 ${s.label} 的工具），输入上面的命令。');
  out.writeln('看到${s.readyHint}就好了；想停下来按 Ctrl+C。');
  out.writeln();
  out.writeln('- ${s.portNote ?? '端口默认 8080；想换就先设环境变量 `PORT`，例如 `PORT=3000 ${s.startCommand}`。'}');
  out.writeln('- 手机上的 `localhost` 指的是手机自己：在这台手机上启动的服务，只有这台手机上的浏览器、预览和终端能用 `localhost` 访问到。');
  out.writeln();
  out.writeln('## 接口');
  out.writeln();
  out.writeln('| 方式 | 路径 | 返回 |');
  out.writeln('| --- | --- | --- |');
  out.writeln('| GET | `/` | 一句问候（JSON） |');
  out.writeln('| GET | `/health` | `{"status":"ok"}`，用来看服务还活着没有 |');
  out.writeln();
  out.writeln('别的地址回 404。');
  out.writeln();
  out.writeln('## 用 curl 试一试');
  out.writeln();
  out.writeln('```');
  out.writeln('curl "http://localhost:8080/"');
  out.writeln('curl "http://localhost:8080/health"');
  out.writeln('```');
  return out.toString();
}
