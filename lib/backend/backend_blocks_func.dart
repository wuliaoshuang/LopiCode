/// 后端积木目录里“函数”的那一半（积木第 4 版·第 2 阶段）：返回、调用放在变量里的函数、匿名函数（带口的值和短写法）、
/// “这个函数本身”、读参数，和 8 个拿函数当参数的列表操作。
///
/// op / e 的名字照 docs/blocks-v4-language-design.md“实施记录·阶段 2·语言核心”的对照表。
/// 调用自定义积木（`call:<id>`）的规格不在这张表里：它跟着每个文档里的定义走，见 backend_func_table.dart。
/// 怎么翻成语法树见 backend_lower_func.dart；这张表和 backend_blocks.dart 的合在一起才是全部内置积木。
library;

import 'package:lopicode/backend/backend_function.dart';
import 'package:lopicode/lowcode/logic_blocks.dart';
import 'package:lopicode/lowcode/logic_model.dart';

const LcArgSpec _xs = LcArgSpec('xs', '列表', LcArgKind.expr);
const LcArgSpec _fn = LcArgSpec('fn', '函数', LcArgKind.expr);

/// 第 2 阶段新加的积木（语句）。键是 op。
const Map<String, LcBlockSpec> beFuncBlockSpecs = {
  'return': LcBlockSpec('return', '返回', '函数', [LcArgSpec('value', '值', LcArgKind.expr)], hint: '结束这个函数，把一个值交回给调用它的地方'),
  'returnNothing': LcBlockSpec('returnNothing', '直接结束', '函数', [], hint: '不带值地结束这个函数，后面的积木不做了'),
  'callValueStmt': LcBlockSpec('callValueStmt', '调用函数', '函数', [_fn, LcArgSpec('args', '带上', LcArgKind.exprList)], hint: '调用一个放在变量 / 参数里的函数，结果不要'),
  'listEach': LcBlockSpec('listEach', '每一项都做一下', '列表', [_xs, _fn], hint: '把列表的每一项依次交给函数；函数收一个参数（这一项）'),
};

/// 第 2 阶段新加的表达式。键是 e。
const Map<String, LcExprSpec> beFuncExprSpecs = {
  // 读一个参数。名字在目录里是直接填的文字；编辑器里是下拉（这一串里看得见的参数），见 backend_func_host.dart。
  'param': LcExprSpec('param', '参数', '函数', [LcArgSpec('name', '参数', LcArgKind.literalText)], hint: '读一个参数的值；从帽子 / 匿名函数上把参数小块拖出来就是它'),
  'lambda': LcExprSpec('lambda', '匿名函数', '函数', [], paramsArg: 'params', hasMouth: true, hint: '一个没有名字的函数，里面放积木；能读、能改外面的变量'),
  'lambdaExpr': LcExprSpec('lambdaExpr', '短函数', '函数', [LcArgSpec('body', '结果', LcArgKind.expr)], paramsArg: 'params', hint: '只有一个式子的函数：收到参数，算出箭头后面的值'),
  // 哪个函数：存的是函数的 id。目录里是直接填的文字；编辑器里是下拉。
  'funcRef': LcExprSpec('funcRef', '函数本身', '函数', [LcArgSpec('fn', '哪个', LcArgKind.literalText)], hint: '把“我的积木”当成一个值交出去（不调用它）'),
  'callValue': LcExprSpec('callValue', '调用函数的结果', '函数', [_fn, LcArgSpec('args', '带上', LcArgKind.exprList)], hint: '调用一个放在变量 / 参数里的函数，得到它返回的值'),
  'listMap': LcExprSpec('listMap', '每一项变一下', '列表', [_xs, _fn], hint: '一个新列表：每一项换成函数算出来的值'),
  'listFilter': LcExprSpec('listFilter', '挑出符合的', '列表', [_xs, _fn], hint: '一个新列表：只留函数说“是”的那些项'),
  'listReduce': LcExprSpec('listReduce', '累起来', '列表', [_xs, _fn, LcArgSpec('init', '从', LcArgKind.expr)], hint: '从一个起始值开始，把每一项依次累进去；函数收两个参数（累到现在的、这一项）'),
  'listFind': LcExprSpec('listFind', '找第一个符合的', '列表', [_xs, _fn], hint: '第一个让函数说“是”的项；没有就是空'),
  'listEvery': LcExprSpec('listEvery', '是不是每一项都符合', '列表', [_xs, _fn], hint: '每一项函数都说“是”才是“是”；空列表算“是”'),
  'listSome': LcExprSpec('listSome', '有没有一项符合', '列表', [_xs, _fn], hint: '只要有一项函数说“是”就是“是”'),
  'listSortBy': LcExprSpec('listSortBy', '按算出来的分排序', '列表', [_xs, _fn], hint: '一个新列表：函数给每一项打个分，按分从小到大排（分一样的保持原来的先后）'),
};

