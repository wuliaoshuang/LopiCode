// 设计约束（后端积木·库面板里多出来的几样，390 宽，浅色 + 深色）— 2026-11-27 第四轮
// - 自带库的面板：最上面说它是什么；“复制一份来改”是这一页唯一的操作（强调色文字行），下面是积木清单（只看）。
// - 新建库多一步“给谁用”：三选一，一行一个，每行下面一句小字说区别；默认是现在这份文档的那一边。
// - 改库的文字：先一页列出能改的文件（一行一个），点开是一整页的编辑框（等宽字、应用统一的代码字号）；
//   主操作是“存”，旁边一个“检查”（只查不存）；有问题时原因（带第几行）写在编辑框上面，文字不丢。
// - 确认手写代码：用公用的预览页（lib/ui/lib_import_sheet.dart），换了标题和按钮上的字。
// - 颜色全取主题值；读写磁盘的事都交给 lib/backend。
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lopicode/backend/backend_lib_build.dart';
import 'package:lopicode/backend/backend_lib_pack.dart';
import 'package:lopicode/backend/backend_lib_store.dart';
import 'package:lopicode/backend/lib_native_trust.dart';
import 'package:lopicode/backend/lib_service.dart';
import 'package:lopicode/backend/lib_service_fork.dart';
import 'package:lopicode/core/path_guard.dart';
import 'package:lopicode/lang/lib_model.dart';
import 'package:lopicode/lang/rules.dart';
import 'package:lopicode/project_session.dart';
import 'package:lopicode/state/code_font.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/backend_core_sheet.dart';
import 'package:lopicode/ui/backend_lib_import_sheet.dart';
import 'package:lopicode/ui/lib_import_sheet.dart';
import 'package:lopicode/ui/top_bar.dart';
import 'package:material_ui/material_ui.dart';

/// 新建库时问“给谁用”。取消返回 null。
Future<LibSide?> askBeLibSide(BuildContext context, {LibSide initial = LibSide.backend}) => showDialog<LibSide>(
  context: context,
  builder: (dialog) => SimpleDialog(
    key: const ValueKey('be-lib-side'),
    title: const Text('这个库给谁用'),
    children: [
      for (final (side, note) in const [(LibSide.backend, '后端的文档能用；可以用“接口服务”的积木'), (LibSide.frontend, '页面逻辑的文档能用；后端的文档里用不了'), (LibSide.both, '两边都能用；只能用语言基础的积木，不能碰接口、页面这些')])
        SimpleDialogOption(
          key: ValueKey('be-lib-side-${side.name}'),
          onPressed: () => Navigator.pop(dialog, side),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${side.label}${side == initial ? '（现在这份文档这一边）' : ''}', style: Theme.of(dialog).textTheme.bodyLarge),
              Text(note, style: Theme.of(dialog).textTheme.bodySmall?.copyWith(color: dialog.colors.textMuted)),
            ],
          ),
        ),
    ],
  ),
);

/// 自带的“接口服务”库的面板。`fork`＝点了“复制一份来改”（问名字、复制、刷新都由调用方做）。
Future<void> showBeServiceLib(BuildContext context, {required Future<void> Function() fork}) {
  final service = beServiceLibrary();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheet) => BeSheetFrame(
      key: const ValueKey('be-lib-builtin-sheet'),
      title: service.name,
      hint:
          '应用自带的库，只读。接口、请求、响应、数据集合这些积木都是它的；有接口的文档会自动用上它。\n'
          '它不是在画布上搭的，是直接用语言基础的文字写法写的，底下接着宿主的能力（${[for (final h in service.hosts) beHostWord(h)].join('、')}）。'
          '${userLibHostEntry ? '“复制一份来改”会得到同样的一份文字写法的库：可以改它的文字，再让文档用它顶替自带的这个。' : ''}',
      children: [
        // 复制件直接用宿主接口；那条路关着时（rules.dart 的 userLibHostEntry）复制出来必然用不了，所以只放一行灰字说明。
        if (userLibHostEntry)
          BeSheetAdd(
            key: const ValueKey('be-lib-builtin-fork'),
            label: '复制一份来改',
            onTap: () {
              Navigator.pop(sheet);
              unawaited(fork());
            },
          )
        else
          const BeSheetRow(key: ValueKey('be-lib-builtin-no-fork'), label: kServiceForkOffNote, muted: true),
        BeSheetSection('积木（${service.blocks.length} 块）'),
        for (final b in service.blocks) BeSheetRow(label: beLibBlockLine(b), muted: true),
      ],
    ),
  );
}

