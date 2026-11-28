// 自带前端库第一批的样例（积木第 5 版·前端 2）：定时、本地保存、状态仓库、事件总线各三组（“请求”的在 front_libs_http_samples.dart，
// 它要本地假服务的地址）。页面逻辑是用积木文档的数据模型搭的；步骤在 Node＋jsdom 里真跑。
import 'package:lopicode/lowcode/model.dart';

import 'backend_core_samples.dart';
import 'backend_lang_blocks.dart';
import 'page_front_samples.dart';

/// 一组样例：名字、页面、步骤。
class FrontLibSample {
  FrontLibSample(this.name, this.doc, this.steps);
  final String name;
  final LcDocument doc;
  final List<Map<String, Object?>> steps;
}

String fl(String lib, String id) => 'lib:lopi/$lib#$id';
J useLib(String lib) => {'id': 'lopi/$lib'};
J libHat(String id, String lib, String block, J args, List<J> body) => {'id': id, 'op': fl(lib, block), 'args': args, 'body': body};
J numVar(String name, [num initial = 0]) => {'name': name, 'type': 'number', 'initial': initial};
J textVar(String name, [String initial = '']) => {'name': name, 'type': 'text', 'initial': initial};
J inc(String state, [num by = 1]) => stSet(state, op2('+', asNum(stGet(state)), nm(by)));
J click(String sel) => {'op': 'click', 'sel': '.n-$sel'};
J textIs(String sel, String text) => {'op': 'text', 'sel': '.n-$sel', 'is': text};
J waitMs(int ms) => {'op': 'wait', 'ms': ms};

/// 等到这段字变成要的样子（有上限）。
J untilText(String sel, String text) => {'op': 'until', 'sel': '.n-$sel', 'is': text};
J storedUntil(String key, String text) => {'op': 'storedUntil', 'key': key, 'is': text};

// —— 定时 ——
List<FrontLibSample> timerSamples() => [
  FrontLibSample(
    '过一会儿做',
    frontPage(
      [btn('b1', '开始'), txt('t1')],
      const [],
      frontDoc(
        uses: [useLib('timer')],
        hats: [
          onClick('h1', 'b1', [
            let('id', nm(0)),
            blk(fl('timer', 'after'), {'ms': nm(60), 'into': 'id'}, [show('t1', tx('到了'))]),
            show('t1', tx('等着')),
          ]),
        ],
      ),
    ),
    [click('b1'), textIs('t1', '等着'), untilText('t1', '到了')],
  ),
  FrontLibSample(
    '每隔一会儿做、取消',
    frontPage(
      [btn('b1', '开始'), btn('b2', '停'), txt('t1'), txt('t2')],
      [numVar('n'), numVar('tid')],
      frontDoc(
        uses: [useLib('timer')],
        hats: [
          onClick('h1', 'b1', [
            let('id', nm(0)),
            blk(fl('timer', 'every'), {'ms': nm(30), 'into': 'id'}, [inc('n'), show('t1', toText(stGet('n')))]),
            stSet('tid', vr('id')),
          ]),
          onClick('h2', 'b2', [
            blk(fl('timer', 'cancel'), {'id': stGet('tid')}),
            stSet('n', nm(100)),
            show('t1', toText(stGet('n'))),
            show('t2', tx('停了')),
          ]),
        ],
      ),
    ),
    // 停了以后再等一阵：数没有再涨（没取消掉的话会变成 101、102……）。
    [click('b1'), waitMs(150), click('b2'), textIs('t2', '停了'), waitMs(150), textIs('t1', '100')],
  ),
  FrontLibSample(
    '防抖、节流、让界面先更新一下',
    frontPage(
      [btn('b1', '防抖'), btn('b2', '节流'), btn('b3', '下一帧'), txt('t1', '0'), txt('t2', '0'), txt('t3')],
      [numVar('n'), numVar('m')],
      frontDoc(
        uses: [useLib('timer')],
        hats: [
          onClick('h1', 'b1', [
            blk(fl('timer', 'debounce'), {'key': tx('搜'), 'ms': nm(80)}, [inc('n'), show('t1', toText(stGet('n')))]),
          ]),
          onClick('h2', 'b2', [
            blk(fl('timer', 'throttle'), {'key': tx('点'), 'ms': nm(5000)}, [inc('m'), show('t2', toText(stGet('m')))]),
          ]),
          onClick('h3', 'b3', [
            blk(fl('timer', 'frame'), const {}, [show('t3', tx('画好了'))]),
          ]),
        ],
      ),
    ),
    [
      click('b1'),
      click('b1'),
      click('b1'),
      textIs('t1', '0'),
      untilText('t1', '1'),
      waitMs(200),
      textIs('t1', '1'),
      click('b2'),
      click('b2'),
      click('b2'),
      textIs('t2', '1'),
      click('b3'),
      untilText('t3', '画好了'),
    ],
  ),
];

