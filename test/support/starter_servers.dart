// 模板测试的支撑：在临时目录里把一个小服务真的起起来（随机端口、只绑 / 只连 127.0.0.1），请求几下，按 pid 杀掉。
//
// 规矩：不联网、不装包；机器上没有对应工具的用例由调用方跳过并打印原因；结束只杀自己起的那个进程（`Process.kill`），
// 绝不按名字杀进程。
import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// 找得到这个命令吗。
Future<bool> toolExists(String exe, [List<String> versionArgs = const ['--version']]) async {
  try {
    final r = await Process.run(exe, versionArgs).timeout(const Duration(seconds: 30));
    return r.exitCode == 0;
  } on Exception {
    return false;
  }
}

/// Go 命令在哪：先看 PATH，再看环境变量 `LOPI_GO`，再看这台机器上装的位置。都没有返回 null。
Future<String?> findGoTool() async {
  final home = Platform.environment['HOME'] ?? '';
  for (final exe in ['go', ?Platform.environment['LOPI_GO'], if (home.isNotEmpty) '$home/workspace/tools/gosdk/go/bin/go']) {
    if (await toolExists(exe, const ['version'])) return exe;
  }
  return null;
}

/// 跑 Go 要带的环境变量：缓存放工程的 `.tmp/` 下（`/tmp` 太小），不许联网。
Map<String, String> goOfflineEnv() {
  final base = '${Directory.current.path}/.tmp';
  return {'GOCACHE': '$base/gocache', 'GOPATH': '$base/gopath', 'GOFLAGS': '-mod=mod', 'GOPROXY': 'off', 'GOSUMDB': 'off', 'GOTOOLCHAIN': 'local', 'GOWORK': 'off', 'CGO_ENABLED': '0'};
}

/// 把一组文件写进一个新的临时目录。用完自己删。
Directory writeTempProject(Map<String, String> files, String prefix) {
  final dir = Directory.systemTemp.createTempSync(prefix);
  for (final f in files.entries) {
    File('${dir.path}/${f.key}')
      ..createSync(recursive: true)
      ..writeAsStringSync(f.value);
  }
  return dir;
}

typedef HttpReply = ({int status, String? contentType, String body, String? cors});

class RunningServer {
  RunningServer(this.process, this.port, this.stderrText, this._subs);

  final Process process;
  final int port;
  final StringBuffer stderrText;
  final List<StreamSubscription<String>> _subs;

  /// 发一个请求（只连 127.0.0.1）。`target` 是路径加参数，原样发出去。
  Future<HttpReply> send(String method, String target, {Object? json}) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final req = await client.openUrl(method, Uri.parse('http://127.0.0.1:$port$target'));
      req.persistentConnection = false;
      if (json != null) {
        final bytes = utf8.encode(jsonEncode(json));
        req.headers.set('Content-Type', 'application/json');
        req.contentLength = bytes.length;
        req.add(bytes);
      }
      final res = await req.close().timeout(const Duration(seconds: 20));
      final body = await res.transform(const Utf8Decoder(allowMalformed: true)).join().timeout(const Duration(seconds: 20));
      return (status: res.statusCode, contentType: res.headers.value('content-type'), body: body, cors: res.headers.value('access-control-allow-origin'));
    } finally {
      client.close(force: true);
    }
  }

  /// 只杀自己起的这个进程。
  Future<void> stop() async {
    process.kill(ProcessSignal.sigkill);
    await process.exitCode.timeout(const Duration(seconds: 10), onTimeout: () => -1);
    for (final s in _subs) {
      await s.cancel();
    }
  }
}

/// 在 `dir` 里用 `command` 起服务（`PORT=0`、`HOST=127.0.0.1`），等它打印 `后端已启动：http://127.0.0.1:端口`。
Future<RunningServer> startServer(Directory dir, List<String> command, {Map<String, String> environment = const {}, Duration wait = const Duration(seconds: 90)}) async {
  final process = await Process.start(command.first, command.sublist(1), workingDirectory: dir.path, environment: {...environment, 'PORT': '0', 'HOST': '127.0.0.1'});
  final ready = Completer<int>();
  final err = StringBuffer();
  final subs = [
    process.stdout.transform(const Utf8Decoder(allowMalformed: true)).transform(const LineSplitter()).listen((line) {
      final m = RegExp(r'^后端已启动：http://127\.0\.0\.1:([0-9]+)$').firstMatch(line);
      if (!ready.isCompleted && m != null) ready.complete(int.parse(m[1]!));
    }, onError: (_) {}), // 进程被杀时管道断开，不用管
    process.stderr.transform(const Utf8Decoder(allowMalformed: true)).transform(const LineSplitter()).listen(err.writeln, onError: (_) {}), // 同上
  ];
  unawaited(
    process.exitCode.then((code) {
      if (!ready.isCompleted) ready.completeError(StateError('服务没起来就退出了（$code）：\n$err'));
    }),
  );
  try {
    final port = await ready.future.timeout(wait);
    return RunningServer(process, port, err, subs);
  } on Object {
    process.kill(ProcessSignal.sigkill);
    for (final s in subs) {
      await s.cancel();
    }
    rethrow;
  }
}
