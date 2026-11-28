// 小应用乙组·“活动报名（多语言）”的四组样例：每组自己一个假服务的世界、自己的一串步骤、跑完以后对假服务那头的核对。
// 四组走的路不一样：中文正常走通（页里进详情又退回）；切成英文＋登录失败再重试＋表单校验拦下＋关掉再开＋切回中文＋退出；
// 取列表超时、服务报错后重试恢复＋名额被抢完＋提交超时、报错后再提交成功；空列表。
import 'front_app_b_events.dart';
import 'front_app_b_kit.dart';
import 'front_libs_samples.dart';

// —— 步骤 ——
/// 一打开是首页：没登录，被送去登录页。
Steps _start(String kind) => [netOn(), ...arriveAt(kind, 'login', wait: untilText('ev_err', '没登录'), ready: untilText('lg_rdy', '好了'))];
Steps _loginOk(String kind, {String said = '登录成功'}) => [
  typeIn('lg_user', '霜霜'),
  typeIn('lg_pass', '123'),
  click('lg_go'),
  ...arriveAt(kind, 'events', home: true, wait: untilText('lg_msg', said), ready: untilText('ev_rdy', '好了')),
];
Steps _toSignup(String kind) => [click('dt_go'), ...arriveAt(kind, 'signup', ready: untilText('su_rdy', '好了'))];
Steps _fill(String name, String phone, String mail, String n) => [typeIn('su_name', name), typeIn('su_phone', phone), typeIn('su_mail', mail), typeIn('su_n', n)];
Steps _submitBack(String kind, {String said = '报名成功'}) => [click('su_go'), ...arriveAt(kind, 'events', home: true, wait: untilText('su_msg', said), ready: untilText('ev_rdy', '好了'))];

class EvCase {
  EvCase(this.name, this.world, this.steps, this.after);
  final String name;
  final EvWorld world;
  final Steps Function(String kind) steps;
  final void Function(FakeApi api, EvWorld world) after;
}

