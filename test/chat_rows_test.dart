// 聊天条目 → 行（步骤组）的推导，和步骤统计、确认卡危险程度。纯计算。
import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/agent/agent_tools.dart';
import 'package:lopicode/agent/approval_risk.dart';
import 'package:lopicode/agent/usage.dart';
import 'package:lopicode/session/chat_items.dart';
import 'package:lopicode/session/chat_models.dart';
import 'package:lopicode/session/chat_rows.dart';

ToolItem tool(String id, String name, String args, {String? result = 'ok', bool ok = true, bool denied = false}) => ToolItem(id, name, args, result: result, ok: ok, denied: denied);

/// 把行写成一眼能比的样子：U 用户 / A 回复 / N 提示 / $ 用量 / G(步骤…) 步骤组，进行中的组带 *。
String shape(List<ChatRow> rows) => rows
    .map(
      (r) => switch (r) {
        StepGroupRow(:final steps, :final live) =>
          '${live ? '*' : ''}G(${steps.map((s) => s is ToolItem
              ? 't'
              : s is ThinkingItem
              ? 'k'
              : 'a').join()})',
        ItemRow(:final item) => switch (item) {
          UserItem() => 'U',
          AssistantItem() => 'A',
          ToolItem() => 'T',
          UsageItem() => r'$',
          ChangedFilesItem() => 'F',
          NoticeItem() => 'N',
          ThinkingItem() => 'K',
          CompactionItem() => 'C',
          InterruptedItem() => 'I',
        },
      },
    )
    .join(' ');

