/// 把积木、表达式、事件处理读成一句人话。积木界面的每一行、校验信息、导出脚本里的注释都用它。
///
/// 控件不说 id（“n3”没人看得懂），说“类型 + 上面的字”：「按钮“提交”」。
library;

import 'package:lopicode/lowcode/logic_blocks.dart';
import 'package:lopicode/lowcode/logic_model.dart';
import 'package:lopicode/lowcode/model.dart';

/// 摘要里的文字最多留这么多个字，多了截断加“…”。
const int _summaryLimit = 12;

/// `keepEdges`：文字字面量两头的空格是内容的一部分（“共 ” 和 “共” 拼出来不一样），要留着给人看见。
String _clip(String s, [int limit = _summaryLimit, bool keepEdges = false]) {
  // 换行、制表符收成空格：这些话会放进单行的列表项和注释里。
  final collapsed = s.replaceAll(RegExp(r'[\r\n\t\u2028\u2029]+'), ' ');
  final flat = keepEdges ? collapsed : collapsed.replaceAll(RegExp(r'\s+'), ' ').trim();
  final runes = flat.runes.toList();
  return runes.length <= limit ? flat : '${String.fromCharCodes(runes.take(limit))}…';
}

/// 控件怎么称呼：「按钮“提交”」；没有字的只说类型：「卡片」；找不到的：「已删除的控件」。
/// `id` 为空（还没选）说「还没选控件」。
String describeNode(LcDocument doc, String? id) {
  if (id == null || id.isEmpty) return '「还没选控件」';
  final node = doc.find(id);
  if (node == null) return '「已删除的控件」';
  final label = lcSpecs[node.type]?.label ?? node.type;
  final words = switch (node.type) {
    'input' => node.strProp('placeholder'),
    'page' => doc.title.isEmpty ? null : doc.title,
    _ => node.strProp('text'),
  };
  return words == null || words.trim().isEmpty ? '「$label」' : '「$label“${_clip(words)}”」';
}

/// 属性的中文名（文字 / 输入内容 / 是否显示 / 背景色…）；不认识的原样返回。
String describeProp(String prop) => lcBlockSpecs['setProp']!.arg('prop')!.choiceLabel(prop);

String _varName(Object? name) => name is String && name.isNotEmpty ? name : '（还没选变量）';

const Map<String, String> _opSigns = {'+': '+', '-': '-', '*': '×', '/': '÷', '%': '除以后余', '==': '=', '!=': '≠', '<': '<', '<=': '≤', '>': '>', '>=': '≥', 'and': '并且', 'or': '或者'};

String _number(num v) => v is int || v == v.roundToDouble() && v.abs() < 1e15 ? '${v.round()}' : '$v';

/// 表达式读成人话：`count > 10`、`“你好”`、`「输入框“请输入”」的输入内容`。
/// 缺了的地方写“（空）”，不认识的写“不认识的值（种类）”。
String describeExpr(Object? expr, LcDocument doc) => _expr(expr, doc, 0, false);

String _expr(Object? expr, LcDocument doc, int depth, bool nested) {
  if (depth > kMaxExprDepth) return '…';
  final kind = exprKind(expr);
  switch (kind) {
    case null:
      return '（空）';
    case 'text':
      final v = exprString(expr, 'v');
      return v == null ? '（空）' : '“${_clip(v, 24, true)}”';
    case 'num':
      final v = exprNum(expr, 'v');
      return v == null ? '（空）' : _number(v);
    case 'bool':
      final v = exprBool(expr, 'v');
      return v == null ? '（空）' : (v ? '是' : '否');
    case 'var':
      return _varName(exprString(expr, 'name'));
    case 'prop':
      return '${describeNode(doc, exprString(expr, 'node'))}的${describeProp(exprString(expr, 'prop') ?? '')}';
    case 'event':
      return '输入的内容';
    case 'bin':
      final op = exprString(expr, 'op') ?? '';
      final text = '${_expr(exprField(expr, 'l'), doc, depth + 1, true)} ${_opSigns[op] ?? '?'} ${_expr(exprField(expr, 'r'), doc, depth + 1, true)}';
      // 套在别的运算里要加括号，不然 “a + b × c” 看不出先算哪个。
      return nested ? '（$text）' : text;
    case 'not':
      return '不是（${_expr(exprField(expr, 'x'), doc, depth + 1, false)}）';
    case 'join':
      final items = exprField(expr, 'items');
      final parts = [
        if (items is List)
          for (final item in items) _expr(item, doc, depth + 1, true),
      ];
      return parts.isEmpty ? '拼接（空）' : '拼接（${parts.join('、')}）';
    default:
      return '不认识的值（${_clip(kind)}）';
  }
}

