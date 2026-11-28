// “完整流程小应用”（甲组：待办、商品下单、笔记）共用的帮手：多页面文档怎么拼、步骤怎么写（纯网页换页是开另一个文件，
// Vue / React 是改井号后面）、本地假服务（和测试同一个进程，只绑 127.0.0.1）、带时限的真跑（到时间没跑完，连子进程按进程号杀掉）。
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/backend/backend_validate.dart';
import 'package:lopicode/backend/front_code.dart';
import 'package:lopicode/backend/front_doc.dart';
import 'package:lopicode/lang/types.dart';
import 'package:lopicode/lowcode/front_check.dart';
import 'package:lopicode/lowcode/logic_gate.dart';
import 'package:lopicode/lowcode/model.dart';

import 'backend_lang_blocks.dart';
import 'bind_export_files.dart';
import 'dev_tools.dart';
import 'front_libs_samples.dart';
import 'page_front_check.dart';
import 'page_front_samples.dart';
import 'proc_bounded.dart';
import 'typeops_sample.dart';

typedef Steps = List<Map<String, Object?>>;

/// 一页：标识（也是网址里的名字）、控件、状态、页面逻辑。
class AppPage {
  AppPage(this.id, this.children, this.variables, this.front);
  final String id;
  final List<J> children;
  final List<J> variables;
  final J front;

  J _json() => {
    'id': id,
    'title': id,
    'root': node('root', 'page', {'padding': 16, 'gap': 8}, children),
    'logic': {'variables': variables, 'front': front},
  };
}

/// 多页面的文档：头一页是首页。
LcDocument appDoc(List<AppPage> pages) {
  final doc = LcDocument.parse(
    jsonEncode({
      'version': 3,
      ...pages.first._json(),
      'pages': [for (final p in pages.skip(1)) p._json()],
    }),
  );
  for (final p in doc.pages) {
    lcFrontStore(p.logic, lcFrontOf(p.logic)!);
  }
  return doc;
}

/// 一组样例：名字、文档、步骤（按导出种类不同略有出入）、跑完以后对假服务的核对。
class AppCase {
  AppCase(this.name, this.doc, this.steps, {this.after});
  final String name;
  final LcDocument doc;
  final Steps Function(String kind) steps;
  final void Function()? after;
}

// —— 积木的小帮手 ——
const LType _dictAny = LType.dictOf(LType.any);
const LType _listDict = LType.listOf(LType.dictOf(LType.any));
J asDict(J x) => castTo(x, _dictAny);
J asDicts(J x) => castTo(x, _listDict);
J at(J of, String key) => ex('index', {'of': of, 'key': tx(key)});
J lenOf(J x) => ex('len', {'x': x});
J notB(J x) => ex('not', {'x': x});
J lx(String lib, String id, [J args = const {}]) => ex(fl(lib, id), args);
J lb(String lib, String id, [J args = const {}, List<J> body = const []]) => blk(fl(lib, id), args, body);
J goTo(String page) => blk(pg('goPage'), {'page': page});
J goWith(String page, Map<String, J> params) => blk(pg('goPageWith'), {'page': page, 'params': dc(params)});
J param(String name) => ex(pg('pageParam'), {'name': tx(name)});
J mounted(List<J> body) => hat('h0', 'onMounted', body);
J valOf(String id) => prGet(id, 'value');
J forIn(J list, String name, List<J> body) => blk('forIn', {'list': list, 'name': name}, body);
J listVar(String name) => {'name': name, 'type': 'list', 'initial': <Object?>[]};

/// 文字跟着状态走的文字控件；[path]＝“重复”里这一项的哪一栏。
J boundText(String id, String state, [List<String> path = const []]) => node(
  id,
  'text',
  {'text': '-'},
  const [],
  {
    'data': {'text': fromVar(state, path)},
  },
);

/// 一行“重复”：照着列表状态 [list] 一项出一份。
J repeatRow(String id, String list, List<J> children) => node(
  id,
  'row',
  {'gap': 8},
  children,
  {
    'repeat': {'list': fromVar(list), 'item': 'it', 'index': 'i'},
  },
);

