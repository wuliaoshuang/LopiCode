// 设计约束（聊天里的一段正文文字 · 390×844）— 2026-11-26
// - **全聊天页画“一段正文”的地方只有这里一个入口**：我的消息（气泡里）、Agent 说的话（不管是最终回答还是两步之间的说明）都走 [MessageText]。
//   以后要把正文换成 Markdown / HTML 渲染，只改这个控件的 build，调用的地方不用动。
// - 层级：正文是聊天页里最重的内容——16 号字、主文字色、可以长按选字。还在往外冒的时候末尾带一个光标块。
// - 这里只管文字本身；气泡、左右对齐、上下留白由调用的地方定（见 chat_row_view.dart）。
import 'package:material_ui/material_ui.dart';

class MessageText extends StatelessWidget {
  const MessageText(this.text, {super.key, this.mine = false, this.streaming = false});

  /// 正文原文（模型写的是 Markdown 原文，现在按纯文字显示）。
  final String text;

  /// true＝我的消息；false＝Agent 说的话。现在两边画法一样，留给以后区分用。
  final bool mine;

  /// 还在往外冒：末尾带光标块。
  final bool streaming;

  @override
  Widget build(BuildContext context) => SelectableText(streaming ? '$text▍' : text, style: Theme.of(context).textTheme.bodyLarge);
}
