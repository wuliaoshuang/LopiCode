import 'dart:convert';
import 'dart:io';

import 'package:lopicode/agent/command_runner.dart';
import 'package:lopicode/core/path_guard.dart';
import 'package:lopicode/core/project_store.dart';
import 'package:lopicode/core/templates.dart';
import 'package:lopicode/lowcode/export_html.dart';
import 'package:lopicode/lowcode/export_tidy.dart';
import 'package:lopicode/lowcode/model.dart';

/// 需要用户点头的一次操作（显示成对话里的确认卡）。
class ApprovalRequest {
  ApprovalRequest({required this.tool, required this.title, required this.detail, this.allowAlways = true});

  /// 这类确认能不能用“本对话都允许”带过。自动化任务的确认卡不能。
  final bool allowAlways;
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

/// 权限三档。
enum PermissionLevel {
  view('view', '仅可查看', '只能看文件，不能写、不能删、不能执行命令'),
  workspace('workspace', '工作区内修改', '可以改工作区里的文件；删除文件、执行命令每次先问你'),
  full('full', '完全权限', '删除文件、执行命令都不再问你');

  const PermissionLevel(this.id, this.label, this.hint);
  final String id;
  final String label;
  final String hint;

  static PermissionLevel byId(Object? id) => values.firstWhere((p) => p.id == id, orElse: () => workspace);
}

/// 工具的性质：权限和计划模式按它来拦。
enum ToolKind {
  /// 只读：任何权限、计划模式下都能用。
  read,

  /// 改动工作区文件。
  write,

  /// 执行命令。
  exec,

  /// 别的（提问、派子代理、任务板……），自己另有规则。
  other,
}

/// 核心工具之外的工具（提问、联网搜索、技能、子代理、任务板、自动化）。
class ExtraTool {
  ExtraTool({required this.spec, required this.kind, required this.run});

  /// OpenAI 格式的工具定义。
  final Map<String, dynamic> spec;
  final ToolKind kind;
  final Future<ToolOutcome> Function(Map<String, dynamic> args) run;

  String get name => '${(spec['function'] as Map)['name']}';
}

/// 造一个 OpenAI 格式的工具定义。
Map<String, dynamic> toolSpec(String name, String description, Map<String, dynamic> props, [List<String> required = const []]) => {
  'type': 'function',
  'function': {
    'name': name,
    'description': description,
    'parameters': {'type': 'object', 'properties': props, 'required': required},
  },
};

/// Agent 能用的全部工具。安全规则都写在这里的代码里，不靠提示词：
/// - 所有路径经 [PathGuard] 解析，越界直接报错，不碰磁盘；
/// - 权限三档、计划模式、Agent 预设里的工具开关都在 [blockReason] 一处判断：
///   被挡住的工具既不会出现在发给模型的工具列表里（[specs]），
///   模型硬要调用时 [execute] 也会直接拒绝，不碰磁盘、不弹确认卡；
/// - `run_command` 和 `delete_file` 必须过 [requestApproval]，除非是“完全权限”或这段对话点过“本对话都允许”；
/// - 读写大小、命令输出、命令时长都有上限。
class AgentToolbox {
  AgentToolbox({
    required this.guard,
    required this.runner,
    required this.requestApproval,
    required this.autoApprove,
    PermissionLevel Function()? permission,
    bool Function()? planMode,
    this.allowedTools,
    this.writeScope,
    this.extras = const [],
  }) : permission = permission ?? (() => PermissionLevel.workspace),
       planMode = planMode ?? (() => false);

  final PathGuard guard;
  final CommandRunner runner;
  final ApprovalRequester requestApproval;

  /// 这段对话是不是点过“本对话都允许”（只在内存里，重启后恢复逐次询问）。
  final bool Function() autoApprove;

  /// 当前对话的权限档位。
  final PermissionLevel Function() permission;

  /// 是不是计划模式（只出计划，不改动）。
  final bool Function() planMode;

  /// Agent 预设勾选的工具；null 表示全部可用。
  final Set<String>? allowedTools;

  /// 团队任务给的写入范围（工作区内的相对路径前缀）；null 表示不限。
  /// 只管文件类工具，管不住 run_command 里的命令。
  final List<String>? writeScope;

  final List<ExtraTool> extras;

  static const Set<String> approvalRequired = {'run_command', 'delete_file'};
  static const int maxReadChars = 60000;
  static const int maxWriteChars = 1000000;
  static const int maxOutputChars = 8000;
  static const Duration commandTimeout = Duration(seconds: 60);

  static const Map<String, ToolKind> coreKinds = {
    'list_files': ToolKind.read,
    'read_file': ToolKind.read,
    'write_file': ToolKind.write,
    'delete_file': ToolKind.write,
    'run_command': ToolKind.exec,
    'lowcode_get_page': ToolKind.read,
    'lowcode_update_page': ToolKind.write,
  };

  static Map<String, dynamic> _fn(String name, String description, Map<String, dynamic> props, [List<String> required = const []]) => toolSpec(name, description, props, required);

  ExtraTool? _extra(String name) => extras.where((e) => e.name == name).firstOrNull;

