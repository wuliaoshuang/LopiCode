// Agent 的两个后端积木工具：读（内容 + 读法 + 校验）、改（校验通过才落盘并重新生成代码）。
// 权限档位 / 计划模式 / 预设开关 / 写入范围都要管得住。
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/agent/agent_tools.dart';
import 'package:lopicode/agent/presets.dart';
import 'package:lopicode/backend/backend_agent_tools.dart';
import 'package:lopicode/backend/backend_model.dart';
import 'package:lopicode/backend/backend_project.dart';
import 'package:lopicode/backend/backend_targets.dart';
import 'package:lopicode/backend/backend_templates.dart';
import 'package:lopicode/core/path_guard.dart';
import 'package:lopicode/core/safe_file.dart';
import 'package:path/path.dart' as p;

import 'agent_test.dart' show RecordingRunner;

void main() {
  late Directory tmp;
  late String ws;
  late PathGuard guard;
  late RecordingRunner shell;
  late List<ApprovalRequest> asked;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('lopi_be_tools_');
    ws = p.join(tmp.path, 'proj');
    Directory(ws).createSync();
    File(p.join(tmp.path, 'outside.txt')).writeAsStringSync('原样');
    guard = PathGuard(ws);
    shell = RecordingRunner();
    asked = [];
  });
  tearDown(() async {
    await pendingWrites();
    tmp.deleteSync(recursive: true);
  });

  AgentToolbox box({PermissionLevel level = PermissionLevel.workspace, bool plan = false, Set<String>? allowed, List<String>? scope}) => AgentToolbox(
    guard: guard,
    runner: shell,
    requestApproval: (r) async {
      asked.add(r);
      return true;
    },
    autoApprove: () => false,
    permission: () => level,
    planMode: () => plan,
    allowedTools: allowed,
    writeScope: scope,
    extras: backendTools(guard: guard, writeScope: scope),
  );

  List<String> names(AgentToolbox b) => [for (final s in b.specs) (s['function'] as Map)['name'] as String];
  File f(String rel) => File(p.join(ws, rel));
  void put(String rel, String content) => f(rel)
    ..createSync(recursive: true)
    ..writeAsStringSync(content);
  Map<String, String> snapshot() => {
    for (final e in Directory(ws).listSync(recursive: true).whereType<File>())
      if (!p.relative(e.path, from: ws).startsWith(PathGuard.reservedDir)) p.relative(e.path, from: ws): e.readAsStringSync(),
  };
  Map<String, dynamic> starter([String language = 'node']) => backendStarterDocument('样本', language: language).toJson();

  group('工具定义', () {
    test('两个工具：读是只读类，改是写类；说明里写清模型结构', () {
      final tools = backendTools(guard: guard);
      expect([for (final t in tools) (t.name, t.kind)], [(kBackendGetTool, ToolKind.read), (kBackendUpdateTool, ToolKind.write)]);
      final update = ((tools[1].spec['function'] as Map)['description'] as String);
      for (final word in ['routes', 'method', 'path', 'respondJson', 'pathParam', 'bodyField', 'dbInsert', 'collections', 'language']) {
        expect(update, contains(word), reason: '改工具的说明里要讲到 $word');
      }
      for (final t in backendTargets) {
        expect(update, contains(t.id), reason: '说明里要列出可选语言 ${t.id}');
      }
      expect(((tools[1].spec['function'] as Map)['parameters'] as Map)['required'], ['backend']);
      expect(update.length, lessThan(6000), reason: '说明每轮都发给模型，不能太长');
      // 设置页的工具开关里有这两个
      expect(kToolLabels.keys, containsAll([kBackendGetTool, kBackendUpdateTool]));
    });

    test('说明里举的积木例子本身是对的：照它写一份能过校验', () async {
      final guide = backendModelGuide();
      final examples = RegExp(r'例：(\{.*\})$', multiLine: true).allMatches(guide).map((m) => m[1]!).toList();
      expect(examples, isNotEmpty, reason: '说明里要有一个完整的例子');
      for (final e in examples) {
        // 例子是一块积木：放进一个接口里，配上它用到的集合
        final r = await box().execute(kBackendUpdateTool, {
          'backend': {
            'collections': [
              {'name': 'todos'},
            ],
            'routes': [
              {
                'method': 'GET',
                'path': '/todos',
                'body': [jsonDecode(e)],
              },
            ],
          },
        });
        expect(r.ok, isTrue, reason: '${r.text}\n$e');
      }
    });
  });

  group('权限', () {
    test('仅可查看 / 计划模式：读工具在，改工具不给模型，硬调用被拒绝，磁盘不动', () async {
      put(kBackendFileName, jsonEncode(starter()));
      final before = snapshot();
      for (final b in [box(level: PermissionLevel.view), box(plan: true)]) {
        expect(names(b), contains(kBackendGetTool));
        expect(names(b), isNot(contains(kBackendUpdateTool)));
        final r = await b.execute(kBackendUpdateTool, {'backend': starter('python')});
        expect((r.ok, r.denied), (false, true));
        expect((await b.execute(kBackendGetTool, {})).ok, isTrue);
      }
      expect(snapshot(), before);
      expect(asked, isEmpty);
    });

    test('工作区内修改 / 完全权限：两个都在，改不弹确认卡（和 write_file 一样）', () async {
      for (final level in [PermissionLevel.workspace, PermissionLevel.full]) {
        final b = box(level: level);
        expect(names(b), containsAll([kBackendGetTool, kBackendUpdateTool]));
        expect((await b.execute(kBackendUpdateTool, {'backend': starter()})).ok, isTrue);
      }
      expect(asked, isEmpty);
    });

    test('预设没勾的工具不给', () async {
      final b = box(allowed: {'read_file', kBackendGetTool});
      expect(names(b), contains(kBackendGetTool));
      expect(names(b), isNot(contains(kBackendUpdateTool)));
      expect((await b.execute(kBackendUpdateTool, {'backend': starter()})).ok, isFalse);
      expect(snapshot(), isEmpty);
    });

    test('写入范围：范围外不写（连生成的代码文件也算），范围内可以', () async {
      final outside = await box(scope: ['web/']).execute(kBackendUpdateTool, {'backend': starter()});
      expect(outside.ok, isFalse);
      expect(outside.text, contains('不在范围内'));
      expect(snapshot(), isEmpty);
      // 只放开了积木文件本身：生成的代码写不进去，所以整个不做
      final partial = await box(scope: [kBackendFileName]).execute(kBackendUpdateTool, {'backend': starter()});
      expect(partial.ok, isFalse);
      expect(snapshot(), isEmpty);
      final inside = await box(scope: ['server']).execute(kBackendUpdateTool, {'backend': starter(), 'path': 'server/$kBackendFileName'});
      expect(inside.ok, isTrue, reason: inside.text);
      expect(snapshot().keys, everyElement(startsWith('server/')));
    });
  });

  group('读', () {
    test('返回文件名、JSON、中文读法、校验结果', () async {
      put(kBackendFileName, jsonEncode(starter()));
      final r = await box().execute(kBackendGetTool, {});
      expect(r.ok, isTrue);
      expect(r.changedFiles, isFalse);
      expect(r.text, contains('文件：$kBackendFileName'));
      expect(r.text, contains('"kind": "backend"'));
      expect(r.text, contains('—— 读法 ——'));
      expect(r.text, contains('GET /hello'));
      expect(r.text, contains('DELETE /todos/:id'));
      expect(r.text, contains('todos'));
      expect(r.text, contains('校验：没有问题。'));
    });

    test('自动找：根目录没有就找 server/；也可以指定路径', () async {
      put('server/$kBackendFileName', jsonEncode(starter('python')));
      expect((await box().execute(kBackendGetTool, {})).text, contains('文件：server/$kBackendFileName'));
      expect((await box().execute(kBackendGetTool, {'path': 'server/$kBackendFileName'})).ok, isTrue);
      expect((await box().execute(kBackendGetTool, {'path': '  '})).ok, isTrue);
    });

    test('有问题的文档：错误和提醒都列出来', () async {
      final doc = backendStarterDocument('样本')..addRoute('GET', '/hello');
      put(kBackendFileName, doc.encode());
      final r = await box().execute(kBackendGetTool, {});
      expect(r.ok, isTrue);
      expect(r.text, contains('处错误'));
      expect(r.text, contains('错误：'));
    });

    test('读不了的情况都说明原因，不崩：没有文件、坏 JSON、别的 kind、路径越界、名字不对', () async {
      expect((await box().execute(kBackendGetTool, {})).text, contains('没有 $kBackendFileName'));
      expect((await box().execute(kBackendGetTool, {'path': 'server/$kBackendFileName'})).text, contains('不存在'));
      put(kBackendFileName, '{ 坏的');
      expect((await box().execute(kBackendGetTool, {})).text, contains('不是合法的 JSON'));
      put(kBackendFileName, '{"kind":"page"}');
      expect((await box().execute(kBackendGetTool, {})).text, contains('不是后端积木文件'));
      put(kBackendFileName, '[]');
      expect((await box().execute(kBackendGetTool, {})).ok, isFalse);
      for (final bad in ['../outside.txt', '/etc/passwd', 'README.md', '${PathGuard.reservedDir}/$kBackendFileName', 42]) {
        final r = await box().execute(kBackendGetTool, {'path': bad});
        expect(r.ok, isFalse, reason: '$bad');
        expect(r.text, isNot(contains('原样')));
      }
    });
  });

  group('改', () {
    test('新建：根目录写下文档并生成代码；返回里有启动命令', () async {
      final r = await box().execute(kBackendUpdateTool, {'backend': starter()});
      expect(r.ok, isTrue, reason: r.text);
      expect(r.changedFiles, isTrue);
      final node = backendTargetFor('node')!;
      expect(r.text, contains('已保存 $kBackendFileName'));
      expect(r.text, contains(node.label));
      expect(r.text, contains('启动命令（在项目目录里）：${node.startCommand.join(' ')}'));
      final saved = BeDocument.parse(f(kBackendFileName).readAsStringSync());
      expect(saved.note, isNull);
      expect(saved.doc.encode(), backendStarterDocument('样本', language: 'node').encode());
      expect(snapshot().keys.toSet(), {kBackendFileName, ...backendProjectFiles(saved.doc)!.files.keys});
      expect(f(kBackendFileName).readAsStringSync().endsWith('\n'), isTrue);
    });

    test('backend 也可以是 JSON 字符串（模型常这么传）', () async {
      final r = await box().execute(kBackendUpdateTool, {'backend': jsonEncode(starter())});
      expect(r.ok, isTrue, reason: r.text);
      expect((await box().execute(kBackendUpdateTool, {'backend': '{ 坏的'})).text, contains('不是合法 JSON'));
    });

    test('只给 routes：name / port / language / 变量 / 集合沿用现有文件的', () async {
      final base = backendStarterDocument('我的接口', language: 'python', port: 9100);
      put('server/$kBackendFileName', base.encode());
      final r = await box().execute(kBackendUpdateTool, {
        'backend': {
          'routes': [
            {
              'method': 'GET',
              'path': '/only',
              'body': [
                {
                  'op': 'respondJson',
                  'args': {
                    'status': {'e': 'num', 'v': 200},
                    'value': {'e': 'dbAll', 'collection': 'todos'},
                  },
                },
              ],
            },
          ],
        },
      });
      expect(r.ok, isTrue, reason: r.text);
      expect(r.text, contains('已保存 server/$kBackendFileName'));
      final saved = BeDocument.parse(f('server/$kBackendFileName').readAsStringSync()).doc;
      expect((saved.name, saved.port, saved.language), ('我的接口', 9100, 'python'));
      expect([for (final c in saved.collections) c.name], ['todos']);
      expect([for (final x in saved.routes) x.path], ['/only']);
      expect(f('server/${backendTargetFor('python')!.entryFile}').readAsStringSync(), contains('/only'));
      expect(r.text, contains('cd server && '));
    });

    test('换语言：新语言的代码生成出来，旧语言没动过的文件清掉', () async {
      await box().execute(kBackendUpdateTool, {'backend': starter('node')});
      final r = await box().execute(kBackendUpdateTool, {
        'backend': {...starter('node'), 'language': 'python'},
      });
      expect(r.ok, isTrue, reason: r.text);
      expect(r.text, contains('清掉旧文件'));
      expect(snapshot().keys.toSet(), {kBackendFileName, ...backendProjectFiles(backendStarterDocument('样本', language: 'python'))!.files.keys});
    });

    test('手改过的代码文件不覆盖：文档照存，返回里说明哪个文件没动', () async {
      await box().execute(kBackendUpdateTool, {'backend': starter()});
      final entry = backendTargetFor('node')!.entryFile;
      f(entry).writeAsStringSync('// 我改的\n');
      final next = starter();
      (next['routes'] as List).removeLast();
      final r = await box().execute(kBackendUpdateTool, {'backend': next});
      expect(r.ok, isTrue);
      expect(r.text, contains('没有动'));
      expect(r.text, contains(entry));
      expect(f(entry).readAsStringSync(), '// 我改的\n');
      expect(BeDocument.parse(f(kBackendFileName).readAsStringSync()).doc.routes.length, 6);
    });

    test('有错误就拒绝，列出问题，什么都不改', () async {
      await box().execute(kBackendUpdateTool, {'backend': starter()});
      final before = snapshot();
      final dup = starter();
      (dup['routes'] as List).add({'method': 'GET', 'path': '/hello', 'body': <Object>[]});
      final cases = <String, Object?>{
        '接口重复': dup,
        '端口不对': {...starter(), 'port': 70000},
        '端口不是整数': {...starter(), 'port': '8080'},
        '语言没有生成器': {...starter(), 'language': 'cobol'},
        '语言不是文字': {...starter(), 'language': 3},
        '路径不对': {
          ...starter(),
          'routes': [
            {'method': 'GET', 'path': 'no-slash', 'body': <Object>[]},
          ],
        },
        '用了没有的集合': {
          ...starter(),
          'routes': [
            {
              'method': 'GET',
              'path': '/x',
              'body': [
                {
                  'op': 'respondJson',
                  'args': {
                    'status': {'e': 'num', 'v': 200},
                    'value': {'e': 'dbAll', 'collection': '没有这个集合'},
                  },
                },
              ],
            },
          ],
        },
        '积木格式不对（会被悄悄丢掉的）': {
          ...starter(),
          'routes': [
            {
              'method': 'GET',
              'path': '/x',
              'body': [
                '不是积木',
                {'没有 op': 1},
              ],
            },
          ],
        },
        '接口不是对象': {
          ...starter(),
          'routes': ['不是接口'],
        },
      };
      for (final c in cases.entries) {
        final r = await box().execute(kBackendUpdateTool, {'backend': c.value});
        expect(r.ok, isFalse, reason: '${c.key}：${r.text}');
        expect(r.text, contains('没有保存'), reason: c.key);
        expect(r.changedFiles, isFalse);
        expect(snapshot(), before, reason: '${c.key} 之后磁盘变了');
      }
    });

    test('参数不对：缺 backend、不是对象、没有 routes、kind 不对', () async {
      for (final args in <Map<String, dynamic>>[
        {},
        {'backend': 42},
        {'backend': <Object>[]},
        {
          'backend': {'name': 'x'},
        },
        {
          'backend': {'routes': '不是数组'},
        },
        {
          'backend': {'kind': 'page', 'routes': <Object>[]},
        },
        {
          'backend': {'routes': <Object>[]},
          'path': 7,
        },
      ]) {
        final r = await box().execute(kBackendUpdateTool, args);
        expect(r.ok, isFalse, reason: '$args');
        expect(r.text, startsWith('错误：'));
      }
      expect(snapshot(), isEmpty);
    });

    test('路径：越界、内部目录、名字不对都拒绝，外面的文件没被动', () async {
      for (final bad in ['../$kBackendFileName', '../../outside.txt', '/tmp/$kBackendFileName', '${PathGuard.reservedDir}/$kBackendFileName', 'server/other.json', 'backend.json']) {
        final r = await box().execute(kBackendUpdateTool, {'backend': starter(), 'path': bad});
        expect(r.ok, isFalse, reason: bad);
      }
      expect(snapshot(), isEmpty);
      expect(Directory(tmp.path).listSync().map((e) => p.basename(e.path)).toSet(), {'proj', 'outside.txt'});
      expect(File(p.join(tmp.path, 'outside.txt')).readAsStringSync(), '原样');
    });

    test('现有文件是坏的：照新的整份写', () async {
      put(kBackendFileName, '{ 坏的');
      final r = await box().execute(kBackendUpdateTool, {'backend': starter()});
      expect(r.ok, isTrue, reason: r.text);
      expect(BeDocument.parse(f(kBackendFileName).readAsStringSync()).doc.routes.length, 7);
    });

    test('没有接口也能存（routes: []）', () async {
      final r = await box().execute(kBackendUpdateTool, {
        'backend': {'name': '空的', 'routes': <Object>[]},
      });
      expect(r.ok, isTrue, reason: r.text);
      expect(BeDocument.parse(f(kBackendFileName).readAsStringSync()).doc.routes, isEmpty);
    });

    test('改完再读：读到的就是刚写的', () async {
      await box().execute(kBackendUpdateTool, {'backend': starter('python')});
      final r = await box().execute(kBackendGetTool, {});
      expect(r.text, contains('"language": "python"'));
      expect(r.text, contains('校验：没有问题。'));
    });
  });

  test('读法摘要：每个接口一行，带积木数；空文档也有话说', () {
    final text = describeBackendDocument(backendStarterDocument('样本'));
    for (final line in ['GET /hello', 'POST /todos', 'GET /todos/count', 'PATCH /todos/:id']) {
      expect(text, contains(line));
    }
    expect(describeBackendDocument(BeDocument()), isNotEmpty);
  });
}
