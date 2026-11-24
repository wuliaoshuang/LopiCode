// HTML 格式化器：例子、四条铁律、刁钻输入。
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/format/format.dart';

import 'format_support.dart';

void main() {
  group('输入 → 期望输出', () {
    test('挤成一行的页面按标签嵌套展开', () {
      expect(
        formatOk('<!DOCTYPE html><html lang="zh"><head><meta charset="utf-8"><title>标题</title><link rel="stylesheet" href="a.css"></head><body><div><h1>你好</h1><p>正文</p></div></body></html>', 'html'),
        '<!DOCTYPE html>\n<html lang="zh">\n  <head>\n    <meta charset="utf-8">\n    <title>标题</title>\n    <link rel="stylesheet" href="a.css">\n  </head>\n  <body>\n    <div>\n      <h1>你好</h1>\n      <p>正文</p>\n    </div>\n  </body>\n</html>\n',
      );
    });

    test('乱缩进的重新缩进', () {
      expect(formatOk('<ul>\n        <li>一</li>\n<li>二\n</li>\n   </ul>\n', 'html'), '<ul>\n  <li>一</li>\n  <li>二\n  </li>\n</ul>\n');
    });

    test('行内元素和短文本不拆行；原来有换行的地方保留换行', () {
      expect(
        formatOk('<div><p>你好 <b>粗体</b> 和 <a href="#">链接</a>，很长\n的文字接着 <i>写</i>。</p><ul><li>一</li><li><span>二</span> <em>2</em></li></ul></div>', 'html'),
        '<div>\n  <p>你好 <b>粗体</b> 和 <a href="#">链接</a>，很长\n    的文字接着 <i>写</i>。</p>\n  <ul>\n    <li>一</li>\n    <li><span>二</span> <em>2</em></li>\n  </ul>\n</div>\n',
      );
    });

    test('<br> <img> <input> <hr> 这些没有结束标签的', () {
      expect(
        formatOk('<div><p>a<br>b <img src="x.png"> <input type="text" disabled></p><hr><p>c<br/>d</p></div>', 'html'),
        '<div>\n  <p>a<br>b <img src="x.png"> <input type="text" disabled></p>\n  <hr>\n  <p>c<br/>d</p>\n</div>\n',
      );
    });

    test('<style> 用 CSS 格式化器、<script> 用 JS 格式化器，整体缩进', () {
      expect(
        formatOk('<head><style>\nbody{margin:0}\n</style><script>\nfunction f(){\nreturn 1\n}\n</script><script src="a.js">\n</script></head>', 'html'),
        '<head>\n  <style>\n    body {\n      margin: 0;\n    }\n  </style>\n  <script>\n    function f() {\n      return 1\n    }\n  </script>\n  <script src="a.js"></script>\n</head>\n',
      );
    });

    test('<script type="application/json"> 按 JSON 排；不认识的 type 原样保留', () {
      expect(
        formatOk('<div><script type="application/json">{"a":[1,2]}</script><script type="text/x-template">  <b>  x </b>\n</script></div>', 'html'),
        '<div>\n  <script type="application/json">\n    {\n      "a": [\n        1,\n        2\n      ]\n    }\n  </script>\n  <script type="text/x-template">  <b>  x </b>\n</script>\n</div>\n',
      );
    });

    test('注释和多行属性', () {
      expect(
        formatOk('<div>\n<!-- 说明 -->\n<input\ntype="text"\n      name="a"\n>\n<a href="#"\nclass="x">链接</a>\n</div>', 'html'),
        '<div>\n  <!-- 说明 -->\n  <input\n    type="text"\n    name="a"\n  >\n  <a href="#"\n    class="x">链接</a>\n</div>\n',
      );
    });

    test('空行最多留一行', () {
      expect(formatOk('<p>a</p>\n\n\n\n<p>b</p>\n\n<p>c</p>', 'html'), '<p>a</p>\n\n<p>b</p>\n\n<p>c</p>\n');
    });

    test('<select> 里的 <option> 一行一个，但 <select> 自己不从文字后面拆开', () {
      expect(
        formatOk('<label>选<select><option>a</option><option selected>b</option></select></label>', 'html'),
        '<label>选<select>\n  <option>a</option>\n  <option selected>b</option>\n</select></label>\n',
      );
    });

    test('缩进宽度可以改', () {
      expect(formatOk('<div><p>a</p></div>', 'html', indent: 4), '<div>\n    <p>a</p>\n</div>\n');
    });

    test('已经整齐的：changed 为假', () {
      const src = '<div>\n  <p>a</p>\n</div>\n';
      final r = formatCode(src, 'html');
      expect(r.changed, isFalse);
      expect(r.text, src);
    });
  });

  group('刁钻输入', () {
    test('属性值里的 > 和引号', () {
      const src = '<div title="a > b" data-x=\'<p class="q">\' onclick="if (a>b) go(\'x\')"><p>ok</p></div>';
      expect(formatOk(src, 'html'), '<div title="a > b" data-x=\'<p class="q">\' onclick="if (a>b) go(\'x\')">\n  <p>ok</p>\n</div>\n');
    });

    test('属性不重排、不改引号、不动属性值里的空白', () {
      const tag = '<input  value=\'a  "b"\'   class="x   y" data-z=1 CHECKED>';
      expect(formatOk('<div>$tag</div>', 'html'), '<div>$tag</div>\n');
    });

    test('内联 script 里的 </div> 字符串、a<b 比较、模板字符串的多行内容', () {
      const src = '<div><script>\nconst s = "</div>"; if(a<b){ go(`\n  第二行   不动\n第三行`) }\n</script></div>';
      expect(formatOk(src, 'html'), '<div>\n  <script>\n    const s = "</div>"; if (a<b) { go(`\n  第二行   不动\n第三行`) }\n  </script>\n</div>\n');
    });

    test('script 里的代码排不了：那一段原样保留，别的照常排，并在说明里讲清', () {
      const src = '<div><p>a</p>\n\n<script>var broken = (;\n   x</script><style>a{</style></div>';
      final r = formatCode(src, 'html');
      expect(r.problem, isNull);
      expect(r.text, '<div>\n  <p>a</p>\n\n  <script>var broken = (;\n   x</script>\n  <style>a{</style>\n</div>\n');
      expect(r.note, contains('第 3 行的 <script>'));
      expect(r.note, contains('第 4 行的 <style>'));
      formatOk(src, 'html');
    });

    test('<pre> 和 <textarea> 的内容一个字节都不动', () {
      const pre = '<pre class="c">\n  保持   这样\n\t<b>不动</b>   \n\n\n</pre>';
      const area = '<textarea>\n 原样  \n   </textarea>';
      final out = formatOk('<div>\n      $pre\n   <p>x $area y</p></div>', 'html');
      expect(out, '<div>\n  $pre\n  <p>x $area y</p>\n</div>\n');
    });

    test('<title> 里的 < 是文字', () {
      expect(formatOk('<head><title> a < b <b> c </title></head>', 'html'), '<head>\n  <title> a < b <b> c </title>\n</head>\n');
    });

    test('文字里的 < 和 {{ a < b }} 不当标签', () {
      expect(formatOk('<p>1 < 2, a<3</p><p>{{ a <b ? 1 : 2 }}</p>', 'html'), '<p>1 < 2, a<3</p>\n<p>{{ a <b ? 1 : 2 }}</p>\n');
    });

    test('行内元素之间：有空白和没空白不一样，一个都不增不减', () {
      const src = '<p><b>a</b><i>b</i> <span>c</span>\n<span>d</span><my-tag>e</my-tag><button>好</button></p>';
      expect(formatOk(src, 'html'), '<p><b>a</b><i>b</i> <span>c</span>\n  <span>d</span><my-tag>e</my-tag><button>好</button></p>\n');
    });

    test('不换行空格（U+00A0）是内容，行首行尾的也不能去掉', () {
      const src = '<p>\u00A0a\u00A0\n\u00A0b\u00A0</p>';
      expect(formatOk(src, 'html'), '<p>\u00A0a\u00A0\n  \u00A0b\u00A0</p>\n');
    });

    test('多行注释、条件注释、CDATA、<?xml?>', () {
      const src = '<?xml version="1.0"?><div><!-- 第一行\n      第二行 > < </div>\n-->\n<!--[if IE]><p>x</p><![endif]--><p>a</p></div>';
      expect(formatOk(src, 'html'), '<?xml version="1.0"?>\n<div>\n  <!-- 第一行\n      第二行 > < </div>\n-->\n  <!--[if IE]><p>x</p><![endif]-->\n  <p>a</p>\n</div>\n');
    });

    test('内联 SVG：自闭合标签、大小写混用的标签名', () {
      expect(
        formatOk('<div><svg viewBox="0 0 1 1"><linearGradient id="g"><stop offset="0"/></linearGradient>\n<path d="M0 0"/></svg></div>', 'html'),
        '<div><svg viewBox="0 0 1 1"><linearGradient id="g"><stop offset="0"/></linearGradient>\n  <path d="M0 0"/></svg></div>\n',
      );
    });

    test('标签名大小写不一致也能配上', () {
      expect(formatOk('<DIV><P>a</p></div>', 'html'), '<DIV>\n  <P>a</p>\n</div>\n');
    });
  });

  group('铁律', () {
    const samples = <String>[
      '<!doctype html>\n<html>\n<head>\n<meta charset="utf-8">\n<meta name="viewport" content="width=device-width, initial-scale=1">\n<title>我的小站</title>\n<link rel="stylesheet" href="style.css">\n</head>\n<body>\n<header><nav><a href="/">首页</a> | <a href="/about">关于</a></nav></header>\n<main>\n<h1>你好</h1>\n<p>这是 <strong>一段</strong> 文字。</p>\n<form action="/go" method="post"><label>名字 <input name="n"></label><button type="submit">提交</button></form>\n</main>\n<script src="app.js"></script>\n</body>\n</html>\n',
      '<table><thead><tr><th>A</th><th>B</th></tr></thead><tbody><tr><td>1</td><td><a href="#">2</a></td></tr></tbody></table>',
      '<section><article><h2>标题</h2><p>文字<br>换行</p><blockquote><p>引用</p></blockquote><dl><dt>词</dt><dd>义</dd></dl></article></section>',
      '<div><style>.a{color:red}@media (min-width:1px){.b{top:0}}</style><script>window.onload=function(){document.title="x"}</script></div>',
      '只有文字，没有标签',
    ];

    test('1 幂等、2 记号序列不变（一批正常页面）', () {
      for (final s in samples) {
        formatOk(s, 'html');
        formatOk(s.replaceAll('><', '>\n\n     <'), 'html');
      }
    });

    test('2 校验对不上就放弃：原样返回并说明', () {
      const src = '<p><b>a</b><i>b</i> c</p>';
      for (final wrong in [
        '<p><b>a</b> <i>b</i> c</p>',
        '<p><b>a</b><i>b</i>c</p>',
        '<p><b>a</b><i>b</i> d</p>',
        '<p><i>b</i><b>a</b> c</p>',
        '<p class="x"><b>a</b><i>b</i> c</p>',
        '<p><b>a</b><i>b</i> c',
      ]) {
        final r = checkedResult(src, wrong, 'html');
        expect(r.problem, kFormatMismatch, reason: wrong);
        expect(r.text, src);
      }
      // 块级标签边上的空白、行内已有空白换成换行：放行
      expect(checkedResult(src, '<p>\n<b>a</b><i>b</i>\nc\n</p>', 'html').problem, isNull);
      // 属性值、pre、注释、script 里的字符串必须逐字相同
      expect(checkedResult('<a title="x  y">a</a>', '<a title="x y">a</a>', 'html').problem, isNotNull);
      expect(checkedResult('<pre>a  b</pre>', '<pre>a b</pre>', 'html').problem, isNotNull);
      expect(checkedResult('<pre>a\n b</pre>', '<pre>a\n  b</pre>', 'html').problem, isNotNull);
      expect(checkedResult('<!-- a  b -->', '<!-- a b -->', 'html').problem, isNotNull);
      expect(checkedResult('<script>s="a  b"</script>', '<script>s="a b"</script>', 'html').problem, isNotNull);
      expect(checkedResult('<script>s = "a"</script>', '<script>\n  s="a"\n</script>', 'html').problem, isNull);
      expect(checkedResult('<textarea> a</textarea>', '<textarea>a</textarea>', 'html').problem, isNotNull);
    });

    test('3 标签不配平：原样返回，说出第几行', () {
      formatFails('<div>\n  <p>a</p>\n', 'html', hint: '第 1 行');
      formatFails('<div>\n<span>a</div>\n', 'html', hint: '第 2 行');
      formatFails('<p>a</p>\n</div>\n', 'html', hint: '第 2 行');
      formatFails('<div>\n<!-- 没结束\n</div>', 'html', hint: '第 2 行');
      formatFails('<div>\n<a href="x>链接</a>\n</div>', 'html', hint: '第 2 行');
      formatFails('<div>\n<p class="a"\n', 'html', hint: '第 2 行');
      formatFails('<div>\n<script>\nvar a = 1\n</div>', 'html', hint: '第 2 行');
      formatFails('<pre>\n没结束', 'html', hint: '第 1 行');
    });

    test('3 省略结束标签的写法（<p>、<li> 不闭合）：整体放弃并说明', () {
      expect(formatFails('<ul>\n<li>一\n<li>二\n</ul>\n', 'html', hint: '第 4 行'), contains('省略结束标签'));
      expect(formatFails('<div>\n<p>第一段\n<p>第二段\n</div>\n', 'html'), contains('省略结束标签'));
      expect(formatFails('<table><tr><td>1<td>2</table>', 'html'), contains('省略结束标签'));
      expect(formatFails('<html><body><p>a</p>', 'html'), contains('没有闭合'));
    });

    test('4 任何输入都不抛异常', () {
      neverThrows('html', [
        '<a',
        '<a b="',
        '<a b=\'',
        '</a',
        '<!',
        '<?',
        '<![CDATA[',
        '<script>',
        '<pre',
        '<style>a{',
        '{{',
        '<p>{{',
        '<a/><a/>',
        '< p >',
        '<1>',
        '</>',
        '<p></p></p>',
        '<script></script >',
        '<SCRIPT>a()</SCRIPT>',
      ]);
    });

    test('4 CRLF 保持 CRLF，BOM 保留，末尾恰好一个换行', () {
      final r = formatCode('\uFEFF<div>\r\n<p>a</p></div>\r\n\r\n', 'html');
      expect(r.text, '\uFEFF<div>\r\n  <p>a</p>\r\n</div>\r\n');
      expect(formatCode(r.text, 'html').changed, isFalse);
      expect(formatCode('<p>a</p>', 'html').text, '<p>a</p>\n');
      expect(formatCode('<p>a</p>\n\n\n', 'html').text, '<p>a</p>\n');
      // <pre> 里的换行跟着整个文件的换行风格走
      expect(formatCode('<pre>a\r\n b</pre>\r\n', 'html').text, '<pre>a\r\n b</pre>\r\n');
      for (final blank in ['', '  \n\t\n']) {
        final b = formatCode(blank, 'html');
        expect(b.text, blank);
        expect(b.problem, isNull);
      }
    });

    test('随机扰动：缩进、行尾空白、空行数量随便变，排出来的结果一模一样', () {
      final rnd = Random(5);
      for (final s in samples) {
        final expected = formatOk(s, 'html');
        for (var round = 0; round < 60; round++) {
          final scrambled = scrambleLines(expected, rnd);
          expect(formatOk(scrambled, 'html'), expected, reason: '第 $round 轮：\n$scrambled');
        }
      }
    });
  });
}
