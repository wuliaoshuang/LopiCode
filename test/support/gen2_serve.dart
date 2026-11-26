// 规矩版本 2 生成的“开服务”的程序真跑用的小工具：编译、在本机回环地址的一个空闲端口上起服务、
// 一条条发请求（自己写的最简单的 HTTP 客户端，拿到的是原始字节）、最后按进程号关掉服务，交回它写的标准输出。
// 只连 127.0.0.1，不联外网；每一步都有时间上限。
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'gen2_run.dart';

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
    _proc.kill(ProcessSignal.sigterm);
    await _proc.exitCode.timeout(
      const Duration(seconds: 10),
      onTimeout: () {
        _proc.kill(ProcessSignal.sigkill);
        return -1;
      },
    );
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
      final b = await Process.run(exe, args, workingDirectory: dir.path, environment: env, includeParentEnvironment: false).timeout(const Duration(seconds: 600));
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
    final proc = await Process.start(cmd.first, cmd.sublist(1), workingDirectory: dir.path, environment: env, includeParentEnvironment: false);
    final out = <int>[], err = <int>[];
    final started = Completer<String?>();
    final pipes = [
      proc.stdout.forEach((chunk) {
        out.addAll(chunk);
        if (!started.isCompleted) {
          final nl = out.indexOf(10);
          if (nl >= 0) started.complete(utf8.decode(out.sublist(0, nl), allowMalformed: true));
        }
      }),
      proc.stderr.forEach(err.addAll),
    ];
    String? startLine;
    try {
      if (language == 'php') {
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
    } on StateError catch (e) {
      proc.kill(ProcessSignal.sigkill);
      throw StateError('${e.message}\n标准输出：${utf8.decode(out, allowMalformed: true)}\n标准错误：${utf8.decode(err, allowMalformed: true)}');
    }
    return Gen2Server._(proc, port, dir, startLine, out, err, pipes);
  } on Object {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
    rethrow;
  }
}
