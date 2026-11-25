// 后台命令给模型用的四个工具：启动、读输出、停止、列清单；以及“后台命令结束了”那条通知怎么写。
//
// 确认规矩（改动要小心）：
// - 启动：和 run_command **同级**。性质是 [ToolKind.exec]（仅可查看、计划模式下不出现、硬调也拒绝）；
// 确认走调用方给的 [approve]——接的是 AgentToolbox 里 run_command 用的同一个判断
// （完全权限 / “本对话都允许”不问，其余出确认卡；没人在场一律按拒绝）。确认卡按 run_command 的样子出，危险提示也一样。
// - 读输出、列清单：只读。
// - 停止：只能停这段对话自己起的，不用确认；性质也是 [ToolKind.exec]（仅可查看、计划模式下不出现）。
// - 执行环境还不能用、已经到上限：不出确认卡，直接把原因回给模型。只会少执行，不会多执行。
import 'dart:async';
import 'dart:io';

import 'package:lopicode/agent/agent_runner.dart';
import 'package:lopicode/agent/agent_tools.dart';
import 'package:lopicode/agent/background_commands.dart';
import 'package:lopicode/agent/command_runner.dart';

const String kBgStartTool = 'start_background_command';
const String kBgReadTool = 'read_background_output';
const String kBgStopTool = 'stop_background_command';
const String kBgListTool = 'list_background_commands';

/// 四个工具的名字 → 给人看的说明（设置页的工具开关、步骤行用）。
const Map<String, String> kBackgroundToolLabels = {kBgStartTool: '后台执行命令', kBgReadTool: '查看后台命令的输出', kBgStopTool: '停止后台命令', kBgListTool: '查看后台命令清单'};

/// 结束通知里带最后几行输出、最多多少字符。
const int kBackgroundNoticeLines = 20;
const int kBackgroundNoticeChars = 2000;

/// 启动后最多等这么久看它是不是马上就退出了（命令打错、端口被占），好把结果直接告诉模型。
const Duration kBackgroundStartPeek = Duration(milliseconds: 400);

/// 读输出时 wait_seconds 最多等多久。
const int kBackgroundMaxWaitSeconds = 20;

/// “3 分 12 秒”这样的时长。
String backgroundAge(Duration d) {
  final s = d.inSeconds < 0 ? 0 : d.inSeconds;
  if (s < 60) return '$s 秒';
  if (s < 3600) return '${s ~/ 60} 分 ${s % 60} 秒';
  return '${s ~/ 3600} 小时 ${s % 3600 ~/ 60} 分';
}

/// 一句话状态：`在跑，已运行 3 分 12 秒` / `已结束，退出码 0，运行了 5 秒` / `已停止（用户停的）`……
String backgroundStatusLine(BackgroundTask t, {DateTime? now}) {
  final age = backgroundAge(t.age(now ?? DateTime.now()));
  return switch (t.status) {
    BackgroundStatus.running => '在跑，已运行 $age',
    BackgroundStatus.exited => '已结束，退出码 ${t.exitCode ?? '未知'}，运行了 $age',
    BackgroundStatus.stopped => switch (t.stoppedBy) {
      StoppedBy.user => '已被用户停止',
      StoppedBy.close => '工作区关闭时已停止',
      _ => '已停止',
    },
    BackgroundStatus.interrupted => '已中断（应用被关闭，命令没有接着跑，也没有自动重跑）',
  };
}

String _clipCommand(String command) {
  final line = command.trim().split('\n').first;
  return line.length > 60 ? '${line.substring(0, 60)}…' : line;
}

/// 聊天页上那一行短提示。
String backgroundNoticeLabel(BackgroundTask t) => switch (t.status) {
  BackgroundStatus.exited => '后台命令 #${t.id} 已结束（退出码 ${t.exitCode ?? '未知'}）',
  BackgroundStatus.stopped => t.stoppedBy == StoppedBy.close ? '后台命令 #${t.id} 在工作区关闭时停掉了' : '后台命令 #${t.id} 已停止',
  BackgroundStatus.interrupted => '后台命令 #${t.id} 在应用关闭时中断了，没有自动重跑',
  BackgroundStatus.running => '后台命令 #${t.id} 在跑',
};

/// “后台命令结束了”给模型的那条通知。
AppNotice backgroundNotice(BackgroundCommands manager, BackgroundTask t) {
  var tail = manager.tail(t.id, lines: kBackgroundNoticeLines);
  if (tail.length > kBackgroundNoticeChars) tail = '…${tail.substring(tail.length - kBackgroundNoticeChars)}';
  final text = StringBuffer('【应用通知，不是用户说的话】后台命令 #${t.id}（${_clipCommand(t.command)}）${backgroundStatusLine(t)}。\n')
    ..write(tail.trim().isEmpty ? '（没有输出）' : '最后几行输出：\n$tail')
    ..write('\n完整日志：${t.log}（可以用 read_file 分段读）。');
  return AppNotice(text.toString(), '${backgroundNoticeLabel(t)}，已告诉 AI');
}

