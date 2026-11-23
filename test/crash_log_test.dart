// 错误日志：抹掉密钥、写文件、轮换、清空；模型接口的超时。
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lopicode/agent/chat_client.dart';
import 'package:lopicode/core/crash_log.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tmp;
  final log = CrashLog.instance;
  setUp(() {
    tmp = Directory.systemTemp.createTempSync('lopi_log_');
    log.resetForTest();
  });
  tearDown(() async {
    await log.flush();
    log.resetForTest();
    tmp.deleteSync(recursive: true);
  });

  test('像密钥的东西都被抹掉', () {
    const secrets = [
      'sk-abcdef1234567890abcdef',
      'ghp_abcdefghijklmnopqrstuvwxyz0123456789',
      'github_pat_11ABCDEFG0abcdefghijkl_mnopqrstuvwxyz',
      'tvly-abcdefghijklmnop',
      'AIzaSyA1234567890abcdefghijklmnopqrstu',
      'my-plain-password-1',
    ];
    final text = [
      'Authorization: Bearer ${secrets[0]}',
      'headers: {x-api-key: ${secrets[0]}}',
      'token ${secrets[1]} rejected',
      'using ${secrets[2]}',
      'search key ${secrets[3]}',
      'url https://x.example.com/v1?key=${secrets[4]}',
      '{"apiKey":"${secrets[0]}","password":"${secrets[5]}"}',
      'ssh://root:${secrets[5]}@82.0.0.1:22',
      'api_key=${secrets[0]}&x=1',
    ].join('\n');
    final out = redactSecrets(text);
    for (final s in secrets) {
      expect(out, isNot(contains(s)), reason: '漏了：$s\n$out');
    }
    // 不是密钥的内容留着
    expect(out, contains('x.example.com'));
    expect(out, contains('82.0.0.1'));
    expect(redactSecrets('普通的一句话，没有密钥'), '普通的一句话，没有密钥');
  });

  test('记录：进内存、写文件、带来源和堆栈；密钥不落盘', () async {
    log.attach(Directory(p.join(tmp.path, 'logs')));
    log.record(StateError('炸了 Bearer sk-secretsecret123456'), StackTrace.current, source: '界面');
    await log.flush();
    expect(log.entries, hasLength(1));
    expect(log.entries.single.source, '界面');
    final text = File(p.join(tmp.path, 'logs', 'errors.log')).readAsStringSync();
    expect(text, contains('炸了'));
    expect(text, contains('界面'));
    expect(text, contains('crash_log_test.dart'));
    expect(text, isNot(contains('sk-secretsecret123456')));
    expect(log.export(), isNot(contains('sk-secretsecret123456')));
    expect(await log.readAll(), contains('炸了'));
  });

  test('没指定目录也能记（只进内存），不抛异常', () async {
    log.record(Exception('x'), null);
    log.note('存盘文件坏了');
    await log.flush();
    expect(log.entries, hasLength(2));
    expect(log.entries.last.fatal, isFalse);
    expect(await log.readAll(), contains('存盘文件坏了'));
  });

  test('目录写不了：照样记进内存，不抛异常', () async {
    final blocker = File(p.join(tmp.path, 'logs'))..writeAsStringSync('我是个文件，不是目录');
    log.attach(Directory(blocker.path));
    log.record(Exception('磁盘写不了'), StackTrace.current);
    await log.flush();
    expect(log.entries.single.message, contains('磁盘写不了'));
  });

  test('内存里最多留 ${CrashLog.maxEntries} 条；堆栈太长会截断', () {
    for (var i = 0; i < CrashLog.maxEntries + 20; i++) {
      log.record(Exception('第 $i 个'), null);
    }
    expect(log.entries.length, CrashLog.maxEntries);
    expect(log.entries.last.message, contains('第 ${CrashLog.maxEntries + 19} 个'));
    log.record(Exception('长堆栈'), StackTrace.fromString(List.generate(200, (i) => '#$i frame').join('\n')));
    expect(log.entries.last.stack.split('\n').length, CrashLog.maxStackLines + 1);
    expect(log.entries.last.stack, contains('共 200 行'));
  });

  test('日志文件太大就轮换（旧的留一份 .1）；清空会把两份都删掉', () async {
    final dir = Directory(p.join(tmp.path, 'logs'))..createSync();
    final file = File(p.join(dir.path, 'errors.log'))..writeAsStringSync('旧' * (CrashLog.maxFileBytes));
    log.attach(dir);
    log.record(Exception('新的一条'), null);
    await log.flush();
    expect(File('${file.path}.1').existsSync(), isTrue);
    expect(file.readAsStringSync(), contains('新的一条'));
    expect(file.lengthSync(), lessThan(2000));
    await log.clear();
    expect(file.existsSync(), isFalse);
    expect(File('${file.path}.1').existsSync(), isFalse);
    expect(log.entries, isEmpty);
    expect((await log.readAll()).trim(), isEmpty);
  });

  test('每记一条发一次通知', () async {
    final got = <CrashEntry>[];
    final sub = log.changes.listen(got.add);
    log.record(Exception('a'), null);
    log.note('b');
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();
    expect(got.map((e) => e.fatal), [true, false]);
  });

  group('模型接口的超时', () {
    test('一直不回响应头 → 报“没有响应”，不会永远等下去', () async {
      final never = Completer<http.StreamedResponse>();
      final client = _FnClient((_) => never.future);
      final request = http.Request('POST', Uri.parse('https://api.example.com/v1/chat/completions'));
      await expectLater(
        sendChatRequest(client, request, timeout: const Duration(milliseconds: 50)),
        throwsA(isA<ChatApiException>().having((e) => e.message, 'message', allOf(contains('api.example.com'), contains('没有响应')))),
      );
    });

    test('连不上 → 报“连不上”，只带主机名，不带 Key', () async {
      final client = MockClient((_) async => throw const SocketException('Connection refused'));
      final request = http.Request('POST', Uri.parse('https://api.example.com/v1/chat/completions'))..headers['Authorization'] = 'Bearer sk-supersecret12345';
      await expectLater(
        sendChatRequest(client, request),
        throwsA(isA<ChatApiException>().having((e) => e.message, 'message', allOf(contains('api.example.com'), isNot(contains('sk-supersecret12345'))))),
      );
    });

    test('流到一半卡住 → 前面的内容照常给，然后报“没有新内容”', () async {
      final controller = StreamController<List<int>>();
      addTearDown(controller.close);
      controller.add([1, 2, 3]);
      final got = <List<int>>[];
      Object? error;
      final done = Completer<void>();
      guardChatStream(controller.stream, 'api.example.com', stall: const Duration(milliseconds: 60)).listen(got.add, onError: (Object e) => error = e, onDone: done.complete);
      await done.future;
      expect(got, [
        [1, 2, 3],
      ]);
      expect(error, isA<ChatApiException>().having((e) => e.message, 'message', contains('没有新内容')));
    });

    test('流到一半断线 → 报“连接中断”', () async {
      final controller = StreamController<List<int>>();
      controller
        ..add([1])
        ..addError(const SocketException('Connection reset by peer'));
      unawaited(controller.close());
      Object? error;
      final done = Completer<void>();
      guardChatStream(controller.stream, 'api.example.com').listen((_) {}, onError: (Object e) => error = e, onDone: done.complete);
      await done.future;
      expect(error, isA<ChatApiException>().having((e) => e.message, 'message', contains('中断')));
    });
  });
}

class _FnClient extends http.BaseClient {
  _FnClient(this.fn);
  final Future<http.StreamedResponse> Function(http.BaseRequest request) fn;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) => fn(request);
}
