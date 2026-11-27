// 新的页面逻辑的样例（接 page_front_samples.dart）：“要等的事”、用了“都行”库和前端库的页面，
// 以及每种形状多出来的几组步骤（每种形状至少三组）。
import 'package:lopicode/backend/front_doc.dart';
import 'package:lopicode/lang/lib_model.dart';
import 'package:lopicode/lowcode/model.dart';

import 'backend_core_samples.dart';
import 'backend_lang_blocks.dart';
import 'backend_wait_sample.dart';
import 'page_core_samples.dart';
import 'page_front_samples.dart';

typedef Steps = List<Map<String, Object?>>;

Map<String, Object?> _click(String id, [int? at]) => {'op': 'click', 'sel': '.n-$id', 'at': ?at};
Map<String, Object?> _text(String id, String want) => {'op': 'text', 'sel': '.n-$id', 'is': want};
Map<String, Object?> _type(String id, String text) => {'op': 'type', 'sel': '.n-$id', 'text': text};
Map<String, Object?> _wait(int ms) => {'op': 'wait', 'ms': ms};
Map<String, Object?> _count(String id, int n) => {'op': 'count', 'sel': '.n-$id', 'is': n};

// —— 样例一（函数＋闭包＋类＋错误）的三组步骤 ——
List<Steps> frontStepSetsCore() => [
  frontStepsCore(),
  [
    // 先闭包（n 还是 3），再阶乘两回，再闭包（n 变了）
    _click('b4'), _text('t4', '103'),
    _click('b1'), _text('t1', 'n=6'),
    _click('b4'), _text('t4', '106'),
    _type('in1', '8'), _click('b3'), _text('t3', '商是 1.25'),
  ],
  [
    // 出错的路先走，再走对的；类每点一次都是新的一个
    _type('in1', '0'), _click('b3'), _text('t3', '出错：不能除以零'),
    _type('in1', '5'), _click('b3'), _text('t3', '商是 2'),
    _click('b2'), _text('t2', '数到 10'),
    _click('b2'), _text('t2', '数到 10'),
  ],
];

// —— 样例二（列表和记录状态＋重复里的事件＋去页面带参数）的三组步骤 ——
List<Steps> frontStepSetsList(String kind) {
  Map<String, Object?> toDetail() => kind == 'html' ? {'op': 'page', 'html': 'page-detail.html'} : {'op': 'hash', 'is': '#/detail'};
  return [
    frontStepsList(kind),
    [
      // 一个都不选就去：带过去的是初值
      _click('go'), toDetail(), _text('got', '带来：无 / 3'),
    ],
    [
      // 删到空，再加两项，选最后一项再去
      _click('del', 0), _click('del', 0), _click('del', 0), _count('itName', 0),
      _type('in1', '戊'), _click('add'), _type('in1', '己'), _click('add'), _count('itName', 2),
      _click('pick', 1), _text('count', '2 项，选了 己@1'),
      _click('go'), toDetail(), _text('got', '带来：己 / 2'),
    ],
  ];
}

// —— 旧积木全集升级后的三组步骤 ——
List<Steps> frontStepSetsOld() => [
  coreStepsOld(),
  [
    // 一上来就点“试试”：count 是 0，“重复 2.5 次”加三回 10
    _type('n3', '30'), _click('nA'), _text('nA', '7.5·0·true·false'),
    _wait(120), _text('n7', '等完了'),
  ],
  [_click('n5'), _text('n1', '点了 1 次'), _type('n3', '塔'), _text('n7', '你好，塔'), _click('nA'), _text('nA', '7.75·0·false·true')],
];

