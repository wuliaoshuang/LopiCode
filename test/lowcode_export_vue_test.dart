// 导出 Vue 3：结构、快照、注入防护、自定义组件、坏数据不崩，以及用 node 把 <script setup> 真的跑一遍。
//
// 本机没有 Vue 的编译器（也不联网装），所以这里验证的是：模板标签配平、只出现我们认识的标签和属性、
// 脚本语法正确而且跑出来的结果对。需要 node 的用例在找不到 node 的机器上会跳过，不算失败。
import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/format/format.dart';
import 'package:lopicode/lowcode/component_model.dart';
import 'package:lopicode/lowcode/export_framework_common.dart';
import 'package:lopicode/lowcode/export_vue.dart';
import 'package:lopicode/lowcode/logic_js.dart';
import 'package:lopicode/lowcode/model.dart';

import 'support/lowcode_samples.dart';

/// 把 .vue 文件拆成三块（每块必须恰好出现一次，否则说明有内容把文件截断了）。
({String script, String template, String style}) splitSfc(String sfc) {
  for (final tag in const ['<script setup>', '</script>', '<template>', '</template>', '<style scoped>', '</style>']) {
    // 不用 expect：这个函数在 group 里（用例外面）也会调用
    if (tag.allMatches(sfc).length != 1) throw StateError('$tag 应该恰好出现一次，文件被截断了？');
  }
  String between(String a, String b) => sfc.substring(sfc.indexOf(a) + a.length, sfc.indexOf(b));
  return (script: between('<script setup>', '</script>'), template: between('<template>', '</template>'), style: between('<style scoped>', '</style>'));
}

const String vueFakes = '''
const lcMounted = [];
const ref = (v) => ({ value: v });
const onMounted = (fn) => lcMounted.push(fn);
const defineProps = (p) => p;
''';

/// 把页面的 <script setup> 配上假的 ref / onMounted 跑起来；`body` 里可以直接用脚本里的变量和处理函数。
Object? runVue(LcFrameworkExport e, String body) => runNode('$vueFakes\n${stripImports(splitSfc(e.files.first.content).script)}', 'lcMounted.forEach((fn) => fn());\n$body');

final RegExp _interpolation = RegExp(r'\{\{([\s\S]*?)\}\}');
final RegExp _safeInterpolation = RegExp(
  r"^ ([A-Za-z_][A-Za-z0-9_]*|'([^'{}<>&"
  r'"`$\\]|\\u[0-9a-f]{4})*'
  r"') $",
);

const Set<String> _knownTags = {'main', 'div', 'p', 'button', 'img', 'input', 'ul', 'li', 'hr'};
const Set<String> _knownAttrs = {'class', 'type', 'v-show', 'v-if', 'v-else', ':style', '@click', '@input', 'src', ':src', 'alt', 'role', 'aria-label', 'placeholder', ':placeholder', ':value'};

/// 模板里只许出现我们认识的标签和属性（组件标签是大写开头的，属性另算），插值只许是“一个名字”或“全转义的字符串”。
void expectSafeTemplate(String template, {Set<String> components = const {}, Set<String> props = const {}}) {
  expect(tagBalanceProblem(template), isNull);
  final body = template.replaceAll(RegExp(r'<!--[\s\S]*?-->'), '');
  for (final m in RegExp(r'<([A-Za-z][A-Za-z0-9]*)((?:"[^"]*"|[^<>"])*)>').allMatches(body)) {
    final tag = m[1]!;
    expect(_knownTags.contains(tag) || components.contains(tag), isTrue, reason: '不认识的标签 <$tag>');
    for (final a in RegExp(r'''\s([:@]?[A-Za-z_][A-Za-z0-9_-]*)(?:="[^"]*")?''').allMatches(m[2]!)) {
      final name = a[1]!;
      final ok = _knownAttrs.contains(name) || (components.contains(tag) && props.contains(name.replaceFirst(':', '')));
      expect(ok, isTrue, reason: '<$tag> 上不认识的属性 $name');
    }
  }
  // 花括号只许出现在两个地方：我们自己写的 :style="{ … }"（里面只有名字），和元素内容里的插值
  final rest = body.replaceAll(RegExp(r' :style="\{ (?:(?:background|color): [A-Za-z_][A-Za-z0-9_]*(?:, )?)+ \}"'), '');
  for (final m in _interpolation.allMatches(rest)) {
    expect(_safeInterpolation.hasMatch(m[1]!), isTrue, reason: '插值里的内容不对：${m[0]}');
  }
  expect(rest.replaceAll(_interpolation, '').contains(RegExp('[{}]')), isFalse, reason: '插值以外不该有花括号');
}

