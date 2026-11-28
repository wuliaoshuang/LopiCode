// 小应用乙组·第 1 种形状“活动报名（多语言）”：三页——活动（首页：列表和详情两块，用“路由”库在页里切）、登录、报名表。
// 登录（请求＋本地保存记住登录）→ 活动列表（请求＋状态仓库）→ 活动详情（路由参数）→ 填报名表提交（表单校验＋请求）→ 回列表看到名额变了。
// 界面上的字全走“国际化”库：中英两张语言表，换了语言界面跟着变，选的语言记在本地，换页、关掉再开都还在。
import 'package:lopicode/lang/types.dart';

import 'backend_core_samples.dart';
import 'backend_func_blocks.dart';
import 'backend_lang_blocks.dart';
import 'front_app_b_kit.dart';
import 'front_libs_samples.dart';
import 'page_front_samples.dart';
import 'typeops_sample.dart';

const String kEvToken = 'ev_token';
const String kEvLang = 'ev_lang';

/// 两张语言表：名字 →（中文，English）。
const Map<String, (String, String)> kEvWords = {
  'loginTitle': ('登录', 'Sign in'),
  'pleaseLogin': ('请登录', 'Please sign in'),
  'already': ('已登录', 'Already signed in'),
  'loginOk': ('登录成功', 'Signed in'),
  'loginFail': ('登录失败（{code}）', 'Sign-in failed ({code})'),
  'langBtn': ('English', '中文'),
  'eventsTitle': ('活动', 'Events'),
  'left': ('剩 {n} 个名额', '{n} left'),
  'empty': ('暂无活动', 'No events yet'),
  'count': ('共 {n} 个活动', '{n} events'),
  'retry': ('重试', 'Retry'),
  'logout': ('退出', 'Sign out'),
  'bye': ('已退出', 'Signed out'),
  'needLogin': ('没登录', 'Not signed in'),
  'loadFail': ('取不到：{code}', 'Failed to load: {code}'),
  'error': ('出错：{msg}', 'Error: {msg}'),
  'open': ('看看', 'View'),
  'signupBtn': ('我要报名', 'Sign up'),
  'back': ('返回', 'Back'),
  'signupTitle': ('报名：{title}', 'Sign up: {title}'),
  'required': ('这一格要填', 'Required'),
  'nameShort': ('名字最少 2 个字', 'Name needs 2+ characters'),
  'phoneBad': ('电话只能是数字', 'Digits only'),
  'mailBad': ('邮箱不对', 'Invalid email'),
  'nRange': ('人数要在 1 和 {max} 之间', 'Between 1 and {max}'),
  'fixFirst': ('请先改好上面的格子', 'Please fix the fields above'),
  'submit': ('提交', 'Submit'),
  'done': ('报名成功', 'Signed up'),
  'full': ('名额满了', 'Fully booked'),
  'submitFail': ('提交失败（{code}）', 'Submit failed ({code})'),
};

/// 假服务这一头的活动世界。[listFaults] / [signupFaults]＝头几次出什么岔子（'hang' 拖着不回、'500' 报错），用完就正常；
/// [soldOut]＝这几个活动的名额其实已经被别人抢完了（列表上还写着有，报名时服务说满了）。
class EvWorld {
  EvWorld(List<(String zh, String en, int left)> start, {List<String> listFaults = const [], List<String> signupFaults = const [], this.soldOut = const {}})
    : _listFaults = [...listFaults],
      _signupFaults = [...signupFaults] {
    for (final (zh, en, left) in start) {
      events.add({'id': events.length + 1, 'zh': zh, 'en': en, 'zhDesc': '$zh的介绍', 'enDesc': 'About $en', 'left': left});
    }
  }
  final List<Map<String, Object?>> events = [];
  final List<Map<String, Object?>> signups = [];
  final List<String> _listFaults;
  final List<String> _signupFaults;
  final Set<int> soldOut;

  int leftOf(int id) => events.firstWhere((e) => e['id'] == id)['left']! as int;