/// 积木读成一句人话，只说这一块自己（里面嵌的积木不展开，用“…”带过）：
/// “把 count 加上 1”“如果 count > 10 那么…”“把「按钮“提交”」的文字 改成 “好了””。
String describeBlock(LcBlock b, LcDocument doc) {
  String arg(String name) => describeExpr(b.args[name], doc);
  switch (b.op) {
    case 'setVar':
      return '把 ${_varName(b.args['name'])} 设为 ${arg('value')}';
    case 'changeVar':
      return '把 ${_varName(b.args['name'])} 加上 ${arg('by')}';
    case 'setProp':
      final node = b.args['node'];
      final prop = b.args['prop'];
      final who = describeNode(doc, node is String ? node : null);
      if (prop == 'visible') {
        // 最常见的写法直接说“显示 / 隐藏”，比“把是否显示改成否”顺口。
        final v = exprKind(b.args['value']) == 'bool' ? exprBool(b.args['value'], 'v') : null;
        if (v != null) return v ? '显示 $who' : '隐藏 $who';
      }
      return '把 $who的${describeProp(prop is String ? prop : '')} 改成 ${arg('value')}';
    case 'if':
      return b.orElse.isEmpty ? '如果 ${arg('cond')} 那么…' : '如果 ${arg('cond')} 那么…否则…';
    case 'repeat':
      return '重复 ${arg('times')} 次…';
    case 'wait':
      return '等 ${arg('ms')} 毫秒，然后…';
    case 'alert':
      return '弹出提示 ${arg('message')}';
    case 'navigate':
      return '跳转到 ${arg('url')}';
    case 'log':
      return '写到控制台 ${arg('value')}';
    case 'fetch':
      final method = b.args['method'] == 'POST' ? 'POST' : 'GET';
      final into = b.args['into'];
      final tail = into is String && into.isNotEmpty ? '，结果放进 $into' : '';
      return '用 $method 请求 ${arg('url')}$tail';
    default:
      return '不认识的积木（${_clip(b.op)}）';
  }
}

/// 事件的中文名：点击时 / 输入内容变化时 / 页面打开时。
String describeEvent(String event) => switch (event) {
  'click' => '点击时',
  'input' => '输入内容变化时',
  'load' => '页面打开时',
  _ => '不认识的事件（${_clip(event)}）',
};

/// 事件处理读成一句话：“点击「按钮“提交”」时”“「输入框“请输入”」的内容变化时”“页面打开时”。
String describeHandler(LcHandler h, LcDocument doc) => switch (h.event) {
  'click' => '点击${describeNode(doc, h.target)}时',
  'input' => '${describeNode(doc, h.target)}的内容变化时',
  'load' => '页面打开时',
  _ => describeEvent(h.event),
};

/// 积木的位置读成人话：“第 2 块 › 否则 › 第 1 块”。
/// 中间的“那么 / 否则 / 成功后…”按每一层积木自己的叫法来；路径对不上就只说到对得上的那一层。
String describeBlockPath(LcHandler h, LcBlockPath path) {
  final parts = <String>[];
  var list = h.body;
  LcBlock? parent;
  for (var i = 0; i < path.length; i++) {
    if (parent != null) {
      final spec = lcBlockSpecs[parent.op];
      parts.add(path[i].inElse ? (spec?.elseLabel ?? '否则') : (spec?.bodyLabel ?? '里面'));
      list = path[i].inElse ? parent.orElse : parent.body;
    }
    parts.add('第 ${path[i].index + 1} 块');
    final index = path[i].index;
    if (index < 0 || index >= list.length) break;
    parent = list[index];
  }
  return parts.join(' › ');
}

/// 变量类型的中文名。
String describeVarType(String type) => switch (type) {
  'number' => '数字',
  'bool' => '是 / 否',
  'text' => '文字',
  _ => type,
};
