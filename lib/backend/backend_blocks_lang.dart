/// 后端积木目录里“语言核心”的那一半（积木第 4 版·第 1 阶段）：新建变量 / 常量、多口的“如果”、分情况、几种循环、跳出 / 跳过、
/// 短路的并且 / 或者、值版的“如果”、类型、数学、文字、列表、字典、JSON。
///
/// op / e 的名字照 docs/blocks-v4-language-design.md“实施记录·阶段 1”的对照表；同一族的小库函数合成一块、用积木上的下拉切换
/// （“一块顶多块”，下拉参数一律叫 `fn`，选项就是小库函数名）。怎么翻成语法树见 backend_lower_lang.dart。
/// 这张表和 backend_blocks.dart 的旧表合在一起才是全部（`beBlockSpecs` / `beExprSpecs`）。
library;

import 'package:lopicode/backend/backend_blocks_core.dart';
import 'package:lopicode/backend/backend_blocks_func.dart';
import 'package:lopicode/backend/backend_blocks_raw.dart';
import 'package:lopicode/backend/backend_blocks_strict.dart';
import 'package:lopicode/backend/backend_function.dart';
import 'package:lopicode/lowcode/logic_blocks.dart';
import 'package:lopicode/lowcode/logic_model.dart';

/// 类型判断能选的类型名（同 lib/lang 的 `kLangTypeNames`）和它们的中文。
const List<String> kBeTypeNames = ['number', 'text', 'bool', 'null', 'list', 'dict'];
const List<String> _typeLabels = ['数字', '文字', '是 / 否', '空', '列表', '字典'];

const LcArgSpec _cond = LcArgSpec('cond', '条件', LcArgKind.expr, valueType: LcType.boolean);
const LcArgSpec _newName = LcArgSpec('name', '名字', LcArgKind.literalText);

/// “如果”的否则如果段、“分情况”的每一种情况（存在积木的 `arms` 里，见 lib/lowcode/logic_model.dart）。
const LcArmSpec kBeIfArms = LcArmSpec('否则如果', [_cond], tailOptional: true);
const LcArmSpec kBeSwitchArms = LcArmSpec('是…时', [LcArgSpec('value', '值', LcArgKind.expr)], min: 1, tailOptional: true);

