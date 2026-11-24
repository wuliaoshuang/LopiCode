/// 后端积木目录：有哪些积木（op）、哪些表达式（e），各自叫什么、归哪一类、要哪些参数、新建时的默认值。
///
/// 说明类沿用前端的 `LcBlockSpec / LcExprSpec / LcArgSpec`（lib/lowcode/logic_blocks.dart），积木编辑器照着这张表画。
/// 校验（backend_validate.dart）、中文读法（backend_text.dart）、翻成各语言（backend_ir.dart）都从这里查参数。
/// 加一种积木：先改 docs/blocks-v3-design.md 的表，再改这里，再补读法和 backend_ir.dart 里的翻译
/// ——`test/backend_model_test.dart` 会核对这张表和设计文档是不是一致。
library;

import 'package:lopicode/backend/backend_model.dart';
import 'package:lopicode/lowcode/logic_blocks.dart';
import 'package:lopicode/lowcode/logic_model.dart';

export 'package:lopicode/lowcode/logic_blocks.dart' show LcArgKind, LcArgSpec, LcBlockSpec, LcExprSpec;
export 'package:lopicode/lowcode/logic_expr.dart';

/// 积木盒的分类，按这个顺序排。
const List<String> beBlockCategories = ['返回', '数据', '变量', '流程', '调试', '网络'];

/// 选表达式时的分类。
const List<String> beExprCategories = ['直接填', '请求', '数据', '变量', '运算', '对象'];

/// 两边合起来（给按类别上色用）：一个类别一种颜色。
const List<String> beCategories = ['请求', '返回', '数据', '变量', '流程', '运算', '对象', '调试', '网络', '直接填'];

const List<String> _binLabels = ['加', '减', '乘', '除以', '除以…的余数', '等于', '不等于', '小于', '小于等于', '大于', '大于等于', '并且', '或者'];

/// “返回”积木常用的状态码（界面可以拿来做快捷选项；状态本身是个表达式，填别的数也行）。
const Map<int, String> kBeCommonStatus = {200: '成功', 201: '已创建', 400: '请求不对', 401: '没登录', 403: '不允许', 404: '找不到', 500: '服务器出错'};

/// 全部积木，按积木盒里的顺序。键是 op。
const Map<String, LcBlockSpec> beBlockSpecs = {
  'respondJson': LcBlockSpec('respondJson', '返回数据', '返回', [
    LcArgSpec('status', '状态码', LcArgKind.expr, valueType: LcType.number),
    LcArgSpec('value', '内容', LcArgKind.expr),
  ], hint: '把一个值按 JSON 返回给对方，这个接口到此结束'),
  'respondText': LcBlockSpec('respondText', '返回文字', '返回', [
    LcArgSpec('status', '状态码', LcArgKind.expr, valueType: LcType.number),
    LcArgSpec('value', '内容', LcArgKind.expr, valueType: LcType.text),
  ], hint: '返回一段纯文字，这个接口到此结束'),
  'dbInsert': LcBlockSpec('dbInsert', '往集合里加一条', '数据', [
    LcArgSpec('collection', '集合', LcArgKind.collection),
    LcArgSpec('value', '内容', LcArgKind.expr),
    LcArgSpec('into', '加好的那条放进变量', LcArgKind.variable, optional: true),
  ], hint: '内容要是一个对象；会自动带上数字 id（从 1 开始）'),
  'dbUpdate': LcBlockSpec('dbUpdate', '改集合里的一条', '数据', [
    LcArgSpec('collection', '集合', LcArgKind.collection),
    LcArgSpec('id', 'id', LcArgKind.expr, valueType: LcType.number),
    LcArgSpec('value', '要改的字段', LcArgKind.expr),
  ], hint: '只改给出的字段，别的字段不动；找不到这个 id 就什么都不做'),
  'dbDelete': LcBlockSpec('dbDelete', '删集合里的一条', '数据', [LcArgSpec('collection', '集合', LcArgKind.collection), LcArgSpec('id', 'id', LcArgKind.expr, valueType: LcType.number)], hint: '找不到这个 id 就什么都不做'),
  'setVar': LcBlockSpec('setVar', '设置变量', '变量', [LcArgSpec('name', '变量', LcArgKind.variable), LcArgSpec('value', '值', LcArgKind.expr)], hint: '把变量改成一个新的值（什么值都能放）'),
  'changeVar': LcBlockSpec('changeVar', '变量加上', '变量', [
    LcArgSpec('name', '变量', LcArgKind.variable, valueType: LcType.number),
    LcArgSpec('by', '加上', LcArgKind.expr, valueType: LcType.number),
  ], hint: '数字变量加上一个数（减就加负数）'),
  'if': LcBlockSpec(
    'if',
    '如果',
    '流程',
    [LcArgSpec('cond', '条件', LcArgKind.expr, valueType: LcType.boolean)],
    bodyLabel: '那么',
    elseLabel: '否则',
    hint: '条件成立做一些事，不成立做另一些事',
  ),
  'repeat': LcBlockSpec(
    'repeat',
    '重复',
    '流程',
    [LcArgSpec('times', '次数', LcArgKind.expr, valueType: LcType.number)],
    bodyLabel: '重复做',
    hint: '把里面的积木做 N 遍（最多 10000 遍）',
  ),
  'forEach': LcBlockSpec('forEach', '对列表里的每一项', '流程', [LcArgSpec('list', '列表', LcArgKind.expr), LcArgSpec('item', '这一项放进变量', LcArgKind.variable)], bodyLabel: '依次做', hint: '把列表里的每一项轮流放进变量，各做一遍里面的积木'),
  'log': LcBlockSpec('log', '写到日志', '调试', [LcArgSpec('value', '内容', LcArgKind.expr)], hint: '调试用：在服务的输出里记一笔'),
  'fetch': LcBlockSpec(
    'fetch',
    '请求别的网址',
    '网络',
    [
      LcArgSpec('url', '网址', LcArgKind.expr, valueType: LcType.text),
      LcArgSpec('method', '方式', LcArgKind.choice, choices: ['GET', 'POST'], choiceLabels: ['GET（取数据）', 'POST（提交）']),
      LcArgSpec('data', '提交的内容', LcArgKind.expr, optional: true),
      LcArgSpec('into', '结果放进变量', LcArgKind.variable, optional: true),
    ],
    bodyLabel: '成功后',
    elseLabel: '失败后',
    hint: '向另一个网址要数据（最多等 10 秒），拿到的文字放进变量',
  ),
};