  ToolKind? kindOf(String name) => coreKinds[name] ?? _extra(name)?.kind;

  /// 这个工具现在为什么不能用；能用返回 null。发工具列表和真正执行都走这里。
  String? blockReason(String name) {
    final kind = kindOf(name);
    if (kind == null) return '没有名为 $name 的工具';
    final allowed = allowedTools;
    if (allowed != null && !allowed.contains(name)) return '当前的 Agent 预设没有开启 $name 这个工具';
    if (kind == ToolKind.write || kind == ToolKind.exec) {
      if (planMode()) return '现在是计划模式：只能查看和出计划，不能改文件、不能执行命令。请把要做的事写进计划，等用户退出计划模式';
      if (permission() == PermissionLevel.view) return '当前权限是“仅可查看”：不能改文件、不能删除、不能执行命令。需要改动请让用户调高权限';
    }
    return null;
  }

  /// 这一轮发给模型的工具定义：被挡住的不出现。
  List<Map<String, dynamic>> get specs => [
    for (final s in coreSpecs)
      if (blockReason('${(s['function'] as Map)['name']}') == null) s,
    for (final e in extras)
      if (blockReason(e.name) == null) e.spec,
  ];

  /// 发给模型的工具定义（`tools` 参数）。
  static final List<Map<String, dynamic>> coreSpecs = [
    _fn('list_files', '列出项目里的文件和目录（相对路径，目录以 / 结尾）。', {
      'path': {'type': 'string', 'description': '要列出的子目录，省略表示项目根目录'},
    }),
    _fn(
      'read_file',
      '读取项目里的一个文本文件。',
      {
        'path': {'type': 'string', 'description': '项目内的相对路径'},
      },
      ['path'],
    ),
    _fn(
      'write_file',
      '创建或整体覆盖项目里的一个文本文件，会自动创建上级目录。',
      {
        'path': {'type': 'string', 'description': '项目内的相对路径'},
        'content': {'type': 'string', 'description': '文件的完整内容'},
      },
      ['path', 'content'],
    ),
    _fn(
      'delete_file',
      '删除项目里的一个文件或目录。需要用户确认。',
      {
        'path': {'type': 'string', 'description': '项目内的相对路径'},
      },
      ['path'],
    ),
    _fn(
      'run_command',
      '在项目目录里用 shell 执行一条命令并返回输出。需要用户确认。',
      {
        'command': {'type': 'string', 'description': '要执行的命令'},
      },
      ['command'],
    ),
    _fn('lowcode_get_page', '读取低代码页面（$kLowcodePageFile）的 JSON。', {}),
    _fn(
      'lowcode_update_page',
      '用新的 JSON 整体替换低代码页面，并重新导出 index.html 和 style.css。',
      {
        'page': {'type': 'object', 'description': '完整的页面对象：{title, root, logic?, components?}，root.type 必须是 page；节点可带 style（CSS 声明表）。logic（积木逻辑）/ components（自定义组件）不传就沿用现有的，要清空请传 {} / []'},
      },
      ['page'],
    ),
  ];

  Future<ToolOutcome> execute(String name, Map<String, dynamic> args) async {
    final blocked = blockReason(name);
    if (blocked != null) return ToolOutcome('错误：$blocked', ok: false, denied: kindOf(name) != null);
    try {
      final extra = _extra(name);
      if (extra != null) return await extra.run(args);
      // 先把参数解析、路径校验做完，再去问用户；越界的请求连确认卡都不会出现。
      switch (name) {
        case 'list_files':
          final files = await listProjectFiles(guard, sub: argOptString(args, 'path') ?? '');
          return ToolOutcome(files.isEmpty ? '（空目录）' : files.join('\n'));
        case 'read_file':
          return await _read(argString(args, 'path'));
        case 'write_file':
          return await _write(argString(args, 'path'), argString(args, 'content', allowEmpty: true));
        case 'delete_file':
          return await _delete(argString(args, 'path'));
        case 'run_command':
          return await _run(argString(args, 'command'));
        case 'lowcode_get_page':
          return await _read(kLowcodePageFile);
        case 'lowcode_update_page':
          return await _updatePage(args['page']);
        default:
          return ToolOutcome('错误：没有名为 $name 的工具', ok: false);
      }
    } on PathGuardException catch (e) {
      return ToolOutcome('错误：${e.message}', ok: false);
    } on ToolArgError catch (e) {
      return ToolOutcome('错误：${e.message}', ok: false);
    } on FormatException catch (e) {
      return ToolOutcome('错误：${e.message}', ok: false);
    } on FileSystemException catch (e) {
      return ToolOutcome('错误：文件操作失败（${e.osError?.message ?? e.message}）', ok: false);
    } on Exception catch (e) {
      final text = '$e';
      return ToolOutcome('错误：${text.length > 300 ? '${text.substring(0, 300)}…' : text}', ok: false);
    }
  }

  Future<bool> _approved(ApprovalRequest request) async {
    assert(approvalRequired.contains(request.tool));
    if (permission() == PermissionLevel.full || autoApprove()) return true;
    return requestApproval(request);
  }