/// 新加的积木（语句）。键是 op。
const Map<String, LcBlockSpec> beLangBlockSpecs = {
  'let': LcBlockSpec('let', '新建变量', '变量', [_newName, LcArgSpec('value', '值', LcArgKind.expr)], hint: '在这个接口里新建一个变量，名字自己起；后面的积木都能读、能改'),
  'const': LcBlockSpec('const', '新建常量', '变量', [_newName, LcArgSpec('value', '值', LcArgKind.expr)], hint: '和变量一样，但新建以后不许再改'),
  'do': LcBlockSpec('do', '算一下', '运算', [LcArgSpec('value', '式子', LcArgKind.expr)], hint: '只为了效果算一个式子，结果不要（比如“取走最后一项”）'),
  'switch': LcBlockSpec('switch', '分情况', '流程', [LcArgSpec('value', '看谁', LcArgKind.expr)], elseLabel: '都不是', arms: kBeSwitchArms, hint: '看一个值等于哪一种情况，就做哪一段；只做第一个对上的'),
  'while': LcBlockSpec('while', '当…时重复', '流程', [_cond], bodyLabel: '重复做', hint: '条件成立就一直做，每做完一遍再看一次条件'),
  'forever': LcBlockSpec('forever', '一直重复', '流程', [], bodyLabel: '重复做', hint: '一直做下去，直到里面碰到“跳出循环”或“返回”'),
  'forCount': LcBlockSpec(
    'forCount',
    '从…数到…',
    '流程',
    [
      LcArgSpec('name', '数到几放进', LcArgKind.literalText),
      LcArgSpec('from', '从', LcArgKind.expr, valueType: LcType.number),
      LcArgSpec('to', '数到', LcArgKind.expr, valueType: LcType.number),
      LcArgSpec('step', '每次加', LcArgKind.expr, valueType: LcType.number),
    ],
    bodyLabel: '依次做',
    hint: '含两头；每次加负数就是倒着数；每次加 0 或方向不对就一遍也不做',
  ),
  'forPairs': LcBlockSpec(
    'forPairs',
    '对字典的每一对',
    '流程',
    [LcArgSpec('dict', '字典', LcArgKind.expr), LcArgSpec('key', '键放进', LcArgKind.literalText), LcArgSpec('value', '值放进', LcArgKind.literalText)],
    bodyLabel: '依次做',
    hint: '按键的顺序（从小到大）一对一对来',
  ),
  'break': LcBlockSpec('break', '跳出循环', '流程', [], hint: '马上结束最里面那个循环'),
  'continue': LcBlockSpec('continue', '跳过这一轮', '流程', [], hint: '这一遍剩下的不做了，直接开始下一遍'),
  'note': LcBlockSpec('note', '备注', '流程', [LcArgSpec('text', '备注', LcArgKind.literalText, optional: true)], hint: '给自己看的一句话，不做任何事（会变成代码里的注释）'),
  'listPush': LcBlockSpec('listPush', '列表末尾加一项', '列表', [LcArgSpec('xs', '列表', LcArgKind.expr), LcArgSpec('v', '加什么', LcArgKind.expr)], hint: '直接改这个列表'),
  'listInsert': LcBlockSpec('listInsert', '列表里插入一项', '列表', [
    LcArgSpec('xs', '列表', LcArgKind.expr),
    LcArgSpec('i', '位置', LcArgKind.expr, valueType: LcType.number),
    LcArgSpec('v', '插什么', LcArgKind.expr),
  ], hint: '位置从 0 数；插在这个位置前面，位置等于项数＝加在末尾'),
  'listSet': LcBlockSpec('listSet', '改列表的一项', '列表', [
    LcArgSpec('xs', '列表', LcArgKind.expr),
    LcArgSpec('i', '位置', LcArgKind.expr, valueType: LcType.number),
    LcArgSpec('v', '改成', LcArgKind.expr),
  ], hint: '位置从 0 数；没有这一项会出错'),
  'listRemove': LcBlockSpec('listRemove', '删列表的一项', '列表', [LcArgSpec('xs', '列表', LcArgKind.expr), LcArgSpec('i', '位置', LcArgKind.expr, valueType: LcType.number)], hint: '位置从 0 数；没有这一项会出错'),
  'setItem': LcBlockSpec('setItem', '改某一项 / 某个键', '列表', [
    LcArgSpec('of', '列表或字典', LcArgKind.expr),
    LcArgSpec('key', '位置或键', LcArgKind.expr),
    LcArgSpec('value', '改成', LcArgKind.expr),
  ], hint: '列表填位置（从 0 数），字典填键'),
  'dictSet': LcBlockSpec('dictSet', '设字典的一个键', '对象', [LcArgSpec('d', '字典', LcArgKind.expr), LcArgSpec('k', '键', LcArgKind.expr), LcArgSpec('v', '值', LcArgKind.expr)], hint: '直接改这个字典；没有这个键就加上'),
  'dictRemove': LcBlockSpec('dictRemove', '删字典的一个键', '对象', [LcArgSpec('d', '字典', LcArgKind.expr), LcArgSpec('k', '键', LcArgKind.expr)], hint: '没有这个键就什么都不做'),
};

