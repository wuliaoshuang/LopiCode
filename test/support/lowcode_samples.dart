// Vue / React 导出测试共用的样本页面。
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/lowcode/logic_expr.dart';
import 'package:lopicode/lowcode/logic_model.dart';
import 'package:lopicode/lowcode/model.dart';

export 'package:lopicode/lowcode/logic_expr.dart';

Map<String, Object?> blk(String op, Map<String, Object?> args, {List<Object?> body = const [], List<Object?> orElse = const []}) => {'op': op, 'args': args, 'body': body, 'else': orElse};

/// 固定样本：文本、按钮、输入框、图片、列表、容器嵌套、自定义 style、计数器、输入联动、如果、请求、一个自定义组件实例。
Map<String, Object?> frameworkSampleJson() => {
  'version': 2,
  'title': 'Counter Demo',
  'root': {
    'id': 'root',
    'type': 'page',
    'props': {'padding': 16, 'gap': 12, 'bg': '#F6FBFD'},
    'children': [
      {
        'id': 'n1',
        'type': 'text',
        'props': {'text': '点了 0 次', 'fontSize': 24, 'bold': true},
        'style': {'letter-spacing': '1px', 'margin-top': '8px'},
      },
      {
        'id': 'n2',
        'type': 'card',
        'props': {'padding': 16, 'gap': 8, 'bg': '#FFFFFF', 'radius': 12, 'width': 'fill'},
        'children': [
          {
            'id': 'n3',
            'type': 'input',
            'props': {'placeholder': '你的名字', 'width': 'fill'},
          },
          {
            'id': 'n4',
            'type': 'row',
            'props': {'gap': 8, 'width': 'fill'},
            'children': [
              {
                'id': 'n5',
                'type': 'button',
                'props': {'text': '加一', 'bg': '#058654', 'color': '#FFFFFF', 'padding': 12, 'radius': 8},
              },
              {
                'id': 'n6',
                'type': 'button',
                'props': {'text': '取数据', 'padding': 12},
              },
            ],
          },
          {
            'id': 'n7',
            'type': 'text',
            'props': {'text': '你好'},
          },
        ],
      },
      {
        'id': 'n8',
        'type': 'image',
        'props': {'src': 'https://example.com/a.png', 'height': 120, 'width': 'fill'},
      },
      {
        'id': 'n9',
        'type': 'image',
        'props': {'height': 80},
      },
      {
        'id': 'n10',
        'type': 'list',
        'props': {
          'items': ['第一项', '第二项'],
        },
      },
      {'id': 'n11', 'type': 'divider'},
      {
        'id': 'n12',
        'type': 'spacer',
        'props': {'size': 8},
      },
      {
        'id': 'n13',
        'type': 'component',
        'props': {
          'ref': 'c1',
          'values': {'title': '今日推荐', 'badge': 3, 'tint': '#FFEEDD'},
          'width': 'fill',
        },
      },
    ],
  },
  'logic': {
    'variables': [
      {'name': 'count', 'type': 'number', 'initial': 0},
      {'name': 'reply', 'type': 'text', 'initial': ''},
    ],
    'handlers': [
      {
        'id': 'h1',
        'event': 'click',
        'target': 'n5',
        'body': [
          blk('changeVar', {'name': 'count', 'by': exNum(1)}),
          blk('setProp', {
            'node': 'n1',
            'prop': 'text',
            'value': exJoin([exText('点了 '), exVar('count'), exText(' 次')]),
          }),
          blk(
            'if',
            {'cond': exBin('>=', exVar('count'), exNum(3))},
            body: [
              blk('setProp', {'node': 'n5', 'prop': 'bg', 'value': exText('#CC3344')}),
              blk('setProp', {'node': 'n8', 'prop': 'visible', 'value': exBool(false)}),
            ],
            orElse: [
              blk('setProp', {'node': 'n9', 'prop': 'src', 'value': exText('b.png')}),
            ],
          ),
        ],
      },
      {
        'id': 'h2',
        'event': 'input',
        'target': 'n3',
        'body': [
          blk('setProp', {
            'node': 'n7',
            'prop': 'text',
            'value': exJoin([exText('你好，'), exEvent()]),
          }),
        ],
      },
      {
        'id': 'h3',
        'event': 'click',
        'target': 'n6',
        'body': [
          blk(
            'fetch',
            {'url': exText('https://example.com/api'), 'method': 'GET', 'into': 'reply'},
            body: [
              blk('setProp', {
                'node': 'n7',
                'prop': 'text',
                'value': exJoin([exVar('reply'), exText(' / '), exProp('n3', 'value')]),
              }),
            ],
            orElse: [
              blk('alert', {'message': exText('失败了')}),
            ],
          ),
        ],
      },
      {
        'id': 'h4',
        'event': 'load',
        'body': [
          blk('setProp', {'node': 'n3', 'prop': 'placeholder', 'value': exText('写点什么')}),
        ],
      },
    ],
  },
  'components': [
    {
      'id': 'c1',
      'name': 'Title Card',
      'props': [
        {'name': 'title', 'type': 'text', 'default': '标题'},
        {'name': 'badge', 'type': 'number', 'default': 0},
        {'name': 'tint', 'type': 'color', 'default': '#FFFFFF'},
        {'name': 'class', 'type': 'text', 'default': ''},
      ],
      'root': {
        'id': 'k1',
        'type': 'card',
        'props': {'padding': 12, 'gap': 4, 'bg': '#FFFFFF'},
        'bind': {'bg': 'tint'},
        'children': [
          {
            'id': 'k2',
            'type': 'text',
            'props': {'text': '标题', 'bold': true},
            'bind': {'text': 'title'},
          },
          {
            'id': 'k3',
            'type': 'text',
            'props': {'text': '0'},
            'bind': {'text': 'badge'},
          },
        ],
      },
    },
  ],
};

