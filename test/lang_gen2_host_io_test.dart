// 接通后端文档生成的前置（核心 2·A5 段的第 1 步）：宿主接口补齐到 C 分册 9.1、9.2 的清单——随机字节、请求别的网址、文件五个。
// 五种语言真跑、输出逐字节一样。“请求别的网址”只打这个测试自己在本机回环地址上起的服务（随机端口），每一步都有时间上限，不联外网。
@Tags(['external'])
@Timeout(Duration(minutes: 30))
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/lang/gen2_all.dart';
import 'package:lopicode/lang/host_v2.dart';
import 'package:lopicode/lang/typecheck.dart';

import 'support/gen2_run.dart';
import 'support/proto_lc.dart';

const String _decls = '''
(宿主 random.bytes ((个数 整数)) -> (列表 整数))
(宿主 net.fetch ((方式 文字) (网址 文字) (请求头 (字典 文字)) (内容 (可空 文字)) (超时毫秒 整数)) -> (字典 任意))
(宿主 file.read ((路径 文字)) -> 文字)
(宿主 file.write ((路径 文字) (内容 文字)) -> 空)
(宿主 file.exists ((路径 文字)) -> 是否)
(宿主 file.list ((路径 文字)) -> (列表 文字))
(宿主 file.remove ((路径 文字)) -> 空)
''';

const String _files = '''
(函数 试试 ((名 文字) (做的 (函数 () 文字)))
  (试 (做 (打印 (连 名 "：" (调 做的))))
      (出错时 错误 e (打印 (连 名 " 出错：" (. e 消息))))))
(主
  ; 随机字节
  (设 字节们 (宿 random.bytes 64))
  (设 都对 是)
  (每个 b 字节们 (如果 (或 (< b 0) (> b 255)) (那么 (改 都对 否))))
  (打印 (连 "random.bytes：" (长 字节们) " 个，都在 0 到 255：" 都对 "；1 个：" (长 (宿 random.bytes 1)) "；1024 个：" (长 (宿 random.bytes 1024))))
  (调 试试 "0 个" (λ () (文 (长 (宿 random.bytes 0)))))
  (调 试试 "1025 个" (λ () (文 (长 (宿 random.bytes 1025)))))
  ; 文件
  (打印 (连 "一开始有没有：" (宿 file.exists "data/a.txt") (宿 file.exists "data")))
  (做 (宿 file.write "data/a.txt" "第一版"))
  (做 (宿 file.write "data/a.txt" "你好，文件 😀\\n第二行"))
  (做 (宿 file.write "data/深/一层/b.txt" ""))
  (做 (宿 file.write "data/Z.txt" "z"))
  (做 (宿 file.write "data/中.txt" "中"))
  (打印 (连 "读：" (宿 file.read "data/a.txt") "｜" (宿 file.read "data/深/一层/b.txt") "｜" (宿 file.read "data/中.txt")))
  (打印 (连 "有没有：" (宿 file.exists "data/a.txt") (宿 file.exists "data") (宿 file.exists "data/没有.txt")))
  (打印 (连 "列：" (宿 file.list "data") (宿 file.list "data/深") (宿 file.list "data/深/一层")))
  (做 (宿 file.remove "data/Z.txt"))
  (打印 (连 "删了以后：" (宿 file.list "data") (宿 file.exists "data/Z.txt")))
  (调 试试 "读没有的" (λ () (宿 file.read "data/没有.txt")))
  (调 试试 "读文件夹" (λ () (宿 file.read "data")))
  (调 试试 "读不是文字的" (λ () (宿 file.read "bad.bin")))
  (调 试试 "列没有的" (λ () (文 (宿 file.list "data/没有"))))
  (调 试试 "列文件" (λ () (文 (宿 file.list "data/a.txt"))))
  (调 试试 "删没有的" (λ块 () (做 (宿 file.remove "data/没有.txt")) (返回 "不该到这里")))
  (调 试试 "删文件夹" (λ块 () (做 (宿 file.remove "data/深")) (返回 "不该到这里")))
  (调 试试 "写到文件夹上" (λ块 () (做 (宿 file.write "data/深" "x")) (返回 "不该到这里")))
  (每个 坏 (列 "" "/etc/passwd" "../x.txt" "data/../../x.txt" "C:/x.txt" "data\\\\..\\\\x")
    (调 试试 (连 "路径「" 坏 "」") (λ () (宿 file.read 坏)))
    (调 试试 (连 "写「" 坏 "」") (λ块 () (做 (宿 file.write 坏 "x")) (返回 "不该到这里"))))
  (打印 (连 "带点的名字可以：" (宿 file.exists "data/..a") (宿 file.exists "./data/a.txt"))))
''';

