// 自带前端库第一批：故意写错的在检查阶段被拦下（每个库至少三条）。
// 拦下＝导出前的检查数得出错误；纯网页 / Vue 3 / React 三种产物里这一页的逻辑都不出。
// 每组先放一条写对的作对照：同一个页面，只把那一处改对，就不拦。
import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/backend/backend_validate.dart';
import 'package:lopicode/backend/front_code.dart';
import 'package:lopicode/backend/front_doc.dart';
import 'package:lopicode/lowcode/logic_gate.dart';
import 'package:lopicode/lowcode/model.dart';

import 'support/backend_lang_blocks.dart';
import 'support/bind_export_files.dart';
import 'support/front_libs_samples.dart';
import 'support/page_front_samples.dart';

LcDocument _page(List<String> libs, List<J> body, {List<J> hats = const []}) =>
    frontPage([btn('b1', '点'), txt('t1')], [numVar('n')], frontDoc(uses: [for (final l in libs) useLib(l)], hats: [onClick('h1', 'b1', body), ...hats]));

void _blocked(LcDocument doc) {
  expect(lcLogicErrorCount(doc), greaterThan(0));
  for (final kind in const ['html', 'vue', 'react']) {
    final all = exportFilesOf(doc, kind).values.join('\n');
    expect(all, contains('这一页的逻辑没有导出'), reason: kind);
    expect(all, isNot(contains('function lcProgram(lc, lcHost)')), reason: kind);
  }
}

void _fine(LcDocument doc) {
  final front = lcFrontOf(doc.logic)!;
  expect(lcLogicErrorCount(doc), 0, reason: [...backendErrors(front).map((i) => i.message), ...lcFrontProgram(front).problems].join('；'));
  for (final kind in const ['html', 'vue', 'react']) {
    expect(exportFilesOf(doc, kind).values.join('\n'), contains('function lcProgram(lc, lcHost)'), reason: kind);
  }
}

J _x(String lib, String id, [J args = const {}]) => ex(fl(lib, id), args);
J _b(String lib, String id, [J args = const {}, List<J> body = const []]) => blk(fl(lib, id), args, body);

void main() {
  group('定时', () {
    test(
      '对照：写对的不拦',
      () => _fine(
        _page(
          ['timer'],
          [
            _b('timer', 'frame', const {}, [show('t1', tx('好'))]),
          ],
        ),
      ),
    );
    test(
      '毫秒数填了一段字',
      () => _blocked(
        _page(
          ['timer'],
          [
            _b('timer', 'debounce', {'key': tx('搜'), 'ms': tx('很快')}, [show('t1', tx('好'))]),
          ],
        ),
      ),
    );
    test(
      '防抖的名字填了数',
      () => _blocked(
        _page(
          ['timer'],
          [
            _b('timer', 'debounce', {'key': nm(1), 'ms': nm(50)}, [show('t1', tx('好'))]),
          ],
        ),
      ),
    );
    test(
      '没在“积木库…”里用上这个库就拖了它的积木',
      () => _blocked(
        _page(const [], [
          _b('timer', 'frame', const {}, [show('t1', tx('好'))]),
        ]),
      ),
    );
  });

  group('请求', () {
    test(
      '对照：写对的不拦',
      () => _fine(
        _page(
          ['http'],
          [
            show('t1', toText(_x('http', 'getJson', {'url': tx('/a')}))),
          ],
        ),
      ),
    );
    test(
      '拿一个数去问“状态码”',
      () => _blocked(
        _page(
          ['http'],
          [
            show('t1', toText(_x('http', 'status', {'res': nm(3)}))),
          ],
        ),
      ),
    );
    test(
      '再试几次填了一段字',
      () => _blocked(
        _page(
          ['http'],
          [
            show(
              't1',
              toText(
                _x('http', 'status', {
                  'res': _x('http', 'retry', {'url': tx('/a'), 'times': tx('三'), 'gap': nm(10)}),
                }),
              ),
            ),
          ],
        ),
      ),
    );
    test(
      '网址填了数',
      () => _blocked(
        _page(
          ['http'],
          [
            show('t1', toText(_x('http', 'getJson', {'url': nm(8080)}))),
          ],
        ),
      ),
    );
    test(
      '没用上这个库',
      () => _blocked(
        _page(const [], [
          show('t1', toText(_x('http', 'getJson', {'url': tx('/a')}))),
        ]),
      ),
    );
  });

  group('本地保存', () {
    test(
      '对照：写对的不拦',
      () => _fine(
        _page(
          ['storage'],
          [
            _b('storage', 'remove', {'key': tx('草稿')}),
          ],
        ),
      ),
    );
    test(
      '名字填了数',
      () => _blocked(
        _page(
          ['storage'],
          [
            _b('storage', 'remove', {'key': nm(1)}),
          ],
        ),
      ),
    );
    test(
      '“存过吗”拿去当数加',
      () => _blocked(
        _page(
          ['storage'],
          [
            stSet('n', op2('+', _x('storage', 'has', {'key': tx('草稿')}), nm(1))),
          ],
        ),
      ),
    );
    test(
      '“所有名字”（一个列表）拿去当名字删',
      () => _blocked(
        _page(
          ['storage'],
          [
            _b('storage', 'remove', {'key': _x('storage', 'keys')}),
          ],
        ),
      ),
    );
    test(
      '没用上这个库',
      () => _blocked(
        _page(const [], [
          _b('storage', 'remove', {'key': tx('草稿')}),
        ]),
      ),
    );
  });

  group('状态仓库', () {
    test(
      '对照：写对的不拦',
      () => _fine(
        _page(
          ['store'],
          [
            _b('store', 'set', {'store': tx('购物车'), 'key': tx('几件'), 'value': nm(1)}),
          ],
        ),
      ),
    );
    test('“变了以后的仓库”用在“当仓库变了”外面', () => _blocked(_page(['store'], [show('t1', toText(_x('store', 'changed')))])));
    test('“动作带来的”用在“仓库的动作”外面', () => _blocked(_page(['store'], [show('t1', toText(_x('store', 'payload')))])));
    test(
      '仓库名填了数',
      () => _blocked(
        _page(
          ['store'],
          [
            show('t1', toText(_x('store', 'get', {'store': nm(1), 'key': tx('几件')}))),
          ],
        ),
      ),
    );
    test(
      '没用上这个库',
      () => _blocked(
        _page(const [], [
          _b('store', 'set', {'store': tx('购物车'), 'key': tx('几件'), 'value': nm(1)}),
        ]),
      ),
    );
  });

  group('事件总线', () {
    test(
      '对照：写对的不拦',
      () => _fine(
        _page(
          ['bus'],
          [
            _b('bus', 'emit', {'name': tx('好了'), 'value': nm(1)}),
          ],
        ),
      ),
    );
    test('“消息带来的”用在“当收到消息”外面', () => _blocked(_page(['bus'], [show('t1', toText(_x('bus', 'data')))])));
    test(
      '“有几个在听”的消息名填了数',
      () => _blocked(
        _page(
          ['bus'],
          [
            show('t1', toText(_x('bus', 'count', {'name': nm(1)}))),
          ],
        ),
      ),
    );
    test(
      '发消息的名字填了数',
      () => _blocked(
        _page(
          ['bus'],
          [
            _b('bus', 'emit', {'name': nm(1), 'value': nm(1)}),
          ],
        ),
      ),
    );
    test(
      '没用上这个库',
      () => _blocked(
        _page(const [], [
          _b('bus', 'emit', {'name': tx('好了'), 'value': nm(1)}),
        ]),
      ),
    );
  });
}
