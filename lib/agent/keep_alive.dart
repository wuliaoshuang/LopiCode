// Agent 干活时的后台保活：什么时候开前台服务、通知上写什么、什么时候发“做完了 / 出错了 / 在等你确认”。
//
// 做法（参考 RikkaHub 的思路，自己写的）：服务只负责“把进程留住 + 显示通知”，Agent 怎么跑还归原来的代码管。
// - 每一轮（主对话、子代理、自动化任务）开始时领一张 [KeepAliveTicket]，结束时交回；手里有票就保持服务开着。
//   同时好几轮在跑也只开一次。
// - 通知上的字最多每 [minGap] 换一次（中间变了几次只发最后那次）。
// - 最后一张票交回后再等 [linger] 才关：排队的下一条消息会紧接着开新的一轮，这段空档不能把服务关掉
//   （应用在后台时系统不让重新开）。
// - 应用看不见时，一轮主对话结束发一条提醒；看得见时不发。用户自己点停止的不发。
// - 凡是交给系统显示的字都先过 [safeNoticeText]：抹密钥、压成一行、截短。
// - 原生那头抛什么错都不许影响 Agent：这里一律接住。
import 'dart:async';

import 'package:lopicode/agent/keep_alive_host.dart';
import 'package:lopicode/core/crash_log.dart';

export 'package:lopicode/agent/keep_alive_host.dart';

/// 通知上一段字最长多少。
const int kNoticeTextMax = 80;

/// 交给系统显示之前：抹掉像密钥的东西、压成一行、截短。
String safeNoticeText(String text, {int max = kNoticeTextMax}) {
  final line = redactSecrets(text).replaceAll(RegExp(r'\s+'), ' ').trim();
  return line.length > max ? '${line.substring(0, max)}…' : line;
}

/// 一轮是怎么结束的。
enum TurnEnd { done, failed, stopped }

/// 一轮在跑的凭据。
class KeepAliveTicket {
  KeepAliveTicket._(this._owner, {required this.title, required this.root, required this.unattended, required this.cancel});
  final AgentKeepAlive _owner;

  /// 对话标题（只出现在提醒的正文里，锁屏隐藏敏感内容时不显示）。
  final String title;

  /// 是不是一轮主对话（子代理结束不单独提醒）。
  final bool root;

  /// 自动化任务（没人在场）。
  final bool unattended;

  /// 通知上点了“停止”：停掉这一轮。
  final void Function() cancel;

  String _text = '正在准备';
  bool _waiting = false;
  bool _ended = false;
  int _seq = 0;

  /// 正在做什么变了。
  void status(String text) {
    if (_ended || text == _text) return;
    _text = text;
    _seq = ++_owner._seq;
    _owner._sync();
  }

  /// 卡在确认卡 / 提问卡上了没有。
  void waiting(bool on) {
    if (_ended || on == _waiting) return;
    _waiting = on;
    _owner._waitingChanged(on);
  }

  /// 这一轮结束了。重复调用只算第一次。
  void end(TurnEnd how) {
    if (_ended) return;
    _ended = true;
    final wasWaiting = _waiting;
    _waiting = false;
    _owner._ended(this, how, wasWaiting: wasWaiting);
  }
}

class AgentKeepAlive {
  AgentKeepAlive({required this.keepEnabled, required this.notifyEnabled, this.minGap = const Duration(seconds: 1), this.linger = const Duration(seconds: 3)});

  /// 设置里“Agent 干活时保持后台运行”开没开。
  final bool Function() keepEnabled;

  /// 设置里“做完时通知我”开没开。
  final bool Function() notifyEnabled;

  /// 通知上的字最快多久换一次（自己定的：1 秒）。测试里会调小。
  Duration minGap;

  /// 最后一轮结束后多久才关服务、发“做完了”（自己定的：3 秒）。测试里会调小。
  Duration linger;

  /// 跟系统说话的那一头。没接之前是空实现（测试、桌面）。
  KeepAliveHost get host => _host;
  KeepAliveHost _host = const NoKeepAliveHost();

