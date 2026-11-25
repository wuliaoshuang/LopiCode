// 设计约束（导出一套主题 · 底部面板 · 390×844）— 2026-11-26
// - 从上到下一行一件事：标题“导出〈名字〉”→ 一句说明（这是一段文本，发给别人，对方在“导入主题”里粘贴或选文件）
//   → 大小 → “附带背景图”开关（**只有背景图那部分接上了、而且现在设了背景图才出现**）
//   → 复制到剪贴板 → 存成文件（存到工作区的 exports/ 里）→ 存好以后显示存在哪。
// - 不调系统分享面板、不联网。文件名：exports/主题-〈名字〉-日期-时间.lopitheme.json。
// - 存文件要有工作区：现在开着工作区就存它里面；没开着就从工作区列表里挑一个；一个工作区都没有时只能复制，并说明原因。
// - 带上背景图以后超过导入能收的上限（12MB）就不带，并说明。
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lopicode/appearance/theme_export_file.dart';
import 'package:lopicode/appearance/theme_json.dart';
import 'package:lopicode/core/path_guard.dart';
import 'package:lopicode/project_session.dart';
import 'package:lopicode/state/theme_hooks.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/app_ref.dart';
import 'package:material_ui/material_ui.dart';

/// 导出 / 导入用到的“一个工作区”：往哪写、叫什么、写完通知谁。
class ThemeWorkspace {
  const ThemeWorkspace(this.guard, this.name, {this.changed});
  final PathGuard guard;
  final String name;

  /// 写了文件以后叫一声（让“文件”页刷新）；没开着的工作区不用。
  final VoidCallback? changed;
}

