// 小应用乙组·第 3 种形状“用户自己的组件库＋JS 库一起用”：会议室预订——登录 → 会议室列表 → 会议室详情 → 提交预订。
// 界面上的四样是用户组件库“预订组件”里的组件：登录块（带事件的表单块）、房间项（列表项）、信息卡（卡片，带插槽）、预订块（带事件的表单块）。
// 组件发出的事件接到页面逻辑的帽子“当〔实例〕发出〔事件〕”；逻辑里用用户 JS 库“会话与接口”（见 front_app_b_tickets.dart）
// 和自带的“定时”库（订好以后过一会儿自动回列表；可以点“留在这里”取消）。
import 'package:lopicode/backend/backend_lib_doc.dart';
import 'package:lopicode/lang/types.dart';
import 'package:lopicode/lowcode/comp_lib.dart';

import 'backend_core_samples.dart';
import 'backend_func_blocks.dart';
import 'backend_lang_blocks.dart';
import 'comp_samples.dart';
import 'front_app_b_kit.dart';
import 'front_app_b_tickets.dart' show kSess, kTkToken;
import 'front_libs_samples.dart';
import 'page_front_samples.dart';
import 'typeops_sample.dart';

const String kRoomsUi = 'shuang/roomsui';
const String kRmToken = kTkToken;

J _emitTo(String event, Map<String, Object?> args) => {
  'emit': {
    'click': {'event': event, 'args': args},
  },
};
J _model(String id, String state, String hint) => cn(
  id,
  'input',
  {'placeholder': hint},
  const [],
  {
    'model': {'state': state},
  },
);
J _bound(String id, String prop) => cn(
  id,
  'text',
  {'text': '-'},
  const [],
  {
    'data': {'text': cFrom(prop)},
  },
);

/// 登录块：两个输入框双向到属性，按钮发“要登录”，带上名字和密码。
J loginBlockDef() => {
  'id': 'c1',
  'name': '登录块',
  'props': [
    {'name': 'user', 'type': 'text', 'default': ''},
    {'name': 'pass', 'type': 'text', 'default': ''},
  ],
  'root': cn(
    'box',
    'column',
    {'gap': 8, 'padding': 12},
    [
      _model('userIn', 'user', '用户名'),
      _model('passIn', 'pass', '密码'),
      cn('go', 'button', {'text': '登录'}, const [], _emitTo('submit', {'user': cFrom('user'), 'pass': cFrom('pass')})),
    ],
  ),
  'events': [
    {
      'name': 'submit',
      'label': '要登录',
      'params': [
        {'name': 'user', 'type': 'text'},
        {'name': 'pass', 'type': 'text'},
      ],
    },
  ],
};

/// 房间项：名字、一句说明、“看看”按钮发“要看”，带上房间号。
J roomItemDef() => {
  'id': 'c2',
  'name': '房间项',
  'props': [
    {'name': 'title', 'type': 'text', 'default': '房间'},
    {'name': 'note', 'type': 'text', 'default': ''},
    {'name': 'rid', 'type': 'text', 'default': ''},
  ],
  'root': cn(
    'line',
    'row',
    {'gap': 8},
    [
      _bound('name', 'title'),
      _bound('note', 'note'),
      cn('open', 'button', {'text': '看看'}, const [], _emitTo('open', {'id': cFrom('rid')})),
    ],
  ),
  'events': [
    {
      'name': 'open',
      'label': '要看',
      'params': [
        {'name': 'id', 'type': 'text'},
      ],
    },
  ],
};

/// 信息卡：标题、正文，下面一个插槽。
J infoCardDef() => {
  'id': 'c3',
  'name': '信息卡',
  'props': [
    {'name': 'title', 'type': 'text', 'default': ''},
    {'name': 'body', 'type': 'text', 'default': ''},
  ],
  'root': cn(
    'card',
    'card',
    {'padding': 12, 'gap': 8},
    [
      _bound('head', 'title'),
      _bound('text', 'body'),
      cn('more', 'slot', const {}, [
        cn('moreText', 'text', {'text': '（没有别的）'}),
      ]),
    ],
  ),
};

