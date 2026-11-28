import 'dart:convert';
import 'dart:io';

import 'package:lopicode/agent/command_output_store.dart';
import 'package:lopicode/agent/command_runner.dart';
import 'package:lopicode/agent/edit_file_tool.dart';
import 'package:lopicode/agent/line_diff.dart';
import 'package:lopicode/core/path_guard.dart';
import 'package:lopicode/core/project_store.dart';
import 'package:lopicode/core/safe_file.dart';
import 'package:lopicode/core/templates.dart';
import 'package:lopicode/lowcode/export_html.dart';
import 'package:lopicode/lowcode/export_pages.dart';
import 'package:lopicode/lowcode/export_tidy.dart';
import 'package:lopicode/lowcode/front_store.dart';
import 'package:lopicode/lowcode/logic_gate.dart';
import 'package:lopicode/lowcode/model.dart';
import 'package:lopicode/lowcode/newer_notice.dart';

/// 需要用户点头的一次操作（显示成对话里的确认卡）。
class ApprovalRequest {
  ApprovalRequest({required this.tool, required this.title, required this.detail, this.allowAlways = true, this.preview, this.alwaysKey, this.alwaysNote});

  /// 这次操作会把文件改成什么样（确认卡上可以先看对比）；没有就是 null。
  final FileChange? preview;

  /// 不为空时，“本对话都允许”只记这一个键（比如某个 MCP 服务器的某个工具），不会把命令、删除也一起放开。
  final String? alwaysKey;

  /// 点“本对话都允许”后、二次确认前显示的说明；为空用默认那句。
  final String? alwaysNote;

  /// 这类确认能不能用“本对话都允许”带过。自动化任务的确认卡不能。
  final bool allowAlways;
  final String tool;
  final String title;
  final String detail;

  /// 用户点“拒绝”时顺手写的一句原因（没写是 null）。只在拒绝时有意义：不影响“执行还是不执行”。
  String? denyReason;

  /// 拼在“用户拒绝……”后面告诉模型的那一句；没写原因是空串（和以前一样）。
  String get denyNote {
    final reason = (denyReason ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
    if (reason.isEmpty) return '';
    return '用户写的原因：${reason.length > kDenyReasonMaxChars ? '${reason.substring(0, kDenyReasonMaxChars)}…' : reason}';
  }
}

/// 拒绝原因最多带给模型多少个字。
const int kDenyReasonMaxChars = 200;

typedef ApprovalRequester = Future<bool> Function(ApprovalRequest request);

class ToolOutcome {
  ToolOutcome(this.text, {this.ok = true, this.denied = false, this.changedFiles = false, this.change, this.images = const []});

  /// 这一步把哪个文件改成了什么样（给界面画对比、记“这次改过的文件”；不发给模型）。
  final FileChange? change;
  final String text;
  final bool ok;
  final bool denied;

  /// 是否改动了项目文件（界面据此刷新文件树和预览）。
  final bool changedFiles;

  /// 要交给模型看的图片（view_image）：每项 `{path, mime, bytes}`，只有路径和大小，不带图片内容。
  final List<Map<String, dynamic>> images;

  /// 换一段文字，别的不变。
  ToolOutcome withText(String text) => ToolOutcome(text, ok: ok, denied: denied, changedFiles: changedFiles, change: change, images: images);
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

  /// 这一轮被用户叫停时完成的信号（执行器接上来的）：正在跑的命令据此中途结束。
  Future<void> Function()? stopSignal;

  /// 和 run_command 同一套确认规矩（完全权限 / “本对话都允许”不问，其余出确认卡）。给“后台执行命令”用。
  Future<bool> approveCommand(ApprovalRequest request) => _approved(request);

  static const Set<String> approvalRequired = {'run_command', 'delete_file'};
  static const int maxReadChars = 60000;
  static const int maxWriteChars = 1000000;
  static const int maxOutputChars = 8000;
  static const Duration commandTimeout = Duration(seconds: 60);

