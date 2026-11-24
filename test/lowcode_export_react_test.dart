// 导出 React：结构、快照、注入防护、自定义组件、坏数据不崩；逻辑部分配上假的 useRef / useState / useEffect 用 node 真的跑一遍。
//
// 本机没有 JSX 的编译器（也不联网装），node 也不认 JSX，所以：
// - `return (…)` 之前的逻辑部分单独取出来，用 node 查语法并真的跑；
// - JSX 部分用下面这个极简的解析器查：标签配平、只有认识的标签和属性、文字里没有会被当成语法的字符，
//   花括号里的每个表达式再单独交给 node 查语法。
// 需要 node 的用例在找不到 node 的机器上会跳过，不算失败。
import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/format/format.dart';
import 'package:lopicode/lowcode/component_model.dart';
import 'package:lopicode/lowcode/export_framework_common.dart';
import 'package:lopicode/lowcode/export_react.dart';
import 'package:lopicode/lowcode/logic_js.dart';
import 'package:lopicode/lowcode/model.dart';

import 'lowcode_export_vue_test.dart' show nasty, nastyJson;
import 'support/lowcode_samples.dart';

/// 极简的 JSX 检查：只认我们自己会生成的写法，别的一律报错。
class JsxScan {
  JsxScan(this.s);
  final String s;
  int i = 0;
  final List<String> tags = [];
  final Set<String> attrs = {};
  final List<String> texts = [];

  /// 花括号里不含 JSX 的表达式（可以单独交给 node 查语法）。
  final List<String> exprs = [];

  Never _fail(String why) => throw FormatException('JSX 第 ${'\n'.allMatches(s.substring(0, i)).length + 1} 行：$why');
  void _ws() {
    while (i < s.length && ' \n\t'.contains(s[i])) {
      i++;
    }
  }

  String _name() {
    final m = RegExp('[A-Za-z][A-Za-z0-9-]*').matchAsPrefix(s, i);
    if (m == null) _fail('这里应该是一个名字');
    i = m.end;
    return m[0]!;
  }

  /// 整段 `return (…)` 里面的内容：一个元素，或一个表达式（三元式 / null）。
  void root() {
    _ws();
    if (s.startsWith('<', i)) {
      element();
    } else {
      expression('');
    }
    _ws();
    if (i != s.length) _fail('后面多了东西');
  }

  /// 读一个表达式，停在最外层的 [end]（空串＝读到结尾）。返回里面有没有 JSX。
  bool expression(String end) {
    var depth = 0;
    var jsx = false;
    var last = '(';
    while (i < s.length) {
      final c = s[i];
      if (depth == 0 && end.isNotEmpty && c == end) return jsx;
      if (c == '"' || c == "'") {
        final start = i++;
        while (i < s.length && s[i] != c) {
          if (s[i] == '\n') _fail('字符串里有换行');
          i += s[i] == r'\' ? 2 : 1;
        }
        if (i >= s.length) _fail('字符串没有结束（从 ${s.substring(start, start + 10)} 开始）');
        i++;
        last = '"';
      } else if (c == '`') {
        _fail('不该有模板字符串');
      } else if (s.startsWith('/*', i)) {
        final close = s.indexOf('*/', i + 2);
        if (close < 0) _fail('注释没有结束');
        i = close + 2;
      } else if (c == '<' && last == '(' && RegExp('<[A-Za-z]').matchAsPrefix(s, i) != null) {
        element();
        jsx = true;
        last = '>';
      } else {
        if ('([{'.contains(c)) depth++;
        if (')]}'.contains(c)) {
          if (depth == 0) _fail('多了一个 $c');
          depth--;
        }
        if (!' \n\t'.contains(c)) last = c;
        i++;
      }
    }
    if (end.isNotEmpty) _fail('表达式没有结束');
    if (depth != 0) _fail('括号没配平');
    return jsx;
  }

  void _container() {
    final start = ++i;
    final jsx = expression('}');
    if (!jsx) exprs.add(s.substring(start, i));
    i++;
  }

