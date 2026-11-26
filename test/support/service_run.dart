// 对着一个真起来的严格规矩服务（test/support/gen2_serve.dart）逐条发请求、逐字节比回应。
import 'dart:convert';

import 'backend_conformance.dart';
import 'gen2_serve.dart';

/// 逐条发，返回没对上的（空＝全过）。请求里的 `{self}`、`{port}` 换成这个服务自己的地址、端口。
Future<List<String>> serviceRun(Gen2Server server, List<BeCase> cases) async {
  final wrong = <String>[];
  for (var i = 0; i < cases.length; i++) {
    final c = cases[i];
    final target = (c.target.isEmpty ? '/' : c.target).replaceAll('{self}', 'http://127.0.0.1:${server.port}').replaceAll('{port}', '${server.port}');
    final body = c.bodyBytes ?? (c.body == null ? null : utf8.encode(c.body!));
    final reply = await server.send(c.method, target, headers: c.headers, body: body);
    // Dart 的 utf8.decode 会吃掉开头的隐形字符（BOM）：补回去再比。
    final hasBom = reply.body.length >= 3 && reply.body[0] == 0xEF && reply.body[1] == 0xBB && reply.body[2] == 0xBF;
    final text = '${hasBom ? '\ufeff' : ''}${utf8.decode(reply.body, allowMalformed: true)}';
    final bad = <String>[
      if (reply.status != c.status) '状态码 ${reply.status}（要 ${c.status}）',
      if (reply.headers['content-type'] != c.type) 'Content-Type ${reply.headers['content-type']}（要 ${c.type}）',
      if (c.pattern != null && !RegExp(c.pattern!).hasMatch(text)) '内容 $text（要对上 ${c.pattern}）',
      if (c.pattern == null && text != c.expect) '内容 $text（要 ${c.expect}）',
      if (c.pattern == null && text == c.expect && !_same(reply.body, utf8.encode(c.expect))) '内容逐字节不一样',
    ];
    if (bad.isNotEmpty) wrong.add('第 ${i + 1} 条 ${c.method} ${c.target}：${bad.join('；')}');
  }
  return wrong;
}

bool _same(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