LcDocument frameworkSample() => LcDocument.parse(jsonEncode(frameworkSampleJson()));

LcDocument docOf(Map<String, Object?> json) => LcDocument.parse(jsonEncode(json));

// —— 用 node 核对生成的脚本（找不到 node 的机器上跳过）——

final bool hasNode = () {
  try {
    return Process.runSync('node', ['--version']).exitCode == 0;
  } on ProcessException {
    return false; // 这台机器没装 node：相关用例跳过
  }
}();
final Object skipWithoutNode = hasNode ? false : '找不到 node，跳过“真的跑一遍 / 语法检查”的用例';

int _fileNo = 0;
final Directory _nodeTmp = Directory.systemTemp.createTempSync('lopi_export_node_');

/// 测试文件的 tearDownAll 里调用，删掉临时脚本。
void cleanNodeTmp() {
  if (_nodeTmp.existsSync()) _nodeTmp.deleteSync(recursive: true);
}

String _script(String source) => (File('${_nodeTmp.path}/case_${_fileNo++}.js')..writeAsStringSync(source)).path;

/// `node --check`：只查语法。返回错误输出（空＝通过）。
String nodeCheck(String source) {
  final r = Process.runSync('node', ['--check', _script(source)], stderrEncoding: utf8);
  return r.exitCode == 0 ? '' : '${r.stderr}';
}

/// 假的浏览器环境：弹窗、控制台、定时器、请求、跳转都只是记下来。`pwn()` 是注入测试的陷阱。
const String fakeBrowser = '''
let pwned = 0;
function pwn() { pwned++; }
const alerts = [], logs = [], timers = [], fetchCalls = [];
const location = { href: "" };
function alert(m) { alerts.push(m); }
const console = { log(...a) { logs.push(a.length === 1 ? a[0] : a); } };
function setTimeout(fn, ms) { timers.push({ fn, ms }); }
function runTimers() { while (timers.length) timers.shift().fn(); }
let fetchReply = () => Promise.resolve({ ok: true, status: 200, text: () => Promise.resolve("响应内容") });
function fetch(url, opts) { fetchCalls.push({ url, method: opts && opts.method }); return fetchReply(url); }
const settle = async () => { for (let i = 0; i < 5; i++) await new Promise((r) => setImmediate(r)); };
const input = (value) => ({ target: { value } });
''';

/// 跑一段脚本（异步函数体），把它 `return` 的东西当 JSON 取回来。
Object? runNode(String prelude, String body) {
  final source =
      '''
$fakeBrowser
$prelude
(async () => {
$body
})().then((out) => process.stdout.write(JSON.stringify(out === undefined ? null : out)), (e) => { process.stderr.write(String(e && e.stack || e)); process.exit(1); });
''';
  final r = Process.runSync('node', [_script(source)], stdoutEncoding: utf8, stderrEncoding: utf8);
  if (r.exitCode != 0) fail('node 运行失败：\n${r.stderr}');
  return jsonDecode('${r.stdout}');
}

String stripImports(String js) => js.split('\n').where((l) => !RegExp(r'^\s*import\b.*;\s*$').hasMatch(l)).join('\n');

/// 极简的标签配平检查（HTML / Vue 模板用）：返回问题说明，配平返回 null。注释先去掉；img / input / hr 不用闭合。
String? tagBalanceProblem(String html) {
  final stack = <String>[];
  final body = html.replaceAll(RegExp(r'<!--[\s\S]*?-->'), '');
  for (final m in RegExp(r'<(/?)([A-Za-z][A-Za-z0-9]*)((?:"[^"]*"|[^<>"])*?)(/?)>').allMatches(body)) {
    final name = m[2]!;
    if (m[1] == '/') {
      if (stack.isEmpty || stack.last != name) return '多了 </$name>（栈：$stack）';
      stack.removeLast();
    } else if (m[4] != '/' && !const ['img', 'input', 'hr'].contains(name)) {
      stack.add(name);
    }
  }
  final rest = body.replaceAll(RegExp(r'<(/?)([A-Za-z][A-Za-z0-9]*)((?:"[^"]*"|[^<>"])*?)(/?)>'), '');
  if (rest.contains('<') || rest.contains('>')) return '标签以外还有尖括号';
  return stack.isEmpty ? null : '没闭合：$stack';
}

/// 造坏数据用的小工具。
abstract final class LcHandlerSample {
  /// 一个“触发它的控件已经不在页面里”的处理。
  static LcHandler orphan() => LcHandler(
    id: 'orphan',
    event: 'click',
    target: 'gone',
    body: [
      LcBlock(op: 'alert', args: {'message': exText('x')}),
    ],
  );
}
