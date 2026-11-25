// 所有工具的超长结果都存文件（2026-11-25）：全文进 `.lopicode/outputs/tool-….txt`，回给模型的是头尾 + 路径 + 怎么接着看；
// 读转存文件本身不再套一层；清理上限和命令输出共用、不碰后台命令的日志；存不了退回只留头尾。不带界面、不联网。
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/agent/agent_runner.dart';
import 'package:lopicode/agent/agent_tools.dart';
import 'package:lopicode/agent/chat_client.dart';
import 'package:lopicode/agent/command_output_store.dart';
import 'package:lopicode/agent/loop_guard.dart';
import 'package:lopicode/agent/tool_output_spill.dart';
import 'package:lopicode/core/path_guard.dart';
import 'package:lopicode/core/safe_file.dart';
import 'package:path/path.dart' as p;

import 'agent_test.dart' show RecordingRunner;
import 'support/harness.dart';

void main() {
  late Directory tmp;
  late PathGuard guard;
  late String root;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('lopi_spill_');
    root = p.join(tmp.path, 'proj');
    Directory(root).createSync();
    guard = PathGuard(root);
  });
  tearDown(() async {
    await pendingWrites();
    tmp.deleteSync(recursive: true);
  });

  Directory outputs() => Directory(p.join(root, '.lopicode', 'outputs'));
  List<String> saved() => outputs().existsSync() ? ([for (final f in outputs().listSync()) p.basename(f.path)]..sort()) : [];

  /// 2000 行、约 4.9 万字符的结果：每行都认得出是第几行。
  String longText() => [for (var i = 1; i <= 2000; i++) '第 $i 行 ${'数据' * 9}'].join('\n');

  group('spillLongResult', () {
    test('不超过上限：原样返回，不存文件', () async {
      final exact = ToolOutcome('x' * kMaxToolResultChars);
      final out = await spillLongResult(guard, 'web_search', const {}, exact);
      expect(identical(out, exact), isTrue);
      expect(saved(), isEmpty);
    });

    test('超过上限：全文原样存成 tool-….txt；回给模型头 16000 + 尾 8000 + 相对路径 + 两种接着看的办法；其余字段不变', () async {
      final text = longText();
      expect(text.length, greaterThan(kMaxToolResultChars));
      final out = await spillLongResult(guard, 'web_search', const {'query': 'x'}, ToolOutcome(text, changedFiles: true));
      expect(saved().single, matches(RegExp(r'^tool-\d{14}-[0-9a-z]+\.txt$')));
      final rel = spilledOutputPathOf(out.text)!;
      expect(rel, '.lopicode/outputs/${saved().single}');
      expect(File(p.join(root, rel)).readAsStringSync(), text, reason: '全文一字不差，没有加抬头（行号和结果里的一致）');
      expect(kToolSpillHeadChars + kToolSpillTailChars, kMaxToolResultChars);
      expect(out.text, startsWith(text.substring(0, kToolSpillHeadChars)));
      expect(out.text, endsWith(text.substring(text.length - kToolSpillTailChars)));
      expect(out.text, contains('中间省略了 ${text.length - kMaxToolResultChars} 字符'));
      expect(out.text, contains('共 ${text.length} 字符、2000 行'));
      expect(out.text, contains('read_file'));
      expect(out.text, contains('start_line / end_line'));
      expect(out.text, contains('grep -n "关键词" $rel'), reason: '命令在项目目录里执行，写相对路径在默认项目（/workspace）和 Linux 项目里都对');
      expect(out.text, isNot(contains('/workspace/')));
      expect(out.text.length, lessThan(kMaxToolResultChars + 400));
      expect(out.ok, isTrue);
      expect(out.changedFiles, isTrue);
    });

    test('失败的结果超长也一样存（ok 还是 false）', () async {
      final out = await spillLongResult(guard, 'mcp_tool', const {}, ToolOutcome('错误：${'e' * 30000}', ok: false));
      expect(out.ok, isFalse);
      expect(spilledOutputPathOf(out.text), isNotNull);
    });

    test('模型照提示接着看：read_file 带行号读转存文件能读到被省略的中间部分', () async {
      final text = longText();
      final out = await spillLongResult(guard, 'web_search', const {}, ToolOutcome(text));
      final rel = spilledOutputPathOf(out.text)!;
      expect(out.text, isNot(contains('第 1000 行 ')), reason: '中间那段被省略了');
      final box = AgentToolbox(guard: guard, runner: RecordingRunner(), requestApproval: (_) async => true, autoApprove: () => false);
      final part = await box.execute('read_file', {'path': rel, 'start_line': 1000, 'end_line': 1001});
      expect(part.ok, isTrue);
      expect(part.text, contains('第 1000 行 '));
      expect(part.text, contains('全文共 2000 行'));
      // 转存目录仍然只读：写和删都不行。
      expect((await box.execute('write_file', {'path': rel, 'content': 'x'})).ok, isFalse);
      expect((await box.execute('delete_file', {'path': rel})).ok, isFalse);
      expect(File(p.join(root, rel)).readAsStringSync(), text);
    });

    test('read_file 读转存目录里的文件（tool- / cmd- / 后台日志 bg-）超长：不再另存一份，只截头尾并提醒分段读', () async {
      outputs().createSync(recursive: true);
      for (final name in ['tool-20261125000000-0.txt', 'cmd-20261125000000-1.txt', 'bg-20261125000000-ab12.txt']) {
        File(p.join(outputs().path, name)).writeAsStringSync('x');
      }
      final before = saved();
      for (final name in before) {
        final out = await spillLongResult(guard, 'read_file', {'path': '.lopicode/outputs/$name'}, ToolOutcome(longText()));
        expect(saved(), before, reason: '$name：没有生出新文件');
        expect(out.text, contains('不会再另存一份'));
        expect(out.text, contains('start_line / end_line'));
        expect(out.text, contains('中间省略'));
        expect(out.text.length, lessThan(kMaxToolResultChars + 400));
      }
      // 写法不同但指的是同一个文件，也认得出来。
      await spillLongResult(guard, 'read_file', {'path': './.lopicode/outputs/../outputs/${before.first}'}, ToolOutcome(longText()));
      expect(saved(), before);
      // 读普通文件超长照常转存；别的工具带着 path 参数也照常转存。
      await spillLongResult(guard, 'read_file', {'path': 'big.txt'}, ToolOutcome(longText()));
      expect(saved().length, before.length + 1);
      await spillLongResult(guard, 'other_tool', {'path': '.lopicode/outputs/${before.first}'}, ToolOutcome(longText()));
      expect(saved().length, before.length + 2);
      // 路径越界、参数类型不对：当普通结果处理，不抛错。
      await spillLongResult(guard, 'read_file', {'path': '../../etc/passwd'}, ToolOutcome(longText()));
      await spillLongResult(guard, 'read_file', {'path': 42}, ToolOutcome(longText()));
      expect(saved().length, before.length + 4);
    });

    test('存不了（转存目录的位置被一个文件占着）：退回只留头尾，结果照样给', () async {
      Directory(p.join(root, '.lopicode')).createSync();
      File(p.join(root, '.lopicode', 'outputs')).writeAsStringSync('占位');
      final text = longText();
      final out = await spillLongResult(guard, 'web_search', const {}, ToolOutcome(text));
      expect(out.text, clipToolResult(text));
      expect(spilledOutputPathOf(out.text), isNull);
    });
  });

  group('清理（命令输出和别的工具结果共用上限，不碰后台日志）', () {
    test('合起来只留最近 20 份；bg- 和不认识的文件不动；同一秒里按序号的数值排（36 进制）', () async {
      outputs().createSync(recursive: true);
      File at(String name) => File(p.join(outputs().path, name));
      // 同一秒里 40 份（序号 0–39，36 进制是 0…z、10…13），cmd 和 tool 交替；外加更早的两份。
      for (var i = 0; i < 40; i++) {
        at('${i.isEven ? 'cmd' : 'tool'}-20261125010101-${i.toRadixString(36)}.txt').writeAsStringSync('n$i');
      }
      at('cmd-20261124010101-zz.txt').writeAsStringSync('old');
      at('tool-20261124010101-zz.txt').writeAsStringSync('old');
      for (var i = 0; i < 25; i++) {
        at('bg-20261120010101-t$i.txt').writeAsStringSync('bg');
      }
      at('notes.txt').writeAsStringSync('别的文件');
      await CommandOutputStore(guard).cleanup();
      final left = saved();
      expect(left.where((n) => n.startsWith('bg-')).length, 25, reason: '后台日志有自己的规矩，这里一份都不删');
      expect(left, contains('notes.txt'));
      final kept = left.where((n) => n.startsWith('cmd-') || n.startsWith('tool-')).toList();
      expect(kept.length, kKeepOutputFiles);
      final seqs = [for (final n in kept) int.parse(RegExp(r'-([0-9a-z]+)\.txt$').firstMatch(n)!.group(1)!, radix: 36)]..sort();
      expect(seqs, [for (var i = 20; i < 40; i++) i], reason: '留下的是序号最大的 20 份（按字面排会把 z 排在 10 后面）');
    });

    test('存一份新的会顺手清理：tool- 和 cmd- 混着存到 25 份，只剩 20 份，最新的在', () async {
      final store = CommandOutputStore(guard);
      String? last;
      for (var i = 0; i < 25; i++) {
        last = i.isEven ? await store.saveToolResult('t$i') : await store.save('echo $i', 'c$i');
      }
      expect(saved().length, kKeepOutputFiles);
      expect(await store.read(last!), 't24');
    });

    test('合计超过 20 MB 从最旧的删；最新的一份再大也留着', () async {
      final store = CommandOutputStore(guard);
      final chunk = 'x' * (7 * 1024 * 1024);
      final a = await store.saveToolResult(chunk);
      final b = await store.saveToolResult(chunk);
      final c = await store.saveToolResult(chunk);
      expect(await store.read(a!), isNull, reason: '三份 21 MB：最旧的删掉');
      expect(await store.read(b!), isNotNull);
      expect(await store.read(c!), isNotNull);
    });

    test('认路径：结果文字里的 tool- / cmd- 路径都认；bg- 的不当成“这一步的完整输出”；读不存在的返回 null 不抛错', () async {
      expect(spilledOutputPathOf('…已存到 .lopicode/outputs/tool-20261125010101-a.txt。'), '.lopicode/outputs/tool-20261125010101-a.txt');
      expect(spilledOutputPathOf('…已存到 .lopicode/outputs/cmd-20261125010101-a.txt。'), '.lopicode/outputs/cmd-20261125010101-a.txt');
      expect(spilledOutputPathOf('日志在 .lopicode/outputs/bg-20261125010101-a.txt'), isNull);
      expect(spilledOutputPathOf('没有路径'), isNull);
      expect(spilledOutputPathOf(null), isNull);
      final store = CommandOutputStore(guard);
      expect(await store.read('.lopicode/outputs/tool-20261125010101-a.txt'), isNull);
      expect(await store.read('../outside.txt'), isNull);
    });
  });

  group('经 AgentRunner', () {
    test('模型看到的工具结果就是头尾 + 路径；全文原样在 tool- 文件里；给用户的提示里不带文件内容', () async {
      final shell = RecordingRunner();
      const secretish = '仅测试用的一段要紧内容';
      final text = '$secretish\n${longText()}';
      final tool = ExtraTool(spec: toolSpec('fetch', '取一大段内容', {}), kind: ToolKind.read, run: (_) async => ToolOutcome(text));
      final client = ScriptedChatClient([
        [call(0, 'fetch', '{}'), ChatDelta(finishReason: 'tool_calls')],
        [say('好。'), ChatDelta(finishReason: 'stop')],
      ]);
      final runner = AgentRunner(
        client: client,
        toolbox: AgentToolbox(guard: guard, runner: shell, requestApproval: (_) async => true, autoApprove: () => false, extras: [tool]),
      );
      final events = await runner.send('取').toList();
      expect(events.whereType<ToolFinished>().length, 1);
      final result = '${runner.messages.lastWhere((m) => m['role'] == 'tool')['content']}';
      final rel = spilledOutputPathOf(result)!;
      expect(p.basename(rel), startsWith('tool-'));
      expect(File(p.join(root, rel)).readAsStringSync(), text, reason: '存之前不做额外处理（和命令输出一致）');
      expect(events.whereType<ToolFinished>().single.outcome.text, result);
      // 给用户看的提示里不带文件内容。
      expect(jsonEncode([for (final e in events.whereType<AgentNotice>()) e.text]), isNot(contains(secretish)));
    });
  });
}
