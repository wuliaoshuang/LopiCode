// 设计约束（导出 Vue / React · 390×844）— 2026-11-24
// - 底部面板，从上到下一行只做一件事：
//   标题 → 分段选择（Vue 3 / React）→ 文件清单（一行一个文件：路径 + 行数，点开看代码）
//   → 一小段弱化的说明（没有真的编译过 + 这次导出简化 / 跳过了什么）→ 固定在底部的结果提示和唯一的主操作“导出到项目”。
// - 文件清单和说明一起滚动；标题、分段选择、主按钮不跟着滚。
// - 看某个文件的代码复用现成的 CodeSheetBody（等宽、可选中、可复制），另开一层面板，不挤在这一层里。
// - 导出的结果（成功 / 失败的真正原因）写在主按钮上方，不用会被面板挡住的底部提示条。
import 'dart:io';

import 'package:lopicode/core/path_guard.dart';
import 'package:lopicode/lowcode/code_sheet.dart';
import 'package:lopicode/lowcode/export_react.dart';
import 'package:lopicode/lowcode/export_vue.dart';
import 'package:lopicode/lowcode/image_assets.dart';
import 'package:lopicode/lowcode/logic_gate.dart';
import 'package:lopicode/lowcode/model.dart';
import 'package:lopicode/project_session.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/code_highlight.dart';
import 'package:material_ui/material_ui.dart';

/// 选一种框架导出，把生成的文件写进项目的 export/ 目录并展示代码。
Future<void> showFrameworkExport(BuildContext context, {required LcDocument doc, required ProjectSession session}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  builder: (_) => FrameworkExportSheet(doc: doc, session: session),
);

/// 两种导出各自写到项目里的哪个目录。
const String kVueExportDir = 'export/vue';
const String kReactExportDir = 'export/react';

const String kExportNotCompiledNote = '生成的代码没有用 Vue / React 的编译器实际编译过；放进你的工程后如有报错告诉我。';

/// 把一次导出的文件写进项目的 [dir] 目录，返回写了几个。
///
/// 每个路径都先过 `session.guard.resolve`（越出项目目录、碰内部目录都会抛 [PathGuardException]），
/// 而且是**全部查完才开始写**：有一个路径不行就一个文件都不写。写文件失败抛 [FileSystemException]。
Future<int> writeFrameworkExport(ProjectSession session, String dir, LcFrameworkExport export) async {
  final targets = <(File, String)>[];
  for (final f in export.files) {
    // 导出的路径是我们自己起的（大驼峰英文名 + 固定的目录），这里再查一遍，防以后有人改了起名规则。
    if (!RegExp(r'^(?:[A-Za-z0-9_-]+/)*[A-Za-z0-9_-]+\.[a-z]+$').hasMatch(f.path)) {
      throw PathGuardException('导出的文件名不合规矩：${f.path}');
    }
    targets.add((File(session.guard.resolve('$dir/${f.path}')), f.content));
  }
  try {
    for (final (file, content) in targets) {
      await file.parent.create(recursive: true);
      await file.writeAsString(content);
    }
  } finally {
    // 写到一半失败时，前面几个文件已经在了：文件树也要刷新。
    session.filesChanged();
  }
  return targets.length;
}

class FrameworkExportSheet extends StatefulWidget {
  const FrameworkExportSheet({super.key, required this.doc, required this.session});
  final LcDocument doc;
  final ProjectSession session;

  @override
  State<FrameworkExportSheet> createState() => _FrameworkExportSheetState();
}

class _FrameworkExportSheetState extends State<FrameworkExportSheet> {
  // 两种都在打开面板时生成一次（纯计算，很快）；切换分段只是换着看。
  late final LcFrameworkExport _vue = exportVue(widget.doc);
  late final LcFrameworkExport _react = exportReact(widget.doc);
  String _kind = 'vue';
  bool _busy = false;
  String? _result;
  bool _failed = false;

  LcFrameworkExport get _export => _kind == 'vue' ? _vue : _react;
  String get _dir => _kind == 'vue' ? kVueExportDir : kReactExportDir;