  static const Map<String, ToolKind> coreKinds = {
    'list_files': ToolKind.read,
    'read_file': ToolKind.read,
    'write_file': ToolKind.write,
    kEditFileTool: ToolKind.write,
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
    if (kind == null) return '没有名为 $name 的工具。现在能用的工具：${[...coreKinds.keys, ...extras.map((e) => e.name)].where((n) => blockReason(n) == null).join('、')}';
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
      '读取项目里的一个文本文件。文件很长时用 start_line / end_line 只读其中一段（行号从 1 开始）。',
      {
        'path': {'type': 'string', 'description': '项目内的相对路径'},
        'start_line': {'type': 'integer', 'description': '从第几行开始读（含），省略表示从头'},
        'end_line': {'type': 'integer', 'description': '读到第几行（含），省略表示到结尾'},
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
    editFileSpec,
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
      '在项目目录里用 shell 执行一条命令并返回输出。需要用户确认。输出太长时只返回开头和结尾，完整输出会存成文件并告诉你路径，用 read_file 分段读。',
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
        'page': {
          'type': 'object',
          'description': '完整的页面对象：{title, root, logic?, components?}，root.type 必须是 page；节点可带 style（CSS 声明表）、name（名字）；读到的不认识的字段原样带回、不要删。除原有的节点类型外还有 11 种：icon{icon,size,color}、textarea{placeholder,rows,value}、switch{checked}、checkbox{text,checked}、radio{options:[{value,label}],value}、select{options:[{value,label}],value,placeholder}、listItem{title,subtitle,chevron}（插槽 left / right）、appBar{title}（插槽 left / right）、bottomNav{items:[{icon,label}],current}、tabs{tabs:[{id,label}],current}（每个页签的 id 就是一个插槽）、dialog{title,text,okText,cancelText,variant,open,dismissible}（插槽 content / footer）；另有滑块 slider{value,min,max,step,disabled}（前四个是数）。放进带插槽组件里的子节点用节点上的 slot 字段指明放哪个插槽；自定义组件（components 里的定义）也能带插槽：定义的树里放 {type:"slot", name:"给人看的名字", props:{name:"插槽名"}（不写＝默认插槽）, children:[没填时显示的默认内容]}，slot 节点只能放在组件定义里、不能当定义的最外层；页面上的实例 {type:"component", props:{ref}} 可以带 children，每个子节点用 slot 字段指明进哪个插槽（不写＝默认插槽）；拿不准某个属性时先用 lowcode_get_page 看现有页面的写法。logic（积木逻辑）/ components（自定义组件）不传就沿用现有的，要清空请传 {} / []。多页面：最外层的 title / root / logic 是首页，别的页放在 pages:[{id,title,root,logic?}]（id 形如 p2，不传 pages 就沿用现有的，要删光别的页请传 []；自定义组件所有页面共用）；去另一页用积木 {op:"goPage",args:{page:"页面 id"}}，底部导航项可以带 page（页面 id）；各页共用的底部导航：内容只写一份在最外层 shared:{bottomNav:{props:{items,…},style?}}，要显示它的页放 {id,type:"bottomNav",shared:true}（不用写 props，哪一项亮着自动算）；别的页导出成 page-<页面 id>.html',
        },
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
          return await _read(argString(args, 'path'), start: _argLine(args, 'start_line'), end: _argLine(args, 'end_line'));
        case 'write_file':
          return await _write(argString(args, 'path'), argString(args, 'content', allowEmpty: true));
        case kEditFileTool:
          return await runEditFile(guard, args, checkScope: _checkScope);
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

  /// 行号参数：模型有时给成字符串或小数，能认就认；不是正整数就报错让它改。
  static int? _argLine(Map<String, dynamic> args, String key) {
    final v = args[key];
    if (v == null) return null;
    final n = v is int ? v : (v is double && v == v.roundToDouble() ? v.toInt() : (v is String ? int.tryParse(v.trim()) : null));
    if (n == null || n < 1) throw ToolArgError('$key 必须是从 1 开始的行号（整数）');
    return n;
  }

  /// 读文件用的路径解析：应用内部目录里只放行“转存的命令输出”（只读；写和删仍然一律拒绝）。
  String _resolveForRead(String path) {
    final full = guard.resolve(path, allowReserved: true);
    final rel = guard.relative(full);
    if (full == guard.root || isCommandOutputPath(rel)) return full;
    return guard.resolve(path); // 其余照旧：碰到内部目录在这里报错
  }

  Future<ToolOutcome> _read(String path, {int? start, int? end}) async {
    final file = File(_resolveForRead(path));
    if (!await file.exists()) return ToolOutcome('错误：文件不存在：$path', ok: false);
    final bytes = await file.readAsBytes();
    if (bytes.take(8000).contains(0)) {
      return ToolOutcome('错误：$path 是二进制文件（${bytes.length} 字节），无法按文本读取', ok: false);
    }
    var text = utf8.decode(bytes, allowMalformed: true);
    var range = '';
    if (start != null || end != null) {
      final lines = const LineSplitter().convert(text);
      final from = start ?? 1;
      final to = end == null || end > lines.length ? lines.length : end;
      if (from > lines.length) return ToolOutcome('错误：$path 一共只有 ${lines.length} 行，start_line=$from 超出了范围', ok: false);
      if (to < from) throw ToolArgError('end_line 不能小于 start_line');
      text = lines.sublist(from - 1, to).join('\n');
      range = '（$path 第 $from–$to 行，全文共 ${lines.length} 行）\n';
    }
    if (text.length > maxReadChars) {
      final shownLines = '\n'.allMatches(text.substring(0, maxReadChars)).length;
      return ToolOutcome(
        '$range${text.substring(0, maxReadChars)}\n…（${range.isEmpty ? '文件' : '这一段'}共 ${text.length} 字符，只显示前 $maxReadChars 字符，约到第 ${(start ?? 1) + shownLines} 行。要看后面的内容，用 start_line / end_line 分段读）',
      );
    }
    return ToolOutcome('$range$text');
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
    final before = await FileSnapshot.of(file);
    await file.parent.create(recursive: true);
    await file.writeAsString(content);
    return ToolOutcome('已写入 ${guard.relative(full)}（${content.length} 字符）', changedFiles: true, change: before.changeTo(guard.relative(full), content));
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
    final gone = isDir ? dirDeleted(rel) : (await FileSnapshot.of(File(full))).changeTo(rel, null);
    final request = ApprovalRequest(tool: 'delete_file', title: isDir ? '删除目录' : '删除文件', detail: rel, preview: gone.slim);
    if (!await _approved(request)) {
      return ToolOutcome('用户拒绝了这次删除，文件没有被改动。${request.denyNote}', ok: false, denied: true);
    }
    if (isDir) {
      await Directory(full).delete(recursive: true);
    } else {
      await File(full).delete();
    }
    return ToolOutcome('已删除 $rel', changedFiles: true, change: gone);
  }

  Future<ToolOutcome> _run(String command) async {
    // 执行环境还不能用（安卓上没装运行环境）：不出确认卡、不执行，直接把原因回给模型。只会少执行，不会多执行。
    final Object env = runner;
    final unavailable = env is HasCommandAvailability ? env.unavailableReason : null;
    if (unavailable != null) return ToolOutcome('命令没有执行：$unavailable', ok: false);
    final request = ApprovalRequest(tool: 'run_command', title: '执行命令', detail: command);
    if (!await _approved(request)) {
      return ToolOutcome('用户拒绝执行这条命令，命令没有运行。${request.denyNote}', ok: false, denied: true);
    }
    final Object r = runner;
    final timeout = r is HasCommandTimeout ? r.commandTimeout : commandTimeout;
    final stop = stopSignal?.call();
    final result = r is HasCommandStop && stop != null
        ? await r.runStoppable(command, workingDirectory: guard.root, timeout: timeout, stop: stop)
        : await runner.run(command, workingDirectory: guard.root, timeout: timeout);
    var output = result.output;
    if (output.length > maxOutputChars) {
      // 太长：完整的转存成文件，回给模型开头 + 结尾 + 文件路径（它可以用 read_file 按行分段读）。
      output = spilledOutputText(output, await CommandOutputStore(guard).save(command, output));
    }
    final status = result.stopped
        ? '用户点了停止，命令已中途结束（它起的进程也一起结束了）'
        : result.timedOut
        ? '超过 ${timeout.inSeconds} 秒，已强制结束'
        : '退出码 ${result.exitCode}';
    return ToolOutcome('$status\n${output.isEmpty ? '（没有输出）' : output}', ok: !result.stopped && !result.timedOut && result.exitCode == 0, changedFiles: true);
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
    int? oldVersion;
    {
      final current = File(guard.resolve(kLowcodePageFile));
      if (await current.exists()) {
        try {
          final old = jsonDecode(await current.readAsString());
          if (old is Map<String, dynamic>) {
            final v = old['version'];
            if (v is int) oldVersion = v;
            merged = {
              ...merged,
              // 逻辑、组件，还有这一版不认识的最外层字段（新版应用写的）：没带就沿用。
              for (final k in old.keys)
                if (k != 'version' && k != 'title' && k != 'root' && !merged.containsKey(k) && old[k] != null) k: old[k],
            };
          }
        } on FormatException {
          // 现有文件本来就坏了：没有可沿用的，照新的写。
        }
      }
    }
    // Agent 写的是新内容：没写版本号就按当前版读（老文件没写版本号才当第 1 版）。
    if (merged['version'] is! int) merged = {...merged, 'version': LcDocument.currentVersion};
    // 原来的文件是更新的版本做的：版本号不往回写（不然里面看不懂的东西就对不上号了）。
    final given = merged['version'];
    if (oldVersion != null && given is int && oldVersion > given) merged = {...merged, 'version': oldVersion};
    final doc = LcDocument.fromJson(merged); // 结构不合法会抛 FormatException，文件不会被改
    for (final f in [
      kLowcodePageFile,
      'index.html',
      'style.css',
      kLowcodeLogicFile,
      for (final p in doc.pages.skip(1)) ...['page-${p.id}.html', 'page-${p.id}.css', 'page-${p.id}.js'],
    ]) {
      _checkScope(guard.resolve(f));
    }
    await saveLowcodePage(guard, doc);
    final more = doc.isMultiPage ? '（共 ${doc.pages.length} 页，别的页是 page-<页面 id>.html）' : '';
    return ToolOutcome('页面已更新，并重新导出了 index.html 和 style.css$more。${lcLogicToolReport(doc)}${doc.isFromNewer ? '\n注意：${lcNewerNoticeText(doc)}' : ''}', changedFiles: true);
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
///
/// 每个文件都是“先写同目录的临时文件、写完再改名”（lib/core/safe_file.dart）：写到一半被杀 / 写不进去时，
/// 原来的页面文件和网页还是完整的旧内容，不会剩半截——页面文件坏了整个页面就打不开了。
Future<void> saveLowcodePage(PathGuard guard, LcDocument doc) async {
  // 页面逻辑用了积木库、手上却还没拿到项目里的库（Agent 改的、刚读出来的）：先读来，不然导出时会说“库没了”。
  if (doc.pages.any((p) => p.logic.uses.isNotEmpty && p.logic.loaded.isEmpty)) await lcAttachLibs(guard, doc);
  final pages = exportHtmlPages(doc, tidy: tidyHtmlExport);
  await writeStringAtomic(File(guard.resolve(kLowcodePageFile)), doc.encode());
  // 只删我们自己生成的（看开头那行标记），用户自己写的同名文件不碰。
  Future<void> dropIfOurs(File f, bool Function(String head) ours) async {
    if (!await f.exists()) return;
    final head = await f.openRead(0, 600).transform(const Utf8Decoder(allowMalformed: true)).join();
    if (ours(head)) await f.delete();
  }

  final written = <String>{};
  for (final page in pages) {
    written.addAll([page.htmlName, page.cssName, page.jsName]);
    await writeStringAtomic(File(guard.resolve(page.htmlName)), page.files.html);
    await writeStringAtomic(File(guard.resolve(page.cssName)), page.files.css);
    final logic = File(guard.resolve(page.jsName));
    if (page.logicErrors > 0) {
      // 这一页的积木逻辑有“错误”：不导出新的脚本，上一次导出的原样留着（见 lib/lowcode/logic_gate.dart）。
      // 例外：换过首页以后，logic.js 可能是上一个首页的——那就不是“这一页上一次的”，删掉。
      if (page.base == 'index') await dropIfOurs(logic, (head) => head.startsWith(kLowcodeLogicMarker) && lcStaleHomeScript(head, page.pageId));
    } else if (page.files.js.isNotEmpty) {
      await writeStringAtomic(logic, page.files.js);
    } else {
      // 逻辑删光了：把上次导出的脚本也删掉。
      await dropIfOurs(logic, (head) => head.startsWith(kLowcodeLogicMarker));
    }
  }
  // 页面删掉 / 换了首页以后，上一次导出留下的 page-<id>.* 没人要了：清掉（同样只清我们自己生成的）。
  final root = Directory(guard.root);
  if (!await root.exists()) return;
  await for (final e in root.list(followLinks: false)) {
    final name = e.uri.pathSegments.lastWhere((s) => s.isNotEmpty, orElse: () => '');
    if (e is! File || !lcLooksLikePageFile(name) || written.contains(name)) continue;
    final base = name.substring(0, name.lastIndexOf('.'));
    await dropIfOurs(e, (head) {
      if (name.endsWith('.js')) return head.startsWith(kLowcodeLogicMarker);
      if (name.endsWith('.css')) return head.startsWith(kLowcodeCssMarker);
      return head.contains('href="$base.css"');
    });
  }
}