/// 新加的表达式。键是 e。
const Map<String, LcExprSpec> beLangExprSpecs = {
  // —— 运算 ——
  'neg': LcExprSpec('neg', '取负', '运算', [LcArgSpec('x', '数', LcArgKind.expr, valueType: LcType.number)], hint: '正的变负的，负的变正的'),
  'round': LcExprSpec('round', '取整', '运算', [
    LcArgSpec('x', '数', LcArgKind.expr, valueType: LcType.number),
    LcArgSpec('fn', '怎么取', LcArgKind.choice, choices: ['round', 'floor', 'ceil'], choiceLabels: ['四舍五入', '向下取整', '向上取整']),
  ], hint: '四舍五入正好一半时往远离 0 的方向（2.5 → 3）'),
  'math': LcExprSpec('math', '绝对值 / 平方根', '运算', [
    LcArgSpec('x', '数', LcArgKind.expr, valueType: LcType.number),
    LcArgSpec('fn', '算什么', LcArgKind.choice, choices: ['abs', 'sqrt'], choiceLabels: ['绝对值', '平方根']),
  ], hint: '负数的平方根当 0'),
  'minmax': LcExprSpec('minmax', '最大 / 最小', '运算', [
    LcArgSpec('a', '一个数', LcArgKind.expr, valueType: LcType.number),
    LcArgSpec('b', '另一个数', LcArgKind.expr, valueType: LcType.number),
    LcArgSpec('fn', '要哪个', LcArgKind.choice, choices: ['max', 'min'], choiceLabels: ['大的', '小的']),
  ], hint: '两个数里大的或小的那个'),
  'pow': LcExprSpec('pow', '乘方', '运算', [LcArgSpec('a', '底数', LcArgKind.expr, valueType: LcType.number), LcArgSpec('b', '几次方', LcArgKind.expr, valueType: LcType.number)], hint: '算不出有限的数时当 0'),
  'random': LcExprSpec('random', '随机整数', '运算', [
    LcArgSpec('a', '最小', LcArgKind.expr, valueType: LcType.number),
    LcArgSpec('b', '最大', LcArgKind.expr, valueType: LcType.number),
  ], hint: '含两头，每次算出来可能不一样'),
  'logic': LcExprSpec('logic', '并且 / 或者', '运算', [
    LcArgSpec('l', '左边', LcArgKind.expr, valueType: LcType.boolean),
    LcArgSpec('op', '关系', LcArgKind.choice, choices: ['and', 'or'], choiceLabels: ['并且', '或者']),
    LcArgSpec('r', '右边', LcArgKind.expr, valueType: LcType.boolean),
  ], hint: '左边已经能定结果时，右边就不算了'),
  'cond': LcExprSpec('cond', '看条件挑一个值', '运算', [_cond, LcArgSpec('then', '成立时', LcArgKind.expr), LcArgSpec('orElse', '不成立时', LcArgKind.expr)], hint: '条件成立是前一个值，不成立是后一个值；没挑中的那个不会算'),
  'null': LcExprSpec('null', '空值', '运算', [], hint: '“什么都没有”这个值'),
  'isType': LcExprSpec('isType', '是不是某种类型', '运算', [
    LcArgSpec('x', '值', LcArgKind.expr),
    LcArgSpec('type', '类型', LcArgKind.choice, choices: kBeTypeNames, choiceLabels: _typeLabels),
  ], hint: '这个值是不是数字 / 文字 / 列表…'),
  'convert': LcExprSpec('convert', '转换类型', '运算', [
    LcArgSpec('x', '值', LcArgKind.expr),
    LcArgSpec('fn', '变成', LcArgKind.choice, choices: ['toNumber', 'toText', 'toBool'], choiceLabels: ['数字', '文字', '是 / 否']),
  ], hint: '转不成数字的当 0；空、0、空文字算“否”'),
  'copy': LcExprSpec('copy', '复制一份', '运算', [LcArgSpec('x', '值', LcArgKind.expr)], hint: '列表 / 字典连里面的一起复制，改复制品不影响原来的'),
  // —— 文字 ——
  'charAt': LcExprSpec('charAt', '第几个字', '文字', [LcArgSpec('s', '文字', LcArgKind.expr, valueType: LcType.text), LcArgSpec('i', '位置', LcArgKind.expr, valueType: LcType.number)], hint: '位置从 0 数；没有就是空'),
  'substring': LcExprSpec('substring', '截一段文字', '文字', [
    LcArgSpec('s', '文字', LcArgKind.expr, valueType: LcType.text),
    LcArgSpec('from', '从', LcArgKind.expr, valueType: LcType.number),
    LcArgSpec('to', '到', LcArgKind.expr, valueType: LcType.number),
  ], hint: '位置从 0 数，不含“到”的那个字'),
  'indexOf': LcExprSpec('indexOf', '在文字里的位置', '文字', [
    LcArgSpec('sub', '找什么', LcArgKind.expr, valueType: LcType.text),
    LcArgSpec('s', '文字', LcArgKind.expr, valueType: LcType.text),
  ], hint: '第一次出现的位置（从 0 数）；找不到是 -1'),
  'textHas': LcExprSpec('textHas', '文字里有没有', '文字', [
    LcArgSpec('s', '文字', LcArgKind.expr, valueType: LcType.text),
    LcArgSpec('fn', '怎么比', LcArgKind.choice, choices: ['contains', 'startsWith', 'endsWith'], choiceLabels: ['里面有', '开头是', '结尾是']),
    LcArgSpec('sub', '什么', LcArgKind.expr, valueType: LcType.text),
  ], hint: '里面有 / 开头是 / 结尾是'),
  'replace': LcExprSpec('replace', '替换文字', '文字', [
    LcArgSpec('s', '文字', LcArgKind.expr, valueType: LcType.text),
    LcArgSpec('from', '把', LcArgKind.expr, valueType: LcType.text),
    LcArgSpec('to', '换成', LcArgKind.expr, valueType: LcType.text),
  ], hint: '所有出现的地方都换'),
  'textCase': LcExprSpec('textCase', '去空白 / 转大小写', '文字', [
    LcArgSpec('s', '文字', LcArgKind.expr, valueType: LcType.text),
    LcArgSpec('fn', '怎么变', LcArgKind.choice, choices: ['trim', 'upper', 'lower'], choiceLabels: ['去掉两头的空白', '转成大写', '转成小写']),
  ], hint: '大小写只管英文字母'),
  'repeatText': LcExprSpec('repeatText', '文字重复几遍', '文字', [
    LcArgSpec('s', '文字', LcArgKind.expr, valueType: LcType.text),
    LcArgSpec('n', '几遍', LcArgKind.expr, valueType: LcType.number),
  ], hint: '最多 10000 遍'),
  'split': LcExprSpec('split', '把文字切开', '文字', [
    LcArgSpec('s', '文字', LcArgKind.expr, valueType: LcType.text),
    LcArgSpec('sep', '按什么切', LcArgKind.expr, valueType: LcType.text),
  ], hint: '得到一个列表；按空文字切＝一个字一项'),
  'template': LcExprSpec('template', '填模板', '文字', [LcArgSpec('s', '模板', LcArgKind.expr, valueType: LcType.text), LcArgSpec('dict', '字典', LcArgKind.expr)], hint: '把模板里的 {键} 换成字典里那个键的值；字典里没有的原样留着'),
  'toJson': LcExprSpec('toJson', '写成 JSON 文字', '文字', [LcArgSpec('x', '值', LcArgKind.expr)], hint: '键按顺序排、不加空格'),
  'fromJson': LcExprSpec('fromJson', '读 JSON 文字', '文字', [LcArgSpec('s', 'JSON 文字', LcArgKind.expr, valueType: LcType.text)], hint: '不是合法的 JSON 就是空'),
  // —— 列表 ——
  'listLit': LcExprSpec('listLit', '列表', '列表', [LcArgSpec('items', '每一项', LcArgKind.exprList)], hint: '把几个值排成一个列表；一项都没有就是空列表'),
  'range': LcExprSpec('range', '一串数', '列表', [
    LcArgSpec('a', '从', LcArgKind.expr, valueType: LcType.number),
    LcArgSpec('b', '到', LcArgKind.expr, valueType: LcType.number),
    LcArgSpec('step', '每次加', LcArgKind.expr, valueType: LcType.number),
  ], hint: '含两头的数列，最多 10000 项'),
  'index': LcExprSpec('index', '取某一项 / 某个键', '列表', [LcArgSpec('of', '列表或字典', LcArgKind.expr), LcArgSpec('key', '位置或键', LcArgKind.expr)], hint: '列表填位置（从 0 数），字典填键；没有就是空'),
  'listGet': LcExprSpec('listGet', '列表的第几项', '列表', [LcArgSpec('xs', '列表', LcArgKind.expr), LcArgSpec('i', '位置', LcArgKind.expr, valueType: LcType.number)], hint: '位置从 0 数；没有就是空'),
  'listPop': LcExprSpec('listPop', '取走最后一项', '列表', [LcArgSpec('xs', '列表', LcArgKind.expr)], hint: '列表会少一项；列表是空的就得到空'),
  'listContains': LcExprSpec('listContains', '列表里有没有', '列表', [LcArgSpec('xs', '列表', LcArgKind.expr), LcArgSpec('v', '找什么', LcArgKind.expr)], hint: '有一项和它相等就是“是”'),
  'listIndexOf': LcExprSpec('listIndexOf', '在列表里的位置', '列表', [LcArgSpec('v', '找什么', LcArgKind.expr), LcArgSpec('xs', '列表', LcArgKind.expr)], hint: '第一个相等的项的位置（从 0 数）；没有是 -1'),
  'listSlice': LcExprSpec('listSlice', '截一段列表', '列表', [
    LcArgSpec('xs', '列表', LcArgKind.expr),
    LcArgSpec('from', '从', LcArgKind.expr, valueType: LcType.number),
    LcArgSpec('to', '到', LcArgKind.expr, valueType: LcType.number),
  ], hint: '一个新列表；位置从 0 数，不含“到”的那一项'),
  'listConcat': LcExprSpec('listConcat', '两个列表接起来', '列表', [LcArgSpec('a', '前面的', LcArgKind.expr), LcArgSpec('b', '后面的', LcArgKind.expr)], hint: '一个新列表，原来的两个不变'),
  'listOrder': LcExprSpec('listOrder', '倒过来 / 排序', '列表', [
    LcArgSpec('xs', '列表', LcArgKind.expr),
    LcArgSpec('fn', '怎么排', LcArgKind.choice, choices: ['listReverse', 'listSort'], choiceLabels: ['倒过来', '从小到大排']),
  ], hint: '一个新列表，原来的不变；排序时数字在前、文字在后'),
  'listJoin': LcExprSpec('listJoin', '把列表连成文字', '列表', [LcArgSpec('xs', '列表', LcArgKind.expr), LcArgSpec('sep', '中间隔着', LcArgKind.expr, valueType: LcType.text)], hint: '每一项变成文字，中间用隔的东西连起来'),
  // —— 字典 ——
  'dictGet': LcExprSpec('dictGet', '字典里某个键的值', '对象', [LcArgSpec('d', '字典', LcArgKind.expr), LcArgSpec('k', '键', LcArgKind.expr)], hint: '键可以是算出来的；没有就是空'),
  'dictHas': LcExprSpec('dictHas', '字典里有没有这个键', '对象', [LcArgSpec('d', '字典', LcArgKind.expr), LcArgSpec('k', '键', LcArgKind.expr)], hint: '键在不在字典里（值是空也算在）'),
  'dictPart': LcExprSpec('dictPart', '所有的键 / 值', '对象', [
    LcArgSpec('d', '字典', LcArgKind.expr),
    LcArgSpec('fn', '要什么', LcArgKind.choice, choices: ['dictKeys', 'dictValues', 'dictPairs'], choiceLabels: ['所有的键', '所有的值', '所有的键值对']),
  ], hint: '一个列表，按键从小到大；键值对是 [键, 值]'),
  'dictMerge': LcExprSpec('dictMerge', '两个字典合起来', '对象', [LcArgSpec('a', '原来的', LcArgKind.expr), LcArgSpec('b', '盖上去的', LcArgKind.expr)], hint: '一个新字典；两边都有的键用后面那个的'),
};