  Future<void> _write() async {
    // 积木逻辑有“错误”：不导出（和 logic.js、后端代码一个规矩），说清楚去哪修。
    final byPage = lcLogicErrorsByPage(widget.doc);
    final errors = byPage.values.fold(0, (a, b) => a + b);
    if (errors > 0) {
      setState(() {
        _result = lcExportBlockedText(errors, widget.doc.isMultiPage ? byPage : null);
        _failed = true;
      });
      return;
    }
    setState(() {
      _busy = true;
      _result = null;
    });
    final dir = _dir;
    String message;
    var failed = false;
    try {
      final count = await writeFrameworkExport(widget.session, dir, _export);
      // 页面里用了项目里的图片：一起带过去，不然导出的代码里图片是断的。
      final images = await lcCopyExportImages(widget.session.guard, dir, widget.doc);
      if (images > 0) widget.session.filesChanged();
      message = images == 0 ? '已导出 $count 个文件到 $dir/' : '已导出 $count 个文件到 $dir/；用到的 $images 张图片在 $dir/public/ 里，请一起放进工程的 public 目录';
    } on PathGuardException catch (e) {
      failed = true;
      message = '没有导出：${e.message}';
    } on FileSystemException catch (e) {
      failed = true;
      final path = e.path;
      final where = path == null ? '' : '（${widget.session.guard.relative(path)}）';
      message = '写文件失败$where：${e.osError?.message ?? e.message}。已经写好的文件还在 $dir/ 里。';
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _result = message;
      _failed = failed;
    });
  }

  void _openFile(LcExportFile f) {
    final problem = f.formatProblem;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => CodeSheetBody(title: f.path, note: problem == null ? '导出后在项目的 $_dir/${f.path}' : '这个文件没排版：$problem', code: f.content, language: CodeHighlighter.languageFor(f.path)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final export = _export;
    final media = MediaQuery.of(context);
    final muted = t.bodySmall?.copyWith(color: c.textMuted, height: 1.5);
    final result = _result;
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: media.size.height * 0.86),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.x4, 0, Space.x4, Space.x3),
              child: Text('导出 Vue / React', style: t.titleLarge),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.x4),
              child: SegmentedButton<String>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: 'vue', label: Text('Vue 3')),
                  ButtonSegment(value: 'react', label: Text('React')),
                ],
                selected: {_kind},
                onSelectionChanged: _busy
                    ? null
                    : (s) => setState(() {
                        _kind = s.first;
                        _result = null;
                      }),
              ),
            ),
            const SizedBox(height: Space.x2),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.only(bottom: Space.x2),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(Space.x4, Space.x2, Space.x4, Space.x1),
                    child: Text('会生成 ${export.files.length} 个文件，放进项目的 $_dir/（点一个看代码）', style: muted),
                  ),
                  for (final f in export.files) _FileRow(key: ValueKey('lc-export-file-${f.path}'), file: f, onTap: () => _openFile(f)),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(Space.x4, Space.x3, Space.x4, 0),
                    child: Text([kExportNotCompiledNote, for (final n in export.notes) '· $n'].join('\n'), key: const ValueKey('lc-export-notes'), style: muted),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.x4, Space.x2, Space.x4, Space.x4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (result != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: Space.x2),
                      child: Text(
                        result,
                        key: const ValueKey('lc-export-result'),
                        style: t.bodyMedium?.copyWith(color: _failed ? c.danger : c.text),
                      ),
                    ),
                  FilledButton.icon(key: const ValueKey('lc-export-write'), onPressed: _busy ? null : _write, icon: const Icon(Icons.save_alt, size: 18), label: Text(_busy ? '正在导出…' : '导出到项目')),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FileRow extends StatelessWidget {
  const _FileRow({super.key, required this.file, required this.onTap});
  final LcExportFile file;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final problem = file.formatProblem;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.x4, vertical: Space.x3),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    file.path,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontFamily: kMonoFont, fontFamilyFallback: kMonoFallback, fontSize: FontSize.sm, color: c.text),
                  ),
                  if (problem != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text('这个文件没排版：$problem', style: t.bodySmall?.copyWith(color: c.warning)),
                    ),
                ],
              ),
            ),
            const SizedBox(width: Space.x3),
            Text('${file.lineCount} 行', style: t.bodySmall?.copyWith(color: c.textMuted)),
            const SizedBox(width: Space.x1),
            Icon(Icons.chevron_right, size: 20, color: c.textFaint),
          ],
        ),
      ),
    );
  }
}
