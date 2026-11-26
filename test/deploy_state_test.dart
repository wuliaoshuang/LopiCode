// “构建与部署”的状态层：本地构建、GitHub 部署、SSH 部署三个 Notifier。
// 都用假的：假运行环境（不起进程）、假 HTTP（不联网）、假 RemoteExec（不连 SSH）。
import 'dart:async';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/build/deploy_backends.dart';
import 'package:lopicode/build/deploy_commands.dart';
import 'package:lopicode/build/deploy_files.dart';
import 'package:lopicode/build/deploy_project.dart';
import 'package:lopicode/build/github_client.dart';
import 'package:lopicode/core/project_store.dart';
import 'package:lopicode/core/safe_file.dart';
import 'package:lopicode/core/stores.dart';
import 'package:lopicode/core/templates.dart';
import 'package:lopicode/project_session.dart';
import 'package:lopicode/state/deploy_busy.dart';
import 'package:lopicode/state/deploy_github.dart';
import 'package:lopicode/state/deploy_local.dart';
import 'package:lopicode/state/deploy_run.dart';
import 'package:lopicode/state/deploy_ssh.dart';
import 'package:path/path.dart' as p;
import 'package:riverpod/riverpod.dart';

import 'support/fake_deploy.dart';
import 'support/harness.dart';

