// 存盘健壮性：原子写、坏文件备份后回退默认、各个存盘文件读到损坏 / 旧版本内容不崩。
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/agent/automation.dart';
import 'package:lopicode/agent/background_commands.dart';
import 'package:lopicode/agent/mcp/mcp_config.dart';
import 'package:lopicode/agent/mcp/mcp_models.dart';
import 'package:lopicode/agent/memory_store.dart';
import 'package:lopicode/agent/model_config.dart';
import 'package:lopicode/agent/team.dart';
import 'package:lopicode/apkpack/apk_pack_contract.dart';
import 'package:lopicode/appearance/theme_builtin.dart';
import 'package:lopicode/appearance/theme_fields.dart';
import 'package:lopicode/appearance/theme_json.dart';
import 'package:lopicode/appearance/theme_store.dart';
import 'package:lopicode/backdrop/backdrop_model.dart';
import 'package:lopicode/backdrop/backdrop_store.dart';
import 'package:lopicode/backdrop/crop_math.dart';
import 'package:lopicode/backend/backend_block_host.dart';
import 'package:lopicode/backend/backend_core_gen.dart';
import 'package:lopicode/backend/backend_lib_store.dart';
import 'package:lopicode/backend/backend_model.dart';
import 'package:lopicode/backend/backend_project.dart';
import 'package:lopicode/backend/backend_type_bridge.dart';
import 'package:lopicode/backend/backend_validate.dart';
import 'package:lopicode/build/local_pack_form.dart';
import 'package:lopicode/core/crash_log.dart';
import 'package:lopicode/core/path_guard.dart';
import 'package:lopicode/core/project_store.dart';
import 'package:lopicode/core/safe_file.dart';
import 'package:lopicode/core/stores.dart';
import 'package:lopicode/core/templates.dart';
import 'package:lopicode/lang/gen2_all.dart';
import 'package:lopicode/lowcode/comp_lib.dart';
import 'package:lopicode/lowcode/comp_lib_store.dart';
import 'package:lopicode/lowcode/component_model.dart';
import 'package:lopicode/lowcode/editor_recents.dart';
import 'package:lopicode/lowcode/model.dart';
import 'package:lopicode/session/conversation.dart';
import 'package:lopicode/session/favorites.dart';
import 'package:lopicode/session/turn_journal.dart';
import 'package:lopicode/templates/project_templates.dart';
import 'package:path/path.dart' as p;

List<File> badBackups(File file) => [
  for (final e in file.parent.listSync())
    if (e is File && p.basename(e.path).startsWith('${p.basename(file.path)}.bad-')) e,
];

/// 各种“坏内容”：半截、乱码、形状不对、空。
const corruptSamples = {'半截': '{"a": 1, "b": [1, 2', '乱码': '\u0000\u0001not json at all }{', '形状不对（数字）': '42', '形状不对（字符串）': '"hello"', 'null': 'null'};

