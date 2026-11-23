import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:lopicode/runtime/linux_runtime.dart';
import 'package:lopicode/terminal/terminal_session.dart';
import 'package:path/path.dart' as p;

/// 本机的小文件服务器：支持 Range，可以模拟中途断线、不支持续传、限速。
class FileServer {
  FileServer._(this._server, this.files);
  final HttpServer _server;
  final Map<String, List<int>> files;
  int? dropAfter;
  bool ignoreRange = false;
  Duration? chunkDelay;

  /// 发到这么多字节后不再发，也不断开（模拟连接卡死）。
  int? stallAfter;
  int requests = 0;
  final List<String> ranges = [];

  int get port => _server.port;
  Uri uri(String path) => Uri.parse('http://127.0.0.1:$port$path');

  static Future<FileServer> start(Map<String, List<int>> files) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final self = FileServer._(server, files);
    server.listen(self._handle);
    return self;
  }

  Future<void> _handle(HttpRequest request) async {
    requests++;
    final data = files[request.uri.path];
    final response = request.response;
    if (data == null) {
      response.statusCode = 404;
      await response.close();
      return;
    }
    var start = 0;
    final range = request.headers.value('range');
    if (range != null) ranges.add(range);
    if (range != null && !ignoreRange) {
      start = int.parse(RegExp(r'bytes=(\d+)-').firstMatch(range)!.group(1)!);
      if (start >= data.length) {
        response.statusCode = 416;
        await response.close();
        return;
      }
      response.statusCode = 206;
      response.headers.set('content-range', 'bytes $start-${data.length - 1}/${data.length}');
    }
    final limit = dropAfter;
    if (limit != null) {
      // 模拟断线：自己写响应头，声明完整长度，只发一部分就掐掉连接。
      final status = response.statusCode == 206 ? '206 Partial Content' : '200 OK';
      final socket = await response.detachSocket(writeHeaders: false);
      socket.add(
        ascii.encode(
          'HTTP/1.1 $status\r\ncontent-length: ${data.length - start}\r\n'
          '${response.statusCode == 206 ? 'content-range: bytes $start-${data.length - 1}/${data.length}\r\n' : ''}\r\n',
        ),
      );
      final end = start + limit > data.length ? data.length : start + limit;
      socket.add(data.sublist(start, end));
      await socket.flush();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      socket.destroy();
      return;
    }
    response.headers.set('accept-ranges', 'bytes');
    response.contentLength = data.length - start;
    var sent = 0;
    try {
      for (var i = start; i < data.length; i += 8192) {
        final end = i + 8192 > data.length ? data.length : i + 8192;
        final stall = stallAfter;
        if (stall != null && sent >= stall) {
          await response.flush();
          await Future<void>.delayed(const Duration(seconds: 20));
          return;
        }
        response.add(data.sublist(i, end));
        sent += end - i;
        await response.flush();
        final delay = chunkDelay;
        if (delay != null) await Future<void>.delayed(delay);
      }
      await response.close();
    } catch (_) {
      // 客户端先断开了
    }
  }

  Future<void> close() => _server.close(force: true);
}

/// 不管请求哪个地址，都改到本机的测试服务器上（保留 Range 头）。
class RedirectingClient extends http.BaseClient {
  RedirectingClient(this.target);
  final Uri target;
  final http.Client _inner = http.Client();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    final copy = http.Request(request.method, target)..headers.addAll(request.headers);
    return _inner.send(copy);
  }

  @override
  void close() => _inner.close();
}

class FakeRuntimeHost implements RuntimeHost {
  FakeRuntimeHost({this.nativeDir, this.free});
  final String? nativeDir;
  final int? free;
  bool keepAlive = false;
  int keepAliveStarts = 0;

  @override
  Future<String?> nativeLibraryDir() async => nativeDir;
  @override
  Future<int?> freeBytes(String path) async => free;
  @override
  Future<void> startKeepAlive(String text) async {
    keepAlive = true;
    keepAliveStarts++;
  }

  @override
  Future<void> stopKeepAlive() async => keepAlive = false;

  @override
  Future<Map<String, String>> deviceInfo() async => const {'手机': 'TestPhone X1', 'Android': '16（API 36）'};
}

/// 假的伪终端进程。
class FakePty implements PtyProcess {
  final StreamController<List<int>> _out = StreamController();
  final Completer<int> _exit = Completer();
  final BytesBuilder _written = BytesBuilder();
  bool killed = false;

  List<int> get written => _written.toBytes();
  void emit(String text) => _out.add(utf8.encode(text));
  void exit(int code) {
    if (!_exit.isCompleted) _exit.complete(code);
  }