const String _filesWant =
    'random.bytes：64 个，都在 0 到 255：true；1 个：1；1024 个：1024\n'
    '0 个 出错：随机字节的个数要在 1 到 1024 之间\n'
    '1025 个 出错：随机字节的个数要在 1 到 1024 之间\n'
    '一开始有没有：falsefalse\n'
    '读：你好，文件 😀\\n第二行｜｜中\n'
    '有没有：truetruefalse\n'
    '列：["Z.txt","a.txt","中.txt","深"]["一层"]["b.txt"]\n'
    '删了以后：["a.txt","中.txt","深"]false\n'
    '读没有的 出错：读不了文件：没有「data/没有.txt」\n'
    '读文件夹 出错：读不了文件：「data」\n'
    '读不是文字的 出错：读不了文件：「bad.bin」不是 UTF-8 文字\n'
    '列没有的 出错：列不了文件夹：「data/没有」\n'
    '列文件 出错：列不了文件夹：「data/a.txt」\n'
    '删没有的 出错：删不了文件：「data/没有.txt」\n'
    '删文件夹 出错：删不了文件：「data/深」\n'
    '写到文件夹上 出错：写不了文件：「data/深」\n'
    '路径「」 出错：路径不对：只能用工程文件夹里面的相对路径\n'
    '写「」 出错：路径不对：只能用工程文件夹里面的相对路径\n'
    '路径「/etc/passwd」 出错：路径不对：只能用工程文件夹里面的相对路径\n'
    '写「/etc/passwd」 出错：路径不对：只能用工程文件夹里面的相对路径\n'
    '路径「../x.txt」 出错：路径不对：只能用工程文件夹里面的相对路径\n'
    '写「../x.txt」 出错：路径不对：只能用工程文件夹里面的相对路径\n'
    '路径「data/../../x.txt」 出错：路径不对：只能用工程文件夹里面的相对路径\n'
    '写「data/../../x.txt」 出错：路径不对：只能用工程文件夹里面的相对路径\n'
    '路径「C:/x.txt」 出错：路径不对：只能用工程文件夹里面的相对路径\n'
    '写「C:/x.txt」 出错：路径不对：只能用工程文件夹里面的相对路径\n'
    '路径「data\\\\..\\\\x」 出错：路径不对：只能用工程文件夹里面的相对路径\n'
    '写「data\\\\..\\\\x」 出错：路径不对：只能用工程文件夹里面的相对路径\n'
    '带点的名字可以：falsetrue\n';

