// 自带前端库第二批的样例（积木第 5 版·前端 2）：路由、表单校验、国际化、动画各三组。
// 页面逻辑是用积木文档的数据模型搭的；步骤在 Node＋jsdom 里真跑。写法和第一批（front_libs_samples.dart）一样。
import 'backend_core_samples.dart';
import 'backend_lang_blocks.dart';
import 'front_libs_samples.dart';
import 'page_front_samples.dart';

J _x(String lib, String id, [J args = const {}]) => ex(fl(lib, id), args);
J _b(String lib, String id, [J args = const {}, List<J> body = const []]) => blk(fl(lib, id), args, body);

/// “当页面放上以后”：做完了在 rdy 上写“好了”——步骤开头先等到它（React 里这一段比头一次点按钮晚一点点才做完）。
J _mounted(List<J> body) => hat('h0', 'onMounted', [...body, show('rdy', tx('好了'))]);
J _ready() => untilText('rdy', '好了');

/// 文字跟着一个状态走的文字控件。
J bound(String id, String state) => node(
  id,
  'text',
  {'text': '-'},
  const [],
  {
    'data': {'text': fromVar(state)},
  },
);
J typeIn(String sel, String text) => {'op': 'type', 'sel': '.n-$sel', 'text': text};
J hashIs(String hash) => {'op': 'hash', 'is': hash};
J _val(String id) => prGet(id, 'value');
J _wrap(J x) => cat([tx('['), x, tx(']')]);

// —— 路由 ——
J _route(String pattern, String name) => _b('router', 'route', {'pattern': tx(pattern), 'name': tx(name)});
J _go(String path) => _b('router', 'go', {'path': tx(path)});

List<FrontLibSample> routerSamples() => [
  FrontLibSample(
    '路由表、去、现在是哪一页、路由参数',
    frontPage(
      [txt('rdy'), btn('b1', '去详情'), btn('b2', '看'), txt('t1'), txt('t2'), txt('t3')],
      const [],
      frontDoc(
        uses: [useLib('router')],
        hats: [
          _mounted([_route('/', '首页'), _route('/detail/:id', '详情')]),
          onClick('h1', 'b1', [_go('/detail/7')]),
          onClick('h2', 'b2', [
            show('t1', _x('router', 'name')),
            show('t2', _wrap(_x('router', 'param', {'name': tx('id')}))),
            show('t3', _x('router', 'path')),
          ]),
        ],
      ),
    ),
    [
      _ready(),
      click('b2'),
      textIs('t1', '首页'),
      textIs('t2', '[]'),
      textIs('t3', '/'),
      click('b1'),
      hashIs('#/detail/7'),
      click('b2'),
      textIs('t1', '详情'),
      textIs('t2', '[7]'),
      textIs('t3', '/detail/7'),
    ],
  ),
  FrontLibSample(
    '当路由变了、后退、换成',
    frontPage(
      [btn('b1', '去甲'), btn('b2', '去乙'), btn('b3', '后退'), btn('b4', '换成丙'), txt('t1')],
      const [],
      frontDoc(
        uses: [useLib('router')],
        hats: [
          libHat('h0', 'router', 'onChange', const {}, [
            show('t1', cat([tx('到 '), _x('router', 'newPath')])),
          ]),
          onClick('h1', 'b1', [_go('/a')]),
          onClick('h2', 'b2', [_go('/b')]),
          onClick('h3', 'b3', [_b('router', 'back')]),
          onClick('h4', 'b4', [
            _b('router', 'replace', {'path': tx('/c')}),
          ]),
        ],
      ),
    ),
    // 换成不留后退：从 /c 后退，回到的是 /a 前面那一条（一开始的 /），不是 /a。
    [
      click('b1'),
      untilText('t1', '到 /a'),
      click('b2'),
      untilText('t1', '到 /b'),
      click('b3'),
      untilText('t1', '到 /a'),
      click('b4'),
      untilText('t1', '到 /c'),
      hashIs('#/c'),
      click('b3'),
      untilText('t1', '到 /'),
    ],
  ),
  FrontLibSample(
    '现在是哪一页跟着放进状态、没对上、参数里的中文、坏的百分号编码',
    frontPage(
      [txt('rdy'), btn('b1', '去搜'), btn('b2', '去没有的'), btn('b3', '比坏的'), btn('b4', '比好的'), bound('p1', 'pg'), txt('t2'), txt('t3')],
      [textVar('pg', '还没定')],
      frontDoc(
        uses: [useLib('router')],
        hats: [
          _mounted([
            _route('/s/:词', '搜索'),
            _b('router', 'bind', {'state': tx('pg')}),
          ]),
          libHat('h00', 'router', 'onChange', const {}, [
            show('t2', _wrap(_x('router', 'param', {'name': tx('词')}))),
          ]),
          onClick('h1', 'b1', [_go('/s/%E4%BD%A0%20%E5%A5%BD')]),
          onClick('h2', 'b2', [_go('/nowhere/x/y')]),
          onClick('h3', 'b3', [
            iff(_x('router', 'match', {'path': tx('/a/%ZZ'), 'pattern': tx('/a/:x')}), [show('t3', tx('对上'))], orElse: [show('t3', tx('没对上'))]),
          ]),
          onClick('h4', 'b4', [
            iff(_x('router', 'match', {'path': tx('/a/b'), 'pattern': tx('/a/:x')}), [show('t3', tx('对上'))], orElse: [show('t3', tx('没对上'))]),
          ]),
        ],
      ),
    ),
    [
      _ready(),
      untilText('p1', ''),
      click('b1'),
      untilText('p1', '搜索'),
      untilText('t2', '[你 好]'),
      click('b2'),
      untilText('p1', ''),
      untilText('t2', '[]'),
      click('b3'),
      textIs('t3', '没对上'),
      click('b4'),
      textIs('t3', '对上'),
    ],
  ),
];