/// 新加的表达式里一定是“是 / 否”的。`convert` 要看选的是哪一种，见 backend_blocks.dart 的 `beExprIsBool`。
const Set<String> kBeLangBoolKinds = {'logic', 'isType', 'textHas', 'listContains', 'dictHas'};

/// 新加的表达式算出来一定是什么类型（说不准的不在表里）。带 `fn` 的看选了哪一种。
String beLangExprType(Object? expr) {
  final kind = exprKind(expr);
  if (kBeLangBoolKinds.contains(kind)) return LcType.boolean;
  switch (kind) {
    case 'neg' || 'round' || 'math' || 'minmax' || 'pow' || 'random' || 'indexOf' || 'listIndexOf':
      return LcType.number;
    case 'substring' || 'replace' || 'textCase' || 'repeatText' || 'template' || 'toJson' || 'listJoin':
      return LcType.text;
    case 'convert':
      return switch (exprString(expr, 'fn')) {
        'toNumber' => LcType.number,
        'toText' => LcType.text,
        'toBool' => LcType.boolean,
        _ => LcType.any,
      };
    default:
      return LcType.any;
  }
}

// —— 新建时的默认值 ——

Map<String, dynamic> _e(String kind, [Map<String, dynamic> args = const {}]) => {'e': kind, ...args};

