import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/build/github_client.dart';

class Recorded {
  Recorded(this.method, this.path, this.query, this.headers, this.body);
  final String method;
  final String path;
  final Map<String, String> query;
  final HttpHeaders headers;
  final String body;
  Map<String, dynamic> get json => jsonDecode(body) as Map<String, dynamic>;
}

/// 假 GitHub：只实现客户端用到的那几个接口。
class FakeGitHub {
  late HttpServer server;
  final List<Recorded> requests = [];
  bool supportsRunDetails = true;
  bool rejectUnknownField = false;
  int runPolls = 0;
  int dispatchStatus = 0; // 非 0 时强制返回这个状态码
  late Uint8List artifactZip;

  String get base => 'http://127.0.0.1:${server.port}';

  Future<void> start() async {
    final archive = Archive()
      ..addFile(ArchiveFile('app-debug.apk', 4, [80, 75, 3, 4]))
      ..addFile(ArchiveFile('notes.txt', 2, [104, 105]));
    artifactZip = Uint8List.fromList(ZipEncoder().encode(archive)!);
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen(_handle);
  }

  Future<void> stop() => server.close(force: true);

  Future<void> _handle(HttpRequest req) async {
    final body = await utf8.decoder.bind(req).join();
    final path = req.uri.path;
    requests.add(Recorded(req.method, path, req.uri.queryParameters, req.headers, body));
    final res = req.response;
    void json(int status, Object data) {
      res.statusCode = status;
      res.headers.contentType = ContentType.json;
      res.write(jsonEncode(data));
    }

    const repo = '/repos/shuang/demo';
    if (path == '/blob-storage/artifact.zip') {
      // 存储服务：带了 GitHub 的 Authorization 就拒绝（真实的 Azure 存储也会）
      if (req.headers.value('authorization') != null) {
        res.statusCode = 400;
      } else {
        res.add(artifactZip);
      }
    } else if (req.headers.value('authorization') != 'Bearer ghp_test') {
      json(401, {'message': 'Bad credentials'});
    } else if (req.method == 'POST' && path == '$repo/actions/workflows/android.yml/dispatches') {
      final data = jsonDecode(body) as Map<String, dynamic>;
      if (dispatchStatus != 0) {
        json(dispatchStatus, {'message': 'Workflow does not have workflow_dispatch trigger'});
      } else if (rejectUnknownField && data.containsKey('return_run_details')) {
        json(422, {'message': 'Invalid request. "return_run_details" is not a permitted key.'});
      } else if (supportsRunDetails && data['return_run_details'] == true) {
        json(200, {'workflow_run_id': 777, 'run_url': '$base$repo/actions/runs/777', 'html_url': 'https://github.com/shuang/demo/actions/runs/777'});
      } else {
        res.statusCode = 204;
      }
    } else if (req.method == 'GET' && path == '$repo/actions/workflows/android.yml/runs') {
      json(200, {
        'total_count': 2,
        'workflow_runs': [
          {'id': 778, 'status': 'queued', 'conclusion': null, 'html_url': 'h', 'created_at': DateTime.now().toUtc().toIso8601String()},
          {'id': 700, 'status': 'completed', 'conclusion': 'success', 'html_url': 'h', 'created_at': '2020-01-01T00:00:00Z'},
        ],
      });
    } else if (req.method == 'GET' && path == '$repo/actions/runs/777') {
      runPolls++;
      json(200, {
        'id': 777,
        'status': runPolls < 3 ? 'in_progress' : 'completed',
        'conclusion': runPolls < 3 ? null : 'success',
        'html_url': 'https://github.com/shuang/demo/actions/runs/777',
        'created_at': '2026-11-22T20:00:00Z',
      });
    } else if (req.method == 'GET' && path == '$repo/actions/runs/777/artifacts') {
      json(200, {
        'total_count': 2,
        'artifacts': [
          {'id': 11, 'name': 'app-debug', 'size_in_bytes': artifactZip.length, 'expired': false, 'archive_download_url': 'x'},
          {'id': 12, 'name': 'old', 'size_in_bytes': 5, 'expired': true, 'archive_download_url': 'x'},
        ],
      });
    } else if (req.method == 'GET' && path == '$repo/actions/artifacts/11/zip') {
      res.statusCode = 302;
      res.headers.set('location', '$base/blob-storage/artifact.zip');
    } else if (req.method == 'GET' && path == '$repo/actions/artifacts/12/zip') {
      json(410, {'message': 'Artifact has expired'});
    } else if (req.method == 'GET' && path == '$repo/git/ref/heads/main') {
      json(200, {'ref': 'refs/heads/main', 'object': {'sha': 'parent111', 'type': 'commit'}});
    } else if (req.method == 'GET' && path == '$repo/git/commits/parent111') {
      json(200, {'sha': 'parent111', 'tree': {'sha': 'tree000'}});
    } else if (req.method == 'POST' && path == '$repo/git/blobs') {
      json(201, {'sha': 'blob${requests.where((r) => r.path.endsWith('/git/blobs')).length}'});
    } else if (req.method == 'POST' && path == '$repo/git/trees') {
      json(201, {'sha': 'tree999'});
    } else if (req.method == 'POST' && path == '$repo/git/commits') {
      json(201, {'sha': 'commit222'});
    } else if (req.method == 'PATCH' && path == '$repo/git/refs/heads/main') {
      json(200, {'ref': 'refs/heads/main', 'object': {'sha': 'commit222'}});
    } else {
      json(404, {'message': 'Not Found'});
    }
    await res.close();
  }
}