  @override
  Stream<List<int>> get output => _out.stream;
  @override
  Future<int> get exitCode => _exit.future;
  @override
  void write(List<int> data) => _written.add(data);
  @override
  void resize(int rows, int columns) {}
  @override
  void kill() {
    killed = true;
    exit(-9);
  }
}

/// 假的原生库目录：libproot.so 是个脚本，把收到的参数和关键环境变量打印出来。
String makeFakeNativeDir(Directory tmp) {
  final dir = Directory(p.join(tmp.path, 'nativelib'))..createSync();
  final proot = File(p.join(dir.path, 'libproot.so'))
    ..writeAsStringSync('#!/bin/sh\necho "ARGS=\$*"\necho "LOADER=\$PROOT_LOADER"\necho "LIBPATH=\$LD_LIBRARY_PATH"\necho "HOSTPATH=\${HOME:-unset}"\n');
  Process.runSync('chmod', ['755', proot.path]);
  File(p.join(dir.path, 'libproot-loader.so')).writeAsStringSync('');
  File(p.join(dir.path, 'libtalloc.so')).writeAsStringSync('talloc');
  File(p.join(dir.path, 'libandroid-shmem.so')).writeAsStringSync('shmem');
  return dir.path;
}

/// 不走下载，直接摆出“已安装”的样子。
void markInstalled(LinuxRuntime runtime) {
  Directory(p.join(runtime.rootfsDir, 'usr', 'bin')).createSync(recursive: true);
  File(p.join(runtime.baseDir, 'rootfs.version')).writeAsStringSync('{"version":"test"}');
}

/// 用系统的 tar 做一个小的“基础系统包”：有普通文件、可执行文件、符号链接、硬链接、超长文件名。
Future<File> makeSampleRootfs(Directory tmp) async {
  final src = Directory(p.join(tmp.path, 'sample'))..createSync();
  Directory(p.join(src.path, 'usr/bin')).createSync(recursive: true);
  Directory(p.join(src.path, 'etc/apt/sources.list.d')).createSync(recursive: true);
  Directory(p.join(src.path, 'usr/share/keyrings')).createSync(recursive: true);
  File(p.join(src.path, 'etc/os-release')).writeAsStringSync('NAME="Ubuntu"\nVERSION_ID="24.04"\n');
  File(p.join(src.path, 'etc/apt/sources.list.d/ubuntu.sources')).writeAsStringSync('URIs: http://ports.ubuntu.com/ubuntu-ports/\n');
  final hello = File(p.join(src.path, 'usr/bin/hello'))..writeAsStringSync('#!/bin/sh\necho hello\n');
  Process.runSync('chmod', ['755', hello.path]);
  Process.runSync('ln', [hello.path, p.join(src.path, 'usr/bin/hello2')]);
  Link(p.join(src.path, 'bin')).createSync('usr/bin');
  Link(p.join(src.path, 'etc/resolv.conf')).createSync('../run/resolv.conf');
  final longDir = Directory(p.join(src.path, 'usr/share/${'d' * 60}/${'e' * 60}'))..createSync(recursive: true);
  File(p.join(longDir.path, '${'f' * 120}.txt')).writeAsStringSync('long');
  // 加一块压不动的数据，让包有几百 KB，下载测试才有“中途”可言。
  var seed = 12345;
  final noise = Uint8List.fromList(List.generate(400000, (_) => (seed = (seed * 1103515245 + 12345) & 0x7fffffff) >> 16 & 0xff));
  File(p.join(src.path, 'usr/share/keyrings/ubuntu-archive-keyring.gpg')).writeAsBytesSync(noise);
  final archive = File(p.join(tmp.path, 'sample-rootfs.tar.gz'));
  final result = await Process.run('tar', ['-czf', archive.path, '-C', src.path, 'etc', 'usr', 'bin']);
  if (result.exitCode != 0) throw StateError('tar 失败：${result.stderr}');
  return archive;
}

/// 手工拼一个 tar 文件头（越界路径测试用）。
Uint8List tarHeader(String name, int size) {
  final h = Uint8List(512);
  void put(int offset, String text) => h.setRange(offset, offset + text.length, ascii.encode(text));
  put(0, name);
  put(100, '0000644\x00');
  put(108, '0000000\x00');
  put(116, '0000000\x00');
  put(124, '${size.toRadixString(8).padLeft(11, '0')}\x00');
  put(136, '00000000000\x00');
  h[156] = 0x30;
  put(257, 'ustar\x0000');
  for (var i = 148; i < 156; i++) {
    h[i] = 0x20;
  }
  final sum = h.fold<int>(0, (a, b) => a + b);
  put(148, '${sum.toRadixString(8).padLeft(6, '0')}\x00 ');
  return h;
}