  FakeRes handle(FakeReq q) {
    if (q.method == 'POST' && q.path == '/login') {
      return q.json['user'] == '霜霜' && q.json['pass'] == '123' ? const FakeRes(200, {'token': 'tk-9'}) : const FakeRes(401, '密码不对');
    }
    if (q.token != 'tk-9') return const FakeRes(401, '没登录');
    if (q.path == '/events' && q.method == 'GET') {
      if (_listFaults.isNotEmpty) {
        return _listFaults.removeAt(0) == 'hang' ? const FakeRes.hang() : const FakeRes(500, '坏了');
      }
      return FakeRes(200, [
        for (final e in events) {'id': e['id'], 'zh': e['zh'], 'en': e['en'], 'left': e['left']},
      ]);
    }
    final one = RegExp(r'^/events/(\d+)$').firstMatch(q.path);
    if (one != null && q.method == 'GET') {
      final found = events.where((e) => '${e['id']}' == one.group(1)).toList();
      return found.isEmpty ? const FakeRes(404, '没有这个活动') : FakeRes(200, found.single);
    }
    final sign = RegExp(r'^/events/(\d+)/signup$').firstMatch(q.path);
    if (sign != null && q.method == 'POST') {
      final found = events.where((e) => '${e['id']}' == sign.group(1)).toList();
      if (found.isEmpty) return const FakeRes(404, '没有这个活动');
      final e = found.single;
      if (soldOut.contains(e['id'])) {
        e['left'] = 0;
        return const FakeRes(409, '满了');
      }
      if (_signupFaults.isNotEmpty) {
        return _signupFaults.removeAt(0) == 'hang' ? const FakeRes.hang() : const FakeRes(500, '坏了');
      }
      final n = q.json['n'];
      final name = '${q.json['name'] ?? ''}'.trim();
      if (name.isEmpty || n is! num || n < 1) return const FakeRes(400, '填得不对');
      if (n > (e['left']! as int)) return const FakeRes(409, '满了');
      e['left'] = (e['left']! as int) - n.toInt();
      signups.add({'event': e['id'], ...q.json});
      return FakeRes(200, {'left': e['left']});
    }
    return const FakeRes(404, '没有');
  }
}

// —— 三页都用的积木 ——
J _t(String key) => lx('i18n', 't', {'key': tx(key)});
J _tw(String key, Map<String, J> data) => lx('i18n', 'tWith', {'key': tx(key), 'data': dc(data)});
J _req(String method, J url, {J? data, num timeout = 2000}) => authReq(kEvToken, method, url, data: data, timeout: timeout);
J _errTo(String node) => catchArm('错误', 'e', [
  show(node, _tw('error', {'msg': getF(vr('e'), '消息')})),
]);
J _table(String lang, String Function((String, String)) pick) => lb('i18n', 'table', {
  'lang': tx(lang),
  'table': dc({for (final w in kEvWords.entries) w.key: tx(pick(w.value))}),
});

/// 我的积木“装语言”：两张语言表、备用语言、上次选的语言、哪条文案跟着放进哪个状态。每一页都要有一份。
J _fnLang(Map<String, String> binds) => tfn('fl', '装语言', const [], [
  _table('中文', (w) => w.$1),
  _table('English', (w) => w.$2),
  lb('i18n', 'fallback', {'lang': tx('中文')}),
  iff(op2('==', toText(lx('storage', 'get', {'key': tx(kEvLang), 'orElse': tx('中文')})), tx('English')), [
    lb('i18n', 'use', {'lang': tx('English')}),
  ], noElse: true),
  for (final b in binds.entries) lb('i18n', 'bind', {'key': tx(b.key), 'state': tx(b.value)}),
]);

/// 我的积木“切换语言”：中英来回换，换完记在本地。
J _fnToggle() => tfn('ft', '切换语言', const [], [
  iff(
    op2('==', lx('i18n', 'current'), tx('中文')),
    [
      lb('i18n', 'use', {'lang': tx('English')}),
    ],
    orElse: [
      lb('i18n', 'use', {'lang': tx('中文')}),
    ],
  ),
  lb('storage', 'set', {'key': tx(kEvLang), 'value': lx('i18n', 'current')}),
]);

List<J> _libs(List<String> names) => [for (final n in names) useLib(n)];

