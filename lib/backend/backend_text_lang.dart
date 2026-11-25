/// 第 4 版新积木、新表达式的中文读法（backend_text.dart 认不出来的交到这里）。只说这一块自己，里面嵌的积木用“…”带过。
library;

import 'package:lopicode/backend/backend_blocks_lang.dart';
import 'package:lopicode/lowcode/logic_blocks.dart';
import 'package:lopicode/lowcode/logic_model.dart';

String _choice(LcArgSpec? arg, Object? value) => arg != null && value is String && arg.choices.contains(value) ? arg.choiceLabel(value) : '（还没选）';

/// 新表达式读成人话；不是新表达式返回 null。[sub] 读它的一个参数（已经是人话）。
String? describeBeLangExpr(Object? expr, String Function(String key) sub) {
  final kind = exprKind(expr);
  final spec = beLangExprSpecs[kind];
  if (kind == null || spec == null) return null;
  String fn([String name = 'fn']) => _choice(spec.arg(name), exprField(expr, name));
  switch (kind) {
    case 'neg':
      return '负的 ${sub('x')}';
    case 'round':
      return '${sub('x')} ${fn()}';
    case 'math':
      return '${sub('x')} 的${fn()}';
    case 'minmax':
      return '${sub('a')} 和 ${sub('b')} 里${fn()}';
    case 'pow':
      return '${sub('a')} 的 ${sub('b')} 次方';
    case 'random':
      return '${sub('a')} 到 ${sub('b')} 之间的随机整数';
    case 'logic':
      return '（${sub('l')} ${fn('op')} ${sub('r')}）';
    case 'cond':
      return '如果 ${sub('cond')} 就是 ${sub('then')} 否则是 ${sub('orElse')}';
    case 'null':
      return '空值';
    case 'isType':
      return '${sub('x')} 是${fn('type')}';
    case 'convert':
      return '把 ${sub('x')} 变成${fn()}';
    case 'copy':
      return '${sub('x')} 的复制品';
    case 'charAt':
      return '${sub('s')} 的第 ${sub('i')} 个字';
    case 'substring':
      return '${sub('s')} 从第 ${sub('from')} 个字到第 ${sub('to')} 个字之前';
    case 'indexOf':
      return '${sub('sub')} 在 ${sub('s')} 里的位置';
    case 'textHas':
      return '${sub('s')} ${fn()} ${sub('sub')}';
    case 'replace':
      return '把 ${sub('s')} 里的 ${sub('from')} 换成 ${sub('to')}';
    case 'textCase':
      return '${sub('s')} ${fn()}';
    case 'repeatText':
      return '${sub('s')} 重复 ${sub('n')} 遍';
    case 'split':
      return '把 ${sub('s')} 按 ${sub('sep')} 切开';
    case 'template':
      return '用 ${sub('dict')} 填模板 ${sub('s')}';
    case 'toJson':
      return '${sub('x')} 写成 JSON 文字';
    case 'fromJson':
      return '读 JSON 文字 ${sub('s')}';
    case 'listLit':
      final items = exprField(expr, 'items');
      final n = items is List ? items.length : 0;
      return n == 0 ? '空列表 []' : '有 $n 项的列表';
    case 'range':
      return '从 ${sub('a')} 到 ${sub('b')} 每次加 ${sub('step')} 的一串数';
    case 'index':
      return '${sub('of')} 里的 ${sub('key')}';
    case 'listGet':
      return '${sub('xs')} 的第 ${sub('i')} 项';
    case 'listPop':
      return '从 ${sub('xs')} 取走最后一项';
    case 'listContains':
      return '${sub('xs')} 里有 ${sub('v')}';
    case 'listIndexOf':
      return '${sub('v')} 在 ${sub('xs')} 里的位置';
    case 'listSlice':
      return '${sub('xs')} 从第 ${sub('from')} 项到第 ${sub('to')} 项之前';
    case 'listConcat':
      return '${sub('a')} 接上 ${sub('b')}';
    case 'listOrder':
      return '${sub('xs')} ${fn()}';
    case 'listJoin':
      return '把 ${sub('xs')} 用 ${sub('sep')} 连成文字';
    case 'dictGet':
      return '${sub('d')} 里键 ${sub('k')} 的值';
    case 'dictHas':
      return '${sub('d')} 里有键 ${sub('k')}';
    case 'dictPart':
      return '${sub('d')} ${fn()}';
    case 'dictMerge':
      return '${sub('a')} 合上 ${sub('b')}';
    default:
      return spec.label;
  }
}

/// 新积木读成人话；不是新积木返回 null。[arg] 读一个式子参数，[name] 读一个直接填的名字。
String? describeBeLangBlock(LcBlock b, String Function(String key) arg, String Function(String key) name) {
  switch (b.op) {
    case 'let':
      return '新建变量 ${name('name')} ＝ ${arg('value')}';
    case 'const':
      return '新建常量 ${name('name')} ＝ ${arg('value')}';
    case 'do':
      return '算一下 ${arg('value')}';
    case 'switch':
      return '看 ${arg('value')} 分 ${b.arms.length} 种情况…';
    case 'while':
      return '当 ${arg('cond')} 时重复…';
    case 'forever':
      return '一直重复…';
    case 'forCount':
      return '${name('name')} 从 ${arg('from')} 数到 ${arg('to')}，每次加 ${arg('step')}，依次做…';
    case 'forPairs':
      return '对 ${arg('dict')} 的每一对（键放进 ${name('key')}，值放进 ${name('value')}）依次做…';
    case 'break':
      return '跳出循环';
    case 'continue':
      return '跳过这一轮';
    case 'note':
      return '备注：${name('text')}';
    case 'listPush':
      return '在 ${arg('xs')} 末尾加上 ${arg('v')}';
    case 'listInsert':
      return '在 ${arg('xs')} 的第 ${arg('i')} 项前插入 ${arg('v')}';
    case 'listSet':
      return '把 ${arg('xs')} 的第 ${arg('i')} 项改成 ${arg('v')}';
    case 'listRemove':
      return '删掉 ${arg('xs')} 的第 ${arg('i')} 项';
    case 'setItem':
      return '把 ${arg('of')} 里的 ${arg('key')} 改成 ${arg('value')}';
    case 'dictSet':
      return '把 ${arg('d')} 的键 ${arg('k')} 设成 ${arg('v')}';
    case 'dictRemove':
      return '删掉 ${arg('d')} 的键 ${arg('k')}';
    default:
      return null;
  }
}
