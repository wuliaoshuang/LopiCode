// 设计约束（后端积木·“积木库”面板 + 一个库的面板，390 宽，浅色 + 深色）— 2026-11-27
// - 内容排序：主＝库的列表（一个一行：名字在左，右边小字说几块积木、用没用上）；
//   次＝“新建库”“从文件导入”（强调色文字行——这里没有唯一的主操作）；应用自带的库排在最后，标“自带”。
// - 一个库的面板：最上面一行开关“在这份文档里用它”（主操作）；下面依次是设置项（一项一行，点开改）、
//   积木清单（一块一行，只看）、更多（在画布上改 / 导出成文件 / 复制一份来改 / 从项目里拿掉，一行一件事；拿掉用危险色）。
// - 空状态：项目里一个库都没有时一句话说明库是什么、怎么来，不出现空列表。
// - 颜色全取主题值；间距只用 Space 里的档。读写磁盘的事都交给 lib/backend/backend_lib_store.dart。
import 'dart:async';

import 'package:lopicode/backend/backend_block_host.dart';
import 'package:lopicode/backend/backend_lib_doc.dart';
import 'package:lopicode/backend/backend_lib_pack.dart';
import 'package:lopicode/backend/backend_lib_store.dart';
import 'package:lopicode/backend/backend_lib_table.dart';
import 'package:lopicode/backend/backend_model.dart';
import 'package:lopicode/backend/lib_native_trust.dart';
import 'package:lopicode/backend/lib_service.dart';
import 'package:lopicode/backend/lib_service_fork.dart';
import 'package:lopicode/core/path_guard.dart';
import 'package:lopicode/lang/lib_model.dart';
import 'package:lopicode/lang/rules.dart';
import 'package:lopicode/lowcode/lib_page.dart' show kLcPageLibId, lcPageLibrary;
import 'package:lopicode/project_session.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/backend_core_sheet.dart';
import 'package:lopicode/ui/backend_lib_import_sheet.dart';
import 'package:lopicode/ui/backend_lib_info_sheet.dart';
import 'package:lopicode/ui/backend_lib_more_sheet.dart';
import 'package:lopicode/ui/backend_screen.dart';
import 'package:lopicode/ui/widgets.dart';
import 'package:material_ui/material_ui.dart';

/// “积木库”面板。`open`＝在后端积木页里打开某个库的画布原件（相对路径）。
Future<void> showBeLibs(BuildContext context, ProjectSession session, BeBlockHost host, {required void Function(String rel) open}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  builder: (_) => _LibsSheet(session: session, host: host, open: open),
);

/// 后端积木页“更多”菜单里和库有关的几项：所有文档有“积木库…”；库文档多一项“这个库…”。
List<PopupMenuEntry<String>> beLibMenuItems(BeBlockHost host, Widget Function(IconData icon, String text) row) => [
  if (host.doc.library != null) PopupMenuItem(key: const ValueKey('be-menu-lib-info'), value: 'lib-info', child: row(Icons.extension_outlined, '这个库（公开了 ${host.doc.library!.blocks.length} 块积木）…')),
  if (host.strictRules) PopupMenuItem(key: const ValueKey('be-menu-libs'), value: 'libs', child: row(Icons.widgets_outlined, '积木库（用了 ${host.doc.uses.where((u) => u.id != kLcPageLibId).length} 个）…')),
];

void beLibOnMenu(BuildContext context, ProjectSession session, BeBlockHost host, String value) {
  if (value == 'lib-info') unawaited(showBeLibInfo(context, host));
  if (value == 'libs') unawaited(showBeLibs(context, session, host, open: (rel) => openBackendBlocks(context, session, rel)));
}

/// 刚读到的文档：把项目里的库交给它。
Future<void> beLibAttach(PathGuard guard, BeDocument doc) => beLibsAttach(guard, doc);

