// 积木编辑器测试共用的样例页面。
import 'package:lopicode/lowcode/logic_blocks.dart';
import 'package:lopicode/lowcode/logic_model.dart';
import 'package:lopicode/lowcode/model.dart';

String nodeIdOf(LcDocument doc, String type) {
  String? walk(LcNode n) {
    if (n.type == type) return n.id;
    for (final c in n.children) {
      final r = walk(c);
      if (r != null) return r;
    }
    return null;
  }

  return walk(doc.root)!;
}

LcDocument _base() {
  final doc = LcDocument.starter('测试页');
  doc.logic.addVariable('count', type: 'number', initial: 0);
  doc.logic.addVariable('msg', type: 'text', initial: '');
  doc.logic.addVariable('ok', type: 'bool', initial: false);
  return doc;
}

/// 三串脚本：点击（赋值、如果…否则、重复）、输入（改控件、拼接）、页面打开（等一会儿、请求）。
LcDocument sampleDoc() {
  final doc = _base();
  final button = nodeIdOf(doc, 'button'), input = nodeIdOf(doc, 'input'), text = nodeIdOf(doc, 'text');
  doc.logic.addHandler('click', target: button)!.body.addAll([
    LcBlock(op: 'changeVar', args: {'name': 'count', 'by': exNum(1)}),
    LcBlock(
      op: 'if',
      args: {'cond': exBin('and', exBin('>', exVar('count'), exNum(10)), exNot(exVar('ok')))},
      body: [
        LcBlock(op: 'alert', args: {'message': exText('点太多次啦')}),
        LcBlock(op: 'setVar', args: {'name': 'count', 'value': exNum(0)}),
      ],
      orElse: [
        LcBlock(
          op: 'setProp',
          args: {
            'node': text,
            'prop': 'text',
            'value': exJoin([exText('点了 '), exVar('count'), exText(' 次')]),
          },
        ),
      ],
    ),
    LcBlock(op: 'repeat', args: {'times': exNum(3)}),
  ]);
  doc.logic.addHandler('input', target: input)!.body.addAll([
    LcBlock(op: 'setVar', args: {'name': 'msg', 'value': exEvent()}),
    LcBlock(op: 'setProp', args: {'node': button, 'prop': 'visible', 'value': exBin('!=', exVar('msg'), exText(''))}),
  ]);
  doc.logic.addHandler('load')!.body.addAll([
    LcBlock(
      op: 'wait',
      args: {'ms': exNum(1000)},
      body: [
        LcBlock(
          op: 'fetch',
          args: {'url': exText('https://example.com/api'), 'method': 'GET', 'into': 'msg'},
          body: [
            LcBlock(op: 'log', args: {'value': exVar('msg')}),
          ],
          orElse: [
            LcBlock(op: 'alert', args: {'message': exText('网络不通')}),
          ],
        ),
      ],
    ),
  ]);
  return doc;
}

/// 一串里放各种不好排的：很长的句子（要换行）、套了好几层的运算、不认识的积木和表达式、没填的槽、没选的变量。
LcDocument shapesDoc() {
  final doc = _base();
  final text = nodeIdOf(doc, 'text');
  doc.logic.addHandler('click')!.body.addAll([
    LcBlock(
      op: 'setProp',
      args: {
        'node': text,
        'prop': 'text',
        'value': exJoin([exText('这是一段特别特别长的文字，用来看输入框怎么省略'), exBin('+', exBin('*', exVar('count'), exNum(2)), exNum(100)), exProp(text, 'text')]),
      },
    ),
    LcBlock(
      op: 'if',
      args: {'cond': exBin('or', exBin('>=', exBin('+', exVar('count'), exBin('%', exNum(7), exNum(3))), exNum(10)), exNot(exBin('==', exVar('msg'), exText('好'))))},
      body: [
        LcBlock(op: 'frobnicate', args: {'x': 1}),
      ],
    ),
    LcBlock(
      op: 'setVar',
      args: {
        'name': '',
        'value': {'e': 'mystery'},
      },
    ),
    LcBlock(op: 'if', args: {}),
    LcBlock(op: 'alert', args: {'message': exBool(true)}),
  ]);
  return doc;
}

/// “如果”一层套一层，一共 `depth` 层，最里面一块“弹提示”。
LcDocument deepDoc([int depth = 12]) {
  final doc = _base();
  var inner = LcBlock(op: 'alert', args: {'message': exText('到底了')});
  for (var i = 0; i < depth; i++) {
    inner = LcBlock(op: i.isEven ? 'if' : 'repeat', args: i.isEven ? {'cond': exBool(true)} : {'times': exNum(2)}, body: [inner]);
  }
  doc.logic.addHandler('load')!.body.add(inner);
  return doc;
}
