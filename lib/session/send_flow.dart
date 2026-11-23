// 发送、插话、排队、停止：用户在输入框这头能做的几件事，和一轮跑完后“接着发下一条”的规矩。
import 'dart:async';

import 'package:lopicode/session/chat_models.dart';
import 'package:lopicode/session/session_core.dart';
import 'package:lopicode/session/turn_runner.dart';

class SendFlow {
  SendFlow(this.core, {required this.execute, required this.loadChat});

  final SessionCore core;
  final ExecuteTurn execute;

  /// 先把对话目录和当前对话从盘上读出来（ProjectSession.loadChat）。
  final Future<void> Function() loadChat;

  bool _stoppedByUser = false;
  QueuedMessage? _sendAfterStop;

  List<QueuedMessage> get _queued => core.queue.current.queue;

  /// 发一条消息。AI 正在生成时按 [mode] 处理：排队（默认）、插话、中断并发送。
  Future<void> send(String text, {List<Map<String, dynamic>> images = const [], SendMode mode = SendMode.queue}) async {
    if (text.trim().isEmpty && images.isEmpty) return;
    if (text.trim().isEmpty) text = '（见附件）';
    await loadChat();
    final run = core.active;
    final queue = core.queue;
    if (run.busy) {
      final msg = QueuedMessage(text, images: images, steer: mode == SendMode.steer && images.isEmpty);
      switch (mode) {
        case SendMode.steer when images.isEmpty:
          queue.add(msg);
          run.runner?.steer(text);
        case SendMode.interrupt:
          _sendAfterStop = msg;
          stop();
        default:
          queue.add(msg);
      }
      return;
    }
    _stoppedByUser = false;
    queue.setDraft(null);
    // 第一句话当标题；没选过模型就用新对话默认；最近说过话的排最前
    core.convs?.update(run.convId, (c) => c.copyWith(title: c.title.isEmpty ? titleFromText(text) : null, selection: c.selection ?? core.app.models.defaultForNewChat()?.selection), toFront: true);
    final conv = run.conv;
    final skills = await core.app.skills.enabled(workspaceDir: core.project.dir);
    try {
      await execute(run, text, root: conv, skills: skills, images: images);
    } finally {
      await _afterRun();
    }
  }

  Future<void> _afterRun() async {
    final queue = core.queue;
    // 没来得及交给模型的插话：改成排队，不丢。
    queue.unsteerAll();
    final interrupt = _sendAfterStop;
    _sendAfterStop = null;
    QueuedMessage? next;
    if (interrupt != null) {
      next = interrupt;
    } else if (!_stoppedByUser && _queued.isNotEmpty && queue.current.restoredDraft == null) {
      next = queue.takeFirst();
    }
    if (next != null && !core.disposed) {
      // 用 unawaited：上一轮的 Future 先结束，界面状态不会卡在“生成中”。
      unawaited(send(next.text, images: next.images));
    }
  }

  /// 排队里的一条：立即发送（中断当前这一轮，马上发它）。
  void sendQueuedNow(QueuedMessage msg) {
    if (!core.queue.remove(msg)) return;
    core.active.runner?.withdrawSteer(msg.text);
    if (core.active.busy) {
      _sendAfterStop = msg;
      stop();
    } else {
      unawaited(send(msg.text, images: msg.images));
    }
  }

  /// 排队里的一条：改为插话（下一步就让模型看到）。带图片的不能插话。
  void steerQueued(QueuedMessage msg) {
    if (!_queued.contains(msg) || msg.steer || msg.images.isNotEmpty || !core.active.busy) return;
    core.queue.setSteer(msg, true);
    core.active.runner?.steer(msg.text);
  }

  /// 排队里的一条：撤回（文字交还输入框）。
  void withdrawQueued(QueuedMessage msg) {
    if (!core.queue.remove(msg)) return;
    core.active.runner?.withdrawSteer(msg.text);
    core.queue.setDraft(msg.text);
  }

  /// 停下当前对话和它派出的全部子代理，等着的确认卡、提问卡一并撤掉。
  void stop() {
    _stoppedByUser = true;
    final id = core.dir.activeId;
    final ids = {id, for (final c in core.dir.descendantsOf(id)) c.id};
    for (final id in ids) {
      core.runs[id]?.runner?.cancel();
    }
    core.cards.dropOf(ids);
  }
}