/// 项目里的库可能在别处变了（存了库、导入了、拿掉了）：重新交给这份文档，积木盒和标红跟着变。
Future<void> beLibRefresh(PathGuard guard, BeBlockHost? host) async {
  if (host == null) return;
  await beLibsAttach(guard, host.doc);
  host.canvasChanged();
}

/// 问“标识”和“名字”：新建库、复制一份来改都用。取消返回 null。
Future<({String id, String name})?> askBeLibName(BuildContext context, {required String title, String id = '', String name = ''}) async {
  final n = await promptDialog(context, title: '$title：叫什么名字', initial: name, hint: '给人看的名字，比如 待办');
  if (n == null || n.trim().isEmpty || !context.mounted) return null;
  final i = await promptDialog(context, title: '$title：标识', initial: id, hint: '作者段/库名，小写字母、数字、连字符，比如 shuang/todo');
  if (i == null || i.trim().isEmpty) return null;
  return (id: i.trim(), name: n.trim());
}

class _LibsSheet extends StatefulWidget {
  const _LibsSheet({required this.session, required this.host, required this.open});
  final ProjectSession session;
  final BeBlockHost host;
  final void Function(String rel) open;

  @override
  State<_LibsSheet> createState() => _LibsSheetState();
}

class _LibsSheetState extends State<_LibsSheet> {
  List<BeStoredLib>? _libs;
  String? _problem;
  BeBlockHost get host => widget.host;
  PathGuard get guard => widget.session.guard;

  @override
  void initState() {
    super.initState();
    unawaited(_reload());
  }

  /// 重新读项目里的库，并把它们交给这份文档（积木盒、校验马上认）。
  Future<void> _reload() async {
    final all = await beLibsAttach(guard, host.doc);
    host.canvasChanged();
    if (mounted) setState(() => _libs = all);
  }

  Future<void> _guarded(Future<String?> Function() job) async {
    String? bad;
    try {
      bad = await job();
    } on PathGuardException catch (e) {
      bad = e.message;
    } on Exception catch (e) {
      bad = '文件操作没做成：$e';
    }
    widget.session.filesChanged();
    await _reload();
    if (mounted) setState(() => _problem = bad);
  }

  Future<void> _create() async {
    final got = await askBeLibName(context, title: '新建库');
    if (got == null || !mounted) return;
    final side = await askBeLibSide(context, initial: host.doc.libSide);
    if (side == null || !mounted) return;
    String? rel;
    await _guarded(() async {
      final made = await beLibCreate(guard, id: got.id, name: got.name, side: side);
      rel = made.rel;
      return made.problem;
    });
    if (rel != null && mounted) {
      Navigator.pop(context);
      widget.open(rel!);
    }
  }

  Future<void> _import() async {
    final files = await beLibPackFiles(guard);
    if (!mounted) return;
    if (files.isEmpty) {
      return setState(() => _problem = '工作区里没有找到库的导出文件（.lopilib）。把文件放到工作区根目录或 exports/ 里再来。');
    }
    final rel = files.length == 1
        ? files.single
        : await showDialog<String>(
            context: context,
            builder: (dialog) => SimpleDialog(
              title: const Text('导入哪个文件'),
              children: [for (final f in files) SimpleDialogOption(key: ValueKey('be-lib-file-$f'), onPressed: () => Navigator.pop(dialog, f), child: Text(f))],
            ),
          );
    if (rel == null || !mounted) return;
    final opened = await beLibOpenPack(guard, rel);
    if (!mounted) return;
    final preview = opened.preview;
    if (preview == null) return setState(() => _problem = '$rel 导不进来：${opened.problem}');
    final existing = _libs?.where((s) => s.id == preview.id).firstOrNull;
    final go = await showBeLibImport(context, preview, file: rel, existing: existing?.lib);
    if (!go || !mounted) return;
    String? note;
    await _guarded(() async {
      // 带手写代码的库：预览页的主按钮只有勾了“我看过这些代码了”才点得动，所以走到这里就是勾过了。
      final saved = await beLibInstall(guard, preview, replace: existing != null, nativeConfirmed: preview.hasNative);
      note = saved.freshNote;
      return saved.problems.firstOrNull;
    });
    if (note != null && mounted) setState(() => _problem = note);
  }