int _taskId(Map<String, dynamic> args) {
  final v = args['id'];
  final n = v is int ? v : (v is String ? int.tryParse(v.trim().replaceFirst('#', '')) : (v is double && v == v.roundToDouble() ? v.toInt() : null));
  if (n == null || n < 1) throw ToolArgError('缺少参数 id（后台命令的任务号，例如 1）');
  return n;
}

/// 后台命令的四个工具。[convId] 是归属的主对话；[runner] 不支持后台启动时返回空（这些工具不出现）。
/// [stopSignal]：这一轮被用户叫停时完成的信号（读输出时的等待据此提前结束）。
List<ExtraTool> backgroundCommandTools({
  required BackgroundCommands manager,
  required String convId,
  required CommandRunner runner,
  required Future<bool> Function(ApprovalRequest request) approve,
  Future<void>? Function()? stopSignal,
}) {
  final Object env = runner;
  if (env is! HasBackgroundStart) return const [];

  BackgroundTask mine(int id) {
    final t = manager.byId(id);
    if (t == null || t.convId != convId) {
      final ids = manager.of(convId).map((t) => '#${t.id}').join('、');
      throw ToolArgError('这段对话里没有后台命令 #$id。${ids.isEmpty ? '现在一个后台命令都没有' : '现有的：$ids'}');
    }
    return t;
  }

  String describe(BackgroundTask t) => '#${t.id} ${backgroundStatusLine(t)}\n命令：${t.command}\n日志：${t.log}';

  Future<ToolOutcome> start(Map<String, dynamic> args) async {
    final command = AgentToolbox.argString(args, 'command');
    final Object probe = runner;
    final unavailable = probe is HasCommandAvailability ? probe.unavailableReason : null;
    if (unavailable != null) return ToolOutcome('命令没有执行：$unavailable', ok: false);
    await manager.load();
    if (manager.runningCount >= kMaxBackgroundRunning) {
      return ToolOutcome('错误：已经有 $kMaxBackgroundRunning 个后台命令在跑（上限 $kMaxBackgroundRunning 个），这一条没有启动。先等一个结束，或者用 $kBgStopTool 停掉一个不用的', ok: false);
    }
    // 和 run_command 同一张确认卡（同样的危险提示、同样受“本对话都允许”和权限档位管）。
    if (!await approve(ApprovalRequest(tool: 'run_command', title: '在后台执行命令', detail: command))) {
      return ToolOutcome('用户拒绝执行这条命令，命令没有运行。', ok: false, denied: true);
    }
    final BackgroundTask task;
    try {
      task = await manager.start(convId, command, env);
    } on BackgroundCommandError catch (e) {
      return ToolOutcome('错误：${e.message}', ok: false);
    } on ProcessException catch (e) {
      return ToolOutcome('错误：后台命令没能启动（${e.message}）', ok: false);
    }
    // 稍等一下：马上就退出的（命令打错、端口被占）直接把结果给模型，不用它再来问。
    final until = DateTime.now().add(kBackgroundStartPeek);
    while ((manager.byId(task.id)?.running ?? false) && DateTime.now().isBefore(until)) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    final now = manager.byId(task.id) ?? task;
    if (!now.running) {
      final out = manager.readNew(now.id)?.text ?? '';
      manager.setNotified([now.id]);
      return ToolOutcome('后台命令 #${now.id} 刚启动就结束了：${backgroundStatusLine(now)}。\n${out.trim().isEmpty ? '（没有输出）' : out}', ok: now.exitCode == 0, changedFiles: true);
    }
    return ToolOutcome(
      '后台命令 #${now.id} 已启动，正在后台运行。\n'
      '- 看输出：$kBgReadTool（id=${now.id}）；停止：$kBgStopTool（id=${now.id}）。\n'
      '- 它结束时你会收到通知，不用反复查询；你可以接着做别的事。\n'
      '- 完整日志：${now.log}',
      changedFiles: true,
    );
  }

  Future<ToolOutcome> read(Map<String, dynamic> args) async {
    await manager.load();
    var task = mine(_taskId(args));
    final lines = args['tail_lines'];
    if (lines != null) {
      final n = lines is int ? lines : (lines is String ? int.tryParse(lines.trim()) : null);
      if (n == null || n < 1) throw ToolArgError('tail_lines 应为正整数');
      final text = manager.tail(task.id, lines: n > 200 ? 200 : n);
      return ToolOutcome('${describe(task)}\n最后 ${n > 200 ? 200 : n} 行：\n${text.isEmpty ? '（没有输出）' : text}');
    }
    final wait = args['wait_seconds'];
    final seconds = wait is num ? wait.clamp(0, kBackgroundMaxWaitSeconds).toInt() : 0;
    var out = manager.readNew(task.id);
    if (seconds > 0 && task.running && (out?.text.isEmpty ?? true)) {
      // 等新输出 / 等它结束，最多 wait_seconds 秒；用户点停止就不等了。
      var cancelled = false;
      unawaited(stopSignal?.call()?.then((_) => cancelled = true, onError: (_) => cancelled = true));
      final until = DateTime.now().add(Duration(seconds: seconds));
      while (!cancelled && DateTime.now().isBefore(until)) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
        out = manager.readNew(task.id);
        if ((out?.text.isNotEmpty ?? false) || !(manager.byId(task.id)?.running ?? false)) break;
      }
    }
    task = manager.byId(task.id) ?? task;
    // 它已经结束、而且模型在这里看到了：不用再另发通知。
    if (!task.running) manager.setNotified([task.id]);
    final skipped = out?.skipped ?? 0;
    final text = out?.text ?? '';
    final note = skipped > 0 ? '（前面还有 $skipped 字节没显示：新输出太多，只给了最后一段。完整日志在 ${task.log}，可以用 read_file 分段读）\n' : '';
    return ToolOutcome('${describe(task)}\n${text.isEmpty ? '（上次读过之后没有新输出）' : '新输出：\n$note$text'}');
  }

  Future<ToolOutcome> stop(Map<String, dynamic> args) async {
    await manager.load();
    final task = mine(_taskId(args));
    if (!task.running) {
      manager.setNotified([task.id]);
      return ToolOutcome('后台命令 #${task.id} 本来就不在跑了：${backgroundStatusLine(task)}');
    }
    final after = await manager.stop(task.id, by: StoppedBy.agent) ?? task;
    if (after.running) return ToolOutcome('错误：后台命令 #${task.id} 没能停下来，还在跑', ok: false);
    final tail = manager.tail(task.id, lines: 10);
    return ToolOutcome('后台命令 #${task.id} 已停止，它起的进程也一起结束了。${tail.isEmpty ? '' : '\n最后几行输出：\n$tail'}', changedFiles: true);
  }

  Future<ToolOutcome> list(Map<String, dynamic> args) async {
    await manager.load();
    final all = manager.of(convId);
    if (all.isEmpty) return ToolOutcome('这段对话里没有后台命令。');
    return ToolOutcome(all.map(describe).join('\n\n'));
  }

  const idProp = {'type': 'integer', 'description': '后台命令的任务号（启动时返回的 #N 里的 N）'};
  return [
    ExtraTool(
      spec: toolSpec(
        kBgStartTool,
        '把一条要长时间运行的命令放到后台跑（开发服务器、文件监听、很久的构建），立刻返回任务号，你可以接着做别的。需要用户确认。'
        '它结束时你会自动收到通知。不要用 run_command 加 & 或 nohup 来代替；很快就能跑完的命令还是用 run_command。'
        '同时最多 $kMaxBackgroundRunning 个。',
        {
          'command': {'type': 'string', 'description': '要在后台执行的命令'},
        },
        ['command'],
      ),
      kind: ToolKind.exec,
      run: start,
    ),
    ExtraTool(
      spec: toolSpec(
        kBgReadTool,
        '看一个后台命令的状态和输出。默认只给“上次读过之后”的新输出；给 tail_lines 则看最后 N 行。',
        {
          'id': idProp,
          'tail_lines': {'type': 'integer', 'description': '看最后多少行（最多 200）。不给就是接着上次读'},
          'wait_seconds': {'type': 'integer', 'description': '没有新输出时最多等几秒（0–$kBackgroundMaxWaitSeconds，默认 0）。等服务器启动好时用'},
        },
        ['id'],
      ),
      kind: ToolKind.read,
      run: read,
    ),
    ExtraTool(spec: toolSpec(kBgStopTool, '停止这段对话里的一个后台命令（连同它起的所有进程）。', {'id': idProp}, ['id']), kind: ToolKind.exec, run: stop),
    ExtraTool(spec: toolSpec(kBgListTool, '列出这段对话里的后台命令（任务号、状态、命令、日志文件）。', {}), kind: ToolKind.read, run: list),
  ];
}