// —— 表单校验 ——
J _rules(String form, String field, List<J> rules) => _b('form', 'rules', {'form': tx(form), 'field': tx(field), 'rules': ls(rules)});
J _rule(String id, [J args = const {}, String msg = '']) => _x('form', id, {...args, 'msg': tx(msg)});
J _check(String form, String field, J value) => _x('form', 'check', {'form': tx(form), 'field': tx(field), 'value': value});
J _error(String form, String field) => _x('form', 'error', {'form': tx(form), 'field': tx(field)});

List<FrontLibSample> formSamples() => [
  FrontLibSample(
    '必填、最少几个字、最多几个字、查一格',
    frontPage(
      [txt('rdy'), inp('in1'), btn('b1', '查'), txt('t1')],
      const [],
      frontDoc(
        uses: [useLib('form')],
        hats: [
          _mounted([
            _rules('注册', '名字', [
              _rule('required'),
              _rule('minLen', {'n': nm(2)}),
              _rule('maxLen', {'n': nm(5)}, '太长了'),
            ]),
          ]),
          onClick('h1', 'b1', [show('t1', _wrap(_check('注册', '名字', _val('in1'))))]),
        ],
      ),
    ),
    [
      _ready(),
      click('b1'),
      textIs('t1', '[这一格要填]'),
      typeIn('in1', '甲'),
      click('b1'),
      textIs('t1', '[最少要 2 个字]'),
      typeIn('in1', '甲乙丙丁戊己'),
      click('b1'),
      textIs('t1', '[太长了]'),
      typeIn('in1', '甲乙丙'),
      click('b1'),
      textIs('t1', '[]'),
    ],
  ),
  FrontLibSample(
    '范围、像邮箱、只有数字、查全部、所有的错、错跟着放进状态',
    frontPage(
      [txt('rdy'), inp('in1'), inp('in2'), inp('in3'), btn('b1', '提交'), txt('t1'), bound('e2', 'mailErr'), txt('t3'), txt('t4')],
      [textVar('mailErr')],
      frontDoc(
        uses: [useLib('form')],
        hats: [
          _mounted([
            _rules('报名', '年龄', [
              _rule('required'),
              _rule('range', {'min': nm(1), 'max': nm(120)}),
            ]),
            _rules('报名', '邮箱', [_rule('email', const {}, '邮箱不对')]),
            _rules('报名', '电话', [_rule('digits')]),
            _b('form', 'bind', {'form': tx('报名'), 'field': tx('邮箱'), 'state': tx('mailErr')}),
          ]),
          onClick('h1', 'b1', [
            iff(
              _x('form', 'checkAll', {
                'form': tx('报名'),
                'values': dc({'年龄': _val('in1'), '邮箱': _val('in2'), '电话': _val('in3')}),
              }),
              [show('t1', tx('都对'))],
              orElse: [show('t1', tx('有错'))],
            ),
            show(
              't3',
              toText(
                ex('len', {
                  'x': _x('form', 'errors', {'form': tx('报名')}),
                }),
              ),
            ),
            show('t4', _wrap(_error('报名', '年龄'))),
          ]),
        ],
      ),
    ),
    [
      _ready(),
      typeIn('in1', '200'),
      typeIn('in2', 'a@b'),
      typeIn('in3', '12x'),
      click('b1'),
      textIs('t1', '有错'),
      textIs('t3', '3'),
      textIs('t4', '[要在 1 和 120 之间]'),
      untilText('e2', '邮箱不对'),
      typeIn('in1', '三十'),
      click('b1'),
      textIs('t4', '[要填一个数]'),
      typeIn('in1', '30'),
      typeIn('in2', 'a@b.com'),
      typeIn('in3', '123'),
      click('b1'),
      textIs('t1', '都对'),
      textIs('t3', '0'),
      textIs('t4', '[]'),
      untilText('e2', ''),
    ],
  ),
  FrontLibSample(
    '自己的规则、这一格不对、清掉错',
    frontPage(
      [inp('in1'), inp('in2'), btn('b1', '查'), btn('b2', '清'), txt('t1'), txt('t2')],
      const [],
      frontDoc(
        uses: [useLib('form')],
        hats: [
          libHat(
            'h0',
            'form',
            'custom',
            {'form': '改密码', 'field': '再输一遍'},
            [
              iff(op2('!=', toText(_x('form', 'value')), toText(_val('in1'))), [
                _b('form', 'fail', {'msg': tx('两次不一样')}),
              ]),
            ],
          ),
          onClick('h1', 'b1', [show('t1', _wrap(_check('改密码', '再输一遍', _val('in2')))), show('t2', _wrap(_error('改密码', '再输一遍')))]),
          onClick('h2', 'b2', [
            _b('form', 'clear', {'form': tx('改密码')}),
            show('t2', _wrap(_error('改密码', '再输一遍'))),
          ]),
        ],
      ),
    ),
    [typeIn('in1', 'abc'), typeIn('in2', 'abd'), click('b1'), textIs('t1', '[两次不一样]'), textIs('t2', '[两次不一样]'), click('b2'), textIs('t2', '[]'), typeIn('in2', 'abc'), click('b1'), textIs('t1', '[]')],
  ),
];