/// 新积木上的话。
const Map<String, String> beFuncBlockSentences = {'return': '返回 {value}', 'returnNothing': '直接结束', 'callValueStmt': '调用 {fn} 带上 {args}', 'listEach': '把 {xs} 的每一项交给 {fn}'};

const Map<String, String> beFuncExprSentences = {
  'param': '{name}',
  'lambda': '函数 {@params}',
  'lambdaExpr': '{@params} → {body}',
  'funcRef': '{fn} 这块积木本身',
  'callValue': '调用 {fn} 带上 {args} 的结果',
  'listMap': '{xs} 每一项变成 {fn}',
  'listFilter': '{xs} 里符合 {fn} 的',
  'listReduce': '{xs} 从 {init} 起用 {fn} 累起来',
  'listFind': '{xs} 里第一个符合 {fn} 的',
  'listEvery': '{xs} 每一项都符合 {fn}',
  'listSome': '{xs} 有一项符合 {fn}',
  'listSortBy': '{xs} 按 {fn} 算的分排序',
};

/// 一定是“是 / 否”的。
const Set<String> kBeFuncBoolKinds = {'listEvery', 'listSome'};

/// 搜索用的别名。
const Map<String, List<String>> beFuncAliases = {
  'block:return': ['返回值', '结果', 'return'],
  'block:returnNothing': ['结束', '退出', '返回', 'return'],
  'block:callValueStmt': ['调用', '执行', '运行', 'call', 'apply'],
  'block:listEach': ['循环', '遍历', '每一项', 'forEach', 'each'],
  'expr:param': ['参数', '形参', 'argument', 'param'],
  'expr:lambda': ['函数', '回调', '闭包', 'lambda', 'function', 'callback'],
  'expr:lambdaExpr': ['函数', '箭头', '回调', 'lambda', '=>', 'arrow'],
  'expr:funcRef': ['函数', '引用', '当值', 'reference'],
  'expr:callValue': ['调用', '执行', '运行', 'call', 'apply'],
  'expr:listMap': ['数组', '映射', '转换', '变换', 'map'],
  'expr:listFilter': ['数组', '筛选', '过滤', 'filter', 'where'],
  'expr:listReduce': ['数组', '累加', '求和', '汇总', '折叠', 'reduce', 'fold', 'sum'],
  'expr:listFind': ['数组', '查找', '找', 'find', 'first'],
  'expr:listEvery': ['数组', '全部', '都', 'every', 'all'],
  'expr:listSome': ['数组', '任意', '有没有', 'some', 'any'],
  'expr:listSortBy': ['数组', '排序', 'sort', 'sortBy', 'orderBy'],
};

// —— 新建时的默认值 ——

Map<String, dynamic> beParam(String name) => {'e': 'param', 'name': name};

/// 带口的匿名函数：`函数 (x) { 积木… }`。
Map<String, dynamic> beLambda(List<String> params, [List<LcBlock> body = const []]) => {
  'e': 'lambda',
  'params': [...params],
  kLcExprBody: [...body],
};

/// 短写法：`(x) → 式子`。
Map<String, dynamic> beLambdaExpr(List<String> params, Object? body) => {
  'e': 'lambdaExpr',
  'params': [...params],
  'body': body,
};

Map<String, dynamic> _list([List<Object?> items = const []]) => {
  'e': 'listLit',
  'items': [...items],
};