void main() {
  late Directory tmp;
  setUp(() {
    tmp = Directory.systemTemp.createTempSync('lopi_safe_');
    CrashLog.instance.resetForTest();
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  group('原子写', () {
    test('写完内容对、不留临时文件、目录不存在会自动建', () async {
      final file = File(p.join(tmp.path, 'a', 'b', 'data.json'));
      await writeJsonAtomic(file, {'x': 1});
      expect(jsonDecode(file.readAsStringSync()), {'x': 1});
      expect(File('${file.path}.tmp').existsSync(), isFalse);
      await writeJsonAtomic(file, {'x': 2});
      expect(jsonDecode(file.readAsStringSync()), {'x': 2});
      expect(file.parent.listSync().length, 1);
    });

    test('同一个文件连着写很多次：最后留下的是最后一次的内容，每一刻文件都是完整的', () async {
      final file = File(p.join(tmp.path, 'data.json'));
      await writeJsonAtomic(file, {'n': -1});
      final writes = [
        for (var i = 0; i < 40; i++) writeJsonAtomic(file, {'n': i, 'pad': 'x' * 2000}),
      ];
      // 写的同时不停地读：读到的必须总是完整的 JSON。Windows 替换文件时允许短暂重开，JSON 不完整仍直接失败。
      Future<Map<String, dynamic>> readComplete() async {
        for (var attempt = 0; ; attempt++) {
          try {
            return jsonDecode(await file.readAsString()) as Map<String, dynamic>;
          } on FileSystemException {
            if (!Platform.isWindows || attempt >= 5) rethrow;
            await Future<void>.delayed(Duration(milliseconds: 5 << attempt));
          }
        }
      }

      for (var i = 0; i < 40; i++) {
        expect(await readComplete(), isA<Map<String, dynamic>>());
      }
      await Future.wait(writes);
      expect((jsonDecode(file.readAsStringSync()) as Map)['n'], 39);
      expect(File('${file.path}.tmp').existsSync(), isFalse);
    });

    test('写失败（目标是个目录）：抛 FileSystemException，不留临时文件，后面的写入不受影响', () async {
      final dir = Directory(p.join(tmp.path, 'data.json'))..createSync();
      await expectLater(writeStringAtomic(File(dir.path), 'x'), throwsA(isA<FileSystemException>()));
      expect(File('${dir.path}.tmp').existsSync(), isFalse);
      dir.deleteSync();
      await writeStringAtomic(File(dir.path), 'ok');
      expect(File(dir.path).readAsStringSync(), 'ok');
    });
  });

  group('读坏文件', () {
    test('不存在 → null，不产生备份', () async {
      final file = File(p.join(tmp.path, 'none.json'));
      expect(await readJsonFile(file), isNull);
      expect(tmp.listSync(), isEmpty);
    });

    test('空文件 → null，不备份（没内容可留）', () async {
      final file = File(p.join(tmp.path, 'empty.json'))..writeAsStringSync('  \n');
      expect(await readJsonFile(file), isNull);
      expect(badBackups(file), isEmpty);
    });

    for (final entry in corruptSamples.entries) {
      test('${entry.key} → null，原文件另存一份 .bad-，内容一字不差，并记一笔日志', () async {
        final file = File(p.join(tmp.path, 'data.json'))..writeAsStringSync(entry.value);
        final got = await readJsonFile(file, accept: (j) => j is Map<String, dynamic>, label: '测试文件');
        expect(got, isNull);
        final backups = badBackups(file);
        expect(backups, hasLength(1));
        expect(backups.single.readAsStringSync(), entry.value);
        expect(CrashLog.instance.entries.last.message, contains('测试文件'));
        expect(CrashLog.instance.entries.last.fatal, isFalse, reason: '回退了默认值，不用打扰用户');
      });
    }

    test('不是合法 UTF-8 → null 且有备份', () async {
      final file = File(p.join(tmp.path, 'data.json'))..writeAsBytesSync([0xff, 0xfe, 0x00, 0xc3, 0x28]);
      expect(await readJsonFile(file), isNull);
      expect(badBackups(file), hasLength(1));
    });

    test('坏文件备份最多留 $kMaxBadBackups 份', () async {
      final file = File(p.join(tmp.path, 'data.json'));
      for (var i = 0; i < kMaxBadBackups + 3; i++) {
        file.writeAsStringSync('{bad $i');
        await readJsonFile(file);
      }
      expect(badBackups(file).length, kMaxBadBackups);
    });
  });

  group('各个存盘文件读到坏内容不崩', () {
    for (final entry in corruptSamples.entries) {
      test('设置文件：${entry.key} → 回退空设置、有备份、之后还能正常保存', () async {
        final file = File(p.join(tmp.path, 'settings.json'))..writeAsStringSync(entry.value);
        final settings = SettingsStore(file);
        await settings.load();
        expect(settings.getString('ui.themeMode', 'system'), 'system');
        expect(badBackups(file), hasLength(1));
        await settings.set('ui.themeMode', 'dark');
        final again = SettingsStore(file);
        await again.load();
        expect(again.getString('ui.themeMode'), 'dark');
      });

      test('自动化任务：${entry.key} → 当没有任务', () async {
        final file = File(p.join(tmp.path, 'automations.json'))..writeAsStringSync(entry.value);
        final store = AutomationStore(file);
        await store.load();
        expect(store.items, isEmpty);
        expect(badBackups(file), hasLength(1));
      });

      test('工作区登记文件：${entry.key} → 应用目录里的项目照样列得出来', () async {
        final store = ProjectStore(p.join(tmp.path, 'projects'));
        final project = await store.create('小站', ProjectTemplate.web);
        File(p.join(tmp.path, 'projects', '.workspaces.json')).writeAsStringSync(entry.value);
        final list = await store.list();
        expect(list.map((x) => x.id), contains(project.id));
      });

      test('项目信息 project.json：${entry.key} → 项目不从列表里消失，名字用目录名顶上', () async {
        final store = ProjectStore(p.join(tmp.path, 'projects'));
        final project = await store.create('小站', ProjectTemplate.web);
        final meta = File(p.join(project.dir, '.lopicode', 'project.json'));
        expect(meta.existsSync(), isTrue);
        meta.writeAsStringSync(entry.value);
        final list = await store.list();
        final got = list.where((x) => x.id == project.id).single;
        expect(got.name, p.basename(project.dir));
        expect(badBackups(meta), hasLength(1));
        // 用户的文件一个没少
        expect(File(p.join(project.dir, 'index.html')).existsSync(), isTrue);
      });

      test('后端生成记录 backend-gen.json：${entry.key} → 当没有记录，照样重新生成，坏文件留备份', () async {
        final store = ProjectStore(p.join(tmp.path, 'projects'));
        final project = await createProjectFromTemplate(store, '后端', ProjectTemplate.backendBlocks, language: 'node');
        final record = File(p.join(project.dir, '.lopicode', kBackendManifestFile))..writeAsStringSync(entry.value);
        final result = await regenerateBackend(project.dir);
        expect(result.error, isNull);
        expect(result.conflicts, isEmpty, reason: '没动过的生成文件靠开头的标记也认得出来');
        expect(badBackups(record), hasLength(1));
        expect(jsonDecode(record.readAsStringSync()), isA<Map<String, dynamic>>());
      });

      test('团队任务板：${entry.key} → 当空任务板', () async {
        final file = File(p.join(tmp.path, 'team.json'))..writeAsStringSync(entry.value);
        final board = TeamBoard(file: file);
        await board.load();
        expect(board.tasks, isEmpty);
      });

      test('MCP 服务器配置 mcp_servers.json：${entry.key} → 当一个服务器都没有，照样能再加、再存', () async {
        final file = File(p.join(tmp.path, 'mcp_servers.json'))..writeAsStringSync(entry.value);
        final store = McpStore(file, MemorySecretStore());
        await store.load();
        expect(store.servers, isEmpty);
        await store.save([McpServerConfig(id: 'a', name: '资料库', url: 'https://example.com/mcp')]);
        expect(((jsonDecode(file.readAsStringSync()) as Map)['servers'] as List).length, 1);
      });

      test('进行中记录 turn.json：${entry.key} → 当没有记录（不提示、不崩），之后还能正常记', () async {
        final file = File(p.join(tmp.path, 'turn.json'))..writeAsStringSync(entry.value);
        final store = TurnJournalStore(file);
        expect(await store.interrupted(), isNull);
        store.begin('做个页面');
        await store.finish();
        expect((jsonDecode(file.readAsStringSync()) as Map)['finished'], isTrue);
      });

      test('后台命令记录 background.json：${entry.key} → 当没有任务，之后还能正常记', () async {
        File(p.join(tmp.path, kBackgroundFile))
          ..parent.createSync(recursive: true)
          ..writeAsStringSync(entry.value);
        final manager = BackgroundCommands(PathGuard(tmp.path));
        await manager.load();
        expect(manager.tasks, isEmpty);
        expect(manager.unnotified('c1'), isEmpty);
        manager.dispose();
        await pendingWrites();
      });
    }

    test('进行中记录：字段类型不对（步骤不是列表、步骤里混着别的东西）→ 读到哪算哪', () async {
      final file = File(p.join(tmp.path, 'turn.json'))
        ..writeAsStringSync(
          jsonEncode({
            'token': 'old',
            'at': 1,
            'text': 42,
            'finished': 'no',
            'steps': [
              7,
              {'id': 'c1'},
              {'id': 'c2', 'name': 'run_command', 'args': 9},
            ],
          }),
        );
      final cut = await TurnJournalStore(file).interrupted();
      expect(cut, isNotNull);
      expect(cut!.steps.single.callId, 'c2');
      expect(cut.describe().lines, isNotEmpty);
      File(p.join(tmp.path, 'turn2.json')).writeAsStringSync(jsonEncode({'token': 'old', 'at': 1, 'steps': 'nope'}));
      expect((await TurnJournalStore(File(p.join(tmp.path, 'turn2.json'))).interrupted())!.steps, isEmpty);
    });

    test('MCP 服务器配置：字段类型全错、混着别的东西、地址不合规矩 → 读到哪算哪，坏的条目跳过，不抛异常', () async {
      final file = File(p.join(tmp.path, 'mcp_servers.json'))
        ..writeAsStringSync(
          jsonEncode({
            'version': 'x',
            'servers': [
              42,
              null,
              {'id': 7, 'name': '没有编号'},
              {
                'id': 'ok',
                'name': '还行',
                'url': 'https://example.com/mcp',
                'transport': 'telepathy',
                'enabled': 'yes',
                'headerNames': ['Authorization', 5, 'bad name'],
                'disabledTools': 'all',
                'tools': [
                  1,
                  {'name': 'good', 'description': 9, 'inputSchema': 'nope'},
                  {'name': ''},
                ],
                'toolsAt': 'yesterday',
                'mode': 12,
              },
            ],
          }),
        );
      final store = McpStore(file, MemorySecretStore());
      await store.load();
      final ok = store.servers.where((s) => s.id == 'ok').single;
      expect(ok.url, 'https://example.com/mcp');
      expect(ok.transport, McpTransportChoice.auto);
      expect(ok.tools.map((t) => t.name), ['good']);
      expect(ok.headerNames, ['Authorization']);
      expect(store.servers, hasLength(1));
      expect(ok.enabled, isTrue);
      expect(ok.disabledTools, isEmpty);
      expect(ok.toolsAt, isNull);
      expect(ok.mode, isNull);
      expect(badBackups(file), isEmpty, reason: '是合法 JSON，不算坏文件');
    });

    test('旧版本 / 字段类型不对的内容：读到哪算哪，不抛异常', () async {
      // 设置：值的类型不对 → 取的时候回退默认
      final sfile = File(p.join(tmp.path, 'settings.json'))
        ..writeAsStringSync(
          jsonEncode({
            'ui.themeMode': 7,
            'models.channels': 'oops',
            'unknown.future.key': {'a': 1},
          }),
        );
      final settings = SettingsStore(sfile);
      await settings.load();
      expect(settings.getString('ui.themeMode', 'system'), 'system');
      final models = ModelConfigStore(settings, MemorySecretStore());
      await models.load();
      expect(models.channels, isEmpty);
      expect(badBackups(sfile), isEmpty, reason: '文件本身是合法 JSON，不算坏文件');

      // 每个模型记住的思考档位（ai.thinkingLevels）：整张表类型不对 / 里面混着别的东西 → 坏的丢掉，好的照用，之后还能再记
      for (final bad in <Object?>[
        'oops',
        7,
        <int>[1, 2],
        null,
      ]) {
        await settings.set(ModelConfigStore.kLevels, bad);
        expect(models.thinkingLevels, isEmpty, reason: '$bad');
        expect(models.thinkingLevelOf('c', 'm'), isNull);
      }
      await settings.set(ModelConfigStore.kLevels, {
        'c/m': 'high',
        'c/n': 3,
        'c/o': null,
        'c/p': {'level': 'low'},
        'c/q': '乱写的档位',
      });
      expect(models.thinkingLevels, {'c/m': 'high', 'c/q': '乱写的档位'});
      final ch = await models.upsert(
        name: '渠道',
        protocol: ChatProtocol.openaiChat,
        // 思考参数核对过的地址（OpenRouter：低 / 中 / 高）；没核对过的服务商不给档位，另有测试
        baseUrl: 'https://openrouter.ai/api/v1',
        models: [ModelSpec(id: 'q', thinking: true)],
      );
      await settings.set(ModelConfigStore.kLevels, {'${ch.id}/q': '乱写的档位', 'x': 1});
      expect(models.resolve(ModelSelection(ch.id, 'q', 'high'))!.level, 'off', reason: '不认识的档位当“关”，不发给接口');
      await models.setThinkingLevel(ch.id, 'q', 'low');
      expect(models.thinkingLevels, {'${ch.id}/q': 'low'}, reason: '再记一次：坏条目顺手清掉');
      expect(models.resolve(ModelSelection(ch.id, 'q', 'high'))!.level, 'low');

      // 自动化：混着好的和坏的条目
      final afile = File(p.join(tmp.path, 'automations.json'))
        ..writeAsStringSync(
          jsonEncode([
            42,
            'x',
            {'id': 7},
            null,
            <int>[],
          ]),
        );
      final autos = AutomationStore(afile);
      await autos.load();
      expect(autos.items, isEmpty);

      // 团队：字段类型全错
      final tfile = File(p.join(tmp.path, 'team.json'))
        ..writeAsStringSync(
          jsonEncode({
            'members': {'not': 'a list'},
            'tasks': 'nope',
            'messages': 3,
            'seq': 'x',
          }),
        );
      final board = TeamBoard(file: tfile);
      await board.load();
      expect(board.tasks, isEmpty);
    });

    test('后端积木文件 backend.lc.json（第 2 版，用了新积木）：段 / 参数 / 选项的类型全错 → 读到哪算哪，不抛异常、不算坏文件，再存一次是稳定的', () async {
      final file = File(p.join(tmp.path, 'backend.lc.json'))
        ..writeAsStringSync(
          jsonEncode({
            'version': 2,
            'kind': 'backend',
            'language': 'node',
            'routes': [
              {
                'id': 'r1',
                'method': 'GET',
                'path': '/x',
                'body': [
                  {
                    'op': 'let',
                    'args': {'name': 7, 'value': '不是式子'},
                  },
                  {
                    'op': 'if',
                    'args': {'cond': null},
                    'arms': '不是列表',
                    'noElse': 'yes',
                  },
                  {
                    'op': 'if',
                    'args': <String, Object?>{},
                    'arms': [
                      3,
                      null,
                      {'args': '不是对象', 'body': 9},
                    ],
                    'else': 'x',
                  },
                  {
                    'op': 'switch',
                    'arms': {'a': 1},
                  },
                  {
                    'op': 'forCount',
                    'args': {'name': <Object?>[], 'from': <String, Object?>{}, 'to': 'x', 'step': null},
                    'body': 'x',
                  },
                  {
                    'op': 'respondJson',
                    'args': {
                      'value': {
                        'e': 'round',
                        'x': {'e': 'listLit', 'items': 4},
                        'fn': 5,
                      },
                    },
                  },
                ],
              },
              '不是接口',
            ],
          }),
        );
      final parsed = (await loadBackendFile(file))!;
      expect(badBackups(file), isEmpty, reason: '文件本身是合法 JSON，不算坏文件');
      expect(parsed.doc.routes, hasLength(1));
      expect(parsed.doc.routes.single.body.map((b) => b.op), containsAll(['let', 'if', 'switch', 'forCount']));
      expect(() => validateBackend(parsed.doc), returnsNormally);
      await saveBackendFile(file, parsed.doc);
      final again = (await loadBackendFile(file))!;
      expect(again.doc.encode(), parsed.doc.encode());
    });

    test('后端积木文件 backend.lc.json（第 4 版，核心 2）：core / 类型 / 字段 / 情况 / 方法 / 模块 / 积木的参数类型全错 → 读到哪算哪，不抛异常、不算坏文件，再存一次是稳定的', () async {
      for (final core in <Object?>[
        '不是对象',
        [1, 2],
        {
          'types': '不是列表',
          'globals': 7,
          'modules': {'a': 1},
          'entry': 3,
          'public': '不是列表',
          'main': '不是对象',
        },
        {
          'types': [
            null,
            3,
            {'id': 9, 'kind': '没有这种', 'name': '甲'},
            {'id': 't1', 'kind': 'record', 'name': 5},
            {
              'id': 't1',
              'kind': 'record',
              'name': '点',
              'fields': [
                null,
                {'name': 3},
                {'name': 'x', 'type': '不是类型', 'init': 5, 'private': 'yes'},
              ],
              'cases': '不是列表',
              'parent': 4,
              'interfaces': [1, null],
              'open': 'yes',
              'ctor': '不是对象',
              'methods': [
                7,
                {'id': 'm1', 'name': '做', 'params': '不是列表', 'returns': 3, 'body': '不是列表'},
              ],
            },
            {
              'id': 't1',
              'kind': 'variant',
              'name': '形状',
              'cases': [
                3,
                {'name': '圆', 'fields': 'x'},
              ],
            },
          ],
          'globals': [
            null,
            {'name': '9bad'},
            {'name': 'n', 'init': '不是值', 'const': 1, 'type': 9},
          ],
          'modules': [
            4,
            {'name': 7},
            {
              'name': '甲',
              'uses': 'x',
              'owns': [1, null, 't1'],
            },
          ],
          'entry': '没有这个模块',
          'public': [3, 'g:没有'],
          'main': {
            'body': [
              {'op': 'try', 'arms': '不是列表', 'args': 3},
              {
                'op': 'match',
                'args': {'value': 7},
                'arms': [
                  3,
                  {'args': 'x', 'body': 9},
                  {
                    'args': {'case': 5, 'binds': <Object?>[]},
                  },
                ],
              },
              {
                'op': 'throw',
                'args': {
                  'value': {'e': 'errNew', 'kind': 3, 'message': null, 'fields': 'x'},
                },
              },
              {
                'op': 'log',
                'args': {
                  'value': {
                    'e': 'recNew',
                    'type': <Object?>[],
                    'fields': [
                      1,
                      {'e': 'pair'},
                      {'e': 'pair', 'key': 3, 'value': 'x'},
                    ],
                  },
                },
              },
              {
                'op': 'setField',
                'args': {
                  'of': {'e': 'classNew', 'type': '没有', 'args': 3},
                  'name': 4,
                  'value': {'e': 'callMethod', 'of': 1, 'name': null, 'args': <String, Object?>{}},
                },
              },
            ],
          },
        },
      ]) {
        final file = File(p.join(tmp.path, 'backend.lc.json'))..writeAsStringSync(jsonEncode({'version': 4, 'kind': 'backend', 'language': 'node', 'rules': 2, 'routes': <Object?>[], 'core': core}));
        final parsed = (await loadBackendFile(file))!;
        expect(badBackups(file), isEmpty, reason: '文件本身是合法 JSON，不算坏文件');
        expect(() => validateBackend(parsed.doc), returnsNormally);
        expect(() => beTypeCheck(parsed.doc), returnsNormally);
        for (final language in kGen2Languages) {
          expect(() => beCoreCodeText(parsed.doc, language), returnsNormally);
        }
        expect(() => BeBlockHost(doc: parsed.doc.clone()).issues, returnsNormally);
        await saveBackendFile(file, parsed.doc);
        final again = (await loadBackendFile(file))!;
        expect(again.doc.encode(), parsed.doc.encode());
      }
    });

    test('后端积木文件 backend.lc.json（第 3 版，带“我的积木”）：functions / 外观 / 参数 / 调用 / 匿名函数的类型全错 → 读到哪算哪，不抛异常、不算坏文件，再存一次是稳定的', () async {
      for (final functions in <Object?>[
        '不是列表',
        {'f1': 1},
        [
          3,
          null,
          '不是函数',
          {'id': 9, 'look': '不是对象', 'params': 7, 'body': '不是列表', 'x': '左', 'y': null},
          {
            'id': 'f1',
            'look': {
              'name': <Object?>[],
              'shape': 5,
              'slots': {'a': 1},
              'template': 3,
              'icon': <String, Object?>{},
            },
            'params': [
              null,
              '不是对象',
              {'name': 3},
              {
                'name': 'a',
                'default': {'x': 1},
                'rest': 'yes',
              },
            ],
            'body': [
              {
                'op': 'return',
                'args': {
                  'value': {'e': 'lambda', 'params': '不是列表', '@body': 'x'},
                },
              },
              {'op': 'call:f1', 'args': '不是对象'},
              {
                'op': 'call:',
                'args': {'a': 7},
              },
              {
                'op': 'listEach',
                'args': {
                  'xs': 3,
                  'fn': {
                    'e': 'lambdaExpr',
                    'params': [1, null, 'e', '@x'],
                    'body': '不是式子',
                  },
                },
              },
            ],
          },
        ],
      ]) {
        final file = File(p.join(tmp.path, 'backend.lc.json'))
          ..writeAsStringSync(
            jsonEncode({
              'version': 3,
              'kind': 'backend',
              'language': 'node',
              'routes': [
                {
                  'id': 'r1',
                  'method': 'GET',
                  'path': '/x',
                  'body': [
                    {
                      'op': 'call:f404',
                      'args': {
                        'a': {
                          'e': 'call:f1',
                          'a': {'e': 'funcRef', 'fn': 12},
                        },
                      },
                    },
                    {
                      'op': 'respondJson',
                      'args': {
                        'value': {'e': 'callValue', 'fn': 4, 'args': 'x'},
                      },
                    },
                  ],
                },
              ],
              'functions': functions,
            }),
          );
        final parsed = (await loadBackendFile(file))!;
        expect(badBackups(file), isEmpty, reason: '文件本身是合法 JSON，不算坏文件');
        expect(parsed.doc.routes.single.body, hasLength(2));
        expect(() => validateBackend(parsed.doc), returnsNormally);
        await saveBackendFile(file, parsed.doc);
        final again = (await loadBackendFile(file))!;
        expect(again.doc.encode(), parsed.doc.encode());
      }
    });
  });

  group('文件记忆的两个存盘文件', () {
    for (final entry in corruptSamples.entries) {
      test('记忆的撤销记录 undo.json：${entry.key} → 当没有可撤销的，记忆本身照常读写', () async {
        final dir = Directory(p.join(tmp.path, 'memory'))..createSync();
        File(p.join(dir.path, '甲.md')).writeAsStringSync('# 甲\n\n一\n');
        final undo = File(p.join(dir.path, 'undo.json'))..writeAsStringSync(entry.value);
        final store = MemoryStore(dir.path, MemoryScope.global);
        expect((await store.load()).single.title, '甲');
        expect(store.changes, isEmpty);
        await store.write('乙', '二');
        expect(store.entries, hasLength(2));
        expect(store.changes, hasLength(1), reason: '坏文件回退以后撤销记录照常能用');
        expect(jsonDecode(undo.readAsStringSync()), isA<List<dynamic>>());
        await pendingWrites();
      });
    }

    test('undo.json 形状对、里面的条目类型全错：读到哪算哪，不抛异常、不算坏文件', () async {
      final dir = Directory(p.join(tmp.path, 'memory'))..createSync();
      final undo = File(p.join(dir.path, 'undo.json'))
        ..writeAsStringSync(
          jsonEncode([
            1,
            'x',
            null,
            {'id': 5},
            {'id': '甲', 'before': 3, 'after': <String>[]},
            {'id': '../外面', 'after': 'x'},
            {'id': '乙', 'title': 9, 'before': null, 'after': '# 乙\n\n二\n', 'at': '不是数字', 'by': 1},
          ]),
        );
      final store = MemoryStore(dir.path, MemoryScope.project);
      await store.load();
      expect(store.changes.single.id, '乙');
      expect(store.changes.single.title, '乙');
      expect(store.changes.single.by, 'agent');
      expect(badBackups(undo), isEmpty, reason: '文件本身是合法 JSON，不算坏文件');
    });

    test('记忆文件本身不是文本（二进制垃圾）：跳过那一条，别的照常', () async {
      final dir = Directory(p.join(tmp.path, 'memory'))..createSync();
      File(p.join(dir.path, '坏的.md')).writeAsBytesSync([0xff, 0xfe, 0x00, 0xc3, 0x28]);
      File(p.join(dir.path, '好的.md')).writeAsStringSync('# 好的\n\n正常\n');
      final store = MemoryStore(dir.path, MemoryScope.global);
      expect((await store.load()).map((e) => e.title), ['好的']);
    });
  });

  group('对话的出处（对话目录 chats.json 里的 from：分支 / 旧版本）', () {
    test('旧目录没有 from：照常读，出处是空的', () {
      final conv = Conversation.fromJson({'id': 'main', 'title': '老对话', 'updatedAt': '2026-11-01T10:00:00.000'})!;
      expect((conv.title, conv.origin), ('老对话', null));
    });

    test('from 的形状不对、里面的字段类型不对：当普通对话读，不抛异常', () {
      for (final bad in <Object?>[
        'x',
        42,
        true,
        <String>['main'],
        <String, dynamic>{},
        {'conv': 42},
        {'conv': null, 'msg': 'm'},
        {'conv': '../x'},
        {'conv': 'a/b'},
      ]) {
        final conv = Conversation.fromJson({'id': 'abc', 'title': 't', 'from': bad});
        expect(conv, isNotNull, reason: '$bad');
        expect(conv!.origin, isNull, reason: '$bad');
      }
      final loose = Conversation.fromJson({
        'id': 'abc',
        'from': {
          'conv': 'main',
          'msg': <int>[1],
          'title': 9,
          'old': 'true',
        },
      })!;
      expect((loose.origin!.convId, loose.origin!.messageId, loose.origin!.title, loose.origin!.old), ('main', null, '', false));
    });

    test('存了再读：原样回来', () {
      final conv = Conversation(
        'abc',
        '标题',
        DateTime(2026, 11, 25),
        origin: const BranchOrigin(convId: 'main', messageId: 'm1', title: '原对话', old: true),
      );
      final back = Conversation.fromJson(jsonDecode(jsonEncode(conv.toJson())) as Map<String, dynamic>)!;
      expect((back.origin!.convId, back.origin!.messageId, back.origin!.title, back.origin!.old), ('main', 'm1', '原对话', true));
    });
  });

  group('用户主题 themes/<标识>.json', () {
    Directory dir() => Directory(p.join(tmp.path, 'themes'));
    File fileOf(String id) => File(p.join(dir().path, '$id.json'));

    test('没有目录：空的，不建目录', () async {
      final store = ThemeStore(dir());
      await store.load();
      expect(store.user, isEmpty);
      expect(store.loaded, isTrue);
      expect(dir().existsSync(), isFalse);
    });

    test('存了再读：原样回来；原子写不留临时文件', () async {
      final store = ThemeStore(dir());
      final t = kDefaultDarkTheme.copyWith(id: 'u-a-0', name: '夜里', builtin: false).withColors('ui', {UiKey.accent: 0xFF123456});
      await store.save(t);
      final again = ThemeStore(dir());
      await again.load();
      expect(again.user.single, t);
      expect(again.byId('u-a-0')!.ui[UiKey.accent], 0xFF123456);
      expect(dir().listSync().where((e) => e.path.endsWith('.tmp')), isEmpty);
    });

    for (final entry in corruptSamples.entries) {
      test('坏内容（${entry.key}）：跳过这一套，不抛异常，别的照常读', () async {
        final store = ThemeStore(dir());
        await store.save(kDefaultLightTheme.copyWith(id: 'u-good-0', name: '好的', builtin: false));
        fileOf('u-bad-0').writeAsStringSync(entry.value);
        final again = ThemeStore(dir());
        await again.load();
        expect(again.user.map((t) => t.id), ['u-good-0']);
      });
    }

    test('半截的文件：留一份 .bad 备份', () async {
      dir().createSync(recursive: true);
      fileOf('u-bad-0').writeAsStringSync(corruptSamples['半截']!);
      await ThemeStore(dir()).load();
      expect(badBackups(fileOf('u-bad-0')), hasLength(1));
    });

    test('是 JSON 但不是主题（形状不对、颜色写错、版本是以后的）：跳过，不崩', () async {
      dir().createSync(recursive: true);
      fileOf('u-x-0').writeAsStringSync(jsonEncode({'hello': 'world'}));
      fileOf('u-x-1').writeAsStringSync(
        jsonEncode({
          'format': 'lopicode-theme',
          'version': 99,
          'theme': {'name': 'a', 'dark': false},
        }),
      );
      fileOf('u-x-2').writeAsStringSync(
        jsonEncode({
          'format': 'lopicode-theme',
          'version': 1,
          'theme': {
            'name': 'a',
            'dark': false,
            'ui': {'bg': 'red'},
          },
        }),
      );
      fileOf('u-ok-0').writeAsStringSync(
        jsonEncode({
          'format': 'lopicode-theme',
          'version': 1,
          'theme': {'name': '只有名字', 'dark': true},
        }),
      );
      final store = ThemeStore(dir());
      await store.load();
      expect(store.user.map((t) => t.id), ['u-ok-0']);
      expect(store.user.single.ui, kDefaultDarkTheme.ui, reason: '缺的字段从同明暗的默认主题补');
    });

    test('文件里写的标识和文件名对不上：以文件名为准', () async {
      dir().createSync(recursive: true);
      fileOf('u-name-0').writeAsStringSync(encodeThemeText(kDefaultLightTheme.copyWith(id: 'u-other-9', name: '甲', builtin: false)));
      final store = ThemeStore(dir());
      await store.load();
      expect(store.user.single.id, 'u-name-0');
    });

    test('标识不合规矩的不写（不会写到 themes 目录外面去）；删除不存在的不报错', () async {
      final store = ThemeStore(dir());
      expect(() => store.save(kDefaultLightTheme.copyWith(id: '../escape', builtin: false)), throwsArgumentError);
      await store.delete('../escape');
      await store.delete('u-none-0');
      expect(File(p.join(tmp.path, 'escape.json')).existsSync(), isFalse);
    });
  });

  group('收藏的消息 favorites.json', () {
    File file() => File(p.join(tmp.path, 'favorites.json'));

    test('没有文件：空列表，不建文件', () async {
      expect(await readFavorites(file()), isEmpty);
      expect(file().existsSync(), isFalse);
    });

    test('存了再读：原样回来（顺序、已删除标记、时间）', () async {
      final items = [
        FavoriteMessage(convId: 'main', messageId: 'm2', role: 'assistant', text: '回答', convTitle: '对话', savedAt: DateTime.fromMillisecondsSinceEpoch(2000), gone: true),
        FavoriteMessage(convId: 'c9', messageId: 'm1', role: 'user', text: '提问', convTitle: '', savedAt: DateTime.fromMillisecondsSinceEpoch(1000)),
      ];
      await writeFavorites(file(), items);
      final back = await readFavorites(file());
      expect([for (final f in back) f.key], ['main/m2', 'c9/m1']);
      expect([for (final f in back) f.gone], [true, false]);
      expect([for (final f in back) f.mine], [false, true]);
      expect(back.first.savedAt.millisecondsSinceEpoch, 2000);
      expect(back.first.text, '回答');
      expect(Directory(tmp.path).listSync().where((e) => e.path.endsWith('.tmp')), isEmpty, reason: '原子写不留临时文件');
    });

    for (final entry in corruptSamples.entries) {
      test('坏内容（${entry.key}）：空列表，不抛异常', () async {
        file().writeAsStringSync(entry.value);
        expect(await readFavorites(file()), isEmpty);
      });
    }

    test('半截的文件：留一份 .bad 备份', () async {
      file().writeAsStringSync(corruptSamples['半截']!);
      await readFavorites(file());
      expect(badBackups(file()), hasLength(1));
    });

    test('形状对、条目类型全错 / 缺字段 / 重复：读到哪算哪，坏的跳过，不算坏文件', () async {
      file().writeAsStringSync(
        jsonEncode({
          'version': 1,
          'items': [
            1,
            'x',
            null,
            {'conv': 5, 'msg': 'm'},
            {'conv': 'main', 'msg': ''},
            {'conv': 'main', 'msg': 'm1', 'role': 9, 'text': 3, 'title': <String>[], 'at': '不是数字', 'gone': 'yes'},
            {'conv': 'main', 'msg': 'm1', 'role': 'user', 'text': '重复的'},
            {'conv': 'main', 'msg': 'm2', 'role': 'user', 'text': '好的', 'title': '标题', 'at': 5},
          ],
        }),
      );
      final back = await readFavorites(file());
      expect([for (final f in back) f.key], ['main/m1', 'main/m2']);
      expect(back.first.text, '');
      expect(back.first.gone, isFalse);
      expect(back.last.convTitle, '标题');
      expect(badBackups(file()), isEmpty);
    });

    test('items 不是列表、版本号是以后的：不崩', () async {
      file().writeAsStringSync(jsonEncode({'version': 99, 'items': 'x'}));
      expect(await readFavorites(file()), isEmpty);
    });
  });
  group('本地打包表单 .lopicode/local-pack.json', () {
    const fallback = LocalPackForm(appName: '默认名', packageName: 'com.lopicode.app.demo', versionName: '1.0.0', versionCode: '1', permissions: {'android.permission.INTERNET'});
    const options = [ApkPermissionOption(id: 'android.permission.INTERNET', label: '联网', hint: '', defaultOn: true), ApkPermissionOption(id: 'android.permission.CAMERA', label: '相机', hint: '')];
    LocalPackFormStore store() => LocalPackFormStore(PathGuard(tmp.path));

    test('没有文件：用默认值，不建文件', () async {
      final form = await store().read(fallback: fallback, options: options);
      expect(form.appName, '默认名');
      expect(store().file.existsSync(), isFalse);
    });

    test('存了再读：原样回来', () async {
      const form = LocalPackForm(appName: '小店', packageName: 'com.example.shop', versionName: '2.1', versionCode: '7', permissions: {'android.permission.CAMERA'}, customIcon: true);
      await store().write(form);
      final back = await store().read(fallback: fallback, options: options);
      expect((back.appName, back.packageName, back.versionName, back.versionCode, back.customIcon), ('小店', 'com.example.shop', '2.1', '7', true));
      expect(back.permissions, {'android.permission.CAMERA'});
      expect(store().file.parent.listSync().where((e) => e.path.endsWith('.tmp')), isEmpty, reason: '原子写不留临时文件');
    });

    for (final entry in corruptSamples.entries) {
      test('坏文件（${entry.key}）：回到默认值，不崩', () async {
        store().file.parent.createSync(recursive: true);
        store().file.writeAsStringSync(entry.value);
        final form = await store().read(fallback: fallback, options: options);
        expect(form.packageName, 'com.lopicode.app.demo');
        expect(form.permissions, {'android.permission.INTERNET'});
      });
    }

    test('半截的文件：留一份 .bad 备份', () async {
      store().file.parent.createSync(recursive: true);
      store().file.writeAsStringSync(corruptSamples['半截']!);
      await store().read(fallback: fallback, options: options);
      expect(badBackups(store().file), hasLength(1));
    });

    test('字段类型全错：每一项各自回到默认值；版本号存成数字的也认', () async {
      store().file.parent.createSync(recursive: true);
      store().file.writeAsStringSync(jsonEncode({'appName': 5, 'packageName': null, 'versionName': <String>[], 'versionCode': 9, 'permissions': 'x', 'customIcon': 'yes'}));
      final form = await store().read(fallback: fallback, options: options);
      expect((form.appName, form.packageName, form.versionName, form.versionCode, form.customIcon), ('默认名', 'com.lopicode.app.demo', '1.0.0', '9', false));
      expect(form.permissions, {'android.permission.INTERNET'});
      expect(badBackups(store().file), isEmpty);
    });

    test('自己选的图标缺了一张：当没有，用默认图标', () async {
      await store().writeIcons({
        for (final size in kApkIconSizes) size: Uint8List.fromList([1, 2, 3]),
      });
      expect((await store().readIcons()).length, 5);
      File(p.join(store().iconDir.path, '96.png')).deleteSync();
      expect(await store().readIcons(), isEmpty);
      await store().clearIcons();
      expect(store().iconDir.existsSync(), isFalse);
    });
  });

  group('背景图片设置 appearance/background.json', () {
    BackdropStore store() => BackdropStore(p.join(tmp.path, 'appearance'));

    test('没有文件：默认值（没有图、算读完了），不建文件', () async {
      final s = await store().load();
      expect(s.loaded, isTrue);
      expect(s.light.hasImage, isFalse);
      expect(store().settingsFile.existsSync(), isFalse);
    });

    for (final entry in corruptSamples.entries) {
      test('坏内容（${entry.key}）：默认值，不抛异常', () async {
        store().settingsFile
          ..parent.createSync(recursive: true)
          ..writeAsStringSync(entry.value);
        final s = await store().load();
        expect(s.loaded, isTrue);
        expect(s.light.hasImage, isFalse);
      });
    }

    test('半截的文件：留一份 .bad 备份', () async {
      store().settingsFile
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(corruptSamples['半截']!);
      await store().load();
      expect(badBackups(store().settingsFile), hasLength(1));
    });

    test('形状对、字段类型全错 / 越界 / 想指到外面去的文件名：逐项回默认，不算坏文件', () async {
      store().settingsFile
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(
          jsonEncode({
            'enabled': 'yes',
            'light': {
              'file': '../../etc/passwd',
              'width': 100,
              'height': 100,
              'crop': {'l': -3, 't': 'x', 'w': 9, 'h': 0},
              'fit': 42,
              'blur': 9999,
              'maskOpacity': -5,
              'brightness': 'bright',
              'turns': 7,
            },
            'dark': [1, 2, 3],
            'darkSeparate': 1,
            'onChat': null,
            'surfaceOpacity': 3,
          }),
        );
      final s = await store().load();
      expect(s.enabled, isTrue);
      expect(s.light.file, isNull);
      expect(s.light.hasImage, isFalse);
      expect(s.light.crop, CropRect.full);
      expect(s.light.fit, BackdropFit.cover);
      expect(s.light.blur, kBackdropBlurMax);
      expect(s.light.maskOpacity, 0);
      expect(s.light.brightness, 0);
      expect(s.light.turns, 3);
      expect(s.dark.hasImage, isFalse);
      expect(s.darkSeparate, isFalse);
      expect(s.onChat, isTrue);
      expect(s.surfaceOpacity, kBackdropSurfaceMin);
      expect(badBackups(store().settingsFile), isEmpty);
    });

    test('存了再读：原样回来', () async {
      const look = BackdropLook(
        file: 'bg-abc.png',
        width: 800,
        height: 600,
        turns: 1,
        crop: CropRect(0.1, 0.2, 0.3, 0.4),
        fit: BackdropFit.tile,
        tilePercent: 35,
        maskFollowsTheme: false,
        maskColor: 0xFF1B2A4A,
        maskOpacity: 45,
        blur: 12,
        brightness: -20,
      );
      const s = BackdropSettings(enabled: false, light: look, darkSeparate: true, onPages: true, terminal: true, lowcode: true, surfaceOpacity: 70, loaded: true);
      await store().save(s);
      expect(await store().load(), s);
    });
  });

  group('低代码组件盒的“常用” .lopicode/lowcode-editor.json', () {
    File file() => File(p.join(tmp.path, '.lopicode', 'lowcode-editor.json'));

    for (final entry in corruptSamples.entries) {
      test('坏内容（${entry.key}）：当没用过（空表），不抛异常', () async {
        file()
          ..createSync(recursive: true)
          ..writeAsStringSync(entry.value);
        expect(await loadPaletteRecent(PathGuard(tmp.path)), isEmpty);
      });

      test('坏内容（${entry.key}）：图层折叠当没折过，之后存折叠状态照常能存能读', () async {
        file()
          ..createSync(recursive: true)
          ..writeAsStringSync(entry.value);
        final guard = PathGuard(tmp.path);
        expect(await loadLayersCollapsed(guard), isEmpty);
        await saveLayersCollapsed(guard, {'n2'});
        expect(await loadLayersCollapsed(guard), {'n2'});
      });
    }

    test('半截的文件：留一份 .bad 备份；之后照常能存能读', () async {
      file()
        ..createSync(recursive: true)
        ..writeAsStringSync(corruptSamples['半截']!);
      final guard = PathGuard(tmp.path);
      await loadPaletteRecent(guard);
      expect(badBackups(file()), hasLength(1));
      await savePaletteRecent(guard, ['text', 'button']);
      expect(await loadPaletteRecent(guard), ['text', 'button']);
    });

    test('形状对、recent 不是列表：空表，不算坏文件', () async {
      file()
        ..createSync(recursive: true)
        ..writeAsStringSync('{"recent": "text"}');
      expect(await loadPaletteRecent(PathGuard(tmp.path)), isEmpty);
      expect(badBackups(file()), isEmpty);
    });

    test('形状对、layersCollapsed 不是列表 / 里面不是字符串：当没折过，不算坏文件', () async {
      file()
        ..createSync(recursive: true)
        ..writeAsStringSync('{"layersCollapsed": {"n1": true}}');
      expect(await loadLayersCollapsed(PathGuard(tmp.path)), isEmpty);
      file().writeAsStringSync('{"layersCollapsed": [1, null, "n3", ""]}');
      expect(await loadLayersCollapsed(PathGuard(tmp.path)), {'n3'});
      expect(badBackups(file()), isEmpty);
    });
  });

  group('项目里的库 blocks/libs.json 和库的文件夹', () {
    for (final entry in corruptSamples.entries) {
      test('坏内容（${entry.key}）：清单坏了当没有登记、库文件坏了那个库标成用不了，不抛异常；之后照常能新建', () async {
        final guard = PathGuard(tmp.path);
        File('${tmp.path}/blocks/libs.json')
          ..createSync(recursive: true)
          ..writeAsStringSync(entry.value);
        File('${tmp.path}/blocks/tata/bad/lib.json')
          ..createSync(recursive: true)
          ..writeAsStringSync(entry.value);
        final libs = await beLibsRead(guard);
        expect(libs.where((s) => s.ok), isEmpty);
        final made = await beLibCreate(guard, id: 'tata/fine', name: '好的');
        expect(made.problem, isNull);
        expect((await beLibsRead(guard)).map((s) => s.id), contains('tata/fine'));
      });
    }
  });
  group('项目里的组件库 components/libs.json 和库的文件夹', () {
    for (final entry in corruptSamples.entries) {
      test('坏内容（${entry.key}）：登记表坏了当没有登记、库文件坏了那个库标成用不了，不抛异常；之后照常能存新的', () async {
        final guard = PathGuard(tmp.path);
        File('${tmp.path}/components/libs.json')
          ..createSync(recursive: true)
          ..writeAsStringSync(entry.value);
        for (final name in ['lib.json', 'components.json', 'images.json']) {
          File('${tmp.path}/components/tata/bad/$name')
            ..createSync(recursive: true)
            ..writeAsStringSync(entry.value);
        }
        final libs = await compLibsRead(guard);
        expect(libs.where((s) => s.ok), isEmpty);
        File('${tmp.path}/bad.lopilib').writeAsStringSync(entry.value);
        expect((await compLibOpenPack(guard, 'bad.lopilib')).lib.ok, isFalse);
        final good = CompLib(id: 'tata/fine', name: '好的', version: '1.0.0', defs: [LcComponentDef(id: 'c1', name: '组件', root: LcNode(id: 'r', type: 'column'))]);
        expect(await compLibStore(guard, good), isNull);
        expect((await compLibsRead(guard)).where((s) => s.ok).map((s) => s.id), ['tata/fine']);
      });
    }
  });
}