/// “请求别的网址”的程序：[base] 是测试服务的地址，[dead] 是一个没人听的端口。
String _fetchProgram(String base, int dead) =>
    '''
(函数 头 ((回 (字典 任意)) (名 文字)) -> 文字
  (返回 (文 (取 (转 (字典 任意) (取 回 "headers")) 名))))
(要等函数 发 ((方式 文字) (路 文字) (请求头 (字典 文字)) (内容 (可空 文字)) (超时 整数))
  (试 (做
        (设 回 (宿 net.fetch 方式 (连 "$base" 路) 请求头 内容 超时))
        (打印 (连 方式 " " 路 " → " (取 回 "status") "｜" (调 头 回 "content-type") "｜" (调 头 回 "x-twice") "｜" (取 回 "body"))))
      (出错时 错误 e (打印 (连 方式 " " 路 " 出错：" (. e 消息))))))
(要等函数 直接 ((网址 文字) (超时 整数))
  (试 (做 (设 回 (宿 net.fetch "GET" 网址 (典) 空 超时)) (打印 (连 "不该成功：" (取 回 "status"))))
      (出错时 错误 e (打印 (连 "出错：" (. e 消息))))))
(主
  (设 没头 (字典 文字) (典))
  (调 发 "GET" "/hello" 没头 空 5000)
  (调 发 "GET" "/hello?名=小 明&x=%E4%B8%AD&坏=%zz#片段" 没头 空 5000)
  (调 发 "POST" "/echo" 没头 "内容 😀" 5000)
  (调 发 "POST" "/echo" (典 ("Content-Type" "application/json") ("X-My" "mine") ("User-Agent" "own-agent") ("Content-Length" "999")) "{}" 5000)
  (调 发 "PUT" "/echo" 没头 空 5000)
  (调 发 "PATCH" "/echo" 没头 "p" 5000)
  (调 发 "DELETE" "/echo" 没头 空 5000)
  (调 发 "GET" "/echo" 没头 "GET 带的内容不发" 5000)
  (调 发 "HEAD" "/hello" 没头 空 5000)
  (调 发 "GET" "/status/404" 没头 空 5000)
  (调 发 "GET" "/status/500" 没头 空 5000)
  (调 发 "GET" "/status/204" 没头 空 5000)
  (调 发 "GET" "/redirect" 没头 空 5000)
  (调 发 "GET" "/bad-utf8" 没头 空 5000)
  (调 发 "GET" "/bom" 没头 空 5000)
  (调 发 "GET" "/slow" 没头 空 400)
  (调 发 "get" "/hello" 没头 空 5000)
  (调 发 "TRACE" "/hello" 没头 空 5000)
  (调 发 "GET" "/hello" 没头 空 0)
  (调 直接 "ftp://127.0.0.1/x" 5000)
  (调 直接 "127.0.0.1/x" 5000)
  (调 直接 "file:///etc/passwd" 5000)
  (调 直接 "http://127.0.0.1:$dead/x" 5000)
  (调 直接 "HTTP://127.0.0.1:$dead/x" 5000)
  (打印 "完"))
''';

const String _fetchWant =
    'GET /hello → 200｜text/plain; charset=utf-8｜one, two｜你好\n'
    'GET /hello?名=小 明&x=%E4%B8%AD&坏=%zz#片段 → 200｜text/plain; charset=utf-8｜one, two｜你好\n'
    'POST /echo → 200｜application/json; charset=utf-8｜｜POST|text/plain; charset=utf-8|LopiCode||内容 😀\n'
    'POST /echo → 200｜application/json; charset=utf-8｜｜POST|application/json|own-agent|mine|{}\n'
    'PUT /echo → 200｜application/json; charset=utf-8｜｜PUT||LopiCode||\n'
    'PATCH /echo → 200｜application/json; charset=utf-8｜｜PATCH|text/plain; charset=utf-8|LopiCode||p\n'
    'DELETE /echo → 200｜application/json; charset=utf-8｜｜DELETE||LopiCode||\n'
    'GET /echo → 200｜application/json; charset=utf-8｜｜GET||LopiCode||\n'
    'HEAD /hello → 200｜text/plain; charset=utf-8｜one, two｜\n'
    'GET /status/404 → 404｜text/plain; charset=utf-8｜｜状态 404\n'
    'GET /status/500 → 500｜text/plain; charset=utf-8｜｜状态 500\n'
    'GET /status/204 → 204｜｜｜\n'
    'GET /redirect → 200｜text/plain; charset=utf-8｜one, two｜你好\n'
    'GET /bad-utf8 → 200｜text/plain; charset=utf-8｜｜a\ufffdb\ufffd\n'
    'GET /bom → 200｜text/plain; charset=utf-8｜｜\ufeff带着\n'
    'GET /slow 出错：请求超时了\n'
    'get /hello 出错：请求不了：不认识的方式「get」\n'
    'TRACE /hello 出错：请求不了：不认识的方式「TRACE」\n'
    'GET /hello 出错：请求不了：超时毫秒要大于 0\n'
    '出错：请求不了：网址要以 http:// 或 https:// 开头\n'
    '出错：请求不了：网址要以 http:// 或 https:// 开头\n'
    '出错：请求不了：网址要以 http:// 或 https:// 开头\n'
    '出错：请求不了：连不上\n'
    '出错：请求不了：连不上\n'
    '完\n';

