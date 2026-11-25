// 记忆接进会话以后（工具箱、系统提示词、聊天步骤、查历史对话）：
// 各权限档 / 计划模式 / 无人值守 / 子代理各自能不能写，系统提示词里有没有记忆，总开关关掉以后什么都没有。
// 模型是脚本客户端，不发任何真实请求。
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/agent/agent_tools.dart';
import 'package:lopicode/agent/automation.dart';
import 'package:lopicode/agent/chat_client.dart';
import 'package:lopicode/agent/memory_store.dart';
import 'package:lopicode/agent/presets.dart';
import 'package:lopicode/core/project_store.dart';
import 'package:lopicode/core/stores.dart';
import 'package:lopicode/core/templates.dart';
import 'package:lopicode/project_session.dart';
import 'package:lopicode/session/chat_rows.dart';
import 'package:lopicode/session/conversation_search.dart';
import 'package:path/path.dart' as p;

import 'agent_test.dart' show RecordingRunner;
import 'session_system_test.dart' show RoutingClient, Turn, reply, use, firstUser, hasToolResult, toolResults;
import 'support/harness.dart';

const _memoryTools = ['memory_read', 'memory_search', 'memory_write', 'memory_delete'];

void main() {
  late TestEnv env;
  late Project project;
  late ProjectSession session;
  late List<({List<Map<String, dynamic>> messages, List<String> tools})> log;
  Turn turn = (_, _) => reply('好的。');

  setUp(() async {
    log = [];
    turn = (_, _) => reply('好的。');
    env = await TestEnv.create(chatClient: () => RoutingClient((m, t) => turn(m, t), log));
    project = await env.services.projects.create('测试工作区', ProjectTemplate.web);
    session = ProjectSession(env.services, project, headless: true);
    session.commandRunnerFactory = RecordingRunner.new;
    await session.loadChat();
  });
  tearDown(() async {
    session.dispose();
    await env.dispose();
  });

  AppMemory memory() => env.services.memory;
  String systemOf(int i) => '${log[i].messages.first['content']}';
  File globalFile(String id) => File(p.join(env.tmp.path, 'memory', '$id.md'));
  File projectFile(String id) => File(p.join(project.dir, '.lopicode', 'memory', '$id.md'));

  /// 模型先调一次 [name]，拿到结果后说“完”。
  void callOnce(String name, Map<String, dynamic> args) {
    var called = false;
    turn = (m, t) {
      if (called) return reply('完');
      called = true;
      return use(name, args);
    };
  }

  group('存在哪', () {
    test('全局记忆在应用数据目录的 memory/ 下（不在任何工作区里）；项目记忆在工作区的 .lopicode/memory/ 下', () async {
      callOnce('memory_write', {'scope': 'global', 'title': '回答的语言', 'content': '用简体中文'});
      await session.sendToAgent('记住：以后都用简体中文');
      callOnce('memory_write', {'scope': 'project', 'title': '构建命令', 'content': 'flutter build apk'});
      await session.sendToAgent('记住这个项目的构建命令');
      expect(globalFile('回答的语言').readAsStringSync(), '# 回答的语言\n\n用简体中文\n');
      expect(projectFile('构建命令').readAsStringSync(), '# 构建命令\n\nflutter build apk\n');
      expect(p.isWithin(project.dir, globalFile('回答的语言').path), isFalse);
      expect(p.isWithin(env.services.projects.rootDir, globalFile('回答的语言').path), isFalse, reason: '全局记忆不在工作区目录树里');
    });

    test('通用文件工具照旧碰不到 .lopicode/memory（那条限制没放松）', () async {
      await memory().project(project).write('构建命令', 'flutter build apk');
      var n = 0;
      turn = (m, t) => switch (n++) {
        0 => [
          call(0, 'read_file', jsonEncode({'path': '.lopicode/memory/构建命令.md'})),
          call(1, 'write_file', jsonEncode({'path': '.lopicode/memory/偷写.md', 'content': '# 偷写\n\n绕过工具'})),
          ChatDelta(finishReason: 'tool_calls'),
        ],
        _ => reply('不行'),
      };
      await session.sendToAgent('试试直接读写');
      expect(toolResults(log.last.messages), isNot(contains('flutter build apk')));
      expect(projectFile('偷写').existsSync(), isFalse);
      expect(session.chat.whereType<ToolItem>().every((t) => !t.ok), isTrue);
    });
  });

  group('谁能写', () {
    test('默认（工作区内修改）：四个工具都有；写入不出确认卡', () async {
      callOnce('memory_write', {'scope': 'global', 'title': '甲', 'content': '一'});
      await session.sendToAgent('记住甲');
      expect(log.first.tools, containsAll(_memoryTools));
      expect(session.pendingApproval, isNull);
      expect(memory().global.entries.single.title, '甲');
      expect(toolResults(log.last.messages), contains('记住了：“甲”'));
    });

    test('仅可查看：只有读和查；硬调写 / 删被拒，文件没动', () async {
      await memory().global.write('原有的', '别动');
      await session.setPermission(PermissionLevel.view);
      var n = 0;
      turn = (m, t) => switch (n++) {
        0 => [
          call(0, 'memory_write', jsonEncode({'scope': 'global', 'title': '偷写', 'content': '不该有'})),
          call(1, 'memory_delete', jsonEncode({'scope': 'global', 'title': '原有的'})),
          call(2, 'memory_read', jsonEncode({'title': '原有的'})),
          ChatDelta(finishReason: 'tool_calls'),
        ],
        _ => reply('写不了'),
      };
      await session.sendToAgent('记一下');
      expect(log.first.tools, containsAll(['memory_read', 'memory_search']));
      expect(log.first.tools, isNot(contains('memory_write')));
      expect(log.first.tools, isNot(contains('memory_delete')));
      await memory().global.load();
      expect(memory().global.entries.map((e) => e.title), ['原有的']);
      final steps = session.chat.whereType<ToolItem>().toList();
      expect(steps.map((t) => t.ok), [false, false, true], reason: '写、删被拒，读照常');
      expect(toolResults(log.last.messages), contains('别动'));
      expect(systemOf(0), contains('只能读记忆，不能写'));
    });

    test('计划模式：只有读和查；硬调写被拒', () async {
      await session.setPlanMode(true);
      callOnce('memory_write', {'scope': 'project', 'title': '偷写', 'content': '不该有'});
      await session.sendToAgent('先出个计划');
      expect(log.first.tools, containsAll(['memory_read', 'memory_search']));
      expect(log.first.tools, isNot(contains('memory_write')));
      expect(log.first.tools, isNot(contains('memory_delete')));
      expect(projectFile('偷写').existsSync(), isFalse);
      expect(session.chat.whereType<ToolItem>().single.ok, isFalse);
      expect(systemOf(0), contains('只能读记忆，不能写'));
    });

    test('完全权限：能写', () async {
      await session.setPermission(PermissionLevel.full);
      callOnce('memory_write', {'scope': 'project', 'title': '甲', 'content': '一'});
      await session.sendToAgent('记住甲');
      expect(projectFile('甲').existsSync(), isTrue);
    });

    test('无人值守（自动化任务）：全局记忆写不了、删不了；项目记忆可以', () async {
      await memory().global.write('原有的', '别动');
      var n = 0;
      turn = (m, t) => switch (n++) {
        0 => [
          call(0, 'memory_write', jsonEncode({'scope': 'global', 'title': '偷写', 'content': '没人看着'})),
          call(1, 'memory_delete', jsonEncode({'scope': 'global', 'title': '原有的'})),
          call(2, 'memory_write', jsonEncode({'scope': 'project', 'title': '巡检结果怎么看', 'content': '看 logs/'})),
          ChatDelta(finishReason: 'tool_calls'),
        ],
        _ => reply('做完了'),
      };
      final run = await session.runAutomation(
        Automation(
          id: 'a1',
          title: '每日巡检',
          instruction: '看看有没有问题',
          workspaceId: project.id,
          rule: TimeRule(kind: RuleKind.daily, tzOffsetMinutes: 480),
        ),
      );
      expect(run.status, 'ok');
      await memory().global.load();
      expect(memory().global.entries.map((e) => e.title), ['原有的'], reason: '全局记忆一个字没动');
      expect(globalFile('偷写').existsSync(), isFalse);
      expect(projectFile('巡检结果怎么看').existsSync(), isTrue);
      final results = toolResults(log.last.messages);
      expect(results, contains('无人值守'));
      expect(results, contains('记住了：“巡检结果怎么看”'));
    });

    test('子代理：能读能查，不能写；硬调写被拒', () async {
      await memory().global.write('怎么称呼', '称呼她霜霜');
      turn = (m, t) {
        if (firstUser(m).contains('子任务')) {
          if (!hasToolResult(m)) {
            return [
              call(0, 'memory_write', jsonEncode({'scope': 'global', 'title': '子代理偷写', 'content': '不该有'})),
              call(1, 'memory_read', jsonEncode({'title': '怎么称呼'})),
              ChatDelta(finishReason: 'tool_calls'),
            ];
          }
          return reply('子做完');
        }
        return hasToolResult(m) ? reply('完') : use('spawn_agent', {'name': '子', 'task': '子任务：看看记忆'});
      };
      await session.sendToAgent('派个子代理');
      final child = log.where((l) => firstUser(l.messages).contains('子任务')).toList();
      expect(child.first.tools, containsAll(['memory_read', 'memory_search']));
      expect(child.first.tools, isNot(contains('memory_write')));
      expect(child.first.tools, isNot(contains('memory_delete')));
      expect('${child.first.messages.first['content']}', contains('只能读记忆，不能写'));
      expect('${child.first.messages.first['content']}', contains('称呼她霜霜'), reason: '子代理也看得到记忆');
      expect(toolResults(child.last.messages), contains('称呼她霜霜'));
      expect(globalFile('子代理偷写').existsSync(), isFalse);
      // 主对话自己还是能写
      expect(log.first.tools, contains('memory_write'));
    });

    test('预设里可以勾掉记忆工具（设置页的工具表里有这几项）', () {
      for (final name in [..._memoryTools, kConversationSearchTool]) {
        expect(kToolLabels.keys, contains(name));
      }
    });
  });

  group('系统提示词', () {
    test('每轮开始时带上记忆；写明不要记密钥；她手改了文件，下一轮就是新的', () async {
      await memory().global.write('怎么称呼', '称呼她霜霜');
      await memory().project(project).write('构建命令', 'flutter build apk');
      await session.sendToAgent('你好');
      expect(systemOf(0), contains('全局记忆'));
      expect(systemOf(0), contains('### 怎么称呼\n称呼她霜霜'));
      expect(systemOf(0), contains('这个项目的记忆'));
      expect(systemOf(0), contains('### 构建命令\nflutter build apk'));
      expect(systemOf(0), contains('绝对不要把密钥、令牌、密码记进记忆'));

      globalFile('怎么称呼').writeAsStringSync('# 怎么称呼\n\n改成用英文\n');
      await session.sendToAgent('再来');
      expect(systemOf(1), contains('改成用英文'));
      expect(systemOf(1), isNot(contains('称呼她霜霜')));
    });

    test('这一轮里刚记下的，下一轮的提示词里就有', () async {
      callOnce('memory_write', {'scope': 'global', 'title': '称呼', 'content': '喊她阿霜'});
      await session.sendToAgent('记住怎么称呼我');
      expect(systemOf(0), contains('现在还没有任何记忆'));
      turn = (_, _) => reply('好的');
      await session.sendToAgent('你好');
      expect(systemOf(log.length - 1), contains('喊她阿霜'));
    });

    test('记忆很多：提示词里只有标题和摘要，全文要用工具读', () async {
      for (var i = 0; i < 4; i++) {
        await memory().global.write('长的 $i', '摘要 $i\n${'字' * 1000}');
      }
      await session.sendToAgent('你好');
      expect(systemOf(0), contains('下面只有标题和摘要'));
      expect(systemOf(0), contains('- 长的 2：摘要 2'));
      expect(systemOf(0), isNot(contains('字' * 50)));
    });
  });

  group('总开关', () {
    test('关掉：提示词里没有记忆、记忆工具不出现；查历史对话的工具还在', () async {
      await memory().global.write('怎么称呼', '称呼她霜霜');
      await env.services.settings.set(SettingKeys.memoryEnabled, false);
      callOnce('memory_write', {'scope': 'global', 'title': '偷写', 'content': '关了还写'});
      await session.sendToAgent('你好');
      for (final name in _memoryTools) {
        expect(log.first.tools, isNot(contains(name)));
      }
      expect(log.first.tools, contains(kConversationSearchTool));
      expect(systemOf(0), isNot(contains('称呼她霜霜')));
      expect(systemOf(0), isNot(contains('记忆（跨对话保留的笔记')));
      expect(globalFile('偷写').existsSync(), isFalse);

      await env.services.settings.set(SettingKeys.memoryEnabled, true);
      turn = (_, _) => reply('好的');
      await session.sendToAgent('再来');
      expect(log.last.tools, containsAll(_memoryTools));
      expect(systemOf(log.length - 1), contains('称呼她霜霜'));
    });
  });

  group('聊天步骤', () {
    test('写入在步骤里显示“记住了 + 标题”，折叠的那一行里有“记住 N 条”', () async {
      var n = 0;
      turn = (m, t) => switch (n++) {
        0 => [
          call(0, 'memory_write', jsonEncode({'scope': 'global', 'title': '回答的语言', 'content': '用简体中文'})),
          call(1, 'memory_write', jsonEncode({'scope': 'project', 'title': '构建命令', 'content': 'flutter build apk'})),
          call(2, 'memory_write', jsonEncode({'scope': 'global', 'title': '', 'content': '没标题，会失败'})),
          call(3, 'memory_read', jsonEncode({'title': '回答的语言'})),
          ChatDelta(finishReason: 'tool_calls'),
        ],
        _ => reply('记好了'),
      };
      await session.sendToAgent('都记一下');
      final tools = session.chat.whereType<ToolItem>().toList();
      expect(stepLabel(tools[0].name, tools[0].arguments), ('记住了', '回答的语言'));
      expect(stepLabel(tools[1].name, tools[1].arguments), ('记住了', '构建命令'));
      final summary = summarizeSteps(tools);
      expect(summary.remembered, 2, reason: '失败的那次不算');
      expect(summary.parts, contains('记住 2 条'));
    });

    test('其他几个工具的步骤文字', () {
      expect(stepLabel('memory_delete', jsonEncode({'title': '甲'})), ('从记忆里删掉', '甲'));
      expect(stepLabel('memory_read', jsonEncode({'title': '甲'})), ('读记忆', '甲'));
      expect(stepLabel('memory_read', '{}'), ('查看记忆清单', ''));
      expect(stepLabel('memory_search', jsonEncode({'query': '中文'})), ('查记忆', '中文'));
      expect(stepLabel(kConversationSearchTool, jsonEncode({'query': '登录页'})), ('查历史对话', '登录页'));
    });
  });

  group('conversation_search：查这个工作区的历史对话', () {
    Future<String> search(String query) async {
      callOnce(kConversationSearchTool, {'query': query});
      await session.sendToAgent('查一下之前的');
      return toolResults(log.last.messages);
    }

    test('只读工具：仅可查看、计划模式下也有', () async {
      await session.setPermission(PermissionLevel.view);
      await session.setPlanMode(true);
      await session.sendToAgent('你好');
      expect(log.first.tools, contains(kConversationSearchTool));
    });

    test('找到以前那段对话：给标题、时间和命中的片段；关掉的对话从盘上读', () async {
      turn = (_, _) => reply('登录页用了 Material 的表单，校验放在提交按钮里。');
      await session.sendToAgent('帮我做一个登录页');
      final oldTitle = session.conversationTitle;
      await session.newConversation();
      final found = await search('登录页 校验');
      expect(found, contains('找到 1 段'));
      expect(found, contains('《$oldTitle》'));
      expect(found, matches(RegExp(r'\d{4}-\d{2}-\d{2} \d{2}:\d{2}')));
      expect(found, contains('助手：登录页用了 Material 的表单'));
      expect(found, isNot(contains('就是现在这段对话')));

      // 重开工作区（那段对话没加载进内存）：照样查得到
      session.dispose();
      session = ProjectSession(env.services, project, headless: true);
      session.commandRunnerFactory = RecordingRunner.new;
      await session.loadChat();
      await session.newConversation();
      expect(await search('校验'), contains('《$oldTitle》'));
    });

    test('几个词要在同一条消息里都出现；不分大小写；没有就说没有', () async {
      turn = (_, _) => reply('用 Flutter 写。');
      await session.sendToAgent('做个计时器');
      await session.newConversation();
      expect(await search('flutter'), contains('用 Flutter 写'));
      await session.newConversation();
      expect(await search('计时器 flutter'), contains('没有提到'), reason: '两个词分别在两条消息里，不算');
    });

    test('不翻工具结果（那里是大段文件内容）', () async {
      File(p.join(project.dir, 'secret-notes.txt')).writeAsStringSync('独一无二的文件内容 xyzzy');
      callOnce('read_file', {'path': 'secret-notes.txt'});
      await session.sendToAgent('读一下那个文件');
      await session.newConversation();
      expect(await search('xyzzy'), contains('没有提到'));
    });

    test('片段先脱敏：以前对话里贴过的密钥不会被原样翻出来', () async {
      final key = 'sk-${'z9y8x7w6' * 3}';
      turn = (_, _) => reply('收到。');
      await session.sendToAgent('部署用的密钥是 $key 你记一下部署步骤');
      await session.newConversation();
      final found = await search('部署');
      expect(found, contains('找到 1 段'));
      expect(found, isNot(contains(key)));
    });

    test('不跨工作区：别的工作区聊过的查不到', () async {
      final other = await env.services.projects.create('另一个工作区', ProjectTemplate.web);
      final otherSession = ProjectSession(env.services, other, headless: true);
      otherSession.commandRunnerFactory = RecordingRunner.new;
      await otherSession.loadChat();
      turn = (_, _) => reply('支付回调的签名用 HMAC。');
      await otherSession.sendToAgent('支付回调怎么验签');
      otherSession.dispose();
      expect(await search('支付回调'), contains('没有提到'));
    });

    test('子代理的对话不单列（它的汇报在上级对话里）', () async {
      turn = (m, t) {
        if (firstUser(m).contains('子任务')) return reply('斐波那契写好了');
        return hasToolResult(m) ? reply('完') : use('spawn_agent', {'name': '子', 'task': '子任务：写斐波那契'});
      };
      await session.sendToAgent('派个子代理');
      await session.newConversation();
      final found = await search('斐波那契写好了');
      expect(found, contains('没有提到'), reason: '只出现在子代理自己的对话和工具结果里');
    });

    test('命中很多：最多 $kConvSearchMaxConversations 段、每段最多 $kConvSearchMaxSnippets 个片段、片段有长度上限', () async {
      for (var i = 0; i < kConvSearchMaxConversations + 2; i++) {
        turn = (_, _) => reply('苹果 ${'很长的回答' * 100}');
        await session.sendToAgent('苹果 $i');
        await session.sendToAgent('再说说苹果');
        await session.newConversation();
      }
      final found = await search('苹果');
      expect(found, contains('找到 $kConvSearchMaxConversations 段'));
      expect(found, contains('还有 2 段也提到了'));
      expect(RegExp(r'^\d+\. 《', multiLine: true).allMatches(found), hasLength(kConvSearchMaxConversations));
      final snippetLines = found.split('\n').where((l) => l.startsWith('   ')).toList();
      expect(snippetLines, hasLength(kConvSearchMaxConversations * kConvSearchMaxSnippets));
      for (final l in snippetLines) {
        expect(l.length, lessThan(kConvSearchSnippetChars + 20));
      }
    });

    test('关键词是空的 / 太长：给模型一个错误', () async {
      expect(await search('   '), contains('错误'));
      await session.newConversation();
      expect(await search('长' * (kConvSearchMaxQueryChars + 1)), contains('关键词太长'));
    });

    test('对话记录文件坏了：跳过那一段，不崩', () async {
      turn = (_, _) => reply('香蕉的事说完了。');
      await session.sendToAgent('聊聊香蕉');
      final brokenId = session.activeConversationId;
      await session.newConversation();
      turn = (_, _) => reply('香蕉还可以做奶昔。');
      await session.sendToAgent('香蕉还能干嘛');
      await session.newConversation();
      session.dispose();
      final chatFile = File(p.join(project.dir, '.lopicode', brokenId == 'main' ? 'chat.json' : 'chat-$brokenId.json'));
      expect(chatFile.existsSync(), isTrue);
      chatFile.writeAsStringSync('{"半截": [');
      session = ProjectSession(env.services, project, headless: true);
      session.commandRunnerFactory = RecordingRunner.new;
      await session.loadChat();
      final found = await search('香蕉');
      expect(found, contains('找到 1 段'));
      expect(found, contains('奶昔'));
    });
  });
}
