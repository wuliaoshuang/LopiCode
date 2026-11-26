// 设计约束（聊天里的一段正文 · 390×844）— 2026-11-26 改成渲染 Markdown / HTML
// - **全聊天页画“一段正文”的地方只有这里一个入口**：我的消息（气泡里）、Agent 说的话（最终回答、两步之间的说明）、
//   思考全文（[muted]）都走 [MessageText]。调用的地方只给原文，怎么排版都在这里和 md_*.dart 里。
// - 层级：正文是聊天页里最重的内容——16 号字、主文字色。思考全文是次要内容：小字、灰色，同一套排版但不放大标题。
// - 从上往下一块一行：段落、标题、列表、引用、代码块、表格、图片、分隔线（各自的排法见 md_blocks.dart 等）。
// - 可以长按选字（整条正文连着选）；“复制”这类操作拿的是原文，不是排版后的样子（见 message_action_bar.dart）。
// - 还在往外冒的时候末尾带一个光标块；只有最后一块跟着变，前面排好的块不重排。
// - 这里只管正文本身；气泡、左右对齐、上下留白由调用的地方定（见 chat_row_view.dart）。
// - 上限：超过 20 万字的消息不解析，整条按纯文字显示（kMdMaxChars）。
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lopicode/markdown/md_document.dart';
import 'package:lopicode/state/code_font.dart';
import 'package:lopicode/state/ui_prefs.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/md_blocks.dart';
import 'package:lopicode/ui/md_link.dart';
import 'package:lopicode/ui/md_style.dart';
import 'package:lopicode/ui/message_action_bar.dart';
import 'package:material_ui/material_ui.dart';

class MessageText extends ConsumerStatefulWidget {
  const MessageText(this.text, {super.key, this.mine = false, this.streaming = false, this.muted = false});

  /// 正文原文（Markdown，里面可以带排版用的 HTML 标签）。
  final String text;

  /// true＝我的消息（在强调色浅底的气泡里）；false＝Agent 说的话（通栏、页面底色）。
  final bool mine;

  /// 还在往外冒：末尾带光标块。
  final bool streaming;

  /// 次要内容（思考全文）：小字、灰色。
  final bool muted;

  @override
  ConsumerState<MessageText> createState() => _MessageTextState();
}

class _MessageTextState extends ConsumerState<MessageText> {
  MdDocument _doc = MdDocument.empty;
  String? _docText;
  bool _docStreaming = false;

  /// 每一大块对应的控件。原文没变的块沿用同一个控件对象，框架就不会重排它。
  List<MdPiece> _pieces = const [];
  List<Widget> _views = const [];
  bool _lastHadCursor = false;

  void _parse() {
    final text = widget.text;
    final streaming = widget.streaming;
    if (_docText == text && _docStreaming == streaming) return;
    // 说完了的走全局缓存（滚出去再回来不重新解析）；还在冒的只重新解析变了的末尾
    _doc = streaming ? mdParseDocument(text, streaming: true, previous: _doc) : (_docStreaming ? mdParseDocument(text, previous: _doc) : mdParseCached(text));
    _docText = text;
    _docStreaming = streaming;
  }

  @override
  Widget build(BuildContext context) {
    _parse();
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final muted = widget.muted;
    final styles = MdStyles(
      tone: muted ? MdTone.muted : (widget.mine ? MdTone.bubble : MdTone.body),
      base: muted ? (t.bodySmall ?? const TextStyle()).copyWith(color: c.textMuted, height: 1.6) : (t.bodyLarge ?? const TextStyle()),
      codeSize: ref.watch(muted ? compactCodeFontProvider : codeFontProvider),
      colors: c,
      dark: Theme.of(context).brightness == Brightness.dark,
    );
    // 只取一次、不订阅：操作栏那边的状态（忙不忙、收藏）变了不用重排正文
    final guard = context.getInheritedWidgetOfExactType<MessageOpsScope>()?.session.guard;
    final autoImages = ref.watch(chatPrefsProvider.select((p) => p.autoImages));

    final Widget body;
    if (_doc.plain) {
      // 太长：不解析，按纯文字
      body = Text(widget.streaming ? '${widget.text}▍' : widget.text, style: styles.base);
    } else if (_doc.pieces.isEmpty) {
      body = Text(widget.streaming ? '▍' : '', style: styles.base);
    } else {
      body = Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: _pieceViews(styles.gap));
    }
    return MdScope(
      styles: styles,
      guard: guard,
      autoImages: autoImages,
      onLink: showMdLinkSheet,
      child: SelectionArea(child: body),
    );
  }

  List<Widget> _pieceViews(double gap) {
    final pieces = _doc.pieces;
    final cursor = widget.streaming;
    final views = <Widget>[];
    for (var i = 0; i < pieces.length; i++) {
      final last = i == pieces.length - 1;
      final reusable = i < _pieces.length && identical(_pieces[i], pieces[i]) && !(last && cursor) && !(i == _pieces.length - 1 && _lastHadCursor);
      views.add(
        reusable
            ? _views[i]
            : Padding(
                key: ValueKey(i),
                padding: EdgeInsets.only(top: i == 0 ? 0 : gap),
                child: MdBlocks(pieces[i].blocks, cursor: last && cursor),
              ),
      );
    }
    _pieces = pieces;
    _views = views;
    _lastHadCursor = cursor;
    return views;
  }
}
