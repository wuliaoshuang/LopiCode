// 设计约束（正文里的代码块 · 390×844）— 2026-11-26
// - 上面一行：左边语言名（小灰字），右边“预览”（只有 html / svg 且代码写完了才有）和“复制”。一行只做这一件事。
// - 下面是代码：等宽、按语言上色（和编辑器同一套 90 种语言）、长行左右滑不折行。
// - 超过 30 行先只显示前 30 行，底下一行“展开全部（N 行）”；还在往外冒的代码块不折（免得写着写着突然缩回去）。
// - 点了“预览”，代码的位置换成网页预览（见 html_preview.dart），再点“看代码”换回来。
// - 字号跟“代码字号”设置走。这里不接捏合缩放：聊天列表本身要上下滑，两根手指容易误触；要调去 设置 › 界面 › 外观。
import 'package:flutter/services.dart';
import 'package:lopicode/markdown/html_preview_doc.dart';
import 'package:lopicode/markdown/md_nodes.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/code_highlight.dart';
import 'package:lopicode/ui/code_langs.dart';
import 'package:lopicode/ui/html_preview.dart';
import 'package:lopicode/ui/md_style.dart';
import 'package:lopicode/ui/widgets.dart';
import 'package:material_ui/material_ui.dart';

/// 代码块超过这么多行先折起来（自己定的）。
const int kMdCodeCollapseLines = 30;

/// 还在往外冒的代码块超过这么多字就先不上色（每来几个字都要重新上色一遍，太长会卡；写完了再上）。
const int kMdStreamingHighlightMaxChars = 20000;

const Map<String, String> _aliases = {
  'javascript': 'js',
  'jsx': 'js',
  'node': 'js',
  'typescript': 'ts',
  'tsx': 'ts',
  'py': 'python',
  'python3': 'python',
  'shell': 'sh',
  'bash': 'sh',
  'zsh': 'sh',
  'console': 'sh',
  'terminal': 'sh',
  'yml': 'yaml',
  'c++': 'cpp',
  'c#': 'csharp',
  'cs': 'csharp',
  'golang': 'go',
  'kt': 'kotlin',
  'rs': 'rust',
  'rb': 'ruby',
  'htm': 'html',
  'xml': 'html',
  'svg': 'html',
  'markdown': 'md',
  'objc': 'objectivec',
  'objective-c': 'objectivec',
  'docker': 'dockerfile',
  'ps1': 'powershell',
  'pwsh': 'powershell',
  'batch': 'bat',
  'tex': 'latex',
  'postgres': 'pgsql',
  'postgresql': 'pgsql',
  'mysql': 'sql',
  'sqlite': 'sql',
  'toml': 'ini',
  'env': 'ini',
  'jsonc': 'json',
  'json5': 'json',
};

/// 围栏上写的语言名 → 高亮用的语言 id；不认识返回 'text'（不上色）。
String codeLanguageForLabel(String label) {
  final l = label.trim().toLowerCase();
  if (l.isEmpty) return 'text';
  if (kCodeLanguages.containsKey(l)) return l;
  final alias = _aliases[l];
  if (alias != null) return alias;
  // 剩下的当成扩展名再认一次（比如 mjs、kts、hpp）
  final byExt = CodeHighlighter.languageFor('f.$l');
  return kCodeLanguages.containsKey(byExt) ? byExt : 'text';
}

class MdCodeBlock extends StatefulWidget {
  const MdCodeBlock(this.block, {super.key, this.cursor = false});
  final MdCode block;
  final bool cursor;

  @override
  State<MdCodeBlock> createState() => _MdCodeBlockState();
}

class _MdCodeBlockState extends State<MdCodeBlock> {
  // 一出来就是写完了的长代码：先折着。出来时还在写的：一直展开（她可以自己折）。
  late bool _expanded = !widget.block.closed || widget.cursor || _lineCount(widget.block.code) <= kMdCodeCollapseLines;
  bool _preview = false;
  TextSpan? _span;
  Object? _spanFor;

  static int _lineCount(String s) => '\n'.allMatches(s).length + 1;

  @override
  Widget build(BuildContext context) {
    final s = MdScope.of(context).styles;
    final c = s.colors;
    final t = Theme.of(context).textTheme;
    final b = widget.block;
    final lines = _lineCount(b.code);
    final long = lines > kMdCodeCollapseLines;
    final canPreview = !b.math && b.closed && !widget.cursor && htmlPreviewable(b.lang) && b.code.trim().isNotEmpty;
    final label = b.math ? '公式' : (b.lang.isEmpty ? '代码' : b.lang);
    final small = t.labelMedium?.copyWith(color: c.textMuted);

    Widget action(String text, IconData icon, VoidCallback onTap, Key key) => InkWell(
      key: key,
      borderRadius: BorderRadius.circular(Radii.sm),
      onTap: onTap,
      child: ConstrainedBox(
        // 字小，但能点的范围留够 40 高
        constraints: const BoxConstraints(minHeight: 40),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.x2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: c.textMuted),
              const SizedBox(width: Space.x1),
              Text(text, style: small),
            ],
          ),
        ),
      ),
    );

    return Container(
      key: const Key('md-code-block'),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: s.blockBg,
        borderRadius: BorderRadius.circular(Radii.md),
        border: s.tone == MdTone.body ? null : Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: Space.x3, right: Space.x1),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: small?.copyWith(color: c.textFaint),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (canPreview) action(_preview ? '看代码' : '预览', _preview ? Icons.code_rounded : Icons.visibility_outlined, () => setState(() => _preview = !_preview), const Key('md-code-preview')),
                action('复制', Icons.copy_rounded, () => _copy(context), const Key('md-code-copy')),
              ],
            ),
          ),
          if (_preview && canPreview)
            HtmlPreviewBox(code: b.code, lang: b.lang)
          else ...[
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(Space.x3, 0, Space.x3, Space.x3),
              child: Text.rich(_highlighted(s, lines), key: const Key('md-code-text'), style: s.mono, softWrap: false),
            ),
            if (long && b.closed)
              InkWell(
                key: const Key('md-code-expand'),
                onTap: () => setState(() => _expanded = !_expanded),
                child: Container(
                  constraints: const BoxConstraints(minHeight: 40),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    border: Border(top: BorderSide(color: c.border)),
                  ),
                  child: Text(_expanded ? '收起' : '展开全部（$lines 行）', style: small?.copyWith(color: c.accent)),
                ),
              ),
          ],
        ],
      ),
    );
  }

  TextSpan _highlighted(MdStyles s, int lines) {
    final b = widget.block;
    final lang = b.math ? 'latex' : codeLanguageForLabel(b.lang);
    var code = b.code;
    if (!_expanded && lines > kMdCodeCollapseLines) code = code.split('\n').take(kMdCodeCollapseLines).join('\n');
    final plain = !b.closed && code.length > kMdStreamingHighlightMaxChars;
    final key = (code, lang, s.dark, s.text, plain, widget.cursor);
    if (_spanFor != key) {
      // 制表符换成 4 个空格再显示（普通文字控件里制表符只有一格宽）；复制拿的是原文
      final shown = code.replaceAll('\t', '    ');
      final base = TextStyle(color: s.text);
      final span = plain ? TextSpan(text: shown, style: base) : highlightCode(shown, lang, dark: s.dark, base: base);
      _span = widget.cursor
          ? TextSpan(
              children: [
                span,
                const TextSpan(text: '▍'),
              ],
            )
          : span;
      _spanFor = key;
    }
    return _span!;
  }

  Future<void> _copy(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: widget.block.code));
    if (context.mounted) showSnack(context, '已复制代码');
  }
}