// —— 步骤的小帮手 ——
Map<String, Object?> typeIn(String id, String text) => {'op': 'type', 'sel': '.n-$id', 'text': text};
Map<String, Object?> clickAt(String id, int at) => {'op': 'click', 'sel': '.n-$id', 'at': at};
Map<String, Object?> countIs(String id, int n) => {'op': 'count', 'sel': '.n-$id', 'is': n};
Map<String, Object?> textAt(String id, int at, String text) => {'op': 'text', 'sel': '.n-$id', 'at': at, 'is': text};
Map<String, Object?> untilAt(String id, int at, String text) => {'op': 'until', 'sel': '.n-$id', 'at': at, 'is': text};
Map<String, Object?> storedIs(String key, String? text) => {'op': 'stored', 'key': key, 'is': text};
Map<String, Object?> netOn() => {'op': 'net'};

/// 逻辑已经说了“去 [page] 页”以后：纯网页真的打开那一页的文件（jsdom 自己不会换页）；Vue / React 看井号对不对。
/// [home]＝这一页是不是首页。
Steps arrive(String kind, String page, {bool home = false}) => [
  if (kind == 'html') {'op': 'page', 'html': home ? 'index.html' : 'page-$page.html'} else {'op': 'hash', 'is': '#/$page'},
];

/// 关掉再开。纯网页重开的是现在这一页；Vue / React 重开是从首页进。
Steps reopen() => [
  {'op': 'reload'},
];

// —— 检查和真跑 ——
/// 每一页画布上的检查说了什么（积木文档自己的、对着页面才查得出的）；没毛病是空表。
List<String> appIssues(LcDocument doc) {
  final out = <String>[];
  final keep = doc.pageIndex;
  for (var i = 0; i < doc.pages.length; i++) {
    final page = doc.pages[i];
    final front = lcFrontOf(page.logic);
    if (front == null) continue;
    out.addAll([for (final x in validateBackend(front).where((x) => x.isError)) '${page.title}：${x.where} ${x.problem}']);
    out.addAll([for (final x in lcFrontPageIssues(doc, page, front)) '${page.title}：${x.where} ${x.problem}']);
    doc.openPageAt(i);
    final n = lcLogicErrorCount(doc);
    if (n != 0) out.add('${page.title}：导出前的检查数出 $n 处${lcFrontProgram(front).problems.isEmpty ? '' : '（程序出不来：${lcFrontProgram(front).problems.join('；')}）'}');
  }
  doc.openPageAt(keep);
  return out;
}

/// 一组样例在一种导出上：检查没毛病 → 真编译 0 错 0 警告 → 在 jsdom 里把步骤一步不差地走完。
/// 真跑最多 [limit]；到时间没完，连子进程按进程号杀掉、算失败。
Future<void> appCheck(String kind, LcDocument doc, Steps steps, {Duration limit = const Duration(minutes: 3)}) async {
  expect(appIssues(doc), isEmpty);
  final files = exportFilesOf(doc, kind);
  final all = files.values.join('\n');
  expect(all, contains('function lcProgram(lc, lcHost)'), reason: '应该走新路');
  expect(all, isNot(contains('这一页的逻辑没有导出')));
  final entry = frontEntry(kind, files);
  final c = await compileExport('compile_$kind.mjs', files, entry);
  expect(c.errors, isEmpty, reason: c.raw);
  expect(c.warnings, isEmpty, reason: c.raw);
  final dir = Directory.systemTemp.createTempSync('lopi_app_');
  try {
    for (final f in files.entries) {
      File('${dir.path}/${f.key}')
        ..createSync(recursive: true)
        ..writeAsStringSync(f.value);
    }
    File('${dir.path}/.lc-steps.json').writeAsStringSync(jsonEncode(steps));
    final r = await runBounded(
      'node',
      ['${Directory.current.path}/tool/verify/run_dom.mjs', kind, dir.path, entry],
      environment: {'LOPI_WEBDEV': webdevDir!, 'LOPI_WEBDEV_DOM': webdevDomDir!},
      limit: limit,
    );
    final out = '${r.stdout}'.trim();
    expect(out, startsWith('{'), reason: '脚本没有给出结果（退出码 ${r.exitCode}）：${r.stderr}');
    final json = jsonDecode(out) as Map<String, Object?>;
    expect(json['errors'], isEmpty);
    expect(json['warnings'], isEmpty);
    expect(json['done'], steps.length);
    expect(json['ok'], isTrue);
  } finally {
    dir.deleteSync(recursive: true);
  }
}

