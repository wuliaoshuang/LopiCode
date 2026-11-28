// 小应用乙组·“用户组件库＋JS 库”的会议室预订：假服务这一头的世界、三组样例。
import 'comp_steps.dart';
import 'front_app_b_kit.dart';
import 'front_app_b_rooms.dart';
import 'front_libs_samples.dart';

/// 假服务的会议室世界。[listFaults] / [bookFaults]＝头几次出的岔子（'hang' 拖着不回、'500' 报错）；同一间同一时段订过了回 409。
class RmWorld {
  RmWorld(List<(String title, int seats, List<String> taken)> start, {List<String> listFaults = const [], List<String> bookFaults = const []})
    : _listFaults = [...listFaults],
      _bookFaults = [...bookFaults] {
    for (final (title, seats, taken) in start) {
      rooms.add({
        'id': rooms.length + 1,
        'title': title,
        'seats': seats,
        'slots': [...taken],
      });
    }
  }
  final List<Map<String, Object?>> rooms = [];
  final List<Map<String, Object?>> books = [];
  final List<String> _listFaults;
  final List<String> _bookFaults;

  List<Object?> slotsOf(int id) => rooms.firstWhere((r) => r['id'] == id)['slots']! as List<Object?>;

  FakeRes handle(FakeReq q) {
    if (q.method == 'POST' && q.path == '/login') {
      return q.json['user'] == '霜霜' && q.json['pass'] == '123' ? const FakeRes(200, {'token': 'tk-7'}) : const FakeRes(401, '密码不对');
    }
    if (q.token != 'tk-7') return const FakeRes(401, '没登录');
    if (q.path == '/rooms' && q.method == 'GET') {
      if (_listFaults.isNotEmpty) return _listFaults.removeAt(0) == 'hang' ? const FakeRes.hang() : const FakeRes(500, '坏了');
      return FakeRes(200, [
        for (final r in rooms) {'id': r['id'], 'title': r['title'], 'seats': r['seats'], 'n': (r['slots']! as List).length},
      ]);
    }
    final m = RegExp(r'^/rooms/(\d+)(/book)?$').firstMatch(q.path);
    if (m == null) return const FakeRes(404, '没有');
    final found = rooms.where((r) => '${r['id']}' == m.group(1)).toList();
    if (found.isEmpty) return const FakeRes(404, '没有这间');
    final r = found.single;
    final slots = r['slots']! as List;
    if (m.group(2) == null && q.method == 'GET') {
      return FakeRes(200, {'id': r['id'], 'title': r['title'], 'seats': r['seats'], 'taken': slots.isEmpty ? '无' : slots.join('、')});
    }
    if (m.group(2) != null && q.method == 'POST') {
      if (_bookFaults.isNotEmpty) return _bookFaults.removeAt(0) == 'hang' ? const FakeRes.hang() : const FakeRes(500, '坏了');
      final slot = '${q.json['slot'] ?? ''}'.trim();
      if (slot.isEmpty) return const FakeRes(400, '没说时段');
      if (slots.contains(slot)) return const FakeRes(409, '订过了');
      slots.add(slot);
      books.add({'room': r['id'], ...q.json});
      return const FakeRes(200, {'ok': true});
    }
    return const FakeRes(404, '没有');
  }
}

/// Vue / React 里组件是单独的文件：找组件里面控件的写法跟着换。
Steps _fit(String kind, Steps steps) => kind == 'html' ? steps : compFileSteps(steps, kRoomsDefs);

Steps _start(String kind) => [netOn(), ...arriveAt(kind, 'login', wait: untilText('rm_err', '没登录'), ready: untilText('lg_rdy', '好了'))];
Steps _login(String kind, {String pass = '123'}) => [
  typeIn('lgf__userIn', '霜霜'),
  typeIn('lgf__passIn', pass),
  click('lgf__go'),
  if (pass == '123') ...arriveAt(kind, 'rooms', home: true, wait: untilText('lg_msg', '登录成功'), ready: untilText('rm_rdy', '好了')),
];
Steps _open(String kind, int at) => [clickAt('rm__open', at), ...arriveAt(kind, 'room', ready: untilText('ro_rdy', '好了'))];
Steps _book(String who, String slot) => [typeIn('bk__whoIn', who), typeIn('bk__slotIn', slot), click('bk__go')];
Steps _autoBack(String kind) => arriveAt(kind, 'rooms', home: true, wait: untilText('ro_msg', '回列表'), ready: untilText('rm_rdy', '好了'));
Map<String, Object?> _valueIs(String id, String v) => {'op': 'value', 'sel': '.n-$id', 'is': v};

class RmCase {
  RmCase(this.name, this.world, Steps Function(String kind) steps, this.after) : steps = ((kind) => _fit(kind, steps(kind)));
  final String name;
  final RmWorld world;
  final Steps Function(String kind) steps;
  final void Function(FakeApi api, RmWorld world) after;
}

