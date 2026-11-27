// 组件事件（积木第 5 版·前端 1·下半）：“当〔组件实例〕发出〔事件〕”这顶帽子和“事件带来的〔某一项〕”在三种产物里真跑。
// 线 B 摊开组件、把组件里的点击变成事件发出来的那一步还在它的分支上没合过来，所以这里先替它发：把两个普通按钮的点击
// 改写成 `lcPage.emit(<实例 id>, "emit:<事件名>", { lcData: {...} })`——合并以后线 B 那一步要发的就是这个样子（对接点写在进度本“文件分工”里）。
// 环境只在开发机上有；找不到就明确跳过。不联网。
@Tags(['external'])
@Timeout(Duration(minutes: 30))
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/backend/front_doc.dart';
import 'package:lopicode/lowcode/model.dart';

import 'support/backend_lang_blocks.dart';
import 'support/dev_tools.dart';
import 'support/page_front_check.dart';
import 'support/page_front_samples.dart';

LcDocument _sample() {
  final doc = LcDocument.parse(
    jsonEncode({
      'version': 3,
      'id': 'home',
      'title': 'Emit',
      'root': node('root', 'page', const {}, [
        btn('b1', '发七'),
        btn('b2', '发五'),
        txt('t1'),
        txt('t2'),
        node('i1', 'component', {'ref': 'c1'}),
      ]),
      'logic': {
        'variables': [
          {'name': 'total', 'type': 'number', 'initial': 0},
        ],
        'front': frontDoc(
          hats: [
            onClick('h1', 'b1', [show('t2', tx('甲'))]),
            onClick('h2', 'b2', [show('t2', tx('乙'))]),
            hat(
              'h3',
              'onEmit',
              [
                stSet('total', op2('+', asNum(stGet('total')), asNum(ex(pg('emitData'), {'name': tx('count')})))),
                show('t1', ex(pg('oldText'), {'value': stGet('total')})),
                show(
                  't2',
                  cat([
                    tx('来自'),
                    ex(pg('oldText'), {
                      'value': ex(pg('emitData'), {'name': tx('who')}),
                    }),
                  ]),
                ),
              ],
              args: {'node': 'i1', 'event': 'picked'},
            ),
          ],
        ),
      },
      'components': [
        {
          'id': 'c1',
          'name': '计数卡',
          'events': [
            {
              'name': 'picked',
              'label': '选中了',
              'params': [
                {'name': 'count', 'type': 'number'},
                {'name': 'who', 'type': 'text'},
              ],
            },
          ],
          'root': node('cr', 'column', const {}, [txt('ct', '卡')]),
        },
      ],
    }),
  );
  lcFrontStore(doc.logic, lcFrontOf(doc.logic)!);
  return doc;
}

/// 替线 B 那一步把事件发出来：b1 的点击＝实例 i1 发 picked（count 7、who 甲）；b2＝（count 5、who 乙）。
Map<String, String> _patch(Map<String, String> files) {
  var hits = 0;
  final out = <String, String>{};
  for (final f in files.entries) {
    var text = f.value;
    for (final (id, data) in const [('b1', '{ count: 7, who: "甲" }'), ('b2', '{ count: 5, who: "乙" }')]) {
      final from = 'lcPage.emit("$id", "click", event)';
      hits += from.allMatches(text).length;
      text = text.replaceAll(from, 'lcPage.emit("i1", "emit:picked", { lcData: $data })');
    }
    // 纯网页：点击是页面宿主自己挂在元素上的，没有转发那一行；在脚本末尾补一个监听替线 B 发。
    if (f.key.endsWith('.js') && text.contains('function lcStart()')) {
      for (final (id, data) in const [('b1', '{ count: 7, who: "甲" }'), ('b2', '{ count: 5, who: "乙" }')]) {
        hits++;
        text = '$text\ndocument.addEventListener("click", (e) => { if (e.target.closest(".n-$id")) lcPage.emit("i1", "emit:picked", { lcData: $data }); });\n';
      }
    }
    out[f.key] = text;
  }
  expect(hits, 2, reason: '两个按钮各有一处转发：${[for (final f in files.entries) ...f.value.split('\n').where((l) => l.contains('lcPage.emit')).map((l) => '${f.key}: ${l.trim()}')]}');
  return out;
}

List<List<Map<String, Object?>>> _steps() => [
  [
    {'op': 'text', 'sel': '.n-t1', 'is': '-'},
    {'op': 'click', 'sel': '.n-b1'},
    {'op': 'text', 'sel': '.n-t1', 'is': '7'},
    {'op': 'text', 'sel': '.n-t2', 'is': '来自甲'},
  ],
  [
    {'op': 'click', 'sel': '.n-b2'},
    {'op': 'text', 'sel': '.n-t1', 'is': '5'},
    {'op': 'text', 'sel': '.n-t2', 'is': '来自乙'},
    {'op': 'click', 'sel': '.n-b1'},
    {'op': 'text', 'sel': '.n-t1', 'is': '12'},
    {'op': 'text', 'sel': '.n-t2', 'is': '来自甲'},
  ],
  [
    {'op': 'click', 'sel': '.n-b1'},
    {'op': 'click', 'sel': '.n-b1'},
    {'op': 'click', 'sel': '.n-b2'},
    {'op': 'click', 'sel': '.n-b1'},
    {'op': 'text', 'sel': '.n-t1', 'is': '26'},
    {'op': 'text', 'sel': '.n-t2', 'is': '来自甲'},
  ],
];

void main() {
  if (skipWithoutDom != false) {
    // ignore: avoid_print 跳过的原因要在测试输出里看得见
    print('【跳过】组件事件的真编译 / 真跑：$skipWithoutDom');
  }
  for (final kind in kFrontKinds.keys) {
    test('${kFrontKinds[kind]}：组件实例发出事件 → 帽子跑、读得到事件带来的数据：三组步骤', () => frontCheckAll(kind, _sample(), _steps(), patch: _patch), skip: skipWithoutDom);
  }
  test('React 开着 StrictMode：组件事件', () => frontCheckAll('react', _sample(), _steps(), strict: true, patch: _patch), skip: skipWithoutDom);
}
