// 小应用乙组·第 2 种形状“用户自己写的 JS 库驱动”：工单小应用——登录 → 工单列表 → 工单详情 → 提交回复。
// 页面自己不碰“请求”“本地保存”“状态仓库”，全靠用户自己用积木写的前端库“会话与接口”（包了这三个自带库，
// 公开“连到服务”“登录”“已登录”“退出”“取列表”“取一条”“提交”“上次的错”八块带类型的积木）。
// 另一种搭法（[TkKit.rich]）换两个不同形状的用户库：纯计算的“金额与格式”库、包事件总线的“通知”库；
// 这时请求那几块写成页面自己的“我的积木”（同一段积木，不从库里来）。
import 'package:lopicode/backend/backend_lib_doc.dart';
import 'package:lopicode/lang/types.dart';
import 'package:lopicode/lang/types_json.dart';

import 'backend_core_samples.dart';
import 'backend_func_blocks.dart';
import 'backend_lang_blocks.dart';
import 'front_app_b_kit.dart';
import 'front_libs_samples.dart';
import 'page_front_samples.dart';
import 'typeops_sample.dart';
import 'user_libs.dart' show def, libDoc, look;

const String kSess = 'shuang/session';
const String kMoney = 'shuang/money';
const String kNotice = 'shuang/notice';
const String kTkToken = 'tk_token';

const LType _dict = LType.dictOf(LType.any);
const LType _dicts = LType.listOf(LType.dictOf(LType.any));
final J tDictAny = lTypeToJson(_dict);
final J tDicts = lTypeToJson(_dicts);

J frontLib(String name, String id, {required List<J> functions, required List<J> blocks, List<String> uses = const []}) {
  final doc = libDoc(name, id, functions: functions, blocks: blocks, uses: [for (final u in uses) useLib(u)]);
  return {
    ...doc,
    'library': {...doc['library'] as Map, 'for': 'frontend'},
  };
}

// —— 用户库一：“会话与接口”（包请求＋本地保存＋状态仓库）——
J _sGet(String key) => toText(lx('store', 'get', {'store': tx('会话'), 'key': tx(key)}));
J _sErr(J what) => lb('store', 'set', {'store': tx('会话'), 'key': tx('err'), 'value': what});
J _url(J path) => cat([_sGet('base'), path]);
J _bad(String res) => _sErr(cat([tx('服务说不行（'), resStatus(res), tx('）')]));
J _caught() => catchArm('错误', 'e', [
  _sErr(cat([tx('出错：'), getF(vr('e'), '消息')])),
]);

/// “会话与接口”的八个函数。放进库文档里就是库；放进页面的“我的积木”里就是页面自己的（另一种搭法）。
List<J> sessionFns() => [
  tfn(
    's0',
    '连到',
    [tpar('地址', tText)],
    [
      lb('store', 'create', {
        'store': tx('会话'),
        'initial': dc({'base': pm('地址'), 'err': tx('')}),
      }),
    ],
  ),
  tfn(
    's1',
    '登录',
    [tpar('名', tText), tpar('密码', tText)],
    [
      tryB(
        [
          let(
            'res',
            lx('http', 'request', {
              'method': 'POST',
              'url': _url(tx('/login')),
              'data': dc({'user': pm('名'), 'pass': pm('密码')}),
              'timeout': nm(2000),
            }),
          ),
          iff(
            resOk('res'),
            [
              lb('storage', 'set', {'key': tx(kTkToken), 'value': at(asDict(resJson('res')), 'token')}),
              _sErr(tx('')),
              ret(ex('bool', {'v': true})),
            ],
            orElse: [_bad('res')],
          ),
        ],
        [_caught()],
      ),
      ret(ex('bool', {'v': false})),
    ],
    returns: tBool,
  ),
  tfn('s2', '已登录', const [], [ret(lx('storage', 'has', {'key': tx(kTkToken)}))], returns: tBool),
  tfn('s3', '退出', const [], [
    lb('storage', 'remove', {'key': tx(kTkToken)}),
  ]),
  tfn(
    's4',
    '取列表',
    [tpar('路径', tText)],
    [
      tryB(
        [
          let('res', authReq(kTkToken, 'GET', _url(pm('路径')), timeout: 250)),
          iff(resOk('res'), [_sErr(tx('')), ret(asDicts(resJson('res')))], orElse: [_bad('res')]),
        ],
        [_caught()],
      ),
      ret(ascribe(ls(const []), _dicts)),
    ],
    returns: tDicts,
  ),
  tfn(
    's5',
    '取一条',
    [tpar('路径', tText)],
    [
      tryB(
        [
          let('res', authReq(kTkToken, 'GET', _url(pm('路径')), timeout: 250)),
          iff(resOk('res'), [_sErr(tx('')), ret(asDict(resJson('res')))], orElse: [_bad('res')]),
        ],
        [_caught()],
      ),
      ret(ascribe(dc(const {}), _dict)),
    ],
    returns: tDictAny,
  ),
  tfn(
    's6',
    '提交',
    [tpar('路径', tText), tpar('数据', tDictAny)],
    [
      tryB(
        [
          let('res', authReq(kTkToken, 'POST', _url(pm('路径')), data: pm('数据'), timeout: 250)),
          iff(resOk('res'), [_sErr(tx('')), ret(ex('bool', {'v': true}))], orElse: [_bad('res')]),
        ],
        [_caught()],
      ),
      ret(ex('bool', {'v': false})),
    ],
    returns: tBool,
  ),
  tfn('s7', '上次的错', const [], [ret(_sGet('err'))], returns: tText),
];