String unescapeHtml(String s) => s.replaceAll('&lt;', '<').replaceAll('&gt;', '>').replaceAll('&quot;', '"').replaceAll('&amp;', '&');

const List<String> nasty = [
  '</script><script>pwn()</script>',
  '</template><p>x</p>',
  '</style><style>*{display:none}',
  '{{ pwn() }}',
  r'${pwn()}',
  '`+pwn()+`',
  '"+pwn()+"',
  "'+pwn()+'",
  '{ } }} {{',
  '<!-- x --> -->',
  'a\u2028pwn()//\u2029b',
  '*/ pwn() /*',
  'line1\nline2\r\npwn()',
  r'tail\',
  '&amp; &lt; &#123;&#123; pwn() &#125;&#125;',
  '<img src=x onerror=pwn()>',
  '" onclick="pwn()',
];

/// 每个恶意字符串都放进：文本、按钮（点了弹这段字）、输入框提示、图片地址、列表项、变量初值、“改控件”的值、组件的默认值和传入值。
Map<String, Object?> nastyJson() => {
  'title': nasty.join(' '),
  'root': {
    'id': 'root',
    'type': 'page',
    'children': [
      for (var i = 0; i < nasty.length; i++) ...[
        {
          'id': 't$i',
          'type': 'text',
          'props': {'text': nasty[i]},
        },
        {
          'id': 'd$i',
          'type': 'text',
          'props': {'text': nasty[i]},
        },
        {
          'id': 'b$i',
          'type': 'button',
          'props': {'text': nasty[i]},
        },
        {
          'id': 'i$i',
          'type': 'input',
          'props': {'placeholder': nasty[i]},
        },
        {
          'id': 'm$i',
          'type': 'image',
          'props': {'src': nasty[i]},
        },
        {
          'id': 'c$i',
          'type': 'component',
          'props': {
            'ref': 'c1',
            'values': {'title': nasty[i]},
          },
        },
      ],
      {
        'id': 'list',
        'type': 'list',
        'props': {'items': nasty},
      },
    ],
  },
  'logic': {
    'variables': [
      for (var i = 0; i < nasty.length; i++) {'name': 'v$i', 'type': 'text', 'initial': nasty[i]},
    ],
    'handlers': [
      for (var i = 0; i < nasty.length; i++)
        {
          'id': 'h$i',
          'event': 'click',
          'target': 'b$i',
          'body': [
            blk('alert', {'message': exText(nasty[i])}),
            blk('setProp', {'node': 'd$i', 'prop': 'text', 'value': exVar('v$i')}),
            blk('setVar', {'name': 'v$i', 'value': exText(nasty[i])}),
            blk('nope ${nasty[i]}', {}),
          ],
        },
    ],
  },
  'components': [
    {
      'id': 'c1',
      'name': 'Card ${nasty.join(' ')}',
      'props': [
        {'name': 'title', 'type': 'text', 'default': nasty.join()},
      ],
      'root': {
        'id': 'k1',
        'type': 'text',
        'props': {'text': nasty[3]},
        'bind': {'text': 'title'},
      },
    },
  ],
};