/// 新建一个新加的表达式；不是这张表里的返回 null。[firstVar] 是文档里第一个变量的名字（没有就是空文字）。
Map<String, dynamic>? newBeLangExpr(String kind, String firstVar) {
  final v = exVar(firstVar);
  return switch (kind) {
    'neg' => _e(kind, {'x': exNum(1)}),
    'round' => _e(kind, {'x': exNum(2.5), 'fn': 'round'}),
    'math' => _e(kind, {'x': exNum(-1), 'fn': 'abs'}),
    'minmax' => _e(kind, {'a': exNum(1), 'b': exNum(2), 'fn': 'max'}),
    'pow' => _e(kind, {'a': exNum(2), 'b': exNum(3)}),
    'random' => _e(kind, {'a': exNum(1), 'b': exNum(6)}),
    'logic' => _e(kind, {'l': exBool(true), 'op': 'and', 'r': exBool(true)}),
    'cond' => _e(kind, {'cond': exBool(true), 'then': exText('是'), 'orElse': exText('否')}),
    'null' => _e(kind),
    'isType' => _e(kind, {'x': v, 'type': 'number'}),
    'convert' => _e(kind, {'x': exText('12'), 'fn': 'toNumber'}),
    'copy' => _e(kind, {'x': v}),
    'charAt' => _e(kind, {'s': exText('你好'), 'i': exNum(0)}),
    'substring' => _e(kind, {'s': exText('你好世界'), 'from': exNum(0), 'to': exNum(2)}),
    'indexOf' => _e(kind, {'sub': exText('好'), 's': exText('你好')}),
    'textHas' => _e(kind, {'s': exText('你好'), 'fn': 'contains', 'sub': exText('好')}),
    'replace' => _e(kind, {'s': exText('你好'), 'from': exText('你'), 'to': exText('大家')}),
    'textCase' => _e(kind, {'s': exText(' abc '), 'fn': 'trim'}),
    'repeatText' => _e(kind, {'s': exText('哈'), 'n': exNum(3)}),
    'split' => _e(kind, {'s': exText('a,b,c'), 'sep': exText(',')}),
    'template' => _e(kind, {'s': exText('你好，{name}'), 'dict': v}),
    'toJson' => _e(kind, {'x': v}),
    'fromJson' => _e(kind, {'s': exText('{"a":1}')}),
    'listLit' => _e(kind, {
      'items': [exNum(1), exNum(2), exNum(3)],
    }),
    'range' => _e(kind, {'a': exNum(1), 'b': exNum(5), 'step': exNum(1)}),
    'index' => _e(kind, {'of': v, 'key': exNum(0)}),
    'listGet' => _e(kind, {'xs': v, 'i': exNum(0)}),
    'listPop' => _e(kind, {'xs': v}),
    'listContains' => _e(kind, {'xs': v, 'v': exText('')}),
    'listIndexOf' => _e(kind, {'v': exText(''), 'xs': v}),
    'listSlice' => _e(kind, {'xs': v, 'from': exNum(0), 'to': exNum(2)}),
    'listConcat' => _e(kind, {
      'a': v,
      'b': _e('listLit', {'items': <dynamic>[]}),
    }),
    'listOrder' => _e(kind, {'xs': v, 'fn': 'listReverse'}),
    'listJoin' => _e(kind, {'xs': v, 'sep': exText('、')}),
    'dictGet' => _e(kind, {'d': v, 'k': exText('name')}),
    'dictHas' => _e(kind, {'d': v, 'k': exText('name')}),
    'dictPart' => _e(kind, {'d': v, 'fn': 'dictKeys'}),
    'dictMerge' => _e(kind, {'a': v, 'b': v}),
    _ => null,
  };
}

