/// 积木目录：有哪些积木（op）、哪些表达式（e），各自叫什么、归哪一类、要哪些参数、新建时的默认值。
///
/// 积木编辑界面照着这张表画（不用自己记每种积木长什么样）；校验（logic_validate.dart）、中文读法（logic_text.dart）、
/// 翻 JavaScript（logic_js.dart）也都从这里查参数。加一种积木：先改 docs/lowcode-v2-design.md 的表，再改这里，
/// 再补翻译和读法——`test/lowcode_logic_test.dart` 会核对这张表和设计文档是不是一致。
library;

import 'package:lopicode/lowcode/logic_expr.dart';
import 'package:lopicode/lowcode/logic_model.dart';
import 'package:lopicode/lowcode/model.dart';

export 'package:lopicode/lowcode/logic_expr.dart';
export 'package:lopicode/lowcode/logic_validate.dart';

/// 参数是哪一种，界面据此决定用什么控件来填。
enum LcArgKind {
  /// 一个表达式对象（`{"e": ...}`）。
  expr,

  /// 一串表达式（`join` 的 items）。
  exprList,

  /// 页面变量的名字。
  variable,

  /// 控件（节点）的 id。
  node,

  /// 几个固定值里选一个（[LcArgSpec.choices]）。
  choice,

  /// 直接填的文字 / 数字 / 是否（只有 text / num / bool 这三种表达式的 `v` 用）。
  literalText,
  literalNumber,
  literalBool,
}

/// 一个参数的说明。
class LcArgSpec {
  const LcArgSpec(this.name, this.label, this.kind, {this.choices = const [], this.choiceLabels = const [], this.optional = false, this.valueType = LcType.any});

  /// JSON 里的字段名。
  final String name;

  /// 界面上显示的中文名。
  final String label;
  final LcArgKind kind;

  /// [LcArgKind.choice] 的可选值，和对应的中文名（一样长）。
  final List<String> choices;
  final List<String> choiceLabels;

  /// 可以不填（现在只有 fetch 的 into）。
  final bool optional;

  /// [LcArgKind.expr] 希望得到什么类型（[LcType]），界面可以据此给默认值和提示；不是硬性要求（翻代码时会自动转换）。
  final String valueType;

  /// 某个可选值的中文名；不在表里就原样返回。
  String choiceLabel(String value) {
    final i = choices.indexOf(value);
    return i >= 0 && i < choiceLabels.length ? choiceLabels[i] : value;
  }
}

/// 一种积木的说明。
class LcBlockSpec {
  const LcBlockSpec(this.op, this.label, this.category, this.args, {this.bodyLabel, this.elseLabel, this.hint = ''});

  final String op;
  final String label;

  /// 分类，见 [lcBlockCategories]。
  final String category;
  final List<LcArgSpec> args;

  /// 有 body 的积木，body 那一格叫什么（“那么”“成功后”“重复做”“然后”）；null＝这种积木里面不能放积木。
  final String? bodyLabel;

  /// 有 else 的积木，else 那一格叫什么（“否则”“失败后”）；null＝没有。
  final String? elseLabel;

  /// 一句话说明，给积木面板当副标题。
  final String hint;

  bool get hasBody => bodyLabel != null;
  bool get hasElse => elseLabel != null;

  LcArgSpec? arg(String name) {
    for (final a in args) {
      if (a.name == name) return a;
    }
    return null;
  }
}

/// 一种表达式的说明。
class LcExprSpec {
  const LcExprSpec(this.kind, this.label, this.category, this.args, {this.hint = ''});

  final String kind;
  final String label;

  /// 分类，见 [lcExprCategories]。
  final String category;
  final List<LcArgSpec> args;
  final String hint;

  LcArgSpec? arg(String name) {
    for (final a in args) {
      if (a.name == name) return a;
    }
    return null;
  }
}

/// 积木面板的分类，按这个顺序排。
const List<String> lcBlockCategories = ['变量', '控件', '流程', '交互', '网络'];

/// 选表达式时的分类。
const List<String> lcExprCategories = ['直接填', '变量', '控件', '运算'];

const List<String> _propLabels = ['文字', '输入内容', '是否显示', '背景色', '文字颜色', '图片地址', '提示文字'];
const List<String> _binLabels = ['加', '减', '乘', '除以', '除以…的余数', '等于', '不等于', '小于', '小于等于', '大于', '大于等于', '并且', '或者'];

