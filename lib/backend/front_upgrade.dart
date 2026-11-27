/// 旧的页面逻辑 → 新的页面逻辑（积木第 5 版·前端 1·下半）。“升级到新的页面逻辑…”用它。
///
/// 一块一块对着换，不改意思：每个处理变成“页面”库的一顶帽子；旧积木换成“页面”库里对着的那一块；
/// 旧规矩（加减乘除先转数字、转不了当 0；比较两边不是同一种就都转成文字；“如果”看的是“成立不成立”）
/// 用“页面”库里“旧积木”那一类的几块原样留住（按旧规矩转数字、转文字、成立、等于、旧运算、旧请求），所以升级以后跑出来和以前一样。
/// 不认识的积木原样留着（画布上标成不认识）。任何输入都不抛异常。
library;

import 'package:lopicode/backend/backend_block_host.dart';
import 'package:lopicode/backend/backend_lib_doc.dart';
import 'package:lopicode/backend/backend_model.dart';
import 'package:lopicode/backend/front_doc.dart';
import 'package:lopicode/lowcode/lib_blocks.dart' show libOp;
import 'package:lopicode/lowcode/lib_page.dart';
import 'package:lopicode/lowcode/logic_blocks.dart';
import 'package:lopicode/lowcode/logic_expr.dart';
import 'package:lopicode/lowcode/logic_model.dart';
import 'package:lopicode/lowcode/model.dart' show kLcGoPageOp;

String _pg(String id) => libOp(kLcPageLibId, id);
Map<String, dynamic> _ex(String id, [Map<String, dynamic> args = const {}]) => {'e': _pg(id), ...args};

class _Up {
  _Up(this.types);

  /// 状态名 → 类型（放进状态以前按它转）。
  final Map<String, String> types;
  final List<String> notes = [];

  Map<String, dynamic> _num(Object? e) => _ex('oldNum', {'value': expr(e)});
  Map<String, dynamic> _text(Object? e) => _ex('oldText', {'value': expr(e)});

  /// 已经改写好的值按旧规矩转成数字（本来就是写死的数字就不用包）。
  Map<String, dynamic> _numOf(Map<String, dynamic> e) => e['e'] == 'num' ? e : _ex('oldNum', {'value': e});
  Map<String, dynamic> _truthy(Object? e) => _ex('oldTruthy', {'value': expr(e)});

  Map<String, dynamic> expr(Object? raw, [int depth = 0]) {
    final e = asExpr(raw);
    if (e == null || depth > kMaxExprDepth) return exText('');
    switch (exprKind(e)) {
      case 'var':
        return _ex('stateGet', {'name': e['name'] is String ? e['name'] : ''});
      case 'prop':
        return _ex('propGet', {'node': e['node'] is String ? e['node'] : '', 'prop': e['prop'] is String ? e['prop'] : 'text'});
      case 'event':
        return _ex('eventValue');
      case 'bin':
        final op = e['op'], l = expr(e['l'], depth + 1), r = expr(e['r'], depth + 1);
        final eq = _ex('oldEq', {'a': l, 'b': r});
        if (op == '==') return eq;
        if (op == '!=') return {'e': 'not', 'x': eq};
        if (op == 'and' || op == 'or') {
          return {
            'e': 'logic',
            'op': op,
            'l': _ex('oldTruthy', {'value': l}),
            'r': _ex('oldTruthy', {'value': r}),
          };
        }
        // 旧规矩：加减乘除和比大小，两边都先转成数字（"3" 加 "10" 是 13，不是 "310"）。
        return _ex('oldOp', {'op': exText(op is String ? op : '+'), 'a': _numOf(l), 'b': _numOf(r)});
      case 'not':
        return {
          'e': 'not',
          'x': _ex('oldTruthy', {'value': expr(e['x'], depth + 1)}),
        };
      case 'join':
        final items = e['items'];
        return {
          'e': 'join',
          'items': [
            if (items is List)
              for (final x in items) _ex('oldText', {'value': expr(x, depth + 1)}),
          ],
        };
      default:
        return Map<String, dynamic>.of(e); // 文字、数字、是 / 否；不认识的原样留着
    }
  }

  List<LcBlock> blocks(List<LcBlock> list, [int depth = 0]) => depth > LcBlock.maxDepth ? const [] : [for (final b in list) ...block(b, depth)];