/// 预订块：谁订、哪个时段（双向到属性），按钮发“要订”，带上这两样。
J bookBlockDef() => {
  'id': 'c4',
  'name': '预订块',
  'props': [
    {'name': 'who', 'type': 'text', 'default': ''},
    {'name': 'slot', 'type': 'text', 'default': ''},
  ],
  'root': cn(
    'box',
    'column',
    {'gap': 8},
    [
      _model('whoIn', 'who', '谁订'),
      _model('slotIn', 'slot', '时段'),
      cn('go', 'button', {'text': '预订'}, const [], _emitTo('book', {'who': cFrom('who'), 'slot': cFrom('slot')})),
    ],
  ),
  'events': [
    {
      'name': 'book',
      'label': '要订',
      'params': [
        {'name': 'who', 'type': 'text'},
        {'name': 'slot', 'type': 'text'},
      ],
    },
  ],
};

List<J> roomsUiDefs() => [loginBlockDef(), roomItemDef(), infoCardDef(), bookBlockDef()];
String rmDef(String id) => compLibDefId(kRoomsUi, id);

/// 各实例用的是哪个定义（Vue / React 里组件是单独的文件，找元素的写法要用）。
Map<String, String> get kRoomsDefs => {'lgf': rmDef('c1'), 'rm': rmDef('c2'), 'info': rmDef('c3'), 'bk': rmDef('c4')};

J _inst(String id, String def, {Map<String, Object?> data = const {}, List<J> children = const [], Map<String, Object?> more = const {}}) =>
    cn(id, 'component', {'ref': rmDef(def)}, children, {if (data.isNotEmpty) 'data': data, ...more});
J _sx(String block, [J args = const {}]) => ex(beLibOp(kSess, block), args);
J _ss(String block, [J args = const {}]) => blk(beLibOp(kSess, block), args);
J _emit(String name) => toText(ex(pg('emitData'), {'name': tx(name)}));
J _onEmit(String id, String node, String event, List<J> body) => hat(id, 'onEmit', body, args: {'node': node, 'event': event});
List<J> _uses({bool timer = false}) => [
  useLib('http'),
  useLib('storage'),
  useLib('store'),
  {'id': kSess},
  if (timer) useLib('timer'),
];
const LType _dicts = LType.listOf(LType.dictOf(LType.any));

AppPage _login(String base) => AppPage(
  'login',
  [
    txt('lg_rdy'),
    _inst('lgf', 'c1', data: {'user': fromVar('user'), 'pass': fromVar('pass')}),
    txt('lg_msg'),
  ],
  [textVar('user'), textVar('pass')],
  frontDoc(
    uses: _uses(),
    hats: [
      mounted([
        _ss('connect', {'地址': tx(base)}),
        iff(_sx('authed'), [show('lg_msg', tx('已登录')), goTo('rooms')], orElse: [show('lg_msg', tx('请登录'))]),
        show('lg_rdy', tx('好了')),
      ]),
      _onEmit('h1', 'lgf', 'submit', [
        iff(
          _sx('login', {'名': _emit('user'), '密码': _emit('pass')}),
          [show('lg_msg', tx('登录成功')), goTo('rooms')],
          orElse: [
            show('lg_msg', _sx('err')),
            // 登录不成：把密码那一格清掉（页面状态变了，组件里的输入框跟着空）。
            stSet('pass', tx('')),
          ],
        ),
      ]),
    ],
  ),
);

