// 页面逻辑新路（语言核心 → 浏览器目标）的样例和它们在浏览器里要走的步骤。
// - 样例甲：旧积木全集（support/lowcode_samples.dart 的样本页再补上“重复、等一会儿、去网址、打印、比较”）。
// - 样例乙：用了一个只用语言核心的“都行”库（函数＋闭包、类、错误“试着做”、列表和记录）＋列表 / 记录状态。
// - 样例丙：状态与绑定的两页样例（support/bind_sample.dart），整页强制走新路。
import 'dart:convert';

import 'package:lopicode/lang/lib_model.dart';
import 'package:lopicode/lowcode/model.dart';

import 'lowcode_samples.dart';

Map<String, dynamic> _lib(String id, Map<String, dynamic> slots) => {'e': 'lib:test/page-kit#$id', ...slots};

/// 样例甲：样本页，加一个按钮 nA（重复＋等一会儿＋比较＋打印）。
LcDocument coreSampleOld() {
  final json = frameworkSampleJson();
  final root = json['root']! as Map<String, Object?>;
  (root['children']! as List).add({
    'id': 'nA',
    'type': 'button',
    'props': {'text': '试试'},
  });
  final logic = json['logic']! as Map<String, Object?>;
  (logic['variables']! as List).add({'name': 'ok', 'type': 'bool', 'initial': false});
  (logic['handlers']! as List).add({
    'id': 'h5',
    'event': 'click',
    'target': 'nA',
    'body': [
      blk(
        'repeat',
        {'times': exText('2.5')},
        body: [
          blk('changeVar', {'name': 'count', 'by': exText('10')}),
        ],
      ),
      blk('setVar', {'name': 'ok', 'value': exBin('==', exProp('n3', 'value'), exVar('count'))}),
      blk('log', {'value': exVar('count')}),
      blk('setProp', {
        'node': 'nA',
        'prop': 'text',
        'value': exJoin([
          exBin('/', exVar('count'), exNum(4)),
          exText('·'),
          exBin('%', exVar('count'), exNum(0)),
          exText('·'),
          exVar('ok'),
          exText('·'),
          exBin('and', exVar('count'), exNot(exVar('ok'))),
        ]),
      }),
      blk(
        'wait',
        {'ms': exNum(30)},
        body: [
          blk('setProp', {'node': 'n7', 'prop': 'text', 'value': exText('等完了')}),
        ],
      ),
    ],
  });
  return docOf(json);
}

List<Map<String, Object?>> coreStepsOld() => [
  {
    'op': 'fake',
    'routes': {
      'https://example.com/api': {'status': 200, 'body': '回来了'},
    },
  },
  {'op': 'click', 'sel': '.n-n5'},
  {'op': 'text', 'sel': '.n-n1', 'is': '点了 1 次'},
  {'op': 'type', 'sel': '.n-n3', 'text': '塔'},
  {'op': 'text', 'sel': '.n-n7', 'is': '你好，塔'},
  {'op': 'click', 'sel': '.n-n6'},
  {'op': 'wait', 'ms': 60},
  {'op': 'text', 'sel': '.n-n7', 'is': '回来了 / 塔'},
  {'op': 'click', 'sel': '.n-n5'},
  {'op': 'click', 'sel': '.n-n5'},
  {'op': 'text', 'sel': '.n-n1', 'is': '点了 3 次'},
  {'op': 'shown', 'sel': '.n-n8', 'is': false},
  {'op': 'type', 'sel': '.n-n3', 'text': '33'},
  {'op': 'click', 'sel': '.n-nA'},
  {'op': 'text', 'sel': '.n-nA', 'is': '8.25·0·true·false'},
  {'op': 'wait', 'ms': 120},
  {'op': 'text', 'sel': '.n-n7', 'is': '等完了'},
  // 请求失败（网址不在假网络里）→ 走“失败后”：弹提示
  {'op': 'fake', 'routes': <String, Object?>{}},
  {'op': 'click', 'sel': '.n-n6'},
  {'op': 'wait', 'ms': 60},
  {'op': 'alerts', 'is': '失败了'},
];

