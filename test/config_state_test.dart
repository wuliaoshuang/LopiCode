// 配置类状态的完整版（不可变状态 + Notifier）：Agent 预设与个人偏好、技能清单。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/agent/presets.dart';
import 'package:lopicode/agent/skills.dart';
import 'package:lopicode/state/presets_state.dart';
import 'package:lopicode/state/skills_state.dart';
import 'package:path/path.dart' as p;
import 'package:riverpod/riverpod.dart';

import 'support/harness.dart';

void main() {
  late TestEnv env;
  late ProviderContainer box;

  setUp(() async {
    env = await TestEnv.create();
    box = env.services.container;
  });
  tearDown(() => env.dispose());

  group('预设与个人偏好', () {
    PresetsState now() => box.read(presetsProvider);
    PresetsNotifier edit() => box.read(presetsProvider.notifier);

    test('一开始只有标准模式；新建、改、复制、设默认、删：每次都是一份新快照，旧快照不变', () async {
      final first = now();
      expect(first.all.single.id, PresetStore.standardId);
      expect(first.defaultPreset.builtIn, isTrue);

      final review = await edit().upsert(name: '审查', prompt: '只看不改', tools: {'read_file', 'list_files'});
      expect(first.custom, isEmpty, reason: '旧快照没被改');
      expect(now().custom.single.name, '审查');

      final renamed = await edit().upsert(id: review.id, name: '代码审查', prompt: '只看不改', tools: {'read_file'});
      expect(renamed.id, review.id);
      expect(review.name, '审查', reason: '旧对象没被改');
      expect(review.tools, {'read_file', 'list_files'});
      expect(now().custom.single.name, '代码审查');

      await edit().copy(renamed);
      expect(now().custom.map((e) => e.name), ['代码审查', '代码审查 副本']);
      await edit().setDefault(review.id);
      expect(now().defaultPreset.name, '代码审查');
      await edit().delete(review.id);
      expect(now().custom.map((e) => e.name), ['代码审查 副本']);
      expect(now().defaultId, PresetStore.standardId, reason: '默认的那个被删了就回到标准模式');
      expect(now().byId('不存在').id, PresetStore.standardId);
    });

    test('快照和预设都改不了：列表、工具集合都是只读的', () async {
      final made = await edit().upsert(name: '只读', prompt: '', tools: {'read_file'});
      expect(() => now().custom.add(made), throwsUnsupportedError);
      expect(() => now().all.clear(), throwsUnsupportedError);
      expect(() => made.tools!.add('run_command'), throwsUnsupportedError);
      expect(() => now().custom.single.tools!.add('run_command'), throwsUnsupportedError);
    });

    test('个人偏好：保存去掉首尾空白，清空就是没有；不经过 Notifier 直接改设置文件也跟着变', () async {
      await edit().setPreferences('  说中文  ');
      expect(now().preferences, '说中文');
      await edit().setPreferences('   ');
      expect(now().preferences, '');
      await env.services.settings.set(PresetStore.kPreferences, '别处写进来的');
      expect(now().preferences, '别处写进来的');
    });

    test('只在预设相关的设置变了才通知', () async {
      var n = 0;
      box.listen(presetsProvider, (_, _) => n++);
      await env.services.settings.set('demo.other', 1);
      box.read(presetsProvider);
      expect(n, 0);
      await edit().setPreferences('说中文');
      box.read(presetsProvider);
      expect(n, 1);
    });
  });

  group('技能清单', () {
    late String ws;
    setUp(() {
      ws = p.join(env.tmp.path, 'ws');
      Directory(ws).createSync();
    });

    Future<SkillsState> settled(String? dir) async {
      for (var i = 0; i < 200; i++) {
        final s = box.read(skillsProvider(dir));
        if (s.loaded) return s;
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      fail('技能清单一直没扫描完');
    }

    Future<SkillsState> until(String? dir, bool Function(SkillsState s) ok) async {
      for (var i = 0; i < 200; i++) {
        final s = box.read(skillsProvider(dir));
        if (s.loaded && ok(s)) return s;
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      fail('技能清单没有变成预期的样子');
    }

    test('扫描完之前是“还没读出来”；新建、关掉、删除之后自己重新扫描', () async {
      final sub = box.listen(skillsProvider(ws), (_, _) {});
      addTearDown(sub.close);
      expect(box.read(skillsProvider(ws)).loaded, isFalse);
      expect((await settled(ws)).skills, isEmpty);

      final edit = box.read(skillsProvider(ws).notifier);
      await edit.create(name: '发版流程', description: '发版前要做的事', body: '先跑测试', global: false);
      await edit.create(name: '写周报', description: '', body: '按模板', global: true);
      var s = await until(ws, (s) => s.skills!.length == 2);
      expect(s.ofWorkspace.single.name, '发版流程');
      expect(s.global.single.name, '写周报');
      expect(() => s.skills!.clear(), throwsUnsupportedError);

      await edit.setEnabled(s.global.single, false);
      s = await until(ws, (s) => !s.global.single.enabled);
      expect(s.ofWorkspace.single.enabled, isTrue);

      await edit.delete(s.ofWorkspace.single);
      s = await until(ws, (s) => s.skills!.length == 1);
      expect(s.ofWorkspace, isEmpty);
    });

    test('名字不合规照样报错（校验没被绕过）', () async {
      final sub = box.listen(skillsProvider(null), (_, _) {});
      addTearDown(sub.close);
      final edit = box.read(skillsProvider(null).notifier);
      await expectLater(edit.create(name: 'a/b', description: '', body: '', global: true), throwsA(isA<SkillException>()));
      await edit.create(name: '同名', description: '', body: '', global: true);
      await expectLater(edit.create(name: '同名', description: '', body: '', global: true), throwsA(isA<SkillException>()));
    });

    test('只看全局的那份看不到工作区的技能；两份互不串', () async {
      final a = box.listen(skillsProvider(ws), (_, _) {});
      final b = box.listen(skillsProvider(null), (_, _) {});
      addTearDown(a.close);
      addTearDown(b.close);
      await box.read(skillsProvider(ws).notifier).create(name: '只属于这个工作区', description: '', body: '', global: false);
      expect((await until(ws, (s) => s.skills!.isNotEmpty)).ofWorkspace.single.name, '只属于这个工作区');
      expect((await settled(null)).skills, isEmpty);
    });

    test('没人看了就释放；过期的扫描结果回来也不会写进已经释放的状态', () async {
      final sub = box.listen(skillsProvider(ws), (_, _) {});
      box.read(skillsProvider(ws)); // 扫描已经发出去
      sub.close();
      await Future<void>.delayed(const Duration(milliseconds: 100)); // 结果回来时状态已释放：不能抛错
      final again = box.listen(skillsProvider(ws), (_, _) {});
      addTearDown(again.close);
      expect((await settled(ws)).skills, isEmpty);
    });
  });
}
