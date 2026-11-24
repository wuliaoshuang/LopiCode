// 代码格式化的入口。文件编辑器的“格式化”和低代码导出的代码都从这里走。
//
// 四条铁律（test/format_*.dart 逐条有用例）：
// 1. 幂等：排过的再排一次，结果不变。
// 2. 不改意思：排完以后重新分词，和原文的记号序列逐个比对，对不上就放弃、原样返回。
// 3. 解析不了（括号 / 引号 / 标签不配平）就原样返回，并说出大概在第几行。
// 4. 任何输入都不抛异常。
import 'package:lopicode/format/format_common.dart';
import 'package:lopicode/format/format_css.dart';
import 'package:lopicode/format/format_html.dart';
import 'package:lopicode/format/format_js.dart';
import 'package:lopicode/format/format_json.dart';
import 'package:lopicode/format/format_vue.dart';
import 'package:lopicode/format/js_lexer.dart';

class FormatResult {
  const FormatResult({required this.text, required this.changed, this.problem, this.note});

  /// 格式化后的全文。没法格式化（[problem] 不为空）时一定等于原文。
  final String text;

  /// [text] 和原文是不是不一样。
  final bool changed;

  /// 没法格式化时给人看的原因；格式化成功时为 null。
  final String? problem;

  /// 格式化成功、但有一部分原样保留时的说明（比如 Vue 文件里 lang="ts" 的脚本）；没有就是 null。
  final String? note;

  bool get ok => problem == null;
}

/// 超过这么多字符的文件不格式化（编辑器本来也打不开超过 1MB 的文件）。
const int kFormatMaxChars = 2 * 1024 * 1024;

const String kFormatMismatch = '格式化结果和原文对不上，已放弃，文件没有改动';

/// 按扩展名判断文件能用哪种格式化；不支持的返回 null。
String? formatLanguageFor(String path) {
  final name = path.split('/').last.split(r'\').last;
  final dot = name.lastIndexOf('.');
  if (dot < 0) return null;
  return switch (name.substring(dot + 1).toLowerCase()) {
    'json' => 'json',
    'css' => 'css',
    'html' || 'htm' => 'html',
    'js' || 'mjs' || 'jsx' => 'js',
    'vue' => 'vue',
    _ => null,
  };
}

String? _canonicalLanguage(String language) => switch (language.trim().toLowerCase()) {
  'json' => 'json',
  'css' => 'css',
  'html' || 'htm' => 'html',
  'js' || 'jsx' || 'mjs' || 'javascript' => 'js',
  'vue' => 'vue',
  _ => null,
};

FormatPiece _format(String language, String source, int indent) => switch (language) {
  'json' => formatJson(source, indent: indent),
  'css' => formatCss(source, indent: indent),
  'html' => formatHtml(source, indent: indent),
  'vue' => formatVue(source, indent: indent),
  _ => formatJs(source, indent: indent),
};

List<String> _signature(String language, String source) => switch (language) {
  'json' => jsonSignature(source),
  'css' => cssSignature(source),
  'html' => htmlSignature(source),
  'vue' => vueSignature(source),
  _ => jsSignature(source),
};

/// 去掉空白以后的“有意义的记号”序列（字符串、模板字符串、正则逐字保留，注释只忽略每行首尾的空白）。
/// 分不了词（代码本身不配平）或不支持的语言返回 null。测试和排查问题时用。
List<String>? codeTokens(String source, String language) {
  final lang = _canonicalLanguage(language);
  if (lang == null) return null;
  try {
    return _signature(lang, _normalize(source).$1);
  } on FormatProblem {
    return null;
    // ignore: avoid_catches_without_on_clauses 栈溢出之类的 Error 也要接住：这个函数承诺不抛
  } catch (_) {
    return null;
  }
}

/// 去掉 BOM、把换行统一成 \n。返回（正文，有没有 BOM，原来是不是 CRLF）。
(String, bool, bool) _normalize(String source) {
  final bom = source.startsWith('\uFEFF');
  var body = bom ? source.substring(1) : source;
  final crlf = body.contains('\r\n');
  if (body.contains('\r')) body = body.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  return (body, bom, crlf);
}

/// 格式化一段代码。
///
/// [language]：json / css / html / js（jsx、mjs、javascript 也算）/ vue。[indent]：一层缩进几个空格。
///
/// 换行风格跟原文走：原文用 CRLF 的，结果也是 CRLF（混用的统一成 CRLF）；有 BOM 的保留 BOM。
/// 结果末尾恰好一个换行。空文件、只有空白的文件原样返回。
///
/// 这个函数不抛异常。没法格式化时 [FormatResult.problem] 是原因，[FormatResult.text] 等于原文。
FormatResult formatCode(String source, String language, {int indent = 2}) {
  FormatResult failed(String why) => FormatResult(text: source, changed: false, problem: why);
  final lang = _canonicalLanguage(language);
  if (lang == null) return failed('不支持格式化这种文件（只支持 JSON、CSS、HTML、JavaScript / JSX、Vue）');
  if (source.length > kFormatMaxChars) return failed('文件太大（超过 2MB），没有格式化');
  if (source.contains('\u0000')) return failed('这个文件看起来不是文本，没有格式化');
  final (body, bom, crlf) = _normalize(source);
  if (trimWs(body).isEmpty) return FormatResult(text: source, changed: false);
  final width = indent < 0 ? 0 : (indent > 16 ? 16 : indent);
  try {
    final piece = _format(lang, body, width);
    return checkedResult(source, piece.text, lang, note: piece.note);
  } on FormatProblem catch (e) {
    return failed(e.message);
    // ignore: avoid_catches_without_on_clauses 栈溢出、越界之类的 Error 也要接住：格式化器再有 bug 也不能让编辑器崩，更不能把文件弄坏
  } catch (_) {
    return failed('格式化时出了意外，已放弃，文件没有改动');
  }
}

/// 最后一道保险：把排好的 [formatted]（换行是 \n）和原文各自分词比对，一样才放行。
/// 对不上就原样返回原文，并说明已放弃。（单独拿出来是为了能直接测“对不上”这条路。）
FormatResult checkedResult(String source, String formatted, String language, {String? note}) {
  FormatResult failed(String why) => FormatResult(text: source, changed: false, problem: why);
  final lang = _canonicalLanguage(language);
  if (lang == null) return failed('不支持格式化这种文件');
  final (body, bom, crlf) = _normalize(source);
  try {
    var text = trimWsRight(formatted.replaceAll('\r\n', '\n'));
    if (text.isEmpty) return failed(kFormatMismatch);
    text = '$text\n';
    if (!sameList(_signature(lang, body), _signature(lang, text))) return failed(kFormatMismatch);
    if (crlf) text = text.replaceAll('\n', '\r\n');
    if (bom) text = '\uFEFF$text';
    return FormatResult(text: text, changed: text != source, note: note);
  } on FormatProblem catch (e) {
    return failed(e.message);
    // ignore: avoid_catches_without_on_clauses 同上：这里不许抛
  } catch (_) {
    return failed(kFormatMismatch);
  }
}
