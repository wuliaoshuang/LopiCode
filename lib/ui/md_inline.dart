// 设计约束（正文里的一段带样式的文字）— 2026-11-26
// - 一段文字是一个整体（一个 Text.rich），这样长按能连着选字；链接是其中带下划线的强调色文字，点了先问。
// - 行内代码：等宽字、浅底，不加边框（一行里边框太吵）。图片在行内占自己的位置（见 md_image.dart）。
// - 上标 / 下标只把字缩小（不挪基线：挪基线要换成不能选字的小控件，得不偿失）。
import 'package:flutter/gestures.dart';
import 'package:lopicode/markdown/md_nodes.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/md_image.dart';
import 'package:lopicode/ui/md_style.dart';
import 'package:material_ui/material_ui.dart';

class MdRichText extends StatefulWidget {
  const MdRichText(this.inlines, {super.key, this.style, this.cursor = false, this.textAlign});
  final List<MdInline> inlines;

  /// 不传就用正文样式。
  final TextStyle? style;

  /// 末尾带光标块（还在往外冒）。
  final bool cursor;
  final TextAlign? textAlign;

  @override
  State<MdRichText> createState() => _MdRichTextState();
}

class _MdRichTextState extends State<MdRichText> {
  final List<TapGestureRecognizer> _taps = [];

  void _clear() {
    for (final t in _taps) {
      t.dispose();
    }
    _taps.clear();
  }

  @override
  void dispose() {
    _clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scope = MdScope.of(context);
    final s = scope.styles;
    _clear();
    final base = widget.style ?? s.base;
    final spans = _spans(context, scope, widget.inlines);
    if (widget.cursor) spans.add(const TextSpan(text: '▍'));
    return Text.rich(
      TextSpan(style: base, children: spans),
      textAlign: widget.textAlign,
    );
  }

  List<InlineSpan> _spans(BuildContext context, MdScope scope, List<MdInline> list) {
    final s = scope.styles;
    final c = s.colors;
    final out = <InlineSpan>[];
    for (final n in list) {
      switch (n) {
        case MdText(:final text):
          out.add(TextSpan(text: text));
        case MdBreak():
          out.add(const TextSpan(text: '\n'));
        case MdInlineCode(:final text):
          out.add(
            TextSpan(
              // 两头各垫一个窄空格，底色不贴着字
              text: '\u2009$text\u2009',
              style: TextStyle(fontFamily: kMonoFont, fontFamilyFallback: kMonoFallback, fontSize: s.codeSize, backgroundColor: s.blockBg),
            ),
          );
        case MdStyled(:final style, :final children):
          final size = style == MdStyle.sub || style == MdStyle.sup ? (s.base.fontSize ?? 16) * 0.75 : null;
          final ts = switch (style) {
            MdStyle.bold => const TextStyle(fontWeight: FontWeight.w600),
            MdStyle.italic => const TextStyle(fontStyle: FontStyle.italic),
            MdStyle.strike => const TextStyle(decoration: TextDecoration.lineThrough),
            MdStyle.underline => const TextStyle(decoration: TextDecoration.underline),
            MdStyle.mark => TextStyle(backgroundColor: c.warningSoft, color: s.dark ? c.warning : null),
            MdStyle.sub || MdStyle.sup => TextStyle(fontSize: size),
            MdStyle.kbd => TextStyle(fontFamily: kMonoFont, fontFamilyFallback: kMonoFallback, fontSize: s.codeSize, backgroundColor: s.blockBg, fontWeight: FontWeight.w600),
          };
          out.add(TextSpan(style: ts, children: _spans(context, scope, children)));
        case MdLink(:final href, :final children):
          final tap = TapGestureRecognizer()..onTap = () => scope.onLink(context, href);
          _taps.add(tap);
          out.add(
            TextSpan(
              style: TextStyle(color: c.accent, decoration: TextDecoration.underline, decorationColor: c.accent),
              recognizer: tap,
              // 链接里的字都挂上同一个点按（链接里套了粗体也能点）
              children: _linkKids(context, scope, children, tap),
            ),
          );
        case MdImage(:final src, :final alt):
          out.add(
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: MdImageView(src: src, alt: alt),
            ),
          );
      }
    }
    return out;
  }

  List<InlineSpan> _linkKids(BuildContext context, MdScope scope, List<MdInline> kids, TapGestureRecognizer tap) {
    InlineSpan hook(InlineSpan sp) => sp is TextSpan ? TextSpan(text: sp.text, style: sp.style, recognizer: tap, children: sp.children?.map(hook).toList()) : sp;
    return _spans(context, scope, kids).map(hook).toList();
  }
}
