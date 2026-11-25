// 设计约束（管理主题 › 导入主题 · 两页 · 390×844）— 2026-11-26
// 第一页「导入主题」——把主题文本拿进来，一行一件事：
// - 一句说明 → 一个多行输入框（粘贴别人发来的主题文本）→ “从剪贴板粘贴” → “从工作区文件里选”（只列 .json 文件，主题文件排前面）
//   → 出错时输入框下面一句人话说原因 → 主操作“检查并预览”（底部一整行；框里没字时是灰的）。
// - 这里只读文本、只做检查：**不执行文件里的任何东西，不联网**。检查没过不往下走。
// 第二页「导入预览」——加进来之前先看看：
// - 名字（大）→ 作者 · 浅色 / 深色 → 预览（界面 / 代码 / 积木 / 终端四种可切）→ 对比度检查结果（都达标，或“N 项偏低”+ 前几条）
//   → 检查时的提示（跳过了哪些不认识的字段、补了哪些缺的）→ 带没带背景图（带了且背景图那部分接上了才有“同时使用”的勾选）。
// - 底部三个按钮各占一行：加入并立即使用（主操作）· 加入我的主题 · 取消。重名会自动改名，加进来以后告诉她叫什么。
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lopicode/appearance/theme_contrast.dart';
import 'package:lopicode/appearance/theme_export_file.dart';
import 'package:lopicode/appearance/theme_json.dart';
import 'package:lopicode/core/path_guard.dart';
import 'package:lopicode/project_session.dart';
import 'package:lopicode/session/file_mentions.dart';
import 'package:lopicode/state/theme_hooks.dart';
import 'package:lopicode/state/themes_state.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/keyboard_tap_dismiss.dart';
import 'package:lopicode/ui/settings_widgets.dart';
import 'package:lopicode/ui/theme_export_sheet.dart';
import 'package:lopicode/ui/theme_preview.dart';
import 'package:lopicode/ui/top_bar.dart';
import 'package:material_ui/material_ui.dart';

/// 从工作区读一个主题文件的文本。读不了就抛 [FormatException]，message 是给人看的原因。
Future<String> readThemeFile(PathGuard guard, String relative) async {
  final File file;
  try {
    file = File(guard.resolve(relative));
  } on PathGuardException catch (e) {
    throw FormatException(e.message);
  }
  try {
    final size = await file.length();
    if (size > kThemeImportMaxBytes) throw FormatException('这个文件有 ${formatThemeBytes(size)}，超过了能收的 ${formatThemeBytes(kThemeImportMaxBytes)}，不像是主题文件。');
    return utf8.decode(await file.readAsBytes());
  } on FileSystemException catch (e) {
    throw FormatException('读不了这个文件：${e.osError?.message ?? e.message}');
  } on FormatException catch (e) {
    if (e.message.startsWith('这个文件有')) rethrow;
    throw const FormatException('这个文件不是文本（可能是图片或压缩包），不是主题文件。');
  }
}

/// 工作区里可能是主题文件的那些（.json），主题文件（.lopitheme.json）排前面。
List<String> themeFileCandidates(List<String> files) {
  final json = files.where((f) => f.toLowerCase().endsWith('.json')).toList();
  final mine = json.where((f) => f.toLowerCase().endsWith(kThemeFileSuffix)).toList();
  return [...mine, ...json.where((f) => !mine.contains(f))];
}

class ThemeImportScreen extends StatefulWidget {
  const ThemeImportScreen({super.key, this.session});
  final ProjectSession? session;

  @override
  State<ThemeImportScreen> createState() => _ThemeImportScreenState();
}

class _ThemeImportScreenState extends State<ThemeImportScreen> {
  final TextEditingController _text = TextEditingController();
  String? _error;

