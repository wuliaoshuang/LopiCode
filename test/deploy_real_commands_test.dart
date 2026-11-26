// 把“本地构建”的默认命令在这台开发机上真跑一遍（对后端积木生成的样例工程），证明命令本身是对的。
// 平时不跑：要 LOPI_REAL_DEPLOY=1，并且机器上有对应的工具（没有的那种语言会跳过并说明）。
// 这不是在手机的 Ubuntu 环境里跑的——手机上没验证。Go 这里不联网（GOFLAGS=-mod=mod GOPROXY=off），样例工程没有第三方依赖。
// 顺带：六份工作流模板用 python 的 yaml 解析一遍（有 python3 和 PyYAML 才做）。
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/backend/backend_project.dart';
import 'package:lopicode/backend/backend_templates.dart';
import 'package:lopicode/build/deploy_commands.dart';
import 'package:lopicode/build/deploy_files.dart';
import 'package:lopicode/build/deploy_project.dart';
import 'package:lopicode/build/deploy_workflows.dart';
import 'package:lopicode/core/templates.dart';
import 'package:path/path.dart' as p;

final bool real = Platform.environment['LOPI_REAL_DEPLOY'] == '1';

bool has(String tool) => Process.runSync('sh', ['-c', 'command -v $tool']).exitCode == 0;

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('lopi_real_deploy_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  /// 后端积木的起步工程，生成到 [tmp]/[dir]。
  DeployProject sample(String language, {String dir = ''}) {
    final doc = backendStarterDocument('样例', language: language);
    final gen = backendProjectFiles(doc, language: language, dir: dir)!;
    for (final e in gen.files.entries) {
      File(p.join(tmp.path, dir, e.key))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(e.value);
    }
    File(p.join(tmp.path, dir, 'backend.lc.json')).writeAsStringSync(jsonEncode({'language': language}));
    final d = detectDeployProject(tmp.path, template: ProjectTemplate.backendBlocks, templateLanguage: language);
    expect(d.kind, ProjectKind.backend);
    expect(d.lang.id, language);
    expect(d.dir, dir);
    return d;
  }

  ProcessResult sh(String command) => Process.runSync('sh', ['-c', command], workingDirectory: tmp.path, environment: {'GOFLAGS': '-mod=mod', 'GOPROXY': 'off', 'GOCACHE': '/tmp/lopi-deploy-gocache'});

  void runAll(LocalBuildPlan plan) {
    expect(plan.unsupported, isNull);
    for (final step in plan.steps) {
      final r = sh(step.command);
      // ignore: avoid_print
      print('\$ ${step.command}\n→ 退出码 ${r.exitCode}\n${r.stdout}${r.stderr}');
      expect(r.exitCode, 0, reason: '${step.title}：${r.stderr}');
    }
  }

  for (final (language, tool, dir) in [('go', 'go', ''), ('go', 'go', 'server'), ('java', 'javac', ''), ('node', 'node', ''), ('python', 'python3', 'server'), ('php', 'php', '')]) {
    test(
      '真跑：$language${dir.isEmpty ? '' : '（在 $dir/ 里）'}',
      () async {
        if (!has(tool)) {
          markTestSkipped('这台机器没有 $tool');
          return;
        }
        final project = sample(language, dir: dir);
        final plan = localBuildPlan(project, name: 'demo');
        runAll(plan);
        final out = File(p.join(tmp.path, 'build', plan.output));
        if (plan.outputKind == LocalOutputKind.archive) {
          final set = collectDeployFiles(dir.isEmpty ? tmp.path : p.join(tmp.path, dir));
          out
            ..parent.createSync(recursive: true)
            ..writeAsBytesSync(await buildDeployArchive(set, topDir: 'demo'));
          // 用系统的 tar 解一遍：证明压缩包是真 tar.gz。
          final list = sh('tar -tzf build/${plan.output}');
          expect(list.exitCode, 0, reason: '${list.stderr}');
          expect('${list.stdout}'.trim().split('\n').toSet(), {for (final f in set.files) 'demo/${f.rel}'});
        }
        expect(out.existsSync(), isTrue, reason: '应该有 build/${plan.output}');
        expect(out.lengthSync(), greaterThan(0));
        if (language == 'go') {
          final file = sh('file build/${plan.output}');
          // ignore: avoid_print
          print(file.stdout);
          expect('${file.stdout}', contains('aarch64'));
          final amd = localBuildPlan(project, name: 'demo', amd64: true);
          runAll(amd);
          expect('${sh('file build/${amd.output}').stdout}', contains('x86-64'));
        }
        if (language == 'java') {
          final list = sh('jar --list --file build/demo.jar');
          expect('${list.stdout}', contains('Main.class'));
          expect('${sh('unzip -p build/demo.jar META-INF/MANIFEST.MF').stdout}', contains('Main-Class: Main'));
          // 再跑一次：上一次的 class 目录被清掉重来，不报错。
          runAll(plan);
        }
      },
      skip: real ? false : '要 LOPI_REAL_DEPLOY=1',
      timeout: const Timeout(Duration(minutes: 10)),
    );
  }

  test('真跑：语法有错时命令退出码不是 0', () {
    for (final (language, tool, file, bad) in [('node', 'node', 'server.js', 'function ( {'), ('python', 'python3', 'main.py', 'def (:\n'), ('php', 'php', 'index.php', '<?php function ( {')]) {
      if (!has(tool)) continue;
      File(p.join(tmp.path, file)).writeAsStringSync(bad);
      final plan = localBuildPlan(
        DeployProject(kind: ProjectKind.backend, auto: true, reason: '', lang: DeployLang.byId(language)),
        name: 'demo',
      );
      final r = sh(plan.steps.first.command);
      expect(r.exitCode, isNot(0), reason: '$language 的语法错应该被查出来');
      File(p.join(tmp.path, file)).deleteSync();
    }
  }, skip: real ? false : '要 LOPI_REAL_DEPLOY=1');

  test('工作流模板是能解析的 YAML', () {
    if (!has('python3') || Process.runSync('python3', ['-c', 'import yaml']).exitCode != 0) {
      markTestSkipped('没有 python3 / PyYAML');
      return;
    }
    for (final lang in DeployLang.values) {
      for (final layout in lang == DeployLang.java ? JavaLayout.values : [JavaLayout.flat]) {
        final text = deployWorkflow(
          DeployProject(
            kind: ProjectKind.backend,
            auto: true,
            reason: '',
            lang: lang,
            dir: 'server',
            javaLayout: layout,
            javaMain: 'Main',
            hasPackageJson: true,
            hasRequirements: true,
            hasComposer: true,
          ),
          name: 'demo',
        );
        final f = File(p.join(tmp.path, 'wf.yml'))..writeAsStringSync(text);
        final r = Process.runSync('python3', [
          '-c',
          'import sys, yaml\nd = yaml.safe_load(open(sys.argv[1], encoding="utf-8"))\nsteps = d["jobs"]["build"]["steps"]\nassert d[True]["workflow_dispatch"]["inputs"]["deploy"]["default"] is False\nassert any("run" in s and s.get("name") == "构建" for s in steps)\nassert steps[-1]["if"] == "\${{ inputs.deploy }}"\nprint(len(steps))',
          f.path,
        ]);
        expect(r.exitCode, 0, reason: '${lang.id} $layout：${r.stderr}\n$text');
      }
    }
  }, skip: real ? false : '要 LOPI_REAL_DEPLOY=1');
}
