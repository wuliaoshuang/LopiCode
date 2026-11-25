// 技能附带的脚本：认脚本、挂进 Ubuntu 的 /skills（挂副本）、告诉模型路径、设置页显示“带 N 个脚本”。
//   LOPI_SHOTS=1 flutter test test/skill_scripts_test.dart   # 同时写截图到 docs/screenshots/
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/agent/agent_tools.dart';
import 'package:lopicode/agent/command_runner.dart';
import 'package:lopicode/agent/skill_mirror.dart';
import 'package:lopicode/agent/skill_scripts.dart';
import 'package:lopicode/agent/skills.dart';
import 'package:lopicode/core/project_store.dart';
import 'package:lopicode/core/stores.dart';
import 'package:lopicode/core/templates.dart';
import 'package:lopicode/runtime/linux_command_runner.dart';
import 'package:lopicode/runtime/linux_runtime.dart';
import 'package:lopicode/runtime/proot_command.dart';
import 'package:lopicode/ui/settings_skills.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;

import 'screens_test.dart' show shot, fontsLoaded;
import 'support/harness.dart';
import 'support/run_fakes.dart';
import 'support/runtime_fakes.dart';

/// 参数里所有 `-b` 后面跟的值。
List<String> bindsOf(List<String> args) => [
  for (var i = 0; i + 1 < args.length; i++)
    if (args[i] == '-b') args[i + 1],
];

void put(String dir, String rel, String text) => File(p.joinAll([dir, ...rel.split('/')]))
  ..parent.createSync(recursive: true)
  ..writeAsStringSync(text);