/// 新建一块新加的积木；不是这张表里的返回 null。
LcBlock? newBeLangBlock(String op, String firstVar) {
  final v = exVar(firstVar);
  return switch (op) {
    'let' => LcBlock(op: op, args: {'name': 'x', 'value': exNum(0)}),
    'const' => LcBlock(op: op, args: {'name': 'MAX', 'value': exNum(10)}),
    'do' => LcBlock(
      op: op,
      args: {
        'value': _e('listPop', {'xs': v}),
      },
    ),
    'switch' => LcBlock(
      op: op,
      args: {'value': v},
      arms: [
        LcArm(args: {'value': exNum(1)}),
      ],
    ),
    'while' => LcBlock(op: op, args: {'cond': exBin('<', v, exNum(10))}),
    'forever' || 'break' || 'continue' => LcBlock(op: op),
    'forCount' => LcBlock(op: op, args: {'name': 'i', 'from': exNum(1), 'to': exNum(10), 'step': exNum(1)}),
    'forPairs' => LcBlock(op: op, args: {'dict': v, 'key': 'key', 'value': 'value'}),
    'note' => LcBlock(op: op, args: {'text': '这里是做什么的'}),
    'listPush' => LcBlock(op: op, args: {'xs': v, 'v': exText('')}),
    'listInsert' => LcBlock(op: op, args: {'xs': v, 'i': exNum(0), 'v': exText('')}),
    'listSet' => LcBlock(op: op, args: {'xs': v, 'i': exNum(0), 'v': exText('')}),
    'listRemove' => LcBlock(op: op, args: {'xs': v, 'i': exNum(0)}),
    'setItem' => LcBlock(op: op, args: {'of': v, 'key': exNum(0), 'value': exText('')}),
    'dictSet' => LcBlock(op: op, args: {'d': v, 'k': exText('name'), 'v': exText('')}),
    'dictRemove' => LcBlock(op: op, args: {'d': v, 'k': exText('name')}),
    _ => null,
  };
}