void main() {
  late FakeGitHub gh;
  late GitHubClient client;

  setUp(() async {
    gh = FakeGitHub();
    await gh.start();
    client = GitHubClient(token: 'ghp_test', owner: 'shuang', repo: 'demo', baseUrl: gh.base);
  });
  tearDown(() => gh.stop());

  test('触发工作流：带标准请求头，直接拿到运行 ID', () async {
    final id = await client.dispatchWorkflow('android.yml', 'main', inputs: {'mode': 'debug'});
    expect(id, 777);
    final r = gh.requests.single;
    expect(r.method, 'POST');
    expect(r.headers.value('accept'), 'application/vnd.github+json');
    expect(r.headers.value('x-github-api-version'), GitHubClient.apiVersion);
    expect(r.json['ref'], 'main');
    expect(r.json['inputs'], {'mode': 'debug'});
    expect(r.json['return_run_details'], true);
  });

  test('老接口返回 204：回退到按时间找最近一次运行', () async {
    gh.supportsRunDetails = false;
    final before = DateTime.now();
    expect(await client.dispatchWorkflow('android.yml', 'main'), isNull);
    final run = await client.findLatestDispatchRun('android.yml', 'main', before);
    expect(run!.id, 778);
    expect(gh.requests.last.query, containsPair('event', 'workflow_dispatch'));
    expect(gh.requests.last.query, containsPair('branch', 'main'));
    // 只有很久以前的运行时，不会误认
    final none = await client.findLatestDispatchRun('android.yml', 'main', DateTime.now().add(const Duration(hours: 1)));
    expect(none, isNull);
  });

  test('服务器不认识 return_run_details：去掉字段重试一次', () async {
    gh.rejectUnknownField = true;
    expect(await client.dispatchWorkflow('android.yml', 'main'), isNull);
    expect(gh.requests.length, 2);
    expect(gh.requests[1].json.containsKey('return_run_details'), isFalse);
  });

  test('轮询运行状态直到完成', () async {
    var run = await client.getRun(777);
    expect(run.isCompleted, isFalse);
    run = await client.getRun(777);
    run = await client.getRun(777);
    expect(run.isCompleted, isTrue);
    expect(run.isSuccess, isTrue);
    expect(run.htmlUrl, contains('/actions/runs/777'));
  });

  test('列出产物、跟随 302 下载（不把 Token 带给存储服务）、解出 APK', () async {
    final artifacts = await client.listArtifacts(777);
    expect(artifacts.map((a) => a.name), ['app-debug', 'old']);
    expect(artifacts[1].expired, isTrue);
    final zip = await client.downloadArtifactZip(artifacts.first.id);
    expect(zip, gh.artifactZip);
    final storage = gh.requests.firstWhere((r) => r.path.startsWith('/blob-storage'));
    expect(storage.headers.value('authorization'), isNull);
    final apks = GitHubClient.extractApks(zip);
    expect(apks.single.name, 'app-debug.apk');
    expect(apks.single.bytes, [80, 75, 3, 4]);
  });

  test('过期产物、坏 zip 给出明确错误', () async {
    await expectLater(client.downloadArtifactZip(12), throwsA(isA<GitHubException>().having((e) => e.message, 'message', contains('过期'))));
    expect(() => GitHubClient.extractApks(Uint8List.fromList([1, 2, 3])), throwsA(isA<GitHubException>()));
  });

  test('推送文件：blob → tree → commit → 更新分支', () async {
    final progress = <int>[];
    final sha = await client.pushFiles(
      branch: 'main',
      files: {'index.html': utf8.encode('<h1>你好</h1>'), '.github/workflows/android.yml': utf8.encode('name: x')},
      message: 'LopiCode 同步',
      onProgress: (done, total) => progress.add(done),
    );
    expect(sha, 'commit222');
    expect(progress, [1, 2]);
    expect(gh.requests.map((r) => '${r.method} ${r.path.split('/demo').last}'), [
      'GET /git/ref/heads/main',
      'GET /git/commits/parent111',
      'POST /git/blobs',
      'POST /git/blobs',
      'POST /git/trees',
      'POST /git/commits',
      'PATCH /git/refs/heads/main',
    ]);
    final blob = gh.requests[2].json;
    expect(blob['encoding'], 'base64');
    expect(utf8.decode(base64Decode(blob['content'] as String)), '<h1>你好</h1>');
    final tree = gh.requests[4].json;
    expect(tree['base_tree'], 'tree000');
    expect((tree['tree'] as List).map((e) => e['path']), ['index.html', '.github/workflows/android.yml']);
    expect((tree['tree'] as List).first, containsPair('mode', '100644'));
    final commit = gh.requests[5].json;
    expect(commit['parents'], ['parent111']);
    expect(commit['tree'], 'tree999');
    expect(gh.requests[6].json['sha'], 'commit222');
  });

  test('错误信息说人话，且不包含 Token', () async {
    final bad = GitHubClient(token: 'ghp_wrong_secret', owner: 'shuang', repo: 'demo', baseUrl: gh.base);
    await expectLater(
      bad.getRun(777),
      throwsA(isA<GitHubException>()
          .having((e) => e.statusCode, 'status', 401)
          .having((e) => e.message, 'message', allOf(contains('Token'), isNot(contains('ghp_wrong_secret'))))),
    );
    await expectLater(client.getRun(999), throwsA(isA<GitHubException>().having((e) => e.statusCode, 'status', 404)));
    gh.dispatchStatus = 422;
    await expectLater(
      client.dispatchWorkflow('android.yml', 'main'),
      throwsA(isA<GitHubException>().having((e) => e.message, 'message', contains('workflow_dispatch'))),
    );
    final offline = GitHubClient(token: 'ghp_wrong_secret', owner: 'a', repo: 'b', baseUrl: 'http://127.0.0.1:1');
    await expectLater(offline.getRun(1), throwsA(isA<GitHubException>().having((e) => e.message, 'message', isNot(contains('ghp_')))));
  });
}
