// 设计约束（改动对比 · 390×844）
// - 这是“想看再点”的次要内容：等宽小字，不抢正式回复。字号跟着“设置 › 界面 › 外观 › 代码字号”走、小一号
//   （默认 14 → 这里 12）；双指捏合由外面包的 CodeZoom 管（步骤详情、确认卡预览、改过的文件各包一层），这里不再包。
// - 一行只有三样，固定顺序：行号（淡灰，靠右对齐）｜ 标记（+ / −）｜ 这一行的内容。
//   行号只占一列：增的行和不变的行写新文件里的行号，删的行写旧文件里的行号。
// - 颜色只表示“增 / 删”：增＝浅绿底，删＝浅红底，不变的行没有底色。四个颜色从当前主题来
//   （主题的“代码 › 改动对比”，[DiffColors]；默认主题里正文和标记在各自底色上对比度都 ≥ 4.5:1）。
// - 长行不折行：整块可以横向滑动，底色铺到最宽那一行。
// - 隔得远的不变行不显示，中间放一行淡字“… 省略 N 行”。
// - 默认最多露 [kDiffCollapsedLines] 行，其余收在“显示其余 N 行”里（点了才展开）。
// - 没有主操作。
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lopicode/agent/line_diff.dart';
import 'package:lopicode/state/code_font.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:material_ui/material_ui.dart';

/// 对比默认最多显示多少行，其余折叠。
const int kDiffCollapsedLines = 40;

/// 增 / 删的颜色（浅色、深色各一组）。
class DiffColors {
  const DiffColors({required this.addBg, required this.addFg, required this.delBg, required this.delFg});
  final Color addBg;
  final Color addFg;
  final Color delBg;
  final Color delFg;

  /// 从一份主题里取（主题的“代码 › 改动对比”那四个颜色）。
  DiffColors.fromTheme(ThemeSpec t) : addBg = t.codeColor(CodeKey.diffAddBg), addFg = t.codeColor(CodeKey.diffAddFg), delBg = t.codeColor(CodeKey.diffDelBg), delFg = t.codeColor(CodeKey.diffDelFg);

  /// 默认浅色 / 默认深色主题的。
  static final DiffColors light = DiffColors.fromTheme(AppColors.light.spec);
  static final DiffColors dark = DiffColors.fromTheme(AppColors.dark.spec);

  static DiffColors of(BuildContext context) => DiffColors.fromTheme(context.themeSpec);
}

/// “+3 −1”：加号绿、减号红，数字等宽。没有增删时什么都不画。
class DiffStat extends StatelessWidget {
  const DiffStat({super.key, required this.added, required this.removed});
  final int added;
  final int removed;

  @override
  Widget build(BuildContext context) {
    if (added == 0 && removed == 0) return const SizedBox.shrink();
    final d = DiffColors.of(context);
    return Text.rich(
      TextSpan(
        children: [
          if (added > 0)
            TextSpan(
              text: '+$added',
              style: TextStyle(color: d.addFg),
            ),
          if (added > 0 && removed > 0) const TextSpan(text: ' '),
          if (removed > 0)
            TextSpan(
              text: '−$removed',
              style: TextStyle(color: d.delFg),
            ),
        ],
      ),
      maxLines: 1,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600, fontFeatures: const [FontFeature.tabularFigures()]),
    );
  }
}

sealed class _Row {
  const _Row();
}

class _Gap extends _Row {
  const _Gap(this.lines);
  final int lines;
}

class _Code extends _Row {
  const _Code(this.line);
  final DiffLine line;
}

/// 一份对比。[numbers]＝false 时不画行号（预览“打算怎么改”时，行号只是那一小段里的，没意义）。
class DiffView extends ConsumerStatefulWidget {
  const DiffView({super.key, required this.change, this.numbers = true, this.collapsedLines = kDiffCollapsedLines});
  final FileChange change;
  final bool numbers;
  final int collapsedLines;

  @override
  ConsumerState<DiffView> createState() => _DiffViewState();
}

class _DiffViewState extends ConsumerState<DiffView> {
  bool _all = false;

