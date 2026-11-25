// 后台命令的管理器：用宿主机上真实的 /bin/sh 跑。
// 启动、接着读、看最后几行、停止（整棵树）、退出后的状态、同时个数上限、工作区关闭时全停、坏的记录文件不崩、重开后标“已中断”。
@TestOn('linux')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/agent/background_commands.dart';
import 'package:lopicode/agent/command_output_store.dart';
import 'package:lopicode/agent/command_runner.dart';
import 'package:lopicode/agent/process_tree.dart';
import 'package:lopicode/core/path_guard.dart';
import 'package:lopicode/core/safe_file.dart';
import 'package:path/path.dart' as p;

import 'command_stop_test.dart' show alive, expectGone, pidOf;

Future<void> until(bool Function() cond, String what, {int ms = 6000}) async {
  final end = DateTime.now().add(Duration(milliseconds: ms));
  while (!cond() && DateTime.now().isBefore(end)) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  if (!cond()) fail('等不到：$what');
}

void main() {
  late Directory tmp;
  late PathGuard guard;
  late BackgroundCommands manager;
  final shell = LocalShellRunner();

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('lopi_bg_');
    guard = PathGuard(tmp.path);
    manager = BackgroundCommands(guard);
    await manager.load();
  });
  tearDown(() async {
    manager.dispose();
    await pendingWrites();
    tmp.deleteSync(recursive: true);
  });

  BackgroundTask now(int id) => manager.byId(id)!;
  String logOf(BackgroundTask t) => File(p.join(tmp.path, t.log)).readAsStringSync();
  File record() => File(p.join(tmp.path, kBackgroundFile));

  test('启动：立刻返回任务号，命令在工作区目录里跑，输出落到 .lopicode/outputs/ 下', () async {
    final watch = Stopwatch()..start();
    final t = await manager.start('c1', 'pwd; echo hello; sleep 30', shell);
    expect(watch.elapsed, lessThan(const Duration(seconds: 2)), reason: '不等命令结束');
    expect(t.id, 1);
    expect(t.running, isTrue);
    expect(t.convId, 'c1');
    expect(t.log, startsWith('.lopicode/outputs/bg-'));
    expect(isCommandOutputPath(t.log), isTrue, reason: 'Agent 能用 read_file 读它');
    await until(() => logOf(t).contains('hello'), '输出写进日志');
    expect(logOf(t), contains(tmp.resolveSymbolicLinksSync()));
    final second = await manager.start('c1', 'sleep 30', shell);
    expect(second.id, 2, reason: '任务号往上数');
    expect(manager.runningCount, 2);
  });

  test('接着读：每次只给上次读过之后的新输出', () async {
    final t = await manager.start('c1', 'echo one; sleep 0.4; echo two; sleep 0.4; echo three; sleep 30', shell);
    await until(() => logOf(t).contains('one'), 'one');
    final first = manager.readNew(t.id)!;
    expect(first.text, contains('one'));
    expect(first.text, isNot(contains('three')));
    await until(() => logOf(t).contains('three'), 'three');
    final second = manager.readNew(t.id)!;
    expect(second.text, isNot(contains('one')), reason: '读过的不再给');
    expect(second.text, contains('three'));
    expect(manager.readNew(t.id)!.text, isEmpty, reason: '没有新输出');
    expect(manager.readNew(99), isNull);
  });

  test('接着读：新输出太多时只给最后一段，并说明跳过了多少', () async {
    final t = await manager.start('c1', r'i=0; while [ $i -lt 3000 ]; do echo "line-$i-xxxxxxxxxxxxxxxxxxxx"; i=$((i+1)); done; echo END', shell);
    await until(() => !now(t.id).running, '跑完');
    final out = manager.readNew(t.id)!;
    expect(out.skipped, greaterThan(0));
    expect(utf8.encode(out.text).length, lessThanOrEqualTo(kBackgroundReadBytes));
    expect(out.text.trimRight(), endsWith('END'));
    expect(out.text, isNot(contains('line-0-')));
  });

  test('看最后 N 行', () async {
    final t = await manager.start('c1', 'for i in 1 2 3 4 5 6; do echo row-\$i; done', shell);
    await until(() => !now(t.id).running, '跑完');
    expect(manager.tail(t.id, lines: 2), 'row-5\nrow-6');
    expect(manager.tail(t.id, lines: 100).split('\n'), hasLength(6));
    expect(manager.tail(99), isEmpty);
  });

  test('自己结束：记下退出码和结束时间，并告诉外面（onEnded）', () async {
    final ended = <BackgroundTask>[];
    manager.onEnded = ended.add;
    final ok = await manager.start('c1', 'echo fine', shell);
    final bad = await manager.start('c1', 'echo oops >&2; exit 7', shell);
    await until(() => ended.length == 2, '两个都结束');
    expect(now(ok.id).status, BackgroundStatus.exited);
    expect(now(ok.id).exitCode, 0);
    expect(now(ok.id).endedAt, isNotNull);
    expect(now(bad.id).exitCode, 7);
    expect(logOf(bad), contains('oops'), reason: '错误输出也进日志');
    expect(manager.unnotified('c1').map((t) => t.id), [ok.id, bad.id], reason: '结束了、模型还不知道');
    expect(manager.unnotified('other'), isEmpty);
    manager.setNotified([ok.id]);
    expect(manager.unnotified('c1').map((t) => t.id), [bad.id]);
    manager.setNotified([ok.id], value: false);
    expect(manager.unnotified('c1'), hasLength(2), reason: '可以还回去');
  });

  test('停止：整棵进程树都结束，状态是“已停止”，记下是谁停的', () async {
    final t = await manager.start('c1', r'sh -c "sleep 311 & echo kid:\$!; wait" & echo mid:$!; wait', shell);
    await until(() => RegExp(r'kid:\d+\n').hasMatch(logOf(t)) && RegExp(r'mid:\d+\n').hasMatch(logOf(t)), '进程号');
    final ids = [pidOf(logOf(t), 'mid'), pidOf(logOf(t), 'kid')];
    expect(ids.every(alive), isTrue);
    final after = await manager.stop(t.id, by: StoppedBy.user);
    expect(after!.status, BackgroundStatus.stopped);
    expect(after.stoppedBy, StoppedBy.user);
    expect(after.running, isFalse);
    await expectGone(ids, reason: '停止后 sleep 和中间那层 sh 都不该留下');
    expect(manager.unnotified('c1').single.id, t.id, reason: '用户停的：模型还不知道，要告诉它');
    expect(await manager.stop(t.id, by: StoppedBy.user), isNotNull, reason: '已经停了再停：不出错');
    expect(await manager.stop(99, by: StoppedBy.user), isNull);
  });

  test('模型自己停的：不用再通知它', () async {
    final t = await manager.start('c1', 'sleep 312', shell);
    await manager.stop(t.id, by: StoppedBy.agent);
    expect(now(t.id).stoppedBy, StoppedBy.agent);
    expect(manager.unnotified('c1'), isEmpty);
  });

  test('同时最多 $kMaxBackgroundRunning 个：多的不启动；结束一个后又能启动', () async {
    final started = [for (var i = 0; i < kMaxBackgroundRunning; i++) await manager.start('c$i', 'sleep 313', shell)];
    await expectLater(manager.start('c1', 'echo no > extra.txt', shell), throwsA(isA<BackgroundCommandError>().having((e) => e.message, 'message', contains('上限'))));
    expect(File(p.join(tmp.path, 'extra.txt')).existsSync(), isFalse, reason: '超出上限的那条没有执行');
    expect(manager.tasks, hasLength(kMaxBackgroundRunning));
    await manager.stop(started.first.id, by: StoppedBy.user);
    final next = await manager.start('c1', 'sleep 313', shell);
    expect(next.id, kMaxBackgroundRunning + 1);
  });

  test('工作区关闭（dispose）：全部立刻结束，进程不留；之后不能再启动', () async {
    final t = await manager.start('c1', r'sleep 314 & echo kid:$!; wait', shell);
    await manager.start('c2', 'sleep 314', shell);
    await until(() => RegExp(r'kid:\d+\n').hasMatch(logOf(t)), '进程号');
    final kid = pidOf(logOf(t), 'kid');
    manager.dispose();
    await expectGone([kid], reason: '工作区关闭后后台命令的进程不该留下');
    expect(manager.disposed, isTrue);
    await expectLater(manager.start('c1', 'echo x', shell), throwsA(isA<BackgroundCommandError>()));
    await pendingWrites();
    // 记录里它们是“工作区关闭时停掉的”，下次打开会告诉模型。
    final again = BackgroundCommands(guard);
    await again.load();
    addTearDown(again.dispose);
    expect(again.tasks.map((t) => t.status), everyElement(BackgroundStatus.stopped));
    expect(again.tasks.map((t) => t.stoppedBy), everyElement(StoppedBy.close));
    expect(again.unnotified('c1'), hasLength(1));
  });

  test('应用被杀后重开：上次还在跑的标成“已中断”，残留进程凭记号清掉，不自动重跑', () async {
    // 模拟“应用被杀”：记录文件里有一条 running 的任务，带着记号的进程还活着，但没有人管它了。
    final tag = newCommandTag();
    final orphan = await Process.start('/bin/sh', ['-c', 'exec sleep 315'], environment: {kCommandTagEnv: tag});
    addTearDown(() => orphan.kill(ProcessSignal.sigkill));
    Directory(p.join(tmp.path, '.lopicode', 'outputs')).createSync(recursive: true);
    File(p.join(tmp.path, '.lopicode/outputs/bg-old-3.txt')).writeAsStringSync('old line\n');
    record().writeAsStringSync(
      jsonEncode({
        'version': 1,
        'next': 4,
        'tasks': [
          {'id': 3, 'conv': 'c1', 'command': 'npm run dev', 'startedAt': '2026-11-25T01:00:00.000Z', 'status': 'running', 'log': '.lopicode/outputs/bg-old-3.txt', 'tag': tag, 'bytes': 9},
        ],
      }),
    );
    final again = BackgroundCommands(guard);
    addTearDown(again.dispose);
    await again.load();
    final t = again.byId(3)!;
    expect(t.status, BackgroundStatus.interrupted);
    expect(t.running, isFalse);
    expect(again.runningCount, 0, reason: '没有自动重跑');
    expect(again.unnotified('c1').single.id, 3, reason: '下次发消息时告诉模型');
    expect(again.tail(3), 'old line', reason: '旧日志还能看');
    await orphan.exitCode;
    await expectGone([orphan.pid], reason: '上次留下的进程凭记号清掉');
    final next = await again.start('c1', 'sleep 316', shell);
    expect(next.id, 4, reason: '任务号接着往上数，不和旧的撞');
  });

  group('坏的记录文件不崩', () {
    for (final (name, content) in [
      ('不是 JSON', '{{{ not json'),
      ('空文件', ''),
      ('是数组', '[1,2,3]'),
      ('tasks 不是数组', '{"version":1,"next":"x","tasks":{"a":1}}'),
      ('字段类型不对', '{"version":1,"next":2,"tasks":[{"id":"1","conv":5,"command":null},42,"x",{"id":1,"conv":"c1","command":"ls","startedAt":"不是时间","status":"exited","log":"x","tag":"t"}]}'),
      ('日志路径想跑到工作区外', '{"version":1,"next":2,"tasks":[{"id":1,"conv":"c1","command":"ls","startedAt":"2026-11-25T01:00:00.000Z","status":"exited","log":"../../etc/passwd","tag":"t"}]}'),
      ('状态是没见过的词', '{"version":1,"next":2,"tasks":[{"id":1,"conv":"c1","command":"ls","startedAt":"2026-11-25T01:00:00.000Z","status":"dancing","log":".lopicode/outputs/bg-1-1.txt","tag":"t"}]}'),
    ]) {
      test(name, () async {
        Directory(p.join(tmp.path, '.lopicode')).createSync(recursive: true);
        record().writeAsStringSync(content);
        final again = BackgroundCommands(guard);
        addTearDown(again.dispose);
        await again.load();
        for (final t in again.tasks) {
          expect(t.running, isFalse);
          expect(again.tail(t.id), isEmpty, reason: '读不到工作区外的东西');
          expect(again.readNew(t.id)?.text ?? '', isEmpty);
        }
        final t = await again.start('c1', 'echo still-works', shell);
        await until(() => !(again.byId(t.id)?.running ?? true), '照常能跑');
        expect(again.tail(t.id), 'still-works');
      });
    }
  });

  test('记录存盘：重开后已结束的任务还在（命令、退出码、日志路径）', () async {
    final t = await manager.start('c1', 'echo saved; exit 3', shell);
    await until(() => !now(t.id).running, '跑完');
    manager.setNotified([t.id]);
    await pendingWrites();
    final again = BackgroundCommands(guard);
    addTearDown(again.dispose);
    await again.load();
    final loaded = again.byId(t.id)!;
    expect(loaded.command, 'echo saved; exit 3');
    expect(loaded.exitCode, 3);
    expect(loaded.status, BackgroundStatus.exited);
    expect(loaded.notified, isTrue);
    expect(again.tail(t.id), 'saved');
  });

  test('删掉对话：它的后台命令停掉、记录和日志一起删；别的对话的不动', () async {
    final mine = await manager.start('c1', 'echo a; sleep 317', shell);
    final other = await manager.start('c2', 'sleep 317', shell);
    await until(() => logOf(mine).contains('a'), '输出');
    final log = File(p.join(tmp.path, mine.log));
    await manager.dropConversation('c1');
    expect(manager.byId(mine.id), isNull);
    expect(log.existsSync(), isFalse);
    expect(now(other.id).running, isTrue);
  });

  test('completeUtf8Length：不把一个汉字从中间切开', () {
    final bytes = utf8.encode('ab好');
    expect(completeUtf8Length(bytes), bytes.length);
    expect(completeUtf8Length(bytes.sublist(0, bytes.length - 1)), 2);
    expect(completeUtf8Length(bytes.sublist(0, 3)), 2);
    expect(completeUtf8Length(bytes.sublist(0, 2)), 2);
    expect(completeUtf8Length(const []), 0);
  });
}
