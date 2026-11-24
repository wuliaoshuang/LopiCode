// 积木翻 JavaScript：每种积木 / 表达式的翻译结果、注入防护、坏数据不崩，以及用 node 真的跑一遍。
//
// 需要 node 的用例在找不到 node 的机器上会跳过（跳过原因会显示在测试输出里），不算失败。
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/lowcode/logic_blocks.dart';
import 'package:lopicode/lowcode/logic_js.dart';
import 'package:lopicode/lowcode/logic_model.dart';
import 'package:lopicode/lowcode/model.dart';

/// 测试页面：n1 文本、n2 按钮、n3 输入框、n4 列表、n5 行（里面 n6 是没填地址的图片）、n7 有地址的图片。
LcDocument makeDoc({List<Map<String, Object?>> variables = const [], List<Map<String, Object?>> handlers = const []}) => LcDocument.parse(
  jsonEncode({
    'title': '测试页',
    'root': {
      'id': 'root',
      'type': 'page',
      'children': [
        {
          'id': 'n1',
          'type': 'text',
          'props': {'text': '0'},
        },
        {
          'id': 'n2',
          'type': 'button',
          'props': {'text': '加一'},
        },
        {
          'id': 'n3',
          'type': 'input',
          'props': {'placeholder': '请输入'},
        },
        {'id': 'n4', 'type': 'list'},
        {
          'id': 'n5',
          'type': 'row',
          'children': [
            {
              'id': 'n6',
              'type': 'image',
              'props': {'src': ''},
            },
          ],
        },
        {
          'id': 'n7',
          'type': 'image',
          'props': {'src': 'a.png'},
        },
      ],
    },
    'logic': {'variables': variables, 'handlers': handlers},
  }),
);

const _vars = [
  {'name': 'count', 'type': 'number', 'initial': 0},
  {'name': 'name', 'type': 'text', 'initial': ''},
  {'name': 'on', 'type': 'bool', 'initial': false},
];

Map<String, Object?> block(String op, Map<String, Object?> args, {List<Object?> body = const [], List<Object?> orElse = const []}) => {'op': op, 'args': args, 'body': body, 'else': orElse};

Map<String, Object?> click(List<Object?> body, {String target = 'n2', String id = 'h1'}) => {'id': id, 'event': 'click', 'target': target, 'body': body};

LcBlock parseBlock(Map<String, Object?> json) => LcBlock.tryParse(jsonDecode(jsonEncode(json)), 0)!;

// —— 用 node 跑的那一套 ——

final bool _hasNode = () {
  try {
    return Process.runSync('node', ['--version']).exitCode == 0;
  } on ProcessException {
    return false; // 这台机器没装 node：相关用例跳过
  }
}();
final Object _skipNode = _hasNode ? false : '找不到 node，跳过“真的跑一遍 / 语法检查”的用例';

late Directory _tmp;
int _fileNo = 0;

/// 极小的假浏览器环境：按 class 找元素、挂事件、弹窗、定时器、请求、跳转，全都只是记下来。
/// `pwn()` 是给注入测试用的“陷阱”：恶意字符串要是被当成代码执行了，就会调到它。
String _fakeDom(LcDocument doc) {
  final els = <String, Object?>{};
  void walk(LcNode n) {
    final tag = switch (n.type) {
      'text' => 'P',
      'button' => 'BUTTON',
      'input' => 'INPUT',
      'list' => 'UL',
      'image' => n.strProp('src') == null ? 'DIV' : 'IMG',
      _ => 'DIV',
    };
    els[n.id] = {'tag': tag, 'text': n.strProp('text') ?? ''};
    n.children.forEach(walk);
  }

  walk(doc.root);
  return '''
let pwned = 0;
function pwn() { pwned++; }
const elements = {};
for (const [id, d] of Object.entries(${jsonEncode(els)})) {
  elements[id] = { tagName: d.tag, textContent: d.text, value: "", placeholder: "", src: "", style: { display: "" }, listeners: {},
    addEventListener(type, fn) { (this.listeners[type] = this.listeners[type] || []).push(fn); } };
}
const ready = [];
const document = {
  readyState: "loading",
  querySelector(sel) {
    const m = /^\\.n-([A-Za-z0-9_]+)\$/.exec(sel);
    if (!m) throw new Error("选择器不对：" + sel);
    return Object.prototype.hasOwnProperty.call(elements, m[1]) ? elements[m[1]] : null;
  },
  addEventListener(type, fn) { if (type === "DOMContentLoaded") ready.push(fn); },
};
const alerts = [], logs = [], timers = [], fetchCalls = [];
const location = { href: "" };
function alert(m) { alerts.push(m); }
const console = { log(...a) { logs.push(a.length === 1 ? a[0] : a); } };
function setTimeout(fn, ms) { timers.push({ fn, ms }); }
function runTimers() { while (timers.length) timers.shift().fn(); }
let fetchReply = () => Promise.resolve({ ok: true, status: 200, text: () => Promise.resolve("响应内容") });
function fetch(url, opts) { fetchCalls.push({ url, method: opts && opts.method }); return fetchReply(url); }
function fire(id, type, value) {
  const el = elements[id];
  if (value !== undefined) el.value = value;
  for (const fn of el.listeners[type] || []) fn({ target: el });
}
const settle = async () => { for (let i = 0; i < 5; i++) await new Promise((r) => setImmediate(r)); };
''';
}

String _writeScript(String source) {
  final file = File('${_tmp.path}/case_${_fileNo++}.js')..writeAsStringSync(source);
  return file.path;
}

/// `node --check`：只查语法。返回错误输出（空＝通过）。
String nodeCheck(String script) {
  final r = Process.runSync('node', ['--check', _writeScript(script)]);
  return r.exitCode == 0 ? '' : '${r.stderr}';
}

