import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:http/http.dart' as http;

/// 普通接口请求的超时。
const Duration kGitHubTimeout = Duration(seconds: 30);

/// 下载构建产物（几十 MB）的超时。
const Duration kGitHubDownloadTimeout = Duration(minutes: 5);

class GitHubException implements Exception {
  GitHubException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;
  @override
  String toString() => message;
}

class WorkflowRun {
  WorkflowRun({required this.id, required this.status, this.conclusion, required this.htmlUrl, this.createdAt});
  final int id;

  /// queued / in_progress / completed 等。
  final String status;

  /// success / failure / cancelled 等；没跑完时为 null。
  final String? conclusion;
  final String htmlUrl;
  final DateTime? createdAt;

  bool get isCompleted => status == 'completed';
  bool get isSuccess => conclusion == 'success';

  factory WorkflowRun.fromJson(Map<String, dynamic> json) => WorkflowRun(
    id: json['id'] as int,
    status: (json['status'] as String?) ?? 'unknown',
    conclusion: json['conclusion'] as String?,
    htmlUrl: (json['html_url'] as String?) ?? '',
    createdAt: DateTime.tryParse(json['created_at'] as String? ?? ''),
  );
}

class RunArtifact {
  RunArtifact({required this.id, required this.name, required this.sizeInBytes, required this.expired});
  final int id;
  final String name;
  final int sizeInBytes;
  final bool expired;

  factory RunArtifact.fromJson(Map<String, dynamic> json) => RunArtifact(
    id: json['id'] as int,
    name: (json['name'] as String?) ?? '',
    sizeInBytes: (json['size_in_bytes'] as int?) ?? 0,
    expired: (json['expired'] as bool?) ?? false,
  );
}

class ExtractedFile {
  ExtractedFile(this.name, this.bytes);
  final String name;
  final Uint8List bytes;
}

/// GitHub REST API 的一小部分：推送文件、触发工作流、查运行状态、下载产物。
/// 用到的接口和字段都对照官方文档核过，见 docs/api-notes.md。
class GitHubClient {
  GitHubClient({
    required this.token,
    required this.owner,
    required this.repo,
    String baseUrl = 'https://api.github.com',
    http.Client? httpClient,
  }) : baseUrl = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl,
       _http = httpClient ?? http.Client();

  final String token;
  final String owner;
  final String repo;
  final String baseUrl;
  final http.Client _http;

  static const String apiVersion = '2022-11-28';

  Map<String, String> get _headers => {
    'Accept': 'application/vnd.github+json',
    'Authorization': 'Bearer $token',
    'X-GitHub-Api-Version': apiVersion,
    'User-Agent': 'LopiCode',
  };

  Uri _uri(String path, [Map<String, String>? query]) =>
      Uri.parse('$baseUrl/repos/$owner/$repo$path').replace(queryParameters: query);

  Future<http.Response> _send(String method, Uri uri, {Object? body}) async {
    final request = http.Request(method, uri)..headers.addAll(_headers);
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    try {
      return await http.Response.fromStream(await _http.send(request)).timeout(kGitHubTimeout);
    } on TimeoutException {
      throw GitHubException('GitHub（${uri.host}）${kGitHubTimeout.inSeconds} 秒没有响应，检查网络后再试');
    } on Exception catch (e) {
      throw GitHubException('连不上 GitHub（${uri.host}）：${e.runtimeType}');
    }
  }

  Never _fail(http.Response r, String what) {
    String? detail;
    try {
      final json = jsonDecode(r.body);
      if (json is Map && json['message'] is String) detail = json['message'] as String;
    } on FormatException {
      // 忽略：不是 JSON
    }
    final reason = switch (r.statusCode) {
      401 => 'Token 无效或已过期',
      403 => 'Token 权限不够（需要仓库的 Actions 和 Contents 读写权限；改工作流文件还要 workflow 权限）',
      404 => '找不到：请检查仓库名、分支名、工作流文件名，以及 Token 能否访问这个仓库',
      409 => '仓库是空的或状态冲突（空仓库请先在 GitHub 上建一个初始提交）',
      422 => '参数不被接受',
      _ => 'GitHub 返回 ${r.statusCode}',
    };
    throw GitHubException('$what失败：$reason${detail != null ? '（$detail）' : ''}', statusCode: r.statusCode);
  }