/// 已经在项目里的库：看它的手写代码并确认（或者重新确认）。确认了返回 true。
Future<bool> confirmBeLibNative(BuildContext context, PathGuard guard, BeStoredLib s, {List<LibLibrary> others = const []}) async {
  final preview = beLibPreview({
    for (final e in s.files.entries)
      if (e.key != kBeLibSourceFile) e.key: e.value,
  }, others: others);
  // 总开关关着（rules.dart 的 libNativeCodeEntry）：这一页只能看，按钮是灰的（预览里有“不能启用”那条问题）。
  final yes = libNativeCodeEntry
      ? await showLibImport(context, beLibImportView(preview), title: '确认手写代码', action: '我确认，可以用', hint: '「${s.name}」已经在项目里了，它带着手写代码。看过并确认以后才能用；以后它的手写代码或清单变了，要回到这里重新确认。')
      : await showLibImport(context, beLibImportView(preview), title: '看手写代码', action: '用不了', hint: '「${s.name}」已经在项目里了，它带着手写代码。$kLibNativeOffNote，这里只能看。');
  if (!yes) return false;
  return LibNativeTrust.instance.confirm(guard.root, s.id, libNativeSum(s.files));
}

/// 改库的文字：列出能改的文件，点开改。有改动存成了返回 true。
Future<bool> showBeLibText(BuildContext context, ProjectSession session, BeStoredLib s) async {
  var changed = false;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheet) => BeSheetFrame(
      key: const ValueKey('be-lib-text'),
      title: '改库的文字',
      hint: '「${s.name}」没有画布上的原样，它是用语言基础的文字写法写的。改哪个文件点哪个；存的时候会把整个库查一遍，查不过不存。',
      children: [
        for (final f in beLibTextFiles(s))
          BeSheetRow(
            key: ValueKey('be-lib-text-$f'),
            label: f,
            value: switch (f) {
              kLibManifestFile => '清单',
              'blocks.json' => '积木表',
              _ => '模块',
            },
            onTap: () async {
              final saved = await Navigator.of(sheet).push<bool>(
                MaterialPageRoute(
                  builder: (_) => _TextPage(session: session, id: s.id, rel: f, text: s.files[f] ?? ''),
                ),
              );
              if (saved == true) {
                changed = true;
                if (sheet.mounted) Navigator.pop(sheet);
              }
            },
          ),
      ],
    ),
  );
  return changed;
}

class _TextPage extends ConsumerStatefulWidget {
  const _TextPage({required this.session, required this.id, required this.rel, required this.text});
  final ProjectSession session;
  final String id;
  final String rel;
  final String text;

  @override
  ConsumerState<_TextPage> createState() => _TextPageState();
}

class _TextPageState extends ConsumerState<_TextPage> {
  late final TextEditingController _text = TextEditingController(text: widget.text);
  String? _problem;
  bool _fine = false;
  bool _busy = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  /// 只查不存。
  Future<void> _check() async {
    setState(() => _busy = true);
    String? bad;
    try {
      bad = await beLibCheckText(widget.session.guard, widget.id, widget.rel, _text.text);
    } on Exception catch (e) {
      bad = '没查成：$e';
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _problem = bad == null ? null : '有问题：$bad';
      _fine = bad == null;
    });
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    String? bad;
    try {
      bad = await beLibSaveText(widget.session.guard, widget.id, widget.rel, _text.text);
    } on Exception catch (e) {
      bad = '没存成：$e';
    }
    widget.session.filesChanged();
    if (!mounted) return;
    if (bad == null) return Navigator.pop(context, true);
    setState(() {
      _busy = false;
      _problem = '没有存：$bad';
      _fine = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      key: const ValueKey('be-lib-text-page'),
      backgroundColor: c.canvas,
      appBar: PageBar(
        background: c.canvas,
        titleText: widget.rel,
        actions: [
          TextButton(key: const ValueKey('be-lib-text-check'), onPressed: _busy ? null : () => unawaited(_check()), child: const Text('检查')),
          TextButton(key: const ValueKey('be-lib-text-save'), onPressed: _busy ? null : () => unawaited(_save()), child: const Text('存')),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_problem != null)
            Container(
              key: const ValueKey('be-lib-text-problem'),
              constraints: const BoxConstraints(maxHeight: 160),
              color: c.surfaceMuted,
              padding: const EdgeInsets.all(Space.x3),
              child: SingleChildScrollView(
                child: Text('$_problem', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: c.danger)),
              ),
            ),
          if (_fine && _problem == null)
            Container(
              key: const ValueKey('be-lib-text-fine'),
              color: c.surfaceMuted,
              padding: const EdgeInsets.all(Space.x3),
              child: Text('查过了，没有问题（还没存）。', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: c.textMuted)),
            ),
          Expanded(
            child: TextField(
              key: const ValueKey('be-lib-text-field'),
              onChanged: (_) {
                if (_fine) setState(() => _fine = false);
              },
              controller: _text,
              maxLines: null,
              expands: true,
              textAlignVertical: TextAlignVertical.top,
              autocorrect: false,
              enableSuggestions: false,
              style: TextStyle(fontFamily: kMonoFont, fontFamilyFallback: kMonoFallback, fontSize: ref.watch(compactCodeFontProvider), color: c.text, height: 1.4),
              decoration: const InputDecoration(border: InputBorder.none, enabledBorder: InputBorder.none, focusedBorder: InputBorder.none, filled: false, contentPadding: EdgeInsets.all(Space.x3)),
            ),
          ),
        ],
      ),
    );
  }
}