// —— 事件总线 ——
List<FrontLibSample> busSamples() => [
  FrontLibSample(
    '发消息、当收到消息',
    frontPage(
      [btn('b1', '发'), txt('t1')],
      const [],
      frontDoc(
        uses: [useLib('bus')],
        hats: [
          libHat(
            'h0',
            'bus',
            'on',
            {'name': '打招呼'},
            [
              show('t1', cat([tx('收到 '), toText(ex(fl('bus', 'data')))])),
            ],
          ),
          onClick('h1', 'b1', [
            blk(fl('bus', 'emit'), {'name': tx('打招呼'), 'value': tx('甲')}),
          ]),
        ],
      ),
    ),
    [click('b1'), textIs('t1', '收到 甲')],
  ),
  FrontLibSample(
    '两个人听、有几个在听、都不听了',
    frontPage(
      [btn('b1', '发'), btn('b2', '几个'), btn('b3', '都不听'), txt('t1', '0'), txt('t2')],
      [numVar('n')],
      frontDoc(
        uses: [useLib('bus')],
        hats: [
          libHat('h0', 'bus', 'on', {'name': '加'}, [inc('n', 1)]),
          libHat('h00', 'bus', 'on', {'name': '加'}, [inc('n', 10)]),
          onClick('h1', 'b1', [
            blk(fl('bus', 'emit'), {'name': tx('加'), 'value': nm(0)}),
            show('t1', toText(stGet('n'))),
          ]),
          onClick('h2', 'b2', [
            show('t2', toText(ex(fl('bus', 'count'), {'name': tx('加')}))),
          ]),
          onClick('h3', 'b3', [
            blk(fl('bus', 'clear'), {'name': tx('加')}),
          ]),
        ],
      ),
    ),
    [click('b1'), textIs('t1', '11'), click('b2'), textIs('t2', '2'), click('b3'), click('b2'), textIs('t2', '0'), click('b1'), textIs('t1', '11')],
  ),
  FrontLibSample(
    '开始听消息、不再听',
    frontPage(
      [btn('b1', '听'), btn('b2', '发'), btn('b3', '不听'), txt('t1', '0')],
      [numVar('c'), numVar('lid')],
      frontDoc(
        uses: [useLib('bus')],
        hats: [
          onClick('h1', 'b1', [
            let('id', nm(0)),
            blk(fl('bus', 'listen'), {'name': tx('响'), 'into': 'id'}, [stSet('c', op2('+', asNum(stGet('c')), asNum(ex(fl('bus', 'data'))))), show('t1', toText(stGet('c')))]),
            stSet('lid', vr('id')),
          ]),
          onClick('h2', 'b2', [
            blk(fl('bus', 'emit'), {'name': tx('响'), 'value': nm(3)}),
          ]),
          onClick('h3', 'b3', [
            blk(fl('bus', 'off'), {'id': stGet('lid')}),
          ]),
        ],
      ),
    ),
    // 还没人听：发了也没事；听了以后发两次＝6；不听了再发，不变。
    [click('b2'), textIs('t1', '0'), click('b1'), click('b2'), click('b2'), textIs('t1', '6'), click('b3'), click('b2'), textIs('t1', '6')],
  ),
];

