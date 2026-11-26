// “构建与部署”测试用的三个假东西：假运行环境、假 GitHub（HTTP 层）、假 SSH。
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lopicode/build/deploy_backends.dart';
import 'package:lopicode/build/remote_exec.dart';
import 'package:lopicode/runtime/pack_install.dart';
import 'package:lopicode/ssh/ssh_connector.dart';

class FakeGuest implements DeployGuest {
  FakeGuest(this.projectDir);
  final String Function() projectDir;

  @override
  GuestStatus status = GuestStatus.ready;
  final Set<String> installed = {'node', 'python', 'go', 'java', 'php'};
  final Set<String> bigPacks = {};
  final List<String> commands = [];
  final List<String> installs = [];
  String? installFails;
  bool stopped = false;
  bool installCancelled = false;
  String output = '编译输出\n';
  GuestRunResult Function(String command)? onRun;
  Future<GuestRunResult> Function(String command)? onRunAsync;

  static const _titles = {'node': 'Node.js', 'python': 'Python', 'go': 'Go', 'java': 'Java（JDK）', 'php': 'PHP'};

  @override
  GuestPack? pack(String id) => _titles.containsKey(id) ? GuestPack(id: id, title: _titles[id]!, sizeNote: bigPacks.contains(id) ? '要下载约 130 MB' : null, needsConfirm: bigPacks.contains(id)) : null;

  @override
  Future<bool?> hasPack(String id) async => installed.contains(id);

  @override
  Future<PackInstallResult> installPack(String id, {required void Function(String line) onLine}) async {
    installs.add(id);
    onLine('正在装 $id');
    if (installFails != null) return PackInstallResult.failed(PackFailure.other, installFails!);
    installed.add(id);
    return const PackInstallResult.ok();
  }

  @override
  void cancelInstall() => installCancelled = true;

  @override
  Future<GuestRunResult> run(String command, {required void Function(String chunk) onOutput, required Future<void> stop}) async {
    commands.add(command);
    unawaited(stop.then((_) => stopped = true));
    onOutput(output);
    if (onRunAsync != null) return onRunAsync!(command);
    return onRun?.call(command) ?? const GuestRunResult(0);
  }
}

/// 假 GitHub：只认“推送、触发、查运行”要用到的那几个接口。仓库固定是 shuang/demo。
class FakeGitHubHttp {
  final List<http.Request> requests = [];
  final Set<String> pushedPaths = {};
  Map<String, dynamic>? dispatchBody;
  String? dispatchPath;
  int refStatus = 200;
  Object? failWith;
  String conclusion = 'success';
  bool neverCompletes = false;
  int runPolls = 0;

  late final http.Client client = MockClient(_handle);

  Future<http.Response> _handle(http.Request req) async {
    requests.add(req);
    final fail = failWith;
    if (fail != null) throw fail;
    http.Response json(int status, Object data) => http.Response(jsonEncode(data), status, headers: {'content-type': 'application/json; charset=utf-8'});
    final path = req.url.path.replaceFirst('/repos/shuang/demo', '');
    if (req.method == 'GET' && path == '/git/ref/heads/main') {
      return json(200, {
        'object': {'sha': 'parent'},
      });
    }
    if (req.method == 'GET' && path == '/git/commits/parent') {
      return json(200, {
        'tree': {'sha': 'basetree'},
      });
    }
    if (req.method == 'POST' && path == '/git/blobs') return json(201, {'sha': 'blob${requests.length}'});
    if (req.method == 'POST' && path == '/git/trees') {
      for (final item in (jsonDecode(req.body) as Map)['tree'] as List) {
        pushedPaths.add((item as Map)['path'] as String);
      }
      return json(201, {'sha': 'newtree'});
    }
    if (req.method == 'POST' && path == '/git/commits') return json(201, {'sha': 'abcdef1234567'});
    if (req.method == 'PATCH' && path == '/git/refs/heads/main') {
      // 令牌没有改工作流的权限：GitHub 在更新分支这一步拒绝。
      if (refStatus != 200) return json(refStatus, {'message': 'Resource not accessible by personal access token'});
      return json(200, {});
    }
    if (req.method == 'POST' && path.endsWith('/dispatches')) {
      dispatchPath = path;
      dispatchBody = jsonDecode(req.body) as Map<String, dynamic>;
      return json(200, {'workflow_run_id': 77});
    }
    if (req.method == 'GET' && path == '/actions/runs/77') {
      runPolls++;
      final done = !neverCompletes && runPolls >= 2;
      return json(200, {
        'id': 77,
        'status': done ? 'completed' : 'in_progress',
        'conclusion': done ? conclusion : null,
        'html_url': 'https://github.com/shuang/demo/actions/runs/77',
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });
    }
    return json(404, {'message': 'Not Found: ${req.method} $path'});
  }
}

class FakeRemote implements RemoteExec {
  bool connected = false;
  bool closed = false;
  String? connectError;
  final List<String> commands = [];
  final Map<String, List<int>> uploads = {};

  /// 命令里含这个字就返回这个退出码。
  final Map<String, int> exitCodes = {};

  /// 命令里含这个字就卡住，直到测试放行。
  final Map<String, Completer<int?>> hold = {};

  @override
  Future<void> connect() async {
    if (connectError != null) throw SshConnectException(connectError!);
    connected = true;
  }

  @override
  Future<int?> run(String command, {required void Function(String chunk) onOutput}) async {
    commands.add(command);
    for (final e in hold.entries) {
      if (command.contains(e.key)) return e.value.future;
    }
    for (final e in exitCodes.entries) {
      if (command.contains(e.key)) {
        onOutput('boom\n');
        return e.value;
      }
    }
    if (command.endsWith('&& pwd')) {
      onOutput('/home/deploy/lopicode-deploy/api\n');
    } else if (command.contains('go build')) {
      onOutput('built ok\n');
    }
    return 0;
  }

  @override
  Future<void> upload(String remotePath, List<int> bytes) async => uploads[remotePath] = bytes;

  @override
  Future<int> download(String remotePath, File target, {void Function(int received, int? total)? onProgress}) async => 0;

  @override
  Future<void> close() async => closed = true;
}