void main() {
  tearDownAll(cleanNodeTmp);

  group('固定样本', () {
    final e = exportVue(frameworkSample());
    final page = e.files.first;

    test('生成哪些文件、叫什么', () {
      expect([for (final f in e.files) f.path], ['CounterDemo.vue', 'components/TitleCard.vue']);
      expect(e.file('CounterDemo.vue'), same(page));
      expect(page.lineCount, '\n'.allMatches(page.content).length);
    });

    test('每个文件都排过版，再排一次不变', () {
      for (final f in e.files) {
        expect(f.formatProblem, isNull, reason: f.path);
        final again = formatCode(f.content, 'vue');
        expect(again.problem, isNull, reason: f.path);
        expect(again.text, f.content, reason: '${f.path} 再排一次应该不变');
      }
    });

    test('脚本和模板的整份快照', () {
      final s = splitSfc(page.content);
      expect(s.script.replaceFirst(lcJsRuntime.trim(), '/* 小工具 */').trim(), _pageScript.trim());
      expect(s.template.trim(), _pageTemplate.trim());
      final c = splitSfc(e.files[1].content);
      expect(c.script.trim(), _componentScript.trim());
      expect(c.template.trim(), _componentTemplate.trim());
    });

    test('样式：基础规则 + 每个节点一条，和导出网页用的是同一份节点样式', () {
      final style = splitSfc(page.content).style;
      expect(style, contains('.lc-row {\n  display: flex;\n  flex-direction: row;\n}'));
      expect(style, isNot(contains('body')));
      expect(style, contains('.n-n1 {\n  margin-top: 8px;\n  font-size: 24px;\n  font-weight: 600;\n  letter-spacing: 1px;\n}'));
      expect(style, contains('.n-n12 {\n  flex: 0 0 8px;\n  height: 8px;\n}'));
      // 组件里的节点用带组件 id 的类名，不会和页面节点撞
      expect(splitSfc(e.files[1].content).style, contains('.n-c1-k1 {'));
      expect('{'.allMatches(style).length, '}'.allMatches(style).length);
    });

    test('模板只有认识的标签和属性，标签配平', () {
      expectSafeTemplate(splitSfc(page.content).template, components: {'TitleCard'}, props: {'title', 'badge', 'tint'});
      expectSafeTemplate(splitSfc(e.files[1].content).template);
    });

    test('说明里讲了简化项', () {
      expect(e.notes, contains(kNoteBody));
      expect(e.notes, contains(kNoteNoBinding));
    });

    test('脚本语法正确（node --check）', () {
      for (final f in e.files) {
        expect(nodeCheck('$vueFakes\n${stripImports(splitSfc(f.content).script)}'), '', reason: f.path);
      }
    }, skip: skipWithoutNode);

    test('真的跑：打开页面、计数器、如果、输入联动、请求', () {
      final out = runVue(e, '''
const opened = n3_placeholder.value;
onClick_n5_h1({});
const first = { count: count.value, text: n1_text.value, bg: n5_bg.value, visible: n8_visible.value, src: n9_src.value };
onClick_n5_h1({}); onClick_n5_h1({});
const third = { count: count.value, text: n1_text.value, bg: n5_bg.value, visible: n8_visible.value };
lcOn_n3_input(input("小塔"));
const typed = { value: n3_value.value, hello: n7_text.value };
onClick_n6_h3({});
await settle();
return { opened, first, third, typed, reply: reply.value, after: n7_text.value, fetchCalls, pwned };
''');
      expect(out, {
        'opened': '写点什么',
        'first': {'count': 1, 'text': '点了 1 次', 'bg': '', 'visible': true, 'src': 'b.png'},
        'third': {'count': 3, 'text': '点了 3 次', 'bg': '#CC3344', 'visible': false},
        'typed': {'value': '小塔', 'hello': '你好，小塔'},
        'reply': '响应内容',
        'after': '响应内容 / 小塔',
        'fetchCalls': [
          {'url': 'https://example.com/api', 'method': 'GET'},
        ],
        'pwned': 0,
      });
    }, skip: skipWithoutNode);
  });

  group('没有逻辑、没有组件的页面', () {
    final e = exportVue(LcDocument.starter('我的页面'));
    test('只有一个文件，名字用默认的；脚本里没有多余的东西', () {
      expect([for (final f in e.files) f.path], ['LcPage.vue']);
      final s = splitSfc(e.files.single.content);
      expect(s.script.trim(), '// 由 LopiCode 低代码搭建器生成，重新导出会覆盖本文件。');
      expect(s.template, contains('<button type="button" class="lc-button n-n5">提交</button>'));
      expect(s.template, isNot(contains('@click')));
      expect(e.files.single.formatProblem, isNull);
      expect(e.notes, [kNoteBody]);
    });
  });

  group('起名', () {
    test('页面名：标题转大驼峰，转不出来用 LcPage', () {
      expect(lcPascalName('login page 2', fallback: 'LcPage'), 'LoginPage2');
      expect(lcPascalName('登录页', fallback: 'LcPage'), 'LcPage');
      expect(lcPascalName('2048 game', fallback: 'LcPage'), 'Lc2048Game');
      expect(lcPascalName('string', fallback: 'LcPage'), 'StringView');
      expect(lcPascalName('a' * 100, fallback: 'LcPage').length, 40);
      expect(lcPascalName('../../etc/passwd', fallback: 'LcPage'), 'EtcPasswd');
    });

    test('变量名撞了保留字 / 小工具 / 处理函数 / 组件名：加后缀，脚本照样能跑', () {
      final json = frameworkSampleJson();
      json['logic'] = {
        'variables': [
          for (final name in const ['class', 'lcNum', 'event', 'ref', '__proto__', 'onClick_n5_h1', 'TitleCard', 'n1_text', 'count']) {'name': name, 'type': 'number', 'initial': 1},
        ],
        'handlers': [
          {
            'id': 'h1',
            'event': 'click',
            'target': 'n5',
            'body': [
              for (final name in const ['class', 'lcNum', 'event', 'ref', '__proto__', 'onClick_n5_h1', 'TitleCard', 'n1_text', 'count']) blk('changeVar', {'name': name, 'by': exNum(1)}),
              blk('setProp', {'node': 'n1', 'prop': 'text', 'value': exVar('n1_text')}),
            ],
          },
        ],
      };
      final e = exportVue(docOf(json));
      final script = splitSfc(e.files.first.content).script;
      for (final decl in const ['class_var', 'v_lcNum', 'event_var', 'ref_var', 'proto', 'onClick_n5_h1_var', 'TitleCard_var', 'n1_text', 'count', 'n1_text_ui']) {
        expect(script, contains('const $decl = ref('), reason: decl);
      }
      if (!hasNode) return;
      final out = runVue(
        e,
        'onClick_n5_h1({}); return [class_var.value, v_lcNum.value, event_var.value, ref_var.value, proto.value, onClick_n5_h1_var.value, TitleCard_var.value, n1_text.value, count.value, n1_text_ui.value, ({}).polluted === undefined];',
      );
      expect(out, [2, 2, 2, 2, 2, 2, 2, 2, 2, '2', true]);
    });
  });

  group('注入', () {
    final e = exportVue(docOf(nastyJson()));
    final page = e.files.first;
    final s = splitSfc(page.content);

    test('三块都没被截断，模板里只有认识的标签和属性', () {
      expect(e.files.length, 2);
      expect(RegExp(r'^[A-Z][A-Za-z0-9]*\.vue$').hasMatch(page.path), isTrue);
      final name = e.files[1].path.split('/').last.replaceAll('.vue', '');
      expect(RegExp(r'^[A-Z][A-Za-z0-9]*$').hasMatch(name), isTrue);
      expectSafeTemplate(s.template, components: {name}, props: {'title'});
      expectSafeTemplate(splitSfc(e.files[1].content).template);
      expect(s.style, isNot(contains('display:none')));
    });

    test('模板里的固定文字、属性原样还原', () {
      final literals = <String>[];
      for (var i = 0; i < nasty.length; i++) {
        final text = RegExp('<p class="lc-text n-t$i">(.*)</p>').firstMatch(s.template)![1]!;
        if (text.startsWith('{{ ')) {
          literals.add(text.substring(3, text.length - 3));
        } else {
          expect(unescapeHtml(text), nasty[i]);
          literals.add(vueStringLiteral(nasty[i]));
        }
        for (final (tag, attr) in const [('input', 'placeholder'), ('img', 'src')]) {
          final line = RegExp('<$tag class="lc-[a-z]+ n-[im]$i"[^\n]*').firstMatch(s.template)![0]!;
          final m = RegExp(' (:?)$attr="([^"]*)"').firstMatch(line)!;
          if (m[1] == ':') {
            literals.add(m[2]!);
          } else {
            expect(unescapeHtml(m[2]!), nasty[i]);
            literals.add(vueStringLiteral(nasty[i]));
          }
        }
      }
      if (!hasNode) return;
      // 写成 '\uXXXX' 的那些交给 node 还原，再和原文比
      expect(runNode('', 'return [${literals.join(', ')}];'), [
        for (final n in nasty) ...[n, n, n],
      ]);
    });

    test('脚本语法正确，跑起来没有一段字被当成代码执行，内容原样', () {
      expect(nodeCheck('$vueFakes\n${stripImports(s.script)}'), '');
      expect(nodeCheck('$vueFakes\n${stripImports(splitSfc(e.files[1].content).script)}'), '');
      final out = runVue(e, '''
const before = [${[for (var i = 0; i < nasty.length; i++) 'v$i.value'].join(', ')}];
${[for (var i = 0; i < nasty.length; i++) 'onClick_b${i}_h$i({});'].join('\n')}
return { before, alerts, shown: [${[for (var i = 0; i < nasty.length; i++) 'd${i}_text.value'].join(', ')}], pwned, polluted: ({}).polluted === undefined ? 0 : 1 };
''');
      expect(out, {'before': nasty, 'alerts': nasty, 'shown': nasty, 'pwned': 0, 'polluted': 0});
    }, skip: skipWithoutNode);

    test('排版器没有把它排坏', () {
      for (final f in e.files) {
        expect(formatCode(f.content, 'vue').text, f.content, reason: f.path);
      }
    });
  });

  group('自定义组件', () {
    test('带默认值的 props；只传和默认值不同的；撞了保留字的 prop 改名', () {
      final e = exportVue(frameworkSample());
      final c = splitSfc(e.files[1].content);
      expect(c.script, contains('title: { type: String, default: "标题" },'));
      expect(c.script, contains('badge: { type: Number, default: 0 },'));
      expect(c.script, contains('class_prop: { type: String, default: "" },'));
      expect(c.template, contains(':style="{ background: tint }"'));
      final json = frameworkSampleJson();
      (((json['root']! as Map)['children']! as List).last as Map)['props'] = {
        'ref': 'c1',
        'values': {'title': '标题', 'badge': '不是数字', 'tint': '#ffffff', 'class': 'x', 'nope': 1},
      };
      expect(splitSfc(exportVue(docOf(json)).files.first.content).template, contains('<TitleCard class="lc-component n-n13" class_prop="x" />'));
    });

    test('定义找不到：留一行注释并记进说明', () {
      final json = frameworkSampleJson()..remove('components');
      final e = exportVue(docOf(json));
      expect(e.files.length, 1);
      expect(e.files.first.content, contains('<!-- 这里原来是一个自定义组件（c1），没有导出'));
      expect(e.files.first.content, isNot(contains('import TitleCard')));
      expect(e.notes.any((n) => n.contains('找不到')), isTrue);
      expectSafeTemplate(splitSfc(e.files.first.content).template);
    });

    test('组件里再用组件；重名加序号；循环引用停下来并记进说明', () {
      Map<String, Object?> def(String id, String name, String? inner) => {
        'id': id,
        'name': name,
        'root': {
          'id': 'k1',
          'type': 'column',
          'children': [
            {
              'id': 'k2',
              'type': 'text',
              'props': {'text': name},
            },
            if (inner != null)
              {
                'id': 'k3',
                'type': 'component',
                'props': {'ref': inner},
              },
          ],
        },
      };
      final doc = docOf({
        'title': 'Box',
        'root': {
          'id': 'root',
          'type': 'page',
          'children': [
            {
              'id': 'n1',
              'type': 'component',
              'props': {'ref': 'c1'},
            },
          ],
        },
        'components': [def('c1', 'Box', 'c2'), def('c2', 'box', 'c3'), def('c3', '盒子', null), def('c9', 'Unused', null)],
      });
      final e = exportVue(doc);
      expect([for (final f in e.files) f.path], ['Box.vue', 'components/Box2.vue', 'components/Box3.vue', 'components/LcComponent.vue']);
      expect(e.files[1].content, contains('import Box3 from "./Box3.vue";'));
      expect(e.files[1].content, contains('<Box3 class="lc-component n-c1-k3" />'));
      expect(e.files[0].content, contains('import Box2 from "./components/Box2.vue";'));

      // 模型读文件时不拦循环引用，这里在内存里造一个：c3 → c1
      doc.component('c3')!.root.children.add(LcNode(id: 'k9', type: 'component', props: {'ref': 'c1'}));
      final loop = exportVue(doc);
      expect(loop.files.length, 4);
      expect(loop.files[3].content, contains('<!-- 这里原来是一个自定义组件（c1），没有导出'));
      expect(loop.notes.any((n) => n.contains('循环引用')), isTrue);
      // 自己直接套自己
      doc.components.add(
        LcComponentDef(
          id: 'c5',
          name: 'Self',
          root: LcNode(id: 'k1', type: 'component', props: {'ref': 'c5'}),
        ),
      );
      doc.root.children.add(LcNode(id: 'n2', type: 'component', props: {'ref': 'c5'}));
      expect(exportVue(doc).files.last.content, contains('没有导出'));
    });
  });

  group('坏数据不崩', () {
    test('内存里被改坏的属性、样式、id、逻辑', () {
      final doc = frameworkSample();
      doc.root.children
        ..add(LcNode(id: 'x1', type: 'list', props: {'items': '不是数组'}))
        ..add(LcNode(id: 'x2', type: 'text', props: {'text': 42}))
        ..add(LcNode(id: 'x3', type: 'image', props: {'src': 7}))
        ..add(LcNode(id: 'x4', type: 'text', style: {'color': 'red } </style> .x { color: blue'}))
        ..add(LcNode(id: 'bad"id<', type: 'input'))
        ..add(LcNode(id: 'x6', type: 'component', props: {'ref': 99, 'values': 'x'}));
      doc.logic.handlers.add(LcHandlerSample.orphan());
      final e = exportVue(doc);
      final s = splitSfc(e.files.first.content);
      expectSafeTemplate(s.template, components: {'TitleCard'}, props: {'title', 'badge', 'tint'});
      expect(s.style, isNot(contains('blue')));
      expect(e.notes.any((n) => n.contains('样式没有导出')), isTrue);
      expect(e.notes.any((n) => n.contains('没有挂到任何控件上')), isTrue);
      if (hasNode) expect(nodeCheck('$vueFakes\n${stripImports(s.script)}'), '');
    });

    test('控件不支持的属性：读成空的、改的那块跳过，都记进说明', () {
      final json = frameworkSampleJson();
      (json['logic']! as Map)['handlers'] = [
        {
          'id': 'h1',
          'event': 'click',
          'target': 'n5',
          'body': [
            blk('setProp', {'node': 'n10', 'prop': 'text', 'value': exText('x')}),
            blk('setProp', {'node': 'n1', 'prop': 'text', 'value': exProp('n2', 'text')}),
            blk('setProp', {'node': 'n13', 'prop': 'visible', 'value': exBool(false)}),
          ],
        },
        {'id': 'h2', 'event': 'click', 'target': 'n5', 'body': <Object?>[]},
      ];
      final e = exportVue(docOf(json));
      final s = splitSfc(e.files.first.content);
      expect(s.script, contains('// 跳过：列表的文字不能用积木改'));
      expect(s.script, contains('n1_text.value = "" /* 卡片的文字读不出来，这里当成空的 */;'));
      expect(e.notes.where((n) => n.contains('被跳过了') || n.contains('读不到')).length, 2);
      // 自定义组件的实例也能显示 / 隐藏；同一个控件的同一个事件有两个处理：包一层
      expect(s.template, contains('<TitleCard class="lc-component n-n13" v-show="n13_visible"'));
      expect(s.template, contains('@click="lcOn_n5_click"'));
      expect(s.script, contains('function lcOn_n5_click(event) {\n  onClick_n5_h1(event);\n  onClick_n5_h2(event);\n}'));
    });
  });
}

