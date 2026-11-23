// 设计约束（文件 · 390×844）
// - 手机上文件树和编辑器不并排：先看文件列表，点文件进编辑器，编辑器顶上是已打开文件的标签条。
// - 文件列表一行一个文件：图标 + 名字（目录按层级缩进）；改名 / 删除收进长按菜单。
// - 编辑器顶栏一行只做“切文件”，保存按钮固定在行尾；未保存用标签上的小圆点表示。
// - 编辑器顶栏行尾：保存 + ⋮（查找、替换、自动换行、撤销、重做）。编辑区见 code_editor.dart。
import 'dart:io';

import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lopicode/core/path_guard.dart';
import 'package:lopicode/core/project_store.dart';
import 'package:lopicode/project_session.dart';
import 'package:lopicode/state/workspace_files.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/code_editor.dart';
import 'package:lopicode/ui/code_highlight.dart';
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
      final file = File(_guard.resolve(path));
      final bytes = await file.readAsBytes();
      if (bytes.length > 1024 * 1024 || bytes.take(8000).contains(0)) {
        if (mounted) showSnack(context, '这个文件是二进制或太大（超过 1MB），不能在编辑器里打开');
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
  Widget build(BuildContext context) => _active >= 0 ? _buildEditor(context) : _buildList(context);

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
              if (_open.isNotEmpty) TextButton(onPressed: () => setState(() => _active = 0), child: Text('回到编辑器（${_open.length}）')),
              PopupMenuButton<String>(
                tooltip: '新建',
                icon: Icon(Icons.add, color: c.accent),
                onSelected: (v) => _create(folder: v == 'folder'),
                itemBuilder: (_) => const [PopupMenuItem(value: 'file', child: Text('新建文件')), PopupMenuItem(value: 'folder', child: Text('新建文件夹'))],
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
                    return InkWell(
                      onTap: isDir ? null : () => _openFile(path),
                      onLongPress: () => _showItemMenu(path),
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(Space.x4 + (parts.length - 1) * Space.x4, 10, Space.x2, 10),
                        child: Row(
                          children: [
                            Icon(isDir ? Icons.folder_outlined : _fileIcon(path), size: 20, color: isDir ? c.accent : c.textFaint),
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
                    );
                  },
                ),
        ),
      ],
    );
  }

  static IconData _fileIcon(String path) => switch (CodeHighlighter.languageFor(path)) {
    'html' => Icons.code,
    'css' => Icons.palette_outlined,
    'js' || 'dart' || 'sh' => Icons.data_object,
    'json' || 'yaml' => Icons.settings_ethernet,
    'md' => Icons.article_outlined,
    _ => Icons.insert_drive_file_outlined,
  };

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
              IconButton(tooltip: '文件列表', icon: const Icon(Icons.menu_open), onPressed: () => setState(() => _active = -1)),
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
                            Text(f.name, style: active ? t.titleSmall : t.bodyMedium?.copyWith(color: c.textMuted)),
                            InkWell(
                              borderRadius: BorderRadius.circular(Radii.sm),
                              onTap: () => _close(i),
                              child: Padding(
                                padding: const EdgeInsets.all(6),
                                child: Icon(Icons.close, size: 14, color: c.textFaint),
                              ),
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
                    case 'wrap':
                      setState(() => _wordWrap = !_wordWrap);
                    case 'undo':
                      file.controller.undo();
                    case 'redo':
                      file.controller.redo();
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(value: 'find', child: Text('查找')),
                  const PopupMenuItem(value: 'replace', child: Text('查找并替换')),
                  PopupMenuItem(value: 'wrap', child: Text(_wordWrap ? '关闭自动换行' : '打开自动换行')),
                  PopupMenuItem(value: 'undo', enabled: file.controller.canUndo, child: const Text('撤销')),
                  PopupMenuItem(value: 'redo', enabled: file.controller.canRedo, child: const Text('重做')),
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
