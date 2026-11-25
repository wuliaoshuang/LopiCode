// 设计约束（后端积木页 · 390×844，浅色 + 深色）— 2026-11-24
// - 这一页是薄壳：主体是通用的积木编辑器 BlockEditorView（画布 + 底部积木盒），这里只负责读写 backend.lc.json、
//   重新生成代码、把“语言 / 变量与集合 / 设置 / 运行”几个入口接上去。主操作＝在画布上搭积木。
// - 顶栏是沉浸式的（悬浮在画布上面、没有底色，见 lib/ui/top_bar.dart；空状态时也是同一个顶栏）：标题“后端积木”，副标题一行说现在的状态（语言 · 几个接口 / “N 个错误，没更新” / “N 个文件没覆盖”）。
//   右边胶囊里从左到右：运行（▶）、更多（⋯）、问题、看代码。语言、变量与集合、服务设置、生成情况都收在“更多”里——一行放不下四个以上的图标。
// - 每次改动后约半秒自动保存并重新生成代码；不弹“保存成功”。出了状况才说话：
//   有文件没覆盖 → 底部一条提示带“查看”，点开列出文件、可以选“用生成的覆盖”；
//   积木有错误 → 不生成新代码（上一次生成的原样留着）：副标题变成“N 个错误，没更新”（顶栏窄，只放得下短说法），刚出错时底部完整提示一次“有 N 个错误，代码没有更新”并带“查看问题”；
//   这时点“运行”或“代码生成情况”不往下走，先弹一张说明，主按钮“查看问题”打开问题列表。只有警告时一切照常。
// - 文件打不开 / 没有：整页一个空状态，说清原因，给两条出路（重置为样本、去文件页修）。
// - 这一页会留在后台：backend.lc.json 在别处被改了（Agent、文件编辑器），没有未保存改动就重新读；有就以这里为准并说一声。
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lopicode/backend/backend_block_host.dart';
import 'package:lopicode/backend/backend_launch.dart';
import 'package:lopicode/backend/backend_model.dart';
import 'package:lopicode/backend/backend_project.dart';
import 'package:lopicode/backend/backend_targets.dart';
import 'package:lopicode/backend/backend_templates.dart';
import 'package:lopicode/blocks/block_editor_view.dart';
import 'package:lopicode/blocks/block_palette_model.dart';
import 'package:lopicode/blocks/block_panels_sheet.dart';
import 'package:lopicode/core/path_guard.dart';
import 'package:lopicode/lowcode/logic_blocks.dart';
import 'package:lopicode/lowcode/logic_vars_sheet.dart';
import 'package:lopicode/project_session.dart';
import 'package:lopicode/state/backend_run.dart';
import 'package:lopicode/state/workspace_files.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/app_ref.dart';
import 'package:lopicode/ui/backend_panels_sheet.dart';
import 'package:lopicode/ui/backend_run_sheet.dart';
import 'package:lopicode/ui/file_icon.dart';
import 'package:lopicode/ui/shell.dart';
import 'package:lopicode/ui/top_bar.dart';
import 'package:lopicode/ui/widgets.dart';
import 'package:material_ui/material_ui.dart';

/// 改动后等多久再存盘 + 重新生成（连着改几下只存一次）。
const Duration kBackendSaveDelay = Duration(milliseconds: 500);

class BackendScreen extends ConsumerStatefulWidget {
  const BackendScreen({super.key, required this.session, this.file, this.go});
  final ProjectSession session;

  /// `backend.lc.json` 在工作区里的相对路径；不给就找第一份（根目录、server/…）。
  final String? file;

  /// 这一页是从别处单独打开的（文件页的“用积木打开”）时给：要去底部导航的某一页，先关掉自己再调它。
  final void Function(ShellDest dest)? go;

  @override
  ConsumerState<BackendScreen> createState() => BackendScreenState();
}

class BackendScreenState extends ConsumerState<BackendScreen> {
  late final BlockStars? _stars = blockStarsOf(context, 'backend');
  BeBlockHost? _host;
  String _rel = kBackendFileName;
  bool _loading = true;

  /// 打不开的原因（文件坏了 / 没有）；null＝正常。
  String? _problem;
  bool _missing = false;

  /// 磁盘上那份文件现在的内容（我们最后一次读到或写下的）。用来分辨“别处改了”还是“自己刚存的”。
  String? _diskText;

  /// 有改动还没存下去。
  bool _dirty = false;
  Timer? _debounce;
  Future<void> _io = Future.value();
  BackendRegenResult? _regen;

