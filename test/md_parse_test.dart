// 聊天正文 Markdown / HTML 解析（纯逻辑）：每种语法、嵌套、安全清单、流式逐字截断。
import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/markdown/md_chunker.dart';
import 'package:lopicode/markdown/md_document.dart';
import 'package:lopicode/markdown/md_html.dart';
import 'package:lopicode/markdown/md_nodes.dart';

List<MdBlock> parse(String text, {bool streaming = false}) => [for (final p in mdParseDocument(text, streaming: streaming).pieces) ...p.blocks];

/// 把节点树写成一行好比对的文字。
String dump(List<MdBlock> blocks) => blocks.map(_b).join(' ');
String _b(MdBlock b) => switch (b) {
  MdParagraph(:final inlines) => 'p(${_i(inlines)})',
  MdHeading(:final level, :final inlines) => 'h$level(${_i(inlines)})',
  MdCode(:final code, :final lang, :final closed, :final math) => '${math ? 'math' : 'code'}[$lang${closed ? '' : ',open'}](${code.replaceAll('\n', r'\n')})',
  MdQuote(:final children) => 'quote(${dump(children)})',
  MdList(:final items, :final ordered, :final start) =>
    '${ordered ? 'ol$start' : 'ul'}(${items.map((it) => '${it.checked == null
        ? ''
        : it.checked!
        ? '[x]'
        : '[ ]'}${dump(it.children)}').join(' | ')})',
  MdTable(:final header, :final rows, :final aligns) => 'table(${header.map(_i).join(',')} / ${rows.map((r) => r.map(_i).join(',')).join(' ; ')} / ${aligns.map((a) => a.name[0]).join()})',
  MdRule() => 'hr',
  MdDetails(:final summary, :final children, :final open) => 'details${open ? '+' : ''}(${_i(summary)} : ${dump(children)})',
};
String _i(List<MdInline> list) => list
    .map(
      (n) => switch (n) {
        MdText(:final text) => text.replaceAll('\n', r'\n'),
        MdStyled(:final style, :final children) => '${style.name}<${_i(children)}>',
        MdInlineCode(:final text, :final math) => math ? '\$$text\$' : '`$text`',
        MdLink(:final href, :final children) => 'a[$href]<${_i(children)}>',
        MdImage(:final src, :final alt) => 'img[$src|$alt]',
        MdBreak() => 'br',
      },
    )
    .join();