// —— 本地保存 ——
List<FrontLibSample> storageSamples() => [
  FrontLibSample(
    '存、读、存过吗、删',
    frontPage(
      [inp('in1'), btn('b1', '存'), btn('b2', '读'), btn('b3', '删'), txt('t1'), txt('t2')],
      const [],
      frontDoc(
        uses: [useLib('storage')],
        hats: [
          onClick('h1', 'b1', [
            blk(fl('storage', 'set'), {'key': tx('名字'), 'value': prGet('in1', 'value')}),
          ]),
          onClick('h2', 'b2', [
            show('t1', toText(ex(fl('storage', 'get'), {'key': tx('名字'), 'orElse': tx('没有')}))),
            iff(ex(fl('storage', 'has'), {'key': tx('名字')}), [show('t2', tx('存过'))], orElse: [show('t2', tx('没存过'))]),
          ]),
          onClick('h3', 'b3', [
            blk(fl('storage', 'remove'), {'key': tx('名字')}),
          ]),
        ],
      ),
    ),
    [
      click('b2'),
      textIs('t1', '没有'),
      textIs('t2', '没存过'),
      {'op': 'type', 'sel': '.n-in1', 'text': '丁'},
      click('b1'),
      {'op': 'stored', 'key': '名字', 'is': '"丁"'},
      click('b2'),
      textIs('t1', '丁'),
      textIs('t2', '存过'),
      {'op': 'reload'},
      click('b2'),
      textIs('t1', '丁'),
      click('b3'),
      {'op': 'stored', 'key': '名字', 'is': null},
      click('b2'),
      textIs('t1', '没有'),
    ],
  ),
  FrontLibSample(
    '状态关掉再开还在',
    frontPage(
      [btn('b1', '加'), btn('b2', '看'), txt('t1')],
      [numVar('n')],
      frontDoc(
        uses: [useLib('storage')],
        hats: [
          hat('h0', 'onMounted', [
            blk(fl('storage', 'persist'), {'name': tx('n'), 'key': tx('留着的数')}),
          ]),
          onClick('h1', 'b1', [inc('n')]),
          onClick('h2', 'b2', [show('t1', toText(stGet('n')))]),
        ],
      ),
    ),
    [
      click('b1'),
      click('b1'),
      click('b2'),
      textIs('t1', '2'),
      storedUntil('留着的数', '2'),
      {'op': 'reload'},
      click('b2'),
      textIs('t1', '2'),
      click('b1'),
      storedUntil('留着的数', '3'),
    ],
  ),
  FrontLibSample(
    '存的东西读不回来就用给的、所有名字、清空',
    frontPage(
      [btn('b1', '读坏的'), btn('b2', '几个'), btn('b3', '清空'), txt('t1'), txt('t2')],
      const [],
      frontDoc(
        uses: [useLib('storage')],
        hats: [
          onClick('h1', 'b1', [
            show('t1', toText(ex(fl('storage', 'get'), {'key': tx('坏的'), 'orElse': tx('用给的')}))),
          ]),
          onClick('h2', 'b2', [
            show('t2', toText(ex('len', {'x': ex(fl('storage', 'keys'))}))),
          ]),
          onClick('h3', 'b3', [blk(fl('storage', 'clear'))]),
        ],
      ),
    ),
    [
      {'op': 'store', 'key': '坏的', 'value': '不是 JSON{'},
      {'op': 'store', 'key': '好的', 'value': '1'},
      click('b1'),
      textIs('t1', '用给的'),
      click('b2'),
      textIs('t2', '2'),
      click('b3'),
      click('b2'),
      textIs('t2', '0'),
      {'op': 'stored', 'key': '好的', 'is': null},
    ],
  ),
];

