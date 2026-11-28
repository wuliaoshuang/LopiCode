// 第四轮 B8：一页样例——“按下”时换样子的容器 / 文字 / 卡片（不是按钮）；“重复”的列表是空的时候显示一块内容。
import 'package:lopicode/lowcode/model.dart';
import 'package:lopicode/lowcode/repeat_empty.dart';

import 'comp_samples.dart';
import 'comp_steps.dart';

/// - `box`：容器，平时浅灰底、内边距 12；按下：黄底、内边距 20、圆角 16；
/// - `word`：文字，平时深色 16 号；按下：红色 20 号；
/// - `card`：卡片，按下换底色，另有一条 Flutter 认不了的（透明度）；
/// - `row`：文字，按列表 xs 重复（开始是空的）；它后面是“空的时候显示的那一块”（里面一句字、一个按钮“放两个进来”）；
/// - `fill` / `clear`：把 xs 换成有两项的 / 空的；
/// - `say`：点了出一个轻提示 `toast`（“已保存”，3 秒）。
LcDocument b8Doc() {
  final doc = LcDocument.fromJson(
    <String, Object?>{
      'version': 3,
      'title': 'B8',
      'logic': {
        'variables': [
          {'name': 'xs', 'type': 'list', 'initial': <Object?>[]},
          {
            'name': 'two',
            'type': 'list',
            'initial': ['苹果', '香蕉'],
          },
          {'name': 'none', 'type': 'list', 'initial': <Object?>[]},
        ],
        'handlers': [
          {
            'id': 'h_say',
            'event': 'click',
            'target': 'say',
            'body': [
              {
                'op': 'setProp',
                'args': {
                  'node': 'toast',
                  'prop': 'visible',
                  'value': {'e': 'bool', 'v': true},
                },
              },
            ],
          },
          for (final (id, from) in [('fill', 'two'), ('clear', 'none'), ('fill2', 'two')])
            {
              'id': 'h_$id',
              'event': 'click',
              'target': id,
              'body': [
                {
                  'op': 'setVar',
                  'args': {'name': 'xs', 'value': cVar(from)},
                },
              ],
            },
        ],
      },
      'root': cn(
        'root',
        'page',
        {'padding': 16, 'gap': 12},
        [
          cn(
            'box',
            'container',
            {'padding': 12, 'bg': '#EEEEEE', 'radius': 4},
            [
              cn('boxText', 'text', {'text': '按住我'}),
            ],
            {
              'states': {
                'pressed': {'background-color': '#FFCC00', 'padding': '20px', 'border-radius': '16px'},
              },
            },
          ),
          cn(
            'word',
            'text',
            {'text': '按住这行字', 'color': '#222222', 'fontSize': 16},
            [],
            {
              'states': {
                'pressed': {'color': '#FF0000', 'font-size': '20px'},
              },
            },
          ),
          cn(
            'card',
            'card',
            {'padding': 12},
            [
              cn('cardText', 'text', {'text': '按住卡片'}),
            ],
            {
              'states': {
                'pressed': {'background-color': '#DDEEFF', 'opacity': '0.6'},
              },
            },
          ),
          cn(
            'row',
            'text',
            {'text': ''},
            [],
            {
              'data': {'text': cFrom('it')},
              'repeat': {'list': cFrom('xs'), 'item': 'it', 'index': 'i'},
            },
          ),
          cn('fill', 'button', {'text': '放两个'}),
          cn('clear', 'button', {'text': '清空'}),
          cn('say', 'button', {'text': '保存'}),
          cn('toast', 'dialog', {'variant': 'toast', 'text': '已保存', 'seconds': 3}),
        ],
      ),
    }.cast<String, dynamic>(),
  );
  final id = lcAddRepeatEmptyBlock(doc, 'row')!;
  final box = doc.find(id)!;
  box.children.single.props['text'] = '还没有东西';
  box.children.add(LcNode(id: 'fill2', type: 'button', props: {'text': '放两个进来'}));
  return LcDocument.parse(doc.encode());
}

/// “空的时候显示的那一块”的 id。
String b8EmptyId(LcDocument doc) => lcRepeatEmptyBlock(doc, 'row')!.id;

CompSteps b8Steps(LcDocument doc) {
  final e = b8EmptyId(doc);
  return [
    // 一开始列表是空的：那一块在，里面的字和按钮都在；没有一份“重复”
    {'op': 'count', 'sel': '.n-$e', 'is': 1},
    {'op': 'text', 'sel': '.n-$e .n-${doc.find(e)!.children.first.id}', 'is': '还没有东西'},
    {'op': 'count', 'sel': '.n-row', 'is': 0},
    // 点那一块里的按钮：列表有了两项，那一块没了
    {'op': 'click', 'sel': '.n-fill2'},
    {'op': 'count', 'sel': '.n-row', 'is': 2},
    {'op': 'count', 'sel': '.n-$e', 'is': 0},
    // 清空：又回来了
    {'op': 'click', 'sel': '.n-clear'},
    {'op': 'count', 'sel': '.n-row', 'is': 0},
    {'op': 'count', 'sel': '.n-$e', 'is': 1},
    {'op': 'click', 'sel': '.n-fill'},
    {'op': 'count', 'sel': '.n-$e', 'is': 0},
    // 轻提示：一开始不在；点“保存”出来（一句话，没有遮罩和按钮）；动画放完自己收起来；再点还能再出来
    {'op': 'shown', 'sel': '.n-toast', 'is': false},
    {'op': 'count', 'sel': '.n-toast .lc-dialog-scrim, .n-toast button', 'is': 0},
    {'op': 'click', 'sel': '.n-say'},
    {'op': 'shown', 'sel': '.n-toast', 'is': true},
    {'op': 'text', 'sel': '.n-toast .lc-toast-text', 'is': '已保存'},
    {'op': 'fire', 'sel': '.n-toast', 'name': 'animationend'},
    {'op': 'shown', 'sel': '.n-toast', 'is': false},
    {'op': 'click', 'sel': '.n-say'},
    {'op': 'shown', 'sel': '.n-toast', 'is': true},
  ];
}
