// 小应用甲组·第 2 种形状“商品下单”：登录 → 商品列表（“重复”＋这一项）→ 详情 → 填数量和地址下单（表单校验库拦不合格的输入）→ 成功页。
// 这一种是一个页面文档、几块内容照“路由”库的“现在是哪一页”换着显示（路由库用的是地址栏井号后面那一段；
// 多页面项目的外壳也用它，两样不能一起用——见汇报“搭应用时发现的问题”）。详情的编号、成功页的单号都是路由参数。
import 'package:lopicode/lang/types.dart';
import 'package:lopicode/lowcode/model.dart';

import 'backend_core_samples.dart';
import 'backend_func_blocks.dart';
import 'backend_lang_blocks.dart';
import 'front_app_a_kit.dart';
import 'front_libs_samples.dart';
import 'page_front_samples.dart';
import 'typeops_sample.dart';

const String kShopToken = 'shop_token';

/// 假服务这一头的小店。[goodsFaults]、[orderFaults]＝头几次出什么岔子（'hang' 拖着不回、'500' 报错），用完就正常。
class ShopWorld {
  ShopWorld(List<(String, int, int)> start, {List<String> goodsFaults = const [], List<String> orderFaults = const []}) : _goodsFaults = [...goodsFaults], _orderFaults = [...orderFaults] {
    for (final (name, price, stock) in start) {
      goods.add({'id': goods.length + 1, 'name': name, 'price': price, 'stock': stock});
    }
  }
  final List<Map<String, Object?>> goods = [];
  final List<Map<String, Object?>> orders = [];
  final List<String> _goodsFaults;
  final List<String> _orderFaults;

  FakeRes handle(FakeReq q) {
    if (q.method == 'POST' && q.path == '/login') {
      return q.json['user'] == '霜霜' && q.json['pass'] == '123' ? const FakeRes(200, {'token': 'tk-2'}) : const FakeRes(401, '密码不对');
    }
    if (q.token != 'tk-2') return const FakeRes(401, '没登录');
    if (q.path == '/goods' && q.method == 'GET') {
      if (_goodsFaults.isNotEmpty) {
        return _goodsFaults.removeAt(0) == 'hang' ? const FakeRes.hang() : const FakeRes(500, '坏了');
      }
      return FakeRes(200, goods);
    }
    final m = RegExp(r'^/goods/(\d+)$').firstMatch(q.path);
    if (m != null && q.method == 'GET') {
      final found = goods.where((g) => '${g['id']}' == m.group(1)).toList();
      return found.isEmpty ? const FakeRes(404, '没有这件') : FakeRes(200, found.single);
    }
    if (q.path == '/orders' && q.method == 'POST') {
      if (_orderFaults.isNotEmpty) {
        return _orderFaults.removeAt(0) == 'hang' ? const FakeRes.hang() : const FakeRes(500, '坏了');
      }
      final found = goods.where((g) => '${g['id']}' == '${q.json['id']}').toList();
      final qty = q.json['qty'];
      if (found.isEmpty || qty is! num || qty < 1) return const FakeRes(400, '单子不对');
      final g = found.single;
      if (qty > (g['stock']! as int)) return const FakeRes(409, '库存不够');
      g['stock'] = (g['stock']! as int) - qty.toInt();
      final order = {'no': 1001 + orders.length, 'total': (g['price']! as int) * qty.toInt(), 'addr': q.json['addr']};
      orders.add(order);
      return FakeRes(201, order);
    }
    return const FakeRes(404, '没有');
  }
}

J _req(String method, J url, {J? data, num timeout = 2000}) => authReq(kShopToken, method, url, data: data, timeout: timeout);
J _errArm() => catchArm('错误', 'e', [
  stSet('err', cat([tx('出错：'), getF(vr('e'), '消息')])),
]);
J _go(J path) => lb('router', 'go', {'path': path});
J _route(String pattern, String name) => lb('router', 'route', {'pattern': tx(pattern), 'name': tx(name)});
J _rule(String id, [J args = const {}, String msg = '']) => lx('form', id, {...args, 'msg': tx(msg)});
J _hasToken() => lx('storage', 'has', {'key': tx(kShopToken)});

/// 一块内容：只在“现在是哪一页”是 [name] 的时候在。
J _section(String id, String name, List<J> kids) => node(
  id,
  'column',
  {'gap': 8},
  kids,
  {
    'renderIf': fromExpr({
      'e': 'bin',
      'op': '==',
      'l': {'e': 'var', 'name': 'pg'},
      'r': {'e': 'text', 'v': name},
    }),
  },
);