// —— 国际化 ——
J _table(String lang, Map<String, String> words) => _b('i18n', 'table', {
  'lang': tx(lang),
  'table': dc({for (final e in words.entries) e.key: tx(e.value)}),
});
J _t(String key) => _x('i18n', 't', {'key': tx(key)});
J _use(String lang) => _b('i18n', 'use', {'lang': tx(lang)});

List<FrontLibSample> i18nSamples() => [
  FrontLibSample(
    '语言表、文案、换语言、现在的语言',
    frontPage(
      [txt('rdy'), btn('b1', '看'), btn('b2', '换'), txt('t1'), txt('t2')],
      const [],
      frontDoc(
        uses: [useLib('i18n')],
        hats: [
          _mounted([
            _table('中文', {'欢迎': '你好'}),
            _table('English', {'欢迎': 'Hello'}),
          ]),
          onClick('h1', 'b1', [show('t1', _t('欢迎')), show('t2', _x('i18n', 'current'))]),
          onClick('h2', 'b2', [_use('English')]),
        ],
      ),
    ),
    [_ready(), click('b1'), textIs('t1', '你好'), textIs('t2', '中文'), click('b2'), click('b1'), textIs('t1', 'Hello'), textIs('t2', 'English')],
  ),
  FrontLibSample(
    '带占位、备用语言、没有的文案、有这句吗、没有的语言出错',
    frontPage(
      [txt('rdy'), btn('b1', '看'), btn('b2', '换'), btn('b3', '乱换'), txt('t1'), txt('t2'), txt('t3'), txt('t4'), txt('t5')],
      const [],
      frontDoc(
        uses: [useLib('i18n')],
        hats: [
          _mounted([
            _table('中文', {'问好': '你好，{名字}！', '只有中文': '只在中文里'}),
            _table('English', {'问好': 'Hi, {名字}!'}),
            _b('i18n', 'fallback', {'lang': tx('中文')}),
          ]),
          onClick('h1', 'b1', [
            show(
              't1',
              _x('i18n', 'tWith', {
                'key': tx('问好'),
                'data': dc({'名字': tx('霜')}),
              }),
            ),
            show('t2', _t('只有中文')),
            show('t3', _t('没有的')),
            iff(_x('i18n', 'has', {'key': tx('只有中文')}), [show('t4', tx('有'))], orElse: [show('t4', tx('没有'))]),
          ]),
          onClick('h2', 'b2', [_use('English')]),
          onClick('h3', 'b3', [
            tryB(
              [_use('日本語')],
              [
                catchArm('错误', 'e', [show('t5', getF(vr('e'), '消息'))]),
              ],
            ),
          ]),
        ],
      ),
    ),
    [
      _ready(),
      click('b1'),
      textIs('t1', '你好，霜！'),
      textIs('t2', '只在中文里'),
      textIs('t3', '没有的'),
      textIs('t4', '有'),
      click('b2'),
      click('b1'),
      textIs('t1', 'Hi, 霜!'),
      textIs('t2', '只在中文里'),
      textIs('t4', '没有'),
      click('b3'),
      textIs('t5', '还没有「日本語」的语言表'),
    ],
  ),
  FrontLibSample(
    '当语言变了、文案跟着放进状态、所有语言、带千位分隔的写法',
    frontPage(
      [txt('rdy'), btn('b1', '换'), btn('b2', '算'), bound('h', 'title'), txt('t1'), txt('t2'), txt('t3'), txt('t4'), txt('t5')],
      [textVar('title')],
      frontDoc(
        uses: [useLib('i18n')],
        hats: [
          _mounted([
            _table('中文', {'标题': '首页'}),
            _table('English', {'标题': 'Home'}),
            _b('i18n', 'bind', {'key': tx('标题'), 'state': tx('title')}),
          ]),
          libHat('h00', 'i18n', 'onChange', const {}, [
            show('t1', cat([tx('换成了 '), _x('i18n', 'newLang')])),
          ]),
          onClick('h1', 'b1', [_use('English')]),
          onClick('h2', 'b2', [
            show('t2', _x('i18n', 'group', {'value': nm(1234567.5), 'digits': nm(2)})),
            show('t3', toText(ex('len', {'x': _x('i18n', 'langs')}))),
            show('t4', _x('i18n', 'group', {'value': nm(-1234), 'digits': nm(0)})),
            show('t5', _x('i18n', 'group', {'value': nm(999), 'digits': nm(1)})),
          ]),
        ],
      ),
    ),
    [
      _ready(),
      untilText('h', '首页'),
      click('b1'),
      untilText('h', 'Home'),
      untilText('t1', '换成了 English'),
      click('b2'),
      textIs('t2', '1,234,567.50'),
      textIs('t3', '2'),
      textIs('t4', '-1,234'),
      textIs('t5', '999.0'),
    ],
  ),
];

