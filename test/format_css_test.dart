// CSS 格式化器：例子、四条铁律、刁钻输入。
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/format/format.dart';

import 'format_support.dart';

void main() {
  group('输入 → 期望输出', () {
    test('一条声明一行、选择器后 {、冒号后一个空格、规则之间空一行', () {
      expect(formatOk('a{color:red;margin : 0 auto}\n.b , .c>d{top:0}', 'css'), 'a {\n  color: red;\n  margin: 0 auto;\n}\n\n.b, .c>d {\n  top: 0;\n}\n');
    });

    test('最后一条声明补上分号，多余的分号去掉', () {
      expect(formatOk('a{;;color:red;;top:0}', 'css'), 'a {\n  color: red;\n  top: 0;\n}\n');
    });

    test('@media / @supports / @keyframes 嵌套', () {
      expect(
        formatOk(
          '@media (min-width:600px) and (max-width:900px){.x{top:0}@supports (display:grid){.z{display:grid}}}\n@keyframes spin{from{transform:rotate(0)}50%{opacity:.5}to{transform:rotate(360deg)}}',
          'css',
        ),
        '@media (min-width:600px) and (max-width:900px) {\n  .x {\n    top: 0;\n  }\n\n  @supports (display:grid) {\n    .z {\n      display: grid;\n    }\n  }\n}\n\n'
        '@keyframes spin {\n  from {\n    transform: rotate(0);\n  }\n\n  50% {\n    opacity: .5;\n  }\n\n  to {\n    transform: rotate(360deg);\n  }\n}\n',
      );
    });

    test('@import / @charset 一行一条，中间不硬加空行', () {
      expect(formatOk('@charset "utf-8";@import url(foo.css);\n@import "b.css" screen\n;\na{}', 'css'), '@charset "utf-8";\n@import url(foo.css);\n@import "b.css" screen;\n\na {}\n');
    });

    test('注释保留：独占一行的、写在行尾的、规则上面的', () {
      expect(formatOk('/* 头 */\na{color:red; /* 行尾 */\n/* 独占 */\ntop:0}\n\n\n/* b 的说明 */\nb{}', 'css'), '/* 头 */\na {\n  color: red; /* 行尾 */\n  /* 独占 */\n  top: 0;\n}\n\n/* b 的说明 */\nb {}\n');
    });

    test('声明之间原来有空行的保留一行；原来一行一个的选择器保持一行一个', () {
      expect(formatOk('h1,\nh2,\n  h3\n{\nfont:12px/1.5 "A B",serif;\n\n\n\ncolor:blue\n}', 'css'), 'h1,\nh2,\nh3 {\n  font: 12px/1.5 "A B",serif;\n\n  color: blue;\n}\n');
    });

    test('多行的值保留换行，后面几行对齐', () {
      expect(formatOk('.y{transition:opacity .2s,\n         transform .3s;}', 'css'), '.y {\n  transition: opacity .2s,\n    transform .3s;\n}\n');
    });

    test('CSS 嵌套写法（规则里套规则）', () {
      expect(formatOk('.a{color:red;&:hover{color:blue}.b &{top:0}}', 'css'), '.a {\n  color: red;\n\n  &:hover {\n    color: blue;\n  }\n\n  .b & {\n    top: 0;\n  }\n}\n');
    });

    test('缩进宽度可以改', () {
      expect(formatOk('a{b:c}', 'css', indent: 4), 'a {\n    b: c;\n}\n');
    });

    test('已经整齐的：changed 为假', () {
      const src = 'a {\n  color: red;\n}\n\nb {}\n';
      final r = formatCode(src, 'css');
      expect(r.changed, isFalse);
      expect(r.text, src);
    });
  });

  group('刁钻输入', () {
    test('content: "}" 和字符串里的 ; { /* 都不当语法', () {
      expect(
        formatOk('a::before{content:"}";quotes:"{" \';\' "/*" "*/"}b{content:\'a\\\'b;\'}', 'css'),
        'a::before {\n  content: "}";\n  quotes: "{" \';\' "/*" "*/";\n}\n\nb {\n  content: \'a\\\'b;\';\n}\n',
      );
    });

    test('url(data:…) 里的 ; { } 逗号原样保留', () {
      const url = 'url(data:image/svg+xml;charset=utf8,%3Csvg xmlns=\'http://www.w3.org/2000/svg\'%3E{};%3C/svg%3E)';
      expect(formatOk('a{background:$url   no-repeat;mask:url( "a;b.png" )}', 'css'), 'a {\n  background: $url no-repeat;\n  mask: url( "a;b.png" );\n}\n');
    });

    test(':is() / :not() / :where() 里的逗号不拆，属性选择器 [a="]"] 里的括号不当语法', () {
      expect(formatOk(':is(h1,h2)>a:not(.x , .y),[a="]"]  [b=\'{\'],a[href^="http://"]{top:0}', 'css'), ':is(h1,h2)>a:not(.x , .y), [a="]"] [b=\'{\'], a[href^="http://"] {\n  top: 0;\n}\n');
    });

    test('!important 不动', () {
      expect(formatOk('a{color:red!important;top:0 !important;left:0 ! important}', 'css'), 'a {\n  color: red!important;\n  top: 0 !important;\n  left: 0 ! important;\n}\n');
    });

    test('自定义属性的值原样保留（包括 { … } 这种怪值和空值）', () {
      expect(
        formatOk(':root{--main:#fff;--weird:{a:b;c:d};--empty:;--sp:  1px   2px ;--json:[1,{"a":"}"}]}', 'css'),
        ':root {\n  --main: #fff;\n  --weird: {a:b;c:d};\n  --empty:;\n  --sp: 1px   2px;\n  --json: [1,{"a":"}"}];\n}\n',
      );
    });

    test('选择器里的空白：有和没有不一样，只压缩不增删', () {
      expect(formatOk('a   b  >  c ~d+e   :hover , f:hover{top:0}', 'css'), 'a b > c ~d+e :hover, f:hover {\n  top: 0;\n}\n');
    });

    test('多行注释：文档式的对齐，别的里面不动', () {
      expect(formatOk('a{\n/**\n* x\n     * y\n*/\ntop:0;\n/* 图\n   +-+\n       |*/\n}', 'css'), 'a {\n  /**\n   * x\n   * y\n   */\n  top: 0;\n  /* 图\n   +-+\n       |*/\n}\n');
    });

    test('@font-face、@page、带反斜杠转义的选择器', () {
      expect(
        formatOk('@font-face{font-family:"A";src:url(a.woff2)format("woff2"),url(a.woff)}\n.sm\\:p-1,.a\\{b{top:0}', 'css'),
        '@font-face {\n  font-family: "A";\n  src: url(a.woff2)format("woff2"),url(a.woff);\n}\n\n.sm\\:p-1, .a\\{b {\n  top: 0;\n}\n',
      );
    });
  });

  group('铁律', () {
    const samples = <String>[
      '*{box-sizing:border-box}html,body{margin:0;padding:0}body{font-family:system-ui,-apple-system,"Segoe UI",sans-serif;line-height:1.6}',
      '.card{display:grid;grid-template-areas:"head head" "side main";gap:8px 16px}\n.card:hover::after{content:"\\201C";opacity:.8}',
      '@media screen{@media (min-width:1px){a{b:c}}}\n@layer base,components;\n@layer base{html{color:black}}',
      'a{background:linear-gradient(to right,rgba(0,0,0,.5) 0%,transparent 100%),url("a b.png")}',
      '/* 只有注释 */',
      '@import "a.css"',
    ];

    test('1 幂等、2 记号序列不变（一批正常样式）', () {
      for (final s in samples) {
        formatOk(s, 'css');
        formatOk(s.replaceAll('{', ' {\n\n').replaceAll(';', ' ;\n\t'), 'css');
      }
    });

    test('2 校验对不上就放弃：原样返回并说明', () {
      const src = 'a b{color:red}';
      for (final wrong in ['ab{color:red}', 'a b{color:blue}', 'a b{color:red;top:0}', 'a b{}', 'a{b{color:red}}', 'a b{color:re d}', 'a :b{color:red}']) {
        final r = checkedResult(wrong == 'a :b{color:red}' ? 'a:b{color:red}' : src, wrong, 'css');
        expect(r.problem, kFormatMismatch, reason: wrong);
        expect(r.changed, isFalse);
      }
      expect(checkedResult(src, 'a   b {\n color : red ;\n}', 'css').problem, isNull);
      // 字符串、注释、url 里的内容必须逐字相同
      expect(checkedResult('a{content:"a  b"}', 'a{content:"a b"}', 'css').problem, isNotNull);
      expect(checkedResult('a{}/* x  y */', 'a{}/* x y */', 'css').problem, isNotNull);
      expect(checkedResult('a{b:url(a  b)}', 'a{b:url(a b)}', 'css').problem, isNotNull);
      expect(checkedResult(':root{--x: a  b}', ':root{--x: a b}', 'css').problem, isNotNull);
    });

    test('3 解析不了：原样返回，说出第几行', () {
      formatFails('a {\n  color: red;\n\nb {\n  top: 0;\n}\n', 'css', hint: '第 1 行');
      formatFails('a {\n  top: 0;\n}\n}\n', 'css', hint: '第 4 行');
      formatFails('a {\n  content: "没结束;\n}\n', 'css', hint: '第 2 行');
      formatFails('a {}\n/* 没结束\nb {}\n', 'css', hint: '第 2 行');
      formatFails('a {\n  b: url(x;\n}\n', 'css', hint: '第 2 行');
      formatFails('a {\n  b: calc(1px + (2px);\n}\n', 'css', hint: '第 2 行');
      formatFails('a {\n  b: c);\n}\n', 'css', hint: '第 2 行');
      formatFails('color: red;\n', 'css', hint: '第 1 行');
      formatFails('a {}\n随便写的字\n', 'css', hint: '第 2 行');
    });

    test('4 任何输入都不抛异常', () {
      neverThrows('css', ['a{', '}', 'a{b:url(', '@', '@media', '--x:{', 'a{--x:{', '\\', 'a\\', 'url(', '[', 'a{b:c;}}', 'a { // 行注释\n b: c }']);
      final deep = '${'a{' * 5000}${'}' * 5000}';
      final r = formatCode(deep, 'css');
      expect(r.text, deep);
      expect(r.problem, contains('嵌套太深'));
    });

    test('4 CRLF 保持 CRLF，BOM 保留，末尾恰好一个换行', () {
      final r = formatCode('\uFEFFa{\r\ncolor:red}\r\n\r\n', 'css');
      expect(r.text, '\uFEFFa {\r\n  color: red;\r\n}\r\n');
      expect(formatCode(r.text, 'css').changed, isFalse);
      expect(formatCode('a{}', 'css').text, 'a {}\n');
      expect(formatCode('a {}\n\n\n', 'css').text, 'a {}\n');
      for (final blank in ['', '  \n\t\n']) {
        final b = formatCode(blank, 'css');
        expect(b.text, blank);
        expect(b.problem, isNull);
      }
    });

    test('随机扰动：缩进、行尾空白、空行数量、行的合并随便变，排出来的结果一模一样', () {
      final rnd = Random(11);
      for (final s in samples.take(4)) {
        final expected = formatOk(s, 'css');
        for (var round = 0; round < 60; round++) {
          var scrambled = scrambleLines(expected, rnd);
          // 把一部分换行去掉（{ 后、; 后、} 前都可以不换行）
          scrambled = scrambled.replaceAllMapped(RegExp(r'([{;])[ \t]*\n(?!\s*\n)'), (m) => rnd.nextBool() ? m.group(1)! : m.group(0)!);
          scrambled = scrambled.replaceAllMapped(RegExp(r'\n[ \t]*\}'), (m) => rnd.nextBool() ? '}' : m.group(0)!);
          expect(formatOk(scrambled, 'css'), expected, reason: '第 $round 轮：\n$scrambled');
        }
      }
    });
  });
}
