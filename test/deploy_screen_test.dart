// 打包页按项目类型分叉（390×844）：网页 / 其它类还是 APK 打包那一页；后端类换成“构建与部署”。
// 后端的三种方式用假运行环境、假 GitHub、假 SSH（test/support/fake_deploy.dart）。
// LOPI_SHOTS=1 时顺手出截图：默认写到 docs/screenshots/，设了 LOPI_SHOT_DIR 就写到那里。
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/build/build_screen.dart';
import 'package:lopicode/build/deploy_backends.dart';
import 'package:lopicode/build/github_client.dart';
import 'package:lopicode/build/local_pack_backend.dart';
import 'package:lopicode/core/project_store.dart';
import 'package:lopicode/core/stores.dart';
import 'package:lopicode/core/templates.dart';
import 'package:lopicode/project_session.dart';
import 'package:lopicode/state/deploy_github.dart';
import 'package:lopicode/state/deploy_local.dart';
import 'package:lopicode/state/deploy_run.dart';
import 'package:lopicode/state/deploy_ssh.dart';
import 'package:lopicode/ui/shell.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;

import 'support/fake_deploy.dart';
import 'support/fake_local_pack.dart';
import 'support/harness.dart';

final bool writeShots = Platform.environment['LOPI_SHOTS'] == '1';
final String shotDir = Platform.environment['LOPI_SHOT_DIR'] ?? 'docs/screenshots';
bool fontsLoaded = false;

Future<void> shot(WidgetTester tester, String name) async {
  expect(tester.takeException(), isNull, reason: '$name 渲染时出了异常');
  if (!writeShots || !fontsLoaded) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(shotKey));
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('$shotDir/$name.png');
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(data!.buffer.asUint8List());
  });
}