  /// 接上宿主（真机是平台通道；测试里换成假的）。
  void attach(KeepAliveHost value) {
    _host = value;
    value.bind(onStop: stopPressed, onVisible: setVisible);
  }

  final List<KeepAliveTicket> _tickets = [];
  int _seq = 0;
  bool _disposed = false;

  /// 应用现在看不看得见（原生那头在界面出现 / 消失时告诉这里；一开始按看得见算）。
  bool get visible => _visible;
  bool _visible = true;

  /// 服务现在是不是（应该）开着。
  bool get active => _on;
  bool _on = false;

  /// 系统刚拒绝过（应用在后台时不让开）：等回到前台或这一批跑完再试。
  bool _blocked = false;
  bool _stopping = false;
  KeepAliveStatus? _sent;
  KeepAliveStatus? _queued;
  Timer? _cooldown;
  Timer? _linger;

  /// 等着发的“做完了 / 出错了”（出错优先）。
  ({TurnEnd how, String title, bool unattended})? _outcome;

  /// 现在有几轮在跑。
  int get running => _tickets.length;

  /// 一轮开始。[cancel]＝通知上点“停止”时怎么停它。
  KeepAliveTicket begin({required String title, required bool root, bool unattended = false, required void Function() cancel}) {
    final ticket = KeepAliveTicket._(this, title: title, root: root, unattended: unattended, cancel: cancel);
    if (_disposed) return ticket.._ended = true;
    ticket._seq = ++_seq;
    _tickets.add(ticket);
    _linger?.cancel();
    _linger = null;
    _sync();
    return ticket;
  }

  /// 设置里的开关动了。
  void refresh() => _sync();

  /// 应用看得见 / 看不见了。
  void setVisible(bool value) {
    if (_disposed || value == _visible) return;
    _visible = value;
    if (!value) return;
    // 人回来了：提醒都收掉，等着发的也不用发了；刚才开不了的服务再试一次。
    _outcome = null;
    _blocked = false;
    _guard(() => _host.cancelAlerts());
    _sync();
  }

  /// 通知上的“停止”被点了：等于聊天页里点停止。
  void stopPressed() {
    if (_disposed || _tickets.isEmpty) return;
    _stopping = true;
    for (final t in [..._tickets]) {
      try {
        t.cancel();
      } on Object catch (e) {
        _complain('停止这一轮时出错：${e.runtimeType}');
      }
    }
    // “正在停止”要马上显示，不等节流
    _cooldown?.cancel();
    _cooldown = null;
    _sync();
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _cooldown?.cancel();
    _linger?.cancel();
    _cooldown = _linger = null;
    _tickets.clear();
    if (_on) {
      _on = false;
      unawaited(_swallow(_host.stop));
    }
  }

  // ── 内部 ─────────────────────────────────────────────
  void _waitingChanged(bool on) {
    if (on) {
      if (!_visible && notifyEnabled()) {
        _guard(() => _host.alert(KeepAliveAlert.waiting, title: 'Agent 在等你确认', text: '有一步要你点头才能继续，打开应用处理', lockText: '打开应用处理'));
      }
    } else if (!_tickets.any((t) => t._waiting)) {
      _guard(() => _host.cancelAlerts(KeepAliveAlert.waiting));
    }
    _sync();
  }

  void _ended(KeepAliveTicket ticket, TurnEnd how, {required bool wasWaiting}) {
    if (_disposed || !_tickets.remove(ticket)) return;
    if (wasWaiting && !_tickets.any((t) => t._waiting)) _guard(() => _host.cancelAlerts(KeepAliveAlert.waiting));
    if (ticket.root && how != TurnEnd.stopped && !_stopping) {
      // 好几轮都结束了只发一条：有出错的就说出错
      if (_outcome?.how != TurnEnd.failed || how == TurnEnd.failed) _outcome = (how: how, title: ticket.title, unattended: ticket.unattended);
    }
    if (_tickets.isNotEmpty) {
      _sync();
      return;
    }
    _linger?.cancel();
    _linger = Timer(linger, _idle);
  }