  /// 积木编辑器（“查看问题”要让它打开问题列表、跳到那块积木）。
  final GlobalKey<BlockEditorViewState> _editor = GlobalKey<BlockEditorViewState>();

  /// 上一次生成是不是因为有错误被拦下了（刚变成被拦时提示一次，之后不重复弹）。
  bool _wasBlocked = false;
  int _conflictsShown = 0;

  ProjectSession get _s => widget.session;
  String get _dir => _rel.contains('/') ? _rel.substring(0, _rel.lastIndexOf('/')) : '';

  /// 测试用：现在的宿主（没读好是 null）。
  BeBlockHost? get host => _host;

  /// 测试用：没有没存的改动，手上的读写也都做完了。
  bool get idle => !_dirty && _debounce == null && _jobs == 0;
  int _jobs = 0;

  @override
  void initState() {
    super.initState();
    _queue(_load);
    // 工作区文件变了（Agent 写了文件、文件页保存了）：看看我们这份是不是被改了。
    ref.listenManual(filesRevProvider(_s), (_, _) => _queue(_checkDisk));
  }

  @override
  void dispose() {
    _debounce?.cancel();
    final host = _host;
    host?.onEdited = null;
    host?.onNotice = null;
    // 离开时还有没存的改动：直接存（不等防抖），页面已经没了所以不再碰界面。
    if (_dirty && host != null && !_s.disposed) _queue(() => _write(host.doc.clone()));
    super.dispose();
  }

  /// 读写排成一队，一个做完再做下一个（存盘、重新生成、检查磁盘不会互相踩）。
  void _queue(Future<void> Function() job) {
    _jobs++;
    _io = _io.then((_) async {
      try {
        await job();
      } on FileSystemException catch (e) {
        _say('文件操作失败：${e.osError?.message ?? e.message}');
      } on PathGuardException catch (e) {
        _say(e.message);
      } finally {
        _jobs--;
      }
    });
  }

  void _say(String text) {
    if (mounted) showSnack(context, text);
  }

  File _fileOf(String rel) => File(_s.guard.resolve(rel));

  /// 读文件：文档（读不懂是 null）+ 原文 + 说明。文件不存在返回 null。
  Future<({BeDocument? doc, String text, String? note})?> _read(String rel) async {
    final file = _fileOf(rel);
    if (!await file.exists()) return null;
    if (await file.length() > kBackendMaxFileBytes) return (doc: null, text: '', note: '文件太大了（超过 2MB），没有读');
    final text = await file.readAsString();
    Object? json;
    try {
      json = jsonDecode(text);
    } on FormatException catch (e) {
      return (doc: null, text: text, note: '不是合法的 JSON（${e.message}）');
    }
    if (json is! Map) return (doc: null, text: text, note: '内容不是预期的格式（应该是一个对象）');
    final kind = json['kind'];
    if (kind != null && kind != 'backend') return (doc: null, text: text, note: '这个文件不是后端积木文件（kind 不是 backend）');
    final parsed = BeDocument.fromJson(json);
    return (doc: parsed.doc, text: text, note: parsed.note);
  }

  Future<void> _load() async {
    var rel = widget.file;
    if (rel == null) {
      final found = await findBackendProjects(_s.project.dir);
      rel = found.isEmpty ? kBackendFileName : found.first.file;
    }
    final read = await _read(rel);
    if (!mounted) return;
    setState(() {
      _rel = rel!;
      _loading = false;
      _dirty = false;
      _regen = null;
      _missing = read == null;
      _diskText = read?.text;
      final doc = read?.doc;
      if (doc == null) {
        _host = null;
        _problem = read == null ? '项目里没有 $rel。' : '$rel 打不开：${read.note}。';
      } else {
        _problem = null;
        _adopt(doc);
      }
    });
    final note = read?.doc == null ? null : read?.note;
    if (note != null) _say(note);
  }

  /// 换上一份文档：已经有宿主就原地换（编辑器跟着重排），没有就新建。
  void _adopt(BeDocument doc) {
    final host = _host;
    if (host != null) {
      host.replaceDoc(doc);
    } else {
      _host = BeBlockHost(doc: doc, onEdited: _edited, onNotice: _say);
    }
  }