AppPage _login(String base) => AppPage(
  'login',
  [txt('lg_rdy'), boundText('lg_h', 'tTitle'), inp('lg_user'), inp('lg_pass'), boundBtn('lg_go', 'tTitle'), boundBtn('lg_lang', 'tLang'), txt('lg_msg')],
  [textVar('tTitle'), textVar('tLang')],
  frontDoc(
    uses: _libs(['http', 'storage', 'i18n']),
    functions: [
      _fnLang({'loginTitle': 'tTitle', 'langBtn': 'tLang'}),
      _fnToggle(),
    ],
    hats: [
      mounted([
        callS('fl'),
        iff(lx('storage', 'has', {'key': tx(kEvToken)}), [show('lg_msg', _t('already')), goTo('events')], orElse: [show('lg_msg', _t('pleaseLogin'))]),
        show('lg_rdy', tx('好了')),
      ]),
      onClick('h1', 'lg_go', [
        tryB(
          [
            let(
              'res',
              lx('http', 'request', {
                'method': 'POST',
                'url': tx('$base/login'),
                'data': dc({'user': valOf('lg_user'), 'pass': valOf('lg_pass')}),
                'timeout': nm(2000),
              }),
            ),
            iff(
              resOk('res'),
              [
                lb('storage', 'set', {'key': tx(kEvToken), 'value': at(asDict(resJson('res')), 'token')}),
                show('lg_msg', _t('loginOk')),
                goTo('events'),
              ],
              orElse: [
                show('lg_msg', _tw('loginFail', {'code': resStatus('res')})),
              ],
            ),
          ],
          [_errTo('lg_msg')],
        ),
      ]),
      onClick('h2', 'lg_lang', [callS('ft'), show('lg_msg', _t('pleaseLogin'))]),
    ],
  ),
);