/// 整个下单小应用（一页，四块内容）。[base]＝假服务的地址。
LcDocument shopApp(String base) => frontPage(
  [
    boundText('v_rdy', 'rdy'),
    boundText('v_pg', 'pg'),
    boundText('v_err', 'err'),
    _section('s_login', '登录', [inp('lg_user'), inp('lg_pass'), btn('lg_go', '登录'), boundText('lg_msg', 'msg')]),
    _section('s_shop', '商品', [
      btn('sp_retry', '重试'),
      repeatRow('sp_row', 'goods', [
        boundText('sp_name', 'it', ['name']),
        boundText('sp_stock', 'it', ['stock']),
        btn('sp_open', '看'),
      ]),
    ]),
    _section('s_item', '详情', [
      boundText('od_name', 'pname'),
      boundText('od_info', 'pinfo'),
      inp('od_qty'),
      boundText('e_qty', 'qtyErr'),
      inp('od_addr'),
      boundText('e_addr', 'addrErr'),
      btn('od_go', '下单'),
      btn('od_back', '返回'),
    ]),
    _section('s_ok', '成功', [boundText('ok_no', 'okno'), boundText('ok_total', 'oktotal'), btn('ok_again', '再逛逛')]),
    btn('out', '退出'),
  ],
  [
    textVar('rdy', '-'),
    textVar('pg', '-'),
    textVar('err'),
    textVar('msg', '请登录'),
    listVar('goods'),
    textVar('pname'),
    textVar('pinfo'),
    numVar('pstock'),
    textVar('pid'),
    textVar('qtyErr'),
    textVar('addrErr'),
    textVar('okno'),
    textVar('oktotal'),
  ],
  frontDoc(
    uses: [useLib('http'), useLib('storage'), useLib('form'), useLib('router')],
    functions: [
      tfn('f1', '加载商品', const [], [
        tryB(
          [
            let('res', _req('GET', tx('$base/goods'), timeout: 250)),
            iff(
              resOk('res'),
              [stSet('goods', resJson('res')), stSet('err', tx(''))],
              orElse: [
                stSet('err', cat([tx('取不到：'), resStatus('res')])),
              ],
            ),
          ],
          [_errArm()],
        ),
      ]),
      tfn(
        'f2',
        '加载这一件',
        [tpar('id', tText)],
        [
          tryB(
            [
              let('res', _req('GET', cat([tx('$base/goods/'), pm('id')]))),
              iff(
                resOk('res'),
                [
                  let('g', asDict(resJson('res'))),
                  stSet('pname', toText(at(vr('g'), 'name'))),
                  stSet('pinfo', cat([tx('单价 '), toText(at(vr('g'), 'price')), tx('，还有 '), toText(at(vr('g'), 'stock')), tx(' 件')])),
                  stSet('pstock', castTo(at(vr('g'), 'stock'), LType.number)),
                  stSet('err', tx('')),
                ],
                orElse: [
                  stSet('err', cat([tx('取不到：'), resStatus('res')])),
                ],
              ),
            ],
            [_errArm()],
          ),
        ],
      ),
      // 到了哪一块就取哪一块要的东西；没登录的一律回登录。“当路由变了”和“页面放上时”都叫它：
      // 页面放上时已经在的那条路由不算“变了”，得自己叫一次。
      tfn('f3', '到了这一页', const [], [
        let('name', lx('router', 'name')),
        iff(op2('!=', vr('name'), tx('登录')), [
          iff(
            notB(_hasToken()),
            [
              lb('router', 'replace', {'path': tx('/')}),
            ],
            orElse: [
              iff(op2('==', vr('name'), tx('商品')), [callS('f1')], noElse: true),
              iff(op2('==', vr('name'), tx('详情')), [
                stSet('pid', lx('router', 'param', {'name': tx('id')})),
                lb('form', 'clear', {'form': tx('订单')}),
                callS('f2', {
                  'id': lx('router', 'param', {'name': tx('id')}),
                }),
              ], noElse: true),
              iff(op2('==', vr('name'), tx('成功')), [
                stSet('okno', lx('router', 'param', {'name': tx('no')})),
              ], noElse: true),
            ],
          ),
        ], noElse: true),
      ]),
    ],
    hats: [
      mounted([
        _route('/', '登录'),
        _route('/shop', '商品'),
        _route('/item/:id', '详情'),
        _route('/ok/:no', '成功'),
        lb('router', 'bind', {'state': tx('pg')}),
        lb('form', 'rules', {
          'form': tx('订单'),
          'field': tx('数量'),
          'rules': ls([
            _rule('required'),
            _rule('range', {'min': nm(1), 'max': nm(99)}),
          ]),
        }),
        lb('form', 'rules', {
          'form': tx('订单'),
          'field': tx('地址'),
          'rules': ls([
            _rule('required'),
            _rule('minLen', {'n': nm(5)}, '地址太短'),
          ]),
        }),
        lb('form', 'bind', {'form': tx('订单'), 'field': tx('数量'), 'state': tx('qtyErr')}),
        lb('form', 'bind', {'form': tx('订单'), 'field': tx('地址'), 'state': tx('addrErr')}),
        // 登录过（本地存着令牌）就直接去商品。
        iff(_hasToken(), [
          lb('router', 'replace', {'path': tx('/shop')}),
        ], noElse: true),
        callS('f3'),
        stSet('rdy', tx('好了')),
      ]),
      // 自己的规则：数量不能比库存多（现成的规则都过了才查到这里）。
      libHat(
        'hc',
        'form',
        'custom',
        {'form': '订单', 'field': '数量'},
        [
          iff(op2('>', toNum(toText(lx('form', 'value'))), asNum(stGet('pstock'))), [
            lb('form', 'fail', {'msg': tx('库存不够')}),
          ], noElse: true),
        ],
      ),
      libHat('hr', 'router', 'onChange', const {}, [callS('f3')]),
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
                lb('storage', 'set', {'key': tx(kShopToken), 'value': at(asDict(resJson('res')), 'token')}),
                stSet('msg', tx('登录成功')),
                _go(tx('/shop')),
              ],
              orElse: [
                stSet('msg', cat([tx('登录失败（'), resStatus('res'), tx('）')])),
              ],
            ),
          ],
          [_errArm()],
        ),
      ]),
      onClick('h2', 'sp_retry', [callS('f1')]),
      onClick('h3', 'sp_open', [
        _go(
          cat([
            tx('/item/'),
            toText(ex(pg('eventItemField'), {'key': tx('id')})),
          ]),
        ),
      ]),
      onClick('h4', 'od_go', [
        iff(
          lx('form', 'checkAll', {
            'form': tx('订单'),
            'values': dc({'数量': valOf('od_qty'), '地址': valOf('od_addr')}),
          }),
          [
            tryB(
              [
                let('res', _req('POST', tx('$base/orders'), data: dc({'id': stGet('pid'), 'qty': toNum(valOf('od_qty')), 'addr': valOf('od_addr')}))),
                iff(
                  resOk('res'),
                  [
                    let('o', asDict(resJson('res'))),
                    stSet('oktotal', cat([tx('合计 '), toText(at(vr('o'), 'total')), tx(' 元')])),
                    stSet('err', tx('')),
                    _go(cat([tx('/ok/'), toText(at(vr('o'), 'no'))])),
                  ],
                  orElse: [
                    stSet('err', cat([tx('下单不成：'), resStatus('res')])),
                  ],
                ),
              ],
              [_errArm()],
            ),
          ],
          orElse: [stSet('err', tx('有格子没填对'))],
        ),
      ]),
      onClick('h5', 'od_back', [lb('router', 'back')]),
      onClick('h6', 'ok_again', [_go(tx('/shop'))]),
      onClick('h7', 'out', [
        lb('storage', 'remove', {'key': tx(kShopToken)}),
        stSet('msg', tx('请登录')),
        lb('router', 'replace', {'path': tx('/')}),
      ]),
    ],
  ),
  title: 'Shop',
);

