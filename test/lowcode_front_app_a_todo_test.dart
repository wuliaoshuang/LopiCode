// 小应用甲组·“待办”：三组样例，纯网页、Vue 3、React 三种导出真编译 0 错 0 警告，在 Node＋jsdom 里对着本地假服务
// （只绑 127.0.0.1，和测试同一个进程）把登录 → 列表 → 详情 → 提交整条路真跑完；三种都一步不差＝三种一致。
// 假服务每组一个，结束、失败、超时都在收尾里关掉；真跑的 Node 到时间没完就连子进程按进程号杀掉。
@Tags(['external'])
library;

import 'package:flutter_test/flutter_test.dart';

import 'support/dev_tools.dart';
import 'support/front_app_a_kit.dart';
import 'support/front_app_a_todo.dart';
import 'support/page_front_check.dart';

void main() {
  FakeApi? api;
  tearDown(() async {
    await api?.stop();
    api = null;
  });

  test('有三组样例，画布上的检查都没毛病', () {
    final cases = todoCases();
    expect(cases.length, greaterThanOrEqualTo(3));
    expect(appIssues(appDoc(todoPages('http://127.0.0.1:1'))), isEmpty);
  });

  final n = todoCases().length;
  for (var i = 0; i < n; i++) {
    for (final kind in kFrontKinds.entries) {
      test(
        '待办·第 ${i + 1} 组·${kind.value}：真编译、对着假服务真跑',
        () async {
          final c = todoCases()[i];
          final server = api = await FakeApi.start(c.world.handle);
          await appCheck(kind.key, appDoc(todoPages(server.base)), c.steps(kind.key));
          c.after(server, c.world);
        },
        skip: skipWithoutDom,
        timeout: const Timeout(Duration(minutes: 6)),
      );
    }
  }
}