// —— 这个接口用没用到新东西 ——

bool _exprUsesLang(Object? value, int depth) {
  if (depth > kMaxExprDepth * 2) return false;
  if (value is List) return value.any((v) => _exprUsesLang(v, depth + 1));
  if (value is! Map) return false;
  final kind = value['e'];
  if (kind is String && (beLangExprSpecs.containsKey(kind) || beFuncExprSpecs.containsKey(kind) || beStrictExprSpecs.containsKey(kind) || beIsCoreExpr(kind) || beCallId(kind) != null)) return true;
  return value.values.any((v) => _exprUsesLang(v, depth + 1));
}

/// 这一串积木里有没有第 4 版才有的东西：新积木、新表达式、“否则如果”段、收起来的“否则”、带序号的“对每一项”、乘方。
/// 有＝这个接口整个走新路（backend_lower_lang.dart），存盘时文档版本升到 2；没有＝和以前一模一样。
bool beBlocksUseLang(List<LcBlock> list, [int depth = 0]) {
  if (depth > LcBlock.maxDepth + 1) return false;
  for (final b in list) {
    if (beLangBlockSpecs.containsKey(b.op) || b.arms.isNotEmpty || b.noElse) return true;
    if (beFuncBlockSpecs.containsKey(b.op) || beIsCoreOp(b.op) || beCallId(b.op) != null) return true;
    final index = b.args['index'];
    if (b.op == 'forEach' && index is String && index.isNotEmpty) return true;
    if (b.args.values.any((v) => _exprUsesLang(v, 0))) return true;
    if (beBlocksUseLang(b.body, depth + 1) || beBlocksUseLang(b.orElse, depth + 1)) return true;
  }
  return false;
}

/// 这一串积木里新建了哪些名字（新建变量 / 常量、各种循环自己的变量），按出现的顺序、不重复。名字不合规矩的不算。
/// 值是 true＝常量。读 / 写变量的下拉、校验、翻译都靠它知道“这个接口里还有哪些名字”。
Map<String, bool> beLocalNames(List<LcBlock> list, RegExp pattern) {
  final out = <String, bool>{};
  void add(Object? name, [bool isConst = false]) {
    if (name is String && pattern.hasMatch(name)) out.putIfAbsent(name, () => isConst);
  }

  void walk(List<LcBlock> blocks, int depth) {
    if (depth > LcBlock.maxDepth + 1) return;
    for (final b in blocks) {
      switch (b.op) {
        case 'let':
          add(b.args['name']);
        case 'const':
          add(b.args['name'], true);
        case 'forCount':
          add(b.args['name']);
        case 'spawn':
          // 核心 3：“开始做”记成的名字（一个“稍后的结果”）。
          add(b.args['name'], true);
        case 'forEach':
          add(b.args['index']);
        case kBeForIn:
          add(b.args['name']);
          add(b.args['index']);
        case kBeRawStmt:
          beRawDeclares(b.args['src']).forEach(add);
        case 'forPairs':
          add(b.args['key']);
          add(b.args['value']);
      }
      walk(b.body, depth + 1);
      for (final a in b.arms) {
        // 核心 2：“出错时”接到的错误、“看是哪种情况”带出来的东西。
        if (b.op == 'try') add(a.args['name'], true);
        if (b.op == 'match') beBindNames(a.args['binds']).forEach((n) => add(n, true));
        walk(a.body, depth + 1);
      }
      walk(b.orElse, depth + 1);
      // “带口的值”（匿名函数）口里新建的名字也算：那里面的积木读它时才认得。
      for (final m in b.exprMouths) {
        walk(m, depth + 1);
      }
    }
  }

  walk(list, 0);
  return out;
}