/// 全部表达式。键是 e。
const Map<String, LcExprSpec> beExprSpecs = {
  'text': LcExprSpec('text', '文字', '直接填', [LcArgSpec('v', '文字', LcArgKind.literalText)]),
  'num': LcExprSpec('num', '数字', '直接填', [LcArgSpec('v', '数字', LcArgKind.literalNumber)]),
  'bool': LcExprSpec('bool', '是 / 否', '直接填', [LcArgSpec('v', '是否', LcArgKind.literalBool)]),
  'pathParam': LcExprSpec('pathParam', '路径参数', '请求', [LcArgSpec('name', '名字', LcArgKind.literalText)], hint: '接口路径里 :名字 那一段实际填的内容'),
  'query': LcExprSpec('query', '网址参数', '请求', [LcArgSpec('name', '名字', LcArgKind.literalText)], hint: '网址问号后面的 名字=值；没带就是空'),
  'bodyField': LcExprSpec('bodyField', '请求内容的字段', '请求', [LcArgSpec('name', '字段', LcArgKind.literalText)], hint: '对方提交的 JSON 对象里的一个字段；没有就是空'),
  'body': LcExprSpec('body', '整个请求内容', '请求', [], hint: '对方提交的 JSON；没提交或不是 JSON 就是空'),
  'header': LcExprSpec('header', '请求头', '请求', [LcArgSpec('name', '名字', LcArgKind.literalText)], hint: '比如 Authorization；没带就是空'),
  'dbAll': LcExprSpec('dbAll', '集合里的全部', '数据', [LcArgSpec('collection', '集合', LcArgKind.collection)], hint: '一个列表，按加进去的顺序'),
  'dbGet': LcExprSpec('dbGet', '集合里的一条', '数据', [LcArgSpec('collection', '集合', LcArgKind.collection), LcArgSpec('id', 'id', LcArgKind.expr, valueType: LcType.number)], hint: '按 id 找；找不到是空'),
  'dbFind': LcExprSpec('dbFind', '集合里符合的', '数据', [
    LcArgSpec('collection', '集合', LcArgKind.collection),
    LcArgSpec('key', '字段', LcArgKind.literalText),
    LcArgSpec('value', '等于', LcArgKind.expr),
  ], hint: '某个字段等于给定值的那些，一个列表'),
  'dbCount': LcExprSpec('dbCount', '集合里有几条', '数据', [LcArgSpec('collection', '集合', LcArgKind.collection)]),
  'var': LcExprSpec('var', '变量的值', '变量', [LcArgSpec('name', '变量', LcArgKind.variable)]),
  'bin': LcExprSpec('bin', '运算 / 比较', '运算', [
    LcArgSpec('l', '左边', LcArgKind.expr),
    LcArgSpec('op', '运算', LcArgKind.choice, choices: kBinOps, choiceLabels: _binLabels),
    LcArgSpec('r', '右边', LcArgKind.expr),
  ], hint: '加减乘除、比大小、并且 / 或者'),
  'not': LcExprSpec('not', '不是', '运算', [LcArgSpec('x', '条件', LcArgKind.expr, valueType: LcType.boolean)], hint: '把“是”变成“否”，“否”变成“是”'),
  'join': LcExprSpec('join', '拼成文字', '运算', [LcArgSpec('items', '内容', LcArgKind.exprList)], hint: '把几个值连成一段文字'),
  'len': LcExprSpec('len', '有几个', '运算', [LcArgSpec('x', '列表或文字', LcArgKind.expr)], hint: '列表有几项、文字有几个字、对象有几个字段'),
  'isNull': LcExprSpec('isNull', '是空的', '运算', [LcArgSpec('x', '值', LcArgKind.expr)], hint: '这个值是不是“空”（没找到、没带）'),
  'now': LcExprSpec('now', '现在的时间', '运算', [], hint: '形如 2026-11-24T06:00:00Z 的文字（世界标准时间）'),
  'obj': LcExprSpec('obj', '对象', '对象', [LcArgSpec('fields', '字段', LcArgKind.exprList)], hint: '把几个“名字: 值”组成一个对象'),
  'pair': LcExprSpec('pair', '一个字段', '对象', [LcArgSpec('key', '名字', LcArgKind.literalText), LcArgSpec('value', '值', LcArgKind.expr)], hint: '只能放在“对象”里'),
  'field': LcExprSpec('field', '对象的字段', '对象', [LcArgSpec('of', '对象', LcArgKind.expr), LcArgSpec('key', '字段', LcArgKind.literalText)], hint: '取对象里某个字段的值；没有就是空'),
};

