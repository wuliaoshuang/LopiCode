// 小应用甲组·“笔记”的三组样例（步骤）。
import 'front_app_a_kit.dart';
import 'front_app_a_note.dart';
import 'front_libs_samples.dart';

class NoteCase {
  NoteCase(this.name, this.world, this.steps, this.after);
  final String name;
  final NoteWorld world;
  final Steps Function(String kind) steps;
  final void Function(FakeApi api, NoteWorld world) after;
}

Steps _login(String kind, {String pass = '123'}) => [typeIn('lg_user', '霜霜'), typeIn('lg_pass', pass), click('lg_go')];
Steps _toList(String kind, Map<String, Object?> wait) => arriveAt(kind, 'list', wait: wait, ready: untilText('ls_rdy', '好了'));
Steps _open(String kind, int at) => [clickAt('ls_open', at), ...arriveAt(kind, 'edit', ready: untilText('ed_rdy', '好了'))];
Steps _save(String title, String body) => [typeIn('ed_title', title), typeIn('ed_body', body), click('ed_save')];

List<(String, String)> _two() => [('买菜', '鸡蛋和葱'), ('读书', '第三章')];

List<NoteCase> noteCases() => [
  NoteCase(
    '正常走通：登录、列表（两件事同时取）、进详情、改了提交、回列表看到变化',
    NoteWorld(_two()),
    (kind) => [
      netOn(),
      untilText('lg_msg', '请登录'),
      ..._login(kind),
      ..._toList(kind, untilText('lg_msg', '登录成功')),
      untilText('ls_sum', '霜霜：2 篇，共 7 字'),
      countIs('ls_title', 2),
      textAt('ls_title', 1, '读书'),
      ..._open(kind, 1),
      textIs('ed_now', '读书｜第三章'),
      {'op': 'value', 'sel': '.n-ed_title', 'is': '读书'},
      ..._save('读完了', '第三章和第四章'),
      ..._toList(kind, untilText('ed_msg', '存好了，这一回存了 1 次')),
      untilText('ls_sum', '霜霜：2 篇，共 11 字'),
      textAt('ls_title', 1, '读完了'),
    ],
    (api, world) {
      if (world.notes[1]['title'] != '读完了' || world.notes[1]['body'] != '第三章和第四章') throw StateError('服务那头：${world.notes}');
      if (api.hit('GET /me') != 2) throw StateError('请求次数：${api.hits}');
    },
  ),
  NoteCase(
    '登录失败再重试；草稿自己查出毛病（标题空、正文太长）不发请求；服务说重名（409）；改对了存上',
    NoteWorld(_two()),
    (kind) => [
      netOn(),
      untilText('lg_msg', '请登录'),
      ..._login(kind, pass: '000'),
      untilText('lg_msg', '登录失败（401）'),
      ..._login(kind),
      ..._toList(kind, untilText('lg_msg', '登录成功')),
      untilText('ls_sum', '霜霜：2 篇，共 7 字'),
      ..._open(kind, 0),
      textIs('ed_now', '买菜｜鸡蛋和葱'),
      ..._save('', '鸡蛋'),
      untilText('ed_msg', '标题不能空'),
      ..._save('买菜', '一二三四五六七八九十一二三四五六七八九十多了'),
      untilText('ed_msg', '正文太长（22 个字，最多 20）'),
      ..._save('读书', '鸡蛋'),
      untilText('ed_msg', '没存上（409）'),
      textIs('ed_now', '买菜｜鸡蛋和葱'),
      ..._save('买好了', '鸡蛋'),
      ..._toList(kind, untilText('ed_msg', '存好了，这一回存了 1 次')),
      untilText('ls_sum', '霜霜：2 篇，共 5 字'),
      textAt('ls_title', 0, '买好了'),
    ],
    (api, world) {
      // 草稿自己拦下的两次没发到服务那头：只有重名那次和成功那次。
      if (api.hit('PUT /notes/1') != 2 || api.hit('POST /login') != 2) throw StateError('请求次数：${api.hits}');
    },
  ),
  NoteCase(
    '列表先超时、再报错（带状态码的错误），重试恢复；关掉再开还在登录；点进去那篇没了（404）；另一篇存的时候服务拖着不回（最多等），再点存上；退出',
    NoteWorld([..._two(), ('旧的', '早删了')], listFaults: ['hang', '500'], saveFaults: ['hang'], gone: {3}),
    (kind) => [
      netOn(),
      untilText('lg_msg', '请登录'),
      ..._login(kind),
      ..._toList(kind, untilText('lg_msg', '登录成功')),
      untilText('ls_err', '出错：超时'),
      countIs('ls_title', 0),
      click('ls_retry'),
      untilText('ls_err', '列表取不到（500）'),
      click('ls_retry'),
      untilText('ls_sum', '霜霜：3 篇，共 10 字'),
      textIs('ls_err', ''),
      ...reopen(),
      if (kind == 'html') ...arrive(kind, 'login', home: true),
      ..._toList(kind, untilText('lg_msg', '已登录')),
      untilText('ls_sum', '霜霜：3 篇，共 10 字'),
      ..._open(kind, 2),
      textIs('ed_msg', '这篇取不到（404）'),
      click('ed_back'),
      ...arriveAt(kind, 'list', ready: untilText('ls_rdy', '好了')),
      untilText('ls_sum', '霜霜：3 篇，共 10 字'),
      ..._open(kind, 0),
      ..._save('买菜', '鸡蛋'),
      untilText('ed_msg', '存得太慢，再点一次'),
      click('ed_save'),
      ..._toList(kind, untilText('ed_msg', '存好了，这一回存了 1 次')),
      untilText('ls_sum', '霜霜：3 篇，共 8 字'),
      click('ls_out'),
      ...arriveAt(kind, 'login', home: true, ready: untilText('lg_msg', '请登录')),
      storedIs(kNoteToken, null),
    ],
    (api, world) {
      if (api.hanging != 2) throw StateError('拖着没回的有 ${api.hanging} 个');
      if (world.notes[0]['body'] != '鸡蛋') throw StateError('服务那头：${world.notes}');
    },
  ),
];
