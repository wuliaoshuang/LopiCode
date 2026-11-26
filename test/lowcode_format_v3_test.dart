// 页面文件格式第 3 版（docs/lowcode-page-format-v3.md）：老文件怎么读进来、存出去丢不丢东西、
// 看不懂的字段和组件留不留、比自己新的版本怎么办。
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/lowcode/component_ops.dart';
import 'package:lopicode/lowcode/export_html.dart';
import 'package:lopicode/lowcode/model.dart';

String fixture(String name) => File('test/fixtures/lowcode/$name').readAsStringSync();
Map<String, dynamic> json(String s) => jsonDecode(s) as Map<String, dynamic>;

/// 在一棵 JSON 里按 id 找节点。
Map<String, dynamic>? nodeOf(Object? tree, String id) {
  if (tree is Map<String, dynamic>) {
    if (tree['id'] == id && tree.containsKey('type')) return tree;
    for (final v in tree.values) {
      final r = nodeOf(v, id);
      if (r != null) return r;
    }
  } else if (tree is List) {
    for (final v in tree) {
      final r = nodeOf(v, id);
      if (r != null) return r;
    }
  }
  return null;
}

LcDocument v3(Map<String, dynamic> root, {Map<String, dynamic> extra = const {}}) => LcDocument.fromJson({'version': 3, 'title': 't', 'root': root, ...extra});

