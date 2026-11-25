// 后台命令的几块小东西：步骤行怎么写、通知在聊天记录和导出里是什么样、时长和状态的文案。
import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/agent/agent_runner.dart';
import 'package:lopicode/agent/background_commands.dart';
import 'package:lopicode/agent/background_tools.dart';
import 'package:lopicode/agent/presets.dart';
import 'package:lopicode/session/chat_export.dart';
import 'package:lopicode/session/chat_items.dart';
import 'package:lopicode/session/chat_models.dart';
import 'package:lopicode/session/chat_rows.dart';

BackgroundTask task({BackgroundStatus status = BackgroundStatus.running, int? exitCode, String? stoppedBy, DateTime? endedAt}) => BackgroundTask(
  id: 3,
  convId: 'c1',
  command: 'npm run dev',
  startedAt: DateTime.utc(2026, 11, 25, 1),
  endedAt: endedAt,
  log: '.lopicode/outputs/bg-x-3.txt',
  tag: 't',
  status: status,
  exitCode: exitCode,
  stoppedBy: stoppedBy,
);

void main() {
  test('步骤行：后台启动 <命令> · #任务号（结果还没回来时没有任务号）', () {
    expect(stepLabel(kBgStartTool, '{"command":"npm run dev"}'), ('后台启动', 'npm run dev'));
    expect(stepLabel(kBgStartTool, '{"command":"npm run dev"}', result: '后台命令 #1 已启动，正在后台运行。'), ('后台启动', 'npm run dev · #1'));
    expect(stepLabel(kBgStartTool, '{"command":"npm run dev"}', result: '用户拒绝执行这条命令，命令没有运行。'), ('后台启动', 'npm run dev'));
    expect(stepLabel(kBgReadTool, '{"id":2}'), ('查看后台命令输出', '#2'));
    expect(stepLabel(kBgStopTool, '{"id":2}'), ('停止后台命令', '#2'));
    expect(stepLabel(kBgListTool, '{}'), ('查看后台命令', ''));
    expect(stepKindOf(kBgStartTool), stepKindOf('run_command'), reason: '和执行命令算同一类步骤');
    expect(stepLabel('run_command', '{"command":"ls"}', result: '后台命令 #1'), ('执行', 'ls'), reason: '别的工具不受影响');
  });

  test('四个工具在设置里都有中文名', () {
    for (final name in kBackgroundToolLabels.keys) {
      expect(kToolLabels[name], kBackgroundToolLabels[name]);
    }
  });

  test('通知在聊天记录里是一行提示，不是用户气泡；导出里也标明是应用通知', () {
    final messages = <Map<String, dynamic>>[
      {'role': 'user', 'content': '结果怎么样'},
      {'role': 'user', 'content': '后台命令 #1 …很长的正文…', kAppNoticeMark: '后台命令 #1 已结束（退出码 0），已告诉 AI'},
      {'role': 'assistant', 'content': '跑完了。'},
    ];
    final items = chatItemsFromMessages(messages, childConversationIds: const [], hostPathOf: (r) => r);
    expect(items.whereType<UserItem>().map((u) => u.text), ['结果怎么样']);
    expect(items.whereType<NoticeItem>().single.text, '后台命令 #1 已结束（退出码 0），已告诉 AI');
    final md = conversationMarkdown('标题', messages);
    expect(md, contains('> 应用通知：后台命令 #1 已结束（退出码 0），已告诉 AI'));
    expect(md, isNot(contains('很长的正文')));
  });

  test('时长和状态的文案', () {
    expect(backgroundAge(const Duration(seconds: 5)), '5 秒');
    expect(backgroundAge(const Duration(seconds: 192)), '3 分 12 秒');
    expect(backgroundAge(const Duration(minutes: 135)), '2 小时 15 分');
    expect(backgroundAge(const Duration(seconds: -3)), '0 秒');
    final end = DateTime.utc(2026, 11, 25, 1, 0, 5);
    expect(backgroundStatusLine(task(), now: end), '在跑，已运行 5 秒');
    expect(backgroundStatusLine(task(status: BackgroundStatus.exited, exitCode: 2, endedAt: end)), '已结束，退出码 2，运行了 5 秒');
    expect(backgroundStatusLine(task(status: BackgroundStatus.stopped, stoppedBy: StoppedBy.user, endedAt: end)), '已被用户停止');
    expect(backgroundStatusLine(task(status: BackgroundStatus.interrupted)), contains('没有自动重跑'));
    expect(backgroundNoticeLabel(task(status: BackgroundStatus.interrupted)), '后台命令 #3 在应用关闭时中断了，没有自动重跑');
  });
}
