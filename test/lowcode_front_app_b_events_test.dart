// 小应用乙组·“活动报名（多语言）”：四组样例，纯网页、Vue 3、React 三种导出真编译 0 错 0 警告，在 Node＋jsdom 里对着本地假服务
// （只绑 127.0.0.1，和测试同一个进程）把登录 → 列表 → 详情 → 提交整条路真跑完；三种都一步不差＝三种一致。
// 假服务每组一个，结束、失败、超时都在收尾里关掉；真跑的 Node 到时间没完就连子进程按进程号杀掉。
// 另：故意写错的几条在检查阶段被拦下（三种产物里这一页的逻辑都不出）。
@Tags(['external'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/lang/rules.dart';
import 'package:lopicode/lowcode/logic_gate.dart';
import 'package:lopicode/lowcode/model.dart';

import 'support/backend_core_samples.dart';
import 'support/backend_func_blocks.dart';
import 'support/backend_lang_blocks.dart';
import 'support/bind_export_files.dart';
import 'support/dev_tools.dart';
import 'support/front_app_b_events.dart';
import 'support/front_app_b_events_cases.dart';
import 'support/front_app_b_kit.dart';
import 'support/front_libs_samples.dart';
import 'support/page_front_check.dart';
import 'support/page_front_samples.dart';

/// 一页的小文档：登录页那几样库都用上（[libs] 可以故意少一个），按钮点了做 [body]。
LcDocument _one(List<J> body, {List<String> libs = const ['http', 'storage', 'i18n', 'form', 'router'], List<J> hats = const []}) => appDoc([
  AppPage('p', [btn('b1', '点'), inp('in1'), txt('t1')], [textVar('s')], frontDoc(uses: [for (final l in libs) useLib(l)], hats: [onClick('h1', 'b1', body), ...hats])),
]);

void _blocked(LcDocument doc) {
  expect(lcLogicErrorCount(doc), greaterThan(0));
  for (final kind in const ['html', 'vue', 'react']) {
    final all = exportFilesOf(doc, kind).values.join('\n');
    expect(all, contains('这一页的逻辑没有导出'), reason: kind);
    expect(all, isNot(contains('function lcProgram(lc, lcHost)')), reason: kind);
  }
}

void main() {
  FakeApi? api;
  setUp(() {
    // 就在默认状态下测：两个安全开关都关着。
    expect(libNativeCodeEntry, isFalse);
    expect(userLibHostEntry, isFalse);
  });
  tearDown(() async {
    await api?.stop();
    api = null;
  });

  test('有四组样例，三页画布上的检查都没毛病', () {
    expect(eventsCases().length, greaterThanOrEqualTo(3));
    expect(appIssues(appDoc(eventsPages('http://127.0.0.1:1'))), isEmpty);
  });

  // 搭这个应用时撞上的：自己的一块积木也叫“换语言”（和“国际化”库里那个函数同名），库的“换成语言”积木就被认成了自己那块，
  // 报“要 0 个参数，给了 1 个”。现在库积木展开出来的名字指明是库里的，两边各走各的。
  test('自己的积木和自带库里的函数同名：库积木还是库里的那个', () {
    final doc = appDoc([
      AppPage(
        'p',
        [btn('b1', '点'), txt('t1')],
        const [],
        frontDoc(
          uses: [useLib('i18n')],
          functions: [
            tfn('f1', '换语言', const [], [
              lb('i18n', 'use', {'lang': tx('English')}),
            ]),
          ],
          hats: [
            onClick('h1', 'b1', [
              lb('i18n', 'table', {
                'lang': tx('中文'),
                'table': dc({'a': tx('甲')}),
              }),
              lb('i18n', 'table', {
                'lang': tx('English'),
                'table': dc({'a': tx('A')}),
              }),
              callS('f1'),
              show('t1', lx('i18n', 't', {'key': tx('a')})),
            ]),
          ],
        ),
      ),
    ]);
    expect(appIssues(doc), isEmpty);
  });

  final n = eventsCases().length;
  for (var i = 0; i < n; i++) {
    for (final kind in kFrontKinds.entries) {
      test(
        '活动报名·第 ${i + 1} 组·${kind.value}：真编译、对着假服务真跑',
        () async {
          final c = eventsCases()[i];
          final server = api = await FakeApi.start(c.world.handle);
          await appCheck(kind.key, appDoc(eventsPages(server.base)), c.steps(kind.key));
          c.after(server, c.world);
        },
        skip: skipWithoutDom,
        timeout: const Timeout(Duration(minutes: 6)),
      );
    }
  }

  group('故意写错的被检查拦下', () {
    J range(J max) => lx('form', 'range', {'min': nm(1), 'max': max, 'msg': tx('不对')});
    J rules(J rule) => lb('form', 'rules', {
      'form': tx('报名'),
      'field': tx('n'),
      'rules': ls([rule]),
    });
    test('对照：写对的不拦', () {
      final doc = _one([
        rules(range(toNum(valOf('in1')))),
        show('t1', lx('i18n', 't', {'key': tx('a')})),
      ]);
      expect(appIssues(doc), isEmpty);
    });
    test('类型放错：人数上限填了字（要数）', () => _blocked(_one([rules(range(tx('三')))])));
    test('类型放错：路由的路径拿了一个数', () {
      _blocked(
        _one([
          lb('router', 'go', {'path': nm(3)}),
        ]),
      );
    });
    test('类型放错：语言表里的一句话填了数（要字）', () {
      _blocked(
        _one([
          lb('i18n', 'table', {
            'lang': tx('中文'),
            'table': dc({'a': nm(1)}),
          }),
        ]),
      );
    });
    test('没把“国际化”用上就拖了它的积木', () {
      _blocked(
        _one(
          [
            show('t1', lx('i18n', 't', {'key': tx('a')})),
          ],
          libs: const ['http', 'storage', 'form', 'router'],
        ),
      );
    });
    test('“新的语言”用在“当语言变了”外面', () => _blocked(_one([show('t1', lx('i18n', 'newLang'))])));
    test('去报名页没带上它要的参数', () {
      final pages = eventsPages('http://127.0.0.1:1');
      final home = pages.first;
      final hats = [
        for (final h in home.front['hats'] as List)
          if ((h as Map)['id'] == 'h5')
            onClick('h5', 'dt_go', [
              goWith('signup', {'id': stGet('eid')}),
            ])
          else
            h as J,
      ];
      final doc = appDoc([
        AppPage(home.id, home.children, home.variables, {...home.front, 'hats': hats}),
        ...pages.skip(1),
      ]);
      expect(appIssues(doc), isNotEmpty);
    });
  });
}
