// 设计约束（代码编辑器 · 390×844）
// - 编辑区：re_editor，左侧行号（弱化色），等宽 14px、行高 1.5；语法高亮只上色，不改字重。
// - 默认自动换行（手机上横向滚动很难用），⋮ 菜单里可以关。
// - 查找 / 替换面板贴在编辑区顶上、占满宽度：
//   第一行只做“查找”：输入框 + 第几个/共几个 + 上一个 / 下一个 + 关闭；
//   第二行（替换模式才有）只做“替换”：输入框 + 替换 + 全部。
//   大小写 / 正则是输入框里的两个小开关，不另占一行。
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/code_highlight.dart';
import 'package:material_ui/material_ui.dart';
import 'package:re_editor/re_editor.dart';
import 'package:re_highlight/languages/bash.dart';
import 'package:re_highlight/languages/css.dart';
import 'package:re_highlight/languages/dart.dart';
import 'package:re_highlight/languages/javascript.dart';
import 'package:re_highlight/languages/json.dart';
import 'package:re_highlight/languages/kotlin.dart';
import 'package:re_highlight/languages/markdown.dart';
import 'package:re_highlight/languages/python.dart';
import 'package:re_highlight/languages/typescript.dart';
import 'package:re_highlight/languages/xml.dart';
import 'package:re_highlight/languages/yaml.dart';
import 'package:re_highlight/re_highlight.dart';
import 'package:re_highlight/styles/atom-one-dark.dart';
import 'package:re_highlight/styles/atom-one-light.dart';

/// 文件对应的高亮语法；不认识的类型返回 null（不高亮）。
(String, Mode)? highlightModeFor(String path) => switch (CodeHighlighter.languageFor(path)) {
  'html' => ('xml', langXml),
  'css' => ('css', langCss),
  'js' => ('javascript', langJavascript),
  'ts' => ('typescript', langTypescript),
  'json' => ('json', langJson),
  'dart' => ('dart', langDart),
  'md' => ('markdown', langMarkdown),
  'yaml' => ('yaml', langYaml),
  'sh' => ('bash', langBash),
  'kotlin' => ('kotlin', langKotlin),
  'python' => ('python', langPython),
  _ => null,
};

class LopiCodeEditor extends StatelessWidget {
  const LopiCodeEditor({
    super.key,
    required this.path,
    required this.controller,
    required this.findController,
    required this.wordWrap,
  });

  final String path;
  final CodeLineEditingController controller;
  final CodeFindController findController;
  final bool wordWrap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final mode = highlightModeFor(path);
    final numberStyle = TextStyle(fontFamily: kMonoFont, fontFamilyFallback: kMonoFallback, fontSize: FontSize.xs, color: c.textFaint);
    return CodeEditor(
      controller: controller,
      findController: findController,
      wordWrap: wordWrap,
      autocompleteSymbols: false,
      padding: const EdgeInsets.symmetric(horizontal: Space.x2, vertical: Space.x2),
      style: CodeEditorStyle(
        fontSize: FontSize.sm,
        fontHeight: 1.5,
        fontFamily: kMonoFont,
        fontFamilyFallback: kMonoFallback,
        textColor: c.text,
        backgroundColor: c.codeBg,
        cursorColor: c.accent,
        cursorLineColor: c.surfaceMuted.withValues(alpha: 0.5),
        selectionColor: c.accent.withValues(alpha: 0.25),
        highlightColor: c.warning.withValues(alpha: 0.3),
        codeTheme: mode == null
            ? null
            : CodeHighlightTheme(
                languages: {mode.$1: CodeHighlightThemeMode(mode: mode.$2)},
                theme: {
                  for (final e in (dark ? atomOneDarkTheme : atomOneLightTheme).entries)
                    e.key: e.value.copyWith(fontWeight: FontWeight.w400, fontStyle: FontStyle.normal),
                },
              ),
      ),
      indicatorBuilder: (context, editingController, chunkController, notifier) => Padding(
        padding: const EdgeInsets.only(left: Space.x1, right: Space.x1),
        child: DefaultCodeLineNumber(
          controller: editingController,
          notifier: notifier,
          minNumberCount: 2,
          textStyle: numberStyle,
          focusedTextStyle: numberStyle.copyWith(color: c.text),
        ),
      ),
      findBuilder: (context, controller, readOnly) => CodeFindPanel(controller: controller),
    );
  }
}