const String _pageScript = r'''
// 由 LopiCode 低代码搭建器生成，重新导出会覆盖本文件。
//
// 怎么读这份脚本：
// - 页面变量是下面的 ref；每个“处理”是一个函数，模板里用 @click / @input 挂在控件上。
// - 变量改了以后，界面上不会自动跟着变。要让界面变，用“改控件”积木：它改的是下面“控件属性”里的 ref，模板绑定着它们。
// - 加减乘除一律按数字算：输入框里读到的是文字，会先用 lcNum 转成数字（转不了的当 0）。
// - “等一会儿”“请求网址”只管它们里面的积木：排在它们后面的积木不会等，马上接着做。
import { onMounted, ref } from "vue";
import TitleCard from "./components/TitleCard.vue";

// 页面变量
const count = ref(0);
const reply = ref("");

// 控件属性：逻辑里读或改到的那些（模板里绑定着它们）
const n1_text = ref("点了 0 次");
const n5_bg = ref("");
const n8_visible = ref(true);
const n9_src = ref("");
const n7_text = ref("你好");
const n3_value = ref("");
const n3_placeholder = ref("你的名字");

// —— 小工具 ——
/* 小工具 */

// 点击「按钮“加一”」时
function onClick_n5_h1(event) {
  count.value = count.value + 1;
  n1_text.value = "点了 " + lcText(count.value) + " 次";
  if (count.value >= 3) {
    n5_bg.value = "#CC3344";
    n8_visible.value = false;
  } else {
    n9_src.value = "b.png";
  }
}

// 「输入框“你的名字”」的内容变化时
function onInput_n3_h2(event) {
  n7_text.value = "你好，" + lcEventValue(event);
}

// 点击「按钮“取数据”」时
function onClick_n6_h3(event) {
  fetch("https://example.com/api", { method: "GET" })
    .then(function (lcRes) {
      if (!lcRes.ok) throw new Error("HTTP " + lcRes.status);
      return lcRes.text();
    })
    .then(function (lcBody) {
      reply.value = lcBody;
      n7_text.value = reply.value + " / " + n3_value.value;
    }, function (lcError) {
      alert("失败了");
    });
}

// 页面打开时
function onLoad_h4() {
  n3_placeholder.value = "写点什么";
}

function lcOn_n3_input(event) {
  n3_value.value = lcEventValue(event);
  onInput_n3_h2(event);
}

// 页面准备好以后，执行“页面打开时”的处理
onMounted(() => {
  onLoad_h4();
});
''';