  void element() {
    i++;
    final tag = _name();
    tags.add(tag);
    while (true) {
      _ws();
      if (s.startsWith('/>', i)) {
        i += 2;
        return;
      }
      if (s.startsWith('>', i)) {
        i++;
        break;
      }
      if (s.startsWith('{...', i)) {
        i += 4;
        attrs.add('...${_name()}');
        if (!s.startsWith('}', i)) _fail('展开写法不对');
        i++;
        continue;
      }
      final attr = _name();
      attrs.add(attr);
      if (!s.startsWith('=', i)) _fail('属性 $attr 后面应该是 =');
      i++;
      if (s.startsWith('"', i)) {
        final close = s.indexOf('"', i + 1);
        if (close < 0 || s.substring(i, close).contains(RegExp('[{}<>\n]'))) _fail('属性 $attr 的引号内容不对');
        i = close + 1;
      } else if (s.startsWith('{', i)) {
        _container();
      } else {
        _fail('属性 $attr 的值不对');
      }
    }
    // 子节点
    while (true) {
      if (i >= s.length) _fail('<$tag> 没有闭合');
      if (s.startsWith('</', i)) {
        i += 2;
        final close = _name();
        if (close != tag) _fail('<$tag> 对上了 </$close>');
        if (!s.startsWith('>', i)) _fail('结束标签没写完');
        i++;
        return;
      }
      if (s.startsWith('<', i)) {
        element();
      } else if (s.startsWith('{', i)) {
        _container();
      } else {
        final m = RegExp('[^<{]+').matchAsPrefix(s, i)!;
        final text = m[0]!;
        if (text.contains(RegExp('[}>]'))) _fail('文字里有会被当成语法的字符：$text');
        if (text.trim().isNotEmpty) texts.add(text.trim());
        i = m.end;
      }
    }
  }
}

/// 取出 `return (` 到最后的 `);` 之间的 JSX。
String jsxOf(String file) {
  final start = file.lastIndexOf('  return (\n');
  final end = file.lastIndexOf('\n  );\n}');
  if (start < 0 || end < start) throw StateError('找不到 return (…)');
  return file.substring(start + '  return (\n'.length, end);
}

const Set<String> _knownTags = {'main', 'div', 'p', 'button', 'img', 'input', 'ul', 'li', 'hr'};
const Set<String> _knownAttrs = {'className', 'type', 'style', 'onClick', 'onChange', 'onInput', 'src', 'alt', 'role', 'aria-label', 'placeholder', 'value', '...lcRest'};
final RegExp _plain = RegExp(r'''^[^{}<>&"'\\`/*\x00-\x1f\x7f\u0085\u2028\u2029]+$''');

JsxScan expectSafeJsx(String file, {Set<String> components = const {}, Set<String> props = const {}}) {
  final scan = JsxScan(jsxOf(file))..root();
  expect(scan.tags.toSet().difference({..._knownTags, ...components}), isEmpty, reason: '不认识的标签');
  expect(scan.attrs.difference({..._knownAttrs, ...props}), isEmpty, reason: '不认识的属性');
  for (final t in scan.texts) {
    expect(_plain.hasMatch(t), isTrue, reason: '文字里有特殊字符：$t');
  }
  if (hasNode && scan.exprs.isNotEmpty) {
    // 对象字面量（style={{ … }}）、注释、字符串、名字：包进括号里都应该是合法的表达式
    expect(nodeCheck([for (final e in scan.exprs) e.trim().startsWith('/*') ? '$e;' : 'void ($e);'].join('\n')), '');
  }
  return scan;
}

/// 假的 React：按调用顺序记住每个 hook 的值，所以可以“重新渲染”（再调用一次组件函数）。
const String reactFakes = '''
const lcSlots = [], lcEffects = [];
let lcSlot = 0, renders = 0, refreshes = 0;
function useRef(v) { const i = lcSlot++; if (!(i in lcSlots)) lcSlots[i] = { current: v }; return lcSlots[i]; }
function useState(v) { const i = lcSlot++; if (!(i in lcSlots)) lcSlots[i] = v; return [lcSlots[i], (f) => { lcSlots[i] = typeof f === "function" ? f(lcSlots[i]) : f; refreshes++; }]; }
function useEffect(fn) { const i = lcSlot++; if (!(i in lcSlots)) { lcSlots[i] = true; lcEffects.push(fn); } }
function render() { lcSlot = 0; renders++; const page = LcTestPage(); while (lcEffects.length) lcEffects.shift()(); return page; }
''';

