import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/lowcode/export_dart.dart';
import 'package:lopicode/lowcode/export_html.dart';
import 'package:lopicode/lowcode/model.dart';

import 'support/sample_doc.dart';

void main() {
  group('模型 ↔ JSON', () {
    test('往返不丢信息', () {
      final doc = sample();
      final again = LcDocument.parse(doc.encode());
      expect(again.toJson(), doc.toJson());
      expect(again.title, '登录页 Demo');
      expect(again.find('b1')!.props['text'], '登录');
      expect(again.find('root')!.props['bg'], '#F6FBFD'); // 颜色统一成大写
    });

    test('起步文档合法且 id 唯一', () {
      final doc = LcDocument.starter('我的页面');
      final ids = <String>[];
      void walk(LcNode n) {
        ids.add(n.id);
        n.children.forEach(walk);
      }

      walk(doc.root);
      expect(ids.toSet().length, ids.length);
      expect(ids.every((id) => id.isNotEmpty), isTrue);
      expect(LcDocument.parse(doc.encode()).toJson(), doc.toJson());
    });

    test('坏输入被拒绝', () {
      void bad(Object json) => expect(() => LcDocument.parse(json is String ? json : jsonEncode(json)), throwsFormatException);
      bad('not json');
      bad([1, 2]);
      bad({'title': 'x'});
      bad({
        'title': 'x',
        'root': {'type': 'text'},
      }); // 根必须是 page
      bad({
        'title': 'x',
        'root': {
          'type': 'page',
          'children': [
            {'type': 'nope'},
          ],
        },
      });
      bad({
        'title': 'x',
        'root': {
          'type': 'page',
          'children': [
            {
              'type': 'text',
              'children': [
                {'type': 'text'},
              ],
            },
          ],
        },
      });
      bad({
        'title': 'x',
        'root': {
          'type': 'page',
          'children': [
            {'type': 'page'},
          ],
        },
      });
      bad({
        'title': 'x',
        'root': {'type': 'page', 'children': 'oops'},
      });
      // 嵌套过深
      Map<String, dynamic> deep = {'type': 'text'};
      for (var i = 0; i < 40; i++) {
        deep = {
          'type': 'container',
          'children': [deep],
        };
      }
      bad({
        'title': 'x',
        'root': {
          'type': 'page',
          'children': [deep],
        },
      });
    });

    test('不认识或非法的属性被清掉，重复 id 被修正', () {
      final doc = LcDocument.parse(
        jsonEncode({
          'title': 't',
          'root': {
            'type': 'page',
            'children': [
              {
                'id': 'a',
                'type': 'text',
                'props': {'text': 'x', 'color': 'red', 'fontSize': -3, 'onclick': 'alert(1)', 'width': 'huge'},
              },
              {
                'id': 'a',
                'type': 'text',
                'props': {'text': 'y', 'color': '#abcdef'},
              },
              {'id': 'bad id!', 'type': 'text'},
            ],
          },
        }),
      );
      final kids = doc.root.children;
      expect(kids[0].props, {'text': 'x'});
      expect(kids[1].props['color'], '#ABCDEF');
      expect({doc.root.id, kids[0].id, kids[1].id, kids[2].id}.length, 4);
      expect(RegExp(r'^[A-Za-z0-9_]+$').hasMatch(kids[2].id), isTrue);
    });
  });

  group('编辑操作', () {
    test('插入、移动、重排、复制、删除', () {
      final doc = sample();
      final n = doc.newNode('button');
      expect(doc.insert('card', n, 0), isTrue);
      expect(doc.find('card')!.children.first.id, n.id);
      expect(doc.insert('t1', doc.newNode('text')), isFalse, reason: '文本不是容器');
      expect(doc.insert('root', LcNode(id: 'p', type: 'page')), isFalse);

      // 同一父级内往后移：下标要按移除后的位置算
      List<String> rootKids() => doc.root.children.map((c) => c.id).toList();
      expect(rootKids().take(3), ['t1', 'card', 'img']);
      expect(doc.move('t1', 'root', 2), isTrue);
      expect(rootKids().take(3), ['card', 't1', 'img']);
      expect(doc.move('t1', 'root', 0), isTrue);
      expect(rootKids().take(3), ['t1', 'card', 'img']);

      // 跨容器
      expect(doc.move('img', 'row', 0), isTrue);
      expect(doc.parentOf('img')!.id, 'row');
      // 不能移进自己或后代
      expect(doc.move('card', 'row', 0), isFalse);
      expect(doc.move('card', 'card', 0), isFalse);
      expect(doc.move('root', 'card', 0), isFalse);

      expect(doc.shift('t1', -1), isFalse);
      expect(doc.shift('t1', 1), isTrue);
      expect(rootKids().take(2), ['card', 't1']);

      final copyId = doc.duplicate('card')!;
      expect(copyId, isNot('card'));
      final copy = doc.find(copyId)!;
      expect(copy.children.length, doc.find('card')!.children.length);
      expect(doc.parentOf(copyId)!.children.indexOf(copy), doc.root.children.indexOf(doc.find('card')!) + 1);

      expect(doc.remove('root'), isFalse);
      expect(doc.remove(copyId), isTrue);
      expect(doc.find(copyId), isNull);
    });

    test('撤销 / 重做', () {
      var doc = sample();
      final history = LcHistory(doc);
      expect(history.canUndo, isFalse);
      doc.find('b1')!.props['text'] = '进入';
      history.record(doc);
      history.record(doc); // 没变化不重复记
      doc.remove('img');
      history.record(doc);
      expect(history.canUndo, isTrue);

      doc = history.undo()!;
      expect(doc.find('img'), isNotNull);
      expect(doc.find('b1')!.props['text'], '进入');
      doc = history.undo()!;
      expect(doc.find('b1')!.props['text'], '登录');
      expect(history.undo(), isNull);

      doc = history.redo()!;
      expect(doc.find('b1')!.props['text'], '进入');
      // 重做途中做了新修改，重做栈清空
      doc.find('b1')!.props['text'] = '新的';
      history.record(doc);
      expect(history.canRedo, isFalse);
    });
  });

  group('导出 HTML', () {
    test('结构完整、文本转义、样式落到 css', () {
      final out = exportHtml(sample());
      expect(out.html, startsWith('<!DOCTYPE html>'));
      expect(out.html, contains('<meta name="viewport"'));
      expect(out.html, contains('href="style.css"'));
      expect(out.html, contains('<title>登录页 Demo</title>'));
      // 用户文字里的标签不能变成真标签
      expect(out.html, contains('&lt;b&gt;'));
      expect(out.html, isNot(contains('<b>')));
      expect(out.html, contains('二 &amp; 三'));
      expect(out.html, contains('placeholder="手机号"'));
      expect(out.html, contains('<button'));
      expect(out.html, contains('src="https://example.com/a.png"'));
      // 标签配对
      for (final tag in ['div', 'button', 'ul', 'li', 'p']) {
        expect(RegExp('<$tag[ >]').allMatches(out.html).length, '</$tag>'.allMatches(out.html).length, reason: tag);
      }
      expect(out.css, contains('.n-b1 {'));
      expect(out.css, contains('background: #058654'));
      expect(out.css, contains('justify-content: space-between'));
      expect(out.css, contains('border-radius: 12px'));
      expect('{'.allMatches(out.css).length, '}'.allMatches(out.css).length);
    });
  });

  group('导出 Dart', () {
    test('生成的代码结构正确、字符串转义、括号配对', () {
      final code = exportDart(sample());
      expect(code, contains("import 'package:flutter/material.dart';"));
      expect(code, contains('extends StatelessWidget'));
      expect(code, contains('Scaffold('));
      expect(code, contains('FilledButton('));
      expect(code, contains('TextField('));
      expect(code, contains('Expanded(')); // 行里撑满的按钮
      expect(code, contains('const Color(0xFF058654)'));
      expect(code, contains('MainAxisAlignment.spaceBetween'));
      expect(code, contains(r"\'回来\'"));
      expect(code, contains(r'\$5'));
      for (final pair in ['()', '[]', '{}']) {
        expect(pair[0].allMatches(code).length, pair[1].allMatches(code).length, reason: pair);
      }
    });

    test('类名从标题生成，中文标题有兜底', () {
      expect(dartClassName('login page'), 'LoginPage');
      expect(dartClassName('我的页面'), isNotEmpty);
      expect(RegExp(r'^[A-Z][A-Za-z0-9]*$').hasMatch(dartClassName('我的页面')), isTrue);
      expect(RegExp(r'^[A-Z][A-Za-z0-9]*$').hasMatch(dartClassName('123 abc')), isTrue);
    });
  });
}
