// 设计约束（文件 · 390×844）
// - 手机上文件树和编辑器不并排：先看文件列表，点文件进编辑器，编辑器顶上是已打开文件的标签条。
// - 文件列表一行一个文件：图标 + 名字（目录按层级缩进）；改名 / 删除收进长按菜单。
// - 编辑器打不开的文件（安装包、二进制、超过 1MB）点了出信息面板（file_info_sheet.dart），安装包在面板里能直接装。
// - 编辑器顶栏一行只做“切文件”，保存按钮固定在行尾；未保存用标签上的小圆点表示。
// - 编辑器顶栏行尾：保存 + ⋮（查找、替换、格式化、自动换行、撤销、重做）。编辑区见 code_editor.dart，格式化见 editor_format.dart。
import 'dart:io';

import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lopicode/core/path_guard.dart';
import 'package:lopicode/core/project_store.dart';
import 'package:lopicode/project_session.dart';
import 'package:lopicode/state/workspace_files.dart';
import 'package:lopicode/theme/breakpoints.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/backend_screen.dart';
import 'package:lopicode/ui/code_editor.dart';
import 'package:lopicode/ui/editor_format.dart';
import 'package:lopicode/ui/file_icon.dart';
import 'package:lopicode/ui/file_info_sheet.dart';
import 'package:lopicode/ui/keyboard_tap_dismiss.dart';
import 'package:lopicode/ui/widgets.dart';
import 'package:material_ui/material_ui.dart';
import 'package:re_editor/re_editor.dart';

class _OpenFile {
  _OpenFile(this.path, String content) : controller = CodeLineEditingController.fromText(content) {
    findController = CodeFindController(controller);
    saved = controller.text; // 编辑器会把换行统一成 \n，以它读回来的为准
  }
  final String path;
  final CodeLineEditingController controller;
  late final CodeFindController findController;
  late String saved;

  /// 有没有未保存的修改。每次内容变化时算一次并记下来，界面重画时不用再拼整篇文本。
  bool dirty = false;
  void refreshDirty() => dirty = controller.text != saved;

  void dispose() {
    findController.dispose();
    controller.dispose();
  }

  String get name => path.split('/').last;
}

class FilesTab extends ConsumerStatefulWidget {
  const FilesTab({super.key, required this.session, this.initialOpen});
  final ProjectSession session;

  /// 测试 / 截图用：一进来就打开这个文件。
  final String? initialOpen;

  @override
  ConsumerState<FilesTab> createState() => _FilesTabState();
}

class _FilesTabState extends ConsumerState<FilesTab> {
  List<String>? _files;
  final List<_OpenFile> _open = [];

  /// 现在是不是两栏（宽屏）。
  bool _split = false;
  final _listKey = GlobalKey();
  final _editorKey = GlobalKey();
  int _active = -1; // -1 = 显示文件列表
  bool _wordWrap = true;

  PathGuard get _guard => widget.session.guard;

  @override
  void initState() {
    super.initState();
    // 别处改了项目文件就跟着刷新（页面销毁时自动取消订阅）
    ref.listenManual(filesRevProvider(widget.session), (_, _) => _onFilesChanged());
    _reload().then((_) {
      final first = widget.initialOpen;
      if (first != null) _openFile(first);
    });
  }

  @override
  void dispose() {
    for (final f in _open) {
      f.dispose();
    }
    super.dispose();
  }

  Future<void> _reload() async {
    try {
      final files = await listProjectFiles(_guard);
      if (mounted) setState(() => _files = files);
    } on PathGuardException {
      if (mounted) setState(() => _files = []);
    }
  }

  /// 别处（Agent、低代码）改了文件：刷新列表；没有未保存修改的标签同步成磁盘上的内容。
  Future<void> _onFilesChanged() async {
    await _reload();
    for (final f in List.of(_open)) {
      final file = File(_guard.resolve(f.path));
      if (!await file.exists()) {
        // 等文件系统的这会儿，标签可能已经被用户关掉了（indexOf 得 -1）：那就不用再关
        final index = _open.indexOf(f);
        if (!f.dirty && index >= 0) await _close(index, force: true);
        continue;
      }
      if (f.dirty) continue;
      final text = await file.readAsString();
      if (text != f.saved && mounted) {
        setState(() {
          f.controller.text = text;
          f.saved = f.controller.text;
          f.refreshDirty();
        });
      }
    }
  }