List<RmCase> roomCases() => [
  RmCase(
    '正常走通：登录块登录、房间项列表、点第二间的“看看”、信息卡、预订块订一个时段、过一会儿自动回列表看到次数变了',
    RmWorld([
      ('大会议室', 12, ['周一上午']),
      ('小会议室', 4, []),
    ]),
    (kind) => [
      ..._start(kind),
      textIs('lg_msg', '请登录'),
      ..._login(kind),
      countIs('rm__name', 2),
      textAt('rm__name', 0, '大会议室'),
      textAt('rm__note', 0, '坐 12 人，订了 1 次'),
      textAt('rm__note', 1, '坐 4 人，订了 0 次'),
      textIs('rm_sum', '共 2 间'),
      ..._open(kind, 1),
      textIs('info__head', '小会议室'),
      textIs('info__text', '坐 4 人'),
      textIs('ro_taken', '已订：无'),
      ..._book('霜霜', '周二下午'),
      untilText('ro_msg', '订好了，马上回列表'),
      untilText('ro_taken', '已订：周二下午'),
      ..._autoBack(kind),
      textAt('rm__note', 1, '坐 4 人，订了 1 次'),
    ],
    (api, world) {
      if (world.slotsOf(2).join('|') != '周二下午' || world.books.single['who'] != '霜霜') throw StateError('服务那头：${world.rooms} ${world.books}');
      if (api.hit('POST /rooms/2/book') != 1) throw StateError('请求次数：${api.hits}');
    },
  ),
  RmCase(
    '一路出岔子：密码错（密码那格被清掉）再重试；取列表超时、报错后重试；没写谁订不发；时段订过了；提交超时、报错后成；点“留在这里”取消自动回列表，再手动返回；退出',
    RmWorld(
      [
        ('大会议室', 12, ['周一上午']),
        ('小会议室', 4, []),
        ('电话间', 1, []),
      ],
      listFaults: ['hang', '500'],
      bookFaults: ['hang', '500'],
    ),
    (kind) => [
      ..._start(kind),
      ..._login(kind, pass: '000'),
      untilText('lg_msg', '服务说不行（401）'),
      _valueIs('lgf__passIn', ''),
      _valueIs('lgf__userIn', '霜霜'),
      ..._login(kind),
      textIs('rm_err', '出错：超时'),
      countIs('rm__name', 0),
      click('rm_retry'),
      untilText('rm_err', '服务说不行（500）'),
      click('rm_retry'),
      untilText('rm_sum', '共 3 间'),
      ..._open(kind, 0),
      textIs('ro_taken', '已订：周一上午'),
      ..._book('', '周一上午'),
      untilText('ro_msg', '写上谁订'),
      // 头一次真发出去的那次被拖住（超时），第二次服务报错，第三次才到“订过了”。
      ..._book('霜霜', '周一上午'),
      untilText('ro_msg', '出错：超时'),
      click('bk__go'),
      untilText('ro_msg', '服务说不行（500）'),
      click('bk__go'),
      untilText('ro_msg', '服务说不行（409）'),
      _valueIs('bk__slotIn', '周一上午'),
      typeIn('bk__slotIn', '周一下午'),
      click('bk__go'),
      untilText('ro_msg', '订好了，马上回列表'),
      click('ro_stay'),
      untilText('ro_msg', '留在这里'),
      untilText('ro_taken', '已订：周一上午、周一下午'),
      _valueIs('bk__slotIn', ''),
      // 等得比定时久：没有自动回列表（话没有变成“回列表”）。
      waitMs(700),
      textIs('ro_msg', '留在这里'),
      click('ro_back'),
      ...arriveAt(kind, 'rooms', home: true, wait: untilText('ro_msg', '返回'), ready: untilText('rm_rdy', '好了')),
      textAt('rm__note', 0, '坐 12 人，订了 2 次'),
      click('rm_out'),
      ...arriveAt(kind, 'login', wait: untilText('rm_err', '已退出'), ready: untilText('lg_msg', '请登录')),
      storedIs(kRmToken, null),
    ],
    (api, world) {
      if (api.hanging != 2) throw StateError('拖着没回的有 ${api.hanging} 个');
      if (api.hit('POST /login') != 2 || api.hit('POST /rooms/1/book') != 4) throw StateError('请求次数：${api.hits}');
      if (world.slotsOf(1).join('|') != '周一上午|周一下午' || world.books.length != 1) throw StateError('服务那头：${world.rooms} ${world.books}');
    },
  ),
  RmCase(
    '一间都没有：空列表的提示；关掉再开还登录着；退出再登录',
    RmWorld(const []),
    (kind) => [
      ..._start(kind),
      ..._login(kind),
      countIs('rm__name', 0),
      textIs('rm_sum', '没有会议室'),
      ...reopen(),
      untilText('rm_sum', '没有会议室'),
      storedIs(kRmToken, '"tk-7"'),
      click('rm_out'),
      ...arriveAt(kind, 'login', wait: untilText('rm_err', '已退出'), ready: untilText('lg_msg', '请登录')),
      ..._login(kind),
      textIs('rm_sum', '没有会议室'),
    ],
    (api, world) {
      if (api.hit('POST /login') != 2 || api.hit('GET /rooms') != 3) throw StateError('请求次数：${api.hits}');
    },
  ),
];
