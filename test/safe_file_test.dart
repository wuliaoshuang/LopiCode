// 存盘健壮性：原子写、坏文件备份后回退默认、各个存盘文件读到损坏 / 旧版本内容不崩。
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/agent/automation.dart';
import 'package:lopicode/agent/model_config.dart';
import 'package:lopicode/agent/team.dart';
import 'package:lopicode/core/crash_log.dart';
import 'package:lopicode/core/project_store.dart';
import 'package:lopicode/core/safe_file.dart';
import 'package:lopicode/core/stores.dart';
import 'package:lopicode/core/templates.dart';
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

      test('团队任务板：${entry.key} → 当空任务板', () async {
        final file = File(p.join(tmp.path, 'team.json'))..writeAsStringSync(entry.value);
        final board = TeamBoard(file: file);
        await board.load();
        expect(board.tasks, isEmpty);
      });
    }

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
  });
}
