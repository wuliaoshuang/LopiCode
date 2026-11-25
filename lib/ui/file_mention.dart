// 设计约束（聊天输入框上方的“@ 选文件”候选列表 · 390×844）
// - 什么时候出现：输入框有焦点，光标前面正在打 `@xxx`（`@` 在草稿开头或前面是空白 / 换行）。规则在 session/file_mentions.dart。
// - 摆在哪：贴在输入框正上方，和输入框同宽，跟着输入框一起被键盘顶上去，所以不会被键盘或底部导航挡住。
// - 层级：主角是文件名（正文色）；所在目录是次要信息（灰色、靠后、放不下就省略）；最下面一行小字只在“没列全”时出现。
// - 一行一个文件：图标 + 文件名 + 灰色目录，行高 48（可点区域不小于 44）。最多露出 5 行半（半行是“下面还有”的提示），多的在列表里滚。
// - 主操作只有一个：点一行＝把正在打的 `@xxx` 换成这个文件的引用（和“＋ › 引用项目文件”插进去的一模一样），焦点和键盘都不动。
// - 收起：光标移走、删掉 `@`、打空格、失焦、按返回键、点列表和输入框以外的地方。
// - 列表和输入框算同一块（TextFieldTapRegion）：点候选不算“点了输入框外面”，不会因此收键盘。
// - 没有匹配、还在找、读不了：各用一行字说清楚，不留一片空白。
import 'dart:async';

import 'package:lopicode/core/path_guard.dart';
import 'package:lopicode/session/file_mentions.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/file_icon.dart';
import 'package:lopicode/ui/widgets.dart';
import 'package:material_ui/material_ui.dart';

/// 候选列表一行的高度。
const double kMentionRowHeight = 48;

/// 候选列表最多露出几行（多的滚动看）。故意多露半行：一眼看得出下面还有、可以滚。
const double kMentionVisibleRows = 5.5;

/// 扫工作区文件的办法；测试里换成假的。
typedef MentionScanner = Future<MentionScan> Function(PathGuard guard);

/// 放在输入框正上方：平时不占地方，正在打 `@` 时显示工作区文件候选。
class FileMentionLayer extends StatefulWidget {
  const FileMentionLayer({super.key, required this.controller, required this.focusNode, required this.guard, this.scanner});

  final TextEditingController controller;
  final FocusNode focusNode;
  final PathGuard guard;
  final MentionScanner? scanner;

  @override
  State<FileMentionLayer> createState() => _FileMentionLayerState();
}

class _FileMentionLayerState extends State<FileMentionLayer> {
  MentionTrigger? _trigger;
  MentionScan? _scan;

  /// 扫描的代次：换了一次扫描以后，旧的那次回来的结果不要。
  int _generation = 0;

  /// 她手动收起（返回键 / 点外面）时的草稿；草稿没变之前不再弹。
  String? _dismissedText;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_sync);
    widget.focusNode.addListener(_sync);
    _trigger = _compute();
    if (_trigger != null) _startScan();
  }

  @override
  void didUpdateWidget(FileMentionLayer old) {
    super.didUpdateWidget(old);
    final rewired = old.controller != widget.controller || old.focusNode != widget.focusNode;
    if (rewired) {
      old.controller.removeListener(_sync);
      old.focusNode.removeListener(_sync);
      widget.controller.addListener(_sync);
      widget.focusNode.addListener(_sync);
    }
    if (rewired || old.guard.root != widget.guard.root) {
      // 换了输入框或换了工作区：旧的判断和旧的扫描结果都作废，按新的重新来。
      _generation++;
      _scan = null;
      _dismissedText = null;
      _trigger = _compute();
      if (_trigger != null) _startScan();
    }
  }

  @override
  void dispose() {
    _generation++;
    widget.controller.removeListener(_sync);
    widget.focusNode.removeListener(_sync);
    super.dispose();
  }

  MentionTrigger? _compute() {
    if (!widget.focusNode.hasFocus) return null;
    final v = widget.controller.value;
    if (_dismissedText != null) {
      if (_dismissedText == v.text) return null;
      _dismissedText = null;
    }
    return mentionTriggerAt(v.text, selStart: v.selection.start, selEnd: v.selection.end, composingStart: v.composing.start, composingEnd: v.composing.end);
  }

  /// 草稿、光标、焦点变了：重新判断。只有“在不在打 @ / 打的是什么”变了才重画。
  void _sync() {
    if (!mounted) return;
    final next = _compute();
    if (next == _trigger) return;
    final opening = _trigger == null && next != null;
    setState(() => _trigger = next);
    // 每次重新弹出都重扫一遍：两次之间文件可能变了。
    if (opening) _startScan();
  }

  void _startScan() {
    final generation = ++_generation;
    _scan = null;
    unawaited(_runScan(generation));
  }

  Future<void> _runScan(int generation) async {
    MentionScan result;
    try {
      result = await (widget.scanner ?? scanMentionFiles)(widget.guard);
    } on Exception catch (e) {
      result = MentionScan(const [], error: '读不了工作区的文件：$e');
    }
    // 旧的一次扫描（已经收起又重弹、换了工作区、页面关了）回来的结果丢掉，不盖新的。
    if (!mounted || generation != _generation) return;
    setState(() => _scan = result);
  }

  void _dismiss() {
    if (_trigger == null) return;
    setState(() {
      _dismissedText = widget.controller.text;
      _trigger = null;
    });
  }

  void _pick(String path) {
    final trigger = _trigger;
    if (trigger == null) return;
    try {
      // 只能引用工作区里面的文件。
      widget.guard.resolve(path);
    } on PathGuardException catch (e) {
      showSnack(context, e.message);
      return;
    }
    final edit = applyMention(widget.controller.text, trigger, path);
    widget.controller.value = TextEditingValue(
      text: edit.text,
      selection: TextSelection.collapsed(offset: edit.cursor),
    );
    if (!edit.added) showSnack(context, '这个文件已经引用过了，没有重复添加。');
  }

  @override
  Widget build(BuildContext context) {
    final trigger = _trigger;
    if (trigger == null) return const SizedBox.shrink();
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _dismiss();
      },
      child: TextFieldTapRegion(
        onTapOutside: (_) => _dismiss(),
        child: _MentionPanel(scan: _scan, query: trigger.query, onPick: _pick),
      ),
    );
  }
}