// —— 样例三：“要等的事”（开始算、等、最多等到超时、取消）＋请求（假网络） ——
LcDocument frontSampleWait() => frontPage(
  [btn('w1', '等'), txt('o1'), btn('w2', '超时'), txt('o2'), btn('w3', '取消'), txt('o3'), btn('w4', '请求'), txt('o4'), btn('w5', '同时'), txt('o5')],
  const [],
  frontDoc(
    functions: [waitSlowFn()],
    hats: [
      onClick('h1', 'w1', [
        konst('t', spawnOf(slow(21, 30))),
        show('o1', tx('开始了')),
        show('o1', cat([tx('得 '), toText(await_(vr('t')))])),
      ]),
      onClick('h2', 'w2', [
        let('m', tx('没超时')),
        tryB(
          [
            blk('do', {
              'value': ex('awaitMax', {'x': spawnOf(slow(5, 300)), 'ms': nm(40)}),
            }),
          ],
          [
            catchArm('超时', 'e', [setv('m', tx('超时了'))]),
          ],
        ),
        show('o2', vr('m')),
      ]),
      onClick('h3', 'w3', [
        konst('c', spawnOf(slow(9, 300))),
        sleep(20),
        blk('cancel', {'x': vr('c')}),
        let('k', tx('没取消')),
        tryB(
          [
            blk('do', {'value': await_(vr('c'))}),
          ],
          [
            catchArm('取消了', 'e', [setv('k', tx('取消了'))]),
          ],
        ),
        show('o3', vr('k')),
      ]),
      onClick('h4', 'w4', [
        blk(pg('oldFetch'), {'method': 'GET', 'url': tx('https://example.com/api')}, [show('o4', ex(pg('fetchText')))], [show('o4', tx('失败了'))]),
      ]),
      onClick('h5', 'w5', [
        konst(
          'all',
          ex('awaitAll', {
            'list': ls([spawnOf(slow(1, 60)), spawnOf(slow(2, 10))]),
          }),
        ),
        konst(
          'any',
          ex('awaitAny', {
            'list': ls([spawnOf(slow(3, 200)), spawnOf(slow(4, 10))]),
          }),
        ),
        show(
          'o5',
          cat([
            toText(ex('len', {'x': vr('all')})),
            tx(' 件，最先 '),
            toText(vr('any')),
          ]),
        ),
      ]),
    ],
  ),
  title: 'Wait',
);

Map<String, Object?> _net([Map<String, Object?> routes = const {}]) => {'op': 'fake', 'routes': routes};

List<Steps> frontStepSetsWait() => [
  [_net(), _click('w1'), _wait(120), _text('o1', '得 42'), _click('w2'), _wait(150), _text('o2', '超时了'), _click('w3'), _wait(150), _text('o3', '取消了')],
  [
    _net({
      'https://example.com/api': {'status': 200, 'body': '回来了'},
    }),
    _click('w4'),
    _wait(60),
    _text('o4', '回来了'),
    _click('w5'),
    _wait(200),
    _text('o5', '2 件，最先 8'),
  ],
  [
    // 连不上走“失败后”；几件事同时开着互不耽误
    _net(),
    _click('w4'), _wait(60), _text('o4', '失败了'),
    _click('w3'), _click('w1'), _wait(200), _text('o1', '得 42'), _text('o3', '取消了'),
  ],
];

// —— 样例四：用了“都行”库（页工具）和只给前端的库（喊话）的页面 ——
const Map<String, String> kFrontKitFiles = {
  'lib.json': '''
{"kind": "lopicode-lib", "format": 1, "id": "test/front-kit", "name": "喊话", "version": "1.0.0", "summary": "测试用", "rules": 2,
 "for": "frontend", "hosts": ["page.alert"], "modules": [{"file": "modules/kit.lc", "name": "喊话"}], "blocks": ["blocks.json"]}''',
  'modules/kit.lc': '''
(模块 喊话
  (宿主 page.alert ((话 文字)) -> 空)
  (公开 (函数 喊 ((话 文字)) (做 (宿 page.alert (连 "【" 话 "】")))))
  (公开 (函数 加感叹 ((话 文字) (几 小数)) -> 文字
    (设 出 话) (设 i 0) (当 (< i 几) (改 出 (连 出 "！")) (改 i (+ i 1))) (返回 出))))
''',
  'blocks.json': '''
{"blocks": [
  {"id": "shout", "how": "expand", "expand": "(做 (调 喊 (槽 text)))", "look": {"name": "喊一声", "shape": "statement", "template": "喊一声 {text}"}},
  {"id": "bang", "how": "call", "of": "加感叹", "args": ["text", "n"], "look": {"name": "加感叹号", "shape": "value", "template": "{text} 加 {n} 个感叹号"}}
]}''',
};

