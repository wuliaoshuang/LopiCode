// 规矩版本 2 生成的“开服务”的程序真跑用的小工具：编译、在本机回环地址的一个空闲端口上起服务、
// 一条条发请求（自己写的最简单的 HTTP 客户端，拿到的是原始字节）、最后按进程号关掉服务，交回它写的标准输出。
// 只连 127.0.0.1，不联外网；每一步都有时间上限。
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'gen2_run.dart';
import 'proc_bounded.dart';

/// 一个回应：状态码、头（名字小写；同名的用“, ”连起来）、内容的原始字节。
class Gen2Reply {
  const Gen2Reply(this.status, this.headers, this.body);
  final int status;
  final Map<String, String> headers;
  final List<int> body;
}

class Gen2Server {
  Gen2Server._(this._proc, this.port, this._dir, this.startLine, this._out, this._err, this._pipes);
  final Process _proc;

  /// 服务的进程号（测试“有没有杀干净”用）。
  int get pid => _proc.pid;
  final int port;
  final Directory _dir;

  /// “后端已启动：…”那一行（PHP 没有：它的服务是 php -S 起的，不经过程序）。
  final String? startLine;
  final List<int> _out;
  final List<int> _err;
  final List<Future<void>> _pipes;

  String get stderrText => utf8.decode(_err, allowMalformed: true);

  /// 发一个请求，读完整个回应。[body] 是 null＝不带内容。
  Future<Gen2Reply> send(String method, String target, {Map<String, String> headers = const {}, List<int>? body, int seconds = 20}) async {
    final socket = await Socket.connect(InternetAddress.loopbackIPv4, port, timeout: Duration(seconds: seconds));
    try {
      final head = StringBuffer('$method $target HTTP/1.1\r\nHost: 127.0.0.1:$port\r\nConnection: close\r\n');
      headers.forEach((k, v) => head.write('$k: $v\r\n'));
      if (body != null) head.write('Content-Length: ${body.length}\r\n');
      head.write('\r\n');
      socket.add(utf8.encode(head.toString()));
      if (body != null) socket.add(body);
      await socket.flush();
      final raw = BytesBuilder(copy: false);
      await socket.forEach(raw.add).timeout(Duration(seconds: seconds));
      return _parse(raw.takeBytes(), method);
    } finally {
      socket.destroy();
    }
  }

  static Gen2Reply _parse(Uint8List raw, String method) {
    var cut = -1;
    for (var i = 0; i + 3 < raw.length; i++) {
      if (raw[i] == 13 && raw[i + 1] == 10 && raw[i + 2] == 13 && raw[i + 3] == 10) {
        cut = i;
        break;
      }
    }
    if (cut < 0) throw StateError('回应不完整：${utf8.decode(raw, allowMalformed: true)}');
    final lines = latin1.decode(raw.sublist(0, cut)).split('\r\n');
    final status = int.parse(lines.first.split(' ')[1]);
    final headers = <String, String>{};
    for (final l in lines.skip(1)) {
      final c = l.indexOf(':');
      final name = l.substring(0, c).toLowerCase(), value = utf8.decode(latin1.encode(l.substring(c + 1).trim()), allowMalformed: true);
      headers[name] = headers.containsKey(name) ? '${headers[name]}, $value' : value;
    }
    final body = raw.sublist(cut + 4);
    // 不许分块传输；写了 Content-Length 的要和真的内容一样长（HEAD 没有内容，不比）。
    if (headers.containsKey('transfer-encoding')) throw StateError('回应用了分块传输：${headers['transfer-encoding']}');
    final len = headers['content-length'];
    if (len != null && method != 'HEAD' && int.parse(len) != body.length) throw StateError('Content-Length 是 $len，内容实际 ${body.length} 个字节');
    return Gen2Reply(status, headers, body);
  }

