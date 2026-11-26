// 第 2 版页面文件（style / bind / logic / components）的读写与容错。
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/lowcode/model.dart';

void main() {
  test('第 1 版文件（没有新字段）照样打开，再存出来不多出空字段', () {
    const v1 = '{"version":1,"title":"旧页面","root":{"id":"root","type":"page","props":{"padding":16},"children":[{"id":"n1","type":"text","props":{"text":"你好"}}]}}';
    final doc = LcDocument.parse(v1);
    expect(doc.title, '旧页面');
    expect(doc.logic.isEmpty, isTrue);
    expect(doc.components, isEmpty);
    expect(doc.find('n1')!.style, isEmpty);
    final out = doc.toJson();
    expect(out['version'], 3);
    expect(out.containsKey('logic'), isFalse);
    expect(out.containsKey('components'), isFalse);
    expect((out['root'] as Map)['children'], [
      {
        'id': 'n1',
        'type': 'text',
        'props': {'text': '你好'},
      },
    ]);
  });

  test('style / bind / logic / components 存了再读是一样的', () {
    final src = {
      'version': 2,
      'title': 't',
      'root': {
        'id': 'root',
        'type': 'page',
        'children': [
          {
            'id': 'n1',
            'type': 'button',
            'props': {'text': '加一'},
            'style': {'margin-top': '8px', 'border': '1px solid #ff0000', '-webkit-line-clamp': '2'},
          },
          {
            'id': 'n2',
            'type': 'component',
            'props': {
              'ref': 'c1',
              'values': {'title': '标题', 'n': 3, 'on': true},
            },
          },
        ],
      },
      'logic': {
        'variables': [
          {'name': 'count', 'type': 'number', 'initial': 0},
        ],
        'handlers': [
          {
            'id': 'h1',
            'event': 'click',
            'target': 'n1',
            'body': [
              {
                'op': 'if',
                'args': {
                  'cond': {'e': 'bool', 'v': true},
                },
                'body': [
                  {
                    'op': 'changeVar',
                    'args': {
                      'name': 'count',
                      'by': {'e': 'num', 'v': 1},
                    },
                  },
                ],
                'else': [
                  {'op': 'alert'},
                ],
              },
            ],
          },
        ],
      },
      'components': [
        {
          'id': 'c1',
          'name': '标题卡',
          'props': [
            {'name': 'title', 'type': 'text', 'default': '默认'},
          ],
          'root': {
            'id': 'k1',
            'type': 'card',
            'children': [
              {
                'id': 'k2',
                'type': 'text',
                'props': {'text': '占位'},
                'bind': {'text': 'title'},
              },
            ],
          },
        },
      ],
    };
    final doc = LcDocument.fromJson(src);
    final again = LcDocument.parse(doc.encode());
    expect(jsonEncode(again.toJson()), jsonEncode(doc.toJson()));
    expect(doc.find('n1')!.style['border'], '1px solid #ff0000');
    expect(doc.logic.handlers.single.body.single.orElse.single.op, 'alert');
    expect(doc.logic.handlersFor('n1').length, 1);
    expect(doc.component('c1')!.root.children.single.bind, {'text': 'title'});
    expect(doc.find('n2')!.props['values'], {'title': '标题', 'n': 3, 'on': true});
  });

  test('新字段的类型不对：逐条跳过，页面照样能打开', () {
    final doc = LcDocument.fromJson({
      'title': 't',
      'root': {
        'id': 'root',
        'type': 'page',
        'children': [
          {
            'id': 'n1',
            'type': 'text',
            'style': {'color': 'red; } body { display:none', 'Width': '1px', 'height': 3, 'width': ' 20px ', 'x': 'a\nb'},
            'bind': {'text': 'has space', 'gap': 'a', 'src': 'ok'},
          },
          {'id': 'n2', 'type': 'text', 'style': 'color:red', 'bind': 3},
        ],
      },
      'logic': {
        'variables': [
          {'name': 'a'},
          {'name': 'a', 'type': 'number'},
          {'name': '1bad'},
          'x',
          {'name': 'n', 'type': 'number', 'initial': 'oops'},
          {'name': 'b', 'type': 'weird', 'initial': 1},
        ],
        'handlers': [
          {'event': 'click', 'target': 'n1', 'body': 'nope'},
          {'event': 'explode'},
          7,
          {
            'id': 'h1',
            'event': 'load',
            'body': [
              {'op': ''},
              {'args': <String, dynamic>{}},
              {'op': 'alert', 'args': 'bad', 'body': 5},
            ],
          },
          {'id': 'h1', 'event': 'load'},
        ],
      },
      'components': [
        {'id': 'c1', 'name': 'bad root', 'root': 3},
        {
          'id': 'c1',
          'root': {'type': 'page'},
        },
        {
          'id': 'c1',
          'root': {'type': 'nope'},
        },
        {
          'id': 'c1',
          'name': '  ',
          'props': [
            {'name': 'p', 'type': 'color', 'default': 'zzz'},
            {'name': 'p'},
            3,
          ],
          'root': {'type': 'text'},
        },
        {
          'id': 'c1',
          'name': '重复 id',
          'root': {
            'type': 'row',
            'children': [
              {'id': 'same', 'type': 'text'},
              {'id': 'same', 'type': 'text'},
            ],
          },
        },
      ],
    });
    expect(doc.find('n1')!.style, {'width': '20px'});
    expect(doc.find('n1')!.bind, {'src': 'ok'});
    expect(doc.find('n2')!.style, isEmpty);
    expect([for (final v in doc.logic.variables) '${v.name}:${v.type}:${v.initial}'], ['a:text:', 'n:number:0', 'b:text:']);
    expect([for (final h in doc.logic.handlers) '${h.id}:${h.event}:${h.body.length}'], ['h1:click:0', 'h2:load:1', 'h3:load:0']);
    expect(doc.logic.handlers[1].body.single.args, isEmpty);
    expect([for (final c in doc.components) '${c.id}:${c.name}'], ['c1:未命名组件', 'c2:重复 id']);
    expect(doc.components.first.props.single.defaultValue, '#000000');
    final ids = [for (final n in doc.components.last.root.children) n.id];
    expect(ids.toSet().length, 2);
  });

  test('logic 不是对象、components 不是数组：当作没有', () {
    final doc = LcDocument.fromJson({
      'title': 't',
      'root': {'id': 'root', 'type': 'page'},
      'logic': [1, 2],
      'components': {'a': 1},
    });
    expect(doc.logic.isEmpty, isTrue);
    expect(doc.components, isEmpty);
  });

  test('积木嵌套超过上限的部分被丢掉，不会栈溢出', () {
    Map<String, dynamic> nest(int n) => {
      'op': 'if',
      if (n > 0) 'body': [nest(n - 1)],
    };
    final doc = LcDocument.fromJson({
      'title': 't',
      'root': {'id': 'root', 'type': 'page'},
      'logic': {
        'handlers': [
          {
            'event': 'load',
            'body': [nest(40)],
          },
        ],
      },
    });
    var depth = 0;
    var b = doc.logic.handlers.single.body.single;
    while (b.body.isNotEmpty) {
      b = b.body.single;
      depth++;
    }
    expect(depth, 12);
  });

  test('撤销 / 重做带着新字段', () {
    final doc = LcDocument.starter('页');
    final history = LcHistory(doc);
    doc.find('root')!.style['min-height'] = '100vh';
    history.record(doc);
    final back = history.undo()!;
    expect(back.root.style, isEmpty);
    expect(history.redo()!.root.style, {'min-height': '100vh'});
  });
}
