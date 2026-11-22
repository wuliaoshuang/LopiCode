import 'dart:convert';
import 'dart:io';

import 'package:lopicode/agent/command_runner.dart';
import 'package:lopicode/core/path_guard.dart';
import 'package:lopicode/core/project_store.dart';
import 'package:lopicode/core/templates.dart';
import 'package:lopicode/lowcode/export_html.dart';
import 'package:lopicode/lowcode/model.dart';

/// 需要用户点头的一次操作（显示成对话里的确认卡）。
class ApprovalRequest {
  ApprovalRequest({required this.tool, required this.title, required this.detail});
  final String tool;
  final String title;
  final String detail;
}

typedef ApprovalRequester = Future<bool> Function(ApprovalRequest request);

class ToolOutcome {
  ToolOutcome(this.text, {this.ok = true, this.denied = false, this.changedFiles = false});
  final String text;
  final bool ok;
  final bool denied;

  /// 是否改动了项目文件（界面据此刷新文件树和预览）。
  final bool changedFiles;
}

/// Agent 能用的全部工具。安全规则都写在这里的代码里，不靠提示词：
/// - 所有路径经 [PathGuard] 解析，越界直接报错，不碰磁盘；
/// - `run_command` 和 `delete_file` 必须过 [requestApproval]，除非该项目开了自动批准；
/// - 读写大小、命令输出、命令时长都有上限。
class AgentToolbox {
  AgentToolbox({
    required this.guard,
    required this.runner,
    required this.requestApproval,
    required this.autoApprove,
  });

  final PathGuard guard;
  final CommandRunner runner;
  final ApprovalRequester requestApproval;
  final bool Function() autoApprove;

  static const Set<String> approvalRequired = {'run_command', 'delete_file'};
  static const int maxReadChars = 60000;
  static const int maxWriteChars = 1000000;
  static const int maxOutputChars = 8000;
  static const Duration commandTimeout = Duration(seconds: 60);

  static Map<String, dynamic> _fn(String name, String description, Map<String, dynamic> props, [List<String> required = const []]) => {
    'type': 'function',
    'function': {
      'name': name,
      'description': description,
      'parameters': {'type': 'object', 'properties': props, 'required': required},
    },
  };

  /// 发给模型的工具定义（`tools` 参数）。
  static final List<Map<String, dynamic>> specs = [
    _fn('list_files', '列出项目里的文件和目录（相对路径，目录以 / 结尾）。', {
      'path': {'type': 'string', 'description': '要列出的子目录，省略表示项目根目录'},
    }),
    _fn('read_file', '读取项目里的一个文本文件。', {
      'path': {'type': 'string', 'description': '项目内的相对路径'},
    }, ['path']),
    _fn('write_file', '创建或整体覆盖项目里的一个文本文件，会自动创建上级目录。', {
      'path': {'type': 'string', 'description': '项目内的相对路径'},
      'content': {'type': 'string', 'description': '文件的完整内容'},
    }, ['path', 'content']),
    _fn('delete_file', '删除项目里的一个文件或目录。需要用户确认。', {
      'path': {'type': 'string', 'description': '项目内的相对路径'},
    }, ['path']),
    _fn('run_command', '在项目目录里用 shell 执行一条命令并返回输出。需要用户确认。', {
      'command': {'type': 'string', 'description': '要执行的命令'},
    }, ['command']),
    _fn('lowcode_get_page', '读取低代码页面（$kLowcodePageFile）的 JSON。', {}),
    _fn('lowcode_update_page', '用新的 JSON 整体替换低代码页面，并重新导出 index.html 和 style.css。', {
      'page': {'type': 'object', 'description': '完整的页面对象：{title, root}，root.type 必须是 page'},
    }, ['page']),
  ];

  Future<ToolOutcome> execute(String name, Map<String, dynamic> args) async {
    try {
      // 先把参数解析、路径校验做完，再去问用户；越界的请求连确认卡都不会出现。
      switch (name) {
        case 'list_files':
          final files = await listProjectFiles(guard, sub: _optString(args, 'path') ?? '');
          return ToolOutcome(files.isEmpty ? '（空目录）' : files.join('\n'));
        case 'read_file':
          return await _read(_string(args, 'path'));
        case 'write_file':
          return await _write(_string(args, 'path'), _string(args, 'content', allowEmpty: true));
        case 'delete_file':
          return await _delete(_string(args, 'path'));
        case 'run_command':
          return await _run(_string(args, 'command'));
        case 'lowcode_get_page':
          return await _read(kLowcodePageFile);
        case 'lowcode_update_page':
          return await _updatePage(args['page']);
        default:
          return ToolOutcome('错误：没有名为 $name 的工具', ok: false);
      }
    } on PathGuardException catch (e) {
      return ToolOutcome('错误：${e.message}', ok: false);
    } on _ArgError catch (e) {
      return ToolOutcome('错误：${e.message}', ok: false);
    } on FormatException catch (e) {
      return ToolOutcome('错误：${e.message}', ok: false);
    } on FileSystemException catch (e) {
      return ToolOutcome('错误：文件操作失败（${e.osError?.message ?? e.message}）', ok: false);
    }
  }