  /// 最后一轮结束后又等了一会儿，确实没有新的一轮了。
  void _idle() {
    _linger = null;
    if (_disposed || _tickets.isNotEmpty) return;
    _turnOff();
    final outcome = _outcome;
    _outcome = null;
    if (outcome == null || _visible || !notifyEnabled()) return;
    final failed = outcome.how == TurnEnd.failed;
    final who = outcome.unattended ? '自动化任务' : 'Agent ';
    final name = safeNoticeText(outcome.title);
    final hint = failed ? '打开应用看原因' : '打开应用看结果';
    _guard(() => _host.alert(failed ? KeepAliveAlert.failed : KeepAliveAlert.done, title: failed ? '$who出错了，没做完' : '$who做完了', text: name.isEmpty ? hint : '$name · $hint', lockText: hint));
  }

  void _turnOff() {
    _cooldown?.cancel();
    _cooldown = null;
    _sent = _queued = null;
    _blocked = false;
    _stopping = false;
    if (!_on) return;
    _on = false;
    _guard(_host.stop);
  }

  KeepAliveStatus _display() {
    const lock = '解锁后查看进度';
    if (_stopping) return const KeepAliveStatus(title: 'Agent 正在干活', text: '正在停止…', lockText: lock);
    if (_tickets.any((t) => t._waiting)) return const KeepAliveStatus(title: 'Agent 在等你确认', text: '有一步要你点头才能继续，打开应用处理', lockText: '打开应用处理');
    // 最近有动静的那一轮最值得看
    final top = _tickets.reduce((a, b) => b._seq > a._seq ? b : a);
    final text = safeNoticeText(top._text);
    return KeepAliveStatus(title: 'Agent 正在干活', text: _tickets.length > 1 ? '$text · 同时在跑 ${_tickets.length} 个' : text, lockText: lock);
  }

  void _sync() {
    if (_disposed) return;
    if (_tickets.isEmpty) return; // 关不关由 _idle 定
    if (!keepEnabled()) {
      if (_on) _turnOff(); // 跑到一半把开关关了：马上撤掉
      return;
    }
    final status = _display();
    if (!_on) {
      if (_blocked) return;
      _on = true;
      _send(status, start: true);
      return;
    }
    if (status == _sent) {
      _queued = null;
      return;
    }
    if (_cooldown != null) {
      _queued = status; // 还在节流：只记最后一次
      return;
    }
    _send(status);
  }

  void _send(KeepAliveStatus status, {bool start = false}) {
    _sent = status;
    _queued = null;
    _cooldown?.cancel();
    _cooldown = Timer(minGap, () {
      _cooldown = null;
      final next = _queued;
      if (next != null && _on && next != _sent) _send(next);
    });
    if (start) {
      unawaited(_start(status));
    } else {
      _guard(() => _host.update(status));
    }
  }

  Future<void> _start(KeepAliveStatus status) async {
    var ok = false;
    try {
      ok = await _host.start(status);
    } on Object catch (e) {
      _complain('开不了前台服务：${e.runtimeType}');
    }
    if (ok || _disposed) return;
    // 系统不让开（多半是应用在后台）：Agent 照常跑，只是没有保活；回到前台再试
    _on = false;
    _blocked = true;
  }

  /// 调原生那头：不等它，出什么错都接住（只记一笔错误类型，不带内容）。
  void _guard(Future<void> Function() call) {
    if (_disposed) return;
    unawaited(_swallow(call));
  }

  Future<void> _swallow(Future<void> Function() call) async {
    try {
      await call();
    } on Object catch (e) {
      _complain('通知通道出错：${e.runtimeType}');
    }
  }

  /// 同一种错只记一次（通道坏了的话每秒都会错，不能把错误日志刷满）。只记错误类型，不带内容。
  void _complain(String what) {
    if (_complained.add(what)) CrashLog.instance.note(what, source: '后台保活');
  }

  final Set<String> _complained = {};
}
