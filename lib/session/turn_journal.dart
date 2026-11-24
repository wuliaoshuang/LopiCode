// “这一轮进行到哪了”的落盘记录：App 在一轮进行中被关掉 / 被系统回收后，下次打开这段对话能说清楚上次停在哪。
//
// 每段对话一个小文件（`.lopicode/turn-<对话 id>.json`）：一轮开始时写上“进行中”，每一步开始、结束、等用户确认时各更新一次，
// 正常收尾（做完、出错、用户点停止）时写上“已结束”。下次读到“进行中”而且不是本次启动写的，就是上一轮没正常结束。
//
// 规矩：
// - 写盘不等（排队写，见 safe_file），不拖慢这一轮；文件坏了当没有（不提示，也不崩）。
// - 这里只管记和读，**绝不重跑任何东西**：要不要继续由用户点。
import 'dart:async';
import 'dart:io';

import 'package:lopicode/core/safe_file.dart';
import 'package:lopicode/session/chat_models.dart';
import 'package:lopicode/session/chat_rows.dart';

/// 本次启动的记号：记录里的记号和它一样，说明那一轮是这次启动跑的（可能还在跑），不算“被中断”。
final String kProcessToken = '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}-$pid';

String _clip(String s, int max) => s.length > max ? '${s.substring(0, max)}…' : s;

/// 记录里的一步（一次工具调用）。
class JournalStep {
  JournalStep(this.callId, this.name, this.arguments, {this.done = false, this.ok = true, this.denied = false, this.awaiting = false});
  final String callId;
  final String name;
  final String arguments;

  /// 结果回来了没有。
  bool done;
  bool ok;
  bool denied;

  /// 被关掉的时候是不是正停在确认卡上（还没执行）。
  bool awaiting;

  Map<String, dynamic> toJson() => {'id': callId, 'name': name, 'args': arguments, 'done': done, 'ok': ok, if (denied) 'denied': true, if (awaiting) 'awaiting': true};

  static JournalStep? fromJson(Object? j) {
    if (j is! Map) return null;
    final id = j['id'], name = j['name'], args = j['args'];
    if (id is! String || name is! String) return null;
    return JournalStep(id, name, args is String ? args : '', done: j['done'] == true, ok: j['ok'] != false, denied: j['denied'] == true, awaiting: j['awaiting'] == true);
  }
}

/// 一轮的记录。
class TurnJournal {
  TurnJournal({required this.token, required this.startedAt, required this.text, List<JournalStep>? steps, this.finished = false, this.awaitingContinue = false}) : steps = steps ?? [];

  final String token;
  final DateTime startedAt;

  /// 这一轮用户说的话（截短）。
  final String text;
  final List<JournalStep> steps;

  /// 正常收尾了。
  bool finished;

  /// 被关掉的时候正在问“已执行 N 步，要继续吗”。
  bool awaitingContinue;

  Map<String, dynamic> toJson() => {
    'v': 1,
    'token': token,
    'at': startedAt.millisecondsSinceEpoch,
    'text': text,
    'finished': finished,
    if (awaitingContinue) 'ask': true,
    'steps': [for (final s in steps) s.toJson()],
  };

  static TurnJournal? fromJson(Object? j) {
    if (j is! Map) return null;
    final token = j['token'], at = j['at'], text = j['text'], steps = j['steps'];
    if (token is! String || at is! int) return null;
    return TurnJournal(
      token: token,
      startedAt: DateTime.fromMillisecondsSinceEpoch(at),
      text: text is String ? text : '',
      finished: j['finished'] == true,
      awaitingContinue: j['ask'] == true,
      steps: [for (final s in steps is List ? steps : const []) ?JournalStep.fromJson(s)],
    );
  }

