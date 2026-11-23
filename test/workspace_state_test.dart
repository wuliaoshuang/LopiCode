// 工作区一级的状态（lib/state/workspace_*.dart）：文件变动信号、终端列表、预览。
import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/core/project_store.dart';
import 'package:lopicode/core/templates.dart';
import 'package:lopicode/project_session.dart';
import 'package:lopicode/state/workspace_files.dart';

import 'support/harness.dart';

void main() {
  late TestEnv env;
  late Project project;
  late ProjectSession session;

  setUp(() async {
    env = await TestEnv.create();
    project = await env.services.projects.create('测试工作区', ProjectTemplate.web);
    session = ProjectSession(env.services, project, headless: true);
  });
  tearDown(() {
    session.dispose();
    env.dispose();
  });

  group('文件变动信号', () {
    test('filesChanged 一次通知一次；两个工作区互不串', () async {
      final other = ProjectSession(env.services, await env.services.projects.create('另一个', ProjectTemplate.web), headless: true);
      addTearDown(other.dispose);
      final box = env.services.container;
      var mine = 0, theirs = 0;
      box.listen(filesRevProvider(session), (_, _) => mine++);
      box.listen(filesRevProvider(other), (_, _) => theirs++);
      session.filesChanged();
      session.filesChanged();
      expect((mine, theirs), (2, 0));
      expect(box.read(filesRevProvider(session)), 2);
      other.filesChanged();
      expect((mine, theirs), (2, 1));
    });

    test('工作区关掉以后再调：不通知、不报错；应用销毁以后也一样', () {
      final box = env.services.container;
      var n = 0;
      final closed = ProjectSession(env.services, project, headless: true);
      box.listen(filesRevProvider(closed), (_, _) => n++);
      closed.dispose();
      closed.filesChanged();
      expect(n, 0);

      final late_ = ProjectSession(env.services, project, headless: true);
      env.services.dispose();
      late_.filesChanged(); // 不抛异常就是过
      late_.dispose();
    });
  });
}
