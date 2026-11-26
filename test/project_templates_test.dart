// 模板目录与各模板生成的文件：
// - 目录分组、id 稳定（旧的三个 id 继续有效，不认识的 id 回退成空项目）、图标找得到；
// - 每个模板 × 每种语言：文件齐全、JSON 能解析、backend.lc.json 校验零问题、生成的代码过语法检查（node --check / py_compile，工具在才跑）；
// - 后端积木的入门样本真的起服务跑一遍（Node.js、Python；只连 127.0.0.1 的随机端口，没有工具就跳过）；
// - 建项目：文件落盘、project.json 记下模板和语言、坏路径不建项目。
@Timeout(Duration(minutes: 10))
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/backend/backend_model.dart';
import 'package:lopicode/backend/backend_project.dart';
import 'package:lopicode/backend/backend_readme.dart';
import 'package:lopicode/backend/backend_targets.dart';
import 'package:lopicode/backend/backend_templates.dart';
import 'package:lopicode/backend/backend_validate.dart';
import 'package:lopicode/core/file_icons.dart';
import 'package:lopicode/core/path_guard.dart';
import 'package:lopicode/core/project_store.dart';
import 'package:lopicode/core/safe_file.dart';
import 'package:lopicode/core/templates.dart';
import 'package:lopicode/lang/rules.dart';
import 'package:lopicode/lowcode/logic_model.dart';
import 'package:lopicode/templates/code_starters.dart';
import 'package:lopicode/templates/project_templates.dart';
import 'package:path/path.dart' as p;

import 'support/starter_servers.dart';

const Map<String, List<String>> _syntaxChecks = {
  '.js': ['node', '--check'],
  '.py': ['python3', '-m', 'py_compile'],
};

/// 对一组文件里认识的代码文件做语法检查；返回检查了几个。工具不在就不查。
Future<int> _checkSyntax(Map<String, String> files, String label) async {
  var checked = 0;
  final dir = writeTempProject(files, 'lopi_tpl_syntax_');
  try {
    for (final path in files.keys) {
      final cmd = _syntaxChecks[p.extension(path)];
      if (cmd == null || !await toolExists(cmd.first)) continue;
      final r = await Process.run(cmd.first, [...cmd.sublist(1), p.join(dir.path, path)], workingDirectory: dir.path);
      expect(r.exitCode, 0, reason: '[$label] $path 语法检查没过：\n${r.stdout}\n${r.stderr}');
      checked++;
    }
  } finally {
    dir.deleteSync(recursive: true);
  }
  return checked;
}

Set<String> _ops(BeDocument doc) {
  final out = <String>{};
  for (final r in doc.routes) {
    r.visitBlocks((b, _) => out.add(b.op));
  }
  return out;
}