/// 全部积木，按积木面板里的顺序。键是 op。
const Map<String, LcBlockSpec> lcBlockSpecs = {
  'setVar': LcBlockSpec('setVar', '设置变量', '变量', [LcArgSpec('name', '变量', LcArgKind.variable), LcArgSpec('value', '值', LcArgKind.expr)], hint: '把变量改成一个新的值'),
  'changeVar': LcBlockSpec('changeVar', '变量加上', '变量', [
    LcArgSpec('name', '变量', LcArgKind.variable, valueType: LcType.number),
    LcArgSpec('by', '加上', LcArgKind.expr, valueType: LcType.number),
  ], hint: '数字变量加上一个数（减就加负数）'),
  'setProp': LcBlockSpec('setProp', '改控件', '控件', [
    LcArgSpec('node', '控件', LcArgKind.node),
    LcArgSpec('prop', '改什么', LcArgKind.choice, choices: kWritableProps, choiceLabels: _propLabels),
    LcArgSpec('value', '改成', LcArgKind.expr),
  ], hint: '改文字、显示 / 隐藏、颜色、图片…'),
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
  'wait': LcBlockSpec(
    'wait',
    '等一会儿',
    '流程',
    [LcArgSpec('ms', '毫秒', LcArgKind.expr, valueType: LcType.number)],
    bodyLabel: '然后',
    hint: '过一段时间再做里面的积木（1000 毫秒＝1 秒）',
  ),
  'alert': LcBlockSpec('alert', '弹提示', '交互', [LcArgSpec('message', '内容', LcArgKind.expr, valueType: LcType.text)], hint: '弹出一个提示框'),
  'navigate': LcBlockSpec('navigate', '跳转网址', '交互', [LcArgSpec('url', '网址', LcArgKind.expr, valueType: LcType.text)], hint: '打开另一个页面'),
  'log': LcBlockSpec('log', '写到控制台', '交互', [LcArgSpec('value', '内容', LcArgKind.expr)], hint: '调试用：在浏览器控制台里记一笔'),
  'fetch': LcBlockSpec(
    'fetch',
    '请求网址',
    '网络',
    [
      LcArgSpec('url', '网址', LcArgKind.expr, valueType: LcType.text),
      LcArgSpec('method', '方式', LcArgKind.choice, choices: ['GET', 'POST'], choiceLabels: ['GET（取数据）', 'POST（提交）']),
      LcArgSpec('into', '结果放进变量', LcArgKind.variable, optional: true),
    ],
    bodyLabel: '成功后',
    elseLabel: '失败后',
    hint: '向一个网址要数据，拿到的文字放进变量',
  ),
};

/// 全部表达式。键是 e。
const Map<String, LcExprSpec> lcExprSpecs = {
  'text': LcExprSpec('text', '文字', '直接填', [LcArgSpec('v', '文字', LcArgKind.literalText)]),
  'num': LcExprSpec('num', '数字', '直接填', [LcArgSpec('v', '数字', LcArgKind.literalNumber)]),
  'bool': LcExprSpec('bool', '是 / 否', '直接填', [LcArgSpec('v', '是否', LcArgKind.literalBool)]),
  'var': LcExprSpec('var', '变量的值', '变量', [LcArgSpec('name', '变量', LcArgKind.variable)]),
  'prop': LcExprSpec('prop', '控件的属性', '控件', [
    LcArgSpec('node', '控件', LcArgKind.node),
    LcArgSpec('prop', '读什么', LcArgKind.choice, choices: kReadableProps, choiceLabels: ['文字', '输入内容', '是否显示']),
  ], hint: '读控件上现在的文字、输入框里的内容、有没有显示'),
  'event': LcExprSpec('event', '输入的内容', '控件', [], hint: '只能用在“输入内容变化时”的处理里：输入框当前的内容'),
  'bin': LcExprSpec('bin', '运算 / 比较', '运算', [
    LcArgSpec('l', '左边', LcArgKind.expr),
    LcArgSpec('op', '运算', LcArgKind.choice, choices: kBinOps, choiceLabels: _binLabels),
    LcArgSpec('r', '右边', LcArgKind.expr),
  ], hint: '加减乘除、比大小、并且 / 或者'),
  'not': LcExprSpec('not', '不是', '运算', [LcArgSpec('x', '条件', LcArgKind.expr, valueType: LcType.boolean)], hint: '把“是”变成“否”，“否”变成“是”'),
  'join': LcExprSpec('join', '拼成文字', '运算', [LcArgSpec('items', '内容', LcArgKind.exprList)], hint: '把几个值连成一段文字'),
};

/// 某一类里的积木，按面板顺序。
List<LcBlockSpec> blockSpecsIn(String category) => [
  for (final s in lcBlockSpecs.values)
    if (s.category == category) s,
];

/// 某一类里的表达式。
List<LcExprSpec> exprSpecsIn(String category) => [
  for (final s in lcExprSpecs.values)
    if (s.category == category) s,
];

