// JavaScript / JSX 格式化器：例子、四条铁律、刁钻输入。
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/format/format.dart';
import 'package:lopicode/format/js_lexer.dart';

import 'format_support.dart';

void main() {
  group('输入 → 期望输出', () {
    test('函数、if / else、空白规整', () {
      expect(
        formatOk('function foo(a,b){\nif(a){\nreturn a+b\n}else{\n      return [a , b]\n}\n}\n', 'js'),
        'function foo(a, b) {\n  if (a) {\n    return a+b\n  } else {\n    return [a, b]\n  }\n}\n',
      );
    });

    test('switch / case', () {
      expect(
        formatOk('switch(x){\ncase 1:\nfoo()\nbreak\n// 说明\ncase 2: {\nbar()\n}\ndefault:\nbaz()\n}\n', 'js'),
        'switch (x) {\n  case 1:\n    foo()\n    break\n  // 说明\n  case 2: {\n    bar()\n  }\n  default:\n    baz()\n}\n',
      );
    });

    test('对象字面量、数组、嵌套回调只缩进一层', () {
      expect(
        formatOk('const o={\na:1,\nb:[\n1,\n2\n],\nc(){\nreturn 1\n}\n}\nfoo(function(){\nbar()\n})\nlist.push({\nid:1\n},{\nid:2\n})\n', 'js'),
        'const o = {\n  a:1,\n  b:[\n    1,\n    2\n  ],\n  c() {\n    return 1\n  }\n}\nfoo(function() {\n  bar()\n})\nlist.push({\n  id:1\n}, {\n  id:2\n})\n',
      );
    });

    test('链式调用、三元、运算符结尾的续行多缩进一层', () {
      expect(
        formatOk('fetch(u)\n.then(r=>{\nreturn r.json()\n})\n.catch(e=>null)\nconst v=ok\n? 1\n: 2\nconst s =\n"a" +\n"b"\nconst f = () =>\ndone()\n', 'js'),
        'fetch(u)\n  .then(r => {\n    return r.json()\n  })\n  .catch(e => null)\nconst v = ok\n  ? 1\n  : 2\nconst s =\n  "a" +\n  "b"\nconst f = () =>\n  done()\n',
      );
    });

    test('不带花括号的 if / else / for', () {
      expect(formatOk('if (a)\nfoo()\nelse\nbar()\nfor (const x of xs)\ngo(x)\n', 'js'), 'if (a)\n  foo()\nelse\n  bar()\nfor (const x of xs)\n  go(x)\n');
    });

    test('多个空行压成一个、行尾空白去掉、开头的空行去掉', () {
      expect(formatOk('\n\n  let a = 1   \n\n\n\n\tlet b = 2\t\n', 'js'), 'let a = 1\n\nlet b = 2\n');
    });

    test('文档注释对齐，画了图的注释里面不动', () {
      expect(
        formatOk('function f(){\n/**\n* 说明\n   * @param a\n*/\nx()\n/* 图：\n   +--+\n      |  | */\n}\n', 'js'),
        'function f() {\n  /**\n   * 说明\n   * @param a\n   */\n  x()\n  /* 图：\n   +--+\n      |  | */\n}\n',
      );
    });

    test('箭头函数、默认参数、关键字后的空格', () {
      expect(
        formatOk('const f=(a=1,b)=>{\nwhile(a<b){a+=1}\ntry{g()}catch(e){h()}finally{k()}\n}\n', 'js'),
        'const f = (a = 1, b) => {\n  while (a<b) {a += 1}\n  try {g()} catch (e) {h()} finally {k()}\n}\n',
      );
    });

    test('方法名叫 catch / if 时不当关键字加空格', () {
      expect(formatOk('p.catch(e=>e)\no.if(1)\n', 'js'), 'p.catch(e => e)\no.if(1)\n');
    });

    test('JSX：只调整整行的缩进，行内内容不动', () {
      expect(
        formatOk(
          'const App=()=>{\nreturn (\n<div className="a" onClick={()=>{ go({a:1}) }}>\n  你好 {name} &gt; 世界\n      <b>x</b> y\n<img\nsrc="x"\n/>\n{list.map(i=><li key={i}>{i}</li>)}\n</div>\n)\n}\n',
          'jsx',
        ),
        'const App = () => {\n  return (\n    <div className="a" onClick={() => { go({a:1}) }}>\n      你好 {name} &gt; 世界\n      <b>x</b> y\n      <img\n        src="x"\n      />\n      {list.map(i =><li key={i}>{i}</li>)}\n    </div>\n  )\n}\n',
      );
    });

    test('JSX：片段、条件渲染、多行属性', () {
      expect(
        formatOk('function A(){\nreturn <>\n{ok && (\n<Foo\na="1"\nb={2}\n>\n文字\n</Foo>\n)}\n</>\n}\n', 'jsx'),
        'function A() {\n  return <>\n    {ok && (\n      <Foo\n        a="1"\n        b={2}\n      >\n        文字\n      </Foo>\n    )}\n  </>\n}\n',
      );
    });

    test('缩进宽度可以改', () {
      expect(formatOk('if(a){\nb()\n}\n', 'js', indent: 4), 'if (a) {\n    b()\n}\n');
    });

    test('已经整齐的：changed 为假', () {
      const src = 'const a = 1\nfunction f() {\n  return a\n}\n';
      final r = formatCode(src, 'js');
      expect(r.changed, isFalse);
      expect(r.text, src);
      expect(r.problem, isNull);
    });
  });

  group('刁钻输入', () {
    test('正则里带 / { 引号，和除法区分开', () {
      const src = 'const re=/a\\/b[/"\'{]{2}/g,q=a / b / c\nif (x) /}/.test(s)\nconst t = s.replace(/"/g, "\'").split(/[{}]/)\nlet d = (a+b) / 2 / c, e = arr[0] / 2\n';
      final out = formatOk(src, 'js');
      expect(out, contains('/a\\/b[/"\'{]{2}/g'));
      expect(out, contains('a / b / c'));
      expect(out, contains('/}/.test(s)'));
      expect(out, contains('/[{}]/'));
    });

    test('有除号的行只换缩进，行内一个空白都不动', () {
      expect(formatOk('function f(){\n   return a/b ,c=1\n}\n', 'js'), 'function f() {\n  return a/b ,c=1\n}\n');
    });

    test('模板字符串：嵌套、里面有 // 和 }、多行内容一个字节都不动', () {
      const tpl = '`a \${ b+`in \${c}  }` } // 不是注释\n      }  保持   \n\t原样 \${ {x:1}.x }`';
      final out = formatOk('function f(){\n      return $tpl\n}\n', 'js');
      expect(out, 'function f() {\n  return $tpl\n}\n');
    });

    test('字符串里有 </script>、引号转义、行尾反斜杠续行', () {
      const src = 'const a="</script>",b=\'it\\\'s {\',c="x\\\n   y"\n';
      final out = formatOk(src, 'js');
      expect(out, contains('"</script>"'));
      expect(out, contains("'it\\'s {'"));
      expect(out, contains('"x\\\n   y"'));
    });

    test('注释里有引号和括号', () {
      const src = 'function f(){\n// it\'s "ok" ({[\n/* don\'t } */ x()\nreturn 1 // 结尾 `\n}\n';
      expect(formatOk(src, 'js'), 'function f() {\n  // it\'s "ok" ({[\n  /* don\'t } */ x()\n  return 1 // 结尾 `\n}\n');
    });

    test('不写分号的风格：行不合并不拆分', () {
      const src = 'let a=1\nlet b=a\n;[1,2].forEach(n=>n)\n;(function(){})()\nconst c=a\n++b\nreturn_\nx\n';
      final out = formatOk(src, 'js');
      expect(out.split('\n').length, src.split('\n').length);
      expect(out, contains('\n;[1, 2].forEach(n => n)\n'));
      expect(out, contains('const c = a\n++b\n'));
    });

    test('挤在一行的多条语句不拆', () {
      expect(formatOk('a();b();if(x){y()}\n', 'js'), 'a(); b(); if (x) {y()}\n');
    });

    test('JSX：属性里的 {}、文本里的 { 和 >、字符串属性里的 >', () {
      const src = 'const x = <p style={{color:"red"}} title="a > b" data-x=\'{\'>\n{"{"} 1 > 0 且 a => b <b>{`}`}</b>\n</p>\n';
      final out = formatOk(src, 'jsx');
      expect(out, 'const x = <p style={{color:"red"}} title="a > b" data-x=\'{\'>\n  {"{"} 1 > 0 且 a => b <b>{`}`}</b>\n</p>\n');
    });

    test('JSX：行内文本两边的空格是内容，不能动', () {
      const src = 'const x = (\n<p>\n   a   <b>b</b>   c{d} e\n</p>\n)\n';
      expect(formatOk(src, 'jsx'), 'const x = (\n  <p>\n    a   <b>b</b>   c{d} e\n  </p>\n)\n');
    });

    test('比较运算符的 < 不当成 JSX', () {
      const src = 'if(a<b&&c>d){x=a<b?1:2}\nfor(let i=0;i<n;i++){}\n';
      expect(formatOk(src, 'js'), 'if (a<b && c>d) {x = a<b?1:2}\nfor (let i = 0; i<n; i++) {}\n');
    });

    test('各种数字、可选链、展开、私有字段、标签语句', () {
      const src = 'class A{\n#x=1e+5\nget y(){return this.#x?.z??.5}\n}\nouter:for(;;){break outer}\nconst n=[0x1F,1_000n,...rest],m=a?.5:1\n';
      final out = formatOk(src, 'js');
      expect(out, contains('#x = 1e+5'));
      expect(out, contains('this.#x?.z ?? .5'));
      expect(out, contains('for (;;) {break outer}'));
      expect(out, contains('m = a?.5:1'));
    });

    test('开头的 #! 行', () {
      expect(formatOk('#!/usr/bin/env node\n  run()\n', 'js'), '#!/usr/bin/env node\nrun()\n');
    });
  });

  group('铁律', () {
    const samples = <String>[
      'const a = [1, 2, 3].map((n) => n * 2)\n',
      'async function load(url) {\n  try {\n    const r = await fetch(url)\n    return await r.json()\n  } catch (e) {\n    console.error(e)\n  } finally {\n    done()\n  }\n}\n',
      'export default class Foo extends Bar {\n  static #n = 0\n  constructor(a) {\n    super(a)\n    this.a = a\n  }\n  get x() {\n    return `\${this.a}`\n  }\n}\n',
      'var x=function(){return{a:1,b:[1,2,{c:3}]}}();\n',
      'label: for (var i = 0; i < 3; i++) { if (i) continue label; else break; }\n',
      'const {a, b: {c}, ...d} = obj, [e, , f = 1] = arr\n',
      'x = a ? b : c ? d : e;\ny = typeof z === "undefined" ? void 0 : z;\n',
      'do { i-- } while (i > 0)\nwhile (true) { break }\n',
    ];

    test('1 幂等、2 记号序列不变（一批正常代码）', () {
      for (final s in samples) {
        formatOk(s, 'js');
        formatOk(s.replaceAll('\n', '\n\n\n   '), 'js');
      }
    });

    test('2 校验对不上就放弃：原样返回并说明', () {
      const src = 'let a = 1\n';
      final bad = checkedResult(src, 'let a = 2\n', 'js');
      expect(bad.problem, kFormatMismatch);
      expect(bad.problem, '格式化结果和原文对不上，已放弃，文件没有改动');
      expect(bad.text, src);
      expect(bad.changed, isFalse);
      // 合并了行、丢了注释、动了字符串里的空格，都算对不上
      expect(checkedResult('a\nb\n', 'a b\n', 'js').problem, isNotNull);
      expect(checkedResult('a // x\n', 'a\n', 'js').problem, isNotNull);
      expect(checkedResult('s = "a  b"\n', 's = "a b"\n', 'js').problem, isNotNull);
      expect(checkedResult('s = `a\n  b`\n', 's = `a\n b`\n', 'js').problem, isNotNull);
      expect(checkedResult('r = /a  b/\n', 'r = /a b/\n', 'js').problem, isNotNull);
      expect(checkedResult('a + +b\n', 'a ++b\n', 'js').problem, isNotNull);
      // 只动了记号之间的空白：放行
      expect(checkedResult('a=1\n', 'a = 1\n', 'js').problem, isNull);
    });

    test('3 解析不了：原样返回，说出第几行', () {
      formatFails('function f() {\n  if (a) {\n    b()\n}\n', 'js', hint: '第 1 行');
      formatFails('a()\nb(]\n', 'js', hint: '第 2 行');
      formatFails('a()\n}\n', 'js', hint: '第 2 行');
      formatFails('x = 1\ny = "abc\nz = 2\n', 'js', hint: '第 2 行');
      formatFails('x = 1\n\n/* 没结束\n', 'js', hint: '第 3 行');
      formatFails('x = `a\${b}\n', 'js', hint: '第 1 行');
      formatFails('x = `a\${b\n', 'js');
      formatFails('x = /abc\n', 'js', hint: '第 1 行');
      formatFails('const a = <div>\n<span>\n</div>\n', 'jsx', hint: '第 3 行');
      formatFails('const a = <div className=>x</div>\n', 'jsx');
    });

    test('4 任何输入都不抛异常', () {
      neverThrows('js', ['a = <', 'a = <b', 'a = <b c="', 'a = <b>{', 'x = 1 /', '\${', 'a\u2028b', '0x', '1e+', '?.', 'a\r\rb\r']);
      neverThrows('jsx', []);
    });

    test('4 CRLF 保持 CRLF，BOM 保留，末尾恰好一个换行', () {
      final r = formatCode('\uFEFFif(a){\r\nb()\r\n}\r\n\r\n\r\n', 'js');
      expect(r.text, '\uFEFFif (a) {\r\n  b()\r\n}\r\n');
      expect(formatCode(r.text, 'js').changed, isFalse);
      expect(formatCode('a()', 'js').text, 'a()\n');
      expect(formatCode('a()\n\n\n', 'js').text, 'a()\n');
      // 模板字符串里的换行跟着整个文件的换行风格走
      expect(formatCode('x=`a\r\nb`\r\n', 'js').text, 'x = `a\r\nb`\r\n');
      // 空文件、只有空白的文件：原样返回
      for (final blank in ['', '  \n\t\n', '\r\n']) {
        final b = formatCode(blank, 'js');
        expect(b.text, blank);
        expect(b.changed, isFalse);
        expect(b.problem, isNull);
      }
    });

    test('随机扰动：只改记号之间已有的空白，排出来的结果一模一样', () {
      final rnd = Random(20261124);
      const sources = <String>[
        'function foo(a, b) {\n  if (a) {\n    return [a, b]\n  } else {\n    switch (b) {\n      case 1:\n        foo()\n        break\n      default:\n        bar(function () {\n          return 1\n        })\n    }\n  }\n}\n',
        'const re = /a\\/b[/]{2}"\'/g, s = "x  y", t = \'a  b\'\npromise\n  .then((r) => {\n    return r // 注释  里的  空格\n  })\n  .catch(() => {})\n\nconst v = cond\n  ? a\n  : b\n',
        'export const App = () => {\n  const [n, setN] = useState(0)\n  return (\n    <div className="a" onClick={() => setN(n + 1)}>\n      <b>x</b>\n      <img\n        src="x"\n      />\n      {list.map((i) => <li key={i}>{i}</li>)}\n    </div>\n  )\n}\n',
        'let i = 0\ni++\n;[1, 2].forEach((n) => n)\nif (a)\n  foo()\nelse\n  bar()\n',
      ];
      for (final src in sources) {
        final language = src.contains('<div') ? 'jsx' : 'js';
        final expected = formatOk(src, language);
        for (var round = 0; round < 40; round++) {
          final tokens = JsLexer(src).run();
          final out = StringBuffer();
          for (var i = 0; i < tokens.length; i++) {
            final t = tokens[i];
            if (i > 0 && t.nl > 0) {
              // 换行处：空行数量随便变（原来有空行的保持至少一个），缩进随便变
              final extra = t.nl >= 2 ? 1 + rnd.nextInt(3) : 0;
              out.write('${' ' * rnd.nextInt(3)}${'\n' * (1 + extra)}${rnd.nextBool() ? ' ' * rnd.nextInt(10) : '\t' * rnd.nextInt(3)}');
            } else if (t.ws.isNotEmpty && !t.jsx && !tokens[i - 1].jsx && !t.isComment) {
              // 同一行里已有的空白：数量随便变（JSX 里的空白是内容，不动；注释前的对齐空白也不动）
              out.write(rnd.nextBool() ? ' ' * (1 + rnd.nextInt(4)) : '\t');
            } else {
              out.write(t.ws);
            }
            out.write(t.text);
          }
          out.write('\n' * rnd.nextInt(4));
          final scrambled = out.toString();
          expect(codeTokens(scrambled, language), codeTokens(src, language), reason: '扰动本身不该改记号');
          expect(formatOk(scrambled, language), expected, reason: '第 $round 轮：\n$scrambled');
        }
      }
    });
  });

  group('node --check（语法仍然合法）', () {
    const programs = <String>[
      'function foo(a,b){\nif(a){ return `line \${ a+`in \${b}` } // x\n   }  keep`\n}else{\n      switch(b){\ncase 1:\nfoo()\nbreak\ndefault:\n  bar(function(){\nreturn 1})\n}\n}\n}\n',
      'const re=/a\\/b[/]{2}"\'/g , x=1 / 2 / 3;\nconst s = "</script>" ,t=\'it\\\'s\'\nlet i=0\ni++\n;[1,2].forEach(n=>n)\nif (i)\ni--\nelse\ni++\n',
      'class A{\n#x=1e+5\nget y(){return this.#x?.z??.5}\nstatic async *g(){yield* [1,2]}\n}\nouter:for(;;){break outer}\nconst n=[0x1F,1_000n,...[1]],m=n?.5:1\n',
      'const p=Promise.resolve(1)\np\n.then(r=>{\nreturn r})\n    .catch(()=>{})\nconst v = p\n? 1\n: 2\nvar o={a:1,"b c":[1,2,{d:null}],e(){return this},get f(){return 1}}\n',
      'async function f(u){try{const r=await fetch(u);return await r.json()}catch(e){throw e}finally{}}\nfor(const k in {}){}\ndo{}while(false)\nvar g=function*(){},h=a=>b=>a+b,t=typeof /x/.test("x")\n',
    ];
    test('格式化前后都能通过语法检查', () {
      if (!hasNode) {
        markTestSkipped('这台机器上找不到 node，跳过语法检查');
        return;
      }
      for (final src in programs) {
        expect(nodeSyntaxOk(src), isTrue, reason: '样本本身应该合法：\n$src');
        final out = formatOk(src, 'js');
        expect(nodeSyntaxOk(out), isTrue, reason: '格式化后语法坏了：\n$out');
      }
    });
  });
}
