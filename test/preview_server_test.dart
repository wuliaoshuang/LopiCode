import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:lopicode/agent/agent_tools.dart';
import 'package:lopicode/core/path_guard.dart';
import 'package:lopicode/lowcode/model.dart';
import 'package:lopicode/preview/preview_server.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tmp;
  late PreviewServer server;

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('lopi_preview_');
    final proj = Directory(p.join(tmp.path, 'proj'))..createSync();
    File(p.join(tmp.path, 'outside.txt')).writeAsStringSync('TOP SECRET');
    File(p.join(proj.path, 'index.html')).writeAsStringSync('<!DOCTYPE html><html><head><title>t</title></head><body>你好</body></html>');
    File(p.join(proj.path, 'style.css')).writeAsStringSync('body{}');
    Directory(p.join(proj.path, 'js')).createSync();
    File(p.join(proj.path, 'js', 'app.js')).writeAsStringSync('console.log(1)');
    Directory(p.join(proj.path, '.lopicode')).createSync();
    File(p.join(proj.path, '.lopicode', 'chat.json')).writeAsStringSync('[]');
    server = PreviewServer(proj.path);
    await server.start();
  });
  tearDown(() async {
    await server.stop();
    tmp.deleteSync(recursive: true);
  });

  Future<http.Response> get(String path) => http.get(Uri.parse('http://127.0.0.1:${server.port}$path'));

  test('根路径返回 index.html，注入控制台钩子，不缓存', () async {
    final r = await get('/');
    expect(r.statusCode, 200);
    expect(r.headers['content-type'], contains('text/html'));
    expect(r.headers['cache-control'], 'no-store');
    final body = utf8.decode(r.bodyBytes);
    expect(body, contains('你好'));
    expect(body.indexOf('__lopi/console'), greaterThan(body.indexOf('<head>')));
    expect(body.indexOf('__lopi/console'), lessThan(body.indexOf('<title>')));
  });

  test('相对资源按类型返回，原样不改', () async {
    final css = await get('/style.css');
    expect(css.headers['content-type'], contains('text/css'));
    expect(css.body, 'body{}');
    final js = await get('/js/app.js');
    expect(js.headers['content-type'], contains('javascript'));
    expect(js.body, 'console.log(1)');
  });

  test('越界、内部目录、不存在的文件', () async {
    expect((await get('/%2e%2e/outside.txt')).body, isNot(contains('TOP SECRET')));
    expect((await get('/..%2Foutside.txt')).statusCode, isNot(200));
    expect((await get('/.lopicode/chat.json')).statusCode, 403);
    final missing = await get('/nope.html');
    expect(missing.statusCode, 404);
    expect(utf8.decode(missing.bodyBytes), contains('找不到'));
    expect((await http.post(Uri.parse('http://127.0.0.1:${server.port}/index.html'))).statusCode, 405);
  });

  test('控制台日志能收上来，有上限', () async {
    var notified = 0;
    server.onLog.listen((_) => notified++);
    final uri = Uri.parse('http://127.0.0.1:${server.port}/__lopi/console');
    final r = await http.post(uri, body: jsonEncode({'level': 'error', 'message': 'x is not defined'}));
    expect(r.statusCode, 204);
    await http.post(uri, body: jsonEncode({'level': 'weird', 'message': 'm'}));
    expect((await http.post(uri, body: 'not json')).statusCode, 400);
    await Future<void>.delayed(Duration.zero);
    expect(server.logs.map((l) => l.level), ['error', 'log']);
    expect(server.logs.first.message, 'x is not defined');
    expect(notified, 2);
    server.clearLogs();
    expect(server.logs, isEmpty);
  });

  test('没有 head 的 HTML 也能注入', () {
    expect(PreviewServer.injectConsoleHook('<p>x</p>'), startsWith('<script>'));
    final withDoctype = PreviewServer.injectConsoleHook('<!DOCTYPE html><p>x</p>');
    expect(withDoctype, startsWith('<!DOCTYPE html><script>'));
  });

  test('低代码导出的网页能被预览服务器打开', () async {
    await saveLowcodePage(PathGuard(server.guard.root), LcDocument.starter('导出测试'));
    final page = await get('/index.html');
    expect(page.statusCode, 200);
    expect(utf8.decode(page.bodyBytes), contains('导出测试'));
    final css = await get('/style.css');
    expect(css.statusCode, 200);
    expect(css.body, contains('.lc-'));
  });
}