  List<_Row> _rows() {
    final rows = <_Row>[];
    var nextNew = 1;
    for (final h in widget.change.hunks) {
      final gap = h.newStart - nextNew;
      if (gap > 0) rows.add(_Gap(gap));
      rows.addAll(h.rows.map(_Code.new));
      nextNew = h.newStart + h.newCount;
    }
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final d = DiffColors.of(context);
    final t = Theme.of(context).textTheme;
    final rows = _rows();
    if (rows.isEmpty) return const SizedBox.shrink();
    final codeRows = rows.whereType<_Code>().length;
    final over = codeRows > widget.collapsedLines && !_all;
    final shown = <_Row>[];
    var used = 0;
    for (final r in rows) {
      if (over && used >= widget.collapsedLines) break;
      shown.add(r);
      if (r is _Code) used++;
    }
    final hidden = codeRows - used;
    final size = ref.watch(compactCodeFontProvider);
    final mono = TextStyle(fontFamily: kMonoFont, fontFamilyFallback: kMonoFallback, fontSize: size, height: 1.5, color: c.text);
    var maxNo = 1;
    for (final r in shown) {
      if (r is _Code) {
        final n = r.line.newNo ?? r.line.oldNo ?? 1;
        if (n > maxNo) maxNo = n;
      }
    }
    // 行号列宽跟着字号走（等宽字一位数字约占字号的 2/3；12 号时正好是原来的 8）。
    final noWidth = size * 2 / 3 * '$maxNo'.length + 8;

    Widget rowOf(_Row r) {
      if (r is _Gap) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.x2, vertical: 2),
          child: Text('… 省略 ${r.lines} 行', style: mono.copyWith(color: c.textFaint)),
        );
      }
      final line = (r as _Code).line;
      final (bg, fg, sign) = switch (line.op) {
        DiffOp.add => (d.addBg, d.addFg, '+'),
        DiffOp.del => (d.delBg, d.delFg, '−'),
        DiffOp.same => (null, c.textFaint, ' '),
      };
      return ColoredBox(
        color: bg ?? Colors.transparent,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.numbers)
              SizedBox(
                width: noWidth,
                child: Text(
                  '${line.op == DiffOp.del ? line.oldNo : line.newNo}',
                  textAlign: TextAlign.right,
                  style: mono.copyWith(color: c.textFaint),
                ),
              ),
            SizedBox(
              width: size * 5 / 3,
              child: Text(
                sign,
                textAlign: TextAlign.center,
                style: mono.copyWith(color: fg, fontWeight: FontWeight.w600),
              ),
            ),
            // 制表符按 2 个空格画，免得一行宽得离谱。
            Text(line.text.replaceAll('\t', '  '), softWrap: false, style: mono),
            const SizedBox(width: Space.x3),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(Radii.sm),
          child: LayoutBuilder(
            builder: (context, box) => SingleChildScrollView(
              key: const ValueKey('diff-scroll'),
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: box.maxWidth.isFinite ? box.maxWidth : 0),
                child: IntrinsicWidth(
                  child: Column(key: const ValueKey('diff-rows'), crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [for (final r in shown) rowOf(r)]),
                ),
              ),
            ),
          ),
        ),
        if (over)
          Align(
            alignment: Alignment.centerLeft,
            child: InkWell(
              key: const ValueKey('diff-show-all'),
              onTap: () => setState(() => _all = true),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: Space.x2),
                child: Text('显示其余 $hidden 行', style: t.bodySmall?.copyWith(color: c.accent)),
              ),
            ),
          ),
      ],
    );
  }
}

/// 一个文件的改动：有说明就先说一句，有对比就画对比。
class FileChangeBody extends StatelessWidget {
  const FileChangeBody({super.key, required this.change, this.numbers = true, this.collapsedLines = kDiffCollapsedLines});
  final FileChange change;
  final bool numbers;
  final int collapsedLines;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final note = change.note;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (note != null)
          Padding(
            padding: EdgeInsets.only(bottom: change.hasDiff ? Space.x2 : 0),
            child: Text(
              note,
              key: const ValueKey('diff-note'),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: c.textMuted, height: 1.5),
            ),
          ),
        if (change.hasDiff) DiffView(change: change, numbers: numbers, collapsedLines: collapsedLines),
      ],
    );
  }
}
