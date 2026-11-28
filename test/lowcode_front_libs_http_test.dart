// 自带前端库“请求”的样例：三组，纯网页、Vue 3、React 三种导出真编译 0 错 0 警告，逻辑在 Node＋jsdom 里对着本地假服务真跑
// （只绑 127.0.0.1，不出本机）。结束、失败、超时三种收场都试到；假服务和它手上没回完的请求在收尾时一并关掉。
@Tags(['external'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'support/backend_core_samples.dart';
import 'support/backend_lang_blocks.dart';
import 'support/dev_tools.dart';
import 'support/front_libs_samples.dart';
import 'support/page_front_check.dart';
import 'support/page_front_samples.dart';

/// 本地假服务：/num、/missing、/echo、/slow（拖着不回）、/flaky（头两次 500）、/count（每次加一）。
class _Fake {
  _Fake(this.server);
  final HttpServer server;
  final List<Timer> timers = [];
  final Map<String, int> hits = {};
  String get base => 'http://127.0.0.1:${server.port}';

  static Future<_Fake> start() async {
    final f = _Fake(await HttpServer.bind(InternetAddress.loopbackIPv4, 0));
    f.server.listen(f._serve);
    return f;
  }

  Future<void> _serve(HttpRequest q) async {
    final path = q.uri.path;
    final n = hits[path] = (hits[path] ?? 0) + 1;
    final body = await utf8.decoder.bind(q).join();
    void reply(int status, String text) {
      q.response
        ..statusCode = status
        ..headers.contentType = ContentType('application', 'json', charset: 'utf-8')
        ..write(text);
      unawaited(q.response.close());
    }

    switch (path) {
      case '/num':
        reply(200, '42');
      case '/echo':
        reply(200, jsonEncode('${q.method} $body ${q.headers.contentType?.mimeType ?? '-'}'));
      case '/head':
        reply(200, jsonEncode('${q.headers.value('x-token') ?? '-'} ${q.headers.contentType?.mimeType ?? '-'}'));
      case '/slow':
        // 拖着不回：等的人超时走了；收尾时这个定时器会被取消、连接被强行关掉。
        timers.add(Timer(const Duration(seconds: 20), () => reply(200, '1')));
      case '/flaky':
        n <= 2 ? reply(500, '"坏了"') : reply(200, '"好了"');
      case '/count':
        reply(200, '$n');
      default:
        reply(404, '"没有"');
    }
  }

  Future<void> stop() async {
    for (final t in timers) {
      t.cancel();
    }
    await server.close(force: true);
  }
}

J _get(String url) => ex(fl('http', 'getJson'), {'url': tx(url)});
J _req(String method, String url, {J? data, num timeout = 0}) => ex(fl('http', 'request'), {'method': method, 'url': tx(url), 'data': data ?? ex('null'), 'timeout': nm(timeout)});
J _caught(String node, List<J> body) => tryB(body, [
  catchArm('错误', 'e', [show(node, getF(vr('e'), '消息'))]),
]);

List<FrontLibSample> _samples(String base, String dead) => [
  FrontLibSample(
    '取 JSON：成功、回应没成功、连不上',
    frontPage(
      [btn('b1', '取'), btn('b2', '没有的'), btn('b3', '连不上'), txt('t1'), txt('t2'), txt('t3')],
      const [],
      frontDoc(
        uses: [useLib('http')],
        hats: [
          onClick('h1', 'b1', [show('t1', toText(_get('$base/num')))]),
          onClick('h2', 'b2', [
            _caught('t2', [show('t2', toText(_get('$base/missing')))]),
          ]),
          onClick('h3', 'b3', [
            _caught('t3', [show('t3', toText(_get('$dead/num')))]),
          ]),
        ],
      ),
    ),
    [
      {'op': 'net'},
      click('b1'),
      untilText('t1', '42'),
      click('b2'),
      untilText('t2', '请求没成功：状态码 404'),
      click('b3'),
      untilText('t3', '请求不了：连不上'),
    ],
  ),
  FrontLibSample(
    '发请求：带上东西、状态码和正文、成功吗、超时',
    frontPage(
      [btn('b1', '发'), btn('b2', '慢的'), btn('b3', '没有的'), btn('b4', '带头'), txt('t1'), txt('t2'), txt('t3'), txt('t4')],
      const [],
      frontDoc(
        uses: [useLib('http')],
        hats: [
          onClick('h1', 'b1', [
            let('res', _req('POST', '$base/echo', data: dc({'a': nm(1)}))),
            show(
              't1',
              cat([
                toText(ex(fl('http', 'status'), {'res': vr('res')})),
                tx(' '),
                toText(ex(fl('http', 'json'), {'res': vr('res')})),
              ]),
            ),
          ]),
          onClick('h2', 'b2', [
            _caught('t2', [let('res', _req('GET', '$base/slow', timeout: 150)), show('t2', tx('不该到这里'))]),
          ]),
          onClick('h4', 'b4', [
            let(
              'res',
              ex(fl('http', 'requestWith'), {
                'method': 'POST',
                'url': tx('$base/head'),
                'headers': dc({'x-token': tx('abc123'), 'content-type': tx('text/plain')}),
                'data': dc({'a': nm(1)}),
                'timeout': nm(0),
              }),
            ),
            show('t4', toText(ex(fl('http', 'json'), {'res': vr('res')}))),
          ]),
          onClick('h3', 'b3', [
            let('res', _req('GET', '$base/missing')),
            iff(
              ex(fl('http', 'ok'), {'res': vr('res')}),
              [show('t3', tx('成功'))],
              orElse: [
                show(
                  't3',
                  cat([
                    tx('没成功 '),
                    ex(fl('http', 'body'), {'res': vr('res')}),
                  ]),
                ),
              ],
            ),
          ]),
        ],
      ),
    ),
    [
      {'op': 'net'},
      click('b1'),
      untilText('t1', '200 POST {"a":1} application/json'),
      click('b4'),
      untilText('t4', 'abc123 text/plain'),
      click('b2'),
      untilText('t2', '超时'),
      click('b3'),
      untilText('t3', '没成功 "没有"'),
    ],
  ),
  FrontLibSample(
    '不成再试、几秒内用上次的、加载到状态',
    frontPage(
      [btn('b1', '再试'), btn('b2', '记着取'), btn('b3', '忘掉'), btn('b4', '加载'), btn('b5', '加载坏的'), txt('t1'), txt('t2'), txt('t4')],
      [numVar('d'), textVar('er'), numVar('ld')],
      frontDoc(
        uses: [useLib('http')],
        hats: [
          onClick('h1', 'b1', [
            let('res', ex(fl('http', 'retry'), {'url': tx('$base/flaky'), 'times': nm(3), 'gap': nm(10)})),
            show(
              't1',
              cat([
                toText(ex(fl('http', 'status'), {'res': vr('res')})),
                tx(' '),
                toText(ex(fl('http', 'json'), {'res': vr('res')})),
              ]),
            ),
          ]),
          onClick('h2', 'b2', [
            show(
              't2',
              cat([
                tx('第 '),
                toText(ex(fl('http', 'cached'), {'url': tx('$base/count'), 'seconds': nm(600)})),
              ]),
            ),
          ]),
          onClick('h3', 'b3', [
            blk(fl('http', 'forget'), {'url': tx('$base/count')}),
            show('t2', tx('忘了')),
          ]),
          onClick('h4', 'b4', [
            blk(fl('http', 'load'), {'url': tx('$base/num'), 'data': tx('d'), 'loading': tx('ld'), 'error': tx('er')}),
            show('t4', cat([toText(stGet('d')), tx('/'), toText(stGet('er')), tx('/'), toText(stGet('ld'))])),
          ]),
          onClick('h5', 'b5', [
            blk(fl('http', 'load'), {'url': tx('$base/missing'), 'data': tx('d'), 'loading': tx('ld'), 'error': tx('er')}),
            show('t4', cat([toText(stGet('d')), tx('/'), toText(stGet('er')), tx('/'), toText(stGet('ld'))])),
          ]),
        ],
      ),
    ),
    [
      {'op': 'net'},
      click('b1'),
      untilText('t1', '200 好了'),
      click('b2'),
      untilText('t2', '第 1'),
      click('b3'),
      untilText('t2', '忘了'),
      click('b2'),
      untilText('t2', '第 2'),
      click('b2'),
      waitMs(150),
      textIs('t2', '第 2'),
      click('b4'),
      untilText('t4', '42//false'),
      click('b5'),
      untilText('t4', '42/请求没成功：状态码 404/false'),
    ],
  ),
];

void main() {
  late _Fake fake;
  late String dead;
  setUp(() async {
    fake = await _Fake.start();
    // 一个肯定没人听的端口：开一下拿到号，马上关掉。
    final s = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    dead = 'http://127.0.0.1:${s.port}';
    await s.close();
  });
  tearDown(() => fake.stop());

  for (final kind in kFrontKinds.entries) {
    test(
      '“请求”库·${kind.value}：三组样例对着本地假服务真编译、真跑',
      () async {
        final samples = _samples(fake.base, dead);
        expect(samples.length, greaterThanOrEqualTo(3));
        for (final s in samples) {
          await frontCheckAll(kind.key, s.doc, [s.steps]);
        }
        // 不成再试：头两次 500、第三次才成，一共去了三次。几秒内用上次的：五次点击只真的去了两次。
        expect(fake.hits['/flaky'], 3);
        expect(fake.hits['/count'], 2);
        // 超时的那一次：等的人走了，假服务手上还拖着一个没回的。
        expect(fake.timers.length, 1);
      },
      skip: skipWithoutDom,
      timeout: const Timeout(Duration(minutes: 6)),
    );
  }
}