  Map<String, dynamic> _json(http.Response r) => jsonDecode(r.body) as Map<String, dynamic>;

  /// 触发 workflow_dispatch。能直接拿到运行 ID 就返回，拿不到返回 null
  /// （老版本接口返回 204 无内容，此时用 [findLatestDispatchRun] 找）。
  Future<int?> dispatchWorkflow(String workflowFile, String ref, {Map<String, String> inputs = const {}}) async {
    final uri = _uri('/actions/workflows/${Uri.encodeComponent(workflowFile)}/dispatches');
    final base = {'ref': ref, if (inputs.isNotEmpty) 'inputs': inputs};
    var r = await _send('POST', uri, body: {...base, 'return_run_details': true});
    if (r.statusCode == 422 && r.body.contains('return_run_details')) {
      r = await _send('POST', uri, body: base); // 不认识这个字段的旧服务器
    }
    if (r.statusCode == 204) return null;
    if (r.statusCode == 200) {
      try {
        final id = _json(r)['workflow_run_id'];
        return id is int ? id : null;
      } on Object {
        return null;
      }
    }
    _fail(r, '触发工作流');
  }

  /// 找某个工作流最近一次手动触发的运行（[after] 之后创建的）。
  Future<WorkflowRun?> findLatestDispatchRun(String workflowFile, String ref, DateTime after) async {
    final r = await _send(
      'GET',
      _uri('/actions/workflows/${Uri.encodeComponent(workflowFile)}/runs', {
        'event': 'workflow_dispatch',
        'branch': ref,
        'per_page': '5',
      }),
    );
    if (r.statusCode != 200) _fail(r, '查询工作流运行');
    final runs = [
      for (final j in (_json(r)['workflow_runs'] as List? ?? const []))
        WorkflowRun.fromJson(j as Map<String, dynamic>),
    ];
    final threshold = after.subtract(const Duration(seconds: 30)); // 容忍手机和服务器的时间差
    for (final run in runs) {
      if (run.createdAt == null || run.createdAt!.isAfter(threshold)) return run;
    }
    return null;
  }

  Future<WorkflowRun> getRun(int runId) async {
    final r = await _send('GET', _uri('/actions/runs/$runId'));
    if (r.statusCode != 200) _fail(r, '查询运行状态');
    return WorkflowRun.fromJson(_json(r));
  }

  Future<List<RunArtifact>> listArtifacts(int runId) async {
    final r = await _send('GET', _uri('/actions/runs/$runId/artifacts', {'per_page': '100'}));
    if (r.statusCode != 200) _fail(r, '查询构建产物');
    return [
      for (final j in (_json(r)['artifacts'] as List? ?? const [])) RunArtifact.fromJson(j as Map<String, dynamic>),
    ];
  }

