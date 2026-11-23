import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:lopicode/core/path_guard.dart';
import 'package:mime/mime.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

class ConsoleEntry {
  ConsoleEntry(this.level, this.message, this.time);
  final String level; // log / info / warn / error
  final String message;
  final DateTime time;
}

/// 应用内的本地 HTTP 服务器：把项目目录当网站根目录，只监听 127.0.0.1。
///
/// HTML 响应里会注入一小段脚本，把页面的 console 输出和未捕获错误
/// POST 回 `/__lopi/console`，供预览页的“控制台”面板显示。
class PreviewServer {
  PreviewServer(String projectDir) : guard = PathGuard(projectDir);

  final PathGuard guard;
  HttpServer? _server;
  final List<ConsoleEntry> logs = [];
  final StreamController<void> _logChanged = StreamController.broadcast();

  static const int maxLogs = 300;
  static const String consolePath = '__lopi/console';

  Stream<void> get onLog => _logChanged.stream;
  bool get isRunning => _server != null;
  int get port => _server?.port ?? 0;
  Uri get baseUri => Uri.parse('http://127.0.0.1:$port/');

  Future<void> start() async {
    if (_server != null) return;
    _server = await shelf_io.serve(_handle, InternetAddress.loopbackIPv4, 0);
  }

  Future<void> stop() async {
    final server = _server;
    _server = null;
    await server?.close(force: true);
  }

  void clearLogs() {
    logs.clear();
    _logChanged.add(null);
  }

  Future<Response> _handle(Request request) async {
    final path = Uri.decodeComponent(request.url.path);
    if (path == consolePath) return _console(request);
    if (request.method != 'GET' && request.method != 'HEAD') {
      return Response(405, body: 'Method Not Allowed');
    }
    final String full;
    try {
      full = guard.resolve(path);
    } on PathGuardException {
      return Response.forbidden('Forbidden');
    }
    var file = File(full);
    if (await FileSystemEntity.isDirectory(full)) {
      file = File('$full/index.html');
    }
    if (!await file.exists()) {
      return Response.notFound(_notFoundPage(path), headers: {'content-type': 'text/html; charset=utf-8'});
    }
    final type = lookupMimeType(file.path) ?? 'application/octet-stream';
    final headers = {
      'content-type': type.startsWith('text/') || type.contains('javascript') || type.contains('json') ? '$type; charset=utf-8' : type,
      // 预览要的是“保存即生效”，一律不缓存。
      'cache-control': 'no-store',
    };
    if (type == 'text/html') {
      final html = await file.readAsString();
      return Response.ok(injectConsoleHook(html), headers: headers);
    }
    return Response.ok(file.openRead(), headers: headers);
  }

  Future<Response> _console(Request request) async {
    if (request.method != 'POST') return Response(405);
    try {
      final body = await request.readAsString();
      if (body.length > 20000) return Response(413);
      final json = jsonDecode(body);
      if (json is Map) {
        final level = const ['log', 'info', 'warn', 'error'].contains(json['level']) ? json['level'] as String : 'log';
        var message = '${json['message'] ?? ''}';
        if (message.length > 2000) message = '${message.substring(0, 2000)}…';
        logs.add(ConsoleEntry(level, message, DateTime.now()));
        if (logs.length > maxLogs) logs.removeRange(0, logs.length - maxLogs);
        _logChanged.add(null);
      }
    } on FormatException {
      return Response(400);
    }
    return Response(204);
  }

  static String _notFoundPage(String path) =>
      '<!DOCTYPE html><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">'
      '<body style="font-family:system-ui;padding:24px;color:#494e62">'
      '<h3 style="margin:0 0 8px">找不到 ${const HtmlEscape().convert(path.isEmpty ? 'index.html' : path)}</h3>'
      '<p style="margin:0;line-height:1.5">预览会打开项目根目录的 index.html。可以在“文件”里新建，或让 Agent 帮你写一个。</p></body>';

  static const String _hook =
      '<script>(function(){'
      'function send(l,a){try{var m=Array.prototype.map.call(a,function(x){'
      'if(x instanceof Error)return x.stack||x.message;'
      'if(typeof x==="object"){try{return JSON.stringify(x)}catch(e){return String(x)}}return String(x)}).join(" ");'
      'fetch("/$consolePath",{method:"POST",headers:{"content-type":"application/json"},body:JSON.stringify({level:l,message:m})}).catch(function(){})}catch(e){}}'
      '["log","info","warn","error"].forEach(function(l){var o=console[l];console[l]=function(){send(l,arguments);o&&o.apply(console,arguments)}});'
      'window.addEventListener("error",function(e){send("error",[e.message+(e.filename?" ("+e.filename.split("/").pop()+":"+e.lineno+")":"")])});'
      'window.addEventListener("unhandledrejection",function(e){send("error",["未处理的 Promise 错误: "+(e.reason&&e.reason.message||e.reason)])});'
      '})();</script>';

  /// 把控制台钩子插到 `<head>` 最前面（没有 head 就放文档最前面），保证比页面脚本先执行。
  static String injectConsoleHook(String html) {
    final match = RegExp(r'<head[^>]*>', caseSensitive: false).firstMatch(html);
    if (match != null) {
      return html.replaceRange(match.end, match.end, _hook);
    }
    final doctype = RegExp(r'^\s*<!doctype[^>]*>', caseSensitive: false).firstMatch(html);
    final at = doctype?.end ?? 0;
    return html.replaceRange(at, at, _hook);
  }
}
