// 设计约束（原始 CSS 编辑；390×844，浅色 + 深色）
// - 从上到下：标题和一句说明 → 等宽的多行输入框 → 一行“应用后会变成什么” → 不会收下的条目（有才显示）→ 操作行（取消 / 应用）
//   → “来自属性的样式”（只读，放最后：它是参考，不是要操作的东西）。
// - 主操作只有“应用”。预览是随输入实时算的，不用再点按钮。
// - 输入框用代码底色和等宽字，和面板其它输入框区分开。
import 'package:lopicode/lowcode/css_codec.dart';
import 'package:lopicode/lowcode/style_model.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/widgets.dart';
import 'package:material_ui/material_ui.dart';

/// 打开原始 CSS 编辑。返回用户点“应用”时框里的文本；取消 / 直接关掉返回 null。
/// [initialCss] 是节点自己的 style 合并简写后的写法；[legacy] 是“属性”翻出来的样式（只读地列在下面）。
Future<String?> showStyleCssEditor(BuildContext context, {required String initialCss, required Map<String, String> legacy}) => showModalBottomSheet<String>(
  context: context,
  isScrollControlled: true,
  builder: (_) => _CssSheet(initialCss: initialCss, legacy: legacy),
);

class _CssSheet extends StatefulWidget {
  const _CssSheet({required this.initialCss, required this.legacy});
  final String initialCss;
  final Map<String, String> legacy;

  @override
  State<_CssSheet> createState() => _CssSheetState();
}

class _CssSheetState extends State<_CssSheet> {
  late final TextEditingController _text = TextEditingController(text: widget.initialCss);
  late CssParseResult _parsed = parseCss(widget.initialCss);

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final mono = t.bodyMedium?.copyWith(fontFamily: kMonoFont, fontFamilyFallback: kMonoFallback, height: 1.5);
    final decl = _parsed.declarations;
    final custom = LcStyle(decl).custom.length;
    final overridden = [
      for (final k in decl.keys)
        if (widget.legacy.containsKey(k)) k,
    ].length;
    final summary = decl.isEmpty
        ? '应用后：这个组件自己的样式会清空。'
        : '应用后：共 ${decl.length} 条样式（简写会拆开存）'
              '${custom > 0 ? '，其中 $custom 条是面板不认识的，会当自定义 CSS 留着' : ''}'
              '${overridden > 0 ? '；有 $overridden 条会盖掉属性里的同名样式' : ''}。';
    // 键盘的高度垫在滚动区外面：滚动区到键盘上沿为止，“应用”才滚得到、点得到。
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.92),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(Space.x4, 0, Space.x4, Space.x4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('原始 CSS', style: t.titleLarge),
                const SizedBox(height: Space.x1),
                Text('一行一条，写成“属性: 值;”。点“应用”会用这里的内容整个换掉这个组件自己的样式。', style: t.bodySmall),
                const SizedBox(height: Space.x3),
                TextField(
                  key: const Key('lc-css-input'),
                  controller: _text,
                  minLines: 6,
                  maxLines: 10,
                  autocorrect: false,
                  enableSuggestions: false,
                  keyboardType: TextInputType.multiline,
                  style: mono,
                  decoration: InputDecoration(
                    hintText: 'margin: 8px 4px;\ncolor: #333;',
                    hintStyle: mono?.copyWith(color: c.textFaint),
                    fillColor: c.codeBg,
                    contentPadding: const EdgeInsets.all(Space.x3),
                  ),
                  onChanged: (v) => setState(() => _parsed = parseCss(v)),
                ),
                const SizedBox(height: Space.x2),
                Text(summary, key: const Key('lc-css-preview'), style: t.bodySmall),
                if (_parsed.dropped.isNotEmpty) ...[const SizedBox(height: Space.x2), InfoBanner(key: const Key('lc-css-dropped'), droppedText(_parsed.dropped), tone: BannerTone.warning)],
                const SizedBox(height: Space.x3),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      style: TextButton.styleFrom(foregroundColor: c.textMuted),
                      child: const Text('取消'),
                    ),
                    const SizedBox(width: Space.x2),
                    FilledButton(key: const Key('lc-css-apply'), onPressed: () => Navigator.pop(context, _text.text), child: const Text('应用')),
                  ],
                ),
                const SizedBox(height: Space.x4),
                Text('来自属性的样式（只读）', style: t.labelMedium),
                const SizedBox(height: Space.x1),
                Text(widget.legacy.isEmpty ? '这个组件的“属性”里没有设会变成样式的东西。' : '这些是从“属性”面板里设的值翻出来的，要改去“属性”里改。在上面写同名的，会盖掉它。', style: t.bodySmall?.copyWith(color: c.textFaint)),
                if (widget.legacy.isNotEmpty) ...[
                  const SizedBox(height: Space.x2),
                  Container(
                    padding: const EdgeInsets.all(Space.x3),
                    decoration: BoxDecoration(color: c.codeBg, borderRadius: BorderRadius.circular(Radii.md)),
                    child: Text(
                      declarationsToCss(widget.legacy),
                      key: const Key('lc-css-legacy'),
                      style: mono?.copyWith(color: c.textMuted, fontSize: FontSize.xs),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 没收下的条目，写成给人看的一段话。
String droppedText(List<String> dropped) => '有 ${dropped.length} 条不会收下（其余照常应用）：\n${dropped.map((d) => '· $d').join('\n')}';