/// 只返回 true / false 的表达式（积木编辑器可以把它们画成六边形）。`bin` 要看运算符，见 [beExprIsBool]。
const Set<String> _boolKinds = {'bool', 'not', 'isNull'};

/// 这个表达式是不是“是非类”。
bool beExprIsBool(Object? expr) {
  final kind = exprKind(expr);
  if (kind == 'bin') {
    final op = exprString(expr, 'op');
    return kCompareOps.contains(op) || kLogicOps.contains(op);
  }
  return _boolKinds.contains(kind);
}

/// 某一类里的积木，按积木盒顺序。
List<LcBlockSpec> beBlockSpecsIn(String category) => [
  for (final s in beBlockSpecs.values)
    if (s.category == category) s,
];

/// 某一类里可以单独挑的表达式（`pair` 只能在“对象”里出现，不单独挑）。
List<LcExprSpec> beExprSpecsIn(String category) => [
  for (final s in beExprSpecs.values)
    if (s.category == category && s.kind != 'pair') s,
];

// —— 表达式工厂（text / num / bool / var / bin / not / join 用 logic_expr.dart 里的 exText 等）——

Map<String, dynamic> bePathParam(String name) => {'e': 'pathParam', 'name': name};
Map<String, dynamic> beQuery(String name) => {'e': 'query', 'name': name};
Map<String, dynamic> beBodyField(String name) => {'e': 'bodyField', 'name': name};
Map<String, dynamic> beBody() => {'e': 'body'};
Map<String, dynamic> beHeader(String name) => {'e': 'header', 'name': name};
Map<String, dynamic> beDbAll(String collection) => {'e': 'dbAll', 'collection': collection};
Map<String, dynamic> beDbGet(String collection, Map<String, dynamic> id) => {'e': 'dbGet', 'collection': collection, 'id': id};
Map<String, dynamic> beDbFind(String collection, String key, Map<String, dynamic> value) => {'e': 'dbFind', 'collection': collection, 'key': key, 'value': value};
Map<String, dynamic> beDbCount(String collection) => {'e': 'dbCount', 'collection': collection};
Map<String, dynamic> beLen(Map<String, dynamic> x) => {'e': 'len', 'x': x};
Map<String, dynamic> beIsNull(Map<String, dynamic> x) => {'e': 'isNull', 'x': x};
Map<String, dynamic> beNow() => {'e': 'now'};
Map<String, dynamic> bePair(String key, Map<String, dynamic> value) => {'e': 'pair', 'key': key, 'value': value};
Map<String, dynamic> beField(Map<String, dynamic> of, String key) => {'e': 'field', 'of': of, 'key': key};