  /// 按进程号关掉服务，交回它写到标准输出的每一行（不含“后端已启动”那一行）。
  Future<List<String>> stop() async {
    // 先记下子进程（php -S 的几个工作进程、bash 起的东西）：父进程一退就查不到了，最后按进程号补杀一遍。
    final kids = procDescendants(_proc.pid);
    _proc.kill(ProcessSignal.sigterm);
    await _proc.exitCode.timeout(
      const Duration(seconds: 10),
      onTimeout: () {
        _proc.kill(ProcessSignal.sigkill);
        return -1;
      },
    );
    for (final k in kids) {
      Process.killPid(k, ProcessSignal.sigkill);
    }
    await Future.wait(_pipes).timeout(const Duration(seconds: 10), onTimeout: () => const []);
    _dir.deleteSync(recursive: true);
    final lines = const LineSplitter().convert(utf8.decode(_out, allowMalformed: true));
    return [
      for (final l in lines)
        if (l != startLine) l,
    ];
  }
}

Future<int> _freePort() async {
  final s = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = s.port;
  await s.close();
  return port;
}

Map<String, String> _env(int port) => {
  for (final e in Platform.environment.entries)
    if (e.key != 'JAVA_TOOL_OPTIONS') e.key: e.value,
  'LC_ALL': 'C.UTF-8',
  'GOFLAGS': '-mod=mod',
  'GOPROXY': 'off',
  'GOCACHE': '${Directory.systemTemp.path}/lopi_gen2_gocache',
  'PORT': '$port',
  'HOST': '127.0.0.1',
  // PHP 自带的开发服务器默认一次只接一个请求；接口里“请求别的网址”指回自己时要有第二个进程接（产品里的启动命令也带这一项）。
  'PHP_CLI_SERVER_WORKERS': '4',
};

/// 把 [files] 写进临时目录，按 [language] 编译，起服务，等它能连上。没起成＝抛 StateError（里面是原因）。
/// PHP 用 `php -S 127.0.0.1:端口 main.php` 起（一个请求把程序从头跑一遍）；别的语言直接跑程序，端口、主机经环境变量 PORT、HOST 给。
Future<Gen2Server> gen2Serve(String language, Map<String, String> files, {int seconds = 60}) async {
  final dir = Directory.systemTemp.createTempSync('lopi_gen2_srv_');
  try {
    for (final f in files.entries) {
      File('${dir.path}/${f.key}')
        ..createSync(recursive: true)
        ..writeAsStringSync(f.value);
    }
    final port = await _freePort();
    final env = _env(port);
    Future<void> build(String exe, List<String> args, String what) async {
      final b = await runBounded(exe, args, workingDirectory: dir.path, environment: env, includeParentEnvironment: false, limit: const Duration(seconds: 600));
      if (b.exitCode != 0) throw StateError('$what 没过：${b.stderr}');
    }

    final List<String> cmd;
    switch (language) {
      case 'node':
        cmd = [gen2Tools['node']!, 'main.js'];
      case 'python':
        cmd = [gen2Tools['python']!, 'main.py'];
      case 'php':
        cmd = [gen2Tools['php']!, '-S', '127.0.0.1:$port', 'main.php'];
      case 'go':
        await build(gen2Tools['go']!, ['build', '-o', 'prog', '.'], 'go build');
        cmd = ['${dir.path}/prog'];
      case 'java':
        final sources = [
          for (final f in files.keys)
            if (f.endsWith('.java')) f,
        ];
        await build(gen2Tools['javac']!, ['-J-Xmx256m', '-J-XX:+UseSerialGC', '-encoding', 'UTF-8', '-Xlint:all', '-Werror', '-d', 'out', ...sources], 'javac');
        // 这台开发机的运行环境要这一项，Java 服务请求本机（127.0.0.1）才连得上。
        cmd = [gen2Tools['java']!, '-Xmx256m', '-XX:+UseSerialGC', '-Djava.net.preferIPv4Stack=true', '-cp', 'out', 'Main'];
      default:
        throw StateError('不认识的语言 $language');
    }
    return await _launch(cmd, dir, port, env, php: language == 'php', seconds: seconds);
  } on Object {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
    rethrow;
  }
}

