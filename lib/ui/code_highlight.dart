import 'package:lopicode/theme/tokens.dart';
import 'package:material_ui/material_ui.dart';

/// 轻量语法高亮：按扩展名选一组正则，把注释 / 字符串 / 关键字 / 数字 / 标签上色。
/// 不是完整的语法分析，够在手机上看清结构；超长文件直接不高亮，保证输入不卡。
class CodeHighlighter {
  CodeHighlighter(this.language);
  final String language;

  static const int maxChars = 40000;

  static String languageFor(String path) {
    final ext = path.contains('.') ? path.split('.').last.toLowerCase() : '';
    return switch (ext) {
      'html' || 'htm' || 'xml' || 'svg' => 'html',
      'css' => 'css',
      'js' || 'mjs' || 'ts' || 'jsx' || 'tsx' => 'js',
      'json' => 'json',
      'dart' => 'dart',
      'md' => 'md',
      'yml' || 'yaml' => 'yaml',
      'sh' => 'sh',
      _ => 'text',
    };
  }

  static const _jsKeywords =
      'break|case|catch|class|const|continue|default|delete|do|else|export|extends|finally|for|from|function|if|import|in|instanceof|let|new|of|return|static|super|switch|this|throw|try|typeof|var|void|while|yield|async|await|true|false|null|undefined';
  static const _dartKeywords =
      'abstract|as|assert|async|await|break|case|catch|class|const|continue|default|do|else|enum|extends|extension|final|finally|for|get|if|implements|import|in|is|late|mixin|new|null|override|required|return|set|static|super|switch|this|throw|true|false|try|typedef|var|void|while|with|yield';

  // 每条规则：(正则, 种类)。按顺序合成一个大正则，先匹配到的优先。
  List<(String, String)> get _rules => switch (language) {
    'html' => [
      (r'<!--[\s\S]*?-->', 'comment'),
      (r'"[^"\n]*"|' r"'[^'\n]*'", 'string'),
      (r'</?[A-Za-z][A-Za-z0-9-]*|/?>', 'tag'),
      (r'\b[a-zA-Z-]+(?==)', 'attr'),
    ],
    'css' => [
      (r'/\*[\s\S]*?\*/', 'comment'),
      (r'"[^"\n]*"|' r"'[^'\n]*'", 'string'),
      (r'#[0-9a-fA-F]{3,8}\b|\b\d+(\.\d+)?(px|em|rem|%|vh|vw|s|ms|deg)?\b', 'number'),
      (r'[a-z-]+(?=\s*:)', 'attr'),
      (r'[.#][A-Za-z_][\w-]*', 'tag'),
    ],
    'js' => [
      (r'//[^\n]*|/\*[\s\S]*?\*/', 'comment'),
      (r'"(?:[^"\\\n]|\\.)*"|' r"'(?:[^'\\\n]|\\.)*'|`(?:[^`\\]|\\.)*`", 'string'),
      ('\\b(?:$_jsKeywords)\\b', 'keyword'),
      (r'\b\d+(\.\d+)?\b', 'number'),
    ],
    'dart' => [
      (r'//[^\n]*|/\*[\s\S]*?\*/', 'comment'),
      (r'"(?:[^"\\\n]|\\.)*"|' r"'(?:[^'\\\n]|\\.)*'", 'string'),
      ('\\b(?:$_dartKeywords)\\b', 'keyword'),
      (r'\b[A-Z][A-Za-z0-9_]*\b', 'tag'),
      (r'\b\d+(\.\d+)?\b', 'number'),
    ],
    'json' => [
      (r'"(?:[^"\\\n]|\\.)*"(?=\s*:)', 'attr'),
      (r'"(?:[^"\\\n]|\\.)*"', 'string'),
      (r'\b(?:true|false|null)\b', 'keyword'),
      (r'-?\b\d+(\.\d+)?\b', 'number'),
    ],
    'yaml' => [
      (r'#[^\n]*', 'comment'),
      (r'"[^"\n]*"|' r"'[^'\n]*'", 'string'),
      (r'^[ \t-]*[A-Za-z_][\w.-]*(?=:)', 'attr'),
      (r'\b(?:true|false|null)\b', 'keyword'),
      (r'\b\d+(\.\d+)?\b', 'number'),
    ],
    'sh' => [
      (r'#[^\n]*', 'comment'),
      (r'"(?:[^"\\]|\\.)*"|' r"'[^']*'", 'string'),
      (r'\b(?:if|then|else|elif|fi|for|in|do|done|while|case|esac|function|return|exit|export|echo|cd)\b', 'keyword'),
      (r'\$\{?[A-Za-z_][A-Za-z0-9_]*\}?', 'attr'),
    ],
    'md' => [
      (r'^#{1,6} [^\n]*', 'keyword'),
      (r'`[^`\n]+`', 'string'),
      (r'^\s*[-*] ', 'tag'),
    ],
    _ => const [],
  };

  late final RegExp? _regex = _rules.isEmpty
      ? null
      : RegExp([for (var i = 0; i < _rules.length; i++) '(?<g$i>${_rules[i].$1})'].join('|'), multiLine: true);

  static Color colorFor(String kind, AppColors c, Brightness b) {
    final dark = b == Brightness.dark;
    return switch (kind) {
      'comment' => c.textFaint,
      'string' => dark ? Palette.warning300 : Palette.warning700,
      'keyword' => dark ? Palette.danger300 : Palette.danger700,
      'number' => dark ? Palette.primary200 : Palette.primary900,
      'tag' => dark ? Palette.primary300 : Palette.primary800,
      'attr' => dark ? Palette.neutral300 : Palette.neutral700,
      _ => c.text,
    };
  }

  List<TextSpan> spans(String text, TextStyle base, AppColors c, Brightness brightness) {
    final regex = _regex;
    if (regex == null || text.length > maxChars) return [TextSpan(text: text, style: base)];
    final out = <TextSpan>[];
    var last = 0;
    for (final m in regex.allMatches(text)) {
      if (m.end == m.start) continue;
      if (m.start > last) out.add(TextSpan(text: text.substring(last, m.start), style: base));
      var kind = 'text';
      for (var i = 0; i < _rules.length; i++) {
        if (m.namedGroup('g$i') != null) {
          kind = _rules[i].$2;
          break;
        }
      }
      out.add(TextSpan(
        text: m[0],
        style: base.copyWith(
          color: colorFor(kind, c, brightness),
          fontStyle: kind == 'comment' ? FontStyle.italic : null,
        ),
      ));
      last = m.end;
    }
    if (last < text.length) out.add(TextSpan(text: text.substring(last), style: base));
    return out;
  }
}

/// 给 TextField 用的控制器：显示时套上高亮。
class CodeController extends TextEditingController {
  CodeController({super.text, required String path}) : highlighter = CodeHighlighter(CodeHighlighter.languageFor(path));
  final CodeHighlighter highlighter;

  @override
  TextSpan buildTextSpan({required BuildContext context, TextStyle? style, required bool withComposing}) {
    final base = style ?? const TextStyle();
    // 输入法组字期间（例如拼音）交给默认实现画下划线，避免光标错位。
    if (withComposing && value.isComposingRangeValid) {
      return super.buildTextSpan(context: context, style: style, withComposing: withComposing);
    }
    return TextSpan(
      style: base,
      children: highlighter.spans(text, base, context.colors, Theme.of(context).brightness),
    );
  }
}