// —— 动画 ——
J _tween(String state, num to, num ms, String ease, [List<J>? then]) =>
    _b('anim', then == null ? 'tween' : 'tweenThen', {'state': tx(state), 'to': nm(to), 'ms': nm(ms), 'ease': ease}, then ?? const []);
J _running(String state, String sel) => iff(_x('anim', 'running', {'state': tx(state)}), [show(sel, tx('在动'))], orElse: [show(sel, tx('没动'))]);

List<FrontLibSample> animSamples() => [
  FrontLibSample(
    '把状态变到、变完以后、在动吗',
    frontPage(
      [btn('b1', '动'), btn('b2', '看'), bound('v', 'x'), txt('t1'), txt('t2')],
      [numVar('x')],
      frontDoc(
        uses: [useLib('anim')],
        hats: [
          onClick('h1', 'b1', [
            _tween('x', 100, 120, '匀速', [show('t1', tx('到了'))]),
            _running('x', 't2'),
          ]),
          onClick('h2', 'b2', [_running('x', 't2')]),
        ],
      ),
    ),
    [textIs('v', '0'), click('b1'), textIs('t2', '在动'), untilText('t1', '到了'), textIs('v', '100'), click('b2'), textIs('t2', '没动')],
  ),
  FrontLibSample(
    '停下、新的一段换掉旧的、零毫秒直接到',
    frontPage(
      [btn('b1', '慢慢动'), btn('b2', '停'), btn('b3', '直接到'), btn('b4', '换一段'), bound('v', 'x'), txt('t1'), txt('t2'), txt('t3')],
      [numVar('x')],
      frontDoc(
        uses: [useLib('anim')],
        hats: [
          onClick('h1', 'b1', [
            _tween('x', 1000, 60000, '先慢后快', [show('t1', tx('不该来'))]),
          ]),
          onClick('h2', 'b2', [
            _b('anim', 'stop', {'state': tx('x')}),
            _running('x', 't2'),
          ]),
          onClick('h3', 'b3', [_tween('x', 5, 0, '匀速')]),
          onClick('h4', 'b4', [
            _tween('x', 50, 60, '两头慢', [show('t3', tx('第二段到了'))]),
          ]),
        ],
      ),
    ),
    // 头一段要走一分钟：停下、被换掉以后，它的“变完以后”都不会来。
    [click('b1'), click('b2'), textIs('t2', '没动'), click('b1'), click('b4'), untilText('t3', '第二段到了'), untilText('v', '50'), textIs('t1', '-'), click('b3'), untilText('v', '5')],
  ),
  FrontLibSample(
    '缓动的值、中间的数、停下所有动画',
    frontPage(
      [btn('b1', '算'), btn('b2', '都动'), btn('b3', '都停'), txt('t1'), txt('t2'), txt('t3'), txt('t4'), txt('t5'), txt('t6')],
      [numVar('x'), numVar('y')],
      frontDoc(
        uses: [useLib('anim')],
        hats: [
          onClick('h1', 'b1', [
            show('t1', toText(_x('anim', 'ease', {'ease': '先慢后快', 't': nm(0.5)}))),
            show('t2', toText(_x('anim', 'ease', {'ease': '先快后慢', 't': nm(0.5)}))),
            show('t3', toText(_x('anim', 'ease', {'ease': '两头慢', 't': nm(0.25)}))),
            show('t4', toText(_x('anim', 'mix', {'from': nm(10), 'to': nm(20), 't': nm(0.5)}))),
            show('t5', toText(_x('anim', 'ease', {'ease': '匀速', 't': nm(2)}))),
          ]),
          onClick('h2', 'b2', [_tween('x', 100, 60000, '匀速'), _tween('y', 100, 60000, '匀速'), _running('y', 't6')]),
          onClick('h3', 'b3', [
            _b('anim', 'stopAll'),
            iff(_x('anim', 'running', {'state': tx('x')}), [show('t6', tx('还在动'))], orElse: [_running('y', 't6')]),
          ]),
        ],
      ),
    ),
    [click('b1'), textIs('t1', '0.25'), textIs('t2', '0.75'), textIs('t3', '0.125'), textIs('t4', '15'), textIs('t5', '1'), click('b2'), textIs('t6', '在动'), click('b3'), textIs('t6', '没动')],
  ),
];
