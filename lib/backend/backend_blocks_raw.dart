/// “文字原样”的两块（一句语句、一个值）和“对列表里的每一项（自带名字）”：内置库上画布时用（backend_from_text.dart）。
///
/// - 文字原样：里面存的是语言核心的文字写法（一句、或者一个式子）。内置库的模块是文字写法的，其中没有对应积木的那些地方
///   翻不成积木，就原样包在这种块里：画布上看得见是什么，翻回语法树时照文字读回去，一个字不差。
///   积木盒里没有这两块（用户不能凭空放一块“随便写”的）：只在“从文字写法翻过来”的文档里出现。
///   里面写了“宿”（直接调宿主接口）的，和“调宿主接口”积木同样对待：算进这个库用到的宿主接口里，同一个开关管着。
/// - “对每一项（自带名字）”：`forEach` 那块要一个事先声明好的变量来接每一项；文字写法里常用的是循环自己带名字的那种，
///   它没有对应的积木，所以补这一块。和核心 2 的积木一样只在严格规矩的文档里出现。
library;

import 'package:lopicode/backend/backend_blocks_core.dart';
import 'package:lopicode/backend/backend_lower_core.dart';
import 'package:lopicode/lang/ast.dart';
import 'package:lopicode/lang/ast_util.dart';
import 'package:lopicode/lang/lc_text.dart';
import 'package:lopicode/lowcode/logic_blocks.dart';
import 'package:lopicode/lowcode/logic_model.dart';

const String kBeRawExpr = 'rawExpr';
const String kBeRawStmt = 'rawStmt';
const String kBeForIn = 'forIn';

const LcArgSpec _src = LcArgSpec('src', '文字写法', LcArgKind.literalText);

const Map<String, LcExprSpec> beRawExprSpecs = {
  kBeRawExpr: LcExprSpec(kBeRawExpr, '文字原样（值）', kBeCatType, [_src], hint: '这一处没有对应的积木，照语言核心的文字写法原样放着'),
};

const Map<String, LcBlockSpec> beRawBlockSpecs = {
  kBeRawStmt: LcBlockSpec(kBeRawStmt, '文字原样', kBeCatType, [_src], hint: '这一句没有对应的积木，照语言核心的文字写法原样放着'),
  kBeForIn: LcBlockSpec(
    kBeForIn,
    '对每一项（自带名字）',
    kBeCatType,
    [LcArgSpec('list', '列表', LcArgKind.expr), LcArgSpec('name', '这一项叫', LcArgKind.literalText), LcArgSpec('index', '第几项叫', LcArgKind.literalText, optional: true)],
    bodyLabel: '依次做',
    hint: '把列表里的每一项轮流拿出来，各做一遍里面的积木；这一项的名字是这个循环自己的，不用先建变量',
  ),
};

const Map<String, String> beRawExprSentences = {kBeRawExpr: '原样 {src}'};
const Map<String, String> beRawBlockSentences = {kBeRawStmt: '原样 {src}', kBeForIn: '对 {list} 的每一项 {name} {index}'};

bool beIsRaw(Object? kindOrOp) => kindOrOp == kBeRawExpr || kindOrOp == kBeRawStmt;

String _clip(Object? src) {
  final s = (src is String ? src : '').replaceAll(RegExp(r'\s+'), ' ').trim();
  return s.length > 40 ? '${s.substring(0, 40)}…' : s;
}

String? describeBeRawExpr(Object? expr) => expr is Map && expr['e'] == kBeRawExpr ? '原样 ${_clip(expr['src'])}' : null;

String? describeBeRawBlock(LcBlock b, String Function(String name) arg) => switch (b.op) {
  kBeRawStmt => '原样 ${_clip(b.args['src'])}',
  kBeForIn => '对 ${arg('list')} 的每一项 ${b.args['name'] ?? ''}',
  _ => null,
};

/// 文字 → 一个式子；读不出来返回 null。
LExpr? beRawReadExpr(Object? src) {
  if (src is! String || src.trim().isEmpty) return null;
  try {
    final parsed = lcParse(src);
    return parsed.length == 1 ? LcReader(const []).expr(parsed.single) : null;
  } on Object {
    return null;
  }
}

/// 文字 → 一句语句；读不出来返回 null。
LStmt? beRawReadStmt(Object? src) {
  if (src is! String || src.trim().isEmpty) return null;
  try {
    final parsed = lcParse(src);
    return parsed.length == 1 && parsed.single is LcList ? LcReader(const []).stmt(parsed.single as LcList) : null;
  } on Object {
    return null;
  }
}

/// 一句“文字原样”里新建了哪些名字（设、常、各种循环自己的变量、接到的错误）：读写变量的下拉和翻译靠它知道这些名字。
List<String> beRawDeclares(Object? src) {
  final s = beRawReadStmt(src);
  if (s == null) return const [];
  final out = <String>[];
  lWalk([s], (x) {
    switch (x) {
      case LLet(:final name):
        out.add(name);
      case LForCount(:final name):
        out.add(name);
      case LForEach(:final item, :final index, :final reuse):
        if (!reuse) out.add(item);
        if (index != null) out.add(index);
      case LForPairs(:final key, :final value):
        out
          ..add(key)
          ..add(value);
      case LTry():
        for (final c in x.catches) {
          if (c.name != null) out.add(c.name!);
        }
      default:
        break;
    }
  });
  return out;
}

/// 这段文字里直接调了哪些宿主接口（“宿 名字 …”）。[isExpr]＝它是一个式子（不是一句语句）。
List<String> beRawHosts(Object? src, {required bool isExpr}) {
  final out = <String>[];
  void look(LExpr e) {
    if (e is LNative && !out.contains(e.name)) out.add(e.name);
    if (e is LLambda) lWalkExprs(e.stmts, look);
    lExprChildren(e).forEach(look);
  }

  if (isExpr) {
    final e = beRawReadExpr(src);
    if (e != null) look(e);
  } else {
    final s = beRawReadStmt(src);
    if (s != null) lWalkExprs([s], look);
  }
  return out;
}

/// 值 → 语法树；不是这里的返回 null。
LExpr? beRawExpr(String kind, Map<dynamic, dynamic> e, BeCoreCx cx) {
  if (kind != kBeRawExpr) return null;
  final got = beRawReadExpr(e['src']);
  if (got == null) {
    cx.note('这一处的文字写法读不出来，当成空的');
    return const LLit(null);
  }
  return got;
}

/// 语句 → 语法树；不是这里的返回 null。
List<LStmt>? beRawBlock(LcBlock b, BeCoreCx cx, List<LStmt> Function(List<LcBlock> list, {bool inElse, int arm}) inner, String? Function(Object? v) varName) {
  if (b.op == kBeRawStmt) {
    final got = beRawReadStmt(b.args['src']);
    if (got == null) {
      cx.note('这一句的文字写法读不出来，跳过了');
      return const [];
    }
    return [got];
  }
  if (b.op != kBeForIn) return null;
  final name = varName(b.args['name']);
  if (name == null) {
    cx.note('已跳过：“这一项叫”的名字不合规矩');
    return const [];
  }
  final index = b.args['index'];
  final hasIndex = index is String && index.isNotEmpty;
  if (hasIndex && varName(index) == null) cx.note('序号的名字不合规矩，没有记序号');
  return [
    LForEach(
      cx.lx(b.args['list'], b, 'list', arg: 'list'),
      name,
      inner(b.body),
      index: hasIndex ? varName(index) : null,
      src: cx.src('name'),
    ),
  ];
}