/// 把假环境 + 生成的脚本 + 一段“操作步骤”拼起来交给 node 跑，返回跑完以后的状态。
Map<String, dynamic> runInNode(LcDocument doc, String steps, {String? script}) {
  final source =
      '''
${_fakeDom(doc)}
${script ?? exportLogicJs(doc)}
(async () => {
  ready.forEach((fn) => fn());
  $steps
  await settle();
  const view = {};
  for (const [id, el] of Object.entries(elements)) view[id] = { text: el.textContent, value: el.value, display: el.style.display, bg: el.style.background, color: el.style.color, src: el.src, placeholder: el.placeholder, bgImage: el.style.backgroundImage };
  process.stdout.write(JSON.stringify({ state: Object.assign({}, state), own: Object.getOwnPropertyNames(state), view, alerts, logs, href: location.href, fetchCalls, waiting: timers.map((t) => t.ms), pwned, polluted: ({}).polluted === undefined ? 0 : 1 }));
})().catch((e) => { process.stderr.write(String(e && e.stack || e)); process.exit(1); });
''';
  final r = Process.runSync('node', [_writeScript(source)], stdoutEncoding: utf8, stderrEncoding: utf8);
  if (r.exitCode != 0) fail('node 运行失败：\n${r.stderr}');
  final decoded = jsonDecode('${r.stdout}');
  if (decoded is! Map<String, dynamic>) fail('node 的输出不是对象：${r.stdout}');
  return decoded;
}

Map<String, dynamic> _map(Object? v) => v is Map<String, dynamic> ? v : fail('不是对象：$v');

/// 一种“别的导出方式”：变量是 ref（读写 .value），控件属性放在 ui 对象里。用来证明翻译可以换写法。
class _RefTarget extends JsTarget {
  const _RefTarget();
  @override
  String readVar(LcVariable v) => '${v.name}.value';
  @override
  List<String> writeVar(LcVariable v, String valueJs) => ['${v.name}.value = $valueJs;'];
  @override
  JsExpr readProp(LcNode node, String prop) => JsExpr('ui.${node.id}.$prop', prop == 'visible' ? LcType.boolean : LcType.text);
  @override
  List<String> writeProp(LcNode node, String prop, String valueJs) => ['ui.${node.id}.$prop = $valueJs;'];
  @override
  String eventValue() => 'event.target.value';
}

