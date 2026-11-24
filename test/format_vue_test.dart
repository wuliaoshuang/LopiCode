// Vue 单文件组件格式化器：例子、四条铁律、刁钻输入。
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/format/format.dart';

import 'format_support.dart';

const String _full =
    '<template>\n<div :class="{a:n>1}" @click="n++"><p v-if="n > 1">{{ n < 3 ? \'a\' : \'b\' }}</p>\n<p v-else>没有</p></div>\n</template>\n<script>\nexport default {\ndata(){\nreturn {n:0}\n}\n}\n</script>\n<style scoped>\n.a{color:red}\n</style>\n';

const String _fullOut =
    '<template>\n  <div :class="{a:n>1}" @click="n++">\n    <p v-if="n > 1">{{ n < 3 ? \'a\' : \'b\' }}</p>\n    <p v-else>没有</p>\n  </div>\n</template>\n\n<script>\nexport default {\n  data() {\n    return {n:0}\n  }\n}\n</script>\n\n<style scoped>\n.a {\n  color: red;\n}\n</style>\n';

void main() {
  group('输入 → 期望输出', () {
    test('三块齐全：模板缩进一层，脚本和样式顶格，块之间空一行', () {
      expect(formatOk(_full, 'vue'), _fullOut);
    });

    test('缺块：只有模板 / 只有脚本', () {
      expect(formatOk('<template><div><p>a</p></div></template>', 'vue'), '<template>\n  <div>\n    <p>a</p>\n  </div>\n</template>\n');
      expect(formatOk('<script setup>\nimport {ref} from "vue"\nconst n=ref(0)\n</script>', 'vue'), '<script setup>\nimport {ref} from "vue"\nconst n = ref(0)\n</script>\n');
    });

    test('顺序不同：保持原来的顺序；两个 <script>、两个 <style> 都保留', () {
      expect(
        formatOk('<style>\na{b:c}\n</style>\n\n\n\n<script>\nlet a=1\n</script><script setup>\nlet b=2\n</script>\n<template><p>x</p></template><style scoped>d{e:f}</style>', 'vue'),
        '<style>\na {\n  b: c;\n}\n</style>\n\n<script>\nlet a = 1\n</script>\n\n<script setup>\nlet b = 2\n</script>\n\n<template>\n  <p>x</p>\n</template>\n\n<style scoped>\nd {\n  e: f;\n}\n</style>\n',
      );
    });

    test('template 里嵌 template（v-if / 具名插槽）', () {
      expect(
        formatOk(
          '<template>\n<div>\n<template v-if="ok"><p>a</p></template>\n<Comp><template #head="{ item }"><b>{{ item }}</b></template></Comp>\n</div>\n</template>\n<script>\nlet a\n</script>',
          'vue',
        ),
        '<template>\n  <div>\n    <template v-if="ok">\n      <p>a</p>\n    </template>\n    <Comp><template #head="{ item }"><b>{{ item }}</b></template></Comp>\n  </div>\n</template>\n\n<script>\nlet a\n</script>\n',
      );
    });

    test('lang="ts" 的脚本、scss / less 的样式原样保留，并在说明里讲清', () {
      const ts = '<script setup lang="ts">\nconst a:number=1\n   let b = <T>(x:T)=>x\n</script>';
      const scss = '<style lang="scss" scoped>\n.a{ .b{color:red}\n  // 行注释\n}\n</style>';
      const less = "<style lang='less'>\n@c:red;.a{color:@c}\n</style>";
      final r = formatCode('<template><p>a</p></template>\n$ts\n$scss\n$less', 'vue');
      expect(r.problem, isNull);
      expect(r.text, '<template>\n  <p>a</p>\n</template>\n\n$ts\n\n$scss\n\n$less\n');
      expect(r.note, contains('lang="ts" 的 <script> 暂不格式化，原样保留'));
      expect(r.note, contains('lang="scss" 的 <style> 暂不格式化，原样保留'));
      expect(r.note, contains('lang="less" 的 <style> 暂不格式化，原样保留'));
      formatOk(r.text, 'vue');
    });

    test('最外层的注释、自定义块原样保留', () {
      const src = '<!-- 说明 -->\n<template><p>a</p></template>\n<i18n>\n{"zh":{"a":  "甲"}}\n</i18n>';
      final r = formatCode(src, 'vue');
      expect(r.text, '<!-- 说明 -->\n\n<template>\n  <p>a</p>\n</template>\n\n<i18n>\n{"zh":{"a":  "甲"}}\n</i18n>\n');
      expect(r.note, contains('<i18n> 块原样保留'));
      formatOk(src, 'vue');
    });

    test('空的块收成一行；缩进宽度可以改', () {
      expect(formatOk('<template>\n\n</template>\n<script>\n</script>', 'vue'), '<template></template>\n\n<script></script>\n');
      expect(formatOk('<template><div><p>a</p></div></template>', 'vue', indent: 4), '<template>\n    <div>\n        <p>a</p>\n    </div>\n</template>\n');
    });

    test('已经整齐的：changed 为假', () {
      final r = formatCode(_fullOut, 'vue');
      expect(r.changed, isFalse);
      expect(r.text, _fullOut);
      expect(r.note, isNull);
    });
  });

  group('刁钻输入', () {
    test('指令属性和 {{ 表达式 }} 原样保留', () {
      const line =
          '<li v-for="(item, i) in list" :key="item.id" @click.stop="pick(item, \$event)" v-bind:class="[a ? \'x\' : \'y\', { z: b > 1 }]" v-model.trim="q" #default="{ row }">{{ item.name | upper }} - {{ i<10 ? \'0\'+i : i }}</li>';
      expect(formatOk('<template><ul>$line</ul></template>', 'vue'), '<template>\n  <ul>\n    $line\n  </ul>\n</template>\n');
    });

    test('脚本里有 </template> 字样的字符串、模板字符串多行内容不动', () {
      const src = '<template><p>a</p></template>\n<script>\nconst t="</template>",h=`<div>\n   <p>不动</p>\n</div>`\n</script>';
      expect(formatOk(src, 'vue'), '<template>\n  <p>a</p>\n</template>\n\n<script>\nconst t = "</template>", h = `<div>\n   <p>不动</p>\n</div>`\n</script>\n');
    });

    test('模板里有 <pre>：内容不动', () {
      const src = '<template>\n<div><pre>\n  a\n     b</pre></div>\n</template>';
      expect(formatOk(src, 'vue'), '<template>\n  <div>\n    <pre>\n  a\n     b</pre>\n  </div>\n</template>\n');
    });

    test('某一块排不了：那一块原样保留，别的照常排，说明里有文件里的行号', () {
      const src = '<template>\n<div><p>a</div>\n</template>\n<script>\nlet a=(1\n</script>\n<style>\na{b:c}\n</style>';
      final r = formatCode(src, 'vue');
      expect(r.problem, isNull);
      expect(r.text, '<template>\n<div><p>a</div>\n</template>\n\n<script>\nlet a=(1\n</script>\n\n<style>\na {\n  b: c;\n}\n</style>\n');
      expect(r.note, contains('<template> 里面没有格式化（第 2 行'));
      expect(r.note, contains('<script> 里面没有格式化（第 5 行'));
      formatOk(src, 'vue');
    });

    test('块的开始标签带 > 的属性值、多行属性', () {
      const src = '<template functional\n  data-x="a > b">\n<p>a</p>\n</template>';
      expect(formatOk(src, 'vue'), '<template functional\n  data-x="a > b">\n  <p>a</p>\n</template>\n');
    });
  });

  group('铁律', () {
    test('1 幂等、2 记号序列不变', () {
      formatOk(_full, 'vue');
      formatOk(_full.replaceAll('\n', '\n\n  '), 'vue');
      formatOk(_fullOut, 'vue');
    });

    test('2 校验对不上就放弃：原样返回并说明', () {
      const src = '<template><p>a</p></template>\n<script>let a=1</script>';
      for (final wrong in [
        '<template><p>b</p></template>\n<script>let a=1</script>',
        '<template><p>a</p></template>\n<script>let a=2</script>',
        '<template><p>a</p></template>',
        '<script>let a=1</script>\n<template><p>a</p></template>',
        '<template lang="x"><p>a</p></template>\n<script>let a=1</script>',
      ]) {
        final r = checkedResult(src, wrong, 'vue');
        expect(r.problem, kFormatMismatch, reason: wrong);
        expect(r.text, src);
      }
      expect(checkedResult(src, '<template>\n  <p>a</p>\n</template>\n\n<script>\nlet a = 1\n</script>\n', 'vue').problem, isNull);
      // 原样保留的块必须逐字相同
      expect(checkedResult('<script lang="ts">let a:  number</script>', '<script lang="ts">let a: number</script>', 'vue').problem, isNotNull);
    });

    test('3 解析不了：原样返回，说出第几行', () {
      formatFails('<template>\n<p>a</p>\n', 'vue', hint: '第 1 行');
      formatFails('<template><p>a</p></template>\n<script>\nlet a\n', 'vue', hint: '第 2 行');
      formatFails('<template><template><p>a</p></template>\n', 'vue', hint: '第 1 行');
      formatFails('<template><p>a</p></template>\n游离的文字\n<script></script>', 'vue', hint: '第 2 行');
      formatFails('<template><p>a</p></template>\n</script>', 'vue', hint: '第 2 行');
      formatFails('<template>\n<p>a</p></template>\n<!-- 没结束', 'vue', hint: '第 3 行');
      formatFails('<template><p>a</p></template>\n<script lang="ts>\n</script>', 'vue');
    });

    test('4 任何输入都不抛异常', () {
      neverThrows('vue', ['<template>', '<template><template>', '<script', '<style lang="', '<template/>', '<template></template></template>', '<a><b>', 'x<template></template>']);
    });

    test('4 CRLF 保持 CRLF，BOM 保留，末尾恰好一个换行', () {
      final r = formatCode('\uFEFF<template>\r\n<p>a</p>\r\n</template>\r\n<script>\r\nlet a=1\r\n</script>\r\n\r\n', 'vue');
      expect(r.text, '\uFEFF<template>\r\n  <p>a</p>\r\n</template>\r\n\r\n<script>\r\nlet a = 1\r\n</script>\r\n');
      expect(formatCode(r.text, 'vue').changed, isFalse);
      for (final blank in ['', '  \n\t\n']) {
        final b = formatCode(blank, 'vue');
        expect(b.text, blank);
        expect(b.problem, isNull);
      }
    });

    test('随机扰动：缩进、行尾空白、空行数量随便变，排出来的结果一模一样', () {
      final rnd = Random(3);
      final expected = formatOk(_full, 'vue');
      for (var round = 0; round < 80; round++) {
        final scrambled = scrambleLines(expected, rnd);
        expect(formatOk(scrambled, 'vue'), expected, reason: '第 $round 轮：\n$scrambled');
      }
    });
  });
}