List<EvCase> eventsCases() => [
  EvCase(
    '中文正常走通：登录、看列表、页里进详情又退回、再进另一个、报名、回列表看到名额少了',
    EvWorld([('读书会', 'Book club', 5), ('徒步', 'Hiking', 3)]),
    (kind) => [
      ..._start(kind),
      textIs('lg_h', '登录'),
      textIs('lg_msg', '请登录'),
      ..._loginOk(kind),
      textIs('ev_h', '活动'),
      shownIs('ev_list', true),
      shownIs('ev_detail', false),
      countIs('ev_title', 2),
      textAt('ev_title', 0, '读书会'),
      textAt('ev_left', 0, '剩 5 个名额'),
      textIs('ev_sum', '共 2 个活动'),
      clickAt('ev_open', 1),
      untilText('dt_title', '徒步'),
      hashIs('#/event/2'),
      shownIs('ev_detail', true),
      shownIs('ev_list', false),
      textIs('dt_desc', '徒步的介绍'),
      textIs('dt_left', '剩 3 个名额'),
      click('dt_back'),
      hashIs('#/'),
      shownIs('ev_list', true),
      shownIs('ev_detail', false),
      clickAt('ev_open', 0),
      untilText('dt_title', '读书会'),
      ..._toSignup(kind),
      textIs('su_h', '报名：读书会'),
      ..._fill('霜霜', '13800001111', 'a@b.com', '2'),
      ..._submitBack(kind),
      shownIs('ev_list', true),
      textAt('ev_left', 0, '剩 3 个名额'),
      textAt('ev_left', 1, '剩 3 个名额'),
    ],
    (api, world) {
      if (world.leftOf(1) != 3 || world.signups.length != 1 || world.signups.single['name'] != '霜霜' || world.signups.single['n'] != 2) throw StateError('服务那头：${world.events} ${world.signups}');
      if (api.hit('POST /events/1/signup') != 1 || api.hit('GET /events/2') != 1) throw StateError('请求次数：${api.hits}');
    },
  ),
  EvCase(
    '切成英文：登录失败再重试；报名表填错被表单校验拦下（英文的话）、改对提交；关掉再开语言和登录都还在；切回中文；退出',
    EvWorld([('读书会', 'Book club', 5), ('徒步', 'Hiking', 3)]),
    (kind) => [
      ..._start(kind),
      click('lg_lang'),
      untilText('lg_h', 'Sign in'),
      textIs('lg_lang', '中文'),
      textIs('lg_msg', 'Please sign in'),
      storedIs(kEvLang, '"English"'),
      typeIn('lg_user', '霜霜'),
      typeIn('lg_pass', '000'),
      click('lg_go'),
      untilText('lg_msg', 'Sign-in failed (401)'),
      storedIs(kEvToken, null),
      ..._loginOk(kind, said: 'Signed in'),
      textIs('ev_h', 'Events'),
      textAt('ev_title', 0, 'Book club'),
      textAt('ev_left', 1, '3 left'),
      textIs('ev_sum', '2 events'),
      clickAt('ev_open', 1),
      untilText('dt_title', 'Hiking'),
      textIs('dt_desc', 'About Hiking'),
      textIs('dt_go', 'Sign up'),
      ..._toSignup(kind),
      textIs('su_h', 'Sign up: Hiking'),
      // 什么都没填就提交：必填的三格报错，邮箱可以不填。
      click('su_go'),
      untilText('su_msg', 'Please fix the fields above'),
      untilText('su_e1', 'Required'),
      untilText('su_e2', 'Required'),
      textIs('su_e3', ''),
      untilText('su_e4', 'Required'),
      // 四格都填错。
      ..._fill('霜', '138-0000', 'a@b', '9'),
      click('su_go'),
      untilText('su_e1', 'Name needs 2+ characters'),
      untilText('su_e2', 'Digits only'),
      untilText('su_e3', 'Invalid email'),
      untilText('su_e4', 'Between 1 and 3'),
      ..._fill('Shuang', '13800002222', 's@x.io', '3'),
      ..._submitBack(kind, said: 'Signed up'),
      textAt('ev_left', 1, '0 left'),
      ...reopen(),
      untilText('ev_rdy', '好了'),
      textIs('ev_h', 'Events'),
      textAt('ev_title', 1, 'Hiking'),
      textAt('ev_left', 1, '0 left'),
      click('ev_lang'),
      untilText('ev_h', '活动'),
      untilAt('ev_title', 1, '徒步'),
      textAt('ev_left', 1, '剩 0 个名额'),
      textIs('ev_sum', '共 2 个活动'),
      storedIs(kEvLang, '"中文"'),
      click('ev_out'),
      ...arriveAt(kind, 'login', wait: untilText('ev_err', '已退出'), ready: untilText('lg_msg', '请登录')),
      textIs('lg_h', '登录'),
      storedIs(kEvToken, null),
    ],
    (api, world) {
      if (api.hit('POST /login') != 2) throw StateError('登录了 ${api.hit('POST /login')} 次');
      // 填错的那两次没有发出去：表单校验在页面这头就拦下了。
      if (api.hit('POST /events/2/signup') != 1) throw StateError('提交了 ${api.hit('POST /events/2/signup')} 次');
      if (world.leftOf(2) != 0 || world.signups.single['mail'] != 's@x.io') throw StateError('服务那头：${world.events} ${world.signups}');
    },
  ),
  EvCase(
    '取列表先超时、再服务报错，重试后恢复；名额被别人抢完（服务说满了）；换一个活动，提交先超时、再报错、第三次成',
    EvWorld([('读书会', 'Book club', 5), ('徒步', 'Hiking', 3)], listFaults: ['hang', '500'], signupFaults: ['hang', '500'], soldOut: {1}),
    (kind) => [
      ..._start(kind),
      ..._loginOk(kind),
      textIs('ev_err', '出错：超时'),
      countIs('ev_title', 0),
      click('ev_retry'),
      untilText('ev_err', '取不到：500'),
      countIs('ev_title', 0),
      click('ev_retry'),
      untilText('ev_err', ''),
      countIs('ev_title', 2),
      clickAt('ev_open', 0),
      untilText('dt_title', '读书会'),
      ..._toSignup(kind),
      ..._fill('霜霜', '13800001111', '', '1'),
      click('su_go'),
      untilText('su_msg', '名额满了'),
      click('su_back'),
      ...arriveAt(kind, 'events', home: true, wait: untilText('su_msg', '返回'), ready: untilText('ev_rdy', '好了')),
      textAt('ev_left', 0, '剩 0 个名额'),
      clickAt('ev_open', 1),
      untilText('dt_title', '徒步'),
      ..._toSignup(kind),
      ..._fill('霜霜', '13800001111', '', '1'),
      click('su_go'),
      untilText('su_msg', '出错：超时'),
      click('su_go'),
      untilText('su_msg', '提交失败（500）'),
      ..._submitBack(kind),
      textAt('ev_left', 1, '剩 2 个名额'),
    ],
    (api, world) {
      // 超时的两次（取列表一次、提交一次）：等的人走了，假服务手上还拖着两个没回的。
      if (api.hanging != 2) throw StateError('拖着没回的有 ${api.hanging} 个');
      if (api.hit('POST /events/2/signup') != 3 || api.hit('POST /events/1/signup') != 1) throw StateError('请求次数：${api.hits}');
      if (world.leftOf(2) != 2 || world.leftOf(1) != 0 || world.signups.length != 1) throw StateError('服务那头：${world.events} ${world.signups}');
    },
  ),
  EvCase(
    '一个活动都没有：空列表的提示（中英都看一眼）；退出回到登录页',
    EvWorld(const []),
    (kind) => [
      ..._start(kind),
      ..._loginOk(kind),
      countIs('ev_title', 0),
      textIs('ev_sum', '暂无活动'),
      click('ev_lang'),
      untilText('ev_sum', 'No events yet'),
      textIs('ev_h', 'Events'),
      click('ev_out'),
      ...arriveAt(kind, 'login', wait: untilText('ev_err', 'Signed out'), ready: untilText('lg_msg', 'Please sign in')),
      textIs('lg_h', 'Sign in'),
    ],
    (api, world) {
      if (api.hit('GET /events') != 1 || world.signups.isNotEmpty) throw StateError('请求次数：${api.hits}');
    },
  ),
];