  /// 团队任务限定了写入范围时，范围外的写和删直接拒绝。
  void _checkScope(String full) {
    final scope = writeScope;
    if (scope == null) return;
    final rel = guard.relative(full);
    for (final raw in scope) {
      var prefix = raw.trim();
      while (prefix.endsWith('/')) {
        prefix = prefix.substring(0, prefix.length - 1);
      }
      if (prefix.isEmpty || prefix == '.' || rel == prefix || rel.startsWith('$prefix/')) return;
    }
    throw ToolArgError('这个任务的写入范围是 ${scope.join('、')}，$rel 不在范围内，没有改动');
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
    if (full == guard.root) throw ToolArgError('path 不能是项目根目录');
    _checkScope(full);
    if (content.length > maxWriteChars) {
      throw ToolArgError('内容太大（${content.length} 字符，上限 $maxWriteChars）');
    }
    if (await Directory(full).exists()) throw ToolArgError('$path 是一个目录');
    final file = File(full);
    await file.parent.create(recursive: true);
    await file.writeAsString(content);
    return ToolOutcome('已写入 ${guard.relative(full)}（${content.length} 字符）', changedFiles: true);
  }

  Future<ToolOutcome> _delete(String path) async {
    final full = guard.resolve(path);
    if (full == guard.root) throw ToolArgError('不能删除项目根目录');
    _checkScope(full);
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
    final Object r = runner;
    final timeout = r is HasCommandTimeout ? r.commandTimeout : commandTimeout;
    final result = await runner.run(command, workingDirectory: guard.root, timeout: timeout);
    var output = result.output;
    if (output.length > maxOutputChars) {
      output = '…（前面省略 ${output.length - maxOutputChars} 字符）\n${output.substring(output.length - maxOutputChars)}';
    }
    final status = result.timedOut ? '超过 ${timeout.inSeconds} 秒，已强制结束' : '退出码 ${result.exitCode}';
    return ToolOutcome('$status\n${output.isEmpty ? '（没有输出）' : output}', ok: !result.timedOut && result.exitCode == 0, changedFiles: true);
  }

  Future<ToolOutcome> _updatePage(Object? page) async {
    Object? value = page;
    if (value is String) {
      try {
        value = jsonDecode(value);
      } on FormatException {
        throw ToolArgError('page 不是合法 JSON');
      }
    }
    if (value is! Map<String, dynamic>) throw ToolArgError('缺少参数 page（应为对象）');
    // Agent 只想改版面时常常不带 logic / components：没带就沿用文件里现有的，免得把用户搭好的积木和组件冲掉。
    // 想清空要明确传空的（logic: {}，components: []）。
    var merged = value;
    if (!merged.containsKey('logic') || !merged.containsKey('components')) {
      final current = File(guard.resolve(kLowcodePageFile));
      if (await current.exists()) {
        try {
          final old = jsonDecode(await current.readAsString());
          if (old is Map<String, dynamic>) {
            merged = {
              ...merged,
              for (final k in const ['logic', 'components'])
                if (!merged.containsKey(k) && old[k] != null) k: old[k],
            };
          }
        } on FormatException {
          // 现有文件本来就坏了：没有可沿用的，照新的写。
        }
      }
    }
    final doc = LcDocument.fromJson(merged); // 结构不合法会抛 FormatException，文件不会被改
    for (final f in [kLowcodePageFile, 'index.html', 'style.css', kLowcodeLogicFile]) {
      _checkScope(guard.resolve(f));
    }
    await saveLowcodePage(guard, doc);
    return ToolOutcome('页面已更新，并重新导出了 index.html 和 style.css。', changedFiles: true);
  }

  static String argString(Map<String, dynamic> args, String key, {bool allowEmpty = false}) {
    final v = args[key];
    if (v is! String || (!allowEmpty && v.trim().isEmpty)) throw ToolArgError('缺少参数 $key（应为字符串）');
    return v;
  }

  static String? argOptString(Map<String, dynamic> args, String key) {
    final v = args[key];
    if (v == null) return null;
    if (v is! String) throw ToolArgError('参数 $key 应为字符串');
    return v;
  }
}

class ToolArgError implements Exception {
  ToolArgError(this.message);
  final String message;
}

/// 保存低代码页面并同步导出网页文件（搭建器和 Agent 共用）。
Future<void> saveLowcodePage(PathGuard guard, LcDocument doc) async {
  final export = tidyHtmlExport(exportHtml(doc));
  await File(guard.resolve(kLowcodePageFile)).writeAsString(doc.encode());
  await File(guard.resolve('index.html')).writeAsString(export.html);
  await File(guard.resolve('style.css')).writeAsString(export.css);
  final logic = File(guard.resolve(kLowcodeLogicFile));
  if (export.js.isNotEmpty) {
    await logic.writeAsString(export.js);
  } else if (await logic.exists()) {
    // 逻辑删光了：把上次导出的 logic.js 也删掉。只删我们自己生成的（看开头那行标记），用户自己写的同名文件不碰。
    final head = await logic.openRead(0, 200).transform(const Utf8Decoder(allowMalformed: true)).join();
    if (head.startsWith(kLowcodeLogicMarker)) await logic.delete();
  }
}
