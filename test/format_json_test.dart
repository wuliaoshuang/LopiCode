// JSON 格式化器：例子、四条铁律、刁钻输入。
import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/format/format.dart';

import 'format_support.dart';

void main() {
  group('输入 → 期望输出', () {
    test('对象、数组、嵌套', () {
      expect(
        formatOk('{"a":1,"b":[1,2,{"c":null}],"d":{"e":true,"f":false}}', 'json'),
        '{\n  "a": 1,\n  "b": [\n    1,\n    2,\n    {\n      "c": null\n    }\n  ],\n  "d": {\n    "e": true,\n    "f": false\n  }\n}\n',
      );
    });

    test('空对象、空数组写在一行', () {
      expect(formatOk('{"a":{ },"b":[\n],"c":[[],{}]}', 'json'), '{\n  "a": {},\n  "b": [],\n  "c": [\n    [],\n    {}\n  ]\n}\n');
      expect(formatOk(' [ ] ', 'json'), '[]\n');
    });

    test('最外层是单个值也行', () {
      expect(formatOk('  "x"  ', 'json'), '"x"\n');
      expect(formatOk('\n-1.5e3\n', 'json'), '-1.5e3\n');
      expect(formatOk('null', 'json'), 'null\n');
    });

    test('缩进宽度可以改', () {
      expect(formatOk('{"a":[1]}', 'json', indent: 4), '{\n    "a": [\n        1\n    ]\n}\n');
    });

    test('已经整齐的：changed 为假', () {
      const src = '{\n  "a": 1\n}\n';
      final r = formatCode(src, 'json');
      expect(r.changed, isFalse);
      expect(r.text, src);
    });
  });

  group('刁钻输入', () {
    test('键的顺序、重复的键原样保留', () {
      expect(formatOk('{"z":1,"a":2,"z":3}', 'json'), '{\n  "z": 1,\n  "a": 2,\n  "z": 3\n}\n');
    });

    test('数字原文照抄：1.0 不变成 1，大整数不丢精度，指数写法不改', () {
      final out = formatOk('{"a":1.0,"big":123456789012345678901234567890,"e":1E+5,"z":-0.0,"s":0.10}', 'json');
      expect(out, contains('"a": 1.0,'));
      expect(out, contains('"big": 123456789012345678901234567890,'));
      expect(out, contains('"e": 1E+5,'));
      expect(out, contains('"z": -0.0,'));
      expect(out, contains('"s": 0.10\n'));
    });

    test('字符串里的转义、括号、逗号、冒号、空格原样保留', () {
      const s = r'"x\n\u00e9 \" \\ { } [ ] , :   /* 不是注释 */ // 也不是"';
      final out = formatOk('{"k":$s,$s:1}', 'json');
      expect(out, '{\n  "k": $s,\n  $s: 1\n}\n');
    });

    test('中文、表情符号', () {
      expect(formatOk('{"名字":"霜霜 😀"}', 'json'), '{\n  "名字": "霜霜 😀"\n}\n');
    });
  });

  group('铁律', () {
    test('1 幂等、2 记号序列不变，并且解析出来的值和原来一样', () {
      const samples = [
        '{"name":"lopi","version":"1.0.0","scripts":{"dev":"vite","build":"vite build"},"dependencies":{},"files":["a","b"]}',
        '[{"id":1,"tags":[],"meta":{"a":[1,[2,[3,[4]]]]}},{"id":2,"x":1.50,"y":-2e-3}]',
        '{"a"\n:\n1\n,\n"b"\n:\n[\n]\n}',
      ];
      for (final s in samples) {
        final out = formatOk(s, 'json');
        expect(jsonEncode(jsonDecode(out)), jsonEncode(jsonDecode(s)));
      }
    });

    test('2 校验对不上就放弃：原样返回并说明', () {
      const src = '{"a":1.0}';
      for (final wrong in ['{"a":1}', '{"a":1.0,"b":2}', '{"A":1.0}', '[1.0]', '']) {
        final r = checkedResult(src, wrong, 'json');
        expect(r.problem, kFormatMismatch);
        expect(r.text, src);
        expect(r.changed, isFalse);
      }
      expect(checkedResult(src, '{ "a" : 1.0 }', 'json').problem, isNull);
    });

    test('3 不合法的 JSON：原样返回，说出第几行和毛病', () {
      formatFails('{\n  "a": 1,\n}', 'json', hint: '第 3 行');
      expect(formatFails('{"a":1,}', 'json'), contains('多了一个逗号'));
      expect(formatFails('[1,2,]', 'json'), contains('逗号'));
      expect(formatFails('{\n  // 说明\n  "a": 1\n}', 'json', hint: '第 2 行'), contains('注释'));
      expect(formatFails('{"a":1 /* x */}', 'json'), contains('注释'));
      expect(formatFails("{'a':1}", 'json'), contains('单引号'));
      expect(formatFails('{a:1}', 'json'), contains('不带引号'));
      formatFails('{"a":1\n"b":2}', 'json', hint: '第 2 行');
      formatFails('{"a":1', 'json', hint: '第 1 行');
      formatFails('[1,\n[2,\n3]', 'json', hint: '第 1 行');
      formatFails('[1}', 'json', hint: '对不上');
      formatFails('{"a":"没结束}', 'json', hint: '引号');
      formatFails('{"a":"换\n行"}', 'json');
      formatFails('{"a":01}', 'json', hint: '数字');
      formatFails('{"a":1.}', 'json', hint: '数字');
      formatFails('{"a":+1}', 'json');
      formatFails('{"a":"\\x"}', 'json', hint: '转义');
      formatFails('{"a":"\\u12"}', 'json', hint: '转义');
      formatFails('{"a" 1}', 'json', hint: '冒号');
      formatFails('{} {}', 'json', hint: '多出');
      formatFails('{"a":undefined}', 'json');
      formatFails('{"a":NaN}', 'json');
      formatFails(',', 'json');
      formatFails('{"a":}', 'json');
    });

    test('4 任何输入都不抛异常；嵌套几万层也不崩', () {
      neverThrows('json', ['{"a":', '[', '"\\', '-', 'tru', '{"a":1}}']);
      final deep = '${'[' * 800}${']' * 800}';
      final r = formatCode(deep, 'json');
      expect(r.problem, isNull);
      expect(formatCode(r.text, 'json').text, r.text);
      final tooDeep = '${'[' * 30000}${']' * 30000}';
      final t = formatCode(tooDeep, 'json');
      expect(t.text, tooDeep);
      expect(t.problem, contains('嵌套太深'));
    });

    test('4 CRLF 保持 CRLF，BOM 保留，末尾恰好一个换行', () {
      final r = formatCode('\uFEFF{"a":\r\n1}\r\n\r\n', 'json');
      expect(r.text, '\uFEFF{\r\n  "a": 1\r\n}\r\n');
      expect(formatCode(r.text, 'json').changed, isFalse);
      expect(formatCode('{}', 'json').text, '{}\n');
      expect(formatCode('{}\n\n\n', 'json').text, '{}\n');
      for (final blank in ['', '  \n\t\n']) {
        final b = formatCode(blank, 'json');
        expect(b.text, blank);
        expect(b.problem, isNull);
      }
    });

    test('随机扰动：记号之间随便加减空白和换行，排出来的结果一模一样', () {
      final rnd = Random(7);
      const src = '{"a":1.0,"s":"x , y : { } [ ]  \\" z","list":[1,[2,{"k":null}],true,false,[],{}],"o":{"p":{"q":-1e-9}}}';
      final expected = formatOk(src, 'json');
      for (var round = 0; round < 200; round++) {
        final out = StringBuffer();
        var inString = false;
        String ws() => [' ', '\n', '\t', '\r\n', ''][rnd.nextInt(5)] * rnd.nextInt(3);
        for (var i = 0; i < src.length; i++) {
          final c = src[i];
          if (inString) {
            out.write(c);
            if (c == r'\') {
              out.write(src[++i]);
            } else if (c == '"') {
              inString = false;
            }
          } else if (c == '"') {
            inString = true;
            out.write(c);
          } else if ('{}[],:'.contains(c)) {
            out.write('${ws()}$c${ws()}');
          } else {
            out.write(c);
          }
        }
        final scrambled = out.toString();
        final r = formatCode(scrambled, 'json');
        expect(r.problem, isNull);
        expect(r.text.replaceAll('\r\n', '\n'), expected, reason: scrambled);
      }
    });
  });

  test('formatLanguageFor 按扩展名认语言', () {
    expect(formatLanguageFor('a/b/package.json'), 'json');
    expect(formatLanguageFor('x.CSS'), 'css');
    expect(formatLanguageFor('index.html'), 'html');
    expect(formatLanguageFor('index.htm'), 'html');
    expect(formatLanguageFor('a.js'), 'js');
    expect(formatLanguageFor('a.mjs'), 'js');
    expect(formatLanguageFor('a.jsx'), 'js');
    expect(formatLanguageFor('App.vue'), 'vue');
    for (final no in ['a.ts', 'a.tsx', 'a.scss', 'a.less', 'a.md', 'a.dart', 'Makefile', 'a.json.bak', '.json/readme', 'a.svg', 'a.xml', '']) {
      expect(formatLanguageFor(no), isNull, reason: no);
    }
  });

  test('不支持的语言：原样返回并说明，不抛', () {
    final r = formatCode('a: 1', 'yaml');
    expect(r.text, 'a: 1');
    expect(r.changed, isFalse);
    expect(r.problem, contains('不支持'));
    expect(codeTokens('a', 'yaml'), isNull);
    // 语言名大小写、别名
    expect(formatCode('{}', 'JSON').problem, isNull);
    expect(formatCode('a()', 'javascript').problem, isNull);
    expect(formatCode('a()', 'mjs').problem, isNull);
    expect(formatCode('<p>a</p>', 'htm').problem, isNull);
  });

  test('太大的文件、带 NUL 的文件不格式化', () {
    final big = '[${'1,' * (kFormatMaxChars ~/ 2)}1]';
    expect(formatCode(big, 'json').problem, contains('太大'));
    expect(formatCode('{"a":"\u0000"}', 'json').problem, contains('不是文本'));
  });
}