void main() {
  late TestEnv env;
  late ProviderContainer box;
  late Project project;
  late ProjectSession session;
  late FakeGuest guest;

  Future<void> boot({String language = 'go', Map<String, String>? files}) async {
    project = await env.services.projects.create('api', ProjectTemplate.backendCode, language: language, files: files ?? {'main.go': 'package main\nfunc main() {}\n', 'go.mod': 'module api\n'});
    session = ProjectSession(env.services, project, headless: true);
  }

  setUp(() async {
    env = await TestEnv.create();
    box = env.services.container;
    guest = FakeGuest(() => project.dir);
    deployGuestOverride = (_) => guest;
    deployPollInterval = const Duration(milliseconds: 5);
  });
  tearDown(() async {
    session.dispose();
    await pendingWrites();
    await env.dispose();
    deployGuestOverride = null;
    deployGitHubOverride = null;
    deployRemoteExecOverride = null;
    deployPollInterval = const Duration(seconds: 6);
    deployPollTimeout = const Duration(minutes: 40);
  });

  Future<void> until(bool Function() ok) async {
    for (var i = 0; i < 500 && !ok(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  DeployProject detected() => box.read(deployProjectProvider(session));

  group('类型和方式', () {
    test('后端模板 → 后端；手动改成网页后跟着变，并按工作区记', () async {
      await boot();
      expect(detected().kind, ProjectKind.backend);
      expect(detected().lang, DeployLang.go);
      await env.services.settings.set(deployKey(SettingKeys.deployKind, session), 'web');
      expect(detected().kind, ProjectKind.web);
      expect(detected().auto, isFalse);
      await env.services.settings.set(deployKey(SettingKeys.deployKind, session), null);
      expect(detected().kind, ProjectKind.backend);
    });

    test('方式默认本地，和 apk.buildMode 互不影响', () async {
      await boot();
      await env.services.settings.set(SettingKeys.apkBuildMode, 'ssh');
      expect(box.read(deployModeProvider(session)), DeployMode.local);
      await env.services.settings.set(deployKey(SettingKeys.deployMode, session), 'github');
      expect(box.read(deployModeProvider(session)), DeployMode.github);
      expect(env.services.settings.getString(SettingKeys.apkBuildMode), 'ssh');
    });

    test('日志：去掉终端控制符，超长丢前面', () {
      var s = const DeployRunState().addLog('\x1b[2m[Agent] \$ go build\x1b[0m\r\nok\r\n');
      expect(s.log, '[Agent] \$ go build\nok\n');
      s = s.addLog('x' * (kDeployLogMax + 10));
      expect(s.log.length, kDeployLogMax);
    });
  });

  group('本地构建', () {
    DeployLocalNotifier n() => box.read(deployLocalProvider(session).notifier);
    DeployRunState st() => box.read(deployLocalProvider(session));

    test('成功：Go 编译出程序，结果卡有文件名、大小、位置、怎么用', () async {
      await boot();
      guest.onRun = (cmd) {
        File(p.join(project.dir, 'build', 'api-linux-arm64'))
          ..parent.createSync(recursive: true)
          ..writeAsBytesSync(List.filled(2048, 1));
        return const GuestRunResult(0);
      };
      await n().start(detected());
      expect(st().phase, DeployPhase.done);
      expect(guest.commands.single, contains('GOARCH=arm64 go build'));
      expect(st().result!.fileName, 'api-linux-arm64');
      expect(st().result!.bytes, 2048);
      expect(st().result!.location, 'build/api-linux-arm64');
      expect(st().result!.notes.join(), contains('chmod +x'));
      expect(st().steps.single.status, StepStatus.ok);
      expect(st().log, contains('编译输出'));
    });

    test('amd64 开关换架构', () async {
      await boot();
      guest.onRun = (cmd) {
        File(p.join(project.dir, 'build', 'api-linux-amd64'))
          ..parent.createSync(recursive: true)
          ..writeAsStringSync('bin');
        return const GuestRunResult(0);
      };
      await n().start(detected(), amd64: true);
      expect(guest.commands.single, contains('GOARCH=amd64'));
      expect(st().result!.fileName, 'api-linux-amd64');
    });

    test('编译失败：停住，说清第几步和退出码，输出留着', () async {
      await boot();
      guest.onRun = (_) => const GuestRunResult(2);
      guest.output = './main.go:3:1: syntax error\n';
      await n().start(detected());
      expect(st().phase, DeployPhase.failed);
      expect(st().failure, allOf(contains('第 1 步'), contains('退出码 2')));
      expect(st().log, contains('syntax error'));
      expect(st().steps.single.status, StepStatus.failed);
      expect(st().needsRuntime, isFalse);
    });

    test('命令说成功了但没产物：算失败', () async {
      await boot();
      await n().start(detected());
      expect(st().phase, DeployPhase.failed);
      expect(st().failure, contains('没有 api-linux-arm64'));
    });

    test('运行环境没装：不跑命令，给“去装运行环境”', () async {
      await boot();
      guest.status = GuestStatus.notInstalled;
      await n().start(detected());
      expect(st().phase, DeployPhase.failed);
      expect(st().needsRuntime, isTrue);
      expect(guest.commands, isEmpty);
    });

    test('缺语言 → 自动装 → 继续', () async {
      await boot(language: 'python', files: {'main.py': 'print(1)\n'});
      guest.installed.clear();
      await n().start(detected());
      expect(guest.installs, ['python']);
      expect(st().phase, DeployPhase.done);
      expect(st().log, contains('正在装 python'));
    });

    test('缺的语言包很大：先问；不同意就停，同意才装', () async {
      await boot(language: 'java', files: {'Main.java': 'public class Main { public static void main(String[] a) {} }\n'});
      guest.installed.clear();
      guest.bigPacks.add('java');
      final run = n().start(detected());
      await until(() => st().ask != null);
      expect(st().ask, contains('Java'));
      expect(guest.installs, isEmpty);
      n().answerInstall(false);
      await run;
      expect(st().phase, DeployPhase.failed);
      expect(guest.installs, isEmpty);
      expect(guest.commands, isEmpty);

      guest.onRun = (cmd) {
        File(p.join(project.dir, 'build', 'api.jar'))
          ..parent.createSync(recursive: true)
          ..writeAsStringSync('jar');
        return const GuestRunResult(0);
      };
      final again = n().start(detected());
      await until(() => st().ask != null);
      n().answerInstall(true);
      await again;
      expect(guest.installs, ['java']);
      expect(st().phase, DeployPhase.done);
      expect(st().result!.fileName, 'api.jar');
    });

    test('装语言失败：停住并带原因', () async {
      await boot(language: 'python', files: {'main.py': 'print(1)\n'});
      guest.installed.clear();
      guest.installFails = '连不上软件源';
      await n().start(detected());
      expect(st().phase, DeployPhase.failed);
      expect(st().failure, contains('连不上软件源'));
      expect(guest.commands, isEmpty);
    });

    test('取消：正在跑的命令被停掉，晚回来的结果不写状态', () async {
      await boot();
      final gate = Completer<GuestRunResult>();
      guest.onRunAsync = (_) => gate.future;
      final run = n().start(detected());
      await until(() => guest.commands.isNotEmpty);
      expect(box.read(deployBusyProvider(session)), isTrue);
      n().cancel();
      expect(st().phase, DeployPhase.cancelled);
      await Future<void>.delayed(Duration.zero);
      expect(guest.stopped, isTrue);
      gate.complete(const GuestRunResult(0));
      await run;
      expect(st().phase, DeployPhase.cancelled);
      expect(box.read(deployBusyProvider(session)), isFalse);
    });

    test('进行中再点开始不受理', () async {
      await boot();
      final gate = Completer<GuestRunResult>();
      guest.onRunAsync = (_) => gate.future;
      final run = n().start(detected());
      await until(() => guest.commands.isNotEmpty);
      expect(await n().start(detected()), isFalse);
      gate.complete(const GuestRunResult(1));
      await run;
    });

    test('Python：语法检查 + 压缩包；密钥和 build 不进包', () async {
      await boot(language: 'python', files: {'main.py': 'print(1)\n', 'requirements.txt': 'flask\n', '.env': 'SECRET=1\n', 'build/old.txt': 'x'});
      await n().start(detected());
      expect(st().phase, DeployPhase.done, reason: st().failure);
      expect(guest.commands.single, contains('py_compile'));
      final out = File(p.join(project.dir, 'build', 'api-python.tar.gz'));
      final names = TarDecoder().decodeBytes(GZipDecoder().decodeBytes(out.readAsBytesSync())).files.map((f) => f.name).toSet();
      expect(names, {'api/main.py', 'api/requirements.txt'});
      expect(st().result!.notes.join(), contains('pip install -r requirements.txt'));
      expect(st().steps.map((s) => s.status), everyElement(StepStatus.ok));
    });

    test('其它语言：不需要运行环境，直接打源码包', () async {
      await boot(language: 'rust', files: {'main.rs': 'fn main() {}\n'});
      guest.status = GuestStatus.notInstalled;
      await n().start(detected());
      expect(st().phase, DeployPhase.done, reason: st().failure);
      expect(File(p.join(project.dir, 'build', 'api-source.tar.gz')).existsSync(), isTrue);
    });

    test('带包名的 Java：本地做不了，说清原因，不跑命令', () async {
      await boot(language: 'java', files: {'App.java': 'package com.x;\npublic class App {}\n'});
      await n().start(detected());
      expect(st().phase, DeployPhase.failed);
      expect(st().failure, contains('package'));
      expect(guest.commands, isEmpty);
    });

    test('工作区关掉以后回来的结果丢掉', () async {
      await boot();
      final gate = Completer<GuestRunResult>();
      guest.onRunAsync = (_) => gate.future;
      final notifier = n();
      final run = notifier.start(detected());
      await until(() => guest.commands.isNotEmpty);
      session.dispose();
      gate.complete(const GuestRunResult(0));
      await run;
      expect(notifier.current.phase, DeployPhase.running, reason: '关掉以后什么都不写');
    });
  });

  group('GitHub 部署', () {
    DeployGithubNotifier n() => box.read(deployGithubProvider(session).notifier);
    DeployRunState st() => box.read(deployGithubProvider(session));
    late FakeGitHubHttp gh;

    Future<void> ready() async {
      await boot();
      gh = FakeGitHubHttp();
      deployGitHubOverride = (token, owner, repo) => GitHubClient(token: token, owner: owner, repo: repo, baseUrl: 'https://gh.test', httpClient: gh.client);
      final s = env.services.settings;
      await s.set(SettingKeys.githubOwner, 'shuang');
      await s.set(SettingKeys.githubRepo, 'demo');
      await s.set(SettingKeys.githubRef, 'main');
      await env.services.secrets.write(SecretKeys.githubToken, 'tok-SECRET-123');
    }

    test('没填仓库 / 没令牌 / 没工作流：plan 直接说缺什么', () async {
      await boot();
      await expectLater(n().plan(), throwsA(isA<DeployException>().having((e) => e.message, 'message', contains('仓库'))));
      await env.services.settings.set(SettingKeys.githubOwner, 'shuang');
      await env.services.settings.set(SettingKeys.githubRepo, 'demo');
      await expectLater(n().plan(), throwsA(isA<DeployException>().having((e) => e.message, 'message', contains('令牌'))));
      await env.services.secrets.write(SecretKeys.githubToken, 't');
      await expectLater(n().plan(), throwsA(isA<DeployException>().having((e) => e.message, 'message', contains('工作流'))));
    });

    test('工作流：先生成给她看，写进项目才落盘；之后读的是项目里那份', () async {
      await ready();
      expect(n().workflowExists, isFalse);
      final text = await n().workflowText(detected());
      expect(text, contains('actions/setup-go@v5'));
      expect(n().workflowExists, isFalse, reason: '只是看，不落盘');
      await n().writeWorkflow('$text# 我改的');
      expect(n().workflowExists, isTrue);
      expect(await n().workflowText(detected()), endsWith('# 我改的\n'));
    });

    test('成功：推送（不带密钥文件）→ 触发 deploy=false → 轮询 → 结论和运行页链接', () async {
      await ready();
      File(p.join(project.dir, '.env')).writeAsStringSync('SECRET=1');
      await n().writeWorkflow(await n().workflowText(detected()));
      final plan = await n().plan();
      expect(plan.touchesWorkflows, isTrue);
      expect(plan.files.files.map((f) => f.rel), ['.github/workflows/deploy.yml', 'go.mod', 'main.go']);
      expect(plan.files.skipped.map((s) => s.rel), contains('.env'));
      expect(gh.requests, isEmpty, reason: '看清单不联网');
      await n().start(plan);
      expect(st().phase, DeployPhase.done, reason: st().failure);
      expect(st().result!.url, 'https://github.com/shuang/demo/actions/runs/77');
      expect(gh.pushedPaths, {'.github/workflows/deploy.yml', 'go.mod', 'main.go'});
      expect(gh.dispatchBody!['inputs'], {'deploy': 'false'});
      expect(gh.dispatchBody!['ref'], 'main');
      expect(gh.dispatchPath, contains('/actions/workflows/deploy.yml/dispatches'));
      expect(st().steps.map((s) => s.status), everyElement(StepStatus.ok));
      expect('${st().log}${st().headline}${st().failure}', isNot(contains('tok-SECRET-123')));
    });

    test('打开“构建完部署”：触发时带 deploy=true', () async {
      await ready();
      await n().writeWorkflow('name: x\n');
      await env.services.settings.set(deployKey(SettingKeys.githubDeployRun, session), true);
      final plan = await n().plan();
      expect(plan.runDeploy, isTrue);
      await n().start(plan);
      expect(gh.dispatchBody!['inputs'], {'deploy': 'true'});
      expect(st().headline, '构建并部署完了');
    });

    test('403 缺 workflow 权限：大白话说缺什么、去哪开', () async {
      await ready();
      await n().writeWorkflow('name: x\n');
      gh.refStatus = 403;
      await n().start(await n().plan());
      expect(st().phase, DeployPhase.failed);
      expect(st().failure, allOf(contains('Workflows'), contains('Read and write'), contains('workflow'), contains('Developer settings')));
      expect(st().steps.first.status, StepStatus.failed);
      expect(gh.dispatchBody, isNull, reason: '推送没成就不触发');
      expect(st().failure, isNot(contains('tok-SECRET-123')));
    });

    test('超时：GitHub 不响应', () async {
      await ready();
      await n().writeWorkflow('name: x\n');
      gh.failWith = TimeoutException('slow');
      await n().start(await n().plan());
      expect(st().phase, DeployPhase.failed);
      expect(st().failure, contains('没有响应'));
    });

    test('连不上', () async {
      await ready();
      await n().writeWorkflow('name: x\n');
      gh.failWith = const SocketException('no route');
      await n().start(await n().plan());
      expect(st().phase, DeployPhase.failed);
      expect(st().failure, contains('连不上 GitHub'));
    });

    test('工作流跑失败：算失败，给运行页链接', () async {
      await ready();
      await n().writeWorkflow('name: x\n');
      gh.conclusion = 'failure';
      await n().start(await n().plan());
      expect(st().phase, DeployPhase.failed);
      expect(st().failure, contains('failure'));
      expect(st().url, 'https://github.com/shuang/demo/actions/runs/77');
    });

    test('停止等待：之后回来的结果不写', () async {
      await ready();
      await n().writeWorkflow('name: x\n');
      gh.neverCompletes = true;
      final run = n().start(await n().plan());
      await until(() => gh.runPolls > 1);
      n().cancel();
      await run;
      expect(st().phase, DeployPhase.cancelled);
      expect(st().failure, contains('不会被撤回'));
    });

    test('等太久：不等了', () async {
      await ready();
      await n().writeWorkflow('name: x\n');
      gh.neverCompletes = true;
      deployPollTimeout = const Duration(milliseconds: 60);
      await n().start(await n().plan());
      expect(st().phase, DeployPhase.failed);
      expect(st().failure, contains('不等了'));
    });
  });

  group('SSH 部署', () {
    DeploySshNotifier n() => box.read(deploySshProvider(session).notifier);
    DeployRunState st() => box.read(deploySshProvider(session));
    late FakeRemote remote;
    Future<bool> noPrompt(Object a, String b, String c) async => false;

    Future<void> ready() async {
      await boot();
      remote = FakeRemote();
      deployRemoteExecOverride = () => remote;
      final s = env.services.settings;
      await s.set(SettingKeys.sshHost, 'example.test');
      await s.set(SettingKeys.sshUser, 'deploy');
    }

    test('没配主机 / 目录是主目录 / 开了重启没填命令：plan 直接说', () async {
      await boot();
      expect(() => n().plan(detected()), throwsA(isA<DeployException>().having((e) => e.message, 'message', contains('主机'))));
      await ready();
      await env.services.settings.set(deployKey(SettingKeys.deploySshDir, session), '~');
      expect(() => n().plan(detected()), throwsA(isA<DeployException>().having((e) => e.message, 'message', contains('主目录'))));
      await env.services.settings.set(deployKey(SettingKeys.deploySshDir, session), null);
      await env.services.settings.set(deployKey(SettingKeys.deploySshRestartOn, session), true);
      expect(() => n().plan(detected()), throwsA(isA<DeployException>().having((e) => e.message, 'message', contains('重启'))));
    });

    test('默认：目录 ~/lopicode-deploy/<名字>，按语言给编译命令，不重启；改过用她的', () async {
      await ready();
      var plan = n().plan(detected());
      expect(plan.remoteDir, '~/lopicode-deploy/api');
      expect(plan.steps.map((s) => s.title), ['建目录', '上传代码', '解压（同名文件覆盖，远端多出来的文件不动）', '编译 / 装依赖']);
      expect(plan.steps.last.command, "cd ~/'lopicode-deploy/api' && go build -buildvcs=false -o server .");
      final s = env.services.settings;
      await s.set(deployKey(SettingKeys.deploySshBuild, session), '');
      await s.set(deployKey(SettingKeys.deploySshRestartOn, session), true);
      await s.set(deployKey(SettingKeys.deploySshRestart, session), 'systemctl restart api');
      plan = n().plan(detected());
      expect(plan.steps.map((s) => s.title), ['建目录', '上传代码', '解压（同名文件覆盖，远端多出来的文件不动）', '重启服务'], reason: '编译命令清空＝跳过这一步');
      expect(plan.steps.last.command, "cd ~/'lopicode-deploy/api' && systemctl restart api");
    });

    test('成功：执行的就是清单里的命令，上传的包里没有密钥', () async {
      await ready();
      File(p.join(project.dir, '.env')).writeAsStringSync('SECRET=1');
      final plan = n().plan(detected());
      expect(remote.connected, isFalse, reason: '看清单不连接');
      await n().start(plan, onUnknownHost: noPrompt);
      expect(st().phase, DeployPhase.done, reason: st().failure);
      expect(remote.commands, [plan.steps[0].command, sshResolveDirCommand(plan.remoteDir), plan.steps[2].command, plan.steps[3].command]);
      expect(remote.uploads.keys.single, '/home/deploy/lopicode-deploy/api/$kRemoteArchiveName');
      final names = TarDecoder().decodeBytes(GZipDecoder().decodeBytes(remote.uploads.values.single)).files.map((f) => f.name).toSet();
      expect(names, {'upload/go.mod', 'upload/main.go'});
      expect(st().steps.map((s) => s.status), everyElement(StepStatus.ok));
      expect(remote.closed, isTrue);
      expect(st().log, contains('built ok'));
    });

    test('某步失败就停：说清第几步和退出码，后面的不执行', () async {
      await ready();
      await env.services.settings.set(deployKey(SettingKeys.deploySshRestartOn, session), true);
      await env.services.settings.set(deployKey(SettingKeys.deploySshRestart, session), 'systemctl restart api');
      remote.exitCodes['go build'] = 2;
      final plan = n().plan(detected());
      await n().start(plan, onUnknownHost: noPrompt);
      expect(st().phase, DeployPhase.failed);
      expect(st().failure, allOf(contains('第 4 步'), contains('退出码 2'), contains('后面的步骤没有执行')));
      expect(remote.commands.any((c) => c.contains('systemctl')), isFalse);
      expect(st().steps.map((s) => s.status), [StepStatus.ok, StepStatus.ok, StepStatus.ok, StepStatus.failed, StepStatus.pending]);
      expect(remote.closed, isTrue);
    });

    test('连不上：没有执行任何命令', () async {
      await ready();
      remote.connectError = '密码不对';
      await n().start(n().plan(detected()), onUnknownHost: noPrompt);
      expect(st().phase, DeployPhase.failed);
      expect(st().failure, contains('连不上服务器：密码不对'));
      expect(remote.commands, isEmpty);
    });

    test('取消：断开连接，晚回来的结果不写', () async {
      await ready();
      final gate = Completer<int?>();
      remote.hold['go build'] = gate;
      final run = n().start(n().plan(detected()), onUnknownHost: noPrompt);
      await until(() => remote.commands.any((c) => c.contains('go build')));
      n().cancel();
      expect(st().phase, DeployPhase.cancelled);
      expect(remote.closed, isTrue);
      gate.complete(null);
      await run;
      expect(st().phase, DeployPhase.cancelled);
    });
  });
}