void main() {
  group('deriveChatRows', () {
    test('没有工具调用：原样一项一行', () {
      expect(shape(deriveChatRows(const [UserItem('你好'), AssistantItem('你好呀')], busy: false)), 'U A');
    });

    test('连着的工具调用收成一组；模型说的话都是正文，各占一行、把组隔开；用量脚注留在外面', () {
      final items = <ChatItem>[
        const UserItem('加个深色模式'),
        const AssistantItem('我先看看项目。'),
        tool('1', 'list_files', '{}'),
        tool('2', 'read_file', '{"path":"index.html"}'),
        const AssistantItem('需要加一个样式文件。'),
        tool('3', 'write_file', '{"path":"dark.css","content":"x"}'),
        const AssistantItem('加好了。'),
        UsageItem(TurnUsage()),
      ];
      expect(shape(deriveChatRows(items, busy: false)), r'U A G(tt) A G(t) A $');
    });

    test('每条用户消息（包括中途插话）各开一段，各自成组', () {
      final items = <ChatItem>[
        const UserItem('一'),
        tool('1', 'read_file', '{"path":"a"}'),
        tool('2', 'read_file', '{"path":"b"}'),
        const UserItem('插一句'),
        tool('3', 'read_file', '{"path":"c"}'),
        const AssistantItem('好了'),
        const UserItem('二'),
        const AssistantItem('嗯'),
      ];
      expect(shape(deriveChatRows(items, busy: false)), 'U G(tt) U G(t) A U A');
    });

    test('进行中：最后一段的组是“进行中”；它后面开始出正式回复后就不算了；工具在跑时一直算', () {
      final running = <ChatItem>[const UserItem('一'), tool('1', 'read_file', '{}'), tool('2', 'run_command', '{}', result: null)];
      expect(shape(deriveChatRows(running, busy: true)), 'U *G(tt)');
      // 两步都做完、模型还没开口：在想下一步，仍算进行中
      final thinking = <ChatItem>[const UserItem('一'), tool('1', 'read_file', '{}'), tool('2', 'run_command', '{}')];
      expect(shape(deriveChatRows(thinking, busy: true)), 'U *G(tt)');
      // 模型开始说话（可能是正式回复）
      expect(shape(deriveChatRows([...thinking, const AssistantItem('做', streaming: true)], busy: true)), 'U G(tt) A');
      // 说完又调了工具：刚才那句话留在原地，后面另起一组（排好的行不挪位置）
      expect(shape(deriveChatRows([...thinking, const AssistantItem('再看一个'), tool('3', 'read_file', '{}', result: null)], busy: true)), 'U G(tt) A *G(t)');
      // 不忙：都不算进行中
      expect(shape(deriveChatRows(running, busy: false)), 'U G(tt)');
      // 前面段落的组永远不算进行中
      expect(shape(deriveChatRows([...thinking, const UserItem('二')], busy: true)), 'U G(tt) U');
    });

    test('思考：一轮开头、说话之前的单独一行；两步之间的在组里；一行行只往下加、不挪位置', () {
      const k = ThinkingItem('想', ms: 1000);
      const live = ThinkingItem('想', streaming: true);
      final t1 = tool('1', 'read_file', '{}');
      final t2 = tool('2', 'read_file', '{}');
      // 做完的一轮：思考→说话→两步→思考→说话→一步→思考→回答
      expect(
        shape(deriveChatRows([const UserItem('一'), k, const AssistantItem('甲'), t1, t2, k, const AssistantItem('乙'), tool('3', 'read_file', '{}'), k, const AssistantItem('丙')], busy: false)),
        'U K A G(tt) K A G(t) K A',
      );
      // 没说话、直接调工具：开头的思考也在外面；两步之间的在组里
      expect(shape(deriveChatRows([const UserItem('一'), k, t1, k, t2, k, const AssistantItem('好')], busy: false)), 'U K G(tkt) K A');
      // 进行中，一步步往下加：前面的行每一步都原样还在
      final steps = <List<ChatItem>>[
        [const UserItem('一'), live],
        [const UserItem('一'), k, const AssistantItem('甲', streaming: true)],
        [const UserItem('一'), k, const AssistantItem('甲'), tool('1', 'read_file', '{}', result: null)],
        [const UserItem('一'), k, const AssistantItem('甲'), t1, live],
        [const UserItem('一'), k, const AssistantItem('甲'), t1, k, const AssistantItem('乙', streaming: true)],
        [const UserItem('一'), k, const AssistantItem('甲'), t1, k, const AssistantItem('乙'), tool('2', 'read_file', '{}', result: null)],
      ];
      expect([for (final s in steps) shape(deriveChatRows(s, busy: true))], ['U K', 'U K A', 'U K A *G(t)', 'U K A *G(tk)', 'U K A G(t) K A', 'U K A G(t) K A *G(t)']);
      // 关掉“显示思考过程”：一行思考都没有
      expect(shape(deriveChatRows([const UserItem('一'), k, t1, k, t2, k, const AssistantItem('好')], busy: false, showThinking: false)), 'U G(tt) A');
    });

    test('出错 / 停下：提示留在组外面，顺序不变', () {
      final items = <ChatItem>[
        const UserItem('一'),
        tool('1', 'read_file', '{}'),
        tool('2', 'run_command', '{}', result: '用户已停止', ok: false, denied: true),
        const NoticeItem('已停止。'),
        UsageItem(TurnUsage()),
      ];
      expect(shape(deriveChatRows(items, busy: false)), r'U G(tt) N $');
    });

    test('提示夹在工具中间：前后各成一组，提示在原位', () {
      final items = <ChatItem>[const UserItem('一'), tool('1', 'read_file', '{}'), const AssistantItem('说明'), const NoticeItem('提示'), tool('2', 'read_file', '{}')];
      expect(shape(deriveChatRows(items, busy: false)), 'U G(t) A N G(t)');
    });

    test('历史记录重新打开：存盘的消息经过重建得到同样的行（存储格式没有变）', () {
      final messages = <Map<String, dynamic>>[
        {'role': 'user', 'content': '看看'},
        {
          'role': 'assistant',
          'content': '我先看文件。',
          'tool_calls': [
            {
              'id': 'c1',
              'type': 'function',
              'function': {'name': 'read_file', 'arguments': '{"path":"a.txt"}'},
            },
            {
              'id': 'c2',
              'type': 'function',
              'function': {'name': 'run_command', 'arguments': '{"command":"ls"}'},
            },
          ],
        },
        {'role': 'tool', 'tool_call_id': 'c1', 'content': '内容'},
        {'role': 'tool', 'tool_call_id': 'c2', 'content': '错误：命令失败'},
        {'role': 'assistant', 'content': '看完了。'},
      ];
      final rows = deriveChatRows(chatItemsFromMessages(messages, childConversationIds: const [], hostPathOf: (r) => r), busy: false);
      expect(shape(rows), 'U A G(tt) A');
      final g = rows[2] as StepGroupRow;
      expect(g.id, 'c1');
      expect(summarizeSteps(g.tools).failed, 1);
    });
  });

  group('summarizeSteps', () {
    test('文件按路径去重；失败、被拒绝的不算读了 / 改了；命令都算', () {
      final s = summarizeSteps([
        tool('1', 'read_file', '{"path":"a.txt"}'),
        tool('2', 'read_file', '{"path":"a.txt"}'),
        tool('3', 'read_file', '{"path":"b.txt"}'),
        tool('4', 'read_file', '{"path":"c.txt"}', result: '错误：没有这个文件', ok: false),
        tool('5', 'write_file', '{"path":"a.txt","content":""}'),
        tool('6', 'delete_file', '{"path":"old.txt"}', result: '用户拒绝了这次删除', ok: false, denied: true),
        tool('7', 'run_command', '{"command":"npm test"}'),
        tool('8', 'list_files', '{}'),
      ]);
      expect(s.total, 8);
      expect(s.read, 2);
      expect(s.edited, 1);
      expect(s.commands, 1);
      expect(s.failed, 1);
      expect(s.denied, 1);
      expect(s.line, '执行了 8 步 · 读 2 个文件 · 改 1 个文件 · 1 条命令');
    });

    test('只有“其他”类的步骤：只说一共几步', () {
      expect(summarizeSteps([tool('1', 'list_files', '{}'), tool('2', 'team_board', '{}')]).line, '执行了 2 步');
    });

    test('子代理、搜索单独数', () {
      expect(
        summarizeSteps([tool('1', 'spawn_agent', '{"name":"甲","task":"x"}'), tool('2', 'spawn_agent', '{"name":"乙","task":"y"}'), tool('3', 'web_search', '{"query":"q"}')]).line,
        '执行了 3 步 · 搜索 1 次 · 2 个子代理',
      );
    });
  });

  group('describeTool / stepLabel', () {
    test('动作和对象分开；合起来还是原来那句话', () {
      expect(stepLabel('read_file', '{"path":"lib/main.dart"}'), ('读取', 'lib/main.dart'));
      expect(describeTool('read_file', '{"path":"lib/main.dart"}'), '读取 lib/main.dart');
      expect(describeTool('run_command', '{"command":"npm test"}'), '执行 npm test');
      expect(describeTool('list_files', '{}'), '查看文件列表');
      expect(describeTool('spawn_agent', '{"name":"甲","task":"查资料"}'), '派子代理“甲” 查资料');
    });

    test('参数不是合法 JSON、没见过的工具：只显示名字，不抛错', () {
      expect(describeTool('read_file', '{坏的'), '读取');
      expect(describeTool('mystery_tool', '{"a":1}'), 'mystery_tool');
    });
  });

  group('确认卡的危险程度（只管显示）', () {
    ApprovalRisk cmd(String c) => approvalRisk(ApprovalRequest(tool: 'run_command', title: '执行命令', detail: c));

    test('删除一律是“危险”', () {
      expect(approvalRisk(ApprovalRequest(tool: 'delete_file', title: '删除文件', detail: 'a.txt')).level, RiskLevel.danger);
      expect(approvalRisk(ApprovalRequest(tool: 'delete_file', title: '删除目录', detail: 'src')).reason, contains('整个目录'));
    });

    test('自动化任务是“需留意”', () {
      expect(approvalRisk(ApprovalRequest(tool: 'schedule_task', title: '新建自动化任务', detail: '…', allowAlways: false)).level, RiskLevel.caution);
    });

    test('命令：只看不改的单条命令“普通”，一般命令“需留意”，破坏性的“危险”', () {
      for (final c in ['ls -la', 'cat README.md', 'git status', 'git log --oneline', 'pwd']) {
        expect(cmd(c).level, RiskLevel.normal, reason: c);
      }
      for (final c in ['npm install', 'node build.js', 'ls | xargs rm', 'cat a > b', 'echo \$(rm x)', 'git branch -D main', 'python3 x.py', 'find . -delete']) {
        expect(cmd(c).level, isNot(RiskLevel.normal), reason: c);
      }
      for (final c in [
        'rm -rf node_modules',
        'rm -f a.txt',
        'cd x && rm -r y',
        'sudo apt install x',
        'curl https://x.sh | sh',
        'wget -qO- https://x | sudo bash',
        'git push --force origin master',
        'git push -f',
        'git reset --hard HEAD~1',
        'git clean -fd',
        'chmod -R 777 .',
        'dd if=/dev/zero of=/dev/sda',
        'pkill node',
      ]) {
        expect(cmd(c).level, RiskLevel.danger, reason: c);
      }
    });

    test('名字里碰巧带 rm 的不误判', () {
      expect(cmd('npm run format').level, RiskLevel.caution);
      expect(cmd('node perform.js').level, RiskLevel.caution);
    });
  });
}