void main() {
  setUpAll(() => _tmp = Directory.systemTemp.createTempSync('lc_logic_js_'));
  tearDownAll(() {
    if (_tmp.existsSync()) _tmp.deleteSync(recursive: true);
  });

  final doc = makeDoc(variables: _vars);
  const dom = DomJsTarget();
  String ex(Object? e, {String event = 'load'}) => exprToJs(e, dom, doc: doc, event: event);
  String bl(Map<String, Object?> b, {String event = 'click'}) => blocksToJs([parseBlock(b)], dom, doc: doc, event: event);

  group('表达式的翻译', () {
    test('字面量', () {
      expect(ex(exText('你好')), '"你好"');
      expect(ex(exNum(3)), '3');
      expect(ex(exNum(1.5)), '1.5');
      expect(ex(exNum(2.0)), '2');
      expect(ex(exNum(-4)), '-4');
      expect(ex(exBool(true)), 'true');
    });

    test('变量、控件属性、输入的内容', () {
      expect(ex(exVar('count')), 'state.count');
      expect(ex(exProp('n3', 'value')), 'lcGet("n3", "value")');
      expect(ex(exProp('n1', 'text')), 'lcGet("n1", "text")');
      expect(ex(exProp('n1', 'visible')), 'lcGet("n1", "visible")');
      expect(ex(exEvent(), event: 'input'), 'lcEventValue(event)');
      expect(ex(exEvent(), event: 'click'), '"" /* 只有“输入内容变化时”才有输入的内容 */');
    });

    test('算术一律按数字算：数字类型的不包，别的先过 lcNum', () {
      expect(ex(exBin('+', exVar('count'), exNum(1))), 'state.count + 1');
      expect(ex(exBin('+', exProp('n3', 'value'), exNum(1))), 'lcNum(lcGet("n3", "value")) + 1');
      expect(ex(exBin('-', exVar('count'), exNum(-1))), 'state.count - (-1)');
      expect(ex(exBin('*', exBin('+', exNum(1), exNum(2)), exText('3'))), '(1 + 2) * lcNum("3")');
      expect(ex(exBin('/', exVar('count'), exNum(2))), 'lcNum(state.count / 2)');
      expect(ex(exBin('%', exVar('count'), exNum(2))), 'lcNum(state.count % 2)');
    });

    test('比较与逻辑', () {
      expect(ex(exBin('>', exVar('count'), exNum(10))), 'state.count > 10');
      expect(ex(exBin('<=', exProp('n3', 'value'), exNum(10))), 'lcNum(lcGet("n3", "value")) <= 10');
      expect(ex(exBin('==', exVar('count'), exNum(10))), 'state.count === 10');
      expect(ex(exBin('!=', exVar('name'), exText('a'))), 'state.name !== "a"');
      // 类型不一样（文字和数字）：交给 lcEq 拉平了比。
      expect(ex(exBin('==', exProp('n3', 'value'), exNum(5))), 'lcEq(lcGet("n3", "value"), 5)');
      expect(ex(exBin('!=', exProp('n3', 'value'), exNum(5))), '!lcEq(lcGet("n3", "value"), 5)');
      expect(ex(exBin('and', exVar('on'), exBin('>', exVar('count'), exNum(0)))), 'state.on && (state.count > 0)');
      expect(ex(exBin('or', exVar('name'), exVar('on'))), '!!state.name || state.on');
      expect(ex(exNot(exVar('on'))), '!state.on');
      expect(ex(exNot(exBin('>', exVar('count'), exNum(0)))), '!(state.count > 0)');
    });

    test('拼成文字', () {
      expect(ex(exJoin([])), '""');
      expect(ex(exJoin([exVar('count')])), 'lcText(state.count)');
      expect(ex(exJoin([exText('共 '), exVar('count'), exText(' 次')])), '"共 " + lcText(state.count) + " 次"');
      expect(ex(exJoin([exBin('+', exNum(1), exNum(2)), exVar('name')])), 'lcText(1 + 2) + state.name');
    });

    test('缺的、坏的、不认识的都翻成 null 加注释，不抛异常', () {
      expect(ex(null), 'null /* 这里还没填 */');
      expect(ex('乱写'), 'null /* 这里还没填 */');
      expect(ex({'e': 'text'}), 'null /* 文字没填 */');
      expect(ex({'e': 'num', 'v': '3'}), 'null /* 数字没填 */');
      expect(ex({'e': 'num', 'v': double.nan}), 'null /* 数字没填 */');
      expect(ex({'e': 'bool', 'v': 1}), 'null /* “是 / 否”没填 */');
      expect(ex(exVar('nope')), 'null /* 没有声明的变量 nope */');
      expect(ex(exProp('n99', 'text')), 'null /* 找不到控件 */');
      expect(ex(exProp('n1', 'bg')), 'null /* 不认识的属性 bg */');
      expect(ex({'e': 'magic', 'x': 1}), 'null /* 不认识的值 magic */');
      expect(ex({'e': 'bin', 'op': '**', 'l': exNum(1), 'r': exNum(2)}), 'null /* 不认识的运算 ** */');
      expect(ex({'e': 'bin', 'op': '+'}), 'lcNum(null /* 这里还没填 */) + lcNum(null /* 这里还没填 */)');
      expect(ex({'e': 'join', 'items': 'x'}), '""');
    });

    test('套得太深的表达式会封顶，不会把栈撑爆', () {
      var e = exNum(1);
      for (var i = 0; i < 5000; i++) {
        e = exNot(e);
      }
      final js = ex(e);
      expect(js, contains('值套得太深'));
      expect(js.length, lessThan(400));
    });
  });

  group('积木的翻译', () {
    test('变量', () {
      expect(bl(block('setVar', {'name': 'count', 'value': exNum(5)})), 'state.count = 5;');
      // 赋值时按变量的类型转换：数字变量收到文字先转数字，文字变量收到数字先转文字，布尔变量按真假。
      expect(bl(block('setVar', {'name': 'count', 'value': exProp('n3', 'value')})), 'state.count = lcNum(lcGet("n3", "value"));');
      expect(bl(block('setVar', {'name': 'name', 'value': exVar('count')})), 'state.name = lcText(state.count);');
      expect(bl(block('setVar', {'name': 'on', 'value': exVar('name')})), 'state.on = !!state.name;');
      expect(bl(block('changeVar', {'name': 'count', 'by': exNum(1)})), 'state.count = state.count + 1;');
      expect(bl(block('changeVar', {'name': 'count', 'by': exNum(-2)})), 'state.count = state.count + (-2);');
      expect(bl(block('changeVar', {'name': 'count', 'by': exProp('n3', 'value')})), 'state.count = state.count + lcNum(lcGet("n3", "value"));');
    });

    test('改控件', () {
      expect(bl(block('setProp', {'node': 'n1', 'prop': 'text', 'value': exVar('count')})), 'lcSet("n1", "text", lcText(state.count));');
      expect(bl(block('setProp', {'node': 'n3', 'prop': 'value', 'value': exText('')})), 'lcSet("n3", "value", "");');
      expect(bl(block('setProp', {'node': 'n5', 'prop': 'visible', 'value': exBool(false)})), 'lcSet("n5", "visible", false);');
      expect(bl(block('setProp', {'node': 'n5', 'prop': 'visible', 'value': exVar('count')})), 'lcSet("n5", "visible", !!state.count);');
      expect(bl(block('setProp', {'node': 'n2', 'prop': 'bg', 'value': exText('#FF0000')})), 'lcSet("n2", "bg", "#FF0000");');
      expect(bl(block('setProp', {'node': 'n2', 'prop': 'color', 'value': exText('#fff')})), 'lcSet("n2", "color", "#fff");');
      expect(bl(block('setProp', {'node': 'n7', 'prop': 'src', 'value': exText('b.png')})), 'lcSet("n7", "src", "b.png");');
      expect(bl(block('setProp', {'node': 'n3', 'prop': 'placeholder', 'value': exText('写点什么')})), 'lcSet("n3", "placeholder", "写点什么");');
    });

    test('这种控件没有的属性翻成注释（列表的文字、容器的文字、按钮的输入内容）', () {
      expect(bl(block('setProp', {'node': 'n4', 'prop': 'text', 'value': exText('x')})), '// 跳过：列表的文字不能用积木改（导出的是 <ul>，整段换文字会把里面的内容冲掉）');
      expect(bl(block('setProp', {'node': 'n5', 'prop': 'text', 'value': exText('x')})), startsWith('// 跳过：行的文字不能用积木改'));
      expect(bl(block('setProp', {'node': 'n2', 'prop': 'value', 'value': exText('x')})), '// 跳过：按钮没有“输入内容”');
      expect(bl(block('setProp', {'node': 'n1', 'prop': 'src', 'value': exText('x')})), '// 跳过：文本没有“图片地址”');
    });

    test('如果 / 否则', () {
      expect(
        bl(
          block(
            'if',
            {'cond': exBin('>', exVar('count'), exNum(10))},
            body: [
              block('alert', {'message': exText('大')}),
            ],
            orElse: [
              block('alert', {'message': exText('小')}),
            ],
          ),
        ),
        'if (state.count > 10) {\n  alert("大");\n} else {\n  alert("小");\n}',
      );
      expect(bl(block('if', {'cond': exVar('on')})), 'if (state.on) {\n}');
    });

    test('重复：封顶 10000 次，嵌套时循环变量不重名', () {
      expect(
        bl(
          block(
            'repeat',
            {'times': exNum(3)},
            body: [
              block(
                'repeat',
                {'times': exProp('n3', 'value')},
                body: [
                  block('changeVar', {'name': 'count', 'by': exNum(1)}),
                ],
              ),
            ],
          ),
        ),
        'for (let lcI1 = 0, lcN1 = Math.min(3, 10000); lcI1 < lcN1; lcI1++) {\n'
        '  for (let lcI2 = 0, lcN2 = Math.min(lcNum(lcGet("n3", "value")), 10000); lcI2 < lcN2; lcI2++) {\n'
        '    state.count = state.count + 1;\n'
        '  }\n'
        '}',
      );
    });

    test('等一会儿、弹提示、跳转、写控制台', () {
      expect(
        bl(
          block(
            'wait',
            {'ms': exNum(500)},
            body: [
              block('log', {'value': exVar('count')}),
            ],
          ),
        ),
        'setTimeout(function () {\n  console.log(state.count);\n}, Math.max(0, 500));',
      );
      expect(bl(block('alert', {'message': exVar('count')})), 'alert(lcText(state.count));');
      expect(bl(block('navigate', {'url': exText('https://example.com/a?b=1')})), 'location.href = "https://example.com/a?b=1";');
      expect(bl(block('log', {'value': exText('到这了')})), 'console.log("到这了");');
    });

    test('请求网址', () {
      expect(
        bl(
          block(
            'fetch',
            {'url': exText('/api'), 'method': 'POST', 'into': 'name'},
            body: [
              block('setProp', {'node': 'n1', 'prop': 'text', 'value': exVar('name')}),
            ],
            orElse: [
              block('alert', {'message': exText('失败')}),
            ],
          ),
        ),
        'fetch("/api", { method: "POST" })\n'
        '  .then(function (lcRes) {\n'
        '    if (!lcRes.ok) throw new Error("HTTP " + lcRes.status);\n'
        '    return lcRes.text();\n'
        '  })\n'
        '  .then(function (lcBody) {\n'
        '    state.name = lcBody;\n'
        '    lcSet("n1", "text", state.name);\n'
        '  }, function (lcError) {\n'
        '    alert("失败");\n'
        '  });',
      );
      // 结果放进数字变量：先转数字。不填 into：不存。method 乱写当 GET。
      expect(bl(block('fetch', {'url': exText('/n'), 'method': 'GET', 'into': 'count'})), contains('state.count = lcNum(lcBody);'));
      final plain = bl(block('fetch', {'url': exText('/n'), 'method': 'DELETE"})//', 'into': ''}));
      expect(plain, startsWith('fetch("/n", { method: "GET" })'));
      expect(plain, isNot(contains('state.')));
      expect(bl(block('fetch', {'url': exText('/n'), 'method': 'GET', 'into': 'nope'})), contains('// 变量 nope 没有声明，结果没有存'));
    });

    test('不认识的积木、没声明的变量、找不到的控件：翻成一行注释', () {
      expect(bl(block('teleport', {'to': 'mars'})), '// 不认识的积木：teleport（已跳过）');
      expect(bl(block('setVar', {'name': 'nope', 'value': exNum(1)})), '// 跳过「把 nope 设为 1」：变量没有声明');
      expect(bl(block('changeVar', {'name': 'name', 'by': exNum(1)})), '// 跳过「把 name 加上 1」：这个变量不是数字');
      expect(bl(block('setProp', {'node': 'n99', 'prop': 'text', 'value': exText('x')})), '// 跳过「把 「已删除的控件」的文字 改成 “x”」：找不到控件');
      expect(bl(block('setProp', {'node': 'n1', 'prop': 'font', 'value': exText('x')})), startsWith('// 跳过'));
    });

    test('换一种写法（ref.value + ui 对象）：流程和运算照旧，只有读写变了', () {
      const ref = _RefTarget();
      expect(exprToJs(exBin('+', exVar('count'), exProp('n3', 'value')), ref, doc: doc), 'count.value + lcNum(ui.n3.value)');
      expect(exprToJs(exEvent(), ref, doc: doc, event: 'input'), 'event.target.value');
      expect(
        blocksToJs(
          [
            parseBlock(
              block(
                'if',
                {'cond': exVar('on')},
                body: [
                  block('changeVar', {'name': 'count', 'by': exNum(1)}),
                  block('setProp', {'node': 'n1', 'prop': 'text', 'value': exVar('count')}),
                ],
              ),
            ),
          ],
          ref,
          doc: doc,
          indent: 1,
        ),
        '  if (on.value) {\n    count.value = count.value + 1;\n    ui.n1.text = lcText(count.value);\n  }',
      );
    });
  });

  group('整份脚本', () {
    test('没有变量也没有处理：返回空字符串', () {
      expect(exportLogicJs(makeDoc()), '');
      expect(exportLogicJs(LcDocument.starter('新页面')), '');
    });

    test('长什么样：state、具名函数、lcStart 里挂事件和调用 load 处理', () {
      final d = makeDoc(
        variables: _vars,
        handlers: [
          click([
            block('changeVar', {'name': 'count', 'by': exNum(1)}),
          ]),
          {
            'id': 'h2',
            'event': 'input',
            'target': 'n3',
            'body': [
              block('setVar', {'name': 'name', 'value': exEvent()}),
            ],
          },
          {
            'id': 'h3',
            'event': 'load',
            'body': [
              block('log', {'value': exText('开始')}),
            ],
          },
          {'id': 'h4', 'event': 'click', 'target': 'n99', 'body': <Object?>[]},
        ],
      );
      final js = exportLogicJs(d);
      expect(js, startsWith('// 由 LopiCode 低代码搭建器生成'));
      expect(js, contains('界面上不会自动跟着变'));
      expect(js, contains('const state = {\n  count: 0,\n  name: "",\n  on: false,\n};'));
      expect(js, contains('// 点击「按钮“加一”」时\nfunction onClick_n2_h1(event) {\n  state.count = state.count + 1;\n}'));
      expect(js, contains('// 「输入框“请输入”」的内容变化时\nfunction onInput_n3_h2(event) {\n  state.name = lcEventValue(event);\n}'));
      expect(js, contains('// 页面打开时\nfunction onLoad_h3() {\n  console.log("开始");\n}'));
      expect(
        js,
        contains(
          'function lcStart() {\n'
          '  lcOn("n2", "click", onClick_n2_h1);\n'
          '  lcOn("n3", "input", onInput_n3_h2);\n'
          '  onLoad_h3();\n'
          '  // onClick_n99_h4：触发它的控件不在页面里，没有挂上\n'
          '}',
        ),
      );
      expect(js, contains('document.addEventListener("DOMContentLoaded", lcStart);'));
      expect(logicHandlerNames(d), ['onClick_n2_h1', 'onInput_n3_h2', 'onLoad_h3', 'onClick_n99_h4']);
      // 每行都没有行尾空格，缩进都是两个空格的倍数。
      for (final line in js.split('\n')) {
        expect(line, isNot(endsWith(' ')), reason: line);
        expect((line.length - line.trimLeft().length).isEven, isTrue, reason: line);
      }
    });

    test('只有变量、没有处理也生成（之后加处理不用改引入）', () {
      final js = exportLogicJs(makeDoc(variables: _vars));
      expect(js, contains('const state = {'));
      expect(js, contains('function lcStart() {\n}'));
    });

    test('处理的 id 被改坏了：函数名里只留安全的字符，重名的加序号', () {
      final d = makeDoc(
        variables: _vars,
        handlers: [
          click([]),
          click([], id: 'h2'),
        ],
      );
      d.logic.handlers[0].id = 'a-b(){}';
      d.logic.handlers[1].id = 'a_b____';
      expect(logicHandlerNames(d), ['onClick_n2_a_b____', 'onClick_n2_a_b_____2']);
    });
  });

  group('注入防护', () {
    test('jsString：引号、反斜杠、换行、</script>、U+2028/2029、<!-- 都转义', () {
      expect(jsString('a"b\\c\nd'), r'"a\"b\\c\nd"');
      expect(jsString('</script><!--'), r'"<\/script><\!--"');
      expect(jsString('x\u2028y\u2029z'), r'"x\u2028y\u2029z"');
      expect(jsString('`\${1}`'), '"`\${1}`"');
      // 落单的代理项（半个表情）也能安全写出来。
      expect(jsString(String.fromCharCode(0xD83D)), r'"\ud83d"');
    });

    test('jsComment：换行类字符、*/、</ 都拆掉，过长截断', () {
      expect(jsComment('a\nb\r\nc\u2028d\u2029e'), 'a b c d e');
      expect(jsComment('x */ alert(1) /* y'), 'x * / alert(1) /* y');
      expect(jsComment('</script><!--'), '< /script>< !--');
      expect(jsComment('*' * 300).runes.length, 121);
      // 截断正好切在 * 和 / 之间也不会留下 */。
      expect(jsComment('${'a' * 119}*/', 120), isNot(contains('*/')));
      expect(jsComment('***///***///'), isNot(contains('*/')));
    });

    test('标识符判断', () {
      expect(isJsIdentifier('count_1'), isTrue);
      expect(isJsIdentifier('1a'), isFalse);
      expect(isJsIdentifier('a-b'), isFalse);
      expect(isJsIdentifier('__proto__'), isFalse);
      expect(isJsIdentifier('a;alert(1)'), isFalse);
      expect(isJsBindingName('class'), isFalse);
      expect(isJsBindingName('count'), isTrue);
      expect(isSafeNodeId('n3'), isTrue);
      expect(isSafeNodeId('n3"]'), isFalse);
    });

    const evil = <String>[
      '</script><script>pwn()</script>',
      '`\${pwn()}`',
      '"; pwn(); "',
      "'; pwn(); '",
      '\\"; pwn(); //',
      '\n pwn(); \r\n pwn();',
      '*/ pwn(); /*',
      '\u2028pwn();\u2029pwn();',
      '<!-- pwn() -->',
      '\\',
      '\\u0022; pwn(); //',
    ];

    /// 一份到处塞了恶意字符串的文档：文字、网址、变量初始值、变量名、控件 id、处理 id、不认识的积木 / 表达式、枚举参数。
    LcDocument evilDoc(String s) {
      final d = makeDoc(
        variables: [
          {'name': 'bad', 'type': 'text', 'initial': s},
          {'name': 'count', 'type': 'number', 'initial': 0},
        ],
        handlers: [
          click([
            block('alert', {'message': exText(s)}),
            block('alert', {'message': exVar('bad')}),
            block('log', {
              'value': exJoin([exText(s), exText(s)]),
            }),
            block('setProp', {'node': 'n1', 'prop': 'text', 'value': exText(s)}),
            block('setProp', {'node': s, 'prop': 'text', 'value': exText('x')}),
            block('setProp', {'node': 'n1', 'prop': s, 'value': exText('x')}),
            block('setVar', {'name': s, 'value': exText('x')}),
            block('setVar', {'name': 'bad', 'value': exVar(s)}),
            block('navigate', {'url': exText(s)}),
            block(s, {'x': s}),
            block('log', {
              'value': {'e': s, 'v': s},
            }),
            block('log', {'value': exProp(s, 'text')}),
            block('log', {'value': exProp('n1', s)}),
            block('log', {
              'value': {'e': 'bin', 'op': s, 'l': exNum(1), 'r': exNum(2)},
            }),
            block(
              'fetch',
              {'url': exText(s), 'method': s, 'into': s},
              body: [
                block('alert', {'message': exText(s)}),
              ],
            ),
            // 最后再把变量改成恶意字符串，看它是不是原样存进去了。
            block('setVar', {'name': 'bad', 'value': exText(s)}),
          ]),
        ],
      );
      // 内存里把名字 / id 改坏（读文件时这些会被拦住，这里绕过去）。
      d.logic.variables.add(LcVariable(name: s, type: 'text', initial: s));
      d.logic.handlers.add(
        LcHandler(
          id: s,
          event: 'click',
          target: s,
          body: [
            parseBlock(block('setVar', {'name': s, 'value': exText('改过')})),
          ],
        ),
      );
      d.logic.handlers.add(LcHandler(id: 'hx', event: s, target: 'n1'));
      return d;
    }

    test('恶意字符串进不了代码：脚本里没有裸的 </script、U+2028/2029，注释不会被撑破', () {
      for (final s in evil) {
        final js = exportLogicJs(evilDoc(s));
        expect(js.toLowerCase(), isNot(contains('</script')), reason: s);
        expect(js, isNot(contains('<!--')), reason: s);
        expect(js, isNot(contains('\u2028')), reason: s);
        expect(js, isNot(contains('\u2029')), reason: s);
        expect(js, isNot(contains('\r')), reason: s);
      }
    });

    test('node --check：含恶意字符串的脚本语法都正确', () {
      for (final s in evil) {
        expect(nodeCheck(exportLogicJs(evilDoc(s))), '', reason: s);
      }
    }, skip: _skipNode);

    test('node 真跑：恶意字符串被当作数据原样输出，陷阱函数一次都没被调到', () {
      for (final s in evil) {
        final d = evilDoc(s);
        final out = runInNode(d, 'fire("n2", "click");');
        expect(out['pwned'], 0, reason: s);
        expect(out['alerts'], [s, s, s], reason: s); // 字面量、变量初始值、请求成功后
        expect((out['logs'] as List).first, s + s, reason: s);
        expect(_map(_map(out['view'])['n1'])['text'], s, reason: s);
        expect(out['href'], s, reason: s);
        expect(_map((out['fetchCalls'] as List).single), {'url': s, 'method': 'GET'}, reason: s);
        final state = _map(out['state']);
        expect(state['bad'], s, reason: s);
        expect(state[s], '响应内容', reason: s); // 名字乱七八糟的变量也只是 state 的一个键（请求结果放进了它）
      }
    }, skip: _skipNode);

    test('变量叫 __proto__ 也只是一个普通的键，不会动到原型', () {
      final d = makeDoc(
        variables: _vars,
        handlers: [
          {
            'id': 'h1',
            'event': 'load',
            'body': [
              block('setVar', {'name': '__proto__', 'value': exText('polluted')}),
              block('alert', {'message': exVar('__proto__')}),
            ],
          },
        ],
      );
      d.logic.variables.add(LcVariable(name: '__proto__', type: 'text', initial: 'x'));
      final js = exportLogicJs(d);
      expect(js, contains('  ["__proto__"]: "x",'));
      expect(js, contains('state["__proto__"] = "polluted";'));
      if (_hasNode) {
        final out = runInNode(d, '');
        expect(out['alerts'], ['polluted']);
        expect(out['own'], contains('__proto__'));
        expect(out['polluted'], 0);
      }
    });

    test('控件 id 在内存里被改坏：不拼进选择器，相关的积木和事件都跳过', () {
      final d = makeDoc(
        variables: _vars,
        handlers: [
          click([
            block('setProp', {'node': 'n1', 'prop': 'text', 'value': exText('x')}),
            block('log', {'value': exProp('n1', 'text')}),
          ]),
        ],
      );
      d.find('n1')!.id = 'x"),pwn(),("';
      d.find('n2')!.id = 'y y';
      final b = d.logic.handlers.single.body;
      b[0].args['node'] = 'x"),pwn(),("';
      b[1].args['value'] = exProp('x"),pwn(),("', 'text');
      d.logic.handlers.single.target = 'y y';
      final js = exportLogicJs(d);
      expect(js, isNot(contains('lcSet("')));
      expect(js, isNot(contains('lcOn("')));
      expect(js, contains('console.log(null /* 找不到控件 */);'));
      expect(js, contains('触发它的控件不在页面里，没有挂上'));
    });
  });

  group('坏数据不崩', () {
    /// args 缺失、类型乱写、body 放错地方的各种积木。
    List<LcBlock> junk() => [
      for (final op in [...lcBlockSpecs.keys, 'what']) ...[
        LcBlock(op: op),
        LcBlock(
          op: op,
          args: {
            'name': 3,
            'value': 'x',
            'by': <Object?>[],
            'node': <String, Object?>{},
            'prop': null,
            'cond': 0,
            'times': '9',
            'ms': true,
            'message': [1],
            'url': {'e': 1},
            'method': 7,
            'into': <String, Object?>{},
          },
        ),
        LcBlock(
          op: op,
          args: {
            'name': 'count',
            'value': {'e': 'bin'},
            'by': {'e': 'join'},
            'node': 'n1',
            'prop': 'visible',
            'cond': {'e': 'not'},
            'times': {'e': 'prop'},
            'ms': {'e': 'var'},
            'message': {'e': 'event'},
            'url': {'e': 'bin', 'op': 5, 'l': 1, 'r': <Object?>[]},
            'method': 'GET',
            'into': 'count',
          },
          body: [LcBlock(op: op)],
          orElse: [LcBlock(op: 'if')],
        ),
      ],
    ];

    test('exportLogicJs 不抛异常', () {
      for (final event in LcHandler.events) {
        final d = makeDoc(variables: _vars);
        d.logic.handlers.add(LcHandler(id: 'h1', event: event, target: event == 'load' ? null : 'n3', body: junk()));
        expect(() => exportLogicJs(d), returnsNormally);
      }
    });

    test('套了 40 层的积木：超过上限的翻成注释', () {
      var b = LcBlock(op: 'alert', args: {'message': exText('最里面')});
      for (var i = 0; i < 40; i++) {
        b = LcBlock(op: 'if', args: {'cond': exBool(true)}, body: [b]);
      }
      final d = makeDoc(variables: _vars);
      d.logic.handlers.add(LcHandler(id: 'h1', event: 'load', body: [b]));
      final js = exportLogicJs(d);
      expect(js, contains('积木套得太深，这里面的 1 块没有翻译'));
      expect(js, isNot(contains('最里面')));
      if (_hasNode) expect(nodeCheck(js), '');
    });

    test('node --check：坏数据生成的脚本语法仍然正确，而且能跑完', () {
      for (final event in LcHandler.events) {
        final d = makeDoc(variables: _vars);
        d.logic.handlers.add(LcHandler(id: 'h1', event: event, target: event == 'load' ? null : 'n3', body: junk()));
        expect(nodeCheck(exportLogicJs(d)), '', reason: event);
        final out = runInNode(d, event == 'load' ? 'runTimers();' : 'fire("n3", "$event", "12"); runTimers();');
        expect(out['pwned'], 0);
      }
    }, skip: _skipNode);
  });

  group('用 node 真的跑', () {
    test('计数器：点一下加一，并把数字写到文本上', () {
      final d = makeDoc(
        variables: _vars,
        handlers: [
          click([
            block('changeVar', {'name': 'count', 'by': exNum(1)}),
            block('setProp', {
              'node': 'n1',
              'prop': 'text',
              'value': exJoin([exText('点了 '), exVar('count'), exText(' 次')]),
            }),
          ]),
        ],
      );
      final out = runInNode(d, 'fire("n2", "click"); fire("n2", "click"); fire("n2", "click");');
      expect(_map(out['state'])['count'], 3);
      expect(_map(_map(out['view'])['n1'])['text'], '点了 3 次');
      // 没点的时候什么都不变（变量改了界面不会自己变，也没有多余的副作用）。
      final idle = runInNode(d, '');
      expect(_map(idle['state'])['count'], 0);
      expect(_map(_map(idle['view'])['n1'])['text'], '0');
    }, skip: _skipNode);

    test('条件分支：超过 2 走“那么”，否则走“否则”', () {
      final d = makeDoc(
        variables: _vars,
        handlers: [
          click([
            block('changeVar', {'name': 'count', 'by': exNum(1)}),
            block(
              'if',
              {'cond': exBin('>', exVar('count'), exNum(2))},
              body: [
                block('alert', {'message': exText('多了')}),
              ],
              orElse: [
                block('alert', {
                  'message': exJoin([exText('第'), exVar('count')]),
                }),
              ],
            ),
          ]),
        ],
      );
      final out = runInNode(d, 'for (let i = 0; i < 4; i++) fire("n2", "click");');
      expect(out['alerts'], ['第1', '第2', '多了', '多了']);
    }, skip: _skipNode);

    test('重复：做 N 遍；次数从输入框来（文字转数字）；封顶 10000；负数、乱写的当 0', () {
      LcDocument d(Object times) => makeDoc(
        variables: _vars,
        handlers: [
          click([
            block(
              'repeat',
              {'times': times},
              body: [
                block('changeVar', {'name': 'count', 'by': exNum(2)}),
              ],
            ),
          ]),
        ],
      );
      expect(_map(runInNode(d(exNum(5)), 'fire("n2", "click");')['state'])['count'], 10);
      expect(_map(runInNode(d(exProp('n3', 'value')), 'elements.n3.value = " 4 "; fire("n2", "click");')['state'])['count'], 8);
      expect(_map(runInNode(d(exNum(99999999)), 'fire("n2", "click");')['state'])['count'], 20000);
      expect(_map(runInNode(d(exNum(-3)), 'fire("n2", "click");')['state'])['count'], 0);
      expect(_map(runInNode(d(exText('abc')), 'fire("n2", "click");')['state'])['count'], 0);
    }, skip: _skipNode);

    test('改控件：文字、显示 / 隐藏、颜色、图片地址、提示文字、输入内容；读回来也对', () {
      final d = makeDoc(
        variables: _vars,
        handlers: [
          click([
            block('setProp', {'node': 'n1', 'prop': 'text', 'value': exNum(7)}),
            block('setProp', {'node': 'n5', 'prop': 'visible', 'value': exBool(false)}),
            block('setVar', {'name': 'on', 'value': exProp('n5', 'visible')}),
            block('setProp', {'node': 'n2', 'prop': 'bg', 'value': exText('#FF0000')}),
            block('setProp', {'node': 'n2', 'prop': 'color', 'value': exText('#FFFFFF')}),
            block('setProp', {'node': 'n7', 'prop': 'src', 'value': exText('b.png')}),
            block('setProp', {'node': 'n6', 'prop': 'src', 'value': exText('c "x".png')}),
            block('setProp', {'node': 'n3', 'prop': 'placeholder', 'value': exText('写点什么')}),
            block('setProp', {'node': 'n3', 'prop': 'value', 'value': exText('默认')}),
            block('setVar', {'name': 'name', 'value': exProp('n1', 'text')}),
            // 列表的文字不支持：翻成注释，列表不受影响。
            block('setProp', {'node': 'n4', 'prop': 'text', 'value': exText('不该出现')}),
          ]),
          click(
            [
              block('setProp', {'node': 'n5', 'prop': 'visible', 'value': exBool(true)}),
            ],
            target: 'n1',
            id: 'h2',
          ),
        ],
      );
      final out = runInNode(d, 'fire("n2", "click");');
      final view = _map(out['view']);
      expect(_map(view['n1'])['text'], '7');
      expect(_map(view['n5'])['display'], 'none');
      expect(_map(view['n2'])['bg'], '#FF0000');
      expect(_map(view['n2'])['color'], '#FFFFFF');
      expect(_map(view['n7'])['src'], 'b.png');
      expect(_map(view['n6'])['src'], '', reason: '占位的 div 没有 src');
      expect(_map(view['n6'])['bgImage'], r'url("c \"x\".png")');
      expect(_map(view['n3'])['placeholder'], '写点什么');
      expect(_map(view['n3'])['value'], '默认');
      expect(_map(view['n4'])['text'], '');
      expect(_map(out['state'])['on'], false);
      expect(_map(out['state'])['name'], '7');
      // 再显示出来：display 清空（让样式表里的 flex 重新生效），而不是写死成 block。
      final shown = runInNode(d, 'fire("n2", "click"); fire("n1", "click");');
      expect(_map(_map(shown['view'])['n5'])['display'], '');
    }, skip: _skipNode);

    test('输入框联动：打字时把内容存进变量并显示到文本上；算术把文字转成数字', () {
      final d = makeDoc(
        variables: _vars,
        handlers: [
          {
            'id': 'h1',
            'event': 'input',
            'target': 'n3',
            'body': [
              block('setVar', {'name': 'name', 'value': exEvent()}),
              block('setVar', {'name': 'count', 'value': exBin('*', exEvent(), exNum(2))}),
              block('setProp', {
                'node': 'n1',
                'prop': 'text',
                'value': exJoin([exText('你好，'), exVar('name'), exText('！翻倍是 '), exVar('count')]),
              }),
              block('setVar', {'name': 'on', 'value': exBin('==', exEvent(), exNum(21))}),
            ],
          },
        ],
      );
      final out = runInNode(d, 'fire("n3", "input", "2"); fire("n3", "input", "21");');
      expect(_map(out['state']), {'count': 42, 'name': '21', 'on': true});
      expect(_map(_map(out['view'])['n1'])['text'], '你好，21！翻倍是 42');
      // 不是数字的文字当 0。
      final nan = runInNode(d, 'fire("n3", "input", "abc");');
      expect(_map(nan['state']), {'count': 0, 'name': 'abc', 'on': false});
    }, skip: _skipNode);

    test('数字和文字的规则：浮点误差不外露、除以 0 存成 0、"5" 等于 5、文字相加按数字', () {
      final d = makeDoc(
        variables: [
          ..._vars,
          {'name': 'out', 'type': 'text', 'initial': ''},
        ],
        handlers: [
          {
            'id': 'h1',
            'event': 'load',
            'body': [
              block('setVar', {'name': 'out', 'value': exBin('+', exNum(0.1), exNum(0.2))}),
              block('alert', {'message': exVar('out')}),
              block('setVar', {'name': 'count', 'value': exBin('/', exNum(1), exNum(0))}),
              block('alert', {'message': exVar('count')}),
              block('alert', {'message': exBin('==', exText('5'), exNum(5))}),
              block('alert', {'message': exBin('+', exText('2'), exText('3'))}),
              block('alert', {
                'message': exJoin([exText('2'), exText('3')]),
              }),
              block('alert', {'message': exBin('and', exText('有字'), exNot(exText('')))}),
            ],
          },
        ],
      );
      expect(runInNode(d, '')['alerts'], ['0.3', '0', 'true', '5', '23', 'true']);
    }, skip: _skipNode);

    test('请求：成功把响应放进变量再做“成功后”；失败（连不上 / 状态码不对）做“失败后”', () {
      final d = makeDoc(
        variables: _vars,
        handlers: [
          click([
            block(
              'fetch',
              {
                'url': exJoin([exText('/api?n='), exVar('count')]),
                'method': 'POST',
                'into': 'name',
              },
              body: [
                block('setProp', {'node': 'n1', 'prop': 'text', 'value': exVar('name')}),
              ],
              orElse: [
                block('setProp', {'node': 'n1', 'prop': 'text', 'value': exText('失败了')}),
              ],
            ),
            // 排在请求后面的积木不等请求回来。
            block('changeVar', {'name': 'count', 'by': exNum(1)}),
          ]),
        ],
      );
      final ok = runInNode(d, 'fire("n2", "click");');
      expect(ok['fetchCalls'], [
        {'url': '/api?n=0', 'method': 'POST'},
      ]);
      expect(_map(ok['state'])['name'], '响应内容');
      expect(_map(ok['state'])['count'], 1);
      expect(_map(_map(ok['view'])['n1'])['text'], '响应内容');

      final down = runInNode(d, 'fetchReply = () => Promise.reject(new Error("连不上")); fire("n2", "click");');
      expect(_map(down['state'])['name'], '');
      expect(_map(_map(down['view'])['n1'])['text'], '失败了');

      final http500 = runInNode(d, 'fetchReply = () => Promise.resolve({ ok: false, status: 500, text: () => Promise.resolve("错误页") }); fire("n2", "click");');
      expect(_map(http500['state'])['name'], '');
      expect(_map(_map(http500['view'])['n1'])['text'], '失败了');
    }, skip: _skipNode);

    test('等一会儿：里面的到点才做，后面的不等；时间是负数当 0', () {
      final d = makeDoc(
        variables: _vars,
        handlers: [
          click([
            block(
              'wait',
              {'ms': exNum(1500)},
              body: [
                block('setVar', {'name': 'name', 'value': exText('到点了')}),
              ],
            ),
            block(
              'wait',
              {'ms': exNum(-5)},
              body: [
                block('changeVar', {'name': 'count', 'by': exNum(10)}),
              ],
            ),
            block('changeVar', {'name': 'count', 'by': exNum(1)}),
          ]),
        ],
      );
      final before = runInNode(d, 'fire("n2", "click");');
      expect(_map(before['state']), {'count': 1, 'name': '', 'on': false});
      expect(before['waiting'], [1500, 0]);
      final after = runInNode(d, 'fire("n2", "click"); runTimers();');
      expect(_map(after['state']), {'count': 11, 'name': '到点了', 'on': false});
    }, skip: _skipNode);

    test('页面打开时的处理、跳转、控制台；挂在不存在的控件上的处理不报错', () {
      final d = makeDoc(
        variables: _vars,
        handlers: [
          {
            'id': 'h1',
            'event': 'load',
            'body': [
              block('log', {'value': exVar('count')}),
              block('setProp', {'node': 'n1', 'prop': 'text', 'value': exText('欢迎')}),
            ],
          },
          click([
            block('navigate', {'url': exText('https://example.com/')}),
          ]),
          click(
            [
              block('alert', {'message': exText('不该弹')}),
            ],
            target: 'gone',
            id: 'h3',
          ),
        ],
      );
      final out = runInNode(d, 'fire("n2", "click");');
      expect(out['logs'], [0]);
      expect(_map(_map(out['view'])['n1'])['text'], '欢迎');
      expect(out['href'], 'https://example.com/');
      expect(out['alerts'], isEmpty);
    }, skip: _skipNode);

    test('页面上少了元素（HTML 和逻辑对不上）：安静跳过，不抛错', () {
      final d = makeDoc(
        variables: _vars,
        handlers: [
          click([
            block('setProp', {'node': 'n1', 'prop': 'text', 'value': exText('x')}),
            block('setVar', {'name': 'name', 'value': exProp('n1', 'text')}),
            block('setVar', {'name': 'on', 'value': exProp('n1', 'visible')}),
            block('changeVar', {'name': 'count', 'by': exNum(1)}),
          ]),
          click([], target: 'n1', id: 'h2'),
        ],
      );
      final out = runInNode(d, 'fire("n2", "click");', script: 'delete elements.n1;\n${exportLogicJs(d)}');
      expect(_map(out['state']), {'count': 1, 'name': '', 'on': false});
    }, skip: _skipNode);

    test('页面已经准备好了才加载脚本（没走 DOMContentLoaded）：直接开始', () {
      final d = makeDoc(
        variables: _vars,
        handlers: [
          click([
            block('changeVar', {'name': 'count', 'by': exNum(1)}),
          ]),
        ],
      );
      final out = runInNode(d, 'fire("n2", "click");', script: 'document.readyState = "complete";\n${exportLogicJs(d)}');
      expect(_map(out['state'])['count'], 1);
    }, skip: _skipNode);
  });
}