Steps _login({String pass = '123'}) => [typeIn('lg_user', '霜霜'), typeIn('lg_pass', pass), click('lg_go')];
Steps _fill(String qty, String addr) => [typeIn('od_qty', qty), typeIn('od_addr', addr), click('od_go')];
const String _addr = '上海市某某路 1 号';

class ShopCase {
  ShopCase(this.name, this.world, this.steps, this.after);
  final String name;
  final ShopWorld world;
  final Steps Function(String kind) steps;
  final void Function(FakeApi api, ShopWorld world) after;
}

List<(String, int, int)> _goods() => [('杯子', 30, 2), ('本子', 12, 5), ('台灯', 99, 1)];

List<ShopCase> shopCases() => [
  ShopCase(
    '正常走通：登录、看商品、进详情、下单、成功页、再逛逛看到库存少了',
    ShopWorld(_goods()),
    (kind) => [
      netOn(),
      untilText('v_rdy', '好了'),
      textIs('v_pg', '登录'),
      countIs('lg_go', 1),
      countIs('sp_retry', 0),
      ..._login(),
      untilText('v_pg', '商品'),
      untilAt('sp_name', 0, '杯子'),
      countIs('sp_name', 3),
      textAt('sp_stock', 1, '5'),
      clickAt('sp_open', 1),
      untilText('v_pg', '详情'),
      {'op': 'hash', 'is': '#/item/2'},
      untilText('od_name', '本子'),
      textIs('od_info', '单价 12，还有 5 件'),
      ..._fill('2', _addr),
      untilText('v_pg', '成功'),
      {'op': 'hash', 'is': '#/ok/1001'},
      textIs('ok_no', '1001'),
      textIs('ok_total', '合计 24 元'),
      click('ok_again'),
      untilText('v_pg', '商品'),
      untilAt('sp_stock', 1, '3'),
    ],
    (api, world) {
      if (world.orders.length != 1 || world.orders.single['total'] != 24 || world.orders.single['addr'] != _addr) throw StateError('服务那头：${world.orders}');
    },
  ),
  ShopCase(
    '登录失败再重试；表单校验一条条拦：没填、不是数、不在范围、比库存多、地址太短；改对了才发出去',
    ShopWorld(_goods()),
    (kind) => [
      netOn(),
      untilText('v_rdy', '好了'),
      ..._login(pass: '000'),
      untilText('lg_msg', '登录失败（401）'),
      textIs('v_pg', '登录'),
      ..._login(),
      untilText('v_pg', '商品'),
      untilAt('sp_name', 0, '杯子'),
      clickAt('sp_open', 0),
      untilText('od_info', '单价 30，还有 2 件'),
      ..._fill('', ''),
      untilText('v_err', '有格子没填对'),
      textIs('e_qty', '这一格要填'),
      textIs('e_addr', '这一格要填'),
      ..._fill('abc', _addr),
      untilText('e_qty', '要填一个数'),
      textIs('e_addr', ''),
      ..._fill('0', _addr),
      untilText('e_qty', '要在 1 和 99 之间'),
      ..._fill('3', '短'),
      untilText('e_qty', '库存不够'),
      textIs('e_addr', '地址太短'),
      textIs('v_pg', '详情'),
      ..._fill('2', _addr),
      untilText('v_pg', '成功'),
      textIs('ok_total', '合计 60 元'),
      textIs('v_err', ''),
    ],
    (api, world) {
      // 不合格的五次一次都没发到服务那头。
      if (api.hit('POST /orders') != 1 || api.hit('POST /login') != 2) throw StateError('请求次数：${api.hits}');
      if (world.goods[0]['stock'] != 0) throw StateError('服务那头：${world.goods}');
    },
  ),
  ShopCase(
    '取商品先超时、再报错，重试后恢复；关掉再开还在登录；后退；下单时服务报错、再点一次成了；退出',
    ShopWorld(_goods(), goodsFaults: ['hang', '500'], orderFaults: ['500']),
    (kind) => [
      netOn(),
      untilText('v_rdy', '好了'),
      ..._login(),
      untilText('v_err', '出错：超时'),
      textIs('v_pg', '商品'),
      countIs('sp_name', 0),
      click('sp_retry'),
      untilText('v_err', '取不到：500'),
      click('sp_retry'),
      untilAt('sp_name', 2, '台灯'),
      textIs('v_err', ''),
      ...reopen(),
      untilText('v_pg', '商品'),
      untilAt('sp_name', 2, '台灯'),
      clickAt('sp_open', 2),
      untilText('od_name', '台灯'),
      click('od_back'),
      untilText('v_pg', '商品'),
      clickAt('sp_open', 2),
      untilText('v_pg', '详情'),
      untilText('od_name', '台灯'),
      ..._fill('1', _addr),
      untilText('v_err', '下单不成：500'),
      textIs('v_pg', '详情'),
      click('od_go'),
      untilText('v_pg', '成功'),
      textIs('ok_no', '1001'),
      click('out'),
      untilText('v_pg', '登录'),
      storedIs(kShopToken, null),
      textIs('lg_msg', '请登录'),
    ],
    (api, world) {
      if (api.hanging != 1) throw StateError('拖着没回的有 ${api.hanging} 个');
      if (api.hit('POST /orders') != 2 || world.orders.length != 1) throw StateError('下单：${api.hits} ${world.orders}');
    },
  ),
];
