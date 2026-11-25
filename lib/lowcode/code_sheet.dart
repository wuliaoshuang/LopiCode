// 设计约束（代码面板 · 390×844）
// - 底部面板：标题和一句说明在上，代码在中间可滚动，“复制全部”固定在底部（主操作）。
// - 代码带语法高亮，双指捏合可调字号（和文件编辑器共用一个字号，见 lib/ui/code_view.dart）。
import 'package:flutter/services.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/code_view.dart';
import 'package:lopicode/ui/widgets.dart';
import 'package:material_ui/material_ui.dart';

/// 显示一段代码 + “复制”按钮的底部面板内容（APK 打包页的工作流模板也用它）。
class CodeSheetBody extends StatelessWidget {
  const CodeSheetBody({super.key, required this.title, required this.note, required this.code, this.language = 'text', this.extraAction});
  final String title;
  final String note;
  final String code;

  /// 语言 id（`CodeHighlighter.languageFor(文件名)` 或宿主给的文件名）；不给就不上色。
  final String language;
  final Widget? extraAction;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      builder: (context, scroll) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.x4, 0, Space.x4, Space.x3),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: t.titleLarge),
                const SizedBox(height: 2),
                Text(note, style: t.bodySmall),
              ],
            ),
          ),
          Expanded(
            child: ColoredBox(
              color: c.codeBg,
              child: CodeZoom(
                child: SingleChildScrollView(
                  controller: scroll,
                  padding: const EdgeInsets.all(Space.x3),
                  child: SizedBox(
                    width: double.infinity,
                    child: CodeView(code: code, language: language),
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(Space.x4),
              child: Row(
                children: [
                  if (extraAction != null) ...[Expanded(child: extraAction!), const SizedBox(width: Space.x2)],
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: code));
                        if (context.mounted) showSnack(context, '已复制');
                      },
                      icon: const Icon(Icons.copy, size: 18),
                      label: const Text('复制全部'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