  List<LcBlock> block(LcBlock b, int depth) {
    List<LcBlock> inner(List<LcBlock> l) => blocks(l, depth + 1);
    final a = b.args;
    String s(String k) => a[k] is String ? a[k] as String : '';
    switch (b.op) {
      case 'setVar':
        // 旧规矩：放进状态以前先按状态的类型转好。
        final value = switch (types[s('name')]) {
          LcType.number => _numOf(expr(a['value'])),
          LcType.text => _text(a['value']),
          LcType.boolean => _truthy(a['value']),
          _ => expr(a['value']),
        };
        return [
          LcBlock(op: _pg('stateSet'), args: {'name': s('name'), 'value': value}),
        ];
      case 'changeVar':
        return [
          LcBlock(
            op: _pg('stateSet'),
            args: {
              'name': s('name'),
              'value': _ex('oldOp', {
                'op': exText('+'),
                'a': _numOf(_ex('stateGet', {'name': s('name')})),
                'b': _numOf(expr(a['by'])),
              }),
            },
          ),
        ];
      case 'setProp':
        return [
          LcBlock(op: _pg('propSet'), args: {'node': s('node'), 'prop': s('prop'), 'value': s('prop') == 'visible' ? _truthy(a['value']) : _text(a['value'])}),
        ];
      case 'if':
        return [
          LcBlock(op: 'if', args: {'cond': _truthy(a['cond'])}, body: inner(b.body), orElse: inner(b.orElse), noElse: b.orElse.isEmpty),
        ];
      case 'repeat':
        // 旧规矩：“重复 2.5 次”做 3 遍——次数先按旧规矩转数字，再向上取整。
        return [
          LcBlock(
            op: 'repeat',
            args: {
              'times': {'e': 'round', 'x': _num(a['times']), 'fn': 'ceil'},
            },
            body: inner(b.body),
          ),
        ];
      case 'wait':
        return [
          LcBlock(op: _pg('after'), args: {'ms': _num(a['ms'])}, body: inner(b.body)),
        ];
      case 'alert':
        return [
          LcBlock(op: _pg('alert'), args: {'message': _text(a['message'])}),
        ];
      case 'navigate':
        return [
          LcBlock(op: _pg('navigate'), args: {'url': _text(a['url'])}),
        ];
      case kLcGoPageOp:
        return [
          LcBlock(op: _pg('goPage'), args: {'page': s('page')}),
        ];
      case 'log':
        return [
          LcBlock(op: _pg('oldLog'), args: {'value': expr(a['value'])}),
        ];
      case 'fetch':
        final into = s('into');
        final data = asExpr(a['data']);
        if (data != null && !(exprKind(data) == 'text' && data['v'] == '')) notes.add('“请求网址”带上的内容没有带过去（新的页面逻辑里用“要等的事”里的请求积木带）');
        return [
          LcBlock(
            op: _pg('oldFetch'),
            args: {'method': a['method'] == 'POST' ? 'POST' : 'GET', 'url': expr(a['url'])},
            body: [
              if (into.isNotEmpty) LcBlock(op: _pg('stateSet'), args: {'name': into, 'value': _ex('fetchText')}),
              ...inner(b.body),
            ],
            orElse: inner(b.orElse),
          ),
        ];
      default:
        return [b.clone()];
    }
  }
}

/// 升级的结果：新的页面逻辑，和要告诉人的话（哪里没能原样带过去）。
typedef LcFrontUpgrade = ({BeDocument doc, List<String> notes});

/// 把这一页的旧处理改写成新的页面逻辑（不动传进来的 [logic]）。
LcFrontUpgrade lcUpgradeToFront(LcLogic logic) {
  final up = _Up({for (final v in logic.variables) v.name: v.type});
  final doc = lcFrontNew()..loaded = logic.loaded;
  var n = 0;
  for (final h in logic.handlers) {
    final String id;
    final args = <String, dynamic>{};
    switch (h.event) {
      case 'click' || 'input':
        id = h.event == 'click' ? 'onClick' : 'onInput';
        args['node'] = h.target ?? '';
      case 'load':
        id = 'onMounted';
      default:
        up.notes.add('有一个处理的事件不认识（${h.event}），没有带过去');
        continue;
    }
    doc.hats.add(BeLibHat(id: 'h${++n}', op: _pg(id), args: args, body: up.blocks(h.body), x: h.x, y: h.y));
  }
  for (final u in logic.uses) {
    final id = u['id'];
    if (id is String && id != kLcPageLibId && doc.use(id) == null) doc.uses.add(BeLibUse(id));
  }
  doc.syncSide();
  return (doc: doc, notes: up.notes);
}

/// 升级前先看一眼：升完会有几处标红、其中几处能一键修、要告诉人的话。
({int errors, int fixable, List<String> notes}) lcUpgradePreview(LcLogic logic) {
  final up = lcUpgradeToFront(logic);
  final host = BeBlockHost(doc: up.doc);
  final errors = host.issues.where((i) => i.isError).toList();
  host.stopIssueTimer();
  return (errors: errors.length, fixable: errors.where((i) => i.actions.isNotEmpty).length, notes: up.notes);
}