Future<Gen2Server> _launch(List<String> cmd, Directory dir, int port, Map<String, String> env, {required bool php, required int seconds, bool firstLine = true}) async {
  final proc = await Process.start(cmd.first, cmd.sublist(1), workingDirectory: dir.path, environment: env, includeParentEnvironment: false);
  final out = <int>[], err = <int>[];
  final started = Completer<String?>();
  final pipes = [
    proc.stdout.forEach((chunk) {
      out.addAll(chunk);
      if (!started.isCompleted) {
        // firstLine：第一行就得是“后端已启动”；不然等到出现这一行为止（文档有“程序开始时”的话它先写自己的）。
        final lines = utf8.decode(out, allowMalformed: true).split('\n')..removeLast();
        final hit = firstLine ? lines.firstOrNull : lines.where((l) => l.startsWith('后端已启动：')).firstOrNull;
        if (hit != null) started.complete(hit);
      }
    }),
    proc.stderr.forEach(err.addAll),
  ];
  String? startLine;
  try {
    if (php) {
      // php -S 不经过程序，没有“后端已启动”那一行：等端口连得上。
      final deadline = DateTime.now().add(Duration(seconds: seconds));
      while (true) {
        try {
          (await Socket.connect(InternetAddress.loopbackIPv4, port, timeout: const Duration(seconds: 2))).destroy();
          break;
        } on SocketException {
          if (DateTime.now().isAfter(deadline)) throw StateError('等了 $seconds 秒，服务还连不上');
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
      }
    } else {
      final exited = proc.exitCode.then<String?>((code) => throw StateError('服务没起来就退出了（退出码 $code）'));
      startLine = await Future.any([started.future, exited]).timeout(Duration(seconds: seconds), onTimeout: () => throw StateError('等了 $seconds 秒，服务没说“后端已启动”'));
      if (startLine != '后端已启动：http://127.0.0.1:$port') throw StateError('第一行应该是“后端已启动：http://127.0.0.1:$port”，实际是：$startLine');
    }
  } on Object catch (e) {
    // 不管哪种没起成（超时、第一行不对、别的异常）：连子进程一起杀掉，不留在后台占着锁。
    procKillTree(proc);
    throw StateError('${e is StateError ? e.message : e}\n标准输出：${utf8.decode(out, allowMalformed: true)}\n标准错误：${utf8.decode(err, allowMalformed: true)}');
  }
  // 保底：测试在 stop() 之前失败、超时、抛异常时，测试收尾也会把服务连子进程杀掉（已经停了的不碍事）。
  try {
    addTearDown(() => procKillTree(proc));
  } on Object {
    // 不在测试里调用（没有收尾可挂）：由调用的人自己 stop()
  }
  return Gen2Server._(proc, port, dir, startLine, out, err, pipes);
}

/// 一个本机现在空着的端口（文档里写端口的测试用）。
Future<int> gen2FreePort() => _freePort();

/// 照产品给的命令起服务（[dir] 里已经写好了工程）：[build] 每条用 `bash -c` 跑完，再 `bash -c "exec [start]"`。
/// 不设 PORT（端口用文档里写的 [port]），HOST 设成 127.0.0.1；node、python3、php、go、javac、java 所在目录放进 PATH。
Future<Gen2Server> gen2ServeShell(Directory dir, {required List<String> build, required String start, required int port, required bool php, int seconds = 60}) async {
  final env = _env(port)..remove('PORT');
  final bins = {for (final t in gen2Tools.values) ?(t == null ? null : File(t).parent.path)};
  env['PATH'] = [...bins, env['PATH'] ?? '/usr/bin:/bin'].join(':');
  for (final b in build) {
    final r = await runBounded('bash', ['-c', b], workingDirectory: dir.path, environment: env, includeParentEnvironment: false, limit: const Duration(seconds: 600));
    if (r.exitCode != 0) throw StateError('“$b”没过：${r.stderr}');
  }
  return _launch(['bash', '-c', 'exec $start'], dir, port, env, php: php, seconds: seconds, firstLine: false);
}