  /// 工作区文件变了：我们这份的内容和手上记的不一样，才是真的被别处改了。
  Future<void> _checkDisk() async {
    if (!mounted || _loading) return;
    final read = await _read(_rel);
    if (!mounted) return;
    if (read == null) {
      if (_missing) return;
      // 文件被删了。手上有内容就留着（下次改动会重新写出来），只说一声。
      if (_host != null) return _say('$_rel 被删掉了；这里的积木还在，改一下就会重新存出来。');
      return setState(() {
        _missing = true;
        _problem = '项目里没有 $_rel。';
      });
    }
    if (read.text == _diskText) return;
    if (_dirty) {
      // 这里有没存的改动：以这里为准（马上会存下去盖掉那边的），说一声。
      _diskText = read.text;
      return _say('$_rel 在别处被改了，但这里有还没保存的改动——以这里的为准。');
    }
    setState(() {
      _diskText = read.text;
      _missing = false;
      _regen = null;
      final doc = read.doc;
      if (doc == null) {
        _host = null;
        _problem = '$_rel 打不开：${read.note}。';
      } else {
        _problem = null;
        _adopt(doc);
      }
    });
    if (read.doc != null) _say('$_rel 在别处被改了，已重新读取。');
  }

  // —— 保存与生成 ——

  void _edited() {
    _dirty = true;
    _debounce?.cancel();
    _debounce = Timer(kBackendSaveDelay, _flush);
    if (mounted) setState(() {});
  }

  /// 把还没存的改动存下去并重新生成（不等防抖）。
  void _flush() {
    _debounce?.cancel();
    _debounce = null;
    final host = _host;
    if (!_dirty || host == null) return;
    _queue(() => _write(host.doc.clone()));
  }