  Future<void> _openFile(String path) async {
    final existing = _open.indexWhere((f) => f.path == path);
    if (existing >= 0) {
      setState(() => _active = existing);
      return;
    }
    try {
      final full = _guard.resolve(path);
      final file = File(full);
      // 先看大小再决定读不读：安装包、大文件不整个读进内存（原来是先全读进来再判断）。
      final size = await file.length();
      final block = isApkPath(path)
          ? FileBlock.apk
          : size > kEditorMaxBytes
          ? FileBlock.tooLarge
          : (await file.readAsBytes()).take(8000).contains(0)
          ? FileBlock.binary
          : null;
      if (block != null) {
        // 编辑器打不开的：给一张信息面板（安装包能直接装），不再只弹一句话。
        if (mounted) await showFileInfoSheet(context, path: path, fullPath: full, block: block, sizeBytes: size, onRename: () => _rename(path), onDelete: () => _delete(path));
        return;
      }
      final opened = _OpenFile(path, await file.readAsString());
      opened.controller.addListener(() => _onEdited(opened));
      if (!mounted) return;
      setState(() {
        _open.add(opened);
        _active = _open.length - 1;
      });
    } on Exception {
      if (mounted) showSnack(context, '打不开 $path');
    }
  }

  /// 编辑器内容变了。re_editor 有时在自己 build 的过程中通知（例如首次排版），
  /// 那时不能直接 setState，挪到这一帧结束后。
  void _onEdited(_OpenFile f) {
    if (!mounted) return;
    final before = f.dirty;
    f.refreshDirty();
    if (before == f.dirty) return;
    if (SchedulerBinding.instance.schedulerPhase == SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    } else {
      setState(() {});
    }
  }

  Future<void> _save() async {
    final f = _open[_active];
    try {
      final text = f.controller.text;
      await File(_guard.resolve(f.path)).writeAsString(text);
      setState(() {
        f.saved = text;
        f.refreshDirty();
      });
      widget.session.filesChanged();
    } on Exception {
      if (mounted) showSnack(context, '保存失败');
    }
  }

  Future<void> _close(int index, {bool force = false}) async {
    final f = _open[index];
    if (f.dirty && !force) {
      final ok = await confirmDialog(context, title: '放弃未保存的修改？', message: f.name, confirmLabel: '放弃', danger: true);
      if (!ok) return;
    }
    if (!mounted) return;
    setState(() {
      _open.removeAt(index).dispose();
      _active = _open.isEmpty ? -1 : _active.clamp(0, _open.length - 1);
    });
  }

  Future<void> _create({required bool folder}) async {
    final name = await promptDialog(context, title: folder ? '新建文件夹' : '新建文件', hint: folder ? '例如 assets' : '例如 about.html 或 js/app.js', confirmLabel: '创建');
    if (name == null || name.trim().isEmpty || !mounted) return;
    try {
      final full = _guard.resolve(name.trim());
      if (folder) {
        await Directory(full).create(recursive: true);
      } else {
        final file = File(full);
        if (await file.exists()) {
          if (mounted) showSnack(context, '已经有同名文件了');
          return;
        }
        await file.create(recursive: true);
      }
      widget.session.filesChanged();
      if (!folder) await _openFile(_guard.relative(full));
    } on PathGuardException catch (e) {
      if (mounted) showSnack(context, e.message);
    } on FileSystemException {
      if (mounted) showSnack(context, '创建失败');
    }
  }

  Future<void> _rename(String path) async {
    final isDir = path.endsWith('/');
    final clean = isDir ? path.substring(0, path.length - 1) : path;
    final next = await promptDialog(context, title: '重命名 / 移动', initial: clean, confirmLabel: '保存');
    if (next == null || next.trim().isEmpty || next.trim() == clean || !mounted) return;
    try {
      final from = _guard.resolve(clean);
      final to = _guard.resolve(next.trim());
      if (await FileSystemEntity.type(to) != FileSystemEntityType.notFound) {
        if (mounted) showSnack(context, '目标位置已经有同名文件了');
        return;
      }
      await Directory(to).parent.create(recursive: true);
      await (isDir ? Directory(from).rename(to) : File(from).rename(to));
      setState(() {
        _open.removeWhere((f) {
          final hit = f.path == clean || f.path.startsWith('$clean/');
          if (hit) f.dispose();
          return hit;
        });
        _active = _open.isEmpty ? -1 : _active.clamp(-1, _open.length - 1);
      });
      widget.session.filesChanged();
    } on PathGuardException catch (e) {
      if (mounted) showSnack(context, e.message);
    } on FileSystemException {
      if (mounted) showSnack(context, '重命名失败');
    }
  }

