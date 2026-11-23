/// 按扩展名判断文件是哪种语言（文件图标和编辑器高亮共用）。
class CodeHighlighter {
  static String languageFor(String path) {
    final ext = path.contains('.') ? path.split('.').last.toLowerCase() : '';
    return switch (ext) {
      'html' || 'htm' || 'xml' || 'svg' => 'html',
      'css' => 'css',
      'js' || 'mjs' || 'jsx' => 'js',
      'ts' || 'tsx' => 'ts',
      'json' => 'json',
      'dart' => 'dart',
      'md' => 'md',
      'yml' || 'yaml' => 'yaml',
      'sh' => 'sh',
      'kt' || 'kts' => 'kotlin',
      'py' => 'python',
      _ => 'text',
    };
  }
}