  Future<bool> _approved(ApprovalRequest request) async {
    assert(approvalRequired.contains(request.tool));
    if (autoApprove()) return true;
    return requestApproval(request);
  }

  Future<ToolOutcome> _read(String path) async {
    final file = File(guard.resolve(path));
    if (!await file.exists()) return ToolOutcome('错误：文件不存在：$path', ok: false);
    final bytes = await file.readAsBytes();
    if (bytes.take(8000).contains(0)) {
      return ToolOutcome('错误：$path 是二进制文件（${bytes.length} 字节），无法按文本读取', ok: false);
    }
    final text = utf8.decode(bytes, allowMalformed: true);
    if (text.length > maxReadChars) {
      return ToolOutcome('${text.substring(0, maxReadChars)}\n…（文件共 ${text.length} 字符，只显示前 $maxReadChars 字符）');
    }
    return ToolOutcome(text);
  }

  Future<ToolOutcome> _write(String path, String content) async {
    final full = guard.resolve(path);
    if (full == guard.root) throw _ArgError('path 不能是项目根目录');
    if (content.length > maxWriteChars) {
      throw _ArgError('内容太大（${content.length} 字符，上限 $maxWriteChars）');
    }
    if (await Directory(full).exists()) throw _ArgError('$path 是一个目录');
    final file = File(full);
    await file.parent.create(recursive: true);
    await file.writeAsString(content);
    return ToolOutcome('已写入 ${guard.relative(full)}（${content.length} 字符）', changedFiles: true);
  }

  Future<ToolOutcome> _delete(String path) async {
    final full = guard.resolve(path);
    if (full == guard.root) throw _ArgError('不能删除项目根目录');
    final type = await FileSystemEntity.type(full, followLinks: false);
    if (type == FileSystemEntityType.notFound) {
      return ToolOutcome('错误：文件不存在：$path', ok: false);
    }
    final rel = guard.relative(full);
    final isDir = type == FileSystemEntityType.directory;
    if (!await _approved(ApprovalRequest(tool: 'delete_file', title: isDir ? '删除目录' : '删除文件', detail: rel))) {
      return ToolOutcome('用户拒绝了这次删除，文件没有被改动。', ok: false, denied: true);
    }
    if (isDir) {
      await Directory(full).delete(recursive: true);
    } else {
      await File(full).delete();
    }
    return ToolOutcome('已删除 $rel', changedFiles: true);
  }

  Future<ToolOutcome> _run(String command) async {
    if (!await _approved(ApprovalRequest(tool: 'run_command', title: '执行命令', detail: command))) {
      return ToolOutcome('用户拒绝执行这条命令，命令没有运行。', ok: false, denied: true);
    }
    final result = await runner.run(command, workingDirectory: guard.root, timeout: commandTimeout);
    var output = result.output;
    if (output.length > maxOutputChars) {
      output = '…（前面省略 ${output.length - maxOutputChars} 字符）\n${output.substring(output.length - maxOutputChars)}';
    }
    final status = result.timedOut ? '超过 ${commandTimeout.inSeconds} 秒，已强制结束' : '退出码 ${result.exitCode}';
    return ToolOutcome(
      '$status\n${output.isEmpty ? '（没有输出）' : output}',
      ok: !result.timedOut && result.exitCode == 0,
      changedFiles: true,
    );
  }

  Future<ToolOutcome> _updatePage(Object? page) async {
    Object? value = page;
    if (value is String) {
      try {
        value = jsonDecode(value);
      } on FormatException {
        throw _ArgError('page 不是合法 JSON');
      }
    }
    if (value is! Map<String, dynamic>) throw _ArgError('缺少参数 page（应为对象）');
    final doc = LcDocument.fromJson(value); // 结构不合法会抛 FormatException，文件不会被改
    await saveLowcodePage(guard, doc);
    return ToolOutcome('页面已更新，并重新导出了 index.html 和 style.css。', changedFiles: true);
  }

  static String _string(Map<String, dynamic> args, String key, {bool allowEmpty = false}) {
    final v = args[key];
    if (v is! String || (!allowEmpty && v.trim().isEmpty)) throw _ArgError('缺少参数 $key（应为字符串）');
    return v;
  }

  static String? _optString(Map<String, dynamic> args, String key) {
    final v = args[key];
    if (v == null) return null;
    if (v is! String) throw _ArgError('参数 $key 应为字符串');
    return v;
  }
}

class _ArgError implements Exception {
  _ArgError(this.message);
  final String message;
}

/// 保存低代码页面并同步导出网页文件（搭建器和 Agent 共用）。
Future<void> saveLowcodePage(PathGuard guard, LcDocument doc) async {
  final export = exportHtml(doc);
  await File(guard.resolve(kLowcodePageFile)).writeAsString(doc.encode());
  await File(guard.resolve('index.html')).writeAsString(export.html);
  await File(guard.resolve('style.css')).writeAsString(export.css);
}