void main() {
  late Directory tmp;
  late SettingsStore settings;
  late SkillStore skills;
  late String ws;

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('lopi_skill_');
    settings = SettingsStore(File(p.join(tmp.path, 'settings.json')));
    await settings.load();
    skills = SkillStore(settings, p.join(tmp.path, 'global skills 全局'));
    ws = p.join(tmp.path, '我的 项目');
    Directory(ws).createSync();
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  Future<String> make(String name, {String? workspaceDir, Map<String, String> files = const {}}) async {
    await skills.create(name: name, description: '$name 的说明', body: '照着做', workspaceDir: workspaceDir);
    final dir = p.join(workspaceDir == null ? skills.globalDir : SkillStore.workspaceSkillsDir(workspaceDir), name);
    files.forEach((rel, text) => put(dir, rel, text));
    return dir;
  }

  group('认脚本', () {
    test('按扩展名认；没有扩展名的看开头是不是 #!；SKILL.md、点开头的不算；排好序', () async {
      final dir = await make(
        '发版',
        files: {'scripts/build.sh': 'echo hi', 'check.py': 'print(1)', 'run': '#!/bin/sh\necho hi', 'LICENSE': 'MIT', 'data/table.csv': 'a,b', '.git/hooks/pre-commit.sh': 'x', '.hidden.sh': 'x'},
      );
      final f = scanSkillFilesSync(dir);
      expect(f.scripts, ['check.py', 'run', 'scripts/build.sh']);
      expect(f.others, ['LICENSE', 'data/table.csv']);
      expect(f.tooBig, isFalse);
      expect(f.hasExtras, isTrue);
    });

    test('目录不存在 / 只有 SKILL.md：什么都没有，不报错', () async {
      expect(scanSkillFilesSync(p.join(tmp.path, '没有')).hasExtras, isFalse);
      expect(scanSkillFilesSync(await make('空')).hasExtras, isFalse);
    });

    test('不跟符号链接：链到技能目录外面的文件、目录都不带进来', () async {
      final outside = Directory(p.join(tmp.path, 'outside'))..createSync();
      put(outside.path, 'secret.sh', 'echo secret');
      final dir = await make('链', files: {'ok.sh': 'echo ok'});
      Link(p.join(dir, 'link.sh')).createSync(p.join(outside.path, 'secret.sh'));
      Link(p.join(dir, 'linkdir')).createSync(outside.path);
      expect(scanSkillFilesSync(dir).scripts, ['ok.sh']);
      expect(scanSkillFilesSync(dir).others, isEmpty);
    });

    test('文件太多 / 太大：标成超限', () async {
      final many = await make('多', files: {for (var i = 0; i <= kSkillMaxFiles; i++) 'f$i.txt': 'x'});
      expect(scanSkillFilesSync(many).tooBig, isTrue);
      final big = await make('大');
      File(p.join(big, 'big.bin')).writeAsBytesSync(List.filled(kSkillMaxBytes + 1, 0));
      expect(scanSkillFilesSync(big).tooBig, isTrue);
    });

    test('技能清单带上脚本数；提示词里带脚本的多一句“带 N 个脚本”', () async {
      await make('发版', files: {'a.sh': 'x', 'b.py': 'x', 'notes.txt': 'x'});
      await make('写周报');
      final on = await skills.enabled();
      expect(on.firstWhere((s) => s.name == '发版').scripts, ['a.sh', 'b.py']);
      expect(on.firstWhere((s) => s.name == '写周报').scripts, isEmpty);
      final section = SkillStore.promptSection(on);
      expect(section, contains('- 发版：发版 的说明（带 2 个脚本）'));
      expect(section.split('\n'), contains('- 写周报：写周报 的说明'));
    });
  });

  group('怎么跑、说明怎么写', () {
    test('shell 引号：空格、中文、单引号都不会被拆开', () {
      expect(shellQuote('/skills/发 版/a b.sh'), "'/skills/发 版/a b.sh'");
      expect(shellQuote("it's"), r"'it'\''s'");
    });

    test('按扩展名选解释器（不靠执行权限）', () {
      expect(scriptRunCommand('/skills/x/a.sh'), "bash '/skills/x/a.sh'");
      expect(scriptRunCommand('/skills/x/a.py'), "python3 '/skills/x/a.py'");
      expect(scriptRunCommand('/skills/x/a.mjs'), "node '/skills/x/a.mjs'");
      expect(scriptRunCommand('/skills/x/run'), "bash '/skills/x/run'");
    });

    const files = SkillFiles(scripts: ['build.sh', 'tools/check.py']);

    test('在 Ubuntu 里：给出 /skills/<名字>/… 的路径，说明用 run_command、要确认、是副本', () {
      final note = skillScriptNote(name: '发 版', hostDir: '/data/skills/发 版', files: files, env: const SkillScriptsInGuest('/skills'));
      expect(note, contains('- /skills/发 版/build.sh'));
      expect(note, contains('- /skills/发 版/tools/check.py'));
      expect(note, contains("run_command 跑，例如：bash '/skills/发 版/build.sh'"));
      expect(note, contains('要用户确认'));
      expect(note, contains('副本'));
      expect(note, isNot(contains('/data/skills')), reason: '不把手机上的真实路径给模型');
    });

    test('运行环境没装好：说明脚本跑不了，不给路径', () {
      final note = skillScriptNote(name: '发版', hostDir: '/data/skills/发版', files: files, env: const SkillScriptsUnavailable());
      expect(note, contains('现在跑不了'));
      expect(note, contains('build.sh'));
      expect(note, isNot(contains('/skills/')));
      expect(note, isNot(contains('/data/skills')));
    });

    test('命令在本机跑（桌面调试）：给技能自己的目录', () {
      final note = skillScriptNote(name: '发版', hostDir: '/data/skills/发版', files: files, env: const SkillScriptsOnHost());
      expect(note, contains('- /data/skills/发版/build.sh'));
      expect(note, contains('要用户确认'));
    });

    test('没有脚本：不加说明；超限：说明没放进环境；脚本很多：只列前 $kSkillNoteMaxScripts 个', () {
      expect(skillScriptNote(name: 'a', hostDir: '/x', files: SkillFiles.none, env: const SkillScriptsInGuest('/skills')), isEmpty);
      expect(
        skillScriptNote(
          name: 'a',
          hostDir: '/x',
          files: const SkillFiles(others: ['a.txt']),
          env: const SkillScriptsInGuest('/skills'),
        ),
        isEmpty,
      );
      expect(skillScriptNote(name: 'a', hostDir: '/x', files: const SkillFiles(tooBig: true), env: const SkillScriptsInGuest('/skills')), contains('没有放进运行环境'));
      final lots = SkillFiles(scripts: [for (var i = 0; i < 30; i++) 's${i.toString().padLeft(2, '0')}.sh']);
      final note = skillScriptNote(name: 'a', hostDir: '/x', files: lots, env: const SkillScriptsInGuest('/skills'));
      expect(note, contains('带 30 个脚本'));
      expect(note, contains('/skills/a/s19.sh'));
      expect(note, isNot(contains('/skills/a/s20.sh')));
      expect(note, contains('还有 10 个'));
    });
  });

  group('技能镜像（挂进去的是副本）', () {
    late SkillMirror mirror;
    setUp(() => mirror = SkillMirror(skills, p.join(tmp.path, 'runtime', 'skills-mirror')));

    test('没有技能目录 / 目录是空的 / 技能都不带文件：不挂、不报错，也不留空目录', () async {
      expect(mirror.sync(null), isNull);
      expect(mirror.sync(ws), isNull);
      Directory(skills.globalDir).createSync(recursive: true);
      Directory(SkillStore.workspaceSkillsDir(ws)).createSync(recursive: true);
      expect(mirror.sync(ws), isNull);
      await make('只有文字');
      expect(mirror.sync(ws), isNull);
      expect(Directory(mirror.rootDir).existsSync() && Directory(mirror.rootDir).listSync().isNotEmpty, isFalse);
    });

    test('带文件的技能整份复制过去（含 SKILL.md、子目录）；原件不动', () async {
      // 应用里建的技能名不许带空格，但用户自己放进去的文件夹可能带：照样能挂。
      final src = p.join(skills.globalDir, '发 版');
      put(src, 'SKILL.md', '---\nname: 发 版\ndescription: x\n---\n照着做');
      put(src, 'scripts/build.sh', 'echo 打包');
      put(src, 'data.csv', 'a,b');
      final dir = mirror.sync(null)!;
      expect(p.isWithin(mirror.rootDir, dir), isTrue);
      expect(File(p.join(dir, '发 版', 'scripts', 'build.sh')).readAsStringSync(), 'echo 打包');
      expect(File(p.join(dir, '发 版', 'data.csv')).readAsStringSync(), 'a,b');
      expect(File(p.join(dir, '发 版', 'SKILL.md')).readAsStringSync(), File(p.join(src, 'SKILL.md')).readAsStringSync());
    });

    test('镜像里被改、被删、多出来的东西，下次对齐时复原；原件始终没变', () async {
      final src = await make('发版', files: {'build.sh': 'echo ok', 'lib/util.py': 'x = 1'});
      final dir = mirror.sync(null)!;
      // 模拟上一条命令在 /skills 里乱动
      File(p.join(dir, '发版', 'build.sh')).writeAsStringSync('rm -rf /');
      File(p.join(dir, '发版', 'lib', 'util.py')).deleteSync();
      put(dir, '发版/evil.sh', 'x');
      put(dir, '别的技能/SKILL.md', 'x');
      put(dir, 'loose.txt', 'x');
      Link(p.join(dir, '发版', 'link')).createSync(src);
      expect(mirror.sync(null), dir);
      expect(File(p.join(dir, '发版', 'build.sh')).readAsStringSync(), 'echo ok');
      expect(File(p.join(dir, '发版', 'lib', 'util.py')).readAsStringSync(), 'x = 1');
      expect(File(p.join(dir, '发版', 'evil.sh')).existsSync(), isFalse);
      expect(Directory(p.join(dir, '别的技能')).existsSync(), isFalse);
      expect(File(p.join(dir, 'loose.txt')).existsSync(), isFalse);
      expect(Link(p.join(dir, '发版', 'link')).existsSync(), isFalse);
      // 原件一个字没变（删链接没有顺着删到原目录）
      expect(File(p.join(src, 'build.sh')).readAsStringSync(), 'echo ok');
      expect(File(p.join(src, 'lib', 'util.py')).readAsStringSync(), 'x = 1');
      expect(File(p.join(src, 'SKILL.md')).existsSync(), isTrue);
    });

    test('原件改了，镜像跟着变；内容没变的文件不重写', () async {
      final src = await make('发版', files: {'a.sh': 'v1', 'b.sh': 'same'});
      final dir = mirror.sync(null)!;
      final b = File(p.join(dir, '发版', 'b.sh'));
      final stamp = DateTime(2020);
      b.setLastModifiedSync(stamp);
      File(p.join(src, 'a.sh')).writeAsStringSync('v2');
      mirror.sync(null);
      expect(File(p.join(dir, '发版', 'a.sh')).readAsStringSync(), 'v2');
      expect(b.lastModifiedSync(), stamp, reason: '没变的不重写');
    });

    test('关掉的、删掉的技能从镜像里撤走；全没了镜像目录也清掉', () async {
      await make('甲', files: {'a.sh': 'x'});
      await make('乙', files: {'b.sh': 'x'});
      final dir = mirror.sync(null)!;
      expect(Directory(dir).listSync().map((e) => p.basename(e.path)), unorderedEquals(['甲', '乙']));
      final all = await skills.list();
      await skills.setEnabled(all.firstWhere((s) => s.name == '甲'), false);
      mirror.sync(null);
      expect(Directory(dir).listSync().map((e) => p.basename(e.path)), ['乙']);
      await skills.delete(all.firstWhere((s) => s.name == '乙'));
      expect(mirror.sync(null), isNull);
      expect(Directory(dir).existsSync(), isFalse);
    });

    test('同名时用工作区那份；工作区那份关掉了就用全局的；不同工作区各有各的镜像', () async {
      await make('发版', files: {'a.sh': 'global'});
      await make('发版', workspaceDir: ws, files: {'a.sh': 'workspace'});
      final dir = mirror.sync(ws)!;
      expect(File(p.join(dir, '发版', 'a.sh')).readAsStringSync(), 'workspace');
      final other = mirror.sync(null)!;
      expect(other, isNot(dir));
      expect(File(p.join(other, '发版', 'a.sh')).readAsStringSync(), 'global');
      final wsSkill = (await skills.list(workspaceDir: ws)).firstWhere((s) => !s.global);
      await skills.setEnabled(wsSkill, false);
      mirror.sync(ws);
      expect(File(p.join(dir, '发版', 'a.sh')).readAsStringSync(), 'global');
    });

    test('超限的技能不放进镜像；技能里的符号链接不带进去', () async {
      await make('多', files: {for (var i = 0; i <= kSkillMaxFiles; i++) 'f$i.sh': 'x'});
      expect(mirror.sync(null), isNull);
      final outside = Directory(p.join(tmp.path, 'outside'))..createSync();
      put(outside.path, 'secret.txt', 'secret');
      final src = await make('链', files: {'ok.sh': 'x'});
      Link(p.join(src, 'leak')).createSync(outside.path);
      final dir = mirror.sync(null)!;
      expect(Directory(dir).listSync().map((e) => p.basename(e.path)), ['链']);
      expect(FileSystemEntity.typeSync(p.join(dir, '链', 'leak'), followLinks: false), FileSystemEntityType.notFound);
      expect(File(p.join(dir, '链', 'ok.sh')).existsSync(), isTrue);
    });
  });

  group('PRoot 绑定参数', () {
    ProotCommand build({List<(String, String)> extra = const []}) =>
        buildProotCommand(nativeLibDir: '/n', libDir: '/l', rootfs: '/r', tmpDir: '/t', guestCommand: guestRun('echo hi'), projectDir: '/p', extraBinds: extra);

    test('不给额外目录：参数和原来一模一样，没有 /skills', () {
      final plain = buildProotCommand(nativeLibDir: '/n', libDir: '/l', rootfs: '/r', tmpDir: '/t', guestCommand: guestRun('echo hi'), projectDir: '/p');
      expect(build().arguments, plain.arguments);
      expect(bindsOf(plain.arguments).where((b) => b.endsWith(':/skills')), isEmpty);
    });

    test('给了：多一组 -b 主机路径:/skills，排在环境里要跑的命令之前；路径带空格和中文是完整的一个参数', () {
      const host = '/data/user/0/app 文件/运行 环境/skills-mirror/ws-1';
      final args = build(extra: [(host, '/skills')]).arguments;
      expect(bindsOf(args), contains('$host:/skills'));
      expect(args.indexOf('$host:/skills'), lessThan(args.indexOf('/usr/bin/env')));
      expect(args.where((a) => a.contains('skills-mirror')), hasLength(1), reason: '没有被拆成几段');
      expect(bindsOf(args), contains('/p:/workspace'), reason: '项目照旧挂在 /workspace');
      // 除了多出来的这一组，其余参数原样
      final rest = [...args]..removeRange(args.indexOf('$host:/skills') - 1, args.indexOf('$host:/skills') + 1);
      expect(rest, build().arguments);
    });

    group('LinuxRuntime', () {
      late LinuxRuntime runtime;
      setUp(() async {
        runtime = LinuxRuntime(
          settings: settings,
          baseDir: p.join(tmp.path, '运行 环境'),
          host: FakeRuntimeHost(nativeDir: makeFakeNativeDir(tmp)),
        );
        markInstalled(runtime);
        await runtime.init();
      });
      List<String> skillBinds(String? project) => bindsOf(runtime.prootCommand(guestCommand: guestLoginShell, projectDir: project).arguments).where((b) => b.endsWith(':/skills')).toList();

      test('没接技能镜像 / 没有技能目录 / 技能目录是空的：不绑定', () {
        expect(skillBinds(ws), isEmpty);
        runtime.skillsMirror = SkillMirror(skills, p.join(runtime.baseDir, 'skills-mirror')).sync;
        expect(skillBinds(ws), isEmpty);
        expect(skillBinds(null), isEmpty);
        Directory(skills.globalDir).createSync(recursive: true);
        expect(skillBinds(ws), isEmpty);
      });

      test('有带脚本的技能：绑定镜像目录（不是原目录）到 /skills；路径带空格和中文', () async {
        final src = await make('发版', workspaceDir: ws, files: {'build.sh': 'echo ok'});
        runtime.skillsMirror = SkillMirror(skills, p.join(runtime.baseDir, 'skills-mirror')).sync;
        final binds = skillBinds(ws);
        expect(binds, hasLength(1));
        final host = binds.single.substring(0, binds.single.length - ':/skills'.length);
        expect(host, contains('运行 环境'));
        expect(p.isWithin(p.join(runtime.baseDir, 'skills-mirror'), host), isTrue);
        expect(p.isWithin(ws, host) || p.isWithin(skills.globalDir, host), isFalse, reason: '挂的是副本');
        expect(File(p.join(host, '发版', 'build.sh')).readAsStringSync(), 'echo ok');
        expect(Directory(p.join(runtime.rootfsDir, 'skills')).existsSync(), isTrue, reason: '挂载点建好了');
        // 别的工作区没有技能：不绑定
        expect(skillBinds(p.join(tmp.path, 'other')), isEmpty);
        // 原件在环境外面：镜像被改了下一次进环境前复原
        File(p.join(host, '发版', 'build.sh')).writeAsStringSync('bad');
        skillBinds(ws);
        expect(File(p.join(host, '发版', 'build.sh')).readAsStringSync(), 'echo ok');
        expect(File(p.join(src, 'build.sh')).readAsStringSync(), 'echo ok');
      });

      test('镜像出错（返回的路径带冒号会被 PRoot 拆错）：不绑定，命令照常', () {
        runtime.skillsMirror = (_) => '/a:b/skills';
        expect(skillBinds(ws), isEmpty);
      });
    });
  });

  group('接到 Agent 上', () {
    test('装好运行环境：read_skill 的结果里是 /skills/<名字>/…，并且真的绑定了', () async {
      final env = await RunEnv.create();
      addTearDown(env.dispose);
      final project = await env.services.projects.create('小站', ProjectTemplate.web);
      await env.services.skills.create(name: '发版', description: '发版时用', body: '先打包');
      put(p.join(env.services.skills.globalDir, '发版'), 'build.sh', 'echo ok');
      final runner = LinuxCommandRunner(env.runtime);
      final on = await env.services.skills.enabled(workspaceDir: project.dir);
      final tool = env.services.skills.tool(on, scriptEnv: () => skillScriptEnvOf(runner, project.dir))!;
      expect(tool.kind, ToolKind.read, reason: '读技能还是只读工具；跑脚本走 run_command');
      final text = (await tool.run({'name': '发版'})).text;
      expect(text, contains('先打包'));
      expect(text, contains('- /skills/发版/build.sh'));
      expect(text, contains("bash '/skills/发版/build.sh'"));
      expect(text, isNot(contains(env.services.skills.globalDir)));
      final binds = bindsOf(env.runtime.prootCommand(guestCommand: guestLoginShell, projectDir: project.dir).arguments);
      expect(binds.where((b) => b.endsWith(':/skills')), hasLength(1));
    });

    test('没装运行环境：技能照旧是文字，说明里写脚本跑不了', () async {
      final env = await RunEnv.create(installed: false);
      addTearDown(env.dispose);
      final project = await env.services.projects.create('小站', ProjectTemplate.web);
      await env.services.skills.create(name: '发版', description: '发版时用', body: '先打包');
      put(p.join(env.services.skills.globalDir, '发版'), 'build.sh', 'echo ok');
      final runner = LinuxCommandRunner(env.runtime);
      expect(runner, isA<HasCommandAvailability>());
      expect(skillScriptEnvOf(runner, project.dir), isA<SkillScriptsUnavailable>());
      final on = await env.services.skills.enabled(workspaceDir: project.dir);
      final text = (await env.services.skills.tool(on, scriptEnv: () => skillScriptEnvOf(runner, project.dir))!.run({'name': '发版'})).text;
      expect(text, contains('先打包'));
      expect(text, contains('现在跑不了'));
      expect(text, isNot(contains('/skills/发版')));
    });

    test('桌面（命令在本机跑）：给技能自己的目录；不带脚本的技能不加说明', () async {
      final env = await RunEnv.create(android: false, installed: false, proot: false);
      addTearDown(env.dispose);
      final project = await env.services.projects.create('小站', ProjectTemplate.web);
      await env.services.skills.create(name: '发版', description: '发版时用', body: '先打包');
      await env.services.skills.create(name: '写周报', description: '周五用', body: '按项目列');
      final dir = p.join(env.services.skills.globalDir, '发版');
      put(dir, 'build.sh', 'echo ok');
      final runner = LinuxCommandRunner(env.runtime);
      expect(skillScriptEnvOf(runner, project.dir), isA<SkillScriptsOnHost>());
      final on = await env.services.skills.enabled(workspaceDir: project.dir);
      final tool = env.services.skills.tool(on, scriptEnv: () => skillScriptEnvOf(runner, project.dir))!;
      expect((await tool.run({'name': '发版'})).text, contains('- ${dir.split(p.separator).join('/')}/build.sh'));
      expect((await tool.run({'name': '写周报'})).text, isNot(contains('附带脚本')));
    });
  });

  group('设置 › 技能', () {
    setUpAll(() async => fontsLoaded = await loadRealFonts());
    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      final suffix = mode == ThemeMode.light ? 'light' : 'dark';
      testWidgets('清单里带脚本的技能多一行“带 N 个脚本”；全文页有〔附带的脚本〕 ($suffix)', (tester) async {
        usePhoneViewport(tester);
        late TestEnv env;
        late Project project;
        await tester.runAsync(() async {
          env = await TestEnv.create();
          project = await env.services.projects.create('我的小站', ProjectTemplate.web);
          await env.services.skills.create(name: '发版流程', description: '要打包发布时用', body: '1. 跑测试\n2. 打包');
          final dir = p.join(env.services.skills.globalDir, '发版流程');
          put(dir, 'scripts/build.sh', 'echo build');
          put(dir, 'scripts/upload.py', 'print(1)');
          put(dir, 'notes.txt', 'x');
          await env.services.skills.create(name: '写周报', description: '周五写周报时用', body: '按项目列进展', workspaceDir: project.dir);
        });
        addTearDown(() => env.dispose());
        await tester.pumpWidget(
          appFor(
            env,
            SkillsScreen(workspace: project),
            mode: mode,
            font: kTestFont,
          ),
        );
        await settle(tester, rounds: 60);
        expect(find.textContaining('带 2 个脚本'), findsOneWidget);
        expect(find.textContaining('要打包发布时用'), findsOneWidget);
        expect(find.textContaining('周五写周报时用'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await shot(tester, '85-skills-scripts-$suffix');

        late Skill skill;
        await tester.runAsync(() async => skill = (await env.services.skills.list(workspaceDir: project.dir)).firstWhere((s) => s.name == '发版流程'));
        await tester.pumpWidget(
          appFor(
            env,
            SkillViewScreen(key: UniqueKey(), skill: skill),
            mode: mode,
            font: kTestFont,
          ),
        );
        await settle(tester, rounds: 20);
        expect(find.byKey(const Key('skill-scripts')), findsOneWidget);
        expect(find.text('附带的脚本（2 个）'), findsOneWidget);
        expect(find.text('scripts/build.sh'), findsOneWidget);
        expect(find.text('scripts/upload.py'), findsOneWidget);
        expect(find.text('notes.txt'), findsNothing);
        expect(find.textContaining('每次要你确认'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await shot(tester, '86-skill-view-scripts-$suffix');

        // 不带脚本的技能：没有这一组
        await tester.runAsync(() async => skill = (await env.services.skills.list(workspaceDir: project.dir)).firstWhere((s) => s.name == '写周报'));
        await tester.pumpWidget(
          appFor(
            env,
            SkillViewScreen(key: UniqueKey(), skill: skill),
            mode: mode,
            font: kTestFont,
          ),
        );
        await settle(tester, rounds: 20);
        expect(find.byKey(const Key('skill-scripts')), findsNothing);
      });
    }
  });
}
