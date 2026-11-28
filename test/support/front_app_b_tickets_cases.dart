// 小应用乙组·“用户自己写的 JS 库驱动”的工单小应用：假服务这一头的世界、四组样例（每组自己的数据和步骤、跑完对假服务的核对）。
// 头两组和第四组靠“会话与接口”库；第三组换成“金额与格式”＋“通知”两个库。
import 'front_app_b_kit.dart';
import 'front_app_b_tickets.dart';
import 'front_libs_samples.dart';

/// 假服务的工单世界。[listFaults] / [replyFaults]＝头几次出的岔子（'hang' 拖着不回、'500' 报错）；[gone]＝列表上还有、其实已经被删了的工单。
class TkWorld {
  TkWorld(List<(String title, int fee, List<String> replies)> start, {List<String> listFaults = const [], List<String> replyFaults = const [], this.gone = const {}})
    : _listFaults = [...listFaults],
      _replyFaults = [...replyFaults] {
    for (final (title, fee, replies) in start) {
      tickets.add({
        'id': tickets.length + 1,
        'title': title,
        'fee': fee,
        'body': '$title的经过',
        'replies': [...replies],
      });
    }
  }
  final List<Map<String, Object?>> tickets = [];
  final List<String> _listFaults;
  final List<String> _replyFaults;
  final Set<int> gone;

  List<Object?> repliesOf(int id) => tickets.firstWhere((t) => t['id'] == id)['replies']! as List<Object?>;

  FakeRes handle(FakeReq q) {
    if (q.method == 'POST' && q.path == '/login') {
      return q.json['user'] == '霜霜' && q.json['pass'] == '123' ? const FakeRes(200, {'token': 'tk-7'}) : const FakeRes(401, '密码不对');
    }
    if (q.token != 'tk-7') return const FakeRes(401, '没登录');
    if (q.path == '/tickets' && q.method == 'GET') {
      if (_listFaults.isNotEmpty) return _listFaults.removeAt(0) == 'hang' ? const FakeRes.hang() : const FakeRes(500, '坏了');
      return FakeRes(200, [
        for (final t in tickets) {'id': t['id'], 'title': t['title'], 'fee': t['fee'], 'n': (t['replies']! as List).length},
      ]);
    }
    final m = RegExp(r'^/tickets/(\d+)(/replies)?$').firstMatch(q.path);
    if (m == null) return const FakeRes(404, '没有');
    final found = tickets.where((t) => '${t['id']}' == m.group(1) && !gone.contains(t['id'])).toList();
    if (found.isEmpty) return const FakeRes(404, '没有这张工单');
    final t = found.single;
    if (m.group(2) == null && q.method == 'GET') return FakeRes(200, t);
    if (m.group(2) != null && q.method == 'POST') {
      if (_replyFaults.isNotEmpty) return _replyFaults.removeAt(0) == 'hang' ? const FakeRes.hang() : const FakeRes(500, '坏了');
      final text = '${q.json['text'] ?? ''}'.trim();
      if (text.isEmpty) return const FakeRes(400, '空的');
      (t['replies']! as List).add(text);
      return FakeRes(200, {'n': (t['replies']! as List).length});
    }
    return const FakeRes(404, '没有');
  }
}

Steps _start(String kind) => [netOn(), ...arriveAt(kind, 'login', wait: untilText('tk_err', '没登录'), ready: untilText('lg_rdy', '好了'))];
Steps _login(String kind) => [
  typeIn('lg_user', '霜霜'),
  typeIn('lg_pass', '123'),
  click('lg_go'),
  ...arriveAt(kind, 'tickets', home: true, wait: untilText('lg_msg', '登录成功'), ready: untilText('tk_rdy', '好了')),
];
Steps _open(String kind, int at) => [clickAt('tk_open', at), ...arriveAt(kind, 'ticket', ready: untilText('tt_rdy', '好了'))];
Steps _back(String kind) => [click('tt_back'), ...arriveAt(kind, 'tickets', home: true, wait: untilText('tt_msg', '返回'), ready: untilText('tk_rdy', '好了'))];
Map<String, Object?> _valueIs(String id, String v) => {'op': 'value', 'sel': '.n-$id', 'is': v};

