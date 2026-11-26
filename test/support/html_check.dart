/// 导出的网页的结构检查（不是完整的 HTML 解析器，只查我们的导出器可能写错的那几样）：
/// 标签都配对、嵌套不交叉；属性值都用双引号包着、一个标签上没有重复的属性；
/// 可以点的元素里不套可以点的元素（button 里不放 button / input / select / textarea / a）；
/// 文字里没有落单的 `<`。返回问题清单，没问题是空的。
List<String> htmlProblems(String html) {
  final problems = <String>[];
  const voids = {'meta', 'link', 'input', 'img', 'hr', 'br'};
  const interactive = {'button', 'a', 'input', 'select', 'textarea'};
  final stack = <String>[];
  final tag = RegExp(r'<(/?)([a-zA-Z][a-zA-Z0-9]*)((?:\s+[^\s"=<>/]+(?:="[^"]*")?)*)\s*(/?)>|<!--[\s\S]*?-->|<!DOCTYPE html>');
  var at = 0;
  var inRawText = false;
  for (final m in tag.allMatches(html)) {
    final between = html.substring(at, m.start);
    if (!inRawText && (between.contains('<') || between.contains('>'))) problems.add('文字里有落单的尖括号：${between.trim()}');
    at = m.end;
    final name = m.group(2)?.toLowerCase();
    if (name == null) continue;
    final closing = m.group(1) == '/';
    if (inRawText) {
      // textarea / title 里面的都是文字，只认它自己的结束标签
      if (!(closing && name == stack.last)) continue;
      inRawText = false;
    }
    if (closing) {
      if (stack.isEmpty || stack.last != name) {
        problems.add('</$name> 对不上（现在开着的是 ${stack.isEmpty ? '无' : stack.last}）');
        if (stack.contains(name)) {
          while (stack.removeLast() != name) {}
        }
      } else {
        stack.removeLast();
      }
      continue;
    }
    final attrs = RegExp(r'\s+([^\s"=<>/]+)(?:="[^"]*")?').allMatches(m.group(3) ?? '').map((a) => a.group(1)!).toList();
    if (attrs.toSet().length != attrs.length) problems.add('<$name> 上有重复的属性：$attrs');
    if (interactive.contains(name) && stack.any((s) => s == 'button' || s == 'a')) problems.add('<$name> 套在了 button / a 里面');
    if (voids.contains(name)) continue;
    stack.add(name);
    if (name == 'textarea' || name == 'title') inRawText = true;
  }
  if (html.substring(at).contains('<')) problems.add('结尾有没写完的标签');
  if (stack.isNotEmpty) problems.add('没关的标签：$stack');
  return problems;
}