  /// 下载产物（zip）。接口返回 302，Location 是一分钟内有效的临时地址；
  /// 跟随跳转时不带 Authorization，避免把 Token 发给存储服务。
  Future<Uint8List> downloadArtifactZip(int artifactId) async {
    final request = http.Request('GET', _uri('/actions/artifacts/$artifactId/zip'))
      ..headers.addAll(_headers)
      ..followRedirects = false;
    final http.Response r;
    try {
      r = await http.Response.fromStream(await _http.send(request)).timeout(kGitHubTimeout);
    } on TimeoutException {
      throw GitHubException('GitHub ${kGitHubTimeout.inSeconds} 秒没有响应，检查网络后再试');
    } on Exception catch (e) {
      throw GitHubException('连不上 GitHub：${e.runtimeType}');
    }
    if (r.statusCode == 200) return r.bodyBytes;
    if (r.statusCode == 410) throw GitHubException('这个构建产物已过期，请重新打包', statusCode: 410);
    if (r.statusCode != 302 && r.statusCode != 301 && r.statusCode != 307) _fail(r, '下载构建产物');
    final location = r.headers['location'];
    if (location == null) throw GitHubException('下载构建产物失败：GitHub 没有返回下载地址');
    final http.Response file;
    try {
      file = await _http.get(Uri.parse(location)).timeout(kGitHubDownloadTimeout);
    } on TimeoutException {
      throw GitHubException('下载构建产物超时（${kGitHubDownloadTimeout.inMinutes} 分钟），检查网络后再试');
    } on Exception catch (e) {
      throw GitHubException('下载构建产物失败：${e.runtimeType}');
    }
    if (file.statusCode != 200) {
      throw GitHubException('下载构建产物失败：存储服务返回 ${file.statusCode}', statusCode: file.statusCode);
    }
    return file.bodyBytes;
  }

  /// 从产物 zip 里取出所有 .apk。
  static List<ExtractedFile> extractApks(Uint8List zipBytes) {
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(zipBytes);
    } on Object {
      throw GitHubException('构建产物不是合法的 zip 文件');
    }
    return [
      for (final f in archive.files)
        if (f.isFile && f.name.toLowerCase().endsWith('.apk'))
          ExtractedFile(f.name.split('/').last, Uint8List.fromList(f.content as List<int>)),
    ];
  }

  /// 把一批文件作为一次提交推到分支上（Git Data API：blob → tree → commit → 更新 ref）。
  /// 返回新提交的 SHA。只增改不删除：仓库里已有而本次没传的文件保持不动。
  Future<String> pushFiles({
    required String branch,
    required Map<String, List<int>> files,
    required String message,
    void Function(int done, int total)? onProgress,
  }) async {
    if (files.isEmpty) throw GitHubException('没有可推送的文件');
    final ref = await _send('GET', _uri('/git/ref/heads/${Uri.encodeComponent(branch)}'));
    if (ref.statusCode != 200) _fail(ref, '读取分支 $branch ');
    final parentSha = (_json(ref)['object'] as Map)['sha'] as String;

    final commit = await _send('GET', _uri('/git/commits/$parentSha'));
    if (commit.statusCode != 200) _fail(commit, '读取最新提交');
    final baseTree = (_json(commit)['tree'] as Map)['sha'] as String;

    final entries = <Map<String, dynamic>>[];
    var done = 0;
    for (final entry in files.entries) {
      final blob = await _send('POST', _uri('/git/blobs'), body: {
        'content': base64Encode(entry.value),
        'encoding': 'base64',
      });
      if (blob.statusCode != 201) _fail(blob, '上传 ${entry.key} ');
      entries.add({'path': entry.key, 'mode': '100644', 'type': 'blob', 'sha': _json(blob)['sha']});
      onProgress?.call(++done, files.length);
    }

    final tree = await _send('POST', _uri('/git/trees'), body: {'base_tree': baseTree, 'tree': entries});
    if (tree.statusCode != 201) _fail(tree, '创建文件树');

    final newCommit = await _send('POST', _uri('/git/commits'), body: {
      'message': message,
      'tree': _json(tree)['sha'],
      'parents': [parentSha],
    });
    if (newCommit.statusCode != 201) _fail(newCommit, '创建提交');
    final sha = _json(newCommit)['sha'] as String;

    final update = await _send('PATCH', _uri('/git/refs/heads/${Uri.encodeComponent(branch)}'), body: {'sha': sha});
    if (update.statusCode != 200) _fail(update, '更新分支 $branch ');
    return sha;
  }
}
