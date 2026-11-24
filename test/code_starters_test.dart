// 纯代码起步模板（“后端 · 代码”）：
// - 每种语言的工程都有入口文件、README、.gitignore，说明里不夸口；
// - 本机有工具的（Node.js、Python、Go、Java、Dart）真的把服务起起来请求一次：GET / 回 JSON 问候、/health 回 ok、别的 404。
//   只绑 / 只连 127.0.0.1 的随机端口；没有工具就跳过并打印原因；结束按 pid 杀掉自己起的进程。
@Timeout(Duration(minutes: 10))
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/core/file_icons.dart';
import 'package:lopicode/templates/code_starters.dart';

import 'support/starter_servers.dart';

/// 怎么在本机跑这种语言的起步工程：要先跑的命令（编译）、启动命令、环境变量。跑不了返回 null 和原因。
Future<({List<List<String>> build, List<String> start, Map<String, String> env})?> _runner(String id) async {
  switch (id) {
    case 'node':
      return await toolExists('node') ? (build: const <List<String>>[], start: const ['node', 'server.js'], env: const <String, String>{}) : null;
    case 'python':
      return await toolExists('python3') ? (build: const <List<String>>[], start: const ['python3', 'server.py'], env: const <String, String>{}) : null;
    case 'go':
      final go = await findGoTool();
      if (go == null) return null;
      // README 里写的是 `go run .`；测试里先编译再直接跑编译结果——这样杀进程时杀的就是服务本身，不会留下 go run 的子进程。
      return (
        build: [
          [go, 'vet', '.'],
          [go, 'build', '-o', 'app', '.'],
        ],
        start: const ['./app'],
        env: goOfflineEnv(),
      );
    case 'java':
      return await toolExists('java') ? (build: const <List<String>>[], start: const ['java', 'Main.java'], env: const <String, String>{}) : null;
    case 'dart':
      return await toolExists('dart') ? (build: const <List<String>>[], start: const ['dart', 'run', 'server.dart'], env: const <String, String>{}) : null;
  }
  return null;
}

void main() {
  test('目录：至少有 Node.js / Python / Go / Java / PHP；id 不重复；图标都找得到', () {
    final ids = [for (final s in codeStarters) s.id];
    expect(ids.take(5), ['node', 'python', 'go', 'java', 'php'], reason: '前五个必须有，而且排在前面');
    expect(ids, containsAll(['csharp', 'rust', 'ruby', 'kotlin', 'dart']));
    expect(ids.toSet().length, ids.length);
    for (final s in codeStarters) {
      expect(languageIconFor(s.id), isNot(languageIconFor('没有这种语言')), reason: '${s.id} 没有对应的语言图标');
      expect(codeStarterFor(s.id), same(s));
    }
    expect(codeStarterFor('cobol'), isNull);
  });

  test('“实际运行过”的标记和这份测试真跑的语言一致', () {
    expect(
      {
        for (final s in codeStarters)
          if (s.verified) s.id,
      },
      {'node', 'python', 'go', 'java', 'dart'},
    );
  });

  for (final s in codeStarters) {
    test('${s.label}：入口文件、README、.gitignore 齐全，说明如实', () {
      final files = s.files('我的 `小` 服务\n<script>');
      expect(files.keys, containsAll([s.entryFile, 'README.md', '.gitignore']));
      for (final f in files.entries) {
        expect(f.value.trim(), isNotEmpty, reason: f.key);
        expect(f.value.endsWith('\n'), isTrue, reason: '${f.key} 末尾要有换行');
        expect(f.key.startsWith('/') || f.key.contains('..'), isFalse);
      }
      final entry = files[s.entryFile]!;
      expect(entry, contains('/health'));
      expect(entry, contains('没有这个接口'));
      expect(entry, isNot(contains('小` 服务')), reason: '项目名只进 README，不进源码');

      final readme = files['README.md']!;
      expect(readme.split('\n').first, '# 我的  小  服务  script', reason: '标题里的换行、反引号、尖括号要去掉');
      expect(readme, contains(s.startCommand));
      expect(readme, contains('/health'));
      expect(readme, contains('localhost'));
      expect(readme, contains(s.needs));
      expect(readme.contains('还没有在真机器上实际运行过'), !s.verified, reason: '没跑过的要写明，跑过的不写');
      if (s.portNote == null) {
        expect(entry, contains('PORT'), reason: '端口要能用环境变量改');
        expect(entry, contains('后端已启动'));
        expect(readme, contains('PORT=3000 ${s.startCommand}'));
      } else {
        expect(readme, contains(s.portNote!));
        expect(readme, isNot(contains('后端已启动')), reason: '这种语言启动时不打印这句话，README 不能这么说');
      }
    });
  }

  for (final s in codeStarters.where((s) => s.verified)) {
    test('${s.label}：真的启动，请求 /、/health、不存在的地址', () async {
      final run = await _runner(s.id);
      if (run == null) {
        markTestSkipped('这台机器上没有 ${s.label} 的工具，跳过实际运行');
        return;
      }
      final dir = writeTempProject(s.files('起步'), 'lopi_starter_${s.id}_');
      try {
        for (final b in run.build) {
          final r = await Process.run(b.first, b.sublist(1), workingDirectory: dir.path, environment: run.env);
          expect(r.exitCode, 0, reason: '[${s.id}] ${b.join(' ')} 失败：\n${r.stdout}\n${r.stderr}');
        }
        final start = run.start.first.startsWith('./') ? ['${dir.path}/${run.start.first.substring(2)}', ...run.start.sublist(1)] : run.start;
        final server = await startServer(dir, start, environment: run.env);
        try {
          final home = await server.send('GET', '/');
          expect(home.status, 200, reason: server.stderrText.toString());
          expect(home.contentType, startsWith('application/json'));
          expect(home.cors, '*');
          expect((jsonDecode(home.body) as Map)['message'], '你好，这里是你的后端');

          final health = await server.send('GET', '/health?x=1');
          expect(health.status, 200);
          expect(jsonDecode(health.body), {'status': 'ok'});

          final missing = await server.send('GET', '/nope');
          expect(missing.status, 404);
          expect(jsonDecode(missing.body), {'error': '没有这个接口'});

          final post = await server.send('POST', '/'); // 不带内容：起步代码不读请求内容，带了内容有的服务会先回 404 再断开
          expect(post.status, 404, reason: '只有 GET / 是问候');
        } finally {
          await server.stop();
        }
      } finally {
        dir.deleteSync(recursive: true);
      }
    });
  }
}
