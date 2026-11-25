// 整条链路（真的跑一轮，模型是脚本化的假客户端，不联网）：
// edit_file / write_file 的对比挂在步骤上并随聊天记录存盘；一轮结束后有“改过的文件”清单，子代理改的也算进上级这一轮；
// 计划模式下模型拿不到 edit_file；写文件仍然不出确认卡。
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/agent/agent_tools.dart';
import 'package:lopicode/agent/chat_client.dart';
import 'package:lopicode/agent/line_diff.dart';
import 'package:lopicode/core/project_store.dart';
import 'package:lopicode/core/safe_file.dart';
import 'package:lopicode/core/templates.dart';
import 'package:lopicode/project_session.dart';

import 'agent_test.dart' show RecordingRunner;
import 'session_system_test.dart' show RoutingClient, Turn, firstUser, hasToolResult, reply, use;
import 'support/harness.dart';

void main() {
  late TestEnv env;
  late Project project;
  late ProjectSession session;
  late List<({List<Map<String, dynamic>> messages, List<String> tools})> log;
  Turn turn = (_, _) => reply('好的。');

  setUp(() async {
    log = [];
    env = await TestEnv.create(chatClient: () => RoutingClient((m, t) => turn(m, t), log));
    project = await env.services.projects.create('测试工作区', ProjectTemplate.web);
    session = ProjectSession(env.services, project, headless: true)..commandRunnerFactory = RecordingRunner.new;
    await session.loadChat();
  });
  tearDown(() async {
    session.dispose();
    await env.dispose();
  });

  File f(String rel) => File('${project.dir}/$rel');

  test('局部修改 + 新建：步骤带对比，回复下面有清单；不出确认卡；重新打开还在；存盘里没有全文', () async {
    f('notes.txt').writeAsStringSync('第一行\n第二行\n第三行\n');
    var n = 0;
    turn = (m, t) => switch (n++) {
      0 => use('edit_file', {'path': 'notes.txt', 'old_text': '第二行', 'new_text': '第二行（改）\n插入的一行'}),
      1 => use('write_file', {'path': 'extra/new.md', 'content': '# 标题\n正文\n'}),
      2 => use('edit_file', {'path': 'notes.txt', 'old_text': '第三行', 'new_text': '第 3 行'}),
      3 => use('edit_file', {'path': 'notes.txt', 'old_text': '不存在的内容', 'new_text': 'x'}),
      _ => reply('改好了。'),
    };
    await session.sendToAgent('改一下笔记');
    expect(session.pendingApproval, isNull);
    expect(f('notes.txt').readAsStringSync(), '第一行\n第二行（改）\n插入的一行\n第 3 行\n');

    void check(List<ChatItem> chat) {
      final tools = chat.whereType<ToolItem>().toList();
      expect([for (final t in tools) (t.name, t.ok, t.change?.stat)], [('edit_file', true, '+2 −1'), ('write_file', true, '+2'), ('edit_file', true, '+1 −1'), ('edit_file', false, null)]);
      expect(tools[1].change!.kind, ChangeKind.created);
      expect(tools.first.change!.before, isNull, reason: '聊天条目里不带全文');
      final files = chat.whereType<ChangedFilesItem>().single.files;
      expect([for (final c in files) (c.path, c.kind, c.added, c.removed)], [('extra/new.md', ChangeKind.created, 2, 0), ('notes.txt', ChangeKind.modified, 3, 2)]);
      expect(files.last.hunks.single.lines, [' 第一行', '-第二行', '-第三行', '+第二行（改）', '+插入的一行', '+第 3 行'], reason: '两次修改合成一份');
      // 清单在回复后面、用量脚注前面
      final at = chat.indexWhere((i) => i is ChangedFilesItem);
      expect(chat[at - 1], isA<AssistantItem>());
      expect(chat[at + 1], isA<UsageItem>());
    }

    check(session.chat);
    // 发给模型的消息里没有我们自己的字段
    expect(jsonEncode(log.last.messages), contains('已修改 notes.txt'));
    await pendingWrites();
    final saved = Directory(project.dir).listSync(recursive: true).whereType<File>().where((x) => x.path.endsWith('.json')).map((x) => x.readAsStringSync()).where((s) => s.contains('_diff')).toList();
    expect(saved, isNotEmpty, reason: '对比跟着聊天记录存了盘');
    expect(saved.join(), contains('_files'));
    expect(saved.join(), isNot(contains('"before"')));

    final again = ProjectSession(env.services, project, headless: true);
    await again.loadChat();
    addTearDown(again.dispose);
    check(again.chat);
  });

  test('接口的请求里不带对比字段（以 _ 开头的键发出去前都去掉）', () {
    final sent = stripInternal([
      {
        'role': 'tool',
        'tool_call_id': 'c1',
        'content': '已修改',
        '_diff': {'p': 'a'},
        '_files': <Object>[],
      },
    ]);
    expect(sent.single.keys, unorderedEquals(['role', 'tool_call_id', 'content']));
  });

  test('子代理改的文件算进上级这一轮的清单；和上级自己改的合在一起', () async {
    f('notes.txt').writeAsStringSync('a\nb\n');
    var parent = 0;
    var child = 0;
    turn = (m, t) {
      if (firstUser(m).contains('写首页')) {
        return switch (child++) {
          0 => use('write_file', {'path': 'home.html', 'content': '<h1>首页</h1>\n'}),
          1 => use('edit_file', {'path': 'notes.txt', 'old_text': 'b', 'new_text': 'b\nc（子代理加的）'}),
          _ => reply('首页写好了'),
        };
      }
      return switch (parent++) {
        0 => use('edit_file', {'path': 'notes.txt', 'old_text': 'a', 'new_text': 'A'}),
        1 => use('spawn_agent', {'name': '前端', 'task': '写首页 home.html'}),
        _ => reply('都做完了'),
      };
    };
    await session.sendToAgent('帮我做个站');
    expect(hasToolResult(log.last.messages), isTrue);
    final files = session.chat.whereType<ChangedFilesItem>().single.files;
    expect([for (final c in files) (c.path, c.kind, c.stat)], [('home.html', ChangeKind.created, '+1'), ('notes.txt', ChangeKind.modified, '+2 −1')]);
    expect(files.last.hunks.single.lines, ['-a', '+A', ' b', '+c（子代理加的）']);
  });

  test('一轮里没改文件：没有清单那一行；只读了文件也没有', () async {
    var n = 0;
    turn = (m, t) => n++ == 0 ? use('read_file', {'path': 'index.html'}) : reply('看过了。');
    await session.sendToAgent('看看首页');
    expect(session.chat.whereType<ChangedFilesItem>(), isEmpty);
  });

  test('计划模式 / 仅可查看：模型拿不到 edit_file；硬调用被拒，文件没动，也没有清单', () async {
    final before = f('index.html').readAsStringSync();
    await session.setPermission(PermissionLevel.view);
    var n = 0;
    turn = (m, t) => n++ == 0 ? use('edit_file', {'path': 'index.html', 'old_text': before.split('\n').first, 'new_text': '被改了'}) : reply('改不了。');
    await session.sendToAgent('改首页');
    expect(log.first.tools, isNot(contains('edit_file')));
    expect(log.first.tools, isNot(contains('write_file')));
    expect(f('index.html').readAsStringSync(), before);
    expect(session.chat.whereType<ToolItem>().single.denied, isTrue);
    expect(session.chat.whereType<ChangedFilesItem>(), isEmpty);
    expect(session.pendingApproval, isNull);
  });
}
