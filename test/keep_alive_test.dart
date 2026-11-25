// 后台保活协调器（lib/agent/keep_alive.dart）的单元测试：不带界面、不碰平台通道。
// 用 testWidgets 只是为了拿到假时钟（节流、收尾等待都是定时器）。
//   flutter test test/keep_alive_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/agent/keep_alive.dart';
import 'package:lopicode/core/crash_log.dart';

import 'support/keep_alive_fakes.dart';

void main() {
  late FakeKeepAliveHost host;
  late AgentKeepAlive keep;
  var keepOn = true;
  var notifyOn = true;
  var cancelled = <String>[];

  setUp(() {
    keepOn = true;
    notifyOn = true;
    cancelled = [];
    host = FakeKeepAliveHost();
    keep = AgentKeepAlive(keepEnabled: () => keepOn, notifyEnabled: () => notifyOn)..attach(host);
    CrashLog.instance.resetForTest();
  });
  tearDown(() => keep.dispose());

  KeepAliveTicket begin(String name, {bool root = true, bool unattended = false}) => keep.begin(title: name, root: root, unattended: unattended, cancel: () => cancelled.add(name));

  const second = Duration(seconds: 1);
  const linger = Duration(seconds: 3);

  group('开和关', () {
    testWidgets('忙→开，闲→等一会儿再关', (tester) async {
      final t = begin('对话一');
      await tester.pump();
      expect(host.of('start'), ['start:正在准备']);
      expect(keep.active, isTrue);
      t.end(TurnEnd.done);
      await tester.pump(const Duration(seconds: 2));
      expect(host.of('stop'), isEmpty, reason: '刚结束不马上关：排队的下一条会紧接着开新的一轮');
      await tester.pump(second);
      expect(host.of('stop'), ['stop']);
      expect(keep.active, isFalse);
    });

    testWidgets('几段对话同时忙只开一次；都闲了才关', (tester) async {
      final a = begin('对话一');
      final b = begin('子代理', root: false);
      final c = begin('自动任务', unattended: true);
      await tester.pump();
      expect(host.of('start').length, 1);
      expect(keep.running, 3);
      a.end(TurnEnd.done);
      b.end(TurnEnd.done);
      await tester.pump(linger);
      expect(host.of('stop'), isEmpty, reason: '还有一轮在跑');
      c.end(TurnEnd.done);
      await tester.pump(linger);
      expect(host.of('stop'), ['stop']);
      expect(host.of('start').length, 1);
    });

    testWidgets('一轮刚结束就接着开下一轮（排队的消息）：服务不关不重开', (tester) async {
      begin('对话一').end(TurnEnd.done);
      await tester.pump(second);
      final next = begin('对话一');
      await tester.pump(linger);
      expect(host.of('stop'), isEmpty);
      expect(host.of('start').length, 1);
      next.end(TurnEnd.done);
      await tester.pump(linger);
      expect(host.of('stop'), ['stop']);
    });

    testWidgets('设置关着：不开服务；跑到一半关掉：马上撤', (tester) async {
      keepOn = false;
      final t = begin('对话一');
      await tester.pump();
      expect(host.calls, isEmpty);
      keepOn = true;
      keep.refresh();
      await tester.pump();
      expect(host.of('start').length, 1, reason: '跑到一半打开开关：补开');
      keepOn = false;
      keep.refresh();
      await tester.pump();
      expect(host.of('stop'), ['stop']);
      t.end(TurnEnd.done);
      await tester.pump(linger);
      expect(host.of('stop'), ['stop'], reason: '已经关了，不再关第二次');
    });

    testWidgets('系统不让开（应用在后台）：不反复重试；回到前台再试一次', (tester) async {
      host.allowStart = false;
      final t = begin('自动任务', unattended: true);
      await tester.pump();
      expect(keep.active, isFalse);
      t.status('第 1 步');
      t.status('第 2 步');
      await tester.pump(linger);
      expect(host.of('start').length, 1, reason: '被拒以后不每次都重试');
      host
        ..allowStart = true
        ..setVisible!(false);
      host.setVisible!(true);
      await tester.pump();
      expect(host.of('start').length, 2);
      expect(keep.active, isTrue);
      t.end(TurnEnd.done);
      await tester.pump(linger);
    });
  });

  group('通知上的字', () {
    testWidgets('节流：一秒里变很多次只发最后那次', (tester) async {
      final t = begin('对话一');
      await tester.pump();
      for (var i = 1; i <= 20; i++) {
        t.status('第 $i 步');
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(host.of('update'), isEmpty, reason: '离上一次发不到一秒');
      await tester.pump(second);
      expect(host.of('update'), ['update:第 20 步']);
      // 之后安静了一秒以上：再变马上发
      await tester.pump(second);
      t.status('正在思考');
      await tester.pump();
      expect(host.of('update'), ['update:第 20 步', 'update:正在思考']);
      // 十秒里不停地变：最多十来次
      for (var i = 0; i < 100; i++) {
        t.status('变 $i');
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(host.of('update').length, lessThanOrEqualTo(2 + 11));
      t.end(TurnEnd.done);
      await tester.pump(linger);
    });

    testWidgets('变回原样不发；同时跑几个时写明个数，显示最近有动静的那个', (tester) async {
      final a = begin('对话一');
      await tester.pump(second);
      a.status('正在读 a.dart');
      await tester.pump(second);
      a.status('正在读 a.dart');
      await tester.pump(second);
      expect(host.of('update'), ['update:正在读 a.dart']);
      final b = begin('子代理', root: false);
      await tester.pump(second);
      b.status('正在改 b.dart');
      await tester.pump(second);
      expect(host.shown!.text, '正在改 b.dart · 同时在跑 2 个');
      b.end(TurnEnd.done);
      await tester.pump(second);
      expect(host.shown!.text, '正在读 a.dart');
      a.end(TurnEnd.done);
      await tester.pump(linger);
    });

    testWidgets('密钥不上通知；多行压成一行；太长截短', (tester) async {
      final t = begin('对话一');
      await tester.pump(second);
      t.status('正在跑命令：curl -H "Authorization: Bearer abcdefgh12345678" https://api.example.com\n&& export OPENAI_API_KEY=sk-abcdefghijklmnop1234');
      await tester.pump(second);
      final text = host.shown!.text;
      expect(text, isNot(contains('abcdefgh12345678')));
      expect(text, isNot(contains('sk-abcdefghijklmnop1234')));
      expect(text, isNot(contains('\n')));
      expect(text.length, lessThanOrEqualTo(kNoticeTextMax + 1));
      expect(host.shown!.lockText, '解锁后查看进度', reason: '锁屏那一句不带任何内容');
      expect(host.shown!.title, isNot(contains('对话一')), reason: '标题不带对话内容');
      t.end(TurnEnd.done);
      await tester.pump(linger);
      expect(safeNoticeText('token=ghp_abcdefgh12345678 ok'), isNot(contains('ghp_abcdefgh12345678')));
      expect(safeNoticeText('x' * 300).length, kNoticeTextMax + 1);
    });
  });

  group('做完 / 出错 / 等确认的提醒', () {
    testWidgets('应用看得见：什么都不发', (tester) async {
      final t = begin('对话一');
      t.waiting(true);
      t.waiting(false);
      t.end(TurnEnd.done);
      await tester.pump(linger);
      expect(host.of('alert'), isEmpty);
    });

    testWidgets('应用看不见：做完发一条，带对话名；锁屏那句不带', (tester) async {
      final t = begin('给首页加个按钮');
      host.setVisible!(false);
      t.end(TurnEnd.done);
      await tester.pump(second);
      expect(host.of('alert'), isEmpty, reason: '等确认没有新的一轮再发');
      await tester.pump(linger);
      expect(host.of('alert'), ['alert:done:Agent 做完了|给首页加个按钮 · 打开应用看结果|打开应用看结果']);
    });

    testWidgets('出错发“出错了”；几轮里有一轮出错就说出错；只发一条', (tester) async {
      host.setVisible!(false);
      final a = begin('对话一');
      final b = begin('对话二');
      a.end(TurnEnd.failed);
      b.end(TurnEnd.done);
      await tester.pump(linger);
      expect(host.of('alert'), ['alert:failed:Agent 出错了，没做完|对话一 · 打开应用看原因|打开应用看原因']);
    });

    testWidgets('自动化任务做完：写明是自动化任务', (tester) async {
      host.setVisible!(false);
      begin('[自动] 每日检查', unattended: true).end(TurnEnd.done);
      await tester.pump(linger);
      expect(host.of('alert').single, startsWith('alert:done:自动化任务做完了|'));
    });

    testWidgets('子代理结束、用户自己点停止、设置关着：都不发', (tester) async {
      host.setVisible!(false);
      begin('子代理', root: false).end(TurnEnd.failed);
      await tester.pump(linger);
      begin('对话一').end(TurnEnd.stopped);
      await tester.pump(linger);
      notifyOn = false;
      begin('对话一').end(TurnEnd.done);
      await tester.pump(linger);
      expect(host.of('alert'), isEmpty);
    });

    testWidgets('做完后、提醒发出前人回来了：不发，并把旧提醒收掉', (tester) async {
      host.setVisible!(false);
      begin('对话一').end(TurnEnd.done);
      await tester.pump(second);
      host.setVisible!(true);
      await tester.pump(linger);
      expect(host.of('alert'), isEmpty);
      expect(host.of('cancel'), contains('cancel:all'));
    });

    testWidgets('看不见时卡在确认卡上：发“在等你确认”，通知上的字也换；点完收掉', (tester) async {
      final t = begin('对话一');
      await tester.pump(second);
      host.setVisible!(false);
      t.waiting(true);
      await tester.pump();
      expect(host.of('alert'), ['alert:waiting:Agent 在等你确认|有一步要你点头才能继续，打开应用处理|打开应用处理']);
      expect(host.shown!.title, 'Agent 在等你确认');
      t.waiting(true);
      await tester.pump();
      expect(host.of('alert').length, 1, reason: '同一张卡只提醒一次');
      t.waiting(false);
      await tester.pump(second);
      expect(host.of('cancel'), contains('cancel:waiting'));
      expect(host.shown!.title, 'Agent 正在干活');
      t.end(TurnEnd.done);
      await tester.pump(linger);
    });

    testWidgets('等确认时这一轮被停了：提醒也收掉', (tester) async {
      final t = begin('对话一');
      host.setVisible!(false);
      t.waiting(true);
      t.end(TurnEnd.stopped);
      await tester.pump(linger);
      expect(host.of('cancel'), contains('cancel:waiting'));
      expect(host.of('alert').where((c) => !c.startsWith('alert:waiting')), isEmpty);
    });
  });

  group('停止按钮', () {
    testWidgets('通知上点停止：每一轮都被叫停，字马上换成“正在停止”，不再提醒做完', (tester) async {
      final a = begin('对话一');
      final b = begin('子代理', root: false);
      await tester.pump();
      host.setVisible!(false);
      a.status('第 3 步 · 正在跑命令');
      host.pressStop!();
      await tester.pump();
      expect(cancelled, ['对话一', '子代理']);
      expect(host.shown!.text, '正在停止…');
      a.end(TurnEnd.failed);
      b.end(TurnEnd.failed);
      await tester.pump(linger);
      expect(host.of('stop'), ['stop']);
      expect(host.of('alert'), isEmpty);
      // 下一轮照常
      final again = begin('对话一');
      await tester.pump();
      expect(host.shown!.text, '正在准备');
      again.end(TurnEnd.done);
      await tester.pump(linger);
    });

    testWidgets('没有在跑的时候点停止：什么都不做；某一轮的停止抛错不影响别的', (tester) async {
      host.pressStop!();
      expect(host.calls, isEmpty);
      final bad = keep.begin(title: '坏的', root: true, cancel: () => throw StateError('停不了'));
      final good = begin('好的');
      host.pressStop!();
      await tester.pump();
      expect(cancelled, ['好的']);
      bad.end(TurnEnd.stopped);
      good.end(TurnEnd.stopped);
      await tester.pump(linger);
    });
  });

  group('不崩、不漏', () {
    testWidgets('通道每次都抛错：不抛到外面，票照常用；同一种错只记一次', (tester) async {
      host.broken = true;
      final t = begin('对话一');
      await tester.pump();
      host.setVisible!(false);
      for (var i = 0; i < 5; i++) {
        t.status('第 $i 步');
        await tester.pump(second);
      }
      t.waiting(true);
      t.waiting(false);
      host.pressStop!();
      t.end(TurnEnd.failed);
      await tester.pump(linger);
      host.setVisible!(true);
      await tester.pump();
      expect(tester.takeException(), isNull);
      final notes = CrashLog.instance.entries.where((e) => e.source == '后台保活').toList();
      expect(notes, isNotEmpty);
      expect(notes.map((e) => e.message).toSet().length, notes.length, reason: '同一种错只记一次');
      expect(notes.every((e) => !e.message.contains('假的')), isTrue, reason: '只记错误类型，不带内容');
    });

    testWidgets('销毁后：不再调用原生，票的方法都是空操作，定时器不再触发', (tester) async {
      final t = begin('对话一');
      await tester.pump();
      host.setVisible!(false);
      keep.dispose();
      await tester.pump();
      final before = host.calls.length;
      expect(host.calls.last, 'stop', reason: '销毁时把服务关掉');
      t.status('第 9 步');
      t.waiting(true);
      t.end(TurnEnd.done);
      host.pressStop!();
      host.setVisible!(true);
      final late = begin('销毁后才来的');
      late.status('x');
      late.end(TurnEnd.done);
      keep.refresh();
      await tester.pump(const Duration(seconds: 10));
      expect(host.calls.length, before);
      expect(cancelled, isEmpty);
    });

    testWidgets('同一张票交两次只算一次', (tester) async {
      host.setVisible!(false);
      final t = begin('对话一');
      t.end(TurnEnd.done);
      t.end(TurnEnd.failed);
      await tester.pump(linger);
      expect(host.of('alert').single, startsWith('alert:done'));
      expect(keep.running, 0);
    });
  });
}
