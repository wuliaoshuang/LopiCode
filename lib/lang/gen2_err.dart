/// 规矩版本 2 的生成器里“错误是对象”的那一块（核心 2）：抛出、试着做 / 出错时（可以好几节、按种类接）/ 最后。五种语言共用骨架，
/// 各语言只答几件小事（外框怎么写、怎么拆出错误对象、怎么原样再抛）。设计：errors.dart 顶上的说明、docs/blocks-v5-parts/B-gen-notes.md 第 9 节。
library;

import 'package:lopicode/lang/ast.dart';
import 'package:lopicode/lang/errors.dart';
import 'package:lopicode/lang/gen2.dart';
import 'package:lopicode/lang/gen2_expr.dart';
import 'package:lopicode/lang/types.dart';

mixin Gen2Err on Gen2Base, Gen2Expr {
  static const LType errType = LType(LKind.object, name: kErrBase);
  static const LField _messageOf = LField(LName('_'), kErrMessageField);

  /// 抛一个错误对象：[obj] 是放着对象的临时名字，[message] 是取它“消息”的代码（外面包的那层要带着这句话，没接住时打印它）。
  List<String> throwObjLines(String obj, String message);

  /// 试着做的外框。[handler]＝null：没有“出错时”（只有“最后”）；否则拿接住的那个异常的名字，给出“出错时”里面的代码。
  List<String> tryFrame(LTry s, List<String> Function(List<LStmt>) gen, List<String> Function(String e)? handler);

  /// 从接住的异常里拆出错误对象（类型是“错误”）。小库自己报的错这时才按种类造出对象。
  String errObjCode(String e);

  /// 哪一节都没对上：原样再抛。
  List<String> rethrowLines(String e);

  /// “出错时”那一节里读错误变量：变量的类型是几节合起来的，这一节里按这一节接的种类看。
  @override
  String errNarrow(String code, LType from, LType to) => downcast(code, from, to);

  /// 程序开头要补的东西（告诉小库“某一种内置错误怎么造”）。只在程序用到错误时才出。
  List<String> errSupport();

  /// 内置错误的种类名 → 用 [message] 造一个的代码。
  List<(String, String)> errMakers(String message) => [
    for (final k in kErrBuiltinNames) (k, newObject(w.classes[k]!, LType(LKind.object, name: k), [message])),
  ];

  @override
  List<String> throwStmt(LThrow s) {
    final o = tmpName('X');
    if (r.opOf(s) == 'throwObj') {
      final ty = t(s.value).nonNull;
      return [tmpDecl(o, ty, x(s.value)), ...throwObjLines(o, fieldGet(o, ty, kErrMessageField, _messageOf))];
    }
    // 一句话：包成内置的“错误”。
    final m = tmpName('M');
    return [
      tmpDecl(m, LType.text, x(s.value, LType.text)),
      tmpDecl(o, errType, newObject(w.classes[kErrBase]!, errType, [m])),
      ...throwObjLines(o, m),
    ];
  }

  @override
  List<String> tryStmt(LTry s, List<String> Function(List<LStmt>) gen) {
    final cs = s.catches;
    if (cs.isEmpty) return s.finallyBody.isEmpty ? gen(s.body) : tryFrame(s, gen, null);
    return tryFrame(s, gen, (e) {
      final o = tmpName('X');
      var used = false;
      final arms = <(String, List<String>)>[];
      var orElse = rethrowLines(e);
      for (final c in cs) {
        final kind = c.kind ?? kErrBase;
        final kt = LType(LKind.object, name: kind);
        final lines = <String>[];
        final name = c.name;
        if (name != null) {
          final v = mustVar(name, s);
          used = true;
          lines.add(assignLine(varCode(v), conv(kind == kErrBase ? o : downcast(o, errType, kt), kt, v.type)));
        }
        lines.addAll(gen(c.body));
        if (kind == kErrBase) {
          orElse = lines;
          break;
        }
        used = true;
        arms.add((isA(o, errType, kind), lines));
      }
      return [if (used) tmpDecl(o, errType, errObjCode(e)), ...(arms.isEmpty ? orElse : ifChain(arms, orElse))];
    });
  }
}