/// 对象：`{'title': exText('买菜'), 'done': exBool(false)}` → `obj{fields:[pair…]}`（按给的顺序）。
Map<String, dynamic> beObj(Map<String, Map<String, dynamic>> fields) => {
  'e': 'obj',
  'fields': [for (final e in fields.entries) bePair(e.key, e.value)],
};

String _firstVar(BeDocument? doc, [String? type]) {
  if (doc == null) return '';
  for (final v in doc.variables) {
    if (type == null || v.type == type) return v.name;
  }
  return '';
}

String _firstCollection(BeDocument? doc) => doc == null || doc.collections.isEmpty ? '' : doc.collections.first.name;

/// 新建一个某种类的表达式，参数填默认值。`doc` 给了就顺手挑第一个变量 / 集合填上，否则留空（校验会提示没选）。
/// `route` 给了，“路径参数”就默认填它路径里的第一个参数名。不认识的种类返回一段空文字。
Map<String, dynamic> newBeExpr(String kind, [BeDocument? doc, BeRoute? route]) {
  switch (kind) {
    case 'num':
      return exNum(0);
    case 'bool':
      return exBool(true);
    case 'pathParam':
      final params = route == null ? const <String>[] : bePathParams(route.path);
      return bePathParam(params.isEmpty ? 'id' : params.first);
    case 'query':
      return beQuery('q');
    case 'bodyField':
      return beBodyField('title');
    case 'body':
      return beBody();
    case 'header':
      return beHeader('Authorization');
    case 'dbAll':
      return beDbAll(_firstCollection(doc));
    case 'dbGet':
      return beDbGet(_firstCollection(doc), exNum(1));
    case 'dbFind':
      return beDbFind(_firstCollection(doc), 'done', exBool(true));
    case 'dbCount':
      return beDbCount(_firstCollection(doc));
    case 'var':
      return exVar(_firstVar(doc));
    case 'bin':
      return exBin('+', exNum(1), exNum(1));
    case 'not':
      return exNot(exBool(true));
    case 'join':
      return exJoin([exText(''), exText('')]);
    case 'len':
      return beLen(exText(''));
    case 'isNull':
      return beIsNull(exText(''));
    case 'now':
      return beNow();
    case 'obj':
      return beObj({'ok': exBool(true)});
    case 'pair':
      return bePair('name', exText(''));
    case 'field':
      return beField(exText(''), 'id');
    default:
      return exText('');
  }
}

/// 往“一串值”的参数里加一项时，新的一项默认是什么：“对象”的字段里加的是 `pair`，其余是一段空文字。
/// `ownerKind`＝外面那个表达式的种类，`arg`＝是它的哪个参数。
Map<String, dynamic> newBeListItem(String ownerKind, String arg) => ownerKind == 'obj' && arg == 'fields' ? bePair('name', exText('')) : exText('');

/// 新建一块积木，参数填默认值。`doc` 给了就顺手挑第一个合适的变量 / 集合填上（这样新积木直接能用）；
/// 没给、或文档里没有合适的，就留空，校验会提示“还没选”。不认识的 op 返回一块没有参数的积木。
LcBlock newBeBlock(String op, [BeDocument? doc]) {
  switch (op) {
    case 'respondJson':
      return LcBlock(
        op: op,
        args: {
          'status': exNum(200),
          'value': beObj({'ok': exBool(true)}),
        },
      );
    case 'respondText':
      return LcBlock(op: op, args: {'status': exNum(200), 'value': exText('好了')});
    case 'dbInsert':
      return LcBlock(op: op, args: {'collection': _firstCollection(doc), 'value': beBody(), 'into': ''});
    case 'dbUpdate':
      return LcBlock(op: op, args: {'collection': _firstCollection(doc), 'id': exNum(1), 'value': beBody()});
    case 'dbDelete':
      return LcBlock(op: op, args: {'collection': _firstCollection(doc), 'id': exNum(1)});
    case 'setVar':
      return LcBlock(op: op, args: {'name': _firstVar(doc), 'value': exText('')});
    case 'changeVar':
      return LcBlock(op: op, args: {'name': _firstVar(doc, 'number'), 'by': exNum(1)});
    case 'if':
      return LcBlock(op: op, args: {'cond': exBool(true)});
    case 'repeat':
      return LcBlock(op: op, args: {'times': exNum(3)});
    case 'forEach':
      return LcBlock(op: op, args: {'list': beDbAll(_firstCollection(doc)), 'item': _firstVar(doc)});
    case 'log':
      return LcBlock(op: op, args: {'value': exText('')});
    case 'fetch':
      return LcBlock(op: op, args: {'url': exText('https://'), 'method': 'GET', 'into': _firstVar(doc, 'text')});
    default:
      return LcBlock(op: op);
  }
}
