// 积木第 4 版·第 2 阶段：Agent 的两个后端积木工具读写“我的积木”——说明里列全了函数相关的 op / 表达式和 functions 的写法；
// 写进去的函数、调用、匿名函数落盘（版本 3）并生成代码，读出来有中文读法；functions 不传就沿用；坏的 functions、新规则的错误会拒绝并说清楚。
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/agent/agent_tools.dart';
import 'package:lopicode/backend/backend_agent_tools.dart';
import 'package:lopicode/backend/backend_blocks_func.dart';
import 'package:lopicode/backend/backend_model.dart';
import 'package:lopicode/core/path_guard.dart';
import 'package:lopicode/core/safe_file.dart';
import 'package:path/path.dart' as p;

import 'agent_test.dart' show RecordingRunner;
import 'support/backend_func_blocks.dart';
import 'support/backend_lang_blocks.dart';

void main() {
  late Directory tmp;
  late String ws;
  late AgentToolbox box;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('lopi_be_func_tools_');
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
  J docJson(List<J> fns, List<J> body) => {
    ...langBlocksDocumentJson([route('r1', 'GET', '/x', body)]),
    'functions': fns,
  };
  Map<String, dynamic> saved() => jsonDecode(f(kBackendFileName).readAsStringSync()) as Map<String, dynamic>;
  Map<String, String> disk() => {for (final e in Directory(ws).listSync(recursive: true).whereType<File>()) e.path: e.readAsStringSync()};

  test('工具说明：函数相关的每个 op、每种表达式、functions 的写法都列到了；总长度没超', () {
    final guide = backendModelGuide();
    expect(guide, contains(backendFuncGuide()));
    for (final op in beFuncBlockSpecs.keys) {
      expect(RegExp('(^|[^A-Za-z])$op([^A-Za-z]|\$)', multiLine: true).hasMatch(guide), isTrue, reason: '说明里要有积木 $op');
    }
    for (final e in beFuncExprSpecs.keys) {
      expect(guide, contains(e), reason: '说明里要有表达式 $e');
    }
    for (final word in ['functions', 'call:', 'look', 'params', 'rest', 'default', '@body', 'template']) {
      expect(guide, contains(word));
    }
    expect(backendFuncGuide().length, lessThan(2600), reason: '说明每轮都发给模型，不能太长');
  });

  test('写：带函数的样本文档 → 通过、落盘是版本 3、functions 原样、生成的代码里函数排在接口前；再读：有“我的积木”的中文读法', () async {
    final source = funcBlocksDocumentJson();
    final r = await box.execute(kBackendUpdateTool, {'backend': source});
    expect(r.ok, isTrue, reason: r.text);
    await pendingWrites();
    expect(saved()['version'], 3);
    expect(saved()['routes'], source['routes']);
    expect([for (final x in saved()['functions'] as List) (x as Map)['id']], [for (final x in source['functions'] as List) (x as Map)['id']]);
    final server = f('server.js').readAsStringSync();
    expect(server.indexOf('f_'), inInclusiveRange(0, server.indexOf('/call')));

    final got = await box.execute(kBackendGetTool, {});
    expect(got.ok, isTrue);
    final flat = got.text.replaceAll(RegExp(r'\s'), '');
    for (final word in ['我的积木“加倍”（idf1，参数：x）', '我的积木“总和”', '其余…（剩下的全收）', '"functions"', '"e":"call:f1"', '"@body"', '匿名函数']) {
      expect(flat.contains(word.replaceAll(' ', '')), isTrue, reason: '读出来的内容里要有 $word：\n${got.text}');
    }
  });

  test('写：functions 不传 → 沿用现有的；传 [] → 删光（还有地方在调用就拒绝）', () async {
    final fns = [
      fnDef('f1', '加倍', [par('x')], [ret(op2('*', pm('x'), nm(2)))]),
    ];
    expect(
      (await box.execute(kBackendUpdateTool, {
        'backend': docJson(fns, [
          json(call('f1', {'x': nm(2)})),
        ]),
      })).ok,
      isTrue,
    );
    await pendingWrites();
    // 不传 functions、接口改一改：函数还在。
    final keep = langBlocksDocumentJson([
      route('r1', 'GET', '/x', [
        json(call('f1', {'x': nm(3)})),
      ]),
    ])..remove('functions');
    final r = await box.execute(kBackendUpdateTool, {'backend': keep});
    expect(r.ok, isTrue, reason: r.text);
    await pendingWrites();
    final kept = (saved()['functions'] as List).single as Map;
    expect(
      {'id': kept['id'], 'params': kept['params'], 'body': kept['body'], 'name': (kept['look'] as Map)['name']},
      {'id': 'f1', 'params': fns.single['params'], 'body': fns.single['body'], 'name': '加倍'},
    );
    // 传 []、接口里还在调用：拒绝，磁盘不动。
    final before = disk();
    final bad = await box.execute(kBackendUpdateTool, {
      'backend': docJson([], [
        json(call('f1', {'x': nm(3)})),
      ]),
    });
    expect(bad.ok, isFalse);
    expect(bad.text, contains('已经不在了'));
    await pendingWrites();
    expect(disk(), before);
    // 传 []、调用也拿掉：删光，回到版本 1。
    final gone = await box.execute(kBackendUpdateTool, {
      'backend': docJson([], [json(nm(1))]),
    });
    expect(gone.ok, isTrue, reason: gone.text);
    await pendingWrites();
    expect(saved().containsKey('functions'), isFalse);
    expect(saved()['version'], 1);
  });

  test('写：functions 不是数组 / 有读不懂的条目 / 参数丢了 / 新规则的错误 → 拒绝并说清原因，磁盘不动', () async {
    expect(
      (await box.execute(kBackendUpdateTool, {
        'backend': docJson([], [json(nm(1))]),
      })).ok,
      isTrue,
    );
    await pendingWrites();
    final before = disk();
    final bad = <String, J>{
      'functions 应为数组': {
        ...docJson([], [json(nm(1))]),
        'functions': {'f1': 1},
      },
      '读不懂': {
        ...docJson([], [callS('f2'), json(nm(1))]),
        'functions': ['不是函数', fnDef('f2', '乙', [], [])],
      },
      '参数': docJson(
        [
          fnDef('f1', '甲', [par('a'), par('a')], [ret(pm('a'))]),
        ],
        [
          json(call('f1', {'a': nm(1)})),
        ],
      ),
      '已经不在了': docJson([], [callS('f9'), json(nm(1))]),
      '只能放在最后一个': docJson(
        [
          fnDef(
            'f1',
            '甲',
            [par('r', rest: true), par('a')],
            [
              ret(cat([pm('a'), pm('r')])),
            ],
          ),
        ],
        [
          json(call('f1', {'a': nm(1)})),
        ],
      ),
      '自定义积木里看不见': docJson(
        [
          fnDef('f1', '甲', [], [ret(vr('total'))]),
        ],
        [json(call('f1'))],
      ),
      '不能放在自定义积木里': docJson(
        [
          fnDef('f1', '甲', [], [json(nm(1))]),
        ],
        [callS('f1'), json(nm(1))],
      ),
    };
    for (final e in bad.entries) {
      final r = await box.execute(kBackendUpdateTool, {'backend': e.value});
      expect(r.ok, isFalse, reason: e.key);
      expect(r.text, contains('没有保存'));
      expect(r.text, contains(e.key), reason: '要说清是哪块、什么原因：${r.text}');
    }
    await pendingWrites();
    expect(disk(), before);
  });

  test('写：只有警告（没人用的积木、没用到的参数、把不交回结果的积木当值用）→ 照样保存并生成，结果里带上警告', () async {
    final r = await box.execute(kBackendUpdateTool, {
      'backend': docJson(
        [
          fnDef(
            'f1',
            '甲',
            [par('a')],
            [
              blk('log', {'value': nm(1)}),
            ],
          ),
          fnDef('f2', '乙', [], []),
        ],
        [
          json(call('f1', {'a': nm(1)})),
        ],
      ),
    });
    expect(r.ok, isTrue, reason: r.text);
    expect(r.text, contains('提醒（不影响保存）'));
    for (final word in ['定义了但没有人用', '参数 a 没有用到', '不交回结果']) {
      expect(r.text, contains(word));
    }
    await pendingWrites();
    expect(f('server.js').existsSync(), isTrue);
  });
}