/// 找一个工作区：开着的优先；否则从列表里挑（只有一个就直接用）。一个都没有返回 null。
Future<ThemeWorkspace?> pickThemeWorkspace(BuildContext context, ProjectSession? session, {required String title}) async {
  if (session != null) return ThemeWorkspace(session.guard, session.project.name, changed: session.filesChanged);
  final projects = await appOf(context).projects.list();
  if (projects.isEmpty || !context.mounted) return null;
  if (projects.length == 1) return ThemeWorkspace(projects.first.guard, projects.first.name);
  return showModalBottomSheet<ThemeWorkspace>(
    context: context,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.7),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.x4, 0, Space.x4, Space.x2),
              child: Text(title, style: Theme.of(context).textTheme.titleMedium),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final p in projects)
                    ListTile(
                      key: Key('theme-ws-${p.id}'),
                      leading: const Icon(Icons.folder_outlined),
                      title: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(p.displayDir, maxLines: 1, overflow: TextOverflow.ellipsis),
                      onTap: () => Navigator.pop(context, ThemeWorkspace(p.guard, p.name)),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

Future<void> showThemeExportSheet(BuildContext context, {required ThemeSpec theme, ProjectSession? session}) =>
    showModalBottomSheet<void>(context: context, isScrollControlled: true, builder: (_) => ThemeExportSheet(theme: theme, session: session));

class ThemeExportSheet extends ConsumerStatefulWidget {
  const ThemeExportSheet({super.key, required this.theme, this.session});
  final ThemeSpec theme;
  final ProjectSession? session;

  @override
  ConsumerState<ThemeExportSheet> createState() => _ThemeExportSheetState();
}

class _ThemeExportSheetState extends ConsumerState<ThemeExportSheet> {
  late final Map<String, Object?> _json = encodeTheme(widget.theme.copyWith(builtin: false));
  late String _text = _encode(_json);
  bool _withImage = false;
  bool _busy = false;

  /// 最近一次操作的结果（“已复制”“存在哪”“为什么没带图”）。
  String? _note;
  bool _noteBad = false;

  static String _encode(Map<String, Object?> json) => const JsonEncoder.withIndent('  ').convert(json);

  void _tell(String text, {bool bad = false}) => setState(() {
    _note = text;
    _noteBad = bad;
  });

  Future<void> _toggleImage(bool on, ThemeBackgroundBridge bridge) async {
    if (!on) {
      return setState(() {
        _withImage = false;
        _text = _encode(_json);
        _note = null;
      });
    }
    setState(() => _busy = true);
    ThemeBackgroundExport got;
    try {
      got = await bridge.export();
    } on Exception catch (e) {
      got = ThemeBackgroundExport(error: '背景图取不出来：$e');
    }
    if (!mounted) return;
    final data = got.data;
    String? text;
    String? why = got.error;
    if (data != null) {
      text = _encode({..._json, 'background': data});
      if (themeTextBytes(text) > kThemeImportMaxBytes) {
        text = null;
        why = '带上背景图以后有 ${formatThemeBytes(themeTextBytes(_encode({..._json, 'background': data})))}，超过了导入能收的 ${formatThemeBytes(kThemeImportMaxBytes)}，所以没带。可以先把背景图换成小一点的。';
      }
    }
    setState(() {
      _busy = false;
      _withImage = text != null;
      _text = text ?? _encode(_json);
      _note = text == null ? (why ?? '背景图带不上。') : (got.notes.isEmpty ? null : got.notes.join('\n'));
      _noteBad = text == null;
    });
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _text));
    if (mounted) _tell('已复制到剪贴板（${formatThemeBytes(themeTextBytes(_text))}）。发给对方，对方在“导入主题”里粘贴。');
  }

  Future<void> _save() async {
    final ws = await pickThemeWorkspace(context, widget.session, title: '存到哪个工作区？');
    if (!mounted) return;
    if (ws == null) return _tell('现在一个工作区都没有，没地方存文件。先用上面的“复制到剪贴板”，或者先建一个工作区。', bad: true);
    setState(() => _busy = true);
    try {
      final path = await writeThemeExport(ws.guard, _text, name: widget.theme.name);
      ws.changed?.call();
      if (mounted) _tell('已存到工作区“${ws.name}”的 $path（${formatThemeBytes(themeTextBytes(_text))}）。在“文件”页能看到。');
    } on Exception catch (e) {
      if (mounted) _tell('没存成：$e', bad: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final bridge = ref.watch(themeBackgroundBridgeProvider);
    final canImage = bridge != null && bridge.hasImage();
    Widget row(String id, IconData icon, String title, String subtitle, VoidCallback onTap) => ListTile(
      key: Key('theme-export-$id'),
      enabled: !_busy,
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      onTap: onTap,
    );
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.x4, 0, Space.x4, Space.x1),
              child: Text('导出“${widget.theme.name}”', style: t.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.x4, 0, Space.x4, Space.x2),
              child: Text('导出的是一段文本（只有颜色和数值，没有任何会运行的东西）。发给别人，对方在“管理主题 › 导入主题”里粘贴或选文件就能用。', style: t.bodySmall?.copyWith(color: c.textMuted)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.x4, 0, Space.x4, Space.x2),
              child: Text('大小：${formatThemeBytes(themeTextBytes(_text))}', key: const Key('theme-export-size'), style: t.bodyMedium),
            ),
            if (canImage)
              SwitchListTile(
                key: const Key('theme-export-with-image'),
                title: const Text('附带背景图'),
                subtitle: const Text('把现在的背景图一起放进去，文件会大很多'),
                value: _withImage,
                onChanged: _busy ? null : (v) => _toggleImage(v, bridge),
              ),
            row('copy', Icons.content_copy_outlined, '复制到剪贴板', '粘贴到聊天软件里发给别人', _copy),
            row('save', Icons.save_alt, '存成文件', '存到工作区的 exports/ 里，在“文件”页能看到', _save),
            if (_note != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(Space.x4, Space.x2, Space.x4, Space.x3),
                child: Text(_note!, key: const Key('theme-export-note'), style: t.bodySmall?.copyWith(color: _noteBad ? c.danger : c.textMuted)),
              ),
            const SizedBox(height: Space.x2),
          ],
        ),
      ),
    );
  }
}