// —— 状态仓库 ——
List<FrontLibSample> storeSamples() => [
  FrontLibSample(
    '新建仓库、读、改、当仓库变了',
    frontPage(
      [btn('b1', '加'), txt('t1', '-')],
      const [],
      frontDoc(
        uses: [useLib('store')],
        hats: [
          hat('h0', 'onMounted', [
            blk(fl('store', 'create'), {
              'store': tx('购物车'),
              'initial': dc({'几件': nm(0)}),
            }),
          ]),
          libHat(
            'h00',
            'store',
            'watch',
            {'store': '购物车'},
            [
              show(
                't1',
                cat([
                  tx('变成 '),
                  toText(ex(fl('store', 'get'), {'store': tx('购物车'), 'key': tx('几件')})),
                ]),
              ),
            ],
          ),
          onClick('h1', 'b1', [
            blk(fl('store', 'set'), {
              'store': tx('购物车'),
              'key': tx('几件'),
              'value': op2('+', asNum(ex(fl('store', 'get'), {'store': tx('购物车'), 'key': tx('几件')})), nm(1)),
            }),
          ]),
        ],
      ),
    ),
    [click('b1'), untilText('t1', '变成 1'), click('b1'), click('b1'), untilText('t1', '变成 3')],
  ),
  FrontLibSample(
    '仓库的动作、让仓库做动作、没有的动作出错',
    frontPage(
      [btn('b1', '加五'), btn('b2', '乱来'), btn('b3', '看'), txt('t1'), txt('t2')],
      const [],
      frontDoc(
        uses: [useLib('store')],
        hats: [
          hat('h0', 'onMounted', [
            blk(fl('store', 'create'), {
              'store': tx('分数'),
              'initial': dc({'分': nm(1)}),
            }),
          ]),
          libHat(
            'h00',
            'store',
            'action',
            {'store': '分数', 'action': '加'},
            [
              blk(fl('store', 'set'), {
                'store': tx('分数'),
                'key': tx('分'),
                'value': op2('+', asNum(ex(fl('store', 'get'), {'store': tx('分数'), 'key': tx('分')})), asNum(ex(fl('store', 'payload')))),
              }),
            ],
          ),
          onClick('h1', 'b1', [
            blk(fl('store', 'dispatch'), {'store': tx('分数'), 'action': tx('加'), 'value': nm(5)}),
          ]),
          onClick('h2', 'b2', [
            tryB(
              [
                blk(fl('store', 'dispatch'), {'store': tx('分数'), 'action': tx('没有的'), 'value': nm(0)}),
              ],
              [
                catchArm('错误', 'e', [show('t2', getF(vr('e'), '消息'))]),
              ],
            ),
          ]),
          onClick('h3', 'b3', [
            show('t1', toText(ex(fl('store', 'get'), {'store': tx('分数'), 'key': tx('分')}))),
          ]),
        ],
      ),
    ),
    [click('b1'), click('b1'), click('b3'), textIs('t1', '11'), click('b2'), textIs('t2', '仓库「分数」没有叫「没有的」的动作')],
  ),
  FrontLibSample(
    '仓库关掉再开还在、整个仓库',
    frontPage(
      [btn('b1', '改'), btn('b2', '看'), txt('t1'), txt('t2')],
      const [],
      frontDoc(
        uses: [useLib('store')],
        hats: [
          hat('h0', 'onMounted', [
            blk(fl('store', 'create'), {
              'store': tx('喜好'),
              'initial': dc({'主题': tx('浅')}),
            }),
            blk(fl('store', 'persist'), {'store': tx('喜好'), 'key': tx('存喜好')}),
          ]),
          onClick('h1', 'b1', [
            blk(fl('store', 'set'), {'store': tx('喜好'), 'key': tx('主题'), 'value': tx('深')}),
          ]),
          onClick('h2', 'b2', [
            show('t1', toText(ex(fl('store', 'get'), {'store': tx('喜好'), 'key': tx('主题')}))),
            show(
              't2',
              toText(
                ex('len', {
                  'x': ex(fl('store', 'all'), {'store': tx('喜好')}),
                }),
              ),
            ),
          ]),
        ],
      ),
    ),
    [
      click('b2'),
      textIs('t1', '浅'),
      textIs('t2', '1'),
      click('b1'),
      storedUntil('存喜好', '{"主题":"深"}'),
      {'op': 'reload'},
      click('b2'),
      textIs('t1', '深'),
    ],
  ),
];