/// 测试自己的服务：只听本机回环地址。记下每个请求的“方式 原样的网址”。
Future<(HttpServer, List<String>)> _testServer() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final seen = <String>[];
  server.listen((req) async {
    seen.add('${req.method} ${req.uri}');
    final res = req.response;
    res.headers.contentType = ContentType('text', 'plain', charset: 'utf-8');
    final path = req.uri.path;
    final body = await utf8.decodeStream(req);
    if (path == '/hello') {
      res.headers.add('X-Twice', 'one');
      res.headers.add('X-Twice', 'two');
      res.add(utf8.encode('你好'));
    } else if (path == '/echo') {
      res.headers.set('Content-Type', 'application/json; charset=utf-8');
      String h(String n) => req.headers.value(n) ?? '';
      res.add(utf8.encode([req.method, h('content-type'), h('user-agent'), h('x-my'), body].join('|')));
    } else if (path.startsWith('/status/')) {
      res.statusCode = int.parse(path.substring(8));
      if (res.statusCode == 204) {
        res.headers.removeAll('content-type');
      } else {
        res.add(utf8.encode('状态 ${res.statusCode}'));
      }
    } else if (path == '/redirect') {
      res.statusCode = 302;
      res.headers.set('Location', '/hello');
    } else if (path == '/bad-utf8') {
      res.add([0x61, 0xFF, 0x62, 0xE4, 0xB8]);
    } else if (path == '/bom') {
      res.add([0xEF, 0xBB, 0xBF, ...utf8.encode('带着')]);
    } else if (path == '/slow') {
      await Future<void>.delayed(const Duration(seconds: 3));
      res.add(utf8.encode('太慢'));
    }
    await res.close();
  });
  return (server, seen);
}

void main() {
  test('宿主接口一共 14 个：C 分册 9.1 的 9 个名字＋9.2 的文件 5 个；要等的是三个；每个都有小库里的名字', () {
    expect(kHostV2.keys.toSet(), {
      'sys.print', 'sys.env', 'time.now', 'time.sleep', 'random.bytes', 'net.fetch', 'http.serve', 'store.read', 'store.update', //
      'file.read', 'file.write', 'file.exists', 'file.list', 'file.remove',
    });
    expect(kHostV2Waits, {'time.sleep', 'http.serve', 'net.fetch'});
    expect(kHostV2Code.keys.toSet(), kHostV2.keys.toSet());
  });

  test('两个程序检查都没有问题', () {
    expect(checkModuleTypes(lcModule(_decls + _files)).errors, isEmpty);
    expect(checkModuleTypes(lcModule(_decls + _fetchProgram('http://127.0.0.1:1', 1))).errors, isEmpty);
  });

  for (final language in kGen2Languages) {
    test('$language：随机字节、文件五个，真跑，输出逐字节一样', () async {
      final skip = gen2SkipReason(language);
      if (skip != null) {
        // ignore: avoid_print — 跳过的原因要让跑测试的人看见
        print('跳过：$skip');
        markTestSkipped(skip);
        return;
      }
      // bad.bin：一个不是 UTF-8 文字的文件，跟着生成的文件一起放进临时目录。
      final files = gen2Files(language, lcModule(_decls + _files));
      final run = await gen2RunFiles(
        language,
        files,
        extra: const {
          'bad.bin': [0x61, 0xFF, 0xFE],
        },
      );
      expect(run.problem, isNull, reason: language);
      expect(utf8.decode(run.stdout), _filesWant, reason: language);
      expect(run.exitCode, 0, reason: language);
    });

    test('$language：请求别的网址（只打本机的测试服务），真跑，输出逐字节一样', () async {
      final skip = gen2SkipReason(language);
      if (skip != null) {
        // ignore: avoid_print — 跳过的原因要让跑测试的人看见
        print('跳过：$skip');
        markTestSkipped(skip);
        return;
      }
      final (server, seen) = await _testServer();
      final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final dead = probe.port;
      await probe.close();
      try {
        final files = gen2Files(language, lcModule(_decls + _fetchProgram('http://127.0.0.1:${server.port}', dead)));
        final run = await gen2RunFiles(language, files);
        expect(run.problem, isNull, reason: language);
        expect(utf8.decode(run.stdout), _fetchWant, reason: language);
        expect(run.exitCode, 0, reason: language);
        // 网址里的空格、中文、写坏的百分号都先转义好了再发；# 后面的不发。
        expect(seen[1], 'GET /hello?%E5%90%8D=%E5%B0%8F%20%E6%98%8E&x=%E4%B8%AD&%E5%9D%8F=%25zz', reason: language);
        expect(seen.where((s) => s.startsWith('TRACE') || s.startsWith('get')), isEmpty, reason: language);
      } finally {
        await server.close(force: true);
      }
    });
  }
}