/// 首页“活动”：列表和详情两块在同一页里，用“路由”库按井号后面那一段切（/ 是列表，/event/3 是 3 号活动的详情）。
AppPage _events(String base) {
  J isDetail() => op2('==', lx('router', 'name'), tx('详情'));
  J routeId() => lx('router', 'param', {'name': tx('id')});
  return AppPage(
    'events',
    [
      txt('ev_rdy'),
      boundText('ev_h', 'tTitle'),
      boundBtn('ev_lang', 'tLang'),
      boundBtn('ev_out', 'tOut'),
      txt('ev_err'),
      boundBtn('ev_retry', 'tRetry'),
      section(
        'ev_list',
        [
          repeatRow('ev_row', 'items', [
            boundText('ev_title', 'it', ['title']),
            boundText('ev_left', 'it', ['left']),
            boundBtn('ev_open', 'tOpen'),
          ]),
          txt('ev_sum'),
        ],
        showWhen: ('pg', '列表'),
      ),
      section('ev_detail', [txt('dt_title'), txt('dt_desc'), txt('dt_left'), boundBtn('dt_go', 'tSign'), boundBtn('dt_back', 'tBack'), txt('dt_err')], showWhen: ('pg', '详情')),
    ],
    [
      textVar('pg'),
      listVar('items'),
      textVar('tTitle'),
      textVar('tLang'),
      textVar('tOut'),
      textVar('tRetry'),
      textVar('tOpen'),
      textVar('tSign'),
      textVar('tBack'),
      textVar('eid'),
      textVar('etitle'),
      numVar('eleft'),
    ],
    frontDoc(
      uses: _libs(['http', 'storage', 'store', 'i18n', 'router']),
      functions: [
        _fnLang({'eventsTitle': 'tTitle', 'langBtn': 'tLang', 'logout': 'tOut', 'retry': 'tRetry', 'open': 'tOpen', 'signupBtn': 'tSign', 'back': 'tBack'}),
        _fnToggle(),
        // 服务给的每个活动有 zh、en 两栏名字：现在是哪种语言就读哪一栏。
        tfn('f4', '哪一栏', const [], [
          iff(op2('==', lx('i18n', 'current'), tx('English')), [ret(tx('en'))], noElse: true),
          ret(tx('zh')),
        ], returns: tText),
        // 把仓库里取回来的活动排成列表状态（名字按现在的语言、名额写成一句话）。
        tfn('f2', '排列表', const [], [
          let('key', call('f4')),
          let('out', ascribe(ls(const []), const LType.listOf(LType.dictOf(LType.any)))),
          forIn(asDicts(lx('store', 'get', {'store': tx('活动'), 'key': tx('raw')})), 'e', [
            push(
              'out',
              dc({
                'id': at(vr('e'), 'id'),
                'title': ex('index', {'of': vr('e'), 'key': vr('key')}),
                'left': _tw('left', {'n': at(vr('e'), 'left')}),
              }),
            ),
          ]),
          stSet('items', vr('out')),
          iff(
            op2('==', lenOf(vr('out')), nm(0)),
            [show('ev_sum', _t('empty'))],
            orElse: [
              show('ev_sum', _tw('count', {'n': lenOf(vr('out'))})),
            ],
          ),
        ]),
        tfn('f1', '加载活动', const [], [
          tryB(
            [
              let('res', _req('GET', tx('$base/events'), timeout: 250)),
              iff(
                resOk('res'),
                [
                  lb('store', 'set', {'store': tx('活动'), 'key': tx('raw'), 'value': resJson('res')}),
                  show('ev_err', tx('')),
                  callS('f2'),
                ],
                orElse: [
                  show('ev_err', _tw('loadFail', {'code': resStatus('res')})),
                ],
              ),
            ],
            [_errTo('ev_err')],
          ),
        ]),
        tfn(
          'f3',
          '看详情',
          [tpar('id', tText)],
          [
            stSet('eid', pm('id')),
            tryB(
              [
                let('res', _req('GET', cat([tx('$base/events/'), pm('id')]))),
                iff(
                  resOk('res'),
                  [
                    let('e', asDict(resJson('res'))),
                    let('key', call('f4')),
                    stSet('etitle', toText(ex('index', {'of': vr('e'), 'key': vr('key')}))),
                    stSet('eleft', toNum(toText(at(vr('e'), 'left')))),
                    show('dt_title', toText(stGet('etitle'))),
                    show(
                      'dt_desc',
                      toText(
                        ex('index', {
                          'of': vr('e'),
                          'key': cat([vr('key'), tx('Desc')]),
                        }),
                      ),
                    ),
                    show('dt_left', _tw('left', {'n': at(vr('e'), 'left')})),
                    show('dt_err', tx('')),
                  ],
                  orElse: [
                    show('dt_err', _tw('loadFail', {'code': resStatus('res')})),
                  ],
                ),
              ],
              [_errTo('dt_err')],
            ),
          ],
        ),
      ],
      hats: [
        mounted([
          lb('store', 'create', {
            'store': tx('活动'),
            'initial': dc({'raw': ls(const [])}),
          }),
          callS('fl'),
          // 首页的地址在纯网页里井号后面是空的（/），在 Vue / React 的多页面外壳里是 #/events——两种都算列表。
          lb('router', 'route', {'pattern': tx('/'), 'name': tx('列表')}),
          lb('router', 'route', {'pattern': tx('/events'), 'name': tx('列表')}),
          lb('router', 'route', {'pattern': tx('/event/:id'), 'name': tx('详情')}),
          lb('router', 'bind', {'state': tx('pg')}),
          iff(lx('storage', 'has', {'key': tx(kEvToken)}), [callS('f1')], orElse: [show('ev_err', _t('needLogin')), goTo('login')]),
          show('ev_rdy', tx('好了')),
        ]),
        libHat('h1', 'i18n', 'onChange', const {}, [
          callS('f2'),
          iff(isDetail(), [
            callS('f3', {'id': routeId()}),
          ], noElse: true),
        ]),
        libHat('h2', 'router', 'onChange', const {}, [
          iff(isDetail(), [
            callS('f3', {'id': routeId()}),
          ], noElse: true),
        ]),
        onClick('h3', 'ev_open', [
          lb('router', 'go', {
            'path': cat([
              tx('/event/'),
              toText(ex(pg('eventItemField'), {'key': tx('id')})),
            ]),
          }),
        ]),
        onClick('h4', 'dt_back', [
          lb('router', 'go', {'path': tx('/')}),
        ]),
        onClick('h5', 'dt_go', [
          goWith('signup', {'id': stGet('eid'), 'title': stGet('etitle'), 'left': stGet('eleft')}),
        ]),
        onClick('h6', 'ev_lang', [callS('ft')]),
        onClick('h7', 'ev_out', [
          lb('storage', 'remove', {'key': tx(kEvToken)}),
          show('ev_err', _t('bye')),
          goTo('login'),
        ]),
        onClick('h8', 'ev_retry', [callS('f1')]),
      ],
    ),
  );
}