  /// 把自带的“接口服务”复制一份来改：问名字和标识，复制进项目，然后打开新库的面板。
  Future<void> _forkService() async {
    if (!mounted) return;
    final got = await askBeLibName(context, title: '复制一份来改', name: '我的接口服务', id: '');
    if (got == null || !mounted) return;
    String? made;
    await _guarded(() async {
      final out = await beServiceFork(guard, id: got.id, name: got.name);
      made = out.id;
      return out.problem;
    });
    final s = _libs?.where((x) => x.id == made).firstOrNull;
    if (s != null && mounted) await _openLib(s);
  }

  Future<void> _openLib(BeStoredLib s) async {
    final rel = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _LibSheet(session: widget.session, host: host, stored: s),
    );
    await _reload();
    if (rel != null && mounted) {
      Navigator.pop(context);
      widget.open(rel);
    }
  }

  @override
  Widget build(BuildContext context) {
    final libs = _libs;
    final doc = host.doc;
    final service = beServiceLibrary();
    final page = lcPageLibrary();
    final mine = [
      for (final s in libs ?? const <BeStoredLib>[])
        if (s.id != doc.library?.id) s,
    ];
    return BeSheetFrame(
      key: const ValueKey('be-libs'),
      title: '积木库',
      hint: !host.strictRules ? '库要“严格规矩”的文档才能用。先在“更多”里升级到严格规矩。' : (mine.isEmpty ? '库＝别人（或你自己）用积木写好的一组积木。用上以后，它的积木会出现在积木盒里。可以新建一个自己写，也可以把别人导出的文件导进来。' : null),
      problem: _problem,
      children: [
        if (libs == null) const BeSheetRow(label: '正在读项目里的库…', muted: true),
        if (mine.isNotEmpty) const BeSheetSection('项目里的库'),
        for (final s in mine)
          BeSheetRow(key: ValueKey('be-lib-${s.id}'), label: s.name, value: !s.ok ? '有问题' : '${s.lib.blocks.length} 块积木${doc.use(s.id) != null ? ' · 用上了' : ''}', onTap: () => unawaited(_openLib(s))),
        if (host.strictRules) BeSheetAdd(key: const ValueKey('be-lib-new'), label: '新建库', onTap: () => unawaited(_create())),
        if (host.strictRules) BeSheetAdd(key: const ValueKey('be-lib-import'), label: '从文件导入', onTap: () => unawaited(_import())),
        const BeSheetSection('应用自带'),
        // 自带的两个库都列出来；这份文档这一边用不了的那个是灰的，下面一行写原因（点开也看得到）。
        for (final b in [if (doc.isFront) page, service, if (!doc.isFront) page]) ...[
          BeSheetRow(
            key: ValueKey(b.id == kLcPageLibId ? 'be-lib-builtin-page' : 'be-lib-builtin'),
            label: b.name,
            value: b.sideProblem(doc.libSide) != null ? '这里用不了' : '${b.blocks.length} 块积木 · 自带${b.id == kLcPageLibId ? ' · 用着' : ''}',
            muted: b.sideProblem(doc.libSide) != null,
            onTap: () => unawaited(b.id == kLcPageLibId ? showBePageLib(context, b, why: b.sideProblem(doc.libSide)) : showBeServiceLib(context, fork: _forkService, why: b.sideProblem(doc.libSide))),
          ),
          if (b.sideProblem(doc.libSide) case final why?)
            Padding(
              key: ValueKey(b.id == kLcPageLibId ? 'be-lib-builtin-page-why' : 'be-lib-builtin-why'),
              padding: const EdgeInsets.fromLTRB(Space.x4, 0, Space.x4, Space.x2),
              // 清单里只说一句短的；完整的原因点开以后在面板顶上。
              child: Text(why.isEmpty ? '' : (b.id == kLcPageLibId ? '只在页面逻辑和前端的库里用得上' : '只在后端的积木里用得上'), style: Theme.of(context).textTheme.bodySmall?.copyWith(color: context.colors.textMuted)),
            ),
        ],
      ],
    );
  }
}