  /// 从文件读进来的原文（很大的文件不往输入框里塞，只在框里写一行说明）。
  String? _fileText;
  String? _fileLabel;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  String get _source => _fileText ?? _text.text;

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (!mounted) return;
    final text = data?.text ?? '';
    if (text.trim().isEmpty) return setState(() => _error = '剪贴板里现在没有文字。先在聊天软件里把主题文本整段复制下来。');
    setState(() {
      _fileText = null;
      _fileLabel = null;
      _text.text = text;
      _error = null;
    });
  }

  Future<void> _pickFile() async {
    final ws = await pickThemeWorkspace(context, widget.session, title: '从哪个工作区里选？');
    if (!mounted) return;
    if (ws == null) return setState(() => _error = '现在一个工作区都没有，没有文件可选。改用“从剪贴板粘贴”。');
    final path = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _ThemeFileSheet(guard: ws.guard, workspace: ws.name),
    );
    if (path == null || !mounted) return;
    try {
      final text = await readThemeFile(ws.guard, path);
      if (!mounted) return;
      setState(() {
        _fileText = text;
        _fileLabel = '${ws.name} / $path（${formatThemeBytes(themeTextBytes(text))}）';
        _text.clear();
        _error = null;
      });
      await _check();
    } on FormatException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _check() async {
    final text = _source;
    final r = decodeThemeText(text);
    if (!r.ok) return setState(() => _error = r.error);
    setState(() => _error = null);
    final added = await pushSettingsPage<ThemeSpec>(context, ThemeImportPreviewScreen(text: text, result: r));
    if (added != null && mounted) Navigator.pop(context, added);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final has = _source.trim().isNotEmpty;
    return Scaffold(
      backgroundColor: c.canvas,
      extendBodyBehindAppBar: true,
      appBar: PageBar(background: c.canvas, titleText: '导入主题'),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Space.x4, Space.x2, Space.x4, Space.x2),
          child: FilledButton(key: const Key('theme-import-check'), onPressed: has ? _check : null, child: const Text('检查并预览')),
        ),
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(Space.x4, PageBar.insetOf(context) + Space.x2, Space.x4, Space.x6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('把别人发来的主题文本粘贴到下面，或者从工作区里选一个主题文件。只会读里面的颜色和数值，不会运行任何东西，也不联网。', style: t.bodySmall?.copyWith(color: c.textMuted)),
            const SizedBox(height: Space.x3),
            if (_fileLabel != null)
              Container(
                key: const Key('theme-import-file'),
                padding: const EdgeInsets.all(Space.x3),
                decoration: BoxDecoration(
                  color: c.surface,
                  borderRadius: BorderRadius.circular(c.radius(Radii.md)),
                  border: Border.all(color: c.border, width: c.hairline),
                ),
                child: Row(
                  children: [
                    Icon(Icons.description_outlined, size: 20, color: c.textMuted),
                    const SizedBox(width: Space.x2),
                    Expanded(child: Text(_fileLabel!, style: t.bodyMedium)),
                    IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      tooltip: '不用这个文件',
                      onPressed: () => setState(() {
                        _fileText = null;
                        _fileLabel = null;
                        _error = null;
                      }),
                    ),
                  ],
                ),
              )
            else
              TextField(
                key: const Key('theme-import-text'),
                controller: _text,
                minLines: 6,
                maxLines: 10,
                autocorrect: false,
                enableSuggestions: false,
                style: t.bodySmall?.copyWith(fontFamily: kMonoFont, fontFamilyFallback: kMonoFallback),
                decoration: const InputDecoration(hintText: '在这里粘贴主题文本（以 { 开头的一大段）', alignLabelWithHint: true),
                onChanged: (_) => setState(() => _error = null),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: Space.x2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.error_outline, size: 16, color: c.danger),
                    const SizedBox(width: Space.x1),
                    Expanded(
                      child: Text(
                        _error!,
                        key: const Key('theme-import-error'),
                        style: t.bodySmall?.copyWith(color: c.danger),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: Space.x3),
            KeyboardKeep(
              child: OutlinedButton.icon(key: const Key('theme-import-paste'), onPressed: _paste, icon: const Icon(Icons.content_paste, size: 18), label: const Text('从剪贴板粘贴')),
            ),
            const SizedBox(height: Space.x2),
            OutlinedButton.icon(key: const Key('theme-import-file-pick'), onPressed: _pickFile, icon: const Icon(Icons.folder_open_outlined, size: 18), label: const Text('从工作区文件里选')),
          ],
        ),
      ),
    );
  }
}