/// 只用语言核心的“都行”库：函数＋闭包、类、错误“试着做”、列表、记录。
const Map<String, String> kPageKitFiles = {
  'lib.json': '''
{"kind": "lopicode-lib", "format": 1, "id": "test/page-kit", "name": "页工具", "version": "1.0.0", "summary": "测试用", "rules": 2,
 "for": "both", "modules": [{"file": "modules/kit.lc", "name": "页工具"}], "blocks": ["blocks.json"]}''',
  'modules/kit.lc': '''
(模块 页工具
  (函数 做加法器 ((步 小数)) -> (函数 (小数) 小数) (返回 (λ ((x 小数)) (+ x 步))))
  (公开 (函数 加两回 ((x 小数) (步 小数)) -> 小数 (设 加 (调 做加法器 步)) (返回 (调 加 (调 加 x)))))
  (类 计数器
    (字段 数 小数 0)
    (创建 ((起 小数)) (改字段 (这) 数 起))
    (方法 加 ((n 小数)) -> 计数器 (改字段 (这) 数 (+ (. (这) 数) n)) (返回 (这))))
  (公开 (函数 数三下 ((起 小数)) -> 小数 (设 c (新 计数器 起)) (返回 (. (发 (发 (发 c 加 1) 加 1) 加 1) 数))))
  (公开 (函数 安全除 ((a 小数) (b 小数)) -> 文字
    (试 (做 (如果 (== b 0) (那么 (抛出 (新 错误 "不能除以零")))) (返回 (连 "商是 " (/ a b))))
        (出错时 错误 e (返回 (连 "出错：" (. e 消息)))))))
  (公开 (函数 添一项 ((表 任意) (项 文字)) -> 任意
    (设 l (转 (列表 任意) 表)) (加项 l 项) (返回 l)))
  (公开 (函数 几项 ((表 任意)) -> 小数 (返回 (长 (转 (列表 任意) 表)))))
  (公开 (函数 改名字 ((人 任意) (名 文字)) -> 任意
    (设 d (转 (字典 任意) 人)) (改项 d "name" 名) (返回 d)))
  (公开 (函数 名字 ((人 任意)) -> 文字 (返回 (文 (取 (转 (字典 任意) 人) "name"))))))
''',
  'blocks.json': '''
{"blocks": [
  {"id": "addTwice", "how": "call", "of": "加两回", "args": ["x", "step"], "look": {"name": "加两回", "shape": "value", "template": "{x} 加两回 {step}"}},
  {"id": "count3", "how": "call", "of": "数三下", "args": ["from"], "look": {"name": "数三下", "shape": "value", "template": "从 {from} 数三下"}},
  {"id": "safeDiv", "how": "call", "of": "安全除", "args": ["a", "b"], "look": {"name": "安全除", "shape": "value", "template": "{a} 除以 {b}"}},
  {"id": "push", "how": "call", "of": "添一项", "args": ["list", "item"], "look": {"name": "添一项", "shape": "value", "template": "{list} 添上 {item}"}},
  {"id": "size", "how": "call", "of": "几项", "args": ["list"], "look": {"name": "几项", "shape": "value", "template": "{list} 有几项"}},
  {"id": "rename", "how": "call", "of": "改名字", "args": ["who", "name"], "look": {"name": "改名字", "shape": "value", "template": "{who} 改名叫 {name}"}},
  {"id": "nameOf", "how": "call", "of": "名字", "args": ["who"], "look": {"name": "名字", "shape": "value", "template": "{who} 的名字"}}
]}''',
};

LibLibrary pageKit() => libRead(kPageKitFiles, builtin: false);

Map<String, Object?> _btn(String id, String text) => {
  'id': id,
  'type': 'button',
  'props': {'text': text},
};
Map<String, Object?> _txt(String id) => {
  'id': id,
  'type': 'text',
  'props': {'text': '-'},
};
Map<String, Object?> _click(String id, String node, List<Object?> body) => {'id': id, 'event': 'click', 'target': node, 'body': body};
Map<String, Object?> _show(String node, Object value) => blk('setProp', {'node': node, 'prop': 'text', 'value': value});

