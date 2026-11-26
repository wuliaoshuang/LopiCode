// “构建与部署”的纯逻辑：项目类型怎么认、哪些文件带走 / 挡掉、默认命令、工作流模板、压缩包。
// 规则见 docs/build-deploy-design.md。
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/apkpack/apk_pack_contract.dart';
import 'package:lopicode/build/deploy_commands.dart';
import 'package:lopicode/build/deploy_files.dart';
import 'package:lopicode/build/deploy_project.dart';
import 'package:lopicode/build/deploy_workflows.dart';
import 'package:lopicode/core/templates.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('lopi_deploy_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  void put(String rel, [String text = 'x']) {
    final f = File(p.join(tmp.path, rel));
    f.parent.createSync(recursive: true);
    f.writeAsStringSync(text);
  }

  DeployProject detect({ProjectTemplate template = ProjectTemplate.empty, String? language, ProjectKind? override}) =>
      detectDeployProject(tmp.path, template: template, templateLanguage: language, override: override);

  group('项目类型识别', () {
    test('空目录是“其它”', () => expect(detect().kind, ProjectKind.other));

    test('根目录有 index.html / 低代码页面是网页', () {
      put('index.html');
      expect(detect().kind, ProjectKind.web);
      File(p.join(tmp.path, 'index.html')).deleteSync();
      put(kLowcodePageFile, '{}');
      expect(detect().kind, ProjectKind.web);
    });

    test('pubspec.yaml、安卓工程是“其它”，哪怕里面还有 Java / index.html', () {
      put('pubspec.yaml');
      put('web/index.html');
      expect(detect().kind, ProjectKind.other);
      File(p.join(tmp.path, 'pubspec.yaml')).deleteSync();
      put('build.gradle');
      put('app/src/main/AndroidManifest.xml');
      put('Main.java');
      expect(detect().kind, ProjectKind.other);
    });

    test('后端模板建的项目是后端；语言没认出文件时用模板记的', () {
      final d = detect(template: ProjectTemplate.backendCode, language: 'go');
      expect(d.kind, ProjectKind.backend);
      expect(d.lang, DeployLang.go);
      expect(d.auto, isTrue);
    });

    test('后端积木：语言读 backend.lc.json', () {
      put('backend.lc.json', jsonEncode({'language': 'java'}));
      put('Main.java', 'public class Main { public static void main(String[] a) {} }');
      final d = detect(template: ProjectTemplate.backendBlocks);
      expect(d.kind, ProjectKind.backend);
      expect(d.lang, DeployLang.java);
      expect(d.fromBlocks, isTrue);
      expect(d.javaLayout, JavaLayout.flat);
      expect(d.javaMain, 'Main');
    });

    test('“前端 + 后端”默认算网页；手动改成后端后找到 server/ 里的后端', () {
      put('web/index.html');
      put('server/server.js');
      expect(detect(template: ProjectTemplate.fullstack).kind, ProjectKind.web);
      final d = detect(template: ProjectTemplate.fullstack, override: ProjectKind.backend);
      expect(d.kind, ProjectKind.backend);
      expect(d.auto, isFalse);
      expect(d.lang, DeployLang.node);
      expect(d.dir, 'server');
      expect(d.entry, 'server.js');
    });

    test('按文件特征认五种语言', () {
      put('go.mod');
      expect(detect().lang, DeployLang.go);
      File(p.join(tmp.path, 'go.mod')).deleteSync();
      put('requirements.txt');
      put('app.py');
      var d = detect();
      expect((d.kind, d.lang, d.hasRequirements, d.entry), (ProjectKind.backend, DeployLang.python, true, 'app.py'));
      File(p.join(tmp.path, 'requirements.txt')).deleteSync();
      File(p.join(tmp.path, 'app.py')).deleteSync();
      put('composer.json', '{}');
      put('index.php');
      d = detect();
      expect((d.lang, d.hasComposer, d.entry), (DeployLang.php, true, 'index.php'));
      File(p.join(tmp.path, 'composer.json')).deleteSync();
      File(p.join(tmp.path, 'index.php')).deleteSync();
      put('package.json', '{"scripts":{"start":"node index.js"}}');
      d = detect();
      expect((d.kind, d.lang, d.hasPackageJson), (ProjectKind.backend, DeployLang.node, true));
    });

    test('package.json 有 build 脚本是前端工程（网页）；有 index.html 的也是网页', () {
      put('package.json', '{"scripts":{"build":"vite build"}}');
      expect(detect().kind, ProjectKind.web);
      put('package.json', '{"scripts":{}}');
      put('index.html');
      expect(detect().kind, ProjectKind.web);
    });

    test('Java 的四种结构', () {
      put('pom.xml');
      expect(detect().javaLayout, JavaLayout.maven);
      File(p.join(tmp.path, 'pom.xml')).deleteSync();
      put('build.gradle');
      expect(detect().javaLayout, JavaLayout.gradle);
      File(p.join(tmp.path, 'build.gradle')).deleteSync();
      put('App.java', 'package com.x;\npublic class App { public static void main(String[] a) {} }');
      expect(detect().javaLayout, JavaLayout.packaged);
      put('App.java', 'public class App { public static void main(String[] a) {} }');
      put('Util.java', 'class Util {}');
      final d = detect();
      expect(d.javaLayout, JavaLayout.flat);
      expect(d.javaMain, 'App');
    });

    test('手动选的优先于一切；坏的 package.json / backend.lc.json 不会崩', () {
      put('index.html');
      put('package.json', '{坏的');
      put('backend.lc.json', '也是坏的');
      expect(detect(override: ProjectKind.other).kind, ProjectKind.other);
      expect(detect(override: ProjectKind.backend).kind, ProjectKind.backend);
      expect(detect().kind, ProjectKind.web);
    });

    test('后端但语言不在五种里：其它语言', () {
      final d = detect(template: ProjectTemplate.backendCode, language: 'rust');
      expect(d.kind, ProjectKind.backend);
      expect(d.lang, DeployLang.other);
    });

    test('名字收拾成能进命令行的样子', () {
      expect(deploySafeName('my app/../x'), 'my-app-..-x');
      expect(deploySafeName('我的小站'), 'app');
      expect(deploySafeName("a'b;rm"), 'a-b-rm');
    });
  });

  group('收文件', () {
    test('密钥、钥匙备份、依赖目录、构建产物、符号链接都挡在外面，并列出原因', () {
      for (final rel in [
        'main.go',
        'sub/a.txt',
        '.github/workflows/deploy.yml',
        '.env',
        '.env.production',
        'conf/server.pem',
        'conf/tls.KEY',
        'id_rsa',
        'id_ed25519.pub',
        'credentials.json',
        '.npmrc',
        'my.keystore',
        '${kKeyBackupPrefix}20261126.json',
        '.lopicode/state.json',
        'build/out.bin',
        '.git/HEAD',
        'node_modules/x/index.js',
        'sub/__pycache__/a.pyc',
        'Main.class',
        'app.apk',
      ]) {
        put(rel);
      }
      Link(p.join(tmp.path, 'link')).createSync('/etc/passwd');
      final set = collectDeployFiles(tmp.path);
      expect(set.files.map((f) => f.rel), ['.github/workflows/deploy.yml', 'main.go', 'sub/a.txt']);
      final skipped = {for (final s in set.skipped) s.rel: s.reason};
      expect(
        skipped.keys,
        containsAll([
          '.env',
          '.env.production',
          'conf/server.pem',
          'conf/tls.KEY',
          'id_rsa',
          'id_ed25519.pub',
          'credentials.json',
          '.npmrc',
          'my.keystore',
          '${kKeyBackupPrefix}20261126.json',
          '.lopicode/',
          'build/',
          '.git/',
          'node_modules/',
          'sub/__pycache__/',
          'Main.class',
          'app.apk',
          'link',
        ]),
      );
      expect(skipped['.env'], contains('密钥'));
      expect(skipped['link'], '符号链接');
    });

    test('子目录里的 build 不算构建产物目录；打开“带依赖”才收 node_modules', () {
      put('src/build/a.js');
      put('node_modules/x/index.js');
      expect(collectDeployFiles(tmp.path).files.map((f) => f.rel), ['src/build/a.js']);
      expect(collectDeployFiles(tmp.path, includeNodeModules: true).files.map((f) => f.rel), ['node_modules/x/index.js', 'src/build/a.js']);
    });

    test('单个太大跳过并列出；个数、总量超限直接不做', () {
      put('big.bin', 'x' * 200);
      put('a.txt');
      const tight = DeployLimits(maxFiles: 10, maxFileBytes: 100, maxTotalBytes: 1000);
      final set = collectDeployFiles(tmp.path, limits: tight);
      expect(set.files.map((f) => f.rel), ['a.txt']);
      expect(set.skipped.single.reason, contains('太大'));
      expect(() => collectDeployFiles(tmp.path, limits: const DeployLimits(maxFiles: 1, maxFileBytes: 1000, maxTotalBytes: 1000)), throwsA(isA<DeployException>()));
      expect(() => collectDeployFiles(tmp.path, limits: const DeployLimits(maxFiles: 10, maxFileBytes: 1000, maxTotalBytes: 150)), throwsA(isA<DeployException>()));
    });

    test('压缩包：tar.gz，文件都在一层目录下面', () async {
      put('main.py', 'print(1)');
      put('pkg/a.py', 'a = 1');
      put('.env', 'SECRET=1');
      final bytes = await buildDeployArchive(collectDeployFiles(tmp.path), topDir: 'demo');
      final archive = TarDecoder().decodeBytes(GZipDecoder().decodeBytes(bytes));
      expect(archive.files.map((f) => f.name).toSet(), {'demo/main.py', 'demo/pkg/a.py'});
      expect(utf8.decode(archive.files.firstWhere((f) => f.name == 'demo/main.py').content as List<int>), 'print(1)');
    });
  });

  group('默认命令', () {
    DeployProject backend(DeployLang lang, {String dir = '', JavaLayout? java, String? javaMain, bool pkg = false, bool req = false, bool composer = false, String? entry}) => DeployProject(
      kind: ProjectKind.backend,
      auto: true,
      reason: '',
      lang: lang,
      dir: dir,
      javaLayout: java,
      javaMain: javaMain,
      hasPackageJson: pkg,
      hasRequirements: req,
      hasComposer: composer,
      entry: entry,
    );

    test('Go：默认 linux/arm64，可换 amd64；产物名带架构', () {
      final arm = localBuildPlan(backend(DeployLang.go, dir: 'server'), name: 'shop');
      expect(arm.output, 'shop-linux-arm64');
      expect(arm.packId, 'go');
      expect(arm.steps.single.command, 'OUT="\$PWD/build"; mkdir -p "\$OUT" && cd \'server\' && CGO_ENABLED=0 GOOS=linux GOARCH=arm64 go build -buildvcs=false -o "\$OUT/shop-linux-arm64" .');
      final amd = localBuildPlan(backend(DeployLang.go), name: 'shop', amd64: true);
      expect(amd.output, 'shop-linux-amd64');
      expect(amd.steps.single.command, contains("cd '.' && CGO_ENABLED=0 GOOS=linux GOARCH=amd64"));
    });

    test('Java：简单结构出 jar；Maven / Gradle / 带包名 / 没有 main 说明原因、不给命令', () {
      final ok = localBuildPlan(
        backend(DeployLang.java, java: JavaLayout.flat, javaMain: 'Main'),
        name: 'api',
      );
      expect(ok.unsupported, isNull);
      expect(ok.output, 'api.jar');
      expect(
        ok.steps.single.command,
        'OUT="\$PWD/build"; rm -rf "\$OUT/classes-api" && mkdir -p "\$OUT/classes-api" && cd \'.\' && javac -encoding UTF-8 -d "\$OUT/classes-api" *.java && '
        'jar --create --file "\$OUT/api.jar" --main-class Main -C "\$OUT/classes-api" .',
      );
      for (final layout in [JavaLayout.maven, JavaLayout.gradle, JavaLayout.packaged]) {
        final plan = localBuildPlan(backend(DeployLang.java, java: layout), name: 'api');
        expect(plan.unsupported, isNotNull);
        expect(plan.steps, isEmpty);
      }
      expect(localBuildPlan(backend(DeployLang.java, java: JavaLayout.flat), name: 'api').unsupported, contains('main'));
    });

    test('Node / Python / PHP：语法检查 + 压缩包；依赖默认不装', () {
      final node = localBuildPlan(backend(DeployLang.node, pkg: true), name: 'api');
      expect(node.output, 'api-node.tar.gz');
      expect(node.steps.map((s) => s.title), ['语法检查（node --check）']);
      expect(node.steps.single.command, contains('xargs -0 -r -n 1 node --check'));
      expect(node.howTo.join(), contains('npm install --omit=dev'));
      final withDeps = localBuildPlan(backend(DeployLang.node, pkg: true), name: 'api', npmInstall: true);
      expect(withDeps.steps.last.command, "cd '.' && npm install --omit=dev");
      expect(localBuildPlan(backend(DeployLang.node), name: 'api', npmInstall: true).steps, hasLength(1), reason: '没有 package.json 就没什么可装');
      final py = localBuildPlan(backend(DeployLang.python, req: true), name: 'api');
      expect(py.steps.single.command, contains('python3 -m py_compile'));
      expect(py.howTo.join(), contains('pip install -r requirements.txt'));
      final php = localBuildPlan(backend(DeployLang.php), name: 'api');
      expect(php.steps.single.command, contains('php -l'));
      final other = localBuildPlan(backend(DeployLang.other), name: 'api');
      expect(other.steps, isEmpty);
      expect(other.packId, isNull);
      expect(other.output, 'api-source.tar.gz');
    });

    test('本地的默认命令里，除了清自己的 class 目录以外没有删除', () {
      for (final lang in DeployLang.values) {
        final plan = localBuildPlan(
          backend(lang, java: JavaLayout.flat, javaMain: 'Main', pkg: true),
          name: 'api',
          npmInstall: true,
        );
        for (final s in plan.steps) {
          final rest = s.command.replaceAll('rm -rf "\$OUT/classes-api"', '');
          expect(rest, isNot(matches(RegExp(r'\brm\b|--delete|\bmv\b'))), reason: s.command);
        }
      }
    });

    test('SSH 的默认编译命令', () {
      expect(defaultRemoteBuildCommand(backend(DeployLang.go)), 'go build -buildvcs=false -o server .');
      expect(defaultRemoteBuildCommand(backend(DeployLang.java, java: JavaLayout.flat)), 'javac -encoding UTF-8 -d out *.java');
      expect(defaultRemoteBuildCommand(backend(DeployLang.java, java: JavaLayout.maven)), 'mvn -B package');
      expect(defaultRemoteBuildCommand(backend(DeployLang.java, java: JavaLayout.gradle)), 'gradle build');
      expect(defaultRemoteBuildCommand(backend(DeployLang.java, java: JavaLayout.packaged)), '');
      expect(defaultRemoteBuildCommand(backend(DeployLang.node, pkg: true)), 'npm install --omit=dev');
      expect(defaultRemoteBuildCommand(backend(DeployLang.node, entry: 'server.js')), "node --check 'server.js'");
      expect(defaultRemoteBuildCommand(backend(DeployLang.python, req: true)), 'python3 -m venv .venv && .venv/bin/pip install -r requirements.txt');
      expect(defaultRemoteBuildCommand(backend(DeployLang.python, entry: 'main.py')), "python3 -m py_compile 'main.py'");
      expect(defaultRemoteBuildCommand(backend(DeployLang.php, composer: true)), 'composer install --no-dev');
      expect(defaultRemoteBuildCommand(backend(DeployLang.php, entry: 'index.php')), "php -l 'index.php'");
      expect(defaultRemoteBuildCommand(backend(DeployLang.other)), '');
    });

    test('SSH 的步骤清单：固定三步 + 编译 + 可选重启；不带任何删除', () {
      final steps = sshDeploySteps(remoteDir: '~/lopicode-deploy/my app', buildCommand: 'go build .', restartCommand: 'systemctl restart api');
      expect(steps.map((s) => s.command), [
        "mkdir -p ~/'lopicode-deploy/my app'",
        "cd ~/'lopicode-deploy/my app' && pwd   # 查出目录的完整路径，然后用 SFTP 把代码打成的 lopicode-upload.tar.gz 传进去",
        "cd ~/'lopicode-deploy/my app' && tar -xzf lopicode-upload.tar.gz --strip-components=1",
        "cd ~/'lopicode-deploy/my app' && go build .",
        "cd ~/'lopicode-deploy/my app' && systemctl restart api",
      ]);
      expect(sshDeploySteps(remoteDir: '/srv/x', buildCommand: ' ', restartCommand: null), hasLength(3));
      for (final s in sshDeploySteps(remoteDir: '/srv/x', buildCommand: '')) {
        expect(s.command, isNot(matches(RegExp(r'\brm\b|--delete'))));
      }
      expect(quoteRemotePath("/srv/it's"), "'/srv/it'\\''s'");
    });
  });

  group('工作流模板', () {
    test('五种语言 + 其它：手动触发、默认不部署、只有 secrets 占位、没有任何密钥', () {
      for (final lang in DeployLang.values) {
        final text = deployWorkflow(
          DeployProject(kind: ProjectKind.backend, auto: true, reason: '', lang: lang, javaLayout: JavaLayout.flat, javaMain: 'Main', hasPackageJson: true, hasRequirements: true, hasComposer: true),
          name: 'api',
        );
        expect(text, startsWith('name: 构建与部署'), reason: lang.id);
        expect(text, contains('workflow_dispatch'));
        expect(text, contains('default: false'));
        expect(text, contains(r'if: ${{ inputs.deploy }}'));
        expect(text, contains('actions/upload-artifact@v4'));
        for (final secret in kDeploySecrets.keys) {
          expect(text, contains('\${{ secrets.$secret }}'));
        }
        expect(text, isNot(contains('BEGIN ')), reason: '不能有私钥');
        expect(text, isNot(contains('\t')), reason: 'YAML 不能有制表符');
      }
    });

    test('后端在子目录时，工作流在那个目录里跑，产物路径跟着变', () {
      final text = deployWorkflow(
        const DeployProject(kind: ProjectKind.backend, auto: true, reason: '', lang: DeployLang.go, dir: 'server'),
        name: 'api',
      );
      expect(text, contains('working-directory: server'));
      expect(text, contains('path: server/dist/'));
      expect(text, contains('go build -buildvcs=false -o dist/api .'));
    });

    test('Java 按结构给命令', () {
      String wf(JavaLayout l) => deployWorkflow(
        DeployProject(kind: ProjectKind.backend, auto: true, reason: '', lang: DeployLang.java, javaLayout: l, javaMain: 'Main'),
        name: 'api',
      );
      expect(wf(JavaLayout.maven), contains('mvn -B package'));
      expect(wf(JavaLayout.gradle), contains('gradle build'));
      expect(wf(JavaLayout.flat), contains('--main-class Main'));
    });
  });
}