/// 哪些类型的控件能改 / 读某个属性。null＝所有控件都行。
/// 这是照 export_html.dart 导出的标签定的：文字只有 <p> 和 <button> 能整段换；输入内容、提示文字只有 <input> 有；图片地址只有图片有。
List<String>? nodeTypesForProp(String prop) => switch (prop) {
  'text' => const ['text', 'button'],
  'value' || 'placeholder' => const ['input'],
  'src' => const ['image'],
  _ => null,
};

/// 这个控件能不能改 / 读这个属性。
bool propFitsNode(String prop, String nodeType) => nodeTypesForProp(prop)?.contains(nodeType) ?? true;

/// 某类型的控件能改的属性（按 [kWritableProps] 的顺序）。
List<String> writablePropsFor(String nodeType) => [
  for (final p in kWritableProps)
    if (propFitsNode(p, nodeType)) p,
];

/// 某类型的控件能读的属性。
List<String> readablePropsFor(String nodeType) => [
  for (final p in kReadableProps)
    if (propFitsNode(p, nodeType)) p,
];

/// 某种类型的值，默认用哪个表达式（新建积木、往 join 里加一项时用）。
Map<String, dynamic> defaultExprFor(String valueType) => switch (valueType) {
  LcType.number => exNum(1),
  LcType.boolean => exBool(true),
  _ => exText(''),
};

/// 新建一个某种类的表达式，参数填默认值。`doc` 给了就顺手挑第一个变量 / 合适的控件填上，否则留空（校验会提示没选）。
/// 不认识的种类返回一段空文字。
Map<String, dynamic> newExpr(String kind, [LcDocument? doc]) {
  switch (kind) {
    case 'num':
      return exNum(0);
    case 'bool':
      return exBool(true);
    case 'var':
      return exVar(doc != null && doc.logic.variables.isNotEmpty ? doc.logic.variables.first.name : '');
    case 'prop':
      final input = doc == null ? null : _firstNode(doc, const ['input']);
      if (input != null) return exProp(input.id, 'value');
      return exProp((doc == null ? null : _firstNode(doc, const ['text', 'button']))?.id ?? '', 'text');
    case 'event':
      return exEvent();
    case 'bin':
      return exBin('+', exNum(1), exNum(1));
    case 'not':
      return exNot(exBool(true));
    case 'join':
      return exJoin([exText(''), exText('')]);
    default:
      return exText('');
  }
}

/// 新建一块积木，参数填默认值。`doc` 给了就顺手挑第一个合适的变量 / 控件填上（这样新积木直接能用）；
/// 没给、或页面里没有合适的，就留空，校验会提示“还没选”。不认识的 op 返回一块没有参数的积木。
LcBlock newBlock(String op, [LcDocument? doc]) {
  String firstVar([String? type]) {
    if (doc == null) return '';
    for (final v in doc.logic.variables) {
      if (type == null || v.type == type) return v.name;
    }
    return '';
  }

  switch (op) {
    case 'setVar':
      final name = firstVar();
      return LcBlock(op: op, args: {'name': name, 'value': defaultExprFor(doc?.logic.variable(name)?.type ?? LcType.text)});
    case 'changeVar':
      return LcBlock(op: op, args: {'name': firstVar('number'), 'by': exNum(1)});
    case 'setProp':
      final node = doc == null ? null : _firstNode(doc, const ['text', 'button']);
      return LcBlock(op: op, args: {'node': node?.id ?? '', 'prop': 'text', 'value': exText('')});
    case 'if':
      return LcBlock(op: op, args: {'cond': exBool(true)});
    case 'repeat':
      return LcBlock(op: op, args: {'times': exNum(3)});
    case 'wait':
      return LcBlock(op: op, args: {'ms': exNum(1000)});
    case 'alert':
      return LcBlock(op: op, args: {'message': exText('你好')});
    case 'navigate':
      return LcBlock(op: op, args: {'url': exText('https://')});
    case 'log':
      return LcBlock(op: op, args: {'value': exText('')});
    case 'fetch':
      return LcBlock(op: op, args: {'url': exText('https://'), 'method': 'GET', 'into': firstVar('text')});
    default:
      return LcBlock(op: op);
  }
}

/// 页面里第一个类型在 `types` 里的控件（按从上到下的顺序）。
LcNode? _firstNode(LcDocument doc, List<String> types) {
  LcNode? walk(LcNode n) {
    if (types.contains(n.type)) return n;
    for (final c in n.children) {
      final r = walk(c);
      if (r != null) return r;
    }
    return null;
  }

  return walk(doc.root);
}