void main() {
  group('Markdown 语法', () {
    test('标题、粗体、斜体、删除线、行内代码', () {
      expect(dump(parse('# 一\n\n## 二\n\n这是**粗**、*斜*、~~删~~、`码`')), 'h1(一) h2(二) p(这是bold<粗>、italic<斜>、strike<删>、`码`)');
    });
    test('单个换行也换行；行尾两个空格是强制换行', () {
      expect(dump(parse('第一行\n第二行')), r'p(第一行\n第二行)');
      expect(dump(parse('a  \nb')), 'p(abrb)');
    });
    test('代码围栏：语言名、内容原样、里面的空行不切块', () {
      expect(dump(parse('```dart\nvoid main() {}\n\nprint(1);\n```')), r'code[dart](void main() {}\n\nprint(1);)');
      expect(dump(parse('~~~\nx\n~~~')), 'code[](x)');
    });
    test('没收尾的围栏当作开着的代码块', () {
      expect(dump(parse('好的：\n\n```js\nlet a = 1;')), 'p(好的：) code[js,open](let a = 1;)');
    });
    test('无序 / 有序 / 嵌套列表', () {
      expect(dump(parse('- a\n- b\n  - c\n  - d\n- e')), 'ul(p(a) | p(b) ul(p(c) | p(d)) | p(e))');
      expect(dump(parse('3. a\n4. b')), 'ol3(p(a) | p(b))');
    });
    test('松散列表（项之间有空行）编号不断', () {
      expect(dump(parse('1. a\n\n2. b\n\n3. c')), 'ol1(p(a) | p(b) | p(c))');
    });
    test('任务列表', () {
      expect(dump(parse('- [x] 做完\n- [ ] 没做\n- 普通')), 'ul([x]p(做完) | [ ]p(没做) | p(普通))');
    });
    test('引用（里面可以再套列表）', () {
      expect(dump(parse('> 引用\n> - 项')), 'quote(p(引用) ul(p(项)))');
    });
    test('表格：对齐、单元格里的行内语法', () {
      expect(dump(parse('| 名 | 值 | 备注 |\n| :-- | :-: | --: |\n| a | **1** | x |\n| b | 2 | y |')), 'table(名,值,备注 / a,bold<1>,x ; b,2,y / lcr)');
    });
    test('链接、自动链接、图片', () {
      expect(dump(parse('[官网](https://a.com/x?y=1) 和 https://b.com 和 ![图](img/a.png)')), 'p(a[https://a.com/x?y=1]<官网> 和 a[https://b.com]<https://b.com> 和 img[img/a.png|图])');
    });
    test('引用式链接：定义在别的块里也认', () {
      expect(dump(parse('看 [这里][1]\n\n另一段\n\n[1]: https://a.com')), contains('a[https://a.com]<这里>'));
    });
    test('分隔线；--- 不把上一行变成标题', () {
      expect(dump(parse('上\n\n---\n\n下')), 'p(上) hr p(下)');
      expect(dump(parse('上\n---\n下')), isNot(contains('h2')));
    });
    test('缩进 4 格不是代码块', () {
      expect(dump(parse('    只是缩进的一句话')), 'p(    只是缩进的一句话)');
    });
    test('公式：按代码样式原样留着', () {
      expect(dump(parse(r'质能 $E=mc^2$ 方程')), r'p(质能 $E=mc^2$ 方程)');
      expect(dump(parse(r'花了 $5 和 $10')), r'p(花了 $5 和 $10)');
      expect(dump(parse('\$\$\na^2+b^2\n\$\$')), 'math[](a^2+b^2)');
    });
    test('转义的记号按字面显示', () {
      expect(dump(parse(r'\*不是斜体\* 和 \<b>')), 'p(*不是斜体* 和 <b>)');
    });
    test('列表里缩进着的围栏，中间有空行也不断', () {
      expect(dump(parse('1. 步骤\n\n   ```sh\n   a\n\n   b\n   ```\n2. 下一步')), r'ol1(p(步骤) code[sh](a\n\nb) | p(下一步))');
    });
  });

  group('HTML 安全清单', () {
    test('行内排版标签', () {
      expect(
        dump(parse('<b>粗</b><i>斜</i><u>线</u><s>删</s><kbd>Ctrl</kbd> H<sub>2</sub>O x<sup>2</sup> <mark>亮</mark><br>下一行')),
        'p(bold<粗>italic<斜>underline<线>strike<删>kbd<Ctrl> Hsub<2>O xsup<2> mark<亮>br下一行)',
      );
    });
    test('标签里可以套 Markdown，Markdown 里可以套标签', () {
      expect(dump(parse('<b>a *b*</b> **<u>c</u>**')), 'p(bold<a italic<b>> bold<underline<c>>)');
    });
    test('a / img 只留 href / src / alt，其余属性丢掉', () {
      expect(dump(parse('<a href="https://a.com" onclick="steal()" style="x">点</a> <img src="a.png" alt="图" onerror="x()">')), 'p(a[https://a.com]<点> img[a.png|图])');
    });
    test('标签属性里的网址、星号不被当成 Markdown', () {
      expect(dump(parse('<a href="https://a.com/*x*_y_">t</a>')), 'p(a[https://a.com/*x*_y_]<t>)');
    });
    test('script / style / iframe / 不认识的标签：当文字，不变成界面', () {
      final d = dump(parse('前 <script>alert(1)</script> <iframe src="https://x"></iframe> <foo>y</foo> 后'));
      expect(d, 'p(前 <script>alert(1)</script> <iframe src="https://x"></iframe> <foo>y</foo> 后)');
    });
    test('没有对应开标签的关标签当文字；没收尾的开标签算到段尾', () {
      expect(dump(parse('a</b> <i>斜')), 'p(a</b> italic<斜>)');
    });
    test('注释不显示', () {
      expect(dump(parse('a<!-- 藏 -->b')), 'p(ab)');
    });
    test('实体', () {
      expect(dump(parse('&lt;b&gt; &amp; &#65; &nbsp;')).contains('<b> & A'), isTrue);
      expect(decodeHtmlEntities('&#0; &#xD800; &nope;'), '&#0; &#xD800; &nope;');
    });
    test('details / summary：里面的 Markdown 照常解析', () {
      expect(dump(parse('<details>\n<summary>点开 <b>看</b></summary>\n\n- 一\n- 二\n\n</details>\n\n后面')), 'details(点开 bold<看> : ul(p(一) | p(二))) p(后面)');
      expect(dump(parse('<details open><summary>s</summary>x</details>')), 'details+(s : p(x))');
    });
    test('HTML 表格', () {
      expect(dump(parse('<table>\n<tr><th>a</th><th align="right">b</th></tr>\n<tr><td>1</td><td><b>2</b></td></tr>\n</table>')), 'table(a,b / 1,bold<2> / lr)');
    });
    test('HTML 列表、引用、标题、pre、hr', () {
      expect(dump(parse('<ul><li>一</li><li>二</ul>')), 'ul(p(一) | p(二))');
      expect(dump(parse('<h2>题 <i>目</i></h2>')), 'h2(题 italic<目>)');
      expect(dump(parse('<pre><code>a &lt; b\n  c</code></pre>')), r'code[](a < b\n  c)');
      expect(dump(parse('<p align="center">居中的 <b>字</b></p>')), 'p(居中的 bold<字>)');
    });
    test('畸形 / 嵌套很深的 HTML 不崩', () {
      for (final s in [
        '<',
        '<b',
        '<b <i>',
        '</',
        '<<<>>>',
        '<a href="x',
        '<table><tr><td>',
        '<details><details><details>',
        '${'<div>' * 200}x',
        '<p><p><p></table></b>',
        '<img src=>',
        '<a href=>x</a>',
        '&#99999999;',
        '<!-- 没收尾',
      ]) {
        expect(() => parse(s), returnsNormally, reason: s);
        expect(() => parse(s, streaming: true), returnsNormally, reason: s);
      }
    });
    test('整条就是一份网页：当成 html 代码块', () {
      expect(dump(parse('<!DOCTYPE html>\n<html><body><script>x()</script></body></html>')), startsWith('code[html](<!DOCTYPE html>'));
      expect(dump(parse('<html>\n<body>', streaming: true)), startsWith('code[html,open]'));
    });
  });

  group('切块与流式', () {
    const all =
        '# 标题\n\n一段**粗体**和[链接](https://a.com)。\n第二行\n\n- 列表一\n- 列表二\n  - 嵌套\n\n1. 有序\n\n2. 松散\n\n> 引用\n\n| a | b |\n| --- | --- |\n| 1 | 2 |\n\n```dart\nvoid main() {\n\n  print("hi");\n}\n```\n\n<details>\n<summary>更多</summary>\n\n里面\n\n</details>\n\n---\n\n最后一段 `code` ~~删~~ <b>粗</b> \$x\$\n';
    test('逐字符截断：不抛异常；说完的块沿用同一个对象', () {
      MdDocument? prev;
      for (var n = 0; n <= all.length; n++) {
        final doc = mdParseDocument(all.substring(0, n), streaming: true, previous: prev);
        if (prev != null) {
          // 倒数第三块往前：原文不会再变，必须是同一个对象（界面靠这个不重排）
          for (var i = 0; i < prev.pieces.length - 2 && i < doc.pieces.length; i++) {
            expect(identical(doc.pieces[i], prev.pieces[i]), isTrue, reason: '截到 $n 时第 $i 块被重新解析了');
          }
        }
        prev = doc;
      }
      // 流式走完和一次解析完，结果一样
      final done = mdParseDocument(all, previous: prev);
      expect(dump([for (final p in done.pieces) ...p.blocks]), dump(parse(all)));
    });
    test('流式末尾的半截记号行先不显示', () {
      expect(dump(parse('一段\n-', streaming: true)), 'p(一段)');
      expect(dump(parse('一段\n``', streaming: true)), 'p(一段)');
      expect(dump(parse('一段\n|', streaming: true)), 'p(一段)');
      expect(dump(parse('一段\n1.', streaming: true)), 'p(一段)');
      expect(dump(parse('-', streaming: true)), isNot(''));
      // 说完了就照实显示
      expect(dump(parse('一段\n-')), isNot('p(一段)'));
    });
    test('半截的强调 / 链接 / 表格先按文字显示', () {
      expect(dump(parse('这是**半截', streaming: true)), 'p(这是**半截)');
      expect(dump(parse('看[文字](https://a.co', streaming: true)), contains('[文字]('));
      expect(dump(parse('| a | b |\n| --', streaming: true)), startsWith('p('));
    });
    test('流式里嵌在列表中的围栏没收尾：标成开着', () {
      expect(dump(parse('- 项\n  ```js\n  let a', streaming: true)), contains('code[js,open]'));
    });
    test('超过上限的消息不解析', () {
      final doc = mdParseDocument('**a** ' * (kMdMaxChars ~/ 6 + 10));
      expect(doc.plain, isTrue);
    });
    test('缓存：同一段原文只解析一次，超量丢最旧的', () {
      mdDebugClearCache();
      final a = mdParseCached('# a');
      expect(identical(mdParseCached('# a'), a), isTrue);
      // 超过解析上限的长文不解析，但一样进缓存：用它把缓存撑满
      for (var i = 0; i < 30; i++) {
        mdParseCached('$i ${'字' * kMdMaxChars}');
      }
      expect(mdDebugCacheSize, lessThanOrEqualTo(kMdCacheMaxChars ~/ kMdMaxChars + 1));
      mdDebugClearCache();
    });
    test('很长的不断开的字母数字（base64 之类）不会把解析拖死：那一块按纯文字', () {
      final sw = Stopwatch()..start();
      final d = dump(parse('前面 **粗**\n\n${'A1' * 60000}\n\n后面 *斜*'));
      sw.stop();
      expect(d, startsWith('p(前面 bold<粗>) p(A1A1'));
      expect(d, endsWith('p(后面 italic<斜>)'));
      expect(sw.elapsed, lessThan(const Duration(seconds: 10)));
    });
    test('消息里的 data: 图片（很长）照样认成图片', () {
      final uri = 'data:image/png;base64,${'iVBORw0KGgo' * 400}';
      final blocks = parse('![点]($uri) 和 <img src="$uri">');
      final imgs = (blocks.single as MdParagraph).inlines.whereType<MdImage>().toList();
      expect(imgs.length, 2);
      expect(imgs.every((i) => i.src == uri), isTrue);
    });
    test('切块：HTML 块里的空行不切；围栏里的空行不切', () {
      expect(mdSplitChunks('<details>\n\na\n\n</details>\n\nb').map((c) => c.kind.name).toList(), ['html', 'markdown']);
      expect(mdSplitChunks('```\na\n\nb\n```\n\nc').length, 2);
    });
    test('几万字的消息解析得动（冒烟）', () {
      final big = List.generate(400, (i) => '## 第 $i 节\n\n这是**第 $i 段**，有 `代码` 和 [链接](https://a.com/$i)。\n\n- 一\n- 二\n\n```js\nlet x$i = $i;\n```\n').join('\n');
      expect(big.length, greaterThan(30000));
      final sw = Stopwatch()..start();
      final doc = mdParseDocument(big);
      sw.stop();
      expect(doc.pieces.length, greaterThan(1000));
      expect(sw.elapsed, lessThan(const Duration(seconds: 20)));
    });
  });
}