/// 新建一个第 2 阶段的表达式；不是这张表里的返回 null。[firstVar] 是文档里第一个变量的名字，[firstFn] 是第一个函数的 id。
Map<String, dynamic>? newBeFuncExpr(String kind, String firstVar, String firstFn) {
  final v = exVar(firstVar);
  Map<String, dynamic> x() => beParam('x');
  return switch (kind) {
    'param' => x(),
    'lambda' => beLambda(const ['x']),
    'lambdaExpr' => beLambdaExpr(const ['x'], x()),
    'funcRef' => {'e': kind, 'fn': firstFn},
    'callValue' => {'e': kind, 'fn': v, 'args': <dynamic>[]},
    'listMap' => {
      'e': kind,
      'xs': v,
      'fn': beLambdaExpr(const ['x'], exBin('*', x(), exNum(2))),
    },
    'listFilter' || 'listFind' || 'listEvery' || 'listSome' => {
      'e': kind,
      'xs': v,
      'fn': beLambdaExpr(const ['x'], exBin('>', x(), exNum(0))),
    },
    'listReduce' => {
      'e': kind,
      'xs': v,
      'fn': beLambdaExpr(const ['sum', 'x'], exBin('+', beParam('sum'), x())),
      'init': exNum(0),
    },
    'listSortBy' => {
      'e': kind,
      'xs': v,
      'fn': beLambdaExpr(const ['x'], x()),
    },
    _ => null,
  };
}

/// 新建一块第 2 阶段的积木；不是这张表里的返回 null。
LcBlock? newBeFuncBlock(String op, String firstVar) {
  final v = exVar(firstVar);
  return switch (op) {
    'return' => LcBlock(op: op, args: {'value': exText('')}),
    'returnNothing' => LcBlock(op: op),
    'callValueStmt' => LcBlock(op: op, args: {'fn': v, 'args': <dynamic>[]}),
    'listEach' => LcBlock(
      op: op,
      args: {
        'xs': v,
        'fn': beLambda(const ['x']),
      },
    ),
    _ => null,
  };
}

/// “剩下的全收”的槽里先放什么：一个空列表（往里加几项，调用时就多带几个值）。
Map<String, dynamic> beRestSlotValue() => _list();

// —— 这一串用没用到第 2 阶段的东西 ——

bool _exprUsesFunc(Object? value, int depth) {
  if (depth > kMaxExprDepth * 2 || value is List<LcBlock>) return false;
  if (value is List) return value.any((v) => _exprUsesFunc(v, depth + 1));
  if (value is! Map) return false;
  final kind = value['e'];
  if (kind is String && (beFuncExprSpecs.containsKey(kind) || beCallId(kind) != null)) return true;
  return value.values.any((v) => _exprUsesFunc(v, depth + 1));
}

/// 这一串积木里有没有第 2 阶段才有的东西：调用自定义积木、返回、匿名函数、拿函数当参数的列表操作……
/// 有＝这个接口整个走语言核心那条路，存盘时文档版本升到 3。
bool beBlocksUseFunc(List<LcBlock> list, [int depth = 0]) {
  if (depth > LcBlock.maxDepth + 1) return false;
  for (final b in list) {
    if (beFuncBlockSpecs.containsKey(b.op) || beCallId(b.op) != null) return true;
    if (b.args.values.any((v) => _exprUsesFunc(v, 0))) return true;
    if (b.arms.any((a) => a.args.values.any((v) => _exprUsesFunc(v, 0)) || beBlocksUseFunc(a.body, depth + 1))) return true;
    if (beBlocksUseFunc(b.body, depth + 1) || beBlocksUseFunc(b.orElse, depth + 1)) return true;
  }
  return false;
}

/// 走一遍一块积木的参数（含各段的）里所有的表达式，从外到里；`visit` 拿到的是可以原地改的对象。不进“带口的值”口里的积木。
void beVisitExprs(LcBlock b, void Function(Map<String, dynamic> expr) visit) {
  void walk(Object? v, int depth) {
    if (depth > kMaxExprDepth * 2 + 4 || v is List<LcBlock>) return;
    if (v is List) {
      for (final x in v) {
        walk(x, depth + 1);
      }
    } else if (v is Map<String, dynamic>) {
      if (v['e'] is String) visit(v);
      for (final x in v.values.toList()) {
        walk(x, depth + 1);
      }
    }
  }

  walk(b.args, 0);
  for (final a in b.arms) {
    walk(a.args, 0);
  }
}

/// 从外到里走一遍一串积木（含各个口、“带口的值”的口）。
void beVisitBlocks(List<LcBlock> list, void Function(LcBlock b) visit, [int depth = 0]) {
  if (depth > LcBlock.maxDepth + 2) return;
  for (final b in list) {
    visit(b);
    beVisitBlocks(b.body, visit, depth + 1);
    for (final a in b.arms) {
      beVisitBlocks(a.body, visit, depth + 1);
    }
    beVisitBlocks(b.orElse, visit, depth + 1);
    for (final m in b.exprMouths) {
      beVisitBlocks(m, visit, depth + 1);
    }
  }
}
