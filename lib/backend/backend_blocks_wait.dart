/// 核心 3 的积木目录（积木第 5 版·核心 3）：“要等的事”——开始做、等、最多等、等全部、等最先的一个、取消、一次只让一个做、等一会儿。
///
/// 和核心 2 的积木一样只在规矩版本 2 的文档里出现，并在 backend_blocks_core.dart 的那几张表里（积木盒、校验、编辑都走同一条路）。
/// 积木上**没有“要等”这回事**：哪个函数要等是检查器自己推的（lib/lang/typecheck_wait.dart），放错地方在类型问题里说。
/// 怎么翻成语法树在 backend_lower_wait.dart。
library;

import 'package:lopicode/lowcode/logic_blocks.dart';
import 'package:lopicode/lowcode/logic_model.dart';

const String kBeCatWait = '要等的事';

const LcArgSpec _task = LcArgSpec('x', '哪件事', LcArgKind.expr);
const LcArgSpec _list = LcArgSpec('list', '哪些事', LcArgKind.expr);
const LcArgSpec _ms = LcArgSpec('ms', '毫秒', LcArgKind.expr, valueType: LcType.number);

const Map<String, LcBlockSpec> beWaitBlockSpecs = {
  'spawn': LcBlockSpec('spawn', '开始做', kBeCatWait, [LcArgSpec('name', '记成', LcArgKind.literalText, optional: true)], bodyLabel: '同时做', hint: '里面的积木马上开始做，不等它做完就接着往下；起个名字以后可以“等”它、“取消”它。里面的“返回”只结束这件事'),
  'sleep': LcBlockSpec('sleep', '等一会儿', kBeCatWait, [_ms], hint: '停这么多毫秒再接着做（1000 毫秒＝1 秒）'),
  'cancel': LcBlockSpec('cancel', '取消', kBeCatWait, [_task], hint: '让那件事到它下一个要等的地方就停；等它的人会拿到“取消了”这种错误。已经做完的不受影响'),
  'critical': LcBlockSpec(
    'critical',
    '一次只让一个做',
    kBeCatWait,
    [LcArgSpec('name', '名字', LcArgKind.expr, valueType: LcType.text)],
    bodyLabel: '里面',
    hint: '名字一样的几段，同时只有一件事在里面，别的排队。不能在里面再进同一个名字',
  ),
};

const Map<String, LcExprSpec> beWaitExprSpecs = {
  'spawnOf': LcExprSpec('spawnOf', '开始算', kBeCatWait, [LcArgSpec('x', '算什么', LcArgKind.expr)], hint: '马上开始算，不等它算完；得到一个“稍后的结果”，放进常量里以后再“等”'),
  'await': LcExprSpec('await', '等', kBeCatWait, [_task], hint: '等那件事做完，拿它的结果；它出了错，错在这里抛出来'),
  'awaitMax': LcExprSpec('awaitMax', '等，最多', kBeCatWait, [_task, _ms], hint: '到时候还没做完就出“超时”错误（那件事自己接着做）'),
  'awaitAll': LcExprSpec('awaitAll', '等全部', kBeCatWait, [_list], hint: '全做完才往下，结果按列表的顺序排；有一件出错，别的还没做完的被取消'),
  'awaitAny': LcExprSpec('awaitAny', '等最先的一个', kBeCatWait, [_list], hint: '谁先做完用谁的结果，别的接着做'),
  'cancelled': LcExprSpec('cancelled', '被取消了吗', kBeCatWait, [], hint: '正在做的这件事有没有被取消'),
};

const Map<String, String> beWaitBlockSentences = {'spawn': '开始做，记成 {name}', 'sleep': '等 {ms} 毫秒', 'cancel': '取消 {x}', 'critical': '一次只让一个做 {name}'};

const Map<String, String> beWaitExprSentences = {'spawnOf': '开始算 {x}', 'await': '等 {x}', 'awaitMax': '等 {x} 最多 {ms} 毫秒', 'awaitAll': '等全部 {list}', 'awaitAny': '等最先的一个 {list}', 'cancelled': '被取消了吗'};

/// 积木盒里拖出来的新的一块值；不是这里的返回 null。
Map<String, dynamic>? newBeWaitExpr(String kind) => switch (kind) {
  'spawnOf' || 'await' => {'e': kind, 'x': null},
  'awaitMax' => {'e': kind, 'x': null, 'ms': exNum(1000)},
  'awaitAll' || 'awaitAny' => {
    'e': kind,
    'list': {'e': 'listLit', 'items': <dynamic>[]},
  },
  'cancelled' => {'e': kind},
  _ => null,
};

/// 积木盒里拖出来的新的一块语句；不是这里的返回 null。
LcBlock? newBeWaitBlock(String op) => switch (op) {
  'spawn' => LcBlock(op: op, args: {'name': ''}),
  'sleep' => LcBlock(op: op, args: {'ms': exNum(1000)}),
  'cancel' => LcBlock(op: op, args: {'x': null}),
  'critical' => LcBlock(op: op, args: {'name': exText('账户')}),
  _ => null,
};

/// 读成人话；不是这里的返回 null。
String? describeBeWaitExpr(Object? expr, String Function(String key) sub) => switch (expr is Map ? expr['e'] : null) {
  'spawnOf' => '开始算 ${sub('x')}',
  'await' => '等 ${sub('x')}',
  'awaitMax' => '等 ${sub('x')}，最多 ${sub('ms')} 毫秒',
  'awaitAll' => '等全部 ${sub('list')}',
  'awaitAny' => '等最先的一个 ${sub('list')}',
  'cancelled' => '被取消了吗',
  _ => null,
};

String? describeBeWaitBlock(LcBlock b, String Function(String name) arg) => switch (b.op) {
  'spawn' => '开始做…${b.args['name'] is String && (b.args['name'] as String).isNotEmpty ? '（记成 ${b.args['name']}）' : ''}',
  'sleep' => '等 ${arg('ms')} 毫秒',
  'cancel' => '取消 ${arg('x')}',
  'critical' => '一次只让一个做 ${arg('name')}',
  _ => null,
};