void main() {
  late TestEnv env;
  late Project project;
  late ProjectSession session;
  late FakeGuest guest;
  late FakeGitHubHttp gh;
  late FakeRemote remote;
  final went = <ShellDest>[];

  setUpAll(() async => fontsLoaded = await loadRealFonts());

  Future<void> boot(WidgetTester tester, {ProjectTemplate template = ProjectTemplate.backendCode, String? language = 'go', Map<String, String>? files}) async {
    usePhoneViewport(tester);
    went.clear();
    localPackBackendOverride = FakeLocalPackBackend();
    guest = FakeGuest(() => project.dir);
    gh = FakeGitHubHttp();
    remote = FakeRemote();
    deployGuestOverride = (_) => guest;
    deployGitHubOverride = (token, owner, repo) => GitHubClient(token: token, owner: owner, repo: repo, baseUrl: 'https://gh.test', httpClient: gh.client);
    deployRemoteExecOverride = () => remote;
    deployPollInterval = const Duration(milliseconds: 5);
    await tester.runAsync(() async {
      env = await TestEnv.create();
      project = await env.services.projects.create(
        'api',
        template,
        language: language,
        files: files ?? (template == ProjectTemplate.backendCode ? {'main.go': 'package main\nfunc main() {}\n', 'go.mod': 'module api\n'} : null),
      );
      session = ProjectSession(env.services, project);
      await session.loadChat();
      await Future<void>.delayed(const Duration(milliseconds: 150));
    });
    addTearDown(() async {
      session.dispose();
      await env.dispose();
      localPackBackendOverride = null;
      deployGuestOverride = null;
      deployGitHubOverride = null;
      deployRemoteExecOverride = null;
      deployPollInterval = const Duration(seconds: 6);
    });
  }

  Future<void> show(WidgetTester tester, {ThemeMode mode = ThemeMode.light}) async {
    await tester.pumpWidget(
      appFor(
        env,
        ShellScope(
          openDrawer: () {},
          go: went.add,
          projectName: 'api',
          child: BuildScreen(key: UniqueKey(), session: session),
        ),
        mode: mode,
        font: kTestFont,
      ),
    );
    await settle(tester);
  }

  Future<void> reveal(WidgetTester tester, Finder f) async {
    await tester.scrollUntilVisible(f, 160, scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(f);
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<void> tapOn(WidgetTester tester, Finder f, {int rounds = 3}) async {
    await reveal(tester, f);
    await tester.tap(f);
    await settle(tester, rounds: rounds);
  }

  Future<void> toBottom(WidgetTester tester) async {
    await tester.drag(find.byType(ListView).first, const Offset(0, -3000));
    await settle(tester, rounds: 2);
  }

  Future<void> set(WidgetTester tester, String key, Object? value) => tester.runAsync(() => env.services.settings.set(key, value));

  String title(WidgetTester tester) => tester.widget<ShellAppBar>(find.byType(ShellAppBar)).title;

  group('按类型分叉', () {
    testWidgets('网页项目：还是“APK 打包”那一页，三选一和说明文字一个字没变', (tester) async {
      await boot(tester, template: ProjectTemplate.web, language: null);
      await show(tester);
      expect(title(tester), 'APK 打包');
      for (final (key, label) in [('pack-mode-local', '本地打包'), ('pack-mode-github', 'GitHub Actions'), ('pack-mode-ssh', 'SSH 构建机')]) {
        expect(find.descendant(of: find.byKey(Key(key)), matching: find.text(label)), findsOneWidget);
      }
      expect(tester.widget<Text>(find.byKey(const Key('pack-mode-about'))).data, '就在这台手机上打包，几秒出包，不用联网。只适合网页项目：把网页装进一个现成的应用壳里。');
      expect(find.text('这个项目可以本地打包'), findsOneWidget);
      expect(find.byKey(const Key('pack-start')), findsOneWidget);
      expect(find.byKey(const Key('deploy-mode-local')), findsNothing);
      expect(find.byKey(const Key('deploy-kind')), findsNothing);
      expect(find.byKey(const Key('pack-project-kind')), findsOneWidget, reason: '只多了顶栏右上角的“项目类型”入口');
      expect(env.services.settings.getString(SettingKeys.apkBuildMode), '');
    });

    testWidgets('低代码、前端 + 后端项目：也是 APK 打包', (tester) async {
      await boot(tester, template: ProjectTemplate.lowcode, language: null);
      await show(tester);
      expect(title(tester), 'APK 打包');
      expect(find.byKey(const Key('pack-mode-local')), findsOneWidget);
    });

    testWidgets('其它类（Flutter 项目）：保持现状，还是 APK 打包', (tester) async {
      await boot(tester, template: ProjectTemplate.empty, language: null, files: {'pubspec.yaml': 'name: app\n', 'lib/main.dart': 'void main() {}\n'});
      await show(tester);
      expect(title(tester), 'APK 打包');
      expect(find.byKey(const Key('pack-mode-github')), findsOneWidget);
      expect(find.byKey(const Key('deploy-mode-local')), findsNothing);
    });

    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      final suffix = mode == ThemeMode.light ? 'light' : 'dark';
      testWidgets('后端项目：标题和三选一换成“构建与部署”，方式单独记 ($suffix)', (tester) async {
        await boot(tester);
        await set(tester, SettingKeys.apkBuildMode, 'ssh');
        await show(tester, mode: mode);
        expect(title(tester), '构建与部署');
        expect(find.byKey(const Key('pack-mode-local')), findsNothing);
        expect(find.byKey(const Key('pack-start')), findsNothing);
        for (final (key, label) in [('deploy-mode-local', '本地构建'), ('deploy-mode-github', 'GitHub 部署'), ('deploy-mode-ssh', 'SSH 部署')]) {
          expect(find.descendant(of: find.byKey(Key(key)), matching: find.text(label)), findsOneWidget);
        }
        expect(tester.widget<Text>(find.byKey(const Key('deploy-kind-value'))).data, '后端 · Go');
        expect(find.textContaining('自动识别'), findsOneWidget);
        expect(tester.widget<Text>(find.byKey(const Key('deploy-mode-about'))).data, DeployMode.local.about, reason: 'APK 那边存的是 ssh，这里不受影响');
        expect(find.text('编译成 Linux 程序'), findsOneWidget);
        expect(find.text('产物：build/api-linux-arm64'), findsOneWidget);
        expect(find.widgetWithText(FilledButton, '开始构建'), findsOneWidget);
        await shot(tester, 'deploy-01-local-$suffix');

        await tapOn(tester, find.byKey(const Key('deploy-mode-github')));
        expect(env.services.settings.getString(deployKey(SettingKeys.deployMode, session)), 'github');
        expect(env.services.settings.getString(SettingKeys.apkBuildMode), 'ssh');
        expect(tester.widget<Text>(find.byKey(const Key('deploy-mode-about'))).data, DeployMode.github.about);
        expect(find.widgetWithText(FilledButton, '推送并启动'), findsOneWidget);
        expect(find.text('还没写进项目：点开看全文，确认后写进项目'), findsOneWidget);
        await shot(tester, 'deploy-10-github-$suffix');

        await tester.drag(find.byType(ListView).first, const Offset(0, 3000));
        await settle(tester, rounds: 2);
        await tapOn(tester, find.byKey(const Key('deploy-mode-ssh')));
        expect(tester.widget<Text>(find.byKey(const Key('deploy-mode-about'))).data, DeployMode.ssh.about);
        expect(tester.widget<TextField>(find.byKey(const Key('deploy-ssh-dir'))).controller!.text, '~/lopicode-deploy/api');
        expect(tester.widget<TextField>(find.byKey(const Key('deploy-ssh-build'))).controller!.text, 'go build -buildvcs=false -o server .');
        expect(find.text('还没设置'), findsOneWidget);
        expect(find.widgetWithText(FilledButton, '查看步骤并开始'), findsOneWidget);
        await shot(tester, 'deploy-20-ssh-$suffix');
      });
    }

    testWidgets('认错了能手动改：后端 → 网页 → 回到自动识别；按工作区记住', (tester) async {
      await boot(tester);
      await show(tester);
      await tapOn(tester, find.byKey(const Key('deploy-kind')));
      expect(find.textContaining('现在认成：后端 · Go'), findsOneWidget);
      await shot(tester, 'deploy-02-kind-sheet-light');
      await tapOn(tester, find.byKey(const Key('deploy-kind-web')));
      expect(env.services.settings.getString(deployKey(SettingKeys.deployKind, session)), 'web');
      expect(title(tester), 'APK 打包');
      expect(find.byKey(const Key('pack-mode-local')), findsOneWidget);

      await tapOn(tester, find.byKey(const Key('pack-project-kind')));
      await tapOn(tester, find.byKey(const Key('deploy-kind-auto')));
      expect(env.services.settings.getString(deployKey(SettingKeys.deployKind, session)), '');
      expect(title(tester), '构建与部署');
    });

    testWidgets('全栈项目手动改成后端：找到 server/ 里的后端', (tester) async {
      await boot(
        tester,
        template: ProjectTemplate.fullstack,
        language: null,
        files: {'web/index.html': '<h1>hi</h1>', 'server/server.js': 'console.log(1)\n', 'server/package.json': '{"scripts":{"start":"node server.js"}}'},
      );
      await show(tester);
      expect(title(tester), 'APK 打包');
      await tapOn(tester, find.byKey(const Key('pack-project-kind')));
      await tapOn(tester, find.byKey(const Key('deploy-kind-backend')));
      expect(title(tester), '构建与部署');
      expect(tester.widget<Text>(find.byKey(const Key('deploy-kind-value'))).data, '后端 · Node.js');
      expect(find.text('产物：build/api-node.tar.gz'), findsOneWidget);
      expect(find.byKey(const Key('deploy-npm-install')), findsOneWidget);
    });
  });

  group('本地构建', () {
    testWidgets('看命令全文 → 开始 → 结果卡；amd64 开关', (tester) async {
      await boot(tester);
      guest.onRun = (cmd) {
        final arch = cmd.contains('GOARCH=amd64') ? 'amd64' : 'arm64';
        File(p.join(project.dir, 'build', 'api-linux-$arch'))
          ..parent.createSync(recursive: true)
          ..writeAsBytesSync(List.filled(3 * 1024 * 1024, 1));
        return const GuestRunResult(0);
      };
      guest.output = 'go: downloading modules...\n';
      await show(tester);
      await tapOn(tester, find.byKey(const Key('deploy-local-steps')));
      expect(find.textContaining('CGO_ENABLED=0 GOOS=linux GOARCH=arm64 go build'), findsOneWidget);
      await tester.tapAt(const Offset(195, 40));
      await settle(tester, rounds: 2);

      await tapOn(tester, find.byKey(const Key('deploy-go-amd64')));
      expect(env.services.settings.getBool(deployKey(SettingKeys.deployGoAmd64, session)), isTrue);
      expect(find.text('产物：build/api-linux-amd64'), findsOneWidget);
      await tapOn(tester, find.byKey(const Key('deploy-start')), rounds: 5);
      expect(guest.commands.single, contains('GOARCH=amd64'));
      final state = env.services.container.read(deployLocalProvider(session));
      expect(state.phase, DeployPhase.done, reason: state.failure);
      await toBottom(tester);
      expect(find.text('编译好了'), findsOneWidget);
      expect(find.text('位置 · 3.0 MB'), findsOneWidget);
      expect(find.text('build/api-linux-amd64'), findsOneWidget);
      expect(find.textContaining('chmod +x api-linux-amd64'), findsOneWidget);
      expect(find.textContaining('go: downloading modules'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, '重新构建'), findsOneWidget);
      await shot(tester, 'deploy-03-local-done-light');
    });

    testWidgets('运行环境没装：给“去装运行环境”按钮，点了跳到运行环境页', (tester) async {
      await boot(tester);
      guest.status = GuestStatus.notInstalled;
      await show(tester);
      await tapOn(tester, find.byKey(const Key('deploy-start')), rounds: 4);
      expect(find.textContaining('还没装运行环境'), findsOneWidget);
      await tapOn(tester, find.byKey(const Key('deploy-go-runtime')));
      expect(went, [ShellDest.runtime]);
      await shot(tester, 'deploy-04-local-no-runtime-light');
    });

    testWidgets('编译失败：红框说停在哪一步，输出留着', (tester) async {
      await boot(tester);
      guest.onRun = (_) => const GuestRunResult(2);
      guest.output = './main.go:3:1: syntax error: unexpected }\n';
      await show(tester);
      await tapOn(tester, find.byKey(const Key('deploy-start')), rounds: 4);
      await toBottom(tester);
      expect(find.text('没成'), findsOneWidget);
      expect(tester.widget<Text>(find.descendant(of: find.byKey(const Key('deploy-failure')), matching: find.byType(Text))).data, contains('退出码 2'));
      expect(find.textContaining('syntax error'), findsOneWidget);
      await shot(tester, 'deploy-05-local-failed-light');
    });

    testWidgets('缺的语言包很大：卡片上先问，点“装上并继续”才装', (tester) async {
      await boot(tester, language: 'java', files: {'Main.java': 'public class Main { public static void main(String[] a) {} }\n'});
      guest.installed.clear();
      guest.bigPacks.add('java');
      guest.onRun = (cmd) {
        File(p.join(project.dir, 'build', 'api.jar'))
          ..parent.createSync(recursive: true)
          ..writeAsStringSync('jar');
        return const GuestRunResult(0);
      };
      await show(tester);
      expect(tester.widget<Text>(find.byKey(const Key('deploy-kind-value'))).data, '后端 · Java');
      await tapOn(tester, find.byKey(const Key('deploy-start')), rounds: 4);
      expect(find.byKey(const Key('deploy-ask')), findsOneWidget);
      expect(guest.installs, isEmpty);
      await tapOn(tester, find.byKey(const Key('deploy-ask-yes')), rounds: 5);
      expect(guest.installs, ['java']);
      expect(env.services.container.read(deployLocalProvider(session)).phase, DeployPhase.done);
    });

    testWidgets('Maven 项目：本地不给主按钮，说明原因和出路', (tester) async {
      await boot(tester, language: 'java', files: {'pom.xml': '<project/>', 'src/main/java/App.java': 'class App {}\n'});
      await show(tester);
      expect(find.byKey(const Key('deploy-local-unsupported')), findsOneWidget);
      expect(find.textContaining('请改用 GitHub 或 SSH 方式'), findsOneWidget);
      expect(find.byKey(const Key('deploy-start')), findsNothing);
    });
  });

  group('GitHub 部署', () {
    Future<void> ready(WidgetTester tester) async {
      await boot(tester);
      await tester.runAsync(() async {
        final s = env.services.settings;
        await s.set(SettingKeys.githubOwner, 'shuang');
        await s.set(SettingKeys.githubRepo, 'demo');
        await s.set(deployKey(SettingKeys.deployMode, session), 'github');
        await env.services.secrets.write(SecretKeys.githubToken, 'tok-SECRET-123');
        File(p.join(project.dir, '.env')).writeAsStringSync('SECRET=1');
      });
      await show(tester);
    }

    testWidgets('没写工作流就点主按钮：提示先看工作流，不联网', (tester) async {
      await ready(tester);
      await tapOn(tester, find.byKey(const Key('deploy-start')), rounds: 4);
      expect(find.textContaining('项目里还没有部署工作流'), findsOneWidget);
      expect(gh.requests, isEmpty);
    });

    testWidgets('看工作流全文 → 写进项目 → 确认清单（取消不动手）→ 确认 → 推送、触发、结果', (tester) async {
      await ready(tester);
      await tapOn(tester, find.byKey(const Key('deploy-gh-edit-workflow')), rounds: 4);
      final text = tester.widget<TextField>(find.byKey(const Key('deploy-workflow-text'))).controller!.text;
      expect(text, contains('actions/setup-go@v5'));
      expect(text, contains(r'${{ secrets.DEPLOY_SSH_KEY }}'));
      expect(find.text('部署工作流'), findsOneWidget);
      expect(find.textContaining('还没写进项目'), findsWidgets);
      await shot(tester, 'deploy-11-github-workflow-light');
      expect(File(p.join(project.dir, '.github/workflows/deploy.yml')).existsSync(), isFalse, reason: '只是看，还没写');
      await tester.tap(find.byKey(const Key('deploy-workflow-write')));
      await settle(tester, rounds: 4);
      expect(File(p.join(project.dir, '.github/workflows/deploy.yml')).readAsStringSync(), contains('workflow_dispatch'));
      expect(find.text('已经在项目里，会跟代码一起推送'), findsOneWidget);
      // “已写入项目”的提示条盖着页面底部：等它自己收起来再点主按钮。
      await tester.pump(const Duration(seconds: 5));
      await settle(tester, rounds: 2);

      await tapOn(tester, find.byKey(const Key('deploy-start')), rounds: 4);
      expect(find.text('确认推送并启动'), findsWidgets);
      expect(find.text('shuang/demo'), findsWidgets, reason: '表单里一处、确认清单里一处');
      expect(find.text('只构建并上传产物，不部署'), findsOneWidget);
      expect(find.textContaining('推送 3 个文件'), findsOneWidget);
      await tester.tap(find.byKey(const Key('deploy-files-toggle')));
      await settle(tester, rounds: 2);
      expect(find.textContaining('.env  — 密钥 / 凭据类文件'), findsOneWidget);
      await shot(tester, 'deploy-12-github-confirm-light');
      await tester.tap(find.byKey(const Key('deploy-confirm-cancel')));
      await settle(tester, rounds: 3);
      expect(gh.requests, isEmpty, reason: '没点确认就不联网');
      expect(env.services.container.read(deployGithubProvider(session)).phase, DeployPhase.idle);

      await tapOn(tester, find.byKey(const Key('deploy-start')), rounds: 4);
      await tester.tap(find.byKey(const Key('deploy-confirm')));
      await settle(tester, rounds: 8);
      final state = env.services.container.read(deployGithubProvider(session));
      expect(state.phase, DeployPhase.done, reason: state.failure);
      expect(gh.pushedPaths, {'.github/workflows/deploy.yml', 'go.mod', 'main.go'});
      expect(gh.dispatchBody!['inputs'], {'deploy': 'false'});
      await toBottom(tester);
      expect(find.text('构建完了'), findsOneWidget);
      expect(find.text('https://github.com/shuang/demo/actions/runs/77'), findsOneWidget);
      expect(find.textContaining('tok-SECRET-123'), findsNothing);
      await shot(tester, 'deploy-13-github-done-light');
    });

    testWidgets('403 缺改工作流的权限：卡片上大白话说去哪开', (tester) async {
      await ready(tester);
      await tester.runAsync(() => env.services.container.read(deployGithubProvider(session).notifier).writeWorkflow('name: x\n'));
      gh.refStatus = 403;
      await settle(tester, rounds: 2);
      await tapOn(tester, find.byKey(const Key('deploy-start')), rounds: 4);
      await tester.tap(find.byKey(const Key('deploy-confirm')));
      await settle(tester, rounds: 8);
      await toBottom(tester);
      final reason = tester.widget<Text>(find.descendant(of: find.byKey(const Key('deploy-failure')), matching: find.byType(Text))).data!;
      expect(reason, allOf(contains('Workflows 设成 Read and write'), contains('勾上 workflow'), contains('Developer settings')));
      await shot(tester, 'deploy-14-github-403-light');
    });
  });

  group('SSH 部署', () {
    Future<void> ready(WidgetTester tester) async {
      await boot(tester);
      await tester.runAsync(() async {
        final s = env.services.settings;
        await s.set(SettingKeys.sshHost, 'example.test');
        await s.set(SettingKeys.sshUser, 'deploy');
        await s.set(deployKey(SettingKeys.deployMode, session), 'ssh');
      });
      await show(tester);
    }

    testWidgets('没配主机就点主按钮：提示去配，不连接', (tester) async {
      await boot(tester);
      await set(tester, deployKey(SettingKeys.deployMode, session), 'ssh');
      await show(tester);
      await tapOn(tester, find.byKey(const Key('deploy-start')), rounds: 4);
      expect(find.textContaining('还没配 SSH 主机'), findsOneWidget);
      expect(remote.connected, isFalse);
    });

    testWidgets('命令清单先完整显示；取消不连接；确认后照清单执行', (tester) async {
      await ready(tester);
      expect(find.text('deploy@example.test'), findsOneWidget);
      await tapOn(tester, find.byKey(const Key('deploy-ssh-restart-on')));
      await reveal(tester, find.byKey(const Key('deploy-ssh-restart')));
      await tester.enterText(find.byKey(const Key('deploy-ssh-restart')), 'systemctl restart api');
      await tapOn(tester, find.byKey(const Key('deploy-start')), rounds: 4);
      expect(find.text('确认要执行的步骤'), findsOneWidget);
      for (final command in [
        "mkdir -p ~/'lopicode-deploy/api'",
        "cd ~/'lopicode-deploy/api' && tar -xzf lopicode-upload.tar.gz --strip-components=1",
        "cd ~/'lopicode-deploy/api' && go build -buildvcs=false -o server .",
        "cd ~/'lopicode-deploy/api' && systemctl restart api",
      ]) {
        expect(find.text(command, skipOffstage: false), findsOneWidget, reason: command);
      }
      await shot(tester, 'deploy-21-ssh-confirm-light');
      await tester.tap(find.byKey(const Key('deploy-confirm-cancel')));
      await settle(tester, rounds: 3);
      expect(remote.connected, isFalse, reason: '没点确认就不连接');

      await tapOn(tester, find.byKey(const Key('deploy-start')), rounds: 4);
      await tester.tap(find.byKey(const Key('deploy-confirm')));
      await settle(tester, rounds: 8);
      final state = env.services.container.read(deploySshProvider(session));
      expect(state.phase, DeployPhase.done, reason: state.failure);
      expect(remote.commands.last, "cd ~/'lopicode-deploy/api' && systemctl restart api");
      expect(remote.uploads.keys.single, '/home/deploy/lopicode-deploy/api/lopicode-upload.tar.gz');
      await toBottom(tester);
      expect(find.text('部署完了'), findsOneWidget);
      expect(find.textContaining('built ok'), findsOneWidget);
      await shot(tester, 'deploy-22-ssh-done-light');
    });

    testWidgets('某步失败：停住，卡片说第几步和退出码', (tester) async {
      await ready(tester);
      remote.exitCodes['go build'] = 2;
      await tapOn(tester, find.byKey(const Key('deploy-start')), rounds: 4);
      await tester.tap(find.byKey(const Key('deploy-confirm')));
      await settle(tester, rounds: 8);
      await toBottom(tester);
      final reason = tester.widget<Text>(find.descendant(of: find.byKey(const Key('deploy-failure')), matching: find.byType(Text))).data!;
      expect(reason, allOf(contains('第 4 步'), contains('退出码 2')));
      await shot(tester, 'deploy-23-ssh-failed-light');
    });
  });
}