/// 一个库的面板。返回值＝要去画布上打开的文件（“在画布上改”“复制一份来改”）；别的情况返回 null。
class _LibSheet extends StatefulWidget {
  const _LibSheet({required this.session, required this.host, required this.stored});
  final ProjectSession session;
  final BeBlockHost host;
  final BeStoredLib stored;

  @override
  State<_LibSheet> createState() => _LibSheetState();
}

class _LibSheetState extends State<_LibSheet> {
  String? _problem;
  String? _note;
  BeBlockHost get host => widget.host;
  BeStoredLib get s => widget.stored;
  LibLibrary get lib => s.lib;
  PathGuard get guard => widget.session.guard;

  void _toggle(bool on) {
    final doc = host.doc;
    if (on) {
      if (doc.uses.length >= kBeMaxLibUses) return setState(() => _problem = '一份文档最多用 $kBeMaxLibUses 个库。');
      host.edit(() => doc.uses.add(BeLibUse(s.id)));
      return setState(() => _problem = null);
    }
    final n = BeLibTable(doc).usesOfLib(s.id);
    if (n > 0) return setState(() => _problem = '这份文档里还有 $n 处在用它的积木。先把那些积木删掉，再关。');
    host.edit(() => doc.uses.removeWhere((u) => u.id == s.id));
    setState(() => _problem = null);
  }

  Future<void> _setting(LibSetting st) async {
    final use = host.doc.use(s.id);
    if (use == null) return;
    final now = use.settings[st.id] ?? st.defaultValue;
    final raw = await promptDialog(context, title: st.name, initial: now == null ? '' : '$now', hint: st.hint.isEmpty ? '不填＝用库里写的（${st.defaultValue ?? '空'}）' : st.hint);
    if (raw == null || !mounted) return;
    final text = raw.trim();
    Object? value;
    if (text.isEmpty) {
      value = null;
    } else if (st.defaultValue is num) {
      final n = num.tryParse(text);
      if (n == null) return setState(() => _problem = '「${st.name}」要填一个数。');
      if ((st.min != null && n < st.min!) || (st.max != null && n > st.max!)) return setState(() => _problem = '「${st.name}」要在 ${st.min ?? '不限'} 到 ${st.max ?? '不限'} 之间。');
      value = st.defaultValue is int ? n.toInt() : n;
    } else if (st.defaultValue is bool) {
      if (text != '是' && text != '否') return setState(() => _problem = '「${st.name}」填 是 或 否。');
      value = text == '是';
    } else {
      value = text;
    }
    host.edit(() => value == null ? use.settings.remove(st.id) : use.settings[st.id] = value);
    setState(() => _problem = null);
  }

  Future<void> _export() async {
    try {
      final out = await beLibExport(guard, s.id);
      widget.session.filesChanged();
      if (!mounted) return;
      setState(() {
        _problem = out.problem;
        _note = out.rel == null ? null : '已导出到 ${out.rel}（在“文件”页里能看到，可以发给别人）。';
      });
    } on Exception catch (e) {
      if (mounted) setState(() => _problem = '没导出成：$e');
    }
  }