AppPage _signup(String base) {
  J rule(String id, String msgKey, [J more = const {}]) => lx('form', id, {...more, 'msg': _t(msgKey)});
  J rules(String field, List<J> rs) => lb('form', 'rules', {'form': tx('报名'), 'field': tx(field), 'rules': ls(rs)});
  J bind(String field, String state) => lb('form', 'bind', {'form': tx('报名'), 'field': tx(field), 'state': tx(state)});
  return AppPage(
    'signup',
    [
      txt('su_rdy'),
      txt('su_h'),
      inp('su_name'),
      boundText('su_e1', 'eName'),
      inp('su_phone'),
      boundText('su_e2', 'ePhone'),
      inp('su_mail'),
      boundText('su_e3', 'eMail'),
      inp('su_n'),
      boundText('su_e4', 'eN'),
      boundBtn('su_go', 'tSubmit'),
      boundBtn('su_back', 'tBack'),
      txt('su_msg'),
    ],
    [textVar('eName'), textVar('ePhone'), textVar('eMail'), textVar('eN'), textVar('tSubmit'), textVar('tBack'), textVar('eid')],
    frontDoc(
      uses: _libs(['http', 'storage', 'i18n', 'form']),
      functions: [
        _fnLang({'submit': 'tSubmit', 'back': 'tBack'}),
      ],
      hats: [
        mounted([
          callS('fl'),
          stSet('eid', toText(param('id'))),
          show('su_h', _tw('signupTitle', {'title': param('title')})),
          // 人数最多报到剩下的名额：上限是列表页带过来的。
          let('max', toNum(toText(param('left')))),
          rules('name', [
            rule('required', 'required'),
            rule('minLen', 'nameShort', {'n': nm(2)}),
          ]),
          rules('phone', [rule('required', 'required'), rule('digits', 'phoneBad')]),
          rules('mail', [rule('email', 'mailBad')]),
          rules('n', [
            rule('required', 'required'),
            lx('form', 'range', {
              'min': nm(1),
              'max': vr('max'),
              'msg': _tw('nRange', {'max': vr('max')}),
            }),
          ]),
          bind('name', 'eName'),
          bind('phone', 'ePhone'),
          bind('mail', 'eMail'),
          bind('n', 'eN'),
          show('su_rdy', tx('好了')),
        ]),
        onClick('h1', 'su_go', [
          iff(
            lx('form', 'checkAll', {
              'form': tx('报名'),
              'values': dc({'name': valOf('su_name'), 'phone': valOf('su_phone'), 'mail': valOf('su_mail'), 'n': valOf('su_n')}),
            }),
            [
              tryB(
                [
                  let(
                    'res',
                    _req(
                      'POST',
                      cat([tx('$base/events/'), toText(stGet('eid')), tx('/signup')]),
                      data: dc({'name': valOf('su_name'), 'phone': valOf('su_phone'), 'mail': valOf('su_mail'), 'n': toNum(toText(valOf('su_n')))}),
                      timeout: 250,
                    ),
                  ),
                  iff(
                    resOk('res'),
                    [show('su_msg', _t('done')), goTo('events')],
                    orElse: [
                      iff(
                        op2('==', lx('http', 'status', {'res': vr('res')}), nm(409)),
                        [show('su_msg', _t('full'))],
                        orElse: [
                          show('su_msg', _tw('submitFail', {'code': resStatus('res')})),
                        ],
                      ),
                    ],
                  ),
                ],
                [_errTo('su_msg')],
              ),
            ],
            orElse: [show('su_msg', _t('fixFirst'))],
          ),
        ]),
        onClick('h2', 'su_back', [show('su_msg', _t('back')), goTo('events')]),
      ],
    ),
  );
}

/// 整个活动报名小应用（三页，首页是“活动”）。[base]＝假服务的地址。
List<AppPage> eventsPages(String base) => [_events(base), _login(base), _signup(base)];