class _MentionPanel extends StatelessWidget {
  const _MentionPanel({required this.scan, required this.query, required this.onPick});

  final MentionScan? scan;
  final String query;
  final void Function(String path) onPick;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final scan = this.scan;
    final List<Widget> children;
    if (scan == null) {
      children = [const _Note(key: ValueKey('mention-loading'), text: '正在找文件…', busy: true)];
    } else if (scan.error != null) {
      children = [_Note(key: const ValueKey('mention-error'), text: scan.error!)];
    } else {
      final matches = filterMentionFiles(scan.files, query);
      final notes = [if (matches.clipped) '匹配的文件有 ${matches.total} 个，只显示前 ${matches.files.length} 个，继续输入可缩小范围。', if (scan.truncated) '工作区文件太多，只找了前 ${scan.files.length} 个；没列出来的可以直接打出路径。'];
      children = [
        if (matches.files.isEmpty)
          _Note(key: const ValueKey('mention-empty'), text: scan.files.isEmpty && !scan.truncated ? '工作区里还没有文件。' : '没有匹配的文件。')
        else
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: kMentionRowHeight * kMentionVisibleRows),
            child: ListView.builder(
              key: const ValueKey('mention-list'),
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              itemExtent: kMentionRowHeight,
              itemCount: matches.files.length,
              itemBuilder: (context, i) => _MentionRow(path: matches.files[i], onTap: () => onPick(matches.files[i])),
            ),
          ),
        if (notes.isNotEmpty)
          Container(
            key: const ValueKey('mention-more'),
            width: double.infinity,
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: c.border)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: Space.x3, vertical: Space.x2),
            child: Text(notes.join('\n'), style: t.bodySmall?.copyWith(color: c.textMuted)),
          ),
      ];
    }
    return Container(
      key: const ValueKey('mention-panel'),
      margin: const EdgeInsets.fromLTRB(Space.x3, 0, Space.x3, Space.x2),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(Radii.lg),
        border: Border.all(color: c.border),
      ),
      // InkWell 的水波要画在 Material 上。
      child: Material(
        type: MaterialType.transparency,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
      ),
    );
  }
}

class _MentionRow extends StatelessWidget {
  const _MentionRow({required this.path, required this.onTap});

  final String path;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final slash = path.lastIndexOf('/');
    final name = slash < 0 ? path : path.substring(slash + 1);
    final dir = slash < 0 ? '' : path.substring(0, slash);
    return InkWell(
      key: ValueKey('mention-$path'),
      onTap: onTap,
      // 点候选不抢输入框的焦点，键盘不动。
      canRequestFocus: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.x3),
        child: Row(
          children: [
            FileIcon(path),
            const SizedBox(width: Space.x3),
            Flexible(
              flex: 3,
              child: Text(
                name,
                style: t.bodyMedium?.copyWith(color: c.text),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: Space.x2),
            Expanded(
              flex: 2,
              child: Text(
                dir,
                style: t.bodySmall?.copyWith(color: c.textMuted),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 列表位置上的一行说明（还在找 / 没有匹配 / 读不了）。
class _Note extends StatelessWidget {
  const _Note({super.key, required this.text, this.busy = false});

  final String text;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: kMentionRowHeight),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.x3, vertical: Space.x2),
        child: Row(
          children: [
            if (busy) ...[SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: c.textFaint)), const SizedBox(width: Space.x3)],
            Expanded(
              child: Text(text, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: c.textMuted)),
            ),
          ],
        ),
      ),
    );
  }
}