  /// 存 backend.lc.json，再照它重新生成代码。`overwrite`＝连手改过的生成文件也覆盖（用户确认过才给 true）。
  Future<void> _write(BeDocument snapshot, {bool overwrite = false}) async {
    final text = '${snapshot.encode()}\n';
    final file = _fileOf(_rel);
    await file.parent.create(recursive: true);
    _diskText = text;
    _missing = false;
    await saveBackendFile(file, snapshot);
    // 存的就是现在手上这份 → 没有未保存的改动了（存的过程中又改了的话，那次改动自己会再排一次存盘）。
    if (_host?.doc.encode() == snapshot.encode()) _dirty = false;
    final result = await regenerateBackend(_s.project.dir, file: _rel, doc: snapshot, overwriteEdited: overwrite);
    if (_s.disposed) return;
    _s.filesChanged();
    if (!mounted) return;
    setState(() => _regen = result);
    final newlyBlocked = result.blocked && !_wasBlocked;
    _wasBlocked = result.blocked;
    if (result.blocked) {
      if (!newlyBlocked) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            key: const ValueKey('be-blocked-snack'),
            content: Text(blockErrorsHeadline(result.errorCount)),
            // 深色主题下提示条是浅底，按钮字默认是白的看不清：跟着提示条正文的颜色走。
            action: SnackBarAction(label: '查看问题', textColor: Theme.of(context).snackBarTheme.contentTextStyle?.color, onPressed: _openIssues),
          ),
        );
      return;
    }
    if (!result.ok) return _say('代码没有重新生成：${result.error}');
    final conflicts = result.conflicts.length;
    if (conflicts > 0 && conflicts != _conflictsShown) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            key: const ValueKey('be-conflict-snack'),
            content: Text('有 $conflicts 个文件你手改过，没有覆盖。'),
            action: SnackBarAction(label: '查看', onPressed: _openRegen),
          ),
        );
    }
    _conflictsShown = conflicts;
  }

  void _openIssues() => unawaited(_editor.currentState?.openIssues());

  /// 积木里有错误：拦下“启动 / 看生成情况”，说清楚代码没有更新，给“查看问题”。返回 true＝被拦下了。
  Future<bool> _gate(String action) async {
    final errors = _host?.errorCount ?? 0;
    if (errors == 0) return false;
    final look = await showBlockErrorsGate(context, errors: errors, action: action);
    if (look && mounted) _openIssues();
    return true;
  }

  Future<void> _openRegen() async {
    if (await _gate('重新生成') || !mounted) return;
    final result = _regen;
    if (result == null) return _say('还没有重新生成过：改一下积木就会自动保存并生成。');
    final overwrite = await showBeRegenSheet(context, result);
    final host = _host;
    if (!overwrite || !mounted || host == null) return;
    _queue(() => _write(host.doc.clone(), overwrite: true));
  }

  Future<void> _resetToStarter() async {
    final ok = _missing || await confirmDialog(context, title: '重置为样本？', message: '$_rel 现在的内容会被一份入门样本（问候 + 待办的增删改查）换掉。', confirmLabel: '重置', danger: true);
    if (!ok || !mounted) return;
    final doc = backendStarterDocument(_s.project.name);
    setState(() {
      _problem = null;
      _adopt(doc);
    });
    _queue(() => _write(doc.clone()));
  }

  // —— 顶栏上的入口 ——

  Future<void> _pickLanguage() async {
    final host = _host!;
    final picked = await showBeLanguageSheet(context, current: host.doc.language);
    if (picked == null || picked == host.doc.language || !mounted) return;
    host.edit(() => host.doc.language = picked);
  }

  Future<void> _openData() async {
    final host = _host!;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => BeDataSheet(read: () => host.doc, edit: (change) => host.edit(() => change(host.doc))),
    );
  }

  Future<void> _openSettings() async {
    final host = _host!;
    final next = await showBeSettingsDialog(context, name: host.doc.name, port: host.doc.port);
    if (next == null || !mounted) return;
    host.edit(() {
      host.doc.name = next.name;
      host.doc.port = next.port;
    });
  }

  void _goTo(ShellDest dest) {
    final go = widget.go;
    if (go != null) {
      Navigator.of(context).pop();
      go(dest);
    } else {
      ShellScope.maybeOf(context)?.go(dest);
    }
  }

  Future<void> _openRun() async {
    if (await _gate('启动') || !mounted) return;
    final host = _host!;
    final action = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (context) => BeRunSheet(doc: host.doc, dir: _dir, errorCount: host.errorCount, onStart: () => Navigator.pop(context, 'start'), onOpenRuntime: () => Navigator.pop(context, 'runtime')),
    );
    if (!mounted || action == null) return;
    if (action == 'runtime') return _goTo(ShellDest.runtime);
    final command = backendLaunchCommand(host.doc, dir: _dir);
    if (command == null) return;
    // 先把没存的改动存下去、代码生成好，再去终端敲命令。
    _flush();
    await _io;
    if (!mounted || _s.disposed) return;
    // 工具没装就先装好再启动（没装 Ubuntu 环境的先装环境）；进度、取消、失败原因都在终端页。
    _s.app.container.read(backendRunProvider(_s).notifier).start(language: host.doc.language, command: command);
    _goTo(ShellDest.terminal);
  }

  void _onMenu(String value) {
    switch (value) {
      case 'language':
        unawaited(_pickLanguage());
      case 'data':
        unawaited(_openData());
      case 'settings':
        unawaited(_openSettings());
      case 'regen':
        unawaited(_openRegen());
    }
  }

  /// 变量 / 集合的下拉菜单最后一项“新建…”：建出来并选中是同一次改动。
  BlockMenuExtra? _menuExtra(LcArgSpec arg) {
    final host = _host;
    if (host == null) return null;
    if (arg.kind == LcArgKind.variable) {
      return (
        label: '新建变量…',
        run: (context) async {
          final draft = await showLcVariableDialog(context, taken: {for (final v in host.doc.variables) v.name});
          if (draft == null || draft.delete) return null;
          return (value: draft.name, apply: () => host.doc.addVariable(draft.name, type: draft.type, initial: draft.initial));
        },
      );
    }
    if (arg.kind == LcArgKind.collection) {
      return (
        label: '新建集合…',
        run: (context) async {
          final name = await showBeCollectionDialog(context, taken: {for (final c in host.doc.collections) c.name});
          if (name == null || name.isEmpty) return null;
          return (value: name, apply: () => host.doc.addCollection(name));
        },
      );
    }
    return null;
  }

  /// 副标题：现在什么状态。平时是“语言 · 几个接口”，出了状况换成那句话。
  String _status(BeBlockHost host) {
    final errors = host.errorCount;
    final regen = _regen;
    if (errors > 0) return blockErrorsBrief(errors);
    if (regen != null && !regen.ok) return '代码没有重新生成';
    if (regen != null && regen.conflicts.isNotEmpty) return '${regen.conflicts.length} 个文件没覆盖';
    final target = host.target;
    final lang = target == null ? '${host.doc.language}（没有生成器）' : beLanguageName(target);
    return '$lang · ${host.doc.routes.length} 个接口';
  }

  bool _attention(BeBlockHost host) => host.errorCount > 0 || (_regen != null && (!_regen!.ok || _regen!.conflicts.isNotEmpty));

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final host = _host;
    if (host == null) {
      return Scaffold(
        extendBodyBehindAppBar: true,
        appBar: const ShellAppBar(title: '后端积木'),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : BelowBar(
                child: EmptyState(
                  key: const ValueKey('be-problem'),
                  icon: _missing ? Icons.dns_outlined : Icons.error_outline,
                  title: _missing ? '这里还没有后端积木' : '后端积木文件打不开',
                  message: '${_problem ?? ''}\n${_missing ? '新建一份入门样本，就可以开始搭了。' : '可以去文件页把它修好；或者重置为一份入门样本（原来的内容会被换掉）。'}',
                  action: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FilledButton(key: const ValueKey('be-reset'), onPressed: _resetToStarter, child: Text(_missing ? '新建入门样本' : '重置为样本')),
                      if (!_missing) ...[const SizedBox(height: Space.x2), TextButton(key: const ValueKey('be-go-files'), onPressed: () => _goTo(ShellDest.files), child: const Text('去文件页修'))],
                    ],
                  ),
                ),
              ),
      );
    }
    final target = host.target;
    final attention = _attention(host);
    return BlockEditorView(
      key: _editor,
      host: host,
      title: '后端积木',
      subtitle: _status(host),
      dockMemoryKey: 'backend',
      stars: _stars,
      menuExtra: _menuExtra,
      onHostChanged: () => setState(() {}),
      extraActions: [
        IconButton(key: const ValueKey('be-run'), tooltip: '运行', onPressed: _openRun, icon: const Icon(Icons.play_arrow_rounded)),
        PopupMenuButton<String>(
          key: const ValueKey('be-more'),
          tooltip: '更多',
          onSelected: _onMenu,
          icon: Badge(isLabelVisible: attention, smallSize: 8, backgroundColor: c.warning, child: const Icon(Icons.more_horiz_rounded)),
          itemBuilder: (_) => [
            PopupMenuItem(
              key: const ValueKey('be-menu-language'),
              value: 'language',
              child: Row(
                children: [
                  FileIcon.language(host.doc.language, size: 20),
                  const SizedBox(width: Space.x3),
                  Flexible(child: Text('语言：${target == null ? host.doc.language : beLanguageName(target)}${target != null && !target.verified ? '（未实测）' : ''}')),
                ],
              ),
            ),
            PopupMenuItem(key: const ValueKey('be-menu-data'), value: 'data', child: _menuRow(Icons.data_object_rounded, '变量与集合（${host.doc.variables.length} + ${host.doc.collections.length}）')),
            PopupMenuItem(key: const ValueKey('be-menu-settings'), value: 'settings', child: _menuRow(Icons.tune_rounded, '服务设置（端口 ${host.doc.port}）')),
            PopupMenuItem(
              key: const ValueKey('be-menu-regen'),
              value: 'regen',
              child: _menuRow(
                attention ? Icons.warning_amber_rounded : Icons.task_alt_rounded,
                _regen != null && _regen!.conflicts.isNotEmpty ? '${_regen!.conflicts.length} 个文件没覆盖…' : '代码生成情况',
                color: attention ? c.warning : null,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _menuRow(IconData icon, String text, {Color? color}) => Row(
    children: [
      Icon(icon, size: 20, color: color ?? context.colors.textMuted),
      const SizedBox(width: Space.x3),
      Flexible(child: Text(text)),
    ],
  );
}

/// 给还没有后端积木的工作区建一份入门样本（根目录的 backend.lc.json + 生成的代码）。已经有同名的代码文件不会被覆盖。
Future<BackendRegenResult> createBackendStarter(ProjectSession session, {String language = kBeDefaultLanguage}) async {
  final doc = backendStarterDocument(session.project.name, language: backendTargetFor(language) == null ? kBeDefaultLanguage : language);
  await saveBackendFile(File(session.guard.resolve(kBackendFileName)), doc);
  final result = await regenerateBackend(session.project.dir, file: kBackendFileName, doc: doc);
  session.filesChanged();
  return result;
}

/// 这个文件是不是后端积木文件（文件页据此给“用积木打开”）。`path` 是工作区里的相对路径。
bool isBackendBlocksFile(String path) => path.replaceAll('\\', '/').split('/').last == kBackendFileName;

/// 从文件页单独打开后端积木页（盖在外壳上面，左上角是返回）。要去终端 / 运行环境时先关掉自己，再让外壳切过去。
void openBackendBlocks(BuildContext context, ProjectSession session, String path) {
  final go = ShellScope.maybeOf(context)?.go;
  unawaited(
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BackendScreen(session: session, file: path.replaceAll('\\', '/'), go: go ?? (_) {}),
      ),
    ),
  );
}