void main() {
  group('老文件读成第 3 版', () {
    test('第 1 版 → 第 3 版：读入记着原来是第 1 版；存出来是第 3 版，原文件里的东西一样不丢', () {
      final doc = LcDocument.parse(fixture('page-v1.lc.json'));
      expect(doc.fileVersion, 1);
      expect(doc.isFromNewer, isFalse);
      final out = json(doc.encode());
      expect(out['version'], 3);
      // 老代码会丢的四样：页面的 background、文字的 weight、输入框的 label、按钮的 variant——现在都还在（oldProps 里）。
      final src = json(fixture('page-v1.lc.json'));
      var kept = 0;
      void check(Map<String, dynamic> a) {
        final b = nodeOf(out, a['id'] as String)!;
        final all = {...?(b['props'] as Map?), ...?(b['oldProps'] as Map?)};
        (a['props'] as Map? ?? const {}).forEach((k, v) {
          expect(all.containsKey(k), isTrue, reason: '${a['id']}.$k 丢了');
          if ((b['oldProps'] as Map?)?.containsKey(k) ?? false) {
            expect(all[k], v);
            kept++;
          }
        });
        for (final c in (a['children'] as List? ?? const [])) {
          check(c as Map<String, dynamic>);
        }
      }

      check(src['root'] as Map<String, dynamic>);
      expect(kept, 4);
      // 再读再存不再变。
      expect(LcDocument.parse(doc.encode()).encode(), doc.encode());
    });

    test('第 1 版文件里碰巧有 label 这种第 3 版才有的属性：不会突然生效（导出里没有标签）', () {
      final doc = LcDocument.parse(fixture('page-v1.lc.json'));
      LcNode? input;
      void walk(LcNode n) {
        if (n.type == 'input') input = n;
        n.children.forEach(walk);
      }

      walk(doc.root);
      expect(input!.props.containsKey('label'), isFalse);
      expect(input!.more['oldProps'], {'label': '名字'});
      expect(exportHtml(doc).html, isNot(contains('lc-label')));
      // 存成第 3 版再打开也一样不生效。
      expect(exportHtml(LcDocument.parse(doc.encode())).html, isNot(contains('lc-label')));
    });

    test('第 2 版 → 第 3 版：样式、逻辑、组件原样；存出来是第 3 版；再读再存不再变', () {
      final doc = LcDocument.parse(fixture('page-v2.lc.json'));
      expect(doc.fileVersion, 2);
      final out = json(doc.encode()), old = json(fixture('page-v2.saved.lc.json'));
      expect(out['version'], 3);
      expect(out['logic'], old['logic']);
      expect(out['components'], old['components']);
      expect(nodeOf(out, 'n5')!['oldProps'], {'title': '你好'}, reason: '老代码存盘时丢掉的那个属性现在留着');
      expect(LcDocument.parse(doc.encode()).encode(), doc.encode());
    });

    test('没写版本号的文件当第 1 版', () {
      final doc = LcDocument.fromJson({
        'title': 't',
        'root': {
          'id': 'root',
          'type': 'page',
          'children': [
            {
              'id': 'a',
              'type': 'button',
              'props': {'text': '好', 'disabled': true},
            },
          ],
        },
      });
      expect(doc.fileVersion, 1);
      expect(doc.find('a')!.props.containsKey('disabled'), isFalse);
      expect(doc.find('a')!.more['oldProps'], {'disabled': true});
    });
  });

  group('第 3 版的新字段', () {
    test('节点的名字 / 锁定 / 编辑器内隐藏：读得进、存得出，字段顺序固定，没设的不写', () {
      final doc = v3({
        'id': 'root',
        'type': 'page',
        'children': [
          {
            'id': 'a',
            'type': 'text',
            'name': ' 大标题\n ',
            'locked': true,
            'hidden': true,
            'props': {'text': 'x'},
          },
          {
            'id': 'b',
            'type': 'text',
            'locked': false,
            'props': {'text': 'y'},
          },
        ],
      });
      final a = doc.find('a')!;
      expect((a.name, a.locked, a.hidden), ('大标题', true, true));
      final out = json(doc.encode());
      expect(nodeOf(out, 'a')!.keys.toList(), ['id', 'type', 'name', 'locked', 'hidden', 'props']);
      expect(nodeOf(out, 'b')!.keys.toList(), ['id', 'type', 'props']);
      expect(a.clone().name, '大标题');
      expect(copyLcTree(a).locked, isTrue);
    });

    test('新属性：按钮图标 / 禁用，图片说明文字，输入框类型 / 值 / 标签 / 必填 / 禁用', () {
      final doc = v3({
        'id': 'root',
        'type': 'page',
        'children': [
          {
            'id': 'b',
            'type': 'button',
            'props': {'text': '发', 'icon': 'send', 'disabled': true},
          },
          {
            'id': 'i',
            'type': 'image',
            'props': {'src': 'a.png', 'alt': '一只猫'},
          },
          {
            'id': 'f',
            'type': 'input',
            'props': {'inputType': 'email', 'value': 'a@b.c', 'label': '邮箱', 'required': true, 'disabled': false},
          },
          {
            'id': 'bad',
            'type': 'input',
            'props': {'inputType': 'date', 'required': 'yes', 'icon': 'No Such'},
          },
        ],
      });
      expect(doc.find('b')!.props, {'text': '发', 'icon': 'send', 'disabled': true});
      expect(doc.find('i')!.props['alt'], '一只猫');
      expect(doc.find('f')!.props, {'inputType': 'email', 'value': 'a@b.c', 'label': '邮箱', 'required': true, 'disabled': false});
      // 值看不懂的：不生效，但原样留着。
      expect(doc.find('bad')!.props, isEmpty);
      expect(nodeOf(json(doc.encode()), 'bad')!['props'], {'inputType': 'date', 'required': 'yes', 'icon': 'No Such'});
    });
  });

  group('看不懂的东西原样保留', () {
    final source = {
      'version': 3,
      'title': 't',
      'root': {
        'id': 'root',
        'type': 'page',
        'future': {'x': 1},
        'children': [
          {
            'id': 'a',
            'type': 'text',
            'props': {
              'text': 'x',
              'mystery': [1, 2],
            },
            'states': {
              'pressed': {'opacity': '0.5'},
            },
            'responsive': {
              'tablet': {
                'style': {'font-size': '20px'},
              },
            },
            'data': {
              'text': {'from': 'var', 'name': 'count'},
            },
            'repeat': {
              'list': {'from': 'var', 'name': 'items'},
              'item': '项',
            },
            'showIf': {'from': 'var', 'name': 'ok'},
            'slot': 'left',
          },
          {
            'id': 'sw',
            'type': 'switch',
            'props': {'checked': true},
            'whatever': 1,
            'children': [
              {'id': 'zz', 'type': 'text'},
            ],
          },
        ],
      },
      'components': [
        {
          'id': 'c1',
          'name': '卡',
          'props': [
            {'name': 'title', 'type': 'text', 'default': 'a'},
            {
              'name': 'kind',
              'type': 'option',
              'options': ['a', 'b'],
              'default': 'a',
            },
          ],
          'root': {'id': 'k1', 'type': 'card'},
          'slots': [
            {'name': 'default'},
          ],
          'events': [
            {'name': 'tap'},
          ],
        },
        {
          'id': 'c2',
          'name': '坏的',
          'root': {'id': 'k1', 'type': 'tabs'},
        },
      ],
      'pages': [
        {'id': 'p2', 'title': '第二页'},
      ],
      'theme': {'color-primary': '#058654'},
      'someday': true,
    };

    test('节点上、属性里、最外层、组件定义上不认识的字段：打开再存一个都不少', () {
      final doc = LcDocument.fromJson(json(jsonEncode(source)));
      final out = json(doc.encode());
      expect(out, source);
      expect(out.keys.toList(), ['version', 'title', 'root', 'components', 'pages', 'theme', 'someday']);
      expect(LcDocument.parse(doc.encode()).encode(), doc.encode());
    });

    test('不认识的组件类型：不报错，整个节点（连它里面的）原样留着；画布和导出知道它是“新版组件”', () {
      final doc = LcDocument.fromJson(json(jsonEncode(source)));
      final sw = doc.find('sw')!;
      expect(sw.isUnknown, isTrue);
      expect(sw.type, LcNode.unknownType);
      expect(sw.fileType, 'switch');
      expect(sw.isContainer, isFalse);
      expect(exportHtml(doc).html, contains('新版应用加的组件'));
      // 复制、移动以后还在。
      final copyId = doc.duplicate('sw')!;
      expect(nodeOf(json(doc.encode()), copyId)!['props'], {'checked': true});
      expect(doc.move('sw', 'root', 0), isTrue);
      expect((json(doc.encode())['root'] as Map)['children'][0]['type'], 'switch');
    });

    test('改了别的东西以后，没碰的那些不认识的字段还在；撤销重做也不丢', () {
      final doc = LcDocument.fromJson(json(jsonEncode(source)));
      final history = LcHistory(doc);
      doc.find('a')!.props['text'] = '改了';
      doc.insert('root', doc.newNode('button'));
      history.record(doc);
      final out = json(doc.encode());
      expect(nodeOf(out, 'a')!['states'], {
        'pressed': {'opacity': '0.5'},
      });
      expect(nodeOf(out, 'a')!['props'], {
        'text': '改了',
        'mystery': [1, 2],
      });
      expect(out['theme'], {'color-primary': '#058654'});
      expect((out['components'] as List).length, 2);
      final back = history.undo()!;
      expect(json(back.encode()), source);
    });

    test('读不懂的组件属性类型不当成文字硬读：留在原位之后，界面里看不到它', () {
      final doc = LcDocument.fromJson(json(jsonEncode(source)));
      final c1 = doc.component('c1')!;
      expect([for (final p in c1.props) p.name], ['title']);
      expect(c1.keptProps.length, 1);
      expect(doc.component('c2'), isNull);
      expect(doc.keptComponents.length, 1);
    });
  });

  group('比自己新的版本', () {
    test('版本号比 3 大：认得出来是新版做的；存盘时版本号不往回写，看不懂的照样留着', () {
      final doc = LcDocument.fromJson({
        'version': 4,
        'title': 't',
        'root': {
          'id': 'root',
          'type': 'page',
          'children': [
            {
              'id': 'a',
              'type': 'hologram',
              'props': {'depth': 3},
            },
            {
              'id': 'b',
              'type': 'text',
              'props': {'text': 'x', 'glow': true},
            },
          ],
        },
        'v4stuff': [1],
      });
      expect(doc.isFromNewer, isTrue);
      expect(doc.fileVersion, 4);
      doc.find('b')!.props['text'] = 'y';
      final out = json(doc.encode());
      expect(out['version'], 4);
      expect(out['v4stuff'], [1]);
      expect(nodeOf(out, 'a'), {
        'id': 'a',
        'type': 'hologram',
        'props': {'depth': 3},
      });
      expect(nodeOf(out, 'b')!['props'], {'text': 'y', 'glow': true});
      // 撤销重做（整份快照）以后还记得是新版的。
      expect(LcDocument.parse(doc.encode()).isFromNewer, isTrue);
    });

    test('当前版（第 3 版）的文件不算新版', () {
      expect(LcDocument.parse(fixture('page-v2.saved-v3.lc.json')).isFromNewer, isFalse);
    });
  });
}
