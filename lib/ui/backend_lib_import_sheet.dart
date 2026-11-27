// 设计约束（后端积木·导入库之前的预览，390 宽，浅色 + 深色）— 2026-11-27
// - 这一页只回答一件事：“这个库是什么、导进来安不安全、要不要导”。主操作只有一个：底部的“导入”（不能导时是灰的，上面写着原因）。
// - 内容排序：主＝库名、标识、版本、作者（各一行）；次＝“要注意的”（它靠哪些库、要用到宿主的什么能力、带没带手写代码）；
//   三＝积木清单（一块一行，只看）。
// - 手写代码：这一版不会把它放进生成的工程，所以带手写代码的库如实列出文件、可以一个个点开看内容，但是不许导入。
// - 一行只做一件事；颜色全取主题值；代码用应用统一的代码字号。
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lopicode/backend/backend_lib_pack.dart';
import 'package:lopicode/lang/lib_model.dart';
import 'package:lopicode/state/code_font.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/backend_core_sheet.dart';
import 'package:material_ui/material_ui.dart';

/// 导入前的预览。返回 true＝用户点了“导入”。`existing`＝项目里已经有的同一个标识的库（有就是“盖掉”）。
Future<bool> showBeLibImport(BuildContext context, BeLibPreview preview, {required String file, LibLibrary? existing}) async =>
    await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ImportSheet(preview: preview, file: file, existing: existing),
    ) ??
    false;

class _ImportSheet extends StatelessWidget {
  const _ImportSheet({required this.preview, required this.file, this.existing});
  final BeLibPreview preview;
  final String file;
  final LibLibrary? existing;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final p = preview;
    return BeSheetFrame(
      key: const ValueKey('be-lib-import-sheet'),
      title: '导入库',
      hint: '来自 $file。导入只是把库的文件放进项目的 blocks/ 里，不会运行它里面的任何东西。',
      problem: p.canImport ? null : '这个库不能导入：${p.problems.join('；')}',
      footer: FilledButton(
        key: const ValueKey('be-lib-import-go'),
        onPressed: p.canImport ? () => Navigator.pop(context, true) : null,
        child: Text(existing == null ? '导入' : '导入，盖掉现在的版本 ${existing!.version}'),
      ),
      children: [
        BeSheetRow(label: '名字', value: p.name),
        BeSheetRow(label: '标识', value: p.id),
        BeSheetRow(label: '版本', value: p.version),
        BeSheetRow(label: '作者', value: p.author),
        if (p.lib.summary.isNotEmpty) BeSheetRow(label: '介绍', value: p.lib.summary),
        const BeSheetSection('要注意的'),
        if (p.needs.isEmpty && !p.hasNative) const BeSheetRow(label: '只用积木写的，不靠别的库，不带手写代码', muted: true),
        for (final n in p.needs) _Line(n),
        if (!p.hasSource) const _Line('没有带画布原件：能用，但是不能回到画布上改它'),
        if (p.hasNative) _Line('带了手写代码（${p.nativeFiles.length} 个文件）。这一版的应用不会把手写代码放进生成的工程里，所以这个库现在不能导入。可以点开看看它写了什么：', color: c.danger),
        for (final f in p.nativeFiles)
          BeSheetRow(
            key: ValueKey('be-lib-native-$f'),
            label: f,
            value: '看代码',
            onTap: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              builder: (_) => _CodeSheet(name: f, code: p.files[f] ?? ''),
            ),
          ),
        if (p.lib.nativeWaits.isNotEmpty) _Line('清单里说这些手写的函数“要等”：${p.lib.nativeWaits.join('、')}'),
        BeSheetSection('积木（${p.blocks.length} 块）'),
        for (final b in p.blocks) BeSheetRow(label: b, muted: true),
      ],
    );
  }
}

/// 一段可以换行的说明（“要注意的”里一条一段）。
class _Line extends StatelessWidget {
  const _Line(this.text, {this.color});
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: Space.x4, vertical: Space.x2),
    child: Text(text, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: color ?? context.colors.text)),
  );
}

class _CodeSheet extends ConsumerWidget {
  const _CodeSheet({required this.name, required this.code});
  final String name;
  final String code;

  @override
  Widget build(BuildContext context, WidgetRef ref) => BeSheetFrame(
    key: const ValueKey('be-lib-native-code'),
    title: name,
    hint: '只是给你看，应用不会运行它。',
    children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.x4, vertical: Space.x2),
        child: SelectableText(
          code,
          style: TextStyle(fontFamily: kMonoFont, fontFamilyFallback: kMonoFallback, fontSize: ref.watch(compactCodeFontProvider), color: context.colors.text, height: 1.4),
        ),
      ),
    ],
  );
}
