import 'dart:async';

import 'package:lopicode/agent/automation.dart';
import 'package:lopicode/app_services.dart';
import 'package:lopicode/project_session.dart';

/// 自动化任务的调度：App 开着的时候每半分钟看一眼有没有到点的任务。
///
/// 如实说明：这是应用内的定时器，**App 没在运行时不会触发**（没有用系统级调度）。
/// App 重新打开后，过点超过 5 分钟的那一次只记一笔“错过”，不补跑。
class AutomationScheduler {
  AutomationScheduler(this.app);
  final AppServices app;

  Timer? _timer;
  bool _ticking = false;

  /// 当前开着的工作区会话（有的话，任务直接在它里面跑，对话列表能马上看到）。
  final Map<String, ProjectSession> liveSessions = {};

  /// 正在跑的任务 id。
  final Set<String> running = {};

  void start() {
    _timer ??= Timer.periodic(const Duration(seconds: 30), (_) => tick(DateTime.now()));
    unawaited(tick(DateTime.now()));
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// 处理一遍到点 / 错过的任务。返回这次真正运行了几个。
  Future<int> tick(DateTime now) async {
    if (_ticking) return 0;
    _ticking = true;
    var ran = 0;
    var changed = false;
    try {
      await app.ready();
      final p = app.automations.pending(now);
      for (final a in p.missed) {
        changed = true;
        await app.automations.record(a, AutomationRun(now.toUtc(), 'missed', '到点时 App 没在运行，这一次没有执行'));
      }
      for (final a in p.due) {
        // 先推进时间再跑：跑的过程很长也不会被下一次检查重复触发。
        final startedAt = now.toUtc();
        a.lastRunAt = startedAt;
        if (a.rule.kind == RuleKind.once) a.enabled = false;
        await app.automations.save();
        ran++;
        changed = true;
        unawaited(_run(a, startedAt));
      }
    } finally {
      _ticking = false;
    }
    // 只有真的记了“错过”或启动了任务才通知界面；以前每 30 秒无条件通知一次，等于整个界面定时白白重建。
    if (changed) app.touch();
    return ran;
  }

  /// 立刻跑一次（“立即运行”按钮也走这里）。不改变下一次触发时间。
  Future<AutomationRun> runNow(Automation a) => _run(a, DateTime.now().toUtc());

  Future<AutomationRun> _run(Automation a, DateTime startedAt) async {
    if (!running.add(a.id)) {
      final skipped = AutomationRun(startedAt, 'skipped', '上一次还没跑完，这一次跳过');
      await app.automations.record(a, skipped, advance: false);
      return skipped;
    }
    app.touch();
    AutomationRun result;
    try {
      final live = liveSessions[a.workspaceId];
      if (live != null) {
        result = await live.runAutomation(a);
      } else {
        final project = (await app.projects.list()).where((p) => p.id == a.workspaceId).firstOrNull;
        if (project == null) {
          result = AutomationRun(startedAt, 'failed', '找不到这个任务的工作区（已被删除或从列表移除）');
        } else {
          final session = ProjectSession(app, project, headless: true);
          try {
            result = await session.runAutomation(a);
          } finally {
            session.dispose();
          }
        }
      }
    } on Exception catch (e) {
      result = AutomationRun(startedAt, 'failed', '运行出错：$e');
    } finally {
      running.remove(a.id);
    }
    await app.automations.record(a, result, advance: false);
    app.touch();
    return result;
  }
}