/// 手机宽度的查找 / 替换面板。
class CodeFindPanel extends StatelessWidget implements PreferredSizeWidget {
  const CodeFindPanel({super.key, required this.controller});
  final CodeFindController controller;

  static const double _row = 48;

  @override
  Size get preferredSize {
    final value = controller.value;
    return Size(double.infinity, value == null ? 0 : (value.replaceMode ? _row * 2 : _row) + 1);
  }

  @override
  Widget build(BuildContext context) {
    final value = controller.value;
    if (value == null) return const SizedBox.shrink();
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final result = value.result;
    final count = value.option.pattern.isEmpty
        ? ''
        : result == null || result.matches.isEmpty
        ? '没找到'
        : '${result.index + 1}/${result.matches.length}';

    InputDecoration deco(String hint, {Widget? suffix}) => InputDecoration(
      hintText: hint,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: Space.x3, vertical: Space.x2),
      suffixIcon: suffix,
      suffixIconConstraints: const BoxConstraints(minHeight: 32),
    );
    Widget toggle(String label, String tip, bool on, VoidCallback onTap) => Tooltip(
      message: tip,
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.sm),
        onTap: onTap,
        child: Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: on ? c.accentSoft : null, borderRadius: BorderRadius.circular(Radii.sm)),
          child: Text(
            label,
            style: TextStyle(fontFamily: kMonoFont, fontSize: FontSize.xs, fontWeight: FontWeight.w600, color: on ? c.accent : c.textFaint),
          ),
        ),
      ),
    );
    Widget icon(IconData data, String tip, VoidCallback? onTap) => IconButton(
      tooltip: tip,
      visualDensity: VisualDensity.compact,
      icon: Icon(data, size: 20),
      onPressed: onTap,
    );
    final hasMatch = result != null && result.matches.isNotEmpty;
    return Container(
      height: preferredSize.height,
      decoration: BoxDecoration(color: c.surface, border: Border(bottom: BorderSide(color: c.border))),
      child: Column(
        children: [
          SizedBox(
            height: _row,
            child: Row(
              children: [
                const SizedBox(width: Space.x2),
                Expanded(
                  child: TextField(
                    key: const Key('find-input'),
                    controller: controller.findInputController,
                    focusNode: controller.findInputFocusNode,
                    autocorrect: false,
                    enableSuggestions: false,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => controller.nextMatch(),
                    style: t.bodyMedium,
                    decoration: deco(
                      '查找',
                      suffix: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          toggle('Aa', '区分大小写', value.option.caseSensitive, controller.toggleCaseSensitive),
                          toggle('.*', '正则表达式', value.option.regex, controller.toggleRegex),
                          const SizedBox(width: Space.x1),
                        ],
                      ),
                    ),
                  ),
                ),
                if (count.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(left: Space.x2),
                    child: Text(count, key: const Key('find-count'), style: t.bodySmall?.copyWith(color: hasMatch ? c.textMuted : c.danger)),
                  ),
                icon(Icons.keyboard_arrow_up, '上一个', hasMatch ? controller.previousMatch : null),
                icon(Icons.keyboard_arrow_down, '下一个', hasMatch ? controller.nextMatch : null),
                icon(Icons.close, '关闭查找', controller.close),
              ],
            ),
          ),
          if (value.replaceMode)
            SizedBox(
              height: _row,
              child: Row(
                children: [
                  const SizedBox(width: Space.x2),
                  Expanded(
                    child: TextField(
                      key: const Key('replace-input'),
                      controller: controller.replaceInputController,
                      focusNode: controller.replaceInputFocusNode,
                      autocorrect: false,
                      enableSuggestions: false,
                      style: t.bodyMedium,
                      decoration: deco('替换成'),
                    ),
                  ),
                  TextButton(onPressed: hasMatch ? controller.replaceMatch : null, child: const Text('替换')),
                  TextButton(key: const Key('replace-all'), onPressed: hasMatch ? controller.replaceAllMatches : null, child: const Text('全部')),
                  const SizedBox(width: Space.x1),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