AppPage _rooms(String base) => AppPage(
  'rooms',
  [
    txt('rm_rdy'),
    txt('rm_err'),
    btn('rm_retry', '重试'),
    btn('rm_out', '退出'),
    repeatRow('rm_row', 'items', [
      _inst(
        'rm',
        'c2',
        data: {
          'title': fromVar('it', ['title']),
          'note': fromVar('it', ['note']),
          'rid': fromVar('it', ['id']),
        },
      ),
    ]),
    txt('rm_sum'),
  ],
  [listVar('items')],
  frontDoc(
    uses: _uses(),
    functions: [
      tfn('f1', '加载房间', const [], [
        let('xs', _sx('list', {'路径': tx('/rooms')})),
        iff(
          op2('==', _sx('err'), tx('')),
          [
            let('out', ascribe(ls(const []), _dicts)),
            forIn(vr('xs'), 'r', [
              push(
                'out',
                dc({
                  'id': toText(at(vr('r'), 'id')),
                  'title': at(vr('r'), 'title'),
                  'note': cat([tx('坐 '), toText(at(vr('r'), 'seats')), tx(' 人，订了 '), toText(at(vr('r'), 'n')), tx(' 次')]),
                }),
              ),
            ]),
            stSet('items', vr('out')),
            show('rm_err', tx('')),
            iff(
              op2('==', lenOf(vr('xs')), nm(0)),
              [show('rm_sum', tx('没有会议室'))],
              orElse: [
                show('rm_sum', cat([tx('共 '), toText(lenOf(vr('xs'))), tx(' 间')])),
              ],
            ),
          ],
          orElse: [show('rm_err', _sx('err'))],
        ),
      ]),
    ],
    hats: [
      mounted([
        _ss('connect', {'地址': tx(base)}),
        iff(_sx('authed'), [callS('f1')], orElse: [show('rm_err', tx('没登录')), goTo('login')]),
        show('rm_rdy', tx('好了')),
      ]),
      _onEmit('h1', 'rm', 'open', [
        goWith('room', {'id': _emit('id')}),
      ]),
      onClick('h2', 'rm_retry', [callS('f1')]),
      onClick('h3', 'rm_out', [_ss('logout'), show('rm_err', tx('已退出')), goTo('login')]),
    ],
  ),
);

AppPage _room(String base) => AppPage(
  'room',
  [
    txt('ro_rdy'),
    _inst(
      'info',
      'c3',
      data: {'title': fromVar('title'), 'body': fromVar('body')},
      children: [
        cn(
          'ro_taken',
          'text',
          {'text': '-'},
          const [],
          {
            'data': {'text': fromVar('taken')},
          },
        ),
      ],
    ),
    _inst('bk', 'c4', data: {'who': fromVar('who'), 'slot': fromVar('slot')}),
    btn('ro_stay', '留在这里'),
    btn('ro_back', '返回'),
    txt('ro_msg'),
  ],
  [textVar('title'), textVar('body'), textVar('taken'), textVar('who'), textVar('slot'), textVar('rid'), numVar('tid')],
  frontDoc(
    uses: _uses(timer: true),
    functions: [
      tfn('f1', '看房间', const [], [
        let(
          'r',
          _sx('one', {
            '路径': cat([tx('/rooms/'), toText(stGet('rid'))]),
          }),
        ),
        iff(
          op2('==', _sx('err'), tx('')),
          [
            stSet('title', toText(at(vr('r'), 'title'))),
            stSet('body', cat([tx('坐 '), toText(at(vr('r'), 'seats')), tx(' 人')])),
            stSet('taken', cat([tx('已订：'), toText(at(vr('r'), 'taken'))])),
          ],
          orElse: [show('ro_msg', _sx('err'))],
        ),
      ]),
    ],
    hats: [
      mounted([
        _ss('connect', {'地址': tx(base)}),
        stSet('rid', toText(param('id'))),
        callS('f1'),
        show('ro_rdy', tx('好了')),
      ]),
      _onEmit('h1', 'bk', 'book', [
        iff(
          op2('==', _emit('who'), tx('')),
          [show('ro_msg', tx('写上谁订'))],
          orElse: [
            iff(
              _sx('submit', {
                '路径': cat([tx('/rooms/'), toText(stGet('rid')), tx('/book')]),
                '数据': dc({'who': _emit('who'), 'slot': _emit('slot')}),
              }),
              [
                show('ro_msg', tx('订好了，马上回列表')),
                stSet('slot', tx('')),
                callS('f1'),
                let('id', nm(0)),
                blk(fl('timer', 'after'), {'ms': nm(400), 'into': 'id'}, [show('ro_msg', tx('回列表')), goTo('rooms')]),
                stSet('tid', vr('id')),
              ],
              orElse: [show('ro_msg', _sx('err'))],
            ),
          ],
        ),
      ]),
      onClick('h2', 'ro_stay', [
        blk(fl('timer', 'cancel'), {'id': stGet('tid')}),
        show('ro_msg', tx('留在这里')),
      ]),
      onClick('h3', 'ro_back', [show('ro_msg', tx('返回')), goTo('rooms')]),
    ],
  ),
);

/// 整个会议室预订小应用（三页，首页是“会议室”）。
List<AppPage> roomPages(String base) => [_rooms(base), _login(base), _room(base)];