/// 从工作区里挑一个 .json 文件。
class _ThemeFileSheet extends StatelessWidget {
  const _ThemeFileSheet({required this.guard, required this.workspace});
  final PathGuard guard;
  final String workspace;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.7),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.x4, 0, Space.x4, Space.x1),
              child: Text('选一个主题文件', style: t.titleMedium),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.x4, 0, Space.x4, Space.x2),
              child: Text('工作区“$workspace”里的 .json 文件。导出的主题文件在 exports/ 里。', style: t.bodySmall?.copyWith(color: c.textMuted)),
            ),
            Flexible(
              child: FutureBuilder<MentionScan>(
                future: scanMentionFiles(guard),
                builder: (context, snap) {
                  final scan = snap.data;
                  if (scan == null) {
                    return const Padding(
                      padding: EdgeInsets.all(Space.x6),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  final files = themeFileCandidates(scan.files);
                  if (files.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.all(Space.x6),
                      child: Text(
                        scan.error ?? '这个工作区里没有 .json 文件。把别人发来的主题文件放进工作区，或者改用“从剪贴板粘贴”。',
                        key: const Key('theme-file-empty'),
                        textAlign: TextAlign.center,
                        style: t.bodyMedium?.copyWith(color: c.textMuted),
                      ),
                    );
                  }
                  return ListView.builder(
                    shrinkWrap: true,
                    itemCount: files.length,
                    itemBuilder: (context, i) => ListTile(
                      key: Key('theme-file-${files[i]}'),
                      dense: true,
                      leading: Icon(files[i].endsWith(kThemeFileSuffix) ? Icons.palette_outlined : Icons.data_object, size: 20),
                      title: Text(files[i], maxLines: 2, overflow: TextOverflow.ellipsis),
                      onTap: () => Navigator.pop(context, files[i]),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 导入预览：加进来之前先看看。返回加进来的那套主题（取消是 null）。
class ThemeImportPreviewScreen extends ConsumerStatefulWidget {
  const ThemeImportPreviewScreen({super.key, required this.text, required this.result});

  /// 原文（加入时交给主题库再检查一遍、落盘）。
  final String text;

  /// 已经检查通过的结果。
  final ThemeDecodeResult result;

  @override
  ConsumerState<ThemeImportPreviewScreen> createState() => _ThemeImportPreviewScreenState();
}

class _ThemeImportPreviewScreenState extends ConsumerState<ThemeImportPreviewScreen> {
  ThemePreviewKind _kind = ThemePreviewKind.ui;
  bool _useImage = true;
  bool _busy = false;
  bool _showAllIssues = false;

  /// 文件里 `background` 那一节的原样（交给背景图那部分用）。
  Map<String, Object?>? _rawBackground() {
    try {
      final json = jsonDecode(widget.text);
      final bg = json is Map ? json['background'] : null;
      return bg is Map ? {for (final e in bg.entries) '${e.key}': e.value} : null;
    } on FormatException {
      return null;
    }
  }

  Future<void> _add({required bool use}) async {
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    final themes = ref.read(themesProvider.notifier);
    final bridge = ref.read(themeBackgroundBridgeProvider);
    setState(() => _busy = true);
    final r = await themes.importText(widget.text);
    final added = r.theme;
    if (added == null) {
      if (!mounted) return;
      setState(() => _busy = false);
      messenger.showSnackBar(SnackBar(content: Text(r.error ?? '没加进来。')));
      return;
    }
    final said = <String>['已加入“${added.name}”${added.name == widget.result.theme!.name ? '' : '（已经有同名的，自动改了名）'}。'];
    if (use) {
      final failed = await themes.select(added.id);
      said.add(failed ?? '已经换上了。');
    }
    final raw = widget.result.background == null ? null : _rawBackground();
    if (bridge != null && raw != null && _useImage) {
      String? failed;
      try {
        failed = await bridge.import(raw);
      } on Exception catch (e) {
        failed = '$e';
      }
      said.add(failed == null ? '背景图也用上了。' : '背景图没用上：$failed');
    }
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(said.join(' '))));
    if (mounted) nav.pop(added);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final theme = widget.result.theme!;
    final issues = checkThemeContrast(theme);
    final notes = widget.result.notes;
    final hasImage = widget.result.background != null;
    final bridge = ref.watch(themeBackgroundBridgeProvider);
    final shown = _showAllIssues ? issues : issues.take(3).toList();

    Widget section(String title, List<Widget> children) => Padding(
      padding: const EdgeInsets.only(top: Space.x4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title, style: t.labelMedium?.copyWith(color: c.textFaint)),
          const SizedBox(height: Space.x1),
          ...children,
        ],
      ),
    );
    Widget line(IconData icon, Color color, String text, {Key? key}) => Padding(
      padding: const EdgeInsets.only(top: Space.x1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, size: 16, color: color),
          ),
          const SizedBox(width: Space.x2),
          Expanded(
            child: Text(
              text,
              key: key,
              style: t.bodySmall?.copyWith(color: c.textMuted),
            ),
          ),
        ],
      ),
    );

    return Scaffold(
      backgroundColor: c.canvas,
      extendBodyBehindAppBar: true,
      appBar: PageBar(background: c.canvas, titleText: '导入预览'),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Space.x4, Space.x2, Space.x4, Space.x2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FilledButton(key: const Key('theme-import-use'), onPressed: _busy ? null : () => _add(use: true), child: const Text('加入并立即使用')),
              const SizedBox(height: Space.x2),
              OutlinedButton(key: const Key('theme-import-add'), onPressed: _busy ? null : () => _add(use: false), child: const Text('加入我的主题')),
              TextButton(key: const Key('theme-import-cancel'), onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('取消')),
            ],
          ),
        ),
      ),
      body: SingleChildScrollView(
        key: const Key('theme-import-preview-scroll'),
        padding: EdgeInsets.fromLTRB(Space.x4, PageBar.insetOf(context) + Space.x2, Space.x4, Space.x6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(theme.name, key: const Key('theme-import-name'), style: t.titleLarge, maxLines: 2, overflow: TextOverflow.ellipsis),
            const SizedBox(height: Space.x1),
            Text(
              '${theme.author == null || theme.author!.isEmpty ? '没写作者' : '作者 ${theme.author}'} · ${theme.dark ? '深色主题' : '浅色主题'}',
              key: const Key('theme-import-meta'),
              style: t.bodyMedium?.copyWith(color: c.textMuted),
            ),
            const SizedBox(height: Space.x3),
            ClipRRect(
              borderRadius: BorderRadius.circular(Radii.md),
              child: DecoratedBox(
                position: DecorationPosition.foreground,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(Radii.md),
                  border: Border.all(color: c.border),
                ),
                child: SizedBox(
                  height: kThemePreviewHeight,
                  child: ThemePreview(spec: theme, kind: _kind),
                ),
              ),
            ),
            const SizedBox(height: Space.x2),
            SegmentedButton<ThemePreviewKind>(
              key: const Key('theme-import-kind'),
              showSelectedIcon: false,
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
              segments: [for (final k in ThemePreviewKind.values) ButtonSegment(value: k, label: Text(k.label))],
              selected: {_kind},
              onSelectionChanged: (s) => setState(() => _kind = s.first),
            ),
            section('对比度检查', [
              if (issues.isEmpty)
                line(Icons.check_circle_outline, c.success, '字和底的对比度都达标。', key: const Key('theme-import-contrast'))
              else ...[
                line(Icons.warning_amber_rounded, c.warning, '${issues.length} 项对比度偏低（字和底太接近，看着会费劲）。照样可以加入，加进来以后能在编辑器里改。', key: const Key('theme-import-contrast')),
                for (final i in shown) line(Icons.remove, c.textFaint, i.message),
                if (issues.length > 3)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      key: const Key('theme-import-issues-more'),
                      onPressed: () => setState(() => _showAllIssues = !_showAllIssues),
                      child: Text(_showAllIssues ? '收起' : '看全部 ${issues.length} 项'),
                    ),
                  ),
              ],
            ]),
            section('检查时的提示', [
              if (notes.isEmpty)
                line(Icons.check_circle_outline, c.success, '文件完整，没有要提醒的。', key: const Key('theme-import-notes'))
              else
                for (final (i, n) in notes.indexed) line(Icons.info_outline, c.info, n, key: Key('theme-import-note-$i')),
            ]),
            section('背景图', [
              if (!hasImage)
                line(Icons.image_not_supported_outlined, c.textFaint, '这个主题没带背景图。', key: const Key('theme-import-image'))
              else if (bridge == null)
                line(Icons.image_outlined, c.textFaint, '这个主题带了一张背景图，但这个版本还用不了背景图，只会加入颜色。', key: const Key('theme-import-image'))
              else
                CheckboxListTile(
                  key: const Key('theme-import-image-use'),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: const Text('同时使用附带的背景图'),
                  subtitle: const Text('会换掉现在的背景图'),
                  value: _useImage,
                  onChanged: _busy ? null : (v) => setState(() => _useImage = v ?? false),
                ),
            ]),
          ],
        ),
      ),
    );
  }
}