class TkCase {
  TkCase(this.name, this.kit, this.world, this.steps, this.after);
  final String name;
  final TkKit kit;
  final TkWorld world;
  final Steps Function(String kind) steps;
  final void Function(FakeApi api, TkWorld world) after;
}

List<TkCase> ticketCases() => [
  TkCase(
    '“会话与接口”库·正常走通：登录、看列表、进详情、提交两条回复、回列表看到回复数变了',
    const TkKit(),
    TkWorld([
      ('打印机坏了', 80, ['收到']),
      ('网络很慢', 0, []),
    ]),
    (kind) => [
      ..._start(kind),
      textIs('lg_msg', '请登录'),
      ..._login(kind),
      textIs('tk_err', ''),
      countIs('tk_title', 2),
      textAt('tk_title', 0, '打印机坏了'),
      textAt('tk_n', 0, '1 条回复'),
      textAt('tk_n', 1, '0 条回复'),
      textIs('tk_sum', '共 2 张'),
      ..._open(kind, 1),
      textIs('tt_title', '网络很慢'),
      textIs('tt_body', '网络很慢的经过'),
      countIs('tt_reply', 0),
      typeIn('tt_in', '重启路由器试试'),
      click('tt_go'),
      untilText('tt_msg', '已提交'),
      {'op': 'until', 'sel': '.n-tt_reply', 'at': 0, 'is': '重启路由器试试'},
      _valueIs('tt_in', ''),
      typeIn('tt_in', '好了'),
      click('tt_go'),
      {'op': 'until', 'sel': '.n-tt_reply', 'at': 1, 'is': '好了'},
      countIs('tt_reply', 2),
      ..._back(kind),
      textAt('tk_n', 1, '2 条回复'),
      storedIs(kTkToken, '"tk-7"'),
    ],
    (api, world) {
      if (world.repliesOf(2).join('|') != '重启路由器试试|好了' || world.repliesOf(1).length != 1) throw StateError('服务那头：${world.tickets}');
      if (api.hit('POST /tickets/2/replies') != 2 || api.hit('GET /tickets/2') != 3) throw StateError('请求次数：${api.hits}');
    },
  ),
  TkCase(
    '“会话与接口”库·一路出岔子：密码错再重试；取列表超时、报错后重试；工单已被删；空回复不发；提交超时、报错后第三次成；关掉再开还登录着；退出',
    const TkKit(),
    TkWorld(
      [
        ('打印机坏了', 80, ['收到']),
        ('网络很慢', 0, []),
        ('要一台显示器', 900, ['在批', '批了']),
      ],
      listFaults: ['hang', '500'],
      replyFaults: ['hang', '500'],
      gone: {1},
    ),
    (kind) => [
      ..._start(kind),
      typeIn('lg_user', '霜霜'),
      typeIn('lg_pass', '321'),
      click('lg_go'),
      untilText('lg_msg', '服务说不行（401）'),
      storedIs(kTkToken, null),
      ..._login(kind),
      textIs('tk_err', '出错：超时'),
      countIs('tk_title', 0),
      click('tk_retry'),
      untilText('tk_err', '服务说不行（500）'),
      click('tk_retry'),
      untilText('tk_sum', '共 3 张'),
      textIs('tk_err', ''),
      countIs('tk_title', 3),
      ..._open(kind, 0),
      textIs('tt_msg', '服务说不行（404）'),
      textIs('tt_title', '-'), // 没取到：标题还是开始的样子
      ..._back(kind),
      ..._open(kind, 2),
      textIs('tt_title', '要一台显示器'),
      countIs('tt_reply', 2),
      click('tt_go'),
      untilText('tt_msg', '写点什么再提交'),
      typeIn('tt_in', '什么时候到'),
      click('tt_go'),
      untilText('tt_msg', '出错：超时'),
      _valueIs('tt_in', '什么时候到'),
      click('tt_go'),
      untilText('tt_msg', '服务说不行（500）'),
      countIs('tt_reply', 2),
      click('tt_go'),
      untilText('tt_msg', '已提交'),
      {'op': 'until', 'sel': '.n-tt_reply', 'at': 2, 'is': '什么时候到'},
      ..._back(kind),
      textAt('tk_n', 2, '3 条回复'),
      ...reopen(),
      untilText('tk_sum', '共 3 张'),
      textAt('tk_title', 2, '要一台显示器'),
      click('tk_out'),
      ...arriveAt(kind, 'login', wait: untilText('tk_err', '已退出'), ready: untilText('lg_msg', '请登录')),
      storedIs(kTkToken, null),
    ],
    (api, world) {
      if (api.hanging != 2) throw StateError('拖着没回的有 ${api.hanging} 个');
      if (api.hit('POST /login') != 2 || api.hit('POST /tickets/3/replies') != 3 || api.hit('GET /tickets/1') != 1) throw StateError('请求次数：${api.hits}');
      if (world.repliesOf(3).join('|') != '在批|批了|什么时候到') throw StateError('服务那头：${world.tickets}');
    },
  ),
  TkCase(
    '换两个库（“金额与格式”＋“通知”）：列表上的标价和合计、详情里要不要主管批、提交后收到通知并数着条数',
    const TkKit(rich: true),
    TkWorld([
      ('打车', 45, []),
      ('请客户吃饭', 320, ['发票呢']),
      ('买书', 99, []),
    ]),
    (kind) => [
      ..._start(kind),
      ..._login(kind),
      countIs('tk_title', 3),
      textAt('tk_fee', 0, '¥45'),
      textAt('tk_fee', 1, '¥320'),
      textIs('tk_sum', '共 3 张，合计 ¥464'),
      ..._open(kind, 1),
      textIs('tt_fee', '¥320'),
      textIs('tt_flag', '要主管批'),
      textIs('tt_cnt', '0 条通知'),
      textIs('tt_note', '-'),
      typeIn('tt_in', '补上了'),
      click('tt_go'),
      untilText('tt_note', '工单 2 有新回复：补上了'),
      textIs('tt_cnt', '1 条通知'),
      untilText('tt_msg', '已提交'),
      {'op': 'until', 'sel': '.n-tt_reply', 'at': 1, 'is': '补上了'},
      typeIn('tt_in', '谢谢'),
      click('tt_go'),
      untilText('tt_note', '工单 2 有新回复：谢谢'),
      textIs('tt_cnt', '2 条通知'),
      ..._back(kind),
      textAt('tk_n', 1, '3 条回复'),
      ..._open(kind, 0),
      textIs('tt_fee', '¥45'),
      textIs('tt_flag', '不用批'),
    ],
    (api, world) {
      if (world.repliesOf(2).join('|') != '发票呢|补上了|谢谢') throw StateError('服务那头：${world.tickets}');
      if (api.hit('POST /tickets/2/replies') != 2) throw StateError('请求次数：${api.hits}');
    },
  ),
  TkCase(
    '“会话与接口”库·一张工单都没有：空列表的提示；退出回登录页，再登录进来',
    const TkKit(),
    TkWorld(const []),
    (kind) => [
      ..._start(kind),
      ..._login(kind),
      countIs('tk_title', 0),
      textIs('tk_sum', '没有工单'),
      click('tk_out'),
      ...arriveAt(kind, 'login', wait: untilText('tk_err', '已退出'), ready: untilText('lg_msg', '请登录')),
      ..._login(kind),
      textIs('tk_sum', '没有工单'),
    ],
    (api, world) {
      if (api.hit('POST /login') != 2 || api.hit('GET /tickets') != 2) throw StateError('请求次数：${api.hits}');
    },
  ),
];
