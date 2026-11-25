// 积木第 4 版·第 1 阶段：Agent 的两个后端积木工具读写新积木——说明里列全了新 op / 新表达式，
// 写进去的新积木落盘（版本 2）并生成代码，读出来有中文读法；新规则的错误会拒绝并说清楚。
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/agent/agent_tools.dart';
import 'package:lopicode/backend/backend_agent_tools.dart';
import 'package:lopicode/backend/backend_blocks_lang.dart';
import 'package:lopicode/backend/backend_model.dart';
import 'package:lopicode/core/path_guard.dart';
import 'package:lopicode/core/safe_file.dart';
import 'package:path/path.dart' as p;

import 'agent_test.dart' show RecordingRunner;
import 'support/backend_lang_blocks.dart';
import 'support/backend_lang_blocks_routes.dart';

void main() {
  late Directory tmp;
  late String ws;
  late AgentToolbox box;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('lopi_be_lang_tools_');
    ws = p.join(tmp.path, 'proj');
    Directory(ws).createSync();
    final guard = PathGuard(ws);
    box = AgentToolbox(
      guard: guard,
      runner: RecordingRunner(),
      requestApproval: (r) async => true,
      autoApprove: () => false,
      permission: () => PermissionLevel.workspace,
      planMode: () => false,
      extras: backendTools(guard: guard),
    );
  });
  tearDown(() async {
    await pendingWrites();
    tmp.deleteSync(recursive: true);
  });

  File f(String rel) => File(p.join(ws, rel));
  J docJson(List<J> body) => langBlocksDocumentJson([route('r1', 'GET', '/x', body)]);

  test('工具说明：每个新 op、每种新表达式、每个下拉选项都列到了；总长度没超', () {
    final guide = backendModelGuide();
    for (final op in beLangBlockSpecs.keys) {
      expect(RegExp('(^|[^A-Za-z])$op([^A-Za-z]|\$)', multiLine: true).hasMatch(guide), isTrue, reason: '说明里要有积木 $op');
    }
    for (final e in beLangExprSpecs.entries) {
      expect(guide, contains(e.key), reason: '说明里要有表达式 ${e.key}');
      for (final a in e.value.args) {
        expect(guide, contains(a.name), reason: '${e.key} 的参数 ${a.name}');
        for (final c in a.choices) {
          expect(guide, contains(c), reason: '${e.key} 的选项 $c');
        }
      }
    }
    for (final word in ['arms', 'index', '短路', '版本']) {
      expect(guide, contains(word));
    }
    expect(guide.length, lessThan(6000), reason: '说明每轮都发给模型，不能太长');
  });

  test('写：用了全部新积木的文档 → 通过、落盘是版本 2、生成了代码和语言核心的小库；再读：积木原样、带中文读法', () async {
    final source = langBlocksDocumentJson(langBlocksRoutes());
    final r = await box.execute(kBackendUpdateTool, {'backend': source});
    expect(r.ok, isTrue, reason: r.text);
    await pendingWrites();
    final saved = jsonDecode(f(kBackendFileName).readAsStringSync()) as Map<String, dynamic>;
    expect(saved['version'], 2);
    expect(saved['routes'], source['routes']);
    expect(f('server.js').existsSync(), isTrue);
    expect(f('lc_lang.js').existsSync(), isTrue);
    expect(f('server.js').readAsStringSync(), contains('while ('));

    final got = await box.execute(kBackendGetTool, {});
    expect(got.ok, isTrue);
    for (final word in ['新建变量', '否则如果', '分', '一直重复', '跳出循环', '"op":"forPairs"', '"arms"']) {
      expect(got.text.replaceAll(RegExp(r'\s'), '').contains(word.replaceAll(' ', '')), isTrue, reason: '读出来的内容里要有 $word');
    }
  });

  test('写：新规则的错误（跳出不在循环里、名字重复、改常量、看不见的名字）→ 拒绝并说清哪块、什么原因，磁盘不动', () async {
    final good = docJson([let('a', nm(1)), json(vr('a'))]);
    expect((await box.execute(kBackendUpdateTool, {'backend': good})).ok, isTrue);
    await pendingWrites();
    final before = {for (final e in Directory(ws).listSync(recursive: true).whereType<File>()) e.path: e.readAsStringSync()};
    final bad = <String, List<J>>{
      '要放在循环里面': [blk('break'), json(nm(1))],
      '不能再新建一次': [let('a', nm(1)), let('a', nm(2)), json(nm(1))],
      '是常量': [konst('c', nm(1)), setv('c', nm(2)), json(nm(1))],
      'nope': [json(vr('nope'))],
    };
    for (final e in bad.entries) {
      final r = await box.execute(kBackendUpdateTool, {'backend': docJson(e.value)});
      expect(r.ok, isFalse, reason: e.key);
      expect(r.text, contains('没有保存'));
      expect(r.text, contains(e.key), reason: '要说清是哪块、什么原因：${r.text}');
    }
    await pendingWrites();
    expect({for (final e in Directory(ws).listSync(recursive: true).whereType<File>()) e.path: e.readAsStringSync()}, before);
  });

  test('写：只有警告（可能停不下来、后面的不会执行）→ 照样保存并生成，结果里带上警告', () async {
    final r = await box.execute(kBackendUpdateTool, {
      'backend': docJson([
        blk('forever', {}, [
          blk('break'),
          blk('log', {'value': tx('x')}),
        ]),
        json(nm(1)),
      ]),
    });
    expect(r.ok, isTrue, reason: r.text);
    expect(r.text, contains('提醒（不影响保存）'));
    expect(r.text, contains('从这里往后的不会执行'));
    await pendingWrites();
    expect(f('server.js').existsSync(), isTrue);
  });
}
