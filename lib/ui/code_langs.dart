// 代码高亮支持哪些语言（都是 re_highlight 自带的规则，没有新依赖）。
// 语言判断只走 CodeHighlighter 一个入口；这里只管“语言 id → 高亮规则”。
import 'package:lopicode/ui/code_highlight.dart';
import 'package:material_ui/material_ui.dart';
import 'package:re_highlight/languages/apache.dart';
import 'package:re_highlight/languages/arduino.dart';
import 'package:re_highlight/languages/asciidoc.dart';
import 'package:re_highlight/languages/awk.dart';
import 'package:re_highlight/languages/bash.dart';
import 'package:re_highlight/languages/c.dart';
import 'package:re_highlight/languages/clojure.dart';
import 'package:re_highlight/languages/cmake.dart';
import 'package:re_highlight/languages/coffeescript.dart';
import 'package:re_highlight/languages/cpp.dart';
import 'package:re_highlight/languages/crystal.dart';
import 'package:re_highlight/languages/csharp.dart';
import 'package:re_highlight/languages/css.dart';
import 'package:re_highlight/languages/d.dart';
import 'package:re_highlight/languages/dart.dart';
import 'package:re_highlight/languages/delphi.dart';
import 'package:re_highlight/languages/diff.dart';
import 'package:re_highlight/languages/django.dart';
import 'package:re_highlight/languages/dockerfile.dart';
import 'package:re_highlight/languages/dos.dart';
import 'package:re_highlight/languages/dts.dart';
import 'package:re_highlight/languages/elixir.dart';
import 'package:re_highlight/languages/elm.dart';
import 'package:re_highlight/languages/erb.dart';
import 'package:re_highlight/languages/erlang.dart';
import 'package:re_highlight/languages/fortran.dart';
import 'package:re_highlight/languages/fsharp.dart';
import 'package:re_highlight/languages/glsl.dart';
import 'package:re_highlight/languages/go.dart';
import 'package:re_highlight/languages/gradle.dart';
import 'package:re_highlight/languages/graphql.dart';
import 'package:re_highlight/languages/groovy.dart';
import 'package:re_highlight/languages/haml.dart';
import 'package:re_highlight/languages/handlebars.dart';
import 'package:re_highlight/languages/haskell.dart';
import 'package:re_highlight/languages/haxe.dart';
import 'package:re_highlight/languages/http.dart';
import 'package:re_highlight/languages/ini.dart';
import 'package:re_highlight/languages/java.dart';
import 'package:re_highlight/languages/javascript.dart';
import 'package:re_highlight/languages/json.dart';
import 'package:re_highlight/languages/julia.dart';
import 'package:re_highlight/languages/kotlin.dart';
import 'package:re_highlight/languages/latex.dart';
import 'package:re_highlight/languages/less.dart';
import 'package:re_highlight/languages/lisp.dart';
import 'package:re_highlight/languages/llvm.dart';
import 'package:re_highlight/languages/lua.dart';
import 'package:re_highlight/languages/makefile.dart';
import 'package:re_highlight/languages/markdown.dart';
import 'package:re_highlight/languages/matlab.dart';
import 'package:re_highlight/languages/nginx.dart';
import 'package:re_highlight/languages/nim.dart';
import 'package:re_highlight/languages/nix.dart';
import 'package:re_highlight/languages/objectivec.dart';
import 'package:re_highlight/languages/ocaml.dart';
import 'package:re_highlight/languages/perl.dart';
import 'package:re_highlight/languages/pgsql.dart';
import 'package:re_highlight/languages/php.dart';
import 'package:re_highlight/languages/powershell.dart';
import 'package:re_highlight/languages/prolog.dart';
import 'package:re_highlight/languages/properties.dart';
import 'package:re_highlight/languages/protobuf.dart';
import 'package:re_highlight/languages/puppet.dart';
import 'package:re_highlight/languages/python.dart';
import 'package:re_highlight/languages/qml.dart';
import 'package:re_highlight/languages/r.dart';
import 'package:re_highlight/languages/ruby.dart';
import 'package:re_highlight/languages/rust.dart';
import 'package:re_highlight/languages/scala.dart';
import 'package:re_highlight/languages/scheme.dart';
import 'package:re_highlight/languages/scss.dart';
import 'package:re_highlight/languages/smali.dart';
import 'package:re_highlight/languages/sql.dart';
import 'package:re_highlight/languages/stylus.dart';
import 'package:re_highlight/languages/swift.dart';
import 'package:re_highlight/languages/tcl.dart';
import 'package:re_highlight/languages/thrift.dart';
import 'package:re_highlight/languages/twig.dart';
import 'package:re_highlight/languages/typescript.dart';
import 'package:re_highlight/languages/vala.dart';
import 'package:re_highlight/languages/vbnet.dart';
import 'package:re_highlight/languages/verilog.dart';
import 'package:re_highlight/languages/vhdl.dart';
import 'package:re_highlight/languages/vim.dart';
import 'package:re_highlight/languages/wasm.dart';
import 'package:re_highlight/languages/x86asm.dart';
import 'package:re_highlight/languages/xml.dart';
import 'package:re_highlight/languages/yaml.dart';
import 'package:re_highlight/re_highlight.dart';
import 'package:re_highlight/styles/atom-one-dark.dart';
import 'package:re_highlight/styles/atom-one-light.dart';

