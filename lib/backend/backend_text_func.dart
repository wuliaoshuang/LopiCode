/// 第 2 阶段的积木（函数、调用、匿名函数、拿函数当参数的列表操作）读成人话。backend_text.dart 认不出的会来问这里。
library;

import 'package:lopicode/backend/backend_blocks_typeops.dart';
import 'package:lopicode/backend/backend_function.dart';
import 'package:lopicode/blocks/block_look.dart';
import 'package:lopicode/lowcode/logic_expr.dart';
import 'package:lopicode/lowcode/logic_model.dart';

String _params(Object? raw, [Object? expr]) => raw is List
    ? [
        for (final (i, p) in raw.indexed)
          if (p is String) '$p${expr is Map && bkExprParamType(expr, i) != null ? '：${beTypeLabel(bkExprParamType(expr, i)) ?? '（读不出来的类型）'}' : ''}',
      ].join('、')
    : '';

String _fnLabel(String id, String? Function(String id)? fnName) {
  final name = fnName?.call(id);
  return name == null || name.isEmpty ? '自定义积木' : '「$name」';
}

String _callArgs(Iterable<String> keys, String Function(String key) sub) {
  final parts = [
    for (final k in keys)
      if (k != 'e' && !k.startsWith('@')) '$k: ${sub(k)}',
  ];
  return parts.isEmpty ? '' : '（${parts.join('，')}）';
}

String _given(Object? args, String Function(String key) sub) => args is List && args.isNotEmpty ? '（带上 ${sub('args')}）' : '';

/// 第 2 阶段的表达式；不是的返回 null。[sub] 读一个子格子，[fnName] 按 id 查函数的名字（没给 / 查不到就说“自定义积木”）。
String? describeBeFuncExpr(Object? expr, String Function(String key) sub, [String? Function(String id)? fnName]) {
  final kind = exprKind(expr);
  if (kind == null || expr is! Map) return null;
  final callee = beCallId(kind);
  if (callee != null) return '${_fnLabel(callee, fnName)}${_callArgs(expr.keys.whereType<String>(), sub)}的结果';
  switch (kind) {
    case 'param':
      final name = exprString(expr, 'name');
      return name == null || name.isEmpty ? '（还没选参数）' : '参数 $name';
    case 'lambda':
      final n = lcExprBody(expr)?.length ?? 0;
      return '函数（${_params(expr['params'], expr)}）{${n == 0 ? '' : '…$n 块'}}';
    case 'lambdaExpr':
      return '函数（${_params(expr['params'], expr)}）→ ${sub('body')}';
    case 'funcRef':
      return '${_fnLabel(exprString(expr, 'fn') ?? '', fnName)}这块积木本身';
    case 'callValue':
      return '调用 ${sub('fn')}${_given(expr['args'], sub)}的结果';
    case 'listMap':
      return '${sub('xs')} 每一项用 ${sub('fn')} 变一下';
    case 'listFilter':
      return '${sub('xs')} 里符合 ${sub('fn')} 的';
    case 'listReduce':
      return '${sub('xs')} 从 ${sub('init')} 起用 ${sub('fn')} 累起来';
    case 'listFind':
      return '${sub('xs')} 里第一个符合 ${sub('fn')} 的';
    case 'listEvery':
      return '${sub('xs')} 每一项都符合 ${sub('fn')}';
    case 'listSome':
      return '${sub('xs')} 有一项符合 ${sub('fn')}';
    case 'listSortBy':
      return '${sub('xs')} 按 ${sub('fn')} 算的分排序';
  }
  return null;
}

/// 第 2 阶段的积木；不是的返回 null。
String? describeBeFuncBlock(LcBlock b, String Function(String key) arg, [String? Function(String id)? fnName]) {
  final callee = beCallId(b.op);
  if (callee != null) return '${_fnLabel(callee, fnName)}${_callArgs(b.args.keys, arg)}';
  switch (b.op) {
    case 'return':
      return '返回 ${arg('value')}';
    case 'returnNothing':
      return '直接结束';
    case 'callValueStmt':
      return '调用 ${arg('fn')}${_given(b.args['args'], arg)}';
    case 'listEach':
      return '把 ${arg('xs')} 的每一项交给 ${arg('fn')}';
  }
  return null;
}