/// 页面文件里 `return (` 之前的逻辑部分，改成一个返回 { lcVars, lcUi, 各处理函数 } 的普通函数。
String logicOf(LcExportFile page, List<String> expose) {
  final head = page.content.substring(0, page.content.indexOf(kReactViewMarker));
  final body = stripImports(head).replaceFirst(RegExp(r'export default function [A-Za-z0-9]+\(\) \{'), 'function LcTestPage() {');
  return '$reactFakes\n$body\n  return { lcVars, lcUi, ${expose.join(', ')} };\n}';
}

Object? runReact(LcFrameworkExport e, List<String> expose, String body) => runNode(logicOf(e.files.first, expose), 'let page = render();\n$body');

void main() {
  tearDownAll(cleanNodeTmp);

  group('固定样本', () {
    final e = exportReact(frameworkSample());
    final page = e.files.first;
    const handlers = ['onClick_n5_h1', 'onInput_n3_h2', 'onClick_n6_h3', 'onLoad_h4', 'lcOn_n3_input'];

    test('生成哪些文件、叫什么', () {
      expect([for (final f in e.files) f.path], ['CounterDemo.jsx', 'CounterDemo.css', 'lc-base.css', 'components/TitleCard.jsx', 'components/TitleCard.css']);
    });

    test('每个文件都排过版，再排一次不变', () {
      for (final f in e.files) {
        expect(f.formatProblem, isNull, reason: f.path);
        final again = formatCode(f.content, f.path.endsWith('.css') ? 'css' : 'jsx');
        expect(again.problem, isNull, reason: f.path);
        expect(again.text, f.content, reason: '${f.path} 再排一次应该不变');
      }
    });

    test('JSX 的整份快照', () {
      expect(page.content.replaceFirst(lcJsRuntime.trim(), '/* 小工具 */').trim(), _pageJsx.trim());
      expect(e.file('components/TitleCard.jsx')!.content.trim(), _componentJsx.trim());
    });

    test('样式文件：基础规则单独一份，页面和组件各自只有节点规则', () {
      final base = e.file('lc-base.css')!.content;
      expect(base, contains('.lc-row {\n  display: flex;\n  flex-direction: row;\n}'));
      expect(base, isNot(contains('body')));
      final css = e.file('CounterDemo.css')!.content;
      expect(css, contains('.n-n1 {\n  margin-top: 8px;\n  font-size: 24px;\n  font-weight: 600;\n  letter-spacing: 1px;\n}'));
      expect(css, isNot(contains('.lc-')));
      expect(e.file('components/TitleCard.css')!.content, contains('.n-c1-k1 {'));
      for (final f in e.files.where((f) => f.path.endsWith('.css'))) {
        expect('{'.allMatches(f.content).length, '}'.allMatches(f.content).length, reason: f.path);
      }
    });

    test('JSX 标签配平，只有认识的标签和属性', () {
      final scan = expectSafeJsx(page.content, components: {'TitleCard'}, props: {'title', 'badge', 'tint'});
      expect(scan.tags.first, 'main');
      expect(scan.texts, containsAll(['加一', '取数据', '第一项']));
      expectSafeJsx(e.file('components/TitleCard.jsx')!.content);
    });

    test('说明里讲了简化项', () {
      expect(e.notes, containsAll([kNoteBody, kNoteNoBinding]));
      expect(e.notes.any((n) => n.contains('StrictMode')), isTrue);
    });

    test('逻辑部分语法正确（node --check）', () {
      expect(nodeCheck(logicOf(page, handlers)), '');
    }, skip: skipWithoutNode);

    test('真的跑：打开页面、计数器、如果、输入联动、请求；每次写完都通知 React 重画', () {
      final out = runReact(e, handlers, '''
const opened = page.lcUi.n3_placeholder;
const r0 = refreshes;
page.onClick_n5_h1({});
const first = { count: page.lcVars.count, text: page.lcUi.n1_text, bg: page.lcUi.n5_bg, visible: page.lcUi.n8_visible, src: page.lcUi.n9_src, refreshed: refreshes - r0 };
page.onClick_n5_h1({}); page.onClick_n5_h1({});
const third = { count: page.lcVars.count, text: page.lcUi.n1_text, bg: page.lcUi.n5_bg, visible: page.lcUi.n8_visible };
page.lcOn_n3_input(input("小塔"));
const typed = { value: page.lcUi.n3_value, hello: page.lcUi.n7_text };
page.onClick_n6_h3({});
await settle();
return { opened, first, third, typed, reply: page.lcVars.reply, after: page.lcUi.n7_text, fetchCalls, pwned };
''');
      expect(out, {
        'opened': '写点什么',
        'first': {'count': 1, 'text': '点了 1 次', 'bg': '', 'visible': true, 'src': 'b.png', 'refreshed': 3},
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

    test('重新渲染以后：状态还在、“页面打开时”不再做第二遍；旧的那次渲染留下的处理函数和回调读到的也是最新的值', () {
      final out = runReact(e, handlers, '''
const old = page;
old.onClick_n5_h1({});
// 请求发出去以后、回来之前，界面重画了两次，用户又改了输入框
old.onClick_n6_h3({});
page = render(); page = render();
page.lcOn_n3_input(input("后来改的"));
page.lcUi.n3_placeholder = "被改过";
page = render();
await settle();
// 旧渲染里的函数接着用
old.onClick_n5_h1({});
return { same: old.lcVars === page.lcVars && old.lcUi === page.lcUi, renders, count: page.lcVars.count, text: page.lcUi.n1_text, after: page.lcUi.n7_text, placeholder: page.lcUi.n3_placeholder };
''');
      expect(out, {'same': true, 'renders': 4, 'count': 2, 'text': '点了 2 次', 'after': '响应内容 / 后来改的', 'placeholder': '被改过'});
    }, skip: skipWithoutNode);
  });

  group('同一个处理里先写后读、等一会儿之后再读', () {
    test('读到的都是刚写进去的值', () {
      final json = frameworkSampleJson();
      (json['logic']! as Map)['handlers'] = [
        {
          'id': 'h1',
          'event': 'click',
          'target': 'n5',
          'body': [
            blk('setVar', {'name': 'count', 'value': exNum(5)}),
            blk('changeVar', {'name': 'count', 'by': exVar('count')}),
            blk('setProp', {'node': 'n1', 'prop': 'text', 'value': exVar('count')}),
            blk('setProp', {'node': 'n7', 'prop': 'text', 'value': exProp('n1', 'text')}),
            blk(
              'wait',
              {'ms': exNum(100)},
              body: [
                blk('setVar', {
                  'name': 'reply',
                  'value': exJoin([exProp('n7', 'text'), exText('+'), exVar('count')]),
                }),
              ],
            ),
            blk(
              'repeat',
              {'times': exNum(3)},
              body: [
                blk('changeVar', {'name': 'count', 'by': exNum(1)}),
              ],
            ),
          ],
        },
      ];
      final e = exportReact(docOf(json));
      final out = runReact(
        e,
        ['onClick_n5_h1'],
        '''
page.onClick_n5_h1({});
const before = page.lcVars.reply;
page = render();
runTimers();
return { before, reply: page.lcVars.reply, count: page.lcVars.count, n7: page.lcUi.n7_text, waiting: timers.length };
''',
      );
      // 等一会儿之后读到的 count 是 13（后面的“重复”已经做完了），不是排队时的 10
      expect(out, {'before': '', 'reply': '10+13', 'count': 13, 'n7': '10', 'waiting': 0});
    }, skip: skipWithoutNode);
  });

  group('没有逻辑、没有组件的页面', () {
    final e = exportReact(LcDocument.starter('我的页面'));
    test('不带任何 hook 和小工具', () {
      expect([for (final f in e.files) f.path], ['LcPage.jsx', 'LcPage.css', 'lc-base.css']);
      final jsx = e.files.first.content;
      expect(jsx, contains('import React from "react";\nimport "./lc-base.css";\nimport "./LcPage.css";\n\nexport default function LcPage() {\n  $kReactViewMarker\n  return ('));
      expect(jsx, isNot(contains('useRef')));
      expect(jsx, isNot(contains('lcNum')));
      expect(jsx, contains('<button type="button" className="lc-button n-n5">提交</button>'));
      expectSafeJsx(jsx);
      expect(e.notes, [kNoteBody]);
    });
  });

  group('变量名', () {
    test('保留字、__proto__ 当变量名也没事（它们只是 lcVars 里的键）', () {
      final json = frameworkSampleJson();
      const names = ['class', 'lcNum', 'event', '__proto__', 'count'];
      json['logic'] = {
        'variables': [
          for (final name in names) {'name': name, 'type': 'number', 'initial': 1},
        ],
        'handlers': [
          {
            'id': 'h1',
            'event': 'click',
            'target': 'n5',
            'body': [
              for (final name in names) blk('changeVar', {'name': name, 'by': exNum(1)}),
            ],
          },
        ],
      };
      final e = exportReact(docOf(json));
      expect(e.files.first.content, contains('["__proto__"]: 1,'));
      final out = runReact(
        e,
        ['onClick_n5_h1'],
        'page.onClick_n5_h1({}); return [page.lcVars.class, page.lcVars.lcNum, page.lcVars.event, Object.getOwnPropertyDescriptor(page.lcVars, "__proto__").value, page.lcVars.count, ({}).polluted === undefined];',
      );
      expect(out, [2, 2, 2, 2, 2, true]);
    }, skip: skipWithoutNode);
  });

  group('注入', () {
    final e = exportReact(docOf(nastyJson()));
    final page = e.files.first;
    final handlers = [for (var i = 0; i < nasty.length; i++) 'onClick_b${i}_h$i'];

    test('JSX 没被截断，只有认识的标签和属性，特殊文字都在字符串表达式里', () {
      final name = e.files[3].path.split('/').last.replaceAll('.jsx', '');
      expect(RegExp(r'^[A-Z][A-Za-z0-9]*$').hasMatch(name), isTrue);
      final scan = expectSafeJsx(page.content, components: {name}, props: {'title'});
      expectSafeJsx(e.files[3].content);
      expect(scan.texts, isEmpty, reason: '样本里的文字全是带特殊字符的，不该有直接写进 JSX 的');
      for (final f in e.files.where((f) => f.path.endsWith('.css'))) {
        expect(f.content, isNot(contains('display:none')));
      }
    });

    test('固定文字、属性原样还原', () {
      final jsx = jsxOf(page.content);
      final literals = <String>[];
      for (var i = 0; i < nasty.length; i++) {
        literals
          ..add(RegExp('<p className="lc-text n-t$i">\\{(.*)\\}</p>').firstMatch(jsx)![1]!)
          ..add(RegExp('<input className="lc-input n-i$i" placeholder=\\{(.*)\\} />').firstMatch(jsx)![1]!)
          ..add(RegExp('<img className="lc-image n-m$i" src=\\{(.*)\\} alt="" />').firstMatch(jsx)![1]!)
          ..add(RegExp(' className="lc-component n-c$i" title=\\{(.*)\\} />').firstMatch(jsx)![1]!);
      }
      expect(runNode('', 'return [${literals.join(', ')}];'), [
        for (final n in nasty) ...[n, n, n, n],
      ]);
    }, skip: skipWithoutNode);

    test('逻辑部分语法正确，跑起来没有一段字被当成代码执行，内容原样', () {
      expect(nodeCheck(logicOf(page, handlers)), '');
      final out = runReact(e, handlers, '''
const before = [${[for (var i = 0; i < nasty.length; i++) 'page.lcVars.v$i'].join(', ')}];
${[for (var i = 0; i < nasty.length; i++) 'page.onClick_b${i}_h$i({});'].join('\n')}
return { before, alerts, shown: [${[for (var i = 0; i < nasty.length; i++) 'page.lcUi.d${i}_text'].join(', ')}], pwned, polluted: ({}).polluted === undefined ? 0 : 1 };
''');
      expect(out, {'before': nasty, 'alerts': nasty, 'shown': nasty, 'pwned': 0, 'polluted': 0});
    }, skip: skipWithoutNode);

    test('排版器没有把它排坏', () {
      for (final f in e.files) {
        expect(f.formatProblem, isNull, reason: f.path);
        expect(formatCode(f.content, f.path.endsWith('.css') ? 'css' : 'jsx').text, f.content, reason: f.path);
      }
    });

    test('jsxText：普通文字直接写，其余写成字符串表达式', () {
      expect(jsxText('提交 OK！'), '提交 OK！');
      expect(jsxText(''), '');
      expect(jsxText(' 前面有空格'), '{" 前面有空格"}');
      expect(jsxText('a{b}'), '{"a{b}"}');
      expect(jsxText('a</script>'), r'{"a<\/script>"}');
      expect(jsxText("it's"), '{"it\'s"}');
    });
  });

  group('自定义组件', () {
    test('参数解构带默认值；接住外面给的 className / style / 事件；不是文字的 prop 显示前先转成文字', () {
      final e = exportReact(frameworkSample());
      final c = e.file('components/TitleCard.jsx')!.content;
      expect(c, contains('export default function TitleCard({ title = "标题", badge = 0, tint = "#FFFFFF", class_prop = "", className, style, ...lcRest }) {'));
      expect(c, contains('<div {...lcRest} className={"lc-card n-c1-k1" + (className ? " " + className : "")} style={{ background: tint || undefined, ...style }}>'));
      expect(c, contains('<p className="lc-text n-c1-k2">{title}</p>'));
      expect(c, contains('<p className="lc-text n-c1-k3">{String(badge)}</p>'));
      expect(c, contains('import "../lc-base.css";\nimport "./TitleCard.css";'));
      final json = frameworkSampleJson();
      (((json['root']! as Map)['children']! as List).last as Map)['props'] = {
        'ref': 'c1',
        'values': {'title': '标题', 'badge': '不是数字', 'tint': '#ffffff', 'class': 'x', 'nope': 1},
      };
      expect(exportReact(docOf(json)).files.first.content, contains('<TitleCard className="lc-component n-n13" class_prop={"x"} />'));
    });

    test('组件最外层是“地址会变的图片”或另一个组件时，也接得住外面给的东西', () {
      final doc = docOf({
        'title': 'p',
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
        'components': [
          {
            'id': 'c1',
            'name': 'Outer',
            'root': {
              'id': 'k1',
              'type': 'component',
              'props': {'ref': 'c2'},
            },
          },
          {
            'id': 'c2',
            'name': 'Pic',
            'props': [
              {'name': 'img', 'type': 'text', 'default': ''},
            ],
            'root': {
              'id': 'k1',
              'type': 'image',
              'bind': {'src': 'img'},
            },
          },
        ],
      });
      final e = exportReact(doc);
      expect(e.file('components/Outer.jsx')!.content, contains('<Pic {...lcRest} className={"lc-component n-c1-k1" + (className ? " " + className : "")} style={style} />'));
      final pic = e.file('components/Pic.jsx')!.content;
      expect(pic, contains('    img ? (\n      <img {...lcRest} className='));
      expect(pic, contains(') : (\n      <div {...lcRest} className='));
      expectSafeJsx(pic);
      expectSafeJsx(e.file('components/Outer.jsx')!.content, components: {'Pic'});
    });

    test('定义找不到：留一行注释并记进说明', () {
      final json = frameworkSampleJson()..remove('components');
      final e = exportReact(docOf(json));
      expect(e.files.length, 3);
      expect(e.files.first.content, contains('{/* 这里原来是一个自定义组件（c1），没有导出'));
      expect(e.notes.any((n) => n.contains('找不到')), isTrue);
      expectSafeJsx(e.files.first.content);
    });

    test('循环引用停下来并记进说明；最外层就是没法导出的组件时返回 null', () {
      final doc = frameworkSample();
      doc.components.add(
        LcComponentDef(
          id: 'c5',
          name: 'Self',
          root: LcNode(id: 'k1', type: 'component', props: {'ref': 'c5'}),
        ),
      );
      doc.root.children.add(LcNode(id: 'n20', type: 'component', props: {'ref': 'c5'}));
      final e = exportReact(doc);
      expect(e.notes.any((n) => n.contains('循环引用')), isTrue);
      final self = e.file('components/Self.jsx')!;
      expect(self.content, contains('    null /* 这里原来是一个自定义组件（c5），没有导出'));
      expect(self.formatProblem, isNull);
      expectSafeJsx(self.content);
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
      final e = exportReact(doc);
      expectSafeJsx(e.files.first.content, components: {'TitleCard'}, props: {'title', 'badge', 'tint'});
      expect(e.file('CounterDemo.css')!.content, isNot(contains('blue')));
      expect(e.notes.any((n) => n.contains('样式没有导出')), isTrue);
      expect(e.notes.any((n) => n.contains('没有挂到任何控件上')), isTrue);
      expect(e.files.every((f) => f.formatProblem == null), isTrue);
    });

    test('控件不支持的属性：读成空的、改的那块跳过；一个事件两个处理包一层；非输入框的“内容变化”用 onInput', () {
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
        {'id': 'h3', 'event': 'input', 'target': 'n2', 'body': <Object?>[]},
        {'id': 'h4', 'event': 'input', 'target': 'n3', 'body': <Object?>[]},
      ];
      final e = exportReact(docOf(json));
      final jsx = e.files.first.content;
      expect(jsx, contains('// 跳过：列表的文字不能用积木改'));
      expect(jsx, contains('lcUi.n1_text = "" /* 卡片的文字读不出来，这里当成空的 */;'));
      expect(jsx, contains('<TitleCard className="lc-component n-n13" style={{ display: lcUi.n13_visible ? undefined : "none" }}'));
      expect(jsx, contains('onClick={lcOn_n5_click}'));
      expect(jsx, contains('  function lcOn_n5_click(event) {\n    onClick_n5_h1(event);\n    onClick_n5_h2(event);\n  }'));
      expect(jsx, contains('<div className="lc-card n-n2" onInput={onInput_n2_h3}>'));
      expect(jsx, contains('<input className="lc-input n-n3" onChange={onInput_n3_h4} placeholder={"你的名字"} />'));
      expectSafeJsx(jsx, components: {'TitleCard'}, props: {'title', 'badge', 'tint'});
    });
  });
}

const String _pageJsx = r'''
// 由 LopiCode 低代码搭建器生成，重新导出会覆盖本文件。
//
// 怎么读这份代码：
// - 页面变量在 lcVars 里，逻辑里读或改到的控件属性在 lcUi 里。它们是 useRef 里的普通对象：读到的永远是最新的值，
//   写完马上生效（请求回来、等一会儿之后也一样）。每次写完调用 lcRefresh()，React 才会重新画界面。
// - 变量改了以后，界面上不会自动跟着变。要让界面变，用“改控件”积木（改的是 lcUi）。
// - 加减乘除一律按数字算：输入框里读到的是文字，会先用 lcNum 转成数字（转不了的当 0）。
// - “等一会儿”“请求网址”只管它们里面的积木：排在它们后面的积木不会等，马上接着做。
import React, { useEffect, useRef, useState } from "react";
import "./lc-base.css";
import "./CounterDemo.css";
import TitleCard from "./components/TitleCard.jsx";

// —— 小工具 ——
/* 小工具 */

export default function CounterDemo() {
  // 页面变量
  const lcVars = useRef({
    count: 0,
    reply: "",
  }).current;
  // 控件属性：逻辑里读或改到的那些（下面的界面绑定着它们）
  const lcUi = useRef({
    n1_text: "点了 0 次",
    n5_bg: "",
    n8_visible: true,
    n9_src: "",
    n7_text: "你好",
    n3_value: "",
    n3_placeholder: "你的名字",
  }).current;
  // 改了上面两样以后调用它，让 React 重新画一遍界面
  const [, lcSetTick] = useState(0);
  function lcRefresh() {
    lcSetTick((n) => n + 1);
  }

  // 点击「按钮“加一”」时
  function onClick_n5_h1(event) {
    lcVars.count = lcVars.count + 1;
    lcRefresh();
    lcUi.n1_text = "点了 " + lcText(lcVars.count) + " 次";
    lcRefresh();
    if (lcVars.count >= 3) {
      lcUi.n5_bg = "#CC3344";
      lcRefresh();
      lcUi.n8_visible = false;
      lcRefresh();
    } else {
      lcUi.n9_src = "b.png";
      lcRefresh();
    }
  }

  // 「输入框“你的名字”」的内容变化时
  function onInput_n3_h2(event) {
    lcUi.n7_text = "你好，" + lcEventValue(event);
    lcRefresh();
  }

  // 点击「按钮“取数据”」时
  function onClick_n6_h3(event) {
    fetch("https://example.com/api", { method: "GET" })
      .then(function (lcRes) {
        if (!lcRes.ok) throw new Error("HTTP " + lcRes.status);
        return lcRes.text();
      })
      .then(function (lcBody) {
        lcVars.reply = lcBody;
        lcRefresh();
        lcUi.n7_text = lcVars.reply + " / " + lcUi.n3_value;
        lcRefresh();
      }, function (lcError) {
        alert("失败了");
      });
  }

  // 页面打开时
  function onLoad_h4() {
    lcUi.n3_placeholder = "写点什么";
    lcRefresh();
  }

  function lcOn_n3_input(event) {
    lcUi.n3_value = lcEventValue(event);
    lcRefresh();
    onInput_n3_h2(event);
  }

  // 页面打开时（只做一次）。开发模式下开着 StrictMode 时 React 会故意做两次，上线后只做一次。
  useEffect(() => {
    onLoad_h4();
  }, []);

  // —— 界面 ——
  return (
    <main className="lc-page n-root">
      <p className="lc-text n-n1">{lcUi.n1_text}</p>
      <div className="lc-card n-n2">
        <input className="lc-input n-n3" onChange={lcOn_n3_input} placeholder={lcUi.n3_placeholder} value={lcUi.n3_value} />
        <div className="lc-row n-n4">
          <button type="button" className="lc-button n-n5" style={{ background: lcUi.n5_bg || undefined }} onClick={onClick_n5_h1}>加一</button>
          <button type="button" className="lc-button n-n6" onClick={onClick_n6_h3}>取数据</button>
        </div>
        <p className="lc-text n-n7">{lcUi.n7_text}</p>
      </div>
      <img className="lc-image n-n8" style={{ display: lcUi.n8_visible ? undefined : "none" }} src={"https://example.com/a.png"} alt="" />
      {lcUi.n9_src ? (
        <img className="lc-image n-n9" src={lcUi.n9_src} alt="" />
      ) : (
        <div className="lc-image n-n9" role="img" aria-label="图片占位"></div>
      )}
      <ul className="lc-list n-n10">
        <li>第一项</li>
        <li>第二项</li>
      </ul>
      <hr className="lc-divider n-n11" />
      <div className="lc-spacer n-n12"></div>
      <TitleCard className="lc-component n-n13" title={"今日推荐"} badge={3} tint={"#FFEEDD"} />
    </main>
  );
}
''';

const String _componentJsx = r'''
// 由 LopiCode 低代码搭建器生成，重新导出会覆盖本文件。
// 自定义组件：Title Card
import React from "react";
import "../lc-base.css";
import "./TitleCard.css";

export default function TitleCard({ title = "标题", badge = 0, tint = "#FFFFFF", class_prop = "", className, style, ...lcRest }) {
  return (
    <div {...lcRest} className={"lc-card n-c1-k1" + (className ? " " + className : "")} style={{ background: tint || undefined, ...style }}>
      <p className="lc-text n-c1-k2">{title}</p>
      <p className="lc-text n-c1-k3">{String(badge)}</p>
    </div>
  );
}
''';