/// 语言 id（[CodeHighlighter.languageFor] 的返回值）→（re_highlight 里的名字，规则）。
///
/// .vue 按 xml 上色：re_highlight 自带的 vue 规则要同时装六种语言才生效，而编辑器一装多种语言就改成“自动猜”，会猜错。
final Map<String, (String, Mode)> kCodeLanguages = {
  'html': ('xml', langXml),
  'vue': ('xml', langXml),
  'css': ('css', langCss),
  'scss': ('scss', langScss),
  'less': ('less', langLess),
  'js': ('javascript', langJavascript),
  'ts': ('typescript', langTypescript),
  'json': ('json', langJson),
  'dart': ('dart', langDart),
  'md': ('markdown', langMarkdown),
  'yaml': ('yaml', langYaml),
  'sh': ('bash', langBash),
  'kotlin': ('kotlin', langKotlin),
  'python': ('python', langPython),
  'go': ('go', langGo),
  'java': ('java', langJava),
  'php': ('php', langPhp),
  'csharp': ('csharp', langCsharp),
  'rust': ('rust', langRust),
  'ruby': ('ruby', langRuby),
  'c': ('c', langC),
  'cpp': ('cpp', langCpp),
  'sql': ('sql', langSql),
  'ini': ('ini', langIni),
  'properties': ('properties', langProperties),
  'dockerfile': ('dockerfile', langDockerfile),
  'gradle': ('gradle', langGradle),
  'groovy': ('groovy', langGroovy),
  'swift': ('swift', langSwift),
  'objectivec': ('objectivec', langObjectivec),
  'lua': ('lua', langLua),
  'perl': ('perl', langPerl),
  'r': ('r', langR),
  'scala': ('scala', langScala),
  'makefile': ('makefile', langMakefile),
  'cmake': ('cmake', langCmake),
  'diff': ('diff', langDiff),
  'powershell': ('powershell', langPowershell),
  'bat': ('dos', langDos),
  'graphql': ('graphql', langGraphql),
  'protobuf': ('protobuf', langProtobuf),
  'nginx': ('nginx', langNginx),
  'haskell': ('haskell', langHaskell),
  'elixir': ('elixir', langElixir),
  'erlang': ('erlang', langErlang),
  'clojure': ('clojure', langClojure),
  'julia': ('julia', langJulia),
  'fsharp': ('fsharp', langFsharp),
  'vbnet': ('vbnet', langVbnet),
  'ocaml': ('ocaml', langOcaml),
  'nim': ('nim', langNim),
  'latex': ('latex', langLatex),
  'delphi': ('delphi', langDelphi),
  'lisp': ('lisp', langLisp),
  'scheme': ('scheme', langScheme),
  'elm': ('elm', langElm),
  'crystal': ('crystal', langCrystal),
  'coffeescript': ('coffeescript', langCoffeescript),
  'stylus': ('stylus', langStylus),
  'handlebars': ('handlebars', langHandlebars),
  'twig': ('twig', langTwig),
  'erb': ('erb', langErb),
  'haml': ('haml', langHaml),
  'django': ('django', langDjango),
  'nix': ('nix', langNix),
  'vim': ('vim', langVim),
  'tcl': ('tcl', langTcl),
  'awk': ('awk', langAwk),
  'http': ('http', langHttp),
  'apache': ('apache', langApache),
  'qml': ('qml', langQml),
  'arduino': ('arduino', langArduino),
  'wasm': ('wasm', langWasm),
  'verilog': ('verilog', langVerilog),
  'vhdl': ('vhdl', langVhdl),
  'fortran': ('fortran', langFortran),
  'thrift': ('thrift', langThrift),
  'prolog': ('prolog', langProlog),
  'pgsql': ('pgsql', langPgsql),
  'glsl': ('glsl', langGlsl),
  'x86asm': ('x86asm', langX86Asm),
  'haxe': ('haxe', langHaxe),
  'd': ('d', langD),
  'vala': ('vala', langVala),
  'dts': ('dts', langDts),
  'llvm': ('llvm', langLlvm),
  'smali': ('smali', langSmali),
  'puppet': ('puppet', langPuppet),
  'asciidoc': ('asciidoc', langAsciidoc),
  'matlab': ('matlab', langMatlab),
};

/// 语言 id 对应的高亮规则；不认识的返回 null（不高亮）。
(String, Mode)? highlightModeForLanguage(String language) => kCodeLanguages[language];

/// 文件对应的高亮规则；不认识的类型返回 null（不高亮）。
(String, Mode)? highlightModeFor(String path) => highlightModeForLanguage(CodeHighlighter.languageFor(path));

final Map<bool, Map<String, TextStyle>> _themes = {};

/// 高亮配色（浅色 / 深色各一套）。只上色，不改字重和斜体：等宽代码里粗体会把列挤歪。
Map<String, TextStyle> codeThemeFor({required bool dark}) =>
    _themes[dark] ??= {for (final e in (dark ? atomOneDarkTheme : atomOneLightTheme).entries) e.key: e.value.copyWith(fontWeight: FontWeight.w400, fontStyle: FontStyle.normal)};

Highlight? _highlight;

/// 超过这么多字就不高亮了（只读查看和输入框是在界面线程上色的，太长会卡）。
const int kHighlightMaxChars = 120000;

/// 把一段代码上色成一串文字片段。语言不认识、代码太长、上色出错都退回不上色的一整段。
TextSpan highlightCode(String code, String language, {required bool dark, required TextStyle base}) {
  final mode = highlightModeForLanguage(language);
  if (mode == null || code.isEmpty || code.length > kHighlightMaxChars) return TextSpan(text: code, style: base);
  try {
    final hl = _highlight ??= (Highlight()..registerLanguages({for (final m in kCodeLanguages.values) m.$1: m.$2}));
    final renderer = TextSpanRenderer(base, codeThemeFor(dark: dark));
    hl.highlight(code: code, language: mode.$1).render(renderer);
    return renderer.span ?? TextSpan(text: code, style: base);
  } on Object {
    // 高亮规则是第三方的正则，遇到它处理不了的内容宁可不上色，也不能让代码显示不出来。
    return TextSpan(text: code, style: base);
  }
}
