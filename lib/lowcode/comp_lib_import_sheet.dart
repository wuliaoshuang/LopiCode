// 设计约束（低代码 · 组件库 · 导入前的预览 · 390×844）
// - 这一页是“薄壳”：数据的形状（[CompLibImportView]）和线 A 的公用预览页 lib/ui/lib_import_sheet.dart 的 LibImportView 一样，
//   两条线合并以后把 [showCompLibImport] 的调用换成 showLibImport、把这个文件删掉就行（调用点只有 comp_lib_sheet.dart 一处）。
// - 从上到下：标题 → 名字 → 一行弱化的“标识 · 版本 · 作者 · 给谁用”→ 要注意的（一条一行）→ 清单 →
//   不能导入的原因（有就用警示色列出来，主操作灰掉）→ 一句提示 → 唯一的主操作。
// - 一行只做一件事；颜色全取主题值。
import 'package:lopicode/theme/tokens.dart';
import 'package:material_ui/material_ui.dart';

/// 导入前给人看的东西。字段和线 A 的 LibImportView 一一对应。
class CompLibImportView {
  const CompLibImportView({
    required this.name,
    required this.id,
    required this.version,
    required this.author,
    required this.side,
    this.summary = '',
    this.needs = const [],
    this.hasSource = true,
    this.nativeFiles = const {},
    this.nativeEnabled = false,
    this.nativeNotes = const [],
    this.listTitle = '组件',
    this.items = const [],
    this.problems = const [],
  });
  final String name, id, version, author, side, summary;

  /// 要注意的（比如“带着 2 张图片”“里面有事件和状态”）。
  final List<String> needs;
  final bool hasSource;

  /// 手写代码文件（组件库这一版不许带，带了就在 [problems] 里）。
  final Map<String, String> nativeFiles;
  final bool nativeEnabled;
  final List<String> nativeNotes;
  final String listTitle;
  final List<String> items;
  final List<String> problems;

  bool get canImport => problems.isEmpty;
}

/// 打开预览；点了主操作返回 true。
Future<bool> showCompLibImport(BuildContext context, CompLibImportView view, {required String hint, String title = '导入库', String action = '导入'}) async =>
    await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ImportSheet(view: view, hint: hint, title: title, action: action),
    ) ??
    false;

class _ImportSheet extends StatelessWidget {
  const _ImportSheet({required this.view, required this.hint, required this.title, required this.action});
  final CompLibImportView view;
  final String hint, title, action;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    Widget head(String s) => Padding(
      padding: const EdgeInsets.only(top: Space.x4, bottom: Space.x1),
      child: Text(s, style: t.labelMedium?.copyWith(color: c.textMuted)),
    );
    final meta = [if (view.id.isNotEmpty) view.id, if (view.version.isNotEmpty) view.version, if (view.author.isNotEmpty) view.author, view.side].join(' · ');
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      minChildSize: 0.3,
      maxChildSize: 0.92,
      builder: (context, scroll) => ListView(
        key: const ValueKey('complib-import'),
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(Space.x4, 0, Space.x4, Space.x6),
        children: [
          Text(title, style: t.titleLarge),
          const SizedBox(height: Space.x3),
          Text(view.name.isEmpty ? '（没有名字）' : view.name, style: t.titleMedium),
          const SizedBox(height: 2),
          Text(meta, style: t.bodySmall?.copyWith(color: c.textMuted)),
          if (view.summary.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: Space.x2),
              child: Text(view.summary, style: t.bodyMedium),
            ),
          if (view.needs.isNotEmpty) head('要注意的'),
          for (final n in view.needs)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text('· $n', style: t.bodyMedium),
            ),
          if (view.items.isNotEmpty) head('${view.listTitle}（${view.items.length}）'),
          for (final i in view.items)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(i, style: t.bodyMedium, maxLines: 2, overflow: TextOverflow.ellipsis),
            ),
          if (view.nativeFiles.isNotEmpty) head('手写代码文件（${view.nativeFiles.length}）'),
          for (final f in view.nativeFiles.keys)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(f, style: t.bodySmall),
            ),
          if (view.problems.isNotEmpty) head('不能导入'),
          for (final p in view.problems)
            Padding(
              key: ValueKey('complib-import-problem-${view.problems.indexOf(p)}'),
              padding: const EdgeInsets.only(bottom: Space.x1),
              child: Text(p, style: t.bodyMedium?.copyWith(color: c.warning)),
            ),
          const SizedBox(height: Space.x4),
          Text(hint, style: t.bodySmall?.copyWith(color: c.textMuted)),
          const SizedBox(height: Space.x3),
          FilledButton(key: const ValueKey('complib-import-go'), onPressed: view.canImport ? () => Navigator.pop(context, true) : null, child: Text(action)),
        ],
      ),
    );
  }
}