// —— 本地假服务 ——
/// 一次请求交给处理的人看的样子。
class FakeReq {
  FakeReq(this.method, this.path, this.token, this.body);
  final String method;
  final String path;
  final String token;
  final String body;

  /// 请求里带的 JSON（不是字典就是空的）。
  Map<String, Object?> get json {
    try {
      final v = jsonDecode(body);
      return v is Map<String, Object?> ? v : const {};
    } on FormatException {
      return const {};
    }
  }
}

/// 处理的人交回的：状态码＋要回的东西；[hang]＝拖着不回（等的人超时走了）。
class FakeRes {
  const FakeRes(this.status, this.value, {this.hang = false});
  const FakeRes.hang() : status = 0, value = null, hang = true;
  final int status;
  final Object? value;
  final bool hang;
}

/// 本地假服务：只绑 127.0.0.1、端口系统挑；和测试同一个进程，没有子进程。[stop] 把它和手上没回完的请求一并关掉。
class FakeApi {
  FakeApi._(this._server, this._handle);
  final HttpServer _server;
  final FakeRes Function(FakeReq q) _handle;
  final List<Timer> _hanging = [];

  /// 每条“方式 路径”来了几次。
  final Map<String, int> hits = {};
  String get base => 'http://127.0.0.1:${_server.port}';
  int hit(String what) => hits[what] ?? 0;

  /// 拖着没回的有几个。
  int get hanging => _hanging.length;

  static Future<FakeApi> start(FakeRes Function(FakeReq q) handle) async {
    final api = FakeApi._(await HttpServer.bind(InternetAddress.loopbackIPv4, 0), handle);
    api._server.listen(api._serve);
    return api;
  }

  Future<void> _serve(HttpRequest q) async {
    final body = await utf8.decoder.bind(q).join();
    final what = '${q.method} ${q.uri.path}';
    hits[what] = hit(what) + 1;
    final r = _handle(FakeReq(q.method, q.uri.path, q.headers.value('x-token') ?? '', body));
    if (r.hang) {
      // 拖着不回：收尾时这个定时器会被取消、连接被强行关掉。
      _hanging.add(Timer(const Duration(seconds: 30), () => unawaited(q.response.close())));
      return;
    }
    q.response
      ..statusCode = r.status
      ..headers.contentType = ContentType('application', 'json', charset: 'utf-8')
      ..write(jsonEncode(r.value));
    unawaited(q.response.close());
  }

  Future<void> stop() async {
    for (final t in _hanging) {
      t.cancel();
    }
    await _server.close(force: true);
  }
}

// —— 三个小应用都用的两样 ——
/// 带着登录令牌（存在本地的 [tokenKey] 下）发请求的回应。
J authReq(String tokenKey, String method, J url, {J? data, num timeout = 2000}) => lx('http', 'requestWith', {
  'method': method,
  'url': url,
  'headers': dc({
    'x-token': toText(lx('storage', 'get', {'key': tx(tokenKey), 'orElse': tx('')})),
  }),
  'data': data ?? ex('null'),
  'timeout': nm(timeout),
});
J resOk(String res) => lx('http', 'ok', {'res': vr(res)});
J resJson(String res) => lx('http', 'json', {'res': vr(res)});
J resStatus(String res) => toText(lx('http', 'status', {'res': vr(res)}));

/// 换页的那几步。[wait]＝纯网页要先等旧页面上这一步成立（请求回来、逻辑说了“去”）再开新文件；
/// [ready]＝新页面放好了的记号。Vue / React 是先等新页面的记号，再看井号。
Steps arriveAt(String kind, String page, {Map<String, Object?>? wait, required Map<String, Object?> ready, bool home = false}) =>
    kind == 'html' ? [?wait, ...arrive(kind, page, home: home), ready] : [ready, ...arrive(kind, page, home: home)];