/// 公开成积木的名字 → 函数。
const Map<String, String> kSessBlocks = {'connect': 's0', 'login': 's1', 'authed': 's2', 'logout': 's3', 'list': 's4', 'one': 's5', 'submit': 's6', 'err': 's7'};

J sessionLib() => frontLib(
  '会话与接口',
  kSess,
  uses: const ['http', 'storage', 'store'],
  functions: sessionFns(),
  blocks: [
    def('connect', 'call', fn: 's0', look: look('连到服务', '连到服务 {地址}', shape: 'statement')),
    def('login', 'call', fn: 's1', look: look('登录', '用 {名} 和 {密码} 登录成了', shape: 'value')),
    def('authed', 'call', fn: 's2', look: look('已登录', '已经登录了', shape: 'value')),
    def('logout', 'call', fn: 's3', look: look('退出', '退出登录', shape: 'statement')),
    def('list', 'call', fn: 's4', look: look('取列表', '从 {路径} 取到的列表', shape: 'value')),
    def('one', 'call', fn: 's5', look: look('取一条', '从 {路径} 取到的一条', shape: 'value')),
    def('submit', 'call', fn: 's6', look: look('提交', '往 {路径} 提交 {数据} 成了', shape: 'value')),
    def('err', 'call', fn: 's7', look: look('上次的错', '上次的错', shape: 'value')),
  ],
);

// —— 用户库二：“金额与格式”（纯计算，谁也不靠）——
J moneyLib() => frontLib(
  '金额与格式',
  kMoney,
  functions: [
    tfn(
      'm1',
      '标价',
      [tpar('钱', tNum)],
      [
        ret(cat([tx('¥'), toText(pm('钱'))])),
      ],
      returns: tText,
    ),
    tfn(
      'm2',
      '合计',
      [tpar('单子', tDicts), tpar('栏', tText)],
      [
        let('sum', nm(0)),
        forIn(pm('单子'), 'x', [
          setv(
            'sum',
            op2('+', vr('sum'), toNum(toText(ex('index', {'of': vr('x'), 'key': pm('栏')})))),
          ),
        ]),
        ret(vr('sum')),
      ],
      returns: tNum,
    ),
    tfn('m3', '超了', [tpar('钱', tNum), tpar('上限', tNum)], [ret(op2('>', pm('钱'), pm('上限')))], returns: tBool),
  ],
  blocks: [
    def('label', 'call', fn: 'm1', look: look('标价', '{钱} 的标价', shape: 'value')),
    def('total', 'call', fn: 'm2', look: look('合计', '{单子} 里 {栏} 的合计', shape: 'value')),
    def('over', 'call', fn: 'm3', look: look('超了', '{钱} 超过 {上限}', shape: 'value')),
  ],
);

