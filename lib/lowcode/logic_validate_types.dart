/// 两套积木（页面逻辑、后端）共用的“值对不对”检查：类型对不上、除以 0、重复次数、网址。
///
/// 只读不改，也不认识文档：要查什么都由调用方给（[LcValueChecker] 的几个函数）。
/// 找到的问题通过 [LcValueChecker.report] 交回去，由各自的校验器补上“在哪个接口 / 事件、第几块”。
///
/// 定级的原则（两套一致，见 docs/blocks-v3-design.md 的“校验规则表”）：
/// - 运行时一定不是想要的结果（数字格里填了“abc”、重复 -1 次）＝错误；
/// - 运行时能算、但多半不是本意（条件里放了数字、除以 0 得 0）＝警告；
/// - 说不准类型的（没声明类型的值、请求里读来的东西）一律不报。
library;

import 'package:lopicode/lowcode/logic_blocks.dart';
import 'package:lopicode/lowcode/logic_model.dart';

/// 报一个问题。`arg`＝积木的哪个参数，`exprPath`＝参数里的哪个位置（和积木编辑器的槽位路径是同一种写法）。
typedef LcValueReport = void Function(LcIssueLevel level, String code, String problem, {required String arg, required List<Object> exprPath, String? fix});

const Set<String> _orderOps = {'<', '<=', '>', '>='};

String _typeName(String type) => switch (type) {
  LcType.number => '数字',
  LcType.boolean => '“是 / 否”',
  LcType.text => '文字',
  _ => '值',
};

String _clip(String s, [int limit = 16]) {
  final runes = s.runes.toList();
  return runes.length <= limit ? s : '${String.fromCharCodes(runes.take(limit))}…';
}

/// 一个直接填的网址有什么毛病：null＝看不出毛病，`empty`＝没填，`partial`＝只填了开头，`bad`＝明显不是网址。
/// `httpOnly`＝只认 http / https 开头的完整网址（后端请求别的服务）；否则相对地址（`about.html`、`/list`、`#top`）也算对。
String? lcUrlProblem(String raw, {required bool httpOnly}) {
  final v = raw.trim();
  if (v.isEmpty) return 'empty';
  if (v == 'http://' || v == 'https://') return 'partial';
  if (RegExp(r'\s').hasMatch(v)) return 'bad';
  final scheme = RegExp(r'^([A-Za-z][A-Za-z0-9+.-]*):').firstMatch(v)?.group(1)?.toLowerCase();
  if (scheme == 'http' || scheme == 'https') return RegExp(r'^https?://[^/?#]+', caseSensitive: false).hasMatch(v) ? null : 'bad';
  if (httpOnly) return 'bad';
  return null;
}

class LcValueChecker {
  LcValueChecker({required this.exprSpec, required this.typeOf, required this.report, required this.repeatLimit});

  /// 查一种表达式的说明；不认识返回 null（不认识的别处已经报过，这里跳过）。
  final LcExprSpec? Function(String kind) exprSpec;

  /// 一个表达式算出来是什么类型（[LcType]）；说不准返回 [LcType.any]。
  final String Function(Object? expr) typeOf;
  final LcValueReport report;

  /// “重复”最多做多少遍（超过的会被截到这个数）。
  final int repeatLimit;

  /// 检查一块积木自己的参数（不进它里面的积木）。`spec` 为 null（不认识的积木）什么都不做。
  void block(LcBlock b, LcBlockSpec? spec) {
    if (spec == null) return;
    for (final a in spec.args) {
      _arg(a, b.args[a.name], a.name, const [], 0, a.valueType);
    }
    if (b.op == 'repeat') _repeat(b.args['times']);
  }

  void _arg(LcArgSpec a, Object? value, String arg, List<Object> xp, int depth, String want) {
    if (a.kind == LcArgKind.expr) {
      _value(value, arg, xp, depth, want);
    } else if (a.kind == LcArgKind.exprList && value is List) {
      for (var i = 0; i < value.length; i++) {
        _value(value[i], arg, [...xp, i], depth, a.valueType);
      }
    }
  }