  /// 上一轮没正常结束时给用户看的提示。
  InterruptedItem describe() {
    final done = steps.where((s) => s.done).toList();
    final open = steps.where((s) => !s.done).toList();
    final lines = <String>[];
    if (text.trim().isNotEmpty) lines.add('当时你说的是：“${_clip(text.trim().replaceAll('\n', ' '), 60)}”');
    if (done.isEmpty) {
      lines.add('一步都还没执行完。');
    } else {
      final failed = done.where((s) => !s.ok && !s.denied).length;
      final shown = done.length > 6 ? done.sublist(done.length - 6) : done;
      lines.add('已经执行完 ${done.length} 步${failed > 0 ? '（其中 $failed 步失败）' : ''}${done.length > shown.length ? '，最后几步是：' : '：'}');
      lines.addAll([for (final s in shown) '· ${_clip(describeTool(s.name, s.arguments).replaceAll('\n', ' '), 60)}']);
    }
    var risky = false;
    for (final s in open) {
      final what = _clip(describeTool(s.name, s.arguments).replaceAll('\n', ' '), 60);
      if (s.awaiting) {
        lines.add('“$what”当时在等你确认，还没点就中断了：这一步没有执行，确认卡不会恢复。');
        continue;
      }
      risky = true;
      lines.add(switch (stepKindOf(s.name)) {
        StepKind.command => '“$what”这条命令当时正在跑：它可能没执行完，只执行了一半。',
        StepKind.edit || StepKind.delete => '“$what”当时正在进行：文件可能没写完 / 没删完。',
        StepKind.agent => '“$what”当时还在干活：子代理可能只做了一半。',
        StepKind.read || StepKind.look || StepKind.search || StepKind.ask || StepKind.plan || StepKind.other => '“$what”当时还没结束（只是查看，不影响文件）。',
      });
    }
    final String headline;
    if (awaitingContinue) {
      headline = '上一轮执行了 ${done.length} 步后在问你“要不要继续”，还没回答 App 就被关掉了';
    } else if (open.isNotEmpty) {
      headline = '上一轮在第 ${done.length + 1} 步时中断了（App 被关掉或被系统回收）';
    } else if (done.isEmpty) {
      headline = '上一轮刚开始、还在等模型回复时中断了（App 被关掉或被系统回收）';
    } else {
      headline = '上一轮执行完第 ${done.length} 步、在等模型回复时中断了（App 被关掉或被系统回收）';
    }
    lines.add('不会自动重做任何一步。点“继续”会让 Agent 从这里接着做；点“不用了”就停在这里。');
    return InterruptedItem(headline: headline, lines: lines, risky: risky);
  }
}

/// 点“继续”时发给 Agent 的话。
const String kResumeText = '接着上次中断的地方继续。已经执行过的步骤不要重复；结果不明的那一步先检查实际情况，再决定要不要重做。';

/// 一段对话的进行中记录：读、写、标记结束。
class TurnJournalStore {
  TurnJournalStore(this.file);
  final File file;

  TurnJournal? _current;

  /// 一轮开始。
  void begin(String text) {
    _current = TurnJournal(token: kProcessToken, startedAt: DateTime.now(), text: _clip(text, 300));
    _save();
  }

  void stepStarted(String callId, String name, String arguments) {
    _current?.steps.add(JournalStep(callId, name, _clip(arguments, 500)));
    _save();
  }

  void stepFinished(String callId, {required bool ok, required bool denied}) {
    final step = _current?.steps.where((s) => s.callId == callId && !s.done).lastOrNull;
    if (step == null) return;
    step
      ..done = true
      ..ok = ok
      ..denied = denied
      ..awaiting = false;
    _save();
  }

  /// 出了 / 收了确认卡：把还没结束的那一步标成“在等确认”。
  void setAwaitingApproval(bool waiting) {
    final step = _current?.steps.where((s) => !s.done).lastOrNull;
    if (step == null || step.awaiting == waiting) return;
    step.awaiting = waiting;
    _save();
  }

  /// 正在 / 不再问“要不要继续”。
  void setAwaitingContinue(bool waiting) {
    final j = _current;
    if (j == null || j.awaitingContinue == waiting) return;
    j.awaitingContinue = waiting;
    _save();
  }

  /// 这一轮正常收尾了（做完、出错、用户点停止都算）。
  Future<void> finish() async {
    final j = _current;
    if (j == null) return;
    j.finished = true;
    _current = null;
    await _write(j.toJson());
  }

  /// 用户看过提示、做了选择：记录作废。
  Future<void> dismiss() async {
    _current = null;
    await _write(const {'v': 1, 'finished': true, 'token': '', 'at': 0, 'steps': <Object>[]});
  }

  /// 上一轮要是没正常结束，返回它的记录；否则 null。文件坏了也是 null。
  Future<TurnJournal?> interrupted() async {
    final j = TurnJournal.fromJson(await readJsonFile(file, accept: (v) => v is Map, label: '进行中记录'));
    if (j == null || j.finished || j.token == kProcessToken) return null;
    return j;
  }

  /// 不等写完。内容在这一刻就定下来了（之后再改不影响这次要写的），写盘按先后排队做。
  void _save() {
    final j = _current;
    if (j != null) unawaited(_write(j.toJson()));
  }

  Future<void> _write(Map<String, dynamic> json) async {
    try {
      await writeJsonAtomic(file, json);
    } on FileSystemException {
      // 记不下来就算了：只是下次少一条提示
    }
  }
}
