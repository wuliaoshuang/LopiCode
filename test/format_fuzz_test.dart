// 乱改一气的输入：随机删字符、插字符、调换片段。不管改成什么样，格式化器都不许抛异常；
// 排成功了就必须幂等、记号序列不变；排不成就必须原样返回。
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/format/format.dart';

const Map<String, List<String>> _seeds = {
  'json': ['{"a":1.0,"s":"x , y : { } [ ] \\" z","list":[1,[2,{"k":null}],true,false,[],{}],"o":{"p":{"q":-1e-9}}}'],
  'css': [
    '@import "a.css";\n/* 说明 */\n:root{--x:{a:b};--y: 1px}\na,b>c:is(h1,h2)::after{color:red!important;background:url(data:image/svg+xml;x,{}) no-repeat;content:"}"; /* 尾 */\nmargin:0 auto}\n@media (min-width:1px){.x{top:0}\n\n.y{transition:a .2s,\n b .3s}}\n[a="]"]{}\n',
  ],
  'js': [
    'function foo(a,b){\nif(a){ return `l \${ a+`in \${b}` } // x\n } k`\n}else{\nswitch(b){\ncase 1:\nfoo()\nbreak\ndefault:\nbar(function(){\nreturn 1})\n}\n}\n}\nconst re=/a\\/b[/]{2}"\'/g , x=a / b / c;\n/** d\n * e */\npromise\n.then(r=>{\nreturn r})\n;[1,2].forEach(n=>n)\nif (a)\nfoo()\nelse\nbar()\n',
    'const App=()=>{\nreturn (\n<div className="a" onClick={()=>{ go({a:1}) }}>\n  你好 {name} &gt; 世界 }\n      <b>x</b> y\n<img\nsrc="x"\n/>\n{list.map(i=><li key={i}>{i}</li>)}\n<>\n{a ? <A b="c" {...d}/> : null}\n</>\n</div>\n)\n}\n',
  ],
  'html': [
    '<!DOCTYPE html><html><head><meta charset="utf-8"><title> A <b> t </title>\n<style>\nbody{margin:0}\n</style></head>\n<body class="a  b"\n   data-x="1 > 2">\n<!-- a\n  c -->\n<div><p>Hi <b>b</b> and <a href="#">l</a>, long\ntext <i>h</i>.</p><ul><li>one</li><li><span>two</span> <em>2</em></li></ul></div>\n<pre>\n  keep   <b>x</b>\n</pre>\n<p>a<br>b <img src="x" alt=">"> {{ a < b }}</p>\n<textarea>\n raw  </textarea>\n<label>P<select><option>a</option></select></label>\n<script>\n  const s = "</div>"; if(a<b){ go(`\n  t`) }\n</script>\n</body></html>\n',
  ],
  'vue': [
    '<script setup>\nimport {ref} from "vue"\nconst n=ref(0)\n</script>\n<!-- c -->\n<template>\n<div :class="{a:n>1}" @click="n++"><template v-if="n > 1"><span>{{ n < 3 ? 1 : 2 }}</span></template>\n<p v-else>none</p></div>\n</template>\n<style scoped>\n.a{color:red}\n</style>\n<style lang="scss">\n.a{ .b{c:d} }\n</style>\n',
  ],
};

const String _alphabet = ' \n\t{}[]()<>/\\"\'`;:,.=+-*!?\$#@&|ax1_%';

String _mutate(String s, Random rnd) {
  var out = s;
  final times = 1 + rnd.nextInt(4);
  for (var k = 0; k < times && out.isNotEmpty; k++) {
    final at = rnd.nextInt(out.length);
    switch (rnd.nextInt(5)) {
      case 0: // 删一个字符
        out = out.substring(0, at) + out.substring(at + 1);
      case 1: // 插一个字符
        out = out.substring(0, at) + _alphabet[rnd.nextInt(_alphabet.length)] + out.substring(at);
      case 2: // 删一段
        final end = min(out.length, at + rnd.nextInt(12));
        out = out.substring(0, at) + out.substring(end);
      case 3: // 把一段重复一遍
        final end = min(out.length, at + rnd.nextInt(20));
        out = out.substring(0, end) + out.substring(at, end) + out.substring(end);
      default: // 截断
        if (rnd.nextInt(4) == 0) out = out.substring(0, at);
    }
  }
  return out;
}

/// 想多跑几轮找毛病时：LOPI_FUZZ_ROUNDS=40000 LOPI_FUZZ_SEED=7 flutter test --no-pub test/format_fuzz_test.dart
final int _rounds = int.tryParse(Platform.environment['LOPI_FUZZ_ROUNDS'] ?? '') ?? 4000;
final int _seed = int.tryParse(Platform.environment['LOPI_FUZZ_SEED'] ?? '') ?? 0x5EED;

void main() {
  for (final entry in _seeds.entries) {
    final language = entry.key;
    test('$language：乱改 $_rounds 次，不抛、成功就幂等且记号不变、失败就原样返回', () {
      final rnd = Random(language.length * 31 + _seed);
      var ok = 0;
      var failed = 0;
      for (final seed in entry.value) {
        expect(formatCode(seed, language).problem, isNull, reason: '种子本身应该能排');
        for (var round = 0; round < _rounds ~/ entry.value.length; round++) {
          final input = _mutate(seed, rnd);
          final FormatResult r;
          try {
            r = formatCode(input, language);
          } on Object catch (e) {
            fail('抛了异常 $e，输入：\n$input');
          }
          if (r.problem != null) {
            // “对不上”是最后一道保险：真走到它说明排版那一步出了错，要当 bug 查，不能靠保险兜着
            expect(r.problem, isNot(kFormatMismatch), reason: '保险被触发了，输入：\n$input');
            expect(r.problem, isNot(contains('意外')), reason: '格式化器内部出错了，输入：\n$input');
            failed++;
            expect(r.text, input, reason: '失败时必须原样返回');
            expect(r.changed, isFalse);
            continue;
          }
          ok++;
          final again = formatCode(r.text, language);
          expect(again.problem, isNull, reason: '排好的结果自己排不了了，输入：\n$input');
          expect(again.text, r.text, reason: '不幂等，输入：\n$input');
          if (input.trim().isNotEmpty) {
            expect(codeTokens(r.text, language), codeTokens(input, language), reason: '记号序列变了，输入：\n$input');
          }
        }
      }
      // 两条路都得真的走到过，不然这个测试什么也没测
      expect(ok, greaterThan(100), reason: '成功 $ok 次、失败 $failed 次');
      expect(failed, greaterThan(100), reason: '成功 $ok 次、失败 $failed 次');
    });
  }
}