  Future<void> _fork() async {
    final got = await askBeLibName(context, title: '复制一份来改', name: '${s.name}二', id: '${s.id}2');
    if (got == null || !mounted) return;
    try {
      final made = await beLibFork(guard, s.id, id: got.id, name: got.name);
      widget.session.filesChanged();
      if (!mounted) return;
      if (made.rel == null) return setState(() => _problem = made.problem);
      // 问一次：这份文档里对原来那个库的用法，要不要换成新的。
      if (host.doc.use(s.id) != null) {
        final yes = await confirmDialog(context, title: '把这份文档里的用法换过去吗', message: '这份文档现在用的是「${s.name}」。换了以后，它的积木都改成用新复制出来的「${got.name}」；不换就还用原来的。', confirmLabel: '换过去');
        if (!mounted) return;
        if (yes) {
          await beLibsAttach(guard, host.doc);
          final switched = beLibSwitchUses(host.doc, s.id, got.id);
          if (switched != null) host.replaceDoc(switched.doc);
          host.onEdited?.call();
        }
      }
      if (mounted) Navigator.pop(context, made.rel);
    } on Exception catch (e) {
      if (mounted) setState(() => _problem = '没复制成：$e');
    }
  }

  /// 看手写代码并确认：确认了就关掉这一页（外面会重新读库，它就能用了）。
  Future<void> _confirmNative() async {
    final ok = await confirmBeLibNative(context, guard, s, others: host.doc.loaded);
    if (ok && mounted) Navigator.pop(context);
  }

  Future<void> _editText() async {
    final changed = await showBeLibText(context, widget.session, s);
    if (changed && mounted) Navigator.pop(context);
  }