void main() {
  group('模板目录', () {
    test('旧的三个 id 继续有效；不认识的 id、没有 id 回退成空项目', () {
      expect(ProjectTemplate.byId('empty'), ProjectTemplate.empty);
      expect(ProjectTemplate.byId('web'), ProjectTemplate.web);
      expect(ProjectTemplate.byId('lowcode'), ProjectTemplate.lowcode);
      expect(ProjectTemplate.byId('backend-blocks'), ProjectTemplate.backendBlocks);
      expect(ProjectTemplate.byId('backend-code'), ProjectTemplate.backendCode);
      expect(ProjectTemplate.byId('fullstack'), ProjectTemplate.fullstack);
      expect(ProjectTemplate.byId('以后才有的模板'), ProjectTemplate.empty);
      expect(ProjectTemplate.byId(null), ProjectTemplate.empty);
    });

    test('分组：每组都有模板，每个模板恰好在一组里；id 不重复；名字和说明不空', () {
      expect(TemplateGroup.values.map((g) => g.label), ['空白', '前端', '后端 · 积木', '后端 · 代码', '全栈']);
      final seen = <ProjectTemplate>[];
      for (final g in TemplateGroup.values) {
        final list = ProjectTemplate.inGroup(g);
        expect(list, isNotEmpty, reason: '${g.label} 这一组是空的');
        seen.addAll(list);
      }
      expect(seen.toSet(), ProjectTemplate.values.toSet());
      expect(seen.length, ProjectTemplate.values.length);
      expect({for (final t in ProjectTemplate.values) t.id}.length, ProjectTemplate.values.length);
      for (final t in ProjectTemplate.values) {
        expect(t.label.trim(), isNotEmpty);
        expect(t.description.trim(), isNotEmpty);
        expect(RegExp(r'^[a-z][a-z0-9-]*$').hasMatch(t.id), isTrue, reason: t.id);
      }
      expect(ProjectTemplate.inGroup(TemplateGroup.frontend), [ProjectTemplate.web, ProjectTemplate.lowcode]);
    });

    test('图标：每个模板、每种可选语言都有随包的图标（不是默认的白纸）', () {
      final fallback = languageIconFor('没有这种语言');
      for (final t in ProjectTemplate.values) {
        expect(languageIconFor(t.icon), isNot(fallback), reason: '${t.id} 的图标 ${t.icon} 找不到');
        expect(languageIconFor(t.icon, light: true), isNot(languageIconFor('没有这种语言', light: true)));
        for (final l in templateLanguages(t)) {
          expect(languageIconFor(l.id), isNot(fallback), reason: '${t.id} 的语言 ${l.id} 没有图标');
        }
      }
    });

    test('要选语言的模板：后端积木 / 全栈取现有的生成器，代码模板取起步工程；别的不用选', () {
      expect(templateLanguages(ProjectTemplate.empty), isEmpty);
      expect(templateLanguages(ProjectTemplate.web), isEmpty);
      expect(templateLanguages(ProjectTemplate.lowcode), isEmpty);
      for (final t in [ProjectTemplate.backendBlocks, ProjectTemplate.fullstack]) {
        final langs = templateLanguages(t);
        expect([for (final l in langs) l.id], [for (final b in backendTargets) b.id], reason: '别人注册了新语言，这里要自动出现');
        expect([for (final l in langs) l.verified], [for (final b in backendTargets) b.verified]);
        expect([for (final l in langs) l.label], [for (final b in backendTargets) b.label]);
      }
      expect([for (final l in templateLanguages(ProjectTemplate.backendCode)) l.id], [for (final s in codeStarters) s.id]);

      expect(resolveTemplateLanguage(ProjectTemplate.web, 'node'), isNull);
      expect(resolveTemplateLanguage(ProjectTemplate.backendBlocks, 'python'), 'python');
      expect(resolveTemplateLanguage(ProjectTemplate.backendBlocks, null), backendTargets.first.id);
      expect(resolveTemplateLanguage(ProjectTemplate.backendBlocks, 'cobol'), backendTargets.first.id, reason: '不认识的语言用第一种');
      expect(resolveTemplateLanguage(ProjectTemplate.backendCode, 'rust'), 'rust');
    });
  });

  group('内置模板（行为不变）', () {
    test('空项目 / 前端网页 / 低代码页面在 core 里直接生成，文件和以前一样', () {
      expect(templateFiles(ProjectTemplate.empty, '甲')!.keys, ['README.md']);
      expect(templateFiles(ProjectTemplate.web, '甲')!.keys.toSet(), {'index.html', 'style.css', 'script.js'});
      expect(templateFiles(ProjectTemplate.lowcode, '甲')!.keys.toSet(), {kLowcodePageFile, 'index.html', 'style.css'});
      for (final t in [ProjectTemplate.empty, ProjectTemplate.web, ProjectTemplate.lowcode]) {
        expect(t.builtIn, isTrue);
        expect(projectTemplateFiles(t, '甲'), templateFiles(t, '甲'), reason: '外面那层对内置模板只是转手');
      }
    });

    test('用到后端的模板不在 core 里生成', () {
      for (final t in [ProjectTemplate.backendBlocks, ProjectTemplate.backendCode, ProjectTemplate.fullstack]) {
        expect(t.builtIn, isFalse);
        expect(templateFiles(t, '甲'), isNull);
      }
    });
  });

  group('后端积木的入门样本', () {
    test('校验零问题（错误和提醒都没有），每种现有语言都一样', () {
      for (final t in backendTargets) {
        final doc = backendStarterDocument('我的服务', language: t.id);
        final issues = validateBackend(doc, languages: backendTargets.map((t) => t.id));
        expect(issues, isEmpty, reason: '[${t.id}] ${issues.join('\n')}');
        expect(doc.language, t.id);
      }
    });

    test('内容：问候、待办增删改查、计数；用到条件、路径参数、请求内容字段、集合读写、返回 JSON', () {
      final doc = backendStarterDocument('  ');
      expect(doc.name, '我的后端', reason: '名字是空的就用默认名');
      final routes = [for (final r in doc.routes) '${r.method} ${r.path}'];
      expect(routes, ['GET /hello', 'GET /todos', 'POST /todos', 'GET /todos/count', 'GET /todos/:id', 'PATCH /todos/:id', 'DELETE /todos/:id']);
      expect(routes.indexOf('GET /todos/count'), lessThan(routes.indexOf('GET /todos/:id')), reason: '计数要排在 :id 前面');
      expect(_ops(doc), containsAll(['if', 'respondJson', 'dbInsert', 'dbUpdate', 'dbDelete']));
      final text = jsonEncode(doc.toJson());
      for (final e in ['pathParam', 'bodyField', 'query', 'dbAll', 'dbGet', 'dbCount', 'obj', 'join']) {
        expect(text, contains('"e":"$e"'), reason: '样本里要用到 $e');
      }
      expect(doc.collections.single.name, 'todos');
      // 存下来再读回来一模一样
      final again = BeDocument.parse(doc.encode());
      expect(again.note, isNull);
      expect(again.doc.encode(), doc.encode());
    });

    test('curl 例子：路径参数换成 1、带上网址参数和请求内容', () {
      final doc = backendStarterDocument('x');
      final lines = [for (final r in doc.routes) beCurlExample(r, doc.port)];
      expect(lines, [
        'curl "http://localhost:8080/hello?name=Lopi"',
        'curl "http://localhost:8080/todos"',
        'curl -X POST "http://localhost:8080/todos" -H "Content-Type: application/json" -d \'{"title":"示例"}\'',
        'curl "http://localhost:8080/todos/count"',
        'curl "http://localhost:8080/todos/1"',
        'curl -X PATCH "http://localhost:8080/todos/1" -H "Content-Type: application/json" -d \'{"done":true}\'',
        'curl -X DELETE "http://localhost:8080/todos/1"',
      ]);
      // 名字不规矩的字段 / 参数不进命令（免得拼出有问题的命令）；路径格式不对的不出例子
      final odd = BeDocument();
      odd
          .addRoute('POST', '/a')!
          .body
          .add(
            LcBlock(
              op: 'log',
              args: {
                'value': {
                  'e': 'join',
                  'items': [
                    {'e': 'bodyField', 'name': "x'; rm -rf / #"},
                    {'e': 'query', 'name': r'$(reboot)'},
                    {'e': 'bodyField', 'name': 'ok_name'},
                  ],
                },
              },
            ),
          );
      odd.addRoute('GET', 'not a path');
      expect(beCurlExample(odd.routes[0], 9000), 'curl -X POST "http://localhost:9000/a" -H "Content-Type: application/json" -d \'{"ok_name":"示例"}\'');
      expect(beCurlExample(odd.routes[1], 9000), isNull);
    });

    for (final id in ['node', 'python']) {
      test('$id：样本生成的服务真的起起来，问候 / 增删改查 / 计数都对', () async {
        final target = backendTargetForRules(id, kLangRulesForNewDocs);
        if (target == null || !await toolExists(target.startCommand.first)) {
          markTestSkipped('这台机器上没有 $id 的工具（或没有它的生成器），跳过实际运行');
          return;
        }
        final files = backendBlocksTemplateFiles('样本', id)!;
        final dir = writeTempProject(files, 'lopi_tpl_run_${id}_');
        try {
          final server = await startServer(dir, target.startCommand);
          try {
            Object? body(HttpReply r) => r.body.isEmpty ? null : jsonDecode(r.body);
            final hello = await server.send('GET', '/hello');
            expect(hello.status, 200, reason: server.stderrText.toString());
            expect(body(hello), {'message': '你好，世界！'});
            expect(hello.cors, '*', reason: '网页要能跨域调');
            expect(body(await server.send('GET', '/hello?name=Lopi')), {'message': '你好，Lopi！'});
            expect(body(await server.send('GET', '/hello?name=')), {'message': '你好，世界！'}, reason: '名字是空的当成没带');

            expect(body(await server.send('GET', '/todos')), isEmpty);
            final bad = await server.send('POST', '/todos', json: {'nope': 1});
            expect(bad.status, 400);
            expect(body(bad), {'error': '缺少 title'});
            final created = await server.send('POST', '/todos', json: {'title': '买菜'});
            expect(created.status, 201);
            final todo = body(created) as Map;
            expect((todo['id'], todo['title'], todo['done']), (1, '买菜', false));
            expect(todo['createdAt'], matches(r'^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ$'));
            await server.send('POST', '/todos', json: {'title': '写作业'});
            expect(body(await server.send('GET', '/todos/count')), {'count': 2});
            expect((body(await server.send('GET', '/todos/2')) as Map)['title'], '写作业');
            final missing = await server.send('GET', '/todos/9');
            expect(missing.status, 404);
            expect(body(missing), {'error': '找不到 id 是 9 的待办'});

            final patched = await server.send('PATCH', '/todos/1', json: {'done': true});
            expect((patched.status, (body(patched) as Map)['done'], (body(patched) as Map)['title']), (200, true, '买菜'));
            expect((await server.send('PATCH', '/todos/9', json: {'done': true})).status, 404);

            final removed = await server.send('DELETE', '/todos/1');
            expect(removed.status, 200);
            expect(body(removed), {'ok': true});
            expect((await server.send('DELETE', '/todos/1')).status, 404);
            expect([for (final t in body(await server.send('GET', '/todos')) as List) (t as Map)['id']], [2]);
            expect(body(await server.send('GET', '/todos/count')), {'count': 1});
          } finally {
            await server.stop();
          }
        } finally {
          dir.deleteSync(recursive: true);
        }
      });
    }
  });

  group('每个模板生成的文件', () {
    test('后端服务（积木）：backend.lc.json + 所选语言的代码 + README；每种语言都齐', () async {
      // 新建的文档现在默认是严格规矩：入口文件、启动命令用严格规矩那一套的。
      for (final t in [for (final b in backendTargets) backendTargetForRules(b.id, kLangRulesForNewDocs)!]) {
        final files = projectTemplateFiles(ProjectTemplate.backendBlocks, '我的接口', language: t.id);
        expect(files.keys, containsAll([kBackendFileName, t.entryFile, 'README.md']), reason: t.id);
        final doc = BeDocument.parse(files[kBackendFileName]!);
        expect(doc.note, isNull);
        expect((doc.doc.name, doc.doc.language), ('我的接口', t.id));
        expect(validateBackend(doc.doc, languages: backendTargets.map((t) => t.id)), isEmpty);
        // 代码就是这份文档生成出来的那份（之后“重新生成”不会改它）
        expect(files, {kBackendFileName: files[kBackendFileName], ...backendProjectFiles(doc.doc)!.files});
        final readme = files['README.md']!;
        expect(hasBackendMarker(readme), isTrue);
        expect(readme, contains(t.startCommand.join(' ')));
        expect(readme, contains('## 在 LopiCode 里启动'));
        expect(readme, contains('## 用 curl 试一试'));
        expect(readme, contains('curl "http://localhost:8080/hello?name=Lopi"'));
        expect(readme, contains('| GET | `/todos/count` |'));
        expect(readme, isNot(contains('cd server')), reason: '放在根目录的不用先进子目录');
        expect(readme.contains('还没有在真机器上实际运行过'), !t.verified);
        expect(hasBackendMarker(files[t.entryFile]!), isTrue, reason: '${t.id} 的入口文件开头要有生成标记');
        await _checkSyntax(files, 'backend-blocks/${t.id}');
      }
    });

    test('后端服务（代码）：每种语言一份起步工程，不带积木', () async {
      for (final s in codeStarters) {
        final files = projectTemplateFiles(ProjectTemplate.backendCode, '起步', language: s.id);
        expect(files, s.files('起步'));
        expect(files.keys, isNot(contains(kBackendFileName)));
        await _checkSyntax(files, 'backend-code/${s.id}');
      }
      // 语言不认识：用第一种，不会给出空项目
      expect(projectTemplateFiles(ProjectTemplate.backendCode, '起步', language: 'cobol'), codeStarters.first.files('起步'));
    });

    test('前端 + 后端：web/ 页面 + server/ 积木后端 + 根 README + 把预览带到 web/ 的 index.html', () async {
      // 新建的文档现在默认是严格规矩：入口文件、启动命令用严格规矩那一套的。
      for (final t in [for (final b in backendTargets) backendTargetForRules(b.id, kLangRulesForNewDocs)!]) {
        final files = projectTemplateFiles(ProjectTemplate.fullstack, '待办 <小站>', language: t.id);
        expect(files.keys, containsAll(['README.md', 'index.html', 'web/index.html', 'web/style.css', 'web/app.js', 'server/$kBackendFileName', 'server/${t.entryFile}', 'server/README.md']));
        // 后端那一半和单独的积木模板一样，只是挪到 server/ 下、README 里多一步 cd server
        final doc = BeDocument.parse(files['server/$kBackendFileName']!).doc;
        expect(validateBackend(doc, languages: backendTargets.map((t) => t.id)), isEmpty);
        expect({
          for (final e in files.entries)
            if (e.key.startsWith('server/') && e.key != 'server/$kBackendFileName') e.key.substring(7): e.value,
        }, backendProjectFiles(doc, dir: 'server')!.files);
        expect(files['server/README.md'], contains('`cd server`'));

        final command = ['cd server', for (final c in t.buildCommands) c.join(' '), t.startCommand.join(' ')].join(' && ');
        final readme = files['README.md']!;
        expect(readme, contains(command));
        expect(readme, contains('先启动后端，再开预览'));
        expect(readme, contains('手机上的 `localhost` 指的是手机自己'));
        expect(hasBackendMarker(readme), isFalse, reason: '根 README 是给人改的，不算生成文件');

        expect(files['index.html'], contains('url=web/'));
        expect(files['web/index.html'], contains('待办 &lt;小站&gt;'), reason: '项目名进网页要转义');
        expect(files['web/index.html'], isNot(contains('<小站>')));
        final js = files['web/app.js']!;
        expect(js, contains("const DEFAULT_API = 'http://localhost:${doc.port}';"));
        expect(js, isNot(contains('__PORT__')));
        expect(js, isNot(contains('innerHTML')), reason: '后端给的内容只用 textContent 放');
        for (final call in ["call('GET', '/todos')", "call('POST', '/todos'", "call('PATCH', '/todos/'", "call('DELETE', '/todos/'"]) {
          expect(js, contains(call));
        }
        expect(await _checkSyntax(files, 'fullstack/${t.id}'), greaterThan(0), reason: '至少 web/app.js 要过语法检查（本机有 node）');
      }
    });

    test('所有模板 × 所有语言：路径规矩、内容不空、JSON 文件能解析', () {
      for (final t in ProjectTemplate.values) {
        final langs = templateLanguages(t);
        for (final lang in langs.isEmpty ? <String?>[null] : [for (final l in langs) l.id]) {
          final files = projectTemplateFiles(t, '样例', language: lang);
          expect(files, isNotEmpty, reason: '${t.id} / $lang');
          for (final f in files.entries) {
            expect(f.key.startsWith('/') || f.key.split('/').contains('..') || f.key.startsWith(PathGuard.reservedDir), isFalse, reason: f.key);
            expect(f.value, isNotEmpty, reason: '${t.id} / $lang / ${f.key}');
            if (f.key.endsWith('.json')) expect(() => jsonDecode(f.value), returnsNormally, reason: f.key);
          }
          expect(files.keys.any((k) => k.toLowerCase().endsWith('readme.md')) || t == ProjectTemplate.web || t == ProjectTemplate.lowcode, isTrue, reason: '${t.id} 要有 README');
        }
      }
    });
  });

  group('照模板建项目', () {
    late Directory tmp;
    late ProjectStore store;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('lopi_tpl_');
      store = ProjectStore(p.join(tmp.path, 'projects'));
    });
    tearDown(() async {
      await pendingWrites();
      tmp.deleteSync(recursive: true);
    });

    Map<String, dynamic> meta(Project project) => jsonDecode(File(p.join(project.dir, PathGuard.reservedDir, 'project.json')).readAsStringSync()) as Map<String, dynamic>;

    test('每个模板都建得出来：文件落盘，project.json 记下模板和语言，列表里读得回来', () async {
      for (final t in ProjectTemplate.values) {
        final langs = templateLanguages(t);
        final lang = langs.isEmpty ? null : langs.last.id;
        final project = await createProjectFromTemplate(store, '样例 ${t.id}', t, language: lang);
        expect((project.template, project.language), (t, lang));
        for (final f in projectTemplateFiles(t, '样例 ${t.id}', language: lang).entries) {
          expect(File(p.join(project.dir, f.key)).readAsStringSync(), f.value, reason: '${t.id} / ${f.key}');
        }
        expect(meta(project)['template'], t.id);
        expect(meta(project)['language'], lang);
        expect(meta(project).containsKey('language'), lang != null, reason: '不用选语言的模板不写 language');
      }
      final listed = await store.list();
      expect({for (final x in listed) x.template}, ProjectTemplate.values.toSet());
      for (final x in listed) {
        expect(x.language, templateLanguages(x.template).isEmpty ? isNull : templateLanguages(x.template).last.id);
      }
    });

    test('后端积木 / 全栈：建完就记下“这些文件是生成的”，马上重新生成一个文件都不变', () async {
      for (final (t, file) in [(ProjectTemplate.backendBlocks, kBackendFileName), (ProjectTemplate.fullstack, 'server/$kBackendFileName')]) {
        final project = await createProjectFromTemplate(store, '后端 ${t.id}', t, language: 'python');
        final found = await findBackendProjects(project.dir);
        expect([for (final b in found) b.file], [file]);
        expect(File(p.join(project.dir, PathGuard.reservedDir, kBackendManifestFile)).existsSync(), isTrue);
        final again = await regenerateBackend(project.dir);
        expect(again.error, isNull);
        expect(again.written, isEmpty);
        expect(again.removed, isEmpty);
        expect(again.conflicts, isEmpty);
        expect(again.unchanged, isNotEmpty);
        expect(again.language, 'python');
      }
    });

    test('不指定语言：用第一种；不用选语言的模板给了语言也不记', () async {
      final a = await createProjectFromTemplate(store, '甲', ProjectTemplate.backendCode);
      expect(a.language, codeStarters.first.id);
      final b = await createProjectFromTemplate(store, '乙', ProjectTemplate.web, language: 'python');
      expect(b.language, isNull);
      expect(File(p.join(b.dir, 'index.html')).existsSync(), isTrue);
    });

    test('旧写法照旧：ProjectStore.create(名字, 内置模板) 不用给文件', () async {
      final web = await store.create('老办法', ProjectTemplate.web);
      expect(File(p.join(web.dir, 'script.js')).existsSync(), isTrue);
      expect(meta(web), {'name': '老办法', 'template': 'web', 'createdAt': web.createdAt.toIso8601String()}, reason: 'project.json 的内容和以前一样');
    });

    test('用到后端的模板直接调 ProjectStore.create 又不给文件：报错，不留下空项目', () async {
      await expectLater(store.create('不行', ProjectTemplate.backendBlocks), throwsA(isA<ProjectException>()));
      expect(await store.list(), isEmpty);
      expect(Directory(store.rootDir).existsSync() ? Directory(store.rootDir).listSync() : const <FileSystemEntity>[], isEmpty);
    });

    test('模板文件的路径越界 / 碰内部目录：整个项目不建，外面的文件没被动', () async {
      File(p.join(tmp.path, 'outside.txt')).writeAsStringSync('原样');
      for (final bad in ['../../outside.txt', '/etc/passwd', '${PathGuard.reservedDir}/project.json', '']) {
        await expectLater(store.create('坏模板', ProjectTemplate.empty, files: {'ok.txt': '好的', bad: '坏的'}), throwsA(isA<ProjectException>()), reason: bad);
      }
      expect(File(p.join(tmp.path, 'outside.txt')).readAsStringSync(), '原样');
      expect(await store.list(), isEmpty);
      expect(Directory(store.rootDir).existsSync() ? Directory(store.rootDir).listSync() : const <FileSystemEntity>[], isEmpty, reason: '一个文件都不该写');
    });

    test('project.json 里是不认识的模板 id、奇怪的 language：项目照样列得出来', () async {
      final project = await store.create('旧项目', ProjectTemplate.empty);
      final file = File(p.join(project.dir, PathGuard.reservedDir, 'project.json'));
      file.writeAsStringSync(jsonEncode({'name': '旧项目', 'template': '以后才有的模板', 'language': 42, 'createdAt': 'x'}));
      final listed = (await store.list()).single;
      expect((listed.name, listed.template, listed.language), ('旧项目', ProjectTemplate.empty, null));
      // 改名会重写 project.json：language 是文字的要原样留着
      file.writeAsStringSync(jsonEncode({'name': '旧项目', 'template': 'backend-code', 'language': 'go', 'createdAt': '2026-11-24T00:00:00.000'}));
      final go = (await store.list()).single;
      expect((go.template, go.language), (ProjectTemplate.backendCode, 'go'));
      await store.rename(go, '新名字');
      expect(jsonDecode(file.readAsStringSync()), {'name': '新名字', 'template': 'backend-code', 'language': 'go', 'createdAt': '2026-11-24T00:00:00.000'});
    });

    test('项目名不合规矩：照旧报错', () async {
      await expectLater(createProjectFromTemplate(store, '   ', ProjectTemplate.fullstack, language: 'node'), throwsA(isA<ProjectException>()));
      await expectLater(createProjectFromTemplate(store, 'x' * 41, ProjectTemplate.backendCode), throwsA(isA<ProjectException>()));
      expect(await store.list(), isEmpty);
    });
  });
}
