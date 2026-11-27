// 设计约束（导入库之前的预览 / 确认手写代码，390 宽，浅色 + 深色）— 2026-11-27 第四轮
// - 公用页：积木库现在用，下一轮的组件库也用。它不认识任何一种文档，只认 [LibImportView]（要给人看的东西都在里面）。
// - 这一页只回答一件事：“这个库是什么、导进来安不安全、要不要导”。主操作只有一个：底部那颗按钮（不能点时是灰的，上面写着原因）。
// - 内容排序：主＝名字、标识、版本、作者、给谁用（各一行）；次＝“要注意的”（靠哪些库、碰哪些宿主能力、带没带手写代码）；
//   三＝清单（一块一行，只看）。
// - 手写代码：每个文件一行、点开看全文；全应用的开关关着＝只能看、不能导入；开着＝底下多一行勾选“我看过这些代码了”，
//   勾上主按钮才亮。警告的字用危险色，而且写的是实话（没有隔开、和工程同权限）。
// - 一行只做一件事；颜色全取主题值；代码用应用统一的代码字号。
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lopicode/state/code_font.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/backend_core_sheet.dart';
import 'package:material_ui/material_ui.dart';

/// 手写代码到底意味着什么（预览页、设置页、确认页说的是同一段话）。
const String kLibNativeRisk =
    '手写代码不是积木，应用看不懂它，也不检查它。它会原样写进生成的工程；工程一运行，它就跟着运行，'
    '和工程里别的代码在同一个进程里、权限一样：能读写这个工程碰得到的所有文件、能联网、能读环境变量（里面可能有密钥）、能起别的程序。'
    '应用没有把它单独关起来，“超时取消”也管不到它里面。只放你自己逐行看过、信得过的代码。';

/// 预览页要给人看的东西。
class LibImportView {
  const LibImportView({
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
    this.listTitle = '积木',
    this.unit = '块',
    this.items = const [],
    this.problems = const [],
  });
  final String name;
  final String id;
  final String version;
  final String author;

  /// 给谁用（人话：后端 / 前端 / 后端和前端都行）。
  final String side;
  final String summary;

  /// “要注意的”：一条一句。
  final List<String> needs;
  final bool hasSource;

  /// 手写代码：文件名 → 全文。
  final Map<String, String> nativeFiles;

  /// 全应用“允许库里的手写代码”开没开。
  final bool nativeEnabled;

  /// 关于手写函数的补充说明（哪些要等、各有哪几种语言）。
  final List<String> nativeNotes;
  final String listTitle;

  /// 清单的量词（积木论“块”，组件论“个”）。
  final String unit;
  final List<String> items;

  /// 不能导入的原因；空＝可以。
  final List<String> problems;

  bool get hasNative => nativeFiles.isNotEmpty;
  bool get canImport => problems.isEmpty;
}

/// 导入前的预览。返回 true＝用户点了主按钮（带手写代码的库：点之前一定勾过“我看过这些代码了”）。
/// `title` / `action`：导入时是“导入库”/“导入”；已经在项目里、只是来确认手写代码时换成别的字。
Future<bool> showLibImport(BuildContext context, LibImportView view, {required String hint, String title = '导入库', String action = '导入'}) async =>
    await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ImportSheet(view: view, hint: hint, title: title, action: action),
    ) ??
    false;

class _ImportSheet extends StatefulWidget {
  const _ImportSheet({required this.view, required this.hint, required this.title, required this.action});
  final LibImportView view;
  final String hint;
  final String title;
  final String action;

  @override
  State<_ImportSheet> createState() => _ImportSheetState();
}

class _ImportSheetState extends State<_ImportSheet> {
  bool _seen = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final p = widget.view;
    final needTick = p.hasNative && p.nativeEnabled;
    final ready = p.canImport && (!needTick || _seen);
    return BeSheetFrame(
      key: const ValueKey('be-lib-import-sheet'),
      title: widget.title,
      hint: widget.hint,
      problem: p.canImport ? null : '这个库不能导入：${p.problems.join('；')}',
      footer: FilledButton(key: const ValueKey('be-lib-import-go'), onPressed: ready ? () => Navigator.pop(context, true) : null, child: Text(widget.action)),
      children: [
        BeSheetRow(label: '名字', value: p.name),
        BeSheetRow(label: '标识', value: p.id),
        BeSheetRow(label: '版本', value: p.version),
        BeSheetRow(label: '作者', value: p.author),
        BeSheetRow(key: const ValueKey('be-lib-import-side'), label: '给谁用', value: p.side),
        if (p.summary.isNotEmpty) BeSheetRow(label: '介绍', value: p.summary),
        const BeSheetSection('要注意的'),
        if (p.needs.isEmpty && !p.hasNative) const BeSheetRow(label: '只用积木写的，不靠别的库，不带手写代码', muted: true),
        for (final n in p.needs) _Line(n),
        if (!p.hasSource) const _Line('没有带画布原件：能用，但是不能回到画布上改它'),
        if (p.hasNative) ...[
          _Line('带了手写代码（${p.nativeFiles.length} 个文件）。$kLibNativeRisk', key: const ValueKey('be-lib-native-risk'), color: c.danger),
          if (!p.nativeEnabled) _Line('“允许库里的手写代码”现在是关着的，所以这个库不能导入。下面的代码可以点开看。', key: const ValueKey('be-lib-native-off'), color: c.danger),
          for (final n in p.nativeNotes) _Line(n),
          for (final f in p.nativeFiles.keys)
            BeSheetRow(
              key: ValueKey('be-lib-native-$f'),
              label: f,
              value: '看代码',
              onTap: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                builder: (_) => _CodeSheet(name: f, code: p.nativeFiles[f] ?? ''),
              ),
            ),
          if (needTick)
            CheckboxListTile(
              key: const ValueKey('be-lib-native-seen'),
              contentPadding: const EdgeInsets.symmetric(horizontal: Space.x4),
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text('我看过这些代码了，知道它会跟着工程一起运行'),
              value: _seen,
              onChanged: p.canImport ? (v) => setState(() => _seen = v ?? false) : null,
            ),
        ],
        BeSheetSection('${p.listTitle}（${p.items.length} ${p.unit}）'),
        for (final b in p.items) BeSheetRow(label: b, muted: true),
      ],
    );
  }
}

/// 一段可以换行的说明（“要注意的”里一条一段）。
class _Line extends StatelessWidget {
  const _Line(this.text, {super.key, this.color});
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
    hint: '只是给你看。应用自己不会运行它；它是放进生成的工程里、工程运行时才跑的。',
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