/// 样例乙：用库积木（函数＋闭包、类、试着做）和列表 / 记录状态。
LcDocument coreSampleLib() {
  final doc = LcDocument.parse(
    jsonEncode({
      'version': 3,
      'title': 'Kit',
      'root': {
        'id': 'root',
        'type': 'page',
        'props': {'padding': 16, 'gap': 8},
        'children': [
          {
            'id': 'in1',
            'type': 'input',
            'props': {'placeholder': '除数'},
          },
          _btn('b1', '闭包'),
          _txt('t1'),
          _btn('b2', '类'),
          _txt('t2'),
          _btn('b3', '除'),
          _txt('t3'),
          _btn('b4', '列表'),
          _txt('t4'),
          _btn('b5', '记录'),
          _txt('t5'),
        ],
      },
      'logic': {
        'uses': [
          {'id': 'test/page-kit'},
        ],
        'variables': [
          {'name': 'n', 'type': 'number', 'initial': 1},
          {
            'name': 'items',
            'type': 'list',
            'initial': ['甲'],
          },
          {
            'name': 'who',
            'type': 'record',
            'initial': {'name': '霜霜', 'age': 3},
          },
        ],
        'handlers': [
          _click('h1', 'b1', [
            blk('setVar', {
              'name': 'n',
              'value': _lib('addTwice', {'x': exVar('n'), 'step': exNum(2)}),
            }),
            _show('t1', exJoin([exText('n='), exVar('n')])),
          ]),
          _click('h2', 'b2', [
            _show(
              't2',
              exJoin([
                exText('数到 '),
                _lib('count3', {'from': exVar('n')}),
              ]),
            ),
          ]),
          _click('h3', 'b3', [
            _show('t3', _lib('safeDiv', {'a': exNum(9), 'b': exBin('+', exProp('in1', 'value'), exNum(0))})),
          ]),
          _click('h4', 'b4', [
            blk('setVar', {
              'name': 'items',
              'value': _lib('push', {
                'list': exVar('items'),
                'item': exJoin([
                  exText('第'),
                  _lib('size', {'list': exVar('items')}),
                  exText('个'),
                ]),
              }),
            }),
            _show(
              't4',
              exJoin([
                _lib('size', {'list': exVar('items')}),
                exText(' 项'),
              ]),
            ),
          ]),
          _click('h5', 'b5', [
            blk('setVar', {
              'name': 'who',
              'value': _lib('rename', {'who': exVar('who'), 'name': exText('小塔塔')}),
            }),
            _show('t5', _lib('nameOf', {'who': exVar('who')})),
          ]),
        ],
      },
    }),
  );
  doc.logic.loaded = [pageKit()];
  return doc;
}

List<Map<String, Object?>> coreStepsLib() => [
  {'op': 'click', 'sel': '.n-b1'},
  {'op': 'text', 'sel': '.n-t1', 'is': 'n=5'},
  {'op': 'click', 'sel': '.n-b1'},
  {'op': 'text', 'sel': '.n-t1', 'is': 'n=9'},
  {'op': 'click', 'sel': '.n-b2'},
  {'op': 'text', 'sel': '.n-t2', 'is': '数到 12'},
  {'op': 'click', 'sel': '.n-b3'},
  {'op': 'text', 'sel': '.n-t3', 'is': '出错：不能除以零'},
  {'op': 'type', 'sel': '.n-in1', 'text': '3'},
  {'op': 'click', 'sel': '.n-b3'},
  {'op': 'text', 'sel': '.n-t3', 'is': '商是 3'},
  {'op': 'click', 'sel': '.n-b4'},
  {'op': 'click', 'sel': '.n-b4'},
  {'op': 'text', 'sel': '.n-t4', 'is': '3 项'},
  {'op': 'click', 'sel': '.n-b5'},
  {'op': 'text', 'sel': '.n-t5', 'is': '小塔塔'},
];