// —— 用户库三：“通知”（包事件总线＋状态仓库：发一条通知，记着发过几条）——
J noticeLib() => frontLib(
  '通知',
  kNotice,
  uses: const ['bus', 'store'],
  functions: [
    tfn('n0', '准备', const [], [
      lb('store', 'create', {
        'store': tx('通知'),
        'initial': dc({'n': nm(0)}),
      }),
    ]),
    tfn('n2', '发过几条', const [], [ret(toNum(toText(lx('store', 'get', {'store': tx('通知'), 'key': tx('n')}))))], returns: tNum),
    tfn(
      'n1',
      '发通知',
      [tpar('话', tText)],
      [
        lb('store', 'set', {'store': tx('通知'), 'key': tx('n'), 'value': op2('+', call('n2'), nm(1))}),
        lb('bus', 'emit', {'name': tx('通知'), 'value': pm('话')}),
      ],
    ),
  ],
  blocks: [
    def('ready', 'call', fn: 'n0', look: look('准备通知', '准备好发通知', shape: 'statement')),
    def('send', 'call', fn: 'n1', look: look('发通知', '发一条通知 {话}', shape: 'statement')),
    def('count', 'call', fn: 'n2', look: look('发过几条', '发过几条通知', shape: 'value')),
  ],
);

/// 一种搭法：[rich]＝不用“会话与接口”库（那几块写成页面自己的），换成“金额与格式”＋“通知”两个库。
class TkKit {
  const TkKit({this.rich = false});
  final bool rich;

  J x(String block, [J args = const {}]) => rich ? call(kSessBlocks[block]!, args) : ex(beLibOp(kSess, block), args);
  J s(String block, [J args = const {}]) => rich ? callS(kSessBlocks[block]!, args) : blk(beLibOp(kSess, block), args);
  J mx(String block, J args) => ex(beLibOp(kMoney, block), args);

  List<J> uses({bool notice = false}) => [
    useLib('http'),
    useLib('storage'),
    useLib('store'),
    if (!rich) {'id': kSess},
    if (rich) {'id': kMoney},
    if (rich && notice) ...[
      useLib('bus'),
      {'id': kNotice},
    ],
  ];
  List<J> fns() => rich ? sessionFns() : const [];
}

J _errIs(TkKit k, String v) => op2('==', k.x('err'), tx(v));

AppPage _login(TkKit k, String base) => AppPage(
  'login',
  [txt('lg_rdy'), inp('lg_user'), inp('lg_pass'), btn('lg_go', '登录'), txt('lg_msg')],
  const [],
  frontDoc(
    uses: k.uses(),
    functions: k.fns(),
    hats: [
      mounted([
        k.s('connect', {'地址': tx(base)}),
        iff(k.x('authed'), [show('lg_msg', tx('已登录')), goTo('tickets')], orElse: [show('lg_msg', tx('请登录'))]),
        show('lg_rdy', tx('好了')),
      ]),
      onClick('h1', 'lg_go', [
        iff(k.x('login', {'名': toText(valOf('lg_user')), '密码': toText(valOf('lg_pass'))}), [show('lg_msg', tx('登录成功')), goTo('tickets')], orElse: [show('lg_msg', k.x('err'))]),
      ]),
    ],
  ),
);

AppPage _tickets(TkKit k, String base) => AppPage(
  'tickets',
  [
    txt('tk_rdy'),
    txt('tk_err'),
    btn('tk_retry', '重试'),
    btn('tk_out', '退出'),
    repeatRow('tk_row', 'items', [boundText('tk_title', 'it', ['title']), boundText('tk_n', 'it', ['n']), if (k.rich) boundText('tk_fee', 'it', ['fee']), btn('tk_open', '看看')]),
    txt('tk_sum'),
  ],
  [listVar('items')],
  frontDoc(
    uses: k.uses(),
    functions: [
      ...k.fns(),
      tfn('f1', '加载工单', const [], [
        let('xs', k.x('list', {'路径': tx('/tickets')})),
        iff(
          _errIs(k, ''),
          [
            let('out', ascribe(ls(const []), _dicts)),
            forIn(vr('xs'), 't', [
              push(
                'out',
                dc({
                  'id': at(vr('t'), 'id'),
                  'title': at(vr('t'), 'title'),
                  'n': cat([toText(at(vr('t'), 'n')), tx(' 条回复')]),
                  if (k.rich) 'fee': k.mx('label', {'钱': toNum(toText(at(vr('t'), 'fee')))}),
                }),
              ),
            ]),
            stSet('items', vr('out')),
            show('tk_err', tx('')),
            iff(
              op2('==', lenOf(vr('xs')), nm(0)),
              [show('tk_sum', tx('没有工单'))],
              orElse: [
                show(
                  'tk_sum',
                  cat([
                    tx('共 '),
                    toText(lenOf(vr('xs'))),
                    tx(' 张'),
                    if (k.rich) ...[tx('，合计 '), k.mx('label', {'钱': k.mx('total', {'单子': vr('xs'), '栏': tx('fee')})})],
                  ]),
                ),
              ],
            ),
          ],
          orElse: [show('tk_err', k.x('err'))],
        ),
      ]),
    ],
    hats: [
      mounted([
        k.s('connect', {'地址': tx(base)}),
        iff(k.x('authed'), [callS('f1')], orElse: [show('tk_err', tx('没登录')), goTo('login')]),
        show('tk_rdy', tx('好了')),
      ]),
      onClick('h1', 'tk_open', [
        goWith('ticket', {'id': ex(pg('eventItemField'), {'key': tx('id')})}),
      ]),
      onClick('h2', 'tk_retry', [callS('f1')]),
      onClick('h3', 'tk_out', [k.s('logout'), show('tk_err', tx('已退出')), goTo('login')]),
    ],
  ),
);