  /// 一个值槽里放的东西：先看它和槽要的类型对不对得上，再进去看它自己的参数。
  void _value(Object? value, String arg, List<Object> xp, int depth, String want) {
    final kind = exprKind(value);
    if (kind == null || value is! Map || depth >= kMaxExprDepth) return;
    final spec = exprSpec(kind);
    if (spec == null) return;
    _fit(want, value, kind, arg, xp);
    final op = kind == 'bin' ? exprString(value, 'op') : null;
    for (final a in spec.args) {
      var sub = a.valueType;
      if (op != null && (a.name == 'l' || a.name == 'r')) {
        // 运算两边要什么，看是哪种运算：算术和比大小要数字，并且 / 或者要条件，等于 / 不等于什么都行。
        sub = kArithmeticOps.contains(op) || _orderOps.contains(op) ? LcType.number : (kLogicOps.contains(op) ? LcType.boolean : LcType.any);
      }
      _arg(a, value[a.name], arg, [...xp, a.name], depth + 1, sub);
    }
    if (op == null) return;
    final l = value['l'], r = value['r'];
    if ((op == '/' || op == '%') && exprKind(r) == 'num' && exprNum(r, 'v') == 0) {
      report(LcIssueLevel.warning, 'divByZero', '${op == '/' ? '除以' : '对'} 0 ${op == '/' ? '' : '取余'}算不出来，运行时结果会是 0', arg: arg, exprPath: [...xp, 'r']);
    }
    if (op == '==' || op == '!=') {
      final lt = typeOf(l), rt = typeOf(r);
      if (lt != LcType.any && rt != LcType.any && lt != rt && (lt == LcType.boolean || rt == LcType.boolean)) {
        report(LcIssueLevel.warning, 'badType', '比较的两边一个是${_typeName(lt)}、一个是${_typeName(rt)}，会先都变成文字再比，多半${op == '==' ? '永远不相等' : '永远不一样'}', arg: arg, exprPath: xp, fix: '把两边换成同一种类型的值再比。');
      }
    }
  }

  void _fit(String want, Map<dynamic, dynamic> value, String kind, String arg, List<Object> xp) {
    final got = typeOf(value);
    if (want == LcType.number) {
      if (kind == 'text') {
        final v = exprString(value, 'v') ?? '';
        final n = num.tryParse(v.trim());
        if (n == null || !n.isFinite) {
          report(LcIssueLevel.error, 'badType', '这里要数字，填的是文字“${_clip(v)}”，运行时会当成 0', arg: arg, exprPath: xp, fix: '长按这一格，换成“数字”再填。');
        }
      } else if (got == LcType.boolean) {
        report(LcIssueLevel.warning, 'badType', '这里要数字，放的是“是 / 否”，会被硬转成数字，多半不是你想要的', arg: arg, exprPath: xp, fix: '长按这个值，换成数字或数字类型的变量。');
      }
    } else if (want == LcType.boolean && (got == LcType.number || got == LcType.text)) {
      final literal = kind == 'num' || kind == 'text';
      report(
        LcIssueLevel.warning,
        'badType',
        literal ? '这里要一个条件，填的是固定的${_typeName(got)}，结果每次都一样' : '这里要一个条件，放的是${_typeName(got)}：会按“是不是 0 / 有没有内容”来算成立不成立',
        arg: arg,
        exprPath: xp,
        fix: '长按这个值，换成比较（等于、大于…）或“是 / 否”。',
      );
    }
  }

  void _repeat(Object? times) {
    if (exprKind(times) != 'num') return;
    final n = exprNum(times, 'v');
    if (n == null || !n.isFinite) return;
    if (n < 0) {
      report(LcIssueLevel.error, 'badRepeat', '重复的次数是负数，里面的积木一遍都不会做', arg: 'times', exprPath: const []);
    } else if (n != n.roundToDouble()) {
      report(LcIssueLevel.warning, 'badRepeat', '重复的次数不是整数，实际做几遍和你想的可能不一样', arg: 'times', exprPath: const []);
    } else if (n > repeatLimit) {
      report(LcIssueLevel.warning, 'badRepeat', '重复最多做 $repeatLimit 遍，超过的不会做', arg: 'times', exprPath: const [], fix: '把次数改到 $repeatLimit 以内。');
    }
  }
}