const String _pageTemplate = r'''
<main class="lc-page n-root">
    <p class="lc-text n-n1">{{ n1_text }}</p>
    <div class="lc-card n-n2">
      <input class="lc-input n-n3" @input="lcOn_n3_input" :placeholder="n3_placeholder" :value="n3_value">
      <div class="lc-row n-n4">
        <button type="button" class="lc-button n-n5" :style="{ background: n5_bg }" @click="onClick_n5_h1">加一</button>
        <button type="button" class="lc-button n-n6" @click="onClick_n6_h3">取数据</button>
      </div>
      <p class="lc-text n-n7">{{ n7_text }}</p>
    </div>
    <img class="lc-image n-n8" v-show="n8_visible" src="https://example.com/a.png" alt="">
    <img v-if="n9_src" class="lc-image n-n9" :src="n9_src" alt="">
    <div v-else class="lc-image n-n9" role="img" aria-label="图片占位"></div>
    <ul class="lc-list n-n10">
      <li>第一项</li>
      <li>第二项</li>
    </ul>
    <hr class="lc-divider n-n11">
    <div class="lc-spacer n-n12"></div>
    <TitleCard class="lc-component n-n13" title="今日推荐" :badge="3" tint="#FFEEDD" />
  </main>
''';

const String _componentScript = r'''
// 由 LopiCode 低代码搭建器生成，重新导出会覆盖本文件。
// 自定义组件：Title Card

defineProps({
  title: { type: String, default: "标题" },
  badge: { type: Number, default: 0 },
  tint: { type: String, default: "#FFFFFF" },
  class_prop: { type: String, default: "" },
});
''';

const String _componentTemplate = r'''
<div class="lc-card n-c1-k1" :style="{ background: tint }">
    <p class="lc-text n-c1-k2">{{ title }}</p>
    <p class="lc-text n-c1-k3">{{ badge }}</p>
  </div>
''';