  Future<void> _delete(String path) async {
    final isDir = path.endsWith('/');
    final ok = await confirmDialog(context, title: '删除 $path？', message: isDir ? '文件夹里的所有内容都会被删除，无法恢复。' : '删除后无法恢复。', confirmLabel: '删除', danger: true);
    if (!ok) return;
    try {
      final full = _guard.resolve(path);
      await (isDir ? Directory(full).delete(recursive: true) : File(full).delete());
      widget.session.filesChanged();
    } on Exception {
      if (mounted) showSnack(context, '删除失败');
    }
  }

  void _showItemMenu(String path) {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.drive_file_rename_outline),
              title: const Text('重命名 / 移动'),
              onTap: () {
                Navigator.pop(context);
                _rename(path);
              },
            ),
            ListTile(
              leading: Icon(Icons.delete_outline, color: context.colors.danger),
              title: Text('删除', style: TextStyle(color: context.colors.danger)),
              onTap: () {
                Navigator.pop(context);
                _delete(path);
              },
            ),
            const SizedBox(height: Space.x2),
          ],
        ),
      ),
    );
  }

  @override
  // 编辑器那一页整页都是输入区（页签、保存、菜单、查找框、编辑区）：点哪里都不收键盘。
  Widget build(BuildContext context) {
    // 宽屏：文件树常驻在左、编辑器在右（中屏和手机还是一次看一样）。
    _split = Breakpoints.of(context).isExpanded;
    // 列表和编辑器各挂一个全局 key：一栏和两栏之间换位置时原样挪过去，不重建（编辑器重建会丢光标、滚动位置，
    // 而且 re_editor 的控制器不能在旧编辑器还没拆完时接到新编辑器上）。
    final list = KeyedSubtree(key: _listKey, child: _buildList(context));
    if (_split && _active < 0 && _open.isNotEmpty) _active = 0; // 两栏时没有“回到文件列表”这一说：开着文件就一直显示编辑器
    final editor = _active >= 0
        ? KeyedSubtree(
            key: _editorKey,
            child: KeyboardKeep(child: _buildEditor(context)),
          )
        : null;
    if (!_split) return editor ?? list;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(key: const ValueKey('files-side'), width: Breakpoints.side, child: list),
        VerticalDivider(width: 1, thickness: 1, color: context.colors.border),
        Expanded(
          child: editor ?? const EmptyState(icon: Icons.description_outlined, title: '还没打开文件', message: '在左边点一个文件，就在这里打开。'),
        ),
      ],
    );
  }

  Widget _buildList(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final files = _files;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.x4, Space.x1, Space.x2, Space.x1),
          child: Row(
            children: [
              Expanded(child: Text(files == null ? '文件' : '${files.where((f) => !f.endsWith('/')).length} 个文件', style: t.labelMedium)),
              if (_open.isNotEmpty && !_split) TextButton(onPressed: () => setState(() => _active = 0), child: Text('回到编辑器（${_open.length}）')),
              PopupMenuButton<String>(
                tooltip: '新建',
                onSelected: (v) => _create(folder: v == 'folder'),
                itemBuilder: (_) => const [PopupMenuItem(value: 'file', child: Text('新建文件')), PopupMenuItem(value: 'folder', child: Text('新建文件夹'))],
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Space.x2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.add, color: c.accent),
                      const SizedBox(width: Space.x1),
                      Text('新建', style: t.labelLarge?.copyWith(color: c.accent)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: files == null
              ? const Center(child: CircularProgressIndicator())
              : files.isEmpty
              ? EmptyState(
                  icon: Icons.note_add_outlined,
                  title: '项目里还没有文件',
                  message: '新建一个文件，或者到 Agent 页签让它帮你写。',
                  action: FilledButton.icon(onPressed: () => _create(folder: false), icon: const Icon(Icons.add), label: const Text('新建文件')),
                )
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: Space.x6),
                  itemCount: files.length,
                  itemBuilder: (context, i) {
                    final path = files[i];
                    final isDir = path.endsWith('/');
                    final parts = (isDir ? path.substring(0, path.length - 1) : path).split('/');
                    return Material(
                      // 两栏时左边标出右边正开着的那个文件
                      color: _split && _active >= 0 && _open[_active].path == path ? c.selectedBg : Colors.transparent,
                      child: InkWell(
                        key: ValueKey('file-row-$path'),
                        onTap: isDir ? null : () => _openFile(path),
                        onLongPress: () => _showItemMenu(path),
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(Space.x4 + (parts.length - 1) * Space.x4, 10, Space.x2, 10),
                          child: Row(
                            children: [
                              FileIcon(path, isDir: isDir, open: isDir),
                              const SizedBox(width: Space.x3),
                              Expanded(
                                child: Text(parts.last, style: isDir ? t.titleSmall : t.bodyMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                              ),
                              IconButton(
                                tooltip: '更多',
                                visualDensity: VisualDensity.compact,
                                icon: Icon(Icons.more_horiz, size: 20, color: c.textFaint),
                                onPressed: () => _showItemMenu(path),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildEditor(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final file = _open[_active];
    return Column(
      children: [
        Container(
          height: 44,
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: c.border)),
          ),
          child: Row(
            children: [
              if (!_split) IconButton(tooltip: '文件列表', icon: const Icon(Icons.menu_open), onPressed: () => setState(() => _active = -1)),
              Expanded(
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: _open.length,
                  itemBuilder: (context, i) {
                    final f = _open[i];
                    final active = i == _active;
                    return InkWell(
                      onTap: () => setState(() => _active = i),
                      child: Container(
                        padding: const EdgeInsets.only(left: Space.x3, right: Space.x1),
                        decoration: BoxDecoration(
                          border: Border(bottom: BorderSide(color: active ? c.accentFill : Colors.transparent, width: 2)),
                        ),
                        child: Row(
                          children: [
                            if (f.dirty)
                              Container(
                                width: 6,
                                height: 6,
                                margin: const EdgeInsets.only(right: 6),
                                decoration: BoxDecoration(color: c.warning, shape: BoxShape.circle),
                              ),
                            Padding(padding: const EdgeInsets.only(right: 6), child: FileIcon(f.name, size: 16)),
                            Text(f.name, style: active ? t.titleSmall : t.bodyMedium?.copyWith(color: c.textMuted)),
                            IconButton(
                              tooltip: '关闭 ${f.name}',
                              onPressed: () => _close(i),
                              style: IconButton.styleFrom(
                                minimumSize: const Size(34, 34),
                                fixedSize: const Size(34, 34),
                                padding: EdgeInsets.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                foregroundColor: c.textFaint,
                              ),
                              icon: const Icon(Icons.close, size: 14),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(left: Space.x2),
                child: TextButton(onPressed: file.dirty ? _save : null, child: Text(file.dirty ? '保存' : '已保存')),
              ),
              PopupMenuButton<String>(
                tooltip: '编辑器菜单',
                icon: const Icon(Icons.more_vert),
                onSelected: (v) {
                  switch (v) {
                    case 'find':
                      file.findController.findMode();
                    case 'replace':
                      file.findController.replaceMode();
                    case 'format':
                      showSnack(context, formatInEditor(file.controller, file.path));
                    case 'wrap':
                      setState(() => _wordWrap = !_wordWrap);
                    case 'undo':
                      file.controller.undo();
                    case 'redo':
                      file.controller.redo();
                    case 'blocks':
                      openBackendBlocks(context, widget.session, file.path);
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(value: 'find', child: Text('查找')),
                  const PopupMenuItem(value: 'replace', child: Text('查找并替换')),
                  PopupMenuItem(value: 'format', enabled: canFormat(file.path), child: const Text('格式化')),
                  PopupMenuItem(value: 'wrap', child: Text(_wordWrap ? '关闭自动换行' : '打开自动换行')),
                  PopupMenuItem(value: 'undo', enabled: file.controller.canUndo, child: const Text('撤销')),
                  PopupMenuItem(value: 'redo', enabled: file.controller.canRedo, child: const Text('重做')),
                  if (isBackendBlocksFile(file.path)) const PopupMenuItem(key: ValueKey('editor-open-blocks'), value: 'blocks', child: Text('用积木打开')),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: LopiCodeEditor(key: ValueKey(file.path), path: file.path, controller: file.controller, findController: file.findController, wordWrap: _wordWrap),
        ),
      ],
    );
  }
}
