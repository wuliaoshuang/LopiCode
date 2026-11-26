// 聊天正文解析出来的“节点树”：纯数据、全部不可变。界面（lib/ui/md_*.dart）只照着它画，不再碰原文。
//
// 分两层：块（一段、标题、代码块、列表、表格……）和行内（文字、加粗、链接、图片……）。

/// 行内文字的样式（可以叠加）。
enum MdStyle { bold, italic, strike, underline, mark, sub, sup, kbd }

sealed class MdInline {
  const MdInline();
}

class MdText extends MdInline {
  const MdText(this.text);
  final String text;
}

class MdStyled extends MdInline {
  const MdStyled(this.style, this.children);
  final MdStyle style;
  final List<MdInline> children;
}

class MdInlineCode extends MdInline {
  const MdInlineCode(this.text, {this.math = false});
  final String text;

  /// true＝行内公式（`$…$`）：现在和行内代码一个画法，原样显示公式源码。
  final bool math;
}

class MdLink extends MdInline {
  const MdLink(this.href, this.children);
  final String href;
  final List<MdInline> children;
}

class MdImage extends MdInline {
  const MdImage(this.src, this.alt);
  final String src;
  final String alt;
}

/// 强制换行（`<br>`、行尾两个空格、普通的单个换行）。
class MdBreak extends MdInline {
  const MdBreak();
}

sealed class MdBlock {
  const MdBlock();
}

class MdParagraph extends MdBlock {
  const MdParagraph(this.inlines);
  final List<MdInline> inlines;
}

class MdHeading extends MdBlock {
  const MdHeading(this.level, this.inlines);
  final int level;
  final List<MdInline> inlines;
}

class MdCode extends MdBlock {
  const MdCode(this.code, {this.lang = '', this.closed = true, this.math = false});
  final String code;

  /// 围栏后面写的语言名（原样、小写），没写就是空。
  final String lang;

  /// 围栏收尾了没有。没收尾（还在往外冒）时不给“预览”。
  final bool closed;

  /// true＝公式块（`$$…$$`）：按代码样式原样显示。
  final bool math;
}

class MdQuote extends MdBlock {
  const MdQuote(this.children);
  final List<MdBlock> children;
}

class MdListItem {
  const MdListItem(this.children, {this.checked});
  final List<MdBlock> children;

  /// 任务列表：true＝打了勾，false＝没打，null＝不是任务项。
  final bool? checked;
}

class MdList extends MdBlock {
  const MdList(this.items, {this.ordered = false, this.start = 1});
  final List<MdListItem> items;
  final bool ordered;
  final int start;
}

enum MdAlign { left, center, right }

class MdTable extends MdBlock {
  const MdTable({required this.header, required this.rows, required this.aligns});
  final List<List<MdInline>> header;
  final List<List<List<MdInline>>> rows;
  final List<MdAlign> aligns;
}

class MdRule extends MdBlock {
  const MdRule();
}

/// `<details><summary>…</summary>…</details>`：点标题展开。
class MdDetails extends MdBlock {
  const MdDetails(this.summary, this.children, {this.open = false});
  final List<MdInline> summary;
  final List<MdBlock> children;
  final bool open;
}

/// 把行内节点拍平成纯文字（图片取说明文字）。
String mdPlainText(List<MdInline> inlines) {
  final b = StringBuffer();
  void walk(List<MdInline> list) {
    for (final n in list) {
      switch (n) {
        case MdText(:final text):
          b.write(text);
        case MdStyled(:final children):
          walk(children);
        case MdInlineCode(:final text):
          b.write(text);
        case MdLink(:final children):
          walk(children);
        case MdImage(:final alt):
          b.write(alt);
        case MdBreak():
          b.write('\n');
      }
    }
  }

  walk(inlines);
  return b.toString();
}