AppPage _ticket(TkKit k, String base) => AppPage(
  'ticket',
  [
    txt('tt_rdy'),
    txt('tt_title'),
    txt('tt_body'),
    if (k.rich) ...[txt('tt_fee'), txt('tt_flag'), txt('tt_note'), txt('tt_cnt')],
    repeatRow('tt_row', 'replies', [boundText('tt_reply', 'it', ['text'])]),
    inp('tt_in'),
    btn('tt_go', '提交回复'),
    btn('tt_back', '返回'),
    txt('tt_msg'),
  ],
  [listVar('replies'), textVar('tid')],
  frontDoc(
    uses: k.uses(notice: true),
    functions: [
      ...k.fns(),
      tfn('f1', '看工单', const [], [
        let(
          't',
          k.x('one', {
            '路径': cat([tx('/tickets/'), toText(stGet('tid'))]),
          }),
        ),
        iff(
          _errIs(k, ''),
          [
            show('tt_title', toText(at(vr('t'), 'title'))),
            show('tt_body', toText(at(vr('t'), 'body'))),
            if (k.rich) ...[
              let('fee', toNum(toText(at(vr('t'), 'fee')))),
              show('tt_fee', k.mx('label', {'钱': vr('fee')})),
              iff(k.mx('over', {'钱': vr('fee'), '上限': nm(200)}), [show('tt_flag', tx('要主管批'))], orElse: [show('tt_flag', tx('不用批'))]),
            ],
            let('out', ascribe(ls(const []), _dicts)),
            forIn(castTo(at(vr('t'), 'replies'), const LType.listOf(LType.any)), 'r', [
              push('out', dc({'text': toText(vr('r'))})),
            ]),
            stSet('replies', vr('out')),
          ],
          orElse: [show('tt_msg', k.x('err'))],
        ),
      ]),
    ],
    hats: [
      mounted([
        k.s('connect', {'地址': tx(base)}),
        if (k.rich) ...[blk(beLibOp(kNotice, 'ready')), show('tt_cnt', tx('0 条通知'))],
        stSet('tid', toText(param('id'))),
        callS('f1'),
        show('tt_rdy', tx('好了')),
      ]),
      if (k.rich)
        libHat('h9', 'bus', 'on', {'name': '通知'}, [
          show('tt_note', toText(lx('bus', 'data'))),
          show('tt_cnt', cat([toText(ex(beLibOp(kNotice, 'count'))), tx(' 条通知')])),
        ]),
      onClick('h1', 'tt_go', [
        iff(
          op2('==', toText(valOf('tt_in')), tx('')),
          [show('tt_msg', tx('写点什么再提交'))],
          orElse: [
            iff(
              k.x('submit', {
                '路径': cat([tx('/tickets/'), toText(stGet('tid')), tx('/replies')]),
                '数据': dc({'text': toText(valOf('tt_in'))}),
              }),
              [
                show('tt_msg', tx('已提交')),
                if (k.rich)
                  blk(beLibOp(kNotice, 'send'), {
                    '话': cat([tx('工单 '), toText(stGet('tid')), tx(' 有新回复：'), toText(valOf('tt_in'))]),
                  }),
                prSet('tt_in', 'value', tx('')),
                callS('f1'),
              ],
              orElse: [show('tt_msg', k.x('err'))],
            ),
          ],
        ),
      ]),
      onClick('h2', 'tt_back', [show('tt_msg', tx('返回')), goTo('tickets')]),
    ],
  ),
);

/// 整个工单小应用（三页，首页是“工单”）。
List<AppPage> ticketPages(TkKit k, String base) => [_tickets(k, base), _login(k, base), _ticket(k, base)];