  Future<void> _remove() async {
    final n = BeLibTable(host.doc).usesOfLib(s.id);
    final yes = await confirmDialog(
      context,
      title: '把「${s.name}」从项目里拿掉吗',
      message: n > 0 ? '这份文档里还有 $n 处在用它的积木，拿掉以后那些积木会标红。库的文件夹（blocks/${s.id}/）会整个删掉。' : '库的文件夹（blocks/${s.id}/）会整个删掉。别的文档要是还在用它，会标红。',
      confirmLabel: '拿掉',
      danger: true,
    );
    if (!yes || !mounted) return;
    try {
      await beLibDelete(guard, s.id);
      await LibNativeTrust.instance.forget(guard.root, s.id);
      if (host.doc.serviceLib == s.id) host.edit(() => host.doc.serviceLib = '');
      widget.session.filesChanged();
      if (mounted) Navigator.pop(context);
    } on Exception catch (e) {
      if (mounted) setState(() => _problem = '没拿掉：$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final use = host.doc.use(s.id);
    final sideWhy = lib.sideProblem(host.doc.libSide);
    final hasNative = s.files.keys.any((f) => f.startsWith('native/'));
    final from = switch (s.from) {
      'file' => '从文件导入的',
      'copy' => '复制来改的',
      _ => '在这个项目里写的',
    };
    return BeSheetFrame(
      key: ValueKey('be-lib-sheet-${s.id}'),
      title: s.name,
      hint: '${s.id} · 版本 ${lib.version}${lib.author.isEmpty ? '' : ' · 作者 ${lib.author}'} · $from · 给${lib.side.label}用${lib.summary.isEmpty ? '' : '\n${lib.summary}'}',
      problem: _problem ?? (s.ok ? null : '这个库现在用不了：${s.problem}'),
      children: [
        if (_note != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.x4, 0, Space.x4, Space.x2),
            child: Text(
              _note!,
              key: const ValueKey('be-lib-note'),
              style: t.bodyMedium?.copyWith(color: c.textMuted),
            ),
          ),
        if (s.ok && host.strictRules && lib.replaces == kBeServiceLibId)
          SwitchListTile(
            key: const ValueKey('be-lib-replace'),
            contentPadding: const EdgeInsets.symmetric(horizontal: Space.x4),
            title: const Text('用它顶替自带的“接口服务”'),
            subtitle: Text(host.doc.serviceLib == s.id ? '这份文档的接口、返回、数据集合这些积木现在都走它' : '打开以后，这份文档的接口、返回、数据集合这些积木都走它（积木的样子不变）'),
            value: host.doc.serviceLib == s.id,
            onChanged: (on) {
              host.edit(() => host.doc.serviceLib = on ? s.id : '');
              setState(() => _problem = null);
            },
          )
        else if (s.ok && host.strictRules)
          SwitchListTile(
            key: const ValueKey('be-lib-use'),
            contentPadding: const EdgeInsets.symmetric(horizontal: Space.x4),
            title: const Text('在这份文档里用它'),
            subtitle: Text(sideWhy ?? (use != null ? '它的积木在积木盒的「${s.name}」那一页' : '打开以后，它的积木会出现在积木盒里')),
            value: use != null,
            // 给谁用对不上：灰掉，原因写在下面那行小字里。已经用上的还许关。
            onChanged: sideWhy != null && use == null ? null : _toggle,
          ),
        // 没有画布原样的库（复制自带库得到的、别人给的文字写法的库）：改它就是改文字，入口放在最上面，不埋在积木清单底下。
        if (!s.hasSource) BeSheetAdd(key: const ValueKey('be-lib-text-open'), label: '改库的文字（清单、模块、积木表）', onTap: () => unawaited(_editText())),
        if (!s.ok && hasNative)
          BeSheetAdd(
            key: const ValueKey('be-lib-native-confirm'),
            label: LibNativeTrust.instance.enabled ? '看手写代码并确认' : (libNativeCodeEntry ? '看手写代码（“允许库里的手写代码”关着，确认不了）' : '看手写代码'),
            onTap: () => unawaited(_confirmNative()),
          ),
        if (use != null && lib.settings.isNotEmpty) const BeSheetSection('设置项（只管这份文档）'),
        if (use != null)
          for (final st in lib.settings)
            BeSheetRow(key: ValueKey('be-lib-setting-${st.id}'), label: st.name, value: '${use.settings[st.id] ?? st.defaultValue ?? '空'}', onTap: () => unawaited(_setting(st))),
        if (lib.hosts.isNotEmpty) const BeSheetSection('它直接用的宿主能力'),
        for (final h in lib.hosts) BeSheetRow(label: beHostWord(h), muted: true),
        if (lib.natives.isNotEmpty) BeSheetSection('手写函数（${lib.natives.length} 个，已经确认过）'),
        for (final n in lib.natives) BeSheetRow(label: n.name, value: n.waits ? '要等' : '不用等', muted: true),
        if (lib.requires.isNotEmpty) const BeSheetSection('它要靠的库'),
        for (final r in lib.requires) BeSheetRow(label: r == kBeServiceLibId ? '接口服务（应用自带）' : r, muted: true),
        BeSheetSection('积木（${lib.blocks.length} 块）'),
        for (final b in lib.blocks) BeSheetRow(label: beLibBlockLine(b), muted: true),
        const BeSheetSection('更多'),
        if (s.hasSource) BeSheetRow(key: const ValueKey('be-lib-edit'), label: '在画布上改', onTap: () => Navigator.pop(context, s.sourceRel)),
        if (s.ok) BeSheetRow(key: const ValueKey('be-lib-export'), label: '导出成一个文件', onTap: () => unawaited(_export())),
        s.hasSource
            ? BeSheetRow(key: const ValueKey('be-lib-fork'), label: '复制一份来改', onTap: () => unawaited(_fork()))
            : const BeSheetRow(key: ValueKey('be-lib-no-fork'), label: '这个库没带画布上的原样，不能复制来改', muted: true),
        InkWell(
          key: const ValueKey('be-lib-remove'),
          onTap: () => unawaited(_remove()),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.x4, vertical: Space.x3),
            child: Text('从项目里拿掉', style: t.bodyLarge?.copyWith(color: c.danger)),
          ),
        ),
      ],
    );
  }
}
