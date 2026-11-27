/// 核心 3 的积木（“要等的事”，目录在 backend_blocks_wait.dart）怎么翻成语法树。
/// 不加语法树节点：除了“开始做”“等”，别的都是小库函数（lib/lang/rt_v2.dart 的 `kLangRtV2Tasks`）；
/// “一次只让一个做”翻成“进去 + 试着做 … 最后总要出来”（`lCritical`）；“等一会儿”调内置库里的同名函数。
library;

import 'package:lopicode/backend/backend_blocks_wait.dart';
import 'package:lopicode/backend/backend_lower_core.dart';
import 'package:lopicode/lang/ast.dart';
import 'package:lopicode/lang/ast_util.dart';
import 'package:lopicode/lowcode/logic_model.dart';

/// 内置库“接口服务”里“等一会儿”那个函数的名字（lib_service_module.dart）。
const String kBeSleepFn = '等一会儿';

/// 值 → 语法树；不是这里的返回 null。
LExpr? beWaitExpr(String kind, Map<dynamic, dynamic> e, BeCoreCx cx) {
  if (!beWaitExprSpecs.containsKey(kind)) return null;
  LExpr sub(String key) => cx.lx(e[key], e, key);
  return switch (kind) {
    'spawnOf' => LSpawn([LReturn(sub('x'))], src: cx.src()),
    'await' => LAwait(sub('x'), src: cx.src()),
    'awaitMax' => LRt('awaitMax', [sub('x'), sub('ms')], src: cx.src()),
    'awaitAll' || 'awaitAny' => LRt(kind, [sub('list')], src: cx.src()),
    _ => LRt('cancelled', const [], src: cx.src()),
  };
}

/// 语句 → 语法树；不是这里的返回 null。[inner]＝翻这块积木的口；[varName]＝名字合不合规矩（不合＝null）。
List<LStmt>? beWaitBlock(LcBlock b, BeCoreCx cx, List<LStmt> Function(List<LcBlock> list, {bool inElse, int arm}) inner, String? Function(Object? v) varName) {
  if (!beWaitBlockSpecs.containsKey(b.op)) return null;
  LExpr arg(String name) => cx.lx(b.args[name], b, name, arg: name);
  switch (b.op) {
    case 'spawn':
      final spawn = LSpawn(inner(b.body), src: cx.src());
      final name = varName(b.args['name']);
      final raw = b.args['name'];
      if (name == null && raw is String && raw.isNotEmpty) cx.note('“开始做”记成的名字不合规矩，没有记');
      return [name == null ? LExprStmt(spawn, src: cx.src()) : LLet(name, spawn, isConst: true, src: cx.src('name'))];
    case 'sleep':
      return [
        // 严格规矩（pure）：调内置库的“等一会儿”。老式检查（不带库）那一遍只要知道“这里用了 ms”，放个宿主调用占位，免得它报“没有这个函数”。
        LExprStmt(cx.pure ? LCall(const LName(kBeSleepFn), [arg('ms')], src: cx.src()) : LNative('time.sleep', [arg('ms')]), src: cx.src()),
      ];
    case 'cancel':
      return [
        LExprStmt(LRt('cancel', [arg('x')], src: cx.src()), src: cx.src()),
      ];
    default:
      return lCritical(arg('name'), inner(b.body), '锁记号${cx.temp()}', src: cx.src());
  }
}
