/// 一份后端文档里的“我的积木”一览（积木第 4 版·第 2 阶段）：每个函数检查出来是什么样（有没有返回值、返回的是不是“是 / 否”）、
/// 调用它的积木长什么样（规格、句子、颜色、形状）。校验、编辑器宿主、Agent 工具都问它，免得各算各的。
///
/// 一张表只管文档的一个瞬间：文档一改就要重新建一张（宿主在 `_bump` 里丢掉旧的）。都是现算现用、算过就记住；任何输入都不抛异常。
library;

import 'package:lopicode/backend/backend_blocks.dart';
import 'package:lopicode/backend/backend_blocks_strict.dart';
import 'package:lopicode/backend/backend_function.dart';
import 'package:lopicode/backend/backend_lang.dart';
import 'package:lopicode/backend/backend_lower_func.dart';
import 'package:lopicode/backend/backend_model.dart';
import 'package:lopicode/blocks/block_look.dart';
import 'package:lopicode/lang/lang.dart';
import 'package:lopicode/lowcode/logic_model.dart';

class BeFuncTable {
  BeFuncTable(this.doc);

  final BeDocument doc;

  bool get isEmpty => doc.functions.isEmpty;

  /// 所有函数按“影子模式”翻成的语法树（校验用；带来源表）。
  late final List<BeLoweredFunction> lowered = _guard(() => beLowerFunctionsWithSpots(doc, shadow: true), const []);

  /// 语言核心的检查器看完这一批函数的结果。
  late final LangFunctionsAnalysis analysis = _guard(() => analyzeFunctions([for (final f in lowered) f.decl], inspect: beHostInspect), const LangFunctionsAnalysis([], {}));

  static T _guard<T>(T Function() run, T fallback) {
    try {
      return run();
    } on Object {
      // 翻不出来 / 查不动：当成“什么都不知道”，别的检查照常，不让编辑器崩。
      return fallback;
    }
  }

  LFuncInfo? infoOf(BeFunction f) => analysis.functions[f.ident];

  /// “自动”形状按定义定下来：没有“返回 (值)”＝语句；有＝值；返回的一定是“是 / 否”＝是否。
  CustomBlockShape shapeOf(BeFunction f) {
    final info = infoOf(f);
    final hasValue = info?.returnsValue ?? false;
    return resolveLookShape(f.look.shape, hasValue: hasValue, returnsBool: hasValue && ((info?.returnsBool ?? false) || _returnsOnlyBool(f)));
  }

  final Set<String> _asking = {};

  /// 定义里每一块“返回 (值)”交回的都是“是 / 否”（旧的比较、判断这些值检查器不认识类型，这里按积木自己的说法补上）。
  bool _returnsOnlyBool(BeFunction f) {
    if (!_asking.add(f.id)) return false; // 自己绕回自己：不猜
    try {
      var any = false, all = true;
      void walk(List<LcBlock> list, int depth) {
        if (depth > LcBlock.maxDepth + 2) return;
        for (final b in list) {
          if (b.op == 'return') {
            any = true;
            if (!isBool(b.args['value'])) all = false;
          }
          walk(b.body, depth + 1);
          walk(b.orElse, depth + 1);
          for (final a in b.arms) {
            walk(a.body, depth + 1);
          }
        }
      }

      walk(f.body, 0);
      return any && all;
    } finally {
      _asking.remove(f.id);
    }
  }

  final Map<String, BlockCustom> _customs = {};

  /// 编辑器眼里的这块积木：id 就是调用它的 op / e（`call:<函数 id>`），形状已经定好。
  BlockCustom customOf(BeFunction f) => _customs[f.id] ??= BlockCustom(beCallOp(f.id), f.look.copyWith(shape: shapeOf(f)), f.paramNames);

  List<BlockCustom> get customs => [for (final f in doc.functions) customOf(f)];

  /// `call:<id>` → 那块积木；不是调用、函数不在了返回 null。
  BlockCustom? callOf(Object? op) {
    final id = beCallId(op);
    final f = id == null ? null : doc.function(id);
    return f == null ? null : customOf(f);
  }

  /// 内置的加上自定义的。调用积木不看形状：值型的也能单独当一句用（结果不要），语句型的当值用得到空（校验给警告）。
  LcBlockSpec? blockSpec(String op) {
    final c = callOf(op);
    return c != null ? bkLookBlockSpec(c) : beBlockSpecs[op];
  }

  LcExprSpec? exprSpec(String? kind) {
    final c = callOf(kind);
    return c != null ? bkLookExprSpec(c) : beExprSpecs[kind] ?? beStrictExprSpecs[kind];
  }

  /// 调用时这个参数没给也行：它有默认值，或者是“剩下的全收”（没给＝一个都不多带）。不是调用返回 false。
  bool argFallsBack(Object? op, String arg) {
    final id = beCallId(op);
    final p = id == null ? null : doc.function(id)?.params.where((p) => p.name == arg).firstOrNull;
    return p != null && (p.rest || p.defaultValue != null);
  }

  String? sentenceOf(String op) {
    final c = callOf(op);
    return c == null ? null : bkLookSentence(c.look, c.params);
  }

  /// 这个值算出来是不是“是 / 否”。
  bool isBool(Object? expr) {
    final c = callOf(exprKind(expr));
    return c != null ? c.look.shape == CustomBlockShape.boolean : beExprIsBool(expr);
  }
}