/// 只给前端的库，可是用了后端才有的宿主接口（读环境变量）：要被拦下。
const Map<String, String> kBadFrontKitFiles = {
  'lib.json': '''
{"kind": "lopicode-lib", "format": 1, "id": "test/bad-front", "name": "偷看环境", "version": "1.0.0", "summary": "测试用", "rules": 2,
 "for": "frontend", "hosts": ["sys.env"], "modules": [{"file": "modules/kit.lc", "name": "偷看环境"}], "blocks": ["blocks.json"]}''',
  'modules/kit.lc': '''
(模块 偷看环境
  (宿主 sys.env ((名 文字)) -> 文字)
  (公开 (函数 看 ((名 文字)) -> 文字 (返回 (宿 sys.env 名)))))
''',
  'blocks.json': '''
{"blocks": [
  {"id": "peek", "how": "call", "of": "看", "args": ["name"], "look": {"name": "看环境", "shape": "value", "template": "环境里的 {name}"}}
]}''',
};

LibLibrary frontKit() => libRead(kFrontKitFiles, builtin: false);
LibLibrary badFrontKit() => libRead(kBadFrontKitFiles, builtin: false);

J kit(String id, J slots) => ex('lib:test/page-kit#$id', slots);
J fkit(String id, J slots) => ex('lib:test/front-kit#$id', slots);

/// 把库交给文档每一页的逻辑，并把新逻辑重新写回（用上的库记进 `uses`）。
LcDocument withLibs(LcDocument doc, List<LibLibrary> libs) {
  for (final p in doc.pages) {
    p.logic.loaded = libs;
    final front = lcFrontOf(p.logic);
    if (front != null) lcFrontStore(p.logic, front);
  }
  return doc;
}

LcDocument frontSampleLibs() => withLibs(
  frontPage(
    [inp('in1'), btn('k1', '加两回'), txt('p1'), btn('k2', '数三下'), txt('p2'), btn('k3', '除'), txt('p3'), btn('k4', '喊'), txt('p4')],
    [
      {'name': 'n', 'type': 'number', 'initial': 1},
    ],
    frontDoc(
      uses: [
        {'id': 'test/page-kit'},
        {'id': 'test/front-kit'},
      ],
      hats: [
        onClick('h1', 'k1', [
          stSet('n', kit('addTwice', {'x': asNum(stGet('n')), 'step': nm(5)})),
          show('p1', toText(stGet('n'))),
        ]),
        onClick('h2', 'k2', [
          show('p2', toText(kit('count3', {'from': asNum(prGet('in1', 'value'))}))),
        ]),
        onClick('h3', 'k3', [
          show('p3', kit('safeDiv', {'a': nm(9), 'b': asNum(prGet('in1', 'value'))})),
        ]),
        onClick('h4', 'k4', [
          blk('lib:test/front-kit#shout', {'text': toText(prGet('in1', 'value'))}),
          show('p4', fkit('bang', {'text': toText(prGet('in1', 'value')), 'n': nm(2)})),
        ]),
      ],
    ),
    title: 'Libs',
  ),
  [pageKit(), frontKit()],
);

List<Steps> frontStepSetsLibs() => [
  [
    _net(),
    _click('k1'),
    _text('p1', '11'),
    _click('k1'),
    _text('p1', '21'),
    _type('in1', '4'),
    _click('k2'),
    _text('p2', '7'),
    _click('k3'),
    _text('p3', '商是 2.25'),
    _click('k4'),
    _text('p4', '4！！'),
    {'op': 'alerts', 'is': '【4】'},
  ],
  [_net(), _type('in1', '0'), _click('k3'), _text('p3', '出错：不能除以零'), _click('k2'), _text('p2', '3')],
  [
    _net(),
    _type('in1', '好'),
    _click('k4'),
    _click('k4'),
    _text('p4', '好！！'),
    {'op': 'alerts', 'is': '【好】 | 【好】'},
    _click('k1'),
    _text('p1', '11'),
  ],
];
